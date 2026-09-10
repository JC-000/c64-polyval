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


def command_substitutions(text):
    """Inner text of every `$( )` and backtick run in *text*, recursively.

    Issue #113, hole 1. A write nested in a command substitution rode in
    unexamined, because the segment CONTAINING it fullmatched an allowed
    shape:

        echo "$(cp "$STAMPED" "$NOTES_REL")"      <- passed, exit 0
        printf %s "$(tee "$NOTES_REL" < "$STAMPED")"

    That is the round-5 family -- "an allowed prefix launders a write" -- one
    level down. A substitution's contents are simple commands that RUN, and
    they run inside double quotes too. Only single quotes suppress them, so
    single-quoted runs are skipped rather than descended into.
    """
    ROUND2 = None  # see the two corrections below
    out, i, n, sq, dq = [], 0, len(text), False, False
    while i < n:
        c = text[i]
        # ROUND-2 CORRECTION (a). This used to toggle `sq` unconditionally.
        # A single quote INSIDE double quotes is a literal character, and the
        # substitution around it still runs, so
        #     echo "'$(cp "$STAMPED" "$NOTES_REL")'"
        # made the scanner treat the whole region as single-quoted and skip
        # it -- and that shape really does write the file under bash. Quote
        # state now mirrors segments(), which had it right all along.
        if c == "'" and not dq:
            sq = not sq; i += 1; continue
        if c == '"' and not sq:
            dq = not dq; i += 1; continue
        if sq:
            i += 1; continue
        if c == "\\":
            i += 2; continue
        # ROUND-2 CORRECTION (b): process substitution. `>(tee "$NOTES_REL")`
        # and `<(...)` run commands exactly as `$( )` does, and
        #     echo x > >(tee "$NOTES_REL")
        # went green -- the round-5 "an allowed prefix launders a write"
        # family again, through a construct the first cut did not model.
        opener = None
        for tok in ("$(", ">(", "<("):
            if text.startswith(tok, i):
                opener = tok; break
        if opener:
            depth, j = 1, i + 2
            start = j
            isq = idq = False
            while j < n:
                ch = text[j]
                if ch == "'" and not idq:
                    isq = not isq
                elif ch == '"' and not isq:
                    idq = not idq
                elif ch == "\\":
                    j += 1
                elif not isq:
                    if text.startswith("$(", j) or text.startswith(">(", j) or text.startswith("<(", j):
                        depth += 1; j += 1
                    elif ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0:
                            break
                j += 1
            if j < n and depth == 0:
                out.append(text[start:j]); i = j + 1; continue
            # An UNTERMINATED substitution is not a pass. It means the command
            # continues onto the next line (a line-continued `$(`), which this
            # line-at-a-time scan cannot see the end of.
            out.append(text[i + 2:])
            i = n; continue
        if c == "`":
            j = text.find("`", i + 1)
            if j == -1:
                break
            out.append(text[i + 1:j]); i = j + 1; continue
        i += 1
    return out


def deep_segments(line):
    """`segments()`, plus the segments of every command substitution inside.

    Recursive, so a substitution nested in a substitution is reached too.
    """
    out = []
    for seg in segments(line):
        out.append(seg)
        for inner in command_substitutions(seg):
            out.extend(deep_segments(inner))
    return out


def analyze(lines):
    """(violations, counts, unterminated_heredoc_line, examined_segments).

    The real scan AND the self-test both call this. That is deliberate: a
    self-test that exercised a reimplementation would certify code the release
    path does not run.
    """
    violations = []
    counts = {k: 0 for k in REQUIRED_RENAMES}
    in_heredoc = None
    examined = 0

    for i, line in enumerate(lines, 1):
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

        segs = deep_segments(stripped)

        # Issue #113, hole 2: this used to be `len(pat.findall(stripped))` over
        # the RAW LINE, so a quoted mention satisfied the count --
        #     echo 'mv "$NOTES_TMP" "$NOTES_REL"' >/dev/null
        # kept the required-rename total at 2 and passed, defeating the very
        # property the positive half exists for. Count only segments that
        # FULLMATCH the rename, which is what "the script performs this
        # rename" actually means.
        for name, (pat, _want) in REQUIRED_RENAMES.items():
            counts[name] += sum(1 for s in segs if pat.fullmatch(s))

        for seg in segs:
            if not MENTION.search(STAGED.sub("", seg)):
                continue
            examined += 1
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

    return violations, counts, in_heredoc, examined


