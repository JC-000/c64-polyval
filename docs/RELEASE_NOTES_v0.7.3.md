# c64-polyval v0.7.3 — 2026-08-23

**Build-correctness PATCH** (contract at SPEC v0.11.1 at release time —
merged on the contract's `main`, not yet tagged there; latest contract
tag is v0.11.0).
Three parts of one defect class: a consumer's `-D` reaching `ca65` but
not reaching make's dependency graph. Nothing exported changed, no
declared footprint moved, and the linked PRG is byte-identical to v0.7.2
on both profiles, so `LIB_POLYVAL_ABI_VERSION` stays 1. The full
per-change log is in
[`CHANGELOG.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.3/CHANGELOG.md);
this file is the concise release summary.

## What's in

SPEC v0.11.1 §6.3 splits the select-or-reject rule by whether the build
*can* honor the knob. This release implements both branches and pins
them.

- **Member-set axes now reject at parse time**
  ([#55](https://github.com/JC-000/c64-polyval/issues/55),
  [PR #56](https://github.com/JC-000/c64-polyval/pull/56)). The issue #40
  `PIN_` table guarded the *make variable* route, but §6.2's consumer
  mechanism is `CONTRACT_DEFINES`, and that route was unguarded. Two
  measured shapes:

  `make lib CONTRACT_DEFINES="-D POLYVAL_PROFILE=1"` gave **opposite
  answers decided only by whether `build/` was warm** — a ca65
  `'POLYVAL_PROFILE' is already defined` (exit 2) from clean, versus
  `Nothing to be done` (exit 0) from warm, with `polyval.a` still holding
  `polyval_long.o`. The consumer asked for SHORT, got LONG, got exit 0.

  `make lib CONTRACT_DEFINES="-D LIB_POLYVAL_NO_AES=1"` was worse and was
  **not in the report**: exit 0 with no diagnostic at all, even from
  clean. Every TU assembles NO_AES while `lib` archives the full AEAD
  member list, so `data.o` drops the AES/GCM-SIV BSS that the archived
  `aes_encrypt.o` still references. The result is unlinkable
  (`Unresolved external 'aes_expanded_key'`) *and* exports the NO_AES
  `RESIDENT` (4352) for an AEAD member set — §6.4-incoherent, wrong on
  both axes at once.

  No `-D` can reach member selection, so these reject rather than
  invalidate; invalidating would only rebuild the same wrong member set.

- **Configuration axes now invalidate**
  ([#58](https://github.com/JC-000/c64-polyval/issues/58), measurements
  from [#57](https://github.com/JC-000/c64-polyval/issues/57),
  [PR #59](https://github.com/JC-000/c64-polyval/pull/59)). The defines
  #56 correctly still accepts — `LIB_NO_BARE_EXPORTS`,
  `ZP_CONFIG_NO_EXPORTS`, ZP slot overrides — reach every `ca65`
  invocation but no make prerequisite, so they were honoured from a clean
  tree and silently ignored from a warm one:

  ```
  $ make clean && make lib
  $ make lib CONTRACT_DEFINES="-D ZP_CONFIG_NO_EXPORTS=1"
  make: Nothing to be done for `lib'.        # exit 0
  $ od65 --dump-exports build/zp_config.o | grep -c Name:
  13                                         # asked for 0
  ```

  **This made v0.7.2's advice wrong in practice.** The
  [#50](https://github.com/JC-000/c64-polyval/issues/50) fix is real and
  its "0 vs 13" verification reproduces — but only from clean. A consumer
  iterating locally, which is how one actually works through a ZP
  overlap, saw the knob appear to do nothing.

  Fixed with a parse-time flag stamp (`build/.ca65flags`) that deletes
  stale objects and archives when the effective `CA65FLAGS` differs.
  Unchanged flags delete nothing, so incremental builds still
  short-circuit.

- **A pin so both stay fixed**
  ([PR #60](https://github.com/JC-000/c64-polyval/pull/60), raised in
  review of #59). `tools/check_knob_staleness.sh`, run as a leg of
  `make lib-verify`, asserts the **artifact** flipped — never that
  "something rebuilt", since an unconditional rebuild wearing a stamp
  satisfies the weak form while destroying incremental builds.

## Two rejected mechanisms, recorded

Both are in the `Makefile` comment so a later simplification does not
reintroduce them. macOS ships **GNU Make 3.81**, which compares mtimes at
1-second granularity:

- **Stamp as a prerequisite, compared by mtime** — the rewritten stamp is
  newer only in the sub-second digits (`…455.095994194` vs
  `…455.036999740`). 3.81 truncates both and skips the rebuild, so this
  silently does nothing whenever two builds land in the same second —
  i.e. exactly when a consumer is iterating.
- **Same prerequisite, deleting instead** — 3.81 stats a target *before*
  running its prerequisites' recipes and caches the result, so the delete
  is invisible for whichever object make considered first. Measured:
  `build/lib_version.o` deleted and then **not** rebuilt, silently
  dropping a member from the archive. That is a worse failure than the
  staleness being fixed, and it passes a casual "does the knob flip?"
  check because every *other* object rebuilds correctly.

Parse time sidesteps both: stale artifacts are gone before make builds
its dependency graph or stats anything.

## The profile-switch gotcha is retired

`make POLYVAL_PROFILE=short` straight after `make` now produces the SHORT
PRG instead of a stale LONG one, so the manual `make clean` between
profile switches is no longer required. `CLAUDE.md` is updated, and now
also records the two rejected mechanisms.

## Footprint values per (profile × variant)

Declared values (SPEC §6.6 obligation 2). Five archive rows; **no
declared value moved this cycle**, each re-verified from inside its
archive:

| Archive / configuration | RESIDENT | COLD |
|---|---|---|
| `polyval.a` / `polyval-gcmsiv.a` (LONG AEAD) | 6656 (unchanged) | 1280 (unchanged) |
| `polyval-gcmsiv-short.a` (SHORT AEAD) | 16128 (unchanged) | 3072 (unchanged) |
| `polyval-long.a` (LONG, no AES) | 4352 (unchanged) | 1280 (unchanged) |
| `polyval-short.a` (SHORT, no AES) | 13824 (unchanged) | 3072 (unchanged) |

## What's NOT shipped

- **No binary changes.** Linked PRG byte-identical to v0.7.2 on both
  profiles — receipt below. Every change is to the build system.
- **No export surface changes.** `LIB_POLYVAL_ABI_VERSION` stays 1.
- **No manifest value changes**, no new archive targets, no new §6.1
  goals. The pin is a leg on the existing `lib-verify`, not a new target:
  §6.5 makes make target names contract surface, and this needed none.
- **No compact/third profile.**
  [#51](https://github.com/JC-000/c64-polyval/issues/51) remains open;
  the requesting consumer has said it is not a blocker.

## Upgrade notes for consumers

This is a v0.x **PATCH** bump.

1. `LIB_POLYVAL_VERSION_PATCH` now exports `3`; `_MINOR` stays `7`.
2. **If you pass configuration defines, upgrade.** Before v0.7.3,
   `CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES` changes were silently
   ignored on a warm tree. The knob you were told about in v0.7.2 now
   works while iterating, not only from clean.
3. **If you were passing `POLYVAL_PROFILE` or `LIB_POLYVAL_NO_AES`
   through `CONTRACT_DEFINES`, that invocation is now rejected** — loudly,
   at parse time, with a message naming the phony target to use instead.
   It never worked; it silently produced the wrong artifact. This is the
   one behaviour change, and it converts a silent wrong answer into a
   build failure.
4. `make clean` between profile switches is no longer required.

See [`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.3/API.md)
§9 for the full contract surface.

## Verification

Full suite at release time (VICE `x64sc`, seed 8452): 376/376 passed, 6
skipped — POLYVAL Direct 217/217, GCM-SIV 159/165 + 6 AAD-by-design
skips. `make consumer-check`, `make consumer-check-noaes`,
`make lib-verify` (including its new staleness leg), and all **five** §6
archive targets build clean.

Knob behaviour, measured on a warm tree in both directions:

| property | result |
|---|---|
| `ZP_CONFIG_NO_EXPORTS` warm | 13 → 0 → 13 |
| `LIB_NO_BARE_EXPORTS` warm | 4 → 0 → 4 |
| `CONTRACT_ZP_DEFINES` `polyval_acc` warm | `0x10` → `0x40` |
| objects present after every transition | 9 of 9 |
| unchanged invocation | **0** recompiles |
| whitespace-variant invocation | **0** recompiles (`$(strip)`) |
| member-set axes via `CONTRACT_DEFINES` | rejected, exit 2 |

**The pin was verified against the real regression**, not only in the
abstract: run against the pre-fix `Makefile` it fails with the exact #58
symptom (`left zp_config.o at 13 exports, expected 0`) and passes against
the fixed one. `tools/check_knob_staleness.sh --selftest` separately
proves it can fail, by disabling the stamp via
`CONTRACT_FLAGS_WAS='$(CONTRACT_FLAGS_NOW)'`.

Per-archive manifest values re-verified by `ar65 x` + `od65
--dump-exports` on each archive's own `lib_manifest.o`: 6656/1280,
6656/1280, 16128/3072, 4352/1280, 13824/3072 respectively.

### Byte-identity verification (worktree rebuild)

Method: `git worktree add --detach <dir> v0.7.2`; in the baseline
worktree and in the v0.7.3 tree: `make clean && make` (LONG) and
`make clean && make POLYVAL_PROFILE=short` (SHORT);
`shasum -a 256 build/polyval.prg` after each.

| Profile | v0.7.2 rebuild | v0.7.3 rebuild | |
|---|---|---|---|
| LONG | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | identical |
| SHORT | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | identical |

Expected: every change this release is to the build system, and none
alters the flags a default build computes.

**Method note — this applies to PRGs only.** `.o` and `.a` files are
*not* byte-comparable across build paths or across builds separated in
time: `ca65` stamps a wall-clock `OPT_DATETIME` (seconds granularity)
into every object and records source paths and mtimes in the object's
`Files:` section, both unconditionally and independent of `-g`. `ar65`
adds nothing. Compare linked output — as above — or `od65` structural
dumps. This finding is recorded upstream as SPEC v0.10.5 §6.3's
checkability note.

## Attestation

`c64-polyval-v0.7.3.tar.gz` is produced reproducibly by
`make dist VERSION=v0.7.3`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.7.3.tar.gz` |
| **Size**   | 103154 bytes |
| **SHA256** | `2528b57cb6e1a25ad4f629b19b3db234b7643fa97f5fe12c39a545b63a4fe623` |

Re-running `make dist VERSION=v0.7.3` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime
is forced to `2026-08-23T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.7.3/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.7.3.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.4 enumeration)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers, including `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs, with the §4
  placement declarations)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor metadata.
Note that `tools/check_knob_staleness.sh`, added this release, is
therefore **not** vendored — like `test/consumer_stub*.s`, it is a
repo-side guard, not consumer-facing surface. The `Makefile` is likewise
not vendored, so a consumer's own build system is unaffected by the
guard and stamp; both protect *this* repo's build and anyone vendoring
it from git.

## Issues and coordination

[#55](https://github.com/JC-000/c64-polyval/issues/55) closed by
[PR #56](https://github.com/JC-000/c64-polyval/pull/56);
[#58](https://github.com/JC-000/c64-polyval/issues/58) closed by
[PR #59](https://github.com/JC-000/c64-polyval/pull/59), with
[#57](https://github.com/JC-000/c64-polyval/issues/57) closed as
superseded (its measurements are what #59 was verified against);
[PR #60](https://github.com/JC-000/c64-polyval/pull/60) adds the pin.

All were reported from
[c64-aes256-ecdsa](https://github.com/JC-000/c64-aes256-ecdsa)
(JC-000/c64-aes256-ecdsa#27), this library's first declared consumer, and
from the contract side. PR #56's `$(error)` is cited by name in SPEC
v0.11.1 §6.3 as the shipped exemplar for the reject branch.

Deferred (not release-blocking, carried from v0.7.2): optional C64U
16/48/64 MHz hardware sweep of `polyval_block` — needs physical hardware.

## Known limitations

Carried over unchanged from v0.7.2; see
[`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.7.3/API.md)
§6 for the full list, including §3's note that neither profile suits a
memory-bound consumer.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.11.1, merged on `main`; latest tag v0.11.0).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git tag
  `lib-v0.1.0`).
