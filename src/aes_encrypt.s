; =============================================================================
; aes_encrypt.s - AES-256 encryption: key expansion, block encrypt (ca65 port)
;
; ca65 port of src/lib/aes_encrypt.asm. Mechanical; behavior-exact.
; Related: aes_decrypt.s, tables.s (S-box, round constants)
; =============================================================================
;
; NOTE: clear_buffers (app-level helper that wiped the demo input/encrypt
; buffers) used to live here. It referenced input_buffer/encrypt_buffer/
; input_length/encrypt_length — all demo-app symbols — so it has been moved
; to the demo app (src/boot.asm).

.include "constants_lib.inc"

; Note: ZP symbols (zp_round, zp_col, zp_temp, zp_count, zp_tmp1..zp_tmp4)
; are numeric equates from constants_lib.inc — no .importzp needed.

; State + tables
.import aes_state
.import aes_expanded_key
.import aes_current_key
.import aes_sbox
.import aes_rcon

.export aes_encrypt_block
.export aes_key_expansion
.export aes_sub_bytes
.export aes_shift_rows
.export aes_mix_columns
.export aes_add_round_key
.export gf_mul2
.export gf_mul3

.segment "LIB_POLYVAL_AES_CODE"

; =============================================================================
; aes_encrypt_block - AES-256 encrypt one 16-byte block in place
;
; Runs the full 14-round AES-256 encryption on aes_state using the round
; keys in aes_expanded_key. Standard FIPS-197 rounds: initial
; AddRoundKey, then 13 x {SubBytes, ShiftRows, MixColumns, AddRoundKey},
; then final {SubBytes, ShiftRows, AddRoundKey}.
;
; Entry:
;   A, X, Y      n/a
;   memory       aes_state        = 16-byte plaintext block
;                aes_expanded_key = 240-byte key schedule from
;                                   aes_key_expansion (or an equivalent
;                                   15-round schedule installed by the
;                                   caller, as GCM-SIV does)
;
; Exit:
;   A, X, Y      undefined
;   memory       aes_state        = ciphertext block (16 bytes)
;                aes_mc_a0..b3    = clobbered (MixColumns scratch)
;
; Clobbers: A, X, Y, aes_state, aes_mc_a0..b3, zp_round
; Cycles:   unmeasured
; IRQ-safe: no
; Reentrant: no
; =============================================================================
aes_encrypt_block:
        ; initial round key addition
        lda #0
        sta zp_round
        jsr aes_add_round_key

        ; main rounds (1 to 13)
        lda #1
        sta zp_round
@round_loop:
        jsr aes_sub_bytes
        jsr aes_shift_rows
        jsr aes_mix_columns
        jsr aes_add_round_key

        inc zp_round
        lda zp_round
        cmp #14
        bcc @round_loop

        ; final round (no mix columns)
        jsr aes_sub_bytes
        jsr aes_shift_rows
        jsr aes_add_round_key

        rts

; =============================================================================
; aes_sub_bytes - substitute each byte using s-box
; =============================================================================
aes_sub_bytes:
        ldx #0
@loop:
        ldy aes_state,x
        lda aes_sbox,y
        sta aes_state,x
        inx
        cpx #16
        bne @loop
        rts

; =============================================================================
; aes_shift_rows - shift rows of state matrix
; =============================================================================
aes_shift_rows:
        ; row 1: rotate left by 1
        lda aes_state+1
        pha
        lda aes_state+5
        sta aes_state+1
        lda aes_state+9
        sta aes_state+5
        lda aes_state+13
        sta aes_state+9
        pla
        sta aes_state+13

        ; row 2: rotate left by 2
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

        ; row 3: rotate left by 3 (same as right by 1)
        lda aes_state+15
        pha
        lda aes_state+11
        sta aes_state+15
        lda aes_state+7
        sta aes_state+11
        lda aes_state+3
        sta aes_state+7
        pla
        sta aes_state+3

        rts

; =============================================================================
; aes_mix_columns - mix columns transformation
; =============================================================================
aes_mix_columns:
        lda #0
        sta zp_col

@col_loop:
        ; get column offset (col * 4)
        lda zp_col
        asl
        asl
        tax

        ; load column bytes
        lda aes_state,x
        sta zp_tmp1             ; a0
        lda aes_state+1,x
        sta zp_tmp2             ; a1
        lda aes_state+2,x
        sta zp_tmp3             ; a2
        lda aes_state+3,x
        sta zp_tmp4             ; a3

        ; b0 = 2*a0 ^ 3*a1 ^ a2 ^ a3
        lda zp_tmp1
        jsr gf_mul2
        sta aes_state,x
        lda zp_tmp2
        jsr gf_mul3
        eor aes_state,x
        eor zp_tmp3
        eor zp_tmp4
        sta aes_state,x

        ; b1 = a0 ^ 2*a1 ^ 3*a2 ^ a3
        lda zp_tmp2
        jsr gf_mul2
        sta aes_state+1,x
        lda zp_tmp3
        jsr gf_mul3
        eor aes_state+1,x
        eor zp_tmp1
        eor zp_tmp4
        sta aes_state+1,x

        ; b2 = a0 ^ a1 ^ 2*a2 ^ 3*a3
        lda zp_tmp3
        jsr gf_mul2
        sta aes_state+2,x
        lda zp_tmp4
        jsr gf_mul3
        eor aes_state+2,x
        eor zp_tmp1
        eor zp_tmp2
        sta aes_state+2,x

        ; b3 = 3*a0 ^ a1 ^ a2 ^ 2*a3
        lda zp_tmp4
        jsr gf_mul2
        sta aes_state+3,x
        lda zp_tmp1
        jsr gf_mul3
        eor aes_state+3,x
        eor zp_tmp2
        eor zp_tmp3
        sta aes_state+3,x

        inc zp_col
        lda zp_col
        cmp #4
        bne @col_loop
        rts

