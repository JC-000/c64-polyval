#!/usr/bin/env python3
"""
benchmark_polyval.py - Cycle-Accurate POLYVAL Benchmark

Measures exact cycle counts for each discrete POLYVAL operation using the
C64's CIA #1 Timer A hardware. With IRQs disabled (SEI), results are
perfectly deterministic (spread = 0).

Benchmarked routines:
  polyval_double           - left-shift 128 bits + reduction
  polyval_shift_left_4     - left-shift 4 bits (4x double)
  polyval_xor_table_entry  - XOR htable[nibble] into acc
  polyval_precompute_table - build htable[0..15] from H
  polyval_multiply         - 4-bit table multiply
  polyval_update           - XOR block + multiply

Usage:
    python3 tools/benchmark_polyval.py [--samples N] [--verbose]

Requires: Python 3.10+, c64_test_harness, VICE x64sc
"""

import os
import subprocess
import sys
import time

from c64_test_harness import (
    Labels,
    ViceConfig,
    ViceInstanceManager,
    dump_screen,
    read_bytes,
    write_bytes,
    jsr,
    wait_for_text,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PRG_PATH = os.path.join(PROJECT_ROOT, "build", "polyval.prg")
LABELS_PATH = os.path.join(PROJECT_ROOT, "build", "labels.txt")

# CIA Timer A wrapper lives at $C000 (unused RAM)
WRAPPER_ADDR = 0xC000
# Offset of JSR operand within the wrapper (low byte at $C00F, high at $C010)
JSR_OPERAND_OFFSET = 0x0F
# Where timer results are stored
TIMER_LO_ADDR = 0xC024
TIMER_HI_ADDR = 0xC025
# RTS-only calibration stub (past end of wrapper)
RTS_STUB_ADDR = 0xC030

# Chained CIA Timer A+B (32-bit) wrapper lives at $C080
LONG_WRAPPER_ADDR = 0xC080
# Offset of JSR operand in the long wrapper (filled in at install time)
LONG_JSR_OPERAND_OFFSET = None  # set below
# Result storage addresses (set below, after wrapper bytes defined)
LONG_A_LO_ADDR = None
LONG_A_HI_ADDR = None
LONG_B_LO_ADDR = None
LONG_B_HI_ADDR = None

# Multi-block polyval_update stub
MULTIBLOCK_STUB_ADDR = 0xC100
MULTIBLOCK_BUFFER_ADDR = 0x6000  # 4096 bytes of block input data
                                 # $6000-$6FFF: well clear of polyval_htable8
                                 # ($3700-$46FF) and the PRG image (ends <$5D00).
MULTIBLOCK_COUNT_ADDR = None     # set below

# ZP scratch used by the multi-block stub (free locations on C64)
MULTIBLOCK_PTR_ZP = 0xFB         # $FB/$FC: source pointer

DEFAULT_SAMPLES = 5
VERBOSE = False

# Max retries for transient VICE connection failures
JSR_RETRIES = 5
JSR_RETRY_DELAY = 1.0


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def robust_jsr(transport, addr, timeout=10.0, retries=JSR_RETRIES):
    """Call jsr() with retry logic for transient VICE connection failures."""
    for attempt in range(retries):
        try:
            return jsr(transport, addr, timeout=timeout)
        except Exception as e:
            if attempt < retries - 1:
                if VERBOSE:
                    print(f"  [retry {attempt+1}/{retries}] jsr(${addr:04X}) failed: {e}")
                time.sleep(JSR_RETRY_DELAY)
            else:
                raise


# ---------------------------------------------------------------------------
# CIA Timer A wrapper
# ---------------------------------------------------------------------------

# 38 bytes at $C000-$C025:
#   $C000  78           SEI
#   $C001  A9 FF        LDA #$FF
#   $C003  8D 04 DC     STA $DC04       ; timer latch low
#   $C006  8D 05 DC     STA $DC05       ; timer latch high
#   $C009  A9 19        LDA #$19        ; force_load + one_shot + start
#   $C00B  8D 0E DC     STA $DC0E
#   $C00E  20 00 00     JSR $0000       ; patched by Python
#   $C011  AD 05 DC     LDA $DC05       ; read high (latches low)
#   $C014  8D 25 C0     STA $C025       ; timer_hi
#   $C017  AD 04 DC     LDA $DC04       ; read latched low
#   $C01A  8D 24 C0     STA $C024       ; timer_lo
#   $C01D  A9 11        LDA #$11        ; restart timer in continuous mode
#   $C01F  8D 0E DC     STA $DC0E       ; (restore normal CIA operation)
#   $C022  58           CLI
#   $C023  60           RTS
#   $C024  00           timer_lo
#   $C025  00           timer_hi
TIMING_WRAPPER = bytes([
    0x78,                               # SEI
    0xA9, 0xFF,                         # LDA #$FF
    0x8D, 0x04, 0xDC,                   # STA $DC04
    0x8D, 0x05, 0xDC,                   # STA $DC05
    0xA9, 0x19,                         # LDA #$19
    0x8D, 0x0E, 0xDC,                   # STA $DC0E
    0x20, 0x00, 0x00,                   # JSR $0000 (patched)
    0xAD, 0x05, 0xDC,                   # LDA $DC05
    0x8D, 0x25, 0xC0,                   # STA $C025  (timer_hi)
    0xAD, 0x04, 0xDC,                   # LDA $DC04
    0x8D, 0x24, 0xC0,                   # STA $C024  (timer_lo)
    0xA9, 0x11,                         # LDA #$11   (continuous + start)
    0x8D, 0x0E, 0xDC,                   # STA $DC0E  (restore CIA)
    0x58,                               # CLI
    0x60,                               # RTS
    0x00,                               # timer_lo
    0x00,                               # timer_hi
])

WRAPPER_LEN = len(TIMING_WRAPPER)  # 38 bytes


def install_timing_wrapper(transport):
    """Write the CIA Timer A wrapper to $C000 and an RTS stub to $C030."""
    write_bytes(transport, WRAPPER_ADDR, TIMING_WRAPPER)
    # RTS-only stub for calibration
    write_bytes(transport, RTS_STUB_ADDR, bytes([0x60]))
    # Verify wrapper was written correctly
    readback = read_bytes(transport, WRAPPER_ADDR, WRAPPER_LEN)
    if readback != TIMING_WRAPPER:
        print("  FATAL: Wrapper readback mismatch!")
        print(f"    wrote:  {TIMING_WRAPPER.hex()}")
        print(f"    read:   {readback.hex()}")
        sys.exit(1)
    if VERBOSE:
        print(f"  Timing wrapper installed at ${WRAPPER_ADDR:04X}")
        print(f"  RTS calibration stub at ${RTS_STUB_ADDR:04X}")


def patch_target(transport, addr):
    """Patch the JSR operand in the wrapper to target the given address."""
    lo = addr & 0xFF
    hi = (addr >> 8) & 0xFF
    write_bytes(transport, WRAPPER_ADDR + JSR_OPERAND_OFFSET, bytes([lo, hi]))


def read_timer(transport):
    """Read the stored timer value (hi:lo) and return as 16-bit int."""
    lo = read_bytes(transport, TIMER_LO_ADDR, 1)[0]
    hi = read_bytes(transport, TIMER_HI_ADDR, 1)[0]
    return (hi << 8) | lo


def measure_cycles(transport, target_addr, overhead):
    """Measure cycle count for a JSR to target_addr, minus overhead."""
    patch_target(transport, target_addr)
    robust_jsr(transport, WRAPPER_ADDR, timeout=30.0)
    timer_val = read_timer(transport)
    raw_cycles = 0xFFFF - timer_val
    return raw_cycles - overhead


def calibrate(transport, samples=10):
    """Measure the wrapper's own overhead by timing an RTS-only stub.

    Returns the overhead in cycles. Aborts if results are inconsistent
    or outside expected range.
    """
    patch_target(transport, RTS_STUB_ADDR)
    time.sleep(0.5)  # let VICE settle before first jsr
    measurements = []
    for _ in range(samples):
        robust_jsr(transport, WRAPPER_ADDR, timeout=10.0)
        timer_val = read_timer(transport)
        raw = 0xFFFF - timer_val
        measurements.append(raw)

    spread = max(measurements) - min(measurements)
    overhead = measurements[0]

    if VERBOSE:
        print(f"  Calibration samples: {measurements}")

    if spread != 0:
        print(f"  WARNING: calibration spread = {spread} (expected 0)")
        print(f"  Samples: {measurements}")

    if not (10 <= overhead <= 25):
        print(f"  FATAL: calibration overhead = {overhead} cycles (expected 10-25)")
        print(f"  Samples: {measurements}")
        sys.exit(1)

    print(f"  Calibration overhead: {overhead} cycles (spread: {spread})")
    return overhead


# ---------------------------------------------------------------------------
# Chained CIA Timer A+B wrapper (32-bit cycle counter)
# ---------------------------------------------------------------------------
#
# The 16-bit single-timer wrapper above overflows for routines longer than
# ~65535 cycles (e.g. polyval_precompute_table). This wrapper chains CIA #1
# Timer A and Timer B together for a full 32-bit cycle count:
#
#   - Timer A: free-run from $FFFF, counts phi2 cycles (1 cycle each).
#   - Timer B: input mode "count Timer A underflows" (INMODE=%10 in CRB
#     bits 6:5), starts at $FFFF, decrements once per A underflow.
#
# Total cycles consumed = (0xFFFF - A) + (0xFFFF - B) * 0x10000.
#
# We save/restore CRA and CRB so the system IRQ (which uses CIA #1 Timer A
# in continuous mode) keeps running after we're done. On return CLI re-enables
# IRQs. Accurate on both real hardware and VICE regardless of warp state.
#
# Layout at $C080:
#   $C080 78           SEI
#   $C081 AD 0E DC     LDA $DC0E
#   $C084 8D E6 C0     STA save_cra
#   $C087 AD 0F DC     LDA $DC0F
#   $C08A 8D E7 C0     STA save_crb
#   $C08D A9 FF        LDA #$FF
#   $C08F 8D 04 DC     STA $DC04       ; A latch lo
#   $C092 8D 05 DC     STA $DC05       ; A latch hi
#   $C095 8D 06 DC     STA $DC06       ; B latch lo
#   $C098 8D 07 DC     STA $DC07       ; B latch hi
#   $C09B A9 50        LDA #$50        ; B: force-load, INMODE=A-underflow, stopped
#   $C09D 8D 0F DC     STA $DC0F
#   $C0A0 A9 10        LDA #$10        ; A: force-load, stopped
#   $C0A2 8D 0E DC     STA $DC0E
#   $C0A5 A9 41        LDA #$41        ; B: start, continuous, INMODE=A-underflow
#   $C0A7 8D 0F DC     STA $DC0F
#   $C0AA A9 11        LDA #$11        ; A: start, continuous
#   $C0AC 8D 0E DC     STA $DC0E
#   $C0AF 20 00 00     JSR target      ; (patched by Python)
#   $C0B2 A9 08        LDA #$08        ; A: stop (continuous bit preserved, start=0)
#   $C0B4 8D 0E DC     STA $DC0E
#   $C0B7 A9 40        LDA #$40        ; B: stop, preserve INMODE
#   $C0B9 8D 0F DC     STA $DC0F
#   $C0BC AD 04 DC     LDA $DC04
#   $C0BF 8D E2 C0     STA a_lo
#   $C0C2 AD 05 DC     LDA $DC05
#   $C0C5 8D E3 C0     STA a_hi
#   $C0C8 AD 06 DC     LDA $DC06
#   $C0CB 8D E4 C0     STA b_lo
#   $C0CE AD 07 DC     LDA $DC07
#   $C0D1 8D E5 C0     STA b_hi
#   $C0D4 AD E6 C0     LDA save_cra
#   $C0D7 8D 0E DC     STA $DC0E
#   $C0DA AD E7 C0     LDA save_crb
#   $C0DD 8D 0F DC     STA $DC0F
#   $C0E0 58           CLI
#   $C0E1 60           RTS
#   $C0E2..$C0E5       result bytes (a_lo, a_hi, b_lo, b_hi)
#   $C0E6..$C0E7       saved CRA/CRB
LONG_TIMING_WRAPPER = bytes([
    0x78,                               # SEI
    0xAD, 0x0E, 0xDC,                   # LDA $DC0E
    0x8D, 0xE6, 0xC0,                   # STA save_cra
    0xAD, 0x0F, 0xDC,                   # LDA $DC0F
    0x8D, 0xE7, 0xC0,                   # STA save_crb
    0xA9, 0xFF,                         # LDA #$FF
    0x8D, 0x04, 0xDC,                   # STA $DC04
    0x8D, 0x05, 0xDC,                   # STA $DC05
    0x8D, 0x06, 0xDC,                   # STA $DC06
    0x8D, 0x07, 0xDC,                   # STA $DC07
    0xA9, 0x50,                         # LDA #$50  (B: force-load, INMODE=A-underflow)
    0x8D, 0x0F, 0xDC,                   # STA $DC0F
    0xA9, 0x10,                         # LDA #$10  (A: force-load)
    0x8D, 0x0E, 0xDC,                   # STA $DC0E
    0xA9, 0x41,                         # LDA #$41  (B: start, continuous, INMODE=A-underflow)
    0x8D, 0x0F, 0xDC,                   # STA $DC0F
    0xA9, 0x11,                         # LDA #$11  (A: start, continuous)
    0x8D, 0x0E, 0xDC,                   # STA $DC0E
    0x20, 0x00, 0x00,                   # JSR target (patched)
    0xA9, 0x08,                         # LDA #$08  (A: stop)
    0x8D, 0x0E, 0xDC,                   # STA $DC0E
    0xA9, 0x40,                         # LDA #$40  (B: stop, preserve INMODE)
    0x8D, 0x0F, 0xDC,                   # STA $DC0F
    0xAD, 0x04, 0xDC,                   # LDA $DC04
    0x8D, 0xE2, 0xC0,                   # STA a_lo
    0xAD, 0x05, 0xDC,                   # LDA $DC05
    0x8D, 0xE3, 0xC0,                   # STA a_hi
    0xAD, 0x06, 0xDC,                   # LDA $DC06
    0x8D, 0xE4, 0xC0,                   # STA b_lo
    0xAD, 0x07, 0xDC,                   # LDA $DC07
    0x8D, 0xE5, 0xC0,                   # STA b_hi
    0xAD, 0xE6, 0xC0,                   # LDA save_cra
    0x8D, 0x0E, 0xDC,                   # STA $DC0E
    0xAD, 0xE7, 0xC0,                   # LDA save_crb
    0x8D, 0x0F, 0xDC,                   # STA $DC0F
    0x58,                               # CLI
    0x60,                               # RTS
])

LONG_WRAPPER_LEN = len(LONG_TIMING_WRAPPER)

# JSR operand sits right after the `A9 11 / 8D 0E DC` A-start sequence.
# Find the `20 00 00` JSR-to-zero pattern and take the operand offset.
def _find_long_jsr_offset(buf):
    for i in range(len(buf) - 2):
        if buf[i] == 0x20 and buf[i + 1] == 0x00 and buf[i + 2] == 0x00:
            return i + 1
    raise RuntimeError("long wrapper has no JSR placeholder")


LONG_JSR_OPERAND_OFFSET = _find_long_jsr_offset(LONG_TIMING_WRAPPER)

# Result bytes live at fixed addresses $C0E2..$C0E7 (referenced by the
# absolute STA instructions above).
LONG_A_LO_ADDR = 0xC0E2
LONG_A_HI_ADDR = 0xC0E3
LONG_B_LO_ADDR = 0xC0E4
LONG_B_HI_ADDR = 0xC0E5
LONG_SAVE_CRA_ADDR = 0xC0E6
LONG_SAVE_CRB_ADDR = 0xC0E7

# Long-wrapper RTS calibration stub (distinct from the short one so the two
# wrappers can coexist).
LONG_RTS_STUB_ADDR = 0xC0F0


def install_long_wrapper(transport):
    """Write the chained Timer A+B wrapper to $C080 and its RTS stub."""
    write_bytes(transport, LONG_WRAPPER_ADDR, LONG_TIMING_WRAPPER)
    write_bytes(transport, LONG_RTS_STUB_ADDR, bytes([0x60]))
    readback = read_bytes(transport, LONG_WRAPPER_ADDR, LONG_WRAPPER_LEN)
    if readback != LONG_TIMING_WRAPPER:
        print("  FATAL: Long-wrapper readback mismatch!")
        print(f"    wrote:  {LONG_TIMING_WRAPPER.hex()}")
        print(f"    read:   {readback.hex()}")
        sys.exit(1)
    if VERBOSE:
        print(f"  Long wrapper installed at ${LONG_WRAPPER_ADDR:04X} "
              f"({LONG_WRAPPER_LEN} bytes)")
        print(f"  Long RTS calibration stub at ${LONG_RTS_STUB_ADDR:04X}")


def patch_long_target(transport, addr):
    lo = addr & 0xFF
    hi = (addr >> 8) & 0xFF
    write_bytes(transport, LONG_WRAPPER_ADDR + LONG_JSR_OPERAND_OFFSET,
                bytes([lo, hi]))


def read_long_timer(transport):
    """Read 32-bit chained-timer result as a cycle count (raw, pre-overhead)."""
    a_lo = read_bytes(transport, LONG_A_LO_ADDR, 1)[0]
    a_hi = read_bytes(transport, LONG_A_HI_ADDR, 1)[0]
    b_lo = read_bytes(transport, LONG_B_LO_ADDR, 1)[0]
    b_hi = read_bytes(transport, LONG_B_HI_ADDR, 1)[0]
    a_val = (a_hi << 8) | a_lo
    b_val = (b_hi << 8) | b_lo
    # Both timers count down from $FFFF
    return (0xFFFF - a_val) + (0xFFFF - b_val) * 0x10000


def measure_cycles_long(transport, target_addr, overhead):
    patch_long_target(transport, target_addr)
    robust_jsr(transport, LONG_WRAPPER_ADDR, timeout=60.0)
    raw = read_long_timer(transport)
    return raw - overhead


def calibrate_long(transport, samples=5):
    """Measure long-wrapper overhead with an RTS-only stub."""
    patch_long_target(transport, LONG_RTS_STUB_ADDR)
    time.sleep(0.5)
    measurements = []
    for _ in range(samples):
        robust_jsr(transport, LONG_WRAPPER_ADDR, timeout=10.0)
        measurements.append(read_long_timer(transport))
    spread = max(measurements) - min(measurements)
    overhead = measurements[0]
    if VERBOSE:
        print(f"  Long calibration samples: {measurements}")
    if spread != 0:
        print(f"  WARNING: long calibration spread = {spread} (expected 0)")
    # The long wrapper has more CIA writes than the short one; overhead is
    # higher but should still be modest. Loose bounds.
    if not (10 <= overhead <= 120):
        print(f"  FATAL: long calibration overhead = {overhead} cycles "
              f"(expected 20-120)")
        sys.exit(1)
    print(f"  Long calibration overhead: {overhead} cycles (spread: {spread})")
    return overhead


def verify_long_wrapper(transport, overhead):
    """Sanity check: time a known-cycle stub and confirm the result matches.

    Stub: LDX #100 / loop: DEX / BNE loop / RTS
      LDX #100       2 cycles
      DEX            2 cycles  x100
      BNE taken      3 cycles  x99
      BNE not taken  2 cycles  x1
      RTS            6 cycles   <- cancels with calibration's RTS
    Delta vs RTS-only calibration = 2 + (2+3)*99 + (2+2) = 501 cycles.
    (Both JSR-to-stub and the final RTS exist in both stubs and cancel.)
    """
    stub = bytes([0xA2, 0x64,           # LDX #$64
                  0xCA,                 # DEX
                  0xD0, 0xFD,           # BNE *-2
                  0x60])                # RTS
    stub_addr = 0xC0F8
    write_bytes(transport, stub_addr, stub)
    patch_long_target(transport, stub_addr)
    robust_jsr(transport, LONG_WRAPPER_ADDR, timeout=10.0)
    raw = read_long_timer(transport)
    measured = raw - overhead
    expected = 501
    if VERBOSE or measured != expected:
        print(f"  Long wrapper verification: measured {measured} cycles, "
              f"expected {expected} "
              f"({'OK' if measured == expected else 'MISMATCH'})")
    if abs(measured - expected) > 2:
        print(f"  FATAL: long wrapper known-cycle test failed "
              f"({measured} vs {expected})")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Multi-block polyval_update benchmark
# ---------------------------------------------------------------------------
#
# The single-block polyval_update is what the existing short-run benchmark
# measures. But the target applications (AES-GCM-SIV, WireGuard ~88 blocks,
# TLS 1.3 up to 1024 blocks) are multi-block. This stub loops over N blocks
# of input, copying each 16-byte block into polyval_temp and then calling
# polyval_update. Per-block cost at various N tells us how the single-block
# hot path compares to the long-message path.
#
# Stub layout at $C100 (built at runtime with real label addresses):
#
#       LDA #<buffer          ; initialize source pointer
#       STA ptr
#       LDA #>buffer
#       STA ptr+1
#       LDX count             ; count byte at $C200
#   loop:
#       LDY #15               ; copy 16 bytes from (ptr),Y into polyval_temp
#   copy:
#       LDA (ptr),Y
#       STA polyval_temp,Y
#       DEY
#       BPL copy
#       CLC                   ; advance ptr by 16
#       LDA ptr
#       ADC #16
#       STA ptr
#       BCC nocarry
#       INC ptr+1
#   nocarry:
#       TXA : PHA             ; save X across jsr
#       JSR polyval_update
#       PLA : TAX
#       DEX
#       BNE loop
#       RTS

MULTIBLOCK_COUNT_ADDR = 0xC200


def build_multiblock_stub(polyval_temp_addr, polyval_update_addr):
    """Assemble the multi-block driver stub as raw bytes."""
    temp_lo = polyval_temp_addr & 0xFF
    temp_hi = (polyval_temp_addr >> 8) & 0xFF
    buf_lo = MULTIBLOCK_BUFFER_ADDR & 0xFF
    buf_hi = (MULTIBLOCK_BUFFER_ADDR >> 8) & 0xFF
    cnt_lo = MULTIBLOCK_COUNT_ADDR & 0xFF
    cnt_hi = (MULTIBLOCK_COUNT_ADDR >> 8) & 0xFF
    upd_lo = polyval_update_addr & 0xFF
    upd_hi = (polyval_update_addr >> 8) & 0xFF
    ptr = MULTIBLOCK_PTR_ZP

    # We build the stub with forward branches; compute offsets manually.
    # Layout (offsets from MULTIBLOCK_STUB_ADDR):
    #   0x00 A9 <buf_lo>         LDA #<buffer
    #   0x02 85 FB                STA ptr
    #   0x04 A9 <buf_hi>         LDA #>buffer
    #   0x06 85 FC                STA ptr+1
    #   0x08 AE <cnt_lo> <cnt_hi> LDX count              ; absolute LDX
    # loop (0x0B):
    #   0x0B A0 0F                LDY #15
    # copy (0x0D):
    #   0x0D B1 FB                LDA (ptr),Y
    #   0x0F 99 <tlo> <thi>       STA polyval_temp,Y    ; abs,Y
    #   0x12 88                   DEY
    #   0x13 10 F8                BPL copy              ; back to 0x0D (-5)
    #   0x15 18                   CLC
    #   0x16 A5 FB                LDA ptr
    #   0x18 69 10                ADC #16
    #   0x1A 85 FB                STA ptr
    #   0x1C 90 02                BCC nocarry (+2)
    #   0x1E E6 FC                INC ptr+1
    # nocarry (0x20):
    #   0x20 8A                   TXA
    #   0x21 48                   PHA
    #   0x22 20 <ulo> <uhi>       JSR polyval_update
    #   0x25 68                   PLA
    #   0x26 AA                   TAX
    #   0x27 CA                   DEX
    #   0x28 D0 E1                BNE loop (-31 -> back to 0x0B)
    #   0x2A 60                   RTS
    return bytes([
        0xA9, buf_lo,                  # LDA #<buffer
        0x85, ptr,                     # STA ptr
        0xA9, buf_hi,                  # LDA #>buffer
        0x85, ptr + 1,                 # STA ptr+1
        0xAE, cnt_lo, cnt_hi,          # LDX count (absolute)
        # loop:
        0xA0, 0x0F,                    # LDY #15
        # copy:
        0xB1, ptr,                     # LDA (ptr),Y
        0x99, temp_lo, temp_hi,        # STA polyval_temp,Y
        0x88,                          # DEY
        0x10, 0xF8,                    # BPL copy
        0x18,                          # CLC
        0xA5, ptr,                     # LDA ptr
        0x69, 0x10,                    # ADC #16
        0x85, ptr,                     # STA ptr
        0x90, 0x02,                    # BCC nocarry
        0xE6, ptr + 1,                 # INC ptr+1
        # nocarry:
        0x8A,                          # TXA
        0x48,                          # PHA
        0x20, upd_lo, upd_hi,          # JSR polyval_update
        0x68,                          # PLA
        0xAA,                          # TAX
        0xCA,                          # DEX
        0xD0, 0xE1,                    # BNE loop  (-31 back to LDY #15)
        0x60,                          # RTS
    ])


def install_multiblock_stub(transport, labels):
    """Install multi-block driver stub and its input buffer."""
    stub = build_multiblock_stub(labels["polyval_temp"],
                                 labels["polyval_update"])
    write_bytes(transport, MULTIBLOCK_STUB_ADDR, stub)
    # Fill buffer with a non-zero pattern. Content doesn't affect cycles.
    pattern = bytes(((i * 37 + 0x55) & 0xFF) for i in range(4096))
    write_bytes(transport, MULTIBLOCK_BUFFER_ADDR, pattern)
    if VERBOSE:
        print(f"  Multi-block stub installed at ${MULTIBLOCK_STUB_ADDR:04X} "
              f"({len(stub)} bytes)")
        print(f"  Multi-block input buffer at ${MULTIBLOCK_BUFFER_ADDR:04X} "
              f"(4096 bytes)")


# ---------------------------------------------------------------------------
# Benchmark setup functions
# ---------------------------------------------------------------------------

def setup_double(transport, labels):
    """Write a known 16-byte value to polyval_acc."""
    test_data = bytes([0x25, 0x62, 0x93, 0x47, 0x58, 0x92, 0x42, 0x76,
                       0x1d, 0x31, 0xf8, 0x26, 0xba, 0x4b, 0x75, 0x7b])
    write_bytes(transport, labels["polyval_acc"], test_data)


def setup_shift_left_4(transport, labels):
    """Write a known 16-byte value to polyval_acc."""
    test_data = bytes([0x4f, 0x4f, 0x95, 0x66, 0x8c, 0x83, 0xdf, 0xb6,
                       0x40, 0x17, 0x62, 0xbb, 0x2d, 0x01, 0xa2, 0x62])
    write_bytes(transport, labels["polyval_acc"], test_data)


def precompute_table_once(transport, labels):
    """Write H and precompute the htable. Call before benchmarks that need it."""
    h = bytes([0x25, 0x62, 0x93, 0x47, 0x58, 0x92, 0x42, 0x76,
               0x1d, 0x31, 0xf8, 0x26, 0xba, 0x4b, 0x75, 0x7b])
    write_bytes(transport, labels["polyval_h"], h)
    robust_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)


