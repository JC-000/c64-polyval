#!/usr/bin/env python3
"""
test_polyval_direct.py - Direct-Memory POLYVAL Regression Test

Tests every routine in polyval.asm by calling them directly via jsr(),
writing inputs and reading outputs through VICE memory access.
Designed as a reliable regression suite for use during performance
optimization of the POLYVAL implementation.

Tested routines:
  polyval_init            - zero accumulator
  polyval_double          - left-shift 128 bits + reduction
  polyval_right_shift_1   - right-shift 128 bits + reduction
  polyval_shift_left_4    - left-shift 4 bits (4x double)
  polyval_xor_table_entry - XOR htable[nibble] into acc
  polyval_precompute_table - build htable[0..15] from H
  polyval_multiply        - 4-bit table multiply (tested in isolation)
  polyval_update          - XOR block + multiply
  Full POLYVAL pipeline   - init + precompute + multi-block update

Usage:
    python3 tools/test_polyval_direct.py [--seed S] [--iterations N] [--verbose]

Requires: Python 3.10+, c64_test_harness, VICE x64sc
"""

import os
import random
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
from reference_sanity import cross_validate_reference
from polyval_reference import (
    polyval,
    polyval_dot,
    polyval_double as py_double,
    polyval_right_shift_1 as py_right_shift_1,
    polyval_precompute_table as py_precompute_table,
    polyval_multiply_table as py_multiply_table,
    bytes_to_int,
    int_to_bytes,
)

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

DEFAULT_SEED = 8452  # deterministic by default (RFC number)
DEFAULT_ITERATIONS = 10  # random cases per test group

VERBOSE = False

# Max retries for transient VICE connection failures
JSR_RETRIES = 3
JSR_RETRY_DELAY = 0.3

# ZP staging wrapper: polyval_acc lives in ZP ($10-$1F) which BASIC/KERNAL
# modifies between jsr() calls. This wrapper copies a staging buffer to/from
# ZP around each routine call so tests can reliably read/write polyval_acc.
ZP_WRAPPER_ADDR = 0xC040
ZP_STAGING_ADDR = 0xC100  # 16-byte staging buffer

# Wrapper code at $C040 (24 bytes):
#   Copy staging ($C100) → ZP ($10-$1F)
#   JSR target (patched)
#   Copy ZP ($10-$1F) → staging ($C100)
#   RTS
ZP_WRAPPER_CODE = bytes([
    0xA2, 0x0F,             # $C040: LDX #15
    0xBD, 0x00, 0xC1,       # $C042: LDA $C100,X
    0x95, 0x10,             # $C045: STA $10,X
    0xCA,                   # $C047: DEX
    0x10, 0xF8,             # $C048: BPL $C042
    0x20, 0x00, 0x00,       # $C04A: JSR $0000 (patched)
    0xA2, 0x0F,             # $C04D: LDX #15
    0xB5, 0x10,             # $C04F: LDA $10,X
    0x9D, 0x00, 0xC1,       # $C051: STA $C100,X
    0xCA,                   # $C054: DEX
    0x10, 0xF8,             # $C055: BPL $C04F
    0x60,                   # $C057: RTS
])
ZP_WRAPPER_JSR_OFFSET = 0x0B  # offset of JSR operand low byte


# ---------------------------------------------------------------------------
# Low-level C64 helpers
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


def install_zp_wrapper(transport):
    """Install ZP staging wrapper at $C040 and clear staging buffer."""
    write_bytes(transport, ZP_WRAPPER_ADDR, ZP_WRAPPER_CODE)
    write_bytes(transport, ZP_STAGING_ADDR, b'\x00' * 16)


def zp_jsr(transport, addr, timeout=10.0, retries=JSR_RETRIES):
    """JSR via ZP wrapper: staging↔ZP copy around the call."""
    lo = addr & 0xFF
    hi = (addr >> 8) & 0xFF
    write_bytes(transport, ZP_WRAPPER_ADDR + ZP_WRAPPER_JSR_OFFSET, bytes([lo, hi]))
    return robust_jsr(transport, ZP_WRAPPER_ADDR, timeout=timeout, retries=retries)


def write_acc(transport, labels, val: bytes):
    """Write 16 bytes to staging buffer (copied to ZP by wrapper)."""
    assert len(val) == 16
    write_bytes(transport, ZP_STAGING_ADDR, val)


