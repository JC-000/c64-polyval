#!/bin/sh
# check_archive_members.sh -- assert an archive contains exactly the members
# its own rule said it would (issue #97).
#
#   check_archive_members.sh <archive.a> <expected .o path> ...
#
# Called from every archive recipe as
#
#   $(TOOLS_DIR)/check_archive_members.sh $@ $^
#
# so the expected set IS the rule's prerequisite list -- there is no second
# list to drift out of step with the first, which is the failure class behind
# issues #93, #95 and #99. `$^` excludes order-only prerequisites, so it is
# exactly the object set; the recipe then hands ar65 the same set by name.
#
# WHY THIS EXISTS. `make verify` links two consumer stubs, and a member is
# only reachable through them if the stub imports a name from it. lib_version.o
# and lib_manifest.o are imported; precalc_manifest.o is NOT -- the SPEC §8.4
# LIB_PRECALC_* triple it carries is imported by no stub and no tool in this
# repo. It is also a member deliberately kept ISOLATED from lib_manifest.o
# (SPEC v1.2.0 §6.1), so nothing else drags it in. If that member silently
# stopped being archived, every existing gate stayed green. That is not
# hypothetical here: CLAUDE.md records a MEASURED make-3.81 failure in this
# repo where build/lib_version.o was deleted and not rebuilt, "silently
# dropping a member from the archive".
#
# TIMESTAMP-IMMUNE, on purpose. Archives are not byte-reproducible (issue #97,
# and the block above VERIFY_TARGETS in the Makefile): ca65 stamps the
# assembly second into every object and ar65's index carries each object
# file's mtime. This check reads the member NAME LIST, which carries no
# timestamp, so it cannot go intermittently red the way an archive-hash gate
# would.
set -e

fail() { echo "check_archive_members: FAIL -- $1" >&2; exit 1; }

if ! command -v ar65 >/dev/null 2>&1; then
  fail "ar65 not on PATH -- cannot read the member list, refusing to pass"
fi

ARCHIVE=$1
[ -n "$ARCHIVE" ] || fail "usage: check_archive_members.sh <archive.a> <expected .o> ..."
shift
[ -f "$ARCHIVE" ] || fail "$ARCHIVE does not exist"

# The expected set must be non-empty. An empty expectation would compare equal
# to an empty member list and the gate would pass having checked nothing --
# the vacuous-pass shape of issues #86 and #91.
[ $# -gt 0 ] || fail "$ARCHIVE: no expected members given (an empty expectation passes vacuously)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/archmembers.XXXXXX") || \
  fail "could not create a scratch directory"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

# ar65 t is the actual member list. Capture its exit status explicitly: a
# failing ar65 that printed nothing must not be read as "the archive is empty".
if ! ar65 t "$ARCHIVE" > "$WORK/actual.raw" 2> "$WORK/err"; then
  sed 's/^/  /' "$WORK/err" >&2
  fail "$ARCHIVE: ar65 t failed"
fi

sort < "$WORK/actual.raw" > "$WORK/actual"

# Likewise the observed set: zero members means ar65 read the archive and
# found nothing, which is a defect, not a match.
if [ ! -s "$WORK/actual" ]; then
  fail "$ARCHIVE: ar65 t listed no members at all"
fi

# Expected: basenames of the prerequisite object paths.
for obj in "$@"; do
  basename "$obj"
done | sort > "$WORK/expected"

if cmp -s "$WORK/expected" "$WORK/actual"; then
  echo "check_archive_members: $ARCHIVE -- $(wc -l < "$WORK/actual" | tr -d ' ') members, exactly as declared"
  exit 0
fi

echo "check_archive_members: FAIL -- $ARCHIVE does not contain the members its rule declares" >&2
comm -23 "$WORK/expected" "$WORK/actual" | sed 's/^/  MISSING from the archive:   /' >&2
comm -13 "$WORK/expected" "$WORK/actual" | sed 's/^/  UNEXPECTED in the archive: /' >&2
echo "  declared: $(tr '\n' ' ' < "$WORK/expected")" >&2
echo "  archived: $(tr '\n' ' ' < "$WORK/actual")" >&2
exit 1
