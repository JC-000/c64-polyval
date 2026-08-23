# Precalculated tables (c64-lib-contract SPEC §8.0)

Per [SPEC §8.0](https://github.com/JC-000/c64-lib-contract/blob/main/SPEC.md#80-bit-allocation-for-lib_x_shared_primitives)
("Catch loop: enumeration at adopter intake"), every adopter must
enumerate any precalculated table meeting the floor — **size ≥ 256 B
AND** one of: REU-resident, hot-loop-read, or page-aligned for fetch
alignment. Enumeration is required regardless of whether a table is
a §8.x shared-primitive candidate; c64-polyval consumes none of the
current §8.1–§8.3 primitives (they cover the 8×8 quarter-square
multiply used by the elliptic-curve / ChaCha20 field-arithmetic
libraries — GF(2^128) carry-less multiplication has no equivalent
shared shape today), so every table below is classified
algorithm-specific.

Each row here has a matching `LIB_PRECALC_TABLE` invocation in
[`src/lib_manifest.s`](../src/lib_manifest.s), exported per the
canonical [`precalc_table.inc`](../src/precalc_table.inc) macro as
`LIB_POLYVAL_PRECALC_<name>_{SIZE,REGION,SHARED}` (SPEC v0.7.0
library-prefixed form, `"POLYVAL"` passed as the fifth macro argument)
plus the deprecated bare `LIB_PRECALC_<name>_{SIZE,REGION,SHARED}`
triple, which is gated on `LIB_NO_BARE_EXPORTS` and removed at
contract v1.0. Audits should grep `_PRECALC_`, which matches both
forms.

## Enumerated tables

| Name | Size | Region | Profile | Source | Classification | Rationale |
|---|---:|---|---|---|---|---|
| `polyval_htable` | 256 B | main RAM (page-aligned) | LONG + SHORT + COMPACT | `src/data.s` (`.segment "LIB_POLYVAL_HTABLE"`), built by `polyval_precompute_table` in `src/polyval_long.s` / `src/polyval_short.s` / `src/polyval_compact.s` | algorithm-specific | Shoup 4-bit window over GF(2^128): 16 precomputed multiples of H, 16 B each. Indexed `abs,y` in the innermost nibble-processing loop of every profile, hence page-aligned and hot-loop-read. No sibling library performs GF(2^128) carry-less multiplication, so this shape has no shared-primitive candidate. |
| `polyval_htable8` | 4096 B | main RAM | LONG only | `src/data.s` (`.segment "LIB_POLYVAL_LONG_HTABLE8"`), built by `polyval_precompute_table` in `src/polyval_long.s` | algorithm-specific | 16 sub-tables (`_s0`..`_s15`) of 256 B each, one per byte position of the 128-bit accumulator, extending the Shoup window to an 8-bit fused shift+reduce+multiply. Hot-loop-read once per input byte in `polyval_multiply` (LONG profile). Exists only when `POLYVAL_PROFILE = POLYVAL_PROFILE_LONG` — the §8.0 registration in `lib_manifest.s` is gated on the same selector. |
| `polyval_reduce8` | 4096 B | main RAM | LONG only | `src/data.s` (`.segment "LIB_POLYVAL_LONG_REDUCE8"`), built alongside `polyval_htable8` | algorithm-specific | Companion reduction table to `polyval_htable8` — precomputed GF(2^128) modular-reduction constants per byte position, same hot-loop-read access pattern and profile gating. |
| `aes_sbox` | 256 B | RODATA | AEAD archives only (`polyval.a` / `polyval-gcmsiv.a` / `polyval-gcmsiv-short.a`) | `src/tables.s` | algorithm-specific (flagged for future audit) | Standard FIPS-197 AES S-box, read once per byte in every `SubBytes` step of `aes_encrypt_block` / key expansion. Hot-loop-read. Not currently a §8.x candidate because no other current adopter (`c64-nist-curves`, `c64-x25519`, `c64-ChaCha20-Poly1305`) implements AES — but this is the byte-for-byte standard S-box, so if `c64-aes256-ecdsa` or another AES-consuming library joins the contract, this table (and `aes_inv_sbox` below) is the first candidate for a future §8.x promotion audit per the SPEC §8.0 "generalisation" trigger. |
| `aes_inv_sbox` | 256 B | RODATA | AEAD archives only (`polyval.a` / `polyval-gcmsiv.a` / `polyval-gcmsiv-short.a`) | `src/tables.s` | algorithm-specific (flagged for future audit) | Inverse AES S-box, read once per byte in every `InvSubBytes` step of `aes_decrypt_block`. Same future-audit note as `aes_sbox`. |

The Profile column tracks two independent axes (issue #23). The
`polyval_*` tables vary by **profile** — their manifest rows are gated
on `POLYVAL_PROFILE`, which the per-profile archive targets pin via
recursive make. The AES tables vary by **archive membership**: they
live in `src/tables.s`, a member of all three AEAD archives
(`polyval.a` / `polyval-gcmsiv.a` / `polyval-gcmsiv-short.a`, and the
full-app / `lib-verify` links) but not of the POLYVAL-only archives
(`polyval-long.a` / `polyval-short.a`).
Profile cannot express that axis — `polyval-long.a` and
`polyval-gcmsiv.a` are both built at `PROFILE=long`, while
`polyval-gcmsiv-short.a` and `polyval-short.a` are both built at
`PROFILE=short` yet differ in AES membership — so the
`lib-polyval-{long,short}` targets pass `-D LIB_POLYVAL_NO_AES=1`,
which suppresses the two AES rows in `src/lib_manifest.s`. A manifest
must never describe tables its archive does not ship (same defect
class as [c64-lib-contract#62](https://github.com/JC-000/c64-lib-contract/issues/62)).

## Below the floor (exempt, not enumerated)

| Name | Size | Why exempt |
|---|---:|---|
| `aes_rcon` | 10 B | Below the 256 B floor. |
| `aes_expanded_key`, `aes_current_key`, `aes_state` | 240 B / 32 B / 16 B | Per-call runtime state (the expanded round-key schedule, the installed key, the working cipher state), not a precomputed lookup table — regenerated per key install, not read as a fixed table. |
| `gcmsiv_exp_enc_key`, `gcmsiv_saved_exp` | 256 B each | Per-message scratch buffers holding a *copy* of the expanded key during GCM-SIV's key-derivation dance (`src/gcm_siv.s`), not precalculated table data. Excluded on the same "runtime state, not a table" grounds as the AES key schedule above, independent of the 256 B floor. |
| All other `gcmsiv_*` / `aes_mc_*` buffers | ≤ 64 B each | Below the floor. |
| ZP scratch (`polyval_acc`, `pv_mul_input`, etc.) | ≤ 16 B each | Below the floor by construction (zero page). |

c64-polyval consumes no REU, so no table here is REU-resident; all
listed tables qualify via hot-loop-read (and `polyval_htable` also
via page-alignment).
