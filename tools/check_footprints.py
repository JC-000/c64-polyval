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

# The `ro` segments that carry shipped bytes. Independent of the classifier,
# which is the point -- see the N1 note in segments_from_cfg().
RO_FLOOR = {
    "LIB_POLYVAL_AES_RODATA",
    "LIB_POLYVAL_AES_CODE",
    "LIB_POLYVAL_GCMSIV_CODE",
    "LIB_POLYVAL_LONG_CODE",
    "LIB_POLYVAL_SHORT_CODE",
    "LIB_POLYVAL_COMPACT_CODE",
}


def classify_segments(txt):
    """(ro, bss, seen) for every LIB_POLYVAL_* segment declared in *txt*.

    Pure, so the self-test drives the same classifier the real run does.
    """
    body = txt[txt.index("SEGMENTS"):] if "SEGMENTS" in txt else txt
    ro, bss, seen = set(), set(), set()
    for decl in body.split(";"):
        m = re.search(r"(LIB_POLYVAL_[A-Z0-9_]+)\s*:", decl)
        if not m: continue
        name = m.group(1); seen.add(name)
        t = re.search(r"type\s*=\s*([a-z]+)", decl)
        if not t:
            die(f"segment {name} has no readable `type` -- refusing to guess; "
                f"an unclassified segment is the one that silently leaves the sum")
        (ro if t.group(1) == "ro" else bss).add(name)
    return ro, bss, seen


def segments_from_cfg():
    """Classify EVERY LIB_POLYVAL_* segment in lib_only.cfg by its `type`.

    D1: an earlier version required name and `type = ro` on one line and only
    failed at a count of zero. Reformatting LIB_POLYVAL_AES_RODATA across four
    lines -- which ld65 accepts -- silently dropped 522 B and still reported
    `ok`. Declarations are now joined on `;` first, and any LIB_POLYVAL_*
    declaration whose type cannot be read is fatal: an unclassifiable segment
    is exactly the one that would go missing from the sum.
    """
    ro, bss, seen = classify_segments(CFG.read_text())
    if not seen: die(f"parsed no LIB_POLYVAL_* segments from {CFG} -- the cfg format changed")
    if not ro:   die(f"parsed no `type = ro` LIB_POLYVAL_* segments from {CFG}")

    # rev-120 N1. The `lost` cross-check in measure() is `n in ro and n not in
    # parsed_names` -- so it SHRINKS WITH `ro`. Narrowing the classifier here
    # instead of the map parser reproduced the D5 damage byte for byte:
    # classifying RODATA as bss gave "6 ro, 7 bss", LONG AEAD resident
    # 6495 -> 5973, every row `ok`, exit 0. A check whose expectation is
    # derived from the thing it checks cannot see that.
    #
    # So the ro membership of the segments that carry the bytes is asserted
    # against a NAMED FLOOR, which does not move when the classifier does.
    # A floor, not an equality: adding a new `ro` segment is fine, losing one
    # of these is not. LIB_POLYVAL_VERIFY_CODE is deliberately absent -- it is
    # lib-verify scaffolding, not shipped surface.
    missing_ro = sorted(RO_FLOOR - ro)
    if missing_ro:
        die(f"these segments are not classified `ro` in {CFG.name}: {', '.join(missing_ro)}. "
            f"They carry the bytes RESIDENT is the sum of, so misclassifying one silently "
            f"REMOVES it from the measurement -- and a smaller measurement makes "
            f"'declared >= measured' easier to satisfy. Either the cfg changed deliberately "
            f"(update RO_FLOOR) or the type classifier has narrowed")
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

def parse_exports(out):
    """{name: value} from `od65 --dump-exports`. Pure, so the self-test can
    drive the same parser the real run uses."""
    vals, name = {}, None
    for line in out.splitlines():
        m = re.search(r'Name:\s*"([^"]+)"', line)
        if m: name = m.group(1); continue
        m = re.search(r"Value:\s*0x[0-9A-Fa-f]+\s*\((\d+)\)", line)
        if m and name: vals[name] = int(m.group(1)); name = None
    return vals

def declared(bd):
    out = run(["od65","--dump-exports",str(bd/"lib_manifest.o")], "od65 on lib_manifest.o")
    vals = parse_exports(out)
    for k in ("LIB_POLYVAL_RESIDENT_BYTES","LIB_POLYVAL_COLD_BYTES"):
        if k not in vals: die(f"{k} not exported by lib_manifest.o")
    return vals

