; =============================================================================
; boot.asm - BASIC stub and program entry point
; =============================================================================

; basic stub: 10 sys 2064
basic_stub:
        !word basic_end         ; pointer to next basic line
        !word 10                ; line number 10
        !byte $9e               ; sys token
        !text "2064"            ; address as ascii
        !byte 0                 ; end of line
basic_end:
        !word 0                 ; end of basic program

; =============================================================================
; main program entry point ($0810)
; =============================================================================
start:
        jsr clrscr              ; clear screen

        ; set uppercase/graphics mode (default)
        lda #$8e                ; chr$(142) = uppercase mode
        jsr chrout

        ; print title
        lda #<title_msg
        ldy #>title_msg
        jsr print_string

        ; clear keyboard buffer
        lda #0
        sta kbd_buffer

        ; print generating key message
        lda #<gen_key_msg
        ldy #>gen_key_msg
        jsr print_string

        ; zero out the key (will be loaded or set by test)
        ldx #0
        lda #0
@clear_key:
        sta key_data,x
        inx
        cpx #32
        bne @clear_key

        ; expand the key for aes
        lda #<expanding_msg
        ldy #>expanding_msg
        jsr print_string
        jsr aes_key_expansion

        ; clear input and output buffers
        jsr clear_buffers

        ; print instructions
        lda #<instructions_msg
        ldy #>instructions_msg
        jsr print_string

        ; enter main input loop
        jmp main_loop
