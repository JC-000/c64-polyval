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


# Repo-root variables a tool may name. build_release.sh uses REPO_ROOT, the
# python tools use ROOT; both denote this repo's root, so both are ours to
# sweep. rev-120 D6: keying on `$ROOT` alone made `"$REPO_ROOT/..."` invisible.
ROOTVAR = r'(?:ROOT|REPO_ROOT)'
# Tokens that make a name per-RUN. `$$` was the only one recognised, so
# `$RANDOM` (and $BASHPID, and a pid interpolated in python) walked past.
PERRUN = r'(?:\$\$|\$RANDOM|\$BASHPID|\$\{RANDOM\})'


def scan_text(name, text):
    """(file, line, var, prefix) for every repo-root scratch tree *text* mints.

    THE SHAPE LIST IS THE WHOLE GATE, and it is not adversary-proof -- stated
    plainly because the alternative is a gate that reads as one. Adversarial
    review (rev-120 D6) enumerated ten shapes the first three patterns missed;
    those are covered below. A scratch path minted in some ELEVENTH shape,
    under a name not in EXPECTED_SITES, is still invisible.

    Two things bound that residue. Any site this scan DOES recognise is
    prefix-checked regardless of its variable name, so a new unswept path in a
    known shape is caught without being declared anywhere. And every name in
    EXPECTED_SITES must be bound exactly once on a line this scan recognised,
    so an existing site cannot be rewritten into an unrecognised shape.

    What remains is a genuinely NEW path in a NEW shape. This is a drift
    detector, and both incidents it was built from (#93, #99) were drift.
    """
    sites, py = [], name.endswith(".py")
    for i, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"): continue

        # --- shell: mktemp -d "<root>/PREFIX.XXXX" (either quote style) -----
        m = re.search(r'mktemp\s+(?:-d|--directory)\s+["\']?\$\{?%s\}?/'
                      r'([A-Za-z0-9._-]+?)\.?X{3,}["\']?' % ROOTVAR, line)
        if m: sites.append((name, i, _assigned(line, py), m.group(1) + ".")); continue

        # --- shell: mktemp -d -p "<root>" PREFIX.XXXX ----------------------
        m = re.search(r'mktemp\s+(?:[^\n]*?\s)?(?:-p|--tmpdir=?)\s*["\']?\$\{?%s\}?["\']?\s+'
                      r'["\']?([A-Za-z0-9._-]+?)\.?X{3,}["\']?' % ROOTVAR, line)
        if m: sites.append((name, i, _assigned(line, py), m.group(1) + ".")); continue

        # --- python: mkdtemp / TemporaryDirectory, kwargs in either order ---
        if re.search(r'(?:mkdtemp|TemporaryDirectory)\s*\(', line) and \
           re.search(r'dir\s*=\s*str\(ROOT\)|dir\s*=\s*ROOT\b', line):
            mp = re.search(r'prefix\s*=\s*"([^"]+)"', line)
            sites.append((name, i, _assigned(line, py), mp.group(1) if mp else ""))
            continue

        # --- python: ROOT / f"prefix.{...}" --------------------------------
        m = re.search(r'ROOT\s*/\s*f?"([^"/{]*)\{', line)
        if m: sites.append((name, i, _assigned(line, py), m.group(1))); continue

        # --- shell: hand-rolled per-run path, repo-root-relative ------------
        # Quoted or bare, with or without a leading './'. A '/' elsewhere means
        # it lives somewhere else and is not ours to sweep. The sweepable
        # prefix is the literal text before the first '$'.
        m = re.match(r'\s*(?:export\s+|local\s+|readonly\s+|declare\s+|typeset\s+)?'
                     r'([A-Za-z_]\w*)=("?)(?:\./)?([^"/\s]*%s[^"/\s]*)\2\s*(?:#.*)?$'
                     % PERRUN, line)
        if m:
            sites.append((name, i, m.group(1), m.group(3).split("$", 1)[0]))
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
    n = re.escape(name)
    if py:
        pats = [re.compile(r"^\s*%s\s*=(?!=)" % n)]
    else:
        # rev-120 N2 enumerated six shell shapes the first cut missed, each
        # verified to rebind the variable while the gate stayed green:
        # declare/typeset, printf -v, read, eval, and the := default.
        pats = [
            re.compile(r"^\s*(?:export\s+|local\s+|readonly\s+|declare\s+|typeset\s+)?%s=" % n),
            re.compile(r"\bprintf\b[^\n]*?\s-v\s+%s\b" % n),
            re.compile(r"\bread\b[^\n#]*\b%s\b" % n),
            re.compile(r"\beval\b[^\n#]*\b%s=" % n),
            re.compile(r":\s*\$\{%s:?=" % n),
            re.compile(r"\bmapfile\b[^\n#]*\b%s\b|\breadarray\b[^\n#]*\b%s\b" % (n, n)),
        ]
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"): continue
        if any(p.search(line) if p.pattern[0] != "^" else p.match(line) for p in pats):
            out.append(i)
    return out


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
    # --- shapes added for rev-120 D6; one fixture per pattern, so a narrowed
    # --- pattern names itself rather than hiding behind a working sibling.
    ("selftest.sh",
     'SELFTEST_P=%s(mktemp -d -p "%s%s" unswept-selftest.XXXXXX)\n' % (_D, _D, _R),
     "SELFTEST_P", "unswept-selftest."),
    ("selftest.sh",
     'SELFTEST_L=%s(mktemp --directory "%s%s/unswept-selftest.XXXXXX")\n' % (_D, _D, _R),
     "SELFTEST_L", "unswept-selftest."),
    ("selftest.sh",
     'SELFTEST_R=%s(mktemp -d "%sREPO_ROOT/unswept-selftest.XXXXXX")\n' % (_D, _D),
     "SELFTEST_R", "unswept-selftest."),
    ("selftest.sh",
     'SELFTEST_U=unswept-selftest.%s%s.tmp\n' % (_D, _D),
     "SELFTEST_U", "unswept-selftest."),
    ("selftest.sh",
     'SELFTEST_DOT="./unswept-selftest.%s%s.tmp"\n' % (_D, _D),
     "SELFTEST_DOT", "unswept-selftest."),
    ("selftest.sh",
     'SELFTEST_RND="unswept-selftest.%sRANDOM"\n' % _D,
     "SELFTEST_RND", "unswept-selftest."),
    ("selftest.py",
     'td = tempfile.TemporaryDirectory(prefix="unswept-selftest.", dir=str(%s))\n' % _R,
     "td", "unswept-selftest."),
    ("selftest.py",
     'rd = Path(tempfile.mkdtemp(dir=str(%s), prefix="unswept-selftest."))\n' % _R,
     "rd", "unswept-selftest."),
]

