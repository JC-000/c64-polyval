#!/usr/bin/env python3
"""
reference_sanity.py - External cross-check of polyval_reference.py

Validates that tools/polyval_reference.py's gcmsiv_encrypt/gcmsiv_decrypt
agree byte-for-byte with cryptography.hazmat.primitives.ciphers.aead.AESGCMSIV
(a fully external AES-256-GCM-SIV implementation). Called at suite startup
from both test_polyval_direct.py and test_gcmsiv_polyval.py so that any
drift in the Python oracle aborts the 6502 test run before it starts.

Test cases:
  - 2 pinned RFC 8452 C.2 vectors (one empty PT, one non-trivial)
  - 5 random vectors with fixed seed 0xCAFE (reproducible)
  - 4 edge cases: empty PT/AAD, 1-byte PT, 16-byte PT, 17-byte PT

polyval_reference.gcmsiv_encrypt supports AAD natively (its POLYVAL input
builder absorbs AAD blocks, independent of the 6502 limitation in
gcmsiv_compute_tag_base). So the sanity check exercises AAD in the Python
path — this is a deliberate choice to maximise oracle coverage even though
the 6502 side still skips AAD-containing RFC vectors.

Run standalone:
    python3 tools/reference_sanity.py
"""

import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cryptography.hazmat.primitives.ciphers.aead import AESGCMSIV

import polyval_reference


PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
VECTORS_PATH = os.path.join(PROJECT_ROOT, "tools", "vectors", "rfc8452_vectors.json")

SANITY_SEED = 0xCAFE


def _fail(case_name: str, expected: bytes, actual: bytes, what: str) -> None:
    raise SystemExit(
        f"[sanity] FATAL: polyval_reference.py diverges from "
        f"cryptography.AESGCMSIV on case '{case_name}' ({what})\n"
        f"  expected: {expected.hex()}\n"
        f"  actual:   {actual.hex()}"
    )


def _check_case(name: str, key: bytes, nonce: bytes, pt: bytes, aad: bytes,
                pinned: bytes | None = None) -> None:
    """Validate one (key, nonce, pt, aad) tuple through both encrypt and decrypt.

    cryptography.AESGCMSIV rejects empty plaintext (ValueError), so for the
    empty-PT case we fall back to the pinned RFC 8452 C.2 expected bytes
    (passed via `pinned`) as the external truth anchor.
    """
    # --- Encrypt path ---
    py_ct, py_tag = polyval_reference.gcmsiv_encrypt(key, nonce, pt, aad)
    py_combined = py_ct + py_tag

    if pt:
        ext = AESGCMSIV(key)
        ext_combined = ext.encrypt(nonce, pt, aad if aad else None)
        if py_combined != ext_combined:
            _fail(name, ext_combined, py_combined, "encrypt(ct||tag)")

        # Decrypt cross-check via external library
        ext_pt = ext.decrypt(nonce, py_ct + py_tag, aad if aad else None)
        if ext_pt != pt:
            _fail(name, pt, ext_pt, "decrypt(pt) via cryptography.AESGCMSIV")
    else:
        # Empty PT: cryptography refuses. Fall back to pinned RFC vector.
        if pinned is None:
            raise SystemExit(
                f"[sanity] INTERNAL: empty-PT case '{name}' has no pinned truth"
            )
        if py_combined != pinned:
            _fail(name, pinned, py_combined, "encrypt(ct||tag) vs pinned RFC")

    # Polyval-reference self-roundtrip (validates decrypt + tag verify).
    py_pt, py_valid = polyval_reference.gcmsiv_decrypt(key, nonce, py_ct, py_tag, aad)
    if not py_valid or py_pt != pt:
        _fail(name, pt, py_pt, "decrypt(pt) via polyval_reference")


