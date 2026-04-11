; =============================================================================
; polyval_api.asm - Public API header for the c64-polyval library
;
; This file is the single-source description of the stable public API and
; calling conventions for the POLYVAL / AES-256 / AES-256-GCM-SIV library
; that lives under src/lib/. It is intentionally free of executable code
; and real memory allocations: the only things it emits are the profile-
; selector equates, which a host may reference before deciding how to
; !source the rest of the library.
;
; -----------------------------------------------------------------------------
; Integration modes
; -----------------------------------------------------------------------------
; 1. Source inclusion (recommended today).
;    The host assembles the library as part of its own translation unit:
;
;        !source "lib/polyval_api.asm"     ; documentation + profile equates
;        POLYVAL_PROFILE = POLYVAL_PROFILE_LONG
;        !source "lib/constants_lib.asm"
;        !source "lib/tables.asm"
;        !source "lib/aes_encrypt.asm"
;        !source "lib/aes_decrypt.asm"
;        !source "lib/polyval.asm"         ; dispatches short/long
;        !source "lib/gcm_siv.asm"
;        !source "lib/data.asm"
;
;    The linker (ACME) resolves all the symbols listed below automatically.
;
; 2. Binary blob (future / out of scope for this header).
;    The library is assembled once as a standalone PRG at a fixed load
;    address. A host then !source's only this file, plus a small table of
;    "symbol = $xxxx" equates produced by the library build, and calls in
;    via the fixed addresses. This header does NOT hard-code those
;    addresses - they must come from the library's build output
;    (build/labels.txt) and are only valid for a specific load address.
;
; -----------------------------------------------------------------------------
; Stable public API surface
; -----------------------------------------------------------------------------
; The following labels are the stable contract. Anything else in src/lib/
; is considered internal and may change without notice.
;
;   --- POLYVAL primitive (RFC 8452 section 3) ---
;   polyval_init              Clear the 128-bit accumulator.
;   polyval_precompute_table  Build the H-table(s) from polyval_h.
;                             Must be called once per new H before
;                             polyval_update / polyval_multiply.
;   polyval_update            Absorb one 16-byte block from polyval_temp
;                             into the accumulator (acc = (acc XOR block) * H).
;   polyval_multiply          Low-level GF(2^128) multiply: acc = acc * H.
;                             Exposed for tests and specialised callers.
;   polyval_double            Low-level GF(2^128) doubling (acc *= x).
;   polyval_shift_left_4      Low-level inlined 4-bit left shift with
;                             reduction. Used by the SHORT profile's
;                             multiply hot path; exposed for tests.
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
;   gcmsiv_decrypt            Full decrypt+verify. Tag status is returned
;                             via the Z flag and A (see header comment on
;                             gcmsiv_decrypt in lib/gcm_siv.asm):
;                                Z=1, A=0 -> tag valid, plaintext in
;                                            gcmsiv_dec_buf.
;                                Z=0, A=1 -> tag invalid, dec_buf zeroed,
;                                            gcmsiv_tag_valid = 0.
;                             The gcmsiv_tag_valid memory byte is also
;                             kept in sync for legacy callers.
;   gcmsiv_derive_keys        RFC 8452 key derivation from master key + nonce.
;   gcmsiv_compute_tag_base   Run POLYVAL over (AAD || PT || lengths) and
;                             leave the result in gcmsiv_tag_acc.
;   gcmsiv_finalize_tag       Apply the final AES-CTR to produce gcmsiv_tag.
;   gcmsiv_ctr_encrypt        AES-CTR keystream over gcmsiv_pt_buf ->
;                             gcmsiv_ct_buf.
;   gcmsiv_ctr_decrypt        AES-CTR keystream over gcmsiv_ct_buf ->
;                             gcmsiv_dec_buf.
;
; -----------------------------------------------------------------------------
; Stable public memory (library state buffers)
; -----------------------------------------------------------------------------
; These labels are allocated by lib/data.asm inside the
; POLYVAL_LIB_MEM_BASE region. A host may rely on their existence and
; sizes, but not on their absolute addresses (those are determined by
; where the library region is placed).
;
;   polyval_h           16 B   Input: hash key H for polyval_precompute_table
;   polyval_temp        16 B   Input: block for polyval_update
;   polyval_acc         16 B   ZP: the running 128-bit accumulator.
;                              Default address $10-$1F; overridable by
;                              pre-defining polyval_acc before !source'ing
;                              lib/constants_lib.asm.
;   polyval_htable     256 B   4-bit Shoup H-table (both profiles)
;   polyval_htable8    4 KB    8-bit Shoup slices (LONG profile only)
;   polyval_reduce8    4 KB    8-bit reduction slices (LONG profile only)
;
;   aes_current_key     32 B   Input: AES-256 master key
;   aes_expanded_key   240 B   Output of aes_key_expansion / working schedule
;   aes_state           16 B   In/out: the AES block being processed
;
;   gcmsiv_nonce        12 B   Input: 96-bit nonce
;   gcmsiv_pt_buf       64 B   Input (encrypt) / scratch (decrypt)
;   gcmsiv_pt_len        1 B   Length in bytes (0..64) of pt/ct
;   gcmsiv_ct_buf       64 B   Output (encrypt) / input (decrypt)
;   gcmsiv_dec_buf      64 B   Output of gcmsiv_decrypt
;   gcmsiv_tag          16 B   In/out: 128-bit auth tag
;   gcmsiv_auth_key     16 B   Derived POLYVAL auth key (internal/debug)
;   gcmsiv_enc_key      32 B   Derived AES-256 enc key (internal/debug)
;   gcmsiv_tag_valid     1 B   Legacy tag result: 1 = valid, 0 = invalid
;
; -----------------------------------------------------------------------------
; Override symbols (host may pre-define before !source'ing the library)
; -----------------------------------------------------------------------------
; POLYVAL_PROFILE            Set to POLYVAL_PROFILE_SHORT or
;                            POLYVAL_PROFILE_LONG. Default: LONG.
;                            See lib/constants_lib.asm for the trade-offs.
;
; POLYVAL_LIB_MEM_BASE       Absolute address where the library's
;                            non-ZP buffers should be placed. Default:
;                            "wherever * happens to be when lib/data.asm
;                            is sourced". lib/data.asm will error out if
;                            this override is below the current PC.
;
; POLYVAL_LIB_MEM_END        (Read-only, produced by the library.)
;                            First byte past the end of the library's
;                            buffer region. Host may use this to bound
;                            its own allocations or verify RAM budget.
;
; polyval_acc                ZP address of the 128-bit POLYVAL
;                            accumulator. Default $10 (uses $10-$1F).
; pv_mul_input               ZP address of the 16-byte multiply input
;                            scratch. Default $20 (uses $20-$2F).
; pv_mul_nibble              ZP address of the 1-byte nibble parameter
;                            for polyval_xor_table_entry. Default $30.
; zp_ptr, zp_ptr2, zp_temp, zp_count,
; zp_round, zp_col, zp_tmp1..zp_tmp4
;                            ZP scratch used by AES and GCM-SIV. Defaults
;                            listed in lib/constants_lib.asm. Each is
;                            wrapped in !ifndef so the host can override
;                            individually.
;
; -----------------------------------------------------------------------------
; Global calling-convention notes
; -----------------------------------------------------------------------------
; - All public routines are entered with JSR and return with RTS.
; - NONE of the routines are IRQ-safe: they all clobber shared zero-page
;   scratch (polyval_acc, pv_mul_input, pv_mul_nibble, zp_*). A host that
;   uses the library from an interrupt context (or whose foreground code
;   uses these ZP bytes) must SEI around the call or save/restore the
;   affected ZP ranges.
; - NONE of the routines are reentrant. A second call cannot begin until
;   the first has returned.
; - Flag state (C, V, N) on return is undefined unless explicitly noted in
;   a routine's header block. The one exception is gcmsiv_decrypt, which
;   uses Z + A to report tag validity (see that routine's header in
;   lib/gcm_siv.asm).
; - Registers A, X, Y are NOT preserved by any public routine unless the
;   per-routine header comment explicitly says so.
; =============================================================================

; --- Profile selector equates ----------------------------------------------
; These are the only equates this header actually emits. They are safe to
; !source multiple times and do not collide with lib/constants_lib.asm
; (which defines the same two values). A host that wants to pick a profile
; can do so by setting POLYVAL_PROFILE to one of these sentinels before
; !source'ing lib/constants_lib.asm.
!ifndef POLYVAL_PROFILE_SHORT { POLYVAL_PROFILE_SHORT = 1 }
!ifndef POLYVAL_PROFILE_LONG  { POLYVAL_PROFILE_LONG  = 2 }
