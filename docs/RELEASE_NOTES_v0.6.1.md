# c64-polyval v0.6.1 — 2026-08-15

**Contract v0.10.x alignment PATCH release** (contract at SPEC
v0.10.3 at release time; the upstream #76 restructuring is complete).
The §6.6 footprint corrections change exported equate *values* only —
no symbols added, removed, or renamed; `LIB_POLYVAL_ABI_VERSION`
stays 1 — and the linked PRG remains byte-identical to v0.4.1 on
both profiles. The full per-change log is in
[`CHANGELOG.md`](https://github.com/JC-000/c64-polyval/blob/v0.6.1/CHANGELOG.md); this file is the concise release
summary.

## What's in

- **§6.6 footprint-value corrections**
  ([PR #35](https://github.com/JC-000/c64-polyval/pull/35), per SPEC
  v0.10.0 §6.6 / contract
  [#69](https://github.com/JC-000/c64-lib-contract/issues/69)). Two
  defects fixed in `LIB_POLYVAL_RESIDENT_BYTES` /
  `LIB_POLYVAL_COLD_BYTES`: values rounded *down* from measured (the
  unsafe direction for §6.6's consumer budget asserts), and
  profile-only gating that let the POLYVAL-only archives claim
  footprints including AES/GCM-SIV code they do not ship —
  `polyval-long.a` declared 6500 B resident against a measured
  4160 B member set. Values are now gated on
  `POLYVAL_PROFILE` × `LIB_POLYVAL_NO_AES`, freshly measured per
  configuration, and rounded UP to the next 256-byte boundary (fleet
  convention).
- **Footprint deltas per (profile × variant)** — declared values;
  actual code size is unchanged (declaration corrections, not
  growth):

  | Archive / configuration | RESIDENT | COLD |
  |---|---|---|
  | `polyval.a` / `polyval-gcmsiv.a` (LONG AEAD) | 6500 → 6656 (+156) | 1200 → 1280 (+80) |
  | `POLYVAL_PROFILE=short` link (SHORT AEAD) | 16000 → 16128 (+128) | 3000 → 3072 (+72) |
  | `polyval-long.a` (LONG, no AES) | 6500 → 4352 (−2148) | 1200 → 1280 (+80) |
  | `polyval-short.a` (SHORT, no AES) | 16000 → 13824 (−2176) | 3000 → 3072 (+72) |

- **§6.6 consumer assert pattern** documented in API.md §9.5
  (`lderror` form against `__MAIN_SIZE__` under `define = yes`),
  with the polyval-specific note that `COLD` here is a carve-out of
  the `RESIDENT` image. **§6.7** (declared non-segment reservations)
  documented N/A — every polyval buffer is segment-resident.
- **SPEC v0.10.3 alignment pass**
  ([PR #36](https://github.com/JC-000/c64-polyval/pull/36),
  reviewer-endorsed): mechanical re-verification of every clause —
  canonical `precalc_table.inc` byte-identical (SHA256 `feb98890…`),
  §1/§2 export inventories, §4 annotations, §6.2 variables, PRG
  hashes — all conformant with no code change. Currency refreshed
  through v0.10.3 (stable-numbers reorder; SPEC snippet fixes this
  repo is audited clean for; the §8.4 heading promotion that made
  the fleet's citations retroactively correct).

## What's NOT shipped

- **No binary changes.** Linked PRG byte-identical to v0.4.1 on both
  profiles (LONG `e93962ac…`, SHORT `98948d02…`).
- **No export surface changes.** Same symbols as v0.6.0; only the
  two footprint equates' *values* moved. `LIB_POLYVAL_ABI_VERSION`
  stays 1.
- **No new crypto primitives, no AAD, no bulk encryption, no
  constant-time hardening** — unchanged; see API.md §6.
- **No §8.1–§8.3 / §6.3 `lib-app-owned` / §6.7 / §13 adoption** —
  all correctly N/A for this library.

## Upgrade notes for consumers

This is a v0.x **PATCH** bump (no API change). Consumers re-vendor
with no integration changes:

1. If you assert against `LIB_POLYVAL_RESIDENT_BYTES` /
   `LIB_POLYVAL_COLD_BYTES` (the §6.6 pattern, API.md §9.5), the
   declared values moved per the delta table above. AEAD consumers
   see small upward corrections (+128…+156 resident); POLYVAL-only
   archive consumers see large *downward* corrections — the old
   values over-claimed by ~2.1 KB, and a budget that previously
   false-refused a fitting configuration may now pass.
2. The values are now per-archive: the manifest inside each `.a`
   describes that archive's member set (SPEC §6.4/§6.6).
3. `LIB_POLYVAL_VERSION_PATCH` now exports `1`.

See `API.md` §9 for the full contract surface.

## Verification

Full suite run at release time (VICE `x64sc`, seed 8452), both
profiles: 376/376 passed, 6 skipped each — POLYVAL Direct 217/217,
GCM-SIV 159/165 + 6 AAD-by-design skips. `make consumer-check` and
all four §6 archive targets build clean; per-archive manifest values
verified via `ar65 x` + `od65 --dump-exports` on every archive's
`lib_manifest.o`.

### Byte-identity verification (worktree rebuild, appended post-release per [#37](https://github.com/JC-000/c64-polyval/issues/37))

Method: `git worktree add <dir> v0.4.1`; in the baseline worktree and
at the `v0.6.1` ref: `make clean && make` (LONG) and
`make clean && make POLYVAL_PROFILE=short` (SHORT);
`shasum -a 256 build/polyval.prg` after each.

| Profile | v0.4.1 rebuild | v0.6.1 rebuild | |
|---|---|---|---|
| LONG | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | identical |
| SHORT | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | identical |

## Attestation

`c64-polyval-v0.6.1.tar.gz` is produced reproducibly by
`make dist VERSION=v0.6.1`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.6.1.tar.gz` |
| **Size**   | 89569 bytes |
| **SHA256** | `24201c11eb4be6f9f5455597f87dcd941fa106c0faefef367cccb9c8c55b1daa` |

Re-running `make dist VERSION=v0.6.1` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's
mtime is forced to `2026-08-15T00:00:00Z`, owner/group are pinned to
`0:0` (numeric), and `gzip -n` drops the gzip timestamp+filename
header. The canonical vendoring file list lives in
`tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.6.1/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.6.1.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.4 enumeration)
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
driven by contract SPEC v0.10.0–v0.10.3. Constituent PRs: #35
(§6.6 footprints), #36 (v0.10.3 alignment pass, reviewer-endorsed).

Deferred (not release-blocking, carried from v0.4.1): optional C64U
16/48/64 MHz hardware sweep of `polyval_block` — needs physical
hardware.

## Known limitations

Carried over unchanged from v0.6.0; see `API.md` §6 for the full
list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.10.3, tagged).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git
  tag `lib-v0.1.0`).
