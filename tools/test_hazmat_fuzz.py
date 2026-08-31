#!/usr/bin/env python3
"""
test_hazmat_fuzz.py - Adversarial differential test of the 6502 POLYVAL /
AES-256-GCM-SIV code against tools/hazmat_oracle.py.

hazmat_oracle.py is an independent, self-verifying oracle written from the
RFC 8452 text (schoolbook carry-less multiply + explicit reduction, pure-
Python AES-256) — NOT derived from tools/polyval_reference.py — so a
misconception shared by the 6502 code and the project's reference cannot
cancel out.  When the `cryptography` package is importable and supports
AESGCMSIV, every GCM-SIV encrypt is additionally cross-checked against
hazmat; when it is not, those checks are counted and printed as SKIPPED
and the pure-Python oracle still gates everything else.

Sections (mirrors the 2026-08 hazmat audit driver):

  A. POLYVAL pipeline with adversarial H (0, 1, top-bit, all-FF, RFC, random)
     x message shapes (1/2/4/8/17/64 blocks, all-FF, repeated block, top-bit),
     htable[0..15] vs (H*x^-128)*i, polyval_h preservation, Appendix A
  B. polyval_multiply with edge operands (acc in {0, 1, top-bit, FF, random})
  C. gcmsiv_encrypt/gcmsiv_decrypt vs oracle for key/nonce in {0, FF, random}
     x len in {0,1,15,16,17,31,32,33,47,48,49,63,64} (+ hazmat cross-check),
     plus `--iterations` extra random (key, nonce, len) triples
  D. gcmsiv_derive_keys vs RFC 8452 s4 and master key-schedule restoration
  E. gcmsiv_ctr_encrypt across the 32-bit LE counter wrap and tag-MSB cases
  F. Exhaustive forgery on one 17-byte message: every tag bit, every
     ciphertext bit, every nonce bit, length tamper; asserts the A/Z return
     convention and the dec_buf wipe

Usage:
    python3.13 tools/test_hazmat_fuzz.py [--seed N|random] [--iterations N]
                                         [--profile long|short|compact]

Requires: Python 3.10+, c64_test_harness, VICE x64sc.  `cryptography` optional.
"""

import argparse
import os
import random
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hazmat_oracle as O
from test_polyval_direct import install_zp_wrapper, zp_jsr, ZP_STAGING_ADDR
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

DEFAULT_SEED = 8452
DEFAULT_ITERATIONS = 10   # extra random cases in sections A and C
SKIP = "SKIP"

JSR_RETRIES = 3
JSR_RETRY_DELAY = 0.3

REQUIRED_LABELS = [
    "polyval_h", "polyval_temp", "polyval_htable", "polyval_init",
    "polyval_precompute_table", "polyval_update", "polyval_multiply",
    "aes_current_key", "aes_expanded_key", "aes_key_expansion",
    "gcmsiv_nonce", "gcmsiv_pt_buf", "gcmsiv_pt_len", "gcmsiv_ct_buf",
    "gcmsiv_dec_buf", "gcmsiv_tag", "gcmsiv_tag_valid", "gcmsiv_encrypt",
    "gcmsiv_decrypt", "gcmsiv_derive_keys", "gcmsiv_auth_key",
    "gcmsiv_enc_key", "gcmsiv_ctr_encrypt",
]


# ---------------------------------------------------------------------------
# Result bookkeeping
# ---------------------------------------------------------------------------

class FuzzResults:
    def __init__(self, verbose=False):
        self.passed = 0
        self.skipped = 0
        self.failed = 0
        self.errors = []
        self.verbose = verbose

    def check(self, section, name, ok, detail=""):
        if ok == SKIP:
            self.skipped += 1
            print(f"  SKIP [{section}] {name}{(' - ' + detail) if detail else ''}")
            return SKIP
        if ok:
            self.passed += 1
            if self.verbose:
                print(f"  PASS [{section}] {name}")
        else:
            self.failed += 1
            self.errors.append(f"[{section}] {name}")
            print(f"  FAIL [{section}] {name} {detail}")
        return bool(ok)


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

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


# POLYVAL plumbing (through the ZP staging wrapper from test_polyval_direct)

def pv_precompute(t, L, h):
    write_bytes(t, L["polyval_h"], h)
    zp_jsr(t, L["polyval_precompute_table"], timeout=60.0)


def pv_hash(t, L, h, msg):
    pv_precompute(t, L, h)
    zp_jsr(t, L["polyval_init"], timeout=5.0)
    for i in range(0, len(msg), 16):
        write_bytes(t, L["polyval_temp"], msg[i:i + 16])
        zp_jsr(t, L["polyval_update"], timeout=30.0)
    return read_bytes(t, ZP_STAGING_ADDR, 16)


