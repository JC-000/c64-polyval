#!/usr/bin/env python3.13
"""check_footprints.py -- assert the §5 footprint equates still bound reality.

Issue #95. LIB_POLYVAL_RESIDENT_BYTES and LIB_POLYVAL_COLD_BYTES are
hand-maintained constants in src/lib_manifest.s, refreshed by a human at
release. Nothing checked them against a measurement: consumer_stub_shipped.s
imports them and asserts COLD < RESIDENT, which proves ordering, not bounding.

Two siblings shipped this defect in the UNSAFE direction on the same day --
c64-x25519#142 (59-210 B unaccounted across all seven profiles) and
c64-ChaCha20-Poly1305#126 (60 B, live on main) -- both found by measurement
rather than review.

MEASURAND: the sum of the placed spans of this library's `ro` segments, per
c64-lib-contract PR#200's basis. Deliberately NOT a sum of object sizes: that
basis is exactly what hid both siblings' gaps, because it cannot see fill.
Deliberately not the contiguous extent either -- a driver object's own
segments interleave with ours in the link, so an extent would charge the
consumer's bytes to us.

The `ro` segment list is DERIVED from src/lib_only.cfg rather than written
here. A second hand-maintained list is what produced #99.
"""
import re, subprocess, sys, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG  = ROOT / "src" / "lib_only.cfg"
BUILD = ROOT / "build"

# (label, make target, driver stub, ca65 defines for the driver)
ARMS = [
    ("LONG AEAD",     "lib",                        "test/consumer_stub.s",       ["-D","POLYVAL_PROFILE=2"]),
    ("SHORT AEAD",    "lib-polyval-gcmsiv-short",   "test/consumer_stub.s",       ["-D","POLYVAL_PROFILE=1"]),
    ("COMPACT AEAD",  "lib-polyval-gcmsiv-compact", "test/consumer_stub.s",       ["-D","POLYVAL_PROFILE=3"]),
    ("LONG NO_AES",   "lib-polyval-long",           "test/consumer_stub_noaes.s", ["-D","POLYVAL_PROFILE=2","-D","LIB_POLYVAL_NO_AES=1"]),
    ("SHORT NO_AES",  "lib-polyval-short",          "test/consumer_stub_noaes.s", ["-D","POLYVAL_PROFILE=1","-D","LIB_POLYVAL_NO_AES=1"]),
    ("COMPACT NO_AES","lib-polyval-compact",        "test/consumer_stub_noaes.s", ["-D","POLYVAL_PROFILE=3","-D","LIB_POLYVAL_NO_AES=1"]),
]

def die(msg):
    print(f"check_footprints: FAIL -- {msg}", file=sys.stderr); sys.exit(1)

def run(cmd, what):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        tail = (r.stderr or r.stdout).strip().splitlines()[-1:] or ["(no output)"]
        die(f"{what} failed (exit {r.returncode}): {tail[0]}")
    return r.stdout

def ro_segments():
    """Names of LIB_POLYVAL_* segments declared `type = ro` in lib_only.cfg."""
    txt = CFG.read_text()
    names = re.findall(r'^\s*(LIB_POLYVAL_[A-Z0-9_]+)\s*:.*?type\s*=\s*ro', txt, re.M)
    if not names:
        die(f"parsed no `type = ro` LIB_POLYVAL_* segments from {CFG} -- the cfg format changed and every number below would be wrong")
    return set(names)

def declared():
    """RESIDENT/COLD as actually exported by the built lib_manifest.o."""
    out = run(["od65","--dump-exports",str(BUILD/"lib_manifest.o")], "od65 on lib_manifest.o")
    vals, name = {}, None
    for line in out.splitlines():
        m = re.search(r'Name:\s*"([^"]+)"', line)
        if m: name = m.group(1); continue
        m = re.search(r'Value:\s*0x[0-9A-Fa-f]+\s*\((\d+)\)', line)
        if m and name: vals[name] = int(m.group(1)); name = None
    for k in ("LIB_POLYVAL_RESIDENT_BYTES","LIB_POLYVAL_COLD_BYTES"):
        if k not in vals: die(f"{k} not exported by lib_manifest.o -- cannot check a value that is not published")
    return vals

def parse_map(text):
    """Segment rows from an `ld65 -m` map. Split out so the empty-map branch is
    unit-testable: an empty parse must FAIL, never read as a zero footprint."""
    rows = []
    for line in text.splitlines():
        m = re.match(r'^(\S+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', line)
        if m: rows.append((m.group(1), int(m.group(4),16)))
    return rows

def measured(driver, defines, ro):
    objs = sorted(p.name for p in BUILD.glob("*.o") if p.name != "lib_main.o")
    if not objs: die("no member objects in build/ -- the arm did not build")
    run(["ca65","-I","src",*defines,"-o","build/_fp_drv.o",driver], f"ca65 {driver}")
    run(["ld65","-C","src/lib_only.cfg","-m","build/_fp_map.txt",
         "-o","build/_fp.prg","build/_fp_drv.o",*[f"build/{o}" for o in objs]], "ld65")
    rows = parse_map((BUILD/"_fp_map.txt").read_text())
    if not rows: die("parsed 0 segment rows from the ld65 map -- the map format changed; an empty parse must never read as a zero footprint")
    hits = [(n,s) for n,s in rows if n in ro]
    if not hits: die(f"no `ro` LIB_POLYVAL_* segment appeared in the link (saw {len(rows)} rows) -- a zero here would be a false pass")
    return sum(s for _,s in hits), hits

def main():
    for tool in ("ca65","ld65","od65","make"):
        if not shutil.which(tool): die(f"{tool} not on PATH")
    ro = ro_segments()
    print(f"check_footprints: {len(ro)} `ro` segments from lib_only.cfg")
    bad = 0
    for label, target, driver, defines in ARMS:
        run(["make","clean"], "make clean"); run(["make",target], f"make {target}")
        d = declared(); m, hits = measured(driver, defines, ro)
        slack = d["LIB_POLYVAL_RESIDENT_BYTES"] - m
        status = "ok" if slack >= 0 else "UNDER-DECLARED"
        if slack < 0: bad += 1
        print(f"  {label:<15} measured {m:6d}  declared {d['LIB_POLYVAL_RESIDENT_BYTES']:6d}  slack {slack:+5d}  {status}")
        if d["LIB_POLYVAL_COLD_BYTES"] > d["LIB_POLYVAL_RESIDENT_BYTES"]:
            print(f"    COLD {d['LIB_POLYVAL_COLD_BYTES']} exceeds RESIDENT -- COLD is a carve-out of RESIDENT", file=sys.stderr); bad += 1
    run(["make","clean"], "make clean"); run(["make"], "make")
    if bad: die(f"{bad} configuration(s) declare less than they measure -- §5 requires the safe direction")
    print("check_footprints: all 6 configurations declare >= measured")

if __name__ == "__main__":
    main()
