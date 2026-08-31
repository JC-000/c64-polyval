; =============================================================================
; lib/constants_lib.inc - Library equates (POLYVAL, AES, GCM-SIV) - ca65 port
;
; No code emitted. Pure equates. No KERNAL / PETSCII / hardware references.
;
; This is the ca65 equivalent of src/lib/constants_lib.asm. Ported mechanically:
; `!ifndef X { X = $val }` becomes `.ifndef X / X = $val / .endif`.
;
; Zero-page slot equates are now declared in src/zp_config.s per
; c64-lib-contract SPEC.md §2 (zero-page contract). We pull them in via
; `.include "zp_config.s"` below, suppressing the dedicated file's
; `.exportzp` block (ZP_CONFIG_NO_EXPORTS=1) so the exports land in exactly
; one translation unit (zp_config.o), not in every consumer of this header.
; =============================================================================

.ifndef CONSTANTS_LIB_INC_
CONSTANTS_LIB_INC_ = 1

; ---------------------------------------------------------------------------
; Zero-page variables: pulled from zp_config.s. The .exportzp directives
; only fire when zp_config.s is assembled as its own translation unit.
; ---------------------------------------------------------------------------
; Guarded so a consumer can pass `-D ZP_CONFIG_NO_EXPORTS=1` on the ca65
; command line -- the documented supplies-own-slots route -- without a hard
; "Symbol already defined" in every TU that includes this header. Every
; library TU includes it, so an unguarded assignment made that route
; unusable rather than merely redundant (issue #50; c64-x25519#99 is the
; same defect, fixed there in v0.11.1). The default remains 1: these
; equates are baked per-TU, and the `.exportzp` block fires only when
; zp_config.s is assembled as its own translation unit.
.ifndef ZP_CONFIG_NO_EXPORTS
ZP_CONFIG_NO_EXPORTS = 1
.endif
.include "zp_config.s"

; ---------------------------------------------------------------------------
; AES constants
; ---------------------------------------------------------------------------
aes_block_size        = 16          ; 128 bits = 16 bytes
aes_key_size          = 32          ; 256 bits = 32 bytes
aes_rounds            = 14          ; aes-256 uses 14 rounds
aes_expanded_key_size = 240         ; (14+1) * 16 = 240 bytes

; GCM-SIV per-call plaintext/ciphertext limit. gcmsiv_pt_buf / _ct_buf /
; _dec_buf are gcmsiv_max_pt_len bytes each; gcmsiv_encrypt and
; gcmsiv_decrypt reject gcmsiv_pt_len > gcmsiv_max_pt_len with A=1 / Z=0
; (issue #70) instead of reading past the buffers.
gcmsiv_max_pt_len     = 64

; ---------------------------------------------------------------------------
; POLYVAL build profile selector
;
; SHORT:   4-bit Shoup table with Tier 1 unrolling. Best for RFC 8452 GCM-SIV
;          short messages (H rederived per message).
; LONG:    Shoup 8-bit fused shift+reduce+htable. Best for long-message /
;          session-stable-H workloads (TLS 1.3, WireGuard).
; COMPACT: 4-bit Shoup table, rolled. Same table and same mathematics as
;          SHORT with the unrolling traded back for cycles. Best for
;          memory-bound consumers that call POLYVAL rarely and cannot spend
;          ~12 KB on it — on a stock C64 the choice can decide whether the
;          image collides with the $A000-$BFFF ROM window (issue #51).
;
; Define POLYVAL_PROFILE on the ca65 command line via -D POLYVAL_PROFILE=2.
; Default: LONG.
;
; The value is a member-set axis (c64-lib-contract SPEC §6.3): it selects
; which multiply object is *archived*, so it must be set as a make variable
; (`make POLYVAL_PROFILE=compact`), not through CONTRACT_DEFINES.
; ---------------------------------------------------------------------------
POLYVAL_PROFILE_SHORT   = 1
POLYVAL_PROFILE_LONG    = 2
POLYVAL_PROFILE_COMPACT = 3
.ifndef POLYVAL_PROFILE
    POLYVAL_PROFILE = POLYVAL_PROFILE_LONG
.endif

; ---------------------------------------------------------------------------
; POLYVAL_LIB_MEM_BASE is an ACME-era concept (advance `*` to a fixed address
; before declaring buffers). Under ca65 the equivalent is segment placement
; via c64.cfg, so no PC-advance equate is emitted here. Segment alignment
; for the page-aligned htables lives in c64.cfg.
; ---------------------------------------------------------------------------

.endif ; CONSTANTS_LIB_INC_
