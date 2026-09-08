#!/bin/sh
# check_archive_members.sh -- assert an archive ships the members it must, and
# exactly the members its own rule declared (issue #97).
#
#   check_archive_members.sh --require "<name.o> ..." <archive.a> <declared .o path> ...
#
# Called from every archive recipe as
#
#   $(TOOLS_DIR)/check_archive_members.sh --require "$(LIB_CONTRACT_MEMBERS)" $@ $^
#
# TWO ASSERTIONS, AND THEY ARE NOT THE SAME ASSERTION. The first is the one
# that does the work; the second is nearly free and catches a different shape.
#
#   1. REQUIRED FLOOR -- every name in --require is in the archive. The list
#      comes from LIB_CONTRACT_MEMBERS, which is written out by name next to
#      LIB_CORE_OBJS and is deliberately NOT derived from it. That
#      independence is the whole point: the first cut of this script checked
#      only assertion 2, and adversarial review broke it in one edit --
#      deleting precalc_manifest.o from LIB_CORE_OBJS shipped a 9-member
#      polyval.a while the check printed "9 members, exactly as declared" and
#      exited 0. Expectation and reality were the same expression, so the
#      tautology that made it drift-free also made it blind.
#
#   2. DECLARED SET -- `ar65 t` equals this rule's own prerequisite list, `$^`
#      (which excludes order-only prerequisites, so it is exactly the object
#      set the recipe then hands ar65 by name). Being a tautology in the
#      source is what makes it free of a second list to drift; it catches the
#      cases where the artifact does NOT match the list make itself used --
#      an object silently not archived, or an ar65 invocation that filters
#      the set. CLAUDE.md records a MEASURED make-3.81 failure of exactly
#      that kind in this repo, where build/lib_version.o was deleted and not
#      rebuilt, "silently dropping a member from the archive".
#
# WHY A FLOOR IS NEEDED AT ALL. `make verify` links three consumer stubs, and
# a member is reachable through them only if a stub imports a name from it.
# Three of the four contract members are: lib_version.o (§1 version equates),
# lib_manifest.o (§5 footprint equates) and zp_config.o (consumer_stub_
# shipped.s .importzp's from it). precalc_manifest.o is NOT -- the SPEC §8.4
# LIB_PRECALC_* / LIB_POLYVAL_PRECALC_* names it carries are imported by no
# stub and no tool here, and it is deliberately kept ISOLATED from
# lib_manifest.o (SPEC v1.2.0 §6.1) so nothing else drags it in. Drop it and
# every link gate stays green.
#
# SCOPE -- this is a RECIPE-TIME check, not a state invariant over the file on
# disk. It runs when a recipe builds an archive. `ar65 d build/lib/polyval.a
# precalc_manifest.o` followed by `make lib` on a warm tree prints "Nothing to
# be done" and runs no check at all; the mutilated archive is still there.
# Rebuild (or `make clean`) if you need the assertion re-established.
#
# TIMESTAMP-IMMUNE, on purpose. Archives are not byte-reproducible (issue #97,
# and the block above VERIFY_TARGETS in the Makefile): ca65 stamps the
# assembly second into every object and ar65's index carries each object
# file's mtime. This check reads the member NAME LIST, which carries no
# timestamp, so it cannot go intermittently red the way an archive-hash gate
# would.
set -e

fail() { echo "check_archive_members: FAIL -- $1" >&2; exit 1; }

REQUIRED=""
if [ "${1:-}" = "--require" ]; then
  REQUIRED=$2
  shift 2
fi

if ! command -v ar65 >/dev/null 2>&1; then
  fail "ar65 not on PATH -- cannot read the member list, refusing to pass"
fi

ARCHIVE=${1:-}
[ -n "$ARCHIVE" ] || fail "usage: check_archive_members.sh [--require \"a.o ...\"] <archive.a> <declared .o> ..."
shift
[ -f "$ARCHIVE" ] || fail "$ARCHIVE does not exist"

# Both expectations must be non-empty. An empty one would compare equal to an
# empty member list and the gate would pass having checked nothing -- the
# vacuous-pass shape of issues #86 and #91.
[ -n "$REQUIRED" ] || fail "$ARCHIVE: --require list is empty (an empty floor asserts nothing)"
[ $# -gt 0 ] || fail "$ARCHIVE: no declared members given (an empty expectation passes vacuously)"

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

# --- assertion 1: the required floor ---------------------------------------
missing=""
for want in $REQUIRED; do
  if ! grep -qx -- "$want" "$WORK/actual"; then
    missing="$missing $want"
  fi
done
if [ -n "$missing" ]; then
  echo "check_archive_members: FAIL -- $ARCHIVE is missing a member every archive MUST ship" >&2
  for m in $missing; do
    echo "  MISSING (required by LIB_CONTRACT_MEMBERS): $m" >&2
  done
  echo "  archived: $(tr '\n' ' ' < "$WORK/actual")" >&2
  exit 1
fi

# --- assertion 2: the declared set -----------------------------------------
for obj in "$@"; do
  basename "$obj"
done | sort > "$WORK/expected"

if ! cmp -s "$WORK/expected" "$WORK/actual"; then
  echo "check_archive_members: FAIL -- $ARCHIVE does not contain the members its rule declares" >&2
  comm -23 "$WORK/expected" "$WORK/actual" | sed 's/^/  MISSING from the archive:   /' >&2
  comm -13 "$WORK/expected" "$WORK/actual" | sed 's/^/  UNEXPECTED in the archive: /' >&2
  echo "  declared: $(tr '\n' ' ' < "$WORK/expected")" >&2
  echo "  archived: $(tr '\n' ' ' < "$WORK/actual")" >&2
  exit 1
fi

echo "check_archive_members: $ARCHIVE -- $(wc -l < "$WORK/actual" | tr -d ' ') members, as declared, contract floor present"
