# c64-polyval

POLYVAL (GF(2^128) universal hash from RFC 8452) implementation for the Commodore 64, with full AES-256-GCM-SIV authenticated encryption.

## Overview

This project implements the POLYVAL universal hash function as specified in [RFC 8452](https://datatracker.ietf.org/doc/html/rfc8452), integrated into a complete AES-256-GCM-SIV encryption/decryption system for the C64.

## Library release v0.1.0 (ca65)

The library has been ported to the [cc65/ca65](https://cc65.github.io/) toolchain and published as a versioned, consumer-ready release for downstream projects (`c64-wireguard`, `c64-https`, etc.). The ca65 build lives under `ca65/`, the release artifacts under `ca65/release/v0.1.0/`:

- `polyval_long.lib`, `polyval_short.lib` — ar65 archives, pick one based on your message-length profile
- `include/abi_v1.inc` — stable public ABI (10 routines + data buffers + 2 ZP symbols)
- `include/test_probes.inc` — internal test-only surface (NOT stable, do not depend on)
- `examples/` — canonical consumer stub, ld65 config, Makefile template
- `attestation/` — test and benchmark results snapshot
- `README.md` + `MANIFEST.txt` — per-release version notes and file checksums

The ca65 port is opcode-exact against the original ACME build (zero real diffs across ~4500 bytes of crypto code, only 3-byte absolute-address operands differ due to relocation). `polyval_multiply` retains its cycle floor (3745 cy min / ~3917 cy median). See `ca65/release/v0.1.0/README.md` for the consumer-facing release notes.

The original ACME tree under `src/` remains in the repo for historical reference but is slated for removal once downstream projects complete their own ca65 ports. New consumers should target the ca65 library only.

**POLYVAL multiplication strategy:** Shoup 8-bit window. The hash key H is transformed to H' = H * x^{-128} via 128 right-shifts, then a page-aligned sliced `polyval_htable8` (16 pages × 256 bytes, one per output byte) and a paired `polyval_reduce8` carry-reduction table (16 pages) are precomputed from H'. Each 128-bit multiply processes 16 bytes of input using a single fused inner loop that combines shift-by-8, polynomial reduction, and htable XOR with no intermediate passes. An earlier 4-bit nibble variant (`polyval_xor_table_entry` + `polyval_htable`) is retained for reference and precompute bootstrap.

**Polynomial:** x^128 + x^127 + x^126 + x^121 + 1

## Building

### ca65 build (primary, recommended)

Requires the [cc65 toolchain](https://cc65.github.io/) (`ca65`, `ld65`, `ar65`).

```
cd ca65
make                           # assemble (defaults to POLYVAL_PROFILE=long)
make POLYVAL_PROFILE=short     # assemble with the low-latency SHORT profile
make POLYVAL_PROFILE=long      # assemble with the throughput LONG profile
make run                       # assemble and launch in VICE
make lib                       # library-only verification build
make consumer-check            # link the canonical consumer stub
make release                   # rebuild ca65/release/v0.1.0/ artifacts
make clean                     # remove build artifacts
```

### ACME build (legacy)

Requires the [ACME cross-assembler](https://sourceforge.net/projects/acme-crossass/). Kept in the repo root for historical reference and for the legacy `tools/` test harness path.

```
make                           # assemble (defaults to POLYVAL_PROFILE=long)
make POLYVAL_PROFILE=short     # low-latency SHORT profile
make POLYVAL_PROFILE=long      # throughput LONG profile
make run                       # assemble and launch in VICE
make clean                     # remove build artifacts
```

## Dual-path POLYVAL profiles

The assembler exposes a build-time `POLYVAL_PROFILE` selector that picks between two different multiply back-ends. Both profiles export the same public symbols, so applications can swap one for the other without source changes — only the `.prg` needs to be rebuilt.

**Why two profiles.** RFC 8452 AES-GCM-SIV derives the POLYVAL hash key H from a per-message nonce, so the `polyval_precompute_table` cost is paid once per message and dominates the total for short plaintexts. The LONG profile's Shoup-8 tables are much faster per block but ~8.7× more expensive to build than the SHORT profile's 4-bit tables, so for short GCM-SIV messages SHORT is a net win. In contrast, TLS 1.3 records and WireGuard sessions reuse a session-stable H across thousands of blocks, and there LONG dominates because the precompute cost amortizes away and what matters is cycles per block.

**When to use each.**

- **SHORT** — latency-critical short-message workloads. Best for RFC 8452 GCM-SIV with per-message H derivation. Wins below the crossover (~68 blocks / ~1 KB per message).
- **LONG** — throughput-critical long-message workloads. Best for session-stable-H protocols such as TLS 1.3 records or WireGuard data packets. Wins above the crossover.

**Performance comparison.**

| Profile | multiply | update (1 blk) | update (N≥4) | precompute | PRG size |
|---|---:|---:|---:|---:|---:|
| SHORT  | 18,770 | 18,846 | ~18,846 | 29,385  | ~10 KB |
| LONG   |  3,915 |  3,992 |  4,241  | 255,263 | ~20 KB |

**Crossover.** Total cost of hashing N blocks is approximately `precompute + N × update`. Solving 29,385 + 18,846·N = 255,263 + 4,241·N gives N ≈ 15.5 blocks for the SHORT/LONG crossover on precompute-included workloads — but once amortization kicks in, the practical crossover where LONG starts winning is around 68 blocks / 1 KB of plaintext per message. Below that, SHORT hashes a full message faster despite its slower per-block inner loop; above that, LONG pulls ahead and keeps pulling ahead.

**Stable public symbols.** Both profiles export an identical set of entry points: `polyval_init`, `polyval_multiply`, `polyval_update`, `polyval_precompute_table`, `polyval_xor_table_entry`, `polyval_shift_left_4`, `polyval_double`, `polyval_right_shift_1`, `polyval_htable`, and the table base for the active multiply back-end. Callers do not need to know which profile is loaded.

The Python test and benchmark scripts honour the same selector via an environment variable:

```bash
POLYVAL_PROFILE=short python3 tools/test_polyval_direct.py
POLYVAL_PROFILE=long  python3 tools/benchmark_polyval.py
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
  benchmark_polyval.py  # cycle-accurate CIA timer benchmarks
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
| `polyval_shift_left_4` | Left-shift 4 bits with reduction (4 inline doublings) |
| `polyval_precompute_table` | Build `polyval_htable` (4-bit) and Shoup `polyval_htable8` / `polyval_reduce8` (8-bit) tables from H |
| `polyval_xor_table_entry` | XOR one 4-bit `polyval_htable` entry into the accumulator |
| `polyval_multiply` | Shoup 8-bit window multiply (fused shift / reduce / xor inner loop) |
| `polyval_update` | Multiply-by-H with the input block XORed into the accumulator seed (single fused pass) |

**Performance optimization.** The sprint on `feature/polyval-speed-sprint` layered several transforms on top of the ZP accumulator baseline:

1. **Tier 1 unrolling** — `polyval_xor_table_entry`, all ZP 16-byte loops, and `polyval_multiply`'s nibble byte loop fully unrolled; `polyval_shift_left_4` inlined as 4 doublings.
2. **Page-aligned tables** — `polyval_htable` moved to a page boundary so nibble lookups never cross pages.
3. **Shoup 8-bit window** — `polyval_multiply` rewritten to consume one byte per iteration against sliced per-output-byte htable8 pages plus a carry reduction table.
4. **Fused inner loop** — the three-pass Shoup-8 shift / reduce / xor sequence was collapsed into a single pass (the biggest single win).
5. **ZP input + update fusion** — `pv_mul_input` moved to zero page at $20-$2F, and `polyval_update`'s block-XOR fused directly into the multiply seed, eliminating a separate XOR loop.

The 128-bit accumulator `polyval_acc` lives in zero page at $10-$1F. Tables are placed at fixed pages: `polyval_htable` at $2E00, sliced `polyval_htable8_s0..s15` at $2F00-$3EFF, `polyval_reduce8_s0..s15` at $3F00-$4EFF.

The dot product `dot(a, b) = a * b * x^{-128} mod p` is computed via the precomputed table built from H' = H * x^{-128}, so that `acc * H' = acc * H * x^{-128} = dot(acc, H)`.

**Public API (stable for backport).** The following symbols are considered stable and are the intended entry points when embedding POLYVAL elsewhere: `polyval_multiply`, `polyval_update`, `polyval_precompute_table`, `polyval_xor_table_entry`, `polyval_shift_left_4`, `polyval_double`, and the table symbols `polyval_htable`, `polyval_htable8`, `polyval_reduce8`.

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

**`test_polyval_direct.py`** (217 tests): regression suite for `polyval.asm`, designed for use during performance optimization. Tests every routine individually via direct `jsr()` calls — `polyval_init`, `polyval_double`, `polyval_right_shift_1`, `polyval_shift_left_4`, `polyval_xor_table_entry`, `polyval_precompute_table`, `polyval_multiply` (in isolation), `polyval_update`, full multi-block pipeline, and multiply-vs-dot-product consistency. Deterministic seed (8452) by default; includes transient VICE connection retry logic.

**`test_gcmsiv_polyval.py`** (~15 tests): verifies the full AES-256-GCM-SIV pipeline — RFC 8452 C.2 encrypt/decrypt vectors, tampered tag detection, and random roundtrip tests at boundary plaintext lengths (1-64 bytes), comparing C64 output against the Python reference. Includes transient VICE connection retry logic.

**`run_all_tests.py`**: parallel test runner that launches two VICE instances simultaneously via `ViceInstanceManager` and runs both suites concurrently using `ThreadPoolExecutor`. Builds once, shares labels, captures per-suite output cleanly, and prints a combined summary with wall-clock time.

## Benchmarks

Cycle-accurate measurements use CIA #1 Timer A (IRQs disabled via SEI for deterministic results). Routines that fit under 65535 cycles run under a "short" wrapper; longer ones (e.g. `polyval_precompute_table` and multi-block update sweeps) run under a 32-bit "long" wrapper that chains CIA Timer A into Timer B for a full 32-bit cycle counter. The benchmark also sweeps `polyval_update` over N = 1, 4, 16, 64, 256 blocks to expose per-block steady-state cost.

```bash
python3 tools/benchmark_polyval.py [--samples N] [--verbose]
```

| Routine | Cycles | Description |
|---|---:|---|
| `polyval_double` | 85 | Left-shift 128 bits + reduction |
| `polyval_shift_left_4` | 370 | Left-shift 4 bits (4 inline doublings) |
| `polyval_xor_table_entry` | 176 | XOR htable[nibble] into accumulator (4-bit path) |
| `polyval_precompute_table` | 255,205 | Build 4-bit htable + Shoup htable8 + reduce8 from H |
| `polyval_multiply` | 3,916 | Shoup 8-bit window multiply (fused inner loop) |
| `polyval_update` (single) | 3,992 | Fused block-XOR + multiply |
| `polyval_update` (N≥4) | 4,240 / block | Steady-state per-block cost (Horner batching) |

A full POLYVAL hash of N blocks costs approximately 255,205 + N × 4,240 cycles (precompute once, then one update per block).

**Optimization sprint summary (`feature/polyval-speed-sprint`).** Cumulative speedups over the ZP-accumulator baseline:

| Routine | Before | After | Speedup |
|---|---:|---:|---:|
| `polyval_multiply` | 25,945 | 3,916 | 6.63× |
| `polyval_update` (single) | 26,220 | 3,992 | 6.57× |
| `polyval_update` (N≥4) | ~26,220 | 4,240 | 6.18× |

PRG size grew from 8,154 to ~19,700 bytes, mostly from the two page-aligned Shoup tables.

## Status

The POLYVAL implementation and GCM-SIV integration are functionally complete. On both the ca65 and ACME builds, the full test suite passes at 217/217 POLYVAL direct tests + 159/165 GCM-SIV tests (6 intentional skips for AAD-bearing RFC 8452 C.2 vectors — the C64 implementation intentionally does not support AAD). All RFC 8452 C.2 encrypt/decrypt vectors with empty AAD pass on both builds.

The ca65 port has been audited against the ACME baseline with opcode-exact byte parity across all crypto routines and cycle-exact parity on `polyval_multiply`. The v0.1.0 library release (`ca65/release/v0.1.0/`) is the recommended consumption path for downstream projects.

The long-term goal is to merge this into [c64-aes256-ecdsa](https://github.com/JC-000/c64-aes256-ecdsa), replacing the simplified CBC-MAC with true POLYVAL.
