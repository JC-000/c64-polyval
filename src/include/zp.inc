; ---------------------------------------------------------------------------
; zp.inc - Zero-page symbol template
;
; ca65 is one-pass: a forward reference to a symbol whose size is not yet
; known defaults to 3-byte absolute addressing. To keep ZP accesses at 2
; bytes, downstream code should either:
;   (a) define the symbol with ORG inside a ZEROPAGE segment before use, OR
;   (b) `.importzp` it (so the linker resolves it as a ZP symbol), OR
;   (c) prefix uses with `z:` (e.g. `lda z:polyval_acc`) to force ZP mode.
;
; This file is the canonical place to declare ZP symbols shared across the
; port. The skeleton defines only one dummy symbol so porters have a working
; template to copy.
; ---------------------------------------------------------------------------

.ifndef ZP_INC_
ZP_INC_ = 1

; Exported by zp.s
.globalzp zp_dummy

.endif ; ZP_INC_
