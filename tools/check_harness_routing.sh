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

# --- THE BAN TABLE, WHICH IS ALSO THE CONTROL CORPUS ----------------------
# ONE list. The alternation the real scan uses is BUILT from these rows, and
# the positive control plants EVERY row's fixture and asserts each is caught.
#
# This is the review finding that rewrote this section. The first cut kept a
# hand-written alternation and a control that planted a single
# `.write_memory(` violation. An adversarial reviewer set the alternation to
# `\.write_memory\(|ZZZNEVERMATCH` -- killing 13 of 15 bans -- appended
# run_prg / UnifiedManager() / pkill to tools/run_all_tests.py, and got
# "check-harness-routing: OK (14 files scanned, positive control caught)",
# exit 0. A control that models one alternative and certifies fifteen IS the
# vacuous-pass shape this script's header claims to defeat.
#
# Each row is  <pattern> <TAB> <fixture>.  The fixture carries a literal `@@`
# which is stripped before use: without it the fixtures below would be real
# violations sitting in a file this scan now reads (tools/*.sh is in scope),
# and the gate would flag itself. The controls prove each de-obfuscated
# fixture is caught, so a split that stopped reconstructing one goes red
# rather than quietly testing nothing.
ban_table() {
    cat <<'TABLE'
\.write_memory[[:space:]]*\(	transport.write_me@@mory(0xC000, b"x" * 200)
\.write_memory[[:space:]]*\\$	transport.write_me@@mory \
(^|[^_a-zA-Z.])load_code[[:space:]]*\(	load_co@@de(t, 0xC000, b"x")
getattr\([^)]*write_memory	getattr(transp@@ort, "write_memory")(0, b"x")
\.run_prg[[:space:]]*\(	client.run_p@@rg(prg_bytes)
\.load_prg[[:space:]]*\(	client.load_p@@rg(prg_bytes)
\.run_crt[[:space:]]*\(	client.run_c@@rt(crt_bytes)
\.sidplay[[:space:]]*\(	client.sidp@@lay(sid_bytes)
\.modplay[[:space:]]*\(	client.modp@@lay(mod_bytes)
\.mount_disk[[:space:]]*\(	client.mount_d@@isk(d64)
Ultimate64Client[[:space:]]*\(	c = Ultimate64Cli@@ent("10.0.0.1")
Ultimate64Transport[[:space:]]*\(	t = Ultimate64Transp@@ort(host)
Ultimate64InstanceManager[[:space:]]*\(	m = Ultimate64InstanceMana@@ger(hosts)
UnifiedManager[[:space:]]*\(	m = UnifiedMana@@ger()
create_manager[[:space:]]*\(	m = create_mana@@ger()
/v1/(runners|machine):	requests.post("http://h/v1/run@@ners:run_prg", data=p)
(^|[^_a-zA-Z.])run_prg[[:space:]]*\(	run_p@@rg(client, prg)
(^|[^_a-zA-Z.])load_prg[[:space:]]*\(	load_p@@rg(client, prg)
requests\.	resp = reque@@sts.post(url, data=prg)
(^|[^_a-zA-Z.])urllib\.	resp = urll@@ib.request.urlopen(req)
pkill	subprocess.run(["pk@@ill", "-f", "x64sc"])
killall	subprocess.run(["kil@@lall", "x64sc"])
TABLE
}

BANNED=$(ban_table | cut -f1 | paste -sd'|' -)
NBANS=$(ban_table | wc -l | tr -d ' ')

if [ -z "$BANNED" ] || [ "$NBANS" -eq 0 ]; then
    echo "FAIL: the ban table is empty -- the scan would match nothing and"
    echo "      every file would read as clean."
    exit 1
fi

# Scan the given files, ignoring comment-only lines. Prints offending
# file:line:text. Returns 0 when clean, 1 when a violation was found.
scan() {
    hits=$(grep -n -E "$BANNED" "$@" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits"
        return 1
    fi
    return 0
}

# Scope: every Python AND shell file under tools/ and test/. The .sh half was
# a reviewer finding too -- four shell scripts live in tools/, and a
# `pkill -f x64sc` in any of them passed a .py-only scan.
# SELF is excluded, and it is the ONLY exclusion. This file must contain the
# banned tokens to ban them -- the table rows, and the remedy text that names
# transport.write_memory()/load_code() for the reader -- so scanning it flags
# itself. Measured, when tools/*.sh came into scope: five self-hits, two of
# them the `pkill`/`killall` rows whose pattern column IS the literal word.
# The blind spot is stated rather than hidden: a violation inside this script
# would not be caught by this script. It is one reviewed file whose whole
# purpose is the ban, and the alternative -- obfuscating the ban table and the
# error message -- would make the gate unreadable to the person it is warning.
SELF=tools/check_harness_routing.sh

scan_set() {
    find tools test \( -name '*.py' -o -name '*.sh' \) \
         -not -path '*/__pycache__/*' 2>/dev/null | grep -v "^\./${SELF}$" \
         | grep -v "^${SELF}$" | sort
}

FILES=$(scan_set)

# The exclusion must remove exactly one file. A widened one (a stray glob, a
# renamed SELF that matches nothing, or one that matches a sibling) would take
# real files out of scope silently -- which is this gate's own failure mode.
ALL=$(find tools test \( -name '*.py' -o -name '*.sh' \) -not -path '*/__pycache__/*' 2>/dev/null | sort)
NALL=$(printf '%s\n' "$ALL" | grep -c . || true)
NSCAN=$(printf '%s\n' "$FILES" | grep -c . || true)
if [ "$((NALL - NSCAN))" -ne 1 ]; then
    echo "FAIL: the SELF exclusion removed $((NALL - NSCAN)) file(s), expected"
    echo "      exactly 1 ($SELF). Files are being dropped from the scan"
    echo "      silently, which is the vacuous-pass shape this gate exists"
    echo "      to prevent."
    exit 1
fi

# --- VACUITY GUARD --------------------------------------------------------
if [ -z "$FILES" ]; then
    echo "FAIL: no Python or shell files found under tools/ or test/ -- the"
    echo "      scan set is empty, so a clean result would be vacuous."
    exit 1
fi

COUNT=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')

# --- POSITIVE CONTROL, ONE ARM PER BAN ------------------------------------
# Planted in the real directory, found by the real scan_set, matched by the
# real scan. Every row must be caught ON ITS OWN, so a dropped or mistyped
# alternative cannot hide behind a sibling that still works.
i=0
ban_table | while IFS='	' read -r pat fix; do
    i=$((i + 1))
    [ -n "$pat" ] || { echo "FAIL: ban table row $i has an empty pattern"; exit 1; }
    [ -n "$fix" ] || { echo "FAIL: ban table row $i ($pat) has no fixture"; exit 1; }

    real=$(printf '%s' "$fix" | sed 's/@@//g')
    if [ "$real" = "$fix" ]; then
        echo "FAIL: ban table row $i ($pat) has a fixture with no '@@' marker."
        echo "      Written literally it would be a real violation in this"
        echo "      file, and this gate would flag itself."
        exit 1
    fi

    printf '# control arm %s\n%s\n' "$i" "$real" > "$SELFTEST"

    if ! scan_set | grep -q "$SELFTEST"; then
        echo "FAIL: control arm $i was planted but scan_set did not pick it up."
        echo "      The scanner is not looking where it thinks it is."
        exit 1
    fi
    if scan $(scan_set) >/dev/null 2>&1; then
        echo "FAIL: control arm $i was NOT caught -- the ban"
        echo "          $pat"
        echo "      does not match its own fixture"
        echo "          $real"
        echo "      That alternative is dead. A clean result from this scan"
        echo "      says nothing about it."
        exit 1
    fi
    rm -f "$SELFTEST"
done || exit 1

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

echo "check-harness-routing: OK ($COUNT files scanned, $NBANS bans each proven live by its own control arm)"
