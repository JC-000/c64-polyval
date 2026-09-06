# Contract watch — charter, ledger and settle condition

This file is the **state of the c64-lib-contract alignment watch**. It exists
because the pre-1.0 contract shipped several releases a day and adopters
burned cycles chasing every one of them — realigning, re-documenting and
re-releasing for changes that did not apply to them. That is the failure
mode this file prevents. It is written to be read by whoever picks the watch
up next, including a future session of this one with no memory of the last.

Update the ledger in the same commit as any alignment work. If you read this
file and the ledger's last row is older than the contract's latest tag, the
watch has lapsed — bring it current before doing anything else.

---

## 1. The settle condition

The watch **ends** when all five hold at the same time. Not four.

| # | Condition | How to check |
|---|---|---|
| **S1** | c64-polyval has no open issues. | `gh issue list --repo JC-000/c64-polyval --state open` |
| **S2** | c64-polyval's latest **tag** is conformant against the latest **tagged** contract SPEC — every applicable clause, verified, not assumed. | §3 ledger, with a row for the current contract tag marked `verified` |
| **S3** | No open contract issue or PR names c64-polyval, or would change a c64-polyval conformance answer if merged. | §4 in-flight register, every row resolved |
| **S4** | Every contract **adopter** has a tag conformant with the latest contract tag. | §5 fleet table |
| **S5** | Every contract **consumer** has a tag that links only conformant adopter tags. | §5 fleet table |

**S4 and S5 are observed, not enforced.** This repository can only PR and tag
in c64-polyval. For every other repo the watch's output is an issue filed
against that repo, or a row in §5 saying what it is waiting on. Do not open
PRs in other people's repositories.

**The watch does not end because the contract went quiet.** Quiet is not
settled — S4 and S5 are about other repos having shipped, which quiet does
not establish.

---

## 2. Gating rules — what earns action

The churn came from treating every contract tag as work. Most are not. Apply
these in order; the first that matches decides.

**G1 — Never act on an untagged change.** Open PRs and issues in the contract
are not obligations. They go in the §4 register, nothing else.

**G2 — But do read the in-flight ones before acting on a tagged clause.** If
an open PR would *change the answer* for a finding you were about to fix,
record the finding and wait for that PR to resolve. If it would *not* change
the answer, act now and say in the commit why the in-flight change does not
moot it. This is the rule that stops both churn and paralysis, and it only
works if you actually read the PR.

> Worked example, 2026-09-06. v1.2.0 §6.1 member isolation made
> `src/lib_manifest.s` non-conformant. Contract PR #187 (then unmerged, since
> tagged as v1.2.1) adds
> a carve-out to that very clause, so waiting looked prudent. Reading it
> settled the matter in the other direction: #187 states that §5 aggregates
> "are counterparts of nothing displaceable … their co-residency with the bare
> `LIB_PRECALC_*` triple is still a violation." Our case survives the
> carve-out verbatim, so the fix was owed under both the tagged and the
> proposed text, and waiting would have been pure delay.

**G3 — Applicability before conformance.** A clause earns a verdict of
`N/A` if it governs something this library does not do. c64-polyval
permanently does not: claim REU banks (§3), consume or provide any §8.1–§8.3
shared primitive, or ship a network backend. An `N/A` verdict costs one
ledger row and nothing else. **Do not write prose explaining an N/A clause
into `API.md` or `CLAUDE.md`** — that is how the old §9 preamble grew into a
version-by-version narrative of a document that has since deleted itself.

**G4 — Doc-only contract changes get a ledger row, never a release.** If no
symbol, equate, value, segment, target or required file changes, the ledger
row is the whole response.

**G5 — Batch.** Do not cut a release per contract tag. Accumulate applicable
findings and release when one of these fires:
- a consumer is blocked on it,
- an ABI-visible defect is found (release immediately — see the v0.10.0/v0.10.1
  precedent in `CHANGELOG.md`),
- or the accumulated set is worth a consumer's attention on its own.

