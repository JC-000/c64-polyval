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

; polyval_acc / pv_mul_input are plain equates from constants_lib.inc; no
; .importzp is needed. Referencing them below (e.g. `lda polyval_acc`) will
; assemble as ZP addressing automatically.

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
