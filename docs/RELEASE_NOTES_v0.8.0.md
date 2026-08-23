# c64-polyval v0.8.0 — 2026-08-23

**Feature MINOR**: a third `POLYVAL_PROFILE` — **COMPACT**, a rolled
Shoup-4 back-end whose multiply assembles to **325 bytes**, against
SHORT's 13,614 and LONG's 4,160. Contract currency unchanged at SPEC
v0.11.1 (merged on the contract's `main`, not yet tagged there; latest
contract tag is v0.11.0). Closes
[#51](https://github.com/JC-000/c64-polyval/issues/51). The full
per-change log is in
[`CHANGELOG.md`](https://github.com/JC-000/c64-polyval/blob/v0.8.0/CHANGELOG.md);
this file is the concise release summary.

Nothing exported was added, removed or renamed, and the LONG and SHORT
profiles are byte-identical to v0.7.3 (receipt below), so
`LIB_POLYVAL_ABI_VERSION` stays 1.

## Why a third profile

The request came from
[c64-aes256-ecdsa](https://github.com/JC-000/c64-aes256-ecdsa), this
library's first declared consumer, after it completed its v0.7.1
integration and shipped on SHORT.

`API.md` §3 presented the profile axis as a memory-vs-speed trade, and
both points on that axis trade **table** memory for speed while assuming
**code** size is cheap. Measured against v0.7.1, linked into that
consumer, `LIB_POLYVAL_SHORT_CODE` is 13,614 bytes — a **27× increase**
over the 508-byte POLYVAL it replaced. LONG is no escape: its 8,448
bytes of tables do not fit either, and it carries its own code on top.

**This is a memory-map decision, not a size preference.** On a stock C64
the BASIC ROM occupies `$A000-$BFFF`, leaving ~38 KB of contiguous RAM
below it. The consumer's image went from `$95A2` to `$CB2F`, putting
8,192 bytes of POLYVAL code underneath the ROM window. Reading
`polyval_multiply` on the running machine returned BASIC's
`ILLEGAL QUANTITY` text; `polyval_precompute_table` wedged the CPU at
`$A005`. They had **7 bytes of headroom** before the swap and solved it
by banking BASIC out program-wide — correctly noting it was their
problem, not the library's. The failure mode when the collision happens
is the CPU executing ROM, not a link error.

Asked for a per-block cycle budget, they answered that the reason they
care is *placement, not throughput*. So COMPACT optimises for size and
lets cycles go: a full roll targeting the ~500-byte order of magnitude
rather than a middle point.

## What's in

- **`src/polyval_compact.s`** — `POLYVAL_PROFILE=compact` /
  `-D POLYVAL_PROFILE=3`, segment `LIB_POLYVAL_COMPACT_CODE`, **325
  bytes**. Same mathematics, same 256-byte `polyval_htable` and the same
  public symbol set as SHORT, with SHORT's 32 straight-line nibble steps
  and its fully unrolled table build rolled back into loops.

  Register-preservation contracts match SHORT and LONG **per routine**,
  including where matching costs a stack round-trip: the rolled loops
  need an index register the unrolled versions did not, and the cost is
  paid rather than documented away, so a consumer swapping profiles does
  not have to re-read the per-routine Exit blocks.

  The cold code (`polyval_precompute_table` and its only private helper)
  is placed **last** in the segment on purpose, so the §6.6 overlayable
  region is contiguous and runs to the segment end.

- **Two §6.1 archive targets**, `make lib-polyval-compact` and
  `make lib-polyval-gcmsiv-compact`, each with a `PIN_` row so a
  mismatched invocation is rejected at parse time like every other
  archive goal. Profile is a member-set axis (SPEC §6.3), so a new
  profile takes targets, never a `CONTRACT_DEFINES` `-D` — adding one is
  the v0.7.0 shape: two targets, two `PIN_` rows, two
  `(profile × NO_AES)` manifest branches, two footprint rows.

- **`make consumer-check-noaes`** now links the issue-#47 stub against
  `polyval-compact.a` as well as `polyval-long.a` and `polyval-short.a`.

## Two stale figures, found and fixed

Benchmarking COMPACT against both incumbents turned up a documentation
defect that had survived since v0.1.0, and the pre-tag review of
[PR #63](https://github.com/JC-000/c64-polyval/pull/63) turned up its
twin one line below.

**SHORT's precompute was documented as ~29,385 cy. It is 4,656 cy** — a
~6× overstatement. The figure predates the release that replaced the
128-iteration `mulX_POLYVAL` loop with the 7-shift RFC 8452 identity
(`x^-128 = 1 + x^-1 + x^-2 + x^-7`), and nothing re-measured it
afterwards. LONG's 255,268 cy and both multiply figures re-measured
within noise of their documented values.

**The "practical break-even ≈ 68 blocks" is withdrawn.** It entered in
`959ffd8` with no derivation — immediately after that commit's own
analytic crossover — and it hangs off the same `precompute + N × update`
model and the same v0.1.0 measurement pass as the figure above. Its own
gloss contradicted it: 1 KB of plaintext is 64 blocks, not 68.

**The SHORT/LONG crossover is 17 blocks (272 bytes)**, measured
end-to-end rather than solved — multi-block `polyval_update` totals plus
each profile's own precompute:

| N blocks | SHORT total | LONG total | winner |
|---:|---:|---:|---|
| 16 | 312,813 cy | 323,122 cy | SHORT by 10,309 |
| **17** | **332,243 cy** | **327,437 cy** | **LONG by 4,806** |
| 18 | 351,125 cy | 331,583 cy | LONG by 19,542 |

There is exactly one crossover: `total_SHORT(N) − total_LONG(N)` is
linear in N with a single root, and measured per-block cost is flat to
within 0.5% from N=14 through N=256 on both profiles, so LONG's margin
only widens past 17 blocks (708,242 cy at N=64). No second break-even
exists for the old figure to name, and LONG's 4,806 cy win at N=17 is
already ~3x the larger of the two per-run measurement spreads there
(1,694 cy). `API.md` §3 now
carries the equation and this table so the number is checkable without a
rebuild, and `README.md` and `API.md` use one word for one number.

A third instance of the same pattern turned up while JC-000 was
independently reproducing the table above, and was fixed before tagging
rather than deferred: `tools/benchmark_polyval.py`'s multi-block sweep
picked its timing wrapper from a stale `n * 7200` cy/block projection,
so the 16-bit CIA wrapper stayed selected past its 65,535 range and
**every SHORT and COMPACT benchmark run tabled one fictional row** at
N=4 (issue [#65](https://github.com/JC-000/c64-polyval/issues/65)). The
sweep now uses the 32-bit wrapper unconditionally and refuses to table a
non-positive measurement. No shipped artifact is affected — `tools/` is
not vendored — and the crossover table above is unchanged, because
N=14…20 always sat in the good band. It is fixed here rather than after
the tag because these notes and `API.md` §3 both point at this tool as
the way to check their numbers.

**An earlier draft of these notes certified 68 as "unaffected" by the
precompute correction.** That had no basis: correcting SHORT's
precompute *downward* pushes crossovers *later*, so if 68 depended on
the model at all it moved too. Caught in review before tagging.
`CLAUDE.md` now says to re-measure before quoting cycle counts — and,
after this, not to certify a neighbouring figure as unaffected without
measuring that one too.

## Profile table

All figures measured — code and table sizes from a `lib_only.cfg` link,
cycles from `tools/benchmark_polyval.py` (CIA timer, SEI, `x64sc`):

| Profile | Multiply | Precompute | Code | Tables | Total RAM |
|---|---:|---:|---:|---:|---:|
| SHORT (`=1`) | 18,776 cy | 4,656 cy | 13,614 B | 256 B | ~13.6 KB |
| LONG (`=2`, default) | 3,917 cy | 255,268 cy | 4,160 B | 8,448 B | ~12.3 KB |
| **COMPACT (`=3`)** | **49,657 cy** | **10,970 cy** | **325 B** | **256 B** | **613 B** |

SHORT/LONG crossover: **17 blocks (272 bytes)** — see below.

**COMPACT is not a third point on the speed/memory axis.** It is
strictly slower than SHORT at every message length — there is no N at
which it wins on time — and LONG overtakes it at ~5 blocks. It is chosen
on footprint alone, when a 13 KB multiply would decide your memory map.

## Footprint values per (profile × variant)

Declared values (SPEC §6.6 obligation 2), **one row per shipped
archive** — seven archives, seven rows, up from five. Declared values
are the measured code+rodata segment sum rounded UP to the next
256-byte boundary; measured values in parentheses. **No LONG or SHORT
value moved this cycle.**

| Archive | Configuration | RESIDENT | COLD |
|---|---|---|---|
| `polyval.a` | LONG AEAD | 6656 (unchanged) | 1280 (unchanged) |
| `polyval-gcmsiv.a` | LONG AEAD | 6656 (unchanged) | 1280 (unchanged) |
| `polyval-gcmsiv-short.a` | SHORT AEAD | 16128 (unchanged) | 3072 (unchanged) |
| `polyval-gcmsiv-compact.a` | COMPACT AEAD | **2816 (new; measured 2732)** | **512 (new; measured 339)** |
| `polyval-long.a` | LONG, no AES | 4352 (unchanged) | 1280 (unchanged) |
| `polyval-short.a` | SHORT, no AES | 13824 (unchanged) | 3072 (unchanged) |
| `polyval-compact.a` | COMPACT, no AES | **512 (new; measured 325)** | **256 (new; measured 147)** |

COMPACT is the first configuration where the `LIB_POLYVAL_NO_AES` gating
actually **moves** a COLD value rather than rounding to the same
boundary: dropping the 192-byte `aes_key_expansion` takes 339 B to
147 B, which is 512 declared versus 256. On LONG and SHORT the same
drop stays inside one page, so the gating looked decorative; it was not.

## What's NOT shipped

- **No change to LONG or SHORT.** No `.o` under either profile changed;
  their PRGs are byte-identical to v0.7.3 (receipt below) and their
  footprint equates are unchanged.
- **No export surface changes.** `LIB_POLYVAL_ABI_VERSION` stays 1. The
  new profile adds no symbol — it *is* the same symbol set.
- **No REU variant.** §9.3's policy is untouched; COMPACT is pure CPU +
  RAM like the other two, so `LIB_POLYVAL_REU_BANKS_USED` stays 0.
- **No default change.** LONG remains the default profile.

## Upgrade notes for consumers

This is a v0.x **MINOR** bump. It is additive: if you do not ask for
COMPACT, nothing about your build changes.

1. `LIB_POLYVAL_VERSION_MINOR` now exports `8`; `_PATCH` resets to `0`.
2. To adopt COMPACT, switch archive target — `make lib-polyval-compact`
   (POLYVAL only) or `make lib-polyval-gcmsiv-compact` (full AEAD) — or
   pass `POLYVAL_PROFILE=compact` for a PRG build. As with every
   profile, it cannot be selected through `CONTRACT_DEFINES`; that
   invocation is rejected at parse time with a message naming the target
   to use.
3. Your linker config must declare `LIB_POLYVAL_COMPACT_CODE` if you
   link the COMPACT profile, alongside the existing
   `LIB_POLYVAL_LONG_CODE` / `_SHORT_CODE` entries. `polyval_htable`
   keeps its page alignment; `polyval_htable8` / `polyval_reduce8` are
   LONG-only as before.
4. If you assert against `LIB_POLYVAL_RESIDENT_BYTES` /
   `_COLD_BYTES`, note the values are per-archive: linking
   `polyval-compact.a` gets you 512 / 256.
5. **If you quoted SHORT's ~29,385 cy precompute figure anywhere,
   correct it to 4,656.**
6. **If you sized a buffer or picked a profile against the ~68-block
   break-even, re-check against 17 blocks (272 bytes).** The practical
   figure is withdrawn, not merely restated: the measured crossover is
   17, and there is no second one. A consumer who chose SHORT for
   messages between 17 and 68 blocks on the strength of the old number
   was choosing the slower profile.

See [`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.8.0/API.md)
§3 for profile selection and §9 for the full contract surface.

## Verification

Full suite at release time (VICE `x64sc`, seed 8452), run under **each
of the three profiles**: 376/376 passed, 6 skipped in every case —
POLYVAL Direct 217/217, GCM-SIV 159/165 + 6 AAD-by-design skips. COMPACT
is validated against the same Python reference and the same RFC 8452
vectors as LONG and SHORT, including `polyval_double`,
`polyval_right_shift_1`, `polyval_shift_left_4`,
`polyval_xor_table_entry` and `polyval_precompute_table` exercised in
isolation.

`make consumer-check` (LONG and COMPACT), `make consumer-check-noaes`
(all three POLYVAL-only archives), `make lib-verify` including its
knob-staleness leg, and all **seven** §6 archive targets build clean.

Guard behaviour for the new profile, measured:

| invocation | result |
|---|---|
| `make lib POLYVAL_PROFILE=compact` | rejected at parse time, exit 2 |
| `make build/lib/polyval-compact.a` (default profile) | rejected at parse time, exit 2 |
| `make lib CONTRACT_DEFINES="-D POLYVAL_PROFILE=3"` | rejected by the member-set guard, exit 2 |
| `make POLYVAL_PROFILE=tiny` | rejected, names the three valid values |

Per-archive manifest values re-verified by `od65 --dump-exports` on each
`(POLYVAL_PROFILE × LIB_POLYVAL_NO_AES)` configuration's own
`lib_manifest.o`: 6656/1280, 16128/3072, 2816/512 (AEAD) and 4352/1280,
13824/3072, 512/256 (no AES).

### Byte-identity verification (worktree rebuild)

Method: `git worktree add --detach <dir> v0.7.3`; in the baseline
worktree and in the v0.8.0 tree: `make clean && make` (LONG) and
`make clean && make POLYVAL_PROFILE=short` (SHORT);
`shasum -a 256 build/polyval.prg` after each.

| Profile | v0.7.3 rebuild | v0.8.0 rebuild | |
|---|---|---|---|
| LONG | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | `e93962ac52384bebba478c2a1647647502f16bdc8a48b9069386117dfa9f2d05` | identical |
| SHORT | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | `98948d023d33c13308739fef75bbd1248b9a90de1149f4e03b8b1b6e03ecb54a` | identical |

Expected: this release adds a file and a set of build targets, and
changes nothing on the paths either existing profile assembles. The
COMPACT PRG, for scale, is 5,639 bytes against LONG's 9,474 and SHORT's
18,928.

**Method note — this applies to PRGs only.** `.o` and `.a` files are
*not* byte-comparable across build paths or across builds separated in
time: `ca65` stamps a wall-clock `OPT_DATETIME` (seconds granularity)
into every object and records source paths and mtimes in the object's
`Files:` section, both unconditionally and independent of `-g`. `ar65`
adds nothing. Compare linked output — as above — or `od65` structural
dumps. This finding is recorded upstream as SPEC v0.10.5 §6.3's
checkability note.

## Attestation

`c64-polyval-v0.8.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.8.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.8.0.tar.gz` |
| **Size**   | 114794 bytes |
| **SHA256** | `425493875c4195895e180df0562457d963c722e720ecedf6df7d7387cfd812cc` |

Re-running `make dist VERSION=v0.8.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime
is forced to `2026-08-23T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.8.0/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.8.0.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.4 enumeration)
- `src/*.s` (library + demo-app sources, now including
  `src/polyval_compact.s`)
- `src/*.inc` (public headers, including `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs, with the §4
  placement declarations and the new `LIB_POLYVAL_COMPACT_CODE` segment)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor metadata.
`src/polyval_compact.s` ships because the staging list globs `src/*.s`;
the benchmark and test scripts that produced the cycle figures above are
repo-side and are not vendored — including
`tools/benchmark_polyval.py`'s new `POLYVAL_BENCH_BLOCKS` override,
which is what makes the crossover table reproducible.

## Issues and coordination

[#51](https://github.com/JC-000/c64-polyval/issues/51) closed by this
release. It was filed from
[c64-aes256-ecdsa](https://github.com/JC-000/c64-aes256-ecdsa)
(JC-000/c64-aes256-ecdsa#27) with the integration measurements quoted
above; its documentation half shipped separately in v0.7.2 (the §3
Code/Tables/Total-RAM columns and the "neither profile serves a
memory-bound consumer" note), and this release closes the remaining
half.

That consumer offered to test any such profile from the consumer side
and report footprint + correctness. Nothing is blocked on it — they have
completed and verified their integration against SHORT — but a real
memory-bound integration is a better check than anything synthetic here,
and the offer is taken up.

Deferred (not release-blocking, carried from v0.7.3): optional C64U
16/48/64 MHz hardware sweep of `polyval_block` — needs physical
hardware.

## Known limitations

Carried over from v0.7.3; see
[`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.8.0/API.md)
§6 for the full list. §3's note that neither profile suits a
memory-bound consumer is **retired** — that is what this release fixes.

Unchanged: GCM-SIV supports empty AAD only, plaintext is capped at 64 B
per call, and the library is not constant-time (§6).

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.11.1, merged on `main`; latest tag v0.11.0).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git tag
  `lib-v0.1.0`).