def footprint_flags(d, res, cold):
    """(resident slack, cold slack, flags). The whole verdict of this gate is
    these three comparisons; pure, so the self-test can prove they still fire."""
    rs = d["LIB_POLYVAL_RESIDENT_BYTES"] - res
    cs = d["LIB_POLYVAL_COLD_BYTES"] - cold
    flags = []
    if rs < 0: flags.append("RESIDENT UNDER-DECLARED")
    if cs < 0: flags.append("COLD UNDER-DECLARED")
    if d["LIB_POLYVAL_COLD_BYTES"] > d["LIB_POLYVAL_RESIDENT_BYTES"]: flags.append("COLD > RESIDENT")
    return rs, cs, flags

def default_emission_from_dump(out, oname):
    """Non-empty CODE/RODATA segments in one `od65 --dump-segments`. Pure."""
    bad, name = [], None
    for ln in out.splitlines():
        m = re.search(r'Name:\s*"([^"]+)"', ln)
        if m: name = m.group(1); continue
        m = re.search(r"Size:\s*(\d+)", ln)
        if m and name in ("CODE","RODATA") and int(m.group(1)) > 0:
            bad.append(f"{oname}:{name}={m.group(1)}B")
        if m: name = None
    return bad

def default_segment_emission(bd):
    """D2: growth in the unprefixed CODE/RODATA aliases was invisible -- a new
    .s with no `.segment` line defaults to CODE, which lib_only.cfg keeps as an
    alias precisely to catch accidental default emission. No library member may
    put bytes there, so assert it rather than measure around it."""
    bad = []
    for o in sorted(bd.glob("*.o")):
        if o.name in ("lib_main.o","_fp_drv.o"): continue
        out = run(["od65","--dump-segments",str(o)], f"od65 --dump-segments {o.name}")
        bad.extend(default_emission_from_dump(out, o.name))
    return bad

def measure(bd, driver, defines, ro):
    objs = sorted(p.name for p in bd.glob("*.o") if p.name != "lib_main.o")
    if not objs: die("no member objects -- the arm did not build")
    run(["ca65","-I","src",*defines,"-o",str(bd/"_fp_drv.o"),driver], f"ca65 {driver}")
    run(["ld65","-C","src/lib_only.cfg","-m",str(bd/"_fp_map.txt"),"-Ln",str(bd/"_fp_lbl.txt"),
         "-o",str(bd/"_fp.prg"),str(bd/"_fp_drv.o"),*[str(bd/o) for o in objs]], "ld65")
    raw_map = (bd/"_fp_map.txt").read_text()
    rows = parse_map(raw_map)
    if not rows: die("parsed 0 segment rows from the ld65 map -- an empty parse must never read as a zero footprint")
    hits = [(n,a,s) for n,a,s in rows if n in ro]
    if not hits: die(f"no `ro` LIB_POLYVAL_* segment in the link (saw {len(rows)} rows) -- a zero here would be a false pass")

    # rev-120 D5. `hits` being non-empty is NOT enough: a parse_map that
    # narrowed to drop some rows still leaves others, so `hits` is truthy, no
    # guard fires, and RESIDENT is simply SMALLER -- which "declared >=
    # measured" is happier to satisfy, not less. Measured: excluding RODATA
    # rows from the parser took LONG AEAD from 6495 to 5973, silently losing
    # LIB_POLYVAL_AES_RODATA's 522 B, and all six arms printed `ok`.
    #
    # So cross-check the parse against the RAW TEXT, which is independent of
    # the row regex: a segment the cfg declares `ro`, whose name appears in the
    # map, must have parsed into a row.
    parsed_names = {n for n, _a, _s in rows}
    lost = sorted(n for n in ro if n in raw_map and n not in parsed_names)
    if lost:
        die(f"these `ro` segments appear in the ld65 map but did not parse into rows: "
            f"{', '.join(lost)} -- the map parser has narrowed, and every byte in them is "
            f"silently missing from RESIDENT. A smaller measurement makes 'declared >= "
            f"measured' EASIER to satisfy, so this cannot be left to the comparison")

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

