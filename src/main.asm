; =============================================================================
; main.asm - AES-256-GCM-SIV + POLYVAL for Commodore 64 (demo app entry)
; Top-level assembly file. Build with:
;   acme -f cbm -o build/polyval.prg --vicelabels build/labels.txt src/main.asm
;
; Library / demo separation:
;   src/lib/*.asm   - Reusable POLYVAL + AES + GCM-SIV primitives. These
;                     files must NOT set an absolute origin (no `* =`,
;                     no !pseudopc, no !org). They assemble at whatever
;                     program counter the host assembly has set before
;                     !source'ing them, which makes the library drop-in
;                     linkable into third-party C64 projects.
;   src/*.asm       - Demo app (boot, UI, disk I/O, display, strings).
;                     `* = $0801` below is the ONLY origin binding in the
;                     tree and belongs to the demo app, not the library.
; =============================================================================

        !cpu 6502
; --- Constants and equates (no code emitted) ---
!source "lib/constants_lib.asm"
!source "constants_app.asm"

; --- Program origin (demo app only; library files inherit this *) ---
        * = $0801

; --- Code modules ---
!source "boot.asm"
!source "main_loop.asm"
!source "lib/aes_encrypt.asm"
!source "lib/aes_decrypt.asm"
!source "disk_io.asm"
!source "lib/gcm_siv.asm"
!source "gcm_siv_ui.asm"
!source "lib/polyval.asm"
!source "display.asm"

; --- Data and tables ---
!source "lib/data.asm"
!source "data_app.asm"
!source "lib/tables.asm"
!source "strings.asm"
