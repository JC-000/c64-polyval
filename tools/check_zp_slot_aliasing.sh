#!/bin/sh
# check_zp_slot_aliasing.sh -- pin for the §2 ZP slot distinctness assertions
# in src/zp_config.s (issue #105).
#
# §6.2 invites a consumer to relocate our 13 zero-page slots
# (`make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'`). Before #105 nothing
# checked the resulting addresses were distinct: two slots aliased onto one
# address assembled, archived, linked and passed every gate, and the library
# then computed incorrect POLYVAL. Wrong results from a green build.
#
# src/zp_config.s now asserts, at ASSEMBLY time, that every slot lies inside
# $02-$ff and that no two slots' byte ranges overlap. ($02, not $00: $00/$01
# are the 6510 data-direction register and processor port, so a slot parked
# there re-banks the machine on every store -- the same silent-corruption
# class, found by review of the first fix.) This script is the pin on those
# assertions. It has to exist because the assertions' normal state is
# "silent": a green `make` says nothing about whether they were evaluated.
#
# What it drives:
#   POSITIVE CONTROL  -D PV_ZP_SELFTEST=1 pushes one synthetic slot through
#                     the same two comparator macros the real checks use,
#                     broken both ways at once. It MUST fail. If it passes,
#                     the machinery is dead and every RED case below could be
#                     failing for some unrelated reason.
#   RED cases         each documented collision shape must fail assembly, and
#                     the diagnostic must name the slots. The case list below
#                     is the authority on which shapes and how many; it is not
#                     restated here, and not all of them come from #105 -- the
#                     $00/$01 processor-port cases came out of review of the
#                     first fix, which had an `addr >= 0` floor.
#   GREEN cases       the default build and every CONTRACT_ZP_DEFINES example
#                     in CLAUDE.md must still assemble.
#   MAKE LEG          `make lib` with an aliased override must fail too. Every
#                     leg above invokes ca65 on src/zp_config.s itself, which
#                     proves the assertions work but NOT that the build still
#                     routes CONTRACT_ZP_DEFINES to the TU carrying them. This
#                     leg is the only one that would go red if it stopped.
#
# Assembly time, not link time: `make lib CONTRACT_ZP_DEFINES=...` runs ca65
# and ar65 and never ld65, so a `.assert ..., lderror` would not fire on the
# build that mints the bad archive. Hence `error` severity, and hence the
# assertion legs above drive ca65 directly instead of going through a link --
# the one leg that does build (MAKE LEG) is checking the build wiring, not
# the assertions.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/src/zp_config.s"

