# c64-polyval v0.11.0 — 2026-09-06

Contract-alignment **MINOR**, current against c64-lib-contract
**v1.2.2** (the fix is owed by v1.2.0 §6.1; v1.2.1 and v1.2.2 landed
mid-release and neither changed it). One
conformance fix that removes a real, reproducible consumer link failure,
and one correction to a justification the contract withdrew underneath us.

**No behavioural change.** The POLYVAL, AES-256 and GCM-SIV code paths are
untouched; all three profile PRGs are byte-identical to v0.9.0 through
v0.10.1. `LIB_POLYVAL_ABI_VERSION` stays **1** — no exported name is
added, removed or renamed anywhere. This release moves symbols between
*archive members*, which is invisible to every symbol a consumer imports
and visible to exactly one thing: what else arrives when they import it.

## §6.1 member isolation — the fix

Contract v1.2.0 added a paragraph to §6.1:

> **Member isolation.** ld65 links whole archive members. A symbol a
> consumer may displace — suppress under `LIB_NO_BARE_EXPORTS`, or define
> itself under `APP_OWNED` (§8.0) — MUST live in a translation unit that
> exports nothing else a consumer may import — other displaceable names
> included — and defines nothing else the library's own code references.
> Otherwise the member arrives uninvited and its displaceable names
> collide with the consumer's own definitions, which the consumer cannot
> repair: member surgery is banned above.

`src/lib_manifest.s` violated it. It carried both:

- the **§5 aggregates** a consumer imports — `LIB_POLYVAL_ZP_USAGE_BYTES`,
  `_REU_BANKS_USED`, `_RESIDENT_BYTES`, `_COLD_BYTES`,
  `_GCMSIV_MAX_PT_LEN`; and
- the `LIB_PRECALC_TABLE` invocations, which emit the **displaceable**
  bare `LIB_PRECALC_<name>_{SIZE,REGION,SHARED}` triple (suppressed under
  `LIB_NO_BARE_EXPORTS`, hence displaceable).

So a consumer importing a footprint equate pulled the whole member in, and
fifteen bare `LIB_PRECALC_*` names arrived with it, uninvited. This is
contract issue **#177**'s exact shape — and the consumer cannot repair it,
because §6.1 bans `ar65` member surgery two paragraphs earlier.

### The failure is real; be precise about which direction bites

The link failure reproduces exactly. A consumer that imports a §5 aggregate
while *owning* a bare precalc name — which it is entitled to do, the name
being displaceable — fails against the v0.10.1 tag and links clean against
this release, same object file both times:

```
ld65: Error: Duplicate external identifier: 'LIB_PRECALC_polyval_htable_SHARED'
```

**But that scenario is contrived, and the honest statement is narrower than
"it was not theoretical".** §6.1's rationale, as corrected at v1.2.2, names
two collision directions, and they do not both bite here today:

- **Library versus library** — two adopters exporting the identical bare
  name, no consumer definition anywhere. This is the direction #177 was
  actually reported for, and for c64-polyval it is **latent, not live**:
  our five enumerated tables are `polyval_htable`, `polyval_htable8`,
  `polyval_reduce8`, `aes_sbox` and `aes_inv_sbox`, and no sibling adopter
  currently enumerates any of them. (The names the fleet *does* share are
  `sqtab`, in four adopters, and `reu_mul`, in two — neither of which we
  consume.)
- **Consumer definition** — the probe above. Unrealistic as written, but it
  is the direction that is reachable in this library today.

What makes the latent direction worth fixing now rather than when it bites:
§8.4 requires table names to be **normative and never library-prefixed**,
precisely so cross-adopter duplication is detectable. That puts every bare
`LIB_PRECALC_*` name in one flat shared namespace by design. `aes_sbox` is
a standard AES table; one future adopter enumerating it turns the latent
direction live, and by then the collision is in released archives on both
sides and neither consumer can repair it — member surgery is banned.

The clause is unconditional in any case: a displaceable name must be
isolated whether or not a collision exists yet. This release satisfies it.

### What moved

The §8.4 invocations now live in **`src/precalc_manifest.s`**, which
exports the precalc names and nothing else (30 on LONG AEAD: 15 prefixed,
15 bare; fewer where the profile/variant gates drop rows).
`lib_manifest.o` exports the §5 surface and nothing else (five names on the
AEAD archives, four on the NO_AES ones, where the published bound is absent).

Both forms moved **together**, deliberately. Contract **v1.2.1** (PR #187,
merged 13:34 while this release was being prepared) adds "their own
prefixed counterparts excepted" to this clause, which blesses exactly that
arrangement and names `c64-x25519`'s identical fix as correct. Separating bare from prefixed would have been
work that the very next contract PATCH un-asks for.

