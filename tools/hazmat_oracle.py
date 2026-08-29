#!/usr/bin/env python3
"""
hazmat_oracle.py - Independent POLYVAL / AES-256-GCM-SIV oracle.

Written from the RFC 8452 text only and deliberately NOT derived from
tools/polyval_reference.py, so that a misconception shared by the 6502 code
and the project's own reference cannot cancel out:

  - dot(a, b) = a * b * x^-128 in GF(2^128)/(x^128 + x^127 + x^126 + x^121 + 1)
    via schoolbook carry-less multiply + explicit polynomial reduction
    (polyval_reference.py uses a bit-serial right-shift loop instead).
  - x^-128 is derived by exponentiation, then checked against the RFC
    identity x^-128 = 1 + x^-1 + x^-2 + x^-7.
  - mulX_POLYVAL per RFC 8452 Section 3.
  - AES-256 is a self-contained pure-Python implementation (FIPS 197), so the
    oracle runs with no third-party dependency at all.
  - GCM-SIV per RFC 8452 Section 4 on top of the above.

`cryptography` (hazmat) is OPTIONAL.  When it is importable, the self-check
additionally cross-checks the pure-Python AES against hazmat AES-ECB and the
GCM-SIV construction against hazmat AESGCMSIV; when it is missing (or its
AESGCMSIV is unsupported by the backend), those cross-checks are reported as
SKIPPED and the RFC-vector self-check still gates the oracle.

Self-check on import: RFC 8452 Appendix A (POLYVAL, mulX_POLYVAL) and the
Appendix C.2 AES-256 vectors carried below (incl. AAD and non-trivial
key/nonce ones), FIPS-197 AES-256 vector, the GHASH relation from
Appendix A, plus the hazmat cross-checks when available.

Run standalone:
    python3.13 tools/hazmat_oracle.py
"""

import random
import struct

# ---------------------------------------------------------------------------
# Optional hazmat
# ---------------------------------------------------------------------------

HAZMAT_AVAILABLE = False
HAZMAT_GCMSIV_AVAILABLE = False
HAZMAT_SKIP_REASON = ""
try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    HAZMAT_AVAILABLE = True
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCMSIV
        # Some backends import the class but refuse to construct it
        # (UnsupportedAlgorithm) — probe once.
        AESGCMSIV(b"\x00" * 32)
        HAZMAT_GCMSIV_AVAILABLE = True
    except Exception as _e:  # ImportError / UnsupportedAlgorithm
        HAZMAT_SKIP_REASON = f"cryptography present but AESGCMSIV unsupported ({type(_e).__name__})"
except ImportError:
    HAZMAT_SKIP_REASON = "cryptography package not installed"


# ---------------------------------------------------------------------------
# GF(2^128) / POLYVAL
# ---------------------------------------------------------------------------

M128 = (1 << 128) - 1
# POLYVAL field polynomial x^128 + x^127 + x^126 + x^121 + 1 (bit i = coeff of x^i)
POLY = (1 << 128) | (1 << 127) | (1 << 126) | (1 << 121) | 1


def le(b: bytes) -> int:
    return int.from_bytes(b, "little")


def unle(n: int) -> bytes:
    return (n & M128).to_bytes(16, "little")


def clmul(a: int, b: int) -> int:
    r = 0
    while b:
        if b & 1:
            r ^= a
        a <<= 1
        b >>= 1
    return r


def reduce(v: int) -> int:
    """Reduce a polynomial of degree < 256 modulo POLY."""
    for i in range(v.bit_length() - 1, 127, -1):
        if (v >> i) & 1:
            v ^= POLY << (i - 128)
    return v


def gf_mul(a: int, b: int) -> int:
    return reduce(clmul(a, b))


def _inv_x128() -> int:
    """x^-128 = x^(2^128 - 1 - 128) by square-and-multiply (group order 2^128-1)."""
    e = (1 << 128) - 1 - 128
    base, result = 2, 1  # the element 'x' is the integer 2
    while e:
        if e & 1:
            result = gf_mul(result, base)
        base = gf_mul(base, base)
        e >>= 1
    return result


X_INV128 = _inv_x128()
assert gf_mul(X_INV128, reduce(1 << 128)) == 1


