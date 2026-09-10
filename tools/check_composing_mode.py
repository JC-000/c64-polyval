#!/usr/bin/env python3.13
"""check_composing_mode.py -- exercise the mode a composing consumer builds in.

Issues #89 and #94. `-D LIB_NO_BARE_EXPORTS=1` is what a consumer linking two
or more sibling libraries must use, to avoid the duplicate-external-identifier
collision c64-aes256-ecdsa#28 is a live instance of. Before this:

  * nothing LINKED a consumer against an archive built that way --
    consumer-check-shipped assembles with a bare $(CA65) and links the default
    archive, consumer-check-noaes passes only profile/NO_AES defines, and
    check_knob_staleness.sh builds with the define but never links (#94);
  * nothing asserted precalc_manifest.o's §8.4 suppression at all, in any arm
    (#89) -- check_knob_staleness covers lib_version.o only.

NO EXPECTED-VALUE TABLE. The obvious implementation hardcodes the per-arm
prefixed counts (15/9/9/9/3/3), which is a hand-maintained list parallel to
the manifest's own `.if` branches -- the shape that produced #99, and that
adversarial review found twice more in #95 and #93. Each arm is built BOTH
ways and compared against itself: the bare names must go to zero, and the
prefixed set must be UNCHANGED. That is c64-nist-curves#158's framing -- check
the gate for what it KEEPS, not only for what it removes.

WHAT AN ANCHOR HAS TO BE (adversarial review of the first cut). Self-comparison
alone is blind to a table that vanishes from BOTH builds of every arm: comment
out the two `aes_sbox` invocations and every row still reads `ok`. The obvious
repair -- parse the names out of `src/precalc_manifest.s` and reconcile the
exports against them -- does not work either, because both sides of that
comparison come out of the SAME file and move together. So the reconciliation
below anchors OUTSIDE the manifest, in two directions:

  * NAMES, SIZES, REGIONS and §8.x CLASSIFICATIONS are reconciled against
    `docs/precalc-tables.md`, the §8.4 artifact of record, which a human
    maintains at a different time -- against the manifest's own literals AND
    against the values od65 reads back out of the built object. A table
    deleted from, added to, or resized in one and not the other is red.
  * ARM SETS. The doc's Profile column names either archives (in backticks) or
    UPPERCASE profile tokens, and the table must be exported by exactly those
    arms. This is the only leg that catches a CONDITIONAL table being
    re-gated: moving `aes_sbox` to LONG-only leaves the union and the
    unconditional set untouched while SHORT and COMPACT AEAD consumers
    silently lose the name. That column was itself wrong until this branch
    corrected it -- issue #103 -- so it is now load-bearing and must stay
    correct.
  * DEPTH, as a cross-check. An invocation not inside any `.if` (the include
    guard aside) must be present in ALL SIX arms.
  * THE PROSE under the table, not only its rows. The paragraph restating the
    AES tables' archive membership in English carried exactly the same #103
    staleness the rows did, and reverting only it left this check green -- so
    the row grammar was proving nothing about the prose, which is now the
    likelier drift site precisely because the rows are watched. Its two
    archive lists and its count word are reconciled against the same
    lib-polyval-* target set; so are the `lib-polyval-{a,b}` brace lists that
    name targets, in API.md as well as here (the same omission was live in
    both), and no backticked archive may appear in the
    membership sentence OUTSIDE the two reconciled parentheticals. What is
    still NOT read is any other prose in that paragraph: a claim written in
    some further form is unchecked, and the fix for that is to state it in one
    of the forms above rather than to widen this into prose interpretation.

The residual gap, stated rather than papered over: the doc is a human artifact
in the same commit, so a change made to BOTH sides at once reconciles by
construction. What this catches is drift -- one side moving without the other
-- which is every instance the repo has actually had. Nothing here proves the
enumerated sizes match the bytes `src/data.s` reserves; that is a different
check (`check_footprints.py`'s territory) and is not claimed here.
"""
import re, subprocess, sys, shutil, tempfile
from pathlib import Path

ROOT     = Path(__file__).resolve().parent.parent
MK       = ROOT / "Makefile"
MANIFEST = ROOT / "src" / "precalc_manifest.s"
MACRO    = ROOT / "src" / "precalc_table.inc"
DOC      = ROOT / "docs" / "precalc-tables.md"

def die(msg):
    print(f"check_composing_mode: FAIL -- {msg}", file=sys.stderr); sys.exit(1)

def run(cmd, what):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        tail = (r.stderr or r.stdout).strip().splitlines()[-1:] or ["(no output)"]
        die(f"{what} failed (exit {r.returncode}): {tail[0]}")
    return r.stdout

