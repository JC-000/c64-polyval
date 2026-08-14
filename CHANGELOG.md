# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases: https://github.com/JC-000/c64-polyval/releases — tagged releases
track `MAJOR.MINOR.PATCH` and are the supported consumption points for
downstream projects (see `API.md` §8 for the integration contract).

## Unreleased

### Added

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
