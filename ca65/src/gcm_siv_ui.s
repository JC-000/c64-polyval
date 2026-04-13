; =============================================================================
; gcm_siv_ui.s - GCM-SIV demo UI wrappers and disk I/O helpers
;                (ca65 port of gcm_siv_ui.asm)
;
; Depends on lib/gcm_siv.s (gcmsiv_encrypt/decrypt), KERNAL, app strings.
; Mechanical port: anonymous `@local` labels preserved as-is.
; =============================================================================

.include "constants_app.inc"
.include "lib/constants_lib.inc"

; --- Library symbols ---
.import gcmsiv_encrypt
.import gcmsiv_decrypt
.import gcmsiv_nonce
.import gcmsiv_pt_buf
.import gcmsiv_pt_len
.import gcmsiv_ct_buf
.import gcmsiv_dec_buf
.import gcmsiv_tag
.import gcmsiv_tag_valid

; --- Display helpers ---
.import print_string
.import print_decimal
.import display_hex_block

; --- UI strings ---
.import gcmsiv_prompt_msg
.import no_input_msg
.import gcmsiv_encrypting_msg
.import bytes_msg
.import gcmsiv_nonce_msg
.import gcmsiv_ciphertext_msg
.import gcmsiv_tag_msg
.import gcmsiv_done_msg
.import instructions_msg
.import gcmsiv_no_data_msg
.import gcmsiv_decrypting_msg
.import gcmsiv_tag_fail_msg
.import gcmsiv_tag_ok_msg
.import gcmsiv_pt_hex_msg
.import gcmsiv_decrypt_done_msg
.import drive_prompt_msg
.import using_drive_msg
.import gcm_filename_prompt_msg
.import file_exists_msg
.import incremented_msg
.import names_exhausted_msg
.import enter_new_name_msg
.import saving_gcm_msg
.import save_success_msg
.import save_error_msg
.import load_gcm_filename_prompt
.import loading_gcm_msg
.import file_not_found_msg
.import gcm_load_success_msg
.import load_error_msg

; --- Disk I/O helpers ---
.import get_input_line
.import copy_input_to_filename
.import set_default_filename
.import increment_filename
.import print_filename
.import check_file_exists
.import build_write_filename
.import build_read_filename
.import write_hex_digit
.import read_hex_char

; --- App data ---
.import input_index
.import filename_buf
.import drive_number
.import using_default_name
.import file_exists_flag
.import write_fname_buf
.import write_fname_len
.import read_fname_buf
.import read_fname_len
.import save_byte_index
.import read_byte_index
.import read_temp_byte

.export do_gcm_siv_encrypt
.export do_gcm_siv_decrypt
.export do_save_gcm_siv
.export do_load_gcm_siv
.export get_gcmsiv_input
.export save_gcmsiv_to_disk
.export load_gcmsiv_from_disk

.segment "CODE"

; =============================================================================
; do_gcm_siv_encrypt - encrypt text using AES-256-GCM-SIV mode
; =============================================================================
do_gcm_siv_encrypt:
        lda     #$0d
        jsr     chrout

        ; print prompt
        lda     #<gcmsiv_prompt_msg
        ldy     #>gcmsiv_prompt_msg
        jsr     print_string

        ; get input text
        jsr     get_gcmsiv_input

        ; check if we got any input
        lda     gcmsiv_pt_len
        bne     @has_input

        lda     #<no_input_msg
        ldy     #>no_input_msg
        jsr     print_string
        jmp     @done

@has_input:
        ; show plaintext length
        lda     #<gcmsiv_encrypting_msg
        ldy     #>gcmsiv_encrypting_msg
        jsr     print_string
        lda     gcmsiv_pt_len
        jsr     print_decimal
        lda     #<bytes_msg
        ldy     #>bytes_msg
        jsr     print_string

        ; generate random 12-byte nonce (zeroed; test harness sets it)
        ldx     #0
        lda     #0
@clear_nonce:
        sta     gcmsiv_nonce,x
        inx
        cpx     #12
        bne     @clear_nonce

        ; show nonce
        lda     #<gcmsiv_nonce_msg
        ldy     #>gcmsiv_nonce_msg
        jsr     print_string

        lda     #<gcmsiv_nonce
        sta     zp_ptr
        lda     #>gcmsiv_nonce
        sta     zp_ptr+1
        lda     #12
        sta     zp_count
        lda     #12
        jsr     display_hex_block

        ; perform GCM-SIV encryption
        jsr     gcmsiv_encrypt

        ; show ciphertext
        lda     #<gcmsiv_ciphertext_msg
        ldy     #>gcmsiv_ciphertext_msg
        jsr     print_string

        lda     #<gcmsiv_ct_buf
        sta     zp_ptr
        lda     #>gcmsiv_ct_buf
        sta     zp_ptr+1
        lda     gcmsiv_pt_len
        sta     zp_count
        lda     #8
        jsr     display_hex_block

        ; show authentication tag
        lda     #<gcmsiv_tag_msg
        ldy     #>gcmsiv_tag_msg
        jsr     print_string

        lda     #<gcmsiv_tag
        sta     zp_ptr
        lda     #>gcmsiv_tag
        sta     zp_ptr+1
        lda     #16
        sta     zp_count
        lda     #16
        jsr     display_hex_block

        lda     #<gcmsiv_done_msg
        ldy     #>gcmsiv_done_msg
        jsr     print_string

