; =============================================================================
; main.asm - AES-256-GCM-SIV + POLYVAL for Commodore 64
; Top-level assembly file. Build with:
;   acme -f cbm -o build/polyval.prg --vicelabels build/labels.txt src/main.asm
; =============================================================================

        !cpu 6502
; --- Constants and equates (no code emitted) ---
!source "constants.asm"

; --- Program origin ---
        * = $0801

; --- Code modules ---
!source "boot.asm"
!source "main_loop.asm"
!source "lib/aes_encrypt.asm"
!source "lib/aes_decrypt.asm"
!source "disk_io.asm"
!source "gcm_siv.asm"
!source "lib/polyval.asm"
!source "display.asm"

; --- Data and tables ---
!source "lib/data.asm"
!source "lib/tables.asm"
!source "strings.asm"
