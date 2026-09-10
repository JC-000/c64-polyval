#!/bin/sh
# check_harness_routing.sh -- pin the single chokepoint for device traffic.
#
# WHY THIS EXISTS
#
# Every host->C64 request this repo makes must be routed by c64-test-harness,
# so that chunking, /Temp hygiene and DeviceLock live in ONE place below us
# and a fleet-wide mitigation lands in one repo instead of six. The failure
# this guards against is not hypothetical: the C64 Ultimate (fw 1.1.0, CBM
# generation) never collects the managed /Temp attachments left by
# body-carrying REST calls, ~15 PRG-sized uploads wedge REST and the UCI
# bridge together, and only a physical power-cycle recovers. A 2026-08/09
# wedge cost about two weeks of a shared device.
#
# The audit of 2026-09-10 found this repo CLEAN -- zero direct-transport
# calls, VICE-only, every blob <=128 bytes on the wire. This script exists to
# keep it that way, because the property is invisible from a green build: the
# suite passes identically whether a write went through write_bytes() or
# around it.
#
# WHAT IT BANS, AND WHY EACH ONE
#
#   .write_memory(     the raw transport write. Bypasses write_bytes()'s
#                      84-byte chunker (memory.py:154,159) entirely. Safe
#                      only while the blob is small -- and nothing checks
#                      that it stays small.
#   load_code(         a bare alias for transport.write_memory despite the
#                      name (execute.py:110). It does NOT chunk.
#   run_prg/load_prg/  the body-carrying POST verbs
#   run_crt/sidplay/   (ultimate64_client.py:936,1054,1079,1089,1097, all via
#   modplay/           _post_binary). These are the ones that leak an
#   mount_disk         attachment per call. ~15 of them is the wedge.
#   Ultimate64Client(  direct device-client construction, reaching around the
#   Ultimate64*(       manager that would otherwise hold the DeviceLock.
#   UnifiedManager(    backend-dispatching constructors: with C64_BACKEND=u64
#   create_manager(    these select hardware. Legitimate someday, but not
#                      without the standing clause in CLAUDE.md being read
#                      first -- so they trip the gate deliberately.
#   pkill/killall      broad-pattern process kills, which clobber other
#                      agents' emulator instances on this shared machine.
#
# NOTE ON SCOPE: `jsr()` itself bypasses the chunker inside the harness
# (execute.py:344, a 5-byte trampoline; the U64 path at :733/:737 is 2 and 14
# bytes). That is a harness-layer property and is NOT this script's business
# -- per the standing clause, hygiene belongs one layer down. We ban the
# direct call sites that are ours to control.
#
# WHAT IT DRIVES
#
#   POSITIVE CONTROL  a synthetic violating file is planted in the REAL scan
#                     directory and the REAL scan is run over it. It MUST be
#                     caught. If it is not, the scanner is dead and the clean
#                     result below means nothing. This is the #86/#91 shape:
#                     a gate whose expectation is satisfied vacuously.
#   VACUITY GUARD     an empty file set is a FAILURE, not a pass. A scan that
#                     matched nothing because it looked at nothing compares
#                     equal to a clean tree.
#   REAL SCAN         tools/*.py and test/*.py must be clean.
#
# Comment-only lines are exempt so the prose above (and in the tools) does not
# trip the gate; a trailing comment on a real call site does not save it,
# because the call text still appears before the '#'.
#
# Full statement of the hardware constraint: CLAUDE.md section
# "Do not wedge the C64U". Retires when DeviceCapabilities.writemem_post_safe
# is True for the device (_CBM_WRITEMEM_FIXED_FROM in u64_capabilities.py).
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

SELFTEST="tools/.harness_routing_selftest.py"

cleanup() {
    rm -f "$SELFTEST"
}
trap cleanup EXIT INT TERM HUP

BANNED='\.write_memory\(|[^_a-zA-Z]load_code\(|\.run_prg\(|\.load_prg\(|\.run_crt\(|\.sidplay\(|\.modplay\(|\.mount_disk\(|Ultimate64Client\(|Ultimate64Transport\(|Ultimate64InstanceManager\(|UnifiedManager\(|create_manager\(|pkill|killall'

# Scan the given files, ignoring comment-only lines. Prints offending
# file:line:text. Returns 0 when clean, 1 when a violation was found.
scan() {
    hits=$(grep -n -E "$BANNED" "$@" 2>/dev/null | grep -vE '^[^:]+:[0-9]+: *#' || true)
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits"
        return 1
    fi
    return 0
}

FILES=$(find tools test -name '*.py' -not -path '*/__pycache__/*' 2>/dev/null | sort)

# --- VACUITY GUARD --------------------------------------------------------
if [ -z "$FILES" ]; then
    echo "FAIL: no Python files found under tools/ or test/ -- the scan set is"
    echo "      empty, so a clean result would be vacuous. Check the paths."
    exit 1
fi

COUNT=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')

# --- POSITIVE CONTROL -----------------------------------------------------
# Planted in the real directory so the real find/scan pair must see it.
cat > "$SELFTEST" <<'EOF'
# synthetic violation -- check_harness_routing.sh positive control
def _control(transport):
    transport.write_memory(0xC000, b"\x00" * 200)
EOF

CONTROL_FILES=$(find tools test -name '*.py' -not -path '*/__pycache__/*' 2>/dev/null | sort)
if ! printf '%s\n' "$CONTROL_FILES" | grep -q "$SELFTEST"; then
    echo "FAIL: positive control was planted but the file scan did not pick it"
    echo "      up. The scanner is not looking where it thinks it is."
    exit 1
fi

if scan $CONTROL_FILES >/dev/null 2>&1; then
    echo "FAIL: positive control was NOT caught. The scanner is dead --"
    echo "      a clean result from it proves nothing. Expected"
    echo "      '$SELFTEST' to trip the banned-pattern scan."
    exit 1
fi

rm -f "$SELFTEST"

# --- REAL SCAN ------------------------------------------------------------
if ! scan $FILES; then
    echo ""
    echo "FAIL: device traffic must be routed by c64-test-harness."
    echo ""
    echo "  Use write_bytes()/read_bytes() rather than transport.write_memory()"
    echo "  or load_code(): the harness chunks at 84 bytes, below the C64U's"
    echo "  128-byte PUT/POST boundary, so routed writes leave no /Temp"
    echo "  attachment behind. A direct call is unchunked and silently leaks"
    echo "  one attachment per call above 128 bytes; ~15 wedge the device and"
    echo "  only a physical power-cycle recovers it."
    echo ""
    echo "  For a manager or an upload verb, read CLAUDE.md section"
    echo "  \"Do not wedge the C64U\" before going further."
    exit 1
fi

echo "check-harness-routing: OK ($COUNT files scanned, positive control caught)"
