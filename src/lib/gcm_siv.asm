; =============================================================================
; lib/gcm_siv.asm - AES-256-GCM-SIV library core (RFC 8452)
; Exported: gcmsiv_encrypt, gcmsiv_decrypt, gcmsiv_derive_keys,
;   gcmsiv_compute_tag_base, gcmsiv_finalize_tag, gcmsiv_install_enc_key,
;   gcmsiv_restore_orig_key, gcmsiv_ctr_encrypt, gcmsiv_ctr_decrypt,
;   gcmsiv_gen_keystream
; No UI or disk dependencies; pure primitives.
; =============================================================================

; =============================================================================
; gcmsiv_encrypt - perform AES-256-GCM-SIV encryption
; Uses key_data as the 256-bit key
; Input: gcmsiv_pt_buf (plaintext), gcmsiv_pt_len (length), gcmsiv_nonce (12 bytes)
; Output: gcmsiv_ct_buf (ciphertext), gcmsiv_tag (16 bytes)
; =============================================================================
gcmsiv_encrypt:
        ; Step 1: Derive authentication key and encryption key from main key + nonce
        jsr gcmsiv_derive_keys

        ; Step 2: Compute POLYVAL over plaintext (no AAD)
        jsr gcmsiv_compute_tag_base

        ; Step 3: Encrypt the tag base to get final tag
        jsr gcmsiv_finalize_tag

        ; Step 4: Encrypt plaintext with AES-CTR using tag as IV
        jsr gcmsiv_ctr_encrypt

        rts

; =============================================================================
; gcmsiv_derive_keys - derive authentication and encryption keys per RFC 8452
; For AES-256-GCM-SIV: 6 AES encryptions of (counter || nonce)
; =============================================================================
gcmsiv_derive_keys:
        lda #0
        sta gcmsiv_derive_ctr

@derive_loop:
        ; Build block: little-endian counter(4) || nonce(12)
        lda gcmsiv_derive_ctr
        sta aes_state
        lda #0
        sta aes_state+1
        sta aes_state+2
        sta aes_state+3

        ldx #0
@copy_nonce:
        lda gcmsiv_nonce,x
        sta aes_state+4,x
        inx
        cpx #12
        bne @copy_nonce

        ; Encrypt with the main key
        jsr aes_encrypt_block

        ; Copy first 8 bytes to appropriate destination
        lda gcmsiv_derive_ctr
        cmp #0
        beq @store_auth_lo
        cmp #1
        beq @store_auth_hi
        cmp #2
        beq @store_enc_0
        cmp #3
        beq @store_enc_1
        cmp #4
        beq @store_enc_2
        cmp #5
        beq @store_enc_3
        jmp @derive_next

@store_auth_lo:
        ldx #0
@sal:   lda aes_state,x
        sta gcmsiv_auth_key,x
        inx
        cpx #8
        bne @sal
        jmp @derive_next

@store_auth_hi:
        ldx #0
@sah:   lda aes_state,x
        sta gcmsiv_auth_key+8,x
        inx
        cpx #8
        bne @sah
        jmp @derive_next

@store_enc_0:
        ldx #0
@se0:   lda aes_state,x
        sta gcmsiv_enc_key,x
        inx
        cpx #8
        bne @se0
        jmp @derive_next

@store_enc_1:
        ldx #0
@se1:   lda aes_state,x
        sta gcmsiv_enc_key+8,x
        inx
        cpx #8
        bne @se1
        jmp @derive_next

@store_enc_2:
        ldx #0
@se2:   lda aes_state,x
        sta gcmsiv_enc_key+16,x
        inx
        cpx #8
        bne @se2
        jmp @derive_next

@store_enc_3:
        ldx #0
@se3:   lda aes_state,x
        sta gcmsiv_enc_key+24,x
        inx
        cpx #8
        bne @se3

@derive_next:
        inc gcmsiv_derive_ctr
        lda gcmsiv_derive_ctr
        cmp #6
        bcs @derive_done_loop
        jmp @derive_loop
@derive_done_loop:

        ; Now expand the derived encryption key
        ; Save original key, install derived key, expand, restore
        ldx #0
@save_key:
        lda key_data,x
        sta gcmsiv_saved_key,x
        lda gcmsiv_enc_key,x
        sta key_data,x
        inx
        cpx #32
        bne @save_key

        jsr aes_key_expansion

        ; Copy expanded key to gcmsiv_exp_enc_key
        ldx #0
@copy_exp:
        lda expanded_key,x
        sta gcmsiv_exp_enc_key,x
        inx
        bne @copy_exp            ; copies 256 bytes

        ; Restore original key and re-expand
        ldx #0
@restore_key:
        lda gcmsiv_saved_key,x
        sta key_data,x
        inx
        cpx #32
        bne @restore_key

        jsr aes_key_expansion

        rts

gcmsiv_derive_ctr:
        !byte 0