# --- od65 ------------------------------------------------------------------
def exports(obj):
    """{name: (address-size word, value)} for every export od65 dumps."""
    if not obj.exists(): die(f"{obj.name} does not exist -- the arm did not build, which is NOT 'no exports'")
    out = run(["od65","--dump-exports",str(obj)], f"od65 on {obj.name}")
    declared = re.search(r"^\s*Count:\s*(\d+)", out, re.M)
    if not declared: die(f"no export Count in od65's dump of {obj.name}")
    ents = {}
    for chunk in re.split(r"^\s*Index:\s*\d+\s*$", out, flags=re.M)[1:]:
        n = re.search(r'Name:\s*"([^"]+)"', chunk)
        a = re.search(r"Address size:\s*0x[0-9a-fA-F]+\s*\(([a-z]+)\)", chunk)
        v = re.search(r"Value:\s*0x([0-9a-fA-F]+)", chunk)
        if not (n and a and v):
            die(f"{obj.name}: an od65 export entry has no Name/Address size/Value -- "
                f"the extractor is wrong, so no comparison below can be trusted")
        ents[n.group(1)] = (a.group(1), int(v.group(1), 16))
    if len(ents) != int(declared.group(1)):
        die(f"{obj.name}: parsed {len(ents)} entries but od65 declared {declared.group(1)} -- "
            f"the extractor is wrong, so no comparison below can be trusted")
    return ents

# --- the Makefile is the only place a profile number is written ------------
def profile_vals():
    """{'long': '2', ...} read out of the Makefile's PROFILE_VAL ifeq ladder.

    Restating the mapping here (issue: review of #89/#94) would drift silently:
    a renumbering assembles the stub under the WRONG profile and still links,
    because ld65 resolves everything it needs from the archive either way.
    """
    pairs = re.findall(r"^\s*(?:else\s+)?ifeq\s*\(\$\(POLYVAL_PROFILE\),(\w+)\)\s*\n"
                       r"\s*PROFILE_VAL\s*=\s*(\d+)\s*$", MK.read_text(), re.M)
    if not pairs:
        die("no `ifeq ($(POLYVAL_PROFILE),<p>)` / `PROFILE_VAL = <n>` pairs in the Makefile -- "
            "the profile numbers cannot be read, and must not be guessed here")
    d = dict(pairs)
    if len(d) != len(pairs): die(f"the Makefile assigns PROFILE_VAL twice for one profile: {pairs}")
    return d

def arms():
    txt  = MK.read_text()
    prof = profile_vals()
    targets = sorted(set(re.findall(r"^(lib-polyval-[a-z-]+):", txt, re.M)))
    out = []
    for t in targets:
        rest = t[len("lib-polyval-"):]
        aead = rest.startswith("gcmsiv")
        p = rest.split("-")[-1] if rest != "gcmsiv" else "long"
        if p not in prof:
            die(f"target {t} names profile '{p}', which the Makefile's PROFILE_VAL ladder does not define")
        out.append((f"{p.upper()} {'AEAD' if aead else 'NO_AES'}", t, prof[p], aead, t[len("lib-"):] + ".a"))
    if len(out) != 6:
        die(f"derived {len(out)} archive configurations from the Makefile, expected 6 -- "
            f"a target was added or renamed and this check must be updated deliberately")
    return out

# --- §8.4 enumeration: the manifest, and its outside anchor ----------------
GUARD = re.compile(r"^\.ifn?def\s+\w*_INCLUDED\b", re.I)
INVOKE = re.compile(r'^LIB_PRECALC_TABLE\s+"([^"]+)"\s*,\s*(\d+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,')

def manifest_tables():
    """[(name, size, region-const, shared-const, unconditional?)] from precalc_manifest.s.

    `unconditional` means: enclosed by nothing except the file's own include
    guard. Those are the tables every arm must carry.
    """
    stack, out = [], []
    for ln, raw in enumerate(MANIFEST.read_text().splitlines(), 1):
        code = raw.split(";")[0].strip()
        if not code: continue
        low = code.lower()
        if low.startswith(".if"):
            stack.append(code)
        elif low.startswith(".endif"):
            if not stack:
                die(f"{MANIFEST.name}:{ln}: .endif with no open .if -- the conditional-depth parse is wrong, "
                    f"so 'unconditional' below would be meaningless")
            stack.pop()
        m = INVOKE.match(code)
        if m:
            out.append((m.group(1), int(m.group(2)), m.group(3), m.group(4),
                        all(GUARD.match(c) for c in stack)))
    if stack:
        die(f"{MANIFEST.name}: {len(stack)} unclosed .if at end of file -- the conditional-depth parse is wrong")
    if not out:
        die(f"{MANIFEST.name}: parsed no LIB_PRECALC_TABLE invocation -- an empty enumeration must not "
            f"read as 'everything reconciles'")
    if not any(u for *_, u in out):
        die(f"{MANIFEST.name}: every invocation parsed as conditional -- either the include-guard rule "
            f"stopped matching or the manifest really gates everything; either way the 'present in all "
            f"six arms' assertion below would be vacuous")
    return out

