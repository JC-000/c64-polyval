# c64-polyval v0.7.1 — 2026-08-23

**Consumer-unblocking PATCH** (contract at SPEC v0.10.6 at release
time). The POLYVAL-only archives could not be linked by any consumer
that owns its own AES — which is precisely the consumer they exist for.
Nothing exported was removed or renamed, no declared footprint moved,
and the linked PRG is byte-identical to v0.7.0 on both profiles, so
`LIB_POLYVAL_ABI_VERSION` stays 1. The full per-change log is in
[`CHANGELOG.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.1/CHANGELOG.md);
this file is the concise release summary.

## What's in

- **`polyval-long.a` / `polyval-short.a` no longer export the AES +
  GCM-SIV BSS block**
  ([#47](https://github.com/JC-000/c64-polyval/issues/47),
  [PR #48](https://github.com/JC-000/c64-polyval/pull/48)). Both
  archives shipped 21 AES/GCM-SIV BSS exports — `aes_state`,
  `aes_current_key`, `aes_expanded_key`, `aes_mc_a0..b3` and the full
  `gcmsiv_*` set — so any consumer defining its own AES or GCM-SIV hit
  `ld65: Error: Duplicate external identifier` on the first link.

  Root cause: `src/data.s` is a single monolithic BSS TU and `data.o` is
  archived whole into every variant, so `LIB_POLYVAL_NO_AES` gated the
  §5 manifest rows ([#23](https://github.com/JC-000/c64-polyval/issues/23))
  but never the storage those rows enumerate. This is #23's defect class
  one layer down: #23 fixed the enumeration, not the thing enumerated.
  Both BSS blocks are now gated on `.ifndef LIB_POLYVAL_NO_AES`;
  POLYVAL references none of them.

- **`make consumer-check-noaes`** — a regression guard for the above.
  It links
  [`test/consumer_stub_noaes.s`](https://github.com/JC-000/c64-polyval/blob/v0.7.1/test/consumer_stub_noaes.s),
  which deliberately *defines* its own `aes_state` and `gcmsiv_tag`,
  against the real `polyval-long.a` and `polyval-short.a`. Both
  profiles, because `data.o` is archived into each and can regress
  independently. It uses `.forceimport` rather than `.import`: ca65
  drops an unreferenced plain import, which would leave the archive
  unextracted and the guard toothless. Verified in both directions — it
  fails on the pre-fix tree (`Duplicate external identifier:
  'gcmsiv_tag'`, make exit 2) and passes after.

## Footprint values per (profile × variant)

Declared values (SPEC §6.6 obligation 2). Five archive rows; **no
declared value moved this cycle**:

| Archive / configuration | RESIDENT | COLD |
|---|---|---|
| `polyval.a` / `polyval-gcmsiv.a` (LONG AEAD) | 6656 (unchanged) | 1280 (unchanged) |
| `polyval-gcmsiv-short.a` (SHORT AEAD) | 16128 (unchanged) | 3072 (unchanged) |
| `polyval-long.a` (LONG, no AES) | 4352 (unchanged) | 1280 (unchanged) |
| `polyval-short.a` (SHORT, no AES) | 13824 (unchanged) | 3072 (unchanged) |

**Why a bug that removed ~1.1 KB of BSS moved no value.**
`LIB_POLYVAL_RESIDENT_BYTES` is code+rodata only — BSS is excluded per
SPEC §5 wording, as
[`src/lib_manifest.s`](https://github.com/JC-000/c64-polyval/blob/v0.7.1/src/lib_manifest.s)
documents — and `LIB_POLYVAL_COLD_BYTES` is a code-span carve-out. This
defect was BSS-only, so neither NO_AES row is affected. Re-measured
after the fix with the scratch-`LOADADDR` method the manifest records:

| Configuration | Resident span | Measured | Declared |
|---|---|---|---|
| LONG NO_AES | `LIB_POLYVAL_LONG_CODE` `$4000..$503F` | 4160 | 4352 |
| SHORT NO_AES | `LIB_POLYVAL_SHORT_CODE` `$4000..$752D` | 13614 | 13824 |

Both match the 2026-08-15 measurements exactly. The
`LIB_POLYVAL_AES_BSS` and `LIB_POLYVAL_GCMSIV_BSS` segments are simply
absent from a NO_AES link now, where before they were allocated.

## What's NOT shipped

- **No binary changes.** Linked PRG byte-identical to v0.7.0 on both
  profiles — receipt below.
- **No export surface removals or renames** *for the archives' intended
  surface*. `LIB_POLYVAL_ABI_VERSION` stays 1. See the upgrade note
  below on the one honest caveat.
- **No manifest value changes**, no new archive targets, no new §6.1
  goals.
- **No new crypto primitives, no AAD, no bulk encryption, no
  constant-time hardening** — unchanged; see
  [`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.1/API.md)
  §6.
- **No §8.1–§8.3 / §6.3 `lib-app-owned` / §6.7 / §13 adoption** — all
  correctly N/A for this library.

## Upgrade notes for consumers

This is a v0.x **PATCH** bump.

1. `LIB_POLYVAL_VERSION_PATCH` now exports `1`; `_MINOR` stays `7`. A
   consumer asserting `>= 7` or `>= 4` continues to link.
2. **If you consume `polyval-long.a` or `polyval-short.a`, upgrade.**
   Before v0.7.1 those archives were unlinkable alongside your own AES
   or GCM-SIV. Nothing on your side needs to change — the link simply
   starts working.