def read_acc(transport, labels) -> bytes:
    """Read 16 bytes from staging buffer (copied from ZP by wrapper)."""
    return read_bytes(transport, ZP_STAGING_ADDR, 16)


def write_h(transport, labels, val: bytes):
    """Write 16 bytes to polyval_h."""
    assert len(val) == 16
    write_bytes(transport, labels["polyval_h"], val)


def read_htable(transport, labels) -> list[bytes]:
    """Read all 16 table entries (256 bytes total)."""
    raw = read_bytes(transport, labels["polyval_htable"], 256)
    return [raw[i * 16:(i + 1) * 16] for i in range(16)]


def write_temp(transport, labels, val: bytes):
    """Write 16 bytes to polyval_temp."""
    assert len(val) == 16
    write_bytes(transport, labels["polyval_temp"], val)


def random_block() -> bytes:
    """Generate a random 16-byte block."""
    return bytes(random.randint(0, 255) for _ in range(16))


# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------

class TestResults:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.errors = []

    def ok(self, name: str):
        self.passed += 1
        if VERBOSE:
            print(f"  PASS: {name}")

    def fail(self, name: str, detail: str = ""):
        self.failed += 1
        msg = f"  FAIL: {name}"
        if detail:
            msg += f"\n{detail}"
        print(msg)
        self.errors.append(name)

    def check(self, name: str, got: bytes, expected: bytes,
              context: str = "") -> bool:
        if got == expected:
            self.ok(name)
            return True
        else:
            lines = [f"    expected: {expected.hex()}",
                     f"    got:      {got.hex()}"]
            if context:
                lines.insert(0, f"    {context}")
            self.fail(name, "\n".join(lines))
            return False


# ---------------------------------------------------------------------------
# Test: polyval_init
# ---------------------------------------------------------------------------

def test_init(transport, labels, results: TestResults, **_kwargs):
    """polyval_init must zero all 16 bytes of the accumulator."""
    print("\n[polyval_init]")

    # Fill acc with non-zero pattern, then init
    write_acc(transport, labels, bytes(range(0x10, 0x20)))
    zp_jsr(transport, labels["polyval_init"], timeout=5.0)
    results.check("init zeros accumulator", read_acc(transport, labels),
                  b'\x00' * 16)


# ---------------------------------------------------------------------------
# Test: polyval_double
# ---------------------------------------------------------------------------

def test_double(transport, labels, results: TestResults, iterations=8):
    """polyval_double: left-shift by 1 with reduction when MSB carries out."""
    print("\n[polyval_double]")

    cases = [
        # (input_bytes, description)
        (b'\x01' + b'\x00' * 15,           "0x01 -> 0x02 (simple shift)"),
        (b'\x80' + b'\x00' * 15,           "0x80 -> carry into byte 1"),
        (b'\x00' * 15 + b'\x80',           "MSB set -> reduction"),
        (b'\x00' * 15 + b'\x40',           "bit 126 -> bit 127 no reduce"),
        (b'\xff' * 16,                      "all-ones"),
        (b'\x00' * 16,                      "zero stays zero"),
        (b'\xaa' * 16,                      "alternating bits 0xAA"),
        (b'\x55' * 16,                      "alternating bits 0x55"),
    ]

    for val, desc in cases:
        write_acc(transport, labels, val)
        zp_jsr(transport, labels["polyval_double"], timeout=5.0)
        expected = int_to_bytes(py_double(bytes_to_int(val)))
        results.check(f"double: {desc}", read_acc(transport, labels), expected)

    # Random cases
    for i in range(iterations):
        val = random_block()
        write_acc(transport, labels, val)
        zp_jsr(transport, labels["polyval_double"], timeout=5.0)
        expected = int_to_bytes(py_double(bytes_to_int(val)))
        results.check(f"double: random #{i+1}", read_acc(transport, labels),
                      expected, context=f"input: {val.hex()}")


# ---------------------------------------------------------------------------
# Test: polyval_right_shift_1
# ---------------------------------------------------------------------------

