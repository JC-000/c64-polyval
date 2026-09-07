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

  if [[ -n "$DRIFTED" || -n "$UNTRACKED" ]]; then
    if [[ "$ALLOW_TAG_DRIFT" == "1" ]]; then
      echo "warning: ALLOW_TAG_DRIFT=1 -- rebuilding $TAG from a tree that has" >&2
      echo "         moved past the tag. The tarball and the Attestation block" >&2
      echo "         in $NOTES_REL will NOT describe the released artifact." >&2
    else
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

# Reset the on-disk notes to placeholder form before staging, so that
# every build (including reruns over already-stamped notes) produces
# the same staged bytes. We restore the on-disk values from the
# computed SHA256/size at the end.
python3 - "$NOTES_REL" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
# Replace the attestation table's SHA256 with the placeholder string.
# SCOPED to the `| **SHA256** | <hash> |` row on purpose: release notes
# also carry OTHER 64-hex hashes — the worktree-rebuild byte-identity
# receipt CLAUDE.md's release flow requires (one PRG hash per profile,
# per baseline). An unscoped `[0-9a-f]{64}` here placeholder-ised those
# too, and the unbounded str.replace() below then stamped the tarball's
# hash over every one of them, rewriting the receipt into a row of
# identical hashes that reads as a successful identity check. Measured;
# see the guard below, which now makes that shape fail loudly.
text = re.sub(r'(\*\*SHA256\*\*\s*\|\s*)`[0-9a-f]{64}`',
              r'\g<1>`SHA256_PLACEHOLDER`', text)
# Replace "|" + decimal + " bytes" with placeholder (the attestation
# table's Size row).
text = re.sub(r'(\*\*Size\*\*\s*\|\s*)(\d+)( bytes)', r'\g<1>SIZE_PLACEHOLDER\g<3>', text)
p.write_text(text)
PY

STAGE_DIR="$(mktemp -d "/tmp/c64-polyval-release-XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

STAGE_ROOT="${STAGE_DIR}/${PREFIX}"
mkdir -p "$STAGE_ROOT/src/include" "$STAGE_ROOT/docs"

# --- Top-level docs + VERSION --------------------------------------------
cp README.md API.md CHANGELOG.md LICENSE VERSION "$STAGE_ROOT/"

# --- Release notes (placeholder form; on-disk stamped after build) -------
cp "$NOTES_REL" "$STAGE_ROOT/$NOTES_REL"

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
    | gzip -n -9 > "$OUT"
else
  tar -C "$STAGE_DIR" \
    --owner=0 --group=0 --numeric-owner \
    --mtime="$MTIME" \
    --sort=name \
    -cf - "$PREFIX" \
    | gzip -n -9 > "$OUT"
fi

SIZE=$(wc -c < "$OUT" | tr -d ' ')
SHA=$(shasum -a 256 "$OUT" | cut -d' ' -f1)

# --- Stamp the *on-disk* notes (not the staged/in-tarball copy) ---------
python3 - "$NOTES_REL" "$SIZE" "$SHA" <<'PY'
import sys, pathlib
path, size, sha = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
text = p.read_text()

# Exactly one of each placeholder must be present. More than one means
# the reset step above matched something it should not have (e.g. a
# byte-identity receipt hash), and stamping would overwrite real
# measurements with the tarball's hash -- silently, and in a shape that
# still reads as a valid attestation. Fail loudly instead.
for name, count in (('SHA256_PLACEHOLDER', text.count('SHA256_PLACEHOLDER')),
                    ('SIZE_PLACEHOLDER',   text.count('SIZE_PLACEHOLDER'))):
    if count != 1:
        sys.exit("release-notes stamping: expected exactly one %s in %s, "
                 "found %d -- refusing to stamp (see the scoped reset regex "
                 "above)" % (name, path, count))

text = text.replace('SHA256_PLACEHOLDER', sha)
text = text.replace('SIZE_PLACEHOLDER', size)
p.write_text(text)
PY

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
