; =============================================================================
; polyval.asm - POLYVAL dispatch shim
;
; Selects one of two POLYVAL implementations at assemble time based on
; POLYVAL_PROFILE (defined in constants.asm; default LONG).
;
;   POLYVAL_PROFILE_SHORT -> polyval_short.asm
;       4-bit Shoup window, Tier 1 unrolling. Latency-optimised for
;       RFC 8452 GCM-SIV where the auth key H is rederived per message
;       and precompute runs on every call. ~29k cycles precompute,
;       ~19k cycles multiply.
;
;   POLYVAL_PROFILE_LONG  -> polyval_long.asm
;       Shoup 8-bit window with fused shift+reduce+htable inner loop.
;       Throughput-optimised for long messages with a stable H
;       (TLS 1.3, WireGuard). ~255k cycles precompute, ~4k cycles
;       multiply.
;
; Both profiles export the same public symbols:
;   polyval_init, polyval_multiply, polyval_update, polyval_precompute_table,
;   polyval_double, polyval_shift_left_4, polyval_xor_table_entry,
;   polyval_h, polyval_temp, polyval_htable
; so an application can link either profile interchangeably.
; =============================================================================

!if POLYVAL_PROFILE = POLYVAL_PROFILE_SHORT {
        !source "lib/polyval_short.asm"
} else {
        !if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG {
                !source "lib/polyval_long.asm"
        } else {
                !error "POLYVAL_PROFILE must be POLYVAL_PROFILE_SHORT or POLYVAL_PROFILE_LONG"
        }
}
