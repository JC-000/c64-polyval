.setcpu "6502"

; =============================================================================
; lib_manifest.s - c64-polyval aggregate ABI manifest (c64-lib-contract §5)
;
; Consumer-facing assemble-time equates that summarize the library's
; resource footprint. Used to gate consumer build attempts before kicking
; off the full link + VICE test cycle.
;
;   LIB_POLYVAL_ZP_USAGE_BYTES   - Total bytes claimed in zero page
;                                  (sum of widths of every .exportzp
;                                  slot declared in src/zp_config.s).
;   LIB_POLYVAL_REU_BANKS_USED   - Bitmask of REU bank indices claimed.
;                                  c64-polyval makes no REU claims; per
;                                  SPEC §3 ("conditional on actual
;                                  usage"), the equate is reported as 0.
;   LIB_POLYVAL_RESIDENT_BYTES   - CPU-RAM-resident footprint (library
;                                  code + rodata that must remain in CPU
;                                  RAM at runtime to serve a
;                                  polyval_update / gcm_siv_encrypt
;                                  call). Conditional on BOTH axes: the
;                                  POLYVAL_PROFILE selector (LONG,
;                                  SHORT and COMPACT differ
;                                  substantively in the size of
;                                  polyval_multiply and
;                                  polyval_precompute_table) AND
;                                  LIB_POLYVAL_NO_AES (the POLYVAL-only
;                                  archives ship no AES / GCM-SIV code
;                                  or rodata at all — SPEC §6.4/§6.6).
;   LIB_POLYVAL_COLD_BYTES       - Code+rodata footprint that a
;                                  consumer MAY page-overlay (boot-only
;                                  init paths: aes_key_expansion and
;                                  polyval_precompute_table; the former
;                                  only when AES ships). Conditional on
;                                  the same two axes as RESIDENT_BYTES.
;
; All values are integer equates. Consumer-side assemble-time `.assert`
; checks compare them against ld65-published `__<MEMORY>_SIZE__` symbols
; (see c64-lib-contract SPEC §5 worked example).
;
; Each equate is `.ifndef`-guarded so a consumer can override via
; `ca65 -D <symbol>=<value>` (ca65 rejects `--asm-define`; that
; spelling is cl65's — SPEC v0.7.1). Exports are wrapped in a
; `.if !.defined(LIB_MANIFEST_NO_EXPORTS)` block so a translation unit
; that transitively `.include`s this file (e.g. via a future
; constants_lib.inc roll-up) can suppress the directives and avoid
; ld65 "duplicate symbol" errors.
;
; The numbers are SAFE-DIRECTION per SPEC v0.10.0 §6.6: each value is
; >= the measured segment sum for the archive it ships in, rounded UP
; to the next 256-byte boundary (the fleet convention — headroom under
; one page absorbs incidental growth without forcing consumer .assert
; rewrites, and the equate moving is itself the signal that a re-look
; is due). Because declared >= actual, a consumer's
; `declared <= budget` assert implies `actual <= budget`; the pre-§6.6
; values here rounded DOWN (6567 -> 6500 etc.), which broke exactly
; that implication. Refreshed at each release that substantively
; changes one of them. Measurement methodology for RESIDENT_BYTES /
; COLD_BYTES, per (POLYVAL_PROFILE x LIB_POLYVAL_NO_AES) configuration:
; `ld65 -C src/lib_only.cfg -Ln -m ...` against exactly the .o member
; set of the archive under measurement; the load span from $4000 up to
; the first BSS-area segment start is the code+rodata footprint.
; Cold-path subset measured from the address delta between the
; entry-point label and the next top-level label in the -Ln label file
; (for COMPACT, whose cold code is placed last in its segment on
; purpose, the delta runs to the segment end from the -m map instead).
; =============================================================================

.ifndef LIB_MANIFEST_S_INCLUDED
LIB_MANIFEST_S_INCLUDED = 1

; constants_lib.inc defines POLYVAL_PROFILE_SHORT (=1),
; POLYVAL_PROFILE_LONG (=2) and POLYVAL_PROFILE_COMPACT (=3), plus the
; POLYVAL_PROFILE selector itself.
; We need them to gate the profile-conditional RESIDENT_BYTES / COLD_BYTES
; values below.
.include "constants_lib.inc"

; c64-lib-contract SPEC §8.0 catch-loop: canonical LIB_PRECALC_TABLE
; macro, copied verbatim from the contract repo. See the registrations
; below and docs/precalc-tables.md for the full enumeration.
.include "precalc_table.inc"


; -----------------------------------------------------------------------------
; Zero-page usage
; -----------------------------------------------------------------------------
; Sum of widths of every `.exportzp` slot declared in src/zp_config.s:
;
;   polyval_zp_ptr2                    ($02-$03)        2
;   polyval_aes_round, polyval_aes_col ($04-$05)        2
;   polyval_aes_tmp1..tmp4             ($06-$09)        4
;   polyval_acc                        ($10-$1F)       16
;   pv_mul_input                       ($20-$2F)       16
;   pv_mul_nibble                      ($30)            1
;   polyval_zp_ptr                     ($fb-$fc)        2
;   polyval_zp_temp                    ($fd)            1
;   polyval_zp_count                   ($fe)            1
;                                                     ----
;                                                       45
;
; Three discontiguous regions: 8 B at $02-$09, 33 B at $10-$30, and
; 4 B at $fb-$fe. The total ($08 + $21 + $04 = $2D = 45) is what the
; consumer cares about for sizing collision asserts; the discontinuity
; is documented in API.md §4 and zp_config.s.
; -----------------------------------------------------------------------------
.ifndef LIB_POLYVAL_ZP_USAGE_BYTES
  LIB_POLYVAL_ZP_USAGE_BYTES = 45
.endif


; -----------------------------------------------------------------------------
; REU bank bitmask
; -----------------------------------------------------------------------------
; c64-polyval makes NO REU claims. Per c64-lib-contract SPEC §3 the
; bitmask is "conditional on actual usage" -- a library that never
; touches the 17xx REU reports zero. All page-aligned tables
; (polyval_htable, polyval_htable8, polyval_reduce8) live in CPU BSS
; segments, not REU.
;
; Policy (API.md §9.3, issue #19): a future variant that offloads
; htable8/reduce8 to REU must ship as an OPTIONAL profile overriding
; this equate -- never the default or only path. REU DMA transfers at
; the ~1 MHz bus rate regardless of CPU turbo, so an REU-resident hot
; path would put a speed-invariant wall-clock floor under turbo hosts
; and a hard REU dependency under stock ones (c64-nist-curves #69/#71).
; -----------------------------------------------------------------------------
.ifndef LIB_POLYVAL_REU_BANKS_USED
  LIB_POLYVAL_REU_BANKS_USED = 0
.endif


; -----------------------------------------------------------------------------
; Resident footprint (safe-direction, SPEC §6.6)
; -----------------------------------------------------------------------------
; Library code + rodata that MUST stay in CPU RAM at runtime to serve a
; polyval_update / polyval_finalize / gcm_siv_encrypt call. Measured
; per (profile x archive-membership) configuration by linking exactly
; the .o member set of each archive with lib_only.cfg at $4000 -- the
; load span from $4000 up to the first BSS-area segment start is
; exactly the code+rodata footprint (ld65 -m segment map cross-checked
; against the -Ln label file). BSS / page-aligned tables (polyval_h,
; polyval_htable, polyval_htable8, polyval_reduce8) are RW state and
; excluded per SPEC §5 wording ("code+rodata").
;
; Declared value = measured, rounded UP to the next 256-byte boundary
; (SPEC §6.6 obligation 1: MUST be >= the measured segment sum for the
; archive it ships in; the pre-§6.6 values rounded DOWN — 6567
; declared 6500, 16021 declared 16000 — which let a consumer's
; `declared <= budget` assert pass while the actual footprint
; overran). Measurements taken 2026-08-15 against the v0.6.0 tree
; (ca65/ld65 V2.18); PRG output byte-identical before/after this
; manifest change. Re-measured 2026-08-29 after the hazmat-audit fixes
; (issues #69 / #70): gcm_siv.o's LIB_POLYVAL_GCMSIV_CODE grew 805 ->
; 847 B (three `cpx #aes_expanded_key_size` terminators, two pt_len
; bounds checks, one reject path), so every AEAD measured figure is
; +42 B; no declared value moves (all stay under their boundary), the
; NO_AES archives do not ship gcm_siv.o and are unchanged, and
; COLD_BYTES is untouched (gcm_siv.o has no cold path). The AEAD span
; comments below keep the 2026-08-15 addresses; the `.if` block holds
; the current measured figures.
;
; AEAD builds (polyval.a / polyval-gcmsiv.a on LONG,
; polyval-gcmsiv-short.a on SHORT; member set: lib_version, zp_config,
; lib_manifest, tables, data, aes_encrypt, aes_decrypt, gcm_siv,
; polyval_<profile>):
;
;   LONG  (POLYVAL_PROFILE = POLYVAL_PROFILE_LONG = 2):
;     $4000 .. $59A7 (first BSS start) = $19A7 = 6567 measured,
;     of which 114 B ($72) is the lib_main.o verify stub's
;     LIB_POLYVAL_VERIFY_CODE — archive members alone are 6453
;     (aes_encrypt/aes_decrypt $3C6 + gcm_siv $325 + polyval_long
;     $1040 + aes rodata $20A). Both round UP to the same boundary:
;     declared 6656 ($1A00).
;     Span covers aes_encrypt_block, aes_decrypt_block,
;     aes_key_expansion, gcmsiv_encrypt/decrypt, polyval_init /
;     polyval_double / polyval_precompute_table / polyval_multiply
;     (8-bit Shoup fused shift+reduce+htable) / polyval_update /
;     polyval_finalize.
;
;   SHORT (POLYVAL_PROFILE = POLYVAL_PROFILE_SHORT = 1):
;     $4000 .. $7E95 = $3E95 = 16021 measured (archive members alone
;     15907: same AES + GCM-SIV surface, polyval_short $352E). Both
;     round UP to the same boundary: declared 16128 ($3F00).
;     polyval_multiply is the heavily-unrolled 4-bit Shoup Tier 1
;     variant plus a larger polyval_precompute_table; the SHORT
;     profile trades RAM-resident code size for smaller BSS (no 4 KB
;     polyval_htable8 and no 4 KB polyval_reduce8).
;
;   COMPACT (POLYVAL_PROFILE = POLYVAL_PROFILE_COMPACT = 3):
;     $4000 .. $4AAC = $AAC = 2732 measured (archive members alone
;     2618: same AES + GCM-SIV surface, polyval_compact $145 = 325).
;     Both round UP to the same boundary: declared 2816 ($B00).
;     Same 256-byte polyval_htable and same mathematics as SHORT with
;     the unrolling rolled back into loops — the axis this profile
;     moves on is code size, not table RAM (issue #51).
;
; POLYVAL-only builds (-D LIB_POLYVAL_NO_AES=1; polyval-long.a /
; polyval-short.a member set: lib_version, zp_config, lib_manifest,
; data, polyval_<profile> — no tables.o, no aes_*.o, no gcm_siv.o, so
; the resident span is the profile's code segment alone; measured with
; a 2-byte scratch LOADADDR stub that emits no MAIN bytes):
;
;   LONG:    $4000 .. $5040 = $1040 =  4160 measured; declared  4352 ($1100).
;   SHORT:   $4000 .. $752E = $352E = 13614 measured; declared 13824 ($3600).
;   COMPACT: $4000 .. $4145 =  $145 =   325 measured; declared   512  ($200).
;
; Pre-§6.6 the values were gated on POLYVAL_PROFILE only, so
; polyval-long.a / polyval-short.a shipped manifests claiming
; AES+GCM-SIV code they do not contain (+2.3 KB over-claim; the §6.6
; changelog's nist-curves false-refusal shape, here in the
; over-claiming direction) — same defect class as issue #23.
; -----------------------------------------------------------------------------
.ifndef LIB_POLYVAL_RESIDENT_BYTES
  .if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG
    .ifdef LIB_POLYVAL_NO_AES
      LIB_POLYVAL_RESIDENT_BYTES = 4352   ; measured 4160  (polyval-long.a)
    .else
      LIB_POLYVAL_RESIDENT_BYTES = 6656   ; measured 6609  (polyval.a / polyval-gcmsiv.a)
    .endif
  .elseif POLYVAL_PROFILE = POLYVAL_PROFILE_SHORT
    .ifdef LIB_POLYVAL_NO_AES
      LIB_POLYVAL_RESIDENT_BYTES = 13824  ; measured 13614 (polyval-short.a)
    .else
      LIB_POLYVAL_RESIDENT_BYTES = 16128  ; measured 16063 (polyval-gcmsiv-short.a)
    .endif
  .else
    .ifdef LIB_POLYVAL_NO_AES
      LIB_POLYVAL_RESIDENT_BYTES = 512    ; measured 325   (polyval-compact.a)
    .else
      LIB_POLYVAL_RESIDENT_BYTES = 2816   ; measured 2774  (polyval-gcmsiv-compact.a)
    .endif
  .endif
.endif


; -----------------------------------------------------------------------------
; Cold (overlay-able) footprint (safe-direction, SPEC §6.6)
; -----------------------------------------------------------------------------
; Library code + rodata that a consumer MAY page-overlay (load on
; demand from REU, kernal-banked RAM, or external storage) without
; breaking a steady-state polyval_update / gcm_siv_encrypt call. For
; c64-polyval these are the boot-only init paths:
;
;   aes_key_expansion        -- runs once per AES key install.
;                               After the 240-byte schedule is
;                               populated, the body of this routine
;                               can be paged out; aes_encrypt_block /
;                               aes_decrypt_block read only the
;                               expanded schedule, not the expander.
;                               AEAD archives only — the POLYVAL-only
;                               archives (LIB_POLYVAL_NO_AES) do not
;                               ship it, so it must not be counted
;                               there (SPEC §6.4/§6.6).
;   polyval_precompute_table -- runs once per H-key install. The
;                               steady-state polyval_multiply reads
;                               the populated htable / htable8 /
;                               reduce8 tables in BSS, not the
;                               precompute body.
;
; Declared value = measured, rounded UP to the next 256-byte boundary
; (SPEC §6.6 obligation 1; the pre-§6.6 values rounded DOWN — 1239
; declared 1200, 3059 declared 3000). RESIDENT_BYTES and COLD_BYTES
; are a pair per §6.6: COLD is reclaimable-after-init and may live in
; a different consumer budget; note COLD is a *subset carve-out* of
; the same load image (the spans below lie inside the RESIDENT span),
; so a consumer overlaying it budgets RESIDENT for the image and gets
; COLD back after init.
;
; Label-span measurements (2026-08-15, from the same four lib_only.cfg
; links as RESIDENT_BYTES above; spans identical between the AEAD and
; NO_AES links of the same profile, only the base addresses shift):
;
; LONG AEAD (POLYVAL_PROFILE=2, polyval.a / polyval-gcmsiv.a):
;   aes_key_expansion        $4134 -> aes_decrypt_block    $41F4   192
;   polyval_precompute_table $4814 -> polyval_multiply     $4C2B  1047
;                                                                -----
;                                                          measured 1239
;   Declared 1280 ($500).
;
; SHORT AEAD (POLYVAL_PROFILE=1):
;   aes_key_expansion        $4134 -> aes_decrypt_block    $41F4   192
;   polyval_precompute_table $4814 -> polyval_multiply     $5347  2867
;                                                                -----
;                                                          measured 3059
;   Declared 3072 ($C00).
;
; COMPACT AEAD (POLYVAL_PROFILE=3):
;   aes_key_expansion        $4134 -> aes_decrypt_block    $41F4   192
;   polyval_precompute_table $479D -> segment end          $4830   147
;                                                                -----
;                                                          measured  339
;   Declared 512 ($200).
;   COMPACT is the one profile whose cold span is measured to the END of
;   its code segment rather than to the next top-level label: the file
;   places polyval_precompute_table and its only private helper last, so
;   the overlayable region is contiguous. pv_xor_temp_acc is deliberately
;   NOT in it — polyval_update calls it on every block.
;
; LONG NO_AES (polyval-long.a — no aes_key_expansion in the archive):
;   polyval_precompute_table $4129 -> polyval_multiply     $4540  1047
;   Declared 1280 ($500).
;
; SHORT NO_AES (polyval-short.a):
;   polyval_precompute_table $4129 -> polyval_multiply     $4C5C  2867
;   Declared 3072 ($C00).
;
; COMPACT NO_AES (polyval-compact.a):
;   polyval_precompute_table $40B2 -> segment end          $4145   147
;   Declared 256 ($100).
;
; (For LONG and SHORT the NO_AES declared values coincide with the AEAD
; ones because dropping the 192-byte aes_key_expansion does not cross a
; 256-byte boundary. COMPACT is the case that shows why the gating is
; load-bearing rather than decorative: its cold span is 147 B, so the
; same 192-byte drop moves the declared value 512 -> 256.)
;
; polyval_init (zero polyval_h) is NOT counted: it is a 12-byte
; per-message reset in GCM-SIV's RFC 8452 H-rederivation, not a one-
; shot cold path. RFC 8452 GCM-SIV intentionally re-runs this on every
; message because H changes; consumers driving polyval directly with a
; stable H (TLS 1.3, WireGuard) call it once at session setup but the
; cost is negligible either way.
; -----------------------------------------------------------------------------
.ifndef LIB_POLYVAL_COLD_BYTES
  .if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG
    .ifdef LIB_POLYVAL_NO_AES
      LIB_POLYVAL_COLD_BYTES = 1280   ; measured 1047 (polyval-long.a)
    .else
      LIB_POLYVAL_COLD_BYTES = 1280   ; measured 1239 (polyval.a / polyval-gcmsiv.a)
    .endif
  .elseif POLYVAL_PROFILE = POLYVAL_PROFILE_SHORT
    .ifdef LIB_POLYVAL_NO_AES
      LIB_POLYVAL_COLD_BYTES = 3072   ; measured 2867 (polyval-short.a)
    .else
      LIB_POLYVAL_COLD_BYTES = 3072   ; measured 3059 (polyval-gcmsiv-short.a)
    .endif
  .else
    .ifdef LIB_POLYVAL_NO_AES
      LIB_POLYVAL_COLD_BYTES = 256    ; measured 147  (polyval-compact.a)
    .else
      LIB_POLYVAL_COLD_BYTES = 512    ; measured 339  (polyval-gcmsiv-compact.a)
    .endif
  .endif
.endif


; -----------------------------------------------------------------------------
; §8.0 catch-loop: precalculated-table enumeration
; -----------------------------------------------------------------------------
; c64-lib-contract SPEC §8.0 requires every adopter to enumerate any
; precalculated table meeting the floor (>= 256 B AND one of:
; REU-resident, hot-loop-read, page-aligned for fetch alignment) via
; the LIB_PRECALC_TABLE macro, in addition to the docs/precalc-tables.md
; human-readable row. c64-polyval consumes none of the §8.1-§8.3 shared
; primitives (GF(2^128) carry-less multiply has no 8x8 quarter-square
; table), so LIB_POLYVAL_SHARED_PRIMITIVES is not emitted -- but the
; enumeration duty applies regardless. See docs/precalc-tables.md for
; the classification rationale behind each PRECALC_SHARED_NO below.
;
; The fifth macro argument is the SPEC v0.7.0 library prefix: each
; invocation emits both LIB_POLYVAL_PRECALC_<name>_* (collision-free,
; permanent) and the deprecated bare LIB_PRECALC_<name>_* triple, the
; latter gated on LIB_NO_BARE_EXPORTS (removed at contract v1.0). The
; prefix names the declaring library, never the table -- table names
; stay unprefixed per SPEC §8.1.
;
; polyval_htable is built by all three profiles; polyval_htable8 and
; polyval_reduce8 exist only under the LONG profile (SHORT and COMPACT
; use the 4-bit Shoup window alone instead of precomputing all 16 nibble
; positions x 16 possible values).
; -----------------------------------------------------------------------------
LIB_PRECALC_TABLE "polyval_htable", 256, PRECALC_REGION_RAM, PRECALC_SHARED_NO, "POLYVAL"

.if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG
LIB_PRECALC_TABLE "polyval_htable8",  4096, PRECALC_REGION_RAM, PRECALC_SHARED_NO, "POLYVAL"
LIB_PRECALC_TABLE "polyval_reduce8",  4096, PRECALC_REGION_RAM, PRECALC_SHARED_NO, "POLYVAL"
.endif

; aes_sbox / aes_inv_sbox live in src/tables.s, which is a member of
; the AEAD archives (polyval.a / polyval-gcmsiv.a) and the full-app /
; lib-verify links only. The POLYVAL-only archives (polyval-long.a /
; polyval-short.a) omit tables.o, so their manifests must not describe
; 512 B of tables they do not ship (issue #23; same defect class as
; c64-lib-contract#62). Archive membership is an axis POLYVAL_PROFILE
; cannot express -- polyval-long.a and polyval-gcmsiv.a are both built
; at PROFILE=long -- so the lib-polyval-{long,short} Makefile targets
; pass -D LIB_POLYVAL_NO_AES=1 to suppress these two rows.
.ifndef LIB_POLYVAL_NO_AES
LIB_PRECALC_TABLE "aes_sbox",     256, PRECALC_REGION_RODATA, PRECALC_SHARED_NO, "POLYVAL"
LIB_PRECALC_TABLE "aes_inv_sbox", 256, PRECALC_REGION_RODATA, PRECALC_SHARED_NO, "POLYVAL"
.endif


; --- Exports ---
; Force absolute address-size on the exports: every value above fits
; in zero-page numerically, so ca65 would default-tag them as
; `zeropage` and ld65 would warn at every `.import ... ; lda #<sym`
; import site. These symbols are scalar parameters, not addresses, so
; absolute is the correct address-size. Matches the pattern in
; src/lib_version.s and src/zp_config.s.
;
; Suppressible via `LIB_MANIFEST_NO_EXPORTS` for a future translation
; unit that wants to .include this file for the equate values without
; re-emitting the directives (ld65 errors on duplicate exports across
; multiple .o files).
.if !.defined(LIB_MANIFEST_NO_EXPORTS)

.export LIB_POLYVAL_ZP_USAGE_BYTES:  abs
.export LIB_POLYVAL_REU_BANKS_USED:  abs
.export LIB_POLYVAL_RESIDENT_BYTES:  abs
.export LIB_POLYVAL_COLD_BYTES:      abs

.endif ; !LIB_MANIFEST_NO_EXPORTS

.endif ; LIB_MANIFEST_S_INCLUDED
