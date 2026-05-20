; =============================================================================
; exports.inc - Cross-module symbol dependency map for ca65 multi-object build
;
; Each library module lists what it EXPORTS (defines) and IMPORTS (uses from
; other modules). This file is the human-readable, link-time ABI companion to
; polyval_api.inc (which is the prose-level public-API contract) and to
; ca65/release/v0.1.0/include/abi_v1.inc (the frozen .global declarations
; downstream consumers should rely on).
;
; This file is .include'd by nothing; it is documentation. Converter agents
; and porters: add .export / .exportzp directives in the defining .s files
; matching the EXPORTS lists below, and .import / .importzp in any consuming
; module matching the IMPORTS lists.
;
; Scope: library modules under src/ that are linked into polyval.lib via
; lib_only.cfg. App-layer modules (main.s, boot.s, main_loop.s, display.s,
; disk_io.s, strings.s, gcm_siv_ui.s, data_app.s, zp.s) are NOT documented
; here -- they are the demo app, not part of the stable library ABI.
;
; Profile gating: symbols marked "LONG only" exist only when the file is
; assembled with -D POLYVAL_PROFILE=2 (POLYVAL_PROFILE_LONG). The SHORT
; profile (profile = 1) omits the 8-bit Shoup window tables.
; =============================================================================

