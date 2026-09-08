; =============================================================================
; lib/polyval_api.inc - Public API header for the c64-polyval library (ca65)
;
; This file is the single-source description of the stable public API and
; calling conventions for the POLYVAL / AES-256 / AES-256-GCM-SIV library
; under ca65/src/lib/. It emits no executable code and no memory: only the
; profile-selector equates.
;
; -----------------------------------------------------------------------------
; Stable public API surface
; -----------------------------------------------------------------------------
;   --- POLYVAL primitive (RFC 8452 section 3) ---
;   polyval_init              Clear the 128-bit accumulator.
;   polyval_precompute_table  Build the H-table(s) from polyval_h.
;   polyval_update            Absorb one 16-byte block from polyval_temp into
;                             the accumulator (acc = (acc XOR block) * H).
;   polyval_multiply          Low-level GF(2^128) multiply: acc = acc * H.
;   polyval_double            Low-level GF(2^128) doubling (acc *= x).
;   polyval_shift_left_4      Low-level inlined 4-bit left shift with
;                             reduction (SHORT / COMPACT hot path).
;   polyval_xor_table_entry   XOR the 4-bit H-table entry selected by
;                             pv_mul_nibble into the accumulator.
;
;   --- AES-256 primitive ---
;   aes_key_expansion         Expand aes_current_key into aes_expanded_key.
;   aes_encrypt_block         Encrypt aes_state in place using aes_expanded_key.
;   aes_decrypt_block         Decrypt aes_state in place using aes_expanded_key.
;
;   --- AES-256-GCM-SIV AEAD ---
;   gcmsiv_encrypt            Full encrypt+auth over the configured buffers.
;   gcmsiv_decrypt            Full decrypt+verify. Z=1/A=0 => valid,
;                             Z=0/A=1 => invalid (dec_buf zeroed).
;   gcmsiv_derive_keys        RFC 8452 key derivation (master key + nonce).
;   gcmsiv_compute_tag_base   POLYVAL over (AAD || PT || lengths) -> tag_acc.
;   gcmsiv_finalize_tag       Final AES-CTR to produce gcmsiv_tag.
;   gcmsiv_ctr_encrypt        AES-CTR keystream over pt_buf -> ct_buf.
;   gcmsiv_ctr_decrypt        AES-CTR keystream over ct_buf -> dec_buf.
;
; -----------------------------------------------------------------------------
; Stable public memory (library state buffers)
; -----------------------------------------------------------------------------
;   polyval_h           16 B   Input: hash key H
;   polyval_temp        16 B   Input: block for polyval_update
;   polyval_acc         16 B   ZP: running 128-bit accumulator ($10-$1F)
;   polyval_htable     256 B   4-bit Shoup table (all three profiles)
;   polyval_htable8    4 KB    8-bit Shoup slices (LONG only)
;   polyval_reduce8    4 KB    8-bit reduction slices (LONG only)
;
;   aes_current_key     32 B   Input: AES-256 master key
;   aes_expanded_key   240 B   Output of aes_key_expansion
;   aes_state           16 B   In/out: AES block being processed
;
;   gcmsiv_nonce        12 B   Input: 96-bit nonce
;   gcmsiv_pt_buf       64 B   Input (encrypt) / scratch (decrypt)
;   gcmsiv_pt_len        1 B   Length in bytes (0..64) of pt/ct
;   gcmsiv_ct_buf       64 B   Output (encrypt) / input (decrypt)
;   gcmsiv_dec_buf      64 B   Output of gcmsiv_decrypt
;   gcmsiv_tag          16 B   In/out: 128-bit auth tag
;   gcmsiv_auth_key     16 B   Derived POLYVAL auth key
;   gcmsiv_enc_key      32 B   Derived AES-256 enc key
;   gcmsiv_tag_valid     1 B   Legacy tag result: 1 = valid, 0 = invalid
;
; -----------------------------------------------------------------------------
; Global calling-convention notes
; -----------------------------------------------------------------------------
; - All public routines are entered with JSR and return with RTS.
; - NONE of the routines are IRQ-safe; they clobber shared ZP scratch.
; - NONE of the routines are reentrant.
; - Flag state (C, V, N) on return is undefined unless explicitly noted.
;   Exception: gcmsiv_decrypt uses Z + A to report tag validity.
; - Registers A, X, Y are NOT preserved unless a routine's header says so.
; =============================================================================

.ifndef POLYVAL_API_INC_
POLYVAL_API_INC_ = 1

; --- Profile selector equates ----------------------------------------------
; Safe to .include multiple times. Same sentinels as constants_lib.inc; a
; host can pre-define POLYVAL_PROFILE to one of these before .include'ing
; constants_lib.inc to pick a profile.
.ifndef POLYVAL_PROFILE_SHORT
    POLYVAL_PROFILE_SHORT = 1
.endif
.ifndef POLYVAL_PROFILE_LONG
    POLYVAL_PROFILE_LONG  = 2
.endif
.ifndef POLYVAL_PROFILE_COMPACT
    POLYVAL_PROFILE_COMPACT = 3
.endif


