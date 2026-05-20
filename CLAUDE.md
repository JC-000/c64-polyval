# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# c64-polyval

## Project overview
POLYVAL (RFC 8452 GF(2^128) universal hash) plus AES-256-GCM-SIV authenticated
encryption, optimized for the Commodore 64 (6502 @ 1 MHz). Long-term goal:
fold into `c64-aes256-ecdsa` and serve as a primitive for `c64-wireguard` and
`c64-https`.

Companion docs (read alongside this file):
- `README.md` — user-facing overview + build flow.
- `API.md` — library API reference; §3 (profile selection), §4 (ZP layout),
  §7–§8 (consumer integration), §9 (c64-lib-contract surface) are load-bearing.
- `CHANGELOG.md` — release history.
- `docs/RELEASE_NOTES_v0.3.0.md` — current release attestation (size + SHA256).

## c64-lib-contract adoption (v0.3.0)
This library implements the [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
SPEC v0.1.0, all six sections:
- §1 `LIB_VERSION_*` + `LIB_ABI_VERSION` — `src/lib_version.s`
- §2 `.exportzp` ZP slot inventory — `src/zp_config.s`
- §3 REU — n/a (c64-polyval makes no REU claims)
- §4 `LIB_POLYVAL_*` segment naming — every `src/*.s`; `src/c64.cfg` and
  `src/lib_only.cfg` SEGMENTS{} alias every prefixed segment back to MAIN
  so the standalone PRG layout is byte-identical to the pre-rename baseline
- §5 aggregate manifest equates (`LIB_POLYVAL_ZP_USAGE_BYTES`, `_REU_BANKS_USED`,
  `_RESIDENT_BYTES`, `_COLD_BYTES`) — `src/lib_manifest.s`, profile-conditional
- §6 ar65 archive build targets — `make lib` / `lib-polyval-{long,short,gcmsiv}`

ZP slots are lowercase with `polyval_` / `pv_` library prefix
(`polyval_acc`, `pv_mul_input`, `polyval_zp_ptr`, `polyval_aes_round`, ...).
Pre-v0.3.0 shared `zp_*` names were renamed; consumers vendoring the
library MUST update their `.importzp` lists.

## Build
```
make                                  # build/polyval.prg (LONG profile, default)
make POLYVAL_PROFILE=short            # SHORT profile
make lib                              # build/lib/polyval.a (full ar65 archive — SPEC §6)
make lib-polyval-long                 # build/lib/polyval-long.a (LONG only, no AES/GCM-SIV)
make lib-polyval-short                # build/lib/polyval-short.a (SHORT only)
make lib-polyval-gcmsiv               # build/lib/polyval-gcmsiv.a (full AEAD bundle)
make lib-verify                       # library-only verification PRG at $4000 (pre-v0.3.0 `make lib`)
make consumer-check                   # link test/consumer_stub.s against the library
make dist VERSION=v0.3.0              # reproducible source-tarball release
```
Assembler: ca65/ld65/ar65 (cc65 toolchain). Single canonical toolchain as of
v0.2.0 — ACME support was retired. `src/` is flat (no `lib/` subdir); ld65
configs live at `src/c64.cfg` (full app) and `src/lib_only.cfg` (library-only).

**Profile-switch gotcha:** `data.o` and `lib_manifest.o` contents are conditional
on `POLYVAL_PROFILE`. Make's pattern rule doesn't track that as a dependency,
so always `make clean` between profile switches; the lib-polyval-{long,short}
archive targets do this automatically via recursive make.

`make dist` produces `c64-polyval-vX.Y.Z.tar.gz` at repo root. The tarball
ships only `src/`, root docs, and `docs/RELEASE_NOTES_*`; it intentionally
omits `tools/`, `test/`, `build/`, and `ca65/`.

## Profile choice
LONG: ~3.9k cy multiply, ~255k cy precompute, larger BSS. Best for
long-message / stable-H workloads.
SHORT: ~18.8k cy multiply, ~29k cy precompute, smaller BSS. Best for
RFC 8452 GCM-SIV's per-message H. Crossover ≈ 68 blocks / ~1 KB.

## Test
```
python3.13 tools/run_all_tests.py --seed 8452
python3.13 tools/test_polyval_direct.py [--seed N] [--iterations N]
python3.13 tools/test_gcmsiv_polyval.py [--seed N|random] [--iterations N]
```
**Use `python3.13` explicitly** — system `python3` is 3.9 on this machine,
and `c64-test-harness` requires 3.10+. Tests need `x64sc` (VICE) on PATH and
the `c64-test-harness` Python package installed.

Expected: 376/376 pass, 6 skip (RFC 8452 vectors with non-empty AAD —
GCM-SIV intentionally does not support AAD; see API.md §6).

## VICE process hygiene — read this before touching any test infra

**NEVER use `pkill -f x64sc`, `pkill -f vice`, `killall x64sc`, or any
broad-pattern process kill** when cleaning up test VICE instances.

**Why this matters:** other Claude sessions and human developers can be
running their own test VICE instances on the same machine — `c64-nist-curves`,
`c64-wireguard`, `c64-https`, `c64-ChaCha20-Poly1305`, `c64-sid-instruments`,
and `c64-test-harness` itself all spawn `x64sc`. `pkill -f` matches by
command-line substring, so it kills *every* matching process system-wide.
The victim agent then sees mysterious test failures and may waste hours
chasing bugs that don't exist in their code or in VICE.

**How to clean up correctly:**
- `c64-test-harness`'s `UnifiedManager` / `ViceInstanceManager` owns VICE
  lifecycle. Use it. Don't reach around it.
- If you spawn `x64sc` directly (rare; almost always wrong), keep the PID
  from the `subprocess.Popen` object and kill by PID, not by pattern.
- If you genuinely think a stale instance from a prior session needs
  cleanup, list with `pgrep -lf x64sc | head -20`, identify the specific
  PID(s) belonging to this session's working directory (check the
  `--moncommands` argument), and kill those PIDs explicitly. Better:
  leave them alone and let the user reap them.

