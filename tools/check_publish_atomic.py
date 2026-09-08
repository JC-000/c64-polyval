#!/usr/bin/env python3.13
"""check_publish_atomic.py -- build_release.sh must PUBLISH by rename only.

Issue #87. The release script writes exactly two tracked files,
docs/RELEASE_NOTES_<tag>.md ($NOTES_REL) and c64-polyval-<tag>.tar.gz ($OUT).
Both are written by renaming a finished temp over them, never by writing them
in place, because an in-place write is TEARABLE: sampling the tracked notes
every 0.5 ms during a successful run of the pre-fix script shows sizes
[0, 19215077, 19215113] -- the file is transiently 0 bytes on every run, and a
kill there leaves it truncated past its Attestation table, so it carries no
size, no SHA256 and no placeholder token to say what happened. rename(2) is
atomic: the tracked file is the old bytes or the new bytes, never a prefix.

That guarantee lives only in the shape of those statements, and no build, test
or other gate in this repo can observe it -- an edit back to an in-place write
still produces a working release.

WHY THIS IS A WHITELIST, NOT A LIST OF FORBIDDEN COMMANDS. The first cut
forbade `cp X "$NOTES_REL"` and `> "$NOTES_REL"` by literal token. Round-3
review walked through it six ways in one line each, all exit 0:

    cp "$STAMPED" "${NOTES_REL}"          # braces
    cp "$STAMPED" $NOTES_REL              # unquoted
    DEST="$NOTES_REL"; cp "$STAMPED" "$DEST"
    install -m 644 "$STAMPED" "$NOTES_REL"
    tee "$NOTES_REL" < "$STAMPED"
    python3 - "$NOTES_REL" <<'PY' ... write_text ...   # the PRE-#87 STAMPER

The last one was built and measured: the gate printed "no in-place write to a
tracked file", exit 0, for a script that truncated the tracked notes to 0 bytes
on every run. A gate reporting a property it does not check is the defect this
whole branch exists to remove, so the polarity is inverted here. EVERY mention
of these two variables must match an explicitly allowed shape, with a stated
reason. A new command, a new quoting style, a new interpreter -- anything not
on the list -- fails by default.

The interpreter case is the sharp one, because a heredoc can do anything with
what it is handed. The script therefore passes the working-tree path to python
only behind a `--label` sentinel, and this file additionally reads the heredoc
body and refuses if the label is opened.
"""
import re, sys
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools" / "build_release.sh"

# A mention of the tracked-file variables: $NOTES_REL, ${NOTES_REL}, $OUT,
# ${OUT}. The negative lookahead keeps $OUT_TMP / $NOTES_TMP out -- those are
# the scratch temps, and may be written any way at all.
MENTION = re.compile(r'\$\{?(?:NOTES_REL|OUT)\}?(?![A-Za-z0-9_])')

# The staged copy under $STAGE_ROOT is a DIFFERENT FILE (inside the staging
# area) that merely shares the path suffix. Erase those spellings before
# looking for mentions of the tracked ones.
STAGED = re.compile(r'"\$STAGE_ROOT/\$NOTES_REL"')

# Optional `--` end-of-options, and any run of spaces, tolerated everywhere:
# `mv -- "$NOTES_TMP"  "$NOTES_REL"` is the same publish. Strictness belongs on
# the negative half, where the guarantee lives; on this half it only produces
# false positives on reformatting (round-3 review, D12).
def rename_re(src, dst):
    return re.compile(r'^mv(\s+--)?\s+"\$%s"\s+"\$%s"\s*$' % (src, dst))

REQUIRED_RENAMES = {
    'mv "$NOTES_TMP" -> "$NOTES_REL"': (rename_re("NOTES_TMP", "NOTES_REL"), 2),
    'mv "$OUT_TMP" -> "$OUT"':         (rename_re("OUT_TMP", "OUT"), 1),
}

