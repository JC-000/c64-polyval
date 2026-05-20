; =============================================================================
; aes_decrypt.s - AES-256 decryption: block decrypt, inverse ops (ca65 port)
;
; ca65 port of src/lib/aes_decrypt.asm. Mechanical; behavior-exact.
; Related: aes_encrypt.s, tables.s (inverse S-box)
; =============================================================================

.include "constants_lib.inc"

; Note: ZP symbols (zp_round, zp_col, zp_temp, zp_tmp1) are numeric
; equates from constants_lib.inc — no .importzp needed.

; State + tables
.import aes_state
.import aes_expanded_key
.import aes_inv_sbox

; MixColumns scratch
.import aes_mc_a0, aes_mc_a1, aes_mc_a2, aes_mc_a3
.import aes_mc_b0, aes_mc_b1, aes_mc_b2, aes_mc_b3

; Siblings (from aes_encrypt.s)
.import aes_add_round_key
.import gf_mul2

.export aes_decrypt_block
.export aes_inv_sub_bytes
.export aes_inv_shift_rows
.export aes_inv_mix_columns
.export gf_mul_09
.export gf_mul_0b
.export gf_mul_0d
.export gf_mul_0e

.segment "LIB_POLYVAL_AES_CODE"

; =============================================================================
; aes_decrypt_block - AES-256 decrypt one 16-byte block in place
;
; Runs the full 14-round inverse AES-256 cipher on aes_state using the
; round keys in aes_expanded_key. FIPS-197 order: AddRoundKey at round
; 14, then 13 x {InvShiftRows, InvSubBytes, AddRoundKey, InvMixColumns},
; then final {InvShiftRows, InvSubBytes, AddRoundKey}.
;
; Entry:
;   A, X, Y      n/a
;   memory       aes_state        = 16-byte ciphertext block
;                aes_expanded_key = 240-byte key schedule from
;                                   aes_key_expansion
;
; Exit:
;   A, X, Y      undefined
;   memory       aes_state        = plaintext block (16 bytes)
;                aes_mc_a0..b3    = clobbered (InvMixColumns scratch)
;
; Clobbers: A, X, Y, aes_state, aes_mc_a0..b3, zp_round
; Cycles:   unmeasured
; IRQ-safe: no
; Reentrant: no
; Note: GCM-SIV never invokes aes_decrypt_block; decryption is done via
;       AES-CTR on encrypt_block. This routine is exposed for direct
;       AES users.
; =============================================================================
aes_decrypt_block:
        ; round 14: initial add round key
        lda #14
        sta zp_round
        jsr aes_add_round_key

        ; rounds 13 down to 1
        lda #13
        sta zp_round

@round_loop:
        jsr aes_inv_shift_rows
        jsr aes_inv_sub_bytes
        jsr aes_add_round_key
        jsr aes_inv_mix_columns

        dec zp_round
        lda zp_round
        bne @round_loop

        ; round 0: final round (no inv mix columns)
        jsr aes_inv_shift_rows
        jsr aes_inv_sub_bytes
        ; zp_round is already 0
        jsr aes_add_round_key

        rts

; =============================================================================
; aes_inv_sub_bytes - inverse substitute using inverse s-box
; =============================================================================
aes_inv_sub_bytes:
        ldx #0
@loop:
        ldy aes_state,x
        lda aes_inv_sbox,y
        sta aes_state,x
        inx
        cpx #16
        bne @loop
        rts

; =============================================================================
; aes_inv_shift_rows - inverse shift rows
; =============================================================================
aes_inv_shift_rows:
        ; row 1: rotate right by 1
        lda aes_state+13
        pha
        lda aes_state+9
        sta aes_state+13
        lda aes_state+5
        sta aes_state+9
        lda aes_state+1
        sta aes_state+5
        pla
        sta aes_state+1

        ; row 2: rotate right by 2 (same as left by 2)
        lda aes_state+2
        pha
        lda aes_state+10
        sta aes_state+2
        pla
        sta aes_state+10
        lda aes_state+6
        pha
        lda aes_state+14
        sta aes_state+6
        pla
        sta aes_state+14

        ; row 3: rotate right by 3 (same as left by 1)
        lda aes_state+3
        pha
        lda aes_state+7
        sta aes_state+3
        lda aes_state+11
        sta aes_state+7
        lda aes_state+15
        sta aes_state+11
        pla
        sta aes_state+15

        rts

; =============================================================================
; aes_inv_mix_columns - inverse mix columns transformation
; =============================================================================
aes_inv_mix_columns:
        lda #0
        sta zp_col

