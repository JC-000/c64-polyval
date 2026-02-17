#!/usr/bin/env python3
"""
test_polyval_direct.py - Direct-Memory POLYVAL Test

Tests the C64 POLYVAL implementation by calling polyval_init,
polyval_precompute_table, polyval_update, and polyval_multiply directly
via jsr() — writing input data and reading results through memory.

Tests:
  - polyval_init zeros the accumulator
  - polyval_precompute_table builds correct H table
  - polyval_double left-shifts correctly
  - polyval_right_shift_1 right-shifts correctly
  - Single-block POLYVAL
  - Multi-block POLYVAL (RFC 8452 Appendix A)
  - Random single/multi-block tests vs Python reference
  - Edge cases: zero H, zero blocks

Usage:
    python3 tools/test_polyval_direct.py [--iterations N] [--seed S]

Requires: Python 3.10+, c64_test_harness, VICE x64sc
"""

import json
import os
import random
import struct
import subprocess
import sys

# Add project tools dir to path for polyval_reference
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
from polyval_reference import (
    polyval,
    polyval_dot,
    polyval_double as py_double,
    polyval_right_shift_1 as py_right_shift_1,
    polyval_precompute_table as py_precompute_table,
    bytes_to_int,
    int_to_bytes,
)

from c64_test_harness import (
    Labels,
    ViceConfig,
    ViceProcess,
    ViceTransport,
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
VECTORS_PATH = os.path.join(PROJECT_ROOT, "test", "rfc8452_vectors.json")

DEFAULT_ITERATIONS = 30


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def random_bytes(n: int) -> bytes:
    return bytes(random.randint(0, 255) for _ in range(n))


def c64_polyval_init(transport: ViceTransport, labels: Labels):
    """Call polyval_init on C64."""
    jsr(transport, labels["polyval_init"], timeout=5.0)


def c64_polyval_precompute(transport: ViceTransport, labels: Labels, h: bytes):
    """Set H key and precompute table on C64."""
    write_bytes(transport, labels["polyval_h"], h)
    jsr(transport, labels["polyval_precompute_table"], timeout=30.0)


def c64_polyval_update(transport: ViceTransport, labels: Labels, block: bytes):
    """Write a 16-byte block to polyval_temp and call polyval_update."""
    assert len(block) == 16
    write_bytes(transport, labels["polyval_temp"], block)
    jsr(transport, labels["polyval_update"], timeout=30.0)


def c64_read_acc(transport: ViceTransport, labels: Labels) -> bytes:
    """Read the 16-byte POLYVAL accumulator."""
    return read_bytes(transport, labels["polyval_acc"], 16)


def c64_read_htable(transport: ViceTransport, labels: Labels) -> list[bytes]:
    """Read all 16 table entries (256 bytes)."""
    raw = read_bytes(transport, labels["polyval_htable"], 256)
    return [raw[i*16:(i+1)*16] for i in range(16)]


def c64_polyval_full(transport: ViceTransport, labels: Labels,
                     h: bytes, blocks: list[bytes]) -> bytes:
    """Run complete POLYVAL: init, precompute, update each block, read result."""
    c64_polyval_precompute(transport, labels, h)
    c64_polyval_init(transport, labels)
    for block in blocks:
        c64_polyval_update(transport, labels, block)
    return c64_read_acc(transport, labels)


# ---------------------------------------------------------------------------
# Individual test functions
# ---------------------------------------------------------------------------

def test_init(transport: ViceTransport, labels: Labels) -> bool:
    """Verify polyval_init zeros the accumulator."""
    print("\n--- polyval_init: zeros accumulator ---")

    # Write non-zero data to acc first
    write_bytes(transport, labels["polyval_acc"], bytes(range(16)))
    c64_polyval_init(transport, labels)
    acc = c64_read_acc(transport, labels)

    if acc == b'\x00' * 16:
        print("  PASS: accumulator zeroed")
        return True
    else:
        print(f"  FAIL: acc = {acc.hex()}")
        return False


def test_double(transport: ViceTransport, labels: Labels) -> bool:
    """Test polyval_double (left-shift with reduction)."""
    print("\n--- polyval_double: left-shift + reduction ---")

    test_cases = [
        (b'\x01' + b'\x00' * 15, "simple shift"),
        (b'\x00' * 15 + b'\x80', "carry out triggers reduction"),
        (b'\xff' * 16, "all-ones"),
    ]

    for val, desc in test_cases:
        write_bytes(transport, labels["polyval_acc"], val)
        jsr(transport, labels["polyval_double"], timeout=5.0)
        c64_result = c64_read_acc(transport, labels)

        py_result = int_to_bytes(py_double(bytes_to_int(val)))

        if c64_result != py_result:
            print(f"  FAIL: {desc}")
            print(f"    Input:    {val.hex()}")
            print(f"    Expected: {py_result.hex()}")
            print(f"    Got:      {c64_result.hex()}")
            return False

    print("  PASS: all double cases match")
    return True


def test_right_shift(transport: ViceTransport, labels: Labels) -> bool:
    """Test polyval_right_shift_1 (right-shift with reduction)."""
    print("\n--- polyval_right_shift_1: right-shift + reduction ---")

    test_cases = [
        (b'\x02' + b'\x00' * 15, "simple shift"),
        (b'\x01' + b'\x00' * 15, "LSB=1 triggers reduction"),
        (b'\xff' * 16, "all-ones"),
        (b'\x00' * 15 + b'\x80', "MSB only"),
    ]

    for val, desc in test_cases:
        write_bytes(transport, labels["polyval_acc"], val)
        jsr(transport, labels["polyval_right_shift_1"], timeout=5.0)
        c64_result = c64_read_acc(transport, labels)

        py_result = int_to_bytes(py_right_shift_1(bytes_to_int(val)))

        if c64_result != py_result:
            print(f"  FAIL: {desc}")
            print(f"    Input:    {val.hex()}")
            print(f"    Expected: {py_result.hex()}")
            print(f"    Got:      {c64_result.hex()}")
            return False

    print("  PASS: all right-shift cases match")
    return True


def test_precompute_table(transport: ViceTransport, labels: Labels) -> bool:
    """Verify precomputed H table matches Python reference."""
    print("\n--- polyval_precompute_table ---")

    h = bytes.fromhex("25629347589242761d31f826ba4b757b")
    c64_polyval_precompute(transport, labels, h)
    c64_table = c64_read_htable(transport, labels)

    py_table = py_precompute_table(bytes_to_int(h))

    for i in range(16):
        expected = int_to_bytes(py_table[i])
        if c64_table[i] != expected:
            print(f"  FAIL: htable[{i}] mismatch")
            print(f"    Expected: {expected.hex()}")
            print(f"    Got:      {c64_table[i].hex()}")
            return False

    print("  PASS: all 16 table entries match")
    return True


def test_appendix_a(transport: ViceTransport, labels: Labels) -> bool:
    """RFC 8452 Appendix A: POLYVAL(H, X1, X2)."""
    print("\n--- RFC 8452 Appendix A: POLYVAL(H, X1, X2) ---")

    h  = bytes.fromhex("25629347589242761d31f826ba4b757b")
    x1 = bytes.fromhex("4f4f95668c83dfb6401762bb2d01a262")
    x2 = bytes.fromhex("d1a24ddd2721d006bbe45f20d3c9f362")
    expected = bytes.fromhex("f7a3b47b846119fae5b7866cf5e5b77e")

    result = c64_polyval_full(transport, labels, h, [x1, x2])

    if result == expected:
        print(f"  PASS: result = {expected.hex()}")
        return True
    else:
        print(f"  FAIL:")
        print(f"    Expected: {expected.hex()}")
        print(f"    Got:      {result.hex()}")
        return False


def test_single_block(transport: ViceTransport, labels: Labels,
                      h: bytes, block: bytes, label: str) -> bool:
    """Test POLYVAL of a single 16-byte block."""
    print(f"\n--- {label} ---")

    expected = polyval(h, block)
    result = c64_polyval_full(transport, labels, h, [block])

    if result == expected:
        print(f"  PASS: {result.hex()}")
        return True
    else:
        print(f"  FAIL:")
        print(f"    H:        {h.hex()}")
        print(f"    Block:    {block.hex()}")
        print(f"    Expected: {expected.hex()}")
        print(f"    Got:      {result.hex()}")
        return False


def test_multi_block(transport: ViceTransport, labels: Labels,
                     h: bytes, blocks: list[bytes], label: str) -> bool:
    """Test POLYVAL of multiple 16-byte blocks."""
    print(f"\n--- {label} ---")

    expected = polyval(h, *blocks)
    result = c64_polyval_full(transport, labels, h, blocks)

    if result == expected:
        print(f"  PASS: {result.hex()}")
        return True
    else:
        print(f"  FAIL:")
        print(f"    H:        {h.hex()}")
        print(f"    Blocks:   {len(blocks)}")
        print(f"    Expected: {expected.hex()}")
        print(f"    Got:      {result.hex()}")
        return False


def test_zero_h(transport: ViceTransport, labels: Labels) -> bool:
    """POLYVAL with H=0 should always produce zero."""
    print("\n--- Edge case: H = 0 ---")

    h = b'\x00' * 16
    block = random_bytes(16)
    expected = b'\x00' * 16

    result = c64_polyval_full(transport, labels, h, [block])

    if result == expected:
        print("  PASS: H=0 gives zero result")
        return True
    else:
        print(f"  FAIL: got {result.hex()}")
        return False


def test_zero_block(transport: ViceTransport, labels: Labels) -> bool:
    """POLYVAL with zero block should equal dot(0, H) = 0."""
    print("\n--- Edge case: zero block ---")

    h = random_bytes(16)
    block = b'\x00' * 16
    expected = polyval(h, block)

    result = c64_polyval_full(transport, labels, h, [block])

    if result == expected:
        print(f"  PASS: {result.hex()}")
        return True
    else:
        print(f"  FAIL: expected {expected.hex()}, got {result.hex()}")
        return False


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

def run_tests(transport: ViceTransport, labels: Labels,
              iterations: int) -> tuple[int, int]:
    """Run all POLYVAL direct tests. Returns (passed, failed)."""
    passed = 0
    failed = 0

    def record(ok: bool):
        nonlocal passed, failed
        if ok:
            passed += 1
        else:
            failed += 1

    # 1. Init
    record(test_init(transport, labels))

    # 2. Double
    record(test_double(transport, labels))

    # 3. Right shift
    record(test_right_shift(transport, labels))

    # 4. Precompute table
    record(test_precompute_table(transport, labels))

    # 5. RFC 8452 Appendix A
    record(test_appendix_a(transport, labels))

    # 6. Edge cases
    record(test_zero_h(transport, labels))
    record(test_zero_block(transport, labels))

    # 7. Single-block with known simple values
    record(test_single_block(
        transport, labels,
        b'\x01' + b'\x00' * 15,
        b'\x01' + b'\x00' * 15,
        "Single block: H=1, X=1",
    ))

    record(test_single_block(
        transport, labels,
        b'\xff' * 16,
        b'\xff' * 16,
        "Single block: H=all-ones, X=all-ones",
    ))

    # 8. Random tests
    fixed_count = 9
    random_count = max(0, iterations - fixed_count)

    for i in range(random_count):
        h = random_bytes(16)
        num_blocks = random.randint(1, 4)
        blocks = [random_bytes(16) for _ in range(num_blocks)]
        label = f"Random test {i+1}/{random_count}: {num_blocks} block(s)"
        record(test_multi_block(transport, labels, h, blocks, label))

    return passed, failed


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    os.chdir(PROJECT_ROOT)

    # Parse args
    iterations = DEFAULT_ITERATIONS
    if "--iterations" in sys.argv:
        idx = sys.argv.index("--iterations")
        if idx + 1 < len(sys.argv):
            iterations = int(sys.argv[idx + 1])

    seed = random.randint(0, 2**32 - 1)
    if "--seed" in sys.argv:
        idx = sys.argv.index("--seed")
        if idx + 1 < len(sys.argv):
            seed = int(sys.argv[idx + 1])
    random.seed(seed)
    print(f"Random seed: {seed} (reproduce with --seed {seed})")

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
        "polyval_acc", "polyval_h", "polyval_temp", "polyval_htable",
        "polyval_init", "polyval_double", "polyval_right_shift_1",
        "polyval_precompute_table", "polyval_update", "polyval_multiply",
    ]
    for name in required_labels:
        if labels.address(name) is None:
            print(f"FATAL: '{name}' label not found")
            sys.exit(1)
    print(f"  Labels loaded, polyval_acc at ${labels['polyval_acc']:04X}")

    # Start VICE
    print("\n=== Starting VICE ===")
    config = ViceConfig(
        prg_path=PRG_PATH,
        warp=True,
        ntsc=True,
        sound=False,
    )

    with ViceProcess(config) as vice:
        if not vice.wait_for_monitor(timeout=30.0):
            print("FATAL: Could not connect to VICE monitor")
            sys.exit(1)
        print(f"  VICE started (PID {vice.pid})")

        transport = ViceTransport(port=config.port)

        # Wait for main menu
        print("  Waiting for main menu...")
        grid = wait_for_text(transport, "Q=QUIT", timeout=60.0)
        if grid is None:
            print("FATAL: Main menu did not appear")
            dump_screen(transport, "startup")
            sys.exit(1)
        print("  Main menu ready")

        # Run tests
        print(f"\n=== POLYVAL Direct Tests ({iterations} iterations) ===")
        passed, failed = run_tests(transport, labels, iterations)

    # Summary
    total = passed + failed
    print("\n" + "=" * 60)
    print("RESULTS")
    print("=" * 60)
    print(f"  Passed: {passed}/{total}")
    print(f"  Failed: {failed}/{total}")
    if failed == 0:
        print(f"\n  [+] POLYVAL Direct: ALL {total} TESTS PASSED")
    else:
        print(f"\n  [-] POLYVAL Direct: {failed} TEST(S) FAILED")
    print("=" * 60)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
