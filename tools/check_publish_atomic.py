#!/usr/bin/env python3.13
"""check_publish_atomic.py -- build_release.sh must PUBLISH by rename only.

Issue #87. The release script writes exactly two tracked files,
docs/RELEASE_NOTES_<tag>.md ($NOTES_REL) and c64-polyval-<tag>.tar.gz ($OUT).
Both are written by renaming a finished temp over them, never in place, because
an in-place write is TEARABLE: sampling the tracked notes every 0.5 ms during a
successful run of the pre-fix script gives sizes [0, 19215077, 19215113] -- the
file is transiently 0 bytes on EVERY run, and a kill there leaves it truncated
past its Attestation table, carrying no size, no SHA256 and no placeholder
token to say what happened. rename(2) is atomic: the tracked file is the old
bytes or the new bytes, never a prefix.

No build, test or other gate in this repo can observe that property -- an edit
back to an in-place write still produces a working release -- so it is asserted
here.

WHY A WHITELIST, AND WHY OVER SIMPLE COMMANDS. Successive reviews walked
through weaker versions of this file one line at a time, renames intact, exit
0 every time:

  round 3, against a list of two forbidden literals:
    cp "$STAMPED" "${NOTES_REL}" / $NOTES_REL / via DEST=... / install /
    tee / python3 - "$NOTES_REL" <<'PY' ... write_text   <- the PRE-#87 STAMPER
  round 5, against a whitelist matched with search() on the whole line:
    grep -q SHA256 "$NOTES_REL" && cp "$STAMPED" "$NOTES_REL"
    echo "publishing"           && cp "$STAMPED" "$NOTES_REL"
    cp "$NOTES_REL" "$NOTES_TMP" && cp "$STAMPED" "$NOTES_REL"
  -- an allowed READ as the prefix, the write laundered into the suffix.

So: each line is split into simple commands at unquoted `&&`, `||`, `;` and
`|`, and EVERY segment that mentions a tracked variable must FULLY match one of
the allowed shapes below. A prefix match is not enough, a new command is not
allowed by default, and a redirection into a tracked path is refused outright.

Heredoc BODIES are scanned for mentions too. They are `<<'PY'` (quoted, no
expansion) so a mention there is inert today -- but changing the opener to
`<<PY` would expand it, and that must not be a silent hole.

THE INTERPRETER CASE, and why there is no sentinel any more. Round 4 let python
receive the working-tree path behind a `--label` marker and policed the heredoc
body for opens of the variable named `shown`; round 5 defeated that by renaming
the variable. The claimed property was really "no textually `shown`-named
open". The script now simply never hands a tracked path to an interpreter -- the
heredocs get the staged copy, and the shell names the file in the diagnostic
after python exits. Nothing is in scope to open, so nothing has to be policed.

THE COST, PAID DELIBERATELY (round-5 review, D15). This whitelist has real
false positives, and they are the point rather than a bug:

    PUBSHA=$(shasum -a 256 "$OUT" | cut -d' ' -f1)     # RED
    test -s "$NOTES_REL" || exit 1                     # RED

Both are harmless reads. A future step that verifies the PUBLISHED artifact --
re-hashing $OUT after the rename, say -- will go red and must add its shape to
ALLOWED, with a reason, in the same commit. That is the price of a gate that
cannot be walked past by inventing a command name, and it is cheaper than the
alternative this file has now been through five rounds of: a check that prints
a property it does not enforce. If you are here because a legitimate read went
red, you are paying the price knowingly -- add the shape, do not loosen the
matcher.
"""
import re, sys
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools" / "build_release.sh"

# A mention of the tracked-file variables, in any spelling. The negative
# lookahead keeps $OUT_TMP / $NOTES_TMP out: those are the scratch temps and
# may be written any way at all.
MENTION = re.compile(r'\$\{?(?:NOTES_REL|OUT)\}?(?![A-Za-z0-9_])')

# The staged copy under $STAGE_ROOT is a DIFFERENT FILE that merely shares the
# path suffix. Erase that spelling before looking for mentions.
STAGED = re.compile(r'"\$STAGE_ROOT/\$NOTES_REL"')

# Any redirection whose target is a tracked path, checked before the whitelist
# so no allowed shape can carry one.
REDIRECT = re.compile(r'>>?\s*(?:"\$\{?(?:NOTES_REL|OUT)\}?"|\$\{?(?:NOTES_REL|OUT)\}?)(?![A-Za-z0-9_])')


def rename_re(src, dst):
    """`mv -- "$A"  "$B"` -- any run of whitespace, optional end-of-options.

    Strictness belongs on the negative half, where the guarantee lives. Here it
    only produces false positives on reformatting (round-3 review, D12).
    """
    return re.compile(r'mv(\s+--)?\s+"\$%s"\s+"\$%s"' % (src, dst))


REQUIRED_RENAMES = {
    'mv "$NOTES_TMP" -> "$NOTES_REL"': (rename_re("NOTES_TMP", "NOTES_REL"), 2),
    'mv "$OUT_TMP" -> "$OUT"':         (rename_re("OUT_TMP", "OUT"), 1),
}

