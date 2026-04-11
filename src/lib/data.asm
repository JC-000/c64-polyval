; =============================================================================
; lib/data.asm - Mutable buffers: POLYVAL, AES, GCM-SIV state
;
; Library-owned buffers are placed inside a PC-advance block controlled by
; POLYVAL_LIB_MEM_BASE (see constants_lib.asm). Default behaviour: the block
; begins at "wherever * happens to be" when this file is !source'd, matching
; the pre-relocation layout exactly. Hosts may pre-define POLYVAL_LIB_MEM_BASE
; to force a fixed placement (e.g. $C000) — the library will then advance the
; PC and physically place its buffers at that address.
;
; App-owned buffers (disk I/O, input_buffer, etc.) currently live at the end
; of this file, OUTSIDE the library block; they get flushed to their own
; translation unit in a later phase.
; =============================================================================

; -----------------------------------------------------------------------------
; Library memory region: advance * to POLYVAL_LIB_MEM_BASE, then place all
; library buffers in a documented, stable order. Buffer layout (sizes):
;
;   polyval_h             16     hash key H
;   polyval_temp          16     multiply scratch
;   (page align)
;   polyval_htable       256     4-bit Shoup table H*{0..15}
;   (LONG profile only, each !fill block page-aligned to avoid cross-page y-index penalties)
;   polyval_htable8     4096     8-bit Shoup window, 16 page-aligned slices
;   polyval_reduce8     4096     8-bit reduction table, 16 page-aligned slices
;
;   aes_current_key              32     AES-256 key
;   aes_state             16     AES working state
;   aes_expanded_key         240     AES round keys (14+1 * 16)
;
;   aes_mc_a0..aes_mc_b3           8     MixColumns scratch
;
;   gcmsiv_*               ...   GCM-SIV derived keys, buffers, scratch
;
; POLYVAL_LIB_MEM_END = * after the final buffer.
; -----------------------------------------------------------------------------

!ifndef POLYVAL_LIB_MEM_BASE { POLYVAL_LIB_MEM_BASE = * }
!if POLYVAL_LIB_MEM_BASE < * {
        !error "POLYVAL_LIB_MEM_BASE is below current PC — host override is too low; raise it above all preceding code"
}
        * = POLYVAL_LIB_MEM_BASE

; --- POLYVAL state ---------------------------------------------------------
; polyval_acc lives in zero page ($10-$1F), defined in constants_lib.asm
polyval_h:       !fill 16, 0   ; 128-bit hash key H
polyval_temp:    !fill 16, 0   ; scratch space for current block

; page-aligned: absolute,y loads in pv_unroll_xor_htable_16 must not cross page
!align 255, 0, 0
polyval_htable:  !fill 256, 0  ; 4-bit table: H*{0..15}, 16 entries * 16 bytes

; -----------------------------------------------------------------------------
; 8-bit Shoup window tables for polyval_multiply (LONG profile only).
; Laid out as 16 page-aligned 256-byte "slices" so abs,x addressing lets us
; XOR byte j of entry i with a single `eor slice_j,x` where X = i.
;
;   polyval_htable8_slice_j + i = byte j of (H' * i)        for i in 0..255
;   polyval_reduce8_slice_j  + i = byte j of (i * x^128)     (reduction result)
;
; Both tables are built at polyval_precompute_table time.
; SHORT profile omits these (~8 KB RAM saved) since it uses only the 4-bit
; polyval_htable above.
; -----------------------------------------------------------------------------
!if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG {
!align 255, 0, 0
polyval_htable8:
polyval_htable8_s0:  !fill 256, 0
polyval_htable8_s1:  !fill 256, 0
polyval_htable8_s2:  !fill 256, 0
polyval_htable8_s3:  !fill 256, 0
polyval_htable8_s4:  !fill 256, 0
polyval_htable8_s5:  !fill 256, 0
polyval_htable8_s6:  !fill 256, 0
polyval_htable8_s7:  !fill 256, 0
polyval_htable8_s8:  !fill 256, 0
polyval_htable8_s9:  !fill 256, 0
polyval_htable8_s10: !fill 256, 0
polyval_htable8_s11: !fill 256, 0
polyval_htable8_s12: !fill 256, 0
polyval_htable8_s13: !fill 256, 0
polyval_htable8_s14: !fill 256, 0
polyval_htable8_s15: !fill 256, 0

polyval_reduce8:
polyval_reduce8_s0:  !fill 256, 0
polyval_reduce8_s1:  !fill 256, 0
polyval_reduce8_s2:  !fill 256, 0
polyval_reduce8_s3:  !fill 256, 0
polyval_reduce8_s4:  !fill 256, 0
polyval_reduce8_s5:  !fill 256, 0
polyval_reduce8_s6:  !fill 256, 0
polyval_reduce8_s7:  !fill 256, 0
polyval_reduce8_s8:  !fill 256, 0
polyval_reduce8_s9:  !fill 256, 0
polyval_reduce8_s10: !fill 256, 0
polyval_reduce8_s11: !fill 256, 0
polyval_reduce8_s12: !fill 256, 0
polyval_reduce8_s13: !fill 256, 0
polyval_reduce8_s14: !fill 256, 0
polyval_reduce8_s15: !fill 256, 0
}       ; !if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG

; --- AES state -------------------------------------------------------------
aes_current_key:
        !fill 32, 0

aes_state:
        !fill 16, 0

aes_expanded_key:
        !fill 240, 0            ; 15 round keys * 16 bytes

; mix columns temp storage
aes_mc_a0:  !byte 0
aes_mc_a1:  !byte 0
aes_mc_a2:  !byte 0
aes_mc_a3:  !byte 0
aes_mc_b0:  !byte 0
aes_mc_b1:  !byte 0
aes_mc_b2:  !byte 0
aes_mc_b3:  !byte 0

; --- GCM-SIV state ---------------------------------------------------------
gcmsiv_nonce:       !fill 12, 0     ; 96-bit nonce
gcmsiv_pt_buf:      !fill 64, 0     ; plaintext buffer
gcmsiv_pt_len:      !byte 0         ; plaintext length
gcmsiv_ct_buf:      !fill 64, 0     ; ciphertext buffer
gcmsiv_dec_buf:     !fill 64, 0     ; decrypted plaintext buffer
gcmsiv_tag:         !fill 16, 0     ; authentication tag
gcmsiv_tag_acc:     !fill 16, 0     ; tag accumulator
gcmsiv_auth_key:    !fill 16, 0     ; derived auth key
gcmsiv_enc_key:     !fill 32, 0     ; derived encryption key (256-bit for AES-256)
gcmsiv_counter:     !fill 16, 0     ; CTR mode counter
gcmsiv_keystream:   !fill 16, 0     ; keystream block
gcmsiv_block_idx:   !byte 0         ; block processing index
gcmsiv_ct_idx:      !byte 0         ; ciphertext index
gcmsiv_ks_idx:      !byte 0         ; keystream index
gcmsiv_tag_valid:   !byte 0         ; tag verification: 0=fail, 1=pass
gcmsiv_verify_tag:  !fill 16, 0     ; saved received tag for verification
gcmsiv_saved_key:   !fill 32, 0     ; saved original key during derivation
gcmsiv_exp_enc_key: !fill 256, 0    ; expanded derived encryption key
gcmsiv_saved_exp:   !fill 256, 0    ; saved original expanded key

POLYVAL_LIB_MEM_END = *
