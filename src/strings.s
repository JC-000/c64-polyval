; =============================================================================
; strings.s - UI message strings (ca65 port)
;
; All messages are null-terminated PETSCII, emitted read-only in RODATA.
; =============================================================================

.export title_msg
.export gen_key_msg
.export expanding_msg
.export instructions_msg
.export no_input_msg
.export exit_msg
.export bytes_msg
.export gcmsiv_prompt_msg
.export gcmsiv_encrypting_msg
.export gcmsiv_nonce_msg
.export gcmsiv_ciphertext_msg
.export gcmsiv_tag_msg
.export gcmsiv_done_msg
.export gcmsiv_no_data_msg
.export gcmsiv_decrypting_msg
.export gcmsiv_pt_hex_msg
.export gcmsiv_decrypt_done_msg
.export gcmsiv_tag_ok_msg
.export gcmsiv_tag_fail_msg
.export drive_prompt_msg
.export using_drive_msg
.export gcm_filename_prompt_msg
.export file_exists_msg
.export incremented_msg
.export enter_new_name_msg
.export names_exhausted_msg
.export saving_gcm_msg
.export save_success_msg
.export save_error_msg
.export load_gcm_filename_prompt
.export loading_gcm_msg
.export gcm_load_success_msg
.export load_error_msg
.export file_not_found_msg

.segment "RODATA"

title_msg:
        .byte   $93
        .byte   "*** AES-256-GCM-SIV + POLYVAL ***"
        .byte   $0d
        .byte   "RFC 8452 IMPLEMENTATION"
        .byte   $0d, $0d, 0

gen_key_msg:
        .byte   "INITIALIZING KEY..."
        .byte   $0d, 0

expanding_msg:
        .byte   "EXPANDING KEY..."
        .byte   $0d, $0d, 0

instructions_msg:
        .byte   $0d
        .byte   "1=GCM-ENC 2=GCM-DEC"
        .byte   $0d
        .byte   "3=GCM-SAVE 4=GCM-LOAD"
        .byte   $0d
        .byte   "Q=QUIT"
        .byte   $0d, 0

no_input_msg:
        .byte   "NO INPUT PROVIDED."
        .byte   $0d, 0

exit_msg:
        .byte   $0d
        .byte   "*** PROGRAM ENDED ***"
        .byte   $0d, 0

bytes_msg:
        .byte   " BYTES"
        .byte   $0d, 0

gcmsiv_prompt_msg:
        .byte   $0d
        .byte   "ENTER TEXT FOR GCM-SIV ENCRYPTION:"
        .byte   $0d, 0

gcmsiv_encrypting_msg:
        .byte   "ENCRYPTING "
        .byte   0

gcmsiv_nonce_msg:
        .byte   "NONCE (12 BYTES):"
        .byte   $0d, 0

gcmsiv_ciphertext_msg:
        .byte   "CIPHERTEXT:"
        .byte   $0d, 0

gcmsiv_tag_msg:
        .byte   "AUTH TAG (16 BYTES):"
        .byte   $0d, 0

gcmsiv_done_msg:
        .byte   $0d
        .byte   "GCM-SIV ENCRYPTION COMPLETE."
        .byte   $0d, 0

gcmsiv_no_data_msg:
        .byte   "NO GCM-SIV CIPHERTEXT TO DECRYPT."
        .byte   $0d
        .byte   "USE OPTION 1 TO ENCRYPT FIRST."
        .byte   $0d, 0

gcmsiv_decrypting_msg:
        .byte   "DECRYPTING GCM-SIV CIPHERTEXT..."
        .byte   $0d, 0

gcmsiv_pt_hex_msg:
        .byte   "DECRYPTED (HEX):"
        .byte   $0d, 0

gcmsiv_decrypt_done_msg:
        .byte   $0d
        .byte   "GCM-SIV DECRYPTION COMPLETE."
        .byte   $0d, 0

gcmsiv_tag_ok_msg:
        .byte   "*** TAG VERIFIED OK ***"
        .byte   $0d, 0

gcmsiv_tag_fail_msg:
        .byte   $0d
        .byte   "*** TAG VERIFICATION FAILED! ***"
        .byte   $0d
        .byte   "DATA MAY BE CORRUPTED/TAMPERED!"
        .byte   $0d, 0

drive_prompt_msg:
        .byte   "DRIVE NUMBER (8): "
        .byte   0

using_drive_msg:
        .byte   "USING DRIVE "
        .byte   0

gcm_filename_prompt_msg:
        .byte   "FILENAME (AESGCM): "
        .byte   0

file_exists_msg:
        .byte   $0d
        .byte   "FILE ALREADY EXISTS!"
        .byte   $0d, 0

incremented_msg:
        .byte   "TRYING: "
        .byte   0

enter_new_name_msg:
        .byte   "ENTER NEW FILENAME: "
        .byte   0

names_exhausted_msg:
        .byte   $0d
        .byte   "ALL DEFAULT NAMES TAKEN (0-9)!"
        .byte   $0d
        .byte   "PLEASE SPECIFY A CUSTOM NAME."
        .byte   $0d, 0

saving_gcm_msg:
        .byte   $0d
        .byte   "SAVING GCM-SIV DATA TO: "
        .byte   0

save_success_msg:
        .byte   "FILE SAVED SUCCESSFULLY."
        .byte   $0d, 0

save_error_msg:
        .byte   "ERROR SAVING FILE!"
        .byte   $0d, 0

load_gcm_filename_prompt:
        .byte   "FILENAME TO LOAD (AESGCM): "
        .byte   0

loading_gcm_msg:
        .byte   $0d
        .byte   "LOADING GCM-SIV DATA FROM: "
        .byte   0

gcm_load_success_msg:
        .byte   "GCM-SIV DATA LOADED SUCCESSFULLY!"
        .byte   $0d
        .byte   "USE OPTION 2 TO DECRYPT."
        .byte   $0d, 0

load_error_msg:
        .byte   "ERROR LOADING FILE!"
        .byte   $0d, 0

file_not_found_msg:
        .byte   $0d
        .byte   "FILE NOT FOUND: "
        .byte   0
