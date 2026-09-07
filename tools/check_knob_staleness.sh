#!/bin/sh
# check_knob_staleness.sh -- pin for the SPEC §6.3 invalidate branch (issue #58).
#
# §6.3 states two properties for a configuration knob that the build CAN honor:
#
#   C1  an unchanged invocation MUST NOT rebuild
#   C2  whatever pins it MUST assert the ARTIFACT flipped -- not merely that
#       something rebuilt
#
# C2 is the reason this script reads od65 export counts rather than watching for
# ca65 lines: "make rebuilt something" is satisfied by an unconditional rebuild
# wearing a stamp, which would pass a naive check while destroying incremental
# builds. Every assertion below is on the artifact.
#
# Runs against a scratch BUILD_DIR so it cannot disturb build/ -- lib-verify's
# own PRG is already built by the time this leg runs.
#
# Self-check: `check_knob_staleness.sh --selftest` re-runs the warm-flip
# assertion with the stamp disabled and requires it to FAIL. A pin that cannot
# fail is not a pin; x25519's first attempt at this disabled the stamp with an
# always-true condition, passed, and meant nothing.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH="$ROOT/build-knobcheck"
MAKE_Q="make -C $ROOT BUILD_DIR=build-knobcheck"
fail() { echo "check_knob_staleness: FAIL -- $1" >&2; exit 1; }
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# --- export inspection (issues #86, #90) ------------------------------------
# These used to be two one-liners ending in `| grep -c ... || true`, which
# answered "0" for THREE different situations: exports genuinely suppressed,
# the object missing, and od65 not running at all. Every assertion whose pass
# condition is a zero was therefore satisfiable by a broken build. Measured:
#   $ od65 --dump-exports /nonexistent.o 2>/dev/null | grep -c 'Name:' || true
#   0
# Two accidental positive controls (the baseline 13/4 assertions, and the
# 10-object count) stood in front of it, so it was latent rather than live --
# but "latent" is not a property to rely on. c64-lib-contract#194 and
# c64-x25519#133 are the same defect in two sibling repos; contract PR#197 is
# the fix this follows: RECONCILE a population, never count to zero.
#
# dump_to writes an object's export dump to a file and distinguishes its
# failure modes by exit status, so the caller can say WHICH thing broke.
dump_to() {   # $1 = object, $2 = destination file
  if [ ! -f "$1" ]; then return 3; fi
  if ! od65 --dump-exports "$1" >"$2" 2>"$2.err"; then return 4; fi
  # od65 states its own export count. If our parse disagrees with it, the
  # parse is wrong and every count derived from it is untrustworthy.
  declared=$(sed -n 's/^ *Count: *\([0-9][0-9]*\).*/\1/p' "$2" | head -1)
  case "$declared" in ''|*[!0-9]*) return 5 ;; esac
  parsed=$(sed -n 's/.*Name: *"\([^"]*\)".*/\1/p' "$2" | grep -c . || true)
  [ "$parsed" = "$declared" ] || return 6
  return 0
}

# Dump or fail, naming the failure. MUST be called from the main shell, never
# inside $( ): `fail` exits, and an exit inside a command substitution only
# ends the subshell -- the script would carry on with an empty count and
# report the wrong thing. Each object gets its own dump file so the counting
# helpers below can never read a dump of some other object.
dump_or_fail() {  # $1 = object, $2 = label
  dump_to "$1" "$SCRATCH/dump.$2.txt" && return 0
  st=$?
  case "$st" in
    3) fail "$2: object '$1' does not exist -- a member was dropped or the build did not run (this is NOT 'zero exports')" ;;
    4) fail "$2: od65 failed on '$1' -- $(head -1 "$SCRATCH/dump.$2.txt.err" 2>/dev/null)" ;;
    5) fail "$2: could not read an export Count from od65's dump of '$1'" ;;
    6) fail "$2: parsed $parsed export names but od65 declared $declared for '$1' -- the extractor is wrong, so no count below can be trusted" ;;
    *) fail "$2: dump of '$1' failed with status $st" ;;
  esac
}

# Re-dump every object this script asserts on. Called after each build so a
# count can never be read from a previous build's dump.
dump_all() {
  dump_or_fail "$SCRATCH/zp_config.o"   zp_config
  dump_or_fail "$SCRATCH/lib_version.o" lib_version
}

