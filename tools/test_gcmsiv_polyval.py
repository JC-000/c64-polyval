#!/usr/bin/env python3
"""
test_gcmsiv_polyval.py - End-to-End AES-256-GCM-SIV Test

Tests the full C64 GCM-SIV encrypt/decrypt pipeline (including POLYVAL)
against the Python reference implementation and RFC 8452 test vectors.

Approach:
  - For encryption: write key + nonce + plaintext to C64 memory,
    trigger gcmsiv_encrypt via jsr(), read back ciphertext + tag,
    compare against Python reference.
  - For decryption: write key + nonce + ciphertext + tag,
    trigger gcmsiv_decrypt, verify plaintext matches.

Note: The C64 implementation has no AAD support (AAD is always empty),
so only vectors with empty AAD are tested via the C64.

Usage:
    python3 tools/test_gcmsiv_polyval.py [--iterations N] [--seed S|random]

Seeding:
  By default, the RNG is seeded with DEFAULT_SEED = 8452 (RFC 8452 number),
  so two runs with no args produce the same random vectors. To reproduce a
  specific failing run, pass `--seed <N>` with the seed printed at startup.
  To opt in to a fresh non-deterministic run (fuzz-style), pass
  `--seed random` — a 32-bit seed is sampled and printed so you can still
  reproduce if something fails.

Requires: Python 3.10+, c64_test_harness, VICE x64sc
"""

import json
import os
import random
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
from reference_sanity import cross_validate_reference
from polyval_reference import (
    gcmsiv_encrypt as py_encrypt,
    gcmsiv_decrypt as py_decrypt,
    gcmsiv_derive_keys as py_derive_keys,
    gcmsiv_compute_tag as py_compute_tag,
    gcmsiv_ctr_encrypt as py_ctr,
    polyval as py_polyval,
    bytes_to_int,
    int_to_bytes,
)
import struct
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

