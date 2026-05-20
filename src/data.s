; =============================================================================
; lib/data.s - Mutable buffers: POLYVAL, AES, GCM-SIV state (ca65 port)
;
; ca65 equivalent of src/lib/data.asm. Buffer placement in the ACME original
; is done by advancing `*` to POLYVAL_LIB_MEM_BASE and emitting `!fill`/`!align`
; blocks. Under ca65 the equivalent is segment placement:
;
;   - Non-aligned 16-byte buffers (polyval_h, polyval_temp, aes_state, ...)
;     go in BSS. They are reservation-only; ld65 places them sequentially
;     within MAIN and does not emit any bytes to the PRG for them.
;
;   - Page-aligned tables (polyval_htable, polyval_htable8_*, polyval_reduce8_*)
;     each go in their own POLYVAL_* segment in c64.cfg, which has
;     align = $100. The linker places each on a page boundary.
;
; ZP symbols used by the library are equates (fixed addresses $10, $20, $30)
; pulled from constants_lib.inc and re-exported via .exportzp so the test
; harness (and sibling .s files) can resolve them as ZP.
; =============================================================================

.include "constants_lib.inc"

; ---------------------------------------------------------------------------
; Zero-page: equates from constants_lib.inc, exported as ZP.
; These are absolute addresses (not .res reservations) to match the ACME
; layout byte-for-byte. polyval_acc must land at $10-$1F, pv_mul_input at
; $20-$2F, pv_mul_nibble at $30. Anything else is host policy and is not
; re-exported here.
; ---------------------------------------------------------------------------
.exportzp polyval_acc
.exportzp pv_mul_input
.exportzp pv_mul_nibble
.exportzp zp_ptr
.exportzp zp_ptr2
.exportzp zp_temp
.exportzp zp_count
.exportzp zp_round
.exportzp zp_col
.exportzp zp_tmp1
.exportzp zp_tmp2
.exportzp zp_tmp3
.exportzp zp_tmp4

; ---------------------------------------------------------------------------
; POLYVAL state - small buffers in BSS.
; (polyval_acc lives in zero page, exported above.)
; ---------------------------------------------------------------------------
.export polyval_h
.export polyval_temp

.segment "LIB_POLYVAL_BSS"
polyval_h:      .res 16         ; 128-bit hash key H
polyval_temp:   .res 16         ; scratch space for current block

; ---------------------------------------------------------------------------
; Page-aligned 4-bit Shoup H-table (both profiles). Its own segment so
; ld65 aligns it to $100.
; ---------------------------------------------------------------------------
.export polyval_htable

.segment "LIB_POLYVAL_HTABLE"
polyval_htable: .res 256        ; 16 entries * 16 bytes