def pv_multiply(t, L, acc):
    write_bytes(t, ZP_STAGING_ADDR, acc)
    zp_jsr(t, L["polyval_multiply"], timeout=30.0)
    return read_bytes(t, ZP_STAGING_ADDR, 16)


# GCM-SIV plumbing (own implementation so side effects can be inspected)

def expand_master(t, L, key):
    write_bytes(t, L["aes_current_key"], key)
    robust_jsr(t, L["aes_key_expansion"], 10.0)


def c64_encrypt(t, L, key, nonce, pt):
    expand_master(t, L, key)
    write_bytes(t, L["gcmsiv_nonce"], nonce)
    if pt:
        write_bytes(t, L["gcmsiv_pt_buf"], pt)
    write_bytes(t, L["gcmsiv_pt_len"], bytes([len(pt)]))
    regs = robust_jsr(t, L["gcmsiv_encrypt"], 120.0)
    ct = read_bytes(t, L["gcmsiv_ct_buf"], len(pt)) if pt else b""
    tag = read_bytes(t, L["gcmsiv_tag"], 16)
    return ct, tag, regs


def c64_decrypt(t, L, key, nonce, ct, tag, pt_len=None):
    """Returns (dec_buf[0..63], tag_valid, regs, tag_after).

    dec_buf is poisoned with 0xA5 before the call so that the wipe-on-
    failure is observable rather than vacuous.
    """
    pt_len = len(ct) if pt_len is None else pt_len
    expand_master(t, L, key)
    write_bytes(t, L["gcmsiv_nonce"], nonce)
    if ct:
        write_bytes(t, L["gcmsiv_ct_buf"], ct)
    write_bytes(t, L["gcmsiv_pt_len"], bytes([pt_len]))
    write_bytes(t, L["gcmsiv_tag"], tag)
    write_bytes(t, L["gcmsiv_dec_buf"], b"\xa5" * 64)
    regs = robust_jsr(t, L["gcmsiv_decrypt"], 120.0)
    pt = read_bytes(t, L["gcmsiv_dec_buf"], 64)
    valid = read_bytes(t, L["gcmsiv_tag_valid"], 1)[0]
    tag_after = read_bytes(t, L["gcmsiv_tag"], 16)
    return pt, valid, regs, tag_after


def _rejected(dpt, valid, regs):
    """Failure convention: tag_valid=0, A=1 (Z clear), dec_buf wiped."""
    return valid == 0 and regs.get("A") == 1 and dpt == b"\x00" * 64


# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

RFC_H = bytes.fromhex("25629347589242761d31f826ba4b757b")
TOP = b"\x00" * 15 + b"\x80"
ONE = b"\x01" + b"\x00" * 15
Z16 = b"\x00" * 16
FF16 = b"\xff" * 16


def section_a(t, L, R, rng, iterations):
    print("\n[A] POLYVAL pipeline vs oracle")
    hs = [("H=0", Z16), ("H=1", ONE), ("H=top-bit", TOP), ("H=FF", FF16),
          ("H=RFC", RFC_H), ("H=rand", rnd(rng, 16))]
    msgs = [("1 block rand", rnd(rng, 16)), ("1 block FF", FF16), ("1 block top", TOP),
            ("2 blocks", rnd(rng, 32)), ("8x repeated block", rnd(rng, 16) * 8),
            ("4 blocks FF", FF16 * 4), ("17 blocks (272 B)", rnd(rng, 272)),
            ("64 blocks (1 KiB)", rnd(rng, 1024))]
    for hn, h in hs:
        for mn, m in msgs:
            got = pv_hash(t, L, h, m)
            exp = O.polyval(h, m)
            R.check("A", f"{hn} / {mn}", got == exp, f"got={got.hex()} exp={exp.hex()}")
    for i in range(iterations):
        h = rnd(rng, 16)
        m = rnd(rng, 16 * rng.randint(1, 8))
        got = pv_hash(t, L, h, m)
        exp = O.polyval(h, m)
        R.check("A", f"random #{i + 1} H / {len(m) // 16} blocks", got == exp,
                f"H={h.hex()} got={got.hex()} exp={exp.hex()}")
    # htable[i] = (H * x^-128) * i, and polyval_h must survive precompute
    for hn, h in hs:
        pv_precompute(t, L, h)
        tbl = read_bytes(t, L["polyval_htable"], 256)
        hp = O.gf_mul(O.le(h), O.X_INV128)
        ok = all(tbl[i * 16:(i + 1) * 16] == O.unle(O.gf_mul(hp, i)) for i in range(16))
        R.check("A", f"htable[0..15] for {hn}", ok)
        h_after = read_bytes(t, L["polyval_h"], 16)
        R.check("A", f"polyval_h preserved across precompute ({hn})", h_after == h,
                f"after={h_after.hex()}")
    x1 = bytes.fromhex("4f4f95668c83dfb6401762bb2d01a262")
    x2 = bytes.fromhex("d1a24ddd2721d006bbe45f20d3c9f362")
    R.check("A", "RFC 8452 Appendix A", pv_hash(t, L, RFC_H, x1 + x2) ==
            bytes.fromhex("f7a3b47b846119fae5b7866cf5e5b77e"))
    return hs