from c64_test_harness import (
    Labels,
    ViceConfig,
    ViceInstanceManager,
    BinaryViceTransport,
    dump_screen,
    read_bytes,
    write_bytes,
    jsr,  # used via robust_jsr wrapper
    wait_for_text,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PRG_PATH = os.path.join(PROJECT_ROOT, "build", "polyval.prg")
LABELS_PATH = os.path.join(PROJECT_ROOT, "build", "labels.txt")
VECTORS_PATH = os.path.join(PROJECT_ROOT, "test", "rfc8452_vectors.json")

DEFAULT_SEED = 8452  # RFC 8452 number; deterministic by default
DEFAULT_ITERATIONS = 15
MAX_PT_LEN = 64  # C64 buffer limit

# Max retries for transient VICE connection failures
JSR_RETRIES = 3
JSR_RETRY_DELAY = 0.3


# Sentinel returned by test functions when a vector is intentionally skipped
# (e.g. AAD-containing RFC vectors: the 6502 gcmsiv_compute_tag_base does not
# absorb AAD, so those tests can't run against the C64 at all). Tracked
# separately from pass/fail in the summary.
SKIP = "SKIP"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def robust_jsr(transport, addr, timeout=10.0, retries=JSR_RETRIES):
    """Call jsr() with retry logic for transient VICE connection failures."""
    for attempt in range(retries):
        try:
            return jsr(transport, addr, timeout=timeout)
        except Exception as e:
            if attempt < retries - 1:
                time.sleep(JSR_RETRY_DELAY)
            else:
                raise

def random_bytes(n: int) -> bytes:
    return bytes(random.randint(0, 255) for _ in range(n))


def setup_key_and_expand(transport: BinaryViceTransport, labels: Labels, key: bytes):
    """Write 32-byte key and call aes_key_expansion."""
    write_bytes(transport, labels["aes_current_key"], key)
    robust_jsr(transport, labels["aes_key_expansion"], timeout=10.0)


def c64_gcmsiv_encrypt(transport: BinaryViceTransport, labels: Labels,
                       key: bytes, nonce: bytes, plaintext: bytes) -> tuple[bytes, bytes]:
    """Run full GCM-SIV encryption on C64 via direct memory + jsr().

    Returns (ciphertext, tag).
    """
    # Set up key
    setup_key_and_expand(transport, labels, key)

    # Save expanded key to gcmsiv_saved_exp (gcmsiv_encrypt expects this)
    exp_key = read_bytes(transport, labels["aes_expanded_key"], 240)
    write_bytes(transport, labels["gcmsiv_saved_exp"], exp_key)
    write_bytes(transport, labels["gcmsiv_saved_key"], key)

    # Write nonce
    write_bytes(transport, labels["gcmsiv_nonce"], nonce)

    # Write plaintext
    write_bytes(transport, labels["gcmsiv_pt_buf"], plaintext)
    write_bytes(transport, labels["gcmsiv_pt_len"], bytes([len(plaintext)]))

    # Run GCM-SIV encrypt
    robust_jsr(transport, labels["gcmsiv_encrypt"], timeout=120.0)

    # Read results
    ct = read_bytes(transport, labels["gcmsiv_ct_buf"], len(plaintext))
    tag = read_bytes(transport, labels["gcmsiv_tag"], 16)

    # Restore original key (gcmsiv_encrypt may clobber aes_expanded_key)
    write_bytes(transport, labels["aes_expanded_key"], exp_key)

    return ct, tag


def c64_gcmsiv_decrypt(transport: BinaryViceTransport, labels: Labels,
                       key: bytes, nonce: bytes, ciphertext: bytes,
                       tag: bytes) -> tuple[bytes, bool]:
    """Run full GCM-SIV decryption on C64 via direct memory + jsr().

    Returns (plaintext, tag_valid).
    """
    # Set up key
    setup_key_and_expand(transport, labels, key)

    # Save expanded key
    exp_key = read_bytes(transport, labels["aes_expanded_key"], 240)
    write_bytes(transport, labels["gcmsiv_saved_exp"], exp_key)
    write_bytes(transport, labels["gcmsiv_saved_key"], key)

    # Write nonce
    write_bytes(transport, labels["gcmsiv_nonce"], nonce)

    # Write ciphertext to ct_buf
    write_bytes(transport, labels["gcmsiv_ct_buf"], ciphertext)
    write_bytes(transport, labels["gcmsiv_pt_len"], bytes([len(ciphertext)]))

    # Write tag
    write_bytes(transport, labels["gcmsiv_tag"], tag)

    # Run GCM-SIV decrypt
    robust_jsr(transport, labels["gcmsiv_decrypt"], timeout=120.0)

    # Read results
    pt = read_bytes(transport, labels["gcmsiv_dec_buf"], len(ciphertext))
    tag_valid = read_bytes(transport, labels["gcmsiv_tag_valid"], 1)[0]

    # Restore original key
    write_bytes(transport, labels["aes_expanded_key"], exp_key)

    return pt, tag_valid == 1


# ---------------------------------------------------------------------------
# Test functions
# ---------------------------------------------------------------------------

def test_rfc_vector_encrypt(transport: BinaryViceTransport, labels: Labels,
                            vector: dict) -> bool:
    """Test C64 encryption against an RFC 8452 vector."""
    name = vector["name"]
    print(f"\n--- Encrypt: {name} ---")

    key = bytes.fromhex(vector["key"])
    nonce = bytes.fromhex(vector["nonce"])
    pt = bytes.fromhex(vector["plaintext"]) if vector["plaintext"] else b""
    expected_ct = bytes.fromhex(vector["ciphertext"]) if vector["ciphertext"] else b""
    expected_tag = bytes.fromhex(vector["tag"])

    if len(pt) > MAX_PT_LEN:
        reason = f"plaintext too long ({len(pt)} > {MAX_PT_LEN}, C64 buffer limit)"
        print(f"  SKIPPED: {name} ({reason})")
        return SKIP

    if vector.get("aad", ""):
        reason = "AAD not supported by 6502 gcmsiv_compute_tag_base"
        print(f"  SKIPPED: {name} ({reason})")
        return SKIP

    ct, tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)

    if ct == expected_ct and tag == expected_tag:
        print(f"  PASS: ct={ct.hex() if ct else '(empty)'}, tag={tag.hex()}")
        return True
    else:
        print(f"  FAIL:")
        if ct != expected_ct:
            print(f"    CT expected: {expected_ct.hex()}")
            print(f"    CT got:      {ct.hex()}")
        if tag != expected_tag:
            print(f"    Tag expected: {expected_tag.hex()}")
            print(f"    Tag got:      {tag.hex()}")
        return False


def test_rfc_vector_decrypt(transport: BinaryViceTransport, labels: Labels,
                            vector: dict) -> bool:
    """Test C64 decryption against an RFC 8452 vector."""
    name = vector["name"]
    print(f"\n--- Decrypt: {name} ---")

    key = bytes.fromhex(vector["key"])
    nonce = bytes.fromhex(vector["nonce"])
    expected_pt = bytes.fromhex(vector["plaintext"]) if vector["plaintext"] else b""
    ct = bytes.fromhex(vector["ciphertext"]) if vector["ciphertext"] else b""
    tag = bytes.fromhex(vector["tag"])

    if len(ct) > MAX_PT_LEN:
        reason = f"ciphertext too long ({len(ct)} > {MAX_PT_LEN}, C64 buffer limit)"
        print(f"  SKIPPED: {name} ({reason})")
        return SKIP

    if vector.get("aad", ""):
        reason = "AAD not supported by 6502 gcmsiv_compute_tag_base"
        print(f"  SKIPPED: {name} ({reason})")
        return SKIP

    pt, valid = c64_gcmsiv_decrypt(transport, labels, key, nonce, ct, tag)

    if pt == expected_pt and valid:
        print(f"  PASS: pt={pt.hex() if pt else '(empty)'}, tag valid")
        return True
    else:
        print(f"  FAIL:")
        if pt != expected_pt:
            print(f"    PT expected: {expected_pt.hex()}")
            print(f"    PT got:      {pt.hex()}")
        if not valid:
            print(f"    Tag verification failed")
        return False


