# c64-polyval v0.12.0 — 2026-09-08

POLYVAL (RFC 8452 GF(2^128) universal hash) plus AES-256-GCM-SIV
authenticated encryption for the Commodore 64.

**A verification release.** Every change is a guard, a gate or a
documentation correction. No emitted code changed: the three profile PRGs
are byte-identical to `v0.11.0`, and the exported name set is unchanged at
162 names. `LIB_POLYVAL_ABI_VERSION` holds at **1**.

Thirteen issues are closed here. All thirteen were filed by this
repository's own audit against itself, seeded by findings ported from
`c64-x25519`, `c64-nist-curves` and `c64-ChaCha20-Poly1305`. Nine share a
single shape, and it is worth naming because it survived several rounds of
review in four repositories:

> **A check whose pass condition is a zero, an absence, or an empty
> result is satisfied equally by a correct artifact and by a broken tool.**

`check_knob_staleness.sh` counted bare exports and passed on zero — which
is also what a missing object, a dead `od65` or an unparseable dump
produces. `make dist` ran no gates, so a release could be minted from a
tree in which every guard was failing. The composing mode
(`LIB_NO_BARE_EXPORTS=1`) that a consumer linking two sibling libraries
must build in was never built by any target, so the §8.4 suppression it
governs was unverified in every arm.

## The one change a consumer can observe