3. **Honest caveat, the one behaviour change.** If you were *depending*
   on the POLYVAL-only archives to supply AES or GCM-SIV BSS —
   `aes_state`, `gcmsiv_tag`, and so on — those symbols are gone from
   them, by design. That dependency could only ever have been
   accidental: the archives ship no AES or GCM-SIV *code* to use the
   storage with. If you want that surface, link an AEAD archive
   (`polyval.a`, `polyval-gcmsiv.a`, `polyval-gcmsiv-short.a`), which is
   unchanged and still exports all of it.
4. AEAD-archive consumers are unaffected in every respect.

See [`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.1/API.md)
§9 for the full contract surface.

## Verification

Full suite at release time (VICE `x64sc`, seed 8452): 376/376 passed, 6
skipped — POLYVAL Direct 217/217, GCM-SIV 159/165 + 6 AAD-by-design
skips, matching the documented baseline. `make consumer-check`,
`make consumer-check-noaes`, `lib-verify`, and all **five** §6 archive
targets build clean.

Per-archive manifest values verified by `ar65 x` + `od65
--dump-exports` on each archive's own `lib_manifest.o`:

| Archive | RESIDENT | COLD |
|---|---|---|
| `polyval.a` | 6656 | 1280 |
| `polyval-gcmsiv.a` | 6656 | 1280 |
| `polyval-gcmsiv-short.a` | 16128 | 3072 |
| `polyval-long.a` | 4352 | 1280 |
| `polyval-short.a` | 13824 | 3072 |

The fix itself was verified by extracting every member of each archive
with `ar65 x` into a clean directory and running `od65 --dump-exports`
over all of them: **0** AES/GCM-SIV exports in `polyval-long.a` and
`polyval-short.a` (was 21), and **54** still present in `polyval.a` and
`polyval-gcmsiv-short.a` — confirming the AEAD archives did not
regress.

### Byte-identity verification (worktree rebuild)

Method: `git worktree add --detach <dir> v0.7.0`; in the baseline
worktree and in the v0.7.1 tree: `make clean && make` (LONG) and
`make clean && make POLYVAL_PROFILE=short` (SHORT);
`shasum -a 256 build/polyval.prg` after each.

| Profile | v0.7.0 rebuild | v0.7.1 rebuild | |
|---|---|---|---|
| LONG | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | identical |
| SHORT | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | identical |

This is the expected result: the demo app builds without
`LIB_POLYVAL_NO_AES`, so the `.ifndef` gate is inactive on that path and
`data.s` assembles exactly as before.

**Method note — this applies to PRGs only.** `.o` and `.a` files are
*not* byte-comparable across build paths or across builds separated in
time: `ca65` stamps a wall-clock `OPT_DATETIME` (seconds granularity)
into every object and records source paths and mtimes in the object's
`Files:` section, both unconditionally and independent of `-g`. `ar65`
adds nothing. Consequently a raw archive-hash diff is a coin flip on
build timing, and extracting members gives no immunity since the stamp
lives inside each member. Compare linked output — as above — or `od65`
structural dumps. This finding is recorded upstream as SPEC v0.10.5
§6.3's checkability note.

## Attestation

`c64-polyval-v0.7.1.tar.gz` is produced reproducibly by
`make dist VERSION=v0.7.1`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.7.1.tar.gz` |
| **Size**   | 96965 bytes |
| **SHA256** | `ce490617d4b2a32662f785ee077666e2e7090badcd40138a1ee44bdfb325b39a` |

Re-running `make dist VERSION=v0.7.1` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime
is forced to `2026-08-23T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.7.1/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.7.1.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.4 enumeration)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers, including `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs, with the §4
  placement declarations)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor metadata.
Note that `test/consumer_stub_noaes.s`, added this release, is therefore
**not** vendored — like `test/consumer_stub.s` before it, it is a
repo-side guard, not consumer-facing surface.

## Issues and coordination

[#47](https://github.com/JC-000/c64-polyval/issues/47) closed by
[PR #48](https://github.com/JC-000/c64-polyval/pull/48).

**How this was found.**
[c64-aes256-ecdsa](https://github.com/JC-000/c64-aes256-ecdsa) is
adopting the contract and consuming this library. It ships its own
AES-256 and its own GCM-SIV, so it wants the POLYVAL-only archives — and
all 21 leaked symbols collide with symbols it defines. It had pinned
`libs/polyval` as a submodule at tag `v0.7.0`, which is why this is a
PATCH release rather than a note on `master`: a tag-pinned submodule
cannot consume an unmerged branch.

Four further integration items are consumer-side and recorded on
[#47](https://github.com/JC-000/c64-polyval/issues/47) rather than fixed
here — `.import polyval_acc` must become `.importzp` (it is an
`.exportzp` slot at `$10`); the vendored `src/polyval.s` and its
`polyval_h` / `polyval_temp` / `polyval_htable` `.res` blocks must be
dropped; ZP ranges `$10-$30` overlap that consumer's `sha_*` / `fp_*`
slots and need `CONTRACT_ZP_DEFINES` relocation; and its own §1
`LIB_VERSION_*` exports need `CONTRACT_DEFINES='-D
LIB_NO_BARE_EXPORTS=1'`. The latter two knobs were confirmed working
against the POLYVAL-only archives as part of this release — including
that a ZP override reaches the code TUs and not merely the exports, so
baked equates cannot silently diverge from exported ones.

Deferred (not release-blocking, carried from v0.7.0): optional C64U
16/48/64 MHz hardware sweep of `polyval_block` — needs physical
hardware.

## Known limitations

Carried over unchanged from v0.7.0; see
[`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.1/API.md)
§6 for the full list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.10.6, tagged).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git tag
  `lib-v0.1.0`).
