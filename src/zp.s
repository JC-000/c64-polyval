; ---------------------------------------------------------------------------
; zp.s - Zero-page allocations (demo app layer)
;
; Defines ZP symbols. Anything declared here lives in the ZEROPAGE segment
; (mapped to the ZP memory area by c64.cfg) and gets 2-byte (not 3-byte)
; addressing.
;
; Nothing here is exported. The library's consumer-facing ZP surface is
; src/zp_config.s (c64-lib-contract §2), whose slot names all carry the
; polyval_ / pv_ prefix registered to this library. Bare zp_* names are a
; cross-library collision class (c64-lib-contract #83; the #76 R2 prefix
; registry rules same-named slots across libraries a defect), so the old
; bare `zp_dummy` export was dropped — it was a pre-contract porting
; placeholder that no code ever imported.
; ---------------------------------------------------------------------------

.segment "ZEROPAGE"

zp_dummy:       .res 1          ; placeholder byte for downstream ports (local)