def setup_xor_table_entry(transport, labels):
    """Set up acc and pv_mul_nibble for xor_table_entry benchmark."""
    test_data = bytes([0xd1, 0xa2, 0x4d, 0xdd, 0x27, 0x21, 0xd0, 0x06,
                       0xbb, 0xe4, 0x5f, 0x20, 0xd3, 0xc9, 0xf3, 0x62])
    write_bytes(transport, labels["polyval_acc"], test_data)
    write_bytes(transport, labels["pv_mul_nibble"], bytes([0x07]))


def setup_precompute_table(transport, labels):
    """Write H for precompute_table benchmark."""
    h = bytes([0x25, 0x62, 0x93, 0x47, 0x58, 0x92, 0x42, 0x76,
               0x1d, 0x31, 0xf8, 0x26, 0xba, 0x4b, 0x75, 0x7b])
    write_bytes(transport, labels["polyval_h"], h)


def setup_multiply(transport, labels):
    """Write acc for multiply benchmark (htable must already exist)."""
    test_data = bytes([0x4f, 0x4f, 0x95, 0x66, 0x8c, 0x83, 0xdf, 0xb6,
                       0x40, 0x17, 0x62, 0xbb, 0x2d, 0x01, 0xa2, 0x62])
    write_bytes(transport, labels["polyval_acc"], test_data)