def dot(a: int, b: int) -> int:
    """RFC 8452: dot(a, b) = a * b * x^-128."""
    return gf_mul(gf_mul(a, b), X_INV128)


def mulX_POLYVAL(v: bytes) -> bytes:
    """RFC 8452 Section 3: multiply by x in the POLYVAL field (byte-string form)."""
    return unle(reduce(le(v) << 1))


def polyval(h: bytes, msg: bytes) -> bytes:
    """POLYVAL(H, X_1..X_n) with msg a multiple of 16 bytes."""
    assert len(msg) % 16 == 0
    hh = le(h)
    s = 0
    for i in range(0, len(msg), 16):
        s = dot(s ^ le(msg[i:i + 16]), hh)
    return unle(s)


# ---------------------------------------------------------------------------
# AES-256 (FIPS 197), pure Python — encrypt-only, that is all GCM-SIV needs
# ---------------------------------------------------------------------------

def _build_sbox():
    sbox = [0] * 256
    p = q = 1
    while True:
        # multiply p by 3
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
        # divide q by 3 (equals multiplication by 0xf6)
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        x = q ^ (q << 1) ^ (q << 2) ^ (q << 3) ^ (q << 4)
        x = (x ^ (x >> 8) ^ 0x63) & 0xFF
        sbox[p] = x
        if p == 1:
            break
    sbox[0] = 0x63
    return sbox


SBOX = _build_sbox()


def _xtime(a: int) -> int:
    a <<= 1
    return (a ^ 0x1B) & 0xFF if a & 0x100 else a


def aes256_expand_key(key: bytes) -> list:
    assert len(key) == 32
    w = [list(key[i:i + 4]) for i in range(0, 32, 4)]
    rcon = 1
    for i in range(8, 60):
        t = list(w[i - 1])
        if i % 8 == 0:
            t = t[1:] + t[:1]
            t = [SBOX[b] for b in t]
            t[0] ^= rcon
            rcon = _xtime(rcon)
        elif i % 8 == 4:
            t = [SBOX[b] for b in t]
        w.append([a ^ b for a, b in zip(w[i - 8], t)])
    return [bytes(sum(w[r * 4:r * 4 + 4], [])) for r in range(15)]


def aes256_encrypt_block(key: bytes, block: bytes) -> bytes:
    rk = aes256_expand_key(key)
    s = [b ^ k for b, k in zip(block, rk[0])]
    for rnd in range(1, 15):
        s = [SBOX[b] for b in s]                                   # SubBytes
        s = [s[(i + 4 * (i % 4)) % 16] for i in range(16)]        # ShiftRows
        if rnd != 14:                                             # MixColumns
            out = []
            for c in range(4):
                a = s[c * 4:c * 4 + 4]
                t = a[0] ^ a[1] ^ a[2] ^ a[3]
                out += [a[i] ^ t ^ _xtime(a[i] ^ a[(i + 1) % 4]) for i in range(4)]
            s = out
        s = [b ^ k for b, k in zip(s, rk[rnd])]                   # AddRoundKey
    return bytes(s)


def aes_ecb(key: bytes, block: bytes) -> bytes:
    return aes256_encrypt_block(key, block)


def hazmat_aes_ecb(key: bytes, block: bytes) -> bytes:
    e = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    return e.update(block) + e.finalize()


# ---------------------------------------------------------------------------
# GCM-SIV (RFC 8452 Section 4)
# ---------------------------------------------------------------------------

def derive_keys(key: bytes, nonce: bytes):
    """RFC 8452 Section 4, AES-256 variant. Returns (auth_key, enc_key)."""
    assert len(key) == 32 and len(nonce) == 12
    out = b"".join(aes_ecb(key, struct.pack("<I", i) + nonce)[:8] for i in range(6))
    return out[:16], out[16:48]


def pad16(b: bytes) -> bytes:
    return b + b"\x00" * ((-len(b)) % 16)


def gcmsiv_tag(auth_key, enc_key, nonce, pt, aad=b""):
    lb = struct.pack("<QQ", len(aad) * 8, len(pt) * 8)
    s = bytearray(polyval(auth_key, pad16(aad) + pad16(pt) + lb))
    for i in range(12):
        s[i] ^= nonce[i]
    s[15] &= 0x7F
    return aes_ecb(enc_key, bytes(s))