`CONTRACT_ZP_DEFINES` can no longer alias two zero-page slots onto one
address, or push a slot off the usable page (issue #105).

SPEC §6.2 invites a consumer to relocate this library's 13 ZP slots to fit
their memory map. Nothing checked the resulting addresses were distinct, so

```sh
make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40 -D pv_mul_input=0x40'
```

exited 0, archived, linked, and passed every gate — while putting the
POLYVAL accumulator on top of the multiply scratch, so every multiply
corrupted the accumulator. **Wrong cryptographic results from a green
build**, with no diagnostic at any stage. On a C64 the symptom is a failed
tag comparison in someone else's code, days later.

`src/zp_config.s` now asserts at assembly time that no two slots' byte
ranges overlap and that every slot fits in `$02–$ff` — the floor is `$02`,
not `$00`, because `$00`/`$01` are the 6510 data-direction register and
processor port. That is 78 pairwise range comparisons, driven from a macro
slot table rather than a hand-written list.

**If you pass `CONTRACT_ZP_DEFINES`, re-check your values against this
release.** An override that was silently accepted before may now fail your
build. That is the point — but it is a build that used to succeed, so it
is called out here rather than left to be discovered. Legal relayouts are
unaffected: the default build, `-D polyval_acc=0x40`, and exactly-abutting
slots all still assemble.

## ABI — holds at 1, argued from the documented domain

`API.md` §9.2 has carried an Address **and a Width** for all 13 slots since
before this change, closing with "Total: **45 bytes** claimed across three
discontiguous regions (`$02–$09`, `$10–$30`, `$fb–$fe`)", and
`LIB_POLYVAL_ZP_USAGE_BYTES = 45` is exported unconditionally — including
from the `NO_AES` archives, so there is no carve-out under which a
POLYVAL-only consumer could legitimately park a live slot on a dead AES
slot. The entailment runs through **distinctness**, not through the widths
alone: `LIB_POLYVAL_ZP_USAGE_BYTES = 45` publishes 45 bytes *claimed* in
zero page, and thirteen slots whose widths total 45 can occupy 45 distinct
bytes only if none of them overlaps — pigeonhole. (The three published
regions hold 8 + 33 + 4 = exactly 45, so the documented layout is tight,
with no slack an overlap could hide in.) An aliased layout therefore claims
fewer than 45 distinct bytes and contradicts a symbol this library has
exported since before the change, so it was never inside the documented
input domain, and a guard that only fires outside that domain cannot move
the counter however its diagnostics read. The same published sentence
supplies the `$02` floor.

Stated carefully because the obvious shorter form is wrong, and the release
notes carried it through review: *"thirteen widths summing to 45 entails
non-overlap"* does **not** follow. The widths are library constants
(`src/zp_config.s`), unchanged by any `-D` override, so they still sum to 45
under `-D polyval_acc=0x40 -D pv_mul_input=0x40` — an overlapping layout.
It is the *distinct-bytes* claim that does the work. Caught in adversarial
review of this release; corrected before tagging.

The argument deliberately does **not** rest on "no entry point, return set,
segment or exported value changed". That is the runtime-surface form
`CLAUDE.md` records as the wrong one at v0.10.0; it appeared in an earlier
commit message on the #105 branch and was withdrawn under review.

## What else is fixed

| Issue | Was |
|---|---|
| #96 | `make dist` ran no gates at all — a release could be minted from a tree where every guard failed |
| #85 | `make dist` silently overwrote a released tarball and restamped its attestation when the tree had moved past the tag |
| #87 | The fail-closed stamper aborted *after* rewriting the notes and overwriting the tarball, leaving the tracked notes truncated with no Attestation table and no placeholder token to detect it by |
| #99 | `build-short/` was tracked in git — six artifacts, including a `polyval-short.a` predating the v0.11.0 member-isolation fix |
| #93 | Concurrent runs in one working tree raced on fixed-name scratch trees; reproduced 3/3 |
| #95 | Nothing verified `RESIDENT_BYTES` / `COLD_BYTES` against a measurement — two sibling libraries shipped this defect in the unsafe direction on one day |
| #86, #90 | `check_knob_staleness.sh` could not distinguish 0 exports from a missing object or a dead `od65`, and checked the gate only for what it removes |
| #89, #94 | The composing mode was unexercised end to end; §8.4 bare-export suppression was never checked in any arm |
| #103 | `docs/precalc-tables.md` omitted `polyval-gcmsiv-compact.a` from both sbox rows — the §8.4 artifact of record, stale since v0.8.0 |
| #97 | `ar65` embeds a timestamp, so `polyval.a` is not byte-reproducible. **Documented, not fixed** — PRGs and the tarball are reproducible; an archive hash in a receipt will not reproduce and will read as a regression |

`make verify` now runs **14** checks and restores the default build.

## Verification

| Check | Result |
|---|---|
| `run_all_tests.py --seed 8452` | **1253/1253 pass, 6 skip, 0 fail** on long, short and compact — 99.6 s VICE wall-clock, run on the final tree |
| PRG byte-identity vs `v0.11.0` | **identical on all three profiles**, by worktree rebuild of the tag (below) |
| Exported name set vs `v0.11.0` | **162 names both sides, zero difference** |
| `make verify` | 14/14 targets pass |
| §5 footprints | all six configurations declare ≥ measured |
| `VERSION` / `src/lib_version.s` / `API.md` §9.1 | agree at `0.12.0`, ABI 1 |

### Byte-identity method

Built from scratch in **separate git worktrees**, so no tree could reuse
another's objects (`BUILD_DIR` is relative, and the `.ca65flags` stamp
lives under it). `make clean && make POLYVAL_PROFILE=<p>` for each of the
three profiles, at **three** refs: `v0.11.0` (`8df10a4`), this release's
parent (`17b969d`), and the release commit itself.

The release commit is included deliberately. It changes
`src/lib_version.s` (`MINOR` 11 → 12), which the parent does not, so a
receipt naming only the parent would not cover the tree that gets tagged.
It produces the same three hashes: `lib_version.s` contributes exported
absolute equates, which emit no bytes into the PRG.

**Reproducing this against `v0.11.0` requires `rm -rf build-short` first.**
That tag tracks `build-short/lib/polyval-short.a` in git (issue #99, fixed
after it), so a fresh checkout arrives with a committed archive already in
place and a clean `git status`, and make will not rebuild it. It does not
affect the PRG hashes above — `make POLYVAL_PROFILE=<p>` never consults
that directory, and the three hashes reproduce with it deleted — but it
does silently contaminate archive and export-set comparisons against that
tag, which is where it was found.

| Profile | `v0.11.0` | this release | SHA256 of `build/polyval.prg` |
|---|---|---|---|
| LONG | ✓ | ✓ | `6dd28baef31040cfb47342614b9392af9a9c12f61bbfc98bf7193caf4c58ae87` |
| SHORT | ✓ | ✓ | `6f4aec2b7b0a4bc056c3104891a12e0aeafbfea019a55d0ca53e07f0fef2c6e5` |
| COMPACT | ✓ | ✓ | `d184fcfc88e3c6540d9c811db8a65739e9f964451fb5607f5e34b30e33f2b873` |

