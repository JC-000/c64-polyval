; =============================================================================
; consumer_stub.s - example downstream consumer of c64-polyval v0.1.0
;
; This file demonstrates the minimum boilerplate required for a downstream
; C64 project to use the c64-polyval library. It deliberately imports ONLY
; the stable v0.1.x ABI (via abi_v1.inc) - no test probes, no internals.
;
; Build this file with the adjacent consumer.cfg and polyval_long.lib:
;
;     ca65 --cpu 6502 -I . consumer_stub.s -o consumer_stub.o
;     ld65 -C consumer.cfg -o consumer.prg consumer_stub.o polyval_long.lib
;
; Replace `polyval_long.lib` with `polyval_short.lib` to use the low-RAM
; profile instead.
; =============================================================================

.include "abi_v1.inc"
.include "constants_lib.inc"

; polyval_acc / pv_mul_input are plain ZP equates from constants_lib.inc; no
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
