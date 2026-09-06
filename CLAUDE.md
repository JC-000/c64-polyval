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
- `docs/RELEASE_NOTES_v0.10.0.md` — current release attestation (size + SHA256).
- `docs/precalc-tables.md` — c64-lib-contract §8.0 precalc-table enumeration.

## c64-lib-contract adoption (current as of v0.10.0)
This library implements the [c64-lib-contract](https://github.com/JC-000/c64-lib-contract),
**SPEC v1.1.0** (tagged 2026-09-03). Re-check the tag before trusting this
line — that repo has historically shipped several releases a day.

**Contract v1.0.0 cut the spec by roughly seven eighths** (40,737 words →
5,154). No symbol, equate, bit value, segment name or build target changed,
so conformance carried over without edits. What went was rationale, incident
history and process regulation, under a two-prong scope rule now stated in
the document itself: a clause belongs there only if it governs (1) a name,
value or placement two independently-built artifacts must agree on, where
(2) a violation is invisible from inside any single repository's own build.
**Retired: §9, §12, §13, §14, §15 and sub-clauses §6.3, §6.6, §6.7.**
Surviving sections kept their numbers, so old citations still resolve; the
retired text lives permanently at `git show v0.17.1:SPEC.md`. v1.1.0 then
added one normative paragraph to §7 (below).

**Do not go through this repo rewriting retired-section citations.** The
contract's own `RETIRED.md` asks adopters not to: a citation is a claim
about the tag it was made against, and it still resolves. `CHANGELOG.md`,
`docs/RELEASE_NOTES_v0.*.md` and the in-line `§6.6` comments in
`src/lib_manifest.s` are left exactly as written on purpose. What v0.10.0
*did* change is only text that had become **false going forward** — chiefly
"removed at contract v1.0" for the bare exports, which v1.0.0 explicitly
deferred to a future MAJOR.

Where the three retired clauses this library had implemented now stand:

| Retired | Status here |
|---|---|
| **§6.3** reachability / looks-reachable | Obligation gone. The `PIN_` parse-time goal table and the `build/.ca65flags` stamp are **kept as local engineering** — they are good properties for this Makefile regardless. `tools/check_knob_staleness.sh` still runs on `lib-verify`. Do not remove them, and do not grow them further to satisfy a clause that no longer exists. |
| **§6.6** consumer footprint asserts | Library-side half moved into **§5**, which now states safe-direction round-up and the RESIDENT/COLD pair directly. Nothing about `src/lib_manifest.s` changes. The consumer-side snippet was only ever RECOMMENDED. |
| **§6.7** non-segment reservations | N/A before and after — every buffer is segment-resident. |

Section-by-section status (see `API.md` §9 for the full account):
- §1 `LIB_POLYVAL_VERSION_*` + `LIB_POLYVAL_ABI_VERSION`, `: abs`, TU
  isolation, bare `LIB_VERSION_*` aliases gated on `LIB_NO_BARE_EXPORTS`
  — `src/lib_version.s`. The bare forms' removal was scheduled for contract
  v1.0 and **deferred there to a future MAJOR**; the §1 zero-consumer
  carve-out does not apply (this library has a tag-pinning consumer,
  `c64-aes256-ecdsa`).
- §2 `.exportzp` slot inventory — `src/zp_config.s`; `polyval_` and `pv_`
  are registered to this library in the §2 ZP prefix registry.
- §3 REU — **N/A**, no REU claims. Zero-REU / turbo-clean scaling is an
  explicit contract feature (issue #19): no I/O on any path, all three
  profiles scale with CPU clock, and any future REU-resident variant must
  be an optional profile, never the default — API.md §9.3, README
  "Turbo / accelerated hosts".
- §4 `LIB_POLYVAL_*` segment naming plus the load-bearing cfg attribute
  declarations — every `src/*.s`; `src/c64.cfg` and `src/lib_only.cfg`
  alias every prefixed segment back to MAIN. The declarations are
  `type = ro` on `LIB_POLYVAL_AES_RODATA` (correctness — 522 initialised
  bytes silently dropped under `type = bss`) and `align = $100` on the
  three table segments (performance only, honestly labelled — the library
  is not constant-time, API.md §6). API.md §9.8.
- §5 aggregate manifest equates + the published input bound — `src/lib_manifest.s`.
  Footprints are safe-direction, measured per archive, rounded UP to the
  next 256-byte boundary, gated on `POLYVAL_PROFILE` × `LIB_POLYVAL_NO_AES`
  (API.md §9.4). **`LIB_POLYVAL_GCMSIV_MAX_PT_LEN = 64` is new in v0.10.0**:
  §5 says a real input ceiling SHOULD be published here as a symbol the
  consumer can reference, and until v0.10.0 the bound existed only as
  `gcmsiv_max_pt_len` in `src/constants_lib.inc` — invisible to a consumer
  who links the archive instead of vendoring our source. It is deliberately
  **not** `.ifndef`-guarded (it is derived from the value `gcm_siv.s`
  actually compares against, so a `-D` override must collide loudly rather
  than export a ceiling the code does not enforce) and is absent from the
  `LIB_POLYVAL_NO_AES` archives, which ship no `gcm_siv.o`.
- §6.1 `make lib` + the six `lib-polyval-*` archive targets. **Every one of
  them now also stages `build/lib/polyval.inc` and
  `build/lib/polyval-example.cfg`** — §6.1 requires the archive "plus the
  consumer-facing `.inc` header and an example `.cfg`", and through v0.9.0
  `build/lib/` held the `.a` alone, so a consumer had to read `src/` to
  link us. Added in v0.10.0; both are §6.5 name surface from that release.
  The cfg is `src/polyval-example.cfg`, maintained **only** for shipping —
  do not point this at `src/lib_only.cfg`, which carries `lib-verify`
  scaffolding (a mandatory `LOADADDR` segment, `LIB_POLYVAL_VERIFY_CODE`)
  and makes a consumer's first link emit
  `ld65: Warning: Segment 'LOADADDR' does not exist`. That was tried and
  reverted. `make consumer-check-shipped` is the guard: it assembles a stub
  against the three shipped files in an empty directory **with no
  `-I src`**, which is the only way this repo can detect an incomplete
  shipped surface — every other build has `src/` on the include path.
- §6.2 `CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES`, both `?=` empty, appended
  to `CA65FLAGS`. Polyval-specific reading: the library has zero
  `.importzp` sites for its own slots (every TU bakes the equates via
  `constants_lib.inc` → `zp_config.s` `.ifndef` guards), so EVERY member TU
  is a ZP-defining TU and all-recipes delivery IS the SPEC's scoped
  delivery — a `zp_config.o`-only delivery would silently mismatch exported
  against baked addresses. Values must be `$`-free (`0x` hex). API.md §9.5.
- §6.4 per-archive manifests — conformant; recursive clean builds under
  pinned `POLYVAL_PROFILE` / `POLYVAL_NO_AES`, rows gated on the same
  switches.
- §6.5 name surface — archive basenames already canonical. Two recorded
  future-MAJOR items, neither actionable now: `lib-verify` is grandfathered
  in the reserved `lib-*` namespace, and archive **member** basenames take
  a `polyval_` prefix at the next MAJOR. Members cannot dual-name, so there
  is no transitional path; v0.11.0's §6.5 zero-consumer carve-out does not
  reach us (`c64-aes256-ecdsa` pins a tag).
- §7 semver + ABI counter. **v1.1.0 added the load-bearing paragraph**: the
  counter moves on what the code does, not on whether the export list
  changed — it moves when a consumer conforming to the *previously
  documented* contract can be broken, typically an entry point's return set
  gaining a value; it **holds** when previously undocumented behaviour
  becomes documented, and when docs are corrected over unchanged code.
  `LIB_POLYVAL_ABI_VERSION` stays **1** through v0.10.0; see the
  "ABI counter" note below.
- §8.1–§8.3 shared primitives — **N/A**. GF(2^128) carry-less multiplication
  has no shared shape with the 8×8 quarter-square-multiply primitive
  (`sqtab` / `reu_mul` / `ct_mul_8x8`) that `c64-nist-curves`, `c64-x25519`
  and `c64-ChaCha20-Poly1305` converged on. This library neither provides
  nor defers any of them and has no deferral switch, so §8.0's mask
  obligations and v0.10.6's provider-surface rule are both N/A.
- §8.4 precalc-table enumeration (applies regardless of §8.1–§8.3) —
  `src/precalc_table.inc` (canonical macro, copied verbatim; refreshed
  from the v1.1.0 canonical in v0.10.0, comment-only) + `LIB_PRECALC_TABLE`
  invocations in `src/lib_manifest.s`; rationale in `docs/precalc-tables.md`.
  The §8.4 zero-consumer carve-out does not apply (tag-pinning consumer),
  so the bare `LIB_PRECALC_<name>_*` triple keeps shipping gated on
  `LIB_NO_BARE_EXPORTS`.

**ABI counter — assessed at v0.10.0, holds at 1.** v0.9.0 gave
`gcmsiv_encrypt` and `gcmsiv_decrypt` a length-rejection return
(`A=1` / `Z=0` above `gcmsiv_max_pt_len`), which is superficially the shape
v1.1.0 §7 says moves the counter. It does not, for each entry point for a
different reason, and the reasoning is worth keeping because the next
domain guard will raise it again:
- `gcmsiv_encrypt` documented `A, X, Y undefined` on exit at v0.8.0 — **no**
  return convention at all. A consumer conforming to that could not have
  been reading `A`. This is §7's "behaviour that was previously
  undocumented becomes documented", the same shape as `c64-nist-curves`
  holding at 2 for v0.12.0.
- `gcmsiv_decrypt` did have an exhaustive documented return set
  (`A=0` valid / `A=1` invalid) — but the reject path was written to be
  **indistinguishable from a tag failure on every documented
  post-condition**: `gcmsiv_dec_buf` wiped, `gcmsiv_tag_valid` cleared,
  `gcmsiv_tag` left as received. The return set did not gain a value and
  exhaustive handling did not become non-exhaustive, so a v0.8.0-conforming
  consumer cannot be broken by it.

That second bullet is a property of `src/gcm_siv.s`'s `@reject_len` path,
not a general fact — **if that path is ever changed to be distinguishable
from a tag failure, the counter moves.** Arbitration was requested upstream
so this reading is on the record rather than only in this file.

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
make lib-polyval-compact              # build/lib/polyval-compact.a (COMPACT only)
make lib-polyval-gcmsiv-compact       # build/lib/polyval-gcmsiv-compact.a (full AEAD, COMPACT)
make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'   # §6.2 ZP slot override ($-free values only)
make lib CONTRACT_DEFINES='-D LIB_NO_BARE_EXPORTS=1' # §6.2 global defines (composing consumers)
make lib-verify                       # library-only verification PRG at $4000 (pre-v0.3.0 `make lib`)
make consumer-check                   # link test/consumer_stub.s against the library
make consumer-check-shipped           # §6.1 guard: assemble+link using ONLY the three
                                      #   shipped files (polyval.a / polyval.inc /
                                      #   polyval-example.cfg) in an empty dir with no
                                      #   -I src — issue #79 regression guard
make consumer-check-noaes             # link test/consumer_stub_noaes.s (owns its own
                                      #   aes_state/gcmsiv_tag) against polyval-long.a,
                                      #   polyval-short.a AND polyval-compact.a —
                                      #   issue #47 regression guard
make dist VERSION=v0.8.0              # reproducible source-tarball release
```
Assembler: ca65/ld65/ar65 (cc65 toolchain). Single canonical toolchain as of
v0.2.0 — ACME support was retired. `src/` is flat (no `lib/` subdir); ld65
configs live at `src/c64.cfg` (full app) and `src/lib_only.cfg` (library-only).

**Profile is a member-set axis (SPEC v0.10.4 §6.3, issue #40).** `POLYVAL_PROFILE`
selects which multiply object is *archived*, so no `CONTRACT_DEFINES` `-D` can
reach it — every documented profile × variant pair needs its own §6.1 target.
`lib` / `lib-polyval-gcmsiv` name the LONG AEAD archive and do not clean first,
so they **reject** `POLYVAL_PROFILE=short` / `=compact` at parse time rather than
reusing objects assembled under another profile; use
`lib-polyval-gcmsiv-{short,compact}`, which clean and pin like
`lib-polyval-{long,short,compact}`. Adding a profile is therefore a §6.1 change:
two targets, two `PIN_` rows, two `(profile × NO_AES)` manifest branches, two
footprint rows — the v0.7.0 shape, done again for COMPACT in v0.8.0 (issue #51).

**Flag-set staleness — handled since issue #58; the manual `make clean` between
profile switches is no longer required.** `data.o` and `lib_manifest.o` contents
are conditional on `POLYVAL_PROFILE` (and `lib_manifest.o` additionally on
`POLYVAL_NO_AES`, which the lib-polyval-{long,short} targets set to suppress the
AES manifest rows the POLYVAL-only archives don't ship — issue #23), and none of
those reach a make prerequisite. A **parse-time flag stamp** (`build/.ca65flags`)
now compares the effective `CA65FLAGS` against the previous invocation's and
deletes the stale objects/archives when they differ, so `make POLYVAL_PROFILE=short`
straight after `make` produces the SHORT PRG rather than a stale LONG one, and
`CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES` changes take effect on a warm tree.
Unchanged flags delete nothing, so incremental builds still short-circuit.

Two mechanisms were measured *failing* here before the parse-time one, and both
are worth knowing before anyone "simplifies" this:
- **Stamp as a rule prerequisite, compared by mtime** — macOS ships GNU Make
  3.81, which compares at 1-second granularity. The rewritten stamp is newer only
  in the sub-second digits, so a same-second rebuild is skipped entirely.
- **Stamp as a rule prerequisite that deletes** — make 3.81 stats a target before
  running its prerequisites' recipes and caches that result, so the delete is
  invisible for whichever object make considered first. Measured:
  `build/lib_version.o` deleted and then *not* rebuilt, silently dropping a member
  from the archive — worse than the staleness being fixed.

`make dist` produces `c64-polyval-vX.Y.Z.tar.gz` at repo root. The tarball
ships only `src/`, root docs, `docs/RELEASE_NOTES_*`, and
`docs/precalc-tables.md`; it intentionally omits `tools/`, `test/`, `build/`,
and `ca65/`. (`docs/precalc-tables.md` is staged by an explicit `cp` in
`tools/build_release.sh`, not a glob — a new `docs/*.md` file doesn't ship
automatically.)

## Profile choice
LONG: 3,917 cy multiply, 255,268 cy precompute, 4,160 B code + 8,448 B
tables. Best for long-message / stable-H workloads.
SHORT: 18,776 cy multiply, 4,656 cy precompute, 13,614 B code + 256 B
tables. Best for RFC 8452 GCM-SIV's per-message H. SHORT/LONG crossover
= 17 blocks (272 B), measured end-to-end, not the ~68 that stood in the
docs from v0.1.0 to v0.7.3 with no derivation.
COMPACT: 49,657 cy multiply, 10,970 cy precompute, 325 B code + 256 B
tables. Same 4-bit Shoup mathematics as SHORT, rolled. Strictly slower
than SHORT at every N — it is a footprint choice, not a speed/memory
trade-off, and exists because 13.6 KB of multiply can push a stock-C64
consumer's image into the $A000-$BFFF ROM window (issue #51).

All cycle figures above are `tools/benchmark_polyval.py` measurements
(`POLYVAL_BENCH_BLOCKS` overrides the multi-block sweep). **Two figures
here were stale from v0.1.0 through v0.7.3**, both corrected in v0.8.0:
SHORT's precompute (~29,385 → 4,656 cy, predating the switch from a
128-iteration mulX_POLYVAL loop to the 7-shift RFC 8452 identity), and
the "practical break-even ≈ 68 blocks", withdrawn — it had no derivation
and its own gloss contradicted it (1 KB is 64 blocks, not 68).

**Two rules from that pair.** Re-measure before quoting a cycle count.
And when correcting one figure, do not certify its neighbours as
unaffected without measuring them too: the v0.8.0 draft said the
68-block figure was "unaffected" by the precompute correction, which was
unfounded — a downward precompute correction pushes crossovers *later*.
Caught in review of PR #63 before tagging.

## Test
```
python3.13 tools/run_all_tests.py --seed 8452                 # all three profiles (~3.5 min)
python3.13 tools/run_all_tests.py --profile short             # one profile (~70 s)
python3.13 tools/run_all_tests.py --seed random --fuzz-iterations 20
python3.13 tools/test_polyval_direct.py [--seed N|random] [--iterations N]
python3.13 tools/test_gcmsiv_polyval.py [--seed N|random] [--iterations N]
python3.13 tools/test_gcmsiv_bounds.py  [--seed N|random] [--profile P]   # regression: #69, #70
python3.13 tools/test_hazmat_fuzz.py    [--seed N|random] [--iterations N] [--profile P]
python3.13 tools/hazmat_oracle.py                            # oracle self-check, no VICE
```
**Use `python3.13` explicitly** — system `python3` is 3.9 on this machine,
and `c64-test-harness` requires 3.10+. Tests need `x64sc` (VICE) on PATH and
the `c64-test-harness` Python package installed. `cryptography` is required
by the reference cross-check and the GCM-SIV suite; `test_hazmat_fuzz.py`
alone treats it as optional (its hazmat cross-checks become counted SKIPs).

The runner builds `make POLYVAL_PROFILE=<p>` for each profile (`--profile
{long,short,compact,all}`, default `all`; the parse-time flag stamp handles
staleness, no `make clean`), runs `cross_validate_reference()` once before
the loop, and drives four suites on three VICE instances per profile:
`test_polyval_direct.py` (217), `test_gcmsiv_polyval.py` (525 + 6 skip),
`test_gcmsiv_bounds.py` (15) and `test_hazmat_fuzz.py` (496 at the runner's
default `--fuzz-iterations 3`; 20 extra checks per iteration).

Expected, **per profile** (identical on LONG, SHORT and COMPACT, measured
2026-08-29 at seed 8452): **1253/1253 pass, 6 skip** once the fix for
issues #69/#70 has merged. The 6 skips are the RFC 8452 vectors with
non-empty AAD — GCM-SIV intentionally does not support AAD; see API.md §6.

**Until that fix PR merges, exactly 8 of the 15 `test_gcmsiv_bounds.py`
checks are RED on every profile by design** (1245 pass, 8 fail):
`gcmsiv_install_enc_key` / `gcmsiv_restore_orig_key` "leaves
aes_expanded_key+240..255 untouched" (issue #69, the 256-byte copy into the
240-byte schedule) and the six `gcmsiv_encrypt`/`gcmsiv_decrypt`
`pt_len=65` / `pt_len=128` checks (issue #70, no bounds check on
`gcmsiv_pt_len`). They are regression tests written RED first; do not
"fix" them by weakening the assertions.

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

## Layout (v0.10.0)
```
src/
  lib_version.s          # §1: LIB_VERSION_*/LIB_ABI_VERSION
  zp_config.s            # §2: .exportzp polyval_* / pv_* slots
  lib_manifest.s         # §5: LIB_POLYVAL_*_BYTES + REU_BANKS_USED +
                         #     LIB_POLYVAL_GCMSIV_MAX_PT_LEN (published
                         #     input bound); §8.4 LIB_PRECALC_TABLE invocations
  precalc_table.inc      # §8.0: canonical LIB_PRECALC_TABLE macro (copied verbatim)
  constants_lib.inc      # AES sizes, profile selectors, .include "zp_config.s"
  polyval_long.s / polyval_short.s / polyval_compact.s
  aes_encrypt.s / aes_decrypt.s / tables.s
  gcm_siv.s
  data.s                 # all BSS + page-aligned tables (segment-partitioned)
  polyval-example.cfg    # §6.1 consumer-facing example cfg (SHIPPED as
                         #   build/lib/polyval-example.cfg; NOT used by any
                         #   build in this repo — deliberately separate from
                         #   c64.cfg and lib_only.cfg, which carry app-layer
                         #   and verification scaffolding respectively)
  lib_main.s             # make lib-verify entry stub
  c64.cfg / lib_only.cfg # ld65 cfgs with LIB_POLYVAL_* SEGMENTS aliases
  exports.inc            # human-readable cross-module symbol map (NOT an .include)
test/                    # consumer_stub.s (`make consumer-check`)
                         # consumer_stub_noaes.s (`make consumer-check-noaes`,
                         #   issue #47 guard; NOT vendored into the tarball)
                         # consumer_stub_shipped.s (`make consumer-check-shipped`,
                         #   issue #79 guard; NOT vendored into the tarball)
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
   every profile the baseline shipped, hash pairs) whenever they claim
   binary identity, and
   MUST use absolute blob URLs (relative links 404 on release pages).
1. Bump `VERSION`, `CHANGELOG.md`, **and `LIB_POLYVAL_VERSION_MINOR`/`_PATCH`
   in `src/lib_version.s`** (the bare `LIB_VERSION_*` aliases follow
   automatically; the v0.3.0 release forgot this file entirely and it went
   unnoticed for a full release cycle — see `API.md` §9.1). Also check the
   value column of the §9.1 table in `API.md` — the v0.4.1 release bumped
   the file but left the table at PATCH 0.
2. Write `docs/RELEASE_NOTES_vX.Y.Z.md` (use the v0.7.3 file as a template).
   Release notes MUST state `RESIDENT`/`COLD` footprint values **per
   shipped archive**, **one row each** — as of v0.8.0 that is **seven
   rows**: `polyval.a`, `polyval-gcmsiv.a`, `polyval-gcmsiv-short.a`,
   `polyval-gcmsiv-compact.a`, `polyval-long.a`, `polyval-short.a`,
   `polyval-compact.a` — even when a value is unchanged. Count the rows
   against the `lib-polyval-*` target list rather than against the
   previous release's table.

   This came from c64-lib-contract §6.6 obligation 2, **retired at
   contract v1.0.0**, and is **kept as local practice**: one tag carries
   a footprint pair per archive, so a single per-version delta is
   meaningless and a merged row makes the count unverifiable. The
   surviving §5 still requires the values themselves to be
   safe-direction and to be presented as a RESIDENT/COLD pair.

   Release notes SHOULD also state `LIB_POLYVAL_GCMSIV_MAX_PT_LEN` when
   it changes — it is exported §5 surface as of v0.10.0, and a consumer
   may be asserting against it.

   **Do not merge archives that share a configuration into one row.**
   `polyval.a` and `polyval-gcmsiv.a` are both LONG AEAD with identical
   values, and v0.7.0–v0.7.2 combined them into a single row while the
   prose said "five rows" — five archives presented as four rows, so the
   row-count check above could not actually be performed as written
   (caught in review of PR #61). One row per archive keeps the count
   literal.
3. `make clean && make dist VERSION=vX.Y.Z` — produces the tarball + stamps
   size/SHA256 into the release notes (two-pass). **The stamper is
   fail-closed** (`tools/build_release.sh`): it aborts unless exactly one
   `SHA256`/`SIZE` placeholder remains after the reset. If it refuses, the
   notes contain a second hash or a literal placeholder token in prose —
   fix the notes, don't loosen the guard. Before v0.7.0 it silently
   stamped the tarball hash over the byte-identity receipt's PRG hashes.
4. Verify reproducibility: re-run `make dist`, SHA256 must be identical.
5. Tag `vX.Y.Z` on the commit that includes the tarball + stamped notes.
