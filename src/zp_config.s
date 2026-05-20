.setcpu "6502"

; =============================================================================
; zp_config.s - public zero-page slot inventory for c64-polyval.
;
; Per c64-lib-contract SPEC.md §2 (zero-page contract), every ZP slot the
; library claims is declared here as an `.ifndef`-guarded equate and is
; `.exportzp`-ed so consumer modules can `.importzp` it instead of
; `.include`-ing constants_lib.inc (which would also pull in profile
; selectors, AES sizes, and other library-internal equates the consumer
; doesn't need).
;
; ZP layout (45 bytes total claimed)
; ----------------------------------
;
;   Shared / pointer & temp slots (8 bytes):
;     polyval_zp_ptr2      $02 (2 bytes)   second pointer
;     polyval_aes_round    $04             AES round counter
;     polyval_aes_col      $05             AES column counter
;     polyval_aes_tmp1     $06             AES temp byte
;     polyval_aes_tmp2     $07             AES temp byte
;     polyval_aes_tmp3     $08             AES temp byte
;     polyval_aes_tmp4     $09             AES temp byte
;
;   POLYVAL multiply working slots (33 bytes):
;     polyval_acc          $10..$1F        16-byte accumulator
;     pv_mul_input         $20..$2F        16-byte multiply input scratch
;     pv_mul_nibble        $30             1-byte nibble param
;
;   Misc pointer / temp / counter (4 bytes):
;     polyval_zp_ptr       $fb (2 bytes)   primary pointer
;     polyval_zp_temp      $fd             temp storage
;     polyval_zp_count     $fe             loop counter
;
; Host overrides
; --------------
;
; A host program can override any slot's address by pre-defining the symbol
; before `.include`-ing zp_config.s. The two recommended ways:
;
;   1. Pass `--asm-define polyval_acc=$40` on the ca65 command line. This
;      defines the symbol globally for the translation unit, and the
;      .ifndef guard below then skips the default. ALL library translation
;      units must be assembled with the same --asm-define values, since
;      each .o bakes in the equate value at assemble time.
;
;   2. Inside a wrapper .s file:
;
;          polyval_acc = $40
;          .include "zp_config.s"
;
; The library's own standalone PRG (`make`) and library-only verification
; (`make lib`) assemble with the defaults. Consumer projects rebuild the
; library from source with --asm-define to pin slots to their preferred
; layout.
;
; Suppressing the .exportzp block
; -------------------------------
;
; When zp_config.s is transitively `.include`'d via constants_lib.inc, the
; including translation unit must NOT re-emit the `.exportzp` directives
; (ld65 errors on the same symbol being exported from multiple .o files).
; constants_lib.inc sets `ZP_CONFIG_NO_EXPORTS = 1` before the include for
; this reason. zp_config.s itself, compiled as its own .o (the only place
; the exports actually need to land), does NOT set the flag and DOES emit
; them.
; =============================================================================

.ifndef ZP_CONFIG_S_INCLUDED
ZP_CONFIG_S_INCLUDED = 1

; --- Shared pointer / temp slots ($02, $04-$09) ---
.ifndef polyval_zp_ptr2
  polyval_zp_ptr2    = $02           ; 2-byte pointer
.endif
.ifndef polyval_aes_round
  polyval_aes_round  = $04           ; AES round counter
.endif
.ifndef polyval_aes_col
  polyval_aes_col    = $05           ; AES column counter
.endif
.ifndef polyval_aes_tmp1
  polyval_aes_tmp1   = $06           ; AES temp byte
.endif
.ifndef polyval_aes_tmp2
  polyval_aes_tmp2   = $07           ; AES temp byte
.endif
.ifndef polyval_aes_tmp3
  polyval_aes_tmp3   = $08           ; AES temp byte
.endif
.ifndef polyval_aes_tmp4
  polyval_aes_tmp4   = $09           ; AES temp byte
.endif

; --- POLYVAL multiply working slots ($10-$30) ---
.ifndef polyval_acc
  polyval_acc        = $10           ; 16-byte POLYVAL accumulator ($10-$1F)
.endif
.ifndef pv_mul_input
  pv_mul_input       = $20           ; 16-byte multiply input scratch ($20-$2F)
.endif
.ifndef pv_mul_nibble
  pv_mul_nibble      = $30           ; 1-byte nibble param for polyval_xor_table_entry
.endif

; --- Misc pointer / temp / counter ($fb-$fe) ---
.ifndef polyval_zp_ptr
  polyval_zp_ptr     = $fb           ; 2-byte primary pointer
.endif
.ifndef polyval_zp_temp
  polyval_zp_temp    = $fd           ; temp storage
.endif
.ifndef polyval_zp_count
  polyval_zp_count   = $fe           ; loop counter
.endif

; --- Exports (suppressed when transitively .include'd via constants_lib.inc) ---
.if !.defined(ZP_CONFIG_NO_EXPORTS)

; Shared pointer / temp slots
.exportzp polyval_zp_ptr2
.exportzp polyval_aes_round, polyval_aes_col
.exportzp polyval_aes_tmp1, polyval_aes_tmp2, polyval_aes_tmp3, polyval_aes_tmp4

; POLYVAL multiply working slots
.exportzp polyval_acc, pv_mul_input, pv_mul_nibble

; Misc pointer / temp / counter
.exportzp polyval_zp_ptr, polyval_zp_temp, polyval_zp_count

.endif ; !ZP_CONFIG_NO_EXPORTS

.endif ; ZP_CONFIG_S_INCLUDED