; =============================================================================
; gcmsiv_compute_tag_base - compute authentication tag base using POLYVAL
; Processes plaintext blocks then a length block (AAD_len || PT_len in bits)
; =============================================================================
gcmsiv_compute_tag_base:
        ; Initialize POLYVAL with the derived auth key
        ; Copy auth key to polyval_h
        ldx #0
@copy_h:
        lda gcmsiv_auth_key,x
        sta polyval_h,x
        inx
        cpx #16
        bne @copy_h

        ; Precompute H table for fast multiplication
        jsr polyval_precompute_table

        ; Initialize accumulator to zero
        jsr polyval_init

        ; Process plaintext in 16-byte blocks
        lda #0
        sta gcmsiv_block_idx

@process_loop:
        ; Calculate remaining bytes
        lda gcmsiv_pt_len
        sec
        sbc gcmsiv_block_idx
        beq @process_done       ; no more data
        bmi @process_done

        ; Copy up to 16 bytes to polyval_temp, padded with zeros
        ldx #0
        ldy gcmsiv_block_idx

@copy_block:
        cpy gcmsiv_pt_len
        bcs @pad_block          ; past end of data

        lda gcmsiv_pt_buf,y
        sta polyval_temp,x
        iny
        inx
        cpx #16
        bne @copy_block
        jmp @update_block

@pad_block:
        lda #0
        sta polyval_temp,x
        inx
        cpx #16
        bne @pad_block

@update_block:
        ; XOR block into accumulator and multiply by H
        jsr polyval_update

        ; Move to next block
        lda gcmsiv_block_idx
        clc
        adc #16
        sta gcmsiv_block_idx

        ; Check if we've processed all data
        cmp gcmsiv_pt_len
        bcc @process_loop

@process_done:
        ; Process length block: 64-bit AAD bit length || 64-bit PT bit length
        ; AAD = 0, so first 8 bytes are zero
        ldx #0
        lda #0
@clear_len_block:
        sta polyval_temp,x
        inx
        cpx #16
        bne @clear_len_block

        ; Store PT bit length at bytes 8-15 (little-endian)
        ; pt_len * 8
        lda gcmsiv_pt_len
        asl                     ; *2
        asl                     ; *4
        asl                     ; *8
        sta polyval_temp+8
        lda gcmsiv_pt_len
        lsr
        lsr
        lsr
        lsr
        lsr                     ; high bits of *8
        sta polyval_temp+9
        ; bytes 10-15 stay zero

        ; Final POLYVAL update with length block
        jsr polyval_update

        ; Copy POLYVAL result to tag accumulator
        ldx #0
@copy_result:
        lda polyval_acc,x
        sta gcmsiv_tag_acc,x
        inx
        cpx #16
        bne @copy_result

        rts

; =============================================================================
; gcmsiv_finalize_tag - encrypt tag base with derived enc key to produce final tag
; =============================================================================
gcmsiv_finalize_tag:
        ; Copy tag accumulator to state
        ldx #0
@copy:
        lda gcmsiv_tag_acc,x
        sta aes_state,x
        inx
        cpx #16
        bne @copy

        ; XOR in the nonce (first 12 bytes)
        ldx #0
@xor_nonce:
        lda aes_state,x
        eor gcmsiv_nonce,x
        sta aes_state,x
        inx
        cpx #12
        bne @xor_nonce

        ; Clear MSB of last byte (as per GCM-SIV spec)
        lda aes_state+15
        and #$7f
        sta aes_state+15

        ; Install derived encryption key for this encryption
        jsr gcmsiv_install_enc_key

        ; Encrypt to get final tag
        jsr aes_encrypt_block

        ; Restore original key
        jsr gcmsiv_restore_orig_key

        ; Store tag
        ldx #0
@store:
        lda aes_state,x
        sta gcmsiv_tag,x
        inx
        cpx #16
        bne @store

        rts

; =============================================================================
; gcmsiv_install_enc_key - install derived enc key into expanded_key
; =============================================================================
gcmsiv_install_enc_key:
        ldx #0
@save:
        lda expanded_key,x
        sta gcmsiv_saved_exp,x
        inx
        bne @save

        ldx #0
@install:
        lda gcmsiv_exp_enc_key,x
        sta expanded_key,x
        inx
        bne @install
        rts

; =============================================================================
; gcmsiv_restore_orig_key - restore original expanded key
; =============================================================================
gcmsiv_restore_orig_key:
        ldx #0
@restore:
        lda gcmsiv_saved_exp,x
        sta expanded_key,x
        inx
        bne @restore
        rts

; =============================================================================
; gcmsiv_ctr_encrypt - encrypt plaintext using AES-CTR with tag as IV
; =============================================================================
gcmsiv_ctr_encrypt:
        jsr gcmsiv_install_enc_key

        ; Copy tag to counter block
        ldx #0
@copy_tag:
        lda gcmsiv_tag,x
        sta gcmsiv_counter,x
        inx
        cpx #16
        bne @copy_tag

        ; Set MSB of last byte (counter mode indicator)
        lda gcmsiv_counter+15
        ora #$80
        sta gcmsiv_counter+15

        lda #0
        sta gcmsiv_ct_idx
        sta gcmsiv_ks_idx
        lda #16
        sta gcmsiv_ks_idx

