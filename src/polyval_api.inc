; =============================================================================
; lib/polyval_api.inc - Public API header for the c64-polyval library (ca65)
;
; This file is the single-source description of the stable public API and
; calling conventions for the POLYVAL / AES-256 / AES-256-GCM-SIV library
; under ca65/src/lib/. It emits no executable code and no memory: only the
; profile-selector equates.
;
; -----------------------------------------------------------------------------
; Stable public API surface
; -----------------------------------------------------------------------------
;   --- POLYVAL primitive (RFC 8452 section 3) ---
;   polyval_init              Clear the 128-bit accumulator.
;   polyval_precompute_table  Build the H-table(s) from polyval_h.
;   polyval_update            Absorb one 16-byte block from polyval_temp into
;                             the accumulator (acc = (acc XOR block) * H).
;   polyval_multiply          Low-level GF(2^128) multiply: acc = acc * H.
;   polyval_double            Low-level GF(2^128) doubling (acc *= x).
;   polyval_shift_left_4      Low-level inlined 4-bit left shift with
;                             reduction (SHORT profile hot path).
;   polyval_xor_table_entry   XOR the 4-bit H-table entry selected by
;                             pv_mul_nibble into the accumulator.
;
;   --- AES-256 primitive ---
;   aes_key_expansion         Expand aes_current_key into aes_expanded_key.
;   aes_encrypt_block         Encrypt aes_state in place using aes_expanded_key.
;   aes_decrypt_block         Decrypt aes_state in place using aes_expanded_key.
;
;   --- AES-256-GCM-SIV AEAD ---
;   gcmsiv_encrypt            Full encrypt+auth over the configured buffers.
;   gcmsiv_decrypt            Full decrypt+verify. Z=1/A=0 => valid,
;                             Z=0/A=1 => invalid (dec_buf zeroed).
;   gcmsiv_derive_keys        RFC 8452 key derivation (master key + nonce).
;   gcmsiv_compute_tag_base   POLYVAL over (AAD || PT || lengths) -> tag_acc.
;   gcmsiv_finalize_tag       Final AES-CTR to produce gcmsiv_tag.
;   gcmsiv_ctr_encrypt        AES-CTR keystream over pt_buf -> ct_buf.
;   gcmsiv_ctr_decrypt        AES-CTR keystream over ct_buf -> dec_buf.
;
; -----------------------------------------------------------------------------
; Stable public memory (library state buffers)
; -----------------------------------------------------------------------------
;   polyval_h           16 B   Input: hash key H
;   polyval_temp        16 B   Input: block for polyval_update
;   polyval_acc         16 B   ZP: running 128-bit accumulator ($10-$1F)
;   polyval_htable     256 B   4-bit Shoup table (both profiles)
;   polyval_htable8    4 KB    8-bit Shoup slices (LONG only)
;   polyval_reduce8    4 KB    8-bit reduction slices (LONG only)
;
;   aes_current_key     32 B   Input: AES-256 master key
;   aes_expanded_key   240 B   Output of aes_key_expansion
;   aes_state           16 B   In/out: AES block being processed
;
;   gcmsiv_nonce        12 B   Input: 96-bit nonce
;   gcmsiv_pt_buf       64 B   Input (encrypt) / scratch (decrypt)
;   gcmsiv_pt_len        1 B   Length in bytes (0..64) of pt/ct
;   gcmsiv_ct_buf       64 B   Output (encrypt) / input (decrypt)
;   gcmsiv_dec_buf      64 B   Output of gcmsiv_decrypt
;   gcmsiv_tag          16 B   In/out: 128-bit auth tag
;   gcmsiv_auth_key     16 B   Derived POLYVAL auth key
;   gcmsiv_enc_key      32 B   Derived AES-256 enc key
;   gcmsiv_tag_valid     1 B   Legacy tag result: 1 = valid, 0 = invalid
;
; -----------------------------------------------------------------------------
; Global calling-convention notes
; -----------------------------------------------------------------------------
; - All public routines are entered with JSR and return with RTS.
; - NONE of the routines are IRQ-safe; they clobber shared ZP scratch.
; - NONE of the routines are reentrant.
; - Flag state (C, V, N) on return is undefined unless explicitly noted.
;   Exception: gcmsiv_decrypt uses Z + A to report tag validity.
; - Registers A, X, Y are NOT preserved unless a routine's header says so.
; =============================================================================

.ifndef POLYVAL_API_INC_
POLYVAL_API_INC_ = 1

; --- Profile selector equates ----------------------------------------------
; Safe to .include multiple times. Same sentinels as constants_lib.inc; a
; host can pre-define POLYVAL_PROFILE to one of these before .include'ing
; constants_lib.inc to pick a profile.
.ifndef POLYVAL_PROFILE_SHORT
    POLYVAL_PROFILE_SHORT = 1
.endif
.ifndef POLYVAL_PROFILE_LONG
    POLYVAL_PROFILE_LONG  = 2
.endif

.endif ; POLYVAL_API_INC_
