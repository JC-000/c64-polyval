#!/usr/bin/env python3.13
"""check_scratch_prefix.py -- every scratch tree a tool mints must be one
`make clean` sweeps.

Issue #93's fix created this need and then fell into it. Giving the scratch
trees per-run names made the literal `build-knobcheck` in the Makefile's
SCRATCH_TREES match nothing, so a run killed with SIGKILL -- which no trap can
catch -- left a tree nothing would ever remove. Adversarial review caught it;
nothing in the repo would have.

The same shape as #99, where .gitignore enumerated `build/` and
`build-knobcheck/` by name and `build-short/` was neither ignored nor cleaned.
Both are one class: TWO PLACES THAT MUST AGREE, WITH NOTHING CHECKING THEY DO.

So this asserts the agreement instead of documenting it: every mktemp /
mkdtemp call in tools/ must mint under a prefix that SCRATCH_TREES sweeps.
It is a source scan, which cannot see a tree minted by some other means -- but
it catches the drift that actually happened, twice.

THIRD SHAPE, added for #87: a repo-root scratch path built by hand from `$$`
rather than by mktemp -- `VAR=".${OUT}.tmp.$$"` is how build_release.sh's first
cut named its temp tarball. It is the same defect (SIGKILL leaves it, `make
clean` does not match it) and this scan was structurally blind to it, printing
"all swept" while the file it could not see went unswept. The prefix such a
name can be swept by is the LITERAL text before its first `$`: everything after
is a runtime value, so a pattern can only key on what comes before. A name that
begins with a variable expansion therefore has prefix "" and can never be
covered, which is the correct answer -- it is unsweepable by construction.
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MK   = ROOT / "Makefile"

# How many scratch-minting sites each file is KNOWN to have.
#
# Round-2 review of #87 broke the gate without tripping it: replacing
# build_release.sh's `OUT_TMP=` line with an unquoted assignment, with a
# `$(date +%s)` name, or with a `mktemp "$REPO_ROOT/..."` call each made the
# scan stop recognising the site, and the gate then reported "2 minting
# site(s), all swept" and exited 0. The site count dropped 3 -> 2 and nothing
# asserted otherwise. The pre-existing zero-sites guard covers ABSENCE, not a
# DECREASE -- the same distinction as issue #86, and the shape this repo keeps
# shipping: a check satisfied by not seeing the thing it must check.
#
# So the expected sites are named. This IS a hand-maintained list, the drift
# class this repo dislikes -- but it drifts in the SAFE direction: adding a
# site is fine (the test is >=), and removing or disguising one is exactly what
# must not pass silently. Update it deliberately when a tool stops minting.
# ISSUE #107 CHANGED THIS FROM COUNTS TO NAMES. It used to be a per-file
# count, and a count is restorable by a DECOY: disguise the real site into a
# shape the scan cannot see, add a swept-looking one beside it, and the total
# is unchanged --
#     OUT_TMP="$(mktemp "$REPO_ROOT/unswept-c.XXXXXX")"   # real, unswept, unseen
#     DECOY_TMP="build-scratch.decoy.$$.txt"              # swept-looking, seen
# -- "4 minting site(s), all swept", exit 0, while the real temp tarball was
# neither swept nor seen. Keying on the VARIABLE NAME makes a disguised site a
# missing NAME, which no decoy under a different name can restore.
#
# Still a hand-maintained list, and still drifting in the SAFE direction:
# adding a site is fine, removing or disguising an expected one is exactly what
# must not pass silently. Update it deliberately when a tool stops minting.
EXPECTED_SITES = {
    "build_release.sh":        {"OUT_TMP", "NOTES_TMP"},
    "check_footprints.py":     {"bd"},
    "check_knob_staleness.sh": {"SCRATCH"},
}

def die(msg):
    print(f"check_scratch_prefix: FAIL -- {msg}", file=sys.stderr); sys.exit(1)

def swept_patterns():
    m = re.search(r"^SCRATCH_TREES\s*=\s*(.+)$", MK.read_text(), re.M)
    if not m: die("no SCRATCH_TREES assignment in the Makefile -- `make clean` sweeps no scratch tree at all")
    pats = m.group(1).split()
    if not pats: die("SCRATCH_TREES is empty")
    return pats

# The variable a minting line assigns to. `None` when the line mints without
# binding a name -- such a site can satisfy no expectation, which is the safe
# answer: it is exactly as invisible as a disguised one.
ASSIGN_SH = re.compile(r'\s*([A-Za-z_]\w*)=')
ASSIGN_PY = re.compile(r'\s*([A-Za-z_]\w*)\s*=')


def _assigned(line, py):
    m = (ASSIGN_PY if py else ASSIGN_SH).match(line)
    return m.group(1) if m else None


def scan_text(name, text):
    """(file, line, var, prefix) for every repo-root scratch tree *text* mints."""
    sites, py = [], name.endswith(".py")
    for i, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"): continue
        m = re.search(r'mktemp\s+-d\s+"\$ROOT/([A-Za-z0-9._-]+?)\.?X{3,}"', line)
        if m: sites.append((name, i, _assigned(line, py), m.group(1) + ".")); continue
        m = re.search(r'mkdtemp\(\s*prefix\s*=\s*"([^"]+)"\s*,\s*dir\s*=\s*str\(ROOT\)', line)
        if m: sites.append((name, i, _assigned(line, py), m.group(1))); continue
        # Hand-rolled `VAR="...$$..."` scratch path, repo-root-relative
        # (a '/' means it is somewhere else and not ours to sweep).
        m = re.match(r'\s*([A-Za-z_]\w*)="([^"/]*\$\$[^"/]*)"\s*(?:#.*)?$', line)
        if m:
            sites.append((name, i, m.group(1), m.group(2).split("$", 1)[0]))
    return sites


def assignments(name, text, py):
    """Every line that BINDS *name*, in any shape at all.

    Deliberately broad and independent of the three minting-shape regexes
    above. That independence is the point: it is what lets this see a binding
    the minting scan cannot.

    #107 ROUND 2. Keying the expectation on the variable NAME was not enough,
    and the first fix's claim -- "a count is restorable by a decoy, a name is
    not" -- was FALSE. A decoy under the SAME name restores it:

        OUT_TMP="build-scratch.decoy.$$.txt"                  <- swept, seen
        OUT_TMP=$(printf %s "unswept-real.$RANDOM.tar.gz")    <- real, unseen

    Measured: "6 minting site(s), all swept ... 3 positive control(s) fired",
    exit 0, while the real temp tarball was neither swept nor seen. The name
    was present, so the name check passed; the LAST binding is what the script
    actually uses, and it was invisible.

    So the invariant is no longer "the name appears" but "the name is bound
    EXACTLY ONCE, and that binding is a minting site the scan recognised". A
    rebinding in any shape -- seen or unseen -- now has to be deliberate.
    """
    pat = (re.compile(r"^\s*%s\s*=(?!=)" % re.escape(name)) if py
           else re.compile(r"^\s*(?:export\s+|local\s+|readonly\s+)?%s=" % re.escape(name)))
    return [i for i, line in enumerate(text.splitlines(), 1)
            if not line.lstrip().startswith("#") and pat.match(line)]


def minting_sites():
    """(file, line, var, prefix) for every scratch tree tools/ creates in the repo root."""
    sites = []
    for f in sorted((ROOT/"tools").glob("*")):
        if not f.is_file() or f.suffix not in (".py",".sh"): continue
        sites.extend(scan_text(f.name, f.read_text()))
    return sites

def covered(prefix, pats):
    for p in pats:
        if p.endswith("*") and prefix.startswith(p[:-1]): return True
        if p == prefix.rstrip("."): return True
    return False

# Positive control. Each fixture is a synthetic tool file that MUST produce a
# site the scan sees, with the variable name and prefix given. Without this,
# every green is equally consistent with a scanner whose regexes match nothing
# -- and the three minting shapes below are precisely what round-2 review broke
# by rewriting a site into a shape the scan could not see.
# ASSEMBLED AT RUNTIME, NOT WRITTEN OUT. This file lives in tools/, so the real
# scan reads it too -- fixtures written literally here would be found as
# genuine minting sites and reported NOT SWEPT (measured while writing this).
# Splitting the giveaway tokens keeps this file clean to the scanner while the
# constructed strings are byte-for-byte the shapes it must recognise. The
# assertions below would fail loudly if a split ever stopped reconstructing
# them, so this cannot rot into a fixture that tests nothing.
_D, _R = "$", "ROOT"
SELFTEST_FIXTURES = [
    ("selftest.sh",
     'SELFTEST_TMP="unswept-selftest.%s%s.tar.gz"\n' % (_D, _D),
     "SELFTEST_TMP", "unswept-selftest."),
    ("selftest.sh",
     'SELFTEST_DIR=%s(mktemp -d "%s%s/unswept-selftest.XXXXXX")\n' % (_D, _D, _R),
     "SELFTEST_DIR", "unswept-selftest."),
    ("selftest.py",
     'sd = Path(tempfile.mkdtemp(prefix="unswept-selftest.", dir=str(%s)))\n' % _R,
     "sd", "unswept-selftest."),
]


def selftest(pats):
    """Prove the scanner still sees each minting shape, and still calls an
    unswept prefix unswept. Runs on every invocation; the green line says so."""
    if not SELFTEST_FIXTURES:
        die("the self-test corpus is empty -- a positive control that asserts nothing certifies nothing")
    for name, text, want_var, want_prefix in SELFTEST_FIXTURES:
        found = scan_text(name, text)
        if not found:
            die(f"POSITIVE CONTROL FAILED: the scan did not see the minting site in `{text.strip()}`. "
                "A minting shape stopped being recognised, which is how this gate reports 'all swept' "
                "about a file it never looked at (#87 round-2 review, D6)")
        _f, _i, var, prefix = found[0]
        if var != want_var:
            die(f"POSITIVE CONTROL FAILED: expected the site to bind `{want_var}`, scan bound `{var}`. "
                "Name-keying is what makes a disguised site a missing NAME rather than a restorable "
                "count (issue #107)")
        if covered(prefix, pats):
            die(f"POSITIVE CONTROL FAILED: `{prefix}*` is an unswept prefix but covered() called it "
                f"swept against SCRATCH_TREES ({' '.join(pats)}). The coverage test is dead, so "
                "'all swept' below means nothing")
    return len(SELFTEST_FIXTURES)


def main():
    pats  = swept_patterns()
    controls = selftest(pats)
    sites = minting_sites()
    if not sites:
        die("found no mktemp/mkdtemp scratch-tree site in tools/ -- either the scan broke or a tool stopped "
            "using one; an empty result must not read as 'all covered'")

    # A site the scan can no longer SEE is indistinguishable from a site that
    # is swept, and the failure is silent in the direction that matters. Keyed
    # on NAMES since #107: a decoy site under a different name no longer
    # restores a disguised one.
    seen = {}
    for f, _i, var, _p in sites:
        if var is not None:
            seen.setdefault(f, set()).add(var)
    missing = [(f, sorted(want - seen.get(f, set())))
               for f, want in sorted(EXPECTED_SITES.items())
               if want - seen.get(f, set())]
    if missing:
        for f, gone in missing:
            print(f"  {f}: expected scratch-minting site(s) bound to {', '.join(gone)}; the scan found "
                  f"{', '.join(sorted(seen.get(f, set()))) or '<none>'}", file=sys.stderr)
        die("a scratch-minting site went MISSING from the scan (see above). Either the tool stopped minting "
            "-- update EXPECTED_SITES deliberately -- or it now mints in a shape this scan cannot see, which "
            "is how this gate passes without ever looking at the file it must sweep (#87 round-2 review, D6). "
            "A site under a NEW name does not substitute for a missing one (#107)")
    # #107 round 2: every expected name must be bound EXACTLY ONCE, and that
    # binding must be the minting site the scan saw. A same-name decoy binds it
    # twice; the original #107 attack binds it once in a shape the scan cannot
    # see. Both are caught here, and this scan is independent of the three
    # minting-shape regexes, so it does not shrink when they do.
    for fname, want in sorted(EXPECTED_SITES.items()):
        fp = ROOT/"tools"/fname
        if not fp.is_file():
            die(f"{fname} is named in EXPECTED_SITES but does not exist -- update it deliberately")
        text, py = fp.read_text(), fname.endswith(".py")
        seen_lines = {(v, i) for f, i, v, _p in sites if f == fname}
        for var in sorted(want):
            binds = assignments(var, text, py)
            if len(binds) != 1:
                die(f"{fname}: `{var}` is bound on {len(binds)} line(s) {binds}, expected exactly 1. "
                    f"The LAST binding is the one the script uses, so a second one -- in any shape, "
                    f"seen by this scan or not -- can point the real scratch path somewhere "
                    f"unswept while the first keeps this gate green (#107 round 2)")
            if (var, binds[0]) not in seen_lines:
                die(f"{fname}:{binds[0]}: `{var}` is bound here, but this scan did not recognise "
                    f"that line as a scratch-minting site. Either it stopped minting -- update "
                    f"EXPECTED_SITES deliberately -- or it now mints in a shape this scan cannot "
                    f"see, which is exactly how a gate reports 'all swept' about a path it never "
                    f"looked at (#87 round-2 review D6, #107)")

    bad = [(f,i,p) for f,i,_v,p in sites if not covered(p, pats)]
    for f,i,var,p in sites:
        print(f"  {f}:{i} {var or '<unbound>'} mints {p or '<no literal prefix>'}*  "
              f"{'swept' if covered(p,pats) else 'NOT SWEPT'}")
    if bad:
        die(f"{len(bad)} scratch prefix(es) are minted but not in SCRATCH_TREES ({' '.join(pats)}) -- "
            f"a run killed with SIGKILL would leave a tree nothing removes")
    print(f"check_scratch_prefix: {len(sites)} minting site(s), all swept by SCRATCH_TREES "
          f"({' '.join(pats)}), {controls} positive control(s) fired")

if __name__ == "__main__":
    main()
