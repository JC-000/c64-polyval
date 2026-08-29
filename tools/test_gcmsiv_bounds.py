#!/usr/bin/env python3
"""
test_gcmsiv_bounds.py - Memory-safety regression tests for the GCM-SIV layer.

Two findings from the 2026-08 hazmat audit, each pinned as a REGRESSION test
that is RED on the code as audited and turns GREEN once the fix lands:

  regression: issue #69 — gcmsiv_derive_keys / gcmsiv_install_enc_key /
    gcmsiv_restore_orig_key copy 256 bytes (inx/bne) into the 240-byte
    aes_expanded_key, so the 16 bytes that follow it (aes_mc_a0..b3 and
    gcmsiv_nonce[0..7]) are transiently overwritten with a stale snapshot.
    Test: poison those 16 bytes after derive, call install / restore, and
    require the poison to survive.  The 16-byte window is located from the
    build's label file (aes_expanded_key + 240), never hard-coded.

  regression: issue #70 — gcmsiv_encrypt / gcmsiv_decrypt do not validate
    gcmsiv_pt_len against the 64-byte buffers; pt_len=65 reads pt_len itself
    as plaintext and spills ciphertext into gcmsiv_dec_buf, pt_len>=128
    hashes zero data blocks.  Test: pt_len in {65, 128} must return the
    failure convention (A=1, Z clear), decrypt must set tag_valid=0 and wipe
    gcmsiv_dec_buf, and neither routine may touch the surrounding buffers.
    pt_len=64 must keep working.

Usage:
    python3.13 tools/test_gcmsiv_bounds.py [--seed N|random]
                                           [--profile long|short|compact]

Requires: Python 3.10+, c64_test_harness, VICE x64sc
"""

import argparse
import os
import random
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hazmat_oracle as O
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

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PRG_PATH = os.path.join(PROJECT_ROOT, "build", "polyval.prg")
LABELS_PATH = os.path.join(PROJECT_ROOT, "build", "labels.txt")

DEFAULT_SEED = 8452
AES_EXPANDED_KEY_SIZE = 240   # 15 round keys * 16 bytes (src/data.s)
OVERRUN_WINDOW = 16           # bytes the 256-iteration loops write past it

JSR_RETRIES = 3
JSR_RETRY_DELAY = 0.3

REQUIRED_LABELS = [
    "aes_current_key", "aes_expanded_key", "aes_key_expansion",
    "aes_mc_a0", "gcmsiv_nonce", "gcmsiv_derive_keys",
    "gcmsiv_install_enc_key", "gcmsiv_restore_orig_key",
    "gcmsiv_pt_buf", "gcmsiv_pt_len", "gcmsiv_ct_buf", "gcmsiv_dec_buf",
    "gcmsiv_tag", "gcmsiv_tag_valid", "gcmsiv_encrypt", "gcmsiv_decrypt",
]


class BoundsResults:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.errors = []

    def check(self, name, ok, detail=""):
        if ok:
            self.passed += 1
            print(f"    PASS: {name}")
        else:
            self.failed += 1
            self.errors.append(name)
            print(f"    FAIL: {name}" + (f"\n      {detail}" if detail else ""))
        return bool(ok)


def robust_jsr(transport, addr, timeout=60.0):
    for attempt in range(JSR_RETRIES):
        try:
            return jsr(transport, addr, timeout=timeout)
        except Exception:
            if attempt == JSR_RETRIES - 1:
                raise
            time.sleep(JSR_RETRY_DELAY)


def rnd(rng, n):
    return bytes(rng.randrange(256) for _ in range(n))


def expand_master(t, L, key):
    write_bytes(t, L["aes_current_key"], key)
    robust_jsr(t, L["aes_key_expansion"], 10.0)


# ---------------------------------------------------------------------------
# regression: issue #69 — 16-byte copy overrun past aes_expanded_key
# ---------------------------------------------------------------------------

