# c64-polyval

POLYVAL (RFC 8452 §3) and AES-256-GCM-SIV authenticated encryption for the
Commodore 64. Hand-optimized 6502 assembly built with the ca65/ld65 toolchain,
shipped with three interchangeable POLYVAL profiles — a SHORT build for
short-message workloads (per-message H derivation), a high-throughput
LONG build for session-stable H (TLS 1.3, WireGuard), and a 325-byte
COMPACT build for consumers whose memory map, not their throughput,
decides the question.

## Features

- POLYVAL GF(2^128) universal hash, byte-accurate against RFC 8452 test
  vectors. Three interchangeable multiply back-ends (SHORT / LONG /
  COMPACT).
- AES-256 ECB encrypt and decrypt, plus key expansion (T-table-free).
- AES-256-GCM-SIV AEAD (RFC 8452), up to 64 B plaintext per call, empty
  AAD only.
- Single stable public ABI across all three POLYVAL profiles — same
  symbols, same register-preservation contracts, so consumers swap one
  for another without source changes.
- Zero-REU / zero-I/O: pure CPU + RAM on every path, so it runs
  unmodified on expansion-less machines and scales with CPU clock on
  turbo hosts (see "Turbo / accelerated hosts" below).
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
make POLYVAL_PROFILE=short        # SHORT profile (small tables, per-message H)
make POLYVAL_PROFILE=long         # LONG profile (high-throughput, stable H)
make POLYVAL_PROFILE=compact      # COMPACT profile (325 B of code)
make lib                          # build/lib/polyval.a (full ar65 archive, LONG AEAD)
make lib-polyval-gcmsiv           # build/lib/polyval-gcmsiv.a (full AEAD, LONG)
make lib-polyval-gcmsiv-short     # build/lib/polyval-gcmsiv-short.a (full AEAD, SHORT)
make lib-polyval-gcmsiv-compact   # build/lib/polyval-gcmsiv-compact.a (full AEAD, COMPACT)
make lib-polyval-long             # build/lib/polyval-long.a (POLYVAL only, LONG)
make lib-polyval-short            # build/lib/polyval-short.a (POLYVAL only, SHORT)
make lib-polyval-compact          # build/lib/polyval-compact.a (POLYVAL only, COMPACT)
make lib-verify                   # library-only verification link (pre-v0.3.0 `make lib`)
make consumer-check               # assemble + link test/consumer_stub.s
make run                          # build then launch in VICE
make dist VERSION=vX.Y.Z          # reproducible source tarball
make clean                        # rm -rf build/
```

The Makefile maps `POLYVAL_PROFILE=short|long|compact` to ca65's
`-D POLYVAL_PROFILE=1|2|3` and to `polyval_short.o` / `polyval_long.o`
/ `polyval_compact.o`
at link time.

Each release ships a stamped attestation in
`docs/RELEASE_NOTES_vX.Y.Z.md` (tarball size + SHA256, double-build
reproducible) and, when it claims binary identity with a prior tag,
the worktree-rebuild receipt: the baseline tag rebuilt in a separate
worktree, every profile the baseline shipped, hash pairs stated. Releases are staged as
PRs and reviewed before tagging (see `CLAUDE.md`, release flow).

## Test

```bash
python3.13 tools/run_all_tests.py [--seed N|random] [--iterations N] \
    [--fuzz-iterations N] [--profile long|short|compact|all] [--verbose]
