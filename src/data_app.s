; =============================================================================
; data_app.s - Demo-app mutable buffers (ca65 port)
;
; ca65 equivalent of src/data_app.asm. Buffers owned by the demo UI / disk-IO
; layer (NOT the library). Under ca65 these live in BSS for uninitialized
; reservations, with the single read-only `default_gcm_filename` string in
; RODATA.
; =============================================================================

.include "constants_app.inc"

.export input_buffer
.export encrypt_buffer
.export input_length
.export encrypt_length
.export input_index
.export drive_number
.export filename_buf
.export actual_filename
.export filename_len
.export filename_suffix
.export using_default_name
.export file_exists_flag
.export cmd_buffer
.export write_fname_buf
.export write_fname_len
.export read_fname_buf
.export read_fname_len
.export key_read_buf
.export decimal_flag
.export save_byte_index
.export read_byte_index
.export read_temp_byte
.export disk_error_code
.export default_gcm_filename

; ---------------------------------------------------------------------------
; BSS: uninitialized runtime buffers (ld65 reserves space, emits no bytes).
; ---------------------------------------------------------------------------
.segment "BSS"

input_buffer:       .res input_buf_size
encrypt_buffer:     .res encrypt_buf_size
input_length:       .res 1
encrypt_length:     .res 1
input_index:        .res 1

filename_buf:       .res 17
actual_filename:    .res 17
filename_len:       .res 1
filename_suffix:    .res 1
using_default_name: .res 1
file_exists_flag:   .res 1
cmd_buffer:         .res 24
write_fname_buf:    .res 32
write_fname_len:    .res 1
read_fname_buf:     .res 32
read_fname_len:     .res 1
key_read_buf:       .res 32
decimal_flag:       .res 1
save_byte_index:    .res 1
read_byte_index:    .res 1
read_temp_byte:     .res 1
disk_error_code:    .res 2

; ---------------------------------------------------------------------------
; DATA: initialized values. drive_number defaults to 8 (matches ACME
; `!byte 8`) so the UI still works before the user picks a drive.
; ---------------------------------------------------------------------------
.segment "DATA"

drive_number:       .byte 8

; ---------------------------------------------------------------------------
; RODATA: "AESGCM" default filename string.
; ---------------------------------------------------------------------------
.segment "RODATA"

default_gcm_filename:
        .byte   "AESGCM", 0
