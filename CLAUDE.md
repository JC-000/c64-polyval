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
- `docs/RELEASE_NOTES_v0.7.1.md` — current release attestation (size + SHA256).
- `docs/precalc-tables.md` — c64-lib-contract §8.0 precalc-table enumeration.

## c64-lib-contract adoption (current as of v0.7.1)
This library implements the [c64-lib-contract](https://github.com/JC-000/c64-lib-contract),
currently at SPEC v0.11.0 (normative surface: v0.7.0's prefixed exports,
v0.7.4's `: abs` pin on the macro's `_REGION`/`_SHARED` exports, v0.8.0's
§4 segment-placement declarations, v0.9.0's §6 build-and-consume
chapter — `CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES` forwarding — plus
the §2 ZP prefix registry, where `polyval_` and `pv_` are registered to
this library, and v0.10.0's §6.6 consumer footprint asserts — per-archive
safe-direction `RESIDENT`/`COLD` values, rounded UP to the next 256-byte
boundary, gated on `POLYVAL_PROFILE` × `LIB_POLYVAL_NO_AES`; v0.10.0's
§6.7 is N/A — all buffers segment-resident, no placement equates;
and v0.10.4's §6.3 member-set scoping — `POLYVAL_PROFILE` swaps an
archived object, so it is member-set-shaped and takes §6.1 targets
rather than §6.2 defines, which is why SHORT+AEAD gained
`lib-polyval-gcmsiv-short` (issue #40; the gap predated v0.10.4 —
§6.3 ¶1's existing MUST already covered it, v0.10.4 only removed the
¶2 ambiguity); and v0.10.5's §6.3 looks-reachable rule — a knob naming
an axis MUST select it (member selection *and* assembly configuration)
or reject loudly, satisfied by the `PIN_` table's parse-time assert on
every archive goal (polyval#40 is the SPEC's shape-2 motivating case).
v0.7.1–v0.7.3, v0.7.5, v0.8.1–v0.8.4, v0.8.6 and v0.9.2 are
doc-only, v0.8.5's §8 export discipline is N/A here; v0.10.6 enumerates
the §8.3 provider surface (`ct_mul_8x8`, the SMC operand pair,
`poly_prod_lo`/`_hi`) and requires deferral gates to leave `.import`s
behind — N/A, verified by grep: c64-polyval neither provides nor defers
any §8.1–§8.3 primitive, and has no deferral switch; v0.10.7 registers
`c64-mlkem` and states "no existing adopter is affected" — N/A;
v0.11.0 adds two **zero-consumer carve-outs**, both N/A here and both
worth recording because they are the clauses that would otherwise have
unlocked the deferred member-basename rename: §1 says a library
onboarding with no released consumers SHOULD NOT export the bare
`LIB_VERSION_*` forms at all, and §6.5 says such a library SHOULD be
"born prefixed" rather than waiting for MAJOR. c64-polyval qualifies
for neither — it is one of the four incumbents the v0.11.0 entry names
as unaffected, and its §6.5 scope test ("no tagged release that any
consumer pins") is now definitively failed: `c64-aes256-ecdsa` is a
declared consumer pinning a tag as of 2026-08-23. The §6.5 MAJOR
deferral for member basenames therefore stands, and members cannot
dual-name, so there is no transitional path short of v1.0.0).
§1–§6 (v0.1.0
baseline) shipped in v0.3.0; §8.0 (precalc-table
catch-loop, applies to every adopter regardless of §8.1–§8.3 applicability)
shipped in v0.4.0; the v0.7.0 prefixed-export surface (§1 `LIB_POLYVAL_VERSION_*`,
§8.4 `LIB_POLYVAL_PRECALC_*`, bare forms gated on `LIB_NO_BARE_EXPORTS`)
plus per-archive manifest accuracy (`POLYVAL_NO_AES`) shipped in v0.5.0
(issues #21–#23, PRs #24–#26):
- §1 `LIB_POLYVAL_VERSION_*` + `LIB_POLYVAL_ABI_VERSION` (v0.7.0
  prefixed form; deprecated bare `LIB_VERSION_*` aliases gated on
  `LIB_NO_BARE_EXPORTS`) — `src/lib_version.s`
- §2 `.exportzp` ZP slot inventory — `src/zp_config.s`
- §3 REU — n/a (c64-polyval makes no REU claims). Zero-REU /
  turbo-clean scaling is documented as an explicit contract feature
  (issue #19): no I/O on any path, both profiles scale with CPU clock,
  and any future REU-resident variant must be an optional profile,
  never the default — see API.md §9.3 and README "Turbo / accelerated
  hosts"
- §4 `LIB_POLYVAL_*` segment naming — every `src/*.s`; `src/c64.cfg` and
  `src/lib_only.cfg` SEGMENTS{} alias every prefixed segment back to MAIN
  so the standalone PRG layout is byte-identical to the pre-rename baseline
- §4 placement declarations (v0.8.0) — load-bearing cfg attributes declared
  as comments on the segment lines of both cfgs: `type = ro` on
  `LIB_POLYVAL_AES_RODATA` (correctness — 522 initialised bytes silently
  dropped under `type = bss`), `align = $100` on the three table segments
  (performance-only, honestly labelled — the library is not CT, API.md §6;
  ld65 emits no diagnostic when dropped since `data.s` has no `.align`) —
  see API.md §9.8
- §5 aggregate manifest equates (`LIB_POLYVAL_ZP_USAGE_BYTES`, `_REU_BANKS_USED`,
  `_RESIDENT_BYTES`, `_COLD_BYTES`) — `src/lib_manifest.s`; the byte counts
  are conditional on `POLYVAL_PROFILE` × `LIB_POLYVAL_NO_AES` and
  safe-direction per §6.6 (measured per archive, rounded UP to the next
  256-byte boundary — see API.md §9.4 for the four-configuration table)
- §6 ar65 archive build targets — `make lib` /
  `lib-polyval-{long,short,gcmsiv,gcmsiv-short}`
- §6.2 consumer-defines forwarding (v0.9.0) — `CONTRACT_DEFINES` (global)
  and `CONTRACT_ZP_DEFINES` (ZP slot overrides), both `?=` empty, appended
  to `CA65FLAGS`. Polyval-specific reading: the library has zero `.importzp`
  sites for its own slots (every TU bakes the equates via constants_lib.inc
  → zp_config.s `.ifndef` guards), so EVERY member TU is a ZP-defining TU
  and all-recipes delivery IS the SPEC's scoped delivery — a
  zp_config.o-only delivery would silently mismatch exported vs baked
  addresses. Values must be $-free (`0x` hex) — see API.md §9.5
- §6.4 per-variant manifests — already conformant (recursive clean builds
  under pinned `POLYVAL_PROFILE`/`POLYVAL_NO_AES`; rows gated on the same
  switches). §6.1/§6.5 notes: archive basenames already canonical;
  `lib-verify` grandfathered in the reserved `lib-*` namespace until next
  MAJOR; archive member basenames take a `polyval_` prefix at next MAJOR
  (recorded, not actioned)
- §8 shared primitives (§8.1–§8.3: `sqtab` / `reu_mul` / `ct_mul_8x8`) — n/a;
  GF(2^128) carry-less multiplication has no shared shape with the 8×8
  quarter-square-multiply libraries (`c64-nist-curves`, `c64-x25519`,
  `c64-ChaCha20-Poly1305`) that converged on that primitive
- §8.0 precalc-table enumeration (mandatory regardless of §8.1–§8.3) —
  `src/precalc_table.inc` (canonical macro) + `LIB_PRECALC_TABLE` invocations
  in `src/lib_manifest.s`; rationale in `docs/precalc-tables.md`

ZP slots are lowercase with `polyval_` / `pv_` library prefix
(`polyval_acc`, `pv_mul_input`, `polyval_zp_ptr`, `polyval_aes_round`, ...).
Pre-v0.3.0 shared `zp_*` names were renamed; consumers vendoring the
library MUST update their `.importzp` lists.

**When bumping `VERSION`, also check `src/lib_version.s`.** The v0.3.0 →
v0.4.0 release fixed a bug where `LIB_VERSION_MINOR`/`_PATCH` had drifted
from the `VERSION` file and stayed stale for an entire release cycle — the
release commit doesn't update `src/lib_version.s` automatically.

## Build
```
make                                  # build/polyval.prg (LONG profile, default)
make POLYVAL_PROFILE=short            # SHORT profile
make lib                              # build/lib/polyval.a (full ar65 archive — SPEC §6; LONG)
make lib-polyval-long                 # build/lib/polyval-long.a (LONG only, no AES/GCM-SIV)
make lib-polyval-short                # build/lib/polyval-short.a (SHORT only)
make lib-polyval-gcmsiv               # build/lib/polyval-gcmsiv.a (full AEAD bundle, LONG)
make lib-polyval-gcmsiv-short         # build/lib/polyval-gcmsiv-short.a (full AEAD, SHORT)
make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'   # §6.2 ZP slot override ($-free values only)
make lib CONTRACT_DEFINES='-D LIB_NO_BARE_EXPORTS=1' # §6.2 global defines (composing consumers)
make lib-verify                       # library-only verification PRG at $4000 (pre-v0.3.0 `make lib`)
make consumer-check                   # link test/consumer_stub.s against the library
make consumer-check-noaes             # link test/consumer_stub_noaes.s (owns its own
                                      #   aes_state/gcmsiv_tag) against polyval-long.a
                                      #   AND polyval-short.a — issue #47 regression guard
make dist VERSION=v0.7.1              # reproducible source-tarball release
```
Assembler: ca65/ld65/ar65 (cc65 toolchain). Single canonical toolchain as of
v0.2.0 — ACME support was retired. `src/` is flat (no `lib/` subdir); ld65
configs live at `src/c64.cfg` (full app) and `src/lib_only.cfg` (library-only).

**Profile is a member-set axis (SPEC v0.10.4 §6.3, issue #40).** `POLYVAL_PROFILE`
selects which multiply object is *archived*, so no `CONTRACT_DEFINES` `-D` can
reach it — every documented profile × variant pair needs its own §6.1 target.
`lib` / `lib-polyval-gcmsiv` name the LONG AEAD archive and do not clean first,
so they **reject** `POLYVAL_PROFILE=short` at parse time rather than reusing
objects assembled under the other profile; use `lib-polyval-gcmsiv-short`, which
cleans and pins like `lib-polyval-{long,short}`.

**Profile-switch gotcha:** `data.o` and `lib_manifest.o` contents are conditional
on `POLYVAL_PROFILE` (and `lib_manifest.o` additionally on `POLYVAL_NO_AES`,
which the lib-polyval-{long,short} targets set to suppress the AES manifest
rows the POLYVAL-only archives don't ship — issue #23). Make's pattern rule
doesn't track either as a dependency, so always `make clean` between profile
switches and after any lib-polyval-{long,short} build; those archive targets
clean before building via recursive make, but leave `-D LIB_POLYVAL_NO_AES=1`
objects in `build/` afterwards.

`make dist` produces `c64-polyval-vX.Y.Z.tar.gz` at repo root. The tarball
ships only `src/`, root docs, `docs/RELEASE_NOTES_*`, and
`docs/precalc-tables.md`; it intentionally omits `tools/`, `test/`, `build/`,
and `ca65/`. (`docs/precalc-tables.md` is staged by an explicit `cp` in
`tools/build_release.sh`, not a glob — a new `docs/*.md` file doesn't ship
automatically.)

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

## Layout (v0.7.1)
```
src/
  lib_version.s          # §1: LIB_VERSION_*/LIB_ABI_VERSION
  zp_config.s            # §2: .exportzp polyval_* / pv_* slots
  lib_manifest.s         # §5: LIB_POLYVAL_*_BYTES + REU_BANKS_USED; §8.0 LIB_PRECALC_TABLE invocations
  precalc_table.inc      # §8.0: canonical LIB_PRECALC_TABLE macro (copied verbatim)
  constants_lib.inc      # AES sizes, profile selectors, .include "zp_config.s"
  polyval_long.s / polyval_short.s
  aes_encrypt.s / aes_decrypt.s / tables.s
  gcm_siv.s
  data.s                 # all BSS + page-aligned tables (segment-partitioned)
  lib_main.s             # make lib-verify entry stub
  c64.cfg / lib_only.cfg # ld65 cfgs with LIB_POLYVAL_* SEGMENTS aliases
  exports.inc            # human-readable cross-module symbol map (NOT an .include)
test/                    # consumer_stub.s (`make consumer-check`)
                         # consumer_stub_noaes.s (`make consumer-check-noaes`,
                         #   issue #47 guard; NOT vendored into the tarball)
tools/                   # test runner, harness, build_release.sh, vectors/
docs/                    # RELEASE_NOTES_v*.md, precalc-tables.md
ca65/release/v0.1.0/     # frozen historical artifact — DO NOT MODIFY
```

The `ca65/release/v0.1.0/` subtree ships the prior `.lib`-archive release
intact (MANIFEST.txt, attestation/, examples/, `abi_v1.inc`). It is preserved
as historical reference and must not be edited. The active ABI is now
`src/exports.inc` plus the contract files (`lib_version.s`, `zp_config.s`,
`lib_manifest.s`).

## Release flow
0. **Release-PR review gate (fleet standing process, adopted after issue
   #37):** stage every release as a PR (version bumps + CHANGELOG +
   stamped notes + tarball) and WAIT for the review comment before
   tagging — do not tag directly on master. Two of this cycle's four
   fleet releases needed pre-tag amendments; tags are immutable here, so
   post-hoc fixes can only amend the release page. Release notes MUST
   state the byte-identity method (worktree-rebuild of the baseline tag,
   both profiles, hash pairs) whenever they claim binary identity, and
   MUST use absolute blob URLs (relative links 404 on release pages).
1. Bump `VERSION`, `CHANGELOG.md`, **and `LIB_POLYVAL_VERSION_MINOR`/`_PATCH`
   in `src/lib_version.s`** (the bare `LIB_VERSION_*` aliases follow
   automatically; the v0.3.0 release forgot this file entirely and it went
   unnoticed for a full release cycle — see `API.md` §9.1). Also check the
   value column of the §9.1 table in `API.md` — the v0.4.1 release bumped
   the file but left the table at PATCH 0.
2. Write `docs/RELEASE_NOTES_vX.Y.Z.md` (use the v0.7.1 file as a template).
   Release notes MUST state `RESIDENT`/`COLD` footprint values **per
   shipped archive** — as of v0.7.0 that is **five** rows, not four:
   `polyval.a`/`polyval-gcmsiv.a` (LONG AEAD), `polyval-gcmsiv-short.a`
   (SHORT AEAD), `polyval-long.a`, `polyval-short.a` — even when a value
   is unchanged, per c64-lib-contract §6.6 obligation 2: one tag carries
   a footprint pair per archive, so a single per-version delta is
   meaningless. Count the rows against the `lib-polyval-*` target list
   rather than against the previous release's table.
3. `make clean && make dist VERSION=vX.Y.Z` — produces the tarball + stamps
   size/SHA256 into the release notes (two-pass). **The stamper is
   fail-closed** (`tools/build_release.sh`): it aborts unless exactly one
   `SHA256`/`SIZE` placeholder remains after the reset. If it refuses, the
   notes contain a second hash or a literal placeholder token in prose —
   fix the notes, don't loosen the guard. Before v0.7.0 it silently
   stamped the tarball hash over the byte-identity receipt's PRG hashes.
4. Verify reproducibility: re-run `make dist`, SHA256 must be identical.
5. Tag `vX.Y.Z` on the commit that includes the tarball + stamped notes.
