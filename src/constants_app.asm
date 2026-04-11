; =============================================================================
; constants_app.asm - Demo application equates (KERNAL vectors, PETSCII)
; No code emitted. Pure equates.
; =============================================================================

; =============================================================================
; c64 system equates
; =============================================================================
chrout          = $ffd2         ; kernal: output character
getin           = $ffe4         ; kernal: get character from keyboard
chrin           = $ffcf         ; kernal: input character
clrscr          = $e544         ; basic rom: clear screen

; kernal disk i/o routines
setlfs          = $ffba         ; set logical file parameters
setnam          = $ffbd         ; set filename
open            = $ffc0         ; open logical file
close           = $ffc3         ; close logical file
chkin           = $ffc6         ; set input channel
chkout          = $ffc9         ; set output channel
clrchn          = $ffcc         ; clear i/o channels
readst          = $ffb7         ; read i/o status
load            = $ffd5         ; load file
save            = $ffd8         ; save file

kbd_buffer      = $c6           ; keyboard buffer count

; petscii codes
petscii_1       = $31           ; '1' key
petscii_2       = $32           ; '2' key
petscii_3       = $33           ; '3' key
petscii_4       = $34           ; '4' key
petscii_5       = $35           ; '5' key
petscii_q       = $51           ; 'q' key
petscii_return  = $0d           ; return key