# Every allowed way for a SIMPLE COMMAND to mention $NOTES_REL / $OUT, with its
# reason. Matched with fullmatch against the segment. Anything else fails.
ALLOWED = [
    (r'(NOTES_REL|OUT)="[^"]*"',
     "assignment of the path itself"),
    (r'(if\s+|elif\s+|while\s+)?\[\[ .* \]\](\s*\\)?',
     "shell test, reads only (a trailing \\ continues into the next line)"),
    (r'grep\s[^>]*',
     "grep, reads only"),
    (r'RELEASE_DATE="\$\(grep\s[^>]*\)"',
     "grep in a command substitution, reads only"),
    (r'(echo|printf)\s.*',
     "diagnostic output (a redirection into a tracked path is refused above)"),
    (r'docs/precalc-tables\.md "\$NOTES_REL"',
     "element of the STAGED_PATHSPECS array, passed to git as a pathspec"),
    (r'cp(\s+--)?\s+"\$NOTES_REL"\s+\S.*',
     "cp with the tracked file as SOURCE (destination is a temp or staged path)"),
    (r'mv(\s+--)?\s+"\$NOTES_TMP"\s+"\$NOTES_REL"',
     "publish rename"),
    (r'mv(\s+--)?\s+"\$OUT_TMP"\s+"\$OUT"',
     "publish rename"),
]
ALLOWED = [(re.compile(p), why) for p, why in ALLOWED]


def die(msg):
    print(f"check_publish_atomic: FAIL -- {msg}", file=sys.stderr)
    sys.exit(1)


def segments(line):
    """Split a shell line into simple commands at UNQUOTED && || ; | operators.

    Quote tracking is what makes this usable here: the script's diagnostics
    contain `&&` inside double quotes (the `git checkout ... && make dist`
    remedy line), and a naive split would tear them apart and then fail to
    match the echo shape.
    """
    out, buf, i = [], [], 0
    sq = dq = False
    depth = 0                      # inside [[ ... ]], where && is part of the test
    while i < len(line):
        c = line[i]
        if c == "'" and not dq:
            sq = not sq
        elif c == '"' and not sq:
            dq = not dq
        if not sq and not dq:
            if line.startswith("[[", i):
                depth += 1
            elif line.startswith("]]", i):
                depth = max(0, depth - 1)
        if not sq and not dq and depth == 0:
            if line.startswith("&&", i) or line.startswith("||", i):
                out.append("".join(buf)); buf = []; i += 2; continue
            if c in ";|":
                out.append("".join(buf)); buf = []; i += 1; continue
        buf.append(c)
        i += 1
    out.append("".join(buf))
    return [s.strip() for s in out if s.strip()]


def main():
    if not SCRIPT.is_file():
        die(f"{SCRIPT} does not exist -- an empty scan must not read as a pass")
    raw = SCRIPT.read_text().splitlines()

    violations = []
    counts = {k: 0 for k in REQUIRED_RENAMES}
    in_heredoc = None

    for i, line in enumerate(raw, 1):
        stripped = line.strip()

        if in_heredoc is not None:
            if stripped == "PY":
                in_heredoc = None
            elif MENTION.search(STAGED.sub("", stripped)):
                violations.append((i, stripped,
                                   "a heredoc body mentions a tracked-file variable; change the opener to "
                                   "an unquoted heredoc and this expands -- interpreters are handed the "
                                   "staged copy only"))
            continue

        if stripped.startswith("#") or not stripped:
            continue

        for name, (pat, _want) in REQUIRED_RENAMES.items():
            counts[name] += len(pat.findall(stripped))

        for seg in segments(stripped):
            if not MENTION.search(STAGED.sub("", seg)):
                continue
            if REDIRECT.search(seg):
                violations.append((i, seg,
                                   "redirects into a tracked path -- build to a temp and rename it over"))
                continue
            if not any(pat.fullmatch(seg) for pat, _why in ALLOWED):
                violations.append((i, seg,
                                   "mentions a tracked-file variable in a shape that is not an allowed "
                                   "read or the publish rename -- if this writes the file, publish by "
                                   "renaming a finished temp over it instead"))

        if stripped.endswith("<<'PY'") or stripped.endswith("<<PY"):
            in_heredoc = i

    if in_heredoc is not None:
        die(f"unterminated heredoc opened at line {in_heredoc} -- a partial scan must not read as a pass")

    missing = [(n, w, counts[n]) for n, (_p, w) in REQUIRED_RENAMES.items() if counts[n] != w]

    for i, seg, why in violations:
        print(f"  build_release.sh:{i}: {seg}\n      {why}", file=sys.stderr)
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
    print("check_publish_atomic: split every line of build_release.sh into simple commands; every segment "
          f"mentioning $NOTES_REL/$OUT fully matched an allowed read or a publish rename, {total} required "
          "rename(s) present, no heredoc body names a tracked path")


if __name__ == "__main__":
    main()