@col_loop:
        lda zp_col
        asl
        asl
        sta zp_tmp1             ; save column offset
        tax

        ; load column bytes to temp storage
        lda aes_state,x
        sta aes_mc_a0
        lda aes_state+1,x
        sta aes_mc_a1
        lda aes_state+2,x
        sta aes_mc_a2
        lda aes_state+3,x
        sta aes_mc_a3

        ; b0 = 0e*a0 ^ 0b*a1 ^ 0d*a2 ^ 09*a3
        lda aes_mc_a0
        jsr gf_mul_0e
        sta aes_mc_b0
        lda aes_mc_a1
        jsr gf_mul_0b
        eor aes_mc_b0
        sta aes_mc_b0
        lda aes_mc_a2
        jsr gf_mul_0d
        eor aes_mc_b0
        sta aes_mc_b0
        lda aes_mc_a3
        jsr gf_mul_09
        eor aes_mc_b0
        sta aes_mc_b0

        ; b1 = 09*a0 ^ 0e*a1 ^ 0b*a2 ^ 0d*a3
        lda aes_mc_a0
        jsr gf_mul_09
        sta aes_mc_b1
        lda aes_mc_a1
        jsr gf_mul_0e
        eor aes_mc_b1
        sta aes_mc_b1
        lda aes_mc_a2
        jsr gf_mul_0b
        eor aes_mc_b1
        sta aes_mc_b1
        lda aes_mc_a3
        jsr gf_mul_0d
        eor aes_mc_b1
        sta aes_mc_b1

        ; b2 = 0d*a0 ^ 09*a1 ^ 0e*a2 ^ 0b*a3
        lda aes_mc_a0
        jsr gf_mul_0d
        sta aes_mc_b2
        lda aes_mc_a1
        jsr gf_mul_09
        eor aes_mc_b2
        sta aes_mc_b2
        lda aes_mc_a2
        jsr gf_mul_0e
        eor aes_mc_b2
        sta aes_mc_b2
        lda aes_mc_a3
        jsr gf_mul_0b
        eor aes_mc_b2
        sta aes_mc_b2

        ; b3 = 0b*a0 ^ 0d*a1 ^ 09*a2 ^ 0e*a3
        lda aes_mc_a0
        jsr gf_mul_0b
        sta aes_mc_b3
        lda aes_mc_a1
        jsr gf_mul_0d
        eor aes_mc_b3
        sta aes_mc_b3
        lda aes_mc_a2
        jsr gf_mul_09
        eor aes_mc_b3
        sta aes_mc_b3
        lda aes_mc_a3
        jsr gf_mul_0e
        eor aes_mc_b3
        sta aes_mc_b3

        ; store results back to state
        ldx zp_tmp1             ; restore column offset
        lda aes_mc_b0
        sta aes_state,x
        lda aes_mc_b1
        sta aes_state+1,x
        lda aes_mc_b2
        sta aes_state+2,x
        lda aes_mc_b3
        sta aes_state+3,x

        inc zp_col
        lda zp_col
        cmp #4
        beq @col_done
        jmp @col_loop
@col_done:
        rts

; =============================================================================
; gf_mul_09 - multiply by 9 in gf(2^8): 9 = 8 + 1
; =============================================================================
gf_mul_09:
        sta zp_temp
        jsr gf_mul2             ; 2
        jsr gf_mul2             ; 4
        jsr gf_mul2             ; 8
        eor zp_temp             ; 8 + 1 = 9
        rts

; =============================================================================
; gf_mul_0b - multiply by 11 in gf(2^8): 11 = 8 + 2 + 1
; =============================================================================
gf_mul_0b:
        sta zp_temp
        jsr gf_mul2             ; 2
        pha                     ; save 2
        jsr gf_mul2             ; 4
        jsr gf_mul2             ; 8
        eor zp_temp             ; 8 + 1 = 9
        sta zp_temp
        pla                     ; get 2
        eor zp_temp             ; 9 + 2 = 11
        rts

; =============================================================================
; gf_mul_0d - multiply by 13 in gf(2^8): 13 = 8 + 4 + 1
; =============================================================================
gf_mul_0d:
        sta zp_temp
        jsr gf_mul2             ; 2
        jsr gf_mul2             ; 4
        pha                     ; save 4
        jsr gf_mul2             ; 8
        eor zp_temp             ; 8 + 1 = 9
        sta zp_temp
        pla                     ; get 4
        eor zp_temp             ; 9 + 4 = 13
        rts

; =============================================================================
; gf_mul_0e - multiply by 14 in gf(2^8): 14 = 8 + 4 + 2
; =============================================================================
gf_mul_0e:
        jsr gf_mul2             ; 2
        pha                     ; save 2
        jsr gf_mul2             ; 4
        pha                     ; save 4
        jsr gf_mul2             ; 8
        sta zp_temp
        pla                     ; get 4
        eor zp_temp             ; 8 + 4 = 12
        sta zp_temp
        pla                     ; get 2
        eor zp_temp             ; 12 + 2 = 14
        rts
