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

Target platform: 6502 @ 1 MHz, stock Commodore 64. No REU — or any
other expansion hardware — is required or ever touched: the library is
pure CPU + RAM on every code path, with no I/O-register or KERNAL
access. It therefore runs unmodified on expansion-less machines, and
its throughput scales with CPU clock on accelerated hosts (see §3).
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

**Turbo / accelerated hosts.** Neither profile touches the REU or any
other ~1 MHz-anchored I/O — every table lives in CPU RAM and every
path is pure CPU work — so per-block cost *and* precompute scale
~linearly with CPU clock on accelerated hosts (Ultimate 64 / C64
Ultimate turbo, SuperCPU-class). There is no speed-invariant
wall-clock floor of the kind REU-DMA-bound hot paths hit: REU DMA
always transfers at the ~1 MHz C64 bus rate regardless of CPU turbo
(c64-nist-curves measured an 87%-of-wall-time floor at 64 MHz before
its optional on-chip profile — see JC-000/c64-nist-curves#69/#71 and
§9.3 of this document). Because both cycle counts scale identically,
the SHORT/LONG crossover *in blocks* is clock-invariant; turbo only
shrinks the absolute cost of the LONG precompute (~255k cy → ~4 ms at
64 MHz).

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

## 9. Library contract (c64-lib-contract v0.10.0)

