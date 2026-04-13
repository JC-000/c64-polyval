; =============================================================================
; test_probes.inc - INTERNAL test probes, NOT a stable ABI
;
; WARNING: The symbols in this file are exported by polyval_long.lib /
; polyval_short.lib for the benefit of the c64-polyval in-repo test suite
; (tools/test_polyval_direct.py, tools/test_gcmsiv_polyval.py). They exist
; so that the tests can drive inner helper routines directly and verify
; bit-level correctness.
;
; Consumers (downstream projects like c64-wireguard, c64-https, etc.) MUST
; NOT depend on any symbol in this file. These names may be renamed, have
; their calling conventions changed, be inlined away, or be removed in any
; v0.1.x point release without notice.
;
; If you find yourself wanting to import something from this header in a
; real application, file an issue upstream so the symbol can be evaluated
; for promotion to abi_v1.inc.
; =============================================================================

.ifndef POLYVAL_TEST_PROBES_INC_
POLYVAL_TEST_PROBES_INC_ = 1

; --- POLYVAL inner helpers (exercised by test_polyval_direct.py) -----------
.global polyval_double
.global polyval_right_shift_1
.global polyval_shift_left_4
.global polyval_xor_table_entry

; --- POLYVAL probe-only data (exercised by test_polyval_direct.py) ---------
.global polyval_htable          ; 256 B 4-bit Shoup table (read by tests)
; NOTE: pv_mul_nibble is a ZP equate from constants_lib.inc, not a
; linker-level symbol; tests reach it via its fixed ZP address.

; --- GCM-SIV inner composition steps (exercised by test_gcmsiv_polyval.py) -
.global gcmsiv_compute_tag_base
.global gcmsiv_finalize_tag
.global gcmsiv_ctr_encrypt
.global gcmsiv_ctr_decrypt

; --- GCM-SIV probe-only data (exercised by test_gcmsiv_polyval.py) ---------
.global gcmsiv_tag_acc          ; 16 B tag accumulator (read by tests)
.global gcmsiv_saved_key        ; 32 B AES key save slot (written by tests)
.global gcmsiv_saved_exp        ; 240 B expanded-key save slot (written by tests)

.endif ; POLYVAL_TEST_PROBES_INC_
