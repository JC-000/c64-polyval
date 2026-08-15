# c64-polyval v0.7.0 — 2026-08-15

**SHORT+AEAD reachability release** (contract at SPEC v0.10.6 at
release time). A v0.x **MINOR** bump: `lib-polyval-gcmsiv-short` is a
new §6.1 archive target and therefore new consumer-visible surface —
but nothing exported was removed or renamed, so
`LIB_POLYVAL_ABI_VERSION` stays 1, and the linked PRG remains
byte-identical to v0.4.1 on both profiles. The full per-change log is
in [`CHANGELOG.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.0/CHANGELOG.md);
this file is the concise release summary.

## What's in

- **`make lib-polyval-gcmsiv-short`** — the full AEAD bundle (POLYVAL +
  AES-256 + GCM-SIV) on the **SHORT** profile, at
  `build/lib/polyval-gcmsiv-short.a`
  ([#40](https://github.com/JC-000/c64-polyval/issues/40),
  [PR #42](https://github.com/JC-000/c64-polyval/pull/42)). This is the
  RFC 8452 per-message-`H` configuration the docs have recommended
  since v0.2.0 — and which, until now, no archive delivered.
- **SHORT+AEAD was documented but undeliverable, and failed silently.**
  `LIB_AEAD_OBJS` pinned `polyval_long.o` while `POLYVAL_PROFILE` still
  reached `CA65FLAGS`, so `make lib POLYVAL_PROFILE=short` exited 0 and
  archived the LONG multiply against a SHORT-assembled `data.o` and
  `lib_manifest.o`. The artifact was simultaneously unlinkable
  (`polyval_long.o` imports `polyval_htable8_s*` / `polyval_reduce8_s*`,
  which SHORT `data.o` does not export) and §6.4-violating (its manifest
  claimed the SHORT footprints over LONG code). `ar65` cannot detect
  either. `LIB_AEAD_OBJS` now uses `$(POLYVAL_PROFILE_OBJ)`.
- **Every archive goal asserts its configuration pair.** A `PIN_` table
  in the `Makefile` declares the required
  `(POLYVAL_PROFILE × LIB_POLYVAL_NO_AES)` pair for each archive goal
  and checks it at parse time, so a mismatched invocation is rejected
  before any object is assembled. This closed two further silent-wrong-
  artifact paths found in review: `make build/lib/polyval-gcmsiv-short.a`
  at the default profile shipped LONG code under the `-short` name, and
  `make build/lib/polyval-short.a` shipped SHORT code with the LONG AEAD
  manifest value (6656 rather than 13824) — incoherent, §6.4-violating,
  and pre-existing.
- **Contract SPEC currency v0.10.3 → v0.10.6.** v0.10.4 scoped §6.3's
  "no further target matrix" posture to *define-reachable* combinations;
  v0.10.5 added the *looks-reachable* rule — a knob naming an axis MUST
  select it in both member selection and assembly configuration, or
  reject the invocation loudly — satisfied here by the `PIN_` table with
  no code change. v0.10.6 (§8.3 provider surface) is N/A: this library
  neither provides nor defers any §8.1–§8.3 primitive.
  **c64-polyval#40 is the upstream motivating case for v0.10.5's
  clause**, and the `OPT_DATETIME` finding below became that clause's
  checkability note.
- **Release-tooling fix.** `tools/build_release.sh` reset *any* 64-hex
  hash in the notes to the attestation placeholder and then stamped the
  tarball's hash over *all* of them. With the byte-identity receipt that
  CLAUDE.md's release flow now requires, that rewrote the receipt into a
  row of identical hashes still shaped like a passing check. The reset
  is now scoped to the attestation row, and stamping refuses to proceed
  unless exactly one placeholder of each kind is present.

## Footprint values per (profile × variant)

Declared values (SPEC §6.6 obligation 2). One tag now carries **five**
archive rows; no declared value moved this cycle:

| Archive / configuration | RESIDENT | COLD |
|---|---|---|
| `polyval.a` / `polyval-gcmsiv.a` (LONG AEAD) | 6656 (unchanged) | 1280 (unchanged) |
| `polyval-gcmsiv-short.a` (SHORT AEAD) | 16128 (**new archive**) | 3072 (**new archive**) |
| `polyval-long.a` (LONG, no AES) | 4352 (unchanged) | 1280 (unchanged) |
| `polyval-short.a` (SHORT, no AES) | 13824 (unchanged) | 3072 (unchanged) |

The SHORT AEAD pair (16128 / 3072) is not new *as a value* — v0.6.1
already declared it for the configuration
[`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.0/API.md)
§9.4 listed with `—` in its Archive column. v0.7.0 is the release in
which an archive finally carries it.

## What's NOT shipped

- **No binary changes.** Linked PRG byte-identical to v0.4.1 on both
  profiles — receipt below.
- **No export surface removals or renames.** `LIB_POLYVAL_ABI_VERSION`
  stays 1. The new surface is a make target, not a symbol.
