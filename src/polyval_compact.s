; =============================================================================
; polyval_compact.s - POLYVAL GF(2^128) universal hash (RFC 8452), COMPACT
;                     profile: size-optimised rolled Shoup-4 back-end.
;
; Algorithm: POLYVAL(H, X_1..X_s) where S_0=0, S_i = dot(S_{i-1} XOR X_i, H)
; Polynomial: x^128 + x^127 + x^126 + x^121 + 1
;
; Same mathematics, same 256-byte table and same public symbol set as the
; SHORT profile (src/polyval_short.s) — the difference is entirely in the
; unrolling. SHORT emits 32 straight-line nibble steps and a fully unrolled
; table build; COMPACT rolls both back into loops.
;
; Why a third profile (issue #51, filed from c64-aes256-ecdsa#27): SHORT's
; multiply assembles to 13,614 bytes and LONG carries 8,448 bytes of tables,
; so on a stock C64 — ~38 KB below the $A000-$BFFF BASIC ROM window —
; selecting either can decide whether the consumer's image collides with the
; ROM window at all. That is a memory-map decision, not a size preference,
; and its failure mode is the CPU executing BASIC ROM rather than a build
; error. The consumer that filed it calls POLYVAL rarely, so this back-end
; optimises for size and lets cycles go.
;
; Strategy: 4-bit nibble table lookup with LEFT-shift processing, identical
; to SHORT. Table is precomputed from H' = H * x^{-128} using left-shift
; doubling.
;
; Left-shift reduction (x^128 mod p): byte[0] ^= $01, byte[15] ^= $C2
; Right-shift reduction (x^{-1} mod p): byte[15] ^= $E1
;
; Register-preservation contracts match SHORT and LONG exactly, including
; where preserving costs a stack round-trip: a consumer swapping profiles
; must not have to re-read the per-routine Exit blocks. §5 of API.md is the
; global convention; the deviations that would otherwise arise here (the
; rolled loops need an index register the unrolled versions did not) are
; paid for rather than documented away.
;
; Loop-control note, load-bearing throughout: INX / DEX / INY / DEY do NOT
; affect the carry flag, while CPX / CPY do. Every 128-bit shift below
; therefore chains its carry through a loop terminated by DEX/BPL or by a
; second counter in the other index register — never by a compare.
; =============================================================================

.include "constants_lib.inc"

; ZP symbols (polyval_acc, pv_mul_input, pv_mul_nibble) come in as numeric
; equates from constants_lib.inc. ca65 emits 2-byte ZP addressing
; automatically for operands in $00..$FF resolvable at encode time.

; Absolute (non-ZP) symbols from data.s.
.import polyval_h
.import polyval_temp
.import polyval_htable

.export polyval_init
.export polyval_double
.export polyval_right_shift_1
.export polyval_shift_left_4
.export polyval_precompute_table
.export polyval_multiply
.export polyval_xor_table_entry
.export polyval_update
.export polyval_finalize

.segment "LIB_POLYVAL_COMPACT_CODE"

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
; Rolled equivalent of the SHORT profile's 16 straight-line ROLs: X walks
; the accumulator LSB -> MSB while Y counts the 16 bytes down, because
; neither INX nor DEY disturbs the carry the ROL chain is threading. A
; CPX #16 here would silently break the propagation.
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_acc = 128-bit value to double
;   flags        none required
;
; Exit:
;   A            reduction constant if branch taken, else undefined
;   X, Y         preserved
;   memory       polyval_acc = input * x (mod POLYVAL reduction polynomial)
;   flags        undefined - do NOT rely on C/Z/N
;
; Clobbers: A, polyval_acc
; Cycles:   282 (measured)
; IRQ-safe: no
; Reentrant: no
; =============================================================================
polyval_double:
        txa
        pha
        tya
        pha
        clc
        ldx #0
        ldy #16
@shift:
        rol polyval_acc,x
        inx
        dey
        bne @shift
        bcc @no_reduce
        ; XOR with left-shift reduction: byte[0] ^= $01, byte[15] ^= $C2
        lda polyval_acc
        eor #$01
        sta polyval_acc
        lda polyval_acc+15
        eor #$c2
        sta polyval_acc+15
@no_reduce:
        pla
        tay
        pla
        tax
        rts

; =============================================================================
; polyval_right_shift_1 - right-shift 128-bit value at polyval_acc by 1 bit
; If bit 0 was set, XOR with right-shift reduction: byte[15] ^= $E1.
;
; No longer used internally (polyval_precompute_table uses the mulX_POLYVAL
; identity on polyval_temp), but retained as a public callable routine so
; test_polyval_direct.py can still exercise it.
;
; Descending X with DEX/BPL: the carry falling from byte k into byte k-1 is
; the loop's own state, so the terminator must leave C alone.
;
; Clobbers: A, polyval_acc.  X, Y preserved.
; =============================================================================
polyval_right_shift_1:
        txa
        pha
        lda polyval_acc
        and #$01
        pha                     ; save "LSB fell off" for the reduction test
        clc
        ldx #15
@shift:
        ror polyval_acc,x
        dex
        bpl @shift
        pla
        beq @no_reduce
        lda polyval_acc+15
        eor #$e1
        sta polyval_acc+15
@no_reduce:
        pla
        tax
        rts

; =============================================================================
; polyval_shift_left_4 - multiply the accumulator by x^4 in GF(2^128)
;
; Four polyval_double calls. The SHORT profile fuses these into one
; straight-line sequence for speed; here the JSR overhead is the trade.
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
; Cycles:   1064 (measured)
; IRQ-safe: no
; Reentrant: no
; =============================================================================
polyval_shift_left_4:
        tya
        pha
        ldy #4
@loop:
        jsr polyval_double
        dey
        bne @loop
        pla
        tay
        rts

; =============================================================================
; polyval_xor_table_entry - XOR the selected 4-bit H-table entry into the
;                           accumulator
;
; Entry:
;   A, X, Y      n/a
;   memory       pv_mul_nibble  = table index (0..15)
;                polyval_htable = built by polyval_precompute_table
;
; Exit:
;   A, Y         undefined
;   X            preserved
;   memory       polyval_acc ^= polyval_htable[pv_mul_nibble]
;                (no-op when pv_mul_nibble == 0)
;
; Clobbers: A, Y, polyval_acc
; Cycles:   363 when nibble != 0 (measured), ~7 for the fast skip
; IRQ-safe: no
; Reentrant: no
; =============================================================================
polyval_xor_table_entry:
        lda pv_mul_nibble
        beq @skip               ; htable[0] is all zeros
        asl
        asl
        asl
        asl                     ; A = nibble * 16
        tay                     ; Y = offset into htable
        txa
        pha                     ; X is the caller's byte index (see multiply)
        ldx #0
@loop:
        lda polyval_acc,x
        eor polyval_htable,y
        sta polyval_acc,x
        iny
        inx
        cpx #16
        bne @loop
        pla
        tax
@skip:
        rts

; =============================================================================
; polyval_multiply - multiply polyval_acc by H in GF(2^128) (COMPACT profile)
;
; Algorithm: result = 0; for i = 15 downto 0:
;   result <<= 4 (with reduction); result ^= htable[byte_high_nibble]
;   result <<= 4 (with reduction); result ^= htable[byte_low_nibble]
;
; Uses LEFT-shift-by-4 with the table built from H' = H * x^{-128}, so the
; result is acc * H' = acc * H * x^{-128} = dot(acc, H). Like SHORT, this
; profile uses only the 256-byte polyval_htable (no htable8 / reduce8
; slices).
;
; X holds the byte index across the whole nibble loop; every callee below
; preserves it, which is why polyval_shift_left_4 and
; polyval_xor_table_entry pay for their stack round-trips.
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
; Cycles:   49657 (COMPACT, measured)
; IRQ-safe: no
; Reentrant: no
; =============================================================================
polyval_multiply:
        ; Stash the operand and clear the accumulator in one pass.
        ldx #15
@save:
        lda polyval_acc,x
        sta pv_mul_input,x
        lda #0
        sta polyval_acc,x
        dex
        bpl @save

        ; Bytes MSB (byte 15) -> LSB (byte 0), high nibble first.
        ldx #15
@byte:
        lda pv_mul_input,x
        lsr
        lsr
        lsr
        lsr
        jsr pv_mul_step
        lda pv_mul_input,x
        and #$0f
        jsr pv_mul_step
        dex
        bpl @byte
        rts

; One nibble step: acc = (acc * x^4) XOR htable[A]. Entry A = nibble (0..15).
; Preserves X. Routed through the public polyval_xor_table_entry so
; pv_mul_nibble keeps exactly the meaning its own contract gives it.
pv_mul_step:
        sta pv_mul_nibble
        jsr polyval_shift_left_4
        jmp polyval_xor_table_entry

; polyval_acc ^= polyval_temp (16 bytes). Shared: the cold precompute path
; folds H*x^-k into H', the hot polyval_update folds the block into the
; accumulator. Clobbers A, X.
pv_xor_temp_acc:
        ldx #15
@loop:
        lda polyval_acc,x
        eor polyval_temp,x
        sta polyval_acc,x
        dex
        bpl @loop
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
; Cycles:   ~49950 (COMPACT, dominated by polyval_multiply)
; IRQ-safe: no
; Reentrant: no
; =============================================================================
polyval_update:
        jsr pv_xor_temp_acc
        jmp polyval_multiply

; =============================================================================
; polyval_finalize - result is already in polyval_acc
; =============================================================================
polyval_finalize:
        rts

; =============================================================================
; COLD PATH — everything below this line runs once per H-key install and may
; be page-overlaid afterwards (c64-lib-contract §5 COLD_BYTES). It is placed
; last in the segment so the overlayable region is contiguous and ends at the
; segment end; the steady-state polyval_update / polyval_multiply path above
; reads only the populated polyval_htable, never this code.
; =============================================================================

; =============================================================================
; polyval_precompute_table - build the 4-bit Shoup window from polyval_h
;
; Step 1: mulX_POLYVAL(H) -> H' = H * x^-128, via the RFC 8452 identity
;
;       x^-128 = 1 + x^-1 + x^-2 + x^-7   (in the POLYVAL field)
;   =>  H * x^-128 = H XOR (H*x^-1) XOR (H*x^-2) XOR (H*x^-7)
;
;   Each H*x^-k is k successive right-shifts of H with POLYVAL right-shift
;   reduction (byte[15] ^= $e1 when the LSB falls off), so 7 single-bit
;   shifts plus 3 full-width XORs replace 128 iterations.
;
; Step 2: build the Shoup-4 window htable[0..15] with a rolled k-loop:
;   htable[0]    = 0
;   htable[1]    = H'
;   htable[2k]   = double(htable[k])          for k = 1..7
;   htable[2k+1] = htable[2k] XOR htable[1]
;
;   k ascending means htable[k] is always already built when it is read
;   (k=3 reads the entry k=1 wrote, k=5 the one k=2 wrote, and so on).
;   Each entry is 16 bytes; total table 256 bytes.
;
;   The doubling reuses polyval_double, which operates on polyval_acc, so
;   each iteration stages htable[k] through the accumulator. Byte offsets
;   fit in one index register because the table is 256 bytes: X carries
;   2k*16 + i and `polyval_htable+16,x` reaches (2k+1)*16 + i for free.
;
; Entry:
;   A, X, Y      n/a
;   memory       polyval_h = 128-bit hash key H
;
; Exit:
;   A, X, Y      undefined
;   memory       polyval_htable = 16 entries * 16 bytes
;                polyval_h      = PRESERVED (H' is built in polyval_acc;
;                                 hazmat audit D-1, issue #71)
;                polyval_acc, polyval_temp = CLOBBERED
;
; Clobbers: A, X, Y, polyval_acc, polyval_temp, polyval_htable
; Cycles:   10970 (COMPACT, measured)
; IRQ-safe: no
; Reentrant: no
; =============================================================================
polyval_precompute_table:
        ; -------------------------------------------------------------------
        ; Step 1: mulX_POLYVAL transform (H -> H' = H * x^-128)
        ; -------------------------------------------------------------------
        ; polyval_acc accumulates the running XOR and ends up holding H';
        ; polyval_temp is the value being shifted.
        ldx #15
@copy_h:
        lda polyval_h,x
        sta polyval_acc,x
        sta polyval_temp,x
        dex
        bpl @copy_h

        jsr pv_rshift_temp      ; temp = H*x^-1
        jsr pv_xor_temp_acc
        jsr pv_rshift_temp      ; temp = H*x^-2
        jsr pv_xor_temp_acc
        ldy #5
@to_x7:
        jsr pv_rshift_temp      ; five more -> temp = H*x^-7
        dey
        bne @to_x7
        jsr pv_xor_temp_acc

        ; polyval_acc now holds H' = H * x^-128.

        ; -------------------------------------------------------------------
        ; Step 2: rolled Shoup-4 table build
        ; -------------------------------------------------------------------
        ; htable[0] = 0
        lda #0
        ldx #15
@zero:
        sta polyval_htable,x
        dex
        bpl @zero

        ; htable[1] = H'
        ldx #15
@entry1:
        lda polyval_acc,x
        sta polyval_htable+16,x
        dex
        bpl @entry1

        ; polyval_temp is finished as a shift buffer; its first byte becomes
        ; the k-loop's source offset (k*16). It is already in this routine's
        ; documented clobber set, so no further ZP slot is claimed.
        lda #16                 ; k = 1
        sta polyval_temp
@build:
        ; polyval_acc = htable[k]
        ldx polyval_temp
        ldy #0
@load_k:
        lda polyval_htable,x
        sta polyval_acc,y
        inx
        iny
        cpy #16
        bne @load_k

        jsr polyval_double      ; acc = htable[k] * x

        ; htable[2k] = acc, htable[2k+1] = acc XOR htable[1]
        lda polyval_temp
        asl                     ; X = 2k*16 (k <= 7, so this cannot overflow)
        tax
        ldy #0
@store_2k:
        lda polyval_acc,y
        sta polyval_htable,x
        eor polyval_htable+16,y
        sta polyval_htable+16,x ; +16 lands on entry 2k+1
        inx
        iny
        cpy #16
        bne @store_2k

        lda polyval_temp
        clc
        adc #16
        sta polyval_temp
        cmp #128                ; stop after k = 7
        bne @build
        rts

; Precompute-only helper.
; polyval_temp >>= 1 with POLYVAL right-shift reduction (byte[15] ^= $e1).
; Clobbers A, X.
pv_rshift_temp:
        lda polyval_temp
        and #$01
        pha
        clc
        ldx #15
@shift:
        ror polyval_temp,x
        dex
        bpl @shift
        pla
        beq @no_reduce
        lda polyval_temp+15
        eor #$e1
        sta polyval_temp+15
@no_reduce:
        rts