; ---------------------------------------------------------------------------
; 8-bit Shoup window tables (LONG profile only).
;
; Laid out as 16 page-aligned 256-byte slices so abs,x addressing lets us
; XOR byte j of entry i with a single `eor slice_j,x` where X = i.
;
;   polyval_htable8_slice_j + i = byte j of (H' * i)       for i in 0..255
;   polyval_reduce8_slice_j  + i = byte j of (i * x^128)    (reduction result)
;
; Both tables are built at polyval_precompute_table time. SHORT profile
; omits these (~8 KB RAM saved).
;
; IMPORTANT: each slice is its own 256-byte block inside the POLYVAL_HTABLE8
; / POLYVAL_REDUCE8 segment. The segment is aligned to $100 in c64.cfg;
; because each slice is exactly 256 bytes, slice_k lands at
; segment_start + k*256, which is also page-aligned. (ld65 does not re-align
; *within* a segment -- we rely on the math.)
; ---------------------------------------------------------------------------
.if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG

.export polyval_htable8
.export polyval_htable8_s0
.export polyval_htable8_s1
.export polyval_htable8_s2
.export polyval_htable8_s3
.export polyval_htable8_s4
.export polyval_htable8_s5
.export polyval_htable8_s6
.export polyval_htable8_s7
.export polyval_htable8_s8
.export polyval_htable8_s9
.export polyval_htable8_s10
.export polyval_htable8_s11
.export polyval_htable8_s12
.export polyval_htable8_s13
.export polyval_htable8_s14
.export polyval_htable8_s15

.segment "LIB_POLYVAL_LONG_HTABLE8"
polyval_htable8:
polyval_htable8_s0:  .res 256
polyval_htable8_s1:  .res 256
polyval_htable8_s2:  .res 256
polyval_htable8_s3:  .res 256
polyval_htable8_s4:  .res 256
polyval_htable8_s5:  .res 256
polyval_htable8_s6:  .res 256
polyval_htable8_s7:  .res 256
polyval_htable8_s8:  .res 256
polyval_htable8_s9:  .res 256
polyval_htable8_s10: .res 256
polyval_htable8_s11: .res 256
polyval_htable8_s12: .res 256
polyval_htable8_s13: .res 256
polyval_htable8_s14: .res 256
polyval_htable8_s15: .res 256

.export polyval_reduce8
.export polyval_reduce8_s0
.export polyval_reduce8_s1
.export polyval_reduce8_s2
.export polyval_reduce8_s3
.export polyval_reduce8_s4
.export polyval_reduce8_s5
.export polyval_reduce8_s6
.export polyval_reduce8_s7
.export polyval_reduce8_s8
.export polyval_reduce8_s9
.export polyval_reduce8_s10
.export polyval_reduce8_s11
.export polyval_reduce8_s12
.export polyval_reduce8_s13
.export polyval_reduce8_s14
.export polyval_reduce8_s15

.segment "LIB_POLYVAL_LONG_REDUCE8"
polyval_reduce8:
polyval_reduce8_s0:  .res 256
polyval_reduce8_s1:  .res 256
polyval_reduce8_s2:  .res 256
polyval_reduce8_s3:  .res 256
polyval_reduce8_s4:  .res 256
polyval_reduce8_s5:  .res 256
polyval_reduce8_s6:  .res 256
polyval_reduce8_s7:  .res 256
polyval_reduce8_s8:  .res 256
polyval_reduce8_s9:  .res 256
polyval_reduce8_s10: .res 256
polyval_reduce8_s11: .res 256
polyval_reduce8_s12: .res 256
polyval_reduce8_s13: .res 256
polyval_reduce8_s14: .res 256
polyval_reduce8_s15: .res 256

.endif  ; POLYVAL_PROFILE = POLYVAL_PROFILE_LONG

; ---------------------------------------------------------------------------
; AES state - in BSS.
; ---------------------------------------------------------------------------
.export aes_current_key
.export aes_state
.export aes_expanded_key
.export aes_mc_a0, aes_mc_a1, aes_mc_a2, aes_mc_a3
.export aes_mc_b0, aes_mc_b1, aes_mc_b2, aes_mc_b3

.segment "LIB_POLYVAL_AES_BSS"
aes_current_key:   .res 32
aes_state:         .res 16
aes_expanded_key:  .res 240      ; 15 round keys * 16 bytes

; MixColumns scratch
aes_mc_a0:  .res 1
aes_mc_a1:  .res 1
aes_mc_a2:  .res 1
aes_mc_a3:  .res 1
aes_mc_b0:  .res 1
aes_mc_b1:  .res 1
aes_mc_b2:  .res 1
aes_mc_b3:  .res 1

; ---------------------------------------------------------------------------
; GCM-SIV state - in BSS.
; ---------------------------------------------------------------------------
.export gcmsiv_nonce
.export gcmsiv_pt_buf
.export gcmsiv_pt_len
.export gcmsiv_ct_buf
.export gcmsiv_dec_buf
.export gcmsiv_tag
.export gcmsiv_tag_acc
.export gcmsiv_auth_key
.export gcmsiv_enc_key
.export gcmsiv_counter
.export gcmsiv_keystream
.export gcmsiv_block_idx
.export gcmsiv_ct_idx
.export gcmsiv_ks_idx
.export gcmsiv_tag_valid
.export gcmsiv_verify_tag
.export gcmsiv_saved_key
.export gcmsiv_exp_enc_key
.export gcmsiv_saved_exp

.segment "LIB_POLYVAL_GCMSIV_BSS"
gcmsiv_nonce:       .res 12     ; 96-bit nonce
gcmsiv_pt_buf:      .res 64     ; plaintext buffer
gcmsiv_pt_len:      .res 1      ; plaintext length
gcmsiv_ct_buf:      .res 64     ; ciphertext buffer
gcmsiv_dec_buf:     .res 64     ; decrypted plaintext buffer
gcmsiv_tag:         .res 16     ; authentication tag
gcmsiv_tag_acc:     .res 16     ; tag accumulator
gcmsiv_auth_key:    .res 16     ; derived auth key
gcmsiv_enc_key:     .res 32     ; derived encryption key (AES-256)
gcmsiv_counter:     .res 16     ; CTR mode counter
gcmsiv_keystream:   .res 16     ; keystream block
gcmsiv_block_idx:   .res 1      ; block processing index
gcmsiv_ct_idx:      .res 1      ; ciphertext index
gcmsiv_ks_idx:      .res 1      ; keystream index
gcmsiv_tag_valid:   .res 1      ; tag verification: 0=fail, 1=pass
gcmsiv_verify_tag:  .res 16     ; saved received tag for verification
gcmsiv_saved_key:   .res 32     ; saved original key during derivation
gcmsiv_exp_enc_key: .res 256    ; expanded derived encryption key
gcmsiv_saved_exp:   .res 256    ; saved original expanded key