@done:
        lda     #<instructions_msg
        ldy     #>instructions_msg
        jsr     print_string
        rts

; =============================================================================
; get_gcmsiv_input - get plaintext input for GCM-SIV encryption
; =============================================================================
get_gcmsiv_input:
        ; clear buffer
        ldx     #0
        lda     #0
@clear:
        sta     gcmsiv_pt_buf,x
        inx
        cpx     #64
        bne     @clear

        lda     #0
        sta     gcmsiv_pt_len

@input_loop:
        jsr     getin
        beq     @input_loop

        cmp     #petscii_return
        beq     @input_done

        cmp     #$14                    ; delete
        beq     @do_delete

        ; check buffer not full
        ldx     gcmsiv_pt_len
        cpx     #63
        bcs     @input_loop

        ; store character
        sta     gcmsiv_pt_buf,x
        inc     gcmsiv_pt_len

        jsr     chrout
        jmp     @input_loop

@do_delete:
        ldx     gcmsiv_pt_len
        beq     @input_loop
        dex
        stx     gcmsiv_pt_len
        lda     #0
        sta     gcmsiv_pt_buf,x
        lda     #$14
        jsr     chrout
        jmp     @input_loop

@input_done:
        lda     #$0d
        jsr     chrout
        rts



; =============================================================================
; do_gcm_siv_decrypt - decrypt ciphertext using AES-256-GCM-SIV mode
; =============================================================================
do_gcm_siv_decrypt:
        lda     #$0d
        jsr     chrout

        lda     gcmsiv_pt_len
        bne     @has_data

        lda     #<gcmsiv_no_data_msg
        ldy     #>gcmsiv_no_data_msg
        jsr     print_string
        jmp     @done

@has_data:
        lda     #<gcmsiv_decrypting_msg
        ldy     #>gcmsiv_decrypting_msg
        jsr     print_string

        ; perform GCM-SIV decryption
        jsr     gcmsiv_decrypt

        ; Check tag verification result
        lda     gcmsiv_tag_valid
        bne     @tag_ok

        lda     #<gcmsiv_tag_fail_msg
        ldy     #>gcmsiv_tag_fail_msg
        jsr     print_string
        jmp     @done

@tag_ok:
        lda     #<gcmsiv_tag_ok_msg
        ldy     #>gcmsiv_tag_ok_msg
        jsr     print_string

        ; show decrypted plaintext as hex
        lda     #<gcmsiv_pt_hex_msg
        ldy     #>gcmsiv_pt_hex_msg
        jsr     print_string

        lda     #<gcmsiv_dec_buf
        sta     zp_ptr
        lda     #>gcmsiv_dec_buf
        sta     zp_ptr+1
        lda     gcmsiv_pt_len
        sta     zp_count
        lda     #8
        jsr     display_hex_block

        lda     #<gcmsiv_decrypt_done_msg
        ldy     #>gcmsiv_decrypt_done_msg
        jsr     print_string

@done:
        lda     #<instructions_msg
        ldy     #>instructions_msg
        jsr     print_string
        rts



; =============================================================================
; do_save_gcm_siv - save GCM-SIV encrypted data to disk
; =============================================================================
do_save_gcm_siv:
        lda     #$0d
        jsr     chrout

        lda     gcmsiv_pt_len
        bne     @has_data

        lda     #<gcmsiv_no_data_msg
        ldy     #>gcmsiv_no_data_msg
        jsr     print_string
        jmp     @done

@has_data:
        ; get drive number
        lda     #<drive_prompt_msg
        ldy     #>drive_prompt_msg
        jsr     print_string

        jsr     get_input_line
        lda     input_index
        beq     @use_default_drive

        lda     filename_buf
        sec
        sbc     #$30
        cmp     #10
        bcs     @use_default_drive
        sta     drive_number
        jmp     @got_drive

@use_default_drive:
        lda     #8
        sta     drive_number

@got_drive:
        lda     #<using_drive_msg
        ldy     #>using_drive_msg
        jsr     print_string
        lda     drive_number
        jsr     print_decimal
        lda     #$0d
        jsr     chrout

        ; get filename
        lda     #<gcm_filename_prompt_msg
        ldy     #>gcm_filename_prompt_msg
        jsr     print_string

        jsr     get_input_line
        lda     input_index
        beq     @use_default_name

        jsr     copy_input_to_filename
        lda     #0
        sta     using_default_name
        jmp     @got_filename