def test_random_roundtrip(transport: BinaryViceTransport, labels: Labels,
                          pt_len: int, label: str) -> bool:
    """Encrypt on C64, decrypt on C64, verify roundtrip + match Python reference."""
    print(f"\n--- {label} ---")

    key = random_bytes(32)
    nonce = random_bytes(12)
    pt = random_bytes(pt_len) if pt_len > 0 else b""

    # Python reference
    py_ct, py_tag = py_encrypt(key, nonce, pt)

    # C64 encrypt
    c64_ct, c64_tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)

    if c64_ct != py_ct or c64_tag != py_tag:
        print(f"  FAIL: C64 encrypt doesn't match Python reference")
        print(f"    Key:   {key.hex()}")
        print(f"    Nonce: {nonce.hex()}")
        print(f"    PT:    {pt.hex() if pt else '(empty)'}")
        if c64_ct != py_ct:
            print(f"    CT expected: {py_ct.hex()}")
            print(f"    CT got:      {c64_ct.hex()}")
        if c64_tag != py_tag:
            print(f"    Tag expected: {py_tag.hex()}")
            print(f"    Tag got:      {c64_tag.hex()}")
        return False

    # C64 decrypt
    dec_pt, valid = c64_gcmsiv_decrypt(transport, labels, key, nonce, c64_ct, c64_tag)

    if dec_pt == pt and valid:
        print(f"  PASS: roundtrip OK ({pt_len} bytes)")
        return True
    else:
        print(f"  FAIL: decrypt mismatch or tag invalid")
        if dec_pt != pt:
            print(f"    PT expected: {pt.hex()}")
            print(f"    PT got:      {dec_pt.hex()}")
        if not valid:
            print(f"    Tag verification failed")
        return False


def test_tampered_tag(transport: BinaryViceTransport, labels: Labels) -> bool:
    """Verify that a tampered tag (single bit in byte 0) causes failure.

    This is the legacy smoke test retained for backward-compatible output.
    The expanded bit-flip coverage lives in test_tampered_tag_bitflips.
    """
    print("\n--- Tampered tag detection ---")

    key = random_bytes(32)
    nonce = random_bytes(12)
    pt = random_bytes(16)

    ct, tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)

    # Flip a bit in the tag
    bad_tag = bytearray(tag)
    bad_tag[0] ^= 0x01
    bad_tag = bytes(bad_tag)

    _, valid = c64_gcmsiv_decrypt(transport, labels, key, nonce, ct, bad_tag)

    if not valid:
        print("  PASS: tampered tag correctly rejected")
        return True
    else:
        print("  FAIL: tampered tag was accepted!")
        return False


# ---------------------------------------------------------------------------
# P4 - Expanded negative tests
# ---------------------------------------------------------------------------

def _assert_rejected(transport, labels, key, nonce, ct, bad_tag, desc):
    """Call decrypt and assert it rejects. Returns bool."""
    _, valid = c64_gcmsiv_decrypt(transport, labels, key, nonce, ct, bad_tag)
    if not valid:
        print(f"    PASS: {desc}")
        return True
    print(f"    FAIL: {desc} -- accepted!")
    return False


def test_tampered_tag_bitflips(transport, labels) -> list:
    """Flip each of the 16 tag bytes (XOR 0x01), plus each of the 8 bits
    in tag byte 0 individually. 16 + 8 = 24 subtests.
    Returns list[bool] of per-subtest results.
    """
    print("\n--- Tag bit-flip coverage (16 bytes + 8 bits in byte 0) ---")
    key = random_bytes(32)
    nonce = random_bytes(12)
    pt = random_bytes(32)
    ct, tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)

    # Oracle: cryptography lib agrees this tag is valid for (key, nonce, pt)
    py_ct, py_tag = py_encrypt(key, nonce, pt)
    assert tag == py_tag and ct == py_ct, "oracle drift"

    results = []
    for i in range(16):
        bad = bytearray(tag)
        bad[i] ^= 0x01
        results.append(_assert_rejected(
            transport, labels, key, nonce, ct, bytes(bad),
            f"byte[{i}] LSB flip"))

    for bit in range(8):
        bad = bytearray(tag)
        bad[0] ^= (1 << bit)
        results.append(_assert_rejected(
            transport, labels, key, nonce, ct, bytes(bad),
            f"byte[0] bit{bit} flip"))
    return results


