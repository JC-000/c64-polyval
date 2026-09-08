#!/usr/bin/env python3.13
"""check_publish_atomic.py -- build_release.sh must PUBLISH by rename only.

Issue #87, round-2 review. The release script writes exactly two tracked files:
docs/RELEASE_NOTES_<tag>.md and c64-polyval-<tag>.tar.gz. Both are written by
renaming a fully-built temp over them, never by copying onto them in place,
because `cp` is tearable: a process-group SIGKILL during the notes copy leaves
the file truncated, and the attestation rows sit ~98% of the way through it, so
a torn copy drops them entirely -- no placeholder tokens, no `**SHA256**` row,
nothing that says what happened. rename(2) is atomic, so each tracked file is
the old bytes or the new bytes and never a prefix of either.

That guarantee lives ONLY in the shape of those statements. An edit back to
`cp "$STAMPED" "$NOTES_REL"` reintroduces the whole class silently, and no
build, test or gate in this repo would notice -- the release still works, and
the defect is only visible if you kill it at the right microsecond. This is the
same "two places that must agree, with nothing checking they do" shape as #93
and #99, so it gets the same treatment: assert it.

TWO HALVES, because a check that only forbids is satisfiable by deletion --
the #86 / D6 distinction that this repo keeps relearning:
  1. NEGATIVE: no `cp` and no `>` redirection whose destination is $NOTES_REL
     or $OUT anywhere in the script.
  2. POSITIVE: the expected rename statements are all present. Removing a
     publish step must fail, not pass for lack of anything to object to.
"""
import re, sys
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools" / "build_release.sh"

# Destinations that name a TRACKED file. `$OUT_TMP` / `$NOTES_TMP` are scratch
# and may be written any way at all -- they are what the renames come from.
TRACKED_DESTS = ('"$NOTES_REL"', '"$OUT"')

# Renames that must exist, with how many times. A publish step that disappears
# is a defect even though nothing then violates the negative half.
REQUIRED_RENAMES = {
    'mv "$NOTES_TMP" "$NOTES_REL"': 2,   # placeholder publish + stamped publish
    'mv "$OUT_TMP" "$OUT"':         1,   # tarball publish
}


def die(msg):
    print(f"check_publish_atomic: FAIL -- {msg}", file=sys.stderr)
    sys.exit(1)


def code_lines(text):
    for i, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        yield i, line


def main():
    if not SCRIPT.is_file():
        die(f"{SCRIPT} does not exist -- the scan has nothing to check, which must not read as a pass")
    text = SCRIPT.read_text()

    violations = []
    for i, line in code_lines(text):
        # Split on whitespace but keep quoted tokens intact enough for an exact
        # match: every destination in this script is a bare "$VAR" token.
        toks = line.split()
        for dest in TRACKED_DESTS:
            if dest not in toks:
                continue
            if toks and toks[0] == "cp" and toks[-1] == dest:
                violations.append((i, line.strip(),
                                   f'`cp` writes {dest} in place -- publish by renaming a temp over it'))
            if re.search(r'>\s*' + re.escape(dest), line):
                violations.append((i, line.strip(),
                                   f'redirection writes {dest} in place -- build to a temp and rename'))

    missing = []
    for stmt, want in sorted(REQUIRED_RENAMES.items()):
        got = sum(1 for _i, line in code_lines(text) if line.strip() == stmt)
        print(f"  {stmt!r}: {got} (expected {want})")
        if got != want:
            missing.append((stmt, want, got))

    for i, line, why in violations:
        print(f"  build_release.sh:{i}: {line}\n      {why}", file=sys.stderr)
    for stmt, want, got in missing:
        print(f"  expected {want} occurrence(s) of {stmt!r}, found {got}", file=sys.stderr)

    if violations:
        die("build_release.sh writes a tracked file in place (see above). A torn write then leaves the "
            "release notes truncated with no attestation row and no placeholder token -- measured on the "
            "pre-fix script, torn in 3/3 process-group SIGKILLs (issue #87)")
    if missing:
        die("a required publish rename is missing or duplicated (see above). Either a publish step was "
            "removed -- update REQUIRED_RENAMES deliberately -- or it now writes the tracked file in a "
            "shape this scan cannot see, which is how a gate passes without checking anything (#87)")

    print("check_publish_atomic: publish is rename-only; "
          f"{sum(REQUIRED_RENAMES.values())} required rename(s) present, no in-place write to a tracked file")


if __name__ == "__main__":
    main()
