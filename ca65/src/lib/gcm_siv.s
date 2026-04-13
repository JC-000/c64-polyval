; =============================================================================
; lib/gcm_siv.s - AES-256-GCM-SIV library core (RFC 8452) - ca65 port
;
; ca65 port of src/lib/gcm_siv.asm. Mechanical; behavior-exact.
;
; Exported: gcmsiv_encrypt, gcmsiv_decrypt, gcmsiv_derive_keys,
;   gcmsiv_compute_tag_base, gcmsiv_finalize_tag, gcmsiv_install_enc_key,
;   gcmsiv_restore_orig_key, gcmsiv_ctr_encrypt, gcmsiv_ctr_decrypt,
;   gcmsiv_gen_keystream
; No UI or disk dependencies; pure primitives.
;
; Empty-plaintext decrypt fix: gcmsiv_decrypt's copy loop (cpx/bne) ran 256
; iterations when pt_len=0, corrupting tag/keys. Fix: `lda pt_len` / `beq
; @skip_copy` guard before the copy loop. Preserved from ACME source.
; =============================================================================

.include "constants_lib.inc"

; AES state + siblings
.import aes_state
.import aes_expanded_key
.import aes_current_key
.import aes_encrypt_block
.import aes_key_expansion

; POLYVAL state + siblings (owned by porter-polyval / data.s)
; Note: polyval_acc is a ZP equate from constants_lib.inc, not an import.
.import polyval_h
.import polyval_temp
.import polyval_precompute_table
.import polyval_init
.import polyval_update

; GCM-SIV state (from data.s)
.import gcmsiv_nonce
.import gcmsiv_pt_buf
.import gcmsiv_pt_len
.import gcmsiv_ct_buf
.import gcmsiv_dec_buf
.import gcmsiv_tag
.import gcmsiv_tag_acc
.import gcmsiv_auth_key
.import gcmsiv_enc_key
.import gcmsiv_counter
.import gcmsiv_keystream
.import gcmsiv_block_idx
.import gcmsiv_ct_idx
.import gcmsiv_ks_idx
.import gcmsiv_tag_valid
.import gcmsiv_verify_tag
.import gcmsiv_saved_key
.import gcmsiv_exp_enc_key
.import gcmsiv_saved_exp

.export gcmsiv_encrypt
.export gcmsiv_decrypt
.export gcmsiv_derive_keys
.export gcmsiv_compute_tag_base
.export gcmsiv_finalize_tag
.export gcmsiv_install_enc_key
.export gcmsiv_restore_orig_key
.export gcmsiv_ctr_encrypt
.export gcmsiv_ctr_decrypt
.export gcmsiv_gen_keystream
.export gcmsiv_derive_ctr

.segment "CODE"

