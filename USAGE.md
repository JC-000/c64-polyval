# c64-polyval library usage guide

This document shows how to drop the POLYVAL / AES-256 / AES-256-GCM-SIV
library under `src/lib/` into another Commodore 64 assembly project.

The library is source-distributed: the host ACME build `!source`s the
lib files into its own translation unit. The binary-blob integration
mode described at the top of `src/lib/polyval_api.asm` is future work.

All public symbols and their calling conventions are documented in
`src/lib/polyval_api.asm`. That file is the authoritative API reference;
this document is the integration cookbook.

## Profile selection

The POLYVAL primitive ships in two flavours selected at assemble time
via the `POLYVAL_PROFILE` equate:

| Profile | Multiply | Precompute | Memory   | Picks when                                   |
|---------|---------:|-----------:|----------|----------------------------------------------|
| SHORT   | ~18.8 kc | ~4.7 kc    | ~0.3 KB  | H rederived per message (RFC 8452 GCM-SIV)   |
| LONG    | ~3.9 kc  | ~255 kc    | ~8.3 KB  | H stable across many blocks (TLS, WireGuard) |

Set the profile on the ACME command line:

```
acme -DPOLYVAL_PROFILE=1 ...     # SHORT
acme -DPOLYVAL_PROFILE=2 ...     # LONG (default)
```

Or pre-define it in host sources before `!source`'ing any library file:

```asm
POLYVAL_PROFILE = 1        ; or: POLYVAL_PROFILE = 2
!source "lib/constants_lib.asm"
```

LONG profile precompute is roughly 54x slower than SHORT, so the break-even
is at the message length where `(LONG_mul - SHORT_mul) * blocks > precompute
delta`. Rule of thumb: pick SHORT unless you have at least ~1 KB of message
to authenticate under a single stable H.

## Memory budget

Per-integration RAM cost, approximate (LONG profile; SHORT drops ~8 KB of
8-bit Shoup slices):

| Integration mode   | Zero page        | Absolute RAM (LONG) | Absolute RAM (SHORT) |
|--------------------|------------------|--------------------:|---------------------:|
| POLYVAL only       | $10-$30 (33 B)   |             ~8.3 KB |                ~320 B |
| AES-256 only       | $02-$09 (8 B)    |              ~290 B |                ~290 B |
| Full GCM-SIV AEAD  | $02-$30 (~39 B)  |             ~8.8 KB |                ~790 B |

Zero page usage is approximate — it depends on which `zp_*` equates your
host leaves at their library defaults. Each ZP equate in
`src/lib/constants_lib.asm` is wrapped in `!ifndef` so you can override
individually; see the **Relocation** section below.

## Relocation: placing library buffers in host memory

### Absolute RAM (`POLYVAL_LIB_MEM_BASE`)

By default `lib/data.asm` places its buffer region at "wherever `*`
happens to be" when the host `!source`s it. To pin the buffers to a
specific address, define `POLYVAL_LIB_MEM_BASE` before sourcing:

```asm
POLYVAL_LIB_MEM_BASE = $C000     ; or: pass -DPOLYVAL_LIB_MEM_BASE=49152
!source "lib/constants_lib.asm"
!source "lib/data.asm"
```

The library exposes `POLYVAL_LIB_MEM_END = *` after the final buffer so
the host can bound its own allocations.

### Zero page

The library's ZP equates all live in `src/lib/constants_lib.asm` inside
`!ifndef` guards. Pre-define any of them before sourcing that file:

```asm
; Host wants polyval_acc at $80 instead of $10, and the AES temps
; squeezed into a different ZP window:
polyval_acc  = $80
pv_mul_input = $90
zp_ptr       = $a0
zp_ptr2      = $a2
!source "lib/constants_lib.asm"   ; picks up the overrides
```

Every ZP byte documented in `polyval_api.asm` under "Override symbols"
can be repointed this way.

## Example 1: POLYVAL-only integration

Use case: you need GF(2^128) multiply (e.g. porting AES-GCM's GHASH,
writing a fast TLS 1.3 auth primitive) and you do NOT want the AES or
GCM-SIV bits.

**Files to `!source`:**
- `lib/constants_lib.asm` (equates only)
- `lib/polyval.asm` (dispatches to polyval_short.asm or polyval_long.asm)
- `lib/data.asm` (allocates `polyval_h`, `polyval_temp`, H-tables)

