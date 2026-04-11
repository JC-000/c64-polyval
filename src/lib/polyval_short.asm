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

; -----------------------------------------------------------------------------
; Precompute-helper macros (mulX_POLYVAL + unrolled Shoup-4 table build)
; -----------------------------------------------------------------------------

; XOR polyval_temp (abs, 16 bytes) into polyval_acc (ZP, 16 bytes).
!macro pv_xor_temp_into_acc_16 {
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

; Right-shift the 16-byte value at polyval_temp by 1 bit with POLYVAL
; right-shift reduction (byte[15] ^= $E1 when bit 0 of byte[0] was set).
; Stash the LSB-out flag in X before the shift clobbers the flags.
!macro pv_rshift1_temp {
        lda polyval_temp
        and #$01
        tax                     ; X = LSB-out flag (0 or 1)
        clc
        ror polyval_temp+15
        ror polyval_temp+14
        ror polyval_temp+13
        ror polyval_temp+12
        ror polyval_temp+11
        ror polyval_temp+10
        ror polyval_temp+9
        ror polyval_temp+8
        ror polyval_temp+7
        ror polyval_temp+6
        ror polyval_temp+5
        ror polyval_temp+4
        ror polyval_temp+3
        ror polyval_temp+2
        ror polyval_temp+1
        ror polyval_temp+0
        cpx #0
        beq +
        lda polyval_temp+15
        eor #$e1
        sta polyval_temp+15
+
}

; Double an htable entry in place: left-shift 128-bit value at `base` with
; POLYVAL left-shift reduction (byte[0] ^= $01, byte[15] ^= $c2 on MSB-out).
; Uses absolute ROLs directly on the table entry (htable is page-aligned).
!macro pv_double_htable_inplace .base {
        clc
        rol .base+0
        rol .base+1
        rol .base+2
        rol .base+3
        rol .base+4
        rol .base+5
        rol .base+6
        rol .base+7
        rol .base+8
        rol .base+9
        rol .base+10
        rol .base+11
        rol .base+12
        rol .base+13
        rol .base+14
        rol .base+15
        bcc +
        lda .base+0
        eor #$01
        sta .base+0
        lda .base+15
        eor #$c2
        sta .base+15
+
}

; Copy-then-double: dst = 2 * src, via straight-line loads/rotates/stores.
; First byte uses ASL (clears carry), remaining bytes use ROL to propagate.
; Applies POLYVAL left-shift reduction on MSB-out.
!macro pv_double_htable_copy .src, .dst {
        lda .src+0  : asl : sta .dst+0
        lda .src+1  : rol : sta .dst+1
        lda .src+2  : rol : sta .dst+2
        lda .src+3  : rol : sta .dst+3
        lda .src+4  : rol : sta .dst+4
        lda .src+5  : rol : sta .dst+5
        lda .src+6  : rol : sta .dst+6
        lda .src+7  : rol : sta .dst+7
        lda .src+8  : rol : sta .dst+8
        lda .src+9  : rol : sta .dst+9
        lda .src+10 : rol : sta .dst+10
        lda .src+11 : rol : sta .dst+11
        lda .src+12 : rol : sta .dst+12
        lda .src+13 : rol : sta .dst+13
        lda .src+14 : rol : sta .dst+14
        lda .src+15 : rol : sta .dst+15
        bcc +
        lda .dst+0
        eor #$01
        sta .dst+0
        lda .dst+15
        eor #$c2
        sta .dst+15
+
}

; Fused XOR: dst = a XOR b (16 bytes, three distinct abs regions).
!macro pv_xor_htable_entries .a, .b, .dst {
        lda .a+0  : eor .b+0  : sta .dst+0
        lda .a+1  : eor .b+1  : sta .dst+1
        lda .a+2  : eor .b+2  : sta .dst+2
        lda .a+3  : eor .b+3  : sta .dst+3
        lda .a+4  : eor .b+4  : sta .dst+4
        lda .a+5  : eor .b+5  : sta .dst+5
        lda .a+6  : eor .b+6  : sta .dst+6
        lda .a+7  : eor .b+7  : sta .dst+7
        lda .a+8  : eor .b+8  : sta .dst+8
        lda .a+9  : eor .b+9  : sta .dst+9
        lda .a+10 : eor .b+10 : sta .dst+10
        lda .a+11 : eor .b+11 : sta .dst+11
        lda .a+12 : eor .b+12 : sta .dst+12
        lda .a+13 : eor .b+13 : sta .dst+13
        lda .a+14 : eor .b+14 : sta .dst+14
        lda .a+15 : eor .b+15 : sta .dst+15
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
; Cycles:   85 (inlined ZP ROLs)
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
; If bit 0 was set, XOR with right-shift reduction: byte[15] ^= $E1.
;
; No longer used internally (polyval_precompute_table now uses the
; mulX_POLYVAL identity inlined on polyval_temp), but retained as a public
; callable routine so test_polyval_direct.py can still exercise it.
; =============================================================================
polyval_right_shift_1:
        lda polyval_acc
        and #$01
        pha

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

        pla
        beq @rshift_no_reduce
        lda polyval_acc+15
        eor #$e1
        sta polyval_acc+15
@rshift_no_reduce:
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
; Cycles:   370 (measured)
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
; polyval_precompute_table - build the 4-bit H-table from polyval_h
;
; SHORT profile: builds only polyval_htable (256 B). Must be called once
; per new H before polyval_update / polyval_multiply.
;
; PRECONDITION (undocumented until now): polyval_h must already contain
; the desired H. This routine uses polyval_temp and polyval_acc as
; scratch during the mulX_POLYVAL transform and leaves polyval_h
; overwritten with H'. Callers that need H back after a precompute must
; save a copy first. (See SURPRISES in the Phase 3 report.)
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_h = 16-byte hash key H
;
; Exit:
;   A, X, Y      undefined
;   memory       polyval_htable[256]  filled
;                polyval_h            CLOBBERED (holds H')
;                polyval_acc, polyval_temp undefined
;
; Clobbers: A, X, Y, polyval_acc, polyval_temp, polyval_h
; Cycles:   4654 (SHORT, measured)
; IRQ-safe: no
; Reentrant: no
;
; Algorithm notes:
; Step 1: Compute H' = H * x^{-128} via the mulX_POLYVAL identity.
;
;   In GF(2^128) under POLYVAL's polynomial p(x) = x^128 + x^127 + x^126
;   + x^121 + 1, we have x^128 = x^127 + x^126 + x^121 + 1 (mod p).
;   Dividing both sides by x^128 gives
;       1 = x^-1 + x^-2 + x^-7 + x^-128   (mod p)
;   hence
;       x^-128 = 1 + x^-1 + x^-2 + x^-7   (mod p).
;   Therefore
;       H * x^-128 = H XOR (H*x^-1) XOR (H*x^-2) XOR (H*x^-7).
;
;   Each H*x^-k is obtained by k successive right-shifts of H with POLYVAL
;   right-shift reduction (byte[15] ^= $e1 when the LSB falls off). This
;   replaces 128 iterations with 7 single-bit shifts plus 3 full-width XORs.
;
; Step 2: Build the Shoup-4 window htable[0..15] completely unrolled:
;   htable[0]    = 0
;   htable[1]    = H'
;   htable[2k]   = double(htable[k])            via pv_double_htable_copy
;   htable[2k+1] = htable[2k] XOR htable[1]     via pv_xor_htable_entries
;
; Each entry is 16 bytes. Total table: 256 bytes.
; =============================================================================
polyval_precompute_table:
        ; -------------------------------------------------------------------
        ; Step 1: mulX_POLYVAL transform (H -> H' = H * x^-128)
        ; -------------------------------------------------------------------

        ; Copy H into polyval_acc (ZP, will accumulate the running XOR and
        ; end up holding H') and into polyval_temp (abs, will be shifted).
        ldx #15
@copy_h:
        lda polyval_h,x
        sta polyval_acc,x
        sta polyval_temp,x
        dex
        bpl @copy_h

        ; Shift temp right by 1: temp = H*x^-1. XOR into acc.
        +pv_rshift1_temp
        +pv_xor_temp_into_acc_16

        ; Shift temp right by 1 more: temp = H*x^-2. XOR into acc.
        +pv_rshift1_temp
        +pv_xor_temp_into_acc_16

        ; Shift temp right by 5 more: temp = H*x^-7. XOR into acc.
        +pv_rshift1_temp
        +pv_rshift1_temp
        +pv_rshift1_temp
        +pv_rshift1_temp
        +pv_rshift1_temp
        +pv_xor_temp_into_acc_16

        ; polyval_acc now holds H' = H * x^-128.

        ; -------------------------------------------------------------------
        ; Step 2: fully unrolled Shoup-4 table build
        ; -------------------------------------------------------------------

        ; htable[0] = 0
        lda #0
        sta polyval_htable+0
        sta polyval_htable+1
        sta polyval_htable+2
        sta polyval_htable+3
        sta polyval_htable+4
        sta polyval_htable+5
        sta polyval_htable+6
        sta polyval_htable+7
        sta polyval_htable+8
        sta polyval_htable+9
        sta polyval_htable+10
        sta polyval_htable+11
        sta polyval_htable+12
        sta polyval_htable+13
        sta polyval_htable+14
        sta polyval_htable+15

        ; htable[1] = H'   (ZP polyval_acc -> polyval_htable+16)
        lda polyval_acc+0  : sta polyval_htable+16
        lda polyval_acc+1  : sta polyval_htable+17
        lda polyval_acc+2  : sta polyval_htable+18
        lda polyval_acc+3  : sta polyval_htable+19
        lda polyval_acc+4  : sta polyval_htable+20
        lda polyval_acc+5  : sta polyval_htable+21
        lda polyval_acc+6  : sta polyval_htable+22
        lda polyval_acc+7  : sta polyval_htable+23
        lda polyval_acc+8  : sta polyval_htable+24
        lda polyval_acc+9  : sta polyval_htable+25
        lda polyval_acc+10 : sta polyval_htable+26
        lda polyval_acc+11 : sta polyval_htable+27
        lda polyval_acc+12 : sta polyval_htable+28
        lda polyval_acc+13 : sta polyval_htable+29
        lda polyval_acc+14 : sta polyval_htable+30
        lda polyval_acc+15 : sta polyval_htable+31

        ; htable[2]  = double(htable[1])
        +pv_double_htable_copy polyval_htable+16,  polyval_htable+32
        ; htable[3]  = htable[2] XOR htable[1]
        +pv_xor_htable_entries polyval_htable+32,  polyval_htable+16, polyval_htable+48
        ; htable[4]  = double(htable[2])
        +pv_double_htable_copy polyval_htable+32,  polyval_htable+64
        ; htable[5]  = htable[4] XOR htable[1]
        +pv_xor_htable_entries polyval_htable+64,  polyval_htable+16, polyval_htable+80
        ; htable[6]  = double(htable[3])
        +pv_double_htable_copy polyval_htable+48,  polyval_htable+96
        ; htable[7]  = htable[6] XOR htable[1]
        +pv_xor_htable_entries polyval_htable+96,  polyval_htable+16, polyval_htable+112
        ; htable[8]  = double(htable[4])
        +pv_double_htable_copy polyval_htable+64,  polyval_htable+128
        ; htable[9]  = htable[8] XOR htable[1]
        +pv_xor_htable_entries polyval_htable+128, polyval_htable+16, polyval_htable+144
        ; htable[10] = double(htable[5])
        +pv_double_htable_copy polyval_htable+80,  polyval_htable+160
        ; htable[11] = htable[10] XOR htable[1]
        +pv_xor_htable_entries polyval_htable+160, polyval_htable+16, polyval_htable+176
        ; htable[12] = double(htable[6])
        +pv_double_htable_copy polyval_htable+96,  polyval_htable+192
        ; htable[13] = htable[12] XOR htable[1]
        +pv_xor_htable_entries polyval_htable+192, polyval_htable+16, polyval_htable+208
        ; htable[14] = double(htable[7])
        +pv_double_htable_copy polyval_htable+112, polyval_htable+224
        ; htable[15] = htable[14] XOR htable[1]
        +pv_xor_htable_entries polyval_htable+224, polyval_htable+16, polyval_htable+240

        rts

; =============================================================================
; polyval_multiply - multiply polyval_acc by H in GF(2^128) (SHORT profile)
;
; Algorithm: result = 0; for i = 15 downto 0:
;   result <<= 4 (with reduction); result ^= htable[byte_high_nibble]
;   result <<= 4 (with reduction); result ^= htable[byte_low_nibble]
;
; Uses LEFT-shift-by-4 with the table built from H' = H * x^{-128},
; so the result is acc * H' = acc * H * x^{-128} = dot(acc, H). The
; SHORT profile uses only the 256-byte polyval_htable (no htable8 /
; reduce8 slices).
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_acc    = 128-bit operand a
;                polyval_htable = built by polyval_precompute_table
;
; Exit:
;   A, X, Y      undefined
;   memory       polyval_acc    = a * H' = dot(a, H)
;                pv_mul_input   = CLOBBERED (holds copy of input a)
;                pv_mul_nibble  = CLOBBERED
;
; Clobbers: A, X, Y, polyval_acc, pv_mul_input, pv_mul_nibble
; Cycles:   18774 (SHORT, measured)
; IRQ-safe: no
; Reentrant: no
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

; pv_mul_input lives in zero page ($20-$2F); pv_mul_nibble lives in zero
; page ($30) - see constants_lib.asm. Shared ZP slots with LONG profile so
; the ABI is identical. pv_mul_byte_idx was used by earlier unrolled
; multiply; the fused Tier 1 hot path no longer needs it.

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
; Cycles:   353 when nibble != 0, ~5 for the fast skip
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
; Entry:
;   A, X, Y      n/a
;   memory       polyval_acc    = current accumulator
;                polyval_temp   = 16-byte block to absorb
;                polyval_htable = already built by polyval_precompute_table
;
; Exit:
;   A, X, Y      undefined
;   memory       polyval_acc    = (old acc XOR polyval_temp) * H
;                polyval_temp   = preserved
;                pv_mul_input   = clobbered
;                pv_mul_nibble  = clobbered
;
; Clobbers: A, X, Y, polyval_acc, pv_mul_input, pv_mul_nibble
; Cycles:   ~19000 (SHORT, dominated by polyval_multiply)
; IRQ-safe: no
; Reentrant: no
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