Two controls, because "the hashes matched" is also what a comparison that
never ran produces:

1. **The trees genuinely differ.** `diff -rq` over `src/` reports five
   differing files (`exports.inc`, `lib_manifest.s`, `polyval_api.inc`,
   `precalc_manifest.s`, `zp_config.s`). The assembler saw different source
   and emitted the same bytes, which is the claim.
2. **The build responds to its input.** The three profile hashes are
   mutually distinct, so a harness that had silently built one thing three
   times would not have produced this table.

No archive hashes appear above, per issue #97.

## Footprint values per archive

Unchanged from `v0.11.0`. Values are the declared `LIB_POLYVAL_*` equates a
consumer links against — safe-direction, measured per archive and rounded
up to the next 256-byte boundary.

| Archive | Configuration | `RESIDENT_BYTES` | `COLD_BYTES` |
|---|---|---:|---:|
| `polyval.a` | LONG, full AEAD | 6656 | 1280 |
| `polyval-gcmsiv.a` | LONG, full AEAD | 6656 | 1280 |
| `polyval-gcmsiv-short.a` | SHORT, full AEAD | 16128 | 3072 |
| `polyval-gcmsiv-compact.a` | COMPACT, full AEAD | 2816 | 512 |
| `polyval-long.a` | LONG, `LIB_POLYVAL_NO_AES` | 4352 | 1280 |
| `polyval-short.a` | SHORT, `LIB_POLYVAL_NO_AES` | 13824 | 3072 |
| `polyval-compact.a` | COMPACT, `LIB_POLYVAL_NO_AES` | 512 | 256 |

`LIB_POLYVAL_GCMSIV_MAX_PT_LEN` is unchanged at **64**.

As of this release `make check-footprints` measures all six configurations
on every `make verify`, so these values are no longer maintained by hand
alone. Live measurements against the declared values, in the same order as
the table above (LONG AEAD 6495/1028, SHORT AEAD 15949/2867, COMPACT AEAD
2660/120, LONG NO_AES 4160/1028, SHORT NO_AES 13614/2867, COMPACT NO_AES
325/120) are all within the declared bound.

## Known open

Six follow-ups remain open and are deliberately not in this release:
**#104** (the `NO_AES` archives are not link-tested in the composing mode),
**#106**, **#107**, **#113** (three LOW gaps in the new gates themselves),
**#109** (`API.md` §4's ZP slot table still uses the pre-v0.3.0 names), and
two remaining paths to #105's failure mode: **#110** (a ZP slot added as an
equate with no table row is unguarded) and **#116** (the `size` column,
`LIB_POLYVAL_ZP_USAGE_BYTES` and `API.md` §9.2 are three hand-maintained
copies of one fact with nothing checking they agree — an understated width
narrows the range the overlap check compares, hiding a real overlap).
None is a conformance defect against c64-lib-contract.

#116 was filed during this release's own pre-tag review, which also
corrected the ABI argument above. It is worth being plain about the shape:
the guard this release ships is sound, and the argument that it cannot move
the ABI counter is sound, but the argument's premise is a hand-maintained
number that nothing checks. That is the same class as the nine defects
closed here, found in the release that closes them.

## Compatibility

- Contract: **c64-lib-contract SPEC v1.2.2**.
- `LIB_POLYVAL_ABI_VERSION` = 1, unchanged.
- No source change is required of a consumer, unless it passes
  `CONTRACT_ZP_DEFINES` with an overlapping or out-of-page layout — which
  was never inside the documented domain and produced wrong results.

## Attestation

`c64-polyval-v0.12.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.12.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.12.0.tar.gz` |
| **Size**   | 151231 bytes |
| **SHA256** | `ce21e6eb9fd0df1228af3221deb7e8f66026c7a4c100e52bcc16ad1ef148ff3c` |

Re-running `make dist VERSION=v0.12.0` against this source tree must
reproduce the recorded hash byte-for-byte: every staged file's mtime is
forced to `2026-09-08T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.

The PRG hashes in the byte-identity table above are **not** the tarball
hash and are not stamped by the release script; they are recorded by hand
from the worktree rebuild. No archive hash appears anywhere in this
document, per issue #97.