def test_wrong_key(transport, labels) -> list:
    """5 random (key,nonce,pt) tuples. Encrypt, then flip one random bit in
    the key and assert decrypt rejects."""
    print("\n--- Wrong key rejection (5 vectors) ---")
    results = []
    for i in range(5):
        key = random_bytes(32)
        nonce = random_bytes(12)
        pt = random_bytes(16)
        ct, tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)
        # Oracle check
        py_ct, py_tag = py_encrypt(key, nonce, pt)
        if (ct, tag) != (py_ct, py_tag):
            print(f"    FAIL[{i}]: oracle drift on encrypt")
            results.append(False)
            continue
        byte_idx = random.randint(0, 31)
        bit_idx = random.randint(0, 7)
        bad_key = bytearray(key)
        bad_key[byte_idx] ^= (1 << bit_idx)
        results.append(_assert_rejected(
            transport, labels, bytes(bad_key), nonce, ct, tag,
            f"vec{i} key byte[{byte_idx}] bit{bit_idx}"))
    return results


def test_tampered_ciphertext(transport, labels) -> list:
    """5 vectors, 3 positions each (first, middle, last byte). 15 subtests."""
    print("\n--- Tampered ciphertext rejection (5 vectors x 3 positions) ---")
    results = []
    for i in range(5):
        key = random_bytes(32)
        nonce = random_bytes(12)
        pt_len = random.choice([32, 48, 64])
        pt = random_bytes(pt_len)
        ct, tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)
        assert (ct, tag) == py_encrypt(key, nonce, pt), "oracle drift"

        positions = [0, pt_len // 2, pt_len - 1]
        for pos in positions:
            bad_ct = bytearray(ct)
            bad_ct[pos] ^= 0x55
            results.append(_assert_rejected(
                transport, labels, key, nonce, bytes(bad_ct), tag,
                f"vec{i} ct[{pos}] flip (len={pt_len})"))
    return results


def test_tampered_nonce(transport, labels) -> list:
    """5 vectors, 3 nonce-byte positions each (0, 5, 11). 15 subtests."""
    print("\n--- Tampered nonce rejection (5 vectors x 3 positions) ---")
    results = []
    for i in range(5):
        key = random_bytes(32)
        nonce = random_bytes(12)
        pt = random_bytes(16)
        ct, tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)
        assert (ct, tag) == py_encrypt(key, nonce, pt), "oracle drift"

        for pos in (0, 5, 11):
            bad_nonce = bytearray(nonce)
            bad_nonce[pos] ^= 0x01
            results.append(_assert_rejected(
                transport, labels, key, bytes(bad_nonce), ct, tag,
                f"vec{i} nonce[{pos}] flip"))
    return results


def test_all_zero_tag(transport, labels) -> list:
    """5 vectors, each with tag replaced by 16 zero bytes."""
    print("\n--- All-zero tag rejection (5 vectors) ---")
    results = []
    for i in range(5):
        key = random_bytes(32)
        nonce = random_bytes(12)
        pt = random_bytes(16)
        ct, _tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)
        results.append(_assert_rejected(
            transport, labels, key, nonce, ct, b"\x00" * 16,
            f"vec{i} zero-tag"))
    return results


def test_all_ones_tag(transport, labels) -> list:
    """5 vectors, each with tag replaced by 16 0xFF bytes."""
    print("\n--- All-ones tag rejection (5 vectors) ---")
    results = []
    for i in range(5):
        key = random_bytes(32)
        nonce = random_bytes(12)
        pt = random_bytes(16)
        ct, _tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)
        results.append(_assert_rejected(
            transport, labels, key, nonce, ct, b"\xff" * 16,
            f"vec{i} ones-tag"))
    return results


def test_tag_equals_pt_block(transport, labels) -> list:
    """5 vectors with tag replaced by pt[0:16]."""
    print("\n--- Tag-is-plaintext-block rejection (5 vectors) ---")
    results = []
    for i in range(5):
        key = random_bytes(32)
        nonce = random_bytes(12)
        pt = random_bytes(32)
        ct, _tag = c64_gcmsiv_encrypt(transport, labels, key, nonce, pt)
        bad_tag = pt[0:16]
        results.append(_assert_rejected(
            transport, labels, key, nonce, ct, bad_tag,
            f"vec{i} tag=pt[0:16]"))
    return results


# ---------------------------------------------------------------------------
# P5 - Direct unit tests for previously-uncovered public API routines
# ---------------------------------------------------------------------------

def _lib_aes_ecb_encrypt(key: bytes, block: bytes) -> bytes:
    c = Cipher(algorithms.AES(key), modes.ECB(), backend=default_backend())
    e = c.encryptor()
    return e.update(block) + e.finalize()


