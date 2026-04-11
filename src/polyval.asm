; =============================================================================
; polyval.asm - POLYVAL GF(2^128) universal hash (RFC 8452)
; Algorithm: POLYVAL(H, X_1..X_s) where S_0=0, S_i = dot(S_{i-1} XOR X_i, H)
; Polynomial: x^128 + x^127 + x^126 + x^121 + 1
;
; The POLYVAL dot product dot(a, b) = a * b * x^{-128} mod p, which is
; equivalent to GHASH-style multiplication in the POLYVAL field.
;
; Strategy: 4-bit nibble table lookup with LEFT-shift processing.
; Table is precomputed from H' = H * x^{-128} using left-shift doubling.
;
; Left-shift reduction (x^128 mod p): byte[0] ^= $01, byte[15] ^= $C2
; Right-shift reduction (x^{-1} mod p): byte[15] ^= $E1
; =============================================================================

; -----------------------------------------------------------------------------
; Unroll macros for hot 16-byte ZP loops (polyval_acc at $10-$1F)
; -----------------------------------------------------------------------------

; XOR htable[nibble*16 .. nibble*16+15] into polyval_acc.
; Entry: Y = nibble*16. Uses htable+k,y so Y stays constant (saves 16 INYs).
!macro pv_unroll_xor_htable_16 {
        lda polyval_acc+0  : eor polyval_htable+0,y  : sta polyval_acc+0
        lda polyval_acc+1  : eor polyval_htable+1,y  : sta polyval_acc+1
        lda polyval_acc+2  : eor polyval_htable+2,y  : sta polyval_acc+2
        lda polyval_acc+3  : eor polyval_htable+3,y  : sta polyval_acc+3
        lda polyval_acc+4  : eor polyval_htable+4,y  : sta polyval_acc+4
        lda polyval_acc+5  : eor polyval_htable+5,y  : sta polyval_acc+5
        lda polyval_acc+6  : eor polyval_htable+6,y  : sta polyval_acc+6
        lda polyval_acc+7  : eor polyval_htable+7,y  : sta polyval_acc+7
        lda polyval_acc+8  : eor polyval_htable+8,y  : sta polyval_acc+8
        lda polyval_acc+9  : eor polyval_htable+9,y  : sta polyval_acc+9
        lda polyval_acc+10 : eor polyval_htable+10,y : sta polyval_acc+10
        lda polyval_acc+11 : eor polyval_htable+11,y : sta polyval_acc+11
        lda polyval_acc+12 : eor polyval_htable+12,y : sta polyval_acc+12
        lda polyval_acc+13 : eor polyval_htable+13,y : sta polyval_acc+13
        lda polyval_acc+14 : eor polyval_htable+14,y : sta polyval_acc+14
        lda polyval_acc+15 : eor polyval_htable+15,y : sta polyval_acc+15
}

; Copy polyval_acc -> pv_mul_input (absolute dest).
!macro pv_unroll_save_acc_16 {
        lda polyval_acc+0  : sta pv_mul_input+0
        lda polyval_acc+1  : sta pv_mul_input+1
        lda polyval_acc+2  : sta pv_mul_input+2
        lda polyval_acc+3  : sta pv_mul_input+3
        lda polyval_acc+4  : sta pv_mul_input+4
        lda polyval_acc+5  : sta pv_mul_input+5
        lda polyval_acc+6  : sta pv_mul_input+6
        lda polyval_acc+7  : sta pv_mul_input+7
        lda polyval_acc+8  : sta pv_mul_input+8
        lda polyval_acc+9  : sta pv_mul_input+9
        lda polyval_acc+10 : sta pv_mul_input+10
        lda polyval_acc+11 : sta pv_mul_input+11
        lda polyval_acc+12 : sta pv_mul_input+12
        lda polyval_acc+13 : sta pv_mul_input+13
        lda polyval_acc+14 : sta pv_mul_input+14
        lda polyval_acc+15 : sta pv_mul_input+15
}

; Zero polyval_acc. A must already hold 0.
!macro pv_unroll_clear_acc_16 {
        sta polyval_acc+0
        sta polyval_acc+1
        sta polyval_acc+2
        sta polyval_acc+3
        sta polyval_acc+4
        sta polyval_acc+5
        sta polyval_acc+6
        sta polyval_acc+7
        sta polyval_acc+8
        sta polyval_acc+9
        sta polyval_acc+10
        sta polyval_acc+11
        sta polyval_acc+12
        sta polyval_acc+13
        sta polyval_acc+14
        sta polyval_acc+15
}