```

For every profile (default: all three, ~3.5 minutes; `--profile short`
for one), the runner builds `make POLYVAL_PROFILE=<p>` and drives four
suites in parallel on three VICE instances:

- `test_polyval_direct.py` — 217 tests, direct `jsr()` against every
  POLYVAL routine;
- `test_gcmsiv_polyval.py` — 525 tests: the 11 RFC 8452 C.2 AES-256
  vectors carried in `tools/vectors/rfc8452_vectors.json` (6 skip by
  design — non-empty AAD is unsupported), every one of the 128 tag bits,
  136 ciphertext bits and 96 nonce bits flipped on one message with the
  `A=1` / wiped-`dec_buf` failure convention asserted, direct API
  coverage, and boundary + random-length round-trips;
- `test_gcmsiv_bounds.py` — 15 memory-safety regression tests for
  issues #69 and #70 (8 of them are RED until the fix merges — see
  `CLAUDE.md`);
- `test_hazmat_fuzz.py` — 496 differential checks against
  `tools/hazmat_oracle.py`, an independent RFC-8452-from-the-text oracle
  (schoolbook carry-less multiply, pure-Python AES-256) that is NOT
  derived from `polyval_reference.py`: adversarial H and message shapes
  up to 1 KiB, `polyval_multiply` edge operands, all-zero/all-FF
  keys and nonces at every length 0..64, key derivation, CTR counter
  wrap at every byte boundary, and an exhaustive single-bit forgery
  sweep. If the `cryptography` package is missing or its `AESGCMSIV`
  is unsupported, the fuzz suite's hazmat cross-checks are counted and
  printed as SKIPs and the pure-Python oracle still gates everything
  else.

Expected per profile: 1253/1253 pass, 6 skip (1245 pass, 8 fail until
the #69/#70 fix lands). `tools/reference_sanity.py` cross-validates the
Python reference against `cryptography.AESGCMSIV` once before the
profile loop.

Individual suites can be run directly (each builds the profile it is
given; `--seed random` samples and prints a fresh seed):

```bash
python3.13 tools/test_polyval_direct.py   # POLYVAL unit tests
python3.13 tools/test_gcmsiv_polyval.py   # AES-256-GCM-SIV end-to-end
python3.13 tools/test_gcmsiv_bounds.py    # #69/#70 regression tests
python3.13 tools/test_hazmat_fuzz.py      # differential fuzz vs hazmat_oracle.py
python3.13 tools/hazmat_oracle.py         # oracle self-check (no VICE)
python3.13 tools/benchmark_polyval.py     # CIA-timer cycle benchmarks
python3.13 tools/polyval_reference.py     # Python reference self-test (no VICE)
```

## Library contract

c64-polyval implements [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
(currently at SPEC v0.10.6) — see the
[SPEC](https://github.com/JC-000/c64-lib-contract/blob/main/SPEC.md)
and the
[adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
All sections that apply to a CPU-RAM-only crypto library with no
shared 8×8 quarter-square-multiply surface are covered:

- §1 — `LIB_POLYVAL_VERSION_MAJOR / _MINOR / _PATCH` and
  `LIB_POLYVAL_ABI_VERSION` exported from `src/lib_version.s`
  (SPEC v0.7.0 prefixed form), plus the deprecated bare
  `LIB_VERSION_*` aliases, gated on `LIB_NO_BARE_EXPORTS` until
  contract v1.0 removes them.
- §2 — every claimed zero-page slot declared in `src/zp_config.s`
  under the `polyval_*` prefix.
- §3 — N/A; c64-polyval makes no REU claims
  (`LIB_POLYVAL_REU_BANKS_USED = 0`).
- §4 — library `.segment` directives use the `LIB_POLYVAL_*`
  prefix; consumer ld65 configs can map them anywhere. Load-bearing
  placement attributes (SPEC v0.8.0) are declared as comments on the
  segment lines of `src/c64.cfg` / `src/lib_only.cfg`: `type = ro`
  on `LIB_POLYVAL_AES_RODATA` is correctness-critical (522
  initialised S-box/rcon bytes), `align = $100` on the three
  runtime-filled table segments is performance-only — see `API.md`
  §9.8.
- §5 — aggregate manifest equates (`LIB_POLYVAL_ZP_USAGE_BYTES`,
  `LIB_POLYVAL_RESIDENT_BYTES`, `LIB_POLYVAL_COLD_BYTES`,
  `LIB_POLYVAL_REU_BANKS_USED`) in `src/lib_manifest.s`. The two
  byte-count equates are per-archive and safe-direction per SPEC
  v0.10.0 §6.6: measured for each (profile × variant) archive and
  rounded UP to the next 256-byte boundary, so a consumer's
  `declared ≤ budget` assert implies `actual ≤ budget` — see
  `API.md` §9.4 for the per-archive value table. §6.7 (declared
  non-segment reservations) is N/A: every buffer is
  segment-resident, no placement equate reserves address space
  invisible to ld65 — see `API.md` §9.5.
- §6 — `make lib`, `make lib-polyval-{long,short,compact}`,
  `make lib-polyval-gcmsiv` and
  `make lib-polyval-gcmsiv-{short,compact}` produce
  ar65 archive bundles under
  `build/lib/` (canonical `polyval[-<variant>].a` basenames). Every
  documented profile × variant pair has its own target, per SPEC §6.3
  as clarified in v0.10.4/v0.10.5 — the profile selects an archived
  object, so it cannot ride a §6.2 define. Consumer
  defines reach every build per §6.2 via
  `CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES`, e.g.
  `make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'` — see
  `API.md` §9.5.