As of v0.3.0, c64-polyval implements
[c64-lib-contract](https://github.com/JC-000/c64-lib-contract)
SPEC v0.1.0 §1–§6 in full. The contract pins a small set of
cross-library symbols every adopter library exports so a downstream
consumer (c64-wireguard, c64-https, …) can size-check, version-gate,
and collision-check its dependencies at assemble time. Six SPEC
sections apply to c64-polyval; §3 (REU bank claims) is N/A because
the library makes no 17xx REU claims.

The contract has since advanced to v0.9.1 (a PATCH re-landing three
review amendments the v0.9.0 merge missed and folding in adopter
defect reports; its restated §6.2 ZP-scoping rule — slot defines
reach every TU that defines the slot, never a TU that `.importzp`s
it — cites this library's PR #34 as the measured evidence for the
defining-TU direction). c64-polyval v0.5.0 adopts
the v0.7.0 surface: library-prefixed §1 version exports and §8.4
precalc-table equates (`LIB_POLYVAL_*` forms alongside the deprecated
bare names, the latter gated on `LIB_NO_BARE_EXPORTS` until contract
v1.0 removes them) — see §9.1 and §9.6. Contract v0.7.1–v0.7.3 are
doc-only upstream (flag spelling, `od65`-vs-archive audit guidance,
§8 bit-constant export prohibition — the last is N/A here since no
`LIB_POLYVAL_SHARED_PRIMITIVES` mask is emitted); v0.7.4 pins the
macro's byte-valued `_REGION`/`_SHARED` exports `: abs` so consumer
imports (which default to absolute) link without address-size
warnings, adopted here via the verbatim re-copy (issue #27). §7
(Semver expectations) is a doc-only renumbering with no export
surface — no action needed. Contract v0.7.5 is doc-only: it redefines
`LIB_<X>_ABI_VERSION` as a monotonic generation counter for the
exported surface — starting at 1, bumped on any breaking export
change, independent of semver MAJOR — which is what c64-polyval
already ships (`LIB_POLYVAL_ABI_VERSION = 1` against MAJOR 0, §9.1);
no action needed. Contract v0.8.0 extends §4 with mandatory
declarations of load-bearing segment-placement attributes, adopted
here as comments on the segment lines of `src/c64.cfg` /
`src/lib_only.cfg` — see §9.8. Contract v0.8.1 is doc-only: it fixes
the SPEC's own §1 consumer version-guard snippets (issues #73/#74),
canonicalizing the `.assert`/`lderror` form this library's §9.7
example and `src/lib_version.s` comment already use. Contract v0.8.2
(doc-only) adds the spec-tagging policy — every spec version is now
tagged (issue #71). Contract v0.8.3 (doc-only) corrects §4's own
risk table after adopter reports (contract #78; this library's §9.8
measurements are part of that record): both ld65 diagnostics are
conditional on library shape, not on the violation, and the common
shapes are the silent ones. Contract v0.8.4 is doc-only: it states
that `ZEROPAGE` is exempt from §4's prefixed-segment rule because §2
owns zero-page allocation — matching this library's existing
`.segment "ZEROPAGE"` usage; no action needed. Contract v0.8.5 adds
export-discipline rulings to §8.1/§8.2 (the shared-primitive
consumer-input equates MUST NOT be exported) — N/A here, since
c64-polyval consumes no §8.1–§8.3 primitive and emits none of those
equates. Contract v0.8.6 makes the `$`-hex quoting rule normative for
every `-D` snippet (make-mediated interfaces pass `$`-free `0x`
values) — already adopted here via the snippet fixes in PR #33.
Contract v0.9.0 rewrites §6 into the six-clause build-and-consume
chapter (obligations attach to *archives*, not "the library") and
adds the §2 ZP prefix registry, in which **`polyval_` and `pv_` are
registered to this library**; adopted in §9.2 and §9.5 below —
`CONTRACT_DEFINES` / `CONTRACT_ZP_DEFINES` forwarding is the one
code change, the rest of the chapter is verified conformant as-is.
Contract v0.9.2 is doc-only upstream (a §2 registry row for
`chacha20poly1305_`, two §8.2 clarifications, and an
archive-inspection tooling note) — every item was already satisfied
or N/A here; no action needed. Contract v0.10.0 is phase 2 of the
contract-#76 restructuring: **§6.6 lands** (consumer footprint
asserts against the per-archive §6.4 manifest — the library-side
obligations are safe-direction round-up values and per-(profile ×
variant) release-note deltas) and **§6.7 is added** (declared
non-segment reservations). §6.6 is adopted in §9.4/§9.5 below —
`LIB_POLYVAL_RESIDENT_BYTES` / `_COLD_BYTES` are now measured per
archive and rounded UP to the next 256-byte boundary, replacing the
pre-§6.6 rounded-DOWN, profile-only values; §6.7 is N/A (§9.5),
since every c64-polyval buffer is segment-resident and the library
places no §8.x equate-reserved region.
§8 (Shared primitives: `sqtab`, `reu_mul`, `ct_mul_8x8`) covers the
8×8 quarter-square-multiply primitive shared by the elliptic-curve
and ChaCha20 field-arithmetic libraries; GF(2^128) carry-less
multiplication has no equivalent shape, so §8.1–§8.3 are N/A and
`LIB_POLYVAL_SHARED_PRIMITIVES` is correctly not exported. §8.0's
precalculated-table enumeration duty *does* apply regardless of
§8.1–§8.3 applicability — see §9.6 below, added in v0.4.0.

### 9.1 §1 — Version identification (`src/lib_version.s`)

Four absolute equates, exported as `:abs` in two forms per SPEC
v0.7.0:

| Symbol (prefixed, permanent) | Deprecated bare alias | Value | Meaning |
|---|---|---:|---|
| `LIB_POLYVAL_VERSION_MAJOR` | `LIB_VERSION_MAJOR` | `0` | Semver major. |
| `LIB_POLYVAL_VERSION_MINOR` | `LIB_VERSION_MINOR` | `6` | Semver minor. |
| `LIB_POLYVAL_VERSION_PATCH` | `LIB_VERSION_PATCH` | `0` | Semver patch. |
| `LIB_POLYVAL_ABI_VERSION`   | `LIB_ABI_VERSION`   | `1` | ABI compatibility level. Coarser than MINOR. |

The bare names are identical across every contract adopter, so a
consumer linking two libraries cannot import both manifests
(contract #43); they are deprecated, removed at contract v1.0, and
gated on `LIB_NO_BARE_EXPORTS` (`ca65 -D LIB_NO_BARE_EXPORTS=1`) so a
composing consumer can suppress them build-wide. New consumers should
import the `LIB_POLYVAL_*` form. The bare aliases are defined in
terms of the prefixed literals, so the two forms cannot drift.

Consumers `.import` whichever subset they need and gate compilation
on them — see the worked example in §9.7.

### 9.2 §2 — Zero-page contract (`src/zp_config.s`)

Every ZP slot the library claims is declared as an `.ifndef`-guarded
equate and `.exportzp`-ed. Consumers `.importzp` the names they
need (or override them in their own translation unit before
`.include`-ing `zp_config.s` / `constants_lib.inc`). The `polyval_`
and `pv_` prefixes are registered to c64-polyval in the SPEC §2 ZP
prefix registry (v0.9.0): every exported slot name begins with one of
them, and no other adopter may claim either prefix.

The canonical override route is the SPEC §6.2 make variable — no
Makefile edit, no per-file ca65 chain:

```sh
make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'
```

Values must be `$`-free (`0x` hex or decimal) — make's `$`-expansion
mangles every `$`-hex escape ladder silently (SPEC §2, v0.8.6). See
§9.5 for why this library forwards `CONTRACT_ZP_DEFINES` to every
member TU.

| Symbol | Address | Width | Role |
|---|---:|---:|---|
| `polyval_zp_ptr2` | `$02` | 2 B | Secondary pointer |
| `polyval_aes_round` | `$04` | 1 B | AES round counter |
| `polyval_aes_col` | `$05` | 1 B | AES column counter |
| `polyval_aes_tmp1` | `$06` | 1 B | AES temp |
| `polyval_aes_tmp2` | `$07` | 1 B | AES temp |
| `polyval_aes_tmp3` | `$08` | 1 B | AES temp |
| `polyval_aes_tmp4` | `$09` | 1 B | AES temp |
| `polyval_acc` | `$10` | 16 B | POLYVAL 128-bit accumulator |
| `pv_mul_input` | `$20` | 16 B | POLYVAL multiply scratch |
| `pv_mul_nibble` | `$30` | 1 B | POLYVAL nibble param |
| `polyval_zp_ptr` | `$fb` | 2 B | Primary pointer |
| `polyval_zp_temp` | `$fd` | 1 B | Generic temp |
| `polyval_zp_count` | `$fe` | 1 B | Generic loop counter |

Total: **45 bytes** claimed across three discontiguous regions
(`$02–$09`, `$10–$30`, `$fb–$fe`). The sum is exposed via
`LIB_POLYVAL_ZP_USAGE_BYTES` (§9.4).

Suppress the `.exportzp` block by defining
`ZP_CONFIG_NO_EXPORTS = 1` before `.include`-ing `zp_config.s`.
This is what `constants_lib.inc` does internally so transitive
includes don't try to re-export the same symbols.

### 9.3 §3 — REU bank usage

N/A. c64-polyval is a CPU-RAM-only library; `LIB_POLYVAL_REU_BANKS_USED`
(§9.4) is therefore `0`.

The zero is a **contract feature, not an accident**: no code path in
either profile touches the 17xx REU, any `$D000–$DFFF` hardware
register, or the KERNAL. Consumers comparing sibling libraries
(c64-https, c64-wireguard) can rely on the two properties this
implies — the library runs unmodified on expansion-less machines, and
it carries no ~1 MHz-anchored wall-clock floor on turbo hosts (§3,
"Turbo / accelerated hosts").

**Policy for future REU-resident variants** (e.g. REU-backed LONG
tables to free ~8.5 KB of RAM): following the c64-nist-curves
precedent (JC-000/c64-nist-curves#69/#71), any such variant must ship
as an *optional profile* with its own manifest delta (an override of
`LIB_POLYVAL_REU_BANKS_USED`), never as the default or only path.
The RAM saving would be bought with a speed-invariant wall-clock
floor at turbo and a hard REU dependency at stock, inverting the
guarantees above.

### 9.4 §5 — Aggregate manifest (`src/lib_manifest.s`)

Four absolute equates for assemble-time size and collision asserts.
`ZP_USAGE_BYTES` and `REU_BANKS_USED` are configuration-invariant:

| Symbol | Value | Meaning |
|---|---:|---|
| `LIB_POLYVAL_ZP_USAGE_BYTES` | 45 | Total ZP bytes claimed (§9.2). |
| `LIB_POLYVAL_REU_BANKS_USED` | 0 | Bitmask of REU banks; always 0. |

`RESIDENT_BYTES` and `COLD_BYTES` are **safe-direction** per SPEC
v0.10.0 §6.6: each declared value is ≥ the measured code+rodata
segment sum of the archive it ships in, rounded UP to the next
256-byte boundary (the fleet convention — under one page of headroom
absorbs incidental growth, and the equate moving is itself the
signal that a consumer re-look is due). Because declared ≥ actual, a
consumer's `declared ≤ budget` assert implies `actual ≤ budget`; the
pre-§6.6 values rounded *down* (6567 → 6500 etc.), which broke
exactly that implication. Both values are conditional on **both**
configuration axes — `POLYVAL_PROFILE` *and* `LIB_POLYVAL_NO_AES` —
so each archive's manifest describes that archive (SPEC §6.4/§6.6;
previously they were profile-gated only, and the POLYVAL-only
archives over-claimed ~2.3 KB of AES+GCM-SIV code they do not
contain). Per-archive values (measured 2026-08-15, ca65/ld65 V2.18):

| Archive | Configuration | `RESIDENT_BYTES` (measured) | `COLD_BYTES` (measured) |
|---|---|---:|---:|
| `polyval.a` / `polyval-gcmsiv.a` | LONG, full AEAD | 6656 (6567) | 1280 (1239) |
| — (`make POLYVAL_PROFILE=short` link) | SHORT, full AEAD | 16128 (16021) | 3072 (3059) |
| `polyval-long.a` | LONG, `LIB_POLYVAL_NO_AES` | 4352 (4160) | 1280 (1047) |
| `polyval-short.a` | SHORT, `LIB_POLYVAL_NO_AES` | 13824 (13614) | 3072 (2867) |

`COLD_BYTES` (boot-only init paths: `aes_key_expansion` where AES
ships, plus `polyval_precompute_table`) is a subset carve-out of the
`RESIDENT_BYTES` load image, reclaimable after init — the §6.6 pair
semantics: budget RESIDENT for the image, get COLD back after init.
See `src/lib_manifest.s` for the full derivation comments and the
per-configuration measurement methodology.

### 9.5 §6 — Build and consume

SPEC v0.9.0 rewrote §6 from a single archive-targets clause into a
six-clause chapter whose obligations attach to archives, not "the
library". c64-polyval's status per clause:

**§6.1 — Targets and artifact names.** Four ar65 archive Make
targets ship the library as a single `.a` file consumers can link
directly without rebuilding `.o` files:

| Target | Output | Contents |
|---|---|---|
| `make lib` | `build/lib/polyval.a` | Full AEAD bundle: POLYVAL LONG + AES-256 + GCM-SIV. |
| `make lib-polyval-long` | `build/lib/polyval-long.a` | POLYVAL LONG primitive only (no AES, no GCM-SIV). |
| `make lib-polyval-short` | `build/lib/polyval-short.a` | POLYVAL SHORT primitive only. |
| `make lib-polyval-gcmsiv` | `build/lib/polyval-gcmsiv.a` | Full AEAD bundle (currently byte-identical to `polyval.a`). |

Each archive bundles the SPEC §1 / §2 / §5 core (`lib_version.o`,
`zp_config.o`, `lib_manifest.o`) plus the variant-specific .o set;
see the `LIB_*_OBJS` blocks in the top-level `Makefile` for the
exact composition. The basenames are already canonical
`<shortname>[-<variant>].a` with `<shortname>` = `polyval` — no
deprecated-dialect dual-shipping needed. `make lib-app-owned` is
required only of §8.x-consuming libraries and is N/A here (no §8
primitive consumed — see the §8 note in the §9 intro and §9.6). One
grandfathered name:
`make lib-verify` is a verification link, not an archive, inside the
reserved `lib-*` namespace; per §6.1 it stays until this repo's next
MAJOR, when it becomes `verify-lib`-shaped.

The previous (pre-v0.3.0) `make lib` target — a library-only
verification PRG link at `$4000` — is what `make lib-verify` names
today.

**§6.2 — Consumer defines reach the build.** Every §6.1 target
accepts the two contract-normative make variables, both defaulting
empty, appended to `CA65FLAGS` so they reach every ca65 invocation:

```sh
make lib CONTRACT_DEFINES='-D LIB_NO_BARE_EXPORTS=1'
make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'
```

Values must be `$`-free (`0x` hex or decimal, SPEC §2 v0.8.6).

The polyval-specific scoped-delivery reading, stated here because it
inverts the SPEC's default caution: the SPEC scopes
`CONTRACT_ZP_DEFINES` to "only the ZP-defining TU(s)" because a
globally-delivered slot override collides with `.importzp` sites in
other TUs (`Symbol already defined`). This library has **zero**
`.importzp` sites for its own slots — every library TU defines the ZP
equates itself via `constants_lib.inc` → `zp_config.s` `.ifndef`
guards, baking the address into each `.o` at assemble time. So in
c64-polyval *every member TU is a ZP-defining TU*: delivering
`CONTRACT_ZP_DEFINES` to all member recipes is the conformant scoped
delivery, and the only correct one — a `zp_config.o`-only delivery
would export the overridden address while every other member had
baked the default, a silent mismatch with no link-time diagnostic.
The [nist#104](https://github.com/JC-000/c64-nist-curves/pull/104)
caveat (a ZP TU built by a generic pattern rule needs an explicit
rule to receive the scoped variable) is inapplicable for the same
reason: here the pattern rule delivering to everything is the point.

Recursive propagation: `lib-polyval-{long,short}` re-invoke
`$(MAKE)`; both variables arrive in the sub-make automatically
because command-line variable assignments are passed down via
`MAKEFLAGS` (measured: `zp_config.o` extracted from a
`make lib-polyval-short CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'`
archive exports `polyval_acc` at `$40`).

**§6.3 — Reachability.** Every documented configuration axis
(`POLYVAL_PROFILE`, `POLYVAL_NO_AES`, `LIB_NO_BARE_EXPORTS`, §2 slot
overrides) is reachable through §6.1 targets plus §6.2 variables with
no library edits. `lib-app-owned` N/A as above.

**§6.4 — The manifest describes the archive it ships in.** Already
conformant, both halves: (1) `lib_manifest.o` is assembled under the
same configuration as the archive it ships in — the
`lib-polyval-{long,short}` targets `make clean` and rebuild
recursively with `POLYVAL_PROFILE` and `POLYVAL_NO_AES` pinned, so no
archive ever receives a manifest object assembled under another
configuration; (2) every manifest row is gated on the same switches
that gate what it describes — `LIB_POLYVAL_RESIDENT_BYTES` /
`_COLD_BYTES` on `POLYVAL_PROFILE` × `LIB_POLYVAL_NO_AES` (both axes
since the §6.6 adoption; §9.4), the §8.0 table rows on the same pair
(§9.6). Equate names stay per-library: the exported surface has no
variant-mangled `LIB_POLYVAL_<VARIANT>_*` names — only the canonical
§5 four plus the `LIB_POLYVAL_PRECALC_*` families — so §6.4's
deprecation of mangled names requires nothing here.

**§6.5 — Name surface.** Known future-MAJOR item, recorded, not
actioned: archive **member** basenames (`lib_version.o`,
`zp_config.o`, `lib_manifest.o`, …) must take the `polyval_` prefix
(`polyval_lib_version.o`, …) at this repo's next MAJOR. Members
cannot carry two names at once, so this cannot ride a dual-name
window — it changes only at MAJOR, together with the `lib-verify`
rename above.

**§6.6 — Consumer footprint asserts (SPEC v0.10.0).** Adopted. The
library-side obligations are met in `src/lib_manifest.s`:
(1) `LIB_POLYVAL_RESIDENT_BYTES` / `LIB_POLYVAL_COLD_BYTES` are
per-archive (§6.4 gating on `POLYVAL_PROFILE` ×
`LIB_POLYVAL_NO_AES`) and safe-direction — each ≥ the measured
segment sum of its archive, rounded UP to the next 256-byte
boundary (the per-archive table in §9.4); (2) the two equates are
documented as a pair (COLD is a reclaimable-after-init carve-out of
the RESIDENT image), and release notes state footprint deltas per
(profile × variant) — one tag carries four footprint pairs, so a
single per-version delta would be meaningless. The RECOMMENDED
consumer pattern, polyval-ized from the SPEC (one per linked
archive, in the consumer's own build; `lderror` because the
operands are imports; the consumer's memory area publishes its
extent via `define = yes`):

```asm
; consumer side — one per linked c64-polyval archive
.import LIB_POLYVAL_RESIDENT_BYTES
.import LIB_POLYVAL_COLD_BYTES
.import __MAIN_SIZE__                  ; cfg: MAIN: ... define = yes;
.assert LIB_POLYVAL_RESIDENT_BYTES + LIB_POLYVAL_COLD_BYTES <= __MAIN_SIZE__, lderror, "c64-polyval declared footprint exceeds the MAIN budget"
```

(For c64-polyval COLD lies inside the RESIDENT span, so asserting
`RESIDENT_BYTES` alone against the load-image budget is also sound;
the summed form above is the SPEC's portable shape and stays correct
for consumers overlaying COLD into a different region.) Because the
declared values are safe-direction, `declared ≤ budget` implies
`actual ≤ budget`, and a bump that moves a declared number past the
budget fails the link with a named cause instead of an opaque
segment overflow discovered mid-bisect.

**§6.7 — Declared non-segment reservations (SPEC v0.10.0).** N/A —
by construction, and in exactly the shape the clause's Rule 1
prefers ("prefer a segment when nothing forces the equate"): every
c64-polyval buffer and table is segment-resident (`.res` in the
`LIB_POLYVAL_*` BSS/table segments of `src/data.s`), so ld65
enforces non-overlap natively for all of them. The library places
no §8.x placement equate reserving address space invisible to ld65
(it consumes no §8.1–§8.3 shared primitive — see the §9 intro and
§9.6), so there is no undeclared region to guard and the
`__MAIN_LAST__` three-line guard TU is not required. If a future
variant ever introduces an equate-reserved region (e.g. an
REU-staging window), it must ship the §6.7 guard in a TU that is a
member of no archive, with a non-weak import.

### 9.6 §8.0 — Precalculated-table enumeration (`src/lib_manifest.s`, `docs/precalc-tables.md`)

Added in v0.4.0. SPEC §8.0 requires every adopter to enumerate any
precalculated table meeting the floor (≥ 256 B AND one of:
REU-resident, hot-loop-read, or page-aligned for fetch alignment) —
regardless of whether the library consumes any §8.1–§8.3 shared
primitive. `src/precalc_table.inc` is the canonical `LIB_PRECALC_TABLE`
macro copied verbatim from the contract repo; `src/lib_manifest.s`
invokes it once per enumerated table with `"POLYVAL"` as the SPEC
v0.7.0 library-prefix argument, exporting
`LIB_POLYVAL_PRECALC_<name>_{SIZE,REGION,SHARED}` plus the deprecated
bare `LIB_PRECALC_<name>_*` triple (gated on `LIB_NO_BARE_EXPORTS`,
removed at contract v1.0):

| Table | Size | Region | Ships in |
|---|---:|---|---|
| `polyval_htable` | 256 B | RAM | every build (both profiles) |
| `polyval_htable8` | 4096 B | RAM | LONG-profile builds only |
| `polyval_reduce8` | 4096 B | RAM | LONG-profile builds only |
| `aes_sbox` | 256 B | RODATA | AEAD bundle only (`polyval.a` / `polyval-gcmsiv.a`) |
| `aes_inv_sbox` | 256 B | RODATA | AEAD bundle only (`polyval.a` / `polyval-gcmsiv.a`) |

Manifest rows are gated on the same two axes: the LONG-only tables on
`POLYVAL_PROFILE`, and the AES tables on `LIB_POLYVAL_NO_AES`, which
the `lib-polyval-{long,short}` targets define so the POLYVAL-only
archives (which omit `src/tables.s`) do not enumerate tables they do
not ship (issue #23). This gating is exactly SPEC v0.9.0 §6.4's
per-variant manifest rule, both halves — see §9.5.

All five are classified algorithm-specific (`PRECALC_SHARED_NO`) — no
current adopter shares POLYVAL's GF(2^128) tables or AES's S-box
shape. See [`docs/precalc-tables.md`](../docs/precalc-tables.md) for
the full rationale per table, including the below-floor exempt list
(`aes_rcon`, key-schedule/GCM-SIV scratch buffers) and the
future-audit note flagging `aes_sbox` / `aes_inv_sbox` as the first
candidate if an AES-consuming library ever joins the contract.
Cross-adopter audit: `od65 --dump-exports build/lib_manifest.o | grep _PRECALC_`
(the `_PRECALC_` pattern matches both the prefixed and bare forms; a
shipped `.a` must have its members extracted with `ar65 x` first —
`od65` reads objects only and silently reports nothing on archives).

### 9.7 Consumer example

A downstream consumer can assemble-time gate on the library
version, then `.importzp` whatever ZP slots and `.import` whatever
manifest equates and routines it needs:

```asm
; consumer.s -----------------------------------------------------------
.include "exports.inc"          ; promised-stable public ABI

; --- §1: ABI version gate (v0.7.0 prefixed form) ---
.import LIB_POLYVAL_VERSION_MAJOR, LIB_POLYVAL_VERSION_MINOR
.import LIB_POLYVAL_ABI_VERSION
.assert LIB_POLYVAL_ABI_VERSION = 1, lderror, "c64-polyval exported-surface generation changed"
.assert LIB_POLYVAL_VERSION_MAJOR = 0, lderror, "c64-polyval 0.x required"
.assert LIB_POLYVAL_VERSION_MINOR >= 4, lderror, "v0.4 or newer required"

; --- §2: ZP slots actually used by this consumer ---
.importzp polyval_acc, pv_mul_input, pv_mul_nibble
.importzp polyval_zp_ptr, polyval_zp_temp

; --- §5: assemble-time size check against the consumer's link budget ---
.import LIB_POLYVAL_ZP_USAGE_BYTES
.import LIB_POLYVAL_RESIDENT_BYTES
.assert LIB_POLYVAL_ZP_USAGE_BYTES <= 64, lderror, "ZP budget overrun"
.assert LIB_POLYVAL_RESIDENT_BYTES <= 8192, lderror, "code budget overrun"

; --- Routines + buffers (unchanged from v0.2.0) ---
.import polyval_init, polyval_precompute_table, polyval_update
.import gcmsiv_encrypt, gcmsiv_decrypt
.import polyval_h, polyval_temp
.import gcmsiv_nonce, gcmsiv_pt_buf, gcmsiv_pt_len, gcmsiv_ct_buf
.import gcmsiv_dec_buf, gcmsiv_tag

; ... host code, calling the imported routines ...
```

Consumers vendoring multiple c64-lib-contract adopters build every
library with `ca65 -D LIB_NO_BARE_EXPORTS=1` and import each
library's prefixed `LIB_<X>_*` symbols side by side — the bare
`LIB_VERSION_*` names collide across adopters and are removed at
contract v1.0. See the contract SPEC §1.

### 9.8 §4 — Segment placement declarations (`src/c64.cfg`, `src/lib_only.cfg`)

Added for contract v0.8.0. (Numbered out of SPEC order so the
established §9.1–§9.7 cross-references stay valid.) SPEC §4 requires
a library whose correctness or constant-time behaviour depends on
*how* its segments are placed to declare the load-bearing cfg
attributes as comments on the segment lines of its example cfg, each
stating the attribute, its required value, and the consequence of
getting it wrong; a consumer writing its own `SEGMENTS{}` block MUST
preserve them. c64-polyval declares, identically in both cfgs:

| Segment | Attribute | Class | Consequence if dropped |
|---|---|---|---|
| `LIB_POLYVAL_AES_RODATA` | `type = ro` in a file-emitting area | correctness | 522 initialised bytes (`aes_sbox`, `aes_inv_sbox`, `aes_rcon`) vanish; AES reads power-on garbage, and in `c64.cfg` (where file-emitting `DATA` follows) everything after the hole loads 522 bytes low. ld65 V2.18 warns — only because the bytes are non-zero (SPEC v0.8.3) — and links exit-0. |
| `LIB_POLYVAL_HTABLE` | `align = $100` | performance | hot-loop `abs,y` reads cross a page for some indices (+1 cycle); documented cycle counts (§2.1, §3) no longer hold. ld65 V2.18 emits **no diagnostic**. |
| `LIB_POLYVAL_LONG_HTABLE8` | `align = $100` | performance | same — every 256-byte slice inherits the segment's misalignment. Silent. |
| `LIB_POLYVAL_LONG_REDUCE8` | `align = $100` | performance | same. Silent. |

Two honesty notes. First, the alignment declarations are
**performance invariants, not correctness or CT invariants** — every
table access is a linker-resolved `abs,x` / `abs,y` with no
high-byte address arithmetic, so an unaligned table still computes
correct results, and this library is not constant-time in the first
place (§6, item 11), so a page-cross cycle is a benchmark deviation,
not a new leak class. They are declared anyway because the cfgs'
existing comments already promise the alignment, the §3/§9.4
cycle-count documentation depends on it, and the failure is the
silent kind. Second, the align dropout is completely silent: the
alignment exists only in the cfg (`src/data.s` reserves with `.res`,
no `.align` directive), so ld65 has no source-side request to check
and prints nothing at all. SPEC v0.8.3 corrected §4's risk table to
document exactly this shape — reported from c64-nist-curves'
adoption and corroborated with this library's measurements on
contract [#78](https://github.com/JC-000/c64-lib-contract/issues/78):
the §4 warning fires only against a source-level `.align`, and the
`bss` warning keys on byte value, so the common library shapes are
the silent ones.

Not declared: the `LIB_POLYVAL_*_CODE` segments and `ZEROPAGE` /
`STARTUP` / `LOADADDR` (no non-obvious placement sensitivity; ZP is
governed by §2/§9.2), the library BSS segments (any address works —
all access is via linker-resolved imports), and `DATA` (the library
emits no initialised read-write data; `DATA` carries demo-app bytes
only).
