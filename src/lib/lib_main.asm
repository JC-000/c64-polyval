; =============================================================================
; lib/lib_main.asm - Library-only assembly wrapper
;
; This is NOT the demo app entry point (that's src/main.asm). This file is
; the canonical "is the library self-contained?" check: it !source's only
; files under src/lib/ and deliberately omits every app-side file
; (boot.asm, constants_app.asm, strings.asm, disk_io.asm, display.asm,
; main_loop.asm, gcm_siv_ui.asm, data_app.asm).
;
; If a library file accidentally references an app-side symbol (e.g. chrout,
; input_buffer, a PETSCII string label) this build will fail with an
; unresolved-symbol error. That failure IS the test: the library directory
; is self-contained iff this file assembles.
;
; Build:
;   acme -I src -DPOLYVAL_PROFILE=2 -f cbm -o build/polyval_lib.prg \
;        --vicelabels build/lib_labels.txt src/lib/lib_main.asm
;
; (The -I src flag is required because lib/polyval.asm sources its
; profile-specific backend via "lib/polyval_long.asm", which is resolved
; relative to the ACME include search path. The demo build achieves the
; same by invoking ACME from src/ with main.asm as the top-level file.)
;
; The produced PRG is not a runnable C64 program — it has no BASIC stub and
; no entry routine. Its existence is the verification.
; =============================================================================

        !cpu 6502

; --- Equates (no code emitted) ---
!source "lib/constants_lib.asm"
!source "lib/polyval_api.asm"

; --- Library code + data origin ---
; Neutral, high-memory origin that does not collide with BASIC ROM
; ($A000-$BFFF) or KERNAL ($E000-$FFFF). A host integration would pick its
; own origin; this is only for the standalone verification build.
!ifndef POLYVAL_LIB_ORIGIN { POLYVAL_LIB_ORIGIN = $4000 }
        * = POLYVAL_LIB_ORIGIN

; --- Code modules ---
!source "lib/aes_encrypt.asm"
!source "lib/aes_decrypt.asm"
!source "lib/polyval.asm"
!source "lib/gcm_siv.asm"

; --- Data and tables ---
!source "lib/data.asm"
!source "lib/tables.asm"