; Inlined body of polyval_shift_left_4: 4 sequential left-doublings with
; sparse-polynomial reduction. Uses ACME anonymous forward labels (`+`)
; which are positional and therefore reusable across macro expansions.
!macro pv_inline_shift_left_4 {
        ; --- doubling 1 ---
        clc
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc +
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
+
        ; --- doubling 2 ---
        clc
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc +
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
+
        ; --- doubling 3 ---
        clc
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc +
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
+
        ; --- doubling 4 ---
        clc
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc +
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
+
}

; Process one nibble: shift acc left by 4, then XOR htable[nibble] into acc.
; Input: A = nibble value (0..15). A is clobbered.
; Preserves the zero-htable[0] early-skip: if nibble==0, the XOR is bypassed.
!macro pv_process_nibble {
        ; shift_left_4 clobbers A (reduction stores $c2-xored byte), so stash
        ; the nibble in Y first, then rehydrate after the shift.
        tax                     ; X = nibble (preserved across shift)
        +pv_inline_shift_left_4
        cpx #0
        beq +
        txa
        asl
        asl
        asl
        asl                     ; A = nibble * 16
        tay                     ; Y = htable offset
        +pv_unroll_xor_htable_16
+
}

; XOR polyval_temp (absolute) into polyval_acc (ZP).
!macro pv_unroll_xor_temp_16 {
        lda polyval_acc+0  : eor polyval_temp+0  : sta polyval_acc+0
        lda polyval_acc+1  : eor polyval_temp+1  : sta polyval_acc+1
        lda polyval_acc+2  : eor polyval_temp+2  : sta polyval_acc+2
        lda polyval_acc+3  : eor polyval_temp+3  : sta polyval_acc+3
        lda polyval_acc+4  : eor polyval_temp+4  : sta polyval_acc+4
        lda polyval_acc+5  : eor polyval_temp+5  : sta polyval_acc+5
        lda polyval_acc+6  : eor polyval_temp+6  : sta polyval_acc+6
        lda polyval_acc+7  : eor polyval_temp+7  : sta polyval_acc+7
        lda polyval_acc+8  : eor polyval_temp+8  : sta polyval_acc+8
        lda polyval_acc+9  : eor polyval_temp+9  : sta polyval_acc+9
        lda polyval_acc+10 : eor polyval_temp+10 : sta polyval_acc+10
        lda polyval_acc+11 : eor polyval_temp+11 : sta polyval_acc+11
        lda polyval_acc+12 : eor polyval_temp+12 : sta polyval_acc+12
        lda polyval_acc+13 : eor polyval_temp+13 : sta polyval_acc+13
        lda polyval_acc+14 : eor polyval_temp+14 : sta polyval_acc+14
        lda polyval_acc+15 : eor polyval_temp+15 : sta polyval_acc+15
}

; =============================================================================
; polyval_init - zero the 128-bit accumulator
; =============================================================================
polyval_init:
        ldx #0
        lda #0
@loop:
        sta polyval_acc,x
        inx
        cpx #16
        bne @loop
        rts

; =============================================================================
; polyval_double - left-shift 128-bit value at polyval_acc by 1 bit
; If carry out, XOR with left-shift reduction constant
; Used during table precomputation and multiplication
; =============================================================================
polyval_double:
        clc
        ; shift left from byte 0 (LSB) to byte 15 (MSB), little-endian
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc @no_reduce
        ; XOR with left-shift reduction: byte[0] ^= $01, byte[15] ^= $C2
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
@no_reduce:
        rts

; =============================================================================
; polyval_right_shift_1 - right-shift 128-bit value at polyval_acc by 1 bit
; If bit 0 was set, XOR with right-shift reduction: byte[15] ^= $E1
; Used during H' = H * x^{-128} precomputation (128 right-shifts)
; =============================================================================
polyval_right_shift_1:
        ; Save bit 0 for reduction
        lda polyval_acc
        and #$01
        pha

        ; Shift right 1 bit from MSB to LSB
        clc
        ror polyval_acc+15
        ror polyval_acc+14
        ror polyval_acc+13
        ror polyval_acc+12
        ror polyval_acc+11
        ror polyval_acc+10
        ror polyval_acc+9
        ror polyval_acc+8
        ror polyval_acc+7
        ror polyval_acc+6
        ror polyval_acc+5
        ror polyval_acc+4
        ror polyval_acc+3
        ror polyval_acc+2
        ror polyval_acc+1
        ror polyval_acc

        ; Reduce if bit 0 was set: XOR byte[15] with $E1
        pla
        beq @no_reduce
        lda polyval_acc+15
        eor #$e1
        sta polyval_acc+15
@no_reduce:
        rts

