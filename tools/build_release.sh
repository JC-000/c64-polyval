#!/bin/bash
# tools/build_release.sh -- build a reproducible source tarball for a tagged release.
#
# Usage:
#   tools/build_release.sh <tag>
#   e.g. tools/build_release.sh v0.2.0
#
# Output: c64-polyval-<tag>.tar.gz in the repo root, plus the byte
# size and SHA256 printed to stdout. The script is location-aware and
# can be invoked from anywhere.
#
# Determinism: contents are staged with fixed owner/group (uid=0/gid=0
# numeric), every staged file's mtime is forced to the release date
# parsed from the release-notes front matter, file order in the
# archive is sorted, and the gzip layer drops its timestamp/filename
# header (`gzip -n`). The same source tree therefore produces a
# byte-identical tarball across machines.
#
# File list: the canonical v0.4.0 vendoring set --
#   * top-level docs: README.md, API.md, CHANGELOG.md, LICENSE, VERSION
#   * docs/RELEASE_NOTES_<tag>.md (with the on-disk copy stamped, see
#     "Two-pass attestation" below)
#   * docs/precalc-tables.md -- c64-lib-contract SPEC §8.0 enumeration
#   * src/ -- every *.s, every *.inc, c64.cfg, lib_only.cfg, and
#     include/ subdir (currently include/zp.inc)
# `src/main.s`, `src/boot.s`, `src/main_loop.s`, etc. ARE included --
# they are the demo-app + worked-example surface (see API.md §8.2).
# Production consumers omit them at link time per API.md §8.2; the
# tarball ships them so the in-repo VICE-runnable demo is reproducible
# from the artifact alone.
#
# Excluded from the tarball:
#   * build/         -- generated artifacts
#   * tools/         -- test+bench drivers (host-side Python, not
#                       library code)
#   * test/          -- consumer-stub smoke harness
#   * ca65/          -- the historical v0.1.0 .lib release tree
#                       (frozen artifact, NOT part of v0.2.0)
#   * .git/, .claude/, .serena/, .gitignore
#
# Two-pass attestation:
#   The release notes carry the canonical tarball's size + SHA256 in a
#   table at section "Attestation". On the first build of a new tag,
#   docs/RELEASE_NOTES_<tag>.md ships with placeholder strings
#   `SIZE_PLACEHOLDER` and `SHA256_PLACEHOLDER`. This script:
#     1. Stages all files (notes still bear placeholders inside the
#        staging area).
#     2. Builds the tarball. The tarball-internal notes therefore also
#        carry placeholders.
#     3. Computes the tarball's size + SHA256.
#     4. Rewrites the *on-disk* (repo-root) notes file with those real
#        values.
#   The tarball-internal copy keeps the placeholder strings, which is
#   intentional: the only way to embed the tarball's own SHA256 inside
#   the tarball would require solving a self-referential hash
#   pre-image, which is intractable. Downstream consumers verify the
#   tarball against the size+SHA256 from the *on-disk* / source-control
#   / GitHub-release-page copy of the notes, not from the embedded
#   copy. Re-running this script against the same source tree (after
#   the on-disk notes have been stamped on a prior run, or against the
#   placeholders on a fresh run) reproduces the same tarball
#   byte-for-byte.
#
# Ordering (issue #87): every check runs before any write to a tracked
#   file. The placeholder reset is applied to the STAGED copy of the
#   notes, the tarball is built to a temp path, and the working-tree
#   notes + c64-polyval-<tag>.tar.gz are written only in the publish
#   block at the very bottom, after the stamper is satisfied. A refused
#   run therefore leaves the working tree exactly as it found it -- which
#   is what "fail-closed" has to mean for a guard whose whole job is to
#   refuse. The publish block itself is ordered placeholder-notes ->
#   tarball -> stamped-notes so that an interruption inside it leaves a
#   loudly unfinished state rather than a plausible-looking release; see
#   the comment on that block.
#
# Make convenience target: `make dist VERSION=v0.2.0`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "usage: $0 <tag>" >&2
  echo "  e.g. $0 v0.2.0" >&2
  exit 1
fi

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: tag '$TAG' does not match ^v[0-9]+\.[0-9]+\.[0-9]+$" >&2
  exit 1
fi