; =============================================================================
; gcmsiv_encrypt - full AES-256-GCM-SIV encryption (RFC 8452)
;
; Pipeline:
;   1. gcmsiv_derive_keys     (auth+enc keys from master key + nonce)
;   2. gcmsiv_compute_tag_base (POLYVAL over plaintext || lengths)
;   3. gcmsiv_finalize_tag    (AES-encrypt the base with derived enc key)
;   4. gcmsiv_ctr_encrypt     (AES-CTR keystream over plaintext)
;
; Caveat: this library's GCM-SIV wrapper does NOT currently absorb AAD
; into the tag. gcmsiv_compute_tag_base treats AAD length as zero. The
; gcmsiv_aad_buf / gcmsiv_aad_len symbols mentioned in the draft API
; header are reserved for a future extension.
;
; Entry:
;   A, X, Y      n/a
;   memory       aes_current_key  = 32-byte AES-256 master key
;                gcmsiv_nonce     = 12-byte nonce
;                gcmsiv_pt_buf    = plaintext
;                gcmsiv_pt_len    = plaintext length in bytes (0..64)
;                aes_expanded_key = already expanded from aes_current_key
;                                   (caller must have called
;                                   aes_key_expansion earlier)
;
; Exit:
;   A, X, Y      undefined
;   memory       gcmsiv_ct_buf    = ciphertext (pt_len bytes)
;                gcmsiv_tag       = 16-byte authentication tag
;                aes_expanded_key = restored to master-key schedule
;                aes_current_key  = preserved
;                polyval_h        = CLOBBERED (holds H' after tag_base)
;                polyval_htable*  = built for the derived auth key
;
; Clobbers: A, X, Y, all POLYVAL / AES / GCM-SIV ZP and buffer state
;           except the listed outputs and preserved inputs.
; Cycles:   unmeasured (dominated by AES and POLYVAL precompute)
; IRQ-safe: no
; Reentrant: no
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
; gcmsiv_derive_keys - RFC 8452 key derivation (auth + enc keys)
;
; For AES-256-GCM-SIV: performs 6 AES encryptions of
; (LE32(counter) || nonce), where counter = 0..5. The low 8 bytes of
; each ciphertext are concatenated to form:
;   - 16-byte POLYVAL auth key (counters 0,1)
;   - 32-byte AES-256 enc key  (counters 2,3,4,5)
; The derived enc key is then expanded into gcmsiv_exp_enc_key and the
; original master-key schedule is restored into aes_expanded_key.
;
; PRECONDITION: aes_expanded_key must already hold the expansion of
; aes_current_key (the master key). This routine does NOT re-expand it
; on entry; it assumes the caller has done so. The top-level
; gcmsiv_encrypt / gcmsiv_decrypt do NOT call aes_key_expansion
; themselves either, so the host is responsible for expanding the
; master key once before the first GCM-SIV call.
; (See SURPRISES in the Phase 3 report.)
;
; Entry:
;   A, X, Y      n/a
;   memory       aes_current_key  = 32-byte master key
;                aes_expanded_key = master-key schedule (caller ensures)
;                gcmsiv_nonce     = 12-byte nonce
;
; Exit:
;   A, X, Y      undefined
;   memory       gcmsiv_auth_key    = 16-byte POLYVAL auth key
;                gcmsiv_enc_key     = 32-byte AES-256 enc key
;                gcmsiv_exp_enc_key = 240-byte expanded enc-key schedule
;                                     (stored full 256 bytes, tail unused)
;                aes_expanded_key   = restored master-key schedule
;                aes_current_key    = preserved
;                aes_state          = clobbered
;                gcmsiv_saved_key   = clobbered (scratch)
;
; Clobbers: A, X, Y, aes_state, gcmsiv_auth_key, gcmsiv_enc_key,
;           gcmsiv_exp_enc_key, gcmsiv_saved_key, gcmsiv_derive_ctr
; Cycles:   unmeasured (dominated by 6 AES encrypts + 2 key expansions)
; IRQ-safe: no
; Reentrant: no
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
        lda aes_current_key,x
        sta gcmsiv_saved_key,x
        lda gcmsiv_enc_key,x
        sta aes_current_key,x
        inx
        cpx #32
        bne @save_key

        jsr aes_key_expansion

        ; Copy expanded key to gcmsiv_exp_enc_key
        ldx #0
@copy_exp:
        lda aes_expanded_key,x
        sta gcmsiv_exp_enc_key,x
        inx
        bne @copy_exp            ; copies 256 bytes

        ; Restore original key and re-expand
        ldx #0
@restore_key:
        lda gcmsiv_saved_key,x
        sta aes_current_key,x
        inx
        cpx #32
        bne @restore_key

        jsr aes_key_expansion

        rts

gcmsiv_derive_ctr:
        .byte 0

; =============================================================================
; gcmsiv_compute_tag_base - run POLYVAL over plaintext and the length block
;
; Pipeline:
;   1. Copy gcmsiv_auth_key -> polyval_h
;   2. polyval_precompute_table (builds H-tables from the auth key)
;   3. polyval_init             (zero the accumulator)
;   4. For each 16-byte (zero-padded) plaintext block:
;        copy into polyval_temp; polyval_update
;   5. Build and absorb the length block:
;        (AAD bit length = 0) || (PT bit length, little-endian)
;   6. Copy polyval_acc -> gcmsiv_tag_acc
;
; Caveat: AAD is NOT processed; the AAD length field is always written
; as zero. This matches the current gcmsiv_encrypt/decrypt surface,
; which does not expose AAD either.
;
; Entry:
;   A, X, Y      n/a
;   memory       gcmsiv_auth_key  = derived POLYVAL auth key
;                gcmsiv_pt_buf    = plaintext
;                gcmsiv_pt_len    = length in bytes (0..64)
;
; Exit:
;   A, X, Y      undefined
;   memory       gcmsiv_tag_acc   = 16-byte POLYVAL result
;                polyval_acc      = same result (mirror)
;                polyval_h        = CLOBBERED (now H')
;                polyval_htable*  = filled for the auth key
;                polyval_temp     = clobbered
;                gcmsiv_block_idx = clobbered
;                gcmsiv_pt_buf    = preserved
;
; Clobbers: A, X, Y, polyval_*, gcmsiv_tag_acc, gcmsiv_block_idx
; Cycles:   unmeasured
; IRQ-safe: no
; Reentrant: no
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
; gcmsiv_finalize_tag - produce the final 16-byte tag from gcmsiv_tag_acc
;
; Pipeline:
;   1. aes_state = gcmsiv_tag_acc
;   2. XOR first 12 bytes with gcmsiv_nonce
;   3. Clear the MSB of aes_state[15] (RFC 8452 tag tweak)
;   4. Install the derived enc-key schedule (gcmsiv_install_enc_key)
;   5. aes_encrypt_block
;   6. Restore the master-key schedule (gcmsiv_restore_orig_key)
;   7. gcmsiv_tag = aes_state
;
; Entry:
;   A, X, Y      n/a
;   memory       gcmsiv_tag_acc     = POLYVAL result from
;                                     gcmsiv_compute_tag_base
;                gcmsiv_nonce       = 12-byte nonce
;                gcmsiv_exp_enc_key = 240 B derived enc-key schedule
;                aes_expanded_key   = master-key schedule to preserve
;
; Exit:
;   A, X, Y      undefined
;   memory       gcmsiv_tag         = 16-byte final tag
;                aes_state          = tag (mirror of gcmsiv_tag)
;                aes_expanded_key   = restored master-key schedule
;                gcmsiv_saved_exp   = clobbered (scratch)
;
; Clobbers: A, X, Y, aes_state, gcmsiv_tag, gcmsiv_saved_exp,
;           aes_expanded_key (temporarily), aes_mc_*
; Cycles:   unmeasured
; IRQ-safe: no
; Reentrant: no
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
; gcmsiv_install_enc_key - install derived enc key into aes_expanded_key
; =============================================================================
gcmsiv_install_enc_key:
        ldx #0
@save:
        lda aes_expanded_key,x
        sta gcmsiv_saved_exp,x
        inx
        bne @save

        ldx #0
@install:
        lda gcmsiv_exp_enc_key,x
        sta aes_expanded_key,x
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
        sta aes_expanded_key,x
        inx
        bne @restore
        rts

; =============================================================================
; gcmsiv_ctr_encrypt - AES-CTR keystream from gcmsiv_pt_buf -> gcmsiv_ct_buf
;
; The counter block is initialised from gcmsiv_tag with the MSB of the
; last byte forced to 1 (RFC 8452 IV construction). The 32-bit LE
; counter at bytes 0..3 is incremented per 16-byte block. Uses the
; derived enc-key schedule via gcmsiv_install_enc_key and restores the
; master-key schedule on exit.
;
; Entry:
;   A, X, Y      n/a
;   memory       gcmsiv_tag         = 16-byte tag (used as IV seed)
;                gcmsiv_pt_buf      = plaintext
;                gcmsiv_pt_len      = length in bytes (0..64)
;                gcmsiv_exp_enc_key = derived enc-key schedule
;                aes_expanded_key   = master-key schedule to preserve
;
; Exit:
;   A, X, Y      undefined
;   memory       gcmsiv_ct_buf      = ciphertext (pt_len bytes)
;                gcmsiv_counter     = clobbered
;                gcmsiv_keystream   = clobbered
;                gcmsiv_ct_idx      = clobbered
;                gcmsiv_ks_idx      = clobbered
;                aes_state          = clobbered
;                aes_expanded_key   = restored master-key schedule
;                gcmsiv_tag         = preserved
;                gcmsiv_pt_buf      = preserved
;
; Clobbers: A, X, Y, gcmsiv_counter, gcmsiv_keystream, gcmsiv_ct_idx,
;           gcmsiv_ks_idx, gcmsiv_ct_buf, aes_state, aes_mc_*
; Cycles:   unmeasured
; IRQ-safe: no
; Reentrant: no
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
; gcmsiv_decrypt - full AES-256-GCM-SIV decryption with tag verification
;
; Pipeline:
;   1. gcmsiv_derive_keys
;   2. gcmsiv_ctr_decrypt          (CT -> gcmsiv_dec_buf)
;   3. save received tag, stage decrypted PT into gcmsiv_pt_buf
;   4. gcmsiv_compute_tag_base / gcmsiv_finalize_tag (recompute)
;   5. constant-time-ish byte-wise compare with the saved tag
;   6. on match: set gcmsiv_tag_valid=1, restore original tag;
;      on mismatch: clear gcmsiv_dec_buf, set gcmsiv_tag_valid=0, restore
;      original tag.
;
; Entry:
;   A, X, Y      n/a
;   memory       aes_current_key    = 32-byte master key
;                aes_expanded_key   = master-key schedule (pre-expanded)
;                gcmsiv_nonce       = 12-byte nonce
;                gcmsiv_ct_buf      = ciphertext
;                gcmsiv_pt_len      = plaintext length (0..64)
;                gcmsiv_tag         = received 16-byte tag
;
; Exit:
;   On valid tag:
;     A             = 0
;     Z flag        = 1 (BEQ taken)
;     gcmsiv_tag_valid = 1
;     gcmsiv_dec_buf   = plaintext (pt_len bytes)
;     gcmsiv_tag       = preserved (restored to received tag)
;   On invalid tag:
;     A             = 1
;     Z flag        = 0 (BNE taken)
;     gcmsiv_tag_valid = 0
;     gcmsiv_dec_buf   = zeroed (64 bytes)
;     gcmsiv_tag       = restored to received tag
;   memory (always): polyval_*, aes_state, gcmsiv_counter/keystream/idx
;                    all clobbered; aes_expanded_key restored to master
;                    schedule; aes_current_key preserved.
;
; Clobbers: A, X, Y, same footprint as gcmsiv_encrypt
; Cycles:   unmeasured
; IRQ-safe: no
; Reentrant: no
;
; Recommended usage:
;   jsr gcmsiv_decrypt
;   beq tag_ok         ; valid -> consume gcmsiv_dec_buf
;   ; ...tag failure path...
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
        ; Return convention: valid tag -> A=0, Z=1 (BEQ taken)
        lda #0
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
        ; Return convention: invalid tag -> A=1, Z=0 (BNE taken)
        lda #1
        rts

; =============================================================================
; gcmsiv_ctr_decrypt - AES-CTR keystream from gcmsiv_ct_buf -> gcmsiv_dec_buf
;
; Mirror image of gcmsiv_ctr_encrypt: reads ciphertext from gcmsiv_ct_buf
; and writes recovered plaintext to gcmsiv_dec_buf. The counter block is
; initialised from gcmsiv_tag with the MSB of the last byte forced to 1.
;
; Entry:
;   A, X, Y      n/a
;   memory       gcmsiv_tag         = 16-byte tag (used as IV seed)
;                gcmsiv_ct_buf      = ciphertext
;                gcmsiv_pt_len      = length in bytes (0..64)
;                gcmsiv_exp_enc_key = derived enc-key schedule
;                aes_expanded_key   = master-key schedule to preserve
;
; Exit:
;   A, X, Y      undefined
;   memory       gcmsiv_dec_buf     = plaintext (pt_len bytes)
;                gcmsiv_counter     = clobbered
;                gcmsiv_keystream   = clobbered
;                gcmsiv_ct_idx      = clobbered
;                gcmsiv_ks_idx      = clobbered
;                aes_state          = clobbered
;                aes_expanded_key   = restored master-key schedule
;                gcmsiv_tag         = preserved
;                gcmsiv_ct_buf      = preserved
;
; Clobbers: A, X, Y, gcmsiv_counter, gcmsiv_keystream, gcmsiv_ct_idx,
;           gcmsiv_ks_idx, gcmsiv_dec_buf, aes_state, aes_mc_*
; Cycles:   unmeasured
; IRQ-safe: no
; Reentrant: no
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