def ctr(enc_key: bytes, tag: bytes, data: bytes) -> bytes:
    blk = bytearray(tag)
    blk[15] |= 0x80
    out = bytearray()
    for i in range(0, len(data), 16):
        ks = aes_ecb(enc_key, bytes(blk))
        chunk = data[i:i + 16]
        out += bytes(x ^ y for x, y in zip(chunk, ks))
        c = (struct.unpack_from("<I", blk)[0] + 1) & 0xFFFFFFFF
        struct.pack_into("<I", blk, 0, c)
    return bytes(out)


def gcmsiv_encrypt(key, nonce, pt, aad=b""):
    ak, ek = derive_keys(key, nonce)
    tag = gcmsiv_tag(ak, ek, nonce, pt, aad)
    return ctr(ek, tag, pt), tag


def gcmsiv_decrypt(key, nonce, ct, tag, aad=b""):
    ak, ek = derive_keys(key, nonce)
    pt = ctr(ek, tag, ct)
    ok = gcmsiv_tag(ak, ek, nonce, pt, aad) == tag
    return pt, ok


# ---------------------------------------------------------------------------
# RFC 8452 Appendix C.2 AES-256-GCM-SIV vectors (transcribed from the RFC text)
# (key, nonce, plaintext, aad, ciphertext||tag)
# ---------------------------------------------------------------------------

_K1 = "01" + "00" * 31
_N1 = "030000000000000000000000"
RFC_C2_VECTORS = [
    (_K1, _N1, "", "", "07f5f4169bbf55a8400cd47ea6fd400f"),
    (_K1, _N1, "0100000000000000", "", "c2ef328e5c71c83b843122130f7364b761e0b97427e3df28"),
    (_K1, _N1, "010000000000000000000000", "", "9aab2aeb3faa0a34aea8e2b18ca50da9ae6559e48fd10f6e5c9ca17e"),
    (_K1, _N1, "01000000000000000000000000000000", "",
     "85a01b63025ba19b7fd3ddfc033b3e76c9eac6fa700942702e90862383c6c366"),
    (_K1, _N1, "0100000000000000000000000000000002000000000000000000000000000000", "",
     "4a6a9db4c8c6549201b9edb53006cba821ec9cf850948a7c86c68ac7539d027fe819e63abcd020b006a976397632eb5d"),
    (_K1, _N1, "0200000000000000", "01", "1de22967237a813291213f267e3b452f02d01ae33e4ec854"),
    (_K1, _N1, "02000000000000000000000000000000", "01",
     "c91545823cc24f17dbb0e9e807d5ec17b292d28ff61189e8e49f3875ef91aff7"),
    # RFC C.2 #17: non-trivial key/nonce, empty PT, empty AAD
    ("e66021d5eb8e4f4066d4adb9c33560e4f46e44bb3da0015c94f7088736864200",
     "e0eaf5284d884a0e77d31646", "", "", "169fbb2fbf389a995f6390af22228a62"),
]


# ---------------------------------------------------------------------------
# Self-verification
# ---------------------------------------------------------------------------