; =============================================================================
; polyval_shift_left_4 - left-shift polyval_acc by 4 bits with reduction
; Inlined: 4 sequential doublings (ZP ROL = 5 cy vs ABS ROL = 6 cy)
; =============================================================================
polyval_shift_left_4:
        ; --- doubling 1 ---
        clc
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc +
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
+
        ; --- doubling 2 ---
        clc
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc +
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
+
        ; --- doubling 3 ---
        clc
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc +
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
+
        ; --- doubling 4 ---
        clc
        rol polyval_acc
        rol polyval_acc+1
        rol polyval_acc+2
        rol polyval_acc+3
        rol polyval_acc+4
        rol polyval_acc+5
        rol polyval_acc+6
        rol polyval_acc+7
        rol polyval_acc+8
        rol polyval_acc+9
        rol polyval_acc+10
        rol polyval_acc+11
        rol polyval_acc+12
        rol polyval_acc+13
        rol polyval_acc+14
        rol polyval_acc+15
        bcc +
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
+
        rts

; =============================================================================
; polyval_precompute_table - build htable[0..15] from H
;
; Step 1: Compute H' = H * x^{-128} by right-shifting H 128 times
; Step 2: Build table: htable[0] = 0, htable[1] = H',
;         even entries = double(htable[i/2]), odd = htable[i-1] XOR H'
;
; Each entry is 16 bytes. Total: 256 bytes.
; =============================================================================
polyval_precompute_table:
        ; Step 1: Compute H' = H * x^{-128}
        ; Copy H to polyval_acc, then right-shift 128 times
        ldx #0
@copy_h_to_acc:
        lda polyval_h,x
        sta polyval_acc,x
        inx
        cpx #16
        bne @copy_h_to_acc

        ; Right-shift 128 times
        lda #128
        sta pv_shift_ctr
