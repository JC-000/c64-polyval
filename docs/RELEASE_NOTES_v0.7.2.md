# c64-polyval v0.7.2 — 2026-08-23

**Consumer-reachability PATCH** (contract at SPEC v0.11.0 at release
time). A documented consumer knob was unusable, and the profile-selection
table hid the number that decides the choice for a memory-bound
consumer. Nothing exported changed, no declared footprint moved, and the
linked PRG is byte-identical to v0.7.1 on both profiles, so
`LIB_POLYVAL_ABI_VERSION` stays 1. The full per-change log is in
[`CHANGELOG.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.2/CHANGELOG.md);
this file is the concise release summary.

## What's in

- **`ZP_CONFIG_NO_EXPORTS` is now consumer-reachable**
  ([#50](https://github.com/JC-000/c64-polyval/issues/50),
  [PR #52](https://github.com/JC-000/c64-polyval/pull/52)).
  `src/constants_lib.inc` assigned it **unguarded**, and every library TU
  includes that header, so the documented supplies-own-slots route —
  `-D ZP_CONFIG_NO_EXPORTS=1` — was a hard
  `Symbol 'ZP_CONFIG_NO_EXPORTS' is already defined` in *every* TU rather
  than a redundant define. Now `.ifndef`-guarded; the default stays 1.

  Same defect and same one-line shape as
  [c64-x25519#99](https://github.com/JC-000/c64-x25519/issues/99), fixed
  there in v0.11.1. Reported from `c64-aes256-ecdsa`, this library's
  first declared consumer, during its v0.7.1 integration.

- **`API.md` §3 gains Code / Tables / Total RAM columns**
  ([#51](https://github.com/JC-000/c64-polyval/issues/51)). The table
  presented the profile axis through a single "Memory (tables)" column —
  `~256 B` for SHORT — which is true and materially misleading: SHORT's
  multiply is a fully unrolled Shoup-4 and its *code* is 13,614 B. A
  consumer choosing on "which profile is smaller" was reading the one
  column that hides the answer.

  §3 now also states plainly that *neither* profile serves a
  memory-bound consumer — both trade only table memory and assume code
  is cheap — and points at #51, which remains open, for the compact
  back-end.

## Profile footprint, corrected

Measured from `lib_only.cfg` links of each POLYVAL-only archive, not
estimated:

| Profile | Code | Tables | +BSS | Total |
|---|---:|---:|---:|---:|
| SHORT | 13,614 B | 256 B | 32 B | 13,902 B (~13.5 KB) |
| LONG | 4,160 B | 8,448 B | 32 B | 12,640 B (~12.3 KB) |

**LONG is the smaller profile overall.** The names describe precompute
cost, not size. The previous `~8.5 KB` figure for LONG's tables is
corrected to the measured 8,448 B (`256 + 4096 + 4096`).

This is a documentation correction only — no code moved, and the
declared §5/§6.6 manifest values are unaffected (those measure the
library's own resident span, not the profile comparison above).

## Footprint values per (profile × variant)

Declared values (SPEC §6.6 obligation 2). Five archive rows; **no
declared value moved this cycle**, and each was re-verified from inside
its archive:

| Archive / configuration | RESIDENT | COLD |
|---|---|---|
| `polyval.a` / `polyval-gcmsiv.a` (LONG AEAD) | 6656 (unchanged) | 1280 (unchanged) |
| `polyval-gcmsiv-short.a` (SHORT AEAD) | 16128 (unchanged) | 3072 (unchanged) |
| `polyval-long.a` (LONG, no AES) | 4352 (unchanged) | 1280 (unchanged) |
| `polyval-short.a` (SHORT, no AES) | 13824 (unchanged) | 3072 (unchanged) |

## What's NOT shipped

- **No binary changes.** Linked PRG byte-identical to v0.7.1 on both
  profiles — receipt below.
- **No export surface changes.** `LIB_POLYVAL_ABI_VERSION` stays 1. The
  default build still exports all 13 ZP slots; only the *suppressed*
  path, which previously could not be requested at all, changes.
- **No manifest value changes**, no new archive targets, no new §6.1
  goals.
- **No compact/third profile.**
  [#51](https://github.com/JC-000/c64-polyval/issues/51) is open and
  unaddressed beyond the documentation half; the requesting consumer has
  said it is not a blocker and is shipping with SHORT.
- **No member-basename prefix.** SPEC v0.11.0's zero-consumer carve-out
  does not reach this library — see below.

## Upgrade notes for consumers

This is a v0.x **PATCH** bump.

1. `LIB_POLYVAL_VERSION_PATCH` now exports `2`; `_MINOR` stays `7`.
2. **If you supply your own ZP slots**, `-D ZP_CONFIG_NO_EXPORTS=1` now
   works — via `CONTRACT_DEFINES` or directly on the ca65 command line.
   Before v0.7.2 it could not be passed at all. Confirmed end-to-end:
   with suppression the archive's `zp_config.o` exports **0** symbols;
   without it, all **13**.
3. Nothing else needs to change. Consumers not passing that define see
   an identical library.

## Contract currency

Recorded adoption moves **v0.10.6 → v0.11.0** this release. v0.10.7
registers `c64-mlkem` and states no existing adopter is affected.
v0.11.0 adds two zero-consumer carve-outs (§1 bare version exports,
§6.5 "born prefixed" archive members), **both N/A here**: c64-polyval is
one of the four incumbents v0.11.0 names as unaffected, and §6.5's scope
test — no tagged release that any consumer pins — is now definitively
failed, `c64-aes256-ecdsa` having become a declared consumer pinning a
tag. The §6.5 MAJOR deferral for member basenames therefore stands, and
members cannot dual-name, so there is no transitional path short of
v1.0.0.

## Verification

Full suite at release time (VICE `x64sc`, seed 8452): 376/376 passed, 6
skipped — POLYVAL Direct 217/217, GCM-SIV 159/165 + 6 AAD-by-design
skips. `make consumer-check`, `make consumer-check-noaes`,
`make lib-verify`, and all **five** §6 archive targets build clean.

The #50 fix is verified by the knob *working*, not merely by the absence
of an error:

| Build | `zp_config.o` exports |
|---|---|
| default `make lib` | 13 |
| `make lib CONTRACT_DEFINES='-D ZP_CONFIG_NO_EXPORTS=1'` | 0 |

Per-archive manifest values re-verified by `ar65 x` + `od65
--dump-exports` on each archive's own `lib_manifest.o`: 6656/1280,
6656/1280, 16128/3072, 4352/1280, 13824/3072 respectively.

### Byte-identity verification (worktree rebuild)

Method: `git worktree add --detach <dir> v0.7.1`; in the baseline
worktree and in the v0.7.2 tree: `make clean && make` (LONG) and
`make clean && make POLYVAL_PROFILE=short` (SHORT);
`shasum -a 256 build/polyval.prg` after each.

| Profile | v0.7.1 rebuild | v0.7.2 rebuild | |
|---|---|---|---|
| LONG | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | identical |
| SHORT | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | identical |

Expected: the guard changes nothing when the define is absent, which is
the app build's case.

**Method note — this applies to PRGs only.** `.o` and `.a` files are
*not* byte-comparable across build paths or across builds separated in
time: `ca65` stamps a wall-clock `OPT_DATETIME` (seconds granularity)
into every object and records source paths and mtimes in the object's
`Files:` section, both unconditionally and independent of `-g`. `ar65`
adds nothing. Compare linked output — as above — or `od65` structural
dumps. This finding is recorded upstream as SPEC v0.10.5 §6.3's
checkability note.

## Attestation

`c64-polyval-v0.7.2.tar.gz` is produced reproducibly by
`make dist VERSION=v0.7.2`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.7.2.tar.gz` |
| **Size**   | 98930 bytes |
| **SHA256** | `f31fbf6f428bb0d3fec6f068ff72184830e147dbb61412fcf30f707b53585ed2` |

Re-running `make dist VERSION=v0.7.2` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime
is forced to `2026-08-23T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.7.2/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.7.2.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.4 enumeration)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers, including `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs, with the §4
  placement declarations)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor metadata.
`test/consumer_stub_noaes.s` is therefore not vendored, matching
`test/consumer_stub.s` — both are repo-side guards, not consumer-facing
surface.

## Issues and coordination

[#50](https://github.com/JC-000/c64-polyval/issues/50) closed by
[PR #52](https://github.com/JC-000/c64-polyval/pull/52).
[#51](https://github.com/JC-000/c64-polyval/issues/51) is addressed in
its documentation half only and **remains open** for the compact
back-end.

Both were reported from
[c64-aes256-ecdsa](https://github.com/JC-000/c64-aes256-ecdsa)
(JC-000/c64-aes256-ecdsa#27), this library's first declared consumer,
during its v0.7.1 integration — which it has since completed, confirming
[#47](https://github.com/JC-000/c64-polyval/issues/47)'s fix against the
shipped tag from the consumer side.

Deferred (not release-blocking, carried from v0.7.1): optional C64U
16/48/64 MHz hardware sweep of `polyval_block` — needs physical
hardware.

## Known limitations

Carried over unchanged from v0.7.1, with one addition now stated
explicitly in `API.md` §3: neither profile suits a memory-bound
consumer. See
[`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.2/API.md)
§6 for the full list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.11.0, tagged).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git tag
  `lib-v0.1.0`).
