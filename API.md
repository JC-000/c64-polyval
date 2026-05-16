# c64-polyval public API

This document is the integration reference for developers embedding the
`c64-polyval` library (POLYVAL + AES-256 + AES-256-GCM-SIV) into another
Commodore 64 program. It lists the public entry points, their calling
convention, the memory the library occupies, and the build-time profile
selector.

For high-level overview, benchmarks, and build instructions, see `README.md`.

## 1. Overview

`c64-polyval` provides three layered primitives tuned for a stock
Commodore 64:

- **POLYVAL** (RFC 8452 §3) — the GF(2^128) carry-less universal hash
  underlying AES-GCM-SIV. Init, precompute, multiply, double, update,
  and a 4-bit-nibble XOR-table helper.
- **AES-256** — single-block ECB encrypt and decrypt, plus key expansion.
  Software T-table-free.
- **AES-256-GCM-SIV AEAD** (RFC 8452) — full encrypt-and-authenticate /
  decrypt-and-verify, up to 64 bytes of plaintext per call, empty AAD only.

All library source lives under `src/`. The library is consumed via the
two ca65 header files in `src/`:

- `src/exports.inc` — stable public ABI declarations (`.global` and
  `.globalzp` for every promised-stable symbol). Replaces the historical
  `ca65/release/v0.1.0/include/abi_v1.inc`.
- `src/polyval_api.inc` — documentation header listing every public
  routine, buffer, and the global calling-convention notes. Currently
  emits only the `POLYVAL_PROFILE_SHORT` / `POLYVAL_PROFILE_LONG`
  sentinels — see §3 for profile selection.
- `src/constants_lib.inc` — ZP equates (overridable) and the
  `POLYVAL_PROFILE` selector. `.include` before any consumer code that
  references library ZP slots.

Target platform: 6502 @ 1 MHz, stock Commodore 64. No REU is required.
Source is ca65/ld65 assembly for the cc65 toolchain; build via `make`.
See `README.md` for toolchain install notes.

Byte-order conventions: POLYVAL and GCM-SIV use the little-endian
on-wire byte order specified by RFC 8452. AES blocks are stored in
the natural byte-major order used by FIPS 197.

The canonical machine-readable surface is `src/exports.inc` — a
cross-module map of every public symbol declared with `.export` /
`.exportzp`. Consumers `.import` the names they need; see §7. The
historical v0.1.0 surface `ca65/release/v0.1.0/include/abi_v1.inc`
is preserved verbatim for backward reference.

## 2. Public symbols

Every routine is entered with `JSR` and returns with `RTS`. None are
re-entrant or IRQ-safe. Registers `A`, `X`, `Y` are not preserved
across the call boundary.

### 2.1 POLYVAL primitive (`src/polyval_long.s` / `src/polyval_short.s`)

The active multiply back-end is picked by `POLYVAL_PROFILE` at assemble
time (§3). Both back-ends export the same symbol set.