@use_default_name:
        jsr     set_default_filename
        lda     #1
        sta     using_default_name

@got_filename:
        jsr     check_file_exists
        lda     file_exists_flag
        beq     @do_save

        lda     #<file_exists_msg
        ldy     #>file_exists_msg
        jsr     print_string

        lda     using_default_name
        beq     @prompt_new_name

        jsr     increment_filename
        bcs     @names_exhausted

        lda     #<incremented_msg
        ldy     #>incremented_msg
        jsr     print_string
        jsr     print_filename
        lda     #$0d
        jsr     chrout
        jmp     @got_filename

@names_exhausted:
        lda     #<names_exhausted_msg
        ldy     #>names_exhausted_msg
        jsr     print_string
        jmp     @done

@prompt_new_name:
        lda     #<enter_new_name_msg
        ldy     #>enter_new_name_msg
        jsr     print_string

        jsr     get_input_line
        lda     input_index
        beq     @do_save
        jsr     copy_input_to_filename
        jmp     @got_filename

@do_save:
        lda     #<saving_gcm_msg
        ldy     #>saving_gcm_msg
        jsr     print_string
        jsr     print_filename
        lda     #$0d
        jsr     chrout

        jsr     save_gcmsiv_to_disk
        bcs     @save_error

        lda     #<save_success_msg
        ldy     #>save_success_msg
        jsr     print_string
        jmp     @done

@save_error:
        lda     #<save_error_msg
        ldy     #>save_error_msg
        jsr     print_string

@done:
        lda     #<instructions_msg
        ldy     #>instructions_msg
        jsr     print_string
        rts

; =============================================================================
; do_load_gcm_siv - load GCM-SIV encrypted data from disk
; =============================================================================
do_load_gcm_siv:
        lda     #$0d
        jsr     chrout

        lda     #<drive_prompt_msg
        ldy     #>drive_prompt_msg
        jsr     print_string

        jsr     get_input_line
        lda     input_index
        beq     @use_default_drive

        lda     filename_buf
        sec
        sbc     #$30
        cmp     #10
        bcs     @use_default_drive
        sta     drive_number
        jmp     @got_drive

@use_default_drive:
        lda     #8
        sta     drive_number

@got_drive:
        lda     #<using_drive_msg
        ldy     #>using_drive_msg
        jsr     print_string
        lda     drive_number
        jsr     print_decimal
        lda     #$0d
        jsr     chrout

        lda     #<load_gcm_filename_prompt
        ldy     #>load_gcm_filename_prompt
        jsr     print_string

        jsr     get_input_line
        lda     input_index
        beq     @use_default_name

        jsr     copy_input_to_filename
        lda     #0
        sta     using_default_name
        jmp     @got_filename

@use_default_name:
        jsr     set_default_filename
        lda     #1
        sta     using_default_name

@got_filename:
        jsr     check_file_exists
        lda     file_exists_flag
        bne     @do_load

        lda     #<file_not_found_msg
        ldy     #>file_not_found_msg
        jsr     print_string
        jsr     print_filename
        lda     #$0d
        jsr     chrout
        jmp     @done

@do_load:
        lda     #<loading_gcm_msg
        ldy     #>loading_gcm_msg
        jsr     print_string
        jsr     print_filename
        lda     #$0d
        jsr     chrout

        jsr     load_gcmsiv_from_disk
        bcs     @load_error

        lda     #<gcm_load_success_msg
        ldy     #>gcm_load_success_msg
        jsr     print_string
        jmp     @done

@load_error:
        lda     #<load_error_msg
        ldy     #>load_error_msg
        jsr     print_string

@done:
        lda     #<instructions_msg
        ldy     #>instructions_msg
        jsr     print_string
        rts

; =============================================================================
; save_gcmsiv_to_disk - save nonce, tag, length, and ciphertext as hex
; =============================================================================
save_gcmsiv_to_disk:
        jsr     build_write_filename

        lda     write_fname_len
        ldx     #<write_fname_buf
        ldy     #>write_fname_buf
        jsr     setnam

        lda     #3
        ldx     drive_number
        ldy     #3
        jsr     setlfs

        jsr     open
        bcc     @open_ok
        jmp     @error
@open_ok:

        ldx     #3
        jsr     chkout
        bcc     @chkout_ok
        jmp     @close_error
@chkout_ok:

        ; write nonce (12 bytes as hex)
        lda     #0
        sta     save_byte_index
