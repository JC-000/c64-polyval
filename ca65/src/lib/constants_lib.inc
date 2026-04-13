; =============================================================================
; lib/constants_lib.inc - Library equates (POLYVAL, AES, GCM-SIV) - ca65 port
;
; No code emitted. Pure equates. No KERNAL / PETSCII / hardware references.
;
; This is the ca65 equivalent of src/lib/constants_lib.asm. Ported mechanically:
; `!ifndef X { X = $val }` becomes `.ifndef X / X = $val / .endif`.
;
; Zero-page symbols declared here are *values only* (addresses). The actual
; `.res` reservations + `.exportzp` live in data.s, which must pick these
; equates up by `.include`ing this file before declaring the ZP segment.
; =============================================================================

.ifndef CONSTANTS_LIB_INC_
CONSTANTS_LIB_INC_ = 1

; ---------------------------------------------------------------------------
; Zero-page variables used by library code.
; Each ZP equate is wrapped in .ifndef so a host can pre-define its own ZP
; layout before .include'ing this file. Defaults preserve the standalone
; demo-app layout.
; ---------------------------------------------------------------------------
.ifndef zp_ptr
    zp_ptr       = $fb              ; 2-byte pointer
.endif
.ifndef zp_temp
    zp_temp      = $fd              ; temp storage
.endif
.ifndef zp_count
    zp_count     = $fe              ; loop counter
.endif
.ifndef zp_ptr2
    zp_ptr2      = $02              ; second pointer (2 bytes)
.endif
.ifndef zp_round
    zp_round     = $04              ; aes round counter
.endif
.ifndef zp_col
    zp_col       = $05              ; aes column counter
.endif
.ifndef zp_tmp1
    zp_tmp1      = $06              ; aes temp
.endif
.ifndef zp_tmp2
    zp_tmp2      = $07              ; aes temp
.endif
.ifndef zp_tmp3
    zp_tmp3      = $08              ; aes temp
.endif
.ifndef zp_tmp4
    zp_tmp4      = $09              ; aes temp
.endif
.ifndef polyval_acc
    polyval_acc  = $10              ; 16-byte POLYVAL accumulator ($10-$1F)
.endif
.ifndef pv_mul_input
    pv_mul_input = $20              ; 16-byte multiply input scratch ($20-$2F)
.endif
.ifndef pv_mul_nibble
    pv_mul_nibble = $30             ; 1-byte nibble param for polyval_xor_table_entry
.endif

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
