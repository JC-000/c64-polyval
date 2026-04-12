; =============================================================================
; data_app.asm - Demo-app mutable buffers
;
; Buffers owned by the demo UI / disk-IO layer. Split out of lib/data.asm
; in Phase 2 so the library translation unit only owns library state and
; third-party hosts don't inherit collisions on symbols like input_buffer.
; =============================================================================

; encryption staging buffers
input_buffer:
        !fill input_buf_size, 0

encrypt_buffer:
        !fill encrypt_buf_size, 0

input_length:
        !byte 0

encrypt_length:
        !byte 0

input_index:
        !byte 0

; disk I/O variables
drive_number:
        !byte 8

filename_buf:
        !fill 17, 0

actual_filename:
        !fill 17, 0

filename_len:
        !byte 0

filename_suffix:
        !byte 0

using_default_name:
        !byte 0

file_exists_flag:
        !byte 0

cmd_buffer:
        !fill 24, 0

write_fname_buf:
        !fill 32, 0

write_fname_len:
        !byte 0

read_fname_buf:
        !fill 32, 0

read_fname_len:
        !byte 0

key_read_buf:
        !fill 32, 0

decimal_flag:
        !byte 0

save_byte_index:
        !byte 0

read_byte_index:
        !byte 0

read_temp_byte:
        !byte 0

disk_error_code:
        !byte 0, 0

default_gcm_filename:
        !text "AESGCM"
        !byte 0