; -----------------------------------------------------------------------------
; Public symbol declarations
; -----------------------------------------------------------------------------
; This file is shipped as build/lib/polyval.inc by every archive target --
; a local choice, not a contract requirement: SPEC v1.1.0 §6.1 briefly
; demanded a shipped header and v1.1.1 withdrew that as an artifact of the
; 1.0.0 text cut. We ship it because a consumer linking the archive needs
; it. Through
; v0.10.0 it declared nothing -- it was a comment block plus the three
; profile equates above -- so a consumer who included it still had to
; hand-author every `.import` from prose, which is what
; test/consumer_stub_shipped.s was doing. The sibling fleet's shape is to
; declare: c64-x25519's shipped src/x25519.inc carries 31 declarations.
;
; `.global`, not `.import`, deliberately. .global resolves to an import in
; a TU that does not define the symbol and to an export in one that does,
; so this file stays safe to include from a library TU as well as a
; consumer one. Two properties were measured before adding this block,
; because both are the kind of thing that would quietly punish a consumer:
;
;   1. An UNREFERENCED declaration of a symbol the linked archive does not
;      contain does NOT fail the link. A POLYVAL-only consumer linking
;      polyval-long.a (no AES, no GCM-SIV) links clean with the AEAD names
;      declared here. ld65 only errors on unresolved symbols that are
;      actually referenced.
;   2. An UNREFERENCED declaration does NOT drag its archive member into
;      the image. Measured against polyval.a: baseline stub 4166 bytes,
;      and 4166 bytes with all nine AES/GCM-SIV entry points declared and
;      none called. No bloat, so declaring the full surface costs a
;      consumer who uses one corner of it nothing.
;
; Suppress the whole block with `-D POLYVAL_API_NO_DECLS=1` if you would
; rather author your own import list.
;
; ZERO PAGE IS NOT DECLARED HERE. The §2 slots (polyval_acc, pv_mul_input,
; polyval_zp_ptr, ...) are `.importzp`, a different directive with a
; different address size, and a consumer overriding a slot via
; CONTRACT_ZP_DEFINES must NOT also import it (SPEC §6.2: a `-D` of an
; imported name is `Symbol already defined`). Import the ones you need
; yourself; the inventory is in API.md §4 and exported from the archive's
; zp_config.o.
;
; NAMESPACE FOOTPRINT IF YOU VENDOR src/zp_config.s (v0.11.0+, issue #105).
; Linking the archive costs you nothing here -- this note is only for a
; consumer who `.include`s zp_config.s or constants_lib.inc into their own
; translation unit, which is documented override route 3. That file's slot
; distinctness checks occupy these names in the including TU, all reserved
; under the PV_ZP_ prefix:
;
;   macros   PV_ZP_SLOT_LIST  PV_ZP_CHECK_RANGE  PV_ZP_CHECK_PAIR
;            PV_ZP_CHECK_AGAINST_REST  PV_ZP_COUNT_SLOT  PV_ZP_EXPORT
;   symbols  PV_ZP_OUTER_IDX  PV_ZP_OUTER_ADDR  PV_ZP_OUTER_SIZE
;            PV_ZP_PAIR_COUNT  PV_ZP_SLOT_COUNT
;   .define  PV_ZP_OUTER_NAME (defined and undefined inside one expansion,
;            so it is not live afterwards, but the name is still taken while
;            zp_config.s is being read)
;
; plus PV_ZP_SELFTEST, which is read but never defined by the library and is
; yours to leave alone. A collision surfaces at assembly time as
; `Symbol 'PV_ZP_...' is already different kind` or a macro redefinition
; error, so it cannot be silent. Additive-only: no previously usable name
; became unusable, and nothing here is exported into your link.
; -----------------------------------------------------------------------------

.ifndef POLYVAL_API_NO_DECLS

    ; --- POLYVAL primitive (all three profiles) ---
    .global polyval_init
    .global polyval_precompute_table
    .global polyval_update
    .global polyval_finalize
    .global polyval_multiply
    .global polyval_double

    ; --- POLYVAL state (src/data.s) ---
    .global polyval_h
    .global polyval_temp

    ; --- AES-256 primitive (absent from the POLYVAL-only archives) ---
    .global aes_key_expansion
    .global aes_encrypt_block
    .global aes_decrypt_block
    .global aes_current_key
    .global aes_expanded_key
    .global aes_state

    ; --- AES-256-GCM-SIV AEAD (absent from the POLYVAL-only archives) ---
    .global gcmsiv_encrypt
    .global gcmsiv_decrypt
    .global gcmsiv_derive_keys
    .global gcmsiv_compute_tag_base
    .global gcmsiv_finalize_tag
    .global gcmsiv_ctr_encrypt
    .global gcmsiv_ctr_decrypt

    ; --- GCM-SIV buffers (src/data.s) ---
    .global gcmsiv_nonce
    .global gcmsiv_tag
    .global gcmsiv_pt_buf
    .global gcmsiv_ct_buf
    .global gcmsiv_dec_buf
    .global gcmsiv_pt_len
    .global gcmsiv_tag_valid

.endif ; POLYVAL_API_NO_DECLS

.endif ; POLYVAL_API_INC_