VERSION_NUM="${TAG#v}"
FILE_VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ "$FILE_VERSION" != "$VERSION_NUM" ]]; then
  echo "error: VERSION file says '$FILE_VERSION' but tag arg says '$VERSION_NUM'" >&2
  echo "       (refusing to mint a tarball whose embedded VERSION disagrees with the tag)" >&2
  exit 1
fi

NOTES_REL="docs/RELEASE_NOTES_${TAG}.md"
if [[ ! -f "$NOTES_REL" ]]; then
  echo "error: release notes '$NOTES_REL' do not exist" >&2
  echo "       (author the notes before running the release script)" >&2
  exit 1
fi

OUT="c64-polyval-${TAG}.tar.gz"
PREFIX="c64-polyval-${TAG}"

# --- Tag-drift guard (issue #85) -----------------------------------------
# If refs/tags/$TAG already exists, this is a RE-RUN against a released tag,
# and the only honest thing to rebuild is the tree that tag names. On a tree
# that has moved past it, the old behaviour rebuilt from HEAD, overwrote the
# tracked c64-polyval-$TAG.tar.gz, and rewrote the released notes'
# Attestation to a size + SHA256 that no longer describes the artifact on the
# release page -- exit 0, no diagnostic. A consumer verifies the download
# against exactly those two values, so that is a consumer-visible corruption
# one `git commit -a` away. Measured on master at dd081a3 with v0.11.0:
# 142336 -> 143194 bytes, hash bd566d1c... -> 91b30596..., because three
# post-tag commits touched API.md, CHANGELOG.md and src/precalc_manifest.s.
#
# Determinism itself was never the defect -- two runs on one unchanged tree
# reproduce byte-for-byte. What was missing is the check that the tree is
# still the tag's.
#
# Set ALLOW_TAG_DRIFT=1 to override, for the deliberate case of re-cutting
# notes for a tag you are about to move. It prints what it is overriding.
ALLOW_TAG_DRIFT="${ALLOW_TAG_DRIFT:-0}"

# The staged set as GIT PATHSPECS, not shell globs. `:(glob)` is load-bearing
# twice over: it makes `*` stop at `/` (a shell `case` glob does not, so
# src/sub/foo.s -- never staged -- used to abort the release), and it hands
# git a PATTERN rather than a list of names that exist right now. Globbing the
# working tree instead meant a file present at the tag and DELETED since was
# never passed to `git diff` at all, so the guard slept through exactly the
# corruption it exists to stop: `rm src/polyval_compact.s` + `make dist
# VERSION=v0.11.0` rebuilt the released tarball without that file, exit 0.
# Found by adversarial review of the first version of this guard.
STAGED_PATHSPECS=(README.md API.md CHANGELOG.md LICENSE VERSION
                  docs/precalc-tables.md "$NOTES_REL"
                  ':(glob)src/*.s' ':(glob)src/*.inc' ':(glob)src/*.cfg'
                  ':(glob)src/include/*.inc')

# git must be able to answer, or the guard says so. `2>/dev/null || true` here
# made the whole check structurally incapable of reporting a git failure: its
# pass condition is an EMPTY result, which is also what a broken git produces.
# Measured with a corrupted index -- `git diff` exited 128, the guard printed
# nothing, exited 0, and built a drifted tarball. That is the shape CLAUDE.md's
# Working standard §1 names, in the very change that cites it.
if ! command -v git >/dev/null 2>&1; then
  echo "warning: git not on PATH -- the tag-drift guard (#85) is INACTIVE." >&2
elif ! git rev-parse --git-dir >/dev/null 2>&1; then
  # Legitimate: building from an extracted tarball with no .git. Still said
  # out loud, because a silently absent guard is the failure being fixed.
  echo "note: not a git repository -- tag-drift guard (#85) not applicable." >&2
