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

# exports of a given object in the scratch tree
zp_exports()   { od65 --dump-exports "$SCRATCH/zp_config.o"  | grep -c 'Name:' || true; }
bare_exports() { od65 --dump-exports "$SCRATCH/lib_version.o" \
                   | grep -cE '"LIB_(VERSION|ABI)' || true; }

SELFTEST=${1:-}

rm -rf "$SCRATCH"
$MAKE_Q lib >/dev/null 2>&1 || fail "baseline build failed"

# --- baseline: both knobs off, artifacts in their default shape -------------
[ "$(zp_exports)" = "13" ]  || fail "baseline zp_config.o exports $(zp_exports), expected 13"
[ "$(bare_exports)" = "4" ] || fail "baseline lib_version.o bare exports $(bare_exports), expected 4"

if [ "$SELFTEST" = "--selftest" ]; then
  # Disable the stamp without touching the Makefile: a command-line variable
  # overrides the `:=` assignment, and command-line variables are recursively
  # expanded, so CONTRACT_FLAGS_WAS='$(CONTRACT_FLAGS_NOW)' makes the parse-time
  # comparison compare a value to itself. It can never differ, so nothing is
  # ever invalidated -- a genuine disable of exactly the mechanism under test,
  # with no hardcoded flag string to drift.
  $MAKE_Q lib CONTRACT_DEFINES="-D ZP_CONFIG_NO_EXPORTS=1" \
          CONTRACT_FLAGS_WAS='$(CONTRACT_FLAGS_NOW)' >/dev/null 2>&1 || true
  if [ "$(zp_exports)" = "0" ]; then
    fail "SELFTEST: stamp was disabled but the artifact still flipped -- the pin is not testing the stamp"
  fi
  echo "check_knob_staleness: selftest OK (disabled stamp correctly leaves zp_config.o at $(zp_exports), pin would fail)"
  exit 0
fi

# --- C2 forward: warm tree + knob must flip the ARTIFACT ---------------------
$MAKE_Q lib CONTRACT_DEFINES="-D ZP_CONFIG_NO_EXPORTS=1" >/dev/null 2>&1 \
  || fail "warm build with ZP_CONFIG_NO_EXPORTS failed"
[ "$(zp_exports)" = "0" ] \
  || fail "warm ZP_CONFIG_NO_EXPORTS=1 left zp_config.o at $(zp_exports) exports, expected 0 (issue #58)"

$MAKE_Q lib CONTRACT_DEFINES="-D LIB_NO_BARE_EXPORTS=1" >/dev/null 2>&1 \
  || fail "warm build with LIB_NO_BARE_EXPORTS failed"
[ "$(bare_exports)" = "0" ] \
  || fail "warm LIB_NO_BARE_EXPORTS=1 left lib_version.o at $(bare_exports) bare exports, expected 0"

# --- C2 reverse: removing the knob must flip back ---------------------------
# The direction a consumer hits when they finish debugging and drop the flag.
$MAKE_Q lib >/dev/null 2>&1 || fail "warm build with knobs removed failed"
[ "$(zp_exports)" = "13" ]  || fail "knob removal left zp_config.o at $(zp_exports), expected 13"
[ "$(bare_exports)" = "4" ] || fail "knob removal left lib_version.o at $(bare_exports), expected 4"

# --- no member silently dropped ---------------------------------------------
# The failure mode of the rejected delete-from-a-rule-prerequisite mechanism:
# an object deleted and then not rebuilt, silently missing from the archive.
n=$(ls "$SCRATCH"/*.o 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = "9" ] || fail "expected 9 objects after knob transitions, found $n"

# --- C1: an unchanged invocation must NOT rebuild ---------------------------
# Guards against "unconditional rebuild wearing a stamp", which would satisfy
# every assertion above while destroying incremental builds.
rebuilt=$($MAKE_Q lib 2>&1 | grep -c '^ca65' || true)
[ "$rebuilt" = "0" ] || fail "unchanged invocation recompiled $rebuilt TUs, expected 0 (SPEC §6.3 C1)"

# --- #56 reject branch must remain intact -----------------------------------
if $MAKE_Q lib CONTRACT_DEFINES="-D POLYVAL_PROFILE=1" >/dev/null 2>&1; then
  fail "member-set axis via CONTRACT_DEFINES was accepted; the issue #55 guard has regressed"
fi

echo "check_knob_staleness: OK (warm flip both knobs, reverse, 9 objects, 0 spurious rebuilds, #55 guard intact)"