| Symbol | Defined in | Contract |
|---|---|---|
| `polyval_init` | polyval_long / polyval_short | Zeroes the 128-bit accumulator `polyval_acc` ($10–$1F). |
| `polyval_precompute_table` | polyval_long / polyval_short | Reads `polyval_h`, builds the 4-bit and (LONG only) Shoup-8 tables. **DESTROYS `polyval_h`** (overwrites with H' = H · x^-128). Save H first if you need it. |
| `polyval_update` | polyval_long / polyval_short | Absorbs one 16-byte block from `polyval_temp` into the accumulator: `acc := (acc XOR block) * H`. |
| `polyval_multiply` | polyval_long / polyval_short | Low-level GF(2^128) multiply: `acc := acc * H` using the precomputed tables. ~3,915 cy (LONG) / ~18,770 cy (SHORT). |
| `polyval_double` | polyval_long / polyval_short | Low-level 128-bit doubling: `acc := acc * x`. |
| `polyval_shift_left_4` | polyval_long / polyval_short | Inlined 4-bit left shift with reduction (SHORT profile hot path). |
| `polyval_xor_table_entry` | polyval_long / polyval_short | XORs `polyval_htable[pv_mul_nibble]` (one 16-byte entry) into the accumulator. |
| `polyval_right_shift_1` | polyval_long / polyval_short | Right-shift 128 bits with reduction (x^-1 mod f). Used by precompute. |
| `polyval_finalize` | polyval_long / polyval_short | Currently a stub / placeholder; reserved for future tag-extraction wrappers. |

### 2.2 POLYVAL data buffers (`src/data.s`)

| Symbol | Size | Role |
|---|---:|---|
| `polyval_h` | 16 B | Input: 128-bit hash key H. Overwritten by `polyval_precompute_table`. |
| `polyval_temp` | 16 B | Input: block consumed by `polyval_update`. |
| `polyval_htable` | 256 B | 4-bit Shoup table (both profiles). Page-aligned. |
| `polyval_htable8` | 4 KB | 8-bit Shoup slices (LONG only). 16 sub-symbols `polyval_htable8_s0..s15`, page-aligned. |
| `polyval_reduce8` | 4 KB | 8-bit reduction slices (LONG only). 16 sub-symbols `polyval_reduce8_s0..s15`, page-aligned. |

### 2.3 POLYVAL zero-page (`src/data.s`, ZP equates in `src/constants_lib.inc`)

| Symbol | Address | Size | Role |
|---|---:|---:|---|
| `polyval_acc` | `$10` | 16 B | Running 128-bit accumulator. |
| `pv_mul_input` | `$20` | 16 B | Multiply input scratch (also receives `polyval_update`'s pre-XORed block). |
| `pv_mul_nibble` | `$30` | 1 B | Nibble parameter for `polyval_xor_table_entry`. |

All three ZP equates are wrapped in `.ifndef` in `constants_lib.inc`,
so hosts can relocate by pre-defining the symbol before `.include`ing
the header (§4).

### 2.4 AES-256 primitive (`src/aes_encrypt.s`, `src/aes_decrypt.s`)

| Symbol | Defined in | Contract |
|---|---|---|
| `aes_key_expansion` | aes_encrypt | Expands `aes_current_key` (32 B) into `aes_expanded_key` (240 B). May clobber bytes of `aes_current_key` as scratch — re-stage before the next expand. |
| `aes_encrypt_block` | aes_encrypt | Encrypts `aes_state` (16 B) in place using `aes_expanded_key`. |
| `aes_decrypt_block` | aes_decrypt | Decrypts `aes_state` (16 B) in place using `aes_expanded_key`. |

### 2.5 AES-256 data buffers (`src/data.s`)

| Symbol | Size | Role |
|---|---:|---|
| `aes_current_key` | 32 B | Input: AES-256 master key. |
| `aes_expanded_key` | 240 B | Output of `aes_key_expansion`. |
| `aes_state` | 16 B | In/out: block being encrypted or decrypted. |

### 2.6 AES-256 zero-page (`src/constants_lib.inc`)

| Symbol | Address | Role |
|---|---:|---|
| `zp_round` | `$04` | Round counter. |
| `zp_col` | `$05` | Column counter. |
| `zp_tmp1..tmp4` | `$06`–`$09` | AES temps. |
| `zp_ptr2` | `$02`–`$03` | Secondary 2-byte pointer (AES + GCM-SIV). |
| `zp_ptr` | `$fb`–`$fc` | Primary 2-byte pointer. |
| `zp_temp` | `$fd` | Generic temp. |
| `zp_count` | `$fe` | Generic loop counter. |

### 2.7 AES-256-GCM-SIV AEAD (`src/gcm_siv.s`)

| Symbol | Contract |
|---|---|
| `gcmsiv_encrypt` | Full RFC 8452 encrypt-and-authenticate. Inputs: pre-expanded master in `aes_expanded_key`, 96-bit nonce at `gcmsiv_nonce`, plaintext at `gcmsiv_pt_buf` (length in `gcmsiv_pt_len`, 0..64). Outputs: ciphertext at `gcmsiv_ct_buf`, 128-bit tag at `gcmsiv_tag`. |
| `gcmsiv_decrypt` | Full RFC 8452 decrypt-and-verify. Inputs: ciphertext at `gcmsiv_ct_buf`, received tag at `gcmsiv_tag`, length at `gcmsiv_pt_len`. Returns `Z=1`/`A=0` on tag valid (plaintext in `gcmsiv_dec_buf`), `Z=0`/`A=1` on tag invalid (`gcmsiv_dec_buf` is wiped to zeros, `gcmsiv_tag_valid` is also cleared). |
| `gcmsiv_derive_keys` | RFC 8452 key derivation: master key + nonce → 16-byte auth key (`gcmsiv_auth_key`) + 32-byte enc key (`gcmsiv_enc_key`). |
| `gcmsiv_compute_tag_base` | POLYVAL over (PT, length-block) → `gcmsiv_tag_acc`. (AAD is always treated as empty — see §6.) |
| `gcmsiv_finalize_tag` | Final AES-CTR over the tag accumulator to produce `gcmsiv_tag`. |
| `gcmsiv_ctr_encrypt` | AES-CTR keystream over `gcmsiv_pt_buf` → `gcmsiv_ct_buf`. |
| `gcmsiv_ctr_decrypt` | AES-CTR keystream over `gcmsiv_ct_buf` → `gcmsiv_dec_buf`. |
| `gcmsiv_derive_ctr` | Internal: derives the AES-CTR initial counter from tag + nonce. |
| `gcmsiv_install_enc_key` | Internal: swaps `gcmsiv_enc_key` into `aes_current_key` and re-expands. |
| `gcmsiv_restore_orig_key` | Internal: restores the master-key expansion saved by `install_enc_key`. |
| `gcmsiv_gen_keystream` | Internal: generates AES-CTR keystream blocks. |

### 2.8 GCM-SIV data buffers (`src/data.s`)

| Symbol | Size | Role |
|---|---:|---|
| `gcmsiv_nonce` | 12 B | Input: 96-bit nonce. |
| `gcmsiv_pt_buf` | 64 B | Input (encrypt) / scratch (decrypt). |
| `gcmsiv_pt_len` | 1 B | Plaintext / ciphertext byte length (0..64). |
| `gcmsiv_ct_buf` | 64 B | Output (encrypt) / input (decrypt). |
| `gcmsiv_dec_buf` | 64 B | Output of `gcmsiv_decrypt`. |
| `gcmsiv_tag` | 16 B | In/out: 128-bit auth tag. |
| `gcmsiv_auth_key` | 16 B | Derived POLYVAL auth key. |
| `gcmsiv_enc_key` | 32 B | Derived AES-256 enc key. |
| `gcmsiv_tag_valid` | 1 B | Legacy result flag (1 = valid, 0 = invalid). |
| `gcmsiv_tag_acc` | 16 B | Internal: tag base accumulator. |

## 3. Profile selection

The POLYVAL primitive ships in two flavours selected at assemble time
via the `POLYVAL_PROFILE` symbol:

| Profile | Multiply | Precompute | Memory (tables) | Picks when |
|---|---:|---:|---:|---|
| SHORT (`POLYVAL_PROFILE=1`) | ~18,770 cy | ~29,385 cy | ~256 B | H rederived per message (RFC 8452 GCM-SIV short messages) |
| LONG (`POLYVAL_PROFILE=2`) (default) | ~3,915 cy | ~255,263 cy | ~8.5 KB | H stable across many blocks (TLS 1.3, WireGuard) |

Both profiles export an identical symbol set (§2.1). Callers do not
need to know which profile is loaded — `.import polyval_multiply` and
the rest of the API are stable across the two back-ends.

Set the profile on the ca65 command line, or via the top-level Makefile:

```
make                              # LONG (default)
make POLYVAL_PROFILE=short        # SHORT
make POLYVAL_PROFILE=long         # LONG (explicit)
```

The Makefile maps these to `-D POLYVAL_PROFILE=2` / `-D POLYVAL_PROFILE=1`
for ca65 and to `polyval_long.o` / `polyval_short.o` for ld65.

**Crossover.** Total cost of hashing N 16-byte blocks under one H is
approximately `precompute + N × multiply`. Solving for the SHORT/LONG
crossover gives roughly 15 blocks on precompute-included workloads;
the practical break-even where LONG starts winning consistently is
around 68 blocks (≈1 KB of plaintext per message). Pick SHORT below
that, LONG above.

The Python test and benchmark scripts honour the same selector via an
environment variable:

```bash
POLYVAL_PROFILE=short python3 tools/test_polyval_direct.py
POLYVAL_PROFILE=long  python3 tools/benchmark_polyval.py
```

## 4. Zero-page layout

The library owns the following zero-page bytes at fixed default
addresses. These are part of the v0.1 ABI; a host integrating
c64-polyval must ensure no other code uses them concurrently.

| ZP range | Default symbol(s) | Purpose |
|---|---|---|
| `$02`–`$03` | `zp_ptr2` | Secondary 2-byte pointer |
| `$04` | `zp_round` | AES round counter |
| `$05` | `zp_col` | AES column counter |
| `$06`–`$09` | `zp_tmp1..tmp4` | AES temps |
| `$10`–`$1F` | `polyval_acc` | POLYVAL 128-bit accumulator |
| `$20`–`$2F` | `pv_mul_input` | POLYVAL multiply input scratch |
| `$30` | `pv_mul_nibble` | POLYVAL nibble parameter |
| `$fb`–`$fc` | `zp_ptr` | Primary 2-byte pointer |
| `$fd` | `zp_temp` | Generic temp |
| `$fe` | `zp_count` | Generic loop counter |

### Overriding ZP slots from a consumer

Every ZP equate in `src/constants_lib.inc` is wrapped in `.ifndef`. A
host can pre-define the symbol before `.include`ing the header, and
the host's value wins:

```asm
; Host wants polyval_acc at $80 instead of $10:
polyval_acc  = $80
pv_mul_input = $90
.include "constants_lib.inc"        ; picks up the overrides
.include "polyval_api.inc"
.include "exports.inc"
```

Doing this is only safe if the host has verified non-overlap with the
library's actual ZP usage and with whatever else the host puts on
zero-page. The defaults above are the canonical layout the library
was tested under.

## 5. Calling conventions

All public routines follow the same contract:

- Entry: `JSR`. Exit: `RTS`.
- Registers `A`, `X`, `Y` are NOT preserved. Save them at the call site
  if the caller needs them.
- Flag state on return (`C`, `V`, `N`) is undefined unless explicitly
  noted.
- **Exception: `gcmsiv_decrypt`.** Returns tag validity in two
  redundant channels:
  - Z-flag: `Z=1` valid, `Z=0` invalid (preferred — branch with `beq` / `bne`).
  - Accumulator: `A=0` valid, `A=1` invalid.
  - On invalid, `gcmsiv_dec_buf` has been zeroed and `gcmsiv_tag_valid`
    is also 0. Do NOT trust any byte of `gcmsiv_dec_buf` after an
    invalid result.
- Re-entrancy: **NONE of the routines are re-entrant.** They share
  ZP scratch (`zp_ptr`, `zp_tmp1..4`, `pv_mul_input`, ...) globally,
  and the multiply back-end maintains state in `polyval_acc` /
  `polyval_htable[8]`. Callers must serialize all library calls and
  must NOT invoke any library routine from an IRQ handler that can
  preempt mainline crypto work. Mask IRQs around library work or keep
  all calls on a single thread of control.

### Input/output convention

Public routines do NOT take operand pointers — they read inputs from
and write outputs to fixed buffer symbols (§2.2, §2.5, §2.8). To use a
routine, copy your data into the library's input buffer, call the
routine, then copy the result out of the library's output buffer.
Example for `polyval_update`:

```asm
        ; Stage one block at polyval_temp.
        ldx #15
@cp:    lda my_block,x
        sta polyval_temp,x
        dex
        bpl @cp
        jsr polyval_update
        ; Result accumulated into polyval_acc ($10-$1F).
```

This is a deliberate trade: fixed-address inputs are simpler at the
ABI than ZP-pointer calling, and the buffer addresses can be relocated
via `src/data.s` if a host needs them elsewhere.

## 6. Known limitations

Carried over from the v0.1.0 audit. These are pre-existing constraints,
not introduced by the v0.2.0 repackage.

1. **`polyval_precompute_table` destroys `polyval_h`.** It overwrites
   `polyval_h` with H' = H · x^-128 mod f. If the host needs the
   original H after precompute, save it to a scratch buffer first.

2. **GCM-SIV requires pre-expanded AES round keys.** Neither
   `gcmsiv_encrypt` nor `gcmsiv_decrypt` calls `aes_key_expansion`
   internally. The host must stage `aes_current_key` with the 32-byte
   master, call `aes_key_expansion` once, and re-expand any time the
   master key changes — all before the first GCM-SIV call.

3. **GCM-SIV does not absorb AAD.** Only empty-AAD messages may be
   authenticated. `gcmsiv_compute_tag_base` always writes a zero AAD
   length into the length block. Calls with non-empty AAD will
   authenticate only the plaintext/ciphertext and silently diverge
   from any reference implementation that mixes AAD in. Reserved for a
   future extension.

4. **GCM-SIV plaintext length is limited to 0..64 bytes per call.**
   The buffers `gcmsiv_pt_buf` / `gcmsiv_ct_buf` / `gcmsiv_dec_buf`
   are 64 B each. Longer messages need to be chunked at the protocol
   layer, which RFC 8452's nonce-misuse-resistant construction does
   not natively support — pick a different mode for bulk encryption.

5. **Not IRQ-safe.** See §5; callers must mask IRQs around library
   work or serialize on a single thread of control.

6. **Not re-entrant.** Library routines share global ZP scratch and
   table state; sequential calls are fine, interleaved calls are not.

7. **Pre-computed H' via 128 right-shifts.** Building H' from H costs
   ~30k cy (SHORT) or ~255k cy (LONG) per key, on top of the table
   build. This is a one-time cost per H; amortizes away if H is
   stable across many blocks (the LONG profile's intended workload),
   dominates the per-message cost when H is rederived per message
   (the SHORT profile's intended workload).

8. **POLYVAL is not Poly1305.** WireGuard data-channel /
   ChaCha20-Poly1305 ports need Poly1305, which this library does not
   provide.

9. **TLS 1.3 GHASH is byte-reversed POLYVAL.** A TLS 1.3 AES-GCM port
   can reuse `polyval_multiply` but needs a byte-reversal shim at the
   input and output stages. The library does not ship that shim.

10. **GCM-SIV counter format ≠ AES-GCM counter format.** If you are
    porting AES-GCM (not GCM-SIV), `gcmsiv_ctr_encrypt` is not a
    drop-in — GCM-SIV uses a 31-bit LE counter with the top bit
    forced, AES-GCM uses a 32-bit BE counter from J0.

11. **Public-input use only for non-constant-time paths.** None of
    the POLYVAL or AES-256 primitives in this library are
    constant-time. Do not use them in contexts where the message
    bytes, key bytes, or nonce bytes must be protected from
    timing side-channels.

## 7. Build integration

Consumer programs assemble their own `.s` files alongside the library
`.s` files, then link everything together with `ld65`. The minimal
shape:

```asm
; consumer.s -----------------------------------------------------------

.include "constants_lib.inc"        ; ZP equates + POLYVAL_PROFILE selector
.include "polyval_api.inc"          ; profile-selector documentation
.include "exports.inc"              ; .global declarations for the public ABI

; polyval_acc / pv_mul_input / pv_mul_nibble are plain equates from
; constants_lib.inc -- no .importzp needed. Referenced below as ZP.

.import polyval_init
.import polyval_precompute_table
.import polyval_update
.import polyval_multiply
.import aes_key_expansion
.import aes_encrypt_block
.import aes_decrypt_block
.import gcmsiv_encrypt
.import gcmsiv_decrypt

.import polyval_h, polyval_temp
.import aes_current_key, aes_state, aes_expanded_key
.import gcmsiv_nonce, gcmsiv_pt_buf, gcmsiv_pt_len
.import gcmsiv_ct_buf, gcmsiv_dec_buf, gcmsiv_tag

; ... host code, calling the imported routines ...
```

A worked example lives at `test/consumer_stub.s` — it `.include`s the
two public headers, `.import`s a representative slice of the ABI,
and `JSR`s each entry point. `make consumer-check` assembles and
links it against the library and is the canonical "the public ABI
is stable enough for external consumers" gate.

### Minimal consumer Makefile fragment

```make
LIB        = lib/c64-polyval               # vendored as a git submodule
LIB_SRC    = $(LIB)/src
LIB_BUILD  = $(BUILD_DIR)/lib/c64-polyval

# Pick POLYVAL profile: 1 = SHORT, 2 = LONG (default).
POLYVAL_PROFILE_VAL ?= 2
POLYVAL_PROFILE_OBJ := $(if $(filter 1,$(POLYVAL_PROFILE_VAL)),polyval_short,polyval_long)

# Library .s files to compile and link. IMPORTANT: see §8 for the
# canonical "include vs omit" list. The DEMO APP files in src/ are
# OMITTED here.
LIB_MODULES = aes_encrypt aes_decrypt gcm_siv tables data lib_main \
              $(POLYVAL_PROFILE_OBJ)

LIB_OBJECTS = $(addprefix $(LIB_BUILD)/,$(addsuffix .o,$(LIB_MODULES)))

CA65FLAGS_LIB = -I $(LIB_SRC) -D POLYVAL_PROFILE=$(POLYVAL_PROFILE_VAL)

$(LIB_BUILD)/%.o: $(LIB_SRC)/%.s | $(LIB_BUILD)
	ca65 $(CA65FLAGS_LIB) -o $@ $<

$(LIB_BUILD):
	mkdir -p $@

# Consumer PRG links its own objects plus the library objects.
consumer.prg: $(CONSUMER_OBJECTS) $(LIB_OBJECTS) consumer.cfg
	ld65 -o consumer.prg -C consumer.cfg $(CONSUMER_OBJECTS) $(LIB_OBJECTS)
```

The consumer's linker config must preserve the page alignment for
`polyval_htable` and (LONG only) `polyval_htable8` / `polyval_reduce8`.
The simplest path is to copy `src/c64.cfg` and extend it with
consumer-specific segments — see that file for the canonical memory
map (LOADADDR at $07FF, MAIN at $0801–$87FF, page-aligned
`POLYVAL_HTABLE` / `POLYVAL_HTABLE8` / `POLYVAL_REDUCE8` segments).

## 8. Consumer integration: file inventory

The `src/` tree mixes the LIBRARY (the public POLYVAL / AES /
GCM-SIV crypto) with a DEMO APP (the in-repo VICE-runnable PRG that
exercises the library through a menu UI, disk I/O, and a hex display).
Production consumers MUST link only the library files; the demo-app
files reference KERNAL routines (`CHRIN`, `CHROUT`), the BASIC stub at
`$0801`, and the standalone `main` entry point that no host wants to
inherit.

### 8.1 LIBRARY files (link these)

| File | Role |
|---|---|
| `src/aes_encrypt.s` | AES-256 encrypt + key expansion |
| `src/aes_decrypt.s` | AES-256 decrypt + inverse MixColumns / S-box helpers |
| `src/gcm_siv.s` | AES-256-GCM-SIV AEAD glue + AES-CTR helpers |
| `src/tables.s` | S-box, inverse S-box, AES round constants |
| `src/data.s` | All library-owned data buffers and ZP `.res` reservations |
| `src/lib_main.s` | Verification stub. `make lib` links ONLY this + the LIBRARY files to catch any accidental DEMO APP dependency; a consumer normally does NOT link this either. |
| `src/polyval_long.s` *OR* `src/polyval_short.s` | Active POLYVAL multiply back-end. Pick one based on `POLYVAL_PROFILE`. Linking both is an error. |

Plus the header files (included, not assembled):

| Header | Role |
|---|---|
| `src/exports.inc` | `.global` / `.globalzp` declarations for the stable public ABI |
| `src/polyval_api.inc` | Documentation header; emits the `POLYVAL_PROFILE_SHORT` / `_LONG` sentinels |
| `src/constants_lib.inc` | ZP equates (`.ifndef`-guarded) and the `POLYVAL_PROFILE` selector default |
| `src/include/zp.inc` | ZP symbol template for downstream ports |

### 8.2 DEMO APP files (OMIT from consumer link)

These files are the in-repo runnable demo and must NOT be linked into
a consumer PRG:

| File | Why omit |
|---|---|
| `src/main.s` | Demo entry point; the consumer provides its own `main` |
| `src/boot.s` | BASIC stub at $0801; the consumer provides its own load header |
| `src/main_loop.s` | Menu UI loop |
| `src/disk_io.s` | KERNAL disk-I/O helpers |
| `src/display.s` | Hex display routines |
| `src/gcm_siv_ui.s` | UI-side GCM-SIV menu glue |
| `src/strings.s` | PETSCII UI strings |
| `src/data_app.s` | Demo-app data buffers (separate from `src/data.s`) |
| `src/zp.s` | Demo-app ZP `.res` reservations |
| `src/constants_app.inc` | Demo-app constants (KERNAL vectors, PETSCII) |

The `src/c64.cfg` and `src/lib_only.cfg` linker configs are demo-app
specific too — consumers should copy one as a starting point and
extend with their own segments rather than linking against the
upstream config directly.

### 8.3 Verification builds

Two ld65 link gates ship in-tree to catch ABI drift:

- `make lib` — links only the LIBRARY files (`src/*.s` from §8.1)
  plus `src/lib_main.s` against `src/lib_only.cfg`. If any library
  file accidentally references a demo-app symbol (`chrout`,
  `print_string`, etc.), `ld65` errors with "unresolved external".
  A passing `make lib` is the canonical "the library directory is
  self-contained" signal.
- `make consumer-check` — assembles `test/consumer_stub.s` against
  `src/exports.inc` + `src/constants_lib.inc` only, and links it
  against the library via `lib_only.cfg`. A passing `consumer-check`
  is the canonical "downstream consumers can use the public ABI"
  signal.

Both gates are also part of the v0.2.0 release tarball acceptance
criteria.

### 8.4 Version compatibility

The `VERSION` file at the repository root carries the current
`MAJOR.MINOR.PATCH` (currently `0.2.0`). Releases are tagged as
`vMAJOR.MINOR.PATCH` in git and shipped as `c64-polyval-vX.Y.Z.tar.gz`
via `make dist VERSION=vX.Y.Z`.

Version policy (pre-1.0, same shape as c64-nist-curves):

- **PATCH** bumps (v0.2.0 → v0.2.1) ship bugfixes or perf wins with no
  public API changes. Always safe to adopt.
- **MINOR** bumps (v0.1.x → v0.2.0) may add public symbols. Will not
  remove or rename existing ones in the v0.x line.
- **MAJOR** bumps (v0.x → v1.0) are reserved for the first stability
  commitment. After v1.0.0, MAJOR bumps indicate breaking API
  changes documented in `CHANGELOG.md` with migration notes.

Consumers should pin to a specific tag, not track `master`.

### 8.5 Historical artifact

The v0.1.0 release format is preserved verbatim at
`ca65/release/v0.1.0/`. It ships the older `.lib` archive format
(`polyval_long.lib` / `polyval_short.lib`) plus the historical
`abi_v1.inc` header, attestation results, and an `examples/`
directory. New consumers should NOT integrate against v0.1.0 —
use v0.2.0's source-tarball + `src/exports.inc` integration path
instead. The v0.1.0 tree is kept only for reproducibility of the
prior release.