def section_b(t, L, R, rng, hs):
    print("[B] polyval_multiply edge operands")
    for hn, h in hs:
        pv_precompute(t, L, h)
        for an, a in [("acc=0", Z16), ("acc=1", ONE), ("acc=top", TOP),
                      ("acc=FF", FF16), ("acc=rand", rnd(rng, 16))]:
            got = pv_multiply(t, L, a)
            exp = O.unle(O.dot(O.le(a), O.le(h)))
            R.check("B", f"{hn} x {an}", got == exp, f"got={got.hex()} exp={exp.hex()}")


def _enc_dec_case(t, L, R, label, key, nonce, pt):
    ct, tag, _ = c64_encrypt(t, L, key, nonce, pt)
    ect, etag = O.gcmsiv_encrypt(key, nonce, pt)
    R.check("C", f"enc {label}", (ct, tag) == (ect, etag),
            f"ct={ct.hex()} tag={tag.hex()} exp_tag={etag.hex()}")
    if pt:  # hazmat rejects empty PT
        if O.HAZMAT_GCMSIV_AVAILABLE:
            R.check("C", f"hazmat agrees {label}",
                    O.AESGCMSIV(key).encrypt(nonce, pt, None) == ct + tag)
        else:
            R.check("C", f"hazmat agrees {label}", SKIP, O.HAZMAT_SKIP_REASON)
    dpt, valid, regs, tag_after = c64_decrypt(t, L, key, nonce, ct, tag)
    n = len(pt)
    R.check("C", f"dec {label}", dpt[:n] == pt and valid == 1
            and regs.get("A") == 0 and tag_after == tag,
            f"valid={valid} A={regs.get('A')} pt_ok={dpt[:n] == pt}")


def section_c(t, L, R, rng, iterations):
    print("[C] GCM-SIV encrypt/decrypt vs oracle" +
          ("" if O.HAZMAT_GCMSIV_AVAILABLE else f" (hazmat cross-checks SKIPPED: {O.HAZMAT_SKIP_REASON})"))
    keys = [("key=0", b"\x00" * 32), ("key=FF", b"\xff" * 32), ("key=rand", rnd(rng, 32))]
    nonces = [("nonce=0", b"\x00" * 12), ("nonce=FF", b"\xff" * 12), ("nonce=rand", rnd(rng, 12))]
    lengths = [0, 1, 15, 16, 17, 31, 32, 33, 47, 48, 49, 63, 64]
    for kn, key in keys:
        for nn, nonce in nonces:
            for n in lengths:
                pt = rnd(rng, n) if n else b""
                if n and rng.random() < 0.3:
                    pt = b"\xff" * n
                _enc_dec_case(t, L, R, f"{kn} {nn} len={n}", key, nonce, pt)
    for i in range(iterations):
        n = rng.randint(0, 64)
        _enc_dec_case(t, L, R, f"random #{i + 1} len={n}",
                      rnd(rng, 32), rnd(rng, 12), rnd(rng, n))
    return keys, nonces


def section_d(t, L, R, keys, nonces):
    print("[D] gcmsiv_derive_keys vs RFC 8452 s4")
    for kn, key in keys:
        for nn, nonce in nonces:
            expand_master(t, L, key)
            write_bytes(t, L["gcmsiv_nonce"], nonce)
            robust_jsr(t, L["gcmsiv_derive_keys"], 30.0)
            ak = read_bytes(t, L["gcmsiv_auth_key"], 16)
            ek = read_bytes(t, L["gcmsiv_enc_key"], 32)
            R.check("D", f"derive {kn} {nn}", (ak, ek) == O.derive_keys(key, nonce))
            sched = read_bytes(t, L["aes_expanded_key"], 240)
            expand_master(t, L, key)
            R.check("D", f"master schedule restored {kn} {nn}",
                    sched == read_bytes(t, L["aes_expanded_key"], 240))


