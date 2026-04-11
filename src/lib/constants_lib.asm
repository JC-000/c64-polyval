; =============================================================================
; lib/constants_lib.asm - Library equates (POLYVAL, AES, GCM-SIV)
; No code emitted. Pure equates. No KERNAL / PETSCII / hardware references.
; =============================================================================

; zero page variables used by library code
zp_ptr          = $fb           ; 2-byte pointer
zp_temp         = $fd           ; temp storage
zp_count        = $fe           ; loop counter
zp_ptr2         = $02           ; second pointer (2 bytes)
zp_round        = $04           ; aes round counter
zp_col          = $05           ; aes column counter
zp_tmp1         = $06           ; aes temp
zp_tmp2         = $07           ; aes temp
zp_tmp3         = $08           ; aes temp
zp_tmp4         = $09           ; aes temp
polyval_acc     = $10           ; 16-byte POLYVAL accumulator ($10-$1F)
pv_mul_input    = $20           ; 16-byte multiply input scratch ($20-$2F)

; aes constants
aes_block_size  = 16            ; 128 bits = 16 bytes
aes_key_size    = 32            ; 256 bits = 32 bytes
aes_rounds      = 14            ; aes-256 uses 14 rounds
aes_expanded_key_size = 240     ; (14+1) * 16 = 240 bytes

; buffer sizes (referenced by data.asm and aes_encrypt.asm)
input_buf_size  = 64            ; max input text size
encrypt_buf_size = 80           ; encrypted output size (input + up to 16 pad)

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