**Skip:** `lib/aes_encrypt.asm`, `lib/aes_decrypt.asm`, `lib/gcm_siv.asm`,
`lib/tables.asm` (AES S-boxes, not used by POLYVAL).

**Host wrapper skeleton:**

```asm
        !cpu 6502
        POLYVAL_PROFILE = 2                  ; LONG
        !source "lib/constants_lib.asm"

        * = $0801                            ; host origin
        ; ... host code ...
        !source "lib/polyval.asm"

        ; Buffer region
        POLYVAL_LIB_MEM_BASE = $C000
        !source "lib/data.asm"
```

**Call pattern** — authenticate N 16-byte blocks under a single H:

```asm
        ; 1. Stage H (16 bytes, little-endian) at polyval_h.
        ldx #15
@cp_h:  lda my_h,x
        sta polyval_h,x
        dex
        bpl @cp_h

        ; 2. Build the H-table(s). WARNING: this routine DESTROYS
        ;    polyval_h (overwrites it with H' = H * x^-128 mod f). If
        ;    you need H again, save it first.
        jsr polyval_precompute_table

        ; 3. Clear the running accumulator.
        jsr polyval_init

        ; 4. For each 16-byte block, copy into polyval_temp and call
        ;    polyval_update.
        ldy #0
@blk:   ldx #15
@cp_b:  lda (msg_ptr),y
        sta polyval_temp,x
        iny
        dex
        bpl @cp_b
        jsr polyval_update
        ; ... loop for remaining blocks ...

        ; 5. Read the 128-bit tag out of polyval_acc ($10-$1F by default).
```

**Profile advice:** LONG if you will absorb at least a few hundred
blocks under this H; SHORT otherwise.

## Example 2: AES-256-only integration

Use case: you need AES-256 ECB or CTR (e.g. disk encryption, a
fully-homebrew cipher mode) without GCM-SIV's authentication.

**Files to `!source`:**
- `lib/constants_lib.asm`
- `lib/aes_encrypt.asm`
- `lib/aes_decrypt.asm` (omit if you only need encryption)
- `lib/tables.asm` (S-box + inverse S-box + round constants)
- `lib/data.asm` (allocates `aes_current_key`, `aes_state`, `aes_expanded_key`)

**Skip:** `lib/polyval.asm`, `lib/gcm_siv.asm`.

**Call pattern** — encrypt one 16-byte block:

```asm
        ; 1. Stage the 32-byte AES-256 master key at aes_current_key.
        ldx #31
@cp_k:  lda my_key,x
        sta aes_current_key,x
        dex
        bpl @cp_k

        ; 2. Expand the key schedule. This writes 240 bytes to
        ;    aes_expanded_key and clobbers aes_current_key bytes as a
        ;    side effect (see aes_encrypt.asm header comments).
        jsr aes_key_expansion

        ; 3. Stage a 16-byte plaintext block at aes_state.
        ldx #15
@cp_p:  lda my_plaintext,x
        sta aes_state,x
        dex
        bpl @cp_p

        ; 4. Encrypt in place.
        jsr aes_encrypt_block

        ; 5. Read ciphertext from aes_state.
```

`aes_decrypt_block` has the same calling convention. For CTR mode, drive
`aes_encrypt_block` over successive counter blocks and XOR the output
keystream with your data yourself — the library does not ship a
standalone AES-CTR primitive outside of the GCM-SIV-specific
`gcmsiv_ctr_encrypt` / `gcmsiv_ctr_decrypt` wrappers.

## Example 3: Full AES-256-GCM-SIV AEAD

Use case: RFC 8452 authenticated encryption with a single stable master
key and fresh 96-bit nonces.

**Files to `!source`:** all of `src/lib/*.asm` (both AES, POLYVAL, tables,
data, gcm_siv, constants_lib).

**Call pattern** — encrypt:

