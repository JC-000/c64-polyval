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
    python3 tools/test_gcmsiv_polyval.py [--iterations N] [--seed S]

Requires: Python 3.10+, c64_test_harness, VICE x64sc
"""

import json
import os
import random
import struct
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
from polyval_reference import gcmsiv_encrypt as py_encrypt, gcmsiv_decrypt as py_decrypt

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
    send_key,
    send_text,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PRG_PATH = os.path.join(PROJECT_ROOT, "build", "polyval.prg")
LABELS_PATH = os.path.join(PROJECT_ROOT, "build", "labels.txt")
VECTORS_PATH = os.path.join(PROJECT_ROOT, "test", "rfc8452_vectors.json")

DEFAULT_ITERATIONS = 15
MAX_PT_LEN = 64  # C64 buffer limit


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def random_bytes(n: int) -> bytes:
    return bytes(random.randint(0, 255) for _ in range(n))


def setup_key_and_expand(transport: ViceTransport, labels: Labels, key: bytes):
    """Write 32-byte key and call aes_key_expansion."""
    write_bytes(transport, labels["key_data"], key)
    jsr(transport, labels["aes_key_expansion"], timeout=10.0)


def c64_gcmsiv_encrypt(transport: ViceTransport, labels: Labels,
                       key: bytes, nonce: bytes, plaintext: bytes) -> tuple[bytes, bytes]:
    """Run full GCM-SIV encryption on C64 via direct memory + jsr().

    Returns (ciphertext, tag).
    """
    # Set up key
    setup_key_and_expand(transport, labels, key)

    # Save expanded key to gcmsiv_saved_exp (gcmsiv_encrypt expects this)
    exp_key = read_bytes(transport, labels["expanded_key"], 240)
    write_bytes(transport, labels["gcmsiv_saved_exp"], exp_key)
    write_bytes(transport, labels["gcmsiv_saved_key"], key)

    # Write nonce
    write_bytes(transport, labels["gcmsiv_nonce"], nonce)

    # Write plaintext
    write_bytes(transport, labels["gcmsiv_pt_buf"], plaintext)
    write_bytes(transport, labels["gcmsiv_pt_len"], bytes([len(plaintext)]))

    # Run GCM-SIV encrypt
    jsr(transport, labels["gcmsiv_encrypt"], timeout=120.0)

    # Read results
    ct = read_bytes(transport, labels["gcmsiv_ct_buf"], len(plaintext))
    tag = read_bytes(transport, labels["gcmsiv_tag"], 16)

    # Restore original key (gcmsiv_encrypt may clobber expanded_key)
    write_bytes(transport, labels["expanded_key"], exp_key)

    return ct, tag


def c64_gcmsiv_decrypt(transport: ViceTransport, labels: Labels,
                       key: bytes, nonce: bytes, ciphertext: bytes,
                       tag: bytes) -> tuple[bytes, bool]:
    """Run full GCM-SIV decryption on C64 via direct memory + jsr().

    Returns (plaintext, tag_valid).
    """
    # Set up key
    setup_key_and_expand(transport, labels, key)

    # Save expanded key
    exp_key = read_bytes(transport, labels["expanded_key"], 240)
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
    jsr(transport, labels["gcmsiv_decrypt"], timeout=120.0)

    # Read results
    pt = read_bytes(transport, labels["gcmsiv_dec_buf"], len(ciphertext))
    tag_valid = read_bytes(transport, labels["gcmsiv_tag_valid"], 1)[0]

    # Restore original key
    write_bytes(transport, labels["expanded_key"], exp_key)

    return pt, tag_valid == 1


# ---------------------------------------------------------------------------
# Test functions
# ---------------------------------------------------------------------------

def test_rfc_vector_encrypt(transport: ViceTransport, labels: Labels,
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
        print(f"  SKIP: plaintext too long ({len(pt)} > {MAX_PT_LEN})")
        return True

    if vector.get("aad", ""):
        print(f"  SKIP: C64 does not support AAD")
        return True

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


def test_rfc_vector_decrypt(transport: ViceTransport, labels: Labels,
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
        print(f"  SKIP: ciphertext too long ({len(ct)} > {MAX_PT_LEN})")
        return True

    if vector.get("aad", ""):
        print(f"  SKIP: C64 does not support AAD")
        return True

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


def test_random_roundtrip(transport: ViceTransport, labels: Labels,
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


def test_tampered_tag(transport: ViceTransport, labels: Labels) -> bool:
    """Verify that a tampered tag causes verification failure."""
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
# Orchestrator
# ---------------------------------------------------------------------------

def run_tests(transport: ViceTransport, labels: Labels,
              iterations: int) -> tuple[int, int]:
    """Run all GCM-SIV tests. Returns (passed, failed)."""
    passed = 0
    failed = 0

    def record(ok: bool):
        nonlocal passed, failed
        if ok:
            passed += 1
        else:
            failed += 1

    # Load RFC vectors
    with open(VECTORS_PATH) as f:
        vectors = json.load(f)

    # Filter to no-AAD vectors for C64 testing
    no_aad_vectors = [v for v in vectors["aes256_gcmsiv_vectors"]
                      if not v.get("aad", "")]

    # 1. RFC vector encryption tests (no AAD only)
    print("\n=== RFC 8452 C.2 Vector Encryption ===")
    for v in no_aad_vectors:
        record(test_rfc_vector_encrypt(transport, labels, v))

    # 2. RFC vector decryption tests (no AAD only)
    print("\n=== RFC 8452 C.2 Vector Decryption ===")
    for v in no_aad_vectors:
        record(test_rfc_vector_decrypt(transport, labels, v))

    # 3. Tampered tag test
    print("\n=== Tampered Tag Detection ===")
    record(test_tampered_tag(transport, labels))

    # 4. Random roundtrip tests
    print("\n=== Random Roundtrip Tests ===")
    fixed_count = len(no_aad_vectors) * 2 + 1  # encrypt + decrypt + tamper
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
        "key_data", "expanded_key", "aes_key_expansion",
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
        print(f"\n=== GCM-SIV + POLYVAL Tests ({iterations} iterations) ===")
        passed, failed = run_tests(transport, labels, iterations)

    # Summary
    total = passed + failed
    print("\n" + "=" * 60)
    print("RESULTS")
    print("=" * 60)
    print(f"  Passed: {passed}/{total}")
    print(f"  Failed: {failed}/{total}")
    if failed == 0:
        print(f"\n  [+] GCM-SIV + POLYVAL: ALL {total} TESTS PASSED")
    else:
        print(f"\n  [-] GCM-SIV + POLYVAL: {failed} TEST(S) FAILED")
    print("=" * 60)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
