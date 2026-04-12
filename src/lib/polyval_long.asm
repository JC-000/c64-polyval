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

; Copy polyval_acc -> pv_mul_input (both in zero page).
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

; Fused: pv_mul_input[k] = polyval_acc[k] XOR polyval_temp[k]
; Used by polyval_update to seed multiply input directly, skipping the
; separate "acc ^= temp" + "save_acc -> pv_mul_input" two-step.
; Note: polyval_acc itself is NOT updated; the multiply seed phase fully
; overwrites polyval_acc from htable8[pv_mul_input+15], so the pre-XOR
; acc value is unused after this point.
!macro pv_unroll_fused_xor_temp_to_input_16 {
        lda polyval_acc+0  : eor polyval_temp+0  : sta pv_mul_input+0
        lda polyval_acc+1  : eor polyval_temp+1  : sta pv_mul_input+1
        lda polyval_acc+2  : eor polyval_temp+2  : sta pv_mul_input+2
        lda polyval_acc+3  : eor polyval_temp+3  : sta pv_mul_input+3
        lda polyval_acc+4  : eor polyval_temp+4  : sta pv_mul_input+4
        lda polyval_acc+5  : eor polyval_temp+5  : sta pv_mul_input+5
        lda polyval_acc+6  : eor polyval_temp+6  : sta pv_mul_input+6
        lda polyval_acc+7  : eor polyval_temp+7  : sta pv_mul_input+7
        lda polyval_acc+8  : eor polyval_temp+8  : sta pv_mul_input+8
        lda polyval_acc+9  : eor polyval_temp+9  : sta pv_mul_input+9
        lda polyval_acc+10 : eor polyval_temp+10 : sta pv_mul_input+10
        lda polyval_acc+11 : eor polyval_temp+11 : sta pv_mul_input+11
        lda polyval_acc+12 : eor polyval_temp+12 : sta pv_mul_input+12
        lda polyval_acc+13 : eor polyval_temp+13 : sta pv_mul_input+13
        lda polyval_acc+14 : eor polyval_temp+14 : sta pv_mul_input+14
        lda polyval_acc+15 : eor polyval_temp+15 : sta pv_mul_input+15
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

; Store polyval_acc -> sliced table entry at index X (for htable8).
!macro pv_store_acc_to_htable8_x {
        lda polyval_acc+0  : sta polyval_htable8_s0,x
        lda polyval_acc+1  : sta polyval_htable8_s1,x
        lda polyval_acc+2  : sta polyval_htable8_s2,x
        lda polyval_acc+3  : sta polyval_htable8_s3,x
        lda polyval_acc+4  : sta polyval_htable8_s4,x
        lda polyval_acc+5  : sta polyval_htable8_s5,x
        lda polyval_acc+6  : sta polyval_htable8_s6,x
        lda polyval_acc+7  : sta polyval_htable8_s7,x
        lda polyval_acc+8  : sta polyval_htable8_s8,x
        lda polyval_acc+9  : sta polyval_htable8_s9,x
        lda polyval_acc+10 : sta polyval_htable8_s10,x
        lda polyval_acc+11 : sta polyval_htable8_s11,x
        lda polyval_acc+12 : sta polyval_htable8_s12,x
        lda polyval_acc+13 : sta polyval_htable8_s13,x
        lda polyval_acc+14 : sta polyval_htable8_s14,x
        lda polyval_acc+15 : sta polyval_htable8_s15,x
}

; Load polyval_acc <- sliced table entry at index X (for htable8).
!macro pv_load_acc_from_htable8_x {
        lda polyval_htable8_s0,x  : sta polyval_acc+0
        lda polyval_htable8_s1,x  : sta polyval_acc+1
        lda polyval_htable8_s2,x  : sta polyval_acc+2
        lda polyval_htable8_s3,x  : sta polyval_acc+3
        lda polyval_htable8_s4,x  : sta polyval_acc+4
        lda polyval_htable8_s5,x  : sta polyval_acc+5
        lda polyval_htable8_s6,x  : sta polyval_acc+6
        lda polyval_htable8_s7,x  : sta polyval_acc+7
        lda polyval_htable8_s8,x  : sta polyval_acc+8
        lda polyval_htable8_s9,x  : sta polyval_acc+9
        lda polyval_htable8_s10,x : sta polyval_acc+10
        lda polyval_htable8_s11,x : sta polyval_acc+11
        lda polyval_htable8_s12,x : sta polyval_acc+12
        lda polyval_htable8_s13,x : sta polyval_acc+13
        lda polyval_htable8_s14,x : sta polyval_acc+14
        lda polyval_htable8_s15,x : sta polyval_acc+15
}

; Store polyval_acc -> sliced reduce8 entry at index X.
!macro pv_store_acc_to_reduce8_x {
        lda polyval_acc+0  : sta polyval_reduce8_s0,x
        lda polyval_acc+1  : sta polyval_reduce8_s1,x
        lda polyval_acc+2  : sta polyval_reduce8_s2,x
        lda polyval_acc+3  : sta polyval_reduce8_s3,x
        lda polyval_acc+4  : sta polyval_reduce8_s4,x
        lda polyval_acc+5  : sta polyval_reduce8_s5,x
        lda polyval_acc+6  : sta polyval_reduce8_s6,x
        lda polyval_acc+7  : sta polyval_reduce8_s7,x
        lda polyval_acc+8  : sta polyval_reduce8_s8,x
        lda polyval_acc+9  : sta polyval_reduce8_s9,x
        lda polyval_acc+10 : sta polyval_reduce8_s10,x
        lda polyval_acc+11 : sta polyval_reduce8_s11,x
        lda polyval_acc+12 : sta polyval_reduce8_s12,x
        lda polyval_acc+13 : sta polyval_reduce8_s13,x
        lda polyval_acc+14 : sta polyval_reduce8_s14,x
        lda polyval_acc+15 : sta polyval_reduce8_s15,x
}

; Load polyval_acc <- sliced reduce8 entry at index X.
!macro pv_load_acc_from_reduce8_x {
        lda polyval_reduce8_s0,x  : sta polyval_acc+0
        lda polyval_reduce8_s1,x  : sta polyval_acc+1
        lda polyval_reduce8_s2,x  : sta polyval_acc+2
        lda polyval_reduce8_s3,x  : sta polyval_acc+3
        lda polyval_reduce8_s4,x  : sta polyval_acc+4
        lda polyval_reduce8_s5,x  : sta polyval_acc+5
        lda polyval_reduce8_s6,x  : sta polyval_acc+6
        lda polyval_reduce8_s7,x  : sta polyval_acc+7
        lda polyval_reduce8_s8,x  : sta polyval_acc+8
        lda polyval_reduce8_s9,x  : sta polyval_acc+9
        lda polyval_reduce8_s10,x : sta polyval_acc+10
        lda polyval_reduce8_s11,x : sta polyval_acc+11
        lda polyval_reduce8_s12,x : sta polyval_acc+12
        lda polyval_reduce8_s13,x : sta polyval_acc+13
        lda polyval_reduce8_s14,x : sta polyval_acc+14
        lda polyval_reduce8_s15,x : sta polyval_acc+15
}

; Inline shift_left_8 with reduction, using polyval_reduce8 sliced table.
; Destroys A, X. Y is preserved if caller needs it.
!macro pv_inline_shift_left_8 {
        ldx polyval_acc+15          ; X = outgoing byte (reduce8 index)
        lda polyval_acc+14 : sta polyval_acc+15
        lda polyval_acc+13 : sta polyval_acc+14
        lda polyval_acc+12 : sta polyval_acc+13
        lda polyval_acc+11 : sta polyval_acc+12
        lda polyval_acc+10 : sta polyval_acc+11
        lda polyval_acc+9  : sta polyval_acc+10
        lda polyval_acc+8  : sta polyval_acc+9
        lda polyval_acc+7  : sta polyval_acc+8
        lda polyval_acc+6  : sta polyval_acc+7
        lda polyval_acc+5  : sta polyval_acc+6
        lda polyval_acc+4  : sta polyval_acc+5
        lda polyval_acc+3  : sta polyval_acc+4
        lda polyval_acc+2  : sta polyval_acc+3
        lda polyval_acc+1  : sta polyval_acc+2
        lda polyval_acc+0  : sta polyval_acc+1
        lda #0             : sta polyval_acc+0
        ; XOR reduce8[X] into polyval_acc
        lda polyval_acc+0  : eor polyval_reduce8_s0,x  : sta polyval_acc+0
        lda polyval_acc+1  : eor polyval_reduce8_s1,x  : sta polyval_acc+1
        lda polyval_acc+2  : eor polyval_reduce8_s2,x  : sta polyval_acc+2
        lda polyval_acc+3  : eor polyval_reduce8_s3,x  : sta polyval_acc+3
        lda polyval_acc+4  : eor polyval_reduce8_s4,x  : sta polyval_acc+4
        lda polyval_acc+5  : eor polyval_reduce8_s5,x  : sta polyval_acc+5
        lda polyval_acc+6  : eor polyval_reduce8_s6,x  : sta polyval_acc+6
        lda polyval_acc+7  : eor polyval_reduce8_s7,x  : sta polyval_acc+7
        lda polyval_acc+8  : eor polyval_reduce8_s8,x  : sta polyval_acc+8
        lda polyval_acc+9  : eor polyval_reduce8_s9,x  : sta polyval_acc+9
        lda polyval_acc+10 : eor polyval_reduce8_s10,x : sta polyval_acc+10
        lda polyval_acc+11 : eor polyval_reduce8_s11,x : sta polyval_acc+11
        lda polyval_acc+12 : eor polyval_reduce8_s12,x : sta polyval_acc+12
        lda polyval_acc+13 : eor polyval_reduce8_s13,x : sta polyval_acc+13
        lda polyval_acc+14 : eor polyval_reduce8_s14,x : sta polyval_acc+14
        lda polyval_acc+15 : eor polyval_reduce8_s15,x : sta polyval_acc+15
}

; Fused shift_left_8 + reduce8 + htable8 XOR pass.
; Walks bytes high-to-low so we can read polyval_acc+(k-1) before overwriting it.
; Entry: X = old polyval_acc+15 (reduce8 index), Y = current input byte
;        (htable8 index). Both registers are preserved.
!macro pv_fused_shift_reduce_htable {
        lda polyval_acc+14 : eor polyval_reduce8_s15,x : eor polyval_htable8_s15,y : sta polyval_acc+15
        lda polyval_acc+13 : eor polyval_reduce8_s14,x : eor polyval_htable8_s14,y : sta polyval_acc+14
        lda polyval_acc+12 : eor polyval_reduce8_s13,x : eor polyval_htable8_s13,y : sta polyval_acc+13
        lda polyval_acc+11 : eor polyval_reduce8_s12,x : eor polyval_htable8_s12,y : sta polyval_acc+12
        lda polyval_acc+10 : eor polyval_reduce8_s11,x : eor polyval_htable8_s11,y : sta polyval_acc+11
        lda polyval_acc+9  : eor polyval_reduce8_s10,x : eor polyval_htable8_s10,y : sta polyval_acc+10
        lda polyval_acc+8  : eor polyval_reduce8_s9,x  : eor polyval_htable8_s9,y  : sta polyval_acc+9
        lda polyval_acc+7  : eor polyval_reduce8_s8,x  : eor polyval_htable8_s8,y  : sta polyval_acc+8
        lda polyval_acc+6  : eor polyval_reduce8_s7,x  : eor polyval_htable8_s7,y  : sta polyval_acc+7
        lda polyval_acc+5  : eor polyval_reduce8_s6,x  : eor polyval_htable8_s6,y  : sta polyval_acc+6
        lda polyval_acc+4  : eor polyval_reduce8_s5,x  : eor polyval_htable8_s5,y  : sta polyval_acc+5
        lda polyval_acc+3  : eor polyval_reduce8_s4,x  : eor polyval_htable8_s4,y  : sta polyval_acc+4
        lda polyval_acc+2  : eor polyval_reduce8_s3,x  : eor polyval_htable8_s3,y  : sta polyval_acc+3
        lda polyval_acc+1  : eor polyval_reduce8_s2,x  : eor polyval_htable8_s2,y  : sta polyval_acc+2
        lda polyval_acc+0  : eor polyval_reduce8_s1,x  : eor polyval_htable8_s1,y  : sta polyval_acc+1
        lda polyval_reduce8_s0,x : eor polyval_htable8_s0,y : sta polyval_acc+0
}

; XOR htable8[byte_k] into polyval_acc. X = byte index (0..255).
!macro pv_inline_xor_htable8_x {
        lda polyval_acc+0  : eor polyval_htable8_s0,x  : sta polyval_acc+0
        lda polyval_acc+1  : eor polyval_htable8_s1,x  : sta polyval_acc+1
        lda polyval_acc+2  : eor polyval_htable8_s2,x  : sta polyval_acc+2
        lda polyval_acc+3  : eor polyval_htable8_s3,x  : sta polyval_acc+3
        lda polyval_acc+4  : eor polyval_htable8_s4,x  : sta polyval_acc+4
        lda polyval_acc+5  : eor polyval_htable8_s5,x  : sta polyval_acc+5
        lda polyval_acc+6  : eor polyval_htable8_s6,x  : sta polyval_acc+6
        lda polyval_acc+7  : eor polyval_htable8_s7,x  : sta polyval_acc+7
        lda polyval_acc+8  : eor polyval_htable8_s8,x  : sta polyval_acc+8
        lda polyval_acc+9  : eor polyval_htable8_s9,x  : sta polyval_acc+9
        lda polyval_acc+10 : eor polyval_htable8_s10,x : sta polyval_acc+10
        lda polyval_acc+11 : eor polyval_htable8_s11,x : sta polyval_acc+11
        lda polyval_acc+12 : eor polyval_htable8_s12,x : sta polyval_acc+12
        lda polyval_acc+13 : eor polyval_htable8_s13,x : sta polyval_acc+13
        lda polyval_acc+14 : eor polyval_htable8_s14,x : sta polyval_acc+14
        lda polyval_acc+15 : eor polyval_htable8_s15,x : sta polyval_acc+15
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
;
; Entry:
;   A, X, Y      n/a (contents ignored)
;   memory       none required
;   flags        none required
;
; Exit:
;   A            0
;   X            16
;   Y            preserved
;   memory       polyval_acc[0..15] = 0
;   flags        Z=1, N=0 (from the trailing compare)
;
; Clobbers: A, X, polyval_acc
; Cycles:   ~110 (16-byte store loop)
; IRQ-safe: no (touches shared ZP polyval_acc)
; Reentrant: no
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
; polyval_double - multiply the accumulator by x in GF(2^128)
;
; Implements a single left-shift of polyval_acc with POLYVAL's left-shift
; reduction polynomial (bytes ^= {$01, ..., $c2}) when the high bit
; carries out. Used internally by polyval_precompute_table and by the
; SHORT-profile multiply; exposed so tests can exercise the doubling
; primitive in isolation.
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_acc = 128-bit value to double
;   flags        none required
;
; Exit:
;   A            reduction constant if branch taken, else last rolled byte
;   X, Y         preserved
;   memory       polyval_acc = input * x (mod POLYVAL reduction polynomial)
;   flags        undefined - do NOT rely on C/Z/N
;
; Clobbers: A, polyval_acc
; Cycles:   85 (inlined ZP ROLs; see project memory)
; IRQ-safe: no
; Reentrant: no
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
; polyval_shift_left_4 - multiply the accumulator by x^4 in GF(2^128)
;
; Four sequential POLYVAL doublings fused into one straight-line sequence
; to get a small speed win on the SHORT-profile multiply hot path.
; Exposed as a public symbol so test_polyval_direct.py can regression-
; test the combined 4-bit shift against the Python reference.
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_acc = 128-bit value to shift
;   flags        none required
;
; Exit:
;   A            undefined
;   X, Y         preserved
;   memory       polyval_acc = input * x^4
;   flags        undefined
;
; Clobbers: A, polyval_acc
; Cycles:   370 (measured, see project memory)
; IRQ-safe: no
; Reentrant: no
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
; polyval_precompute_table - build the H-tables from polyval_h
;
; LONG profile: builds BOTH the 4-bit polyval_htable (256 B) and the
; 8-bit Shoup slices polyval_htable8 / polyval_reduce8 (8 KB). Must be
; called once per new H before polyval_update / polyval_multiply.
;
; Algorithm:
;   Step 1: Compute H' = H * x^{-128} via 128 right-shifts (classical)
;           or the mulX_POLYVAL identity (SHORT profile).
;   Step 2: Fill polyval_htable[0..15] where htable[0]=0, htable[1]=H',
;           even entries = double(htable[i/2]), odd = htable[i-1] ^ H'.
;   Step 3: Build the 8-bit Shoup slices and reduction slices from the
;           4-bit table (LONG profile only).
;
; PRECONDITION (undocumented until now): polyval_h must already contain
; the desired H. This routine destructively overwrites polyval_h with H'
; during the build and does NOT restore it. Callers that need H back
; after a precompute must save a copy before calling. (See SURPRISES in
; the Phase 3 report.)
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_h = 16-byte hash key H
;
; Exit:
;   A, X, Y      undefined
;   memory       polyval_htable[256]    filled
;                polyval_htable8[4096]  filled (LONG only)
;                polyval_reduce8[4096]  filled (LONG only)
;                polyval_h              CLOBBERED (now holds H')
;                polyval_acc            undefined
;
; Clobbers: A, X, Y, polyval_acc, polyval_h, pv_shift_ctr and internal
;           scratch; see the implementation.
; Cycles:   LONG ~255211, SHORT ~4654 (see benchmark_polyval.py)
; IRQ-safe: no
; Reentrant: no
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
        ; -----------------------------------------------------------------
        ; Build 8-bit Shoup window tables:
        ;   polyval_htable8[i]  = H' * i        (i in 0..255)
        ;   polyval_reduce8[i]  = i * x^128 mod P
        ;
        ; Both are GF(2^128) values; i is an 8-bit polynomial coefficient
        ; vector. Build recurrence:
        ;   T[0] = 0
        ;   T[1] = base
        ;   T[i even] = double(T[i/2])    via polyval_double (reads from
        ;                                  sliced storage with X = i/2)
        ;   T[i odd]  = T[i-1] XOR T[1]  (T[i-1] is still in polyval_acc
        ;                                  from the previous iteration)
        ; -----------------------------------------------------------------

        ; --- Build polyval_htable8 from H' (= htable[1]) ---

        ; T[0] = 0
        ldx #0
        lda #0
        +pv_unroll_clear_acc_16
        +pv_store_acc_to_htable8_x

        ; T[1] = H' (still stored at polyval_htable+16)
        ldx #0
@copy_hprime_htable8_1:
        lda polyval_htable+16,x
        sta polyval_acc,x
        inx
        cpx #16
        bne @copy_hprime_htable8_1
        ldx #1
        +pv_store_acc_to_htable8_x

        ; For i = 2..255:
        lda #2
        sta pv_tbl8_idx
@h8_loop:
        lda pv_tbl8_idx
        lsr                         ; carry = parity; A = i/2
        bcs @h8_odd
        ; -- EVEN: acc = double(htable8[i/2]), i/2 is in A --
        tax
        +pv_load_acc_from_htable8_x
        jsr polyval_double
        jmp @h8_store
@h8_odd:
        ; -- ODD: acc currently holds htable8[i-1]. XOR with htable8[1] --
        ldx #0
@h8_odd_xor:
        lda polyval_acc,x
        eor polyval_htable+16,x     ; H' = htable8[1]
        sta polyval_acc,x
        inx
        cpx #16
        bne @h8_odd_xor
@h8_store:
        ldx pv_tbl8_idx
        +pv_store_acc_to_htable8_x
        inc pv_tbl8_idx
        beq @h8_done                ; wrapped 0 → finished 2..255
        jmp @h8_loop
@h8_done:

        ; --- Build polyval_reduce8 from pv_reduce_base (= x^128 mod P) ---

        ; T[0] = 0
        ldx #0
        lda #0
        +pv_unroll_clear_acc_16
        +pv_store_acc_to_reduce8_x

        ; T[1] = pv_reduce_base
        ldx #0
@copy_rbase_reduce8_1:
        lda pv_reduce_base,x
        sta polyval_acc,x
        inx
        cpx #16
        bne @copy_rbase_reduce8_1
        ldx #1
        +pv_store_acc_to_reduce8_x

        ; For i = 2..255:
        lda #2
        sta pv_tbl8_idx
@r8_loop:
        lda pv_tbl8_idx
        lsr
        bcs @r8_odd
        tax
        +pv_load_acc_from_reduce8_x
        jsr polyval_double
        jmp @r8_store
@r8_odd:
        ldx #0
@r8_odd_xor:
        lda polyval_acc,x
        eor pv_reduce_base,x
        sta polyval_acc,x
        inx
        cpx #16
        bne @r8_odd_xor
@r8_store:
        ldx pv_tbl8_idx
        +pv_store_acc_to_reduce8_x
        inc pv_tbl8_idx
        beq @r8_done
        jmp @r8_loop
@r8_done:
        rts

pv_tbl_idx:     !byte 0
pv_shift_ctr:   !byte 0

; x^128 mod P(x) as 16 little-endian bytes.
; Bits set: bit 0 (x^0=1), bit 121, bit 126, bit 127
; => byte 0 = $01, byte 15 = $C2 (0b11000010: bits 1, 6, 7)
pv_reduce_base:
        !byte $01, $00, $00, $00, $00, $00, $00, $00
        !byte $00, $00, $00, $00, $00, $00, $00, $c2

; Scratch counter for 8-bit table build
pv_tbl8_idx:    !byte 0

; =============================================================================
; polyval_multiply - multiply polyval_acc by H using 8-bit Shoup window
; Processes 16 input bytes from MSB (byte 15) to LSB (byte 0).
;
; Algorithm: result = 0; for i = 15 downto 0:
;   result = shift_left_8(result) with reduction
;   result ^= htable8[input_byte_i]
;
; Uses two sliced 4 KB tables:
;   polyval_htable8[i] = H' * i            (for i = 0..255)
;   polyval_reduce8[b] = b * x^128 mod P   (reduction carry contribution)
; Built from H' = H * x^{-128}, so result = acc * H' = dot(acc, H).
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_acc = 128-bit operand a
;                polyval_htable8, polyval_reduce8 = already built by
;                polyval_precompute_table
;
; Exit:
;   A, X, Y      undefined
;   memory       polyval_acc = a * H' = dot(a, H)
;                pv_mul_input = CLOBBERED (holds copy of input)
;
; Clobbers: A, X, Y, polyval_acc, pv_mul_input
; Cycles:   3917 (LONG, measured)
; IRQ-safe: no
; Reentrant: no
; =============================================================================
polyval_multiply:
        ; Save input. Byte-15 seed below initialises the whole accumulator,
        ; so no separate clear pass is needed.
        +pv_unroll_save_acc_16
        ; Fall through to polyval_multiply_core.

; Internal entry point used by polyval_update: assumes pv_mul_input is
; already populated (typically with acc XOR block) and skips the save step.
; Not a published API symbol — callers outside this file must use
; polyval_multiply, which preserves the legacy "input is current acc" contract.
polyval_multiply_core:
        ; Fully unrolled 16-byte Shoup-8 loop using the fused
        ; shift_left_8 + reduce8 + htable8 macro:
        ;   X = old polyval_acc+15 (reduce8 index, "outgoing" byte)
        ;   Y = current input byte (htable8 index)
        ;
        ; Byte 15 is special: acc starts at zero, so the shift+reduce parts
        ; are no-ops and we just seed acc <- htable8[input[15]] directly.

        ; --- byte 15 (seed from zero) ---
        ldy pv_mul_input+15
        lda polyval_htable8_s0,y  : sta polyval_acc+0
        lda polyval_htable8_s1,y  : sta polyval_acc+1
        lda polyval_htable8_s2,y  : sta polyval_acc+2
        lda polyval_htable8_s3,y  : sta polyval_acc+3
        lda polyval_htable8_s4,y  : sta polyval_acc+4
        lda polyval_htable8_s5,y  : sta polyval_acc+5
        lda polyval_htable8_s6,y  : sta polyval_acc+6
        lda polyval_htable8_s7,y  : sta polyval_acc+7
        lda polyval_htable8_s8,y  : sta polyval_acc+8
        lda polyval_htable8_s9,y  : sta polyval_acc+9
        lda polyval_htable8_s10,y : sta polyval_acc+10
        lda polyval_htable8_s11,y : sta polyval_acc+11
        lda polyval_htable8_s12,y : sta polyval_acc+12
        lda polyval_htable8_s13,y : sta polyval_acc+13
        lda polyval_htable8_s14,y : sta polyval_acc+14
        lda polyval_htable8_s15,y : sta polyval_acc+15

        ; --- bytes 14..0: fused shift+reduce+htable per iteration ---
        ldx polyval_acc+15 : ldy pv_mul_input+14 : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+13 : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+12 : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+11 : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+10 : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+9  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+8  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+7  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+6  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+5  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+4  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+3  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+2  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+1  : +pv_fused_shift_reduce_htable
        ldx polyval_acc+15 : ldy pv_mul_input+0  : +pv_fused_shift_reduce_htable
        rts


; pv_mul_input lives in zero page ($20-$2F); pv_mul_nibble lives in zero
; page ($30) - see constants_lib.asm. pv_mul_byte_idx was used by earlier
; Tier 1 unrolled multiply; the fused Shoup-8 hot path no longer needs it.

; =============================================================================
; polyval_xor_table_entry - XOR polyval_htable[pv_mul_nibble] into acc
;
; Low-level helper exposed for the regression suite. Selects one 16-byte
; entry from the 4-bit Shoup H-table (indexed by pv_mul_nibble in 0..15)
; and XORs it into polyval_acc in place.
;
; Entry:
;   A, X, Y      n/a
;   memory       pv_mul_nibble  = entry index 0..15 (low nibble only)
;                polyval_htable = already built by polyval_precompute_table
;                polyval_acc    = current accumulator
;
; Exit:
;   A, X, Y      undefined
;   memory       polyval_acc ^= polyval_htable[pv_mul_nibble]
;                (no-op when pv_mul_nibble == 0)
;
; Clobbers: A, Y, polyval_acc
; Cycles:   353 when nibble != 0 (measured), ~5 for the fast skip
; IRQ-safe: no
; Reentrant: no
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
; polyval_update - absorb one 16-byte block into the POLYVAL accumulator
;
; Computes acc = (acc XOR polyval_temp) * H for one 128-bit block.
; This is the per-block step of the RFC 8452 POLYVAL construction.
;
; LONG-profile fast path: the XOR and the multiply-seed are fused, so
; polyval_acc is NOT touched by the XOR step; the multiply's seed phase
; overwrites acc from htable8[pv_mul_input+15] directly.
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_acc    = current accumulator
;                polyval_temp   = 16-byte block to absorb
;                polyval_htable8, polyval_reduce8 = already precomputed
;
; Exit:
;   A, X, Y      undefined
;   memory       polyval_acc    = (old acc XOR polyval_temp) * H
;                polyval_temp   = preserved
;                pv_mul_input   = clobbered
;
; Clobbers: A, X, Y, polyval_acc, pv_mul_input
; Cycles:   3993 (LONG, measured)
; IRQ-safe: no
; Reentrant: no
; =============================================================================
polyval_update:
        ; Fused: write pv_mul_input = polyval_acc XOR polyval_temp directly.
        ; This replaces the old two-step (acc ^= temp; multiply saves acc)
        ; with a single pass (~112 cy saved). polyval_acc is left untouched
        ; here because the multiply seed phase fully overwrites it from
        ; htable8[pv_mul_input+15].
        +pv_unroll_fused_xor_temp_to_input_16

        ; Multiply by H, skipping the save (pv_mul_input is already loaded).
        jsr polyval_multiply_core

        rts

; =============================================================================
; polyval_finalize - result is already in polyval_acc
; =============================================================================
polyval_finalize:
        rts
