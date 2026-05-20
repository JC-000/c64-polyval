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
;   LIB_POLYVAL_RESIDENT_BYTES   - Approx CPU-RAM-resident footprint
;                                  (library code + rodata that must
;                                  remain in CPU RAM at runtime to serve
;                                  a polyval_update / gcm_siv_encrypt
;                                  call). Profile-conditional: the LONG
;                                  and SHORT builds differ substantively
;                                  in the size of polyval_multiply and
;                                  polyval_precompute_table.
;   LIB_POLYVAL_COLD_BYTES       - Approx code+rodata footprint that a
;                                  consumer MAY page-overlay (boot-only
;                                  init paths: aes_key_expansion and
;                                  polyval_precompute_table). Profile-
;                                  conditional for the same reason as
;                                  RESIDENT_BYTES.
;
; All values are integer equates. Consumer-side assemble-time `.assert`
; checks compare them against ld65-published `__<MEMORY>_SIZE__` symbols
; (see c64-lib-contract SPEC §5 worked example).
;
; Each equate is `.ifndef`-guarded so a consumer can override via
; `ca65 --asm-define <symbol>=<value>`. Exports are wrapped in a
; `.if !.defined(LIB_MANIFEST_NO_EXPORTS)` block so a translation unit
; that transitively `.include`s this file (e.g. via a future
; constants_lib.inc roll-up) can suppress the directives and avoid
; ld65 "duplicate symbol" errors.
;
; The numbers are approximate -- within ±5% per SPEC §5. Refreshed at
; each release that substantively changes one of them. Measurement
; methodology for RESIDENT_BYTES / COLD_BYTES: build with the relevant
; profile, then `ld65 -C src/lib_only.cfg -Ln ...` against the library
; .o files; the resulting .prg's load span up to `__LIB_POLYVAL_BSS_*`
; is the code+rodata footprint. Cold-path subset measured from the
; address delta between the entry-point label and the next top-level
; label in build/lib_labels.txt.
; =============================================================================

.ifndef LIB_MANIFEST_S_INCLUDED
LIB_MANIFEST_S_INCLUDED = 1

; constants_lib.inc defines POLYVAL_PROFILE_SHORT (=1) and
; POLYVAL_PROFILE_LONG (=2), plus the POLYVAL_PROFILE selector itself.
; We need them to gate the profile-conditional RESIDENT_BYTES / COLD_BYTES
; values below.
.include "constants_lib.inc"


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
; A future variant that offloads htable8/reduce8 to REU would override
; this equate at that point.
; -----------------------------------------------------------------------------
.ifndef LIB_POLYVAL_REU_BANKS_USED
  LIB_POLYVAL_REU_BANKS_USED = 0
.endif


; -----------------------------------------------------------------------------
; Resident footprint (approx)
; -----------------------------------------------------------------------------
; Library code + rodata that MUST stay in CPU RAM at runtime to serve a
; polyval_update / polyval_finalize / gcm_siv_encrypt call. Measured
; from `make lib` (lib_only.cfg) which links ONLY the library .o files
; at $4000 -- the file span from $4000 up to __LIB_POLYVAL_BSS_LOAD__
; is exactly the code+rodata footprint. BSS / page-aligned tables
; (polyval_h, polyval_htable, polyval_htable8, polyval_reduce8) are
; RW state and excluded per SPEC §5 wording ("code+rodata").
;
; LONG profile (POLYVAL_PROFILE = POLYVAL_PROFILE_LONG = 2):
;   $4000 (load base) .. $59A7 (__LIB_POLYVAL_BSS_LOAD__) = $19A7
;   = 6567 bytes. Rounded to 6500 for the ±5% manifest commitment.
;   Span covers aes_encrypt_block, aes_decrypt_block, aes_key_expansion,
;   gcm_siv_encrypt/decrypt, polyval_init / polyval_double /
;   polyval_precompute_table / polyval_multiply (8-bit Shoup fused
;   shift+reduce+htable) / polyval_update / polyval_finalize.
;
; SHORT profile (POLYVAL_PROFILE = POLYVAL_PROFILE_SHORT = 1):
;   $4000 (load base) .. $7E95 (__LIB_POLYVAL_BSS_LOAD__) = $3E95
;   = 16021 bytes. Rounded to 16000 for the ±5% manifest commitment.
;   Same AES + GCM-SIV surface, but polyval_multiply is the heavily-
;   unrolled 4-bit Shoup Tier 1 variant (~10 KB unrolled body at
;   $5347-$7B2A) plus a larger polyval_precompute_table (~2.8 KB at
;   $4814-$5347). The SHORT profile trades RAM-resident code size for
;   smaller BSS (no 4 KB polyval_htable8 and no 4 KB polyval_reduce8).
; -----------------------------------------------------------------------------
.ifndef LIB_POLYVAL_RESIDENT_BYTES
  .if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG
    LIB_POLYVAL_RESIDENT_BYTES = 6500
  .else
    LIB_POLYVAL_RESIDENT_BYTES = 16000
  .endif
.endif


; -----------------------------------------------------------------------------
; Cold (overlay-able) footprint
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
;   polyval_precompute_table -- runs once per H-key install. The
;                               steady-state polyval_multiply reads
;                               the populated htable / htable8 /
;                               reduce8 tables in BSS, not the
;                               precompute body.
;
; LONG profile measurements (from build/lib_labels.txt under
; POLYVAL_PROFILE=2):
;   aes_key_expansion        $4134 -> aes_decrypt_block    $41F4   192
;   polyval_precompute_table $4814 -> polyval_multiply     $4C2B  1047
;                                                                -----
;                                                                 1239
;   Rounded to 1200 for the ±5% manifest commitment.
;
; SHORT profile measurements (from build/lib_labels.txt under
; POLYVAL_PROFILE=1):
;   aes_key_expansion        $4134 -> aes_decrypt_block    $41F4   192
;   polyval_precompute_table $4814 -> polyval_multiply     $5347  2867
;                                                                -----
;                                                                 3059
;   Rounded to 3000 for the ±5% manifest commitment.
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
    LIB_POLYVAL_COLD_BYTES = 1200
  .else
    LIB_POLYVAL_COLD_BYTES = 3000
  .endif
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