elif git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  git_st=0
  DRIFTED="$(git diff --name-only "$TAG" -- "${STAGED_PATHSPECS[@]}")" || git_st=$?
  if [[ "$git_st" -ne 0 ]]; then
    echo "error: 'git diff' against tag '$TAG' failed (exit $git_st)." >&2
    echo "       Refusing to build: the tag-drift guard (#85) could not run," >&2
    echo "       and a guard that cannot run must not pass silently." >&2
    exit 1
  fi

  # A file ADDED under src/ after the tag is drift too, and `git diff` against
  # the tag cannot see it while it is untracked.
  git_st=0
  UNTRACKED="$(git ls-files --others --exclude-standard -- \
                 ':(glob)src/*.s' ':(glob)src/*.inc' ':(glob)src/*.cfg' \
                 ':(glob)src/include/*.inc')" || git_st=$?
  if [[ "$git_st" -ne 0 ]]; then
    echo "error: 'git ls-files' failed (exit $git_st); guard cannot run." >&2
    exit 1
  fi

  # INTERRUPTED-PUBLISH SIGNATURE (#87 round-2 review, D7). A `make dist` killed
  # inside the publish block leaves the notes in placeholder form -- deliberately
  # loud -- and on an already-tagged tree that loudness IS tag drift, so the next
  # plain re-run lands here. Both messages below were wrong for that operator:
  # the refusal never mentioned the interrupted run, and ALLOW_TAG_DRIFT's
  # warning asserted the rebuilt tarball would NOT describe the released
  # artifact, which is false when the notes' placeholder rows are the only
  # difference -- the tarball stages the notes in placeholder form either way,
  # so the rebuild reproduces the released bytes exactly. Being told the
  # artifact will be wrong when it will not is worse than being told nothing.
  #
  # The signature is: the notes are the ONLY drifted path, nothing untracked
  # would be staged, and the notes carry the placeholder tokens.
  INTERRUPTED=0
  if [[ "$DRIFTED" == "$NOTES_REL" && -z "$UNTRACKED" ]] \
     && grep -q 'SHA256_PLACEHOLDER\|SIZE_PLACEHOLDER' "$NOTES_REL"; then
    INTERRUPTED=1
  fi

  if [[ -n "$DRIFTED" || -n "$UNTRACKED" ]]; then
    if [[ "$ALLOW_TAG_DRIFT" == "1" ]]; then
      if [[ "$INTERRUPTED" == "1" ]]; then
        echo "warning: ALLOW_TAG_DRIFT=1 -- $NOTES_REL differs from tag '$TAG'" >&2
        echo "         only by its placeholder Attestation rows, which is the" >&2
        echo "         signature of a 'make dist' interrupted mid-publish (#87)." >&2
        echo "         The tarball stages the notes in placeholder form either" >&2
        echo "         way, so this rebuild DOES reproduce the released bytes;" >&2
        echo "         the stamp it writes back is the repair." >&2
      else
        echo "warning: ALLOW_TAG_DRIFT=1 -- rebuilding $TAG from a tree that has" >&2
        echo "         moved past the tag. The tarball and the Attestation block" >&2
        echo "         in $NOTES_REL will NOT describe the released artifact." >&2
      fi
    else
      if [[ "$INTERRUPTED" == "1" ]]; then
        echo "error: $NOTES_REL carries placeholder Attestation rows and is the" >&2
        echo "       only file that differs from tag '$TAG'. That is the" >&2
        echo "       signature of a 'make dist' interrupted mid-publish (#87):" >&2
        echo "       the notes were reset for staging and never stamped back." >&2
        echo "       Restore them, then re-run -- this is the first remedy:" >&2
        echo "         git checkout $TAG -- $NOTES_REL && make dist VERSION=$TAG" >&2
        echo "       ALLOW_TAG_DRIFT=1 also repairs it and reproduces the same" >&2
        echo "       bytes, because the tarball stages the notes in placeholder" >&2
        echo "       form regardless; its warning about the artifact not" >&2
        echo "       matching the release does not apply to this case." >&2
        echo "       Check $OUT too: an interrupt after the rename leaves the" >&2
        echo "       NEW tarball in place, one an unstamped Attestation does" >&2
        echo "       not describe." >&2
        exit 1
      fi
      echo "error: tag '$TAG' exists, but staged files differ from it." >&2
      [[ -n "$DRIFTED" ]]   && { echo "       changed since the tag:" >&2; \
                                 echo "$DRIFTED" | sed 's/^/         /' >&2; }
      [[ -n "$UNTRACKED" ]] && { echo "       untracked, would be staged:" >&2; \
                                 echo "$UNTRACKED" | sed 's/^/         /' >&2; }
      echo "       Rebuilding here would overwrite the released $OUT and rewrite" >&2
      echo "       the Attestation in $NOTES_REL to values that do not match the" >&2
      echo "       published release (issue #85)." >&2
      echo "       To verify a released tag, build from a worktree of it:" >&2
      echo "         git worktree add /tmp/verify-$TAG $TAG && cd /tmp/verify-$TAG && make dist VERSION=$TAG" >&2
      echo "       To override deliberately: ALLOW_TAG_DRIFT=1 make dist VERSION=$TAG" >&2
      exit 1
    fi
  fi