def section_e(t, L, R, rng):
    print("[E] CTR counter wrap / 0x80 handling (gcmsiv_ctr_encrypt direct)")
    key, nonce = rnd(rng, 32), rnd(rng, 12)
    expand_master(t, L, key)
    write_bytes(t, L["gcmsiv_nonce"], nonce)
    robust_jsr(t, L["gcmsiv_derive_keys"], 30.0)
    _, ek = O.derive_keys(key, nonce)
    pt = rnd(rng, 64)
    tag_cases = [
        ("ctr=FFFFFFFF (wrap all 4 bytes)", b"\xff\xff\xff\xff" + rnd(rng, 11) + b"\x00"),
        ("ctr=FFFFFFFE", b"\xfe\xff\xff\xff" + rnd(rng, 11) + b"\x7f"),
        ("ctr=FFFFFFFD", b"\xfd\xff\xff\xff" + rnd(rng, 11) + b"\xff"),
        ("ctr=000000FF (byte0 wrap)", b"\xff\x00\x00\x00" + rnd(rng, 12)),
        ("ctr=0000FFFF", b"\xff\xff\x00\x00" + rnd(rng, 12)),
        ("ctr=00FFFFFF", b"\xff\xff\xff\x00" + rnd(rng, 12)),
        ("ctr=7FFFFFFF", b"\xff\xff\xff\x7f" + rnd(rng, 12)),
        ("tag[15] MSB clear", rnd(rng, 15) + b"\x00"),
        ("tag[15] MSB set", rnd(rng, 15) + b"\x80"),
        ("tag all zero", b"\x00" * 16),
        ("tag all FF", b"\xff" * 16),
    ]
    for tn, tag in tag_cases:
        write_bytes(t, L["gcmsiv_pt_buf"], pt)
        write_bytes(t, L["gcmsiv_pt_len"], bytes([64]))
        write_bytes(t, L["gcmsiv_tag"], tag)
        robust_jsr(t, L["gcmsiv_ctr_encrypt"], 60.0)
        got = read_bytes(t, L["gcmsiv_ct_buf"], 64)
        R.check("E", tn, got == O.ctr(ek, tag, pt))
        R.check("E", tn + " (tag preserved)", read_bytes(t, L["gcmsiv_tag"], 16) == tag)


