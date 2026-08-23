# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases: https://github.com/JC-000/c64-polyval/releases — tagged releases
track `MAJOR.MINOR.PATCH` and are the supported consumption points for
downstream projects (see `API.md` §8 for the integration contract).

## Unreleased

### Fixed

- **`polyval-long.a` / `polyval-short.a` exported the AES + GCM-SIV BSS
  block, making the POLYVAL-only archives unlinkable by the very
  consumers they exist for** ([issue
  #47](https://github.com/JC-000/c64-polyval/issues/47)). `src/data.s` is
  a single monolithic BSS TU and `data.o` is archived whole into every
  variant, so `LIB_POLYVAL_NO_AES` gated the §5 manifest rows (issue #23)
  but never the storage those rows enumerate. The two POLYVAL-only
  archives therefore shipped 21 AES/GCM-SIV BSS exports — `aes_state`,
  `aes_current_key`, `aes_expanded_key`, `aes_mc_a0..b3` and the full
  `gcmsiv_*` set — and any consumer defining its own AES or GCM-SIV hit
  `ld65: Error: Duplicate external identifier`. This is issue #23's
  defect class one layer down: #23 fixed the enumeration, not the thing
  enumerated. The AES and GCM-SIV BSS blocks are now gated on
  `.ifndef LIB_POLYVAL_NO_AES`; POLYVAL references none of them.

  Found while `c64-aes256-ecdsa` — which ships its own AES-256 and its
  own GCM-SIV — was adopting the contract and consuming this library;
  all 21 symbols collided with symbols it defines.

  **No manifest change.** `LIB_POLYVAL_RESIDENT_BYTES` is code+rodata
  only (BSS excluded per SPEC §5) and `LIB_POLYVAL_COLD_BYTES` is
  code-span only, so both NO_AES rows are unaffected. Re-measured after
  the fix with the scratch-LOADADDR method `src/lib_manifest.s` records:
  LONG `$4000..$503F` = 4160 and SHORT `$4000..$752D` = 13614, both
  matching the 2026-08-15 values exactly. `build/polyval.prg` is
  byte-identical to master on both profiles, and the suite is unchanged
  at 376/376 passed, 6 skipped.

### Added

- **`make consumer-check-noaes`** — regression guard for the above.
  Links `test/consumer_stub_noaes.s`, which deliberately *defines* its
  own `aes_state` and `gcmsiv_tag`, against the real `polyval-long.a`
  and `polyval-short.a` archives; a re-leak fails the link. Verified to
  fail on the pre-fix tree and pass after, on both profiles. Uses
  `.forceimport` so ld65 actually extracts the archive members — a plain
  `.import` of an unreferenced symbol is dropped by ca65 and would leave
  the guard toothless.

### Documentation

- **Release-flow corrections learned by running it** ([PR
  #45](https://github.com/JC-000/c64-polyval/pull/45)): step 2 said "all
  four configurations" when v0.7.0 brought the archive count to five, so
  it now enumerates per shipped archive and instructs counting rows
  against the `lib-polyval-*` target list rather than against the
  previous release's table — counting against the last release is how it
  went stale. Step 3 records that the notes stamper is fail-closed and
  what a refusal means (a second 64-hex hash, or a literal placeholder
  token in prose): fix the notes, not the guard.
- **`docs/precalc-tables.md` archive membership** — the `aes_sbox` /
  `aes_inv_sbox` rows listed the AEAD bundle as `polyval.a` /
  `polyval-gcmsiv.a`, omitting `polyval-gcmsiv-short.a`, which ships
  `tables.o` and enumerates both S-boxes in its own §8.4 manifest
  (verified from inside the archive). The prose on the two independent
  axes is extended with the case v0.7.0 introduced: `polyval-short.a`
  and `polyval-gcmsiv-short.a` are both `PROFILE=short` yet differ in
  AES membership, which is precisely why profile alone cannot express
  that axis.
- **`README.md` build block** listed only two of the five archive
  targets after `lib-polyval-gcmsiv-short` was added; all five are now
  shown, each labelled with its profile and AES membership.

## v0.7.0 — 2026-08-15

The SHORT+AEAD reachability release. A v0.x **MINOR** bump: a new §6.1
archive target (`lib-polyval-gcmsiv-short`) is new consumer-visible
surface, so MINOR rather than PATCH — but nothing exported was removed
or renamed, so `LIB_POLYVAL_ABI_VERSION` stays 1 and the linked PRG
remains byte-identical to v0.4.1 on both profiles.

The cycle closed a defect in which the SHORT+AEAD configuration was
documented and recommended for RFC 8452 per-message `H`, yet no archive
delivered it — and the near-miss invocation exited 0 while shipping an
unlinkable archive whose §6.4 manifest misdescribed it
([#40](https://github.com/JC-000/c64-polyval/issues/40)). c64-polyval#40
became the upstream motivating case for contract SPEC v0.10.5's §6.3
*looks-reachable* rule.

Footprint values per (profile × variant), declared (SPEC §6.6
obligation 2 — one tag now carries **five** archive rows; no declared
value moved this cycle):

| Archive / configuration | RESIDENT | COLD |
|---|---|---|
| `polyval.a` / `polyval-gcmsiv.a` (LONG AEAD) | 6656 (unchanged) | 1280 (unchanged) |
| `polyval-gcmsiv-short.a` (SHORT AEAD) | 16128 (**new archive**) | 3072 (**new archive**) |
| `polyval-long.a` (LONG, no AES) | 4352 (unchanged) | 1280 (unchanged) |
| `polyval-short.a` (SHORT, no AES) | 13824 (unchanged) | 3072 (unchanged) |

The SHORT AEAD pair (16128 / 3072) is not new *as a value* — v0.6.1
already declared it for the configuration `API.md` §9.4 listed with `—`
in its Archive column. v0.7.0 is the release in which an archive finally
carries it.

### Added

- **`make lib-polyval-gcmsiv-short`** — new SPEC §6.1 archive target
  producing `build/lib/polyval-gcmsiv-short.a`: the full AEAD bundle
  (POLYVAL + AES-256 + GCM-SIV) on the **SHORT** profile, i.e. the RFC
  8452 per-message-`H` configuration
  ([#40](https://github.com/JC-000/c64-polyval/issues/40)). It follows
  the `lib-polyval-{long,short}` recursive clean-and-pin shape, so its
  `lib_manifest.o` is assembled under the same profile pin and the §5
  equates describe the archive they ship in (SPEC §6.4): `RESIDENT`
  16128 / `COLD` 3072.
- **Archive-goal configuration guard.** A `PIN_` table in the `Makefile`
  declares each archive goal's required
  `(POLYVAL_PROFILE × LIB_POLYVAL_NO_AES)` pair and asserts it at parse
  time, so a mismatched invocation is rejected before any object is
  assembled. Beyond the SHORT+AEAD case below, this closed two silent
  wrong-artifact paths found in review: naming
  `build/lib/polyval-gcmsiv-short.a` at the default profile shipped LONG
  code under the `-short` name, and `build/lib/polyval-short.a` shipped
  SHORT code carrying the LONG AEAD manifest value (6656 rather than
  13824) — incoherent, §6.4-violating and pre-existing. It also rejects
  `make lib POLYVAL_NO_AES=1` (AEAD member set, NO_AES manifest).

### Fixed

- **Release-notes stamping could silently falsify the byte-identity
  receipt.** `tools/build_release.sh` reset *every* 64-hex hash in the
  notes to the attestation placeholder, then stamped the tarball's hash
  over all of them with an unbounded `str.replace`. Since CLAUDE.md's
  post-[#37](https://github.com/JC-000/c64-polyval/issues/37) release
  flow requires a worktree-rebuild receipt in the notes, that rewrote
  the receipt's per-profile PRG hashes into a row of identical values
  still shaped like a passing identity check. The reset is now scoped to
  the `| **SHA256** |` attestation row, and stamping aborts unless
  exactly one placeholder of each kind is present. Measured on a scratch
  copy before fixing, and the new guard immediately caught a second live
  instance (prose in the v0.7.0 notes naming the placeholder token).

- **SHORT+AEAD was documented but undeliverable, and failed silently.**
  `LIB_AEAD_OBJS` hardcoded `polyval_long.o` while `POLYVAL_PROFILE`
  still reached `CA65FLAGS`, so `make lib POLYVAL_PROFILE=short` exited
  0 and archived the LONG multiply against a SHORT-assembled `data.o`
  and `lib_manifest.o`. The result was unlinkable (`polyval_long.o`
  imports `polyval_htable8_s*` / `polyval_reduce8_s*`, which SHORT
  `data.o` does not export) *and* SPEC §6.4-violating (the manifest
  claimed the SHORT footprints over LONG code). `ar65` cannot detect
  either. `LIB_AEAD_OBJS` now uses `$(POLYVAL_PROFILE_OBJ)`, and the
  unpinned `lib` / `lib-polyval-gcmsiv` targets reject a non-`long`
  profile at parse time — they do not `make clean` first, so under a
  profile switch they would otherwise reuse stale objects from the
  other profile. `API.md` §9.4's footprint table previously listed this
  configuration with `—` in the Archive column; it now names the
  archive. Existing archives (`polyval.a`, `polyval-gcmsiv.a`,
  `polyval-long.a`, `polyval-short.a`) and both PRGs are byte-identical
  across this change.

### Documentation

- SPEC currency **v0.10.4 → v0.10.6** (both tagged upstream 2026-08-15). The
  new §6.3 *looks-reachable* rule — a build knob naming a variant/profile
  axis MUST, on every §6.1 target accepting it, select that axis in both
  member selection and assembly configuration or reject the invocation
  loudly — is satisfied by the `PIN_` table's parse-time assert; no code
  change was required. c64-polyval#40 is the clause's shape-2 motivating
  case, and the `OPT_DATETIME` finding from its verification became the
  clause's checkability note upstream. `README.md`'s contract line was
  additionally two versions stale (v0.10.3) — it tracked neither this
  bump nor the v0.10.4 one. New `API.md` §9.5 entry for §6.3; `CLAUDE.md`
  records the rule and its `PIN_`-table discharge. **v0.10.6** enumerates
  the §8.3 provider surface (`ct_mul_8x8`, the SMC operand pair,
  `poly_prod_lo`/`_hi`) and requires a deferral gate to leave `.import`s
  behind for every name it un-defines — N/A here, verified by grep rather
  than assumed: the only §8.1–§8.3 names anywhere in this tree are the
  existing N/A declarations plus a doc-comment example in
  `precalc_table.inc`, and the library has no deferral switch. Also
  corrects two §6 target enumerations left at four entries when
  `lib-polyval-gcmsiv-short` was added.

- SPEC currency v0.10.3 → **v0.10.4**: the §6.3 clarification scoping
  the "no further target matrix" posture to *define-reachable*
  combinations, and requiring a §6.1 target for any documented axis
  that changes an archive's member set. `API.md` §9.5 gains a
  member-set-axis subsection; `README.md` "Profiles" and `CLAUDE.md`
  gain the profile-is-a-build-time-axis note. The gap this closes
  predated v0.10.4 — §6.3 ¶1's existing MUST already covered it.

- Post-release review of v0.6.1
  ([#37](https://github.com/JC-000/c64-polyval/issues/37)): the
  worktree-rebuild byte-identity receipt was produced post-hoc (claim
  reproduces exactly — v0.4.1 baseline rebuild hashes match v0.6.1 on
  both profiles) and appended to the release page and the on-disk
  notes; the release page's relative `CHANGELOG.md` link replaced
  with an absolute blob URL. The fleet's pre-tag release-PR review
  gate is adopted as release-flow step 0 in CLAUDE.md — releases now
  stage as PRs and wait for the review comment before tagging.
  README: dist example generalized to `vX.Y.Z` (was stale at
  `v0.5.0`) and the attestation/receipt practice documented.

## v0.6.1 — 2026-08-15

The contract v0.10.x alignment roll-up. A v0.x **PATCH** bump per this
library's own policy (bugfix with no API change): the §6.6 footprint
corrections change exported equate *values* only — no symbols added,
removed, or renamed; `LIB_POLYVAL_ABI_VERSION` stays 1 — and the
linked PRG remains byte-identical to v0.4.1 on both profiles.

Footprint deltas per (profile × variant), declared values (SPEC §6.6
obligation 2; actual code size is unchanged — these are declaration
corrections, not growth):

| Archive / configuration | RESIDENT | COLD |
|---|---|---|
| `polyval.a` / `polyval-gcmsiv.a` (LONG AEAD) | 6500 → 6656 (+156) | 1200 → 1280 (+80) |
| `POLYVAL_PROFILE=short` link (SHORT AEAD) | 16000 → 16128 (+128) | 3000 → 3072 (+72) |
| `polyval-long.a` (LONG, no AES) | 6500 → 4352 (−2148) | 1200 → 1280 (+80) |
| `polyval-short.a` (SHORT, no AES) | 16000 → 13824 (−2176) | 3000 → 3072 (+72) |

### Documentation

- Alignment pass against contract SPEC v0.10.3 (all-clauses
  mechanical re-verification: canonical `precalc_table.inc`
  byte-identical, §1/§2 export inventories, §4 annotations, §5/§6.6
  per-archive values, §6.2 variables, PRG hashes on both profiles —
  all pass, no code change needed): currency refresh v0.10.0 →
  v0.10.3 across README / API.md §9 / CLAUDE.md. v0.10.1 (stable-
  numbers reorder), v0.10.2 (SPEC snippet fixes — this repo audited
  clean for both forms), and v0.10.3 (§8.4 heading promoted; our
  citations retroactively correct) require no adoption work.

### Changed

- **`LIB_POLYVAL_RESIDENT_BYTES` / `LIB_POLYVAL_COLD_BYTES` value
  corrections** per c64-lib-contract SPEC v0.10.0
  [§6.6](https://github.com/JC-000/c64-lib-contract/blob/main/SPEC.md)
  (consumer footprint asserts, contract
  [#69](https://github.com/JC-000/c64-lib-contract/issues/69) /
  [#76](https://github.com/JC-000/c64-lib-contract/issues/76) phase 2).
  Two defects fixed in `src/lib_manifest.s`:
  1. *Unsafe rounding* — both equates rounded DOWN from measured
     (6567 → 6500, 1239 → 1200 LONG; 16021 → 16000, 3059 → 3000
     SHORT), so a consumer's `declared ≤ budget` assert could pass
     while the actual footprint overran. §6.6 obligation 1: each
     value must be ≥ the measured segment sum, rounded UP — fleet
     convention next 256-byte boundary.
  2. *Per-archive accuracy* — values were gated on `POLYVAL_PROFILE`
     only, so `polyval-long.a` / `polyval-short.a` (built with
     `-D LIB_POLYVAL_NO_AES=1`, containing no `tables.o` /
     `aes_*.o` / `gcm_siv.o`) shipped manifests claiming ~2.3 KB of
     AES+GCM-SIV code they do not contain (SPEC §6.4/§6.6; same
     defect class as issue #23). Both equates now gate on
     `POLYVAL_PROFILE` × `LIB_POLYVAL_NO_AES`.

  Measured (lib_only.cfg link of each archive's exact member set,
  ca65/ld65 V2.18) → declared:

  | Configuration (archive) | RESIDENT | COLD |
  |---|---:|---:|
  | LONG AEAD (`polyval.a` / `polyval-gcmsiv.a`) | 6567 → 6656 | 1239 → 1280 |
  | SHORT AEAD (`make POLYVAL_PROFILE=short` link) | 16021 → 16128 | 3059 → 3072 |
  | LONG NO_AES (`polyval-long.a`) | 4160 → 4352 | 1047 → 1280 |
  | SHORT NO_AES (`polyval-short.a`) | 13614 → 13824 | 2867 → 3072 |

  Linked PRG output stays byte-identical on both profiles (equates
  emit no segment data). Docs: API.md §9 currency to SPEC v0.10.0
  (v0.9.2 was doc-only, already satisfied), §9.4 per-archive value
  table + safe-direction rationale, §9.5 §6.6 adoption with the
  polyval-ized consumer assert snippet and §6.7 declared N/A (all
  buffers segment-resident; no §8.x placement equates); release flow
  now requires per-(profile × variant) footprint deltas in release
  notes per §6.6 obligation 2.

## v0.6.0 — 2026-08-14

The c64-lib-contract v0.9.x alignment roll-up — polyval's re-tag in
the [#76](https://github.com/JC-000/c64-lib-contract/issues/76)
phase-3 coordinated adopter wave (gated on the upstream v0.9.0 tag).
A v0.x **MINOR** bump: the §6.2 `CONTRACT_DEFINES` /
`CONTRACT_ZP_DEFINES` make-variable surface is new; nothing exported
by any archive was removed or renamed, so `LIB_POLYVAL_ABI_VERSION`
stays 1. Linked PRG output remains byte-identical to v0.4.1 on both
profiles — every change since is equate-, export-, gating-, cfg-, or
docs-level.

### Removed

- The bare `zp_dummy` `.exportzp` in `src/zp.s` (with its orphaned
  `.globalzp` template line in `src/include/zp.inc`), per the
  c64-lib-contract [#76](https://github.com/JC-000/c64-lib-contract/issues/76)
  R2 ruling and the [#83](https://github.com/JC-000/c64-lib-contract/issues/83)
  bare-`zp_*`-name collision class. It was a pre-contract porting
  placeholder: app-layer only (`zp.o` is in `APP_MODULES`, never a
  member of any §6 archive), imported by nothing, and not part of the
  §2 surface or the `LIB_POLYVAL_ZP_USAGE_BYTES` sum — so no consumer
  export surface shrinks and no ABI-counter implication. The
  `ZEROPAGE` placeholder byte itself remains (unexported), and
  `zp.inc` now shows the prefixed-name pattern instead of a live
  declaration. Exported-vs-summed ZP audit (per the #76 R2
  all-adopters action): 13 exported slots, all `polyval_`/`pv_`
  prefixed, widths sum 45 = `LIB_POLYVAL_ZP_USAGE_BYTES`.

### Documentation

- Consumer version-guard snippets aligned with the canonical SPEC §1
  `.assert`/`lderror` form (contract
  [#73](https://github.com/JC-000/c64-lib-contract/issues/73), fixed
  upstream in v0.8.1): `src/lib_version.s`'s header comment showed an
  `.if`-on-imported-symbol gate that never assembled; API.md §9.7's
  combined `.assert` used a `\` line continuation ca65 rejects
  without `.linecont +`. Both snippets are now single-line `lderror`
  asserts, compile-tested.
- Contract-currency: SPEC v0.9.1 re-lands the §6.5 suppression-gate
  and §2 registry-gate amendments the v0.9.0 merge missed, and its
  restated §6.2 ZP-scoping rule cites this library's PR #34
  measurements as the defining-TU-direction evidence.
- Consumer ZP-override snippets fixed for two copied-snippet defect
  classes the contract catalogued (SPEC v0.7.1 and v0.8.6, which asked
  adopters to re-check): `src/zp_config.s`'s host-override comment
  said `--asm-define` (ca65 rejects it — cl65's spelling) with an
  unquoted `$40` (the shell expands `$4` + `0`, silently placing the
  slot at `$00`); `src/lib_manifest.s`'s override note had the same
  spelling. Snippets now show `-D polyval_acc=0x40` (measured: the
  slot exports at `$40`) with the quoting rule and make-recipe `0x`
  preference stated.
- Contract-currency refresh to SPEC v0.9.0 (API.md §9, README,
  CLAUDE.md): v0.8.4 (`ZEROPAGE` exempt from §4 — matches existing
  usage) and v0.8.6 ($-hex snippet rule — already adopted via the
  snippet fixes below) are doc-only; v0.8.5's §8.1/§8.2 export
  discipline is N/A (no shared-primitive equates emitted); v0.9.0's
  §2 ZP prefix registry registers `polyval_` and `pv_` to this
  library (noted in API.md §9.2), and its §6 chapter is adopted in
  the Added entry below. `src/zp_config.s`'s host-override comment
  now leads with the §6.2 make-level route.
- Contract-currency refresh to SPEC v0.8.3: v0.8.2 is the upstream
  spec-tagging policy (issue #71), v0.8.3 corrects §4's measured risk
  table per adopter reports (contract
  [#78](https://github.com/JC-000/c64-lib-contract/issues/78) — this
  library's §9.8/cfg measurements were part of the record). The cfg
  annotations and API.md §9.8 now state the corrected semantics: both
  ld65 diagnostics are shape-conditional (the align warning needs a
  source-level `.align`; the bss warning keys on byte value), and the
  `type = bss` mutation additionally displaces everything after the
  hole in `c64.cfg`, where file-emitting `DATA` follows the segment.

### Added

- c64-lib-contract v0.9.0 §6.2 consumer-defines forwarding (contract
  [#76](https://github.com/JC-000/c64-lib-contract/issues/76) phase 1):
  the Makefile now accepts the two contract-normative variables
  `CONTRACT_DEFINES` (global ca65 `-D` flags) and `CONTRACT_ZP_DEFINES`
  (§2 ZP slot overrides, e.g.
  `make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'`), both `?=`
  empty and appended to `CA65FLAGS`, so consumer defines reach every
  §6.1 target — including the recursive `lib-polyval-{long,short}`
  builds — without editing the Makefile or clobbering `CA65FLAGS`.
  Delivering `CONTRACT_ZP_DEFINES` to *every* member recipe is this
  library's conformant reading of the SPEC's "only the ZP-defining
  TU(s)" scope: c64-polyval has zero `.importzp` sites for its own
  slots (each TU bakes the equates via `constants_lib.inc` →
  `zp_config.s` `.ifndef` guards), so every member TU is a ZP-defining
  TU and a `zp_config.o`-only delivery would export an overridden
  address other members never baked. Measured: an overridden
  `polyval_acc=0x40` lands in `zp_config.o`'s exports in `polyval.a`
  and (via automatic sub-make propagation) `polyval-short.a`, and
  `lib-verify` / `consumer-check` link clean under the override.
  The rest of the v0.9.0 §6 chapter needs no code change, verified and
  documented in `API.md` §9.5: archive basenames already canonical
  (`polyval[-<variant>].a`), `lib-app-owned` N/A (no §8.x primitive
  consumed), §6.4 per-variant manifests already conformant (both
  halves), `lib-verify` grandfathered in the reserved `lib-*` namespace
  until next MAJOR, and the §6.5 `polyval_`-prefixed archive member
  basenames recorded as a next-MAJOR item.
- c64-lib-contract v0.8.0 §4 segment-placement declarations
  (contract [#63](https://github.com/JC-000/c64-lib-contract/issues/63)):
  load-bearing cfg attributes are now declared as comments on the
  segment lines of `src/c64.cfg` and `src/lib_only.cfg` — `type = ro`
  on `LIB_POLYVAL_AES_RODATA` (correctness: 522 initialised S-box/rcon
  bytes are dropped under `type = bss`; ld65 warns but links) and
  `align = $100` on `LIB_POLYVAL_HTABLE` /
  `LIB_POLYVAL_LONG_HTABLE8` / `LIB_POLYVAL_LONG_REDUCE8`
  (performance-only, and declared as such — the library is not
  constant-time, API.md §6; dropping the attribute is fully silent
  since `src/data.s` carries no `.align`). New API.md §9.8 documents
  the declarations and the segments deliberately left undeclared;
  README §4 bullet, API.md §9 currency paragraph (v0.7.5 + v0.8.0),
  and CLAUDE.md updated. Docs and cfg comments only — linked PRG
  output is byte-identical on both profiles.

## v0.5.0 — 2026-08-13

Adopts the [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
v0.7.0 prefixed-export surface (§1 + §8.4, contract at SPEC v0.7.3 at
release time) and fixes a §8.0 manifest-accuracy defect in the
POLYVAL-only archives. This is a v0.x **MINOR** bump: new exported
symbols, no removals or renames, `LIB_POLYVAL_ABI_VERSION` stays 1.
Linked PRG output is byte-identical to v0.4.1 on both profiles —
every change is equate-, export-, gating-, or docs-level.

### Added

- §1 prefixed version exports
  ([#21](https://github.com/JC-000/c64-polyval/issues/21), via
  [PR #26](https://github.com/JC-000/c64-polyval/pull/26)):
  `src/lib_version.s` now exports `LIB_POLYVAL_VERSION_{MAJOR,MINOR,PATCH}`
  and `LIB_POLYVAL_ABI_VERSION` as the permanent, collision-free form.
  The deprecated bare `LIB_VERSION_*` / `LIB_ABI_VERSION` names remain
  exported by default (required through contract v0.x, removed at
  v1.0), are gated on `LIB_NO_BARE_EXPORTS`, and alias the prefixed
  literals so the two forms cannot drift. `test/consumer_stub.s`
  imports both forms, so `make consumer-check` guards the full set.
- §8.4 prefixed precalc-table exports
  ([#22](https://github.com/JC-000/c64-polyval/issues/22), via
  [PR #24](https://github.com/JC-000/c64-polyval/pull/24)):
  `src/precalc_table.inc` re-copied byte-for-byte from the contract
  root (SHA256-verified); all five `LIB_PRECALC_TABLE` call sites pass
  `"POLYVAL"` as the fifth argument, emitting
  `LIB_POLYVAL_PRECALC_<name>_{SIZE,REGION,SHARED}` alongside the
  bare triple (same `LIB_NO_BARE_EXPORTS` gating). Table names stay
  unprefixed per SPEC §8.1. Audit greps move from `LIB_PRECALC_` to
  `_PRECALC_`.
- Makefile `POLYVAL_NO_AES=1` knob (passes `-D LIB_POLYVAL_NO_AES=1`),
  set automatically by the `lib-polyval-{long,short}` targets.

### Fixed

- §8.0 manifest accuracy
  ([#23](https://github.com/JC-000/c64-polyval/issues/23), via
  [PR #25](https://github.com/JC-000/c64-polyval/pull/25)):
  `polyval-long.a` / `polyval-short.a` no longer export
  `LIB_*PRECALC_aes_sbox_*` / `_aes_inv_sbox_*` equates describing
  512 B of AES tables those archives do not contain (`tables.s` is a
  member of the AEAD bundle only). The AES rows are gated on
  `LIB_POLYVAL_NO_AES` — archive membership is an axis
  `POLYVAL_PROFILE` cannot express, since `polyval-long.a` and
  `polyval-gcmsiv.a` are both PROFILE=long. Verified by `ar65 x` +
  `od65 --dump-exports` on every archive's extracted manifest member.
- API.md §9.1 value table had said `LIB_VERSION_PATCH` = 0 since the
  v0.4.1 release bumped the export to 1 — the §9.1 drift class hitting
  the docs side this time. The release checklist now covers the table.

### Changed

- `src/lib_version.s`: `LIB_POLYVAL_VERSION_MINOR` 4 → 5,
  `LIB_POLYVAL_VERSION_PATCH` 1 → 0 (bare aliases follow), with the
  matching `VERSION` bump.
- Docs currency: contract references bumped to SPEC v0.7.3 across
  README / API.md §9 / CLAUDE.md; `docs/precalc-tables.md` and
  API.md §9.6 now state which archives carry each table and the
  od65-reads-objects-not-archives audit caveat.

## v0.4.1 — 2026-07-28

Docs-only **PATCH** release: rolls up the issue-#19 turbo-scaling
documentation and a documentation-currency pass (contract SPEC v0.4.1
references, corrected test counts). The only source change is the
`LIB_VERSION_PATCH` bump itself — no code, ABI, or binary changes.

### Documentation

- Zero-REU / turbo-clean scaling documented as an explicit contract
  feature ([#19](https://github.com/JC-000/c64-polyval/issues/19),
  prompted by c64-nist-curves #69/#71): new README "Turbo /
  accelerated hosts" section and Features bullet; API.md §1 platform
  statement strengthened, §3 turbo-scaling paragraph added, §9.3
  expanded with the consumer-facing guarantees and a stated policy
  that any future REU-resident variant must ship as an *optional
  profile* with a manifest delta, never the default path (also in the
  `src/lib_manifest.s` §3 comment block). Comment/docs only — no code
  or binary changes.
- Contract-currency refresh: c64-lib-contract references in README,
  API.md §9, and CLAUDE.md bumped from SPEC v0.4.0 to SPEC v0.4.1.
  The contract's v0.4.1 is itself doc-only (no symbol, macro,
  section, or build-target semantics changed), so no adoption work
  was required — verified against the upstream SPEC changelog, and
  `src/precalc_table.inc` re-confirmed byte-identical to the
  canonical root file.
- README test section corrected: the `test_gcmsiv_polyval.py`
  end-to-end suite had grown to 165 tests (README still said "~15");
  expected totals (376/376 pass, 6 AAD-by-design skips) now stated.
  Release example generalized to `vX.Y.Z`.

### Changed

- `src/lib_version.s`: `LIB_VERSION_PATCH` 0 → 1 (with the matching
  `VERSION` file bump — the two are checked together per the v0.3.0
  drift lesson, API.md §9.1).

## v0.4.0 — 2026-07-16

Adopts [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
SPEC §8.0 (the "catch loop" precalculated-table enumeration, added to
the contract in v0.3.1 and still applicable at the contract's current
v0.4.0). §8.1–§8.3 (shared 8×8 quarter-square-multiply primitives)
remain N/A for c64-polyval — GF(2^128) carry-less multiplication has
no equivalent shared shape with the elliptic-curve / ChaCha20
libraries — so no `LIB_POLYVAL_SHARED_PRIMITIVES` equate is emitted.
This is a v0.x **MINOR** bump: new exported symbols, no removals.

### Added

- `src/precalc_table.inc` — canonical `LIB_PRECALC_TABLE` macro,
  copied verbatim from the contract repo per SPEC §8.0.
- `src/lib_manifest.s` now `.include`s it and registers five tables
  that clear the §8.0 floor (≥ 256 B AND hot-loop-read /
  page-aligned): `polyval_htable` (256 B, both profiles),
  `polyval_htable8` / `polyval_reduce8` (4096 B each, LONG profile
  only), `aes_sbox` / `aes_inv_sbox` (256 B each, both profiles).
  All classified `PRECALC_SHARED_NO` (algorithm-specific).
- `docs/precalc-tables.md` — the required human-readable enumeration:
  name, size, region, source file, classification, and rationale per
  table, plus the below-floor exempt list.
- `tools/build_release.sh` now stages `docs/precalc-tables.md` into
  the release tarball.

### Fixed

- `src/lib_version.s` exported `LIB_VERSION_MINOR = 2` /
  `LIB_VERSION_PATCH = 0` (i.e. "v0.2.0") ever since the v0.3.0
  release — the release commit (`0e7dd34`) bumped the `VERSION` file
  and `API.md` §9.1's documented value to 0.3.0 but never updated
  `src/lib_version.s` itself, so a consumer `.assert`ing
  `LIB_VERSION_MINOR >= 3` per `API.md` §9.6's own worked example
  would have failed to link against the actual v0.3.0 release. Now
  correctly exports 0.4.0.

## v0.3.0 — 2026-05-20

Adopts the [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
SPEC v0.1.0 in full. All six SPEC sections that apply to c64-polyval
land in this release (§3 is N/A — c64-polyval makes no REU claims).
This is a v0.x **MINOR** bump per the contract's §7 versioning rule
(breaking surface changes are allowed pre-v1.0). Consumers vendoring
c64-polyval need to update their `.import` / `.importzp` lists for
the renamed ZP slots and their `.segment` references in any custom
ld65 configs.

### Added

- `src/lib_version.s` — c64-lib-contract §1 surface. Exports
  `LIB_VERSION_MAJOR`, `LIB_VERSION_MINOR`, `LIB_VERSION_PATCH`, and
  `LIB_ABI_VERSION` as absolute equates, for consumer-side assemble-
  time version gating.
- `src/zp_config.s` — c64-lib-contract §2 surface. Every zero-page
  slot the library claims is now declared in a dedicated, `.ifndef`-
  guarded, `.exportzp`-ed translation unit. Suppression flag
  `ZP_CONFIG_NO_EXPORTS` mirrors the c64-x25519 / c64-nist-curves
  idiom.
- `src/lib_manifest.s` — c64-lib-contract §5 surface. Exports
  `LIB_POLYVAL_ZP_USAGE_BYTES` (45), `LIB_POLYVAL_REU_BANKS_USED`
  (0), and the profile-conditional `LIB_POLYVAL_RESIDENT_BYTES` /
  `LIB_POLYVAL_COLD_BYTES` so consumers can size-check the library
  at assemble time.
- Four new ar65 archive `make` targets (c64-lib-contract §6):
  - `make lib` — full AEAD bundle at `build/lib/polyval.a`
    (POLYVAL LONG + AES-256 + GCM-SIV).
  - `make lib-polyval-long` — POLYVAL LONG primitive only.
  - `make lib-polyval-short` — POLYVAL SHORT primitive only.
  - `make lib-polyval-gcmsiv` — explicit name for the AEAD bundle
    (currently byte-identical to `make lib`).

### Changed

- Segment names library-wide carry the `LIB_POLYVAL_*` prefix per
  c64-lib-contract §4. The library `.s` files now `.segment
  "LIB_POLYVAL_<VARIANT>_<KIND>"` (e.g. `LIB_POLYVAL_AES_CODE`,
  `LIB_POLYVAL_HTABLE`) instead of bare `CODE` / `RODATA` / `BSS`.
  `src/c64.cfg` and `src/lib_only.cfg` carry SEGMENTS{} aliases back
  to the same memory areas as before; the linked PRG is byte-
  identical to the v0.2.0 baseline.
- Shared ZP slots renamed from `zp_*` to `polyval_*_*` (e.g.
  `zp_ptr` → `polyval_zp_ptr`, `zp_round` → `polyval_aes_round`).
  Cross-library prefix isolation per c64-lib-contract §2.
- The pre-v0.3.0 `make lib` target (library-only verification PRG
  link at `$4000`) is renamed to `make lib-verify`. The freed
  `make lib` name now produces the SPEC §6 ar65 archive at
  `build/lib/polyval.a`.

### Compatibility

This is a v0.x **MINOR** bump per c64-lib-contract SPEC §7
(breaking surface changes allowed pre-v1.0). Consumers vendoring
c64-polyval must:

1. Update `.importzp` lists: every `zp_*` slot (e.g. `zp_ptr`,
   `zp_round`, `zp_tmp1..tmp4`, `zp_ptr2`, `zp_temp`, `zp_count`)
   is renamed to its `polyval_*_*` form (see `src/zp_config.s` for
   the canonical names).
2. Update any custom ld65 cfg overlays referencing the old
   `CODE` / `RODATA` / `BSS` segment names — the library now
   emits `LIB_POLYVAL_*_*` segments.
3. Optionally add `.import LIB_ABI_VERSION` and an assemble-time
   `.assert LIB_ABI_VERSION = 1` gate, plus the SPEC §5 size
   asserts against `LIB_POLYVAL_ZP_USAGE_BYTES` &c.

The public POLYVAL / AES-256 / GCM-SIV entry-point names (§2.1,
§2.4, §2.7 in `API.md`) and their calling conventions are
unchanged.

Contract: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
SPEC v0.1.0 adoption — closes #12 (§1), #13 (§2), #14 (§4),
#15 (§5), #16 (§6).

## v0.2.0 — 2026-05-15

- Repackage to c64-nist-curves library format
- Retire ACME assembler support; consolidate to ca65 (cc65 toolchain)
- Replace dual root/ca65 Makefiles with single top-level Makefile
- Move ABI surface from `abi_v1.inc` to `src/exports.inc`
- Add MIT LICENSE
- Source tarball release format (`make dist VERSION=…`) replaces `.lib` archive shipping
- Preserve `ca65/release/v0.1.0/` as historical artifact

## v0.1.0 — (earlier)

- Initial public release. POLYVAL + AES-256-GCM-SIV with ca65+ACME parallel
  builds, LONG/SHORT profiles, `.lib` archive release format.
- Frozen at `ca65/release/v0.1.0/`.
