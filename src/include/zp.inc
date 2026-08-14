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
; This file is the canonical place for a downstream port to declare ZP
; symbols shared across its own modules. Pattern for a port named "myport":
;
;   ; in the port's zp.s:      .exportzp myport_zp_scratch
;   ; in this include:         .globalzp myport_zp_scratch
;
; Prefix every exported slot with the port's own name: bare zp_* exports
; collide across c64-lib-contract libraries (contract #83), and the
; contract's ZP prefix registry (#76 R2) treats same-named slots in two
; libraries as a defect. The c64-polyval library's own slots are declared
; in src/zp_config.s under the registered polyval_ / pv_ prefixes.
; ---------------------------------------------------------------------------

.ifndef ZP_INC_
ZP_INC_ = 1

; (no live declarations — see the pattern above)

.endif ; ZP_INC_
