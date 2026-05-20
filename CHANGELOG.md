# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases: https://github.com/JC-000/c64-polyval/releases — tagged releases
track `MAJOR.MINOR.PATCH` and are the supported consumption points for
downstream projects (see `API.md` §8 for the integration contract).

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
