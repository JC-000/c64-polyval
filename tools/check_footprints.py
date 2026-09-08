#!/usr/bin/env python3.13
"""check_footprints.py -- assert the §5 footprint equates still bound reality.

Issue #95. LIB_POLYVAL_RESIDENT_BYTES and LIB_POLYVAL_COLD_BYTES were
hand-maintained constants refreshed by a human at release, with nothing
checking them against a measurement. c64-x25519#142 and
c64-ChaCha20-Poly1305#126 both shipped that defect in the UNSAFE direction on
one day, both found by measurement rather than review.

MEASURAND: the sum of the placed spans of this library's `ro` segments, per
c64-lib-contract PR#200's basis. Not a sum of object sizes -- that basis is
what hid both siblings' gaps, since it cannot see fill. Not a contiguous
extent either: the driver object's own segments interleave with ours (the
NO_AES driver's BSS lands at $4000, ahead of LIB_POLYVAL_*_CODE), so an
extent would charge a consumer's bytes to us.

Everything here is derived and reconciled rather than restated, because a
second hand-maintained list is what produced #99 -- and adversarial review
still found three ways to make an earlier version report a number that was
too small while staying green. Each guard below exists because one of them
worked.
"""
import re, subprocess, sys, shutil, os, tempfile
from pathlib import Path

ROOT  = Path(__file__).resolve().parent.parent
CFG   = ROOT / "src" / "lib_only.cfg"
MK    = ROOT / "Makefile"
COLD_ENTRY = "polyval_precompute_table"

def die(msg):
    print(f"check_footprints: FAIL -- {msg}", file=sys.stderr); sys.exit(1)

def run(cmd, what, env=None):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        tail = (r.stderr or r.stdout).strip().splitlines()[-1:] or ["(no output)"]
        die(f"{what} failed (exit {r.returncode}): {tail[0]}")
    return r.stdout

def segments_from_cfg():
    """Classify EVERY LIB_POLYVAL_* segment in lib_only.cfg by its `type`.

    D1: an earlier version required name and `type = ro` on one line and only
    failed at a count of zero. Reformatting LIB_POLYVAL_AES_RODATA across four
    lines -- which ld65 accepts -- silently dropped 522 B and still reported
    `ok`. Declarations are now joined on `;` first, and any LIB_POLYVAL_*
    declaration whose type cannot be read is fatal: an unclassifiable segment
    is exactly the one that would go missing from the sum.
    """
    txt = CFG.read_text()
    body = txt[txt.index("SEGMENTS"):] if "SEGMENTS" in txt else txt
    ro, bss, seen = set(), set(), set()
    for decl in body.split(";"):
        m = re.search(r"(LIB_POLYVAL_[A-Z0-9_]+)\s*:", decl)
        if not m: continue
        name = m.group(1); seen.add(name)
        t = re.search(r"type\s*=\s*([a-z]+)", decl)
        if not t:
            die(f"segment {name} in {CFG.name} has no readable `type` -- refusing to guess; "
                f"an unclassified segment is the one that silently leaves the sum")
        (ro if t.group(1) == "ro" else bss).add(name)
    if not seen: die(f"parsed no LIB_POLYVAL_* segments from {CFG} -- the cfg format changed")
    if not ro:   die(f"parsed no `type = ro` LIB_POLYVAL_* segments from {CFG}")
    return ro, bss, seen

def parse_map(text):
    """Segment rows from `ld65 -m`. Split out so the empty-map branch is
    unit-testable: an empty parse must FAIL, never read as a zero footprint."""
    rows = []
    for line in text.splitlines():
        m = re.match(r"^(\S+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})", line)
        if m: rows.append((m.group(1), int(m.group(2),16), int(m.group(4),16)))
    return rows

def parse_labels(text):
    """Top-level labels from `ld65 -Ln`, address-sorted. `@` names are ca65
    cheap-locals; the manifest's documented method uses top-level labels."""
    labs = set()
    for ln in text.splitlines():
        m = re.match(r"^al\s+([0-9A-Fa-f]{6})\s+\.(\S+)", ln)
        if m and not m.group(2).startswith("@"):
            labs.add((int(m.group(1),16), m.group(2)))
    return sorted(labs)

def arms_from_makefile():
    """The six archive configurations, derived from the Makefile's own target
    list. D4: this was a hand-maintained six-row table parallel to those
    targets -- the #99 shape, in the script that cites #99."""
    txt = MK.read_text()
    targets = sorted(set(re.findall(r"^(lib-polyval-[a-z-]+):", txt, re.M)))
    prof = {"long":"2","short":"1","compact":"3"}
    arms = []
    for t in targets:
        rest = t[len("lib-polyval-"):]
        aead = rest.startswith("gcmsiv")
        p = rest.split("-")[-1] if rest != "gcmsiv" else "long"
        if p not in prof: die(f"cannot read a profile out of target {t}")
        defs = ["-D", f"POLYVAL_PROFILE={prof[p]}"] + ([] if aead else ["-D","LIB_POLYVAL_NO_AES=1"])
        drv  = "test/consumer_stub.s" if aead else "test/consumer_stub_noaes.s"
        arms.append((f"{p.upper()} {'AEAD' if aead else 'NO_AES'}", t, drv, defs))
    if len(arms) != 6:
        die(f"derived {len(arms)} archive configurations from the Makefile, expected 6 -- "
            f"a target was added or renamed and this check must be updated deliberately")
    return arms