@write_nonce:
        ldx     save_byte_index
        cpx     #12
        beq     @nonce_done
        lda     gcmsiv_nonce,x
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     write_hex_digit
        pla
        and     #$0f
        jsr     write_hex_digit
        lda     #$20
        jsr     chrout
        inc     save_byte_index
        jmp     @write_nonce
@nonce_done:
        lda     #$0d
        jsr     chrout

        ; write tag (16 bytes as hex)
        lda     #0
        sta     save_byte_index
@write_tag:
        ldx     save_byte_index
        cpx     #16
        beq     @tag_done
        lda     gcmsiv_tag,x
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     write_hex_digit
        pla
        and     #$0f
        jsr     write_hex_digit
        lda     #$20
        jsr     chrout
        inc     save_byte_index
        jmp     @write_tag
@tag_done:
        lda     #$0d
        jsr     chrout

        ; write length (1 byte as hex)
        lda     gcmsiv_pt_len
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     write_hex_digit
        pla
        and     #$0f
        jsr     write_hex_digit
        lda     #$0d
        jsr     chrout

        ; write ciphertext
        lda     #0
        sta     save_byte_index
@write_ct:
        ldx     save_byte_index
        cpx     gcmsiv_pt_len
        beq     @ct_done
        lda     gcmsiv_ct_buf,x
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     write_hex_digit
        pla
        and     #$0f
        jsr     write_hex_digit
        lda     #$20
        jsr     chrout
        lda     save_byte_index
        and     #$07
        cmp     #$07
        bne     @no_newline
        lda     #$0d
        jsr     chrout
@no_newline:
        inc     save_byte_index
        jmp     @write_ct
@ct_done:

        jsr     readst
        bne     @close_error

        jsr     clrchn
        lda     #3
        jsr     close
        clc
        rts

@close_error:
        jsr     clrchn
        lda     #3
        jsr     close
@error:
        sec
        rts

; =============================================================================
; load_gcmsiv_from_disk - load nonce, tag, length, and ciphertext
; =============================================================================
load_gcmsiv_from_disk:
        jsr     build_read_filename

        lda     read_fname_len
        ldx     #<read_fname_buf
        ldy     #>read_fname_buf
        jsr     setnam

        lda     #4
        ldx     drive_number
        ldy     #4
        jsr     setlfs

        jsr     open
        bcc     @open_ok
        jmp     @error
@open_ok:

        ldx     #4
        jsr     chkin
        bcc     @chkin_ok
        jmp     @close_error
@chkin_ok:

        ; read nonce (12 bytes)
        lda     #0
        sta     read_byte_index
@read_nonce:
        lda     read_byte_index
        cmp     #12
        beq     @nonce_done
        jsr     read_hex_char
        bcc     @nonce_ok1
        jmp     @close_error
@nonce_ok1:
        asl
        asl
        asl
        asl
        sta     read_temp_byte
        jsr     read_hex_char
        bcc     @nonce_ok2
        jmp     @close_error
@nonce_ok2:
        ora     read_temp_byte
        ldx     read_byte_index
        sta     gcmsiv_nonce,x
        inc     read_byte_index
        jmp     @read_nonce
@nonce_done:

        ; read tag (16 bytes)
        lda     #0
        sta     read_byte_index
@read_tag:
        lda     read_byte_index
        cmp     #16
        beq     @tag_done
        jsr     read_hex_char
        bcc     @tag_ok1
        jmp     @close_error
@tag_ok1:
        asl
        asl
        asl
        asl
        sta     read_temp_byte
        jsr     read_hex_char
        bcc     @tag_ok2
        jmp     @close_error
@tag_ok2:
        ora     read_temp_byte
        ldx     read_byte_index
        sta     gcmsiv_tag,x
        inc     read_byte_index
        jmp     @read_tag
@tag_done:

        ; read length (1 byte)
        jsr     read_hex_char
        bcc     @len_ok1
        jmp     @close_error
@len_ok1:
        asl
        asl
        asl
        asl
        sta     read_temp_byte
        jsr     read_hex_char
        bcc     @len_ok2
        jmp     @close_error
@len_ok2:
        ora     read_temp_byte
        sta     gcmsiv_pt_len

        ; read ciphertext
        lda     #0
        sta     read_byte_index
@read_ct:
        lda     read_byte_index
        cmp     gcmsiv_pt_len
        beq     @ct_done
        jsr     read_hex_char
        bcs     @ct_done
        asl
        asl
        asl
        asl
        sta     read_temp_byte
        jsr     read_hex_char
        bcs     @ct_done
        ora     read_temp_byte
        ldx     read_byte_index
        sta     gcmsiv_ct_buf,x
        inc     read_byte_index
        jmp     @read_ct
@ct_done:

        jsr     clrchn
        lda     #4
        jsr     close
        clc
        rts

@close_error:
        jsr     clrchn
        lda     #4
        jsr     close
@error:
        sec
        rts