def test_right_shift(transport, labels, results: TestResults, iterations=8):
    """polyval_right_shift_1: right-shift by 1 with $E1 reduction on LSB."""
    print("\n[polyval_right_shift_1]")

    cases = [
        (b'\x02' + b'\x00' * 15,           "0x02 -> 0x01 (simple)"),
        (b'\x00\x01' + b'\x00' * 14,       "byte 1 bit 0 -> byte 0 MSB"),
        (b'\x01' + b'\x00' * 15,           "LSB=1 triggers $E1 reduction"),
        (b'\x00' * 15 + b'\x80',           "MSB only"),
        (b'\xff' * 16,                      "all-ones"),
        (b'\x00' * 16,                      "zero stays zero"),
        (b'\x03' + b'\x00' * 15,           "0x03 -> 0x01 + reduction"),
        (b'\xaa' * 16,                      "alternating bits 0xAA"),
    ]

    for val, desc in cases:
        write_acc(transport, labels, val)
        zp_jsr(transport, labels["polyval_right_shift_1"], timeout=5.0)
        expected = int_to_bytes(py_right_shift_1(bytes_to_int(val)))
        results.check(f"rshift: {desc}", read_acc(transport, labels), expected)

    # Random cases
    for i in range(iterations):
        val = random_block()
        write_acc(transport, labels, val)
        zp_jsr(transport, labels["polyval_right_shift_1"], timeout=5.0)
        expected = int_to_bytes(py_right_shift_1(bytes_to_int(val)))
        results.check(f"rshift: random #{i+1}", read_acc(transport, labels),
                      expected, context=f"input: {val.hex()}")


# ---------------------------------------------------------------------------
# Test: polyval_shift_left_4
# ---------------------------------------------------------------------------

def test_shift_left_4(transport, labels, results: TestResults, iterations=6):
    """polyval_shift_left_4: must equal 4 consecutive doubles."""
    print("\n[polyval_shift_left_4]")

    cases = [
        b'\x01' + b'\x00' * 15,
        b'\x00' * 15 + b'\x80',
        b'\xff' * 16,
        b'\x00' * 14 + b'\x10\x00',
    ]

    for val in cases:
        write_acc(transport, labels, val)
        zp_jsr(transport, labels["polyval_shift_left_4"], timeout=5.0)
        # Python: apply double 4 times
        v = bytes_to_int(val)
        for _ in range(4):
            v = py_double(v)
        expected = int_to_bytes(v)
        results.check(f"shl4: {val.hex()}", read_acc(transport, labels),
                      expected)

    # Random cases
    for i in range(iterations):
        val = random_block()
        write_acc(transport, labels, val)
        zp_jsr(transport, labels["polyval_shift_left_4"], timeout=5.0)
        v = bytes_to_int(val)
        for _ in range(4):
            v = py_double(v)
        expected = int_to_bytes(v)
        results.check(f"shl4: random #{i+1}", read_acc(transport, labels),
                      expected, context=f"input: {val.hex()}")


# ---------------------------------------------------------------------------
# Test: polyval_precompute_table
# ---------------------------------------------------------------------------

def test_precompute_table(transport, labels, results: TestResults, iterations=3):
    """polyval_precompute_table: verify all 16 entries for multiple H values."""
    print("\n[polyval_precompute_table]")

    h_values = [
        ("25629347589242761d31f826ba4b757b", "RFC 8452 Appendix A"),
        ("01" + "00" * 15, "H = 1"),
        ("ff" * 16, "H = all-ones"),
        ("00" * 16, "H = 0"),
    ]

    # Add random H values
    for i in range(iterations):
        h_values.append((random_block().hex(), f"random H #{i+1}"))

    for h_hex, desc in h_values:
        h = bytes.fromhex(h_hex) if isinstance(h_hex, str) else h_hex
        write_h(transport, labels, h)
        zp_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)
        c64_table = read_htable(transport, labels)
        py_table = py_precompute_table(bytes_to_int(h))

        all_match = True
        for i in range(16):
            expected = int_to_bytes(py_table[i])
            if c64_table[i] != expected:
                results.fail(f"table {desc}: entry [{i}]",
                             f"    expected: {expected.hex()}\n"
                             f"    got:      {c64_table[i].hex()}")
                all_match = False
                break

        if all_match:
            results.ok(f"table: {desc} (16/16 entries)")


# ---------------------------------------------------------------------------
# Test: polyval_xor_table_entry
# ---------------------------------------------------------------------------

