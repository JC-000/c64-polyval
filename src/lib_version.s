; =============================================================================
; lib_version.s - c64-polyval library version constants
;
; Implements c64-lib-contract §1 (Version identification). See
; ../../c64-lib-contract/SPEC.md, section "1. Version identification".
;
; Consumers import these for link-time compatibility checks. An
; .import'ed symbol's value is not known until link, so gate with
; .assert using the lderror action (evaluated by ld65 at link time), never
; with .if/.error — that fails to assemble with "Constant expression
; expected" (c64-lib-contract issue #73):
;
;   .import LIB_POLYVAL_VERSION_MAJOR, LIB_POLYVAL_VERSION_MINOR
;   .assert LIB_POLYVAL_VERSION_MAJOR = 0, lderror, "c64-polyval 0.x required"
;   .assert LIB_POLYVAL_VERSION_MINOR >= 4, lderror, "v0.4 or newer required"
;
; Versioning policy: semver 2.0.0 - https://semver.org/
;   MAJOR             - incompatible API changes (symbol removals,
;                       calling-convention changes)
;   MINOR             - additive API changes (new exports, no removals
;                       or renames of existing exports)
;   PATCH             - bugfix or perf improvement with no API change
;   ABI_VERSION       - ABI compatibility level. Bumped only when the
;                       public symbol set or calling convention
;                       changes. Coarser than MINOR; consumers that
;                       don't care about which patch level can pin to
;                       ABI alone.
;
; The library is currently in the v0.x pre-stable series. MINOR bumps
; may add public symbols but will not remove or rename existing
; symbols without a MAJOR bump. Consumers should pin to a specific
; git tag, not track the mainline branch.
;
; Two export forms per SPEC v0.7.0 (contract #43): the library-prefixed
; LIB_POLYVAL_* names are the permanent, collision-free form a consumer
; linking multiple adopters imports side by side. The unprefixed names
; are identical across every adopter library — that collision is the
; reason they are DEPRECATED and removed at contract v1.0. Until then
; they remain required for existing single-library consumers, gated on
; LIB_NO_BARE_EXPORTS (ca65 -D LIB_NO_BARE_EXPORTS=1) so a composing
; consumer can suppress them build-wide. The bare form aliases the
; prefixed literals rather than restating them, so the two cannot
; drift; a release bump touches only the four LIB_POLYVAL_* lines.
;
; SPEC §1 TU isolation: this file exports the version equates and
; nothing else, so importing any other library symbol can never drag
; the collision-prone bare names into a consumer's link uninvited.
; The §5 aggregate manifest equates live in src/lib_manifest.s.
; =============================================================================

.setcpu "6502"

LIB_POLYVAL_VERSION_MAJOR = 0
LIB_POLYVAL_VERSION_MINOR = 8
LIB_POLYVAL_VERSION_PATCH = 0
LIB_POLYVAL_ABI_VERSION   = 1

; Exported as absolute (16-bit) symbols, not zeropage. ca65 would otherwise
; infer zeropage size because the values fit in a byte, which then mismatches
; consumer `.import` declarations that default to absolute.
.export LIB_POLYVAL_VERSION_MAJOR: abs
.export LIB_POLYVAL_VERSION_MINOR: abs
.export LIB_POLYVAL_VERSION_PATCH: abs
.export LIB_POLYVAL_ABI_VERSION:   abs

.ifndef LIB_NO_BARE_EXPORTS
    ; Deprecated bare forms — removed at contract v1.0.
    LIB_VERSION_MAJOR = LIB_POLYVAL_VERSION_MAJOR
    LIB_VERSION_MINOR = LIB_POLYVAL_VERSION_MINOR
    LIB_VERSION_PATCH = LIB_POLYVAL_VERSION_PATCH
    LIB_ABI_VERSION   = LIB_POLYVAL_ABI_VERSION

    .export LIB_VERSION_MAJOR: abs
    .export LIB_VERSION_MINOR: abs
    .export LIB_VERSION_PATCH: abs
    .export LIB_ABI_VERSION:   abs
.endif
