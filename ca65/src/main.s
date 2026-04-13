; =============================================================================
; main.s - Top-level entry point for c64-polyval (ca65 port)
;
; ca65 equivalent of src/main.asm. Under ACME, main.asm was a dispatcher
; that !source'd every library + app file into a single translation unit.
; Under ca65 each file is compiled separately and the linker resolves
; cross-file references, so main.s no longer needs to enumerate source
; files. Its only jobs are:
;
;   1. Own the LOADADDR segment so ld65 writes the 2-byte PRG header.
;   2. Serve as a convenient place to document the app-level file layout:
;
;        boot.s           BASIC stub + start:          (STARTUP segment)
;        main_loop.s      menu dispatch                (CODE)
;        disk_io.s        file I/O helpers             (CODE)
;        display.s        hex display routines         (CODE)
;        gcm_siv_ui.s     GCM-SIV demo UI              (CODE)
;        strings.s        PETSCII UI message strings   (RODATA)
;        data_app.s       mutable app buffers          (BSS + DATA)
;        constants_app.inc  KERNAL/PETSCII equates (no code emitted)
;
;      plus everything under ca65/src/lib/ for the library itself.
;
; No code is emitted from this file; see boot.s for the BASIC stub and the
; `start` entry point.
; =============================================================================

; --- BASIC load address header --------------------------------------------
; ld65 emits these two bytes as the first two bytes of the .prg. The rest of
; the file starts at $0801 (owned by boot.s's STARTUP segment).
.segment "LOADADDR"
        .word   $0801