def test_xor_table_entry(transport, labels, results: TestResults, **_kwargs):
    """polyval_xor_table_entry: XOR htable[nibble] into acc."""
    print("\n[polyval_xor_table_entry]")

    # First precompute a known table
    h = bytes.fromhex("25629347589242761d31f826ba4b757b")
    write_h(transport, labels, h)
    zp_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)
    py_table = py_precompute_table(bytes_to_int(h))

    # Test nibble 0 (should be no-op since htable[0] = 0)
    acc_val = random_block()
    write_acc(transport, labels, acc_val)
    write_bytes(transport, labels["pv_mul_nibble"], b'\x00')
    zp_jsr(transport, labels["polyval_xor_table_entry"], timeout=5.0)
    results.check("xor_table: nibble 0 (no-op)", read_acc(transport, labels),
                  acc_val)

    # Test each nibble 1..15
    for nibble in range(1, 16):
        acc_val = random_block()
        write_acc(transport, labels, acc_val)
        write_bytes(transport, labels["pv_mul_nibble"], bytes([nibble]))
        zp_jsr(transport, labels["polyval_xor_table_entry"], timeout=5.0)

        expected = int_to_bytes(bytes_to_int(acc_val) ^ py_table[nibble])
        results.check(f"xor_table: nibble {nibble}", read_acc(transport, labels),
                      expected)


# ---------------------------------------------------------------------------
# Test: polyval_multiply (in isolation)
# ---------------------------------------------------------------------------

def test_multiply_isolated(transport, labels, results: TestResults, iterations=5):
    """polyval_multiply: test the multiply in isolation.

    polyval_multiply reads polyval_acc, multiplies by H using the
    precomputed htable, and writes the result back to polyval_acc.
    We test it directly, without going through polyval_update.
    """
    print("\n[polyval_multiply — isolated]")

    # Use several different H keys
    h_keys = [
        bytes.fromhex("25629347589242761d31f826ba4b757b"),
        b'\x01' + b'\x00' * 15,
        b'\xff' * 16,
    ]
    # Add random H keys
    for _ in range(3):
        h_keys.append(random_block())

    for h_idx, h in enumerate(h_keys):
        # Precompute table for this H
        write_h(transport, labels, h)
        zp_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)
        py_table = py_precompute_table(bytes_to_int(h))

        # Test with several accumulator values
        acc_values = [
            b'\x01' + b'\x00' * 15,
            b'\xff' * 16,
            b'\x00' * 16,
        ]
        # Add random acc values
        for _ in range(iterations):
            acc_values.append(random_block())

        for acc_idx, acc_val in enumerate(acc_values):
            write_acc(transport, labels, acc_val)
            zp_jsr(transport, labels["polyval_multiply"], timeout=30.0)

            expected = int_to_bytes(
                py_multiply_table(bytes_to_int(acc_val), py_table)
            )
            tag = f"multiply: H#{h_idx} acc#{acc_idx}"
            results.check(tag, read_acc(transport, labels), expected,
                          context=f"H: {h.hex()}, acc: {acc_val.hex()}")


# ---------------------------------------------------------------------------
# Test: polyval_update
# ---------------------------------------------------------------------------

def test_update(transport, labels, results: TestResults, iterations=5):
    """polyval_update: XOR polyval_temp into acc, then multiply by H."""
    print("\n[polyval_update]")

    h = bytes.fromhex("25629347589242761d31f826ba4b757b")
    write_h(transport, labels, h)
    zp_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)
    py_table = py_precompute_table(bytes_to_int(h))

    cases = [
        (b'\x00' * 16, b'\x01' + b'\x00' * 15, "zero acc + simple block"),
        (b'\xff' * 16, b'\xff' * 16, "all-ones XOR all-ones = 0"),
        (b'\x00' * 16, b'\x00' * 16, "zero XOR zero = 0"),
    ]

    # Add random cases
    for i in range(iterations):
        cases.append((random_block(), random_block(), f"random #{i+1}"))

    for acc_val, block, desc in cases:
        write_acc(transport, labels, acc_val)
        write_temp(transport, labels, block)
        zp_jsr(transport, labels["polyval_update"], timeout=30.0)

        xored = bytes_to_int(acc_val) ^ bytes_to_int(block)
        expected = int_to_bytes(py_multiply_table(xored, py_table))
        results.check(f"update: {desc}", read_acc(transport, labels), expected,
                      context=f"acc: {acc_val.hex()}, block: {block.hex()}")


