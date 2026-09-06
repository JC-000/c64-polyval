.setcpu "6502"

; =============================================================================
; precalc_manifest.s - c64-polyval §8.0 precalc-table enumeration
;                      ISOLATED TRANSLATION UNIT
; =============================================================================
;
; This file exists ONLY to hold the LIB_PRECALC_TABLE invocations, and it
; must stay that way. It is not a stylistic split.
;
; c64-lib-contract SPEC §6.1 "Member isolation", quoted at v1.2.2 (the
; current text; added at v1.2.0, carve-out added at v1.2.1, rationale
; corrected at v1.2.2):
;
;   ld65 links whole archive members. A symbol a consumer may displace —
;   suppress under LIB_NO_BARE_EXPORTS, or define itself under APP_OWNED
;   (§8.0) — MUST live in a translation unit that exports nothing else a
;   consumer may import — their own prefixed counterparts excepted — and
;   defines nothing else the library's own code references.
;
; QUOTE THE CURRENT TEXT, and check which tag you are quoting. v1.2.0's
; wording lacked "their own prefixed counterparts excepted", and under
; THAT wording this very file would be non-conformant: it exports the
; prefixed LIB_POLYVAL_PRECALC_* names, which consumers do import. v1.2.1
; added the carve-out precisely because v1.2.0 had made §8.4 unsatisfiable
; by construction — one macro invocation emits both forms into one TU and
; adopters MUST NOT hand-edit the macro.
;
; The macro emits the deprecated BARE triple
; LIB_PRECALC_<name>_{SIZE,REGION,SHARED} unless LIB_NO_BARE_EXPORTS is
; defined. Those names carry no library prefix and are spelled identically
; in every §8.0/§8.4 adopter, so they are exactly the displaceable class
; the rule governs. Until this release they lived in src/lib_manifest.s
; beside the four §5 aggregate equates (LIB_POLYVAL_ZP_USAGE_BYTES,
; _REU_BANKS_USED, _RESIDENT_BYTES, _COLD_BYTES) a consumer imports for
; its footprint asserts, plus LIB_POLYVAL_GCMSIV_MAX_PT_LEN — which is a
; published input BOUND, not a footprint aggregate, and is absent from the
; three NO_AES archives, where this member exports four names rather than
; five. Importing any one of them pulled the whole member in and dragged
; the bare LIB_PRECALC_* names into the consumer's link uninvited (fifteen
; on LONG AEAD; nine on SHORT/COMPACT AEAD, three on the NO_AES archives —
; the count is profile- and variant-gated), where they collide with any
; other adopter's identically-named triple. The consumer cannot repair that: §6.1 bans
; ar65 member surgery.
;
; This is c64-lib-contract#177's shape, settled there at SPEC v1.2.0 and
; still forbidden under v1.2.1's carve-out, which excepts only a name's own
; prefixed counterparts: §5 aggregates are counterparts of nothing
; displaceable, so their co-residency with the bare triple remains a
; violation. That is stated in v1.2.1's own CHANGELOG entry.
; c64-x25519 fixed the identical defect in its v0.14.0 by the same split
; (their src/precalc_manifest.s); c64-nist-curves keeps the same shape.
;
; DO NOT add anything else to this file — no §5 aggregates, no §1 version
; equates, no code, no data. The whole value of the split is that a
; consumer importing something else never has to link this member.
;
; The BARE and PREFIXED forms stay TOGETHER here, deliberately. Both are
; emitted by one macro invocation per table, and a library's own prefixed
; counterparts are not the collision class the rule is about — nothing
; else in the fleet exports LIB_POLYVAL_PRECALC_*. Splitting them would
; mean hand-writing the triples instead of invoking the canonical macro.
;
; Discovery moved with the block: the audit command is now
;   od65 --dump-exports build/precalc_manifest.o | grep _PRECALC_
; (the pattern is `_PRECALC_`, not `LIB_PRECALC_` — the latter silently
; misses every prefixed export; SPEC v0.7.0.)
; =============================================================================

.ifndef PRECALC_MANIFEST_S_INCLUDED
PRECALC_MANIFEST_S_INCLUDED = 1

