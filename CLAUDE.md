# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# c64-polyval

## Project overview
POLYVAL (RFC 8452 GF(2^128) universal hash) plus AES-256-GCM-SIV authenticated
encryption, optimized for the Commodore 64 (6502 @ 1 MHz). Long-term goal:
fold into `c64-aes256-ecdsa` and serve as a primitive for `c64-wireguard` and
`c64-https`.

Companion docs (read alongside this file):
- `README.md` — user-facing overview + build flow.
- `API.md` — library API reference; §3 (profile selection), §4 (ZP layout),
  §7–§8 (consumer integration), §9 (c64-lib-contract surface) are load-bearing.
- `CHANGELOG.md` — release history.
- `docs/RELEASE_NOTES_v0.10.1.md` — current release attestation (size + SHA256).
- `docs/precalc-tables.md` — c64-lib-contract §8.4 precalc-table enumeration.

## Working standard — adversarial review + red/green (MANDATORY)

**Applies to every feature, issue, bugfix and release in this repo.** Not a
release-only gate: it governs the work while it is being done. The two halves
exist because this fleet has repeatedly shipped a *claim* that nobody had
tried to falsify.

### 1. Red/green — the test fails first, for the right reason

For any change with observable behaviour (a defect fix, a new entry point, a
bound, a build guard, a conformance property):

1. **Write the check first and run it against the UNFIXED tree.** Record the
   failure text in the PR/commit body. A check that has never been observed
   to fail has not been shown to check anything.
2. **Read the failure.** It must fail for the reason under test, not because
   the fixture is broken, a path is wrong, or the tool exited non-zero for an
   unrelated cause. This is the step that catches a gate whose *fixture
   encodes the defect it should catch* — the check passes by construction.
3. **Then fix, and observe green.** Both directions get recorded; "it passes
   now" alone is not evidence.
4. **Never weaken a red test to make it green.** `tools/test_gcmsiv_bounds.py`
   is the precedent: 8 of its 15 checks were written RED against issues
   #69/#70 and stayed red until the code was fixed.

**Verify the fixture before you believe the result — red OR green.** A
sabotage test has two subjects: the code under test and the harness. If the
harness never reached the code, the run tells you nothing, and it fails in
*both* directions — a green that means "the mutation was not applied" and a
red that means "the harness broke". Three instances in one session, all
self-inflicted: a reset that ran `git checkout -- .` between cases and
reverted the script under test (all-green, nothing tested); a sabotaged copy
run from a scratch directory, where `ROOT=$(cd "$(dirname "$0")/.." ...)`
resolved outside the repo (all-red, still nothing tested); and an
extracted-function harness that an adversarial reviewer declined to trust and
re-derived against the real script instead. So: assert the mutation is
present before each case, prefer sabotaging the real script over a copy, and
when a copy is unavoidable, keep it where its own path assumptions still
hold. **An A/B beats an assertion** — show the check failing WITH your change
and passing WITHOUT it, which proves your change is what does the work.

**Positive control for anything that is not a plain unit test.** When the
check is a build probe, an export-set comparison, a link probe or a grep over
artifacts, prove the probe can see: make the expected condition false on
purpose (an old tag, a stub, a renamed symbol) and confirm the check goes
red. `docs/contract-watch.md` §6e/§6g are the two cases where this repo's own
tooling returned a confident wrong answer without one; the v1.2.0 member-
isolation verdict in the §3 ledger is what a red/green link probe looks like
when it is done right.

**Shell checks: `||` in a `;`-chain does not propagate.**
`X || (echo "FAIL"; exit 1)` inside a longer chain prints FAIL and exits 0 —
the leg is structurally incapable of failing. Write
`if ! X; then echo "FAIL: ..."; exit 1; fi`, and then drive it red once to
prove it. Four sibling repos shipped this bug; contract#193 is the writeup.

### 2. Adversarial review — commissioned, and waited for

Every PR, and every release, gets an **adversarial review agent** before it
merges or tags.

- **Brief it to falsify a specific claim**, not to "look for bugs". Hand it
  the claim in the commit/PR/release notes — "the sweep found every site",
  "the footprints are safe-direction", "byte-identical to the baseline tag",
  "the counter holds at 1" — and ask it to break that. Include the evidence
  the claim rests on so it can attack the evidence, not just the conclusion.
- **Review the evidence, not only the code.** The recurring defect in this
  fleet is a green report about a property that was never examined: the
  v0.10.0 self-certification, the §6.1 sweep that fixed the sites it
  remembered, contract#193's three legs that could not fail. Ask of every
  check: *if the thing it tests were broken right now, would this have gone
  red?*
- **A silent reviewer is a HOLD, not a pass** (contract-watch G7). v0.10.0
  was tagged when reviewers went quiet; their late reports found four real
  defects, two introduced by that release, and forced v0.10.1.
- **Record the outcome** in the PR: what was attacked, what was found, what
  was dismissed and why. A review that found nothing still says what it
  looked at.