else
  # No such tag locally. Normal for a first cut -- but a shallow or --no-tags
  # clone reaches here too, with no protection and nothing to say so.
  if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
    echo "warning: shallow clone -- tag '$TAG' may exist upstream and not here," >&2
    echo "         so the tag-drift guard (#85) cannot vouch for this build." >&2
  fi
fi


# Parse the release date from the notes front matter so the tarball
# timestamps track the documented release rather than the build clock.
# Convention: first line is "# c64-polyval vX.Y.Z -- YYYY-MM-DD".
RELEASE_DATE="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$NOTES_REL" | head -1 || true)"
if [[ -z "$RELEASE_DATE" ]]; then
  echo "error: could not parse release date from '$NOTES_REL'" >&2
  exit 1
fi
MTIME="${RELEASE_DATE}T00:00:00Z"

# --- No mutation before every check (issue #87) ---------------------------
# Everything from here down to the two writes at the very bottom happens in
# scratch space. Until this fix, the script reset the on-disk notes to
# placeholder form and overwrote the tracked c64-polyval-<tag>.tar.gz BEFORE
# the fail-closed stamper ran, so a REFUSED run exited non-zero having already
# left both tracked files modified, with no restoration and nothing said about
# it. The operator was told the notes were wrong, not that the tree had
# already changed. Measured on the unfixed script with notes carrying a second
# `**SHA256**` row:
#     release-notes stamping: expected exactly one SHA256_PLACEHOLDER in
#     docs/RELEASE_NOTES_v0.12.0.md, found 2 -- refusing to stamp
#     make: *** [dist] Error 1
#     $ git status --porcelain
#      M c64-polyval-v0.12.0.tar.gz
#      M docs/RELEASE_NOTES_v0.12.0.md
#
# The fix is ORDERING, not restoration: the placeholder reset rewrites the
# STAGED copy rather than the working-tree file, the placeholder-count guard
# runs at reset time (before a tarball exists at all), and the tarball is
# built to a temp path renamed onto $OUT only once every check has passed.
# The #85 tag-drift guard's "a refusal touches nothing" property now holds
# for the script as a whole. The working-tree notes are still put through
# placeholder form, but in the publish block at the bottom, where it is a
# deliberate crash-visible marker rather than a pre-check mutation.
STAGE_DIR="$(mktemp -d "/tmp/c64-polyval-release-XXXXXX")"

# Temp tarball path. In the repo root rather than $STAGE_DIR so the final
# publish is a same-directory rename, not a cross-filesystem copy.
#
# The NAME is load-bearing and must keep the `build-scratch.` prefix. This is
# scratch state minted in the repo root, i.e. exactly #93's shape, and SIGKILL
# catches no trap -- so it has to be a name `make clean` already sweeps
# (SCRATCH_TREES = build-scratch.*). The first cut of this fix used
# `.${OUT}.tmp.$$`, which nothing swept: `make clean` did not match it and
# `make check-scratch-prefix` printed "all swept" because its scan only knew
# the `mktemp -d "$ROOT/..."` and `mkdtemp(dir=ROOT)` shapes. Adversarial
# review caught both halves. check_scratch_prefix.py now recognises this
# `VAR="literal...$$..."` shape too, so the agreement is asserted rather than
# described -- rename this and that gate goes red.
OUT_TMP="build-scratch.release.$$.tar.gz"

# Same for the notes: the working-tree notes file is only ever REPLACED by a
# rename of this temp, never written in place, so it cannot be caught torn.
NOTES_TMP="build-scratch.release.$$.notes.md"