# rev-120 N2: six shell shapes that REBIND a variable, each verified to keep
# the gate green before assignments() was extended. One control arm each, for
# the same reason as above.
_N = "SELFTEST_BIND"
ASSIGN_FIXTURES = [
    ('plain',      '%s="x.%s%s"' % (_N, _D, _D)),
    ('export',     'export %s="x"' % _N),
    ('declare',    'declare %s="x"' % _N),
    ('typeset',    'typeset %s="x"' % _N),
    ('printf -v',  'printf -v %s "%%s" "x"' % _N),
    ('read',       'read %s <<< "x"' % _N),
    ('eval',       'eval "%s=x"' % _N),
    (':= default', ': %s{%s:=x}' % (_D, _N)),
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

    # Every binding shape must be seen by assignments(), or a rebinding in that
    # shape silently points the real scratch path somewhere unswept.
    if not ASSIGN_FIXTURES:
        die("the assignment-shape corpus is empty -- a positive control that asserts nothing "
            "certifies nothing")
    for label, line in ASSIGN_FIXTURES:
        if _N not in line:
            die(f"POSITIVE CONTROL FAILED: the {label} fixture did not reconstruct a binding of "
                f"{_N} -- a runtime split has stopped producing the shape it must test")
        if assignments(_N, line + "\n", False) != [1]:
            die(f"POSITIVE CONTROL FAILED: assignments() did not see the {label} binding "
                f"`{line}`. A rebinding in that shape would point the real scratch path "
                f"somewhere unswept while every name check below still passed (#107 round 2)")
    # and it must not see a binding that is not there
    if assignments(_N, 'echo "%s is not bound here"\n' % _N, False):
        die("NEGATIVE CONTROL FAILED: assignments() reported a binding in a line that only "
            "mentions the name -- it would refuse every correct script")

    return len(SELFTEST_FIXTURES) + len(ASSIGN_FIXTURES)


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