**G6 — Correct false claims promptly, even when nothing else moves.** A
statement that *was* true and has become false is not doc churn; it is a
defect, because a consumer plans against it. Two have bitten already: "removed
at contract v1.0" (deferred, not done) and our own claim to conform to a §6.1
requirement that v1.1.1 **withdrew**. When sweeping prose for a phrase, search
across line breaks (`tr '\n' ' '` before grep) — a line-at-a-time grep missed
two sites in v0.10.0, one of which shipped in the tarball.

**G7 — Every release goes through the gate in `CLAUDE.md`, and the
adversarial review is not optional.** If the reviewer has not reported, the
release is **held**. v0.10.0 was self-certified when the reviewers went silent
and shipped four real defects that their late reports then found, two of them
introduced by that release. A silent reviewer is a reason to wait.

---

## 3. Ledger — contract versions and our verdict

One row per contract tag. `verified` means someone checked the clause against
this repository and recorded how; `N/A` means G3; `doc-only` means G4.

| Contract tag | Applicable to c64-polyval? | Verdict | Where |
|---|---|---|---|
| v1.1.0 | §7 ABI-counter paragraph | **verified** — counter holds at 1; the argument is the *documented domain* (`pt_len 0..64` at v0.8.0), not the reject path's post-conditions | `API.md` §9.1; corrected in v0.10.1 |
| v1.1.1 | §6.1 `.inc`+`.cfg` requirement **withdrawn**; §4 `or similar` restored | **action — false claim** | our docs claimed §6.1 conformance for shipping them; see §6 below |
| v1.2.0 | §6.1 **member isolation** | **verified** (unreleased) — the §8.4 invocations now live in `src/precalc_manifest.s`; `lib_manifest.o` exports the §5 surface and nothing else (five names on the AEAD archives, four on the NO_AES ones — `LIB_POLYVAL_GCMSIV_MAX_PT_LEN` is a published bound, not a footprint aggregate, and is correctly absent there). Checked by per-archive export-set equality across all seven archives before/after (identical), and by a red/green link probe: a stub importing `LIB_POLYVAL_RESIDENT_BYTES` while owning `LIB_PRECALC_polyval_htable_SHARED` fails on v0.10.1 with `Duplicate external identifier` and links clean now | `src/precalc_manifest.s`; `API.md` §9.6 |
| v1.2.1 | §6.1 carve-out: "a displaceable name may share a TU with its own prefixed counterparts, and nothing else" | **no action, and it CONFIRMS the v1.2.0 fix.** Tagged text: "§5 aggregates are counterparts of nothing displaceable, so #177's case — bare `LIB_PRECALC_*` beside the §5 equates — stays forbidden." Also blesses keeping bare+prefixed precalc names together in one TU, which is what we did. "none needs to move" for the §1 case → `src/lib_version.s` correctly untouched | ledger only |
| v1.2.2 (2) | its #188 ruling states "**members are not consumer-named**" | **no action, but noted.** That bears on the §6.5 member-basename-prefix-at-MAJOR item this repo has recorded (and which v0.11.0 extends by adding `precalc_manifest.o`). §6.5's own text is byte-identical v1.2.0 → v1.2.2 and still names "archive members", so the deferral stands unchanged; re-check it at the next MAJOR rather than acting now | `CLAUDE.md` §6.5 bullet |
| v1.2.2 | §6.1 member-isolation **rationale** corrected (named only one of the two collision directions); plus the #188 `zp_` alias ruling | **doc-only (G4).** "No test changes and no obligation is added or removed: every library conformant at 1.2.1 is conformant here." The #188 ruling measured the fleet and names us: "c64-polyval and c64-mlkem export no bare `zp_` aliases" — N/A, stated by the contract itself | ledger only |

### Clauses permanently N/A (do not re-litigate)

§3 REU · §8.1 `sqtab` · §8.2 `reu_mul` · §8.3 `ct_mul_8x8` · §8.0 masks
(conditioned on consuming a §8.x primitive) · retired §9, §12, §13, §14, §15,
§6.3, §6.6, §6.7.

