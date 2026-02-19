# c64-polyval

POLYVAL (GF(2^128) universal hash from RFC 8452) implementation for the Commodore 64, with full AES-256-GCM-SIV authenticated encryption.

## Overview

This project implements the POLYVAL universal hash function as specified in [RFC 8452](https://datatracker.ietf.org/doc/html/rfc8452), integrated into a complete AES-256-GCM-SIV encryption/decryption system for the C64.

**POLYVAL multiplication strategy:** 4-bit nibble table lookup with left-shift processing. The hash key H is transformed to H' = H * x^{-128} via 128 right-shifts, then a 256-byte table (16 entries of 16 bytes) is precomputed from H' using left-shift doubling. Each 128-bit multiply processes 32 nibbles with table lookups.

**Polynomial:** x^128 + x^127 + x^126 + x^121 + 1

## Building

Requires the [ACME cross-assembler](https://sourceforge.net/projects/acme-crossass/).

```
make        # assemble
make run    # assemble and launch in VICE
make clean  # remove build artifacts
```

## Project Structure

```
src/
  main.asm              # top-level include chain
  polyval.asm           # POLYVAL GF(2^128) universal hash
  gcm_siv.asm           # AES-256-GCM-SIV: key derivation, tag, CTR mode
  aes_encrypt.asm       # AES-256 encryption + key expansion
  aes_decrypt.asm       # AES-256 decryption
  constants.asm         # system equates, zero page, AES constants
  data.asm              # mutable buffers (key, AES state, POLYVAL, GCM-SIV)
  tables.asm            # S-box, inverse S-box, round constants
  boot.asm              # BASIC stub, initialization
  main_loop.asm         # menu UI
  display.asm           # hex display routines
  disk_io.asm           # file I/O helpers
  strings.asm           # UI message strings
build/                  # compiled output (gitignored)
tools/
  polyval_reference.py  # Python reference: POLYVAL + AES-256-GCM-SIV
  test_polyval_direct.py  # direct jsr() POLYVAL unit tests
  test_gcmsiv_polyval.py  # end-to-end GCM-SIV integration tests
  run_all_tests.py      # parallel runner for both test suites
test/
  rfc8452_vectors.json  # RFC 8452 Appendix A + C.2 test vectors
```

## POLYVAL Implementation

The core POLYVAL routines in `src/polyval.asm`:

| Routine | Description |
|---------|-------------|
| `polyval_init` | Zero the 128-bit accumulator |
| `polyval_double` | Left-shift 128 bits with reduction (x^128 mod p) |
| `polyval_right_shift_1` | Right-shift 128 bits with reduction (x^{-1} mod p) |
| `polyval_precompute_table` | Build htable[0..15] from H via H' = H * x^{-128} |
| `polyval_multiply` | 4-bit nibble table multiply (32 lookups per 128-bit multiply) |
| `polyval_update` | XOR block into accumulator, then multiply by H |

The dot product `dot(a, b) = a * b * x^{-128} mod p` is computed via the precomputed table built from H' = H * x^{-128}, so that `acc * H' = acc * H * x^{-128} = dot(acc, H)`.

## Testing

Tests require Python 3.10+, [VICE](https://vice-emu.sourceforge.io/) (x64sc), and the [`c64-test-harness`](https://github.com/JC-000/c64-test-harness) package.

```bash
# Run Python reference self-test (no VICE needed)
python3 tools/polyval_reference.py

# Run both test suites in parallel (recommended)
python3 tools/run_all_tests.py [--seed N] [--iterations N] [--verbose]

# Run POLYVAL regression tests (requires VICE) — 153+ tests, deterministic
python3 tools/test_polyval_direct.py [--seed N] [--iterations N] [--verbose]

# Run end-to-end GCM-SIV tests (requires VICE)
python3 tools/test_gcmsiv_polyval.py [--iterations 15] [--seed N]
```

**`test_polyval_direct.py`** (153 tests): regression suite for `polyval.asm`, designed for use during performance optimization. Tests every routine individually via direct `jsr()` calls — `polyval_init`, `polyval_double`, `polyval_right_shift_1`, `polyval_shift_left_4`, `polyval_xor_table_entry`, `polyval_precompute_table`, `polyval_multiply` (in isolation), `polyval_update`, full multi-block pipeline, and multiply-vs-dot-product consistency. Deterministic seed (8452) by default; includes transient VICE connection retry logic.

**`test_gcmsiv_polyval.py`** (~15 tests): verifies the full AES-256-GCM-SIV pipeline — RFC 8452 C.2 encrypt/decrypt vectors, tampered tag detection, and random roundtrip tests at boundary plaintext lengths (1-64 bytes), comparing C64 output against the Python reference. Includes transient VICE connection retry logic.

**`run_all_tests.py`**: parallel test runner that launches two VICE instances simultaneously via `ViceInstanceManager` and runs both suites concurrently using `ThreadPoolExecutor`. Builds once, shares labels, captures per-suite output cleanly, and prints a combined summary with wall-clock time.

## Status

The POLYVAL implementation and GCM-SIV integration are functionally complete, passing all 232 tests (217 POLYVAL + 15 GCM-SIV) including all RFC 8452 C.2 vectors for both encryption and decryption. The long-term goal is to merge this into [c64-aes256-ecdsa](https://github.com/JC-000/c64-aes256-ecdsa), replacing the simplified CBC-MAC with true POLYVAL.