def doc_arms(cell, name):
    """Read the doc's Profile column as an exact set of archives-or-profiles.

    Two disjoint grammars, both mechanical -- no prose is interpreted:

      * the cell names archive basenames in backticks (`polyval-gcmsiv.a` ...)
        -> the table must be exported by exactly those archives' arms;
      * otherwise the cell names UPPERCASE profile tokens (LONG / SHORT /
        COMPACT) -> the table must be exported by exactly those profiles' arms,
        AEAD and NO_AES alike.

    An archive basename is lowercase, so the two never collide, and a cell
    matching neither is a hard failure rather than a silently skipped row.
    """
    archives = set(re.findall(r"`([a-z0-9.-]+\.a)`", cell))
    if archives: return ("archives", archives)
    profiles = {p.lower() for p in re.findall(r"\b(LONG|SHORT|COMPACT)\b", cell)}
    if profiles: return ("profiles", profiles)
    die(f"{DOC.name}: the Profile column for {name} names neither an archive nor a profile "
        f"({cell.strip()!r}) -- the arm reconciliation cannot be performed, and must not be skipped")

def doc_tables():
    """{name: (size, region-const, shared-const, arm-spec)} from docs/precalc-tables.md.

    The outside anchor. Columns: Name | Size | Region | Profile | Source |
    Classification | Rationale.
    """
    m = re.search(r"^##\s*Enumerated tables\s*$(.*?)^##\s", DOC.read_text(), re.M | re.S)
    if not m: die(f"{DOC.name}: no '## Enumerated tables' section -- the outside anchor is gone")
    rows = {}
    for line in m.group(1).splitlines():
        if not line.startswith("|"): continue
        cells = line.split("|")
        if all(set(c.strip()) <= set("-: ") for c in cells[1:-1]): continue   # header rule
        if [c.strip() for c in cells[1:3]] == ["Name","Size"]: continue       # header row
        if len(cells) != 9:
            die(f"{DOC.name}: enumerated-table row has {len(cells)-2} columns, expected 7 -- "
                f"the anchor's shape changed and this parse must be updated deliberately:\n    {line.strip()}")
        name = re.fullmatch(r"`([A-Za-z0-9_]+)`", cells[1].strip())
        size = re.fullmatch(r"([0-9]+)\s*B", cells[2].strip())
        if not name or not size:
            die(f"{DOC.name}: cannot read a name/size out of row:\n    {line.strip()}")
        region_txt, klass = cells[3].upper(), cells[6].strip().lower()
        if   "RODATA" in region_txt: region = "PRECALC_REGION_RODATA"
        elif "REU"    in region_txt: region = "PRECALC_REGION_REU"
        elif "RAM"    in region_txt: region = "PRECALC_REGION_RAM"
        else: die(f"{DOC.name}: cannot read a region out of {cells[3].strip()!r} for {name.group(1)}")
        if   klass.startswith("algorithm-specific"): shared = "PRECALC_SHARED_NO"
        elif klass.startswith("shared"):             shared = "PRECALC_SHARED_YES"
        else: die(f"{DOC.name}: cannot read a §8.x classification out of {cells[6].strip()!r} "
                  f"for {name.group(1)}")
        if name.group(1) in rows: die(f"{DOC.name}: {name.group(1)} is enumerated twice")
        rows[name.group(1)] = (int(size.group(1)), region, shared,
                               doc_arms(cells[4], name.group(1)))
    if not rows:
        die(f"{DOC.name}: parsed no rows out of '## Enumerated tables' -- an empty anchor must not "
            f"read as 'everything reconciles'")
    return rows