This rule applies to all Claude sessions in this multi-project workspace.

## Layout (v0.3.0)
```
src/
  lib_version.s          # §1: LIB_VERSION_*/LIB_ABI_VERSION
  zp_config.s            # §2: .exportzp polyval_* / pv_* slots
  lib_manifest.s         # §5: LIB_POLYVAL_*_BYTES + REU_BANKS_USED
  constants_lib.inc      # AES sizes, profile selectors, .include "zp_config.s"
  polyval_long.s / polyval_short.s
  aes_encrypt.s / aes_decrypt.s / tables.s
  gcm_siv.s
  data.s                 # all BSS + page-aligned tables (segment-partitioned)
  lib_main.s             # make lib-verify entry stub
  c64.cfg / lib_only.cfg # ld65 cfgs with LIB_POLYVAL_* SEGMENTS aliases
  exports.inc            # human-readable cross-module symbol map (NOT an .include)
test/                    # consumer_stub.s (used by `make consumer-check`)
tools/                   # test runner, harness, build_release.sh, vectors/
docs/                    # RELEASE_NOTES_v*.md
ca65/release/v0.1.0/     # frozen historical artifact — DO NOT MODIFY
```

The `ca65/release/v0.1.0/` subtree ships the prior `.lib`-archive release
intact (MANIFEST.txt, attestation/, examples/, `abi_v1.inc`). It is preserved
as historical reference and must not be edited. The active ABI is now
`src/exports.inc` plus the contract files (`lib_version.s`, `zp_config.s`,
`lib_manifest.s`).

## Release flow
1. Bump `VERSION` and `CHANGELOG.md`.
2. Write `docs/RELEASE_NOTES_vX.Y.Z.md` (use the v0.2.0 file as a template).
3. `make clean && make dist VERSION=vX.Y.Z` — produces the tarball + stamps
   size/SHA256 into the release notes (two-pass).
4. Verify reproducibility: re-run `make dist`, SHA256 must be identical.
5. Tag `vX.Y.Z` on the commit that includes the tarball + stamped notes.