# ---------------------------------------------------------------------------
# Test: full POLYVAL pipeline
# ---------------------------------------------------------------------------

def test_full_pipeline(transport, labels, results: TestResults, iterations=5):
    """Full POLYVAL(H, X1, ..., Xn) via init + precompute + update loop."""
    print("\n[full POLYVAL pipeline]")

    # 1. RFC 8452 Appendix A
    h = bytes.fromhex("25629347589242761d31f826ba4b757b")
    x1 = bytes.fromhex("4f4f95668c83dfb6401762bb2d01a262")
    x2 = bytes.fromhex("d1a24ddd2721d006bbe45f20d3c9f362")
    expected = bytes.fromhex("f7a3b47b846119fae5b7866cf5e5b77e")

    write_h(transport, labels, h)
    zp_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)
    zp_jsr(transport, labels["polyval_init"], timeout=5.0)
    write_temp(transport, labels, x1)
    zp_jsr(transport, labels["polyval_update"], timeout=30.0)
    write_temp(transport, labels, x2)
    zp_jsr(transport, labels["polyval_update"], timeout=30.0)
    results.check("RFC 8452 Appendix A: POLYVAL(H, X1, X2)",
                  read_acc(transport, labels), expected)

    # 2. Single block: H=1, X=1
    h = b'\x01' + b'\x00' * 15
    block = b'\x01' + b'\x00' * 15
    expected = polyval(h, block)
    _run_pipeline(transport, labels, h, [block], results,
                  "single block: H=1, X=1")

    # 3. H=0 with random block -> must be zero
    h = b'\x00' * 16
    block = random_block()
    _run_pipeline(transport, labels, h, [block], results,
                  "H=0 -> zero output")

    # 4. Zero block
    h = random_block()
    _run_pipeline(transport, labels, h, [b'\x00' * 16], results,
                  "zero block")

    # 5. Random: 1 block
    for i in range(iterations):
        h = random_block()
        blocks = [random_block()]
        _run_pipeline(transport, labels, h, blocks, results,
                      f"random 1-block #{i+1}")

    # 6. Random: 2 blocks
    for i in range(iterations):
        h = random_block()
        blocks = [random_block(), random_block()]
        _run_pipeline(transport, labels, h, blocks, results,
                      f"random 2-block #{i+1}")

    # 7. Random: 3 blocks
    for i in range(max(1, iterations // 2)):
        h = random_block()
        blocks = [random_block() for _ in range(3)]
        _run_pipeline(transport, labels, h, blocks, results,
                      f"random 3-block #{i+1}")

    # 8. Random: 4 blocks
    for i in range(max(1, iterations // 2)):
        h = random_block()
        blocks = [random_block() for _ in range(4)]
        _run_pipeline(transport, labels, h, blocks, results,
                      f"random 4-block #{i+1}")

    # 9. Same H, sequential blocks (tests accumulator chaining)
    h = random_block()
    write_h(transport, labels, h)
    zp_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)
    zp_jsr(transport, labels["polyval_init"], timeout=5.0)

    blocks = [random_block() for _ in range(6)]
    for block in blocks:
        write_temp(transport, labels, block)
        zp_jsr(transport, labels["polyval_update"], timeout=30.0)

    expected = polyval(h, *blocks)
    results.check("chained 6-block (single precompute)",
                  read_acc(transport, labels), expected,
                  context=f"H: {h.hex()}")


def _run_pipeline(transport, labels, h: bytes, blocks: list[bytes],
                  results: TestResults, desc: str):
    """Helper: run full POLYVAL pipeline and check result."""
    write_h(transport, labels, h)
    zp_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)
    zp_jsr(transport, labels["polyval_init"], timeout=5.0)
    for block in blocks:
        write_temp(transport, labels, block)
        zp_jsr(transport, labels["polyval_update"], timeout=30.0)

    expected = polyval(h, *blocks)
    results.check(f"pipeline: {desc}", read_acc(transport, labels), expected,
                  context=f"H: {h.hex()}, {len(blocks)} block(s)")


# ---------------------------------------------------------------------------
# Test: multiply consistency (table vs dot product)
# ---------------------------------------------------------------------------

def test_multiply_vs_dot(transport, labels, results: TestResults, iterations=10):
    """Verify polyval_multiply matches polyval_dot for random inputs.

    polyval_multiply computes dot(acc, H) using the table.
    We compare against the bit-by-bit polyval_dot reference.
    """
    print("\n[multiply vs dot product consistency]")

    for i in range(iterations):
        h = random_block()
        acc_val = random_block()

        # Set up table
        write_h(transport, labels, h)
        zp_jsr(transport, labels["polyval_precompute_table"], timeout=30.0)

        # Multiply on C64
        write_acc(transport, labels, acc_val)
        zp_jsr(transport, labels["polyval_multiply"], timeout=30.0)
        c64_result = read_acc(transport, labels)

        # Compare against bit-by-bit dot product
        expected = int_to_bytes(polyval_dot(bytes_to_int(acc_val),
                                            bytes_to_int(h)))
        results.check(f"dot consistency #{i+1}", c64_result, expected,
                      context=f"H: {h.hex()}, acc: {acc_val.hex()}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    global VERBOSE
    os.chdir(PROJECT_ROOT)

    # Cross-check Python oracle against an external AES-GCM-SIV implementation
    # BEFORE any 6502 code runs. Aborts the suite on drift.
    cross_validate_reference()

    # Parse args
    seed = DEFAULT_SEED
    if "--seed" in sys.argv:
        idx = sys.argv.index("--seed")
        if idx + 1 < len(sys.argv):
            seed = int(sys.argv[idx + 1])
    random.seed(seed)

    iterations = DEFAULT_ITERATIONS
    if "--iterations" in sys.argv:
        idx = sys.argv.index("--iterations")
        if idx + 1 < len(sys.argv):
            iterations = int(sys.argv[idx + 1])

    VERBOSE = "--verbose" in sys.argv or "-v" in sys.argv

    print(f"POLYVAL Direct Regression Test")
    print(f"Seed: {seed} (reproduce with --seed {seed})")
    print(f"Iterations: {iterations} random cases per test group")

    # Build. Honour POLYVAL_PROFILE env var for dual-path selection.
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
        "polyval_acc", "polyval_h", "polyval_temp", "polyval_htable",
        "polyval_init", "polyval_double", "polyval_right_shift_1",
        "polyval_shift_left_4", "polyval_precompute_table",
        "polyval_multiply", "polyval_update",
        "polyval_xor_table_entry", "pv_mul_nibble",
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

        # Install ZP staging wrapper for polyval_acc
        install_zp_wrapper(transport)
        print("  ZP staging wrapper installed")

        # Run all tests
        results = TestResults()

        test_groups = [
            ("polyval_init", test_init),
            ("polyval_double", test_double),
            ("polyval_right_shift_1", test_right_shift),
            ("polyval_shift_left_4", test_shift_left_4),
            ("polyval_precompute_table", test_precompute_table),
            ("polyval_xor_table_entry", test_xor_table_entry),
            ("polyval_multiply (isolated)", test_multiply_isolated),
            ("polyval_update", test_update),
            ("full pipeline", test_full_pipeline),
            ("multiply vs dot", test_multiply_vs_dot),
        ]

        for group_name, test_fn in test_groups:
            try:
                test_fn(transport, labels, results, iterations=iterations)
            except Exception as e:
                results.fail(f"{group_name}: EXCEPTION",
                             f"    {type(e).__name__}: {e}")
                print(f"  (continuing with next test group...)")

    elapsed = time.time() - t0
    total = results.passed + results.failed

    # Summary
    print("\n" + "=" * 60)
    print(f"POLYVAL Direct Regression Test — {elapsed:.1f}s")
    print("=" * 60)
    print(f"  Passed: {results.passed}/{total}")
    print(f"  Failed: {results.failed}/{total}")
    if results.failed == 0:
        print(f"\n  ALL {total} TESTS PASSED")
    else:
        print(f"\n  {results.failed} TEST(S) FAILED:")
        for name in results.errors:
            print(f"    - {name}")
    print("=" * 60)

    sys.exit(0 if results.failed == 0 else 1)


if __name__ == "__main__":
    main()