- §8 (shared primitives, §8.1–§8.3) — N/A; GF(2^128) carry-less
  multiplication shares no shape with the 8×8 quarter-square-multiply
  primitive the elliptic-curve / ChaCha20 libraries converged on.
- §8.0/§8.4 — precalculated-table enumeration (required of every
  adopter regardless of §8.1–§8.3 applicability): `src/precalc_table.inc`
  + `LIB_PRECALC_TABLE` invocations in `src/lib_manifest.s` with the
  v0.7.0 `"POLYVAL"` prefix argument, documented in
  [`docs/precalc-tables.md`](docs/precalc-tables.md). Manifest rows are
  gated so each §6 archive enumerates only the tables it actually
  ships.

See `API.md` §9 for the consumer-facing symbol surface and a worked
import example.

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

| Profile | multiply | precompute | code | tables | picks when |
|---|---:|---:|---:|---:|---|
| SHORT | 18,776 cy | 4,656 cy | 13,614 B | 256 B | H rederived per message (RFC 8452 GCM-SIV) |
| LONG  | 3,917 cy  | 255,268 cy | 4,160 B | 8,448 B | H stable across many blocks (TLS 1.3, WireGuard) |
| COMPACT | 49,657 cy | 10,970 cy | 325 B | 256 B | footprint decides the memory map |

All three profiles export an identical set of public symbols with
identical register-preservation contracts. The SHORT/LONG **crossover
is 17 blocks (272 bytes)** — measured end-to-end, precompute included:
at N=16 SHORT is ahead by 10,309 cy, at N=17 LONG is ahead by 4,806,
and LONG's margin only widens after that. Below 17 blocks SHORT hashes
a full message faster despite its slower per-block inner loop; at or
above it, LONG pulls ahead. See `API.md` §3 for the figures and the
derivation.

**Read the code column.** SHORT and LONG both trade *table* memory
for speed and assume code is cheap; on total footprint they are 13.6
KB and 12.3 KB respectively, and LONG is the smaller of the two.
COMPACT is a different axis: same mathematics and same 256-byte table
as SHORT with the unrolling rolled back into loops, 613 B of total
RAM, and strictly slower than SHORT at every message length. Pick it
when a 13 KB multiply would push your image into the `$A000-$BFFF`
BASIC ROM window — a memory-map decision whose failure mode is the
CPU executing ROM, not a link error. See issue
[#51](https://github.com/JC-000/c64-polyval/issues/51).

The profile is fixed when the archive is built — it selects which
multiply object is archived, so it cannot be changed by a consumer
`-D` define. Each profile has its own archive targets: `make lib` and
`make lib-polyval-gcmsiv` produce the LONG AEAD bundle,
`make lib-polyval-gcmsiv-short` the SHORT one,
`make lib-polyval-gcmsiv-compact` the COMPACT one, and
`make lib-polyval-{long,short,compact}` the POLYVAL-only trio. Pick
the target that matches the profile you want; see `API.md` §9.5.

## Turbo / accelerated hosts

c64-polyval never touches the REU, any I/O register, or the KERNAL —
every profile is pure CPU + RAM on every path
(`LIB_POLYVAL_REU_BANKS_USED = 0`). Two guarantees follow:

- Runs unmodified on expansion-less machines.
- Per-block cost **and** precompute scale ~linearly with CPU clock on
  accelerated hosts (Ultimate 64 / C64 Ultimate turbo, SuperCPU-class).
  There is no ~1 MHz-anchored wall-clock floor of the kind
  REU-DMA-bound hot paths hit, and the SHORT/LONG crossover
  (17 blocks) is clock-invariant.

See `API.md` §3 for the scaling discussion and §9.3 for the policy any
future REU-resident variant must follow (optional profile with a
manifest delta — never the default path).

## Release

`make dist VERSION=vX.Y.Z` produces a reproducible source tarball
`c64-polyval-vX.Y.Z.tar.gz` rooted at the named git tag. Tagged
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
