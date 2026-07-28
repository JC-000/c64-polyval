# c64-polyval v0.4.1 — 2026-07-28

**Docs-only PATCH release.** Rolls up the issue-#19 turbo-scaling
documentation and a documentation-currency pass; the only source
change is the `LIB_VERSION_PATCH` export bump itself. POLYVAL /
AES-256 / AES-256-GCM-SIV behaviour, entry-point calling
conventions, ZP layout, segments, and build targets are all
unchanged from v0.4.0. The full per-change log is in
[`CHANGELOG.md`](../CHANGELOG.md); this file is the concise release
summary.

## What's in

- **Zero-REU / turbo-clean scaling as an explicit contract feature**
  ([#19](https://github.com/JC-000/c64-polyval/issues/19), shipped
  via [PR #20](https://github.com/JC-000/c64-polyval/pull/20),
  prompted by the c64-nist-curves #69/#71 REU-DMA wall-clock-floor
  finding). A source audit confirmed no code path in either profile
  touches the 17xx REU, any `$D000–$DFFF` register, or the KERNAL,
  so this shipped as documentation: new README "Turbo / accelerated
  hosts" section, API.md §1/§3/§9.3 updates, and a stated policy
  that any future REU-resident variant must ship as an *optional
  profile* with a manifest delta (`LIB_POLYVAL_REU_BANKS_USED`
  override), never the default path. Corollary now documented: the
  SHORT/LONG crossover (~68 blocks) is clock-invariant.
- **Contract-currency refresh.** Upstream
  [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  advanced to SPEC v0.4.1 (2026-07-18), a doc-only contract release
  — no symbol, macro, section, or build-target semantics changed —
  so no adoption work was required. README, API.md §9, and CLAUDE.md
  references were bumped, and `src/precalc_table.inc` was
  re-verified byte-identical to the canonical contract-root file.
- **Test-count corrections.** The README's GCM-SIV suite count was
  stale ("~15"; actual: 165). Expected suite totals are now stated
  everywhere: 376/376 pass, 6 skip (RFC 8452 C.2 vectors with
  non-empty AAD, unsupported by design).

## What's NOT shipped

Everything. This is a docs-only PATCH release:

- **No code changes** beyond `LIB_VERSION_PATCH = 1`.
- **No new crypto primitives.** POLYVAL, AES-256, and
  AES-256-GCM-SIV entry points are unchanged in signature and
  contract.
- **No AAD support.** GCM-SIV still authenticates empty-AAD
  messages only.
- **No bulk-encryption support.** GCM-SIV plaintext is still capped
  at 64 bytes per call.
- **No constant-time hardening.** The library remains
  non-constant-time on all paths (public-input use only).
- **No §8.1–§8.3 shared-primitive adoption.** Correctly N/A —
  GF(2^128) carry-less multiplication shares no shape with the 8×8
  quarter-square-multiply primitive.

## Upgrade notes for consumers

This is a v0.x **PATCH** bump per c64-lib-contract SPEC §7 (no API
change). Consumers vendoring c64-polyval can re-vendor with no
integration changes:

1. No ZP, segment, manifest-equate, or build-target changes from
   v0.4.0.
2. `LIB_VERSION_PATCH` now exports `1`; any `>= 0` patch gate is
   unaffected.
3. New consumer-facing guarantee worth pinning: both profiles are
   pure CPU + RAM (`LIB_POLYVAL_REU_BANKS_USED = 0` is a contract
   feature, not an accident) and scale ~linearly with CPU clock on
   turbo hosts — see API.md §9.3.

See `API.md` §9 for the full contract surface.

## Verification

Full suite run at release time (VICE `x64sc`, seed 8452):
376/376 passed, 6 skipped — POLYVAL Direct 217/217, GCM-SIV 159/165
+ 6 AAD-by-design skips. `make consumer-check` and all four §6
archive targets (`lib`, `lib-polyval-long`, `lib-polyval-short`,
`lib-polyval-gcmsiv`) build clean.

## Attestation

`c64-polyval-v0.4.1.tar.gz` is produced reproducibly by
`make dist VERSION=v0.4.1`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.4.1.tar.gz` |
| **Size**   | 71582 bytes |
| **SHA256** | `d16651edcc13f1085a61b7d1c535d72808579cbd00c427f5f3710351baa56732` |

Re-running `make dist VERSION=v0.4.1` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's
mtime is forced to `2026-07-28T00:00:00Z`, owner/group are pinned to
`0:0` (numeric), and `gzip -n` drops the gzip timestamp+filename
header. The canonical vendoring file list lives in
`tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.4.1/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.4.1.md` (this file)
- `docs/precalc-tables.md` (SPEC §8.0 enumeration)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers, including `src/precalc_table.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor
metadata.

## Issues closed

- [#19](https://github.com/JC-000/c64-polyval/issues/19) — document
  zero-REU / turbo-clean scaling as an explicit contract feature
  (closed by [PR #20](https://github.com/JC-000/c64-polyval/pull/20),
  merged 2026-07-26).

Deferred (not release-blocking): optional C64U 16/48/64 MHz hardware
sweep of `polyval_block` to empirically confirm the documented
turbo scaling — needs physical hardware; compare within a single
run (the 48 MHz jiffy rate drifts ~3.8% across reboots).

## Known limitations

Carried over unchanged from v0.4.0; see `API.md` §6 for the full
list.

## Cross-references

- Contract repo: [c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
  (SPEC v0.4.1).
- Sibling adopters: see the contract's
  [adopters table](https://github.com/JC-000/c64-lib-contract/blob/main/adopters.md).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git
  tag `lib-v0.1.0`).