NUMWORD = {"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8}

def doc_prose_archives():
    """The archive lists in the PROSE below the table, as two sets and a count.

    doc_tables() reads ONLY the `## Enumerated tables` rows. The paragraph
    under them restates the same archive membership in English, and it carried
    exactly the same #103 staleness the rows did -- "all three AEAD archives",
    and a two-item POLYVAL-only list. Reverting only that paragraph left this
    check green, so the row grammar proved nothing about the prose; and the
    prose is now the LIKELIER drift site precisely because the rows are
    watched. Hence this leg.

    Mechanical, like doc_arms(): a count word, and the backticked `*.a`
    basenames inside each of the two parentheticals. No other prose is
    interpreted. Either sentence going missing is a hard failure -- a check
    that silently skips the thing it watches is the shape being fixed here.
    """
    m = re.search(r"^##\s*Enumerated tables\s*$(.*?)^##\s", DOC.read_text(), re.M | re.S)
    if not m: die(f"{DOC.name}: no '## Enumerated tables' section -- the outside anchor is gone")
    body = m.group(1)
    a = re.search(r"member of all\s+([a-z]+)\s+AEAD archives\s*\(([^)]*)\)", body)
    if not a:
        die(f"{DOC.name}: no 'member of all <count> AEAD archives (...)' sentence under "
            f"'## Enumerated tables' -- the prose half of the archive-membership claim "
            f"cannot be reconciled, and must not be skipped")
    n = re.search(r"POLYVAL-only archives\s*\(([^)]*)\)", body[a.end():])
    if not n:
        die(f"{DOC.name}: no 'POLYVAL-only archives (...)' sentence after the AEAD one under "
            f"'## Enumerated tables' -- the prose half of the archive-membership claim "
            f"cannot be reconciled, and must not be skipped")
    # NOTHING OUTSIDE THE TWO PARENTHETICALS. Everything above reads only what is
    # inside them, so a clause between them parsed green with both lists and the
    # count correct -- and the constructed case was "a member of ... and of
    # `polyval-long.a`", the exact false claim issue #23 exists to prevent. Any
    # backticked archive in the membership sentence must be inside one of the two
    # lists that ARE reconciled.
    span = body[a.start():a.end() + n.end()]
    stray = set(re.findall(r"`([a-z0-9.-]+\.a)`",
                           span.replace(a.group(2), "").replace(n.group(1), "")))
    if stray:
        die(f"{DOC.name}: the membership sentence names {sorted(stray)} OUTSIDE the two "
            f"parenthetical lists -- only those two are reconciled, so an archive claim "
            f"made anywhere else in the sentence is unchecked prose")
    if a.group(1) not in NUMWORD:
        die(f"{DOC.name}: 'all {a.group(1)} AEAD archives' -- {a.group(1)!r} is not a count word "
            f"this check knows, so the count cannot be reconciled")
    aead  = set(re.findall(r"`([a-z0-9.-]+\.a)`", a.group(2)))
    noaes = set(re.findall(r"`([a-z0-9.-]+\.a)`", n.group(1)))
    for what, s in (("AEAD", aead), ("POLYVAL-only", noaes)):
        if not s:
            die(f"{DOC.name}: the {what} parenthetical names no `*.a` archive -- an empty list "
                f"must not read as 'reconciles'")
    return NUMWORD[a.group(1)], aead, noaes

# Backticks optional: CLAUDE.md writes the same list bare, and that instance was
# stale too. The gcmsiv- form is read as well -- same drift risk, same fix.
BRACE = re.compile(r"lib-polyval-(gcmsiv-)?\{([a-z,]+)\}")
# HAND-MAINTAINED, and that is a real limitation: a new file naming targets is
# unwatched until someone adds it here. Scanning every tracked file instead is a
# different change, and it would have to cope with the forms this grammar does
# NOT read -- the pipe form `polyval_(long|short)` in src/exports.inc, and the
# archive brace `polyval-{long,short,compact}.a` in src/lib_manifest.s. Those
# files were corrected by hand in the same sweep and are NOT guarded by
# anything.
#
# The Makefile is not in the list either, and the reason first written here was
# WRONG -- it said a Makefile brace list "can sit near a POLYVAL_NO_AES mention
# while correctly naming a different set", so the file "would fail on a true
# statement". Measured, adding "Makefile" gives the OPPOSITE failure:
#   Makefile: mentions POLYVAL_NO_AES but has no `lib-polyval-{...}` list
#   within 150 characters of it
# None of its three grammar-matched lists is anywhere near any of its 24
# POLYVAL_NO_AES mentions -- NEAR would have to rise from 150 to 221 before one
# of them read as the claim. (Its one five-target list is not matched at all:
# the character class above is [a-z,] and `gcmsiv-short` has a hyphen.)
#
# The second, more useful reason: guarding the Makefile would not have caught
# the defect that motivated this note. The expansion leg below only asserts the
# names are REAL TARGETS, never that the set is COMPLETE, so a comment naming
# three of the five recursive $(MAKE) wrappers passes it. Both limits are
# honest; neither is a proximity accident.
BRACE_FILES = ("docs/precalc-tables.md", "API.md", "README.md", "CLAUDE.md",
               "src/precalc_manifest.s")
NEAR = 150
NOAES = "POLYVAL_NO_AES"

def brace_targets():
    """Every `lib-polyval-{a,b}` brace list in the docs that name targets.

    The form is invisible to the parenthetical grammar above, and D11 is the
    proof that matters: `lib-polyval-{long,short}` said TWO targets pass
    -D LIB_POLYVAL_NO_AES=1 when the Makefile has had three since v0.8.0 --
    #103's own omission, four lines below the sentence corrected for #103, and
    green. A sweep then found the SAME omission in API.md, which ships in the
    release tarball. So this reads both files, not just the §8.4 one.

    Two mechanical legs, no prose interpreted:
      * every list expands to targets the Makefile actually provides;
      * a list within NEAR characters of `LIB_POLYVAL_NO_AES` is claiming which
        targets suppress the AES rows, and must name exactly those. Each file
        must carry at least one such list -- a rewording that moves the mention
        out of range fails loudly here rather than dropping the leg silently.

    Returns [(file, expanded set, is-the-NO_AES-claim)].
    """
    out = []
    for rel in BRACE_FILES:
        f = ROOT / rel
        if not f.exists(): die(f"{rel} does not exist -- its brace lists cannot be reconciled")
        txt, seen = f.read_text(), 0
        for mm in BRACE.finditer(txt):
            stem = "lib-polyval-" + (mm.group(1) or "")
            names = {stem + x for x in mm.group(2).split(",") if x}
            if not names:
                die(f"{rel}: an empty `lib-polyval-{{}}` list -- it names no target")
            ctx = txt[max(0, mm.start()-NEAR): mm.end()+NEAR]
            is_noaes = NOAES in ctx
            seen += is_noaes
            out.append((rel, names, is_noaes))
        # A file that never mentions the define makes no claim to reconcile (README
        # is that case). A file that DOES mention it must state which targets carry
        # it in the reconcilable form, so a rewording cannot drop the leg quietly.
        if NOAES in txt and not seen:
            die(f"{rel}: mentions {NOAES} but has no `lib-polyval-{{...}}` list within "
                f"{NEAR} characters of it -- the claim naming which targets suppress the "
                f"AES rows cannot be reconciled, and must not be skipped")
    return out

def const_vals():
    """PRECALC_REGION_* / PRECALC_SHARED_* numeric values from the canonical macro."""
    vals = {m.group(1): int(m.group(2), 16) for m in
            re.finditer(r"^(PRECALC_(?:REGION|SHARED)_\w+)\s*=\s*\$([0-9A-Fa-f]+)", MACRO.read_text(), re.M)}
    for need in ("PRECALC_REGION_RAM","PRECALC_REGION_RODATA","PRECALC_SHARED_NO"):
        if need not in vals: die(f"{MACRO.name}: no {need} equate -- cannot check exported values")
    return vals

BARE = {
    "precalc_manifest.o": re.compile(r"^LIB_PRECALC_"),
    "lib_version.o":      re.compile(r"^LIB_(VERSION|ABI)"),
}
PREFIXED = {
    "precalc_manifest.o": re.compile(r"^LIB_POLYVAL_PRECALC_"),
    "lib_version.o":      re.compile(r"^LIB_POLYVAL_(VERSION|ABI)"),
}
SUFFIXES = ("SIZE","REGION","SHARED")

def selftest():
    """Positive control over the four matchers this gate's verdict rests on.

    This file is unusually well guarded against an EMPTY parse -- ~18 explicit
    dies, each earned by a review. What none of them can catch is a matcher
    that still matches SOMETHING but no longer matches the shape that matters:
    a narrowed regex reconciles a smaller set against a smaller set and every
    row still prints. Rebuilding the library cannot reveal that, because the
    code under test is a regex over source and prose.

    Drives the same module-level patterns and the same doc_arms() the real run
    uses, over synthetic inputs in the real formats.
    """
    checks = 0

    # 1. The brace lists. D11 is the precedent: `lib-polyval-{long,short}` sat
    #    four lines from a corrected sentence, claiming two NO_AES targets
    #    against the Makefile's three, and every other leg was green on it.
    got = [(m.group(1), m.group(2)) for m in BRACE.finditer(
        "lib-polyval-{long,short,compact} and lib-polyval-gcmsiv-{short,compact}")]
    if got != [(None, "long,short,compact"), ("gcmsiv-", "short,compact")]:
        die(f"POSITIVE CONTROL FAILED: BRACE parsed {got} out of a known pair of brace "
            "lists. A narrowed pattern reconciles fewer claims against fewer targets and "
            "still prints a row for each (D11)")
    checks += 1

    # 2. The §8.4 invocation parse. `parsed no LIB_PRECALC_TABLE invocation`
    #    covers zero; it does not cover a pattern that has stopped seeing SOME.
    m = INVOKE.match('LIB_PRECALC_TABLE "aes_sbox", 256, aes_sbox, polyval,')
    if not m or m.groups()[:3] != ("aes_sbox", "256", "aes_sbox"):
        die(f"POSITIVE CONTROL FAILED: INVOKE did not parse a well-formed "
            f"LIB_PRECALC_TABLE line (got {m.groups() if m else None}) -- the "
            "enumeration this gate reconciles is built by this pattern")
    checks += 1

    # 3. The include-guard exclusion, both directions. Over-matching here marks
    #    a real invocation conditional and drops it from the enumeration.
    if not GUARD.match(".ifndef PRECALC_TABLE_INCLUDED"):
        die("POSITIVE CONTROL FAILED: GUARD did not match a real include guard -- "
            "guarded blocks would be read as genuine conditionals")
    if GUARD.match(".ifdef LIB_POLYVAL_NO_AES"):
        die("NEGATIVE CONTROL FAILED: GUARD matched `.ifdef LIB_POLYVAL_NO_AES`, "
            "which is a genuine conditional, not an include guard -- a real "
            "conditional would be excused as one")
    checks += 1

    # 4. doc_arms' two disjoint grammars. A cell read as the WRONG kind
    #    reconciles against the wrong arm set and still passes.
    if doc_arms("`polyval-gcmsiv.a`, `polyval-gcmsiv-short.a`", "<control>") != \
       ("archives", {"polyval-gcmsiv.a", "polyval-gcmsiv-short.a"}):
        die("POSITIVE CONTROL FAILED: doc_arms misread a backticked archive cell")
    if doc_arms("LONG and COMPACT", "<control>") != ("profiles", {"long", "compact"}):
        die("POSITIVE CONTROL FAILED: doc_arms misread an uppercase profile cell")
    checks += 1

    return checks


def main():
    controls = selftest()
    for tool in ("ca65","ld65","od65","make"):
        if not shutil.which(tool): die(f"{tool} not on PATH")

    consts = const_vals()
    tables = manifest_tables()
    doc    = doc_tables()

    # (1) the manifest reconciles against the artifact of record, both ways.
    m_by_name = {n: (s, r, sh) for n, s, r, sh, _ in tables}
    if len(m_by_name) != len(tables): die(f"{MANIFEST.name}: a table is enumerated twice")
    if set(m_by_name) != set(doc):
        die(f"§8.4 enumeration does not reconcile with {DOC.name}: "
            f"in the manifest only {sorted(set(m_by_name)-set(doc))}, "
            f"in the doc only {sorted(set(doc)-set(m_by_name))}")
    for n in sorted(m_by_name):
        if m_by_name[n] != doc[n][:3]:
            die(f"§8.4 {n}: the manifest says (size, region, shared) = {m_by_name[n]} "
                f"but {DOC.name} says {doc[n][:3]}")
    uncond = sorted(n for n, *_ , u in tables if u)
    print(f"  §8.4 enumeration    {len(tables)} table(s) reconcile with {DOC.name}; "
          f"unconditional: {', '.join(uncond)}")

    ARMS = arms()
    bd  = Path(tempfile.mkdtemp(prefix="build-scratch.", dir=str(ROOT)))
    rel, bad = bd.name, 0
    union, per_arm = set(), {}
    try:
        for label, target, profile, aead, archive in ARMS:
            snap = {}
            for mode, defines in (("default", ""), ("nobare", "-D LIB_NO_BARE_EXPORTS=1")):
                run(["make",f"BUILD_DIR={rel}","clean-build"], "make clean-build")
                run(["make",f"BUILD_DIR={rel}",target,f"CONTRACT_DEFINES={defines}"], f"make {target} [{mode}]")
                snap[mode] = {}
                for o in BARE:
                    # EVERY inspected object, not just one: dropping lib_version from
                    # LIB_CORE_OBJS used to print no row for it and still report ok.
                    if not (bd/o).exists():
                        die(f"{label} [{mode}]: {o} is absent from the build -- it is a member of every "
                            f"archive; its absence must not read as 'suppression works'")
                    snap[mode][o] = exports(bd/o)

            for obj in sorted(BARE):
                d, n = snap["default"][obj], snap["nobare"][obj]
                d_bare = {k for k in d if BARE[obj].match(k)}
                n_bare = {k for k in n if BARE[obj].match(k)}
                d_pre  = {k for k in d if PREFIXED[obj].match(k)}
                n_pre  = {k for k in n if PREFIXED[obj].match(k)}
                notes = []
                if not d_bare:
                    notes.append("NO BARE NAMES IN THE DEFAULT BUILD -- nothing to suppress, so the "
                                 "suppression assertion below would pass vacuously")
                if n_bare:  notes.append(f"{len(n_bare)} bare name(s) SURVIVED suppression: {sorted(n_bare)[:3]}")
                if d_pre != n_pre:
                    notes.append(f"prefixed surface CHANGED: {len(d_pre)} -> {len(n_pre)}, "
                                 f"lost {sorted(d_pre - n_pre)[:3]}")
                # #89 items 2-3: every name in either family, in either mode, absolute.
                rel_ = [(m, k, v[0]) for m, s in (("default",d), ("nobare",n)) for k, v in s.items()
                        if (BARE[obj].match(k) or PREFIXED[obj].match(k)) and v[0] != "absolute"]
                if rel_:
                    notes.append(f"{len(rel_)} export(s) are not absolute: "
                                 f"{[f'{k} ({m}: {a})' for m,k,a in rel_[:3]]}")
                # a bare name and its prefixed twin must carry the same value.
                for k in sorted(d_bare):
                    twin = k.replace("LIB_", "LIB_POLYVAL_", 1)
                    if twin in d and d[twin][1] != d[k][1]:
                        notes.append(f"{k} = {d[k][1]} but {twin} = {d[twin][1]} -- the two forms disagree")
                if notes: bad += 1
                print(f"  {label:<15} {obj:<22} bare {len(d_bare):2d} -> {len(n_bare):2d}   "
                      f"prefixed {len(d_pre):2d} -> {len(n_pre):2d}   {'; '.join(notes) or 'ok'}")
                if notes: print("      " + "\n      ".join(notes), file=sys.stderr)

            # (2) what this arm's §8.4 surface actually says, checked against the doc.
            pre = {k: v for k, v in snap["nobare"]["precalc_manifest.o"].items()
                   if PREFIXED["precalc_manifest.o"].match(k)}
            seen = {}
            for k, (_, val) in pre.items():
                mm = re.fullmatch(r"LIB_POLYVAL_PRECALC_(.+)_(SIZE|REGION|SHARED)", k)
                if not mm: die(f"{label}: cannot split {k} into <table>_<SIZE|REGION|SHARED>")
                seen.setdefault(mm.group(1), {})[mm.group(2)] = val
            for name in sorted(seen):
                if name not in doc:
                    die(f"{label}: exports LIB_POLYVAL_PRECALC_{name}_* but {DOC.name} does not "
                        f"enumerate {name} -- the §8.4 surface widened without the artifact of record")
                missing = [s for s in SUFFIXES if s not in seen[name]]
                if missing: die(f"{label}: {name} exports no {'/'.join(missing)}")
                size, region, shared, _ = doc[name]
                want = {"SIZE": size, "REGION": consts[region], "SHARED": consts[shared]}
                for s in SUFFIXES:
                    if seen[name][s] != want[s]:
                        die(f"{label}: LIB_POLYVAL_PRECALC_{name}_{s} = {seen[name][s]}, "
                            f"but {DOC.name} says {want[s]}")
            per_arm[label] = set(seen)
            union |= set(seen)

            # (3) #94: the composing mode must LINK A CONSUMER AGAINST THE ARCHIVE.
            # Linking the loose bd/*.o set with the repo-internal src/lib_only.cfg
            # (the first cut) tested neither: with the AEAD ar65 recipes reduced to
            # a single member the link still produced an identical 6543-byte PRG.
            if aead:
                # -I the STAGED lib dir, never src/ -- consumer_stub_shipped.s is the
                # #79 guard's stub and its point is that the shipped surface suffices.
                inc = bd/"lib"
                for f in ("polyval.inc", "polyval-example.cfg", archive):
                    if not (inc/f).exists():
                        die(f"{label}: {inc}/{f} was not staged -- the shipped surface is incomplete")
                found = sorted(p.name for p in inc.glob("*.a"))
                if found != [archive]:
                    die(f"{label}: expected exactly {archive} under {inc}, found {found}")
                run(["ca65","-I",str(inc),"-D",f"POLYVAL_PROFILE={profile}","-D","LIB_NO_BARE_EXPORTS=1",
                     "-o",str(bd/"_cm_drv.o"),"test/consumer_stub_shipped.s"], f"{label}: ca65 shipped stub [nobare]")
                run(["ld65","-C",str(inc/"polyval-example.cfg"),"-o",str(bd/"_cm.prg"),
                     str(bd/"_cm_drv.o"), str(inc/archive)], f"{label}: ld65 against {archive} [nobare]")
                if not (bd/"_cm.prg").exists() or (bd/"_cm.prg").stat().st_size == 0:
                    die(f"{label}: the nobare link produced no output")
                print(f"  {label:<15} {('link vs '+archive):<22} {(bd/'_cm.prg').stat().st_size} bytes   ok")
    finally:
        shutil.rmtree(bd, ignore_errors=True)

    # (4) every enumerated table must be emitted SOMEWHERE, and every
    # unconditional one EVERYWHERE.
    never = sorted(set(doc) - union)
    if never:
        die(f"enumerated in {DOC.name} and {MANIFEST.name} but exported by NO arm: {never} -- "
            f"the enumeration describes a table no archive ships")
    for name in uncond:
        absent = sorted(a for a, s in per_arm.items() if name not in s)
        if absent:
            die(f"{name} is enumerated unconditionally but is absent from: {absent} -- "
                f"a consumer of those archives loses the name")

    # (5) and the EXACT arm set, which is the only leg that catches a
    # CONDITIONAL table being re-gated: `aes_sbox` moved from
    # `.ifndef LIB_POLYVAL_NO_AES` to LONG-only leaves both the union and the
    # unconditional set untouched, while SHORT and COMPACT AEAD consumers
    # silently lose the name. The doc's Profile column is the anchor; it was
    # itself wrong until this branch corrected it (issue #103).
    by_archive = {a[4]: a[0] for a in ARMS}
    by_archive["polyval.a"] = by_archive["polyval-gcmsiv.a"]   # `lib`: same LIB_AEAD_OBJS, same profile
    if not re.search(r"^\$\(LIB_DIR\)/polyval\.a:\s*\$\(LIB_AEAD_OBJS\)", MK.read_text(), re.M):
        die("the Makefile no longer builds polyval.a from $(LIB_AEAD_OBJS) -- the alias that lets "
            f"{DOC.name} name polyval.a alongside polyval-gcmsiv.a is no longer sound")
    for name in sorted(doc):
        kind, spec = doc[name][3]
        if kind == "archives":
            unknown = sorted(spec - set(by_archive))
            if unknown:
                die(f"{DOC.name}: the Profile column for {name} names {unknown}, which no "
                    f"lib-polyval-* target builds")
            want = {by_archive[a] for a in spec}
        else:
            unknown = sorted(spec - {a[0].split()[0].lower() for a in ARMS})
            if unknown:
                die(f"{DOC.name}: the Profile column for {name} names profile(s) {unknown}, "
                    f"which no lib-polyval-* target builds")
            want = {a[0] for a in ARMS if a[0].split()[0].lower() in spec}
        got = {lbl for lbl, s in per_arm.items() if name in s}
        if got != want:
            die(f"{name}: {DOC.name} puts it in {sorted(want)}, the archives export it in "
                f"{sorted(got)} -- missing from {sorted(want-got)}, unexpected in {sorted(got-want)}")
    print(f"  §8.4 arm sets       every enumerated table appears in exactly the arms "
          f"{DOC.name} says it does")

    # (6) the PROSE half of the same claim. The rows above are watched; the
    # paragraph restating them in English was not, and carried the identical
    # #103 staleness. Reverting only that paragraph used to leave this green.
    count, prose_aead, prose_noaes = doc_prose_archives()
    want_aead  = {a for a, lbl in by_archive.items() if lbl.endswith("AEAD")}
    want_noaes = {a for a, lbl in by_archive.items() if lbl.endswith("NO_AES")}
    if prose_aead != want_aead:
        die(f"{DOC.name}: the prose calls the AEAD archives {sorted(prose_aead)}, but the "
            f"lib-polyval-* targets build {sorted(want_aead)} -- missing "
            f"{sorted(want_aead - prose_aead)}, unexpected {sorted(prose_aead - want_aead)}")
    if prose_noaes != want_noaes:
        die(f"{DOC.name}: the prose calls the POLYVAL-only archives {sorted(prose_noaes)}, but "
            f"the lib-polyval-* targets build {sorted(want_noaes)} -- missing "
            f"{sorted(want_noaes - prose_noaes)}, unexpected {sorted(prose_noaes - want_noaes)}")
    if count != len(want_aead):
        die(f"{DOC.name}: the prose says 'all {count} AEAD archives' but names {len(prose_aead)} "
            f"and the Makefile builds {len(want_aead)}")
    # (7) the brace lists in the same paragraph. D11: `lib-polyval-{long,short}`
    # claimed two NO_AES targets against the Makefile's three, four lines below
    # the sentence #103 corrected, and every leg above was green on it.
    braces = brace_targets()
    all_targets = {a[1] for a in ARMS}
    want_noaes_targets = {a[1] for a in ARMS if not a[3]}
    for rel, names, is_noaes in braces:
        unknown = sorted(names - all_targets)
        if unknown:
            die(f"{rel}: a `lib-polyval-{{...}}` list expands to {unknown}, which no "
                f"lib-polyval-* target in the Makefile provides")
        if is_noaes and names != want_noaes_targets:
            die(f"{rel}: the prose says {sorted(names)} carry LIB_POLYVAL_NO_AES, but the "
                f"Makefile passes POLYVAL_NO_AES=1 from {sorted(want_noaes_targets)} -- "
                f"missing {sorted(want_noaes_targets - names)}, unexpected "
                f"{sorted(names - want_noaes_targets)}")
    print(f"  §8.4 prose          the paragraph's archive lists match the "
          f"lib-polyval-* targets ({count} AEAD, {len(want_noaes)} POLYVAL-only); "
          f"{len(braces)} brace list(s) in {len(BRACE_FILES)} file(s) expand to real "
          f"targets, {sum(1 for _,_,n in braces if n)} of them the NO_AES claim")
    if bad: die(f"{bad} assertion(s) failed -- see the rows above")
    print(f"check_composing_mode: suppression removes every bare name and keeps every prefixed one, "
          f"all 6 arms; {len(doc)} enumerated table(s) reconcile with {DOC.name}; "
          f"the shipped surface links against each AEAD archive in the composing mode; "
          f"{controls} positive control group(s) fired")

if __name__ == "__main__":
    main()
