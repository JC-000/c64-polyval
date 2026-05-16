; ---------------------------------------------------------------------------
; zp.s - Zero-page allocations
;
; Defines ZP symbols. Anything declared here lives in the ZEROPAGE segment
; (mapped to the ZP memory area by c64.cfg) and is exported as a ZP symbol
; so callers get 2-byte (not 3-byte) addressing.
; ---------------------------------------------------------------------------

.exportzp zp_dummy

.segment "ZEROPAGE"

zp_dummy:       .res 1          ; placeholder for downstream ports
