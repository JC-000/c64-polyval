; =============================================================================
; lib/constants_lib.asm - Library equates (POLYVAL, AES, GCM-SIV)
; No code emitted. Pure equates. No KERNAL / PETSCII / hardware references.
; =============================================================================

; zero page variables used by library code
; Each ZP equate is wrapped in !ifndef so a host project can pre-define its
; own ZP layout before !source'ing this file. Defaults preserve the
; standalone demo-app layout.
!ifndef zp_ptr       { zp_ptr       = $fb }   ; 2-byte pointer
!ifndef zp_temp      { zp_temp      = $fd }   ; temp storage
!ifndef zp_count     { zp_count     = $fe }   ; loop counter
!ifndef zp_ptr2      { zp_ptr2      = $02 }   ; second pointer (2 bytes)
!ifndef zp_round     { zp_round     = $04 }   ; aes round counter
!ifndef zp_col       { zp_col       = $05 }   ; aes column counter
!ifndef zp_tmp1      { zp_tmp1      = $06 }   ; aes temp
!ifndef zp_tmp2      { zp_tmp2      = $07 }   ; aes temp
!ifndef zp_tmp3      { zp_tmp3      = $08 }   ; aes temp
!ifndef zp_tmp4      { zp_tmp4      = $09 }   ; aes temp
!ifndef polyval_acc  { polyval_acc  = $10 }   ; 16-byte POLYVAL accumulator ($10-$1F)
!ifndef pv_mul_input { pv_mul_input = $20 }   ; 16-byte multiply input scratch ($20-$2F)
!ifndef pv_mul_nibble { pv_mul_nibble = $30 } ; 1-byte nibble parameter for polyval_xor_table_entry

; aes constants
aes_block_size  = 16            ; 128 bits = 16 bytes
aes_key_size    = 32            ; 256 bits = 32 bytes
aes_rounds      = 14            ; aes-256 uses 14 rounds
aes_expanded_key_size = 240     ; (14+1) * 16 = 240 bytes

; =============================================================================
; POLYVAL build profile selector
; -----------------------------------------------------------------------------
; SHORT:  4-bit Shoup table with Tier 1 unrolling. ~19k multiply, ~29k
;         precompute. Best for RFC 8452 GCM-SIV short messages (auth key H
;         is rederived per message, so precompute runs every call).
; LONG:   Shoup 8-bit fused shift+reduce+htable. ~4k multiply, ~255k
;         precompute. Best for long-message / session-stable-H workloads
;         (TLS 1.3, WireGuard) where precompute amortises.
;
; Define POLYVAL_PROFILE on the ACME command line via -DPOLYVAL_PROFILE=...
; If left undefined, default to LONG (preserves feature/polyval-speed-sprint
; correctness).
; =============================================================================
POLYVAL_PROFILE_SHORT = 1
POLYVAL_PROFILE_LONG  = 2
!ifndef POLYVAL_PROFILE {
        POLYVAL_PROFILE = POLYVAL_PROFILE_LONG
}

; =============================================================================
; POLYVAL_LIB_MEM_BASE — library absolute-memory relocation anchor
; -----------------------------------------------------------------------------
; Library buffers (polyval_h, polyval_htable, polyval_htable8, AES state,
; GCM-SIV state, etc.) are placed inside a PC-advance block at this address
; when lib/data.asm is !source'd.
;
; Default: NOT defined here — lib/data.asm falls back to "wherever * happens
; to be" which preserves the standalone demo-app layout and wastes zero bytes.
;
; Host override: define POLYVAL_LIB_MEM_BASE before !source'ing any library
; file (typically alongside the other overrides). The library will advance *
; to POLYVAL_LIB_MEM_BASE before declaring buffers, so tables land at a
; known address. lib/data.asm will error out if POLYVAL_LIB_MEM_BASE is
; below the current PC (the override is too low — raise it). It also
; declares POLYVAL_LIB_MEM_END = * after the final buffer so the host can
; see how much space the library consumed.
; =============================================================================
