# c64-polyval v0.4.0 — 2026-07-16

**c64-lib-contract currency update: SPEC §8.0 catch-loop enumeration
+ a stale-export fix.** The upstream
[c64-lib-contract](https://github.com/JC-000/c64-lib-contract) has
advanced from v0.1.0 (adopted in v0.3.0) to v0.4.0. Of the sections
added since — §7 (doc-only semver renumbering) and §8 (shared
primitives) — only §8.0's precalculated-table enumeration duty
applies to c64-polyval; §8.1–§8.3 remain N/A because GF(2^128)
carry-less multiplication shares no shape with the 8×8
quarter-square-multiply primitive the curve/ChaCha20 libraries
converged on. This release also fixes a version-export bug that has
been live since v0.3.0.

POLYVAL / AES-256 / AES-256-GCM-SIV behaviour and entry-point
calling conventions are unchanged. The full per-change log is in
[`CHANGELOG.md`](../CHANGELOG.md); this file is the concise release
summary.

## What's in

- **§8.0: precalculated-table enumeration.**
  [`src/precalc_table.inc`](../src/precalc_table.inc) is the
  canonical `LIB_PRECALC_TABLE` macro copied verbatim from the
  contract repo. `src/lib_manifest.s` registers the five tables that
  clear the SPEC floor (≥ 256 B AND hot-loop-read / page-aligned):
  `polyval_htable` (256 B, both profiles), `polyval_htable8` /
  `polyval_reduce8` (4096 B each, LONG profile only), `aes_sbox` /
  `aes_inv_sbox` (256 B each, both profiles) — all classified
  `PRECALC_SHARED_NO`. [`docs/precalc-tables.md`](precalc-tables.md)
  carries the required human-readable rationale per table plus the
  below-floor exempt list. See `API.md` §9.6 for the consumer-facing
  summary.
- **Bugfix: `LIB_VERSION_MINOR` / `LIB_VERSION_PATCH` drift.**
  `src/lib_version.s` had exported `LIB_VERSION_MINOR = 2` /
  `LIB_VERSION_PATCH = 0` — i.e. "v0.2.0" — continuously since the
  v0.3.0 release, because the v0.3.0 release commit bumped the
  `VERSION` file and `API.md`'s documented value but never touched
  `src/lib_version.s` itself. A consumer following `API.md` §9.6's
  own worked example (`.assert LIB_VERSION_MINOR >= 3`) would have
  failed to link against the real v0.3.0/v0.3.x releases. Now
  correctly exports `LIB_VERSION_MINOR = 4`, `LIB_VERSION_PATCH = 0`.

## What's NOT shipped

This release is a **contract-currency** release, same category as
v0.3.0. The cryptographic primitives are unchanged:

- **No new crypto primitives.** POLYVAL, AES-256, and AES-256-GCM-SIV
  entry points are unchanged in signature and contract.
- **No AAD support.** GCM-SIV still authenticates empty-AAD
  messages only.
- **No bulk-encryption support.** GCM-SIV plaintext is still capped
  at 64 bytes per call.
- **No constant-time hardening.** The library remains
  non-constant-time on all paths (public-input use only).
- **No §8.1–§8.3 shared-primitive adoption.** Correctly N/A — see
  above.

## Upgrade notes for consumers

This is a v0.x **MINOR** bump per c64-lib-contract SPEC §7 (new
exported symbols, no removals or renames). Consumers vendoring
c64-polyval should:

1. **Re-check any `LIB_VERSION_MINOR` gate.** If your consumer
   asserts `LIB_VERSION_MINOR >= 3` against a vendored v0.3.x tag,
   note that tag was *actually exporting* `LIB_VERSION_MINOR = 2`
   until this release (see Bugfix above) — the assert would have
   failed at assemble time. Re-vendor to v0.4.0 to get a
   `LIB_VERSION_MINOR` that matches the tag.
2. **Optionally cross-check the precalc-table shape.** If your
   consumer links c64-polyval alongside other c64-lib-contract
   adopters and wants to confirm none of POLYVAL's tables
   double-claim a shared shape:
   `od65 --dump-exports build/lib_manifest.o | grep LIB_PRECALC`.
3. No ZP, segment, or build-target changes from v0.3.0 — those
   surfaces are unchanged.

See `API.md` §9 for the full contract surface.

## Attestation

`c64-polyval-v0.4.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.4.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.4.0.tar.gz` |
| **Size**   | 69311 bytes |
| **SHA256** | `731b047e952cbce759302927b9b450e2ae0dc8dc6423ce1e22bfb01de6035f79` |

Re-running `make dist VERSION=v0.4.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's
mtime is forced to `2026-07-16T00:00:00Z`, owner/group are pinned to
`0:0` (numeric), and `gzip -n` drops the gzip timestamp+filename
header. The canonical vendoring file list lives in
`tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.4.0/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.4.0.md` (this file)
- `docs/precalc-tables.md` (new — SPEC §8.0 enumeration)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers, including the new
  `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor
metadata.

## Issues closed

None — this is a proactive contract-currency update rather than a
response to a filed tracking issue. Note: the contract repo's own
[`adopters.md`](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md)
row for c64-polyval is stale (still shows §1–§6 as ❌ todo despite
issues #12–#16 being closed since v0.3.0, and has no §8.0 column
entry). Updating that row is tracked as a follow-up PR against the
contract repo, not part of this release.

## Known limitations

Carried over unchanged from v0.3.0; see `API.md` §6 for the full
list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.4.0).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git
  tag `lib-v0.1.0`).
