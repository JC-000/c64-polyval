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

## 0. STATUS: REOPENED 2026-09-07 — S4 broke after close

**The watch was closed 2026-09-06 with S1–S4 met (scope reduced to adopters
by JC-000's ruling; §11 consumers out of scope, handed off in §5a). It is
reopened because S4 no longer holds: the contract session RETRACTED
c64-x25519's settled status the next day (contract#193), so one of the five
adopters is now "tagged with open findings", not settled. Reopening at the
ruled scope — S1–S4. S5 stays out of scope; §5a remains the handoff, not a
condition.**

| | State at reopen, 2026-09-07 | vs. close |
|---|---|---|
| **S1** | **NOT MET; twelve open, six of them covered by four PRs now awaiting JC-000.** **PR#108** (#97), **PR#111** (#89/#94/#103), **PR#112** (#105), **PR#114** (#87) — all four MERGEABLE, each rebased onto master independently and `make verify` green on each, each adversarially reviewed to a stop (4/4/3/6 rounds). **Every one had its headline claim broken on first review; three had a second broken after the first fix.** The remaining six — #104, #106, #107, #109, #110, #113 — are deliberate follow-ups, each deferred with argued reasoning, and #113's rule was stated *before* the round that produced it | **awaiting merge** |
| **S2** | `v0.11.0`, verified conformant against SPEC **v1.2.2** (still the latest tag) | holds |
| **S3** | three open contract items as of 07:05: **#193** (x25519 retraction), **#194** (their `verify-addrsize` passes with no `od65` at all), **PR #195** (records adversarial review + red/green as *their repo's* standards, explicitly **not** contract text). Each read; **none changes a c64-polyval conformance answer** | was 0/0 |
| **S4** | **NOT MET.** x25519 `v0.16.0` retracted by #193 — four reproduced conformance gaps (§8.2, §8.4, §2/§5, §4) plus an evidence defect. polyval `v0.11.0`, nist-curves `v0.14.0`, chacha `v0.11.0`, mlkem `v0.5.0` unchanged, but nist-curves carries **#155 [HIGH] §6.1** filed 2026-09-06, which is the same shape and wants the same "tagged with open findings" reading | **broke** |
| **S5** | out of scope by ruling — see §5a; pins unchanged | unchanged |

**The reopening reason is the one this file already warned about.** §0's
close said S4 "claims each library's tag is true about itself" — and that
claim was false for x25519 within a day, on evidence that existed at the
time but had not been read. Two commissioned adversarial reviews arrived
after the settle call was published.

**Carry contract#193's lesson into this repo's own practice** (it is why the
adversarial-review + red/green standard is now written into `CLAUDE.md`):
its three `-negative` verification legs were *structurally incapable of
failing* — `X || (echo FAIL; exit 1)` mid-`;`-chain does not propagate, so
each printed FAIL and then exited 0. Every claim those legs backed was
unverified when made. A check that has never been observed to fail has not
been shown to check anything. Its taxonomy also adds a fourth form worth
holding onto: **a gate whose fixture encodes the defect it should catch.**