def selftest():
    """Positive control over the four things that decide this gate's verdict.

    Every one is a regex parser or a comparison. Rebuilding the library cannot
    reveal a parser that has silently stopped matching -- it would report a
    smaller measurement, or none, and "declared >= measured" is EASIER to
    satisfy the less you measure. That is the failure this gate is most
    exposed to, and it is the failure a green run looks exactly like.

    Synthetic inputs are in the real od65 / ld65 -Ln formats. Drives the same
    functions the real run calls.
    """
    checks = 0

    # 1. od65 --dump-exports parsing. A break here means declared() dies on a
    #    missing key -- loud -- but a PARTIAL break silently drops a symbol.
    exports = parse_exports(
        '    Name:  "LIB_POLYVAL_RESIDENT_BYTES"\n'
        '    Value: 0x001A00 (6656)\n'
        '    Name:  "LIB_POLYVAL_COLD_BYTES"\n'
        '    Value: 0x000100 (256)\n')
    if exports != {"LIB_POLYVAL_RESIDENT_BYTES": 6656, "LIB_POLYVAL_COLD_BYTES": 256}:
        die(f"POSITIVE CONTROL FAILED: parse_exports returned {exports} for a known "
            "od65 --dump-exports fixture. The manifest parser is broken, and a "
            "declared value it cannot read is not a value this gate is checking")
    checks += 1

    # 2. ld65 -Ln label parsing, including the cheap-local exclusion. COLD is
    #    measured as the distance to the NEXT label, so a parser that drops
    #    labels reports a LARGER cold span, and a parser that invents one
    #    reports a smaller -- both silent.
    labs = parse_labels(
        "al 00A000 .polyval_cold_entry\n"
        "al 00A040 .@cheap_local\n"
        "al 00A080 .next_real_label\n")
    if labs != [(0xA000, "polyval_cold_entry"), (0xA080, "next_real_label")]:
        die(f"POSITIVE CONTROL FAILED: parse_labels returned {labs}. Either the "
            "-Ln format stopped being recognised or the `@` cheap-local exclusion "
            "broke -- COLD is measured off these labels")
    checks += 1

    # 2b. ld65 -m segment-row parsing (rev-120 D5). The gate's own docstring
    #     names this failure and the first cut did not cover it. A RODATA row
    #     is in the fixture on purpose: excluding exactly those was the
    #     mutation that silently dropped 522 B while every row printed `ok`.
    rows = parse_map(
        "Name                   Start     End    Size  Align\n"
        "----------------------------------------------------\n"
        "LIB_POLYVAL_CODE      00A000  00A3FF  000400  00001\n"
        "LIB_POLYVAL_AES_RODATA 00A400  00A609  00020A  00001\n")
    if rows != [("LIB_POLYVAL_CODE", 0xA000, 0x400),
                ("LIB_POLYVAL_AES_RODATA", 0xA400, 0x20A)]:
        die(f"POSITIVE CONTROL FAILED: parse_map returned {rows} for a known ld65 -m "
            "fixture. A narrowed row parser reports a SMALLER resident footprint, which "
            "'declared >= measured' is happier to satisfy, not less")
    checks += 1

    # 2c. the cfg type classifier (rev-120 N1). Narrowing HERE rather than in
    #     parse_map reproduced D5 exactly, because the `lost` cross-check is
    #     built from `ro` and shrinks with it. The RO_FLOOR assertion is the
    #     real anchor; this proves the classifier still reads both types.
    c_ro, c_bss, c_seen = classify_segments(
        "SEGMENTS {\n"
        "    LIB_POLYVAL_AES_RODATA: load = MAIN, type = ro, align = $100;\n"
        "    LIB_POLYVAL_BSS:        load = MAIN, type = bss;\n"
        "}\n")
    if c_ro != {"LIB_POLYVAL_AES_RODATA"} or c_bss != {"LIB_POLYVAL_BSS"} or len(c_seen) != 2:
        die(f"POSITIVE CONTROL FAILED: classify_segments returned ro={c_ro}, bss={c_bss} for a "
            "known two-segment cfg. A classifier that moves a segment out of `ro` removes its "
            "bytes from RESIDENT silently, and the map cross-check cannot see it because that "
            "check is built from `ro` itself")
    checks += 1

    # 3. default-segment emission. The gate asserts no member emits into the
    #    unprefixed CODE/RODATA aliases; a parser that sees nothing agrees.
    dump_bad = 'Name:  "CODE"\n  Size:  12\n'
    dump_ok  = 'Name:  "CODE"\n  Size:  0\n'
    if default_emission_from_dump(dump_bad, "x.o") != ["x.o:CODE=12B"]:
        die("POSITIVE CONTROL FAILED: a 12-byte CODE segment was not reported as "
            "default-segment emission -- this assertion is dead and every 'ok' row "
            "below is consistent with a member quietly emitting into CODE")
    if default_emission_from_dump(dump_ok, "x.o") != []:
        die("NEGATIVE CONTROL FAILED: a 0-byte CODE segment was reported as "
            "emission -- the assertion would refuse a correct build")
    checks += 1

    # 4. the verdict arithmetic itself.
    over  = {"LIB_POLYVAL_RESIDENT_BYTES": 100, "LIB_POLYVAL_COLD_BYTES": 50}
    if footprint_flags(over, 200, 10)[2] != ["RESIDENT UNDER-DECLARED"]:
        die("POSITIVE CONTROL FAILED: declaring 100 bytes while measuring 200 did "
            "not flag RESIDENT UNDER-DECLARED")
    if footprint_flags(over, 10, 200)[2] != ["COLD UNDER-DECLARED"]:
        die("POSITIVE CONTROL FAILED: declaring 50 cold bytes while measuring 200 "
            "did not flag COLD UNDER-DECLARED")
    if footprint_flags({"LIB_POLYVAL_RESIDENT_BYTES": 10, "LIB_POLYVAL_COLD_BYTES": 20},
                       1, 1)[2] != ["COLD > RESIDENT"]:
        die("POSITIVE CONTROL FAILED: cold 20 > resident 10 did not flag")
    if footprint_flags(over, 10, 10)[2] != []:
        die("NEGATIVE CONTROL FAILED: a correctly over-declared arm was flagged")
    checks += 1

    return checks


