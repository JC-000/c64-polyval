; =============================================================================
; data.asm - Mutable buffers: key, AES state, GCM-SIV, POLYVAL, I/O
; =============================================================================

; =============================================================================
; key and AES working data
; =============================================================================
key_data:
        !fill 32, 0

aes_state:
        !fill 16, 0

expanded_key:
        !fill 240, 0            ; 15 round keys * 16 bytes

; encryption buffers
input_buffer:
        !fill input_buf_size, 0

encrypt_buffer:
        !fill encrypt_buf_size, 0

input_length:
        !byte 0

encrypt_length:
        !byte 0

input_index:
        !byte 0

; disk I/O variables
drive_number:
        !byte 8

filename_buf:
        !fill 17, 0

actual_filename:
        !fill 17, 0

filename_len:
        !byte 0

filename_suffix:
        !byte 0

using_default_name:
        !byte 0

file_exists_flag:
        !byte 0

cmd_buffer:
        !fill 24, 0

write_fname_buf:
        !fill 32, 0

write_fname_len:
        !byte 0

read_fname_buf:
        !fill 32, 0

read_fname_len:
        !byte 0

key_read_buf:
        !fill 32, 0

decimal_flag:
        !byte 0

save_byte_index:
        !byte 0

read_byte_index:
        !byte 0

read_temp_byte:
        !byte 0

disk_error_code:
        !byte 0, 0

default_gcm_filename:
        !text "AESGCM"
        !byte 0

; GCM-SIV variables
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

; mix columns temp storage
mc_a0:  !byte 0
mc_a1:  !byte 0
mc_a2:  !byte 0
mc_a3:  !byte 0
mc_b0:  !byte 0
mc_b1:  !byte 0
mc_b2:  !byte 0
mc_b3:  !byte 0

; POLYVAL buffers
; polyval_acc is in zero page ($10-$1F), defined in constants.asm
polyval_h:       !fill 16, 0   ; 128-bit hash key H
polyval_temp:    !fill 16, 0   ; scratch space for current block
; page-aligned: absolute,y loads in pv_unroll_xor_htable_16 must not cross page
!align 255, 0, 0
polyval_htable:  !fill 256, 0  ; 4-bit table: H*{0..15}, 16 entries * 16 bytes

; -----------------------------------------------------------------------------
; 8-bit Shoup window tables for polyval_multiply.
; Laid out as 16 page-aligned 256-byte "slices" so abs,x addressing lets us
; XOR byte j of entry i with a single `eor slice_j,x` where X = i.
;
;   polyval_htable8_slice_j + i = byte j of (H' * i)        for i in 0..255
;   polyval_reduce8_slice_j  + i = byte j of (i * x^128)     (reduction result)
;
; Both tables are built at polyval_precompute_table time.
; -----------------------------------------------------------------------------
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
