; =============================================================================
; consumer_stub.s - Downstream-consumer import rehearsal.
;
; This file simulates what a downstream project (c64-wireguard, c64-https,
; ...) would do to use the library: include the two public .inc files,
; import the public ZP and routine surface, and call a handful of entry
; points. It deliberately touches ONLY the public API -- no lib internals,
; no lib .s files. If this file assembles + links against lib_only.cfg,
; the library ABI is stable enough for external consumers.
;
; Build: make consumer-check
; =============================================================================

.include "constants_lib.inc"
.include "polyval_api.inc"

; --- c64-lib-contract §1: version constants -------------------------------
; Imported so the linker pulls lib_version.o out of the (future P5) archive
; per the c64-x25519 forced-extraction pattern. .word references below.
.import LIB_VERSION_MAJOR
.import LIB_VERSION_MINOR
.import LIB_VERSION_PATCH
.import LIB_ABI_VERSION

; ZP slot equates (polyval_acc, polyval_zp_ptr, polyval_aes_*, ...) come from
; constants_lib.inc → zp_config.s as pure equates with ZP_CONFIG_NO_EXPORTS=1.
; They're addresses, not external symbols, so .importzp would collide. When
; P5 lands the .a archive, this file's link path will need to drop the
; constants_lib.inc include and switch to .importzp from the archive instead.

.import polyval_init
.import polyval_multiply
.import polyval_update
.import aes_encrypt_block
.import gcmsiv_encrypt
.import gcmsiv_decrypt

.export consumer_entry

.segment "LOADADDR"
        .word   $4000

.segment "CODE"

consumer_entry:
        jsr     polyval_init
        jsr     polyval_multiply
        jsr     polyval_update
        jsr     aes_encrypt_block
        jsr     gcmsiv_encrypt
        jsr     gcmsiv_decrypt
        rts

; --- Forced archive-member extraction tables ------------------------------
; .word for 16-bit version equates (ca65 can't prove they fit in a byte until
; link). Linker resolves these against the archive, pulling lib_version.o
; into the final image. ZP slot extraction will be added in P5 when the
; .include path is replaced by .importzp from the archive.
.segment "RODATA"

public_version_refs:
        .word   LIB_VERSION_MAJOR, LIB_VERSION_MINOR
        .word   LIB_VERSION_PATCH, LIB_ABI_VERSION
