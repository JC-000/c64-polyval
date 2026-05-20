; =============================================================================
; lib_main.s - Library-only verification stub (ca65 equivalent of ACME's
;              src/lib/lib_main.asm).
;
; This is NOT the demo app entry point (that's src/main.s). This file gets
; linked against ONLY the library .o files using lib_only.cfg. Its sole job
; is to reference every public library symbol so ld65 is forced to pull in
; every lib .o, and if any lib file accidentally depends on an app-layer
; symbol (chrout, print_string, strings.s labels, ...) the link fails with
; "unresolved external" -- that failure IS the test.
;
; The produced build/lib_main.prg has a $3FFE load header, lands code at
; $4000, and runs nothing useful. It is not intended to execute on a C64.
; =============================================================================

.include "constants_lib.inc"
.include "polyval_api.inc"

; ZP addresses (polyval_acc, pv_mul_input, pv_mul_nibble) come from
; constants_lib.inc as pure equates, so no .importzp needed here -- ca65
; already emits 2-byte ZP addressing for the lda/sta below.

; --- POLYVAL primitive ---
.import polyval_init
.import polyval_double
.import polyval_right_shift_1
.import polyval_shift_left_4
.import polyval_precompute_table
.import polyval_multiply
.import polyval_xor_table_entry
.import polyval_update
.import polyval_finalize

; --- Public POLYVAL buffers ---
.import polyval_h
.import polyval_temp
.import polyval_htable

; --- AES-256 primitive ---
.import aes_key_expansion
.import aes_encrypt_block
.import aes_decrypt_block

; --- Public AES buffers ---
.import aes_current_key
.import aes_state
.import aes_expanded_key

; --- AES-256-GCM-SIV AEAD ---
.import gcmsiv_encrypt
.import gcmsiv_decrypt
.import gcmsiv_derive_keys
.import gcmsiv_derive_ctr
.import gcmsiv_compute_tag_base
.import gcmsiv_finalize_tag
.import gcmsiv_ctr_encrypt
.import gcmsiv_ctr_decrypt

; --- Public GCM-SIV buffers ---
.import gcmsiv_nonce
.import gcmsiv_pt_buf
.import gcmsiv_pt_len
.import gcmsiv_ct_buf
.import gcmsiv_dec_buf
.import gcmsiv_tag
.import gcmsiv_auth_key
.import gcmsiv_enc_key
.import gcmsiv_tag_valid

.export lib_main_entry

; ---------------------------------------------------------------------------
; LOADADDR: emit a $3FFE header so the output file is a valid .prg even
; though it is never expected to run.
; ---------------------------------------------------------------------------
.segment "LOADADDR"
        .word   $4000

; ---------------------------------------------------------------------------
; CODE: touch every public symbol so the linker pulls in every lib .o and
; reports unresolved externals for any app-layer dependency. This sequence
; is not meant to execute correctly on a C64; it exists purely to create
; link-time references. JSR emits an absolute reference, and LDA abs / LDA
; zp emits address references to each public buffer / ZP symbol.
; ---------------------------------------------------------------------------
.segment "LIB_POLYVAL_VERIFY_CODE"

lib_main_entry:
        ; POLYVAL routines
        jsr     polyval_init
        jsr     polyval_double
        jsr     polyval_right_shift_1
        jsr     polyval_shift_left_4
        jsr     polyval_precompute_table
        jsr     polyval_multiply
        jsr     polyval_xor_table_entry
        jsr     polyval_update
        jsr     polyval_finalize

        ; POLYVAL buffers - one byte load each to create an abs reference
        lda     polyval_h
        lda     polyval_temp
        lda     polyval_htable
        lda     polyval_acc             ; ZP
        lda     pv_mul_input            ; ZP
        lda     pv_mul_nibble           ; ZP

        ; AES routines
        jsr     aes_key_expansion
        jsr     aes_encrypt_block
        jsr     aes_decrypt_block

        ; AES buffers
        lda     aes_current_key
        lda     aes_state
        lda     aes_expanded_key

        ; GCM-SIV routines
        jsr     gcmsiv_encrypt
        jsr     gcmsiv_decrypt
        jsr     gcmsiv_derive_keys
        jsr     gcmsiv_derive_ctr
        jsr     gcmsiv_compute_tag_base
        jsr     gcmsiv_finalize_tag
        jsr     gcmsiv_ctr_encrypt
        jsr     gcmsiv_ctr_decrypt

        ; GCM-SIV buffers
        lda     gcmsiv_nonce
        lda     gcmsiv_pt_buf
        lda     gcmsiv_pt_len
        lda     gcmsiv_ct_buf
        lda     gcmsiv_dec_buf
        lda     gcmsiv_tag
        lda     gcmsiv_auth_key
        lda     gcmsiv_enc_key
        lda     gcmsiv_tag_valid

@spin:
        jmp     @spin
