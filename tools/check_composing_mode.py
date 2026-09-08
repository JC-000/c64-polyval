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
    lib-polyval-* target set.

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
    n = re.search(r"POLYVAL-only archives\s*\(([^)]*)\)", body)
    if not n:
        die(f"{DOC.name}: no 'POLYVAL-only archives (...)' sentence under "
            f"'## Enumerated tables' -- the prose half of the archive-membership claim "
            f"cannot be reconciled, and must not be skipped")
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

def main():
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
    print(f"  §8.4 prose          the paragraph's archive lists match the "
          f"lib-polyval-* targets ({count} AEAD, {len(want_noaes)} POLYVAL-only)")
    if bad: die(f"{bad} assertion(s) failed -- see the rows above")
    print(f"check_composing_mode: suppression removes every bare name and keeps every prefixed one, "
          f"all 6 arms; {len(doc)} enumerated table(s) reconcile with {DOC.name}; "
          f"the shipped surface links against each AEAD archive in the composing mode")

if __name__ == "__main__":
    main()