def _lib_aes_ecb_decrypt(key: bytes, block: bytes) -> bytes:
    c = Cipher(algorithms.AES(key), modes.ECB(), backend=default_backend())
    d = c.decryptor()
    return d.update(block) + d.finalize()


def test_aes_encrypt_block(transport, labels) -> list:
    """Direct unit test: aes_encrypt_block vs cryptography AES-256-ECB."""
    print("\n--- aes_encrypt_block direct (10 vectors) ---")
    results = []
    for i in range(10):
        key = random_bytes(32)
        pt = random_bytes(16)
        # Install key, expand, write state, jsr, read state
        write_bytes(transport, labels["aes_current_key"], key)
        robust_jsr(transport, labels["aes_key_expansion"], timeout=10.0)
        write_bytes(transport, labels["aes_state"], pt)
        robust_jsr(transport, labels["aes_encrypt_block"], timeout=10.0)
        got = read_bytes(transport, labels["aes_state"], 16)
        expected = _lib_aes_ecb_encrypt(key, pt)
        if got == expected:
            print(f"    PASS: vec{i}")
            results.append(True)
        else:
            print(f"    FAIL: vec{i}  expected {expected.hex()} got {got.hex()}")
            results.append(False)
    return results


def test_aes_decrypt_block(transport, labels) -> list:
    """Direct unit test: aes_decrypt_block vs cryptography AES-256-ECB."""
    print("\n--- aes_decrypt_block direct (10 vectors) ---")
    results = []
    for i in range(10):
        key = random_bytes(32)
        pt = random_bytes(16)
        ct = _lib_aes_ecb_encrypt(key, pt)
        write_bytes(transport, labels["aes_current_key"], key)
        robust_jsr(transport, labels["aes_key_expansion"], timeout=10.0)
        write_bytes(transport, labels["aes_state"], ct)
        robust_jsr(transport, labels["aes_decrypt_block"], timeout=10.0)
        got = read_bytes(transport, labels["aes_state"], 16)
        if got == pt:
            print(f"    PASS: vec{i}")
            results.append(True)
        else:
            print(f"    FAIL: vec{i}  expected {pt.hex()} got {got.hex()}")
            results.append(False)
    return results


def test_gcmsiv_derive_keys(transport, labels) -> list:
    """Direct unit test: gcmsiv_derive_keys vs polyval_reference.

    Precondition: aes_expanded_key must already hold the master-key expansion.
    """
    print("\n--- gcmsiv_derive_keys direct (10 vectors) ---")
    results = []
    for i in range(10):
        key = random_bytes(32)
        nonce = random_bytes(12)
        # Install master key and expand it (required precondition)
        write_bytes(transport, labels["aes_current_key"], key)
        robust_jsr(transport, labels["aes_key_expansion"], timeout=10.0)
        write_bytes(transport, labels["gcmsiv_nonce"], nonce)
        robust_jsr(transport, labels["gcmsiv_derive_keys"], timeout=30.0)
        got_auth = read_bytes(transport, labels["gcmsiv_auth_key"], 16)
        got_enc = read_bytes(transport, labels["gcmsiv_enc_key"], 32)
        exp_auth, exp_enc = py_derive_keys(key, nonce)
        if got_auth == exp_auth and got_enc == exp_enc:
            print(f"    PASS: vec{i}")
            results.append(True)
        else:
            print(f"    FAIL: vec{i}")
            if got_auth != exp_auth:
                print(f"      auth expected {exp_auth.hex()} got {got_auth.hex()}")
            if got_enc != exp_enc:
                print(f"      enc  expected {exp_enc.hex()} got {got_enc.hex()}")
            results.append(False)
    return results


def _py_polyval_tag_base(auth_key: bytes, pt: bytes) -> bytes:
    """Replicate what gcmsiv_compute_tag_base does: POLYVAL over
    [PT blocks] [length block with AAD=0]. Returns 16-byte POLYVAL result."""
    blocks = []
    if pt:
        for i in range(0, len(pt), 16):
            chunk = pt[i:i+16]
            if len(chunk) < 16:
                chunk = chunk + b"\x00" * (16 - len(chunk))
            blocks.append(chunk)
    len_block = struct.pack("<QQ", 0, len(pt) * 8)
    blocks.append(len_block)
    return py_polyval(auth_key, *blocks)


