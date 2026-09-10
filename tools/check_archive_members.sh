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
# WHY NOT COVER THE MEMBER WITH A STUB IMPORT INSTEAD. The elegant
# alternative is to have a consumer stub `.import` a name from
# precalc_manifest.o, so ld65 fails if the member is gone. Rejected on
# ARITHMETIC, not on safety. Only 4 of the 7 archives are linked by any gate:
# polyval.a (consumer-check-shipped) and the three NO_AES archives
# (consumer-check-noaes). consumer-check links LOOSE OBJECTS, $(LIB_OBJECTS),
# not an archive, and nothing links polyval-gcmsiv.a, -gcmsiv-short.a or
# -gcmsiv-compact.a. So imports in both stubs would cover at best 4 of 7
# archives and 1 of the 4 contract members, while the floor covers 4 members
# in all 7. It would also argue against the §6.1 member isolation that is
# precalc_manifest.o's whole reason for being a separate member.
#   Correction, recorded because this repo re-derives recorded reasons: the
#   commit that added the floor also claimed the import would be unsafe under
#   composition, because the natural name comes from the triple that
#   LIB_NO_BARE_EXPORTS suppresses. That is FALSE. src/precalc_table.inc
#   emits the PREFIXED LIB_%s_PRECALC_%s_* triple outside the
#   `.ifndef LIB_NO_BARE_EXPORTS` block, gated only on a non-blank lib
#   argument -- `od65 --dump-exports build/precalc_manifest.o` lists
#   LIB_POLYVAL_PRECALC_aes_sbox_SIZE unconditionally. Importing the prefixed
#   form is safe. The decision stands on the two reasons above.
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
#
# Count the floor by WORD-SPLITTING it, not with [ -n ]. `--require "   "` is
# non-empty as a string but iterates zero times, so the floor asserted nothing
# and the script still printed "contract floor present" -- measured. It is
# reachable from a plausible edit: LIB_CONTRACT_MEMBERS = $(CONTRACT_EXTRA)
# with CONTRACT_EXTRA undefined hands this call site a blank argument.
[ $# -gt 0 ] || fail "$ARCHIVE: no declared members given (an empty expectation passes vacuously)"
# count_words is a function so the word-split happens on ITS positional
# parameters -- `set -- $REQUIRED` here would clobber the declared object
# list that assertion 2 still needs.
count_words() { echo $#; }
if [ "$(count_words $REQUIRED)" -eq 0 ]; then
  fail "$ARCHIVE: --require list is empty or blank (an empty floor asserts nothing)"
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/archmembers.XXXXXX") || \
  fail "could not create a scratch directory"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

# --- POSITIVE CONTROL ------------------------------------------------------
# Both assertions below are string comparisons. A string comparison that has
# quietly stopped comparing passes exactly like a correct archive, and no
# mutation of the LIBRARY can reveal that -- the code under test here is
# `grep -qxF` and `cmp`. So drive both over synthetic member lists first, and
# refuse to report on the real archive if either fails to notice a defect.
#
# Arms 2 and 3 are this script's own MEASURED regressions, promoted from
# comments into assertions: an archive holding lib_versionXo once satisfied a
# floor asking for lib_version.o (missing -F), and the declared-set comparison
# is the half that caught a member silently not archived.
SELF=$WORK/selftest
mkdir -p "$SELF"
printf 'a.o\nb.o\n' > "$SELF/actual"

# 1. a name that is ABSENT must be reported absent.
if grep -qxF -- "c.o" "$SELF/actual"; then
  fail "POSITIVE CONTROL: the floor matcher found 'c.o' in a list that does not contain it -- it is not comparing, so 'contract floor present' below would mean nothing"
fi
# 2. '.' must not match any character (the -F property, measured).
printf 'lib_versionXo\n' > "$SELF/dotted"
if grep -qxF -- "lib_version.o" "$SELF/dotted"; then
  fail "POSITIVE CONTROL: 'lib_version.o' matched 'lib_versionXo' -- the floor is being matched as a regex, so a wrongly-named member would satisfy it"
fi
# 3. a name that IS present must be found (a matcher that always fails would
#    pass arms 1 and 2 while asserting nothing).
if ! grep -qxF -- "a.o" "$SELF/actual"; then
  fail "POSITIVE CONTROL: the floor matcher did not find 'a.o' in a list containing it -- it always fails, so arms 1 and 2 prove nothing"
fi
# 4. the declared-set comparison must notice a surplus member.
printf 'a.o\n' > "$SELF/expected"
if cmp -s "$SELF/expected" "$SELF/actual"; then
  fail "POSITIVE CONTROL: cmp called a 1-member list equal to a 2-member list -- the declared-set assertion is dead"
fi
rm -rf "$SELF"

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
  # -F: the names contain '.', which a BRE would match against any character.
  # Measured: without -F, an archive holding lib_versionXo satisfied a floor
  # asking for lib_version.o.
  if ! grep -qxF -- "$want" "$WORK/actual"; then
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

echo "check_archive_members: $ARCHIVE -- $(wc -l < "$WORK/actual" | tr -d ' ') members, as declared, contract floor present, 4 positive controls fired"
