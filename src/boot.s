; =============================================================================
; boot.s - BASIC stub + program entry point (ca65 port of boot.asm)
;
; The BASIC stub encodes the one-line program `10 SYS 2061`. 2061 = $080D,
; which is the address of `start:` given the stub layout below. ACME's
; original boot.asm had `SYS 2064` (a stale constant — the real start label
; was actually at $080D), but nobody noticed because the test harness drives
; `start` via JSR from the binary monitor rather than running the BASIC
; stub. We fix it to 2061 so the SYS hint actually matches the code.
;
; This file owns the STARTUP segment so ld65 places the stub first at $0801.
; =============================================================================

.include "constants_app.inc"

.import main_loop
.import print_string
.import aes_key_expansion
.import aes_current_key
.import title_msg
.import gen_key_msg
.import expanding_msg
.import instructions_msg

.export start

.segment "STARTUP"

; --- BASIC stub: 10 SYS 2061 ---
; Layout at $0801 (12 bytes total):
;   $0801: basic_stub   .word basic_end     (2 bytes)
;   $0803:              .word 10            (2 bytes)
;   $0805:              .byte $9e           (SYS token, 1 byte)
;   $0806:              "2061"              (4 bytes)
;   $080a:              .byte 0             (1 byte)
;   $080b: basic_end    .word 0             (2 bytes)
;   $080d: start:       ...
basic_stub:
        .word   basic_end           ; pointer to next basic line
        .word   10                  ; line number 10
        .byte   $9e                 ; sys token
        .byte   "2061"              ; address as ascii (= $080D)
        .byte   0                   ; end of line
basic_end:
        .word   0                   ; end of basic program

; =============================================================================
; main program entry point ($0810)
; =============================================================================
start:
        jsr     clrscr              ; clear screen

        ; set uppercase/graphics mode (default)
        lda     #$8e                ; chr$(142) = uppercase mode
        jsr     chrout

        ; print title
        lda     #<title_msg
        ldy     #>title_msg
        jsr     print_string

        ; clear keyboard buffer
        lda     #0
        sta     kbd_buffer

        ; print generating key message
        lda     #<gen_key_msg
        ldy     #>gen_key_msg
        jsr     print_string

        ; zero out the key (will be loaded or set by test)
        ldx     #0
        lda     #0
@clear_key:
        sta     aes_current_key,x
        inx
        cpx     #32
        bne     @clear_key

        ; expand the key for aes
        lda     #<expanding_msg
        ldy     #>expanding_msg
        jsr     print_string
        jsr     aes_key_expansion

        ; clear input and output buffers
        jsr     clear_buffers

        ; print instructions
        lda     #<instructions_msg
        ldy     #>instructions_msg
        jsr     print_string

        ; enter main input loop
        jmp     main_loop

; =============================================================================
; clear_buffers - clear demo-app input and encrypted buffers
; (App-level helper; lives outside the library.)
; =============================================================================
.export clear_buffers

.import input_buffer
.import encrypt_buffer
.import input_length
.import encrypt_length

.segment "CODE"

clear_buffers:
        lda     #0
        ldx     #0
@loop:
        sta     input_buffer,x
        sta     encrypt_buffer,x
        inx
        cpx     #input_buf_size
        bne     @loop
        sta     input_length            ; clear input length
        sta     encrypt_length          ; clear encrypted length
        rts