; =============================================================================
; gf_mul2 - multiply by 2 in gf(2^8)
; =============================================================================
gf_mul2:
        asl
        bcc @no_reduce
        eor #$1b                ; reduce by aes polynomial
@no_reduce:
        rts

; =============================================================================
; gf_mul3 - multiply by 3 in gf(2^8)
; =============================================================================
gf_mul3:
        sta zp_temp
        jsr gf_mul2
        eor zp_temp             ; 3*x = 2*x ^ x
        rts

; =============================================================================
; aes_add_round_key - xor state with round key
; =============================================================================
aes_add_round_key:
        lda zp_round
        asl
        asl
        asl
        asl                     ; * 16
        tay                     ; y = offset into expanded key

        ldx #0
@loop:
        lda aes_state,x
        eor aes_expanded_key,y
        sta aes_state,x
        iny
        inx
        cpx #16
        bne @loop
        rts

; =============================================================================
; aes_key_expansion - expand a 256-bit AES key into the 240-byte schedule
;
; FIPS-197 AES-256 key schedule: 14+1 round keys of 16 bytes each,
; derived from aes_current_key using SubWord, RotWord, and the Rcon
; table (in lib/tables.s).
;
; Entry:
;   A, X, Y      n/a
;   memory       aes_current_key  = 32-byte AES-256 key
;
; Exit:
;   A, X, Y      undefined
;   memory       aes_expanded_key = 240 bytes of round keys
;                aes_current_key  = preserved
;
; Clobbers: A, X, Y, aes_expanded_key, zp_count, zp_tmp1..zp_tmp4
; Cycles:   unmeasured
; IRQ-safe: no
; Reentrant: no
; =============================================================================
aes_key_expansion:
        ; copy original key to first 32 bytes of expanded key
        ldx #0
@copy_key:
        lda aes_current_key,x
        sta aes_expanded_key,x
        inx
        cpx #32
        bne @copy_key

        ; generate remaining round keys
        lda #8                  ; start at word 8 (byte 32)
        sta zp_count            ; word counter

@expand_loop:
        lda zp_count
        asl
        asl                     ; * 4 = byte offset
        tax

        ; get w[i-1] (previous word)
        lda aes_expanded_key-4,x
        sta zp_tmp1
        lda aes_expanded_key-3,x
        sta zp_tmp2
        lda aes_expanded_key-2,x
        sta zp_tmp3
        lda aes_expanded_key-1,x
        sta zp_tmp4

        ; check if i mod 8 == 0
        lda zp_count
        and #$07
        bne @check_mod4

        ; rotword + subword + rcon
        lda zp_tmp1
        pha
        lda zp_tmp2
        sta zp_tmp1
        lda zp_tmp3
        sta zp_tmp2
        lda zp_tmp4
        sta zp_tmp3
        pla
        sta zp_tmp4

        ; subword
        ldy zp_tmp1
        lda aes_sbox,y
        sta zp_tmp1
        ldy zp_tmp2
        lda aes_sbox,y
        sta zp_tmp2
        ldy zp_tmp3
        lda aes_sbox,y
        sta zp_tmp3
        ldy zp_tmp4
        lda aes_sbox,y
        sta zp_tmp4

        ; xor with rcon
        lda zp_count
        lsr
        lsr
        lsr                     ; i / 8
        tay
        dey                     ; rcon index (0-based)
        lda aes_rcon,y
        eor zp_tmp1
        sta zp_tmp1
        jmp @do_xor

@check_mod4:
        cmp #4
        bne @do_xor

        ; just subword
        ldy zp_tmp1
        lda aes_sbox,y
        sta zp_tmp1
        ldy zp_tmp2
        lda aes_sbox,y
        sta zp_tmp2
        ldy zp_tmp3
        lda aes_sbox,y
        sta zp_tmp3
        ldy zp_tmp4
        lda aes_sbox,y
        sta zp_tmp4

@do_xor:
        ; w[i] = w[i-8] xor temp
        lda zp_count
        asl
        asl
        tax

        lda aes_expanded_key-32,x   ; w[i-8]
        eor zp_tmp1
        sta aes_expanded_key,x

        lda aes_expanded_key-31,x
        eor zp_tmp2
        sta aes_expanded_key+1,x

        lda aes_expanded_key-30,x
        eor zp_tmp3
        sta aes_expanded_key+2,x

        lda aes_expanded_key-29,x
        eor zp_tmp4
        sta aes_expanded_key+3,x

        ; next word
        inc zp_count
        lda zp_count
        cmp #60                 ; 60 words = 240 bytes
        bcs @expand_done
        jmp @expand_loop

@expand_done:
        rts