- **Check the agent's citations.** Grep every quote and every `file:line` a
  review agent hands you before acting on it. Fabricated verbatim quotes have
  been produced in this fleet attached to otherwise-sound substance, and an
  unchecked one becomes a false claim in a commit message.
- **The churn test — what gets commissioned at all.** Work that drives this
  repo through compliance effort must deliver one of: easier integration for
  a consumer, a new capability, or a measurable improvement. Work whose only
  product is closing its own loop does not get commissioned. A clause never
  has to demonstrate it caused anything, so the reviewer is the one who has
  to ask. (Adopted from c64-lib-contract PR #195, which is that repo's own
  local standard and explicitly **not** contract text — no obligation lands
  on adopters from it.)

**The reviewer is checked in.** `.claude/agents/adversarial-reviewer.md` is
the definition this section names — the brief, the failure shapes to hunt,
the citation duty, and the rules of engagement (scratch/worktree only,
restore tracked files from a copy, never a broad process kill). It is the one
file under `.claude/` that ships; everything else there stays local. Use it
rather than re-improvising a brief, and extend it when a review finds a shape
it did not list. Prior art: c64-nist-curves PR#160, which checked in the same
pair the same day.

`/code-review` is the usual vehicle; a task-specific brief to a subagent is
fine when the claim is not diff-shaped (a footprint table, a fleet row, a
reproducibility receipt). Either way the reviewer is a **different** agent
from the one that wrote the change.