def test_expanded_key_overrun(t, L, R, rng):
    print("\n--- regression: issue #69 — no write past aes_expanded_key[240] ---")
    window = L["aes_expanded_key"] + AES_EXPANDED_KEY_SIZE
    # Sanity on the layout the finding depends on: the window is aes_mc_* then
    # gcmsiv_nonce.  If a future data.s reorders things the test still checks
    # the 16 bytes after aes_expanded_key — whatever they are — stay intact.
    layout_ok = (L["aes_mc_a0"] == window and L["gcmsiv_nonce"] == window + 8)
    print(f"    window ${window:04X}..${window + OVERRUN_WINDOW - 1:04X} "
          f"(aes_mc_a0=${L['aes_mc_a0']:04X}, gcmsiv_nonce=${L['gcmsiv_nonce']:04X}"
          f"{'' if layout_ok else ' — layout differs from audit, still checking window'})")

    key, nonce = rnd(rng, 32), rnd(rng, 12)
    expand_master(t, L, key)
    write_bytes(t, L["gcmsiv_nonce"], nonce)
    robust_jsr(t, L["gcmsiv_derive_keys"], 30.0)

    # (a) install: the snapshot taken at derive time must not be written back.
    poison = rnd(rng, OVERRUN_WINDOW)
    write_bytes(t, window, poison)
    robust_jsr(t, L["gcmsiv_install_enc_key"], 10.0)
    after = read_bytes(t, window, OVERRUN_WINDOW)
    R.check("gcmsiv_install_enc_key leaves aes_expanded_key+240..255 untouched",
            after == poison, f"expected {poison.hex()} got {after.hex()}")

    # (b) restore: the saved_exp snapshot (taken by install) must not be written back.
    poison2 = rnd(rng, OVERRUN_WINDOW)
    write_bytes(t, window, poison2)
    robust_jsr(t, L["gcmsiv_restore_orig_key"], 10.0)
    after = read_bytes(t, window, OVERRUN_WINDOW)
    R.check("gcmsiv_restore_orig_key leaves aes_expanded_key+240..255 untouched",
            after == poison2, f"expected {poison2.hex()} got {after.hex()}")

    # (c) the master schedule itself must have come back intact (the fix must
    # not shorten the copy so far that round keys are lost).
    expand_master(t, L, key)
    expected_sched = read_bytes(t, L["aes_expanded_key"], AES_EXPANDED_KEY_SIZE)
    write_bytes(t, L["gcmsiv_nonce"], nonce)
    robust_jsr(t, L["gcmsiv_derive_keys"], 30.0)
    robust_jsr(t, L["gcmsiv_install_enc_key"], 10.0)
    robust_jsr(t, L["gcmsiv_restore_orig_key"], 10.0)
    R.check("install + restore round-trips all 240 bytes of the master schedule",
            read_bytes(t, L["aes_expanded_key"], AES_EXPANDED_KEY_SIZE) == expected_sched)


# ---------------------------------------------------------------------------
# regression: issue #70 — pt_len > 64 must be rejected, not processed
# ---------------------------------------------------------------------------

def _snapshot(t, L):
    return {
        "pt_buf": read_bytes(t, L["gcmsiv_pt_buf"], 64),
        "pt_len": read_bytes(t, L["gcmsiv_pt_len"], 1),
        "ct_buf": read_bytes(t, L["gcmsiv_ct_buf"], 64),
        "dec_buf": read_bytes(t, L["gcmsiv_dec_buf"], 64),
        "tag": read_bytes(t, L["gcmsiv_tag"], 16),
    }


def _changed(before, after, keys):
    return [k for k in keys if before[k] != after[k]]


def test_pt_len_bounds(t, L, R, rng):
    print("\n--- regression: issue #70 — pt_len > 64 rejected with A=1 ---")
    key, nonce = rnd(rng, 32), rnd(rng, 12)

    # Control: 64 bytes (the documented maximum) still works end to end.
    pt = rnd(rng, 64)
    expand_master(t, L, key)
    write_bytes(t, L["gcmsiv_nonce"], nonce)
    write_bytes(t, L["gcmsiv_pt_buf"], pt)
    write_bytes(t, L["gcmsiv_pt_len"], bytes([64]))
    regs = robust_jsr(t, L["gcmsiv_encrypt"], 120.0)
    ct = read_bytes(t, L["gcmsiv_ct_buf"], 64)
    tag = read_bytes(t, L["gcmsiv_tag"], 16)
    R.check("control: pt_len=64 encrypt matches oracle",
            (ct, tag) == O.gcmsiv_encrypt(key, nonce, pt), f"A={regs.get('A')}")
    write_bytes(t, L["gcmsiv_dec_buf"], b"\xa5" * 64)
    regs = robust_jsr(t, L["gcmsiv_decrypt"], 120.0)
    R.check("control: pt_len=64 decrypt valid (A=0)",
            regs.get("A") == 0 and read_bytes(t, L["gcmsiv_tag_valid"], 1) == b"\x01"
            and read_bytes(t, L["gcmsiv_dec_buf"], 64) == pt)

    for n in (65, 128):
        # --- encrypt: must reject and write nothing ---
        expand_master(t, L, key)
        write_bytes(t, L["gcmsiv_nonce"], nonce)
        write_bytes(t, L["gcmsiv_pt_buf"], rnd(rng, 64))
        write_bytes(t, L["gcmsiv_pt_len"], bytes([n]))
        write_bytes(t, L["gcmsiv_ct_buf"], b"\x5a" * 64)
        write_bytes(t, L["gcmsiv_dec_buf"], b"\xa5" * 64)
        write_bytes(t, L["gcmsiv_tag"], b"\xc3" * 16)
        before = _snapshot(t, L)
        regs = robust_jsr(t, L["gcmsiv_encrypt"], 120.0)
        after = _snapshot(t, L)
        changed = _changed(before, after, ["pt_buf", "pt_len", "ct_buf", "dec_buf", "tag"])
        R.check(f"gcmsiv_encrypt pt_len={n} returns A=1 (Z clear)",
                regs.get("A") == 1, f"A={regs.get('A')}")
        R.check(f"gcmsiv_encrypt pt_len={n} writes nothing (pt_buf/pt_len/ct_buf/dec_buf/tag)",
                not changed, f"changed: {changed}")

        # --- decrypt: must reject, wipe dec_buf, and not touch its inputs ---
        expand_master(t, L, key)
        write_bytes(t, L["gcmsiv_nonce"], nonce)
        write_bytes(t, L["gcmsiv_ct_buf"], rnd(rng, 64))
        write_bytes(t, L["gcmsiv_pt_len"], bytes([n]))
        write_bytes(t, L["gcmsiv_tag"], rnd(rng, 16))
        write_bytes(t, L["gcmsiv_dec_buf"], b"\xa5" * 64)
        before = _snapshot(t, L)
        regs = robust_jsr(t, L["gcmsiv_decrypt"], 120.0)
        after = _snapshot(t, L)
        valid = read_bytes(t, L["gcmsiv_tag_valid"], 1)[0]
        changed = _changed(before, after, ["pt_len", "ct_buf", "tag"])
        R.check(f"gcmsiv_decrypt pt_len={n} returns A=1 (Z clear), tag_valid=0",
                regs.get("A") == 1 and valid == 0, f"A={regs.get('A')} tag_valid={valid}")
        R.check(f"gcmsiv_decrypt pt_len={n} wipes gcmsiv_dec_buf",
                after["dec_buf"] == b"\x00" * 64, f"dec_buf={after['dec_buf'].hex()[:32]}..")
        R.check(f"gcmsiv_decrypt pt_len={n} leaves pt_len/ct_buf/tag untouched",
                not changed, f"changed: {changed}")


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