```asm
        ; 1. Stage 32-byte master key at aes_current_key.
        ldx #31
@cp_k:  lda my_master_key,x
        sta aes_current_key,x
        dex
        bpl @cp_k

        ; 2. Expand the master key. gcmsiv_encrypt does NOT call
        ;    aes_key_expansion internally — the host must do this before
        ;    the first GCM-SIV call, and again any time the master key
        ;    changes. (See "Known limitations" below.)
        jsr aes_key_expansion

        ; 3. Stage 12-byte nonce at gcmsiv_nonce.
        ldx #11
@cp_n:  lda my_nonce,x
        sta gcmsiv_nonce,x
        dex
        bpl @cp_n

        ; 4. Stage plaintext (0..64 bytes) at gcmsiv_pt_buf; length at
        ;    gcmsiv_pt_len.
        lda #my_pt_len
        sta gcmsiv_pt_len
        ; ... copy my_pt_len bytes from source into gcmsiv_pt_buf ...

        ; 5. Encrypt + authenticate.
        jsr gcmsiv_encrypt

        ; 6. Read 16-byte tag from gcmsiv_tag, ciphertext from
        ;    gcmsiv_ct_buf.
```

**Call pattern** — decrypt and verify:

```asm
        ; ... master key expansion and nonce staging as above ...

        ; Stage ciphertext at gcmsiv_ct_buf, received tag at gcmsiv_tag,
        ; length at gcmsiv_pt_len.

        jsr gcmsiv_decrypt
        beq @tag_ok                          ; Z=1 -> tag valid, A=0
        ; Z=0, A=1 -> tag invalid. gcmsiv_dec_buf has been wiped to
        ; zeros; do NOT trust any plaintext. gcmsiv_tag_valid is also 0.
        jmp handle_auth_failure
@tag_ok:
        ; Plaintext is in gcmsiv_dec_buf, length still in gcmsiv_pt_len.
```

## Known limitations

Carried over from the Phase 3 audit of the library restructure. These
are pre-existing constraints, not introduced by splitting the tree.

1. **`polyval_precompute_table` destroys `polyval_h`.** It overwrites
   `polyval_h` with the reduced `H' = H * x^-128 mod f(x)`. If your host
   needs the original H after precompute (e.g. to rekey or to rederive),
   save it to a scratch buffer before calling.

2. **GCM-SIV requires pre-expanded AES round keys.** Neither
   `gcmsiv_encrypt` nor `gcmsiv_decrypt` calls `aes_key_expansion`
   internally. The host must stage `aes_current_key` with the 32-byte
   master and call `aes_key_expansion` once (and again any time the
   master key changes) before calling into GCM-SIV.

3. **GCM-SIV does not absorb AAD.** `gcmsiv_compute_tag_base` always
   writes a zero AAD length into the length block. Calls with non-empty
   AAD will authenticate only the plaintext/ciphertext and silently
   diverge from any reference implementation that mixes AAD in. Reserved
   for a future extension; track this if you need RFC 8452 with AAD.

4. **POLYVAL is not Poly1305.** WireGuard / ChaCha20-Poly1305 ports need
   Poly1305, not POLYVAL. This library does not help with that use case.

5. **TLS 1.3 GHASH is byte-reversed POLYVAL.** GHASH and POLYVAL compute
   the same underlying product in two different bit orderings. A TLS 1.3
   AES-GCM port can reuse `polyval_multiply` but needs a byte-reversal
   shim at the input and output stages. The library does not ship this
   shim.

6. **GCM-SIV counter format ≠ AES-GCM counter format.** If you are
   porting AES-GCM (not GCM-SIV), `gcmsiv_ctr_encrypt` is not a
   drop-in — GCM-SIV uses a 31-bit LE counter with the top bit forced,
   AES-GCM uses a 32-bit BE counter from J0. Don't mix them.

## Testing

The test harness in `tools/` targets the demo PRG (`build/polyval.prg`)
and consumes `build/labels.txt`. It is not a library-level test suite
and will not work against a host project's integration build.

If you integrate the library into another project, write your own
regression tests. You can reuse the pure-Python reference implementation
at `tools/polyval_reference.py` to generate expected values for
POLYVAL and GCM-SIV. That file has zero C64 dependencies.

For the library-only assembly check run:

```
make lib                        # LONG profile
make lib POLYVAL_PROFILE=short   # SHORT profile
```

Both targets build `src/lib/lib_main.asm` with ONLY the files under
`src/lib/`. If any library file has accidentally grown a reference to
an app-side symbol (e.g. `chrout`, `input_buffer`, a PETSCII string),
`make lib` will fail with an unresolved-symbol error. A passing
`make lib` is the canonical "yes, the library directory is actually
self-contained" signal.
