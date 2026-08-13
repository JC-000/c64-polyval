# c64-polyval v0.5.0 — 2026-08-13

**Contract v0.7.0 adoption MINOR release.** Adopts the
[c64-lib-contract](https://github.com/JC-000/c64-lib-contract) v0.7.0
prefixed-export surface (§1 version equates + §8.4 precalc-table
equates; contract at SPEC v0.7.3 at release time) and fixes a §8.0
manifest-accuracy defect in the POLYVAL-only archives. New exported
symbols only — no removals, no renames, `LIB_POLYVAL_ABI_VERSION`
stays 1, and the linked PRG is byte-identical to v0.4.1 on both
profiles. The full per-change log is in
[`CHANGELOG.md`](../CHANGELOG.md); this file is the concise release
summary.

## What's in

- **§1 prefixed version exports**
  ([#21](https://github.com/JC-000/c64-polyval/issues/21) via
  [PR #26](https://github.com/JC-000/c64-polyval/pull/26)).
  `src/lib_version.s` exports `LIB_POLYVAL_VERSION_{MAJOR,MINOR,PATCH}`
  / `LIB_POLYVAL_ABI_VERSION` as the permanent, collision-free form a
  consumer linking multiple contract adopters imports side by side.
  The deprecated bare `LIB_VERSION_*` names remain exported by
  default through contract v0.x, gated on `LIB_NO_BARE_EXPORTS`
  (`ca65 -D LIB_NO_BARE_EXPORTS=1`), and alias the prefixed literals
  so the two forms cannot drift.
- **§8.4 prefixed precalc-table exports**
  ([#22](https://github.com/JC-000/c64-polyval/issues/22) via
  [PR #24](https://github.com/JC-000/c64-polyval/pull/24)).
  `src/precalc_table.inc` re-copied byte-for-byte from the canonical
  contract root (SHA256-verified); all five `LIB_PRECALC_TABLE`
  invocations pass `"POLYVAL"` as the fifth argument, emitting
  `LIB_POLYVAL_PRECALC_<name>_{SIZE,REGION,SHARED}` alongside the
  deprecated bare triple. Audit greps should target `_PRECALC_`,
  which matches both forms.
- **§8.0 manifest accuracy for the POLYVAL-only archives**
  ([#23](https://github.com/JC-000/c64-polyval/issues/23) via
  [PR #25](https://github.com/JC-000/c64-polyval/pull/25)).
  `polyval-long.a` / `polyval-short.a` no longer enumerate
  `aes_sbox` / `aes_inv_sbox` — 512 B of tables only the AEAD bundle
  ships. The AES manifest rows are gated on `LIB_POLYVAL_NO_AES`,
  set by the `lib-polyval-{long,short}` targets via the new
  `POLYVAL_NO_AES=1` Makefile knob; archive membership is an axis
  `POLYVAL_PROFILE` cannot express (`polyval-long.a` and
  `polyval-gcmsiv.a` are both PROFILE=long).
- **Docs.** API.md §9.1/§9.6 rewritten for the two export forms
  (§9.1's value table also fixed — it had been stale at PATCH 0
  since v0.4.1); `docs/precalc-tables.md` states which archives
  carry each table; contract references bumped to SPEC v0.7.3.

## What's NOT shipped

- **No binary changes.** The linked PRG is byte-identical to v0.4.1
  on both profiles (LONG `e93962ac…`, SHORT `98948d02…` before and
  after every constituent PR).
- **No new crypto primitives.** POLYVAL, AES-256, and
  AES-256-GCM-SIV entry points are unchanged in signature and
  contract.
- **No AAD support.** GCM-SIV still authenticates empty-AAD
  messages only.
- **No bulk-encryption support.** GCM-SIV plaintext is still capped
  at 64 bytes per call.
- **No constant-time hardening.** The library remains
  non-constant-time on all paths (public-input use only).
- **No §8.1–§8.3 shared-primitive adoption.** Correctly N/A —
  GF(2^128) carry-less multiplication shares no shape with the 8×8
  quarter-square-multiply primitive. No
  `LIB_POLYVAL_SHARED_PRIMITIVES` mask is emitted, which also makes
  contract v0.7.3's §8 bit-constant export prohibition N/A here.

## Upgrade notes for consumers

This is a v0.x **MINOR** bump per c64-lib-contract SPEC §7 (additive
API change). Consumers vendoring c64-polyval re-vendor with no
mandatory integration changes:

1. Existing bare-name imports (`LIB_VERSION_*`, `LIB_PRECALC_*`)
   keep working unchanged in default builds — the bare forms stay
   exported through contract v0.x.
2. New consumers, and any consumer linking two or more contract
   adopters, should import the `LIB_POLYVAL_*` prefixed forms and
   build every library with `ca65 -D LIB_NO_BARE_EXPORTS=1`; the
   bare names collide across adopters and are removed at contract
   v1.0.
3. If you consume `polyval-long.a` or `polyval-short.a` and imported
   the AES precalc equates from them, that import now fails at link
   time — correctly: those archives never contained the tables the
   equates described. Import them from the AEAD bundle instead.
4. `LIB_POLYVAL_VERSION_MINOR` now exports `5`; a
   `MINOR >= 4` gate per API.md's worked example is unaffected.

See `API.md` §9 for the full contract surface.

## Verification

Full suite run at release time (VICE `x64sc`, seed 8452), both
profiles: 376/376 passed, 6 skipped each — POLYVAL Direct 217/217,
GCM-SIV 159/165 + 6 AAD-by-design skips. `make consumer-check`
(which now imports both §1 export forms) and all four §6 archive
targets build clean. Per-archive manifest audit via `ar65 x` +
`od65 --dump-exports`: `polyval-long.a` 18 `_PRECALC_` exports (zero
AES), `polyval-short.a` 6, AEAD bundle 30 including all 12 AES
equates.

## Attestation

`c64-polyval-v0.5.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.5.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.5.0.tar.gz` |
| **Size**   | 75571 bytes |
| **SHA256** | `45c2a7abb32edf42e67171a7d2a5a576d2d6cc1adbb31c891b5fc0d35e5d9445` |

Re-running `make dist VERSION=v0.5.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's
mtime is forced to `2026-08-13T00:00:00Z`, owner/group are pinned to
`0:0` (numeric), and `gzip -n` drops the gzip timestamp+filename
header. The canonical vendoring file list lives in
`tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.5.0/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.5.0.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.0 enumeration)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers, including `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor
metadata.

## Issues closed

- [#21](https://github.com/JC-000/c64-polyval/issues/21) — §1
  prefixed version exports + `LIB_NO_BARE_EXPORTS` gating (closed by
  [PR #26](https://github.com/JC-000/c64-polyval/pull/26)).
- [#22](https://github.com/JC-000/c64-polyval/issues/22) — §8.4
  canonical `precalc_table.inc` refresh + `"POLYVAL"` prefix (closed
  by [PR #24](https://github.com/JC-000/c64-polyval/pull/24)).
- [#23](https://github.com/JC-000/c64-polyval/issues/23) —
  POLYVAL-only archives enumerated AES tables they don't ship
  (closed by [PR #25](https://github.com/JC-000/c64-polyval/pull/25)).

Deferred (not release-blocking, carried from v0.4.1): optional C64U
16/48/64 MHz hardware sweep of `polyval_block` to empirically
confirm the documented turbo scaling — needs physical hardware;
compare within a single run (the 48 MHz jiffy rate drifts ~3.8%
across reboots).

## Known limitations

Carried over unchanged from v0.4.1; see `API.md` §6 for the full
list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.7.3).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git
  tag `lib-v0.1.0`).
