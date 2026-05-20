# c64-polyval v0.3.0 — 2026-05-20

**c64-lib-contract v0.1.0 adoption (all six sections).** This release
implements every SPEC section that applies to c64-polyval:

- §1 — assemble-time `LIB_VERSION_*` / `LIB_ABI_VERSION` equates.
- §2 — every claimed zero-page slot declared in a dedicated
  `.exportzp` translation unit, under the `polyval_*` prefix.
- §3 — N/A; c64-polyval makes no REU claims.
- §4 — library `.segment` directives use the `LIB_POLYVAL_*` prefix.
- §5 — aggregate manifest equates (`ZP_USAGE_BYTES`,
  `REU_BANKS_USED`, `RESIDENT_BYTES`, `COLD_BYTES`).
- §6 — four ar65 archive Make targets producing single-file `.a`
  bundles.

POLYVAL / AES-256 / AES-256-GCM-SIV behaviour and entry-point
calling conventions are unchanged from v0.2.0. The full per-change
log is in [`CHANGELOG.md`](../CHANGELOG.md); this file is the
concise release summary.

## What's in

- **§1: `src/lib_version.s`** exports `LIB_VERSION_MAJOR=0`,
  `LIB_VERSION_MINOR=3`, `LIB_VERSION_PATCH=0`, and
  `LIB_ABI_VERSION=1` as absolute equates. Consumers `.import` them
  for assemble-time version gating.
- **§2: `src/zp_config.s`** extracts every claimed ZP slot from
  `constants_lib.inc` into a dedicated `.ifndef`-guarded +
  `.exportzp` translation unit. Suppression flag
  `ZP_CONFIG_NO_EXPORTS` mirrors the c64-x25519 / c64-nist-curves
  idiom for transitive includes. 13 slots, 45 bytes claimed across
  three discontiguous regions (`$02–$09`, `$10–$30`, `$fb–$fe`).
  Shared `zp_*` slots are renamed to `polyval_*_*` for cross-library
  prefix isolation.
- **§4: segment naming.** Library `.s` files now emit
  `.segment "LIB_POLYVAL_<VARIANT>_<KIND>"` (e.g.
  `LIB_POLYVAL_AES_CODE`, `LIB_POLYVAL_HTABLE`) instead of bare
  `CODE` / `RODATA` / `BSS`. `src/c64.cfg` and `src/lib_only.cfg`
  carry SEGMENTS{} aliases mapping the new names back to the same
  memory areas as before; the linked PRG is byte-identical to the
  v0.2.0 baseline (LONG: `e93962ac…` / 9474 B; SHORT: `98948d02…` /
  18928 B).
- **§5: `src/lib_manifest.s`** exports `LIB_POLYVAL_ZP_USAGE_BYTES`
  (45), `LIB_POLYVAL_REU_BANKS_USED` (0), and the profile-
  conditional `LIB_POLYVAL_RESIDENT_BYTES` (6500 LONG / 16000
  SHORT) + `LIB_POLYVAL_COLD_BYTES` (1200 LONG / 3000 SHORT).
  Values are within ±5% per SPEC §5 wording. See the file's
  derivation comments for the measurement methodology.
- **§6: four ar65 archive Make targets** under `build/lib/`:
  `make lib` (full AEAD bundle), `make lib-polyval-long`,
  `make lib-polyval-short`, and `make lib-polyval-gcmsiv` (alias
  for the AEAD bundle). The pre-v0.3.0 `make lib` target —
  library-only verification PRG at `$4000` — is renamed to
  `make lib-verify`.

## What's NOT shipped

This release is a **contract-adoption** release. The cryptographic
primitives are unchanged from v0.2.0; only the surface around them
moves. Specifically:

- **No new crypto primitives.** POLYVAL, AES-256, and AES-256-GCM-SIV
  entry points are unchanged in signature and contract. The linked
  PRG is byte-identical to v0.2.0 for both profiles.
- **No AAD support.** GCM-SIV still authenticates empty-AAD
  messages only.
