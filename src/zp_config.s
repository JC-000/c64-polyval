.setcpu "6502"

; =============================================================================
; zp_config.s - public zero-page slot inventory for c64-polyval.
;
; Per c64-lib-contract SPEC.md §2 (zero-page contract), every ZP slot the
; library claims is declared here as an `.ifndef`-guarded equate and is
; `.exportzp`-ed so consumer modules can `.importzp` it instead of
; `.include`-ing constants_lib.inc (which would also pull in profile
; selectors, AES sizes, and other library-internal equates the consumer
; doesn't need).
;
; ZP layout (45 bytes total claimed)
; ----------------------------------
;
;   Shared / pointer & temp slots (8 bytes):
;     polyval_zp_ptr2      $02 (2 bytes)   second pointer
;     polyval_aes_round    $04             AES round counter
;     polyval_aes_col      $05             AES column counter
;     polyval_aes_tmp1     $06             AES temp byte
;     polyval_aes_tmp2     $07             AES temp byte
;     polyval_aes_tmp3     $08             AES temp byte
;     polyval_aes_tmp4     $09             AES temp byte
;
;   POLYVAL multiply working slots (33 bytes):
;     polyval_acc          $10..$1F        16-byte accumulator
;     pv_mul_input         $20..$2F        16-byte multiply input scratch
;     pv_mul_nibble        $30             1-byte nibble param
;
;   Misc pointer / temp / counter (4 bytes):
;     polyval_zp_ptr       $fb (2 bytes)   primary pointer
;     polyval_zp_temp      $fd             temp storage
;     polyval_zp_count     $fe             loop counter
;
; Host overrides
; --------------
;
; A host program can override any slot's address by pre-defining the symbol
; before `.include`-ing zp_config.s. The recommended ways, best first:
;
;   1. At the make level (SPEC §6.2, the recommended mechanism):
;
;          make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'
;
;      The Makefile appends CONTRACT_ZP_DEFINES to every library
;      translation unit's ca65 invocation. In this library that IS the
;      SPEC's "ZP-defining TU(s)" scope: no library TU `.importzp`s its
;      own slots — each one defines the equates itself via
;      constants_lib.inc -> this file's .ifndef guards — so all-members
;      delivery is the conformant (and only correct) scoped delivery.
;      Values must be $-free (0x hex or decimal): make's $-expansion
;      mangles every $-hex escape ladder silently (SPEC §2, v0.8.6).
;
;   2. Pass `-D polyval_acc=0x40` (or `-D polyval_acc='$40'` — the $-hex
;      MUST be quoted or the shell eats it: unquoted $40 expands as
;      positional parameter $4 + literal "0" and the slot silently lands
;      at $00; in make recipes prefer the 0x form, which survives
;      make+shell unescaped — SPEC v0.8.6) on the ca65 command line.
;      The flag is `-D`: ca65 rejects `--asm-define` with "Unknown
;      option" — that spelling is cl65's (SPEC v0.7.1). The define is
;      global for the translation unit, and the .ifndef guard below
;      then skips the default. ALL library translation units must be
;      assembled with the same -D values, since each .o bakes in the
;      equate value at assemble time.
;
;   3. Inside a wrapper .s file:
;
;          polyval_acc = $40
;          .include "zp_config.s"
;
; The library's own standalone PRG (`make`) and library-only verification
; (`make lib`) assemble with the defaults. Consumer projects rebuild the
; library from source with -D to pin slots to their preferred layout.
;
; Suppressing the .exportzp block
; -------------------------------
;
; When zp_config.s is transitively `.include`'d via constants_lib.inc, the
; including translation unit must NOT re-emit the `.exportzp` directives
; (ld65 errors on the same symbol being exported from multiple .o files).
; constants_lib.inc sets `ZP_CONFIG_NO_EXPORTS = 1` before the include for
; this reason. zp_config.s itself, compiled as its own .o (the only place
; the exports actually need to land), does NOT set the flag and DOES emit
; them.
; =============================================================================

.ifndef ZP_CONFIG_S_INCLUDED
ZP_CONFIG_S_INCLUDED = 1

; --- Shared pointer / temp slots ($02, $04-$09) ---
.ifndef polyval_zp_ptr2
  polyval_zp_ptr2    = $02           ; 2-byte pointer
.endif
.ifndef polyval_aes_round
  polyval_aes_round  = $04           ; AES round counter
.endif
.ifndef polyval_aes_col
  polyval_aes_col    = $05           ; AES column counter
.endif
.ifndef polyval_aes_tmp1
  polyval_aes_tmp1   = $06           ; AES temp byte
.endif
.ifndef polyval_aes_tmp2
  polyval_aes_tmp2   = $07           ; AES temp byte
.endif
.ifndef polyval_aes_tmp3
  polyval_aes_tmp3   = $08           ; AES temp byte
.endif
.ifndef polyval_aes_tmp4
  polyval_aes_tmp4   = $09           ; AES temp byte
.endif

; --- POLYVAL multiply working slots ($10-$30) ---
.ifndef polyval_acc
  polyval_acc        = $10           ; 16-byte POLYVAL accumulator ($10-$1F)
.endif
.ifndef pv_mul_input
  pv_mul_input       = $20           ; 16-byte multiply input scratch ($20-$2F)
.endif
.ifndef pv_mul_nibble
  pv_mul_nibble      = $30           ; 1-byte nibble param for polyval_xor_table_entry
.endif

; --- Misc pointer / temp / counter ($fb-$fe) ---
.ifndef polyval_zp_ptr
  polyval_zp_ptr     = $fb           ; 2-byte primary pointer
.endif
.ifndef polyval_zp_temp
  polyval_zp_temp    = $fd           ; temp storage
.endif
.ifndef polyval_zp_count
  polyval_zp_count   = $fe           ; loop counter
.endif

; =============================================================================
; The slot table (issue #105)
; =============================================================================
;
; ONE list, three consumers: the range check, the pairwise-overlap check, and
; the `.exportzp` block. Driving the exports from the same list keeps the two
; from drifting apart the way two hand-maintained lists would.
;
; WHAT THIS DOES NOT GUARD -- read before adding a slot.
;
; Adding a ZP slot is a MANUAL edit: you add an `.ifndef` equate above AND a
; row here, and nothing in this file detects the second half being forgotten.
; An earlier revision of this comment claimed such a slot would at least be
; caught downstream "at a link that references it". That is FALSE for the
; likelier case and was measured false: a new slot used only by library code
; is baked into every TU via constants_lib.inc's include of this file, so no
; TU ever needs the `.exportzp`, and `make lib-verify` links and exits 0 with
; the new slot aliased on top of an existing one. Only an EXTERNAL consumer's
; `.importzp` of the missing name fails, and a purely internal slot has no
; such consumer.
;
; A ca65 assertion cannot close this: the assembler offers no way to enumerate
; the symbols a file has defined, so "every `.ifndef` equate above has a row
; below" is not expressible here. So it is stated rather than guarded. The
; slot count is pinned in three places (see check 3) to make a half-finished
; edit noisy, but a slot added above with no row anywhere is UNGUARDED and
; will silently escape the distinctness checks.
;
; Each row is: index, symbol, byte-length, "symbol as a string".
;   - the index gives the pair loop a canonical order so each unordered pair is
;     tested once (78 pairs for 13 slots) and no slot is compared with itself;
;   - the byte-length is load-bearing: polyval_acc and pv_mul_input claim 16
;     bytes each and the two pointers claim 2, so an equality-only check would
;     pass `-D polyval_acc=0x28` while $28..$37 sits on top of pv_mul_input
;     ($20..$2F) and pv_mul_nibble ($30). Overlap, not equality;
;   - the string is only for the diagnostic, so it names both slots.
;
; Rows MUST stay in ascending default-address order for readability, but the
; checks do not depend on it — they cannot, since §6.2 lets a consumer move a
; slot anywhere (`-D polyval_acc=0x40` reorders the layout and must still
; pass). That is why this is a pairwise check and not a cheaper sorted-order
; one: there is no order to assert against once overrides are in play.

.macro PV_ZP_SLOT_LIST cb
  cb  0, polyval_zp_ptr2,   2, "polyval_zp_ptr2"
  cb  1, polyval_aes_round, 1, "polyval_aes_round"
  cb  2, polyval_aes_col,   1, "polyval_aes_col"
  cb  3, polyval_aes_tmp1,  1, "polyval_aes_tmp1"
  cb  4, polyval_aes_tmp2,  1, "polyval_aes_tmp2"
  cb  5, polyval_aes_tmp3,  1, "polyval_aes_tmp3"
  cb  6, polyval_aes_tmp4,  1, "polyval_aes_tmp4"
  cb  7, polyval_acc,      16, "polyval_acc"
  cb  8, pv_mul_input,     16, "pv_mul_input"
  cb  9, pv_mul_nibble,     1, "pv_mul_nibble"
  cb 10, polyval_zp_ptr,    2, "polyval_zp_ptr"
  cb 11, polyval_zp_temp,   1, "polyval_zp_temp"
  cb 12, polyval_zp_count,  1, "polyval_zp_count"
.endmacro

; --- Check 1: every slot lies wholly inside $02-$FF -------------------------
;
; A slot pushed off the end of the zero page is a different silent corruption:
; ca65 emits only "Symbol 'x' is absolute but exported zeropage" (a WARNING,
; exit 0), and every `lda slot,x` in the library then addresses the wrong
; page. The last byte, not the first, has to fit: polyval_acc at $f8 puts
; bytes 8..15 outside the page.
;
; The FLOOR is $02, not $00. $00 and $01 are the 6510's data-direction
; register and processor port -- the bytes that bank BASIC, KERNAL, CHAREN and
; I/O in and out. A consumer fitting the library into their memory map with
; `-D polyval_zp_temp=0x00` looks exactly as legal as the documented
; `-D polyval_acc=0x40`, and before this floor it assembled, archived and
; linked; every `sta polyval_zp_temp` in the library would then re-bank the
; machine mid-multiply. That is the same silent-corruption class as the
; aliasing this file exists to reject, so it is rejected the same way rather
; than documented as a caveat. $02 is also the floor API.md section 9.2
; already publishes: the claimed layout's lowest region is `$02-$09`.
;
; `error`, not `lderror`, throughout. `lderror` is deferred to ld65, and the
; §6.2 delivery this defends -- `make lib CONTRACT_ZP_DEFINES=...` -- runs
; ca65 and ar65 only, never ld65. A deferred assertion would not fire on the
; build that produces the wrong archive; it would fire later, in the
; consumer's link, or never if they archive and stop. `error` fires while
; zp_config.s is being assembled, in the build that supplied the -D.

.macro PV_ZP_CHECK_RANGE idx, addr, size, name
  .assert (addr >= $02) && (addr + size <= $100), error, .sprintf("zp_config: slot %s is outside $02-$ff (base $%04x, %d bytes) -- $00/$01 are the 6510 DDR and processor port and are never available; see CONTRACT_ZP_DEFINES in this file's header", name, addr, size)
.endmacro

PV_ZP_SLOT_LIST PV_ZP_CHECK_RANGE

; --- Check 2: no two slots overlap ------------------------------------------
;
; Nested expansion of the one list. The outer pass parks its row in three
; `.set` symbols plus a `.define`d name, then re-expands the list with the
; inner comparator; the `idx > outer` guard makes it the 78 unordered pairs.
; Disjointness of [a, a+sa) and [b, b+sb) is `a >= b+sb || b >= a+sa`.

.macro PV_ZP_CHECK_PAIR idx, addr, size, name
  .if idx > PV_ZP_OUTER_IDX
    PV_ZP_PAIR_COUNT .set PV_ZP_PAIR_COUNT + 1
    .assert (addr >= PV_ZP_OUTER_ADDR + PV_ZP_OUTER_SIZE) || (PV_ZP_OUTER_ADDR >= addr + size), error, .sprintf("zp_config: ZP slots %s ($%02x, %d bytes) and %s ($%02x, %d bytes) OVERLAP -- CONTRACT_ZP_DEFINES must place every slot at a distinct, non-overlapping address", PV_ZP_OUTER_NAME, PV_ZP_OUTER_ADDR, PV_ZP_OUTER_SIZE, name, addr, size)
  .endif
.endmacro

.macro PV_ZP_CHECK_AGAINST_REST idx, addr, size, name
  PV_ZP_OUTER_IDX  .set idx
  PV_ZP_OUTER_ADDR .set addr
  PV_ZP_OUTER_SIZE .set size
  .define PV_ZP_OUTER_NAME name
  PV_ZP_SLOT_LIST PV_ZP_CHECK_PAIR
  .undefine PV_ZP_OUTER_NAME
.endmacro

PV_ZP_OUTER_IDX  .set 0
PV_ZP_OUTER_ADDR .set 0
PV_ZP_OUTER_SIZE .set 0
PV_ZP_PAIR_COUNT .set 0
PV_ZP_SLOT_COUNT .set 0

.macro PV_ZP_COUNT_SLOT idx, addr, size, name
  PV_ZP_SLOT_COUNT .set PV_ZP_SLOT_COUNT + 1
.endmacro

PV_ZP_SLOT_LIST PV_ZP_COUNT_SLOT
PV_ZP_SLOT_LIST PV_ZP_CHECK_AGAINST_REST

; --- Check 3: the pair loop is not degenerate -------------------------------
;
; Cheap in-build proof that check 2 above did work rather than expanding to
; nothing. A `.assert` that is never reached is this repo's recurring defect
; (#86, #91, #95), and a nested macro expansion is exactly the shape that can
; quietly collapse: if the inner re-expansion of the list ever stopped
; happening, every pairwise assertion would vanish, the default build would
; still be green, and #105 would be back with no diagnostic anywhere.
;
; n slots is n*(n-1)/2 unordered pairs; for the 13 rows above that is 78. The
; identity form needs no edit when a row is added -- only the slot count on
; the second line does, and that is deliberate: it is the speed bump that
; makes adding a slot notice this block exists. 13 is also the export count
; `od65 --dump-exports build/zp_config.o | grep -c Name:` reports, and
; tools/check_zp_slot_aliasing.sh pins that count too -- so adding a slot
; means editing three places (a row above, the 13 below, that script) and
; failing loudly at each until all three agree. That is the intended cost.

.assert PV_ZP_PAIR_COUNT = PV_ZP_SLOT_COUNT * (PV_ZP_SLOT_COUNT - 1) / 2, error, .sprintf("zp_config: pairwise slot check is degenerate -- %d slots should give %d pairs, %d were evaluated", PV_ZP_SLOT_COUNT, PV_ZP_SLOT_COUNT * (PV_ZP_SLOT_COUNT - 1) / 2, PV_ZP_PAIR_COUNT)
.assert PV_ZP_SLOT_COUNT = 13, error, .sprintf("zp_config: PV_ZP_SLOT_LIST has %d rows, expected 13 -- if you added or removed a ZP slot, update this count, the ZP layout table in API.md section 4, and the export-count pin in tools/check_zp_slot_aliasing.sh", PV_ZP_SLOT_COUNT)

; --- Positive control -------------------------------------------------------
;
; Assemble with `-D PV_ZP_SELFTEST=1` to prove the two checks above are really
; evaluated rather than passing vacuously (issues #86, #91, #95: this repo's
; recurring defect is a check that cannot go red). It feeds ONE synthetic slot
; through the SAME two comparator macros the real checks use -- not copies of
; them -- and that slot is broken in both ways at once, so the assembly must
; FAIL with both diagnostics. If `ca65 -D PV_ZP_SELFTEST=1` ever exits 0, the
; machinery above is dead and the green default build means nothing.
; `tools/check_zp_slot_aliasing.sh` drives this and is wired into `make
; verify`. Nothing in this block affects a build that does not define the
; symbol.
;
; PV_ZP_SELFTEST_SLOT is $f8..$107: it runs off the end of the zero page (the
; range check) AND sits on top of polyval_zp_ptr / _temp / _count (the pair
; check). Its index is -1 so the `idx > PV_ZP_OUTER_IDX` guard compares it
; against every one of the 13 real rows, not a subset.

.ifdef PV_ZP_SELFTEST
  PV_ZP_CHECK_RANGE        -1, $f8, 16, "PV_ZP_SELFTEST_SLOT"
  PV_ZP_CHECK_AGAINST_REST -1, $f8, 16, "PV_ZP_SELFTEST_SLOT"
.endif

; --- Exports (suppressed when transitively .include'd via constants_lib.inc) ---
.if !.defined(ZP_CONFIG_NO_EXPORTS)

.macro PV_ZP_EXPORT idx, addr, size, name
  .exportzp addr
.endmacro

PV_ZP_SLOT_LIST PV_ZP_EXPORT

.endif ; !ZP_CONFIG_NO_EXPORTS

.endif ; ZP_CONFIG_S_INCLUDED
