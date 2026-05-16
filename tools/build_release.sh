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
# File list: the canonical v0.2.0 vendoring set --
#   * top-level docs: README.md, API.md, CHANGELOG.md, LICENSE, VERSION
#   * docs/RELEASE_NOTES_<tag>.md (with the on-disk copy stamped, see
#     "Two-pass attestation" below)
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
# Replace any 64-hex-char SHA256 with the placeholder string. The
# placeholder lives between backticks in the attestation table.
text = re.sub(r'`[0-9a-f]{64}`', '`SHA256_PLACEHOLDER`', text)
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

# --- src/ : *.s, *.inc, linker configs, include/ ------------------------
for f in src/*.s src/*.inc src/c64.cfg src/lib_only.cfg; do
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