; constants_lib.inc defines POLYVAL_PROFILE_SHORT (=1),
; POLYVAL_PROFILE_LONG (=2) and POLYVAL_PROFILE_COMPACT (=3), plus the
; POLYVAL_PROFILE selector itself, which gates the htable8 / reduce8 rows
; below. It sets ZP_CONFIG_NO_EXPORTS=1 before pulling in zp_config.s, so
; this transitive include emits no consumer-facing exports of its own —
; which is also what keeps this TU isolated.
.include "constants_lib.inc"

; c64-lib-contract SPEC §8.0 catch-loop: canonical LIB_PRECALC_TABLE
; macro, copied verbatim from the contract repo. See the registrations
; below and docs/precalc-tables.md for the full enumeration.
.include "precalc_table.inc"


; -----------------------------------------------------------------------------
; §8.0 catch-loop: precalculated-table enumeration
; -----------------------------------------------------------------------------
; c64-lib-contract SPEC §8.4 requires every adopter to enumerate any
; precalculated table meeting the floor (>= 256 B AND one of:
; REU-resident, hot-loop-read, page-aligned for fetch alignment) via
; the LIB_PRECALC_TABLE macro, in addition to the docs/precalc-tables.md
; human-readable row. c64-polyval consumes none of the §8.1-§8.3 shared
; primitives (GF(2^128) carry-less multiply has no 8x8 quarter-square
; table), so LIB_POLYVAL_SHARED_PRIMITIVES is not emitted -- but the
; enumeration duty applies regardless. See docs/precalc-tables.md for
; the classification rationale behind each PRECALC_SHARED_NO below.
;
; The fifth macro argument is the SPEC v0.7.0 library prefix: each
; invocation emits both LIB_POLYVAL_PRECALC_<name>_* (collision-free,
; permanent) and the deprecated bare LIB_PRECALC_<name>_* triple, the
; latter gated on LIB_NO_BARE_EXPORTS (removal deferred to a future
; contract MAJOR — SPEC v1.0.0 §8.4). The
; prefix names the declaring library, never the table -- table names
; stay unprefixed per SPEC §8.1.
;
; polyval_htable is built by all three profiles; polyval_htable8 and
; polyval_reduce8 exist only under the LONG profile (SHORT and COMPACT
; use the 4-bit Shoup window alone instead of precomputing all 16 nibble
; positions x 16 possible values).
; -----------------------------------------------------------------------------
LIB_PRECALC_TABLE "polyval_htable", 256, PRECALC_REGION_RAM, PRECALC_SHARED_NO, "POLYVAL"

.if POLYVAL_PROFILE = POLYVAL_PROFILE_LONG
LIB_PRECALC_TABLE "polyval_htable8",  4096, PRECALC_REGION_RAM, PRECALC_SHARED_NO, "POLYVAL"
LIB_PRECALC_TABLE "polyval_reduce8",  4096, PRECALC_REGION_RAM, PRECALC_SHARED_NO, "POLYVAL"
.endif

; aes_sbox / aes_inv_sbox live in src/tables.s, which is a member of
; the AEAD archives (polyval.a / polyval-gcmsiv.a) and the full-app /
; lib-verify links only. The POLYVAL-only archives (polyval-long.a /
; polyval-short.a) omit tables.o, so their manifests must not describe
; 512 B of tables they do not ship (issue #23; same defect class as
; c64-lib-contract#62). Archive membership is an axis POLYVAL_PROFILE
; cannot express -- polyval-long.a and polyval-gcmsiv.a are both built
; at PROFILE=long -- so the lib-polyval-{long,short} Makefile targets
; pass -D LIB_POLYVAL_NO_AES=1 to suppress these two rows.
.ifndef LIB_POLYVAL_NO_AES
LIB_PRECALC_TABLE "aes_sbox",     256, PRECALC_REGION_RODATA, PRECALC_SHARED_NO, "POLYVAL"
LIB_PRECALC_TABLE "aes_inv_sbox", 256, PRECALC_REGION_RODATA, PRECALC_SHARED_NO, "POLYVAL"
.endif

.endif ; PRECALC_MANIFEST_S_INCLUDED
