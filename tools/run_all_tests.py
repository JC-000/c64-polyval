#!/usr/bin/env python3
"""
run_all_tests.py - Parallel, per-profile test runner

For every requested POLYVAL profile (default: all three), builds
`make POLYVAL_PROFILE=<p>` and runs the four suites on three VICE instances:

  instance 1: test_polyval_direct.py  (POLYVAL unit tests, ZP-wrapped jsr)
              + test_gcmsiv_bounds.py (regression: issues #69, #70)
  instance 2: test_gcmsiv_polyval.py  (RFC 8452 vectors, negative tests,
                                       direct API, round-trips)
  instance 3: test_hazmat_fuzz.py     (differential fuzz vs hazmat_oracle.py)

tools/reference_sanity.cross_validate_reference() runs ONCE before the
profile loop, so the Python oracle the suites trust is checked against
cryptography.AESGCMSIV before any 6502 code executes.

No `make clean` between profiles: the parse-time flag stamp (issue #58)
evicts objects assembled under a different POLYVAL_PROFILE.

Usage:
    python3.13 tools/run_all_tests.py [--seed S|random] [--iterations N]
        [--fuzz-iterations N] [--profile long|short|compact|all] [--verbose]

Requires: Python 3.10+, c64_test_harness, VICE x64sc
"""

import argparse
import io
import os
import random
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))

from c64_test_harness import (
    Labels,
    ViceConfig,
    ViceInstanceManager,
    wait_for_text,
    dump_screen,
)

from reference_sanity import cross_validate_reference