; -----------------------------------------------------------------------------
; constants_lib.inc - Library-wide equates (pure .inc, no code, no .export)
; EXPORTS (as ca65 equates, picked up by `.include`):
;   ZP equates: polyval_zp_ptr, polyval_zp_ptr2, polyval_zp_temp, polyval_zp_count, polyval_aes_round, polyval_aes_col,
;               polyval_aes_tmp1, polyval_aes_tmp2, polyval_aes_tmp3, polyval_aes_tmp4,
;               polyval_acc, pv_mul_input, pv_mul_nibble
;   AES sizes:  aes_block_size, aes_key_size, aes_rounds, aes_expanded_key_size
;   Profile:    POLYVAL_PROFILE_SHORT (=1), POLYVAL_PROFILE_LONG (=2),
;               POLYVAL_PROFILE (default = LONG)
; IMPORTS: (none)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; polyval_api.inc - Public API prose header (pure .inc, no code, no .export)
; EXPORTS (as ca65 equates / documentation):
;   POLYVAL_PROFILE_SHORT, POLYVAL_PROFILE_LONG (idempotent re-declarations)
; IMPORTS: (none)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; zp_config.s - canonical c64-lib-contract §2 ZP slot inventory
; EXPORTS (via .exportzp, in this translation unit only):
;   polyval_acc, pv_mul_input, pv_mul_nibble,
;   polyval_zp_ptr, polyval_zp_ptr2, polyval_zp_temp, polyval_zp_count,
;   polyval_aes_round, polyval_aes_col,
;   polyval_aes_tmp1, polyval_aes_tmp2, polyval_aes_tmp3, polyval_aes_tmp4
; IMPORTS: (none - all .ifndef-guarded equates with default addresses)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; data.s - Library mutable state (BSS) + page-aligned Shoup tables
; EXPORTS:
;   POLYVAL buffers:
;     polyval_h, polyval_temp, polyval_htable
;   POLYVAL LONG-only Shoup 8-bit window tables:
;     polyval_htable8, polyval_htable8_s0..polyval_htable8_s15,
;     polyval_reduce8, polyval_reduce8_s0..polyval_reduce8_s15
;   AES buffers:
;     aes_current_key, aes_state, aes_expanded_key,
;     aes_mc_a0..aes_mc_a3, aes_mc_b0..aes_mc_b3
;   GCM-SIV buffers:
;     gcmsiv_nonce, gcmsiv_pt_buf, gcmsiv_pt_len, gcmsiv_ct_buf,
;     gcmsiv_dec_buf, gcmsiv_tag, gcmsiv_tag_acc,
;     gcmsiv_auth_key, gcmsiv_enc_key,
;     gcmsiv_counter, gcmsiv_keystream,
;     gcmsiv_block_idx, gcmsiv_ct_idx, gcmsiv_ks_idx,
;     gcmsiv_tag_valid, gcmsiv_verify_tag,
;     gcmsiv_saved_key, gcmsiv_exp_enc_key, gcmsiv_saved_exp
; IMPORTS: (none - pure data; equates come from constants_lib.inc via .include)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; tables.s - AES read-only lookup tables (RODATA)
; EXPORTS:
;   aes_sbox, aes_inv_sbox, aes_rcon
; IMPORTS: (none - pure data)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; aes_encrypt.s - AES-256 key expansion + forward block encrypt
; EXPORTS:
;   aes_encrypt_block, aes_key_expansion,
;   aes_sub_bytes, aes_shift_rows, aes_mix_columns, aes_add_round_key,
;   gf_mul2, gf_mul3
; IMPORTS:
;   data: aes_state, aes_expanded_key, aes_current_key
;   tables: aes_sbox, aes_rcon
;   (ZP scratch: polyval_zp_ptr, polyval_aes_round, polyval_aes_col, polyval_aes_tmp1..polyval_aes_tmp4 from
;    constants_lib.inc equates -- no .importzp needed)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; aes_decrypt.s - AES-256 inverse block decrypt
; EXPORTS:
;   aes_decrypt_block,
;   aes_inv_sub_bytes, aes_inv_shift_rows, aes_inv_mix_columns,
;   gf_mul_09, gf_mul_0b, gf_mul_0d, gf_mul_0e
; IMPORTS:
;   data: aes_state, aes_expanded_key,
;         aes_mc_a0..aes_mc_a3, aes_mc_b0..aes_mc_b3
;   tables: aes_inv_sbox
;   aes_encrypt: aes_add_round_key, gf_mul2
;   (ZP scratch: polyval_zp_ptr, polyval_aes_round, polyval_aes_col, polyval_aes_tmp1..polyval_aes_tmp4 from
;    constants_lib.inc equates)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; polyval_long.s - POLYVAL (RFC 8452 sec 3), LONG profile
;                  Shoup 8-bit fused shift+reduce+htable. Linked only when
;                  POLYVAL_PROFILE = POLYVAL_PROFILE_LONG (=2).
; EXPORTS:
;   polyval_init, polyval_precompute_table, polyval_update,
;   polyval_multiply, polyval_double, polyval_right_shift_1,
;   polyval_shift_left_4, polyval_xor_table_entry, polyval_finalize
; IMPORTS:
;   data: polyval_h, polyval_temp, polyval_htable,
;         polyval_htable8, polyval_htable8_s0..polyval_htable8_s15,
;         polyval_reduce8, polyval_reduce8_s0..polyval_reduce8_s15
;   (ZP: polyval_acc, pv_mul_input, pv_mul_nibble, polyval_zp_ptr, polyval_zp_temp,
;    polyval_zp_count from constants_lib.inc equates -- no .importzp needed)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; polyval_short.s - POLYVAL (RFC 8452 sec 3), SHORT profile
;                   4-bit Shoup table with Tier 1 unrolling. Linked only
;                   when POLYVAL_PROFILE = POLYVAL_PROFILE_SHORT (=1).
;                   Exports the same public surface as polyval_long.s so a
;                   downstream consumer can swap profiles at link time.
; EXPORTS:
;   polyval_init, polyval_precompute_table, polyval_update,
;   polyval_multiply, polyval_double, polyval_right_shift_1,
;   polyval_shift_left_4, polyval_xor_table_entry, polyval_finalize
; IMPORTS:
;   data: polyval_h, polyval_temp, polyval_htable
;   (ZP: polyval_acc, pv_mul_input, pv_mul_nibble, polyval_zp_ptr, polyval_zp_temp,
;    polyval_zp_count from constants_lib.inc equates)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; gcm_siv.s - AES-256-GCM-SIV AEAD (RFC 8452)
; EXPORTS:
;   gcmsiv_encrypt, gcmsiv_decrypt, gcmsiv_derive_keys,
;   gcmsiv_compute_tag_base, gcmsiv_finalize_tag,
;   gcmsiv_install_enc_key, gcmsiv_restore_orig_key,
;   gcmsiv_ctr_encrypt, gcmsiv_ctr_decrypt,
;   gcmsiv_gen_keystream, gcmsiv_derive_ctr
; IMPORTS:
;   aes_encrypt: aes_encrypt_block, aes_key_expansion
;   polyval_(long|short): polyval_init, polyval_update,
;                         polyval_precompute_table
;   data: aes_state, aes_expanded_key, aes_current_key,
;         polyval_h, polyval_temp,
;         gcmsiv_nonce, gcmsiv_pt_buf, gcmsiv_pt_len,
;         gcmsiv_ct_buf, gcmsiv_dec_buf,
;         gcmsiv_tag, gcmsiv_tag_acc,
;         gcmsiv_auth_key, gcmsiv_enc_key,
;         gcmsiv_counter, gcmsiv_keystream,
;         gcmsiv_block_idx, gcmsiv_ct_idx, gcmsiv_ks_idx,
;         gcmsiv_tag_valid, gcmsiv_verify_tag,
;         gcmsiv_saved_key, gcmsiv_exp_enc_key, gcmsiv_saved_exp
;   (ZP: polyval_acc, pv_mul_input, polyval_zp_ptr, polyval_zp_temp, polyval_zp_count,
;    polyval_aes_tmp1..polyval_aes_tmp4 from constants_lib.inc equates)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; Stable public ABI surface (per ca65/release/v0.1.0/include/abi_v1.inc)
;
; The subset of the above that downstream consumers (c64-wireguard,
; c64-https, ...) are promised across v0.1.x:
;
;   Routines:
;     polyval_init, polyval_precompute_table, polyval_update,
;     polyval_multiply,
;     aes_key_expansion, aes_encrypt_block, aes_decrypt_block,
;     gcmsiv_encrypt, gcmsiv_decrypt, gcmsiv_derive_keys
;
;   Buffers:
;     polyval_h, polyval_temp,
;     aes_current_key, aes_expanded_key, aes_state,
;     gcmsiv_nonce, gcmsiv_pt_buf, gcmsiv_pt_len,
;     gcmsiv_ct_buf, gcmsiv_dec_buf, gcmsiv_tag,
;     gcmsiv_auth_key, gcmsiv_enc_key, gcmsiv_tag_valid
;
;   Zero-page equates (pulled from constants_lib.inc, not linker symbols):
;     polyval_acc, pv_mul_input, pv_mul_nibble
;
; Symbols exported above but absent from abi_v1.inc (polyval_double,
; polyval_shift_left_4, polyval_xor_table_entry, polyval_finalize, the
; per-slice htable8/reduce8 labels, gf_mul2/3/09/0b/0d/0e, gcmsiv_compute_tag_base,
; gcmsiv_finalize_tag, gcmsiv_ctr_encrypt, gcmsiv_ctr_decrypt, ...) are
; cross-.o linker artifacts: present in the archive so the lib_main + test
; harness can resolve them, but NOT promised stable across major releases.
; -----------------------------------------------------------------------------
