; =============================================================================
; constants.asm - System equates, zero page, AES constants
; No code emitted - pure equates only
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

; zero page variables
zp_ptr          = $fb           ; 2-byte pointer
zp_temp         = $fd           ; temp storage
zp_count        = $fe           ; loop counter
zp_ptr2         = $02           ; second pointer (2 bytes)
zp_round        = $04           ; aes round counter
zp_col          = $05           ; aes column counter
zp_tmp1         = $06           ; aes temp
zp_tmp2         = $07           ; aes temp
zp_tmp3         = $08           ; aes temp
zp_tmp4         = $09           ; aes temp
polyval_acc     = $10           ; 16-byte POLYVAL accumulator ($10-$1F)
kbd_buffer      = $c6           ; keyboard buffer count

; petscii codes
petscii_1       = $31           ; '1' key
petscii_2       = $32           ; '2' key
petscii_3       = $33           ; '3' key
petscii_4       = $34           ; '4' key
petscii_5       = $35           ; '5' key
petscii_q       = $51           ; 'q' key
petscii_return  = $0d           ; return key

; aes constants
aes_block_size  = 16            ; 128 bits = 16 bytes
aes_key_size    = 32            ; 256 bits = 32 bytes
aes_rounds      = 14            ; aes-256 uses 14 rounds
aes_expanded_key_size = 240     ; (14+1) * 16 = 240 bytes

; buffer sizes
input_buf_size  = 64            ; max input text size
encrypt_buf_size = 80           ; encrypted output size (input + up to 16 pad)
