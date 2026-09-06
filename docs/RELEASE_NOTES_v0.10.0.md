# c64-polyval v0.10.0 — 2026-09-06

Contract-alignment **MINOR**. Two real conformance gaps against
[c64-lib-contract](https://github.com/JC-000/c64-lib-contract) closed —
one of them a §6.1 MUST that had been open for the entire life of the
archive targets — plus documentation brought back into agreement with a
specification that has just lost roughly seven eighths of its text.

**No behavioural change to any routine.** The POLYVAL, AES-256 and
GCM-SIV code paths are untouched. All three profile PRGs are
byte-identical to `v0.9.0` (receipt below), the full suite is
1253/1253 pass + 6 skip on every profile, and
`LIB_POLYVAL_ABI_VERSION` stays **1**.

## What happened to the contract

Contract **v1.0.0** (2026-09-03) cut `SPEC.md` from 40,737 words to
5,154 under a scope rule the document now states about itself: a clause
belongs there only if it governs **(1)** a name, value or placement that
two independently-built artifacts must agree on, where **(2)** a
violation is invisible from inside any single repository's own build.
Both prongs required.

**No symbol, equate, bit value, segment name or build target changed**,
so a library conformant at v0.17.1 was conformant at v1.0.0 without
edits. What went was rationale, incident history and process regulation.
Retired: §9, §12, §13, §14, §15 and sub-clauses §6.3, §6.6 and §6.7.
Surviving sections kept their original numbers, so every existing
citation still resolves. **v1.1.0** then added one normative paragraph
to §7, on when `LIB_<X>_ABI_VERSION` moves.

The cut is why this release exists, but not in the way that phrase
usually means. Nothing we exported had to change. What the cut did was
make §6.1 legible: its requirement to ship a header and an example cfg
is one clause inside a sentence about archive *names*, and for the whole
pre-cut period our §6 attention was on §6.3, §6.4 and §6.6 — two of
which are now retired. Reading a five-page document end to end surfaced
in one pass a MUST that a forty-page one had hidden for six releases.

## The two gaps

### §6.1 — `make lib` shipped the archive alone ([#79](https://github.com/JC-000/c64-polyval/issues/79))

> Every library MUST provide `make lib`, producing `build/lib/<shortname>.a`
> **plus the consumer-facing `.inc` header and an example `.cfg`**.

`build/lib/` had only ever held the `.a`. A consumer doing exactly what
the rest of §6.1 tells them to — fetch the archive, link it directly —
got no declaration of the public symbols and no statement of the
load-bearing segment attributes §4 obliges this library to declare. Both
omissions are silent at link: ld65 warns about a dropped `align = $100`
only when the segment carries a source-level `.align` (ours expresses
alignment in the cfg alone), and about a `type = ro` → `bss` flip only
when the content is non-zero. So the consumer's recourse was to read
`src/` and reconstruct both — which is the mid-build source-poking the
same clause forbids two sentences later.

Every one of the seven archive targets now stages both files:

| Shipped file | Copied from | What it is |
|---|---|---|
| `build/lib/polyval.inc` | `src/polyval_api.inc` | Consumer-facing header: public entry points, calling conventions, buffer surface, profile-selector equates. Emits no code and no memory. |
| `build/lib/polyval-example.cfg` | `src/polyval-example.cfg` | Example ld65 config: a `$0801` consumer memory map plus the full `SEGMENTS{}` block mapping every `LIB_POLYVAL_*` segment, with each §4 placement attribute annotated in place by the consequence of dropping it. Ends with the recommended §1/§5 link-time asserts. |

They are attached as an **order-only** prerequisite of each archive
rule, so a header edit does not force a pointless re-archive, and kept
flat in `build/lib/` rather than a `cfg/` subdirectory: a nested output
directory needs its own order-only prerequisite, and naming only the
parent is the defect that made `c64-x25519`'s `make lib` fail on a warm
tree whose subdirectory had been cleaned away. Both are §6.5 name
surface from this release forward.

**The example cfg is purpose-built.** The obvious move — ship
`src/lib_only.cfg`, which already has the complete `SEGMENTS{}` block —
was tried and reverted. That file is the `make lib-verify` config: it
declares a mandatory `LOADADDR` segment and a `LIB_POLYVAL_VERIFY_CODE`
segment that only our own verification stub emits, so a consumer
linking their own code against `polyval.a` with it takes
`ld65: Warning: Segment 'LOADADDR' does not exist` on their first
build, and reads an opening line telling them the file is for our
internal verification build. `src/polyval-example.cfg` is maintained
separately, is used by no build in this repo, and is warning-free for a
consumer.

**A guard so this cannot rot: `make consumer-check-shipped`.** It copies
exactly the three shipped files plus `test/consumer_stub_shipped.s` into
an empty scratch directory and assembles there **with no `-I src`**.
That is the whole mechanism: every other build in this repository runs
with `src/` on the include path, so a header quietly depending on an
unshipped `src/` file assembles fine for us and fails only for a
consumer. This is the one check that can see an incomplete shipped
surface — which is why #79 survived six releases without anything going
red.

Shown capable of failing, in both directions that matter:

| Perturbation | Result |
|---|---|
| Remove `polyval.inc` from the staged set | `consumer_stub_shipped.s(39): Error: Cannot open include file 'polyval.inc'` |
| Add `.include "constants_lib.inc"` (a file consumers never receive) | `Error: Cannot open include file 'constants_lib.inc'` at that line |
| Neither | links clean, **zero ld65 warnings** |

The stub imports the full public surface — §1 version equates, all four
§5 manifest equates plus the new bound, the §2 slots by `.importzp`
from the archive's `zp_config.o`, every public entry point and buffer —
and carries the `.assert`/`lderror` gates the example cfg recommends, so
those recommendations are exercised rather than merely written down. The
zero-warning property is deliberate: a warning from this target in
future is signal, not noise.

### §5 — the 64-byte ceiling was not referenceable ([#80](https://github.com/JC-000/c64-polyval/issues/80))

> Where a library's real input restriction is a bound a consumer must
> respect — a maximum length, a ceiling — it SHOULD publish that bound
> **here** as a symbol the consumer can reference [...] A consumer SHOULD
> reference the published symbol rather than re-derive the value.

This is where §14.2's one boundary-crossing sentence landed when §14 was
retired. Since v0.9.0, `gcmsiv_encrypt` and `gcmsiv_decrypt` reject
`gcmsiv_pt_len > 64` with `A=1` / `Z=0`. That bound lived only as
`gcmsiv_max_pt_len` in `src/constants_lib.inc` — an equate in a header,
reachable by a consumer who **vendors** our source and invisible to one
who links the archive. They had to hard-code `64` out of prose in
`API.md`, which is the re-derivation the clause's second sentence asks
consumers to avoid.

Now exported from `src/lib_manifest.s` (§5's file — not
`src/lib_version.s`, which §1 reserves for the bare exports and nothing
else):

```asm
.import LIB_POLYVAL_GCMSIV_MAX_PT_LEN
.assert MY_MAX_MESSAGE <= LIB_POLYVAL_GCMSIV_MAX_PT_LEN, lderror, "message longer than c64-polyval accepts"
```

Two details are load-bearing:

- **It is the one equate in that file that is not `.ifndef`-guarded.**
  The other four are consumer-overridable *descriptions*; this one is
  *derived*. `gcm_siv.s` compares against `gcmsiv_max_pt_len`, and
  nothing a consumer defines can move the `cmp #gcmsiv_max_pt_len+1`
  already assembled into the archive. A guard would let
  `-D LIB_POLYVAL_GCMSIV_MAX_PT_LEN=128` assemble quietly and export a
  ceiling twice the enforced one — the §3 "a bare guard converts a
  compile error into silent divergence" shape. Verified unguarded:
  that `-D` fails with
  `src/lib_manifest.s(388): Error: Symbol 'LIB_POLYVAL_GCMSIV_MAX_PT_LEN' is already defined`.

  One consumer-facing wrinkle, not specific to this symbol but this is
  where people will meet it: an `.import`ed symbol has no value until
  link, so ca65 cannot prove it fits in a byte and a bare
  `lda #LIB_POLYVAL_GCMSIV_MAX_PT_LEN` is a `Range error`. Write
  `lda #<LIB_POLYVAL_GCMSIV_MAX_PT_LEN`. `.assert` is unaffected — ld65
  evaluates it once the value is known. Documented in `API.md` §9.4 and
  in the shipped example cfg.
- **It is absent from the POLYVAL-only archives.** `polyval-long.a`,
  `polyval-short.a` and `polyval-compact.a` ship no `gcm_siv.o`, so
  there is no entry point in them for the bound to describe — the §6.4
  discipline from issue #23. The `.ifndef LIB_POLYVAL_NO_AES` has to
  wrap the `.export` as well as the definition, or ld65 reports an
  undefined export for those three archives instead of omitting the row.
  Verified by `od65 --dump-exports` on both configurations: present at
  value `0x40`, address size absolute, in the AEAD manifest; absent from
  the NO_AES one.

## `LIB_POLYVAL_ABI_VERSION` — assessed under the new §7, holds at 1

Contract v1.1.0 added the rule that the counter turns on **what the code
does**, not on whether the export list changed: it moves when a consumer
conforming to the *previously documented* contract can be broken, most
often when an entry point's return set gains a value; it holds when
previously undocumented behaviour becomes documented, and when
documentation is corrected over unchanged code.

v0.9.0's length-rejection return is superficially the shape that moves
the counter. It does not, and the two entry points get there by
different routes:

- **`gcmsiv_encrypt`** documented `A, X, Y undefined` on exit at v0.8.0.
  There was no return convention at all, so a consumer conforming to the
  previously documented contract could not have been reading `A`. This
  is §7's "previously undocumented becomes documented" limb — the same
  shape as `c64-nist-curves` holding at 2 for its v0.12.0.
- **`gcmsiv_decrypt`** *did* carry an exhaustive documented return set at
  v0.8.0 (`A=0` valid / `A=1` invalid, documented for use as `jsr` then
  `beq`), so the non-exhaustiveness test is live. It does not fire,
  because the reject path was written to be indistinguishable from a tag
  failure on **every documented post-condition**: `gcmsiv_dec_buf`
  wiped, `gcmsiv_tag_valid` cleared, `gcmsiv_tag` left as received. The
  return set did not gain a value, and a v0.8.0-conforming consumer
  branching on `Z` handles the new case correctly by construction.

That second point is a property of `@reject_len` in `src/gcm_siv.s`, not
a general fact about domain guards. **If that path is ever made
distinguishable from a tag failure, the counter moves**, and that is now
recorded in `CLAUDE.md` and `API.md` §9.1 rather than left to be
rediscovered.

The reading was put to the contract for arbitration as
[c64-lib-contract#180](https://github.com/JC-000/c64-lib-contract/issues/180),
because v1.1.0's fleet position adjudicates three sibling libraries by
name and does not mention c64-polyval, which shipped the same shape in
the same week. **This release does not wait on that answer** — holding
at 1 is the status quo, and if arbitration says otherwise the counter
moves in a follow-up.

## What was deliberately *not* changed

The contract's `RETIRED.md` asks adopters not to rewrite citations to
retired sections: each is a claim about the tagged revision it was made
against, it resolves permanently at `git show v0.17.1:SPEC.md`, and
rewriting is churn with no reader benefit. So:

- `CHANGELOG.md` and every `docs/RELEASE_NOTES_v0.*.md` are untouched,
  including v0.9.0's account of the §14 and §15 clauses as "in flight
  upstream, not tagged, so not claimed as adopted" — which was accurate
  when written, and whose subjects have since been both tagged and
  retired.
- The thirteen in-line `§6.6` citations in `src/lib_manifest.s` stay.
  The file gained **one** header note saying where that obligation lives
  now (§5 carries safe-direction and the RESIDENT/COLD pair directly),
  in place of rewriting them all.
- The §6.3 machinery — the `PIN_` parse-time goal table, the
  `build/.ca65flags` stamp, `tools/check_knob_staleness.sh` on
  `lib-verify` — is **kept as local engineering**. The clause that
  required it is retired; the properties are still good ones for this
  Makefile to have. `CLAUDE.md` now says so explicitly, so a future
  reader does not delete them as dead conformance or grow them further
  to satisfy a clause that no longer exists.

What *was* corrected is text that had become **false going forward**, as
distinct from text merely citing a retired number: the bare
`LIB_VERSION_*` exports were described in five places as "removed at
contract v1.0", which v1.0.0 explicitly **deferred to a future MAJOR**
rather than doing. Also corrected: `API.md` §9.4 said one tag carries
"four footprint pairs" when it has carried seven since v0.8.0 — counted
against a stale archive list rather than against the `lib-polyval-*`
target list, which is precisely the failure mode the surrounding prose
warns about.

## Footprint values per archive

Unchanged from v0.9.0 — this release adds no code. One row per shipped
archive, seven rows, counted against the `lib-polyval-*` target list.
Declared values are safe-direction: each ≥ the measured code+rodata
segment sum of the archive it ships in, rounded UP to the next 256-byte
boundary, so a consumer's `declared ≤ budget` assert implies
`actual ≤ budget`.

| Archive | Configuration | `RESIDENT_BYTES` (measured) | `COLD_BYTES` (measured) |
|---|---|---:|---:|
| `polyval.a` | LONG, full AEAD | 6656 (6609) | 1280 (1239) |
| `polyval-gcmsiv.a` | LONG, full AEAD | 6656 (6609) | 1280 (1239) |
| `polyval-gcmsiv-short.a` | SHORT, full AEAD | 16128 (16063) | 3072 (3059) |
| `polyval-gcmsiv-compact.a` | COMPACT, full AEAD | 2816 (2774) | 512 (339) |
| `polyval-long.a` | LONG, `LIB_POLYVAL_NO_AES` | 4352 (4160) | 1280 (1047) |
| `polyval-short.a` | SHORT, `LIB_POLYVAL_NO_AES` | 13824 (13614) | 3072 (2867) |
| `polyval-compact.a` | COMPACT, `LIB_POLYVAL_NO_AES` | 512 (325) | 256 (147) |

`polyval.a` and `polyval-gcmsiv.a` are the same configuration with
identical values and still get one row each: merging them makes the
row-count check unperformable, which is how a "five rows" claim once
stood over four printed rows.

New in the §5 surface this release, and worth a consumer's attention if
they are asserting against it:

| Symbol | Value | Archives |
|---|---:|---|
| `LIB_POLYVAL_GCMSIV_MAX_PT_LEN` | 64 | the four AEAD archives only |

## Verification

Full suite, `python3.13 tools/run_all_tests.py --seed 8452`, 164.9 s
VICE wall-clock:

| Profile | Passed | Skipped | Failed |
|---|---:|---:|---:|
| long | 1253 | 6 | 0 |
| short | 1253 | 6 | 0 |
| compact | 1253 | 6 | 0 |

The 6 skips are the RFC 8452 vectors with non-empty AAD; GCM-SIV here
intentionally does not support AAD (`API.md` §6).

All seven archive targets build and stage both shipped files.
`make lib-verify` passes including the knob-staleness pin
(`warm flip both knobs, reverse, 9 objects, 0 spurious rebuilds`).
`make consumer-check` and `make consumer-check-noaes` link clean — the
latter against all three POLYVAL-only archives, the issue #47 guard.
`make consumer-check-shipped` links clean with zero warnings, and has
been demonstrated failing for the right reason in both perturbations
tabulated above.

### Byte-identity receipt

The claim that no routine changed is verified by rebuilding the
**v0.9.0 tag in a separate git worktree** with the same toolchain and
comparing full-app PRGs for every profile v0.9.0 shipped:

| Profile | v0.9.0 rebuild | v0.10.0 | |
|---|---|---|---|
| long | `6dd28baef31040cf…` | `6dd28baef31040cf…` | identical |
| short | `6f4aec2b7b0a4bc0…` | `6f4aec2b7b0a4bc0…` | identical |
| compact | `d184fcfc88e3c654…` | `d184fcfc88e3c654…` | identical |

Both sides were built from clean under `make POLYVAL_PROFILE=<p>`. The
new `LIB_POLYVAL_GCMSIV_MAX_PT_LEN` export and the version bump are pure
assemble-time equates and emit no bytes, which is what the receipt
confirms rather than assumes.

## If you are upgrading

Nothing is required. This release removes no symbol, renames nothing and
changes no calling convention.

Two things you may want:

1. **Take the shipped header and cfg** instead of copying out of `src/`.
   `make lib` now leaves `build/lib/polyval.inc` and
   `build/lib/polyval-example.cfg` next to the archive. If you
   previously vendored `src/lib_only.cfg` or `src/c64.cfg` as a starting
   point, diff your cfg against the new example — in particular
   `type = ro` on `LIB_POLYVAL_AES_RODATA` (dropping it silently loses
   522 initialised S-box bytes and AES then reads power-on garbage) and
   `align = $100` on the three table segments (dropping it is completely
   silent and invalidates the documented cycle counts). The example
   annotates each attribute with what happens if it goes missing.
2. **Assert against `LIB_POLYVAL_GCMSIV_MAX_PT_LEN`** rather than a
   literal `64`, if you bound your message sizes at build time.

## Contract currency

Current against **SPEC v1.1.0** (2026-09-03), the contract's latest tag
at the time of writing. That repository has historically shipped several
releases a day — re-check its tags rather than trusting this line.

Applicability is unchanged: §3 (REU) and §8.1–§8.3 (shared primitives)
remain N/A — c64-polyval makes no REU claims, and GF(2^128) carry-less
multiplication has no shared shape with the 8×8 quarter-square-multiply
primitive the elliptic-curve and ChaCha20 libraries converged on. The §1
and §8.4 zero-consumer carve-outs remain inapplicable: `c64-aes256-ecdsa`
pins a tag, so both bare export families keep shipping, gated on
`LIB_NO_BARE_EXPORTS`.

`src/precalc_table.inc` was refreshed from the v1.1.0 canonical. The
change is comment-only and the contract's own 1.0.0 entry notes that
adopters' copies need not be refreshed — but one of those comments said
the bare triple was "scheduled for removal at contract v1.0", which is
now false.

## Attestation

`c64-polyval-v0.10.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.10.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.10.0.tar.gz` |
| **Size**   | SIZE_PLACEHOLDER bytes |
| **SHA256** | `SHA256_PLACEHOLDER` |

Re-running `make dist VERSION=v0.10.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime
is forced to `2026-09-06T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.