def run_tests(transport, labels, seed=DEFAULT_SEED):
    """Returns (passed, failed, errors)."""
    rng = random.Random(seed)
    R = BoundsResults()
    for name, fn in [("issue #69 overrun", test_expanded_key_overrun),
                     ("issue #70 pt_len bounds", test_pt_len_bounds)]:
        try:
            fn(transport, labels, R, rng)
        except Exception as e:
            R.check(f"{name}: EXCEPTION", False, f"{type(e).__name__}: {e}")
    return R.passed, R.failed, R.errors


def parse_seed(raw):
    if raw == "random":
        return random.SystemRandom().randint(0, 2 ** 32 - 1)
    return int(raw)


def main():
    ap = argparse.ArgumentParser(description="GCM-SIV memory-safety regression tests (#69, #70)")
    ap.add_argument("--seed", default=str(DEFAULT_SEED), help="integer seed or 'random'")
    ap.add_argument("--profile", choices=["long", "short", "compact"],
                    default=os.environ.get("POLYVAL_PROFILE", "long"))
    args = ap.parse_args()
    seed = parse_seed(args.seed)

    os.chdir(PROJECT_ROOT)
    print("GCM-SIV bounds regression tests (issues #69, #70)")
    print(f"Seed: {seed} (reproduce with --seed {seed}); profile: {args.profile}")
    print("\n=== Building ===")
    result = subprocess.run(["make", f"POLYVAL_PROFILE={args.profile}"],
                            capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Build failed:\n{result.stderr}")
        sys.exit(1)
    print("  Build OK")

    labels = Labels.from_file(LABELS_PATH)
    for name in REQUIRED_LABELS:
        if labels.address(name) is None:
            print(f"FATAL: '{name}' label not found in {LABELS_PATH}")
            sys.exit(1)

    config = ViceConfig(prg_path=PRG_PATH, warp=True, ntsc=True, sound=False)
    t0 = time.time()
    with ViceInstanceManager(config=config) as mgr:
        inst = mgr.acquire()
        print(f"  VICE started (PID {inst.pid}, port {inst.port})")
        if wait_for_text(inst.transport, "Q=QUIT", timeout=60.0, verbose=False) is None:
            print("FATAL: Main menu did not appear")
            dump_screen(inst.transport, "startup")
            sys.exit(1)
        passed, failed, errors = run_tests(inst.transport, labels, seed)
        mgr.release(inst)

    total = passed + failed
    print("\n" + "=" * 60)
    print(f"RESULTS — {time.time() - t0:.1f}s")
    print("=" * 60)
    print(f"  Passed:  {passed}/{total}")
    print(f"  Failed:  {failed}/{total}")
    if failed == 0:
        print(f"\n  [+] GCM-SIV bounds: {passed} passed, 0 failed")
    else:
        print(f"\n  [-] GCM-SIV bounds: {failed} TEST(S) FAILED ({passed} passed)")
        for e in errors:
            print(f"    - {e}")
    print("=" * 60)
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