@shift_loop:
        jsr polyval_right_shift_1
        dec pv_shift_ctr
        bne @shift_loop

        ; polyval_acc now contains H' = H * x^{-128}
        ; Copy H' to htable[1] and also back to polyval_h for table building
        ; (We use polyval_h temporarily to store H' during table build)

        ; htable[0] = 0
        ldx #0
        lda #0
@zero_entry:
        sta polyval_htable,x
        inx
        cpx #16
        bne @zero_entry

        ; htable[1] = H'
        ldx #0
@store_h_prime:
        lda polyval_acc,x
        sta polyval_htable+16,x
        inx
        cpx #16
        bne @store_h_prime

        ; htable[2] = 2*H' (left-shift double)
        ; polyval_acc still contains H'
        jsr polyval_double

        ldx #0
@store_2h:
        lda polyval_acc,x
        sta polyval_htable+32,x
        inx
        cpx #16
        bne @store_2h

        ; htable[i] for i=3..15
        lda #3
        sta pv_tbl_idx

@table_loop:
        lda pv_tbl_idx
        lsr                     ; check even/odd via carry
        bcs @odd_entry

        ; --- EVEN: double htable[i/2] ---
        ; A = i/2 from the LSR; calculate source offset = (i/2) * 16
        asl
        asl
        asl
        asl                     ; * 16
        tay                     ; Y = source offset

        ldx #0
@copy_even:
        lda polyval_htable,y
        sta polyval_acc,x
        iny
        inx
        cpx #16
        bne @copy_even

        jsr polyval_double

        ; calculate dest offset = i * 16
        lda pv_tbl_idx
        asl
        asl
        asl
        asl
        tay

        ldx #0
@store_even:
        lda polyval_acc,x
        sta polyval_htable,y
        iny
        inx
        cpx #16
        bne @store_even

        jmp @table_next

@odd_entry:
        ; --- ODD: htable[i] = htable[i-1] XOR htable[1] ---
        ; Copy htable[i-1] to polyval_acc
        lda pv_tbl_idx
        sec
        sbc #1
        asl
        asl
        asl
        asl
        tay                     ; Y = offset of htable[i-1]

        ldx #0
@copy_prev:
        lda polyval_htable,y
        sta polyval_acc,x
        iny
        inx
        cpx #16
        bne @copy_prev

        ; XOR with htable[1] = H'
        ldx #0
@xor_h:
        lda polyval_acc,x
        eor polyval_htable+16,x
        sta polyval_acc,x
        inx
        cpx #16
        bne @xor_h

        ; Store to htable[i] via pointer
        lda pv_tbl_idx
        asl
        asl
        asl
        asl
        clc
        adc #<polyval_htable
        sta zp_ptr2
        lda #>polyval_htable
        adc #0
        sta zp_ptr2+1

        ldy #0
@store_odd:
        lda polyval_acc,y
        sta (zp_ptr2),y
        iny
        cpy #16
        bne @store_odd

@table_next:
        inc pv_tbl_idx
        lda pv_tbl_idx
        cmp #16
        bcs @table_done
        jmp @table_loop

@table_done:
        rts

pv_tbl_idx:     !byte 0
pv_shift_ctr:   !byte 0

; =============================================================================
; polyval_multiply - multiply polyval_acc by H using 4-bit table lookup
; Process each byte of the accumulator as two nibbles (32 lookups total)
;
; Algorithm: result = 0; for i = 15 downto 0:
;   result <<= 4 (with reduction); result ^= htable[byte_high_nibble]
;   result <<= 4 (with reduction); result ^= htable[byte_low_nibble]
;
; Uses LEFT-shift-by-4 with the table built from H' = H * x^{-128},
; so the result is acc * H' = acc * H * x^{-128} = dot(acc, H).
; =============================================================================
polyval_multiply:
        ; Unrolled 16-byte save: eliminates per-call loop overhead in hot path.
        +pv_unroll_save_acc_16

        ; Unrolled 16-byte clear: eliminates per-call loop overhead in hot path.
        lda #0
        +pv_unroll_clear_acc_16

        ; Fully unrolled nibble loop: 32 straight-line invocations of
        ; pv_process_nibble (inlined shift_left_4 + xor_table_entry body).
        ; Bytes processed MSB (byte 15) -> LSB (byte 0), high nibble first.
        ; pv_mul_byte_idx / pv_mul_nibble bookkeeping eliminated.

        ; --- byte 15 ---
        lda pv_mul_input+15
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+15
        and #$0f
        +pv_process_nibble
        ; --- byte 14 ---
        lda pv_mul_input+14
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+14
        and #$0f
        +pv_process_nibble
        ; --- byte 13 ---
        lda pv_mul_input+13
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+13
        and #$0f
        +pv_process_nibble
        ; --- byte 12 ---
        lda pv_mul_input+12
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+12
        and #$0f
        +pv_process_nibble
        ; --- byte 11 ---
        lda pv_mul_input+11
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+11
        and #$0f
        +pv_process_nibble
        ; --- byte 10 ---
        lda pv_mul_input+10
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+10
        and #$0f
        +pv_process_nibble
        ; --- byte 9 ---
        lda pv_mul_input+9
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+9
        and #$0f
        +pv_process_nibble
        ; --- byte 8 ---
        lda pv_mul_input+8
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+8
        and #$0f
        +pv_process_nibble
        ; --- byte 7 ---
        lda pv_mul_input+7
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+7
        and #$0f
        +pv_process_nibble
        ; --- byte 6 ---
        lda pv_mul_input+6
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+6
        and #$0f
        +pv_process_nibble
        ; --- byte 5 ---
        lda pv_mul_input+5
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+5
        and #$0f
        +pv_process_nibble
        ; --- byte 4 ---
        lda pv_mul_input+4
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+4
        and #$0f
        +pv_process_nibble
        ; --- byte 3 ---
        lda pv_mul_input+3
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+3
        and #$0f
        +pv_process_nibble
        ; --- byte 2 ---
        lda pv_mul_input+2
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+2
        and #$0f
        +pv_process_nibble
        ; --- byte 1 ---
        lda pv_mul_input+1
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+1
        and #$0f
        +pv_process_nibble
        ; --- byte 0 ---
        lda pv_mul_input+0
        lsr
        lsr
        lsr
        lsr
        +pv_process_nibble
        lda pv_mul_input+0
        and #$0f
        +pv_process_nibble

        rts

pv_mul_input:   !fill 16, 0    ; saved copy of input accumulator
pv_mul_byte_idx: !byte 0
pv_mul_nibble:  !byte 0

; =============================================================================
; polyval_xor_table_entry - XOR htable[pv_mul_nibble] into polyval_acc
; =============================================================================
polyval_xor_table_entry:
        ; Calculate table offset: nibble * 16
        lda pv_mul_nibble
        beq @skip               ; htable[0] is all zeros
        asl
        asl
        asl
        asl                     ; * 16
        tay                     ; Y = offset into htable (nibble*16)

        ; Unrolled 16-byte XOR from htable: Y stays constant, saves 16 INYs.
        +pv_unroll_xor_htable_16
@skip:
        rts

; =============================================================================
; polyval_update - XOR polyval_temp into accumulator, then multiply by H
; polyval_temp contains the 16-byte block
; =============================================================================
polyval_update:
        ; Unrolled 16-byte XOR of block into accumulator: hot-path loop removal.
        +pv_unroll_xor_temp_16

        ; Multiply accumulator by H
        jsr polyval_multiply

        rts

; =============================================================================
; polyval_finalize - result is already in polyval_acc
; =============================================================================
polyval_finalize:
        rts
