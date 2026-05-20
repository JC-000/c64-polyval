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
ZP_CONFIG_NO_EXPORTS = 1
.include "zp_config.s"

; ---------------------------------------------------------------------------
; AES constants
; ---------------------------------------------------------------------------
aes_block_size        = 16          ; 128 bits = 16 bytes
aes_key_size          = 32          ; 256 bits = 32 bytes
aes_rounds            = 14          ; aes-256 uses 14 rounds
aes_expanded_key_size = 240         ; (14+1) * 16 = 240 bytes

; ---------------------------------------------------------------------------
; POLYVAL build profile selector
;
; SHORT: 4-bit Shoup table with Tier 1 unrolling. Best for RFC 8452 GCM-SIV
;        short messages (H rederived per message).
; LONG:  Shoup 8-bit fused shift+reduce+htable. Best for long-message /
;        session-stable-H workloads (TLS 1.3, WireGuard).
;
; Define POLYVAL_PROFILE on the ca65 command line via -D POLYVAL_PROFILE=2.
; Default: LONG.
; ---------------------------------------------------------------------------
POLYVAL_PROFILE_SHORT = 1
POLYVAL_PROFILE_LONG  = 2
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
