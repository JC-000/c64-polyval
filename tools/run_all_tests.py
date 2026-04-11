#!/usr/bin/env python3
"""
run_all_tests.py - Parallel Test Runner

Runs both POLYVAL direct tests and GCM-SIV end-to-end tests simultaneously
on separate VICE instances, cutting wall-clock time nearly in half.

Usage:
    python3 tools/run_all_tests.py [--seed S] [--iterations N] [--verbose]

Requires: Python 3.10+, c64_test_harness, VICE x64sc
"""

import io
import os
import random
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))

from c64_test_harness import (
    Labels,
    ViceConfig,
    ViceInstanceManager,
    wait_for_text,
    dump_screen,
)

# Import test functions from polyval_direct
from test_polyval_direct import (
    TestResults,
    test_init,
    test_double,
    test_right_shift,
    test_shift_left_4,
    test_precompute_table,
    test_xor_table_entry,
    test_multiply_isolated,
    test_update,
    test_full_pipeline,
    test_multiply_vs_dot,
)
import test_polyval_direct

# Import GCM-SIV test runner
from test_gcmsiv_polyval import run_tests as gcmsiv_run_tests

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PRG_PATH = os.path.join(PROJECT_ROOT, "build", "polyval.prg")
LABELS_PATH = os.path.join(PROJECT_ROOT, "build", "labels.txt")

DEFAULT_SEED = 8452
DEFAULT_ITERATIONS_POLYVAL = 10
DEFAULT_ITERATIONS_GCMSIV = 15


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build():
    """Run make clean && make, verify PRG + labels exist."""
    print("=== Building ===")
    subprocess.run(["make", "clean"], capture_output=True, cwd=PROJECT_ROOT)
    result = subprocess.run(["make"], capture_output=True, text=True,
                            cwd=PROJECT_ROOT)
    if result.returncode != 0:
        print(f"Build failed:\n{result.stderr}")
        sys.exit(1)
    print("  Build OK")

    if not os.path.exists(PRG_PATH):
        print(f"FATAL: {PRG_PATH} not found")
        sys.exit(1)
    if not os.path.exists(LABELS_PATH):
        print(f"FATAL: {LABELS_PATH} not found")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Workers
# ---------------------------------------------------------------------------

class _ThreadLocalStdout(io.TextIOBase):
    """A stdout wrapper that routes writes to per-thread StringIO buffers.

    Threads that have registered a buffer via set_buffer() get their output
    captured; all other threads write to the original stdout.
    """

    def __init__(self, real_stdout):
        self._real = real_stdout
        self._local = threading.local()

    def set_buffer(self, buf: io.StringIO):
        self._local.buf = buf

    def clear_buffer(self):
        self._local.buf = None

    def write(self, s):
        buf = getattr(self._local, "buf", None)
        if buf is not None:
            return buf.write(s)
        return self._real.write(s)

    def flush(self):
        buf = getattr(self._local, "buf", None)
        if buf is not None:
            buf.flush()
        else:
            self._real.flush()


def worker_polyval(transport, labels, seed, iterations, verbose, tls_stdout):
    """Run all POLYVAL direct test groups. Returns (passed, failed, output)."""
    buf = io.StringIO()
    tls_stdout.set_buffer(buf)

    # Seed this thread's RNG independently
    random.seed(seed)

    # Set the VERBOSE flag for this run
    test_polyval_direct.VERBOSE = verbose

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

    tls_stdout.clear_buffer()
    return results.passed, results.failed, results.errors, buf.getvalue()