def test_gcmsiv_compute_tag_base(transport, labels) -> list:
    """Direct unit test: gcmsiv_compute_tag_base leaves POLYVAL result in
    gcmsiv_tag_acc (also polyval_acc). Compare vs python reference which
    is externally validated."""
    print("\n--- gcmsiv_compute_tag_base direct (10 vectors, varying len) ---")
    results = []
    lengths = [0, 1, 15, 16, 17, 32, 48, 63, 64, 7]
    for i, pt_len in enumerate(lengths):
        auth_key = random_bytes(16)
        pt = random_bytes(pt_len) if pt_len > 0 else b""
        # Set up state directly
        write_bytes(transport, labels["gcmsiv_auth_key"], auth_key)
        write_bytes(transport, labels["gcmsiv_pt_buf"], pt if pt else b"\x00")
        write_bytes(transport, labels["gcmsiv_pt_len"], bytes([pt_len]))
        robust_jsr(transport, labels["gcmsiv_compute_tag_base"], timeout=30.0)
        got = read_bytes(transport, labels["gcmsiv_tag_acc"], 16)
        expected = _py_polyval_tag_base(auth_key, pt)
        if got == expected:
            print(f"    PASS: vec{i} len={pt_len}")
            results.append(True)
        else:
            print(f"    FAIL: vec{i} len={pt_len}")
            print(f"      expected {expected.hex()}")
            print(f"      got      {got.hex()}")
            results.append(False)
    return results


def test_gcmsiv_finalize_tag(transport, labels) -> list:
    """Direct unit test: gcmsiv_finalize_tag applies (XOR nonce, clear MSB,
    AES-encrypt with derived enc key) to gcmsiv_tag_acc -> gcmsiv_tag.

    Precondition: gcmsiv_exp_enc_key must hold the derived enc-key schedule,
    and aes_expanded_key must hold the master schedule (the routine installs
    the enc key via gcmsiv_install_enc_key and restores it via
    gcmsiv_restore_orig_key)."""
    print("\n--- gcmsiv_finalize_tag direct (10 vectors) ---")
    results = []
    for i in range(10):
        key = random_bytes(32)
        nonce = random_bytes(12)
        tag_acc = random_bytes(16)

        # Bootstrap: install master key + expand, then run derive_keys
        # so that gcmsiv_exp_enc_key gets populated.
        write_bytes(transport, labels["aes_current_key"], key)
        robust_jsr(transport, labels["aes_key_expansion"], timeout=10.0)
        write_bytes(transport, labels["gcmsiv_nonce"], nonce)
        robust_jsr(transport, labels["gcmsiv_derive_keys"], timeout=30.0)

        # Now set up the inputs for finalize_tag
        write_bytes(transport, labels["gcmsiv_tag_acc"], tag_acc)
        # nonce already in place; exp_enc_key populated by derive_keys
        robust_jsr(transport, labels["gcmsiv_finalize_tag"], timeout=10.0)
        got = read_bytes(transport, labels["gcmsiv_tag"], 16)

        # Compute expected
        _auth, enc_key = py_derive_keys(key, nonce)
        block = bytearray(tag_acc)
        for j in range(12):
            block[j] ^= nonce[j]
        block[15] &= 0x7f
        expected = _lib_aes_ecb_encrypt(enc_key, bytes(block))
        if got == expected:
            print(f"    PASS: vec{i}")
            results.append(True)
        else:
            print(f"    FAIL: vec{i}")
            print(f"      expected {expected.hex()}")
            print(f"      got      {got.hex()}")
            results.append(False)
    return results


def _py_gcmsiv_ctr(enc_key: bytes, tag: bytes, data: bytes) -> bytes:
    """GCM-SIV CTR: counter = tag with MSB of byte 15 set, 32-bit LE
    increment on bytes 0..3 per block. Mirrors polyval_reference.gcmsiv_ctr_encrypt
    but we reimplement via cryptography for the P5 external oracle."""
    if not data:
        return b""
    counter = bytearray(tag)
    counter[15] |= 0x80
    out = bytearray()
    for i in range(0, len(data), 16):
        ks = _lib_aes_ecb_encrypt(enc_key, bytes(counter))
        chunk = data[i:i+16]
        for j in range(len(chunk)):
            out.append(chunk[j] ^ ks[j])
        c = struct.unpack_from("<I", counter, 0)[0]
        c = (c + 1) & 0xFFFFFFFF
        struct.pack_into("<I", counter, 0, c)
    return bytes(out)