# EXIT alone leaves scratch state behind on a catchable signal. Bash does run
# an EXIT trap on SIGINT, but SIGTERM was measured leaving the tree behind in
# 1 of 2 attempts in the sibling case (#93, check_knob_staleness.sh); the #87
# comment asks for the same closure here. INT TERM HUP closes the catchable
# half; SIGKILL cannot be closed, which is what the swept name is for.
#
# Each signal handler re-raises rather than `exit`ing: `exit 143` makes the
# script look like it terminated NORMALLY with status 143, so a caller's
# WIFSIGNALED/`$?` == -15 test can no longer tell a killed release from a
# script that chose to fail. Clear the trap and kill ourselves with the same
# signal instead, which is the portable idiom and preserves the exit status a
# supervisor expects.
cleanup() { rm -rf "$STAGE_DIR"; rm -f "$OUT_TMP" "$NOTES_TMP"; }
trap 'cleanup' EXIT
trap 'cleanup; trap - INT ; kill -INT  $$' INT
trap 'cleanup; trap - TERM; kill -TERM $$' TERM
trap 'cleanup; trap - HUP ; kill -HUP  $$' HUP

STAGE_ROOT="${STAGE_DIR}/${PREFIX}"
mkdir -p "$STAGE_ROOT/src/include" "$STAGE_ROOT/docs"

# --- Top-level docs + VERSION --------------------------------------------
cp README.md API.md CHANGELOG.md LICENSE VERSION "$STAGE_ROOT/"

# --- Release notes (placeholder form; on-disk stamped after build) -------
# The working-tree notes are copied verbatim and the placeholder reset is then
# applied IN PLACE to the staged copy. Doing it in this order rather than
# resetting the working-tree file first buys two things (issue #87):
#   * the working-tree file is not written until every check has passed, and
#   * the staged file keeps the mode `cp` gave it from the source, so the tar
#     header bytes are exactly what the old order produced -- the
#     reproducibility this script exists for is unperturbed.
cp "$NOTES_REL" "$STAGE_ROOT/$NOTES_REL"

# Reset the STAGED notes to placeholder form, so that every build (including
# reruns over already-stamped notes) produces the same staged bytes. The
# on-disk values are stamped from the computed SHA256/size at the very end.
#
# The placeholder-count guard that used to live only in the stamper runs HERE
# as well, before a tarball exists: its entire purpose is to refuse, and a
# guard whose refusal has already rewritten two tracked files is not
# fail-closed in any useful sense.
python3 - "$STAGE_ROOT/$NOTES_REL" "$NOTES_REL" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])   # staged copy -- the only thing rewritten here
shown = sys.argv[2]             # working-tree path, for the diagnostic only
text = p.read_text()
# Replace the attestation table's SHA256 with the placeholder string.
# SCOPED to the `| **SHA256** | <hash> |` row on purpose: release notes
# also carry OTHER 64-hex hashes — the worktree-rebuild byte-identity
# receipt CLAUDE.md's release flow requires (one PRG hash per profile,
# per baseline). An unscoped `[0-9a-f]{64}` here placeholder-ised those
# too, and the unbounded str.replace() in the stamper then stamped the
# tarball's hash over every one of them, rewriting the receipt into a row
# of identical hashes that reads as a successful identity check. Measured;
# see the count guard below, which makes that shape fail loudly.
text = re.sub(r'(\*\*SHA256\*\*\s*\|\s*)`[0-9a-f]{64}`',
              r'\g<1>`SHA256_PLACEHOLDER`', text)
# Replace "|" + decimal + " bytes" with placeholder (the attestation
# table's Size row).
text = re.sub(r'(\*\*Size\*\*\s*\|\s*)(\d+)( bytes)', r'\g<1>SIZE_PLACEHOLDER\g<3>', text)

# Exactly one of each placeholder must be present. More than one means the
# reset matched something it should not have (e.g. a byte-identity receipt
# hash), and stamping would overwrite real measurements with the tarball's
# hash -- silently, and in a shape that still reads as a valid attestation.
# Zero means there is no attestation row to stamp at all. Fail loudly here,
# where nothing outside the scratch staging area has been written.
for name in ('SHA256_PLACEHOLDER', 'SIZE_PLACEHOLDER'):
    count = text.count(name)
    if count != 1:
        sys.exit("release-notes stamping: expected exactly one %s in %s, "
                 "found %d -- refusing to stamp (see the scoped reset regex "
                 "above). No files were modified." % (name, shown, count))

p.write_text(text)
PY

# --- Precalc-table enumeration (c64-lib-contract SPEC §8.0) --------------
cp docs/precalc-tables.md "$STAGE_ROOT/docs/precalc-tables.md"