- **No new crypto primitives, no AAD, no bulk encryption, no
  constant-time hardening** — unchanged; see API.md §6.
- **No §8.1–§8.3 / §6.3 `lib-app-owned` / §6.7 / §13 adoption** — all
  correctly N/A for this library.

## Upgrade notes for consumers

This is a v0.x **MINOR** bump. Existing integrations need no changes:

1. `LIB_POLYVAL_VERSION_MINOR` now exports `7`, `_PATCH` `0`. A
   consumer asserting `>= 6` continues to link.
2. **If you want SHORT + AEAD, there is now an archive for it**: build
   `make lib-polyval-gcmsiv-short` and link
   `build/lib/polyval-gcmsiv-short.a`. Previously the only route was a
   full-source link; the archive route silently produced a broken
   artifact.
3. **`make lib POLYVAL_PROFILE=short` is now rejected** rather than
   silently producing a wrong archive. Use the named target above. The
   same applies to naming an archive's file path directly without its
   pair — use the phony targets, which clean and pin for you.
4. Footprint equates are unchanged from v0.6.1; no §6.6 assert needs
   revisiting.

See [`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.0/API.md)
§9 for the full contract surface.

## Verification

Full suite at release time (VICE `x64sc`, seed 8452), **both
profiles**: 376/376 passed, 6 skipped each — POLYVAL Direct 217/217,
GCM-SIV 159/165 + 6 AAD-by-design skips. `make consumer-check`,
`lib-verify`, and all **five** §6 archive targets build clean.

Per-archive manifest values verified by `ar65 x` + `od65
--dump-exports` on each archive's own `lib_manifest.o` — 6656/1280,
6656/1280, 16128/3072, 4352/1280, 13824/3072 respectively. The new
archive's symbol closure was checked directly: 115 exports, 43 imports,
**0 unresolved** (`polyval.a` for comparison: 161/75/0), which is the
property the old SHORT+AEAD build violated.

### Byte-identity verification (worktree rebuild)

Method: `git worktree add <dir> v0.4.1`; in the baseline worktree and
in the v0.7.0 tree: `make clean && make` (LONG) and
`make clean && make POLYVAL_PROFILE=short` (SHORT);
`shasum -a 256 build/polyval.prg` after each.

| Profile | v0.4.1 rebuild | v0.7.0 rebuild | |
|---|---|---|---|
| LONG | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | identical |
| SHORT | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | identical |

**Method note — this applies to PRGs only.** `.o` and `.a` files are
*not* byte-comparable across build paths or across builds separated in
time: `ca65` stamps a wall-clock `OPT_DATETIME` (seconds granularity)
into every object and records source paths and mtimes in the object's
`Files:` section, both unconditionally and independent of `-g`. `ar65`
adds nothing — `touch`-ing every `.o` and re-archiving reproduces the
archive byte-for-byte. Measured: two assembles of `src/data.s` three
seconds apart differ in exactly one byte, offset 101, the low byte of
that field; two inside the same second are identical. Consequently a
raw archive-hash diff is a coin flip on build timing, and extracting
members gives no immunity since the stamp lives inside each member.
Compare linked output — as above — or `od65` structural dumps. This
finding is recorded upstream as SPEC v0.10.5 §6.3's checkability note.

## Attestation

`c64-polyval-v0.7.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.7.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.7.0.tar.gz` |
| **Size**   | 94787 bytes |
| **SHA256** | `ba7941166dac47bbba0bebd9f25b9f48e4271378bf3a1cfd73fffd3af774c1b5` |

Re-running `make dist VERSION=v0.7.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime
is forced to `2026-08-15T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.7.0/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.7.0.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.4 enumeration)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers, including `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs, with the §4
  placement declarations)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor metadata.

## Issues and coordination

[#40](https://github.com/JC-000/c64-polyval/issues/40) closed by
[PR #42](https://github.com/JC-000/c64-polyval/pull/42). Constituent
PRs: [#41](https://github.com/JC-000/c64-polyval/pull/41) (parse-time
stopgap), [#42](https://github.com/JC-000/c64-polyval/pull/42) (the
§6.1 target + PIN table),
[#43](https://github.com/JC-000/c64-polyval/pull/43) (SPEC currency
v0.10.4 → v0.10.6).

Upstream coordination: contract
[#117](https://github.com/JC-000/c64-lib-contract/issues/117) (v0.10.4
changelog record correction) and
[#118](https://github.com/JC-000/c64-lib-contract/pull/118) (v0.10.5
§6.3 looks-reachable clause, which cites this library's #40 as its
shape-2 motivating case and adopted this repo's `OPT_DATETIME`
measurement as its checkability note).

Deferred (not release-blocking, carried from v0.4.1): optional C64U
16/48/64 MHz hardware sweep of `polyval_block` — needs physical
hardware.

## Known limitations

Carried over unchanged from v0.6.1; see
[`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.0/API.md)
§6 for the full list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.10.6, tagged).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git tag
  `lib-v0.1.0`).
