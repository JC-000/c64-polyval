# c64-polyval v0.9.0 — 2026-08-31

**Hardening MINOR** from an adversarial audit of this library against
[`cryptography.hazmat`](https://cryptography.io/) as an independent
oracle (2026-08-28). Two latent defects fixed, one documentation error
corrected, and the test suite rebuilt so that the checks which found
them are permanent and have been demonstrated capable of failing.
Closes [#69](https://github.com/JC-000/c64-polyval/issues/69),
[#70](https://github.com/JC-000/c64-polyval/issues/70),
[#71](https://github.com/JC-000/c64-polyval/issues/71),
[#72](https://github.com/JC-000/c64-polyval/issues/72),
[#73](https://github.com/JC-000/c64-polyval/issues/73),
[#74](https://github.com/JC-000/c64-polyval/issues/74) and
[#75](https://github.com/JC-000/c64-polyval/issues/75). The full
per-change log is in
[`CHANGELOG.md`](https://github.com/JC-000/c64-polyval/blob/v0.9.0/CHANGELOG.md);
this file is the concise release summary.

Nothing exported was added, removed or renamed, so
`LIB_POLYVAL_ABI_VERSION` stays **1**. **This release makes no
byte-identity claim** — the fixes add code, and the PRGs differ from
v0.8.0 by design (sizes below).

## What the audit found, and did not find

**It did not find a cryptographic defect.** POLYVAL and AES-256-GCM-SIV
agree with hazmat's `AESGCMSIV` and with an independently written
RFC 8452 oracle — deliberately built on different mathematics from this
repo's Python reference, schoolbook carry-less multiply with an explicit
`x^-128` by exponentiation rather than a shift loop — on **all three
profiles**, across:

- adversarial `H` values (0, 1, top-bit-set, all-`FF`, the RFC vector, random);
- message shapes to 1 KiB, including repeated blocks and all-`FF` blocks;
- all-zero and all-`FF` keys and nonces, at every message length 0..64;
- RFC 8452 §4 key derivation, the length-block encoding, and the tag
  MSB handling;
- CTR counter wrap at every 32-bit little-endian byte boundary;
- an exhaustive single-bit forgery sweep — every one of 128 tag bits,
  136 ciphertext bits and 96 nonce bits — each rejected with `A=1` and
  the plaintext buffer wiped.

Both defects it did find sit at the AEAD entry points, in reachability
and memory safety rather than in the field arithmetic.

## The two defects

**1. A 16-byte buffer overrun past the AES key schedule** (issue #69).
`gcmsiv_install_enc_key`, `gcmsiv_restore_orig_key` and the `@copy_exp`
loop in `gcmsiv_derive_keys` looped with `inx / bne` — 256 iterations —
into the 240-byte `aes_expanded_key`. The 16 bytes past the schedule
(`aes_mc_*` and `gcmsiv_nonce[0..7]` in the shipped layout; whatever a
consumer's linker places there in general) were snapshotted at key
derivation and transiently overwritten during every tag-finalise and
CTR window, with any write made to them inside that window silently
reverted by the restore.

**This was invisible to every existing test, and would have stayed
invisible.** The documented call sequence is save → install → work →
restore, and the nonce is read *before* the install and never inside the
window, so the corruption healed itself before anything could observe
it: all 376 tests passed, and all RFC vectors matched. It is a latent
memory-safety defect for any consumer whose linker places live state in
those 16 bytes — and one that an interrupt handler writing there would
have turned into silent data loss. All three loops now terminate at
`aes_expanded_key_size` (240), and the two 256-byte scratch copies
shrink to 240.

**2. No bounds check on `gcmsiv_pt_len`** (issue #70). Neither entry
point validated the length, and `gcmsiv_pt_len` sat immediately after
the 64-byte `gcmsiv_pt_buf`. At `pt_len = 65` the 65th plaintext byte
read was the length byte itself, and ciphertext byte 64 landed in
`gcmsiv_dec_buf[0]`. At `pt_len >= 128` the tag loop's `bmi` guard
treated the remaining count as negative and hashed **no data blocks at
all** — only the length block — while CTR wrote `pt_len` bytes across
the decrypt buffer, the tag, the derived keys, and the live counter and
keystream. The routine returned normally, with a wrong tag and no error.

This is outside the documented 0..64 domain, but "documented" was doing
too much work: nothing enforced it and nothing announced the breach.
Both entry points now check before touching any state and reject
`> gcmsiv_max_pt_len` with `A=1` / `Z=0`, the tag-failure convention
`gcmsiv_decrypt` already used. `gcmsiv_encrypt` writes nothing on
rejection; `gcmsiv_decrypt` wipes `gcmsiv_dec_buf` and clears
`gcmsiv_tag_valid` exactly as a bad tag does. `gcmsiv_pt_len` also moves
away from `gcmsiv_pt_buf` in `src/data.s` as defence in depth.

`gcmsiv_max_pt_len = 64` is published as an equate in
`src/constants_lib.inc`, with the buffers sized from it — a bound a
consumer can assert against rather than a number living only in prose.

**3. A documentation error** (issue #71). `API.md` §6 and all three
profile headers said `polyval_precompute_table` clobbers `polyval_h`.
Measured on LONG, SHORT and COMPACT: it preserves it — none of the three
back-ends contains a store to `polyval_h`. A consumer following the docs
was saving 16 bytes for nothing. §6 item 7's stale ~30,000-cycle SHORT
precompute figure is also corrected to the measured 4,656 (COMPACT
10,970, LONG 255,268).

## Verification is now three profiles, not one

`tools/run_all_tests.py` built with a plain `make` and had no profile
loop, so the documented entry point certified **LONG only** — SHORT and
COMPACT shipped uncertified by it. Two other checks were structurally
incapable of reporting: the random round-trip budget was
`iterations - (2 × no-AAD vectors + 1)`, which at the default left room
for only the 1- and 15-byte cases, so the 16/17/32/48/63/64 boundaries
never ran; and the hazmat cross-validation of the Python reference was
never invoked by the runner at all.

`--profile {long,short,compact,all}` now defaults to **all**:

| profile | passed | skipped | failed |
|---|---|---|---|
| LONG    | 1253 | 6 | 0 |
| SHORT   | 1253 | 6 | 0 |
| COMPACT | 1253 | 6 | 0 |

The 6 skips are the RFC 8452 non-empty-AAD vectors, which GCM-SIV
intentionally does not support (`API.md` §6).

New in `tools/`:

- **`hazmat_oracle.py`** — the independent RFC 8452 oracle, self-verifying
  on import against the Appendix A worked example, seven C.2 vectors and
  the `1 + x^-1 + x^-2 + x^-7` identity. `cryptography` is optional: its
  cross-checks become counted skips when it is absent.
- **`test_hazmat_fuzz.py`** — the audit's six-section differential
  driver, 496 checks per profile.
- **`test_gcmsiv_bounds.py`** — permanent regression tests for #69 and
  #70, asserting memory state rather than return codes: the 16-byte
  window is located from the label file, poisoned, and must survive
  install and restore; the out-of-domain lengths must return `A=1`,
  wipe `dec_buf`, and leave every surrounding buffer untouched.

**These checks were demonstrated capable of failing.** Against the
pre-fix tree they are red — 1245 passed / 6 skipped / **8 failed** on
each of the three profiles, the 8 being exactly the #69 and #70
regressions, with no other suite reporting a failure. After the fixes,
1253 / 6 / **0**. A check never observed to fail is evidence only that
it ran.

## Footprint values per archive

Per c64-lib-contract §6.6, one row per shipped archive — seven rows,
stated even where a value is unchanged, because a tag carries a
footprint pair per archive and a single per-version delta would be
meaningless.

**No declared value moves this cycle**, and `declared >= measured`
holds on every row in the safe direction:

| Archive | Configuration | RESIDENT (declared / measured) | COLD (declared / measured) |
|---|---|---|---|
| `polyval.a` | LONG AEAD | 6656 / 6609 (was 6567) | 1280 / 1239 |
| `polyval-gcmsiv.a` | LONG AEAD | 6656 / 6609 (was 6567) | 1280 / 1239 |
| `polyval-gcmsiv-short.a` | SHORT AEAD | 16128 / 16063 (was 16021) | 3072 / 3059 |
| `polyval-gcmsiv-compact.a` | COMPACT AEAD | 2816 / 2774 (was 2732) | 512 / 339 |
| `polyval-long.a` | LONG, no AES | 4352 / 4160 (unchanged) | 1280 / 1047 |
| `polyval-short.a` | SHORT, no AES | 13824 / 13614 (unchanged) | 3072 / 2867 |
| `polyval-compact.a` | COMPACT, no AES | 512 / 325 (unchanged) | 256 / 147 |

The three AEAD archives grew **42 bytes** —
`LIB_POLYVAL_GCMSIV_CODE` 805 → 847 B, the bounds checks of #70 and the
loop terminators of #69. The four POLYVAL-only rows are unchanged in
both columns. Declared values are read from each archive's own
`lib_manifest.o`; measured values are the link span, cross-checked
against the per-member `type = ro` segment sum.

**Headroom worth knowing:** `polyval-gcmsiv-short.a` is the tightest at
**65 bytes** below its declared RESIDENT ceiling. A consumer asserting
against 16128 still passes, but that archive is the one to watch.

`LIB_POLYVAL_GCMSIV_BSS` **shrank** 881 → 849 B (the two scratch key
copies going 256 → 240 each), and its internal layout changed. BSS is
not part of `RESIDENT_BYTES`, so no manifest equate reflects either
fact — see the upgrade note below.

## If you are upgrading

1. **If you hard-coded a `LIB_POLYVAL_GCMSIV_BSS` buffer offset relative
   to another buffer, re-link.** The segment shrank 881 → 849 B and its
   layout changed: `gcmsiv_exp_enc_key` and `gcmsiv_saved_exp` are 240 B
   each instead of 256, and `gcmsiv_pt_len` moved after
   `gcmsiv_dec_buf`. No manifest equate reflects this — BSS is not part
   of `RESIDENT_BYTES`. Every documented buffer keeps its size and
   segment membership, and
   consumers that `.import` the labels are unaffected. This is the only
   change here that can require action.
2. **If you pass a length above 64, you now get an error instead of a
   wrong tag.** Previously out-of-domain lengths were undefined
   behaviour that returned normally; they now return `A=1` / `Z=0`.
   Assert against `gcmsiv_max_pt_len` rather than a literal 64.
3. `gcmsiv_encrypt` now defines `A` on success (`A=0` / `Z=1`), where it
   was previously undefined. Callers that ignored it are unaffected.
4. **If you saved `polyval_h` across `polyval_precompute_table`, you can
   stop** — it was never clobbered on any profile.
5. **If you quoted SHORT's ~30,000-cycle precompute figure, correct it
   to 4,656.**
6. Declared `RESIDENT` / `COLD` values are unchanged from v0.8.0, so
   existing §6.6 consumer asserts continue to hold.

See [`API.md`](https://github.com/JC-000/c64-polyval/blob/v0.9.0/API.md)
§3 for profile selection and §9 for the full contract surface.

## Contract currency

Unchanged in substance at SPEC **v0.15.0** (the contract's latest tag;
v0.14.2 and v0.15.0 are §8.1/§8.4 clauses that do not apply here — this
library has no `sqtab` and has released consumers, so the zero-consumer
carve-out is inapplicable).

Two normative clauses are in flight upstream that this release already
satisfies, both citing work from this cycle: an **entry-point
termination and documented domain** clause, whose published-bound
mechanism cites `gcmsiv_max_pt_len` by name as an adopter arriving at
the pattern before the clause existed; and a **conformance evidence**
clause requiring that a check offered as evidence be shown capable of
failing, which the red/green pair above demonstrates. Neither is tagged
at the time of writing, so neither is claimed as adopted.

## Attestation

`c64-polyval-v0.9.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.9.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.9.0.tar.gz` |
| **Size**   | 120971 bytes |
| **SHA256** | `89c9278e9357b70b8d83fdea1fec67daf487c351499409939e174a6befc60e98` |

Re-running `make dist VERSION=v0.9.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime
is forced to `2026-08-31T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.
