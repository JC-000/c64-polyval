; =============================================================================
; consumer_stub_shipped.s — the c64-lib-contract §6.1 shipped-surface guard.
;
; This stub simulates a consumer who has ONLY what `make lib` puts in
; build/lib/:
;
;   polyval.a              the archive
;   polyval.inc            the consumer-facing header
;   polyval-example.cfg    the example ld65 config
;
; `make consumer-check-shipped` copies exactly those three files plus this
; stub into an otherwise empty scratch directory and assembles there with
; **no `-I src`**, so any reachback into the repo's source tree is a hard
; failure rather than something that quietly works for us and breaks for a
; consumer. That is the whole point: the library's own builds always have
; src/ on the include path, so they cannot detect an incomplete shipped
; surface. Only a link performed without src/ can.
;
; It exists because build/lib/ held the archive ALONE from the first
; archive target through v0.9.0 (issue #79) — §6.1 requires the header and
; the example cfg too, and nothing in the build could see they were
; missing. This target is what makes that regression visible.
;
; Deliberately NOT `.include`d: src/constants_lib.inc. A consumer who links
; the archive does not vendor our source, and does not need it — the ZP
; slots arrive by `.importzp` from the archive's zp_config.o (SPEC §2), and
; the buffers and entry points by `.import` from its data.o. Vendoring
; consumers who DO include constants_lib.inc are covered by the separate
; test/consumer_stub.s. If this file ever needs constants_lib.inc to
; assemble, the shipped surface is incomplete and that is the finding.
;
; Not vendored into the release tarball (tools/build_release.sh ships src/
; and docs only), same as the other two consumer stubs.
; =============================================================================

.setcpu "6502"

; The ONLY include. Resolved from the scratch directory, not from src/.
.include "polyval.inc"

; --- §1 version identification -----------------------------------------------
; Prefixed forms only. A consumer composing two contract libraries builds
; both with -D LIB_NO_BARE_EXPORTS=1 and never touches the bare names, so
; this stub does not import them either.
.import LIB_POLYVAL_VERSION_MAJOR
.import LIB_POLYVAL_VERSION_MINOR
.import LIB_POLYVAL_VERSION_PATCH
.import LIB_POLYVAL_ABI_VERSION

; --- §5 aggregate manifest ---------------------------------------------------
.import LIB_POLYVAL_ZP_USAGE_BYTES
.import LIB_POLYVAL_REU_BANKS_USED
.import LIB_POLYVAL_RESIDENT_BYTES
.import LIB_POLYVAL_COLD_BYTES

; --- §5 published input bound (issue #80) ------------------------------------
; The reason this symbol exists: before it, a consumer standing exactly
; where this stub stands could not learn the 64-byte ceiling from anything
; they had been shipped, and had to hard-code it from prose.
.import LIB_POLYVAL_GCMSIV_MAX_PT_LEN

; --- §2 zero page ------------------------------------------------------------
; .importzp, not an include — these come from the archive's zp_config.o.
.importzp polyval_acc
.importzp pv_mul_input
.importzp polyval_zp_ptr

; --- Public entry points and buffers -----------------------------------------
; NOT hand-written imports, deliberately, as of v0.10.1. Everything called
; below is declared by `polyval.inc` itself via `.global`. That is the
; point of this section: through v0.10.0 this stub listed 27 `.import`
; lines, and the fact that it had to was the evidence that the shipped
; header declared nothing while `API.md` and the Makefile both described
; it as the consumer's "declaration of the public symbols". If the header
; ever stops declaring the public surface, this file stops assembling.
;
; The §1 and §5 equates above ARE still imported explicitly: they are
; manifest surface, not API surface, and the header deliberately does not
; declare them.

; --- Link-time gates ---------------------------------------------------------
; .assert/lderror, never .if/.error: an .import'ed symbol has no value until
; link, so an .if-based gate fails to assemble with "Constant expression
; expected" (SPEC §1). These are the guards the example cfg's trailing
; comment recommends, exercised for real so the recommendation is tested
; rather than merely written down.
MY_MAX_MESSAGE = 32

.assert LIB_POLYVAL_ABI_VERSION = 1, lderror, "c64-polyval exported-surface generation changed; re-check the integration"
.assert LIB_POLYVAL_VERSION_MAJOR = 0, lderror, "c64-polyval 0.x expected"
.assert LIB_POLYVAL_REU_BANKS_USED = 0, lderror, "c64-polyval claims REU banks it should not"
.assert LIB_POLYVAL_ZP_USAGE_BYTES > 0, lderror, "c64-polyval ZP usage not published"
.assert LIB_POLYVAL_COLD_BYTES < LIB_POLYVAL_RESIDENT_BYTES, lderror, "COLD should be a carve-out of RESIDENT here"
.assert MY_MAX_MESSAGE <= LIB_POLYVAL_GCMSIV_MAX_PT_LEN, lderror, "message longer than c64-polyval accepts"

; The 2-byte PRG load address, exactly as a real consumer's startup code
; emits it. Present so this link produces ZERO ld65 warnings: the example
; cfg declares LOADADDR non-optional on purpose (silently dropping the load
; header would make a consumer's .prg load at the wrong address), so a stub
; that omitted the segment would warn here forever and train a reader to
; ignore warnings from this guard.
.segment "LOADADDR"
        .word $0801

.segment "CODE"

; A plausible call sequence. Never executed — the produced .prg is a link
; artifact, not a runnable program — but it must ASSEMBLE and LINK, which
; is what proves the shipped surface is complete and correctly typed.
consumer_entry:
        ; §5 bound used as an immediate. The `#<` is load-bearing: an
        ; .import'ed symbol has no assemble-time value, so a bare
        ; `lda #LIB_POLYVAL_GCMSIV_MAX_PT_LEN` is a ca65 "Range error"
        ; (ca65 cannot prove it fits in a byte). Documented in API.md §9.4
        ; because it is the first thing a consumer hits.
        lda #<LIB_POLYVAL_GCMSIV_MAX_PT_LEN
        sta gcmsiv_pt_len

        ; POLYVAL direct: install H, precompute, absorb one block.
        jsr polyval_init
        jsr polyval_precompute_table
        jsr polyval_update
        jsr polyval_multiply

        ; AES-256 direct.
        jsr aes_key_expansion
        jsr aes_encrypt_block
        jsr aes_decrypt_block

        ; AEAD round trip. Both entry points report through A/Z, and above
        ; the published bound both reject with A=1 / Z=0 (issue #70).
        jsr gcmsiv_encrypt
        bne @done                    ; A=1 -> length rejected
        jsr gcmsiv_decrypt
        bne @done                    ; A=1 -> tag invalid or length rejected
        lda polyval_acc
        ora pv_mul_input
        ora polyval_zp_ptr
        sta gcmsiv_dec_buf
@done:
        rts