To close again: **S1** needs the eight open issues resolved (two are in
review as PR#88 and PR#92; #87, #89, #93 and #94 have reproductions and no
fix), and S4 needs x25519 back to settled (their #130/#132 and the
four #193 gaps) and nist-curves#155 resolved or ruled non-settling, with
each verified **at the tag**. Treat §5a as starting facts, not something to
rediscover.

## 1. The settle condition

The watch **ends** when all five hold at the same time. Not four.
*(Superseded at close: scope reduced to S1–S4 by ruling — see §0.)*

| # | Condition | How to check |
|---|---|---|
| **S1** | c64-polyval has no open issues. | `gh issue list --repo JC-000/c64-polyval --state open` |
| **S2** | c64-polyval's latest **tag** is conformant against the latest **tagged** contract SPEC — every applicable clause, verified, not assumed. | §3 ledger, with a row for the current contract tag marked `verified` |
| **S3** | No open contract issue or PR names c64-polyval, or would change a c64-polyval conformance answer if merged. | §4 in-flight register, every row resolved |
| **S4** | Every contract **adopter** has a tag conformant with the latest contract tag. | §5 fleet table |
| **S5** | Every contract **consumer** has a tag that links only conformant adopter tags. | §5 fleet table |

> **S5, re-measured from the remotes 2026-09-06.** Four stale pins across
> **two** consumer repos, then their tags: c64-https (`nistcurves`
> v0.11.2 → v0.14.0, `x25519` v0.13.0 → v0.16.0) and c64-wireguard
> (`chacha20poly1305` v0.9.0 → v0.11.0, `x25519` v0.11.2 → v0.16.0).
> c64-aes256-ecdsa is **not** an archive consumer on `master` and does not
> belong in this count — the earlier "five pins across three repos" figure
> included a submodule that exists only in a local checkout (§6h). Do not read "S4 nearly closed" as "settlement nearly
> reached": they are different orders of work, and the second is in repos
> this watch can only observe.

> **S4 is a TAGGING gate, not a work gate** (checked 2026-09-06). The
> contract is frozen clean at v1.2.2, zero open issues, zero open PRs. S4
> **S4 IS MET as of 2026-09-06.** All five adopters carry a settling tag,
> each verified at the tag: c64-polyval **v0.11.0**, c64-nist-curves
> **v0.14.0**, c64-x25519 **v0.16.0**, c64-ChaCha20-Poly1305 **v0.11.0**,
> c64-mlkem **v0.5.0** (clean by the §8.4 zero-consumer carve-out).
>
> **S5 is the only condition still open**, and it is the larger one: five
> stale submodule pins across three consumer repos, then three consumer
> tags. See the consumer rows below. Verify each against the
> **tag**, never against a branch: a fix on a branch is not a release, and
> a consumer pins tags. Equally — read the **tag**, not the latest GitHub
> Release; they are different things and §6g is the cycle where that cost
> three cycles of a wrong fleet row.

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
adversarial review is not optional.** Since 2026-09-07 this is the wider repo
standard, not a release-only rule: `CLAUDE.md` §"Working standard" requires a
commissioned adversarial review and a red-first check on every feature and
issue, with the positive-control step contract#193 shows the cost of skipping. If the reviewer has not reported, the
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
**As of 2026-09-07 ~20:10 the contract has FIVE open issues (#198, #199,
#201, #202, #203) and ONE open PR (#200 — SPEC v1.2.3, §5 footprint basis),
at v1.2.2.** #202 is the scope problem (a figure does not say which
configuration it describes) and **#203 is our own 9,625 B finding, filed
upstream as promised** — the §7 reading for it is pre-recorded in §6 item 3.
Earlier state: **TWO open issues (#198, #199) and ZERO open PRs at ~19:15.** #193 and #194 closed COMPLETED; PRs #195, #196
and #197 all merged within 27 seconds of each other. **None of the three
touched `SPEC.md`** — they changed `CLAUDE.md`, `adopters.md` and `Makefile`
respectively — and no new tag was cut. So the conformance surface is
unmoved: G1 (untagged) and G4 (doc-only) both apply, ledger row and nothing
else. The one substantive consequence is that **#196 makes "x25519 is tagged
with open findings" the contract's own recorded position**, which is what §0
already reads S4 against (was 0/0 at close the previous
day). None changes a c64-polyval conformance answer; #196 and #197 close the
two issues when they merge. Re-check before trusting
this — that repo has shipped several releases a day.

| Ref | What | Changes our answer? |
|---|---|---|
| ~~**#193**~~ | **Closed COMPLETED by PR#196** (merged 2026-09-07, `adopters.md` only). Retraction of c64-x25519's settled status at v0.16.0: four reproduced conformance gaps (§8.2 provider surface, §8.4 2048 B unenumerated, §2/§5 `fe_wide` ZP, §4 RAM-backed declaration) plus an evidence defect — three `-negative` legs that could not fail | **No conformance answer changes here.** No clause text moved; the contract is still v1.2.2 and §8.x is N/A to us (G3). Two effects that are not conformance: it **breaks S4** (§0), and its check-taxonomy fourth form — *a gate whose fixture encodes the defect it should catch* — is adopted into this repo's working standard (`CLAUDE.md`) |
| ~~**#194**~~ | **Closed COMPLETED by PR#197** (merged 2026-09-07, `Makefile` only). Their `make verify-addrsize` was a zero-count absence check with no positive control: `OD65=/bin/false make verify-addrsize` prints `ok` and exits 0. A `dump=$(... | awk)` assignment takes awk's status, so a missing dumper yields an empty string, both loops iterate zero times, and `bad=0` prints success | **No.** Their Makefile, not ours (G3/G1 — untagged, and not a clause). Kept for the **form**: an absence assertion that cannot tell "looked and found none" from "looked at nothing". `CLAUDE.md`'s positive-control rule already covers it; the local audit it implies is recorded in §6 |
| ~~**PR #195**~~ | **MERGED** 2026-09-07, `CLAUDE.md` only — no SPEC change, so still no obligation on adopters, exactly as its own text said. Records adversarial review + red/green as standards **in the contract repo's own `CLAUDE.md`**. States in its own text that it is not contract text and fails prong 2 of the scope rule, and that it is **not** grounds to un-retire §15 | **No — and no obligation lands on adopters, by its own terms.** Convergent with what this repo adopted the same morning. Two of its ideas are worth taking locally and have been (§6 item 3): the **churn test** and the **citation duty** |
| ~~**PR #196**~~ | **MERGED** 2026-09-07, `adopters.md` only. Records c64-x25519 as *tagged with open findings*, not settled; closes #193. Its own adversarial review rejected two of the four verdicts and it revised them — all four gaps stand, §4 confirmed on the declaration (not the attribute), §2's parenthetical withdrawn, §8.2 rescoped with a positive-controlled `git grep` in place of a GitHub code search | **No.** Confirms the S4 reading already recorded in §0. The eight x25519 issues (#130, #132–#138) are the gaps filed out; observed, not audited here |
| **PR #204** | Records nist-curves' #155 as *fixed on main but not in any tag* | **No** — but it is the same distinction this watch drew independently an hour earlier for the same PR pair. Nothing to do; noted as corroboration that S4 reads tags |
| ~~**PR #197**~~ | **MERGED** 2026-09-07, `Makefile` only. Fixes their #194: three gates — od65 actually ran, the extractor saw every export the dumper declared, and the population reconciles — replacing the zero-count absence check. Also drops the `awk $2` extraction whose padding is `|24 - namelen|` | **No** (their Makefile). Worth reading as prior art when fixing **our #86**, which is the same class || Ref | What | Changes our answer? |
| **#198** | Their `verify-addrsize` never dumps the `nobare` object, so the address-size ratchet is checked **only in the mode a composing consumer does not use**. The two modes emit from different macro branches, so passing in one is not evidence about the other. Found by the adversarial review on #197 | **No conformance answer changes** (their Makefile, untagged — G1/G3). But the *question* lands here and was worth asking: measured on `a8db2a2`, our `precalc_manifest.o` suppresses correctly (15 bare → 0, 15 prefixed kept, all absolute in both modes) and **nothing asserts it**. Filed as our **#89** ||---|---|---|
| **#199** | Concludes **no clause** for the "gate never builds this configuration" class: the sweeping form is unbounded and unsatisfiable — c64-https assembles x25519's sources directly, so no library-side `make` could reproduce it. **CORRECTED TWICE by its own author after adversarial review, and my first summary of it here repeated a retracted claim** (see the row below) | **No obligation lands here, and it names our class explicitly**: the "gate never builds this configuration" findings — ours is **#94** — are "each library's own testing gap", findable from inside the repo, failing prong 2 |
| **#199 (corrected)** | The retracted part was the reasoning, not the outcome. Two corrections: (1) *"§5's safe direction — a consumer's fit assert is conservative, not wrong"* **is false as stated** — it generalised from one consumer, and the two consumers assert on the same field in **opposite senses** (`c64-https/src/contract_footprint_asserts.s:127,130` asserts `RESIDENT + COLD <= __CRYPTO_HOT_SIZE`), so over-declaration is not automatically harmless; (2) chacha's 17664-vs-8351 gap was **not** a §6.4 violation — their gates are purely subtractive `.ifndef`, so declaring the un-deferred value is a deliberate superset. The sharper property that survives: **"round up, never down" is only meaningful if every axis that moves the footprint is modelled — a subtractive gate guarantees the direction, a swap does not.** Their `ROLLED` multiply axis appears **0 times** in their manifest, so their figure is safe only by coincidence of which body is currently biggest | **Checked against us, and we are clean by construction — measured, not assumed.** Both size-moving axes here are swap-or-subtract and **both are modelled**: `POLYVAL_PROFILE` (16 references in `src/lib_manifest.s`) and `LIB_POLYVAL_NO_AES` (13), with a distinct declared pair per arm — RESIDENT/COLD of 6656/1280, 16128/3072, 2816/512, 4352/1280, 13824/3072, 512/256 across the six archives. A source scan finds no other conditional that moves code or data: the remaining `.ifndef`s are ZP-slot equate guards and `ZP_CONFIG_NO_EXPORTS`, which suppresses `.exportzp` directives only. **The profile axis is exactly the swap shape that bit chacha** — SHORT's multiply is 13,614 B against LONG's 4,160 — and it is modelled per-arm rather than covered by one number || ~~PR #187~~ | merged as **v1.2.1**, verbatim as read; the G2 call it justified was correct | resolved |
| ~~#186~~ | closed by v1.2.1 | resolved |
| ~~#188~~ | §2 / bare `zp_` alias placement | resolved at v1.2.2, which measured the fleet and found c64-polyval exports no bare `zp_` aliases |
| ~~#180~~ | our §7 arbitration | **closed, and the ruling corrected in place.** It had affirmed our post-conditions argument; we found three post-conditions differ, and the contract re-based the ruling on the documented-input-domain argument. The forward test is recorded in `CLAUDE.md` and `API.md` §9.1 |
| ~~#182~~ | §8.2 `reu_mul` fetch entry | closed; N/A here (no REU) |
| #182 | §8.2 `reu_mul` providers disagree on the fetch entry | **N/A** (G3) — no REU. |
| #180 | our own §7 arbitration request | Open, ours. Answer either way is a follow-up; holding at 1 is the status quo. |

---

## 5. Fleet status — S4 and S5

Refresh with the one-liner in §7. `conformant?` is against the latest contract
tag, and is **observed**, not asserted on someone else's behalf.

| Repo | Role | Latest tag | Conformant? |
|---|---|---|---|
| c64-polyval | adopter | **v0.11.0 (tagged, released)** | verified against v1.2.2: §6.1 member isolation fixed, the withdrawn-§6.1 claims corrected, `lib_version.s` conformant outright under v1.2.1's carve-out |
| c64-nist-curves | adopter | **v0.14.0 — tagged with open findings; six open** (#142, #159, #161, #167, #168, #170). PR#160/#162/#164/#165 merged; **PR#166, #169, #171 open** — #171 closes #159, our **#89**'s twin (11 of 12 archives never examined by the gated legs), and is **stacked on #169**. Every merged fix is still on `main` with the tag at v0.14.0, so their settling tag carries none of them and S4 is unmoved | #153 and #154 both closed. #154 verified at the tag with a §6g positive control: bare `zp_*` aliases in `zp_config.s` went **4 → 0**, and `src/zp_aliases.s` (104 lines) plus `src/mul_aliases.s` appeared as the separate archived TUs. #153 is §8.2 REU — **N/A to this library** and their domain to certify; recorded as closed by them, not audited here |
| c64-x25519 | adopter | **v0.16.0 — RETRACTED (contract#193), eleven open** (#132, #134–#138, #140, #142–#145). PR#141, PR#146 and **PR#147 merged** (our #86's and #94's twins, plus the `.import`/`.global` header fix that is N/A here). All three are on `main`; their tag is still v0.16.0, so none is in a tag and S4 is unmoved | their settling tag, verified at the tag with a §6g positive control: `src/precalc_manifest.s` present, `lib_manifest.s` 0 macro invocations (3 at v0.13.0), ref+path confirmed to exist so the zero is a real zero. Member isolation shipped at v0.14.0; v0.15.0 added §8.2 `A = a` and ABI 3 → 4; v0.16.0 closes their #128 |
| c64-ChaCha20-Poly1305 | adopter | **v0.12.0 tagged 2026-09-07** (was v0.11.0), tracker clean: zero open issues, zero open PRs. Their release notes state ABI generation stays 4, 97 export rows on both sides with zero name difference, and all four profile PRGs byte-identical to v0.11.0 — a label/footprint/gate-coverage release with no emitted-code change. **Recorded as THEIR evidence, not our verification**: checking it would mean building their tree, which this watch does not do (§6a). Conformance carries from the v0.11.0 verification if those claims hold | verified at the tag with a §6g positive control. `lib_manifest.s` 5 macro invocations at v0.10.0 → **0** at v0.11.0, `src/lib/precalc_manifest.s` present. Both #108 members done: `poly1305_lib.s` went 11 `.export` lines → 2, moving out the 8 `APP_OWNED` §8.1/§8.3 names. Their release also corrects the five under-reporting footprint equates from #113 |
| c64-mlkem | adopter | v0.5.0 (open: #3 stale contract version in their CLAUDE.md, #1 §6.3 warm-tree define drop) | **clean on §8.4** — defines `LIB_NO_BARE_EXPORTS = 1` in its enumerating TU per §8.4's zero-consumer carve-out, so nothing displaceable is there to isolate |
| c64-https | consumer | v0.4.3 | pins `libs/nistcurves` **v0.11.2** and `libs/x25519` **v0.13.0** — both stale; needs nistcurves v0.14.0 and x25519 v0.16.0 |
| c64-wireguard | consumer | v2.0.0-ca65 | pins `libs/chacha20poly1305` **v0.9.0** and `libs/x25519` **v0.11.2** — both stale; needs chacha v0.11.0 and x25519 v0.16.0 |
| c64-aes256-ecdsa | consumer | (none) | **Not an archive consumer on `master`.** Verified from `origin/master`: no `.gitmodules`, no `libs/` tree, and `src/polyval.s` is built as its own `MODULES` entry. The v0.7.1 submodule pin recorded here earlier came from a **locally modified clone**, not the repo — see §6h. Its `src/precalc_manifest.s` does emit bare-only triples overlapping three of our names (`aes_sbox`, `aes_inv_sbox`, `polyval_htable`), latent until it links one of our archives — their #28. **Enumerates `aes_sbox` + `aes_inv_sbox` with no library-prefix argument**, so it emits bare-only triples that collide with ours on any AEAD archive — dormant while it links `polyval-short.a` (NO_AES). See §6c |

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

3. **Release in flight: v0.12.0.** JC-000 asked for the board cleared and a
   tagged release, worked by a supervised team (implementer + a *different*
   adversarial reviewer per change, supervisor holds the gate and does not
   implement — the shape c64-x25519 adopted in their PR#141).

   **Version call: MINOR, v0.12.0.** The library itself is unchanged — every
   commit this cycle touches `Makefile`, `tools/` or docs, so the three PRGs
   should come out byte-identical to v0.11.0 and `LIB_POLYVAL_ABI_VERSION`
   stays **1**. What makes it MINOR rather than PATCH is additive §6.1 surface:
   `verify` plus `check-no-tracked-artifacts`, `check-scratch-prefix`,
   `check-footprints`, `check-composing-mode` are consumer-visible make
   targets, and nothing was removed or renamed.

   **The seven footprint rows, measured 2026-09-08** — one per shipped
   archive, per the release-flow rule. `polyval.a` and `polyval-gcmsiv.a`
   carry identical values and still get **two rows**: merging them is what
   made v0.7.0–v0.7.2's own row-count claim unperformable.

   | archive | RESIDENT | COLD | `GCMSIV_MAX_PT_LEN` |
   |---|---|---|---|
   | `polyval.a` | 6656 | 1280 | 64 |
   | `polyval-gcmsiv.a` | 6656 | 1280 | 64 |
   | `polyval-gcmsiv-short.a` | 16128 | 3072 | 64 |
   | `polyval-gcmsiv-compact.a` | 2816 | 512 | 64 |
   | `polyval-long.a` | 4352 | 1280 | absent |
   | `polyval-short.a` | 13824 | 3072 | absent |
   | `polyval-compact.a` | 512 | 256 | absent |

   `MAX_PT_LEN` is correctly absent from the three NO_AES archives, which
   ship no `gcm_siv.o`. All seven values are unchanged from v0.11.0.

   **Version-bump sites verified consistent 2026-09-08**, so the bump is a
   clean 11 → 12 in exactly three places and nothing needs reconciling first:
   `VERSION` says `0.11.0`, `src/lib_version.s` builds an object exporting
   `MAJOR 0 / MINOR 11 / PATCH 0 / ABI 1`, and `API.md` §9.1's value table
   rows read the same. Checked because v0.4.1 bumped the file and left the
   table stale, and v0.3.0 forgot the file entirely for a whole cycle.

   Release gate, in order: board cleared → version bump in `VERSION`,
   `src/lib_version.s` **and `API.md` §9.1's value table** → notes with the seven rows → `make clean &&
   make dist` → reproducibility re-run → full VICE suite on all three profiles
   → a U64E confirmation run (JC-000 offered the hardware; it is confirmatory,
   not diagnostic, since the PRGs are byte-identical) → release PR →
   adversarial review → **then** the tag. Never the tag first: that is how
   v0.10.0 shipped four defects.

4. **Audit this repo's own checks for the #194 form — OPEN, not yet done.**
   Filed here 2026-09-07 off contract#194 and nist-curves#142. The question
   is not "do our checks pass" but **"has each one ever been observed to
   fail?"** Candidates, in rough order of exposure: `make
   consumer-check-shipped` (issue #79 guard — does it still fail if a shipped
   file is removed?), `make consumer-check-noaes` (#47 guard),
   `tools/check_knob_staleness.sh`, the `build/.ca65flags` parse-time stamp,
   and the `make dist` reproducibility re-run. Any that is an **absence**
   assertion, or whose pass condition is a zero, needs a positive control:
   sabotage the input, confirm red, restore, confirm green — and record both
   directions. Also sweep for the non-propagating
   `X || (echo FAIL; exit 1)` shell form in `Makefile` and `tools/*.sh`.

   **First pass done 2026-09-07.** Four guards driven red, each with a
   deliberate defect: `consumer-check-shipped` (a reachback added to the
   shipped `.inc` → `Cannot open include file`), `consumer-check-noaes` (the
   NO_AES stub linked against the AEAD archive → `Duplicate external
   identifier: 'gcmsiv_tag'`), the `.ca65flags` stamp (warm LONG→SHORT switch
   with the stamp disabled → PRG byte-identical, i.e. the #58 defect
   reproduced), and `check_knob_staleness.sh --selftest` (reports 13, not 0).
   All four can fail. Two defects fell out and are filed: **#85** (`make dist`
   overwrites a released tarball and rewrites its Attestation when the tree
   has moved past the tag — fixed in PR #88, whose *first* version was itself
   broken by adversarial review in two places) and **#86** (export counters
   cannot tell 0 from a missing object). **#87** came from the same review.
   c64-x25519#133, filed the same day, is #86's exact twin in another repo,
   and contract PR#197 is the fix for the same class — read both before
   fixing ours.

   **Second pass, same day, from contract#198 + x25519#139 + chacha#119 —
   one question, asked three ways across the fleet: *is the gate checked in
   the mode consumers compose in, and does anything invoke it at all?*** Our
   answers, measured: the §1 half IS verified
   (`check_knob_staleness.sh` asserts `lib_version.o` 4 → 0 under
   `-D LIB_NO_BARE_EXPORTS=1`); the §8.4 half is **not** — nothing looks at
   `precalc_manifest.o` in that mode, which is the surface
   c64-aes256-ecdsa#28 would collide with. Filed as **#89** (behaviour is
   correct today; the assertion is what is missing). Second answer, recorded
   here because it is chacha#119's question and it has no issue yet: this
   repo has **no CI** — `.github/workflows` does not exist, and only
   `lib-verify` invokes a guard automatically (`check_knob_staleness.sh`).
   `consumer-check`, `consumer-check-shipped` and `consumer-check-noaes` run
   only when a human types them. Raise with the owner before filing; an
   umbrella `verify` target is the cheap half and CI is a policy call.
   **Resolved 2026-09-07 by chacha PR#128**, which fixed their side and made
   the sharper question askable: their *release script* carried a hand-copied
   gate list that had drifted, so every tarball shipped checked with four of
   six. Asked here, the answer was worse — **`make dist` has no prerequisites
   and `tools/build_release.sh` invokes no gate at all, so our releases run
   zero.** Filed as **#96**. The cost objection died on measurement: all four
   gates from a cold tree take **~1 second** (verified they actually ran, not
   short-circuited — `consumer-check-noaes` emitted its three archive builds).
   CI still deliberately not filed. **Their PR#128 merged 2026-09-07** — it is prior art for #96 and worth reading before implementing ours: one `VERIFY_TARGETS` list, the release script calling `make verify` rather than restating it, and a throwaway-clone red/green that tags nothing in the real repo.

   **Third pass, from nist-curves#158 — and this one found a live gap in a
   check we already had.** Their framing: *the gate is checked only for what
   it must remove, never for what it must keep.* Reproduced here by mutation:
   move `.export LIB_POLYVAL_VERSION_PATCH: abs` into the
   `.ifndef LIB_NO_BARE_EXPORTS` block, and the prefixed export vanishes from
   the composing mode while `check_knob_staleness.sh` **and**
   `consumer-check-shipped` both stay green. A consumer building with
   `-D LIB_NO_BARE_EXPORTS=1` — the whole point of the switch — would get an
   undefined symbol from a library whose gates are green. Filed as **#90**.
   Source restored from a pre-mutation copy, not `git checkout`, and `build/`
   rebuilt after.

   **#86, #90, #89 are one job in that order:** rewrite the export-counting
   helpers to reconcile instead of counting to zero (#86), then use them to
   assert the kept surface for §1 (#90) and §8.4 (#89).

   **Fourth pass, from x25519#140 — reproduced here 3/3.** Their finding is
   fixed-name guard trees racing between concurrent runs. Ours:
   `check_knob_staleness.sh`'s `build-knobcheck` and the Makefile's
   `shipped-check`, both fixed-name, both `rm -rf`'d at recipe start, with a
   cleanup trap deleting the same path on exit. Two concurrent runs in one
   tree destroy each other every time. Filed as **#93**. It fails *loudly*, so
   it cannot certify a broken library as good — but it compounds with #86: a
   raced `od65` on a half-deleted tree used to report `0`, which every
   assertion whose pass condition is a zero would have accepted.

   **Fifth pass, from chacha#122 — *does any gate build what a real consumer
   builds?*** Measured: **no guard here links a consumer against an archive
   built with `-D LIB_NO_BARE_EXPORTS=1`.** `consumer-check-shipped`
   assembles with a bare `$(CA65)` and links the default archive;
   `consumer-check-noaes` passes profile and NO_AES defines only;
   `check_knob_staleness.sh` builds with the define but never links. The
   configuration does work by hand (archive built nobare, stub links, 6543 B)
   — it is simply unexercised, in the one mode a composing consumer must use
   and that c64-aes256-ecdsa#28's collision forces. Filed as **#94**.

   **Sixth pass, from nist#159 — the VARIANT axis.** Their finding: the
   gated-surface leg assembles with no variant define, so a bare export
   leaking in a variant arm passes every leg. Ours builds only the default
   LONG AEAD arm, while `lib_manifest.s` carries 21 conditionals,
   `precalc_manifest.s` 3, and six archives ship. Measured across all six
   arms under `-D LIB_NO_BARE_EXPORTS=1`: bare is 0 everywhere, prefixed is
   **15/9/9/9/3/3**. Correct in every arm, checked in none. Folded into #89
   as a requirement rather than filed separately — those per-arm numbers are
   exactly the expected-value set a reconciling check needs, and a leak
   planted in one arm must fail that arm alone.

   Their **PR#160** also checks in a reviewer agent definition alongside the
   standard. Adopted: `.claude/agents/adversarial-reviewer.md`, which encodes
   the brief that has now found defects twice in this repo.

   **Trip-wire check against contract#199, 2026-09-07** (the issue was
   corrected twice after this was written; the check below still stands, and
   the ledger row records what changed). That issue records three conditions
   that would turn this class into a clause, the first being *a library
   **under**-declaring its §5 footprint in the configuration a consumer
   actually ships*. Measured here: the §5 aggregates are byte-
   identical between the default build and `-D LIB_NO_BARE_EXPORTS=1` —
   `RESIDENT 6656`, `COLD 1280`, `REU_BANKS 0`, `ZP 45`, `MAX_PT_LEN 64` in
   both — which is expected, since that knob suppresses export *names* and
   moves no code or data, but it is now measured rather than assumed. The
   other two trip-wires (a miss producing a link failure; a third consumer
   entering the fleet) are not ours to observe. **Re-check this if a footprint
   ever becomes conditional on a non-member-set define.**

   A note on how that measurement was nearly botched, since it is the
   session's recurring theme: the first extraction pasted a *sorted* name list
   against an *unsorted* value list and reported
   `LIB_POLYVAL_RESIDENT_BYTES = 0` with two blanks. The tell was that the
   number was absurd. Pair each `Name:` with the `Value:` that follows it, and
   look at the raw blocks before trusting any derived table.

   **And the watch's own monitor had the defect too, found 2026-09-07 by it
   firing.** The poller reported the entire fleet's tags, issues and PRs
   vanishing at once — six repos, one poll. That is not a fleet event, it is
   a failed query: it captured `gh` output with `2>/dev/null` and never
   checked the exit status, so a transient failure produced empty fields that
   compared as a real CHANGE. Confirmed within a minute by re-querying by
   hand (`core: 5000/5000`, every answer correct). Rewritten to check every
   query's status, to HOLD the previous snapshot on a failed poll — an
   unanswered poll is *unknown*, not *changed* — and to say "BLIND, not
   quiet" after four consecutive failures, with a recovery line when it
   clears. **Empty is a legitimate answer here** (a repo with no tags, a repo
   with no open issues); only the status distinguishes it from a failure,
   which is the whole of #86 restated. Written by the session that had filed
   #86, #91 and #94 about this shape.

   **Convergence worth recording, x25519 PR#141 (2026-09-07).** Their fix for
   #133 — our #86's twin — lands on the same two design choices our PR#92
   made independently: **reconcile a population instead of passing at zero**,
   and make the positive control *structural* (check the return code, name the
   object, require `Count >= 1`) rather than trusting an absence. Two repos,
   same defect, same remedy, no coordination. That is decent evidence the
   remedy is right rather than merely ours.
   
   They parametrise over **16 arms**; our #89 needs 6 (three profiles ×
   NO_AES). Their PR is prior art for that work — read it before writing ours.

   One practice difference, noted and NOT adopted unilaterally: their standard
   has the supervisor hold the gate and *not implement*, with a separate
   implementer agent writing the change and its red/green. Ours requires only
   that the reviewer be a different agent from the author, which this session
   has honoured — and the review caught real defects twice, so the weaker
   separation did work here. Whether to add the stronger one is JC-000's call,
   not a gap to close quietly.

   **§5 rounding-limit draft — answered for the record, 2026-09-07.** The
   contract session (`c64-lib-contract-11`) measured our `polyval.a` as
   declaring **6656** against **14943**, an apparent 8287 B UNDER-declaration,
   and asked us to check before it calibrated a clause. **Their arithmetic was
   right and their classification was wrong:** `LIB_POLYVAL_HTABLE` (256),
   `LIB_POLYVAL_LONG_HTABLE8` (4096) and `LIB_POLYVAL_LONG_REDUCE8` (4096)
   are `type = bss` in `src/lib_only.cfg:90-92` — runtime-computed tables, not
   shipped bytes. 14943 − 8448 = **6495**, under a declared 6656. Safe
   direction, 161 B of slack. Answers sent; the numbers are here so the next
   session does not re-derive them.

   | archive | measured | declared | slack | % |
   |---|---|---|---|---|
   | `polyval.a` / `-gcmsiv.a` | 6495 | 6656 | 161 | 2.5% |
   | `-gcmsiv-short.a` | 15949 | 16128 | 179 | 1.1% |
   | `-gcmsiv-compact.a` | 2660 | 2816 | 156 | 5.9% |
   | `-long.a` | 4160 | 4352 | 192 | 4.6% |
   | `-short.a` | 13614 | 13824 | 210 | 1.5% |
   | `-compact.a` | 325 | 512 | 187 | **57.5%** |

   *(Corrected. The version first sent upstream had SHORT at 16063 and
   COMPACT at 2774 — those were spans **including** the 114 B `lib_main.o`
   verify stub, which is not an archive member, while LONG was members-only:
   mixed bases in one table. The error understated slack, so it was safe in
   their direction, but they were calibrating a clause against it. Corrected
   to them the same session; all six rows are now members-only.)*

   **Alignment-gap under-declaration (x25519#142, chacha#126 — the latter
   now CLOSED COMPLETED) — measured here, zero in all six arms, and structurally so.** Both siblings found RESIDENT
   under-declared in the **unsafe** direction (59 B and 60 B) by inter-segment
   alignment fill their object-size sums could not see. Ours cannot, for two
   independent reasons: **no `ro` segment carries an `align` attribute** (the
   three `$100`-aligned segments are all `type = bss`, outside RESIDENT), and
   **the measurand is a placed span, so any fill would already be inside the
   number.** Measured: the three AEAD arms have five contiguous `ro` segments,
   internal fill 0; the three NO_AES arms have exactly **one** `ro` segment
   each, where inter-segment fill is impossible. That is PR#200's basis
   argument from the other side — a span charges fill automatically, an
   object-size sum cannot see it.

   Conformant against the draft's `max(1024 B, 10%)` in all six — but only
   because of the absolute floor. **A percentage-only limit would fail
   `-compact.a`**, not for any defect but because rounding UP to a 256-byte
   boundary is inherently up to 78% slack on a 325 B archive. If that draft
   ever loses its floor, say so before it merges.

   **Two things conceded to them, because they are true.** (1) A third party
   cannot derive our RESIDENT/COLD split from the artifact: COLD is a *subset*
   of the resident span measured by label delta, not a segment of its own.
   x25519's `LIB_X25519_INIT_CODE` is the better shape, and this is worth an
   issue here if the draft does not force it. (2) §5's "code+rodata" renders
   **9625 B** invisible — 1177 B of named BSS plus 8448 B of page-aligned
   tables — which a consumer must still place, and which on a stock C64 is the
   difference between fitting under $A000 and not. Told them the measurand is
   the clause worth having, not the slack.

   **PR#200 outcome, and we are already on its basis — verified.** The cap was
   dropped and the under-declaration claim against us withdrawn; what lands is
   the *basis*: placed span including fill, not object-size sums. Ours has
   always been the placed span (`ld65 -m`, $4000 to the first BSS-area segment
   start), so the change is a no-op here. Measured on the real map at
   `3d7fc7b`, 12 segment rows:

   ```
   LIB_POLYVAL_AES_CODE     004000 0043C5   3C6
   LIB_POLYVAL_GCMSIV_CODE  0043C6 004714   34F
   LIB_POLYVAL_LONG_CODE    004715 005754  1040
   LIB_POLYVAL_VERIFY_CODE  005755 0057C6    72   <- lib_main.o, NOT an archive member
   LIB_POLYVAL_AES_RODATA   0057C7 0059D0   20A
   LIB_POLYVAL_BSS          0059D1 ...            <- first BSS start
   ```

   Span = `$59D1 − $4000` = **6609**; minus the 114 B verify stub =
   **6495** for the archive members alone, which is the §6.4 per-archive
   measurand and the number given to the contract session. **Zero fill in the
   resident span** — the five ro segments are contiguous, and the only
   alignment gap in the whole link is 150 B between `GCMSIV_BSS` and the
   `$100`-aligned `HTABLE`, which is in BSS and outside RESIDENT. So
   span-basis and object-sum basis agree here; adopters whose ro segments are
   aligned will see the two diverge, which is the point of the clause.

   **The COMPACT-omission class, swept 2026-09-08.** COMPACT arrived in
   v0.8.0, and lists written before it have been wrong ever since — now
   **four findings of one shape**: `docs/precalc-tables.md`'s table rows
   (#103), its prose paragraph, its `lib-polyval-{long,short}` brace list,
   and `API.md:1305`'s identical brace list. The last is the one that
   matters, because `API.md` is staged into the release tarball while the
   precalc doc is maintainer-facing.

   **That sweep was itself truncated, and the correction is the more useful
   record.** I grepped every tracked `*.md`, `*.s`, `*.inc`, `*.cfg` and the
   `Makefile` for lines naming long and short without compact, piped it
   through `head -20`, and reported the result as a completed sweep — then
   told the implementer "two live instances, do not claim more than that".
   The real match count is **66 lines, 51 after excluding CHANGELOG**. The
   implementer found `CLAUDE.md:362` (a brace list past my cut) and
   `API.md:1300-1301` (an archive list omitting `-gcmsiv-short.a` since
   v0.7.0 and `-gcmsiv-compact.a` since v0.8.0 — consumer-facing, and the
   twin of the rows #103 corrected) despite that instruction, and was right
   to.

   **A truncated observation reported as a complete one, turned into an
   instruction that capped the fix** — the exact failure this cycle keeps
   finding, committed by the person auditing for it, inside a note about it.
   `head -N` on a sweep is the same shape as `tail -2` hiding a FAIL line and
   `grep -F` matching a prefix: the command ran, and it measured something
   narrower than the claim built on it. The remaining candidates were handed
   over unclassified rather than pre-filtered a second time.

   The lesson is about where guards go, not about COMPACT: each guard added
   to that paragraph displaced the drift rather than removing it — rows
   watched, so it moved to the prose; parentheticals watched, so it moved
   four lines down into a brace list. **Anchor on the Makefile's target set
   wherever a document names archives**, rather than parsing more prose.

   **Method note, 2026-09-08 — assert the BRANCH before committing watch work.**
   A watch-cycle commit went onto a detached HEAD and was orphaned: an agent's
   worktree had vanished, its git commands resolved against the main checkout,
   and it left that checkout detached at a feature branch's head. The cycle
   then committed there. `git push origin master` pushed the *unchanged*
   master ref and exited 0, while `git log --oneline -1` printed the new
   commit — so it read as a successful push. Found only because a later
   `git rev-parse` showed master one commit behind where it had been left, and
   recovered by cherry-picking the orphan (`87c8352` → `92c49ff`).

   Two lessons. **A push that succeeds is not evidence your commit was
   pushed** — `git push` reports on the ref it was given, not on HEAD. And
   `git log -1` after a push describes HEAD, which is exactly the wrong thing
   to look at. Verify with `git rev-list --left-right --count
   origin/master...master`, or check `git rev-parse --abbrev-ref HEAD` before
   committing. Same shape as every fixture failure this cycle: the check ran,
   and it was measuring something other than what it claimed.

   *(Method note: the first attempt to check for fill printed "no fill"
   from an `awk` that had parsed **zero** rows — the placed-segment lines
   break column assumptions when a segment name is long. Count the rows
   before believing an absence. Same shape as #86, fifth instance today.)*

   **The immunity is by COMPOSITION, not construction — and that turned into
   our #95.** The contract session's observation, which is right and is the
   most useful thing to come out of the exchange: our `ro` segments carry no
   `align` attribute only because the three `$100`-aligned tables happen to be
   `type = bss`. **That stops holding the moment an aligned table moves into a
   file-emitting segment**, a shape this fleet has already been bitten by, and
   nothing here would notice — because **nothing verifies the declared §5
   values against a measurement at all.** `test/consumer_stub_shipped.s:57-58`
   imports them and `:97` asserts `COLD < RESIDENT`, which proves ordering,
   not bounding; `tools/` and the `Makefile` do not mention them. The
   manifest's own comment shows the check being done by hand after the
   #69/#70 fixes grew `gcm_siv.o` by 42 B. Filed as **#95** with the six
   measured pairs as its expected-value table; worst slack is 210 B, which one
   routine of moderate size would consume.

   Also recorded from that exchange, since it settles a question rather than
   opening one: **the clause reads inter-segment gaps as *placement*, not
   footprint** — the gap depends on the order a consumer places segments in
   and vanishes if the aligned segment goes first, so making it footprint
   would make the figure a function of the consumer's cfg. A consumer
   reserving one contiguous region adds that padding itself from §4's declared
   alignments. **No action here; our declared values stay correct under that
   reading.**

   **PR#200 revisited — the "no-op" was wrong, and I tested my objection
   before making it.** The contract session corrected itself: the clause now
   says a figure is the **sum of its segments' placed spans**, while ours is a
   **contiguous extent**, so we are in the moving set on basis even though no
   number changes. I was going to argue their sentence *"reordering relocates
   such padding rather than removing it"* is conditional — an aligned segment
   placed first at an already-aligned start has no pad. **Built it first, and
   it failed:** moving `LIB_POLYVAL_HTABLE` (`align = $100`) ahead of the
   three unaligned BSS segments in our own cfg moved the pad from `005F00`
   (150 B) to `005A00` (**47 B**) — smaller, relocated, not removed, because
   the boundary it lands on is not itself aligned. That measurement is better
   evidence for their ruling than for my objection, so I dropped it and said
   so on the PR.

   What was posted instead is a **wording request: make the clause a floor,
   not an equality.** A contiguous extent is always ≥ the sum of spans, so it
   is always safe; but read as a definition of the measurand, a library
   measuring conservatively would have to *loosen a tighter number* to
   conform. That is the only thing in PR#200 that could force a change here.

   **Two items filed separately upstream, both JC-000's call, neither
   actionable by this watch.** (1) *Cold-split verifiability*, now
   **contract#201**, whose table names us correctly: our COLD is not
   third-party derivable, and that is not disputed. For us it is a segment
   restructure, not wording — COLD is an address delta inside a span, and the
   fix is an `LIB_POLYVAL_INIT_CODE`-shaped segment on x25519's model.
   **Scoping note: the COMPACT arm is the awkward one**, its cold code placed
   last in-segment on purpose and measured to segment end from the `-m` map,
   so a split there revisits a placement decision rather than renaming.
   (2) *The 9,625 B the equates render invisible.* **Record the §7 reading
   now, because this repo has re-derived ABI arguments badly before:**
   changing what `LIB_POLYVAL_RESIDENT_BYTES` / `_COLD_BYTES` *cover* is a
   semantic change to released symbols. A consumer asserting
   `RESIDENT + COLD <= budget` — which `c64-https` does on its own libraries at
   `src/contract_footprint_asserts.s:127,130` — breaks when the value silently
   grows by 9,625 B. That is a consumer conforming to the documented contract
   being broken, so it moves `LIB_POLYVAL_ABI_VERSION`. New symbols alongside
   the existing ones would not.

   **Same-day convergence, worth recording as evidence rather than
   coincidence.** By 2026-09-07 evening, four of five adopters had landed a
   fix for one defect class — a check whose pass condition is a zero or an
   absence: c64-polyval PR#88/#92 (#85, #86, #90, #91), c64-x25519 PR#141
   (#133, 16 arms), c64-nist-curves PR#160 (#158), c64-ChaCha20-Poly1305
   PR#128 (#119) plus their earlier #126. Nobody coordinated the remedy; the
   findings propagated as *questions* and each repo measured its own answer.

   **One to watch on their side, not ours: nist is stacking PRs** — #171 says
   "stacked on #161 (PR #169) — merge that first". c64-ChaCha20-Poly1305's own
   standard (their PR#195, adopted into their CLAUDE.md) records that a
   stacked pair once *stranded a released version off `main`*, which is why
   this repo has deliberately kept its four branches independent and rebased
   them in sequence rather than chaining them. If nist merges #171 without
   #169, or tags between the two, their next tag could carry half a fix — an
   S4 hazard worth checking at their next tag rather than assuming the merge
   order held.

   **nist#170 asked here and already answered — by our own review, before
   they filed it.** Their finding: twelve "links against that archive" rows
   pull **zero** archive members, because their stub only `.include`s the
   header and ca65 drops unreferenced imports, so every row would print
   identically against an empty archive. Ours does not have that shape:
   `test/consumer_stub_shipped.s` carries **21 unresolved imports** after
   assembly and fails to link against a one-member archive. That is not a
   lucky escape — it is the exact sabotage the #89/#94 reviewer ran when it
   broke the first version of our composing-mode link test, which linked
   loose objects and never put the archive on the command line at all. The
   fix made the archive load-bearing; #170 is the same defect, found
   independently in a sibling.

   **x25519#130/PR#147 asked here and answered N/A — structurally, not by
   luck.** Their defect: the public header used `.import` for names an
   APP_OWNED consumer defines, and `.import` of a name the including TU also
   exports is an **assemble-time** error, so such a consumer could not include
   the header at all. Measured here: `src/polyval_api.inc` has **28 `.global`
   and zero `.import`**, and `.global` serves all three §8.0 states. Verified
   end to end — a stub that `.export`s `aes_state` and then includes the
   *shipped* `polyval.inc` assembles clean (exit 0), with a negative control
   confirming the failure is real when it applies (`.import` of an owned name
   gives `Error: Cannot import exported symbol 'aes_state'`). No issue.

   **x25519#145 — *has the hand-maintained sweep list drifted?* — found the
   worst thing in this repo all day, and it was not a check.** Ours had
   drifted: `make clean` removes only `$(BUILD_DIR)` and `.gitignore` lists
   `build/` and `build-knobcheck/` but not `build-short/` — which is
   **tracked in git**, six build artifacts committed by `ec66030` as
   collateral. They are stale and **unattributed**: 5 members against a
   current 6, 155,005 B against 156,705 B, built in a configuration the
   artifact does not record.

   **~~Non-conformant against §6.1, carrying c64-aes256-ecdsa#28's collision
   surface~~ — RETRACTED, both halves, by adversarial review of the fix.**
   Re-measured from git: the tracked `lib_manifest.o` exports **0** bare
   `LIB_PRECALC_*` (3 prefixed) and the tracked `lib_version.o` **0** bare
   `LIB_(VERSION|ABI)` (4 prefixed) — that build used
   `-D LIB_NO_BARE_EXPORTS=1`. §6.1 governs **displaceable** names and this
   member has none co-resident, so it is not a member-isolation violation;
   and #28's collision class is the bare triple the artifact does not carry.
   *Stale and unattributed* was always the sufficient claim. Recorded because
   the escalation would have been quoted back as fact — the same failure as
   the v0.10.0 ABI argument this file already documents. Not in the tarball (0 entries), so the
   exposure is git consumers: a clone, a `git archive`, or a submodule pin,
   which is how c64-https and c64-wireguard consume libraries. Filed as
   **#99**.

   Worth noting what found it: not a code review, and not a check. A sibling
   repo asked whether a *hand-maintained list* was complete, and ours had two
   — `clean` and `.gitignore` — neither of which anything verifies.

   **x25519#143 asked here and answered N/A — recorded so it is not filed by
   mistake later.** Their finding is that `tests/lib_linkage` cannot link
   under `-D ZP_CONFIG_NO_EXPORTS=1`, the ZP mode their consumer actually
   ships in. Reproduced verbatim here: build the archive with that define and
   the shipped stub fails with `Unresolved external 'polyval_acc'`. **That is
   correct behaviour, not a defect, because the flag is not a consumer mode
   here.** `src/zp_config.s:79-84` states its purpose: a TU that transitively
   `.include`s `zp_config.s` via `constants_lib.inc` must not re-emit the
   `.exportzp` directives, since ld65 errors on a symbol exported from two
   objects — so `constants_lib.inc` sets it, and only `zp_config.s` compiled
   as its own object emits them. Passing it globally suppresses the exports in
   `zp_config.o` itself, which is not what the flag is for;
   `check_knob_staleness.sh` does exactly that deliberately, as a lever to
   make the artifact flip observably. No consumer ships in that mode, and
   `c64-aes256-ecdsa` is not an archive consumer at all. **G3: applicability
   before conformance — no issue.** Their #144 (a check hard-coding
   bare-mode counts) is also N/A: our counts are hard-coded, but the script
   sets each knob itself and asserts the value appropriate to that mode.

   **A second pattern, and the one that says the standard is doing work:
   adversarial review broke the headline claim of the first cut in every
   substantial PR of the day, in three different repos.** Ours: PR#88's guard
   slept through a deleted file and swallowed git's exit status; PR#92's fix
   left three live instances of its own defect in the same file; PR#98's
   umbrella never built what ships. nist PR#162 says the same of itself —
   *"the second commit exists because adversarial review proved the first
   one's headline claim false."* The reviews are not finding style; they are
   finding the thing the author was most confident about.

   **Score for this audit so far: ten issues, six of them found by asking
   another repo's question here rather than by reading our own code.** #85,
   #87 (adversarial review of #85's fix), #91 (review of #86/#90's fix) came
   from review; #86 from contract#194, #89 from contract#198, #90 from
   nist-curves#158, #93 from x25519#140, #94 from chacha#122, #96 from chacha#128; #95 came
   from the contract session's own observation on our answer. The fleet's
   findings port across repos far better than any of them ports a fix.

   Adopted from PR #195 into `CLAUDE.md` at the same time, as local practice:
   the **churn test** (compliance work must deliver easier consumer
   integration, a new capability, or a measurable improvement — work whose
   only product is closing its own loop does not get commissioned) and the
   **citation duty** (grep every quote and `file:line` a review agent hands
   you; fabricated verbatim quotes have been produced in this fleet attached
   to otherwise-sound substance).

---

## 5a. Consumer handoff — measured state at close

S5 was ruled out of scope, not completed. These are the facts as measured
**from the remotes** (§6h) on 2026-09-06, so whoever picks consumer
alignment up starts from them rather than re-deriving them.

| Consumer | Tag | Pin, from `origin/master` gitlinks | Needs |
|---|---|---|---|
| c64-https | `v0.4.3` | `libs/nistcurves` **v0.11.2**, `libs/x25519` **v0.13.0** | v0.14.0, v0.16.0 |
| c64-wireguard | `v2.0.0-ca65` | `libs/chacha20poly1305` **v0.9.0**, `libs/x25519` **v0.11.2** | v0.11.0, v0.16.0 |
| c64-aes256-ecdsa | **never tagged** | **none — not an archive consumer** | n/a |

**Four stale pins across two repos**, not five across three. The
c64-aes256-ecdsa row is the one to get right, because it was reported wrong
twice — once by this watch and once by the contract session, both times
from `git submodule status` on a dirty local clone. On `origin/master` that
repo has no `.gitmodules`, no `libs/` tree, and builds its own
`src/polyval.s` as a `MODULES` entry. Its `libs/polyval` exists only as
uncommitted local work in this workspace.

Two known items, neither live:

- **c64-aes256-ecdsa#28** — its `src/precalc_manifest.s` emits **bare-only**
  `LIB_PRECALC_*` triples (no library-prefix argument) for five tables,
  three overlapping ours: `aes_sbox`, `aes_inv_sbox`, `polyval_htable`.
  **Latent** — it arms only if that repo ever links a c64-polyval archive,
  which on `master` it does not. Do not record it as a live exposure.
- **c64-wireguard** carries a `v2.0.0-ca65` MAJOR whose scope is
  unestablished; the pin bumps may already be inside it.

Scale, for whoever scopes it: 38 open issues across the consumer repos at
close, against a handful across the adopters. **Re-measured 2026-09-07
~13:30: 45** (c64-https 25, c64-wireguard 20). Still out of scope by the
ruling — recorded so the handoff figure is not stale, not as an argument to
reopen S5.

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

**"Unprefixed" is not "displaceable."** A crude grep for names lacking the
library prefix over-reports: `poly1305_lib.s` at chacha v0.11.0 still
exports `poly1305_init`, `poly1305_clamp` and `shoup_init`, and they are
fine. Displaceable means a consumer can *suppress* it
(`LIB_NO_BARE_EXPORTS`) or *define* it itself (`APP_OWNED`) — an ordinary
unprefixed entry point is neither. Check what the name IS, not how it is
spelled, before filing against another repo.

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

## 6f. §5 footprint basis — measure a link span, never a sum of object sizes

Raised by the contract session from c64-ChaCha20-Poly1305 #113, where all
five `RESIDENT_BYTES` literals under-reported a real link by 39–295 B, in
the direction §5 explicitly calls dangerous. c64-nist-curves hit the same
class independently: six of twelve archives understating, one by 72 B.

**The defective basis is `Σ od65 --dump-segments` per member** — the sum of
what each object contributes. That omits the padding `ld65` inserts
*between* sections when placing them, so wherever a segment carries
`align = $100` the shortfall is systematic: `od65 basis + fill = real link`.

**c64-polyval is clean, and was checked rather than assumed.** Measured at
v0.11.0 by linking every member of each archive with `lib_only.cfg`, taking
real segment extents from the `-m` map, and comparing against the declared
equate:

| Configuration | declared | real span | headroom |
|---|---:|---:|---:|
| LONG AEAD | 6656 | 6495 | +161 |
| SHORT AEAD | 16128 | 15949 | +179 |
| COMPACT AEAD | 2816 | 2660 | +156 |
| LONG NO_AES | 4352 | 4160 | +192 |
| SHORT NO_AES | 13824 | 13614 | +210 |
| COMPACT NO_AES | 512 | 325 | +187 |

Safe-direction in every configuration, headroom 156–210 B from the
round-up-to-256 policy.

**Two independent reasons it cannot bite here**, which is why it does not
generalise from chacha to us:

1. **Our declared basis is already a real link span**, not an object-size
   sum — `ld65 -C src/lib_only.cfg -Ln -m`, `$4000` to the first BSS-area
   segment start. A span includes inter-section fill by construction.
2. **No aligned segment is inside the measured span.** The only three
   `align = $100` segments — `LIB_POLYVAL_HTABLE`,
   `LIB_POLYVAL_LONG_HTABLE8`, `LIB_POLYVAL_LONG_REDUCE8` — are all
   `type = bss`, and §5 scopes the footprint to *code+rodata*, so they are
   excluded. There is no alignment fill in the quantity being declared.

Reason 2 means even the defective basis would have produced the right
answer here — which is exactly why reason 1 has to be the one recorded.
A correct number from a basis that happens not to be exercised is the same
artifact as a green check that never examined the property (§6a, §6e).

**Keep the span basis** even though the tables are BSS today. If a future
variant ever places an aligned table in a file-emitting segment, an
object-size sum silently starts under-reporting and nothing fails.

## 6g. Two ways this watch's own tooling reported a confident wrong answer

Both found on 2026-09-06, both in the same family as §6a/§6e/§6f, and both
worth keeping because the *watch* is an artifact too and nothing was
auditing it.

**1. "Latest release" is not "latest tag."** §7's refresh used
`gh release view --json tagName`, which returns the most recent **GitHub
Release**. `c64-x25519` had tagged `v0.14.0` and `v0.15.0` without cutting
Releases, so this watch reported them at `v0.13.0` for **three cycles** and
carried "fix landed, UNTAGGED" in the fleet table — while the fix had in
fact been tagged since `v0.14.0`. Measured after the correction:

```
c64-x25519   release=v0.13.0   tag=v0.15.0     <-- MISMATCH
(four other repos: release == tag)
```

That last line is why it survived: **the extraction was right for four of
five repos**, so every spot-check agreed with it. A wrong method that
coincides with the right answer most of the time is harder to catch than
one that is always wrong, and it produced a stale fact that was then
relayed to another session as a nudge.

Verify a tag's *contents* at the tag, too, not just its name:
`git show v0.15.0:src/lib_manifest.s | grep -c LIB_PRECALC_TABLE` returns
0 at `v0.15.0` and 3 at `v0.13.0` — which is what actually establishes that
the fix shipped.

**2. An absence assertion satisfied by empty input** — contributed by the
contract session against itself. Checking whether c64-ChaCha20-Poly1305 had
fixed its manifest, they ran `git show origin/master:…` in a repo whose
default branch is `main`. The ref does not exist, `git show` produced empty
output, `grep -c` on empty input returned **0**, and 0 is exactly what
"clean" looks like. They were one step from reporting "chacha is clean" as
a finding.

**The general shape: a check whose pass condition is a count of zero passes
when its input is empty.** Nothing distinguishes "looked and found none"
from "looked at nothing." Any absence assertion needs a positive control —
assert the input was non-empty, or assert the same query returns non-zero
somewhere it should:

```sh
# wrong: passes on a bad ref, a renamed file, an empty archive
[ "$(git show "$REF:$F" | grep -c PATTERN)" = 0 ] && echo clean

# right: prove the input existed before believing the zero
git show "$REF:$F" >/dev/null 2>&1 || { echo "bad ref/path: $REF:$F"; exit 1; }
```

Both are the same disease this file keeps cataloguing: **an artifact
reporting green about a property it never actually examined.** §6a (a sweep
blind to macro-emitted names), §6e (a diff whose extractor drops a symbol
from both sides), §6f (a footprint basis that happens not to be exercised),
and now the watch's own fleet table.

## 6h. Read another repo from its REMOTE, never from a local checkout

The fleet table recorded c64-aes256-ecdsa as pinning `libs/polyval` at
`v0.7.1`, and issue **ecdsa#28** was filed partly on that basis. Both were
wrong. That repository's `origin/master` has **no `.gitmodules`, no `libs/`
tree**, and builds its own `src/polyval.s` as a `MODULES` entry — it links
no c64-polyval archive at all.

The local clone at `~/Documents/c64-aes256-ecdsa` carried **uncommitted
changes**: a staged `.gitmodules`, a modified `README.md` and `Makefile`,
and a populated `libs/polyval` directory. `git submodule status` and a
working-tree `grep` reported all of it as fact.

**`HEAD` matching `origin/master` is not enough** — it was equal here
(`823772e`), and the working tree was still dirty. The commit being right
says nothing about the files being read.

**This applies to a repo's own TAG LIST too, not just its gitlinks.** A
cycle after §6h was written, an ad-hoc check read c64-wireguard's latest
tag with local `git tag` and got `verify93-rescue-amended-master` — a
local-only tag in this workspace's clone. The remote has four tags, latest
`v2.0.0-ca65`. Same root cause, different artifact: local clones in this
workspace accumulate tags, branches and uncommitted work from other
sessions.

Two compounding traps in one line: also filter to semver shapes before
sorting. `sort -V | tail -1` over a mixed tag list returns whichever name
sorts last, which is not the newest release:

```sh
gh api "repos/JC-000/$r/tags?per_page=100" --jq '.[].name' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1
```

Read other repositories this way:

```sh
git -C "$d" fetch -q origin
git -C "$d" ls-tree -r origin/master | awk '$2=="commit"{print $4, $3}'   # real gitlinks
git -C "$d" show origin/master:path/to/file                              # real file content
```

Three traps met doing this, all §6g-shaped:

1. **`ls-tree` without `-r`** shows only top-level entries, so nested
   gitlinks under `libs/` vanish and the listing looks empty.
2. **A repo whose default branch is not `master`** — `git show
   origin/master:f` on a `main` repo yields empty output and a `grep -c`
   of 0. Resolve it: `git ls-remote --symref origin HEAD`.
3. **An empty gitlink list can be true.** For ecdsa it *was* true, and
   only checking `.gitmodules` and the `MODULES` list distinguished "no
   submodules" from "I looked wrong".

The correction cost a wrong claim in someone else's tracker. Filing against
another repo means reading that repo as published, not as checked out here
— a clone in this workspace may be mid-work by another session.

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
  # TAGS, not releases -- see §6g. `gh release view` answers a different
  # question and looks right whenever the two coincide.
  echo "issues=$(gh issue list --repo JC-000/$r --state open --limit 100 | wc -l | tr -d ' ')" \
       "tag=$(gh api "repos/JC-000/$r/tags?per_page=100" --jq '.[].name' 2>/dev/null | sort -V | tail -1)"
done
```