def setup_update(transport, labels):
    """Write acc and temp for update benchmark (htable must already exist)."""
    acc = bytes([0x00] * 16)
    temp = bytes([0x4f, 0x4f, 0x95, 0x66, 0x8c, 0x83, 0xdf, 0xb6,
                  0x40, 0x17, 0x62, 0xbb, 0x2d, 0x01, 0xa2, 0x62])
    write_bytes(transport, labels["polyval_acc"], acc)
    write_bytes(transport, labels["polyval_temp"], temp)


# ---------------------------------------------------------------------------
# Benchmark runner
# ---------------------------------------------------------------------------

def run_benchmarks(transport, labels, overhead, num_samples):
    """Run all benchmarks and return results dict."""

    # Precompute htable once for benchmarks that need it
    print("\n  Precomputing htable for benchmarks...")
    precompute_table_once(transport, labels)

    benchmarks = [
        {
            "name": "polyval_double",
            "label": "polyval_double",
            "setup": setup_double,
            "needs_htable": False,
        },
        {
            "name": "polyval_shift_left_4",
            "label": "polyval_shift_left_4",
            "setup": setup_shift_left_4,
            "needs_htable": False,
        },
        {
            "name": "polyval_xor_table_entry",
            "label": "polyval_xor_table_entry",
            "setup": setup_xor_table_entry,
            "needs_htable": True,
        },
        # polyval_precompute_table moved to the long-path benchmark: after
        # the Shoup 8-bit window rewrite its cycle count exceeds the 16-bit
        # Timer A range.
        {
            "name": "polyval_multiply",
            "label": "polyval_multiply",
            "setup": setup_multiply,
            "needs_htable": True,
        },
        {
            "name": "polyval_update",
            "label": "polyval_update",
            "setup": setup_update,
            "needs_htable": True,
        },
    ]

    results = {}

    for bench in benchmarks:
        name = bench["name"]
        target_addr = labels[bench["label"]]
        print(f"\n  Benchmarking {name} (${target_addr:04X})...")

        # If this benchmark needs the htable and the previous one was
        # precompute_table (which overwrites it), re-precompute
        if bench["needs_htable"] and name != "polyval_precompute_table":
            # Ensure htable is valid before each htable-dependent benchmark
            precompute_table_once(transport, labels)

        samples = []
        for i in range(num_samples):
            bench["setup"](transport, labels)
            cycles = measure_cycles(transport, target_addr, overhead)
            samples.append(cycles)
            if VERBOSE:
                print(f"    sample {i+1}: {cycles} cycles")

        spread = max(samples) - min(samples)
        median = sorted(samples)[len(samples) // 2]

        results[name] = {
            "samples": samples,
            "min": min(samples),
            "max": max(samples),
            "median": median,
            "spread": spread,
        }

        if spread > 0:
            print(f"    WARNING: spread = {spread} (expected 0 with SEI)")
        if min(samples) < 0 or max(samples) > 65000:
            print(f"    WARNING: possible overflow — min={min(samples)}, max={max(samples)}")

    return results


def run_long_benchmarks(transport, labels, long_overhead, num_samples):
    """Run benchmarks that exceed the 16-bit timer range."""
    benchmarks = [
        {
            "name": "polyval_precompute_table",
            "label": "polyval_precompute_table",
            "setup": setup_precompute_table,
        },
    ]
    results = {}
    for bench in benchmarks:
        name = bench["name"]
        target_addr = labels[bench["label"]]
        print(f"\n  Benchmarking {name} (${target_addr:04X}) [long]...")
        samples = []
        for i in range(num_samples):
            bench["setup"](transport, labels)
            cycles = measure_cycles_long(transport, target_addr, long_overhead)
            samples.append(cycles)
            if VERBOSE:
                print(f"    sample {i+1}: {cycles} cycles")
        spread = max(samples) - min(samples)
        median = sorted(samples)[len(samples) // 2]
        results[name] = {
            "samples": samples,
            "min": min(samples),
            "max": max(samples),
            "median": median,
            "spread": spread,
        }
        if spread > 0:
            print(f"    WARNING: spread = {spread} (expected 0 with SEI)")
    return results


def run_multiblock_benchmarks(transport, labels, short_overhead,
                              long_overhead, num_samples):
    """Measure polyval_update on N-block messages for N in {1,4,16,64,256}.

    For small N the short 16-bit wrapper suffices; for larger N we must use
    the chained 32-bit wrapper. We pick the wrapper per-N based on a safe
    threshold (any N whose projected cycle cost exceeds ~55000 uses long).
    """
    # Ensure htable is freshly populated (precompute_table clobbers it last).
    precompute_table_once(transport, labels)

    sizes = [1, 4, 16, 64, 256]
    results = {}

    # Projected per-block cost (current Shoup: polyval_update ~7085 cy).
    # Threshold: if N * 7200 > 55000, use the long wrapper. So N >= 8 → long.
    short_threshold_cycles = 55000

    for n in sizes:
        # Reset accumulator to zero before the run. The run's cycle count is
        # independent of acc content, but deterministic state is good hygiene.
        write_bytes(transport, labels["polyval_acc"], bytes([0] * 16))
        write_bytes(transport, MULTIBLOCK_COUNT_ADDR, bytes([n & 0xFF]))

        # Decide wrapper
        projected = n * 7200
        use_long = projected > short_threshold_cycles

        samples = []
        for i in range(num_samples):
            # Reset pointer / count each sample (count is consumed by DEX=0).
            write_bytes(transport, MULTIBLOCK_COUNT_ADDR, bytes([n & 0xFF]))
            if use_long:
                cycles = measure_cycles_long(transport, MULTIBLOCK_STUB_ADDR,
                                             long_overhead)
            else:
                cycles = measure_cycles(transport, MULTIBLOCK_STUB_ADDR,
                                        short_overhead)
            samples.append(cycles)
            if VERBOSE:
                wrapper = "long" if use_long else "short"
                print(f"    N={n:3d} sample {i+1} [{wrapper}]: {cycles} cycles")

        spread = max(samples) - min(samples)
        median = sorted(samples)[len(samples) // 2]
        results[n] = {
            "samples": samples,
            "median": median,
            "spread": spread,
            "wrapper": "long" if use_long else "short",
        }
        print(f"  N={n:3d}: {median} cycles "
              f"({median / n:.1f} cy/block) "
              f"[{'long' if use_long else 'short'}, spread={spread}]")

    return results


def print_long_results_table(results):
    if not results:
        return
    print("\n" + "=" * 70)
    print("POLYVAL Long-Run Benchmark Results (32-bit chained Timer A+B)")
    print("=" * 70)
    print(f"{'Routine':<30} {'Cycles':>10} {'Min':>10} {'Max':>10} {'Spread':>8}")
    print("-" * 70)
    for name, data in results.items():
        spread_str = str(data["spread"])
        if data["spread"] > 0:
            spread_str += " (!)"
        print(f"{name:<30} {data['median']:>10} {data['min']:>10} "
              f"{data['max']:>10} {spread_str:>8}")
    print("=" * 70)


def print_multiblock_results_table(results):
    if not results:
        return
    print("\n" + "=" * 70)
    print("Multi-block polyval_update (Horner batching baseline)")
    print("=" * 70)
    print(f"{'N blocks':>10} {'Total cycles':>14} {'cy/block':>12} "
          f"{'Spread':>8} {'Wrapper':>8}")
    print("-" * 70)
    for n, data in results.items():
        cyb = data["median"] / n
        spread_str = str(data["spread"])
        if data["spread"] > 0:
            spread_str += " (!)"
        print(f"{n:>10d} {data['median']:>14d} {cyb:>12.1f} "
              f"{spread_str:>8} {data['wrapper']:>8}")
    print("=" * 70)


def print_results_table(results):
    """Print a formatted results table."""
    print("\n" + "=" * 70)
    print("POLYVAL Cycle-Accurate Benchmark Results")
    print("=" * 70)
    print(f"{'Routine':<30} {'Cycles':>8} {'Min':>8} {'Max':>8} {'Spread':>8}")
    print("-" * 70)

    for name, data in results.items():
        spread_str = str(data["spread"])
        if data["spread"] > 0:
            spread_str += " (!)"
        print(f"{name:<30} {data['median']:>8} {data['min']:>8} {data['max']:>8} {spread_str:>8}")

    print("-" * 70)

    # Derived: update - multiply = XOR loop cost
    if "polyval_update" in results and "polyval_multiply" in results:
        xor_cost = results["polyval_update"]["median"] - results["polyval_multiply"]["median"]
        print(f"{'(update - multiply = XOR loop)':<30} {xor_cost:>8}")

    print("=" * 70)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    global VERBOSE
    os.chdir(PROJECT_ROOT)

    # Parse args
    num_samples = DEFAULT_SAMPLES
    if "--samples" in sys.argv:
        idx = sys.argv.index("--samples")
        if idx + 1 < len(sys.argv):
            num_samples = int(sys.argv[idx + 1])

    VERBOSE = "--verbose" in sys.argv or "-v" in sys.argv

    print("POLYVAL Cycle-Accurate Benchmark")
    print(f"Samples per routine: {num_samples}")

    # Build. Honour POLYVAL_PROFILE from the environment so
    # `POLYVAL_PROFILE=short python3 tools/benchmark_polyval.py` picks the
    # short-profile build. Default matches the Makefile default (long).
    print("\n=== Building ===")
    profile = os.environ.get("POLYVAL_PROFILE", "long")
    print(f"  Profile: {profile}")
    subprocess.run(["make", "clean"], capture_output=True)
    result = subprocess.run(
        ["make", f"POLYVAL_PROFILE={profile}"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"Build failed:\n{result.stderr}")
        sys.exit(1)
    print("  Build OK")

    if not os.path.exists(PRG_PATH):
        print(f"FATAL: {PRG_PATH} not found")
        sys.exit(1)

    # Load labels
    labels = Labels.from_file(LABELS_PATH)
    required_labels = [
        "polyval_double", "polyval_shift_left_4", "polyval_xor_table_entry",
        "polyval_precompute_table", "polyval_multiply", "polyval_update",
        "polyval_acc", "polyval_h", "polyval_temp", "pv_mul_nibble",
    ]
    for name in required_labels:
        if labels.address(name) is None:
            print(f"FATAL: '{name}' label not found in {LABELS_PATH}")
            sys.exit(1)
    print(f"  Labels loaded ({len(required_labels)} symbols)")
    if VERBOSE:
        for name in required_labels:
            print(f"    {name}: ${labels[name]:04X}")

    # Start VICE
    print("\n=== Starting VICE ===")
    config = ViceConfig(
        prg_path=PRG_PATH,
        warp=True,
        ntsc=True,
        sound=False,
    )

    t0 = time.time()

    with ViceInstanceManager(config=config) as mgr:
        inst = mgr.acquire()
        print(f"  VICE started (PID {inst.pid}, port {inst.port})")

        transport = inst.transport

        # Wait for program to initialize
        print("  Waiting for main menu...")
        grid = wait_for_text(transport, "Q=QUIT", timeout=60.0, verbose=False)
        if grid is None:
            print("FATAL: Main menu did not appear")
            dump_screen(transport, "startup")
            sys.exit(1)
        print("  Ready")

        # Install timing wrappers
        print("\n=== Installing CIA Timer Wrappers ===")
        install_timing_wrapper(transport)
        install_long_wrapper(transport)
        install_multiblock_stub(transport, labels)

        # Calibrate short and long paths
        print("\n=== Calibrating (16-bit Timer A) ===")
        overhead = calibrate(transport)

        print("\n=== Calibrating (32-bit chained Timer A+B) ===")
        long_overhead = calibrate_long(transport)
        verify_long_wrapper(transport, long_overhead)

        # Run short-path benchmarks
        print("\n=== Running Benchmarks (short path) ===")
        results = run_benchmarks(transport, labels, overhead, num_samples)

        # Long-path: polyval_precompute_table (overflows 16-bit timer)
        print("\n=== Running Benchmarks (long path) ===")
        long_results = run_long_benchmarks(transport, labels,
                                           long_overhead, num_samples)

        # Multi-block polyval_update sweep
        print("\n=== Multi-block polyval_update ===")
        multiblock_results = run_multiblock_benchmarks(
            transport, labels, overhead, long_overhead, num_samples)

    elapsed = time.time() - t0

    # Print results
    print_results_table(results)
    print_long_results_table(long_results)
    print_multiblock_results_table(multiblock_results)
    print(f"\nTotal time: {elapsed:.1f}s")


if __name__ == "__main__":
    main()