Retired-section citations elsewhere in this repo are **left as written** on
the contract's own instruction (`RETIRED.md`): each is a claim about the tag it
was made against and resolves at `git show v0.17.1:SPEC.md`.

---

## 4. In-flight register — contract issues and PRs

Read each once, decide whether it changes a c64-polyval answer, record the
verdict, and do not re-read it every cycle unless it changes.

| Ref | What | Changes our answer? |
|---|---|---|
| ~~PR #187~~ | **MERGED as v1.2.1**, verbatim as read. Moved to the ledger; the G2 call it justified was correct. | resolved |
| ~~#186~~ | closed by v1.2.1 | resolved |
| #188 | §2 / bare `zp_` alias placement | **No** — ruled at v1.2.2, which measured the fleet and found c64-polyval exports no bare `zp_` aliases. |
| #182 | §8.2 `reu_mul` providers disagree on the fetch entry | **N/A** (G3) — no REU. |
| #180 | our own §7 arbitration request | Open, ours. Answer either way is a follow-up; holding at 1 is the status quo. |

---

## 5. Fleet status — S4 and S5

Refresh with the one-liner in §7. `conformant?` is against the latest contract
tag, and is **observed**, not asserted on someone else's behalf.

| Repo | Role | Latest tag | Conformant? |
|---|---|---|---|
| c64-polyval | adopter | **v0.11.0 (tagged, released)** | verified against v1.2.2: §6.1 member isolation fixed, the withdrawn-§6.1 claims corrected, `lib_version.s` conformant outright under v1.2.1's carve-out |
| c64-nist-curves | adopter | v0.12.0 | has `src/precalc_manifest.s`; v1.2.0 changelog says "already conforms" |
| c64-x25519 | adopter | v0.13.0 | has `src/precalc_manifest.s`; split landed for v0.14.0 (**untagged** — S4 needs the tag); staging-buffer split still owed |
| c64-ChaCha20-Poly1305 | adopter | v0.10.0 | **BLOCKED on S4** — §6.1 member isolation: shipped `lib_manifest.o` exports 9 bare `LIB_PRECALC_*` names beside 8 importable §5/§8.0 equates (#177's shape). Measured in their prebuilt archive; filed as [chacha#110](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/110) |
| c64-mlkem | adopter | v0.5.0 | **clean** — defines `LIB_NO_BARE_EXPORTS = 1` in its enumerating TU per §8.4's zero-consumer carve-out, so nothing displaceable is there to isolate |
| c64-https | consumer | v0.4.3 | pins nistcurves + x25519 |
| c64-wireguard | consumer | v1.1.0 | pins x25519 + chacha20poly1305 |
| c64-aes256-ecdsa | consumer | (none) | pins c64-polyval at **v0.7.1** (four releases behind). **Enumerates `aes_sbox` + `aes_inv_sbox` with no library-prefix argument**, so it emits bare-only triples that collide with ours on any AEAD archive — dormant while it links `polyval-short.a` (NO_AES). See §6c |

---

## 6. Open alignment work in this repository

Cleared as it lands; empty means S1/S2 are met for the current contract tag.

1. ~~**§6.1 member isolation (v1.2.0).**~~ **Done, unreleased.** The
   `LIB_PRECALC_TABLE` invocations moved to `src/precalc_manifest.s`, bare and
   prefixed forms together; `precalc_manifest.o` joined `LIB_CORE_OBJS`, so
   every archive that carried those equates still carries them. Export-set
   equality holds per archive across all seven (162/162, 116/116, 89/89,
   43/43), and all three full-app PRGs are byte-identical to v0.10.1.
   `src/lib_version.s` was deliberately not touched (PR #187: "No adopter
   moves"). Drops out of this list at the next release.
2. **§6.1 `.inc`/`.cfg` claim (v1.1.1).** v0.10.0 and v0.10.1 justify shipping
   `build/lib/polyval.inc` and `build/lib/polyval-example.cfg` as a §6.1
   **MUST**. That requirement was withdrawn at v1.1.1 as never-proposed and
   failing the scope rule on both prongs. **Keep the artifacts** — they are
   useful, a consumer linking the archive genuinely needs them, and
   `make consumer-check-shipped` guards them — but restate the justification
   as a deliberate local choice, not conformance. **Done.**

   **This list was itself incomplete, and that is the lesson.** It named
   `README.md`, `API.md` and `CLAUDE.md`. The live claims were actually in
   seven places across five files — adding `Makefile` (x3),
   `src/polyval_api.inc` (x2), `src/polyval-example.cfg` and
   `test/consumer_stub_shipped.s` — and **three of those ship**:
   `README.md` and both `src/` files go into the release tarball, and the
   two `src/` files are also staged into `build/lib/` as `polyval.inc` and
   `polyval-example.cfg`. The first fix pass missed four sites; adversarial
   review caught them before tagging.

   G6 exists because of exactly this, and this release violated G6 while
   documenting it. **Enumerate the sites by sweeping, then fix — never fix
   the sites you remember and then write down that you were thorough.** The
   sweep is `tr '\n' ' '` across every tracked
   `.md`/`.s`/`.inc`/`.cfg`/`Makefile`, because the phrases wrap.

   Historical release notes stay as written (they were true at their tag).

---

## 6a. Auditing OTHER repos — use the corrected method

The contract's own fleet sweep cleared c64-polyval on this class wrongly,
and said so: it scanned sources for literal `.export` directives, and
**`LIB_PRECALC_*` names are macro-emitted**, so no source scan can see
them. It then cross-checked four built archives, and polyval was not among
them. Two holes lining up produced a confident wrong answer.

The reliable test is not *"does this library export the bare triple"* but
*"does it export the bare triple **from a TU that also exports something
else a consumer may import**"* — and it is answered from **built members**,
not source:

```sh
ar65 x <archive>.a lib_manifest.o
od65 --dump-exports lib_manifest.o | grep -c '"LIB_PRECALC_'          # displaceable
od65 --dump-exports lib_manifest.o | grep -oE '"[A-Z][A-Za-z0-9_]*"'   | tr -d '"' | grep -v '_PRECALC_' | sort                            # importable
```

Both non-empty → violation. Note two legitimate exemptions before filing:
a TU that defines `LIB_NO_BARE_EXPORTS` itself emits no bare triple
(c64-mlkem, §8.4 zero-consumer carve-out), and a name's **own prefixed
counterparts** are excepted by v1.2.1.

**Do not build in another session's working tree.** Several sibling repos
have live sessions; inspect a prebuilt archive read-only, copy it to your
own scratch dir to extract, and say in the report that a prebuilt artifact
may lag their `master`.

**G8 — check before filing cross-repo.** Search the target repo's tracker
first, and ask the contract session (`c64-lib-contract-5e`, which watches
all six trackers) whether the finding is already known. A correct,
well-measured finding filed on top of an existing one is still churn in
someone else's tracker during a settlement run — which is the cost this
watch exists to avoid, so it is not excused by being right. Cost paid once:
polyval filed chacha#110 forty-four minutes after chacha#108 already
covered it more broadly; closed as duplicate with the corroboration left
attached, since a second measurement by a different route was the one part
worth keeping.

Do not let the check become a blocker. If the coordinating session does not
answer, search the tracker yourself and file with a line saying you could
not confirm it was novel.

## 6b. This file does not ship

`tools/build_release.sh` stages `docs/` by explicit `cp`, not a glob, and
this file is deliberately left out — recorded here and in the script because
an omission in an explicit list is otherwise indistinguishable from an
oversight. It is live process state: a ledger that moves with every contract
tag, an in-flight register of other repositories' open issues, and a fleet
table. Frozen into a release tarball it would be stale on arrival and would
make claims about other repositories that a consumer could read as current.
It lives on `master`.

## 6c. Sweep CONSUMERS too, not just adopters

v0.11.0 shipped a release note claiming the library-versus-library
collision direction was latent because "no sibling **adopter** enumerates
any of our five table names". True, and irrelevant: `c64-aes256-ecdsa` is
a **consumer**, it is in the §5 fleet table above, and it enumerates two of
them. The sweep was scoped to the wrong list by habit.

The bare `LIB_PRECALC_*` namespace is flat across everything that includes
`precalc_table.inc` — adopters, consumers, and any app that vendors the
macro. Sweep all of them:

```sh
for r in c64-nist-curves c64-x25519 c64-ChaCha20-Poly1305 c64-mlkem \
         c64-polyval c64-aes256-ecdsa c64-https c64-wireguard; do
  printf '%-24s ' "$r"
  grep -rhE '^[[:space:]]*LIB_PRECALC_TABLE' ~/Documents/$r/src 2>/dev/null \
    | grep -oE '"[a-z0-9_]+"' | tr -d '"' | sort -u | tr '\n' ' '; echo
done
```

Two traps met while doing it: matching commented examples inside
`precalc_table.inc` itself (it documents `"sqtab"` and `"name"`, which made
every repo look like an `sqtab` enumerator), and an invocation with **no
fifth argument**, which emits the bare triple *only* — the collision-prone
form, and easy to read past.

## 6d. Two kinds of stale citation — sweep for the second one

Contributed by the contract session from four repos' findings. The first
kind is easy and the second is the one that survives audits.

**Kind 1 — wrong quotation.** Superseded clause text reproduced verbatim.
Our `src/precalc_manifest.s` quoted v1.2.0 §6.1 without v1.2.1's carve-out,
under which that very file would have been non-conformant. Found by diffing
the quote against the frozen tag: `git show v1.2.2:SPEC.md`.

**Kind 2 — correct citation, wrong tense.** c64-nist-curves' Makefile had
`# §6.1 (contract v1.1.0) requires make lib to produce the archive PLUS the
.inc header and an example .cfg`. The citation is *accurate* — v1.1.0 did
require it. The defect is the present-tense **requires** in a repo claiming
conformance through v1.2.2. A quotation diff finds nothing here, because
nothing is wrong with the quotation.

**The durable form subsumes both:** *does every present-tense obligation in
my tree still exist at the tag I claim?* Sweep the modal verbs and check
each against the frozen SPEC:

```sh
python3 - <<'EOF'
import re, subprocess, pathlib
files = [f for f in subprocess.run(["git","ls-files"],capture_output=True,text=True).stdout.split()
         if re.search(r"\.(md|s|inc|cfg|sh|py)$|Makefile$", f)
         and not f.startswith("docs/RELEASE_NOTES_v0.")]
pat = re.compile(r"§\d+(?:\.\d+)?[^.;\n]{0,80}?\b(requires|MUST|must|owes|obliges|demands)\b[^.;\n]{0,50}")
for f in files:
    flat = " ".join(pathlib.Path(f).read_text(errors="ignore").split())
    for m in pat.finditer(flat):
        print(f"{f}\n    {m.group(0)[:150]}")
EOF
```

Note it must flatten newlines first — these phrases wrap, which is the same
trap as G6.

**Run on this repo at v0.11.0 it returned 31 hits and three were real**, all
present-tense obligations against retired or renumbered clauses:

| Site | Was | Now |
|---|---|---|
| `src/precalc_manifest.s` | "SPEC §8.0 requires every adopter to enumerate" | §8.4 — and this was a file created *the same day* I fixed §8.0→§8.4 everywhere else |
| `Makefile` | "SPEC §6.3's looks-reachable rule — a knob … MUST" | §6.3 retired at v1.0.0; marked as local engineering |
| `tools/check_knob_staleness.sh` | fail message citing "SPEC §6.3 C1" | same |

**Not every citation of a moved section is stale.** c64-nist-curves' own
distinction: their `check_archives.py` cites §6.1 for the *live*
member-isolation clause and correctly keeps it; their example cfg cited
"§4 / §6.1" where §4's standalone-build clause is live and §6.1's file
requirement is not. Judge per clause, not per section number.

The `§6.6` citations in `src/lib_manifest.s` are deliberately **not** in
this table: they are historical, the file carries a header note saying where
the obligation moved (§5), and `RETIRED.md` asks adopters not to churn them.
Kind 2 is about a live obligation stated in the present tense, not about a
citation of a retired clause that is honestly labelled as history.

## 6e. Parsing `od65` — and why a comparison check fails silently here

Every conformance measurement in §6a and §6d runs through
`od65 --dump-exports`. Its `Name:` field is padded by **`|24 − namelen|`
spaces** — a negative `%*s` width left-justifying, *not* a fixed column.
At namelen exactly 24 the padding is zero and the output reads
`Name:"foo"` with no separator at all.

**c64-polyval has such a symbol: `polyval_precompute_table`, exactly 24.**
It is exported from all three profile objects, so it is in every archive
this library ships. Measured here, 29 distinct lengths from our own
archives, 9 through 42 — every one matches `|24 − namelen|`:

```
namelen 22 -> "      Name:  \"LIB_POLYVAL_COLD_BYTES\""      2 spaces
namelen 24 -> "      Name:\"polyval_precompute_table\""      0 spaces  <-- runs together
namelen 42 -> 18 spaces
```

A fixed-column model predicts zero padding for *every* length ≥ 24 and is
refuted by the 42-length row. It also predicts long names are the hazard,
when the hazard is the single length where the expression is zero.

**Use quote-anchored extraction. Never field-splitting.**

```sh
od65 --dump-exports x.o | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"'   # correct
od65 --dump-exports x.o | awk '/Name:/{print $2}'                           # WRONG
```

Verified on the real object: the quote-anchored form returns
`polyval_precompute_table`; the field-splitting form returns **nothing** for
it. `\s*` and quote-anchored `sed` are safe; `\s+` and field-splitting are
not.

**The near-miss, which is the part worth internalising.** v0.11.0's central
evidence was per-archive export-set *equality* — the same extraction run
over a `master` build and a patched build, sorted and diffed. Had that used
field-splitting, `polyval_precompute_table` would have been dropped from
**both** sides and the sets would still have matched. The check would have
reported "identical, zero added, zero dropped" while being blind to one
symbol in every archive.

**A comparison check does not fail loudly when its extractor is broken
symmetrically — it agrees, wrongly.** That is strictly worse than a check
that errors, and it is the same family as a sweep that cannot see a class
and returns silence (§6a) and a green artifact that never examined the
property it reports on. When the evidence is a diff, verify the *extractor*
against a known-hard input before trusting the *result*.

**The general rule, from the contract session:** before broadcasting a
mechanism, vary the parameter across its range. The fixed-column story was
relayed to three repos on two data points. Two points fit a lot of curves,
and a symptom reproduced is not a cause established.

## 7. Refresh one-liner

```sh
# contract state
git -C ~/Documents/c64-lib-contract fetch --tags -q
git -C ~/Documents/c64-lib-contract tag --sort=-v:refname | head -3
gh issue list --repo JC-000/c64-lib-contract --state open --limit 30
gh pr    list --repo JC-000/c64-lib-contract --state open --limit 20

# fleet state (S4/S5)
for r in c64-polyval c64-nist-curves c64-x25519 c64-ChaCha20-Poly1305 \
         c64-mlkem c64-https c64-wireguard c64-aes256-ecdsa; do
  printf '%-26s ' "$r"
  echo "issues=$(gh issue list --repo JC-000/$r --state open --limit 100 | wc -l | tr -d ' ')" \
       "tag=$(gh release view --repo JC-000/$r --json tagName -q .tagName 2>/dev/null || echo -)"
done
```