# docs/contract-watch.md is DELIBERATELY NOT staged. Recording the decision
# because docs/ is copied by explicit name rather than a glob, so an omission
# here is indistinguishable from an oversight -- the trap CLAUDE.md flags.
# It is internal process state: a live ledger of contract tags, an in-flight
# register of other repos' open issues, and a fleet status table. Frozen into
# a tarball it would be stale on arrival and would assert things about OTHER
# repositories that a consumer might read as current. It is on master for
# anyone who wants it.

# --- src/ : *.s, *.inc, linker configs, include/ ------------------------
# `src/*.cfg` is a GLOB, not the enumeration `src/c64.cfg src/lib_only.cfg`
# it replaced. That enumeration was a silent-omission trap of exactly the
# kind CLAUDE.md already flags for docs/*.md: adding src/polyval-example.cfg
# (the c64-lib-contract §6.1 consumer-facing example, issue #79) left it out
# of the tarball with no diagnostic from this script, from `make dist`, or
# from the reproducibility re-run -- the tarball is simply, quietly, missing
# a file a consumer was told to expect. Globbing the extension the way the
# two lines above already glob *.s and *.inc removes the trap instead of
# adding one more name to forget.
for f in src/*.s src/*.inc src/*.cfg; do
  [[ -e "$f" ]] || continue
  cp "$f" "$STAGE_ROOT/$f"
done
for f in src/include/*.inc; do
  [[ -e "$f" ]] || continue
  cp "$f" "$STAGE_ROOT/$f"
done

# --- Reproducibility: detect tar flavour --------------------------------
# macOS ships bsdtar (libarchive); it pins owner/group via --uid/--gid/
# --uname/--gname but does NOT accept --mtime as a create-mode option
# in 3.5.x. GNU tar accepts --mtime and --sort=name. Strategy:
#   bsdtar  -> pre-touch every staged file to MTIME, drive entry order
#              via `find ... | LC_ALL=C sort | tar -T -`.
#   gnutar  -> use --mtime + --sort=name directly.
TAR_FLAVOUR="gnu"
if tar --version 2>&1 | grep -qi bsdtar; then
  TAR_FLAVOUR="bsd"
fi

# Convert RFC-3339 MTIME -> touch -t format YYYYMMDDhhmm.SS.
if TOUCH_STAMP="$(date -j -f %Y-%m-%dT%H:%M:%SZ "$MTIME" +%Y%m%d%H%M.%S 2>/dev/null)"; then
  :
else
  TOUCH_STAMP="$(date -d "$MTIME" +%Y%m%d%H%M.%S)"
fi

# Force every entry under STAGE_DIR (files + dirs) to MTIME so the
# archive records that mtime in the header.
find "$STAGE_DIR" -exec touch -t "$TOUCH_STAMP" {} +

# --- Build the tarball --------------------------------------------------
if [[ "$TAR_FLAVOUR" == "bsd" ]]; then
  # -n / --no-recursion: tar must not descend into directories on its
  # own; the `find ... | sort` pipe enumerates every entry (files +
  # dirs) exactly once in a deterministic order.
  ( cd "$STAGE_DIR" \
    && find "$PREFIX" -print | LC_ALL=C sort \
       | tar --no-recursion \
             --uid 0 --gid 0 --uname "" --gname "" \
             -cf - -T - ) \
    | gzip -n -9 > "$OUT_TMP"
else
  tar -C "$STAGE_DIR" \
    --owner=0 --group=0 --numeric-owner \
    --mtime="$MTIME" \
    --sort=name \
    -cf - "$PREFIX" \
    | gzip -n -9 > "$OUT_TMP"
fi

SIZE=$(wc -c < "$OUT_TMP" | tr -d ' ')
SHA=$(shasum -a 256 "$OUT_TMP" | cut -d' ' -f1)

# --- Compute the stamped notes, still in scratch space ------------------
# Source is the STAGED placeholder copy, not the working-tree file, which at
# this point still holds the previous run's values untouched.
STAMPED="${STAGE_DIR}/notes.stamped.md"
python3 - "$STAGE_ROOT/$NOTES_REL" "$STAMPED" "$NOTES_REL" "$SIZE" "$SHA" <<'PY'
import sys, pathlib
src, dst, shown, size, sha = sys.argv[1:6]
text = pathlib.Path(src).read_text()

# Defence in depth: the reset step already refused on any count != 1, so this
# cannot fire on a path that reaches here. It is kept because the substitution
# below is unbounded, and it still runs before anything outside scratch space
# is written.
for name, count in (('SHA256_PLACEHOLDER', text.count('SHA256_PLACEHOLDER')),
                    ('SIZE_PLACEHOLDER',   text.count('SIZE_PLACEHOLDER'))):
    if count != 1:
        sys.exit("release-notes stamping: expected exactly one %s in %s, "
                 "found %d -- refusing to stamp (see the scoped reset regex "
                 "above). No files were modified." % (name, shown, count))

text = text.replace('SHA256_PLACEHOLDER', sha)
text = text.replace('SIZE_PLACEHOLDER', size)
pathlib.Path(dst).write_text(text)
PY

# --- Publish: the only writes to tracked files, and their ORDER ---------
# All three happen after every check has passed. The order is chosen so that
# an interruption anywhere inside this block leaves a LOUD state, not a state
# that reads as a finished release.
#
# The first cut of this fix wrote the stamped notes and then renamed the
# tarball. Adversarial review widened that gap with a `sleep 4` and sent
# SIGTERM: the notes came out fully stamped with ZERO placeholder tokens, the
# on-disk tarball was still the PREVIOUS run's, and the correct tarball had
# been deleted by the TERM handler -- `git status` then showed exactly what a
# successful release shows, with an Attestation describing an artifact that no
# longer existed. That is a smaller window than the one it replaced, but a
# SILENT one, and the old window was always loud. Trading loud for silent is
# a regression in failure-mode quality however much smaller the window gets.
#
# So: reset the working-tree notes to the STAGED placeholder form FIRST, then
# rename the tarball, then stamp. `$SIZE`/`$SHA` were computed from
# `$OUT_TMP` above, so the values stamped in step 3 describe exactly the bytes
# step 2 published. Interrupted after step 1 or step 2, the notes carry
# SHA256_PLACEHOLDER / SIZE_PLACEHOLDER -- the same unmistakable signature the
# pre-fix window left, and one a re-run consumes cleanly (the reset step finds
# exactly one of each and proceeds).
#
# ALL THREE STEPS ARE RENAMES. The notes steps were plain `cp`s until round-2
# review measured the remaining hole: a `cp` is tearable, and the attestation
# rows sit ~98% of the way through the file, so a torn copy drops them
# entirely -- no placeholder tokens, no `**SHA256**` row at all. (Reaching it
# needs a process-group SIGKILL: killing only the shell lets the `cp` child
# run to completion, which is why the first probes missed it.) Every torn
# state is still unmistakably broken -- a re-run dies at "could not parse
# release date" -- so this was a documentation question, not a correctness
# one. Renaming removes the class instead of describing it: rename(2) is
# atomic, so each tracked file is the old bytes or the new bytes and never a
# prefix of either.
#
# The temp files live in the repo root, not in docs/. Atomicity needs the same
# FILESYSTEM, not the same directory, and one repo is one filesystem -- while
# `make clean`'s SCRATCH_TREES only sweeps the repo root, so a docs/-resident
# temp would be #93's shape all over again.
#
# NOTES_TMP is seeded by copying the CURRENT notes first, purely so it inherits
# that file's mode: `cp` onto an existing file keeps the destination's mode, so
# the second `cp` writes content without changing it, and the rename then
# installs a file with the same permissions the notes already had.
cp "$NOTES_REL"             "$NOTES_TMP"
cp "$STAGE_ROOT/$NOTES_REL" "$NOTES_TMP"
mv "$NOTES_TMP" "$NOTES_REL"

mv "$OUT_TMP" "$OUT"

cp "$NOTES_REL" "$NOTES_TMP"
cp "$STAMPED"   "$NOTES_TMP"
mv "$NOTES_TMP" "$NOTES_REL"

echo "Built ${OUT}"
echo "  Path:   ${REPO_ROOT}/${OUT}"
echo "  Size:   ${SIZE} bytes"
echo "  SHA256: ${SHA}"
echo "  Tar:    ${TAR_FLAVOUR}tar"
echo "  MTime:  ${MTIME} (reproducible)"
echo ""
echo "On-disk ${NOTES_REL} has been stamped with the canonical size+SHA256."
echo "The tarball-internal copy of the notes carries the placeholder strings"
echo "by design (a tarball cannot embed its own SHA256 without a hash"
echo "pre-image attack); downstream consumers verify against the on-disk"
echo "/ source-control / GitHub-release-page copy of the notes."