def _selfcheck():
    """Returns (log_lines, skipped_lines). Raises AssertionError on any drift."""
    log, skipped = [], []

    # FIPS-197 C.3 AES-256 vector
    assert aes256_encrypt_block(bytes(range(32)), bytes.fromhex("00112233445566778899aabbccddeeff")) == \
        bytes.fromhex("8ea2b7ca516745bfeafc49904b496089")
    log.append("FIPS-197 C.3 AES-256 vector: OK")

    # RFC 8452 Appendix A
    h = bytes.fromhex("25629347589242761d31f826ba4b757b")
    x1 = bytes.fromhex("4f4f95668c83dfb6401762bb2d01a262")
    x2 = bytes.fromhex("d1a24ddd2721d006bbe45f20d3c9f362")
    assert polyval(h, x1 + x2) == bytes.fromhex("f7a3b47b846119fae5b7866cf5e5b77e")
    assert mulX_POLYVAL(bytes.fromhex("01000000000000000000000000000000")) == \
        bytes.fromhex("02000000000000000000000000000000")
    assert mulX_POLYVAL(bytes.fromhex("9c98c04df9387ded828175a92ba652d8")) == \
        bytes.fromhex("3931819bf271fada0503eb52574ca572")
    inv_x = gf_mul(X_INV128, reduce(1 << 127))  # x^-1 = x^-128 * x^127
    assert gf_mul(inv_x, 2) == 1
    ident = 1
    for k in (1, 2, 7):
        v = 1
        for _ in range(k):
            v = gf_mul(v, inv_x)
        ident ^= v
    assert ident == X_INV128, "RFC identity x^-128 = 1 + x^-1 + x^-2 + x^-7 failed"
    log.append("RFC 8452 Appendix A POLYVAL + mulX_POLYVAL + x^-128 identity: OK")

    n = 0
    for key, nonce, pt, aad, exp in RFC_C2_VECTORS:
        ct, tag = gcmsiv_encrypt(bytes.fromhex(key), bytes.fromhex(nonce),
                                 bytes.fromhex(pt), bytes.fromhex(aad))
        assert (ct + tag).hex() == exp, (pt, aad, (ct + tag).hex(), exp)
        n += 1
    log.append(f"RFC 8452 C.2 AES-256 vectors ({n}, incl. AAD, 16-byte PT and #17): OK")

    # dot() vs the GHASH relation from RFC 8452 Appendix A:
    # POLYVAL(H, X) == byteswap(GHASH(mulX_GHASH(byteswap(H)), byteswap(X)))
    rng = random.Random(0x8452)

    def ghash_mul(a, b):
        R = 0xE1 << 120
        z, v = 0, a
        for i in range(128):
            if (b >> (127 - i)) & 1:
                z ^= v
            v = (v >> 1) ^ (R if v & 1 else 0)
        return z

    for _ in range(100):
        H, X, Y = rng.randbytes(16), rng.randbytes(16), rng.randbytes(16)
        hg = int.from_bytes(H[::-1], "big")
        hg = (hg >> 1) ^ ((0xE1 << 120) if hg & 1 else 0)
        s = 0
        for blk in (X[::-1], Y[::-1]):
            s = ghash_mul(s ^ int.from_bytes(blk, "big"), hg)
        assert s.to_bytes(16, "big")[::-1] == polyval(H, X + Y)
    log.append("dot() vs GHASH relation (RFC 8452 App. A, 100 random 2-block msgs): OK")

    # Optional hazmat cross-checks
    if HAZMAT_AVAILABLE:
        for _ in range(50):
            k, b = rng.randbytes(32), rng.randbytes(16)
            assert aes_ecb(k, b) == hazmat_aes_ecb(k, b)
        log.append("pure-Python AES-256 vs hazmat AES-ECB (50 random blocks): OK")
    else:
        skipped.append(f"hazmat AES-ECB cross-check SKIPPED: {HAZMAT_SKIP_REASON}")
    if HAZMAT_GCMSIV_AVAILABLE:
        m = 0
        for _ in range(100):
            key, nonce = rng.randbytes(32), rng.randbytes(12)
            pt = rng.randbytes(rng.randint(1, 300))
            aad = rng.randbytes(rng.choice([0, 0, 1, 17, 40]))
            ext = AESGCMSIV(key).encrypt(nonce, pt, aad or None)
            ct, tag = gcmsiv_encrypt(key, nonce, pt, aad)
            assert ct + tag == ext
            assert AESGCMSIV(key).decrypt(nonce, ct + tag, aad or None) == pt
            m += 1
        log.append(f"hazmat AESGCMSIV random cross-check ({m} cases, PT 1..300 B, AAD 0..40 B): OK")
    else:
        skipped.append(f"hazmat AESGCMSIV cross-check SKIPPED: {HAZMAT_SKIP_REASON}")
    return log, skipped


SELFCHECK_LOG, SELFCHECK_SKIPPED = _selfcheck()

if __name__ == "__main__":
    for line in SELFCHECK_LOG:
        print("  " + line)
    for line in SELFCHECK_SKIPPED:
        print("  " + line)
    print(f"hazmat_oracle: {len(SELFCHECK_LOG)} self-checks OK, "
          f"{len(SELFCHECK_SKIPPED)} skipped")
