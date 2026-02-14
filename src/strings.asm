; =============================================================================
; strings.asm - UI message strings
; =============================================================================

title_msg:
        !byte $93
        !text "*** AES-256-GCM-SIV + POLYVAL ***"
        !byte $0d
        !text "RFC 8452 IMPLEMENTATION"
        !byte $0d, $0d, 0

gen_key_msg:
        !text "INITIALIZING KEY..."
        !byte $0d, 0

expanding_msg:
        !text "EXPANDING KEY..."
        !byte $0d, $0d, 0

instructions_msg:
        !byte $0d
        !text "1=GCM-ENC 2=GCM-DEC"
        !byte $0d
        !text "3=GCM-SAVE 4=GCM-LOAD"
        !byte $0d
        !text "Q=QUIT"
        !byte $0d, 0

no_input_msg:
        !text "NO INPUT PROVIDED."
        !byte $0d, 0

exit_msg:
        !byte $0d
        !text "*** PROGRAM ENDED ***"
        !byte $0d, 0

bytes_msg:
        !text " BYTES"
        !byte $0d, 0

gcmsiv_prompt_msg:
        !byte $0d
        !text "ENTER TEXT FOR GCM-SIV ENCRYPTION:"
        !byte $0d, 0

gcmsiv_encrypting_msg:
        !text "ENCRYPTING "
        !byte 0

gcmsiv_nonce_msg:
        !text "NONCE (12 BYTES):"
        !byte $0d, 0

gcmsiv_ciphertext_msg:
        !text "CIPHERTEXT:"
        !byte $0d, 0

gcmsiv_tag_msg:
        !text "AUTH TAG (16 BYTES):"
        !byte $0d, 0

gcmsiv_done_msg:
        !byte $0d
        !text "GCM-SIV ENCRYPTION COMPLETE."
        !byte $0d, 0

gcmsiv_no_data_msg:
        !text "NO GCM-SIV CIPHERTEXT TO DECRYPT."
        !byte $0d
        !text "USE OPTION 1 TO ENCRYPT FIRST."
        !byte $0d, 0

gcmsiv_decrypting_msg:
        !text "DECRYPTING GCM-SIV CIPHERTEXT..."
        !byte $0d, 0

gcmsiv_pt_hex_msg:
        !text "DECRYPTED (HEX):"
        !byte $0d, 0

gcmsiv_decrypt_done_msg:
        !byte $0d
        !text "GCM-SIV DECRYPTION COMPLETE."
        !byte $0d, 0

gcmsiv_tag_ok_msg:
        !text "*** TAG VERIFIED OK ***"
        !byte $0d, 0

gcmsiv_tag_fail_msg:
        !byte $0d
        !text "*** TAG VERIFICATION FAILED! ***"
        !byte $0d
        !text "DATA MAY BE CORRUPTED/TAMPERED!"
        !byte $0d, 0

drive_prompt_msg:
        !text "DRIVE NUMBER (8): "
        !byte 0

using_drive_msg:
        !text "USING DRIVE "
        !byte 0

gcm_filename_prompt_msg:
        !text "FILENAME (AESGCM): "
        !byte 0

file_exists_msg:
        !byte $0d
        !text "FILE ALREADY EXISTS!"
        !byte $0d, 0

incremented_msg:
        !text "TRYING: "
        !byte 0

enter_new_name_msg:
        !text "ENTER NEW FILENAME: "
        !byte 0

names_exhausted_msg:
        !byte $0d
        !text "ALL DEFAULT NAMES TAKEN (0-9)!"
        !byte $0d
        !text "PLEASE SPECIFY A CUSTOM NAME."
        !byte $0d, 0

saving_gcm_msg:
        !byte $0d
        !text "SAVING GCM-SIV DATA TO: "
        !byte 0

save_success_msg:
        !text "FILE SAVED SUCCESSFULLY."
        !byte $0d, 0

save_error_msg:
        !text "ERROR SAVING FILE!"
        !byte $0d, 0

load_gcm_filename_prompt:
        !text "FILENAME TO LOAD (AESGCM): "
        !byte 0

loading_gcm_msg:
        !byte $0d
        !text "LOADING GCM-SIV DATA FROM: "
        !byte 0

gcm_load_success_msg:
        !text "GCM-SIV DATA LOADED SUCCESSFULLY!"
        !byte $0d
        !text "USE OPTION 2 TO DECRYPT."
        !byte $0d, 0

load_error_msg:
        !text "ERROR LOADING FILE!"
        !byte $0d, 0

file_not_found_msg:
        !byte $0d
        !text "FILE NOT FOUND: "
        !byte 0