# Counts, taken from an already-reconciled dump file.
n_matching() { grep -cE "$1" "$SCRATCH/dump.$2.txt" || true; }

zp_exports() { n_matching 'Name:' zp_config; }
# The gate must be checked for what it KEEPS, not only for what it removes
# (issue #90, c64-nist-curves#158). Moving `.export LIB_POLYVAL_VERSION_PATCH`
# inside the .ifndef block dropped it from the composing mode entirely while
# every guard here stayed green; a consumer building with
# -D LIB_NO_BARE_EXPORTS=1 -- the whole point of the switch -- would then get
# an undefined symbol from a library reporting OK.
bare_exports()     { n_matching '"LIB_(VERSION|ABI)' lib_version; }
prefixed_exports() { n_matching '"LIB_POLYVAL_(VERSION|ABI)' lib_version; }

SELFTEST=${1:-}

rm -rf "$SCRATCH"
$MAKE_Q lib >/dev/null 2>&1 || fail "baseline build failed"
dump_all

# --- baseline: both knobs off, artifacts in their default shape -------------
[ "$(zp_exports)" = "13" ]  || fail "baseline zp_config.o exports $(zp_exports), expected 13"
[ "$(bare_exports)" = "4" ] || fail "baseline lib_version.o bare exports $(bare_exports), expected 4"
[ "$(prefixed_exports)" = "4" ] \
  || fail "baseline lib_version.o prefixed exports $(prefixed_exports), expected 4"

if [ "$SELFTEST" = "--selftest" ]; then
  # Disable the stamp without touching the Makefile: a command-line variable
  # overrides the `:=` assignment, and command-line variables are recursively
  # expanded, so CONTRACT_FLAGS_WAS='$(CONTRACT_FLAGS_NOW)' makes the parse-time
  # comparison compare a value to itself. It can never differ, so nothing is
  # ever invalidated -- a genuine disable of exactly the mechanism under test,
  # with no hardcoded flag string to drift.
  # Not `|| true`: with the stamp disabled this build is expected to be a
  # no-op, and a no-op exits 0. Swallowing the status meant a build that
  # failed outright left dump_all reading the BASELINE objects, and the
  # selftest concluded "disabled stamp correctly leaves 13" from a build that
  # never ran. Measured: make shimmed to fail here -> "selftest OK", exit 0.
  $MAKE_Q lib CONTRACT_DEFINES="-D ZP_CONFIG_NO_EXPORTS=1" \
          CONTRACT_FLAGS_WAS='$(CONTRACT_FLAGS_NOW)' >"$SCRATCH/selftest.log" 2>&1 \
    || fail "SELFTEST: the stamp-disabled build failed -- $(tail -1 "$SCRATCH/selftest.log")"
  dump_all
  if [ "$(zp_exports)" = "0" ]; then
    fail "SELFTEST: stamp was disabled but the artifact still flipped -- the pin is not testing the stamp"
  fi
  echo "check_knob_staleness: selftest OK (disabled stamp correctly leaves zp_config.o at $(zp_exports), pin would fail)"
  exit 0
fi

# --- C2 forward: warm tree + knob must flip the ARTIFACT ---------------------
$MAKE_Q lib CONTRACT_DEFINES="-D ZP_CONFIG_NO_EXPORTS=1" >/dev/null 2>&1 \
  || fail "warm build with ZP_CONFIG_NO_EXPORTS failed"
dump_all
[ "$(zp_exports)" = "0" ] \
  || fail "warm ZP_CONFIG_NO_EXPORTS=1 left zp_config.o at $(zp_exports) exports, expected 0 (issue #58)"

$MAKE_Q lib CONTRACT_DEFINES="-D LIB_NO_BARE_EXPORTS=1" >/dev/null 2>&1 \
  || fail "warm build with LIB_NO_BARE_EXPORTS failed"
dump_all
[ "$(bare_exports)" = "0" ] \
  || fail "warm LIB_NO_BARE_EXPORTS=1 left lib_version.o at $(bare_exports) bare exports, expected 0"
