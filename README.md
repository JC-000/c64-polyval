# c64-polyval

POLYVAL (RFC 8452 §3) and AES-256-GCM-SIV authenticated encryption for the
Commodore 64. Hand-optimized 6502 assembly built with the ca65/ld65 toolchain,
shipped with two interchangeable POLYVAL profiles — a low-memory SHORT
build for short-message workloads (per-message H derivation) and a
high-throughput LONG build for session-stable H (TLS 1.3, WireGuard).

## Features

- POLYVAL GF(2^128) universal hash, byte-accurate against RFC 8452 test
  vectors. Two interchangeable multiply back-ends (SHORT / LONG).
- AES-256 ECB encrypt and decrypt, plus key expansion (T-table-free).
- AES-256-GCM-SIV AEAD (RFC 8452), up to 64 B plaintext per call, empty
  AAD only.
- Single stable public ABI across both POLYVAL profiles — consumers swap
  one for the other without source changes.
- `make consumer-check` link gate that assembles `test/consumer_stub.s`
  against the public headers and links it against the library, catching
  ABI drift before a release.
- Reproducible source-tarball release format via `make dist`.

## Requirements

- [cc65](https://cc65.github.io/) toolchain (ca65 assembler + ld65 linker)
- [VICE](https://vice-emu.sourceforge.io/) emulator (for testing) with
  `x64sc`
- Python 3.10+ with
  [c64-test-harness](https://github.com/JC-000/c64-test-harness)

## Build

```bash
make                              # build build/polyval.prg (LONG profile, default)
make POLYVAL_PROFILE=short        # SHORT profile (low-memory, per-message H)
make POLYVAL_PROFILE=long         # LONG profile (high-throughput, stable H)
make lib                          # library-only verification link
make consumer-check               # assemble + link test/consumer_stub.s
make run                          # build then launch in VICE
make dist VERSION=v0.2.0          # reproducible source tarball
make clean                        # rm -rf build/
```

The Makefile maps `POLYVAL_PROFILE=short|long` to ca65's
`-D POLYVAL_PROFILE=1|2` and to `polyval_short.o` / `polyval_long.o`
at link time.

## Test

```bash
python3 tools/run_all_tests.py [--seed N] [--iterations N] [--verbose]
```

Runs both the `test_polyval_direct.py` regression suite (217 tests,
direct `jsr()` against every POLYVAL routine) and the
`test_gcmsiv_polyval.py` end-to-end suite (~15 tests, RFC 8452 C.2
vectors + tampered-tag detection + random roundtrips) in parallel
under two VICE instances.

Individual suites can be run directly:

```bash
python3 tools/test_polyval_direct.py      # POLYVAL unit tests
python3 tools/test_gcmsiv_polyval.py      # AES-256-GCM-SIV end-to-end
python3 tools/benchmark_polyval.py        # CIA-timer cycle benchmarks
python3 tools/polyval_reference.py        # Python reference self-test (no VICE)
```

## API

See [`API.md`](API.md) for the complete integration reference:
public symbols and contracts, profile selection, zero-page layout,
calling conventions, known limitations, build integration, and the
canonical LIBRARY-vs-DEMO-APP file inventory consumers must follow
when linking.

A worked example for downstream consumers (`c64-wireguard`,
`c64-https`, ...) lives at [`test/consumer_stub.s`](test/consumer_stub.s):
it includes the public headers (`constants_lib.inc`,
`polyval_api.inc`, `exports.inc`), imports a representative slice of
the ABI, and `jsr`s each entry point. `make consumer-check` is the
gate that proves the public surface is stable for external use.

## Profiles

| Profile | multiply | precompute | tables | picks when |
|---|---:|---:|---:|---|
| SHORT | ~18,770 cy | ~29,385 cy | ~256 B | H rederived per message (RFC 8452 GCM-SIV) |
| LONG  | ~3,915 cy  | ~255,263 cy | ~8.5 KB | H stable across many blocks (TLS 1.3, WireGuard) |

Both profiles export an identical set of public symbols. The
practical crossover where LONG starts winning consistently is around
68 blocks (~1 KB of plaintext per message). Below that, SHORT hashes
a full message faster despite its slower per-block inner loop; above
that, LONG pulls ahead. See `API.md` §3 for the full discussion and
the math.

## Release

`make dist VERSION=v0.2.0` produces a reproducible source tarball
`c64-polyval-v0.2.0.tar.gz` rooted at the named git tag. Tagged
releases are published at
https://github.com/JC-000/c64-polyval/releases; consumers should pin
to a specific `vX.Y.Z` tag (typically as a git submodule) and consult
[`CHANGELOG.md`](CHANGELOG.md) before bumping.

## License

MIT. See [`LICENSE`](LICENSE).

## History

The v0.1.0 release shipped a `.lib`-archive distribution format under
`ca65/release/v0.1.0/` (two `ar65` archives `polyval_long.lib` /
`polyval_short.lib`, a stable `abi_v1.inc` header, attestation
results, and a canonical consumer example). That tree is preserved
verbatim in this repository for reproducibility of the prior
release, but new consumers should integrate against the v0.2.0
source-tarball format described in `API.md` §8 instead — the
`exports.inc` ABI header has superseded `abi_v1.inc`, and the
top-level `Makefile` has replaced the dual root + `ca65/` build
trees.