## c64-lib-contract adoption (current as of v0.10.0)
This library implements the [c64-lib-contract](https://github.com/JC-000/c64-lib-contract),
**SPEC v1.1.0** (tagged 2026-09-03). Re-check the tag before trusting this
line — that repo has historically shipped several releases a day.

**Contract v1.0.0 cut the spec by roughly seven eighths** (40,737 words →
5,154). No symbol, equate, bit value, segment name or build target changed,
so conformance carried over without edits. What went was rationale, incident
history and process regulation, under a two-prong scope rule now stated in
the document itself: a clause belongs there only if it governs (1) a name,
value or placement two independently-built artifacts must agree on, where
(2) a violation is invisible from inside any single repository's own build.
**Retired: §9, §12, §13, §14, §15 and sub-clauses §6.3, §6.6, §6.7.**
Surviving sections kept their numbers, so old citations still resolve; the
retired text lives permanently at `git show v0.17.1:SPEC.md`. v1.1.0 then
added one normative paragraph to §7 (below).

**Do not go through this repo rewriting retired-section citations.** The
contract's own `RETIRED.md` asks adopters not to: a citation is a claim
about the tag it was made against, and it still resolves. `CHANGELOG.md`,
`docs/RELEASE_NOTES_v0.*.md` and the in-line `§6.6` comments in
`src/lib_manifest.s` are left exactly as written on purpose. What v0.10.0
*did* change is only text that had become **false going forward** — chiefly
"removed at contract v1.0" for the bare exports, which v1.0.0 explicitly
deferred to a future MAJOR.

Where the three retired clauses this library had implemented now stand:

| Retired | Status here |
|---|---|
| **§6.3** reachability / looks-reachable | Obligation gone. The `PIN_` parse-time goal table and the `build/.ca65flags` stamp are **kept as local engineering** — they are good properties for this Makefile regardless. `tools/check_knob_staleness.sh` still runs on `lib-verify`. Do not remove them, and do not grow them further to satisfy a clause that no longer exists. |
| **§6.6** consumer footprint asserts | Library-side half moved into **§5**, which now states safe-direction round-up and the RESIDENT/COLD pair directly. Nothing about `src/lib_manifest.s` changes. The consumer-side snippet was only ever RECOMMENDED. |
| **§6.7** non-segment reservations | N/A before and after — every buffer is segment-resident. |

Section-by-section status (see `API.md` §9 for the full account):
- §1 `LIB_POLYVAL_VERSION_*` + `LIB_POLYVAL_ABI_VERSION`, `: abs`, TU
  isolation, bare `LIB_VERSION_*` aliases gated on `LIB_NO_BARE_EXPORTS`
  — `src/lib_version.s`. The bare forms' removal was scheduled for contract
  v1.0 and **deferred there to a future MAJOR**; the §1 zero-consumer
  carve-out does not apply (this library has a tag-pinning consumer,
  `c64-aes256-ecdsa`).
- §2 `.exportzp` slot inventory — `src/zp_config.s`; `polyval_` and `pv_`
  are registered to this library in the §2 ZP prefix registry.
- §3 REU — **N/A**, no REU claims. Zero-REU / turbo-clean scaling is an
  explicit contract feature (issue #19): no I/O on any path, all three
  profiles scale with CPU clock, and any future REU-resident variant must
  be an optional profile, never the default — API.md §9.3, README
  "Turbo / accelerated hosts".
- §4 `LIB_POLYVAL_*` segment naming plus the load-bearing cfg attribute
  declarations — every `src/*.s`; `src/c64.cfg` and `src/lib_only.cfg`
  alias every prefixed segment back to MAIN. The declarations are
  `type = ro` on `LIB_POLYVAL_AES_RODATA` (correctness — 522 initialised
  bytes silently dropped under `type = bss`) and `align = $100` on the
  three table segments (performance only, honestly labelled — the library
  is not constant-time, API.md §6). API.md §9.8.
- §5 aggregate manifest equates + the published input bound — `src/lib_manifest.s`.
  Footprints are safe-direction, measured per archive, rounded UP to the
  next 256-byte boundary, gated on `POLYVAL_PROFILE` × `LIB_POLYVAL_NO_AES`
  (API.md §9.4). **`LIB_POLYVAL_GCMSIV_MAX_PT_LEN = 64` is new in v0.10.0**:
  §5 says a real input ceiling SHOULD be published here as a symbol the
  consumer can reference, and until v0.10.0 the bound existed only as
  `gcmsiv_max_pt_len` in `src/constants_lib.inc` — invisible to a consumer
  who links the archive instead of vendoring our source. It is deliberately
  **not** `.ifndef`-guarded (it is derived from the value `gcm_siv.s`
  actually compares against, so a `-D` override must collide loudly rather
  than export a ceiling the code does not enforce) and is absent from the
  `LIB_POLYVAL_NO_AES` archives, which ship no `gcm_siv.o`.
- §6.1 `make lib` + the six `lib-polyval-*` archive targets. Every one of
  them also stages `build/lib/polyval.inc` and
  `build/lib/polyval-example.cfg` — **a local choice, NOT a contract
  requirement.** v0.10.0 added it against SPEC v1.1.0 §6.1's "plus the
  consumer-facing `.inc` header and an example `.cfg`"; **v1.1.1 withdrew
  that clause** (contract#178) as an unannounced artifact of the 1.0.0 cut.
  We keep the artifacts because a consumer linking the archive genuinely
  needs them and `consumer-check-shipped` guards them — but do not write
  "§6.1 requires" anywhere again. Both are §6.5 name surface from v0.10.0.
  The cfg is `src/polyval-example.cfg`, maintained **only** for shipping —
  do not point this at `src/lib_only.cfg`, which carries `lib-verify`
  scaffolding (a mandatory `LOADADDR` segment, `LIB_POLYVAL_VERIFY_CODE`)
  and makes a consumer's first link emit
  `ld65: Warning: Segment 'LOADADDR' does not exist`. That was tried and
  reverted. `make consumer-check-shipped` is the guard: it assembles a stub
  against the three shipped files in an empty directory **with no
  `-I src`**, which is the only way this repo can detect an incomplete
  shipped surface — every other build has `src/` on the include path.
- §6.2 `CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES`, both `?=` empty, appended
  to `CA65FLAGS`. Polyval-specific reading: the library has zero
  `.importzp` sites for its own slots (every TU bakes the equates via
  `constants_lib.inc` → `zp_config.s` `.ifndef` guards), so EVERY member TU
  is a ZP-defining TU and all-recipes delivery IS the SPEC's scoped
  delivery — a `zp_config.o`-only delivery would silently mismatch exported
  against baked addresses. Values must be `$`-free (`0x` hex). API.md §9.5.
- §6.4 per-archive manifests — conformant; recursive clean builds under
  pinned `POLYVAL_PROFILE` / `POLYVAL_NO_AES`, rows gated on the same
  switches.
- §6.5 name surface — archive basenames already canonical. Two recorded
  future-MAJOR items, neither actionable now: `lib-verify` is grandfathered
  in the reserved `lib-*` namespace, and archive **member** basenames take
  a `polyval_` prefix at the next MAJOR. Members cannot dual-name, so there
  is no transitional path. (Contract v0.11.0's §6.5 zero-consumer
  "born prefixed" carve-out, which earlier revisions of this file discussed
  at length, **no longer exists in v1.1.0 §6.5** — the cut removed it. It
  was inapplicable to us anyway since `c64-aes256-ecdsa` pins a tag, so the
  discussion is now moot rather than wrong.)
- §7 semver + ABI counter. **v1.1.0 added the load-bearing paragraph**: the
  counter moves on what the code does, not on whether the export list
  changed — it moves when a consumer conforming to the *previously
  documented* contract can be broken, typically an entry point's return set
  gaining a value; it **holds** when previously undocumented behaviour
  becomes documented, and when docs are corrected over unchanged code.
  `LIB_POLYVAL_ABI_VERSION` stays **1** through v0.10.0; see the
  "ABI counter" note below.
- §8.1–§8.3 shared primitives — **N/A**. GF(2^128) carry-less multiplication
  has no shared shape with the 8×8 quarter-square-multiply primitive
  (`sqtab` / `reu_mul` / `ct_mul_8x8`) that `c64-nist-curves`, `c64-x25519`
  and `c64-ChaCha20-Poly1305` converged on. This library neither provides
  nor defers any of them and has no deferral switch, so §8.0's bit-allocation
  and mask
  obligations and v0.10.6's provider-surface rule are both N/A.
- §8.4 precalc-table enumeration (applies regardless of §8.1–§8.3) —
  `src/precalc_table.inc` (canonical macro, copied verbatim; refreshed
  from the v1.1.0 canonical in v0.10.0, comment-only) + `LIB_PRECALC_TABLE`
  invocations in `src/precalc_manifest.s` — an ISOLATED TU per v1.2.0 §6.1
  member isolation, never back in `lib_manifest.s`; rationale in
  `docs/precalc-tables.md`.
  The §8.4 zero-consumer carve-out does not apply (tag-pinning consumer),
  so the bare `LIB_PRECALC_<name>_*` triple keeps shipping gated on
  `LIB_NO_BARE_EXPORTS`.

**ABI counter — holds at 1. Argue it from the DOMAIN, not from the reject
path's post-conditions.** v0.9.0 gave `gcmsiv_encrypt` and `gcmsiv_decrypt`
a length-rejection return (`A=1` / `Z=0` above `gcmsiv_max_pt_len`), which
is superficially the shape v1.1.0 §7 says moves the counter.

The load-bearing reason it does not: **v0.8.0's Entry banner on both entry
points already read `gcmsiv_pt_len = plaintext length (0..64)`**, so
`pt_len > 64` was outside the documented input domain before the change.
§7 asks whether a consumer conforming to the *previously documented*
contract can be broken; no conforming consumer reaches the reject path on
either routine, so the test cannot fire. This covers both entry points and
every post-condition at once.

**Do not reach for either of the two weaker arguments — v0.10.0 shipped
one of them and it was wrong.** Recorded so it is not re-derived:
- "`gcmsiv_encrypt` documented `A, X, Y undefined`, so nobody could read
  `A`" — true, but addresses only `A`. v0.8.0 also documented
  *unconditional* memory outputs (`gcmsiv_ct_buf = ciphertext`,
  `gcmsiv_tag = 16-byte tag`) that the reject path does not produce.
- "`gcmsiv_decrypt`'s reject path is indistinguishable from a tag failure
  on **every** documented post-condition" — **false**, and v0.10.0's
  release notes, API.md and this file all said it. It matches `A`/`Z`,
  `gcmsiv_tag_valid`, the 64-byte `dec_buf` wipe, `gcmsiv_tag` and
  `aes_expanded_key`. It does **not** match v0.8.0's `memory (always)`
  line, which documents `polyval_*`, `aes_state` and
  `gcmsiv_counter`/`keystream`/`idx` as clobbered — the reject path
  returns before `gcmsiv_derive_keys` and clobbers none of them. Corrected
  in v0.10.1.

Those three are a real consumer-visible difference that simply does not
move the counter: a caller reading "clobbered" as *scrubbed* finds the
previous call's derived-key material still in `polyval_htable*` and
`gcmsiv_keystream` after a length rejection. Also note `src/gcm_siv.s`'s
`gcmsiv_decrypt` banner still carries that `memory (always)` line eight
lines below a reject block stating no key derivation is performed — the
banner contradicts itself, tracked as issue #82.

**What WOULD move the counter, stated because the rejected arguments above
are not a test.** Not the reject path becoming distinguishable from a tag
failure — that was the wrong property, and testing it is the trap v0.10.0
fell into. The counter moves on **a change that breaks a caller who was
conforming to the documented input domain**. Concretely: widening or
narrowing the documented `gcmsiv_pt_len` range, changing what a value
inside `0..64` does, or adding a return a caller inside that domain can
observe. A guard that only fires outside the documented domain cannot move
it, however its post-conditions read.

Arbitration requested upstream (c64-lib-contract#180, now closed) so the
reading is on the record. The contract session corrected its own published
ruling there after we corrected ours, and made the sharper point this
paragraph records: "a future reader applying my original reasoning to a
third case would test the wrong property."

ZP slots are lowercase with `polyval_` / `pv_` library prefix
(`polyval_acc`, `pv_mul_input`, `polyval_zp_ptr`, `polyval_aes_round`, ...).
Pre-v0.3.0 shared `zp_*` names were renamed; consumers vendoring the
library MUST update their `.importzp` lists.

**When bumping `VERSION`, also check `src/lib_version.s`.** The v0.3.0 →
v0.4.0 release fixed a bug where `LIB_VERSION_MINOR`/`_PATCH` had drifted
from the `VERSION` file and stayed stale for an entire release cycle — the
release commit doesn't update `src/lib_version.s` automatically.

## Build
```
make                                  # build/polyval.prg (LONG profile, default)
make POLYVAL_PROFILE=short            # SHORT profile
make lib                              # build/lib/polyval.a (full ar65 archive — SPEC §6; LONG)
make lib-polyval-long                 # build/lib/polyval-long.a (LONG only, no AES/GCM-SIV)
make lib-polyval-short                # build/lib/polyval-short.a (SHORT only)
make lib-polyval-gcmsiv               # build/lib/polyval-gcmsiv.a (full AEAD bundle, LONG)
make lib-polyval-gcmsiv-short         # build/lib/polyval-gcmsiv-short.a (full AEAD, SHORT)
make lib-polyval-compact              # build/lib/polyval-compact.a (COMPACT only)
make lib-polyval-gcmsiv-compact       # build/lib/polyval-gcmsiv-compact.a (full AEAD, COMPACT)
make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'   # §6.2 ZP slot override ($-free values only)
make lib CONTRACT_DEFINES='-D LIB_NO_BARE_EXPORTS=1' # §6.2 global defines (composing consumers)
make lib-verify                       # library-only verification PRG at $4000 (pre-v0.3.0 `make lib`)
make consumer-check                   # link test/consumer_stub.s against the library
make consumer-check-shipped           # §6.1 guard: assemble+link using ONLY the three
                                      #   shipped files (polyval.a / polyval.inc /
                                      #   polyval-example.cfg) in an empty dir with no
                                      #   -I src — issue #79 regression guard
make consumer-check-noaes             # link test/consumer_stub_noaes.s (owns its own
                                      #   aes_state/gcmsiv_tag) against polyval-long.a,
                                      #   polyval-short.a AND polyval-compact.a —
                                      #   issue #47 regression guard
make dist VERSION=v0.8.0              # reproducible source-tarball release
```
Assembler: ca65/ld65/ar65 (cc65 toolchain). Single canonical toolchain as of
v0.2.0 — ACME support was retired. `src/` is flat (no `lib/` subdir); ld65
configs live at `src/c64.cfg` (full app) and `src/lib_only.cfg` (library-only).

**Profile is a member-set axis (SPEC v0.10.4 §6.3, issue #40).** `POLYVAL_PROFILE`
selects which multiply object is *archived*, so no `CONTRACT_DEFINES` `-D` can
reach it — every documented profile × variant pair needs its own §6.1 target.
`lib` / `lib-polyval-gcmsiv` name the LONG AEAD archive and do not clean first,
so they **reject** `POLYVAL_PROFILE=short` / `=compact` at parse time rather than
reusing objects assembled under another profile; use
`lib-polyval-gcmsiv-{short,compact}`, which clean and pin like
`lib-polyval-{long,short,compact}`. Adding a profile is therefore a §6.1 change:
two targets, two `PIN_` rows, two `(profile × NO_AES)` manifest branches, two
footprint rows — the v0.7.0 shape, done again for COMPACT in v0.8.0 (issue #51).

**Adding a contract MEMBER is the other member-set axis, and it has one more
place: `LIB_CONTRACT_MEMBERS`** in the `Makefile`, next to `LIB_CORE_OBJS`.
That is the floor `tools/check_archive_members.sh` asserts on every archive,
and it is deliberately a second list — a check whose expectation is the list
it checks is blind to an edit of that list (issue #97). Adding the member to
`LIB_CORE_OBJS` alone is not wrong and goes green; it just leaves the new
member uncovered, and the next contract member will by its nature be another
manifest TU that no consumer stub links — inheriting `precalc_manifest.o`'s
invisibility exactly. So: add it in both places. This cannot be automated by
asserting the two lists are equal, which would restore the tautology for a
two-place delete.

**Only members COMMON TO ALL SEVEN ARCHIVES belong in the floor.** It is
asserted on every archive, so an AEAD-only member put there breaks the
POLYVAL-only builds: adding `tables.o` to `LIB_CONTRACT_MEMBERS` leaves
`make lib` green and then fails `make lib-polyval-long` with
`MISSING (required by LIB_CONTRACT_MEMBERS): tables.o` (measured). An
AEAD-only member belongs in `LIB_AEAD_OBJS`, not the floor. This is a clause
rather than a check because the failure is loud, immediate and
self-correcting — the wrong choice cannot ship quietly, it just costs a
build — whereas the omission the floor exists to catch is silent.

**Flag-set staleness — handled since issue #58; the manual `make clean` between
profile switches is no longer required.** `data.o` and `lib_manifest.o` contents
are conditional on `POLYVAL_PROFILE` (and `lib_manifest.o` additionally on
`POLYVAL_NO_AES`, which the lib-polyval-{long,short,compact} targets set to suppress the
AES manifest rows the POLYVAL-only archives don't ship — issue #23), and none of
those reach a make prerequisite. A **parse-time flag stamp** (`build/.ca65flags`)
now compares the effective `CA65FLAGS` against the previous invocation's and
deletes the stale objects/archives when they differ, so `make POLYVAL_PROFILE=short`
straight after `make` produces the SHORT PRG rather than a stale LONG one, and
`CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES` changes take effect on a warm tree.
Unchanged flags delete nothing, so incremental builds still short-circuit.

Two mechanisms were measured *failing* here before the parse-time one, and both
are worth knowing before anyone "simplifies" this:
- **Stamp as a rule prerequisite, compared by mtime** — macOS ships GNU Make
  3.81, which compares at 1-second granularity. The rewritten stamp is newer only
  in the sub-second digits, so a same-second rebuild is skipped entirely.
- **Stamp as a rule prerequisite that deletes** — make 3.81 stats a target before
  running its prerequisites' recipes and caches that result, so the delete is
  invisible for whichever object make considered first. Measured:
  `build/lib_version.o` deleted and then *not* rebuilt, silently dropping a member
  from the archive — worse than the staleness being fixed.

`make dist` produces `c64-polyval-vX.Y.Z.tar.gz` at repo root. The tarball
ships only `src/`, root docs, `docs/RELEASE_NOTES_*`, and
`docs/precalc-tables.md`; it intentionally omits `tools/`, `test/`, `build/`,
and `ca65/`. (`docs/precalc-tables.md` is staged by an explicit `cp` in
`tools/build_release.sh`, not a glob — a new `docs/*.md` file doesn't ship
automatically. `src/` is fully globbed as of v0.10.0: `*.s`, `*.inc` **and
`*.cfg`**. The cfgs were enumerated by name until then, which silently
left `src/polyval-example.cfg` out of the tarball when it was added —
no diagnostic from the script, from `make dist`, or from the
reproducibility re-run.)

## Profile choice
LONG: 3,917 cy multiply, 255,268 cy precompute, 4,160 B code + 8,448 B
tables. Best for long-message / stable-H workloads.
SHORT: 18,776 cy multiply, 4,656 cy precompute, 13,614 B code + 256 B
tables. Best for RFC 8452 GCM-SIV's per-message H. SHORT/LONG crossover
= 17 blocks (272 B), measured end-to-end, not the ~68 that stood in the
docs from v0.1.0 to v0.7.3 with no derivation.
COMPACT: 49,657 cy multiply, 10,970 cy precompute, 325 B code + 256 B
tables. Same 4-bit Shoup mathematics as SHORT, rolled. Strictly slower
than SHORT at every N — it is a footprint choice, not a speed/memory
trade-off, and exists because 13.6 KB of multiply can push a stock-C64
consumer's image into the $A000-$BFFF ROM window (issue #51).

All cycle figures above are `tools/benchmark_polyval.py` measurements
(`POLYVAL_BENCH_BLOCKS` overrides the multi-block sweep). **Two figures
here were stale from v0.1.0 through v0.7.3**, both corrected in v0.8.0:
SHORT's precompute (~29,385 → 4,656 cy, predating the switch from a
128-iteration mulX_POLYVAL loop to the 7-shift RFC 8452 identity), and
the "practical break-even ≈ 68 blocks", withdrawn — it had no derivation
and its own gloss contradicted it (1 KB is 64 blocks, not 68).

**Two rules from that pair.** Re-measure before quoting a cycle count.
And when correcting one figure, do not certify its neighbours as
unaffected without measuring them too: the v0.8.0 draft said the
68-block figure was "unaffected" by the precompute correction, which was
unfounded — a downward precompute correction pushes crossovers *later*.
Caught in review of PR #63 before tagging.

## Test
```
python3.13 tools/run_all_tests.py --seed 8452                 # all three profiles (~3.5 min)
python3.13 tools/run_all_tests.py --profile short             # one profile (~70 s)
python3.13 tools/run_all_tests.py --seed random --fuzz-iterations 20
python3.13 tools/test_polyval_direct.py [--seed N|random] [--iterations N]
python3.13 tools/test_gcmsiv_polyval.py [--seed N|random] [--iterations N]
python3.13 tools/test_gcmsiv_bounds.py  [--seed N|random] [--profile P]   # regression: #69, #70
python3.13 tools/test_hazmat_fuzz.py    [--seed N|random] [--iterations N] [--profile P]
python3.13 tools/hazmat_oracle.py                            # oracle self-check, no VICE
```
**Use `python3.13` explicitly** — system `python3` is 3.9 on this machine,
and `c64-test-harness` requires 3.10+. Tests need `x64sc` (VICE) on PATH and
the `c64-test-harness` Python package installed. `cryptography` is required
by the reference cross-check and the GCM-SIV suite; `test_hazmat_fuzz.py`
alone treats it as optional (its hazmat cross-checks become counted SKIPs).

The runner builds `make POLYVAL_PROFILE=<p>` for each profile (`--profile
{long,short,compact,all}`, default `all`; the parse-time flag stamp handles
staleness, no `make clean`), runs `cross_validate_reference()` once before
the loop, and drives four suites on three VICE instances per profile:
`test_polyval_direct.py` (217), `test_gcmsiv_polyval.py` (525 + 6 skip),
`test_gcmsiv_bounds.py` (15) and `test_hazmat_fuzz.py` (496 at the runner's
default `--fuzz-iterations 3`; 20 extra checks per iteration).

Expected, **per profile** (identical on LONG, SHORT and COMPACT, measured
2026-08-29 at seed 8452): **1253/1253 pass, 6 skip** once the fix for
issues #69/#70 has merged. The 6 skips are the RFC 8452 vectors with
non-empty AAD — GCM-SIV intentionally does not support AAD; see API.md §6.

**Until that fix PR merges, exactly 8 of the 15 `test_gcmsiv_bounds.py`
checks are RED on every profile by design** (1245 pass, 8 fail):
`gcmsiv_install_enc_key` / `gcmsiv_restore_orig_key` "leaves
aes_expanded_key+240..255 untouched" (issue #69, the 256-byte copy into the
240-byte schedule) and the six `gcmsiv_encrypt`/`gcmsiv_decrypt`
`pt_len=65` / `pt_len=128` checks (issue #70, no bounds check on
`gcmsiv_pt_len`). They are regression tests written RED first; do not
"fix" them by weakening the assertions.

## VICE process hygiene — read this before touching any test infra

**NEVER use `pkill -f x64sc`, `pkill -f vice`, `killall x64sc`, or any
broad-pattern process kill** when cleaning up test VICE instances.

**Why this matters:** other Claude sessions and human developers can be
running their own test VICE instances on the same machine — `c64-nist-curves`,
`c64-wireguard`, `c64-https`, `c64-ChaCha20-Poly1305`, `c64-sid-instruments`,
and `c64-test-harness` itself all spawn `x64sc`. `pkill -f` matches by
command-line substring, so it kills *every* matching process system-wide.
The victim agent then sees mysterious test failures and may waste hours
chasing bugs that don't exist in their code or in VICE.

**How to clean up correctly:**
- `c64-test-harness`'s `UnifiedManager` / `ViceInstanceManager` owns VICE
  lifecycle. Use it. Don't reach around it.
- If you spawn `x64sc` directly (rare; almost always wrong), keep the PID
  from the `subprocess.Popen` object and kill by PID, not by pattern.
- If you genuinely think a stale instance from a prior session needs
  cleanup, list with `pgrep -lf x64sc | head -20`, identify the specific
  PID(s) belonging to this session's working directory (check the
  `--moncommands` argument), and kill those PIDs explicitly. Better:
  leave them alone and let the user reap them.

This rule applies to all Claude sessions in this multi-project workspace.

## Layout (v0.10.0)
```
src/
  lib_version.s          # §1: LIB_VERSION_*/LIB_ABI_VERSION
  zp_config.s            # §2: .exportzp polyval_* / pv_* slots
  lib_manifest.s         # §5: LIB_POLYVAL_*_BYTES + REU_BANKS_USED +
                         #     LIB_POLYVAL_GCMSIV_MAX_PT_LEN (published
                         #     input bound). §5 aggregates ONLY — v1.2.0 §6.1
                         #     member isolation
  precalc_manifest.s     # §8.4: LIB_PRECALC_TABLE invocations, isolated TU
                         #     (holds the displaceable bare LIB_PRECALC_* triple)
  precalc_table.inc      # §8.4: canonical LIB_PRECALC_TABLE macro (copied verbatim)
  constants_lib.inc      # AES sizes, profile selectors, .include "zp_config.s"
  polyval_long.s / polyval_short.s / polyval_compact.s
  aes_encrypt.s / aes_decrypt.s / tables.s
  gcm_siv.s
  data.s                 # all BSS + page-aligned tables (segment-partitioned)
  polyval-example.cfg    # §6.1 consumer-facing example cfg (SHIPPED as
                         #   build/lib/polyval-example.cfg; NOT used by any
                         #   build in this repo — deliberately separate from
                         #   c64.cfg and lib_only.cfg, which carry app-layer
                         #   and verification scaffolding respectively)
  lib_main.s             # make lib-verify entry stub
  c64.cfg / lib_only.cfg # ld65 cfgs with LIB_POLYVAL_* SEGMENTS aliases
  exports.inc            # human-readable cross-module symbol map (NOT an .include)
test/                    # consumer_stub.s (`make consumer-check`)
                         # consumer_stub_noaes.s (`make consumer-check-noaes`,
                         #   issue #47 guard; NOT vendored into the tarball)
                         # consumer_stub_shipped.s (`make consumer-check-shipped`,
                         #   issue #79 guard; NOT vendored into the tarball)
tools/                   # test runner, harness, build_release.sh, vectors/
docs/                    # RELEASE_NOTES_v*.md, precalc-tables.md
ca65/release/v0.1.0/     # frozen historical artifact — DO NOT MODIFY
```

The `ca65/release/v0.1.0/` subtree ships the prior `.lib`-archive release
intact (MANIFEST.txt, attestation/, examples/, `abi_v1.inc`). It is preserved
as historical reference and must not be edited. The active ABI is now
`src/exports.inc` plus the contract files (`lib_version.s`, `zp_config.s`,
`lib_manifest.s`).

## Release flow
0. **Release-PR review gate (fleet standing process, adopted after issue
   #37; see also the MANDATORY working standard above — the adversarial
   review is commissioned per-PR, not only per-release):** stage every release as a PR (version bumps + CHANGELOG +
   stamped notes + tarball) and WAIT for the review comment before
   tagging — do not tag directly on master. Two of this cycle's four
   fleet releases needed pre-tag amendments; tags are immutable here, so
   post-hoc fixes can only amend the release page. Release notes MUST
   state the byte-identity method (worktree-rebuild of the baseline tag,
   every profile the baseline shipped, hash pairs) whenever they claim
   binary identity, and
   MUST use absolute blob URLs (relative links 404 on release pages).

   **Comparing anything against `v0.11.0`: `rm -rf build-short` FIRST.**
   That tag tracks `build-short/lib/polyval-short.a` in git (issue #99,
   fixed after it), so a fresh checkout arrives with a committed archive
   already in place and `git status` clean. Make sees an up-to-date
   target and never rebuilds it, and the comparison silently measures an
   artifact that predates the v0.11.0 member-isolation fix. Found during
   the v0.12.0 pre-tag review, where it first produced a **false**
   finding: `v0.11.0` appeared to export 724 names against v0.12.0's 731,
   with `polyval-short.a` seeming to gain the whole bare surface — which
   would have read as a §6.1 widening in a release claiming an unchanged
   surface. After `rm -rf build-short build` and a forced rebuild both
   sides measure 731/731/162, identical per-name. #99 removes the hazard
   going forward, but **the tag keeps it permanently**: any ABI diff,
   export-set comparison or footprint measurement against `v0.11.0` must
   force the rebuild. Two related notes, both measured rather than
   assumed: PRG byte-identity is *not* affected (`make POLYVAL_PROFILE=<p>`
   writes `build/polyval.prg` and never consults `build-short/`, and the
   v0.12.0 receipt reproduces hash-for-hash with the directory removed);
   and a single `make` invocation naming all seven archive targets does
   not produce all seven — later targets overwrite earlier output, so
   build them separately.

   **A byte-identity receipt may hash PRGs and the tarball, never a `.a`
   or a `.o`.** ca65 stamps the assembly wall-clock second into every
   object; ar65 stores members verbatim (so the stamp rides along) and
   its index additionally records each object file's mtime. Archives and
   objects are therefore not byte-reproducible, while the PRGs and the
   tarball are (measured; issue #97). An archive hash in a receipt
   will fail to reproduce and will read as a regression. The measurement,
   and the traps in comparing archives some other way, are recorded in
   the `Makefile` block above `VERIFY_TARGETS`.

1. Bump `VERSION`, `CHANGELOG.md`, **and `LIB_POLYVAL_VERSION_MINOR`/`_PATCH`
   in `src/lib_version.s`** (the bare `LIB_VERSION_*` aliases follow
   automatically; the v0.3.0 release forgot this file entirely and it went
   unnoticed for a full release cycle — see `API.md` §9.1). Also check the
   value column of the §9.1 table in `API.md` — the v0.4.1 release bumped
   the file but left the table at PATCH 0.
2. Write `docs/RELEASE_NOTES_vX.Y.Z.md` (use the v0.7.3 file as a template).
   Release notes MUST state `RESIDENT`/`COLD` footprint values **per
   shipped archive**, **one row each** — as of v0.8.0 that is **seven
   rows**: `polyval.a`, `polyval-gcmsiv.a`, `polyval-gcmsiv-short.a`,
   `polyval-gcmsiv-compact.a`, `polyval-long.a`, `polyval-short.a`,
   `polyval-compact.a` — even when a value is unchanged. Count the rows
   against the `lib-polyval-*` target list rather than against the
   previous release's table.

   This came from c64-lib-contract §6.6 obligation 2, **retired at
   contract v1.0.0**, and is **kept as local practice**: one tag carries
   a footprint pair per archive, so a single per-version delta is
   meaningless and a merged row makes the count unverifiable. The
   surviving §5 still requires the values themselves to be
   safe-direction and to be presented as a RESIDENT/COLD pair.

   Release notes SHOULD also state `LIB_POLYVAL_GCMSIV_MAX_PT_LEN` when
   it changes — it is exported §5 surface as of v0.10.0, and a consumer
   may be asserting against it.

   **Do not merge archives that share a configuration into one row.**
   `polyval.a` and `polyval-gcmsiv.a` are both LONG AEAD with identical
   values, and v0.7.0–v0.7.2 combined them into a single row while the
   prose said "five rows" — five archives presented as four rows, so the
   row-count check above could not actually be performed as written
   (caught in review of PR #61). One row per archive keeps the count
   literal.
3. `make clean && make dist VERSION=vX.Y.Z` — produces the tarball + stamps
   size/SHA256 into the release notes (two-pass). **The stamper is
   fail-closed** (`tools/build_release.sh`): it aborts unless exactly one
   `SHA256`/`SIZE` placeholder remains after the reset. If it refuses, the
   notes contain a second hash or a literal placeholder token in prose —
   fix the notes, don't loosen the guard. Before v0.7.0 it silently
   stamped the tarball hash over the byte-identity receipt's PRG hashes.
4. Verify reproducibility: re-run `make dist`, SHA256 must be identical.
5. Tag `vX.Y.Z` on the commit that includes the tarball + stamped notes.
