#!/usr/bin/env python3.13
"""check_composing_mode.py -- exercise the mode a composing consumer builds in.

Issues #89 and #94. `-D LIB_NO_BARE_EXPORTS=1` is what a consumer linking two
or more sibling libraries must use, to avoid the duplicate-external-identifier
collision c64-aes256-ecdsa#28 is a live instance of. Before this:

  * nothing LINKED a consumer against an archive built that way -- 
    consumer-check-shipped assembles with a bare $(CA65) and links the default
    archive, consumer-check-noaes passes only profile/NO_AES defines, and
    check_knob_staleness.sh builds with the define but never links (#94);
  * nothing asserted precalc_manifest.o's §8.4 suppression at all, in any arm
    (#89) -- check_knob_staleness covers lib_version.o only.

NO EXPECTED-VALUE TABLE. The obvious implementation hardcodes the per-arm
prefixed counts (15/9/9/9/3/3), which is a hand-maintained list parallel to
the manifest's own `.if` branches -- the shape that produced #99, and that
adversarial review found twice more in #95 and #93. Instead each arm is built
BOTH ways and compared against itself: the bare names must go to zero, and the
prefixed set must be UNCHANGED. That is c64-nist-curves#158's framing -- check
the gate for what it KEEPS, not only for what it removes -- and it needs no
number written down anywhere.
"""
import re, subprocess, sys, shutil, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MK   = ROOT / "Makefile"

def die(msg):
    print(f"check_composing_mode: FAIL -- {msg}", file=sys.stderr); sys.exit(1)

def run(cmd, what):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        tail = (r.stderr or r.stdout).strip().splitlines()[-1:] or ["(no output)"]
        die(f"{what} failed (exit {r.returncode}): {tail[0]}")
    return r.stdout

def exports(obj):
    if not obj.exists(): die(f"{obj.name} does not exist -- the arm did not build, which is NOT 'no exports'")
    out = run(["od65","--dump-exports",str(obj)], f"od65 on {obj.name}")
    declared = re.search(r"^\s*Count:\s*(\d+)", out, re.M)
    if not declared: die(f"no export Count in od65's dump of {obj.name}")
    names = set(re.findall(r'Name:\s*"([^"]+)"', out))
    if len(names) != int(declared.group(1)):
        die(f"{obj.name}: parsed {len(names)} names but od65 declared {declared.group(1)} -- "
            f"the extractor is wrong, so no comparison below can be trusted")
    return names

def arms():
    txt = MK.read_text()
    targets = sorted(set(re.findall(r"^(lib-polyval-[a-z-]+):", txt, re.M)))
    prof = {"long":"2","short":"1","compact":"3"}
    out = []
    for t in targets:
        rest = t[len("lib-polyval-"):]
        aead = rest.startswith("gcmsiv")
        p = rest.split("-")[-1] if rest != "gcmsiv" else "long"
        if p not in prof: die(f"cannot read a profile out of target {t}")
        out.append((f"{p.upper()} {'AEAD' if aead else 'NO_AES'}", t, prof[p], aead))
    if len(out) != 6:
        die(f"derived {len(out)} archive configurations from the Makefile, expected 6 -- "
            f"a target was added or renamed and this check must be updated deliberately")
    return out

BARE = {
    "precalc_manifest.o": re.compile(r"^LIB_PRECALC_"),
    "lib_version.o":      re.compile(r"^LIB_(VERSION|ABI)"),
}
PREFIXED = {
    "precalc_manifest.o": re.compile(r"^LIB_POLYVAL_PRECALC_"),
    "lib_version.o":      re.compile(r"^LIB_POLYVAL_(VERSION|ABI)"),
}

def main():
    for tool in ("ca65","ld65","od65","make"):
        if not shutil.which(tool): die(f"{tool} not on PATH")
    bd = Path(tempfile.mkdtemp(prefix="build-scratch.", dir=str(ROOT)))
    rel, bad = bd.name, 0
    try:
        for label, target, profile, aead in arms():
            snap = {}
            for mode, defines in (("default", ""), ("nobare", "-D LIB_NO_BARE_EXPORTS=1")):
                run(["make",f"BUILD_DIR={rel}","clean"], "make clean")
                run(["make",f"BUILD_DIR={rel}",target,f"CONTRACT_DEFINES={defines}"], f"make {target} [{mode}]")
                snap[mode] = {o: exports(bd/o) for o in BARE if (bd/o).exists()}
                if "precalc_manifest.o" not in snap[mode]:
                    die(f"{label} [{mode}]: precalc_manifest.o is absent -- it is a member of every archive; "
                        f"its absence must not read as 'suppression works'")
            for obj in sorted(snap["default"]):
                d_bare = {n for n in snap["default"][obj] if BARE[obj].match(n)}
                n_bare = {n for n in snap["nobare"][obj]  if BARE[obj].match(n)}
                d_pre  = {n for n in snap["default"][obj] if PREFIXED[obj].match(n)}
                n_pre  = {n for n in snap["nobare"][obj]  if PREFIXED[obj].match(n)}
                notes = []
                if not d_bare:
                    notes.append("NO BARE NAMES IN THE DEFAULT BUILD -- nothing to suppress, so the "
                                 "suppression assertion below would pass vacuously")
                if n_bare:  notes.append(f"{len(n_bare)} bare name(s) SURVIVED suppression: {sorted(n_bare)[:3]}")
                if d_pre != n_pre:
                    notes.append(f"prefixed surface CHANGED: {len(d_pre)} -> {len(n_pre)}, "
                                 f"lost {sorted(d_pre - n_pre)[:3]}")
                if notes: bad += 1
                print(f"  {label:<15} {obj:<22} bare {len(d_bare):2d} -> {len(n_bare):2d}   "
                      f"prefixed {len(d_pre):2d} -> {len(n_pre):2d}   {'; '.join(notes) or 'ok'}")
                if notes: print("      " + "\n      ".join(notes), file=sys.stderr)

            # #94: the composing mode must LINK, not merely build.
            if aead:
                # -I the STAGED lib dir, never src/ -- consumer_stub_shipped.s is the
                # #79 guard's stub and its point is that the shipped surface suffices.
                # Feeding it src/ here would quietly restore the reachback #79 exists
                # to catch.
                inc = bd/"lib"
                if not (inc/"polyval.inc").exists():
                    die(f"{label}: {inc}/polyval.inc was not staged -- the shipped surface is incomplete")
                run(["ca65","-I",str(inc),"-D",f"POLYVAL_PROFILE={profile}","-D","LIB_NO_BARE_EXPORTS=1",
                     "-o",str(bd/"_cm_drv.o"),"test/consumer_stub_shipped.s"], f"{label}: ca65 shipped stub [nobare]")
                objs = sorted(p.name for p in bd.glob("*.o") if p.name not in ("lib_main.o","_cm_drv.o"))
                run(["ld65","-C","src/lib_only.cfg","-o",str(bd/"_cm.prg"),
                     str(bd/"_cm_drv.o"),*[str(bd/o) for o in objs]], f"{label}: ld65 [nobare]")
                if not (bd/"_cm.prg").exists() or (bd/"_cm.prg").stat().st_size == 0:
                    die(f"{label}: the nobare link produced no output")
                print(f"  {label:<15} {'shipped stub link':<22} {(bd/'_cm.prg').stat().st_size} bytes   ok")
    finally:
        shutil.rmtree(bd, ignore_errors=True)
    if bad: die(f"{bad} assertion(s) failed -- see the rows above")
    print("check_composing_mode: suppression removes every bare name and keeps every prefixed one, all 6 arms")

if __name__ == "__main__":
    main()