# What the gate must KEEP (#90). Without this, the whole leg above is
# satisfied by an object that lost the prefixed surface too -- or by no
# object at all, before dump_or_fail existed.
[ "$(prefixed_exports)" = "4" ] \
  || fail "warm LIB_NO_BARE_EXPORTS=1 left lib_version.o at $(prefixed_exports) PREFIXED exports, expected 4 -- the gate removed what it must keep (issue #90)"

# --- C2 reverse: removing the knob must flip back ---------------------------
# The direction a consumer hits when they finish debugging and drop the flag.
$MAKE_Q lib >/dev/null 2>&1 || fail "warm build with knobs removed failed"
dump_all
[ "$(zp_exports)" = "13" ]  || fail "knob removal left zp_config.o at $(zp_exports), expected 13"
[ "$(bare_exports)" = "4" ] || fail "knob removal left lib_version.o at $(bare_exports), expected 4"
[ "$(prefixed_exports)" = "4" ] \
  || fail "knob removal left lib_version.o at $(prefixed_exports) prefixed, expected 4"

# --- no member silently dropped ---------------------------------------------
# The failure mode of the rejected delete-from-a-rule-prerequisite mechanism:
# an object deleted and then not rebuilt, silently missing from the archive.
# The count is LIB_AEAD_OBJS: lib_version, zp_config, lib_manifest,
# precalc_manifest, data, tables, aes_encrypt, aes_decrypt, gcm_siv,
# polyval_long. It moved 9 -> 10 when the SPEC v1.2.0 §6.1 member-isolation
# split gave the §8.0 precalc enumeration its own TU; bump it with the member
# set, never to make a failure go away.
n=$(ls "$SCRATCH"/*.o 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = "10" ] || fail "expected 10 objects after knob transitions, found $n"

# --- C1: an unchanged invocation must NOT rebuild ---------------------------
# Guards against "unconditional rebuild wearing a stamp", which would satisfy
# every assertion above while destroying incremental builds.
# The status of `make` is captured SEPARATELY. Written as
# `rebuilt=$(... | grep -c '^ca65' || true)` this was the #86 defect, live:
# the assignment takes the pipeline's last status, `|| true` forces that to 0,
# and `2>&1` folds make's errors into grep's input where they match nothing.
# Measured -- with make shimmed to fail silently on this invocation, the
# script printed "0 spurious rebuilds" and exited 0, asserting a property
# about a build that never happened.
$MAKE_Q lib >"$SCRATCH/c1.log" 2>&1 \
  || fail "C1: the unchanged invocation FAILED to build -- $(tail -1 "$SCRATCH/c1.log")"
rebuilt=$(grep -c '^ca65' "$SCRATCH/c1.log" || true)
[ "$rebuilt" = "0" ] || fail "unchanged invocation recompiled $rebuilt TUs, expected 0 (was SPEC §6.3 C1; clause retired at contract v1.0.0, check kept as local engineering)"

# --- #56 reject branch must remain intact -----------------------------------
# Assert the rejection's IDENTITY, not merely a non-zero exit. "make failed"
# is satisfied by any failure at all -- a broken Makefile, a typo in an
# unrelated target, a missing assembler -- so the old form reported "#55 guard
# intact" while the guard was regressed, whenever something else happened to
# be broken. Measured, with the rejection simulated away and an unrelated
# ca65 failure injected: exit 0, "#55 guard intact". The control (same setup,
# healthy ca65) correctly failed, which is what proved the shim honest.
if $MAKE_Q lib CONTRACT_DEFINES="-D POLYVAL_PROFILE=1" >"$SCRATCH/reject.log" 2>&1; then
  fail "member-set axis via CONTRACT_DEFINES was ACCEPTED; the issue #55 guard has regressed"
fi
grep -q 'member-set axis \[POLYVAL_PROFILE\] cannot be set through' "$SCRATCH/reject.log" \
  || fail "the #55 build failed, but NOT with the member-set parse-time rejection -- something else is broken, and this leg cannot vouch for the guard. Last line: $(tail -1 "$SCRATCH/reject.log")"

echo "check_knob_staleness: OK (warm flip both knobs incl. the kept prefixed surface, reverse, 10 objects, 0 spurious rebuilds, #55 guard intact)"
