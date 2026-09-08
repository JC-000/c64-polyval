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

def die(msg):
    print(f"check_scratch_prefix: FAIL -- {msg}", file=sys.stderr); sys.exit(1)

def swept_patterns():
    m = re.search(r"^SCRATCH_TREES\s*=\s*(.+)$", MK.read_text(), re.M)
    if not m: die("no SCRATCH_TREES assignment in the Makefile -- `make clean` sweeps no scratch tree at all")
    pats = m.group(1).split()
    if not pats: die("SCRATCH_TREES is empty")
    return pats

def minting_sites():
    """(file, line, prefix) for every scratch tree tools/ creates in the repo root."""
    sites = []
    for f in sorted((ROOT/"tools").glob("*")):
        if not f.is_file() or f.suffix not in (".py",".sh"): continue
        for i, line in enumerate(f.read_text().splitlines(), 1):
            if line.lstrip().startswith("#"): continue
            m = re.search(r'mktemp\s+-d\s+"\$ROOT/([A-Za-z0-9._-]+?)\.?X{3,}"', line)
            if m: sites.append((f.name, i, m.group(1) + ".")); continue
            m = re.search(r'mkdtemp\(\s*prefix\s*=\s*"([^"]+)"\s*,\s*dir\s*=\s*str\(ROOT\)', line)
            if m: sites.append((f.name, i, m.group(1))); continue
            # Hand-rolled `VAR="...$$..."` scratch path, repo-root-relative
            # (a '/' means it is somewhere else and not ours to sweep).
            m = re.match(r'\s*[A-Za-z_]\w*="([^"/]*\$\$[^"/]*)"\s*(?:#.*)?$', line)
            if m:
                literal = m.group(1)
                sites.append((f.name, i, literal.split("$", 1)[0]))
    return sites

def covered(prefix, pats):
    for p in pats:
        if p.endswith("*") and prefix.startswith(p[:-1]): return True
        if p == prefix.rstrip("."): return True
    return False

def main():
    pats  = swept_patterns()
    sites = minting_sites()
    if not sites:
        die("found no mktemp/mkdtemp scratch-tree site in tools/ -- either the scan broke or a tool stopped "
            "using one; an empty result must not read as 'all covered'")
    bad = [(f,i,p) for f,i,p in sites if not covered(p, pats)]
    for f,i,p in sites:
        print(f"  {f}:{i} mints {p or '<no literal prefix>'}*  "
              f"{'swept' if covered(p,pats) else 'NOT SWEPT'}")
    if bad:
        die(f"{len(bad)} scratch prefix(es) are minted but not in SCRATCH_TREES ({' '.join(pats)}) -- "
            f"a run killed with SIGKILL would leave a tree nothing removes")
    print(f"check_scratch_prefix: {len(sites)} minting site(s), all swept by SCRATCH_TREES ({' '.join(pats)})")

if __name__ == "__main__":
    main()