Gating is preserved exactly, because it is load-bearing (issue #23, §6.4):
`polyval_htable8` / `polyval_reduce8` under
`.if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG`, and `aes_sbox` /
`aes_inv_sbox` under `.ifndef LIB_POLYVAL_NO_AES` so the POLYVAL-only
archives do not enumerate tables they never ship.

### Verified by per-archive export-set equality

The risk in a translation-unit split is silently dropping an exported
symbol from an archive. Checked directly, on all seven: for each archive,
`ar65 t` to list members, `ar65 x` to extract them, `od65 --dump-exports`
over every member, sorted into one set per archive, diffed against the
same set built from a `master` worktree.

| Archive | Exported names | Before vs after |
|---|---:|---|
| `polyval.a` | 162 | identical |
| `polyval-gcmsiv.a` | 162 | identical |
| `polyval-gcmsiv-short.a` | 116 | identical |
| `polyval-gcmsiv-compact.a` | 116 | identical |
| `polyval-long.a` | 89 | identical |
| `polyval-short.a` | 43 | identical |
| `polyval-compact.a` | 43 | identical |

Zero names added, zero dropped, in any archive. Member lists differ by
exactly `+precalc_manifest.o`. Gating re-checked from those same sets:
`polyval_htable` in all seven; `htable8`/`reduce8` only in the three LONG
archives; `aes_sbox`/`aes_inv_sbox` only in the four AEAD archives.

`tools/check_knob_staleness.sh`'s member-count expectation moved 9 → 10,
because `LIB_AEAD_OBJS` genuinely grew by one. Its comment now enumerates
the members and says to bump the number *with the member set* and never to
make a failure go away — the count is a real check, not a formality, and
`make lib-verify` failed until it was updated. `--selftest` still passes,
so the pin is still shown capable of failing.

## A justification the contract withdrew

**Contract v1.1.1 withdrew §6.1's requirement that `make lib` also produce
a `.inc` header and an example `.cfg`** (contract#178). It was an
unannounced artifact of the 1.0.0 text cut: never proposed, naming neither
path, and failing the contract's own scope rule on both prongs. v1.2.0
§6.1 asks for `build/lib/<shortname>.a` and nothing more.

c64-polyval v0.10.0 had built its entire §6.1 story on that clause and
closed issue #79 against it.

**The artifacts stay. The claim goes.** `build/lib/polyval.inc` and
`build/lib/polyval-example.cfg` are still staged by all seven archive
targets and still guarded by `make consumer-check-shipped`, because the
reasoning that made them worth shipping never actually depended on the
clause: a consumer who fetches only the `.a` has no declaration of the
public symbols and no statement of the §4 placement attributes, and both
omissions are silent at link.

What is corrected is every live place that called this **conformance** —
`Makefile`, `API.md` §9.5, `CLAUDE.md`, `test/consumer_stub_shipped.s`.
This is the same class as v0.10.1's "removed at contract v1.0": a
statement that was true when written and has since become false, which a
consumer may plan against. Historical release notes are left as written —
they were accurate at their tag.

## New: the alignment watch has a charter

`docs/contract-watch.md` now holds the state of the contract-alignment
watch: the settle condition, the gating rules that decide what earns
action, a per-contract-tag ledger, an in-flight register of open contract
issues and PRs with a verdict on each, and the fleet table.

It exists because the pre-1.0 contract shipped several releases a day, and
chasing every one of them — realigning, re-documenting, re-releasing for
changes that did not apply — was the dominant cost. The rules that do the
work: never act on an untagged change, but *read* the in-flight ones;
applicability before conformance, with N/A costing one ledger row and no
prose; batch rather than releasing per contract tag; and hold any release
whose adversarial review has not reported.

Its first real use is recorded in it. v1.2.0 §6.1 made this library
non-conformant. Contract PR #187 amends that same clause, so waiting for
it looked like the careful move. Reading #187 settled it the other way —
it states that §5 aggregates "are counterparts of nothing displaceable …
their co-residency with the bare `LIB_PRECALC_*` triple is still a
violation." Our case survives the carve-out verbatim, so the fix was owed
under both the tagged and the proposed text, and waiting would have been
pure delay.

## Not changed, deliberately

**`src/lib_version.s`.** v1.2.0 §6.1 as published forbade its bare and
prefixed version equates sharing a translation unit. **v1.2.1 repaired
that** — §1 prescribes the pattern in a worked code block, four of five
adopters ship it, and the release states plainly that no adopter moves.
Leaving it alone was the right call and is now settled by the tagged text
rather than by a pending PR. Verified directly: `lib_version.o` exports
exactly eight names — the four bare forms and the four prefixed forms they
alias — and nothing else importable, which is the carve-out exactly.

## Verification

| Check | Result |
|---|---|
| `run_all_tests.py --seed 8452` | **1253/1253 pass, 6 skip, 0 fail** on long, short and compact — re-run on the final tree after the review fixes, not inherited from an earlier build |
| Per-archive export sets, all seven | identical to `master`, zero added, zero dropped |
| Member isolation | `lib_manifest.o` → §5 surface only (5 names AEAD / 4 NO_AES), 0 matching `_PRECALC_`; `precalc_manifest.o` → precalc names only (30 on LONG AEAD), 0 not matching `_PRECALC_` |
| Consumer collision probe | fails on v0.10.1, links clean here |
| All seven archive targets | build and stage the archive plus both shipped files |
| `lib-verify` (incl. knob-staleness pin + `--selftest`) | passes |
| `consumer-check` / `-noaes` / `-shipped` | clean |
| PRG byte-identity vs `v0.10.1` | identical on all three profiles |
| `VERSION` / `lib_version.s` / `API.md` §9.1 | agree at `0.11.0`, ABI 1 |

## Footprint values per archive

Unchanged from v0.8.0 — this release moves symbols between members and adds
no code. Stated anyway, one row per shipped archive, because a tag carries a
footprint pair *per archive* and "unchanged" is a claim that has to be made
per archive to be checkable. Values read back from each configuration's
built `lib_manifest.o` rather than copied from the previous release's table,
and the row count is taken against the `lib-polyval-*` target list.

| Archive | Configuration | `RESIDENT_BYTES` | `COLD_BYTES` |
|---|---|---:|---:|
| `polyval.a` | LONG, full AEAD | 6656 | 1280 |
| `polyval-gcmsiv.a` | LONG, full AEAD | 6656 | 1280 |
| `polyval-gcmsiv-short.a` | SHORT, full AEAD | 16128 | 3072 |
| `polyval-gcmsiv-compact.a` | COMPACT, full AEAD | 2816 | 512 |
| `polyval-long.a` | LONG, `LIB_POLYVAL_NO_AES` | 4352 | 1280 |
| `polyval-short.a` | SHORT, `LIB_POLYVAL_NO_AES` | 13824 | 3072 |
| `polyval-compact.a` | COMPACT, `LIB_POLYVAL_NO_AES` | 512 | 256 |

`polyval.a` and `polyval-gcmsiv.a` are the same configuration with identical
values and still get a row each: merging them makes the count unperformable,
which is how a "five rows" claim once stood over four printed rows.

The §5 published bound is unchanged: `LIB_POLYVAL_GCMSIV_MAX_PT_LEN = 64`,
exported by the four AEAD archives only.

> This table was **missing from v0.10.1 and from the first draft of these
> notes** — two consecutive releases skipping a gate `CLAUDE.md` still
> declares in force, caught by adversarial review. The trap is that both
> drafts *did* carry a seven-row table, of export counts, which satisfies a
> row-count check performed carelessly. Count the rows **and** check what
> the columns hold.

## If you are upgrading

Nothing is required, and nothing you import moves. If you link
c64-polyval **alongside another contract adopter**, this release is worth
taking: importing a §5 footprint equate no longer drags fifteen bare
`LIB_PRECALC_*` names into your link, which is a collision you could not
have worked around without member surgery the contract forbids.

## Contract currency

Current against **SPEC v1.2.2** (2026-09-06), the contract's latest tag at
the time of writing. That repository ships several releases a day —
re-check its tags rather than trusting this line, and see
`docs/contract-watch.md` for the ledger and the in-flight register.

v1.2.1 and v1.2.2 both landed while this release was being prepared, and
neither changed a line of it — which is the watch working rather than a
coincidence:

- **v1.2.1** merged the carve-out this release had already read as
  non-mooting, and its tagged text says so outright: "§5 aggregates are
  counterparts of nothing displaceable, so #177's case — bare
  `LIB_PRECALC_*` beside the §5 equates — stays forbidden." It also
  blesses keeping the bare and prefixed precalc names together, which is
  the arrangement chosen here, and states that no adopter needs to move
  for the §1 case — confirming `src/lib_version.s` was rightly left alone.
- **v1.2.2** corrects the member-isolation *rationale* only: "no
  obligation is added or removed: every library conformant at 1.2.1 is
  conformant here." Its separate ruling on bare `zp_` aliases measured the
  fleet and records that "c64-polyval and c64-mlkem export no bare `zp_`
  aliases" — N/A here, stated by the contract itself rather than asserted
  by us.

Applicability is unchanged: §3 (REU) and §8.1–§8.3 (shared primitives)
remain N/A; the §1 and §8.4 zero-consumer carve-outs remain inapplicable,
since `c64-aes256-ecdsa` pins a tag.

## Attestation

`c64-polyval-v0.11.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.11.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.11.0.tar.gz` |
| **Size**   | SIZE_PLACEHOLDER bytes |
| **SHA256** | `SHA256_PLACEHOLDER` |

Re-running `make dist VERSION=v0.11.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime is
forced to `2026-09-06T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.