def worker_gcmsiv(transport, labels, seed, iterations, tls_stdout):
    """Run GCM-SIV end-to-end tests. Returns (passed, failed, output)."""
    buf = io.StringIO()
    tls_stdout.set_buffer(buf)

    # Seed this thread's RNG independently
    random.seed(seed)

    try:
        passed, skipped, failed = gcmsiv_run_tests(transport, labels, iterations)
        errors = [] if failed == 0 else [f"{failed} GCM-SIV test(s) failed"]
    except Exception as e:
        passed, skipped, failed = 0, 0, 1
        errors = [f"EXCEPTION: {type(e).__name__}: {e}"]
        print(f"EXCEPTION: {type(e).__name__}: {e}")

    tls_stdout.clear_buffer()
    return passed, skipped, failed, errors, buf.getvalue()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    os.chdir(PROJECT_ROOT)

    # Parse args
    seed = DEFAULT_SEED
    if "--seed" in sys.argv:
        idx = sys.argv.index("--seed")
        if idx + 1 < len(sys.argv):
            seed = int(sys.argv[idx + 1])

    iterations_polyval = DEFAULT_ITERATIONS_POLYVAL
    iterations_gcmsiv = DEFAULT_ITERATIONS_GCMSIV
    if "--iterations" in sys.argv:
        idx = sys.argv.index("--iterations")
        if idx + 1 < len(sys.argv):
            n = int(sys.argv[idx + 1])
            iterations_polyval = n
            iterations_gcmsiv = n

    verbose = "--verbose" in sys.argv or "-v" in sys.argv

    print("=" * 60)
    print("Parallel Test Runner — POLYVAL + GCM-SIV")
    print("=" * 60)
    print(f"Seed: {seed}")
    print(f"Iterations: polyval={iterations_polyval}, gcmsiv={iterations_gcmsiv}")
    print(f"Verbose: {verbose}")

    # Build once
    build()

    # Load labels once (shared, read-only)
    labels = Labels.from_file(LABELS_PATH)
    print(f"  Labels loaded from {LABELS_PATH}")

    # Launch 2 VICE instances
    print("\n=== Launching VICE instances ===")
    config = ViceConfig(
        prg_path=PRG_PATH,
        warp=True,
        ntsc=True,
        sound=False,
    )

    t0 = time.time()

    with ViceInstanceManager(config) as mgr:
        inst1 = mgr.acquire()
        inst2 = mgr.acquire()
        print(f"  Instance 1: port {inst1.port}")
        print(f"  Instance 2: port {inst2.port}")

        # Wait for both to reach main menu
        print("  Waiting for main menus...")
        for i, inst in enumerate([inst1, inst2], 1):
            grid = wait_for_text(inst.transport, "Q=QUIT", timeout=60.0,
                                 verbose=False)
            if grid is None:
                print(f"FATAL: Instance {i} main menu did not appear")
                dump_screen(inst.transport, f"startup_{i}")
                mgr.shutdown()
                sys.exit(1)
        print("  Both instances ready")

        # Run suites in parallel
        print("\n=== Running test suites in parallel ===\n")

        # Install thread-local stdout to capture per-worker output
        tls_stdout = _ThreadLocalStdout(sys.stdout)
        sys.stdout = tls_stdout

        with ThreadPoolExecutor(max_workers=2) as executor:
            fut_polyval = executor.submit(
                worker_polyval, inst1.transport, labels,
                seed, iterations_polyval, verbose, tls_stdout,
            )
            fut_gcmsiv = executor.submit(
                worker_gcmsiv, inst2.transport, labels,
                seed, iterations_gcmsiv, tls_stdout,
            )

            # Wait for both
            polyval_result = fut_polyval.result()
            gcmsiv_result = fut_gcmsiv.result()

        # Restore real stdout
        sys.stdout = tls_stdout._real

        # Release instances
        mgr.release(inst1)
        mgr.release(inst2)

    elapsed = time.time() - t0

    # Unpack results
    pv_passed, pv_failed, pv_errors, pv_output = polyval_result
    gc_passed, gc_skipped, gc_failed, gc_errors, gc_output = gcmsiv_result

    # Print captured output sequentially
    print("-" * 60)
    print("POLYVAL Direct Tests")
    print("-" * 60)
    print(pv_output)

    print("-" * 60)
    print("GCM-SIV Tests")
    print("-" * 60)
    print(gc_output)

    # Aggregated summary
    total_passed = pv_passed + gc_passed
    total_failed = pv_failed + gc_failed
    total = total_passed + total_failed

    print("=" * 60)
    print(f"COMBINED RESULTS — {elapsed:.1f}s wall-clock")
    print("=" * 60)
    print(f"  POLYVAL Direct : {pv_passed}/{pv_passed + pv_failed} passed"
          f"{'  ALL PASSED' if pv_failed == 0 else ''}")
    gc_total = gc_passed + gc_skipped + gc_failed
    skip_str = f", {gc_skipped} skipped" if gc_skipped else ""
    print(f"  GCM-SIV        : {gc_passed}/{gc_total} passed{skip_str}"
          f"{'  ALL PASSED' if gc_failed == 0 else ''}")
    print(f"  {'─' * 40}")
    print(f"  Total          : {total_passed}/{total} passed")

    if total_failed == 0:
        print(f"\n  ALL {total} TESTS PASSED")
    else:
        print(f"\n  {total_failed} TEST(S) FAILED:")
        for e in pv_errors:
            print(f"    [POLYVAL] {e}")
        for e in gc_errors:
            print(f"    [GCM-SIV] {e}")
    print("=" * 60)

    sys.exit(0 if total_failed == 0 else 1)


if __name__ == "__main__":
    main()
