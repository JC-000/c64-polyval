; =============================================================================
; display.s - display_hex_block, print_hex_byte, print_hex_digit, print_string,
;             print_decimal (ca65 port of display.asm)
; =============================================================================

.include "constants_app.inc"
.include "constants_lib.inc"

.import decimal_flag

.export display_hex_block
.export print_hex_byte
.export print_hex_digit
.export print_string
.export print_decimal

.segment "CODE"

; =============================================================================
; display_hex_block - display bytes in hex format
; =============================================================================
display_hex_block:
        sta     polyval_zp_temp

@row_loop:
        ldx     polyval_zp_temp
@byte_loop:
        ldy     #0
        lda     (polyval_zp_ptr),y
        jsr     print_hex_byte

        lda     #$20
        jsr     chrout

        inc     polyval_zp_ptr
        bne     @no_carry
        inc     polyval_zp_ptr+1
@no_carry:

        dec     polyval_zp_count
        beq     @done

        dex
        bne     @byte_loop

        lda     #$0d
        jsr     chrout

        jmp     @row_loop

@done:
        lda     #$0d
        jsr     chrout
        rts

; =============================================================================
; print_hex_byte - print byte as two hex digits
; =============================================================================
print_hex_byte:
        pha

        lsr
        lsr
        lsr
        lsr
        jsr     print_hex_digit

        pla
        and     #$0f
        jsr     print_hex_digit

        rts

; =============================================================================
; print_hex_digit - print a single hex digit (0-15)
; =============================================================================
print_hex_digit:
        cmp     #10
        bcs     @letter
        clc
        adc     #'0'
        jmp     chrout
@letter:
        clc
        adc     #'A'-10
        jmp     chrout

; =============================================================================
; print_string - print null-terminated string
; =============================================================================
print_string:
        sta     polyval_zp_ptr
        sty     polyval_zp_ptr+1
        ldy     #0
@loop:
        lda     (polyval_zp_ptr),y
        beq     @done
        jsr     chrout
        iny
        bne     @loop
        inc     polyval_zp_ptr+1
        jmp     @loop
@done:
        rts

; =============================================================================
; print_decimal - print A as decimal number
; =============================================================================
print_decimal:
        ldx     #0
        stx     decimal_flag

        ; hundreds
        ldx     #0
@hundreds:
        cmp     #100
        bcc     @tens
        sbc     #100
        inx
        jmp     @hundreds
@tens:
        pha
        txa
        beq     @skip_hundreds
        ora     #$30
        jsr     chrout
        inc     decimal_flag
@skip_hundreds:
        pla

        ; tens
        ldx     #0
@tens_loop:
        cmp     #10
        bcc     @ones
        sbc     #10
        inx
        jmp     @tens_loop
@ones:
        pha
        txa
        bne     @print_tens
        lda     decimal_flag
        beq     @skip_tens
@print_tens:
        txa
        ora     #$30
        jsr     chrout
@skip_tens:
        pla

        ; ones
        ora     #$30
        jsr     chrout
        rts
