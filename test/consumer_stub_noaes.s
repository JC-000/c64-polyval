; =============================================================================
; consumer_stub_noaes.s - POLYVAL-only consumer rehearsal (issue #47 guard).
;
; Simulates a downstream project that already ships its OWN AES and GCM-SIV
; (c64-aes256-ecdsa is the motivating consumer) and wants POLYVAL alone from
; polyval-long.a / polyval-short.a.
;
; The point of this stub is the definitions below: it DEFINES aes_state and
; gcmsiv_tag itself. If the POLYVAL-only archives ever again ship the AES /
; GCM-SIV BSS block out of the monolithic data.o, ld65 fails this link with
; "Duplicate external identifier" -- which is exactly how issue #47 presented.
;
; Build: make consumer-check-noaes  (links against the real .a, not objects)
; =============================================================================

; --- Symbols the consumer owns. Must NOT come from a POLYVAL-only archive. ---
.export aes_state
.export gcmsiv_tag

.segment "BSS"
aes_state:   .res 16, 0
gcmsiv_tag:  .res 16, 0

; --- The POLYVAL surface the consumer actually wants ------------------------
; .forceimport so ld65 extracts the archive members even though this stub
; emits no calling code; a plain .import of an unreferenced symbol is dropped
; by ca65 and would leave the archive unlinked (and the guard toothless).
.forceimport polyval_init
.forceimport polyval_update
.forceimport polyval_multiply
.forceimport polyval_precompute_table
.forceimport polyval_double
.forceimport polyval_finalize

; c64-lib-contract §1 + §5: prefixed exports must survive in the NO_AES
; archives too. Bare LIB_VERSION_* aliases are deliberately NOT imported --
; a POLYVAL-only consumer composing several contract libraries builds with
; LIB_NO_BARE_EXPORTS=1 and must not depend on them.
.forceimport LIB_POLYVAL_VERSION_MAJOR
.forceimport LIB_POLYVAL_ABI_VERSION
.forceimport LIB_POLYVAL_RESIDENT_BYTES
.forceimport LIB_POLYVAL_COLD_BYTES

.segment "LOADADDR"
.word $4000