def test_gcmsiv_ctr_encrypt(transport, labels) -> list:
    """Direct unit test: gcmsiv_ctr_encrypt runs AES-CTR over gcmsiv_pt_buf
    -> gcmsiv_ct_buf using the derived enc-key schedule and gcmsiv_tag as IV."""
    print("\n--- gcmsiv_ctr_encrypt direct (10 vectors) ---")
    results = []
    for i in range(10):
        key = random_bytes(32)
        nonce = random_bytes(12)
        pt_len = random.choice([1, 15, 16, 17, 32, 48, 63, 64])
        pt = random_bytes(pt_len)
        tag = random_bytes(16)

        # Bootstrap derive_keys to populate gcmsiv_exp_enc_key
        write_bytes(transport, labels["aes_current_key"], key)
        robust_jsr(transport, labels["aes_key_expansion"], timeout=10.0)
        write_bytes(transport, labels["gcmsiv_nonce"], nonce)
        robust_jsr(transport, labels["gcmsiv_derive_keys"], timeout=30.0)

        # Set inputs
        write_bytes(transport, labels["gcmsiv_pt_buf"], pt)
        write_bytes(transport, labels["gcmsiv_pt_len"], bytes([pt_len]))
        write_bytes(transport, labels["gcmsiv_tag"], tag)
        robust_jsr(transport, labels["gcmsiv_ctr_encrypt"], timeout=30.0)
        got = read_bytes(transport, labels["gcmsiv_ct_buf"], pt_len)

        _auth, enc_key = py_derive_keys(key, nonce)
        expected = _py_gcmsiv_ctr(enc_key, tag, pt)
        if got == expected:
            print(f"    PASS: vec{i} len={pt_len}")
            results.append(True)
        else:
            print(f"    FAIL: vec{i} len={pt_len}")
            print(f"      expected {expected.hex()}")
            print(f"      got      {got.hex()}")
            results.append(False)
    return results


def test_gcmsiv_ctr_decrypt(transport, labels) -> list:
    """Direct unit test: gcmsiv_ctr_decrypt is symmetric; encrypt via
    cryptography, decrypt via 6502, compare to plaintext."""
    print("\n--- gcmsiv_ctr_decrypt direct (10 vectors) ---")
    results = []
    for i in range(10):
        key = random_bytes(32)
        nonce = random_bytes(12)
        pt_len = random.choice([1, 15, 16, 17, 32, 48, 63, 64])
        pt = random_bytes(pt_len)
        tag = random_bytes(16)

        _auth, enc_key = py_derive_keys(key, nonce)
        ct = _py_gcmsiv_ctr(enc_key, tag, pt)

        write_bytes(transport, labels["aes_current_key"], key)
        robust_jsr(transport, labels["aes_key_expansion"], timeout=10.0)
        write_bytes(transport, labels["gcmsiv_nonce"], nonce)
        robust_jsr(transport, labels["gcmsiv_derive_keys"], timeout=30.0)

        write_bytes(transport, labels["gcmsiv_ct_buf"], ct)
        write_bytes(transport, labels["gcmsiv_pt_len"], bytes([pt_len]))
        write_bytes(transport, labels["gcmsiv_tag"], tag)
        robust_jsr(transport, labels["gcmsiv_ctr_decrypt"], timeout=30.0)
        got = read_bytes(transport, labels["gcmsiv_dec_buf"], pt_len)
        if got == pt:
            print(f"    PASS: vec{i} len={pt_len}")
            results.append(True)
        else:
            print(f"    FAIL: vec{i} len={pt_len}")
            print(f"      expected {pt.hex()}")
            print(f"      got      {got.hex()}")
            results.append(False)
    return results


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