def section_f(t, L, R, rng):
    print("[F] exhaustive forgery on one 17-byte message (128 tag + 136 ct + 96 nonce bits)")
    key, nonce = rnd(rng, 32), rnd(rng, 12)
    pt = rnd(rng, 17)
    ct, tag, _ = c64_encrypt(t, L, key, nonce, pt)
    R.check("F", "17-byte baseline matches oracle", (ct, tag) == O.gcmsiv_encrypt(key, nonce, pt))

    bad = []
    for b in range(128):
        bt = bytearray(tag)
        bt[b // 8] ^= 1 << (b % 8)
        dpt, valid, regs, _ = c64_decrypt(t, L, key, nonce, ct, bytes(bt))
        if not _rejected(dpt, valid, regs):
            bad.append(f"tag bit {b}: valid={valid} A={regs.get('A')} wiped={dpt == bytes(64)}")
    R.check("F", "all 128 tag-bit flips rejected (A=1) + dec_buf wiped", not bad, "; ".join(bad[:4]))

    bad = []
    for b in range(17 * 8):
        bc = bytearray(ct)
        bc[b // 8] ^= 1 << (b % 8)
        dpt, valid, regs, _ = c64_decrypt(t, L, key, nonce, bytes(bc), tag)
        if not _rejected(dpt, valid, regs):
            bad.append(f"ct bit {b}: valid={valid} A={regs.get('A')}")
    R.check("F", "all 136 ct-bit flips rejected (A=1) + dec_buf wiped", not bad, "; ".join(bad[:4]))

    bad = []
    for b in range(96):
        bn = bytearray(nonce)
        bn[b // 8] ^= 1 << (b % 8)
        dpt, valid, regs, _ = c64_decrypt(t, L, key, bytes(bn), ct, tag)
        if not _rejected(dpt, valid, regs):
            bad.append(f"nonce bit {b}: valid={valid} A={regs.get('A')}")
    R.check("F", "all 96 nonce-bit flips rejected (A=1) + dec_buf wiped", not bad, "; ".join(bad[:4]))

    for n in (16, 18, 0, 32):
        dpt, valid, regs, _ = c64_decrypt(t, L, key, nonce, ct, tag, pt_len=n)
        R.check("F", f"length tamper 17->{n} rejected", _rejected(dpt, valid, regs),
                f"valid={valid} A={regs.get('A')}")

    # bytes beyond pt_len in ct_buf must not influence a valid decrypt
    write_bytes(t, L["gcmsiv_ct_buf"] + 17, b"\x5a" * 47)
    dpt, valid, regs, _ = c64_decrypt(t, L, key, nonce, ct, tag)
    R.check("F", "bytes beyond pt_len in ct_buf ignored (valid decrypt, A=0)",
            valid == 1 and regs.get("A") == 0 and dpt[:17] == pt)

    ct0, tag0, _ = c64_encrypt(t, L, key, nonce, b"")
    _, v, regs, _ = c64_decrypt(t, L, key, nonce, b"", tag0)
    R.check("F", "empty msg correct tag accepted (A=0)", v == 1 and regs.get("A") == 0)
    bt = bytearray(tag0)
    bt[15] ^= 0x80
    dpt, v, regs, _ = c64_decrypt(t, L, key, nonce, b"", bytes(bt))
    R.check("F", "empty msg tag MSB flip rejected (A=1) + wiped", _rejected(dpt, v, regs))


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

def run_tests(transport, labels, iterations=DEFAULT_ITERATIONS, seed=DEFAULT_SEED,
              verbose=False, install_wrapper=True):
    """Run every section. Returns (passed, skipped, failed, errors)."""
    for line in O.SELFCHECK_LOG:
        print("  oracle:", line)
    for line in O.SELFCHECK_SKIPPED:
        print("  oracle:", line)
    if install_wrapper:
        install_zp_wrapper(transport)
    rng = random.Random(seed)
    R = FuzzResults(verbose=verbose)
    hs = keys = nonces = None
    try:
        hs = section_a(transport, labels, R, rng, iterations)
    except Exception as e:
        R.check("A", "EXCEPTION", False, f"{type(e).__name__}: {e}")
    for name, fn in [
        ("B", lambda: section_b(transport, labels, R, rng, hs or [])),
        ("C", lambda: section_c(transport, labels, R, rng, iterations)),
    ]:
        try:
            out = fn()
            if name == "C":
                keys, nonces = out
        except Exception as e:
            R.check(name, "EXCEPTION", False, f"{type(e).__name__}: {e}")
    for name, fn in [
        ("D", lambda: section_d(transport, labels, R, keys or [], nonces or [])),
        ("E", lambda: section_e(transport, labels, R, rng)),
        ("F", lambda: section_f(transport, labels, R, rng)),
    ]:
        try:
            fn()
        except Exception as e:
            R.check(name, "EXCEPTION", False, f"{type(e).__name__}: {e}")
    return R.passed, R.skipped, R.failed, R.errors


def parse_seed(raw):
    if raw == "random":
        return random.SystemRandom().randint(0, 2 ** 32 - 1)
    return int(raw)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seed", default=str(DEFAULT_SEED),
                    help="integer seed, or 'random' (default %(default)s)")
    ap.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS,
                    help="extra random cases in sections A and C (default %(default)s)")
    ap.add_argument("--profile", choices=["long", "short", "compact"],
                    default=os.environ.get("POLYVAL_PROFILE", "long"),
                    help="POLYVAL_PROFILE to build and test (default: $POLYVAL_PROFILE or long)")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()
    seed = parse_seed(args.seed)

    os.chdir(PROJECT_ROOT)
    print("Hazmat differential fuzz — POLYVAL + AES-256-GCM-SIV")
    print(f"Seed: {seed} (reproduce with --seed {seed})")
    print(f"Iterations: {args.iterations}, profile: {args.profile}")

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
        transport = inst.transport
        if wait_for_text(transport, "Q=QUIT", timeout=60.0, verbose=False) is None:
            print("FATAL: Main menu did not appear")
            dump_screen(transport, "startup")
            sys.exit(1)
        passed, skipped, failed, errors = run_tests(
            transport, labels, args.iterations, seed, args.verbose)
        mgr.release(inst)

    total = passed + skipped + failed
    print("\n" + "=" * 60)
    print(f"RESULTS — {time.time() - t0:.1f}s")
    print("=" * 60)
    print(f"  Passed:  {passed}/{total}")
    print(f"  Skipped: {skipped}/{total}")
    print(f"  Failed:  {failed}/{total}")
    if failed == 0:
        print(f"\n  [+] Hazmat fuzz: {passed} passed, {skipped} skipped, 0 failed")
    else:
        print(f"\n  [-] Hazmat fuzz: {failed} TEST(S) FAILED ({passed} passed, {skipped} skipped)")
        for e in errors:
            print(f"    - {e}")
    print("=" * 60)
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