def declared(bd):
    out = run(["od65","--dump-exports",str(bd/"lib_manifest.o")], "od65 on lib_manifest.o")
    vals, name = {}, None
    for line in out.splitlines():
        m = re.search(r'Name:\s*"([^"]+)"', line)
        if m: name = m.group(1); continue
        m = re.search(r"Value:\s*0x[0-9A-Fa-f]+\s*\((\d+)\)", line)
        if m and name: vals[name] = int(m.group(1)); name = None
    for k in ("LIB_POLYVAL_RESIDENT_BYTES","LIB_POLYVAL_COLD_BYTES"):
        if k not in vals: die(f"{k} not exported by lib_manifest.o")
    return vals

def default_segment_emission(bd):
    """D2: growth in the unprefixed CODE/RODATA aliases was invisible -- a new
    .s with no `.segment` line defaults to CODE, which lib_only.cfg keeps as an
    alias precisely to catch accidental default emission. No library member may
    put bytes there, so assert it rather than measure around it."""
    bad = []
    for o in sorted(bd.glob("*.o")):
        if o.name in ("lib_main.o","_fp_drv.o"): continue
        out = run(["od65","--dump-segments",str(o)], f"od65 --dump-segments {o.name}")
        name = None
        for ln in out.splitlines():
            m = re.search(r'Name:\s*"([^"]+)"', ln)
            if m: name = m.group(1); continue
            m = re.search(r"Size:\s*(\d+)", ln)
            if m and name in ("CODE","RODATA") and int(m.group(1)) > 0:
                bad.append(f"{o.name}:{name}={m.group(1)}B")
            if m: name = None
    return bad

def measure(bd, driver, defines, ro):
    objs = sorted(p.name for p in bd.glob("*.o") if p.name != "lib_main.o")
    if not objs: die("no member objects -- the arm did not build")
    run(["ca65","-I","src",*defines,"-o",str(bd/"_fp_drv.o"),driver], f"ca65 {driver}")
    run(["ld65","-C","src/lib_only.cfg","-m",str(bd/"_fp_map.txt"),"-Ln",str(bd/"_fp_lbl.txt"),
         "-o",str(bd/"_fp.prg"),str(bd/"_fp_drv.o"),*[str(bd/o) for o in objs]], "ld65")
    rows = parse_map((bd/"_fp_map.txt").read_text())
    if not rows: die("parsed 0 segment rows from the ld65 map -- an empty parse must never read as a zero footprint")
    hits = [(n,a,s) for n,a,s in rows if n in ro]
    if not hits: die(f"no `ro` LIB_POLYVAL_* segment in the link (saw {len(rows)} rows) -- a zero here would be a false pass")
    resident = sum(s for _,_,s in hits)

    labs = parse_labels((bd/"_fp_lbl.txt").read_text())
    if not labs: die("parsed 0 labels from the -Ln file -- cannot measure COLD")
    entry = [a for a,n in labs if n == COLD_ENTRY]
    if not entry: die(f"cold entry label {COLD_ENTRY} not found -- COLD cannot be measured, and an unmeasured COLD is what this check exists to stop")
    a0 = entry[0]
    later = [a for a,_ in labs if a > a0]
    if later:
        cold = later[0] - a0
    else:
        seg = [(n,a,s) for n,a,s in hits if a <= a0 < a+s]
        if not seg: die("cold entry lies in no `ro` segment -- cannot bound COLD")
        cold = seg[0][1] + seg[0][2] - a0
    return resident, cold

def main():
    for tool in ("ca65","ld65","od65","make"):
        if not shutil.which(tool): die(f"{tool} not on PATH")
    ro, bss, seen = segments_from_cfg()
    print(f"check_footprints: {len(seen)} LIB_POLYVAL_* segments in lib_only.cfg -- {len(ro)} ro, {len(bss)} bss")
    arms = arms_from_makefile()

    # D3: a private BUILD_DIR. This used to run `make clean` six times against
    # the real build/, destroying a concurrent build from inside `make verify`
    # -- worse than the #93 race it would have added to. mkdtemp also avoids
    # adding a new fixed-name scratch tree while #93 is open.
    bd = Path(tempfile.mkdtemp(prefix="build-scratch.", dir=str(ROOT)))
    rel = bd.name
    bad = 0
    try:
        for label, target, driver, defines in arms:
            run(["make",f"BUILD_DIR={rel}","clean"], "make clean")
            run(["make",f"BUILD_DIR={rel}",target], f"make {target}")
            emit = default_segment_emission(bd)
            if emit:
                print(f"  {label:<15} DEFAULT-SEGMENT EMISSION: {' '.join(emit)}", file=sys.stderr); bad += 1
            d = declared(bd)
            res, cold = measure(bd, driver, defines, ro)
            rs = d["LIB_POLYVAL_RESIDENT_BYTES"] - res
            cs = d["LIB_POLYVAL_COLD_BYTES"] - cold
            flags = []
            if rs < 0: flags.append("RESIDENT UNDER-DECLARED")
            if cs < 0: flags.append("COLD UNDER-DECLARED")
            if d["LIB_POLYVAL_COLD_BYTES"] > d["LIB_POLYVAL_RESIDENT_BYTES"]: flags.append("COLD > RESIDENT")
            if flags: bad += 1
            print(f"  {label:<15} resident {res:6d}/{d['LIB_POLYVAL_RESIDENT_BYTES']:6d} ({rs:+5d})  "
                  f"cold {cold:5d}/{d['LIB_POLYVAL_COLD_BYTES']:5d} ({cs:+5d})  {' '.join(flags) or 'ok'}")
    finally:
        shutil.rmtree(bd, ignore_errors=True)
    if bad: die(f"{bad} configuration(s) failed a footprint assertion -- see the rows above")
    print(f"check_footprints: all {len(arms)} configurations declare >= measured, resident and cold")

if __name__ == "__main__":
    main()