def main():
    for tool in ("ca65","ld65","od65","make"):
        if not shutil.which(tool): die(f"{tool} not on PATH")
    controls = selftest()
    ro, bss, seen = segments_from_cfg()
    print(f"check_footprints: {len(seen)} LIB_POLYVAL_* segments in lib_only.cfg -- {len(ro)} ro, {len(bss)} bss")
    arms = arms_from_makefile()

    # D3: a private BUILD_DIR. This used to run `make clean` six times against
    # the real build/, destroying a concurrent build from inside `make verify`
    # -- worse than the #93 race it would have added to. mkdtemp also avoids
    # adding a new fixed-name scratch tree while #93 is open.
    #
    # `clean-build`, not `clean`: plain `clean` also sweeps $(SCRATCH_TREES),
    # which is the repo-wide `build-scratch.*` glob, so cleaning THIS tree
    # deleted every other tool's private tree too -- #93's per-run names bought
    # nothing while the cleanup was still global.
    bd = Path(tempfile.mkdtemp(prefix="build-scratch.", dir=str(ROOT)))
    rel = bd.name
    bad = 0
    try:
        for label, target, driver, defines in arms:
            run(["make",f"BUILD_DIR={rel}","clean-build"], "make clean-build")
            run(["make",f"BUILD_DIR={rel}",target], f"make {target}")
            emit = default_segment_emission(bd)
            if emit:
                print(f"  {label:<15} DEFAULT-SEGMENT EMISSION: {' '.join(emit)}", file=sys.stderr); bad += 1
            d = declared(bd)
            res, cold = measure(bd, driver, defines, ro)
            rs, cs, flags = footprint_flags(d, res, cold)
            if flags: bad += 1
            print(f"  {label:<15} resident {res:6d}/{d['LIB_POLYVAL_RESIDENT_BYTES']:6d} ({rs:+5d})  "
                  f"cold {cold:5d}/{d['LIB_POLYVAL_COLD_BYTES']:5d} ({cs:+5d})  {' '.join(flags) or 'ok'}")
    finally:
        shutil.rmtree(bd, ignore_errors=True)
    if bad: die(f"{bad} configuration(s) failed a footprint assertion -- see the rows above")
    print(f"check_footprints: all {len(arms)} configurations declare >= measured, resident and cold, "
          f"{controls} positive control group(s) fired")

if __name__ == "__main__":
    main()