# Import test functions from polyval_direct
from test_polyval_direct import (
    TestResults,
    install_zp_wrapper,
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

from test_gcmsiv_polyval import run_tests as gcmsiv_run_tests
from test_gcmsiv_bounds import run_tests as bounds_run_tests
from test_hazmat_fuzz import run_tests as fuzz_run_tests

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PRG_PATH = os.path.join(PROJECT_ROOT, "build", "polyval.prg")
LABELS_PATH = os.path.join(PROJECT_ROOT, "build", "labels.txt")

PROFILES = ["long", "short", "compact"]

DEFAULT_SEED = 8452
DEFAULT_ITERATIONS_POLYVAL = 10
DEFAULT_ITERATIONS_GCMSIV = 15
DEFAULT_ITERATIONS_FUZZ = 3     # extra random cases per fuzz section (A, C);
                                # the fixed adversarial set always runs

SUITES = ["POLYVAL Direct", "GCM-SIV", "GCM-SIV bounds", "Hazmat fuzz"]


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build(profile):
    """make POLYVAL_PROFILE=<profile>; verify PRG + labels exist."""
    print(f"=== Building (POLYVAL_PROFILE={profile}) ===")
    result = subprocess.run(["make", f"POLYVAL_PROFILE={profile}"],
                            capture_output=True, text=True, cwd=PROJECT_ROOT)
    if result.returncode != 0:
        print(f"Build failed:\n{result.stderr}")
        sys.exit(1)
    print("  Build OK")
    for path in (PRG_PATH, LABELS_PATH):
        if not os.path.exists(path):
            print(f"FATAL: {path} not found")
            sys.exit(1)


# ---------------------------------------------------------------------------
# Per-thread stdout capture
# ---------------------------------------------------------------------------

class _ThreadLocalStdout(io.TextIOBase):
    """Routes writes to per-thread StringIO buffers (registered via
    set_buffer()); unregistered threads write to the real stdout."""

    def __init__(self, real_stdout):
        self._real = real_stdout
        self._local = threading.local()

    def set_buffer(self, buf):
        self._local.buf = buf

    def clear_buffer(self):
        self._local.buf = None

    def write(self, s):
        buf = getattr(self._local, "buf", None)
        return buf.write(s) if buf is not None else self._real.write(s)

    def flush(self):
        buf = getattr(self._local, "buf", None)
        (buf if buf is not None else self._real).flush()


# ---------------------------------------------------------------------------
# Workers — each returns a dict {suite_name: (passed, skipped, failed, errors)}
# plus the captured output
# ---------------------------------------------------------------------------

def worker_polyval_and_bounds(transport, labels, seed, iterations, verbose, tls_stdout):
    buf = io.StringIO()
    tls_stdout.set_buffer(buf)
    out = {}

    random.seed(seed)
    test_polyval_direct.VERBOSE = verbose
    # polyval_acc lives in ZP, which BASIC/KERNAL clobber between jsr()
    # calls — every direct group routes through the $C040 staging wrapper.
    install_zp_wrapper(transport)
    print("  ZP staging wrapper installed")

    results = TestResults()
    for group_name, test_fn in [
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
    ]:
        try:
            test_fn(transport, labels, results, iterations=iterations)
        except Exception as e:
            results.fail(f"{group_name}: EXCEPTION", f"    {type(e).__name__}: {e}")
            print("  (continuing with next test group...)")
    out["POLYVAL Direct"] = (results.passed, 0, results.failed, list(results.errors))

    print("\n" + "-" * 60)
    print("GCM-SIV bounds regression tests (issues #69, #70)")
    print("-" * 60)
    try:
        passed, failed, errors = bounds_run_tests(transport, labels, seed)
    except Exception as e:
        passed, failed, errors = 0, 1, [f"EXCEPTION: {type(e).__name__}: {e}"]
        print(errors[0])
    out["GCM-SIV bounds"] = (passed, 0, failed, errors)

    tls_stdout.clear_buffer()
    return out, buf.getvalue()


def worker_gcmsiv(transport, labels, seed, iterations, tls_stdout):
    buf = io.StringIO()
    tls_stdout.set_buffer(buf)
    random.seed(seed)
    try:
        passed, skipped, failed = gcmsiv_run_tests(transport, labels, iterations)
        errors = [] if failed == 0 else [f"{failed} GCM-SIV test(s) failed (see log above)"]
    except Exception as e:
        passed, skipped, failed = 0, 0, 1
        errors = [f"EXCEPTION: {type(e).__name__}: {e}"]
        print(errors[0])
    tls_stdout.clear_buffer()
    return {"GCM-SIV": (passed, skipped, failed, errors)}, buf.getvalue()


def worker_fuzz(transport, labels, seed, iterations, verbose, tls_stdout):
    buf = io.StringIO()
    tls_stdout.set_buffer(buf)
    try:
        passed, skipped, failed, errors = fuzz_run_tests(
            transport, labels, iterations, seed, verbose)
    except Exception as e:
        passed, skipped, failed = 0, 0, 1
        errors = [f"EXCEPTION: {type(e).__name__}: {e}"]
        print(errors[0])
    tls_stdout.clear_buffer()
    return {"Hazmat fuzz": (passed, skipped, failed, errors)}, buf.getvalue()


# ---------------------------------------------------------------------------
# One profile
# ---------------------------------------------------------------------------

def run_profile(profile, args, seed):
    """Build + run every suite for one profile. Returns {suite: (p, s, f, errors)}."""
    build(profile)
    labels = Labels.from_file(LABELS_PATH)
    print(f"  Labels loaded from {LABELS_PATH}")

    print("\n=== Launching VICE instances ===")
    config = ViceConfig(prg_path=PRG_PATH, warp=True, ntsc=True, sound=False)
    t0 = time.time()
    outputs = []
    results = {}

    with ViceInstanceManager(config) as mgr:
        insts = [mgr.acquire() for _ in range(3)]
        for i, inst in enumerate(insts, 1):
            print(f"  Instance {i}: PID {inst.pid}, port {inst.port}")
        print("  Waiting for main menus...")
        for i, inst in enumerate(insts, 1):
            if wait_for_text(inst.transport, "Q=QUIT", timeout=60.0, verbose=False) is None:
                print(f"FATAL: Instance {i} main menu did not appear")
                dump_screen(inst.transport, f"startup_{profile}_{i}")
                mgr.shutdown()
                sys.exit(1)
        print("  All instances ready")

        print(f"\n=== Running test suites in parallel ({profile}) ===\n")
        tls_stdout = _ThreadLocalStdout(sys.stdout)
        sys.stdout = tls_stdout
        try:
            with ThreadPoolExecutor(max_workers=3) as ex:
                futs = [
                    ex.submit(worker_polyval_and_bounds, insts[0].transport, labels,
                              seed, args.iterations_polyval, args.verbose, tls_stdout),
                    ex.submit(worker_gcmsiv, insts[1].transport, labels,
                              seed, args.iterations_gcmsiv, tls_stdout),
                    ex.submit(worker_fuzz, insts[2].transport, labels,
                              seed, args.fuzz_iterations, args.verbose, tls_stdout),
                ]
                for fut in futs:
                    res, text = fut.result()
                    results.update(res)
                    outputs.append(text)
        finally:
            sys.stdout = tls_stdout._real
        for inst in insts:
            mgr.release(inst)

    elapsed = time.time() - t0
    for title, text in zip(["POLYVAL Direct + GCM-SIV bounds", "GCM-SIV", "Hazmat fuzz"], outputs):
        print("-" * 60)
        print(f"{title} ({profile})")
        print("-" * 60)
        print(text)

    print_summary(f"PROFILE {profile.upper()} — {elapsed:.1f}s wall-clock", results)
    return results, elapsed


def print_summary(title, results):
    print("=" * 60)
    print(title)
    print("=" * 60)
    tp = ts = tf = 0
    for suite in SUITES:
        if suite not in results:
            continue
        p, s, f, _ = results[suite]
        tp, ts, tf = tp + p, ts + s, tf + f
        skip_str = f", {s} skipped" if s else ""
        print(f"  {suite:15s}: {p}/{p + f} passed{skip_str}"
              f"{'  ALL PASSED' if f == 0 else f'  {f} FAILED'}")
    print(f"  {'─' * 44}")
    print(f"  {'Total':15s}: {tp}/{tp + tf} passed, {ts} skipped, {tf} failed")
    if tf:
        for suite in SUITES:
            for e in results.get(suite, (0, 0, 0, []))[3]:
                print(f"    [{suite}] {e}")
    print("=" * 60)
    return tp, ts, tf


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args():
    ap = argparse.ArgumentParser(description="c64-polyval parallel per-profile test runner")
    ap.add_argument("--seed", default=str(DEFAULT_SEED),
                    help="integer seed, or 'random' (default %(default)s)")
    ap.add_argument("--iterations", type=int, default=None,
                    help="random cases per group for the POLYVAL and GCM-SIV suites "
                         f"(defaults {DEFAULT_ITERATIONS_POLYVAL}/{DEFAULT_ITERATIONS_GCMSIV})")
    ap.add_argument("--fuzz-iterations", type=int, default=DEFAULT_ITERATIONS_FUZZ,
                    help="extra random cases per hazmat-fuzz section (default %(default)s)")
    ap.add_argument("--profile", choices=PROFILES + ["all"], default="all",
                    help="POLYVAL_PROFILE to build and test (default: all)")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()
    args.iterations_polyval = args.iterations if args.iterations is not None else DEFAULT_ITERATIONS_POLYVAL
    args.iterations_gcmsiv = args.iterations if args.iterations is not None else DEFAULT_ITERATIONS_GCMSIV
    return args


def main():
    os.chdir(PROJECT_ROOT)
    args = parse_args()
    if args.seed == "random":
        seed = random.SystemRandom().randint(0, 2 ** 32 - 1)
    else:
        seed = int(args.seed)
    profiles = PROFILES if args.profile == "all" else [args.profile]

    print("=" * 60)
    print("Parallel Test Runner — POLYVAL + GCM-SIV + bounds + hazmat fuzz")
    print("=" * 60)
    print(f"Seed: {seed} (reproduce with --seed {seed})")
    print(f"Iterations: polyval={args.iterations_polyval}, gcmsiv={args.iterations_gcmsiv}, "
          f"fuzz={args.fuzz_iterations}")
    print(f"Profiles: {', '.join(profiles)}")
    print(f"Verbose: {args.verbose}")

    # T-3: check the Python oracle against cryptography.AESGCMSIV once,
    # before any 6502 code runs (aborts on drift).
    cross_validate_reference()

    per_profile = {}
    total_elapsed = 0.0
    for profile in profiles:
        print("\n" + "#" * 60)
        print(f"# PROFILE: {profile}")
        print("#" * 60)
        per_profile[profile], el = run_profile(profile, args, seed)
        total_elapsed += el

    # Final combined table
    print("\n" + "=" * 60)
    print(f"COMBINED RESULTS — {total_elapsed:.1f}s VICE wall-clock, seed {seed}")
    print("=" * 60)
    print(f"  {'profile':8s} {'passed':>7s} {'skipped':>8s} {'failed':>7s}  status")
    grand_f = 0
    for profile in profiles:
        r = per_profile[profile]
        p = sum(v[0] for v in r.values())
        s = sum(v[1] for v in r.values())
        f = sum(v[2] for v in r.values())
        grand_f += f
        print(f"  {profile:8s} {p:7d} {s:8d} {f:7d}  {'OK' if f == 0 else 'FAILED'}")
    if grand_f:
        print("\n  FAILING TESTS:")
        for profile in profiles:
            for suite in SUITES:
                for e in per_profile[profile].get(suite, (0, 0, 0, []))[3]:
                    print(f"    [{profile}/{suite}] {e}")
    else:
        print("\n  ALL TESTS PASSED ON ALL PROFILES")
    print("=" * 60)
    sys.exit(0 if grand_f == 0 else 1)


if __name__ == "__main__":
    main()
