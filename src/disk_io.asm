; =============================================================================
; disk_io.asm - Disk I/O helpers: input, filename mgmt, hex conversion
; Related: constants.asm (Kernal I/O equates)
; =============================================================================

; =============================================================================
; get_input_line - get a line of input into filename_buf
; =============================================================================
get_input_line:
        lda #0
        sta input_index

        ldx #0
@clear:
        sta filename_buf,x
        inx
        cpx #17
        bne @clear

@loop:
        jsr getin
        beq @loop

        cmp #petscii_return
        beq @done

        cmp #$14                ; delete
        beq @delete

        ldx input_index
        cpx #16                 ; max 16 chars
        bcs @loop

        sta filename_buf,x
        inc input_index
        jsr chrout
        jmp @loop

@delete:
        ldx input_index
        beq @loop
        dex
        stx input_index
        lda #0
        sta filename_buf,x
        lda #$14
        jsr chrout
        jmp @loop

@done:
        lda #$0d
        jsr chrout
        rts

; =============================================================================
; copy_input_to_filename - copy filename_buf to actual_filename
; =============================================================================
copy_input_to_filename:
        ldx #0
@loop:
        lda filename_buf,x
        beq @done
        sta actual_filename,x
        inx
        cpx #16
        bne @loop
@done:
        stx filename_len
        rts

; =============================================================================
; set_default_filename - set filename to "AESGCM"
; =============================================================================
set_default_filename:
        ldx #0
@loop:
        lda default_gcm_filename,x
        sta actual_filename,x
        beq @done
        inx
        cpx #7
        bne @loop
@done:
        lda #0
        sta actual_filename,x
        lda #6
        sta filename_len
        lda #0
        sta filename_suffix
        rts

; =============================================================================
; increment_filename - increment the numeric suffix
; returns: carry set if exhausted (reached 9)
; =============================================================================
increment_filename:
        lda filename_suffix
        cmp #10
        bcs @exhausted

        inc filename_suffix
        lda filename_suffix

        clc
        adc #$2F                ; convert 1-10 to '0'-'9'
        ldx #6
        sta actual_filename,x
        lda #0
        sta actual_filename+7
        lda #7
        sta filename_len

        clc
        rts

@exhausted:
        sec
        rts

; =============================================================================
; print_filename - print the current filename
; =============================================================================
print_filename:
        ldx #0
@loop:
        lda actual_filename,x
        beq @done
        jsr chrout
        inx
        cpx #16
        bne @loop
@done:
        rts

; =============================================================================
; check_file_exists - check if file already exists on disk
; sets file_exists_flag (0 = no, 1 = yes)
; =============================================================================
check_file_exists:
        lda #0
        sta file_exists_flag

        jsr build_read_filename

        lda read_fname_len
        ldx #<read_fname_buf
        ldy #>read_fname_buf
        jsr setnam

        lda #2
        ldx drive_number
        ldy #2
        jsr setlfs

        jsr open
        bcs @not_found

        jsr check_disk_error
        bcs @close_not_found

        lda #1
        sta file_exists_flag

@close_not_found:
        jsr clrchn
        lda #2
        jsr close
        rts

@not_found:
        lda #0
        sta file_exists_flag
        rts

; =============================================================================
; check_disk_error - read error channel, return carry set if error
; =============================================================================
check_disk_error:
        lda #0
        ldx #<cmd_buffer
        ldy #>cmd_buffer
        jsr setnam

        lda #15
        ldx drive_number
        ldy #15
        jsr setlfs

        jsr open
        bcs @error

        ldx #15
        jsr chkin
        bcs @close_error

        jsr chrin
        sta disk_error_code

        jsr chrin
        sta disk_error_code+1

        jsr clrchn
        lda #15
        jsr close

        lda disk_error_code
        cmp #$30
        bne @is_error
        lda disk_error_code+1
        cmp #$30
        bne @is_error

        clc
        rts

@close_error:
        jsr clrchn
        lda #15
        jsr close
@error:
@is_error:
        sec
        rts

; =============================================================================
; write_hex_digit - write a hex digit (0-15) to output channel
; =============================================================================
write_hex_digit:
        cmp #10
        bcc @digit
        clc
        adc #($41 - 10)         ; 'A' - 10
        jmp chrout
@digit:
        clc
        adc #$30                ; '0'
        jmp chrout

; =============================================================================
; read_hex_char - read next hex character, skipping spaces/newlines
; returns: A = value 0-15, carry clear on success; carry set on error/EOF
; =============================================================================
read_hex_char:
@skip_loop:
        jsr chrin
        pha
        jsr readst
        and #$40                ; EOF?
        bne @eof
        pla

        cmp #$20                ; space
        beq @skip_loop
        cmp #$0d                ; carriage return
        beq @skip_loop
        cmp #$0a                ; line feed
        beq @skip_loop

        cmp #$30                ; '0'
        bcc @invalid
        cmp #$3a                ; '9' + 1
        bcc @is_digit

        cmp #$41                ; 'A'
        bcc @invalid
        cmp #$47                ; 'F' + 1
        bcc @is_upper

        cmp #$61                ; 'a'
        bcc @invalid
        cmp #$67                ; 'f' + 1
        bcs @invalid

        sec
        sbc #($61 - 10)
        clc
        rts

@is_upper:
        sec
        sbc #($41 - 10)
        clc
        rts

@is_digit:
        sec
        sbc #$30
        clc
        rts

@eof:
        pla
@invalid:
        sec
        rts

; =============================================================================
; build_write_filename - build "0:filename,s,w" in write_fname_buf
; =============================================================================
build_write_filename:
        lda #$30                ; '0'
        sta write_fname_buf
        lda #$3a                ; ':'
        sta write_fname_buf+1

        ldx #0
@copy:
        lda actual_filename,x
        beq @add_suffix
        sta write_fname_buf+2,x
        inx
        cpx #16
        bne @copy

@add_suffix:
        txa
        clc
        adc #2
        tay

        lda #$2c                ; ','
        sta write_fname_buf,y
        iny
        lda #$53                ; 'S'
        sta write_fname_buf,y
        iny
        lda #$2c                ; ','
        sta write_fname_buf,y
        iny
        lda #$57                ; 'W'
        sta write_fname_buf,y
        iny

        sty write_fname_len
        rts

; =============================================================================
; build_read_filename - build "0:filename,s,r" in read_fname_buf
; =============================================================================
build_read_filename:
        lda #$30                ; '0'
        sta read_fname_buf
        lda #$3a                ; ':'
        sta read_fname_buf+1

        ldx #0
@copy:
        lda actual_filename,x
        beq @add_suffix
        sta read_fname_buf+2,x
        inx
        cpx #16
        bne @copy

@add_suffix:
        txa
        clc
        adc #2
        tay

        lda #$2c                ; ','
        sta read_fname_buf,y
        iny
        lda #$53                ; 'S'
        sta read_fname_buf,y
        iny
        lda #$2c                ; ','
        sta read_fname_buf,y
        iny
        lda #$52                ; 'R'
        sta read_fname_buf,y
        iny

        sty read_fname_len
        rts

; =============================================================================
; verify_key_match - verify read key matches original
; returns: carry clear = match, carry set = mismatch
; =============================================================================
verify_key_match:
        ldx #0
@loop:
        lda key_data,x
        cmp key_read_buf,x
        bne @mismatch
        inx
        cpx #32
        bne @loop

        clc
        rts

@mismatch:
        sec
        rts