# Private scratch tree per run (issue #93); the `build-scratch.` prefix is the
# ONE prefix `make clean`'s SCRATCH_TREES sweeps and tools/check_scratch_prefix.py
# asserts that agreement.
SCRATCH=$(mktemp -d "$ROOT/build-scratch.XXXXXX") || {
  echo "check_zp_slot_aliasing: FAIL -- could not create a scratch tree" >&2; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

fail() { echo "check_zp_slot_aliasing: FAIL -- $1" >&2; exit 1; }

# asm <outfile> <ca65 args...> -- assemble zp_config.s, stdout+stderr to
# $SCRATCH/last.log, return ca65's exit status. Deliberately not part of a
# `;`-chain: `X || (echo FAIL; exit 1)` inside one prints FAIL and exits 0
# (contract#193), so every caller below uses `if ! ...; then ... fi`.
asm() {
  out="$1"; shift
  set +e
  ca65 -I "$ROOT/src" "$@" -o "$SCRATCH/$out" "$SRC" >"$SCRATCH/last.log" 2>&1
  rc=$?
  set -e
  return $rc
}

# --- 0. Positive control ---------------------------------------------------
# Must FAIL, and must fail with BOTH diagnostics -- a range error and an
# overlap error. Checking only the exit status would accept a failure caused
# by, say, a typo in the file.
echo "check_zp_slot_aliasing: positive control (-D PV_ZP_SELFTEST=1 must fail)"
if asm selftest.o -D PV_ZP_SELFTEST=1; then
  fail "the -D PV_ZP_SELFTEST=1 positive control ASSEMBLED CLEANLY. The slot
  checks in src/zp_config.s are not being evaluated, so every green build below
  is vacuous and issue #105 is live again."
fi
if ! grep -q "PV_ZP_SELFTEST_SLOT is outside" "$SCRATCH/last.log"; then
  cat "$SCRATCH/last.log" >&2
  fail "the positive control failed, but not with the RANGE diagnostic -- the range check may be dead"
fi
if ! grep -q "PV_ZP_SELFTEST_SLOT .*OVERLAP" "$SCRATCH/last.log"; then
  cat "$SCRATCH/last.log" >&2
  fail "the positive control failed, but not with the OVERLAP diagnostic -- the pairwise check may be dead"
fi

# --- 1. RED cases ----------------------------------------------------------
# red <label> <expected substring> <ca65 args...>
red() {
  label="$1"; want="$2"; shift 2
  echo "check_zp_slot_aliasing: RED   $label"
  if asm red.o "$@"; then
    fail "$label ASSEMBLED CLEANLY (exit 0) -- this is the #105 defect: $*"
  fi
  if ! grep -q "$want" "$SCRATCH/last.log"; then
    cat "$SCRATCH/last.log" >&2
    fail "$label failed, but the diagnostic did not contain '$want'"
  fi
}

# 1a: two OVERRIDDEN slots aliased onto one address -- the case measured in #105.
red "two overridden slots on one address" \
    "polyval_acc (\$40, 16 bytes) and pv_mul_input (\$40, 16 bytes) OVERLAP" \
    -D polyval_acc=0x40 -D pv_mul_input=0x40

# 1b: one override landing on a slot the consumer did NOT override. Note $28 is
# not equal to any default address -- an equality-only check would pass this,
# while $28..$37 sits across pv_mul_input ($20..$2f) and pv_mul_nibble ($30).
red "override collides with a non-overridden slot" \
    "polyval_acc (\$28, 16 bytes) and pv_mul_input (\$20, 16 bytes) OVERLAP" \
    -D polyval_acc=0x28

# 1c: a slot pushed off the zero page. ca65 alone emits only a WARNING here
# ("absolute but exported zeropage") and exits 0.
red "slot pushed outside \$02-\$ff" \
    "polyval_zp_temp is outside \$02-\$ff" \
    -D polyval_zp_temp=0x100

# 1d: the last byte, not the first, has to fit -- the base address is in range.
red "slot whose last byte falls off the zero page" \
    "polyval_acc is outside \$02-\$ff" \
    -D polyval_acc=0xf8

# 1e/1f: $00 and $01 are the 6510 data-direction register and processor port --
# the bytes that bank BASIC/KERNAL/CHAREN/IO. A slot parked there assembles,
# archives and links, and every store to it re-banks the machine mid-multiply.
# Same silent-corruption class as the aliasing, so the floor is $02 and both
# addresses get their own case: an `addr >= 0` floor accepts both, and that is
# what shipped in the first cut of this fix.
red "slot on \$00 (6510 data-direction register)" \
    "polyval_zp_temp is outside \$02-\$ff" \
    -D polyval_zp_temp=0x00

red "slot on \$01 (6510 processor port)" \
    "polyval_zp_count is outside \$02-\$ff" \
    -D polyval_zp_count=0x01

# --- 2. GREEN cases --------------------------------------------------------
green() {
  label="$1"; shift
  echo "check_zp_slot_aliasing: GREEN $label"
  if ! asm green.o "$@"; then
    cat "$SCRATCH/last.log" >&2
    fail "$label must still assemble, but did not: $*"
  fi
}

green "default build, no overrides"
green "CLAUDE.md example: -D polyval_acc=0x40"          -D polyval_acc=0x40
green "CLAUDE.md example: -D LIB_NO_BARE_EXPORTS=1"     -D LIB_NO_BARE_EXPORTS=1
green "a full non-overlapping relayout"                 \
    -D polyval_acc=0x40 -D pv_mul_input=0x50 -D pv_mul_nibble=0x60
# Exactly abutting is legal, and is the boundary the >= comparisons turn on:
# pv_mul_input $31..$40 starts one byte past pv_mul_nibble ($30) and ends one
# byte before polyval_acc ($41..$50). Off by one either way and this goes red
# -- the first draft of this line used polyval_acc=0x40 and did, correctly.
green "slots abutting without overlap"                  -D polyval_acc=0x41 -D pv_mul_input=0x31

# --- 3. The export set is unchanged by all of this -------------------------
# The slot list drives the .exportzp block as well as the checks. That coupling
# is what keeps a newly added slot from escaping the checks silently, but it
# also means a mistake in the list would change the §2 ABI surface. Pin the
# count.
if ! asm exports.o; then fail "default assembly for the export count failed"; fi
n=$(od65 --dump-exports "$SCRATCH/exports.o" | grep -c "Name:")
if [ "$n" -ne 13 ]; then
  fail "zp_config.o exports $n zero-page symbols, expected 13 -- the §2 slot inventory changed"
fi

# --- 4. The whole thing through `make`, not just ca65 ----------------------
# Every leg above invokes ca65 on src/zp_config.s directly. That proves the
# assertions work, but NOT that the build still routes CONTRACT_ZP_DEFINES to
# the TU carrying them: a future Makefile change that stopped forwarding them
# to zp_config.o would leave every leg above green while `make lib` happily
# minted the aliased archive #105 is about. So drive the documented §6.2
# entry point end to end, once, and require it to fail.
#
# Uses a scratch BUILD_DIR so it cannot disturb build/ or race a concurrent
# `make verify` in the same tree, and `make clean` is NOT used -- it would
# sweep this run's own scratch tree (build-scratch.* is in SCRATCH_TREES).
echo "check_zp_slot_aliasing: RED   make lib with aliased CONTRACT_ZP_DEFINES"
set +e
make -C "$ROOT" BUILD_DIR="$(basename "$SCRATCH")/mk" lib \
     CONTRACT_ZP_DEFINES="-D polyval_acc=0x40 -D pv_mul_input=0x40" \
     >"$SCRATCH/make.log" 2>&1
mk_rc=$?
set -e
if [ $mk_rc -eq 0 ]; then
  fail "\`make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40 -D pv_mul_input=0x40'\`
  SUCCEEDED. The assertions in src/zp_config.s pass their direct ca65 legs but
  the build is no longer delivering CONTRACT_ZP_DEFINES to the TU that carries
  them, so a consumer can still mint an aliased archive -- issue #105 is live
  through the documented entry point."
fi
if ! grep -q "polyval_acc.*pv_mul_input.*OVERLAP" "$SCRATCH/make.log"; then
  cat "$SCRATCH/make.log" >&2
  fail "\`make lib\` with aliased overrides failed, but not with the OVERLAP diagnostic -- it may be failing for an unrelated reason"
fi

echo "check_zp_slot_aliasing: PASS -- positive control fires, 6 red cases + the make leg fail, 5 green cases assemble, 13 exports"