# Every shape a review has walked past this gate, plus the two from #113, as
# executable assertions. MUST_FLAG lines have to produce a violation; MUST_PASS
# lines must not, so that tightening the matcher cannot quietly start refusing
# the real script's legitimate reads.
#
# This is contract-watch.md item 4 made concrete: the question is not "does the
# gate pass" but "has it ever been observed to fail?". Every entry below is a
# shape that DID pass some earlier revision of this file.
SELFTEST_MUST_FLAG = [
    ('echo "$(cp "$STAMPED" "$NOTES_REL")"',
     "#113 hole 1 -- write nested in a command substitution"),
    ('printf %s "$(tee "$NOTES_REL" < "$STAMPED")"',
     "#113 hole 1 -- tee nested in a command substitution"),
    ('cp "$STAMPED" "${NOTES_REL}"',
     "round 3 -- braced spelling"),
    ('install -m 644 "$STAMPED" "$NOTES_REL"',
     "round 3 -- a different command name"),
    ('tee "$NOTES_REL" < "$STAMPED"',
     "round 3 -- tee"),
    ('grep -q SHA256 "$NOTES_REL" && cp "$STAMPED" "$NOTES_REL"',
     "round 5 -- an allowed read as the prefix, the write in the suffix"),
    ('echo "publishing" && cp "$STAMPED" "$NOTES_REL"',
     "round 5 -- an allowed echo as the prefix"),
    ('cp "$NOTES_REL" "$NOTES_TMP" && cp "$STAMPED" "$NOTES_REL"',
     "round 5 -- an allowed cp-as-source as the prefix"),
    ('echo done > "$NOTES_REL"',
     "redirection into a tracked path"),
    # --- round 2, all found by adversarial review of the first cut ---------
    ("""echo "'$(cp "$STAMPED" "$NOTES_REL")'\"""",
     "round 2 -- a literal ' inside double quotes; the substitution still runs"),
    ('echo x > >(tee "$NOTES_REL")',
     "round 2 -- process substitution"),
    ('cat "$STAMPED" > >(dd of="$NOTES_REL")',
     "round 2 -- process substitution behind a redirect"),
    # D4: ALLOWED could be loosened by ADDING a shape, and no entry above used
    # an in-place editor -- so `(r'sed\\s.*', ...)` let the pre-#87 in-place
    # stamper straight through while the self-test still reported all controls
    # firing. These four are the in-place writers that matter; a new ALLOWED
    # shape that admits any of them now goes red.
    ('sed -i "" "s/SHA256_PLACEHOLDER/$SHA/" "$NOTES_REL"',
     "D4 -- in-place sed, the pre-#87 stamper"),
    ('perl -i -pe "s/X/Y/" "$NOTES_REL"',
     "D4 -- in-place perl"),
    ('python3 -c "open(\'x\',\'w\')" "$NOTES_REL"',
     "D4 -- a tracked path handed to an interpreter"),
    ('dd if="$STAMPED" of="$NOTES_REL"',
     "D4 -- dd writing the tracked path"),
]

SELFTEST_MUST_PASS = [
    'mv "$NOTES_TMP" "$NOTES_REL"',
    'mv "$OUT_TMP" "$OUT"',
    'cp "$NOTES_REL" "$NOTES_TMP"',
    'RELEASE_DATE="$(grep -oE \'[0-9]{4}\' "$NOTES_REL" | head -1 || true)"',
]


def selftest():
    """Positive control: prove the scanner still catches what it exists to catch.

    Without this, every green below is consistent with a matcher that matches
    nothing -- the failure mode that a mutation of the CODE UNDER TEST can
    never reveal, because the code under test is a regex. Runs on every
    invocation; the success line says it fired.
    """
    if not SELFTEST_MUST_FLAG or not SELFTEST_MUST_PASS:
        die("the self-test corpus is empty -- a positive control that asserts "
            "nothing certifies nothing")

    for line, why in SELFTEST_MUST_FLAG:
        violations, _c, _h, _e = analyze([line])
        if not violations:
            die(f"POSITIVE CONTROL FAILED: the scanner did not flag `{line}` ({why}). "
                "The matcher is dead or has been loosened -- a clean result from it "
                "proves nothing. Do not weaken this corpus to go green")

    for line in SELFTEST_MUST_PASS:
        violations, _c, _h, _e = analyze([line])
        if violations:
            die(f"NEGATIVE CONTROL FAILED: the scanner flagged `{line}`, which the "
                "release script legitimately does. The matcher has been tightened "
                "past the real script and would refuse a correct release")

    # Hole 2 is a counting defect, not a violation, so it needs its own arm.
    decoy = """echo 'mv "$NOTES_TMP" "$NOTES_REL"' >/dev/null"""
    _v, counts, _h, _e = analyze([decoy])
    if any(counts.values()):
        die("POSITIVE CONTROL FAILED: a quoted mention still counts as a publish "
            f"rename ({counts}) -- issue #113 hole 2 has regressed")

    return len(SELFTEST_MUST_FLAG) + len(SELFTEST_MUST_PASS) + 1


def main():
    if not SCRIPT.is_file():
        die(f"{SCRIPT} does not exist -- an empty scan must not read as a pass")
    raw = SCRIPT.read_text().splitlines()
    if not raw:
        die(f"{SCRIPT} is empty -- an empty scan must not read as a pass")

    controls = selftest()

    violations, counts, in_heredoc, examined = analyze(raw)

    if in_heredoc is not None:
        die(f"unterminated heredoc opened at line {in_heredoc} -- a partial scan must not read as a pass")

    # Vacuity guard. The whole gate is about how tracked-file variables are
    # used; if the scan found none, it examined nothing and its silence is not
    # evidence (#86/#91 shape).
    if examined == 0:
        die("no segment of build_release.sh mentions $NOTES_REL or $OUT -- the scan "
            "examined nothing, so a clean result is vacuous. Either the script stopped "
            "publishing or the scanner stopped seeing it")

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
    print("check_publish_atomic: split every line of build_release.sh into simple commands (command "
          f"substitutions included); {examined} segment(s) mentioning $NOTES_REL/$OUT fully matched an "
          f"allowed read or a publish rename, {total} required rename(s) present, no heredoc body names a "
          f"tracked path, {controls} positive/negative control(s) fired")


if __name__ == "__main__":
    main()
