; =============================================================================
; main_loop.asm - Main menu dispatcher
; =============================================================================

; =============================================================================
; main_loop - wait for keypress and handle commands
; =============================================================================
main_loop:
        ; clear keyboard buffer
        lda #0
        sta kbd_buffer

@wait_key:
        jsr getin               ; get key from buffer
        beq @wait_key           ; no key, keep waiting

        ; check for '1' - encrypt with GCM-SIV
        cmp #petscii_1
        beq @gcm_siv_encrypt

        ; check for '2' - decrypt with GCM-SIV
        cmp #petscii_2
        beq @gcm_siv_decrypt

        ; check for '3' - save GCM-SIV to disk
        cmp #petscii_3
        beq @save_gcm_siv

        ; check for '4' - load GCM-SIV from disk
        cmp #petscii_4
        beq @load_gcm_siv

        ; check for 'q' or 'Q' - quit
        cmp #petscii_q          ; uppercase Q
        beq @quit
        cmp #$71                ; lowercase q (shifted)
        beq @quit

        ; unknown key, keep waiting
        jmp @wait_key

@gcm_siv_encrypt:
        jsr do_gcm_siv_encrypt
        jmp main_loop

@gcm_siv_decrypt:
        jsr do_gcm_siv_decrypt
        jmp main_loop

@save_gcm_siv:
        jsr do_save_gcm_siv
        jmp main_loop

@load_gcm_siv:
        jsr do_load_gcm_siv
        jmp main_loop

@quit:
        jsr cleanup
        rts                     ; return to basic

; =============================================================================
; cleanup - print exit message
; =============================================================================
cleanup:
        lda #<exit_msg
        ldy #>exit_msg
        jsr print_string
        rts