- **No bulk-encryption support.** GCM-SIV plaintext is still capped
  at 64 bytes per call.
- **No constant-time hardening.** The library remains
  non-constant-time on all paths (public-input use only).

## Upgrade notes for consumers

This is a v0.x **MINOR** bump per c64-lib-contract SPEC §7
(breaking surface changes allowed pre-v1.0). Consumers vendoring
c64-polyval must:

1. **Rename ZP imports.** Every `zp_*` slot is renamed to its
   `polyval_*_*` form:

   | Old name | New name |
   |---|---|
   | `zp_ptr` | `polyval_zp_ptr` |
   | `zp_ptr2` | `polyval_zp_ptr2` |
   | `zp_temp` | `polyval_zp_temp` |
   | `zp_count` | `polyval_zp_count` |
   | `zp_round` | `polyval_aes_round` |
   | `zp_col` | `polyval_aes_col` |
   | `zp_tmp1..tmp4` | `polyval_aes_tmp1..tmp4` |

   `polyval_acc`, `pv_mul_input`, and `pv_mul_nibble` are
   unchanged (they already carried POLYVAL-style names).

2. **Rename segment references in custom cfg overlays.** A consumer
   that copied `src/c64.cfg` and extended it must update any
   references to the old bare `CODE` / `RODATA` / `BSS` library
   segments to the new `LIB_POLYVAL_*_*` names. The
   `src/c64.cfg` / `src/lib_only.cfg` shipped in this release are
   the canonical templates.

3. **Rename `make lib` invocations**, if your consumer build
   system shells out to it expecting a verification PRG. The old
   behaviour is now `make lib-verify`; the new `make lib`
   produces a `.a` archive instead.

4. **Optionally adopt the contract surface.** Add
   `.import LIB_ABI_VERSION` (or `LIB_VERSION_MAJOR/MINOR`) and
   `.assert` against them for cross-library version gating, and
   `.import LIB_POLYVAL_ZP_USAGE_BYTES` /
   `LIB_POLYVAL_RESIDENT_BYTES` for collision asserts. See
   `API.md` §9.6 for a worked snippet.

The POLYVAL / AES-256 / GCM-SIV entry-point names and calling
conventions are unchanged. See `API.md` §9 for the full contract
surface.

## Attestation

`c64-polyval-v0.3.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.3.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.3.0.tar.gz` |
| **Size**   | 65362 bytes |
| **SHA256** | `6a366de3fd4876486206336ab573acb55548a05751859f8354e54a5186356945` |

Re-running `make dist VERSION=v0.3.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's
mtime is forced to `2026-05-20T00:00:00Z`, owner/group are pinned to
`0:0` (numeric), and `gzip -n` drops the gzip timestamp+filename
header. The canonical vendoring file list lives in
`tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.3.0/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.3.0.md` (this file)
- `src/*.s` (library + demo-app sources, including the new
  `src/lib_version.s`, `src/zp_config.s`, and `src/lib_manifest.s`)
- `src/*.inc` (public headers: `exports.inc`, `polyval_api.inc`,
  `constants_lib.inc`, `constants_app.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs with the
  `LIB_POLYVAL_*` SEGMENTS{} aliases)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor
metadata.

## Issues closed

This release closes the c64-lib-contract adoption tracking issues:

- #12 — §1: `LIB_VERSION_*` / `LIB_ABI_VERSION` (commit `2813d00`).
- #13 — §2: `src/zp_config.s` ZP inventory (commit `2813d00`).
- #14 — §4: `LIB_POLYVAL_*` segment naming (commit `addf7ea`,
  merged via `b21e910`).
- #15 — §5: `src/lib_manifest.s` aggregate equates (commit `1df2300`).
- #16 — §6: ar65 archive Make targets (commit `1df2300`).

## Known limitations

Carried over unchanged from v0.2.0; see `API.md` §6 for the full
list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.1.0).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git
  tag `lib-v0.1.0`).