def run_tests(transport: BinaryViceTransport, labels: Labels,
              iterations: int) -> tuple[int, int, int]:
    """Run all GCM-SIV tests. Returns (passed, skipped, failed)."""
    passed = 0
    skipped = 0
    failed = 0

    def record(result):
        nonlocal passed, skipped, failed
        if result == SKIP:
            skipped += 1
        elif result:
            passed += 1
        else:
            failed += 1

    # Load RFC vectors
    with open(VECTORS_PATH) as f:
        vectors = json.load(f)

    all_vectors = vectors["aes256_gcmsiv_vectors"]

    # 1. RFC vector encryption tests (AAD/oversized are reported as SKIPPED)
    print("\n=== RFC 8452 C.2 Vector Encryption ===")
    for v in all_vectors:
        record(test_rfc_vector_encrypt(transport, labels, v))

    # 2. RFC vector decryption tests
    print("\n=== RFC 8452 C.2 Vector Decryption ===")
    for v in all_vectors:
        record(test_rfc_vector_decrypt(transport, labels, v))

    # 3. Tampered tag test (legacy smoke)
    print("\n=== Tampered Tag Detection ===")
    record(test_tampered_tag(transport, labels))

    def record_many(results):
        for r in results:
            record(r)

    # 3a. Expanded negative tests (P4)
    print("\n=== Expanded Negative Tests ===")
    record_many(test_tampered_tag_bitflips(transport, labels))
    record_many(test_wrong_key(transport, labels))
    record_many(test_tampered_ciphertext(transport, labels))
    record_many(test_tampered_nonce(transport, labels))
    record_many(test_all_zero_tag(transport, labels))
    record_many(test_all_ones_tag(transport, labels))
    record_many(test_tag_equals_pt_block(transport, labels))

    # 3b. Direct API coverage tests (P5)
    print("\n=== Direct API Coverage Tests ===")
    record_many(test_aes_encrypt_block(transport, labels))
    record_many(test_aes_decrypt_block(transport, labels))
    record_many(test_gcmsiv_derive_keys(transport, labels))
    record_many(test_gcmsiv_compute_tag_base(transport, labels))
    record_many(test_gcmsiv_finalize_tag(transport, labels))
    record_many(test_gcmsiv_ctr_encrypt(transport, labels))
    record_many(test_gcmsiv_ctr_decrypt(transport, labels))

    # 4. Random roundtrip tests
    print("\n=== Random Roundtrip Tests ===")
    no_aad_count = sum(1 for v in all_vectors if not v.get("aad", ""))
    fixed_count = no_aad_count * 2 + 1  # encrypt + decrypt + tamper
    random_count = max(0, iterations - fixed_count)

    # Boundary cases
    boundary_lengths = [1, 15, 16, 17, 32, 48, 63, 64]
    for pt_len in boundary_lengths:
        if random_count <= 0:
            break
        record(test_random_roundtrip(
            transport, labels, pt_len,
            f"Roundtrip: {pt_len} bytes",
        ))
        random_count -= 1

    # Random lengths
    for i in range(random_count):
        pt_len = random.randint(1, MAX_PT_LEN)
        record(test_random_roundtrip(
            transport, labels, pt_len,
            f"Random roundtrip {i+1}: {pt_len} bytes",
        ))

    return passed, skipped, failed


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    os.chdir(PROJECT_ROOT)

    # Cross-check Python oracle against an external AES-GCM-SIV implementation
    # BEFORE any 6502 code runs. Aborts the suite on drift.
    cross_validate_reference()

    # Parse args
    iterations = DEFAULT_ITERATIONS
    if "--iterations" in sys.argv:
        idx = sys.argv.index("--iterations")
        if idx + 1 < len(sys.argv):
            iterations = int(sys.argv[idx + 1])

    seed = DEFAULT_SEED
    if "--seed" in sys.argv:
        idx = sys.argv.index("--seed")
        if idx + 1 < len(sys.argv):
            raw = sys.argv[idx + 1]
            if raw == "random":
                # Opt-in fuzz mode: sample a fresh seed but print it so
                # any failure is still reproducible via `--seed <N>`.
                seed = random.SystemRandom().randint(0, 2**32 - 1)
            else:
                seed = int(raw)
    random.seed(seed)
    print(f"Seed: {seed} (reproduce with --seed {seed})")

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
        "aes_current_key", "aes_expanded_key", "aes_key_expansion",
        "gcmsiv_nonce", "gcmsiv_pt_buf", "gcmsiv_pt_len",
        "gcmsiv_ct_buf", "gcmsiv_tag", "gcmsiv_tag_valid",
        "gcmsiv_dec_buf", "gcmsiv_encrypt", "gcmsiv_decrypt",
        "gcmsiv_saved_key", "gcmsiv_saved_exp",
        "polyval_acc", "polyval_h",
    ]
    for name in required_labels:
        if labels.address(name) is None:
            print(f"FATAL: '{name}' label not found")
            sys.exit(1)
    print(f"  Labels loaded")

    # Start VICE
    print("\n=== Starting VICE ===")
    config = ViceConfig(
        prg_path=PRG_PATH,
        warp=True,
        ntsc=True,
        sound=False,
    )

    with ViceInstanceManager(config=config) as mgr:
        inst = mgr.acquire()
        print(f"  VICE started (PID {inst.pid}, port {inst.port})")

        transport = inst.transport

        # Wait for main menu
        print("  Waiting for main menu...")
        grid = wait_for_text(transport, "Q=QUIT", timeout=60.0, verbose=False)
        if grid is None:
            print("FATAL: Main menu did not appear")
            dump_screen(transport, "startup")
            sys.exit(1)
        print("  Main menu ready")

        # Run tests
        print(f"\n=== GCM-SIV + POLYVAL Tests ({iterations} iterations) ===")
        passed, skipped, failed = run_tests(transport, labels, iterations)

    # Summary
    total = passed + skipped + failed
    print("\n" + "=" * 60)
    print("RESULTS")
    print("=" * 60)
    print(f"  Passed:  {passed}/{total}")
    print(f"  Skipped: {skipped}/{total}")
    print(f"  Failed:  {failed}/{total}")
    if failed == 0:
        summary = f"{passed} passed, {skipped} skipped, 0 failed"
        print(f"\n  [+] GCM-SIV + POLYVAL: {summary}")
    else:
        print(f"\n  [-] GCM-SIV + POLYVAL: {failed} TEST(S) FAILED "
              f"({passed} passed, {skipped} skipped)")
    print("=" * 60)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