# Every allowed way for a line to mention $NOTES_REL / $OUT, with its reason.
# Anything else is a violation.
ALLOWED = [
    (re.compile(r'^(NOTES_REL|OUT)="[^"]*"\s*$'),
     "assignment of the path itself"),
    (re.compile(r'^(if\s+|elif\s+)?\[\[ .* \]\]\s*(;\s*then)?\s*(\\)?\s*$'),
     "shell test, reads only"),
    (re.compile(r'^(&&\s+)?grep\b(?![^|]*>)'),
     "grep, reads only"),
    (re.compile(r'^(echo|printf)\b(?![^|]*>\s*["$])'),
     "diagnostic output, no redirection into the tracked path"),
    (re.compile(r'^RELEASE_DATE="\$\(grep\b'),
     "grep in a command substitution, reads only"),
    (re.compile(r'^\s*docs/precalc-tables\.md "\$NOTES_REL"\s*$'),
     "element of the STAGED_PATHSPECS array, passed to git as a pathspec"),
    (re.compile(r'^cp\s+(--\s+)?"\$NOTES_REL"\s+\S.*$'),
     "cp with the tracked file as SOURCE (destination is a temp/staged path)"),
    (rename_re("NOTES_TMP", "NOTES_REL"), "publish rename"),
    (rename_re("OUT_TMP", "OUT"), "publish rename"),
    (re.compile(r'^python3 - .*--label "\$NOTES_REL" <<\'PY\'\s*$'),
     "working-tree path handed to python behind the --label sentinel"),
]

# In a heredoc that received a --label, the label must not be opened.
LABEL_OPENED = re.compile(r'(pathlib\.Path|Path|open)\(\s*shown\b|\bshown\s*\.\s*(write|open)')


def die(msg):
    print(f"check_publish_atomic: FAIL -- {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    if not SCRIPT.is_file():
        die(f"{SCRIPT} does not exist -- an empty scan must not read as a pass")
    raw = SCRIPT.read_text().splitlines()

    violations = []
    counts = {k: 0 for k in REQUIRED_RENAMES}
    labelled_heredocs = 0
    in_heredoc = None            # line number of the `<<'PY'` that opened it
    heredoc_labelled = False

    for i, line in enumerate(raw, 1):
        stripped = line.strip()

        if in_heredoc is not None:
            if stripped == "PY":
                in_heredoc = None
                heredoc_labelled = False
            elif heredoc_labelled and LABEL_OPENED.search(line):
                violations.append((i, stripped,
                                   "the --label diagnostic string is opened inside the heredoc; "
                                   "a label must never become a path"))
            continue

        if stripped.startswith("#") or not stripped:
            continue

        for name, (pat, _want) in REQUIRED_RENAMES.items():
            if pat.match(stripped):
                counts[name] += 1

        probe = STAGED.sub("", stripped)
        if MENTION.search(probe):
            if not any(pat.search(stripped) for pat, _why in ALLOWED):
                violations.append((i, stripped,
                                   "mentions a tracked-file variable in a shape that is not an allowed "
                                   "read or the publish rename -- if this writes the file, publish by "
                                   "renaming a finished temp over it instead"))

        if stripped.endswith("<<'PY'"):
            in_heredoc = i
            heredoc_labelled = "--label" in stripped
            if heredoc_labelled:
                labelled_heredocs += 1

    if in_heredoc is not None:
        die(f"unterminated heredoc opened at line {in_heredoc} -- the scan cannot see the whole script, "
            "and a partial scan must not read as a pass")

    missing = [(n, w, counts[n]) for n, (_p, w) in REQUIRED_RENAMES.items() if counts[n] != w]

    for i, line, why in violations:
        print(f"  build_release.sh:{i}: {line}\n      {why}", file=sys.stderr)
    for name, want, got in missing:
        print(f"  expected {want} occurrence(s) of `{name}`, found {got}", file=sys.stderr)

    if violations:
        die("build_release.sh may write a tracked file other than by renaming a temp over it (see above). "
            "An in-place write is tearable: the pre-#87 stamper truncated the tracked notes to 0 bytes on "
            "every run, so a kill there left them with no Attestation and no placeholder token (issue #87)")
    if missing:
        die("a required publish rename is missing or duplicated (see above). Either a publish step was "
            "removed -- update REQUIRED_RENAMES deliberately -- or it now writes the tracked file in a "
            "shape this scan cannot see, which is how a gate passes without checking anything (#87)")

    total = sum(w for _p, w in REQUIRED_RENAMES.values())
    print(f"check_publish_atomic: scanned every mention of $NOTES_REL/$OUT in build_release.sh; "
          f"each matched an allowed read or a publish rename, {total} required rename(s) present, "
          f"{labelled_heredocs} labelled heredoc(s) do not open the label")


if __name__ == "__main__":
    main()