@encrypt_loop:
        lda gcmsiv_ct_idx
        cmp gcmsiv_pt_len
        bcs @encrypt_done

        lda gcmsiv_ks_idx
        cmp #16
        bcc @have_keystream

        jsr gcmsiv_gen_keystream
        lda #0
        sta gcmsiv_ks_idx

@have_keystream:
        ldx gcmsiv_ct_idx
        ldy gcmsiv_ks_idx
        lda gcmsiv_pt_buf,x
        eor gcmsiv_keystream,y
        sta gcmsiv_ct_buf,x

        inc gcmsiv_ct_idx
        inc gcmsiv_ks_idx

        jmp @encrypt_loop

@encrypt_done:
        jsr gcmsiv_restore_orig_key
        rts

; =============================================================================
; gcmsiv_gen_keystream - generate 16-byte keystream block
; =============================================================================
gcmsiv_gen_keystream:
        ldx #0
@copy:
        lda gcmsiv_counter,x
        sta aes_state,x
        inx
        cpx #16
        bne @copy

        jsr aes_encrypt_block

        ldx #0
@store:
        lda aes_state,x
        sta gcmsiv_keystream,x
        inx
        cpx #16
        bne @store

        ; Increment counter (32-bit LE increment on bytes 0-3)
        inc gcmsiv_counter
        bne @no_carry
        inc gcmsiv_counter+1
        bne @no_carry
        inc gcmsiv_counter+2
        bne @no_carry
        inc gcmsiv_counter+3
@no_carry:
        rts

; =============================================================================
; gcmsiv_decrypt - perform AES-256-GCM-SIV decryption with tag verification
; =============================================================================
gcmsiv_decrypt:
        lda #0
        sta gcmsiv_tag_valid

        ; Step 1: Derive keys
        jsr gcmsiv_derive_keys

        ; Step 2: Decrypt ciphertext using AES-CTR with stored tag as IV
        jsr gcmsiv_ctr_decrypt

        ; Step 3: Save received tag, recompute tag over decrypted plaintext
        ldx #0
@save_tag:
        lda gcmsiv_tag,x
        sta gcmsiv_verify_tag,x
        inx
        cpx #16
        bne @save_tag

        ; Copy decrypted data to pt_buf for tag computation
        lda gcmsiv_pt_len
        beq @skip_copy          ; skip if zero-length plaintext
        ldx #0
@copy_dec:
        lda gcmsiv_dec_buf,x
        sta gcmsiv_pt_buf,x
        inx
        cpx gcmsiv_pt_len
        bne @copy_dec
@skip_copy:

        ; Recompute tag
        jsr gcmsiv_compute_tag_base
        jsr gcmsiv_finalize_tag

        ; Compare recomputed tag with received tag
        ldx #0
@compare:
        lda gcmsiv_tag,x
        cmp gcmsiv_verify_tag,x
        bne @tag_fail
        inx
        cpx #16
        bne @compare

        lda #1
        sta gcmsiv_tag_valid

        ; Restore original tag
        ldx #0
@restore_tag:
        lda gcmsiv_verify_tag,x
        sta gcmsiv_tag,x
        inx
        cpx #16
        bne @restore_tag
        rts

@tag_fail:
        lda #0
        sta gcmsiv_tag_valid
        ldx #0
@clear_dec:
        sta gcmsiv_dec_buf,x
        inx
        cpx #64
        bne @clear_dec

        ldx #0
@restore_tag2:
        lda gcmsiv_verify_tag,x
        sta gcmsiv_tag,x
        inx
        cpx #16
        bne @restore_tag2
        rts

; =============================================================================
; gcmsiv_ctr_decrypt - decrypt ciphertext using AES-CTR with tag as IV
; =============================================================================
gcmsiv_ctr_decrypt:
        jsr gcmsiv_install_enc_key

        ldx #0
@copy_tag:
        lda gcmsiv_tag,x
        sta gcmsiv_counter,x
        inx
        cpx #16
        bne @copy_tag

        lda gcmsiv_counter+15
        ora #$80
        sta gcmsiv_counter+15

        lda #0
        sta gcmsiv_ct_idx
        lda #16
        sta gcmsiv_ks_idx

@decrypt_loop:
        lda gcmsiv_ct_idx
        cmp gcmsiv_pt_len
        bcs @decrypt_done

        lda gcmsiv_ks_idx
        cmp #16
        bcc @have_keystream

        jsr gcmsiv_gen_keystream
        lda #0
        sta gcmsiv_ks_idx

@have_keystream:
        ldx gcmsiv_ct_idx
        ldy gcmsiv_ks_idx
        lda gcmsiv_ct_buf,x
        eor gcmsiv_keystream,y
        sta gcmsiv_dec_buf,x

        inc gcmsiv_ct_idx
        inc gcmsiv_ks_idx

        jmp @decrypt_loop

@decrypt_done:
        jsr gcmsiv_restore_orig_key
        rts
