; =============================================================================
; abi_v1.inc - c64-polyval v0.1.x stable public ABI
;
; This header declares the complete set of symbols promised stable for all
; v0.1.x releases of the c64-polyval library. Consumers should .include this
; file and rely ONLY on the symbols declared here.
;
; Anything NOT in this file is either:
;   - A test probe (see test_probes.inc) - allowed for the in-repo test suite
;     only; NOT guaranteed to exist in future releases.
;   - A cross-.o linker artifact - present in the archive but undocumented
;     and subject to removal without notice.
;
; Use this file like:
;
;     .include "abi_v1.inc"
;     .include "constants_lib.inc"     ; for ZP equates + profile selector
;
; then `.import polyval_init` etc., and link against polyval_long.lib or
; polyval_short.lib.
;
; Zero-page symbols (polyval_acc, pv_mul_input) are plain equates coming
; from constants_lib.inc; they do NOT need .importzp because they are not
; linker-level symbols in this library. Referencing them by name after
; .include'ing constants_lib.inc is sufficient.
; =============================================================================

.ifndef POLYVAL_ABI_V1_INC_
POLYVAL_ABI_V1_INC_ = 1

; --- POLYVAL primitive (RFC 8452 section 3) --------------------------------
.global polyval_init
.global polyval_precompute_table
.global polyval_update
.global polyval_multiply

; --- POLYVAL stable data buffers -------------------------------------------
.global polyval_h               ; 16 B input: hash key H
.global polyval_temp            ; 16 B input block for polyval_update

; --- AES-256 primitive -----------------------------------------------------
.global aes_key_expansion
.global aes_encrypt_block
.global aes_decrypt_block

; --- AES-256 stable data buffers -------------------------------------------
.global aes_current_key         ;  32 B input: AES-256 master key
.global aes_expanded_key        ; 240 B output of aes_key_expansion
.global aes_state               ;  16 B in/out AES block

; --- AES-256-GCM-SIV AEAD --------------------------------------------------
.global gcmsiv_encrypt
.global gcmsiv_decrypt
.global gcmsiv_derive_keys

; --- GCM-SIV stable data buffers -------------------------------------------
.global gcmsiv_nonce            ; 12 B input: 96-bit nonce
.global gcmsiv_pt_buf           ; 64 B input (encrypt) / scratch (decrypt)
.global gcmsiv_pt_len           ;  1 B length in bytes (0..64) of pt/ct
.global gcmsiv_ct_buf           ; 64 B output (encrypt) / input (decrypt)
.global gcmsiv_dec_buf          ; 64 B output of gcmsiv_decrypt
.global gcmsiv_tag              ; 16 B in/out 128-bit auth tag
.global gcmsiv_auth_key         ; 16 B derived POLYVAL auth key
.global gcmsiv_enc_key          ; 32 B derived AES-256 enc key
.global gcmsiv_tag_valid        ;  1 B legacy result flag (1=valid, 0=invalid)

.endif ; POLYVAL_ABI_V1_INC_
