# c64-polyval v0.6.0 — 2026-08-14

**Contract v0.9.x alignment MINOR release** — polyval's re-tag in the
[c64-lib-contract#76](https://github.com/JC-000/c64-lib-contract/issues/76)
phase-3 coordinated adopter wave (contract at SPEC v0.9.1 at release
time). The §6.2 `CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES`
make-variable surface is new; nothing exported by any archive was
removed or renamed, so `LIB_POLYVAL_ABI_VERSION` stays 1, and the
linked PRG remains byte-identical to v0.4.1 on both profiles. The
full per-change log is in [`CHANGELOG.md`](../CHANGELOG.md); this
file is the concise release summary.

## What's in

- **§6.2 consumer-defines forwarding**
  ([PR #34](https://github.com/JC-000/c64-polyval/pull/34)). The
  Makefile accepts the two contract-normative variables:
  `CONTRACT_DEFINES` (global ca65 `-D` flags, e.g.
  `-D LIB_NO_BARE_EXPORTS=1`) and `CONTRACT_ZP_DEFINES` (§2 slot
  overrides, e.g. `make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'`
  — values `$`-free per the SPEC's quoting rule). Both reach every
  §6.1 target including the recursive per-profile archive builds.
  Polyval's scoped-delivery reading — every member TU is a
  ZP-defining TU (zero `.importzp` sites; equates baked per-object) —
  is cited by SPEC v0.9.1's restated §6.2 rule as the measured
  defining-TU-direction evidence.
- **v0.8.0 §4 segment-placement declarations**
  ([PR #30](https://github.com/JC-000/c64-polyval/pull/30), corrected
  to the v0.8.3 risk table in
  [PR #31](https://github.com/JC-000/c64-polyval/pull/31)). Both ld65
  cfgs declare the load-bearing attributes: `type = ro` on
  `LIB_POLYVAL_AES_RODATA` (correctness — 522 initialised bytes
  silently vanish under `type = bss`, with mid-area displacement in
  `c64.cfg`) and `align = $100` on the three table segments
  (performance-only, honestly labelled; the dropout is fully silent
  for cfg-only alignment — a finding this library measured
  independently and contributed to contract
  [#78](https://github.com/JC-000/c64-lib-contract/issues/78)).
  New API.md §9.8 documents the declarations.
- **ZP hygiene** ([PR #32](https://github.com/JC-000/c64-polyval/pull/32),
  per the #76 R2 ruling): the bare `zp_dummy` export (app-layer
  porting placeholder, never an archive member) is gone; the
  exported-vs-summed audit confirms 13 slots, all under the
  registered `polyval_`/`pv_` prefixes, summing to
  `LIB_POLYVAL_ZP_USAGE_BYTES` = 45.
- **Copied-snippet fixes** ([PR #29](https://github.com/JC-000/c64-polyval/pull/29),
  [PR #33](https://github.com/JC-000/c64-polyval/pull/33)): consumer
  version-guard snippets moved to the canonical `.assert`/`lderror`
  form (the `.if`-on-import form never assembled — contract #73);
  ZP-override snippets moved to `-D polyval_acc=0x40` (the old
  `--asm-define` spelling is rejected by ca65, and unquoted `$40` is
  eaten by the shell — contract v0.7.1/v0.8.6 classes).
- **Docs**: contract currency to SPEC v0.9.1 across README / API.md
  §9 / CLAUDE.md; API.md §9.5 rewritten as a per-clause §6.1–§6.5
  conformance statement (`lib-app-owned` N/A — no §8.x primitive;
  `lib-verify` grandfathered; member-basename `polyval_` prefix
  recorded as a next-MAJOR item).

## What's NOT shipped

- **No binary changes.** Linked PRG byte-identical to v0.4.1 on both
  profiles (LONG `e93962ac…`, SHORT `98948d02…`), verified after
  every constituent PR and re-verified at release.
- **No new crypto primitives, no AAD, no bulk encryption, no
  constant-time hardening** — all unchanged from v0.5.0; see API.md
  §6.
- **No §8.1–§8.3 shared-primitive adoption.** Correctly N/A, which
  also makes v0.8.5's export-discipline clause and the §6.3
  `lib-app-owned` target inapplicable.
- **No archive member renames.** The §6.5 `polyval_`-prefixed member
  basenames ride this repo's next MAJOR, per the SPEC's
  cannot-dual-name rule.

## Upgrade notes for consumers

This is a v0.x **MINOR** bump per c64-lib-contract SPEC §7 (additive
build surface, no export changes). Consumers re-vendor with no
mandatory integration changes:

1. To override a ZP slot you can now use the §6.2 route on any
   archive target — `make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'`
   — instead of editing `CA65FLAGS`. Values must be `$`-free
   (`0x` hex or decimal).
2. Composing consumers pass `-D LIB_NO_BARE_EXPORTS=1` via
   `CONTRACT_DEFINES` on the same targets.
3. `LIB_POLYVAL_VERSION_MINOR` now exports `6`;
   `LIB_POLYVAL_ABI_VERSION` is unchanged at `1` (nothing exported
   was removed — the dropped `zp_dummy` never reached an archive).
4. If you hand-write a `SEGMENTS{}` block, preserve the §4 placement
   attributes now declared in the cfg comments (API.md §9.8) —
   `type = ro` on `LIB_POLYVAL_AES_RODATA` is correctness-critical
   and its violation can be completely silent.

See `API.md` §9 for the full contract surface.

## Verification

Full suite run at release time (VICE `x64sc`, seed 8452), both
profiles: 376/376 passed, 6 skipped each — POLYVAL Direct 217/217,
GCM-SIV 159/165 + 6 AAD-by-design skips. `make consumer-check` and
all four §6 archive targets build clean; §6.2 override reachability
measured end-to-end (overridden slot present in `ar65`-extracted
archive members, including through the recursive per-profile
targets).

## Attestation

`c64-polyval-v0.6.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.6.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.6.0.tar.gz` |
| **Size**   | 84745 bytes |
| **SHA256** | `427a1217e68dd22f05c6feb217723f15e716ef08b3c10f4ddba0e4d1f1b3658c` |

Re-running `make dist VERSION=v0.6.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's
mtime is forced to `2026-08-14T00:00:00Z`, owner/group are pinned to
`0:0` (numeric), and `gzip -n` drops the gzip timestamp+filename
header. The canonical vendoring file list lives in
`tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.6.0/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.6.0.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.0 enumeration)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers, including `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs, with the
  §4 placement declarations)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor
metadata.

## Issues and coordination

No c64-polyval tracker issues were open for this cycle; the work was
driven by the c64-lib-contract v0.8.x–v0.9.x releases and the
[#76](https://github.com/JC-000/c64-lib-contract/issues/76)
execution-direction rulings (R2 ZP audit reported on
[#83](https://github.com/JC-000/c64-lib-contract/issues/83);
§4 measurements contributed to
[#78](https://github.com/JC-000/c64-lib-contract/issues/78); phase-1
status posted on #76). Constituent PRs: #29, #30, #31, #32, #33, #34.

Deferred (not release-blocking, carried from v0.4.1): optional C64U
16/48/64 MHz hardware sweep of `polyval_block` — needs physical
hardware.

## Known limitations

Carried over unchanged from v0.5.0; see `API.md` §6 for the full
list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.9.1, tagged).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git
  tag `lib-v0.1.0`).
