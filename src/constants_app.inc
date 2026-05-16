; =============================================================================
; constants_app.inc - Demo application equates (KERNAL vectors, PETSCII) - ca65
;
; ca65 port of src/constants_app.asm. Pure equates; no code emitted. Guarded
; against multiple inclusion so any .s file can .include it freely.
; =============================================================================

.ifndef CONSTANTS_APP_INC_
CONSTANTS_APP_INC_ = 1

; ---------------------------------------------------------------------------
; C64 system equates
; ---------------------------------------------------------------------------
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

; buffer sizes for demo-app input/encryption staging
input_buf_size   = 64           ; max input text size
encrypt_buf_size = 80           ; encrypted output size (input + up to 16 pad)

; petscii codes
petscii_1       = $31           ; '1' key
petscii_2       = $32           ; '2' key
petscii_3       = $33           ; '3' key
petscii_4       = $34           ; '4' key
petscii_5       = $35           ; '5' key
petscii_q       = $51           ; 'q' key
petscii_return  = $0d           ; return key

.endif ; CONSTANTS_APP_INC_
