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
        {
            "name": "polyval_precompute_table",
            "label": "polyval_precompute_table",
            "setup": setup_precompute_table,
            "needs_htable": False,
        },
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

    # Build
    print("\n=== Building ===")
    subprocess.run(["make", "clean"], capture_output=True)
    result = subprocess.run(["make"], capture_output=True, text=True)
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

        # Install timing wrapper
        print("\n=== Installing CIA Timer Wrapper ===")
        install_timing_wrapper(transport)

        # Calibrate
        print("\n=== Calibrating ===")
        overhead = calibrate(transport)

        # Run benchmarks
        print("\n=== Running Benchmarks ===")
        results = run_benchmarks(transport, labels, overhead, num_samples)

    elapsed = time.time() - t0

    # Print results
    print_results_table(results)
    print(f"\nTotal time: {elapsed:.1f}s")


if __name__ == "__main__":
    main()