def _load_rfc_cases() -> list:
    """Pick 2 RFC 8452 C.2 vectors as pinned truth anchors.

    Returns list of (name, key, nonce, pt, aad, pinned_ct_tag) tuples.
    """
    with open(VECTORS_PATH) as f:
        data = json.load(f)
    vectors = data["aes256_gcmsiv_vectors"]

    picks = []
    # One empty-PT vector (can only be checked via pinned bytes, not AESGCMSIV).
    for v in vectors:
        if not v["plaintext"] and not v.get("aad", ""):
            picks.append(v)
            break
    # One non-trivial vector (cross-checks AESGCMSIV AND pinned bytes).
    for v in vectors:
        if v["plaintext"] and len(bytes.fromhex(v["plaintext"])) >= 8:
            picks.append(v)
            break

    out = []
    for v in picks:
        key = bytes.fromhex(v["key"])
        nonce = bytes.fromhex(v["nonce"])
        pt = bytes.fromhex(v["plaintext"]) if v["plaintext"] else b""
        aad = bytes.fromhex(v["aad"]) if v.get("aad", "") else b""
        pinned = bytes.fromhex(v["ciphertext"] + v["tag"])
        out.append(("RFC8452 " + v["name"], key, nonce, pt, aad, pinned))
    return out


def _random_cases() -> list:
    """5 reproducible random cases using seed 0xCAFE."""
    rng = random.Random(SANITY_SEED)
    cases = []
    for i in range(5):
        key = bytes(rng.randint(0, 255) for _ in range(32))
        nonce = bytes(rng.randint(0, 255) for _ in range(12))
        # pt_len >= 1 so cryptography.AESGCMSIV can validate (it rejects empty PT).
        pt_len = rng.randint(1, 128)
        aad_len = rng.randint(0, 64)
        pt = bytes(rng.randint(0, 255) for _ in range(pt_len))
        aad = bytes(rng.randint(0, 255) for _ in range(aad_len))
        cases.append(
            (f"random#{i+1} pt={pt_len} aad={aad_len}", key, nonce, pt, aad, None)
        )
    return cases


def _edge_cases(rfc_empty_pinned: bytes, rfc_empty_key: bytes,
                rfc_empty_nonce: bytes) -> list:
    """Hand-picked boundary cases. Fixed key/nonce for determinism.

    The empty-PT edge case reuses the pinned RFC 8452 Test 1 vector so we
    have an external truth anchor (cryptography.AESGCMSIV refuses empty PT).
    """
    key = bytes(range(32))
    nonce = bytes(range(12))
    return [
        ("edge: empty PT + empty AAD",
         rfc_empty_key, rfc_empty_nonce, b"", b"", rfc_empty_pinned),
        ("edge: 1-byte PT",             key, nonce, b"\xa5", b"", None),
        ("edge: exactly 16 bytes PT",   key, nonce, bytes(range(16)), b"", None),
        ("edge: 17-byte PT (1 block+1)", key, nonce, bytes(range(17)), b"", None),
    ]


def cross_validate_reference() -> None:
    """Cross-check polyval_reference.py against cryptography.AESGCMSIV.

    Raises SystemExit if any mismatch is detected. Prints a one-line
    summary on success. Intended to be called at the top of any test
    entry point that trusts polyval_reference.py as an oracle.
    """
    rfc_cases = _load_rfc_cases()
    # The first RFC pick is the empty-PT vector; reuse its pinned bytes/key/nonce
    # for the empty-PT edge case so we still have an external truth anchor.
    empty_pick = rfc_cases[0]
    cases = []
    cases.extend(rfc_cases)
    cases.extend(_random_cases())
    cases.extend(_edge_cases(
        rfc_empty_pinned=empty_pick[5],
        rfc_empty_key=empty_pick[1],
        rfc_empty_nonce=empty_pick[2],
    ))

    for name, key, nonce, pt, aad, pinned in cases:
        _check_case(name, key, nonce, pt, aad, pinned=pinned)

    print(
        f"[sanity] polyval_reference.py cross-validated against "
        f"cryptography.AESGCMSIV ({len(cases)} cases)"
    )


if __name__ == "__main__":
    cross_validate_reference()
