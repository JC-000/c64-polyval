# ---------------------------------------------------------------------------
# Makefile - top-level ca65 build for c64-polyval
#
# Targets:
#   all                  (default) build $(BUILD_DIR)/polyval.prg + labels.txt
#                        (full app + library at $0801).
#   lib                  build $(BUILD_DIR)/lib/polyval.a, the full-library
#                        ar65 archive (c64-lib-contract SPEC §6 minimal-
#                        archive target). LONG profile by default. Consumers
#                        fetch this and link directly.
#   lib-polyval-long     build $(BUILD_DIR)/lib/polyval-long.a — POLYVAL
#                        LONG primitive only, no AES, no GCM-SIV.
#   lib-polyval-short    build $(BUILD_DIR)/lib/polyval-short.a — POLYVAL
#                        SHORT primitive only, no AES, no GCM-SIV.
#   lib-polyval-gcmsiv   build $(BUILD_DIR)/lib/polyval-gcmsiv.a — full
#                        AEAD bundle (POLYVAL LONG + AES + GCM-SIV).
#                        Currently identical to `make lib`; the named
#                        variant exists so consumers can pin to "the
#                        GCM-SIV bundle" semantically.
#   lib-polyval-gcmsiv-short
#                        build $(BUILD_DIR)/lib/polyval-gcmsiv-short.a —
#                        full AEAD bundle on the SHORT profile (POLYVAL
#                        SHORT + AES + GCM-SIV). The RFC 8452 per-message-H
#                        configuration; see "Profile choice" in CLAUDE.md.
#   lib-polyval-compact  build $(BUILD_DIR)/lib/polyval-compact.a — POLYVAL
#                        COMPACT primitive only, no AES, no GCM-SIV. The
#                        memory-bound configuration (issue #51).
#   lib-polyval-gcmsiv-compact
#                        build $(BUILD_DIR)/lib/polyval-gcmsiv-compact.a —
#                        full AEAD bundle on the COMPACT profile.
#   lib-verify           build $(BUILD_DIR)/lib_main.prg using lib_only.cfg
#                        — library-only verification link at $4000. Fails
#                        if any lib .o references an app-layer symbol. Not
#                        runnable. (Renamed from pre-SPEC-§6 `make lib`.)
#   consumer-check       assemble + link test/consumer_stub.s against the
#                        library to prove the public ABI is callable from a
#                        clean consumer. Output build/consumer_stub.prg.
#   consumer-check-shipped
#                        shipped-surface guard (issue #79): copy
#                        ONLY build/lib/{polyval.a,polyval.inc,
#                        polyval-example.cfg} + test/consumer_stub_shipped.s
#                        into an empty scratch dir and assemble there with
#                        no -I src, proving the shipped set is a sufficient
#                        consumer surface. The only check that can see an
#                        incomplete one.
#   consumer-check-noaes link test/consumer_stub_noaes.s -- a consumer that
#                        owns its own AES/GCM-SIV -- against polyval-long.a,
#                        polyval-short.a and polyval-compact.a. Guards issue
#                        #47: the POLYVAL-only archives must not export the
#                        AES / GCM-SIV BSS block out of the shared data.o.
#   run                  `make all` then launch VICE x64sc with -moncommands.
#   clean                rm -rf build/.
#   dist                 reproducible release tarball.
#
# Variables:
#   POLYVAL_PROFILE=long|short|compact
#                                maps to -D POLYVAL_PROFILE=2|1|3 for ca65.
#                                Default: long. Selects polyval_long.s vs
#                                polyval_short.s vs polyval_compact.s at
#                                link time (ca65 has no ACME-style !source
#                                dispatcher).
#
#                                lib-polyval-{long,short,compact} re-invoke
#                                `make` recursively with the right
#                                POLYVAL_PROFILE so the per-profile archives
#                                are always assembled against the matching
#                                equate.
#
#   CONTRACT_DEFINES=...         consumer-supplied global ca65 -D flags
#   CONTRACT_ZP_DEFINES=...      consumer-supplied §2 ZP slot overrides
#                                (c64-lib-contract SPEC §6.2 — see the
#                                block below CA65FLAGS; values must be
#                                $-free: 0x hex or decimal).
# ---------------------------------------------------------------------------

CA65   = ca65
LD65   = ld65
AR65   = ar65
PYTHON = python3

SRC_DIR   = src
BUILD_DIR = build
LIB_DIR   = $(BUILD_DIR)/lib
TEST_DIR  = test
TOOLS_DIR = tools

CFG     = $(SRC_DIR)/c64.cfg
LIB_CFG = $(SRC_DIR)/lib_only.cfg

PRG            = $(BUILD_DIR)/polyval.prg
LBL_RAW        = $(BUILD_DIR)/polyval.lbl
LABELS         = $(BUILD_DIR)/labels.txt
LIB_PRG        = $(BUILD_DIR)/lib_main.prg
LIB_LBL_RAW    = $(BUILD_DIR)/lib_main.lbl
LIB_LABELS     = $(BUILD_DIR)/lib_labels.txt
CONSUMER_PRG   = $(BUILD_DIR)/consumer_stub.prg
CONSUMER_LBL   = $(BUILD_DIR)/consumer_stub.lbl

# --- POLYVAL profile ------------------------------------------------------
# `long`    -> -D POLYVAL_PROFILE=2, links polyval_long.o    (8-bit Shoup, fast)
# `short`   -> -D POLYVAL_PROFILE=1, links polyval_short.o   (4-bit Shoup, unrolled)
# `compact` -> -D POLYVAL_PROFILE=3, links polyval_compact.o (4-bit Shoup, rolled)
POLYVAL_PROFILE ?= long
ifeq ($(POLYVAL_PROFILE),long)
  PROFILE_VAL        = 2
  POLYVAL_PROFILE_OBJ = polyval_long
else ifeq ($(POLYVAL_PROFILE),short)
  PROFILE_VAL        = 1
  POLYVAL_PROFILE_OBJ = polyval_short
else ifeq ($(POLYVAL_PROFILE),compact)
  PROFILE_VAL        = 3
  POLYVAL_PROFILE_OBJ = polyval_compact
else
  $(error POLYVAL_PROFILE must be 'long', 'short' or 'compact', got '$(POLYVAL_PROFILE)')
endif

# `-I src` resolves `.include "constants_lib.inc"`, `.include "polyval_api.inc"`,
# and `.include "include/zp.inc"` against the flat src/ layout.
CA65FLAGS = -I $(SRC_DIR) -D POLYVAL_PROFILE=$(PROFILE_VAL) -g

# --- Archive-membership gating (issue #23) --------------------------------
# The POLYVAL-only archives ship no tables.o, so their lib_manifest.o must
# not enumerate the AES S-box tables (§8.0 catch-loop accuracy). This is a
# different axis from POLYVAL_PROFILE — polyval-long.a and polyval-gcmsiv.a
# are both PROFILE=long; only archive membership differs — so it gets its
# own define. Set by the lib-polyval-{long,short,compact} recursive
# invocations.
# Like the profile define, lib_manifest.o content depends on it without a
# tracked dependency: `make clean` between differently-gated targets (the
# recursive targets already do).
POLYVAL_NO_AES ?=
ifneq ($(POLYVAL_NO_AES),)
  CA65FLAGS += -D LIB_POLYVAL_NO_AES=1
endif

# --- Consumer defines (c64-lib-contract SPEC §6.2) ------------------------
# Two contract-normative variables, both defaulting empty, so a consumer
# can inject ca65 -D flags without editing this Makefile or clobbering
# CA65FLAGS wholesale (which would silently drop -I src and the profile
# define):
#
#   CONTRACT_DEFINES     global defines — LIB_NO_BARE_EXPORTS, variant/
#                        profile selectors, future deferral switches.
#   CONTRACT_ZP_DEFINES  §2 ZP slot overrides, e.g.
#                        make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40'
#
# Values MUST be $-free (0x hex or decimal): make's own $-expansion mangles
# every $-hex escape ladder with no diagnostic (SPEC §2, v0.8.6).
#
# Scoped delivery, polyval-specific reading: the SPEC scopes
# CONTRACT_ZP_DEFINES to "only the ZP-defining TU(s)" because a
# globally-delivered slot override collides with `.importzp` sites in other
# TUs. This library has ZERO `.importzp` sites for its own slots — every
# library TU defines the ZP equates itself via constants_lib.inc ->
# zp_config.s `.ifndef` guards, baking the address into each .o at assemble
# time. So here EVERY member TU is a ZP-defining TU: appending
# CONTRACT_ZP_DEFINES to CA65FLAGS (all recipes) IS the conformant scoped
# delivery, and the only correct one — a zp_config.o-only delivery would
# export the overridden address while every other member had baked the
# default, a silent mismatch. The nist#104 explicit-pattern-rule caveat
# (ZP TU built by a generic pattern rule missing the scoped variable) is
# therefore inapplicable: the pattern rule delivering to everything is the
# point. The lib-polyval-{long,short} recursive $(MAKE) invocations inherit
# both variables automatically (command-line-origin variables propagate to
# sub-makes; measured — see API.md §9.5).
CONTRACT_DEFINES    ?=
CONTRACT_ZP_DEFINES ?=
CA65FLAGS += $(CONTRACT_DEFINES) $(CONTRACT_ZP_DEFINES)

# --- Module ordering ------------------------------------------------------
# Order matters for ld65 segment layout. Recovered from the old
# ca65/Makefile: APP_MODULES come first, then library modules, then the
# profile-selected polyval implementation last.
APP_MODULES = main zp boot main_loop disk_io display gcm_siv_ui strings data_app

LIB_MODULES = lib_version zp_config lib_manifest precalc_manifest tables data aes_encrypt aes_decrypt gcm_siv $(POLYVAL_PROFILE_OBJ)

MODULES = $(APP_MODULES) $(LIB_MODULES)

OBJECTS     = $(addprefix $(BUILD_DIR)/,$(addsuffix .o,$(MODULES)))
LIB_OBJECTS = $(addprefix $(BUILD_DIR)/,$(addsuffix .o,$(LIB_MODULES)))

# --- Library archive object sets (SPEC §6) --------------------------------
# Each `make lib(-variant)` target builds a single ar65 archive under
# $(LIB_DIR)/. Object-set composition is captured in named variables so the
# inventory is self-describing.
#
# LIB_CORE_OBJS is the shared baseline: every archive carries the SPEC §1
# version equates, the SPEC §2 ZP inventory, the SPEC §5 aggregate
# manifest equates, and the SPEC §8.0 precalc-table enumeration. None of
# these emit segment data, so adding them to any archive does not grow
# consumer-side link size — they only contribute import-time equates.
#
# precalc_manifest.o is a separate member from lib_manifest.o on purpose
# (SPEC v1.2.0 §6.1 member isolation): the §8.0 macro emits the bare,
# unprefixed LIB_PRECALC_<name>_* triple that a composing consumer
# suppresses with LIB_NO_BARE_EXPORTS, and ld65 links whole members, so
# those names must not ride along with the §5 equates a consumer imports
# for its footprint asserts. Both members go into every archive — the
# split changes which member a name lives in, never which archive.
LIB_CORE_OBJS = $(BUILD_DIR)/lib_version.o \
                $(BUILD_DIR)/zp_config.o \
                $(BUILD_DIR)/lib_manifest.o \
                $(BUILD_DIR)/precalc_manifest.o

# POLYVAL-only variants: just the chosen polyval primitive plus data.o
# (which provides polyval_h / polyval_temp / polyval_htable[8] / polyval_
# reduce8 buffer reservations). No AES, no GCM-SIV.
LIB_POLYVAL_LONG_OBJS  = $(LIB_CORE_OBJS) $(BUILD_DIR)/data.o \
                         $(BUILD_DIR)/polyval_long.o
LIB_POLYVAL_SHORT_OBJS = $(LIB_CORE_OBJS) $(BUILD_DIR)/data.o \
                         $(BUILD_DIR)/polyval_short.o
LIB_POLYVAL_COMPACT_OBJS = $(LIB_CORE_OBJS) $(BUILD_DIR)/data.o \
                         $(BUILD_DIR)/polyval_compact.o

# Full AEAD bundle: the profile-selected POLYVAL primitive + AES
# (encrypt/decrypt + sbox tables) + GCM-SIV glue. This is what `make lib`
# and `lib-polyval-gcmsiv` ship (LONG), and what `lib-polyval-gcmsiv-short`
# ships (SHORT).
#
# $(POLYVAL_PROFILE_OBJ) rather than a pinned polyval_long.o (issue #40):
# hardcoding the LONG object while POLYVAL_PROFILE still reached CA65FLAGS
# made SHORT+AEAD unbuildable-but-silent — see the guard below.
LIB_AEAD_OBJS = $(LIB_CORE_OBJS) $(BUILD_DIR)/data.o \
                $(BUILD_DIR)/tables.o \
                $(BUILD_DIR)/aes_encrypt.o $(BUILD_DIR)/aes_decrypt.o \
                $(BUILD_DIR)/gcm_siv.o \
                $(BUILD_DIR)/$(POLYVAL_PROFILE_OBJ).o

# --- Archive goal configuration guard (issue #40) -------------------------
# Every archive is defined by a (POLYVAL_PROFILE x LIB_POLYVAL_NO_AES) pair.
# The lib-polyval-* phony targets set both behind a `make clean`, but make
# cannot infer the pair from a goal, so any invocation that names an archive
# without the matching pair silently produces a wrong artifact — exit 0, no
# diagnostic, and ar65 cannot notice. All three shapes are measured:
#
#   make lib POLYVAL_PROFILE=short
#     `lib` does not clean, so the pattern rules reuse the stale LONG data.o
#     and lib_manifest.o (POLYVAL_PROFILE is not a prerequisite — the
#     profile-switch gotcha in CLAUDE.md) -> manifest describes the wrong
#     profile.
#   make build/lib/polyval-gcmsiv-short.a          (default profile)
#     -> the LONG multiply archived under the -short name: coherent,
#        correctly manifested, and not the artifact requested.
#   make build/lib/polyval-short.a                 (default profile)
#     -> polyval_short.o with a manifest exporting the LONG AEAD footprint
#        (RESIDENT 6656 rather than 13824): incoherent, SPEC §6.4-violating,
#        wrong on both axes at once.
#
# So each archive goal declares its required pair and asserts it. Guarding
# at parse time rather than in a recipe means nothing is built before the
# rejection — a half-built tree is itself the input to the staleness shape.
#
# The lib-polyval-{long,short,gcmsiv-short} wrappers are deliberately absent
# from the table: they establish the pin themselves via a recursive $(MAKE),
# and their inner invocation names the archive path, which is what gets
# checked here.
POLYVAL_PIN = $(POLYVAL_PROFILE)$(if $(POLYVAL_NO_AES),-noaes)

PIN_lib                               = long
PIN_lib-polyval-gcmsiv                = long
# consumer-check-shipped is the THIRD phony that reaches
# $(LIB_DIR)/polyval.a, and it needs a row for the same reason the two
# above do: the guard inspects the named GOAL, not the files a goal
# eventually builds. Without it, `make consumer-check-shipped
# POLYVAL_PROFILE=short` exited 0 having put polyval_short.o and a SHORT
# manifest (RESIDENT 16128) into polyval.a -- the canonical LONG name --
# and the shipped-surface check then certified that mis-pinned archive as
# sound and left it in build/lib/ for whatever ran next. Measured, and
# verbatim the failure the §6.3 block below documents.
PIN_consumer-check-shipped            = long
PIN_$(LIB_DIR)/polyval.a              = long
PIN_$(LIB_DIR)/polyval-gcmsiv.a       = long
PIN_$(LIB_DIR)/polyval-gcmsiv-short.a = short
PIN_$(LIB_DIR)/polyval-gcmsiv-compact.a = compact
PIN_$(LIB_DIR)/polyval-long.a         = long-noaes
PIN_$(LIB_DIR)/polyval-short.a        = short-noaes
PIN_$(LIB_DIR)/polyval-compact.a      = compact-noaes

$(foreach g,$(MAKECMDGOALS),$(if $(PIN_$(g)),$(if $(filter $(PIN_$(g)),$(POLYVAL_PIN)),,\
  $(error goal `$(g)` builds the '$(PIN_$(g))' configuration, but this invocation \
    is '$(POLYVAL_PIN)' (POLYVAL_PROFILE=$(POLYVAL_PROFILE)$(if $(POLYVAL_NO_AES), \
    POLYVAL_NO_AES=$(POLYVAL_NO_AES))). Use the phony target, which cleans and pins \
    for you: `make lib` / `lib-polyval-gcmsiv` (LONG AEAD), \
    `lib-polyval-gcmsiv-short` (SHORT AEAD), \
    `lib-polyval-gcmsiv-compact` (COMPACT AEAD), `lib-polyval-long` / \
    `lib-polyval-short` / `lib-polyval-compact` (POLYVAL-only). For a \
    SHORT or COMPACT full-AEAD *PRG*, `make POLYVAL_PROFILE=short` / \
    `make POLYVAL_PROFILE=compact`))))

# --- §6.2 defines-route guard for the member-set axes (issue #55) ---------
# The PIN table above guards the *make variable* route. SPEC §6.2's consumer
# mechanism is CONTRACT_DEFINES, which this Makefile appends to CA65FLAGS --
# and a member-set axis routed that way cannot work, because no ca65 -D can
# reach member selection. Both axes were measured walking past the PIN guard:
#
#   make lib CONTRACT_DEFINES="-D POLYVAL_PROFILE=1"
#     clean tree -> ca65: 'POLYVAL_PROFILE' is already defined      (exit 2)
#     warm tree  -> "Nothing to be done for `lib'"                  (exit 0)
#                   ...and polyval.a still holds polyval_long.o. The consumer
#                   asked for SHORT, got LONG, got exit 0. Five TUs branch on
#                   POLYVAL_PROFILE; the stale lib_manifest.o reports the
#                   other profile's §5 footprint and §8.0 rows, which no
#                   downstream assert catches.
#
#   make lib CONTRACT_DEFINES="-D LIB_POLYVAL_NO_AES=1"
#     clean tree -> exit 0, no diagnostic at all. Worse than the above: every
#                   TU assembles NO_AES while `lib` archives the full AEAD
#                   member list, so data.o drops the AES/GCM-SIV BSS that the
#                   archived aes_encrypt.o still references. Measured: the
#                   archive is unlinkable ("Unresolved external
#                   'aes_expanded_key'") AND its manifest exports the NO_AES
#                   RESIDENT (4352) for an AEAD member set -- §6.4-incoherent
#                   and wrong on both axes at once.
#
# The state-dependence is the sharpest edge: a diagnostic that fires from
# clean and stays silent from a warm tree is worse than one that never fires,
# because a consumer probing interactively concludes the define was accepted.
#
# SPEC §6.3's looks-reachable rule -- RETIRED at contract v1.0.0; kept here
# as local engineering, not conformance. It said a knob naming an axis MUST
# select it or
# reject loudly. These cannot select it, so they reject. Parse time, before
# anything is built: a half-built tree is itself the input to the stale shape.
#
# Two probe strings cover every spelling: LIB_POLYVAL_NO_AES contains
# POLYVAL_NO_AES, and POLYVAL_PROFILE_{SHORT,LONG} contain POLYVAL_PROFILE.
MEMBER_SET_AXES = POLYVAL_PROFILE POLYVAL_NO_AES
CONTRACT_AXIS_HITS = $(strip $(foreach a,$(MEMBER_SET_AXES),\
  $(if $(findstring $(a),$(CONTRACT_DEFINES) $(CONTRACT_ZP_DEFINES)),$(a))))

ifneq ($(CONTRACT_AXIS_HITS),)
  $(error member-set axis [$(CONTRACT_AXIS_HITS)] cannot be set through \
    CONTRACT_DEFINES / CONTRACT_ZP_DEFINES. POLYVAL_PROFILE and \
    LIB_POLYVAL_NO_AES select which objects are *archived* (SPEC §6.3 \
    member-set axis), and no ca65 -D reaches member selection -- routing \
    them through the defines forwarding yields a wrong artifact, silently \
    on a warm tree. Use the make variable and the phony target that pins \
    it: `make lib` / `lib-polyval-gcmsiv` (LONG AEAD), \
    `lib-polyval-gcmsiv-short` (SHORT AEAD), \
    `lib-polyval-gcmsiv-compact` (COMPACT AEAD), `lib-polyval-long` / \
    `lib-polyval-short` / `lib-polyval-compact` (POLYVAL-only), or \
    `make POLYVAL_PROFILE=short` for a SHORT full-AEAD PRG. \
    CONTRACT_DEFINES remains correct for \
    non-member-set defines such as LIB_NO_BARE_EXPORTS and \
    ZP_CONFIG_NO_EXPORTS)
endif

.PHONY: all lib lib-verify lib-polyval-long lib-polyval-short \
        lib-polyval-compact lib-polyval-gcmsiv lib-polyval-gcmsiv-short \
        lib-polyval-gcmsiv-compact consumer-check \
        consumer-check-noaes consumer-check-shipped run clean dist verify \
        check-no-tracked-artifacts check-footprints check-scratch-prefix
.DEFAULT_GOAL := all

all: $(PRG) $(LABELS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(LIB_DIR): | $(BUILD_DIR)
	mkdir -p $(LIB_DIR)

# --- Define-set stamp (issue #57) -----------------------------------------
# CA65FLAGS is not a prerequisite of anything, so make cannot see that a
# consumer changed it. The *configuration* axes -- the ones #56 correctly
# still accepts, because unlike the member-set axes they genuinely work --
# were therefore honoured from a clean tree and silently dropped from a warm
# one:
#
#   $ make clean && make lib                                  # warm the tree
#   $ make lib CONTRACT_DEFINES="-D ZP_CONFIG_NO_EXPORTS=1"
#   make: Nothing to be done for `lib'.                       # exit 0
#   $ od65 --dump-exports build/zp_config.o | grep -c Name:
#   13                                                        # asked for 0
#
# Rejecting would be wrong here (these knobs are honorable), so the fix is to
# invalidate: stamp the effective flag set and make every object depend on
# the stamp. The stamp is rewritten only when the flags actually change, so
# an unchanged invocation still short-circuits -- both properties matter, and
# a fix that rebuilt unconditionally would trade this bug for a worse one.
#
# Stamping all of CA65FLAGS rather than just the two contract variables is
# deliberate: it covers every -D this Makefile honours, including ones no one
# has audited yet, and it also retires the profile-switch gotcha -- data.o and
# lib_manifest.o content depends on POLYVAL_PROFILE / LIB_POLYVAL_NO_AES, and
# those now invalidate too instead of requiring a manual `make clean`.
#
# Invalidation happens at PARSE TIME, by deletion. Both halves are
# load-bearing, and the two obvious alternatives were measured failing.
#
# *Not* by timestamp: macOS ships **GNU Make 3.81**, which compares mtimes at
# 1-second granularity. A stamp that merely rewrites itself is newer only in
# the sub-second digits -- measured on the very sequence this bug is about:
#
#   1787503455.095994194  build/.ca65flags     (rewritten)
#   1787503455.036999740  build/zp_config.o    (stale)
#
# 3.81 truncates both to 1787503455, calls the object up to date, and skips
# the rebuild. So a stamp-as-prerequisite silently does nothing whenever two
# builds land in the same second -- i.e. exactly when a consumer is iterating
# interactively, which is the case this is reported from.
#
# *Not* as a rule prerequisite either, even deleting: make 3.81 stats a
# target before running its prerequisites' recipes and caches the result, so
# a delete performed from the stamp rule is invisible for whichever object
# make happened to consider first. Measured: build/lib_version.o was deleted
# and then NOT rebuilt -- make still believed the pre-deletion stat -- while
# every later object rebuilt correctly. That silently drops a member from the
# archive, which is a worse failure than the staleness being fixed.
#
# Doing it at parse time sidesteps both: the stale artifacts are gone before
# make builds its dependency graph or stats anything, so no clock granularity
# and no stat cache is involved. Unchanged flags touch nothing, which
# preserves incremental builds.
#
# `$(strip)` normalises whitespace so a differently-spaced but equivalent
# invocation does not force a rebuild. The `clean` goal is excluded so a
# `make clean` does not recreate build/ just to drop a stamp in it -- which
# also covers the recursive `$(MAKE) clean` in the lib-polyval-* targets.
#
# Limitation: the stamp round-trips through the shell, so a define containing
# a single quote would not compare correctly. ca65 -D values are symbols and
# integers, so this does not arise in practice.
CONTRACT_STAMP = $(BUILD_DIR)/.ca65flags

ifeq ($(filter clean,$(MAKECMDGOALS)),)
  CONTRACT_FLAGS_NOW := $(strip $(CA65FLAGS))
  CONTRACT_FLAGS_WAS := $(strip $(shell cat $(CONTRACT_STAMP) 2>/dev/null))
  ifneq ($(CONTRACT_FLAGS_NOW),$(CONTRACT_FLAGS_WAS))
    $(shell rm -f $(BUILD_DIR)/*.o $(BUILD_DIR)/*.prg $(BUILD_DIR)/*.lbl \
                  $(LIB_DIR)/*.a 2>/dev/null)
    $(shell mkdir -p $(BUILD_DIR) && \
            printf '%s\n' '$(CONTRACT_FLAGS_NOW)' > $(CONTRACT_STAMP))
  endif
endif

# --- Pattern rules --------------------------------------------------------
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.s | $(BUILD_DIR)
	$(CA65) $(CA65FLAGS) -o $@ $<

$(BUILD_DIR)/lib_main.o: $(SRC_DIR)/lib_main.s | $(BUILD_DIR)
	$(CA65) $(CA65FLAGS) -o $@ $<

$(BUILD_DIR)/consumer_stub.o: $(TEST_DIR)/consumer_stub.s | $(BUILD_DIR)
	$(CA65) $(CA65FLAGS) -o $@ $<

# --- Full app+lib link ----------------------------------------------------
$(PRG) $(LBL_RAW): $(OBJECTS) $(CFG) | $(BUILD_DIR)
	$(LD65) -C $(CFG) -Ln $(LBL_RAW) -o $(PRG) $(OBJECTS)

$(LABELS): $(LBL_RAW) $(TOOLS_DIR)/vice_label_shim.py
	$(PYTHON) $(TOOLS_DIR)/vice_label_shim.py $(LBL_RAW) $(LABELS)

# --- Library-only verification build --------------------------------------
# Links ONLY lib .o files + lib_main.o stub via lib_only.cfg ($4000). If a
# lib file references an app-layer symbol, ld65 errors out — that error IS
# the verification. The produced .prg is NOT runnable.
#
# Pre-SPEC-§6 this target was named `make lib`; that name now belongs to
# the archive output (build/lib/polyval.a) per SPEC §6.
# The knob-staleness leg pins SPEC §6.3's invalidate branch (issue #58): it
# asserts the ARTIFACT flips when a configuration knob changes on a warm tree,
# in both directions, and that an unchanged invocation still recompiles
# nothing. It runs in its own scratch BUILD_DIR, so it cannot disturb build/,
# and it runs after the PRG so a verification build is not held up by it.
# `tools/check_knob_staleness.sh --selftest` proves the pin can fail.
# A leg on this existing target rather than a new one: §6.5 makes make target
# names contract surface, and this needs none.
lib-verify: $(LIB_PRG) $(LIB_LABELS)
	@$(TOOLS_DIR)/check_knob_staleness.sh

$(LIB_PRG) $(LIB_LBL_RAW): $(LIB_OBJECTS) $(BUILD_DIR)/lib_main.o $(LIB_CFG) | $(BUILD_DIR)
	$(LD65) -C $(LIB_CFG) -Ln $(LIB_LBL_RAW) -o $(LIB_PRG) \
	    $(LIB_OBJECTS) $(BUILD_DIR)/lib_main.o

$(LIB_LABELS): $(LIB_LBL_RAW) $(TOOLS_DIR)/vice_label_shim.py
	$(PYTHON) $(TOOLS_DIR)/vice_label_shim.py $(LIB_LBL_RAW) $(LIB_LABELS)

# --- Consumer-facing shipped surface (a LOCAL choice, not a contract MUST) -
# HISTORY, because the justification changed under us and the artifacts did
# not. c64-polyval v0.10.0 added this staging to satisfy what SPEC v1.1.0
# §6.1 stated as a MUST: "producing build/lib/<shortname>.a plus the
# consumer-facing `.inc` header and an example `.cfg`". **Contract v1.1.1
# WITHDREW that requirement** (contract#178): it was an unannounced artifact
# of the 1.0.0 text cut, had never been proposed, named neither path, and
# failed the contract's own scope rule on both prongs. v1.2.0 §6.1 requires
# the archive and nothing else.
#
# We keep shipping both files anyway, deliberately. The reasoning that made
# it worth doing is unchanged and was never really about conformance: a
# consumer who fetches only the .a has no declaration of the public symbols
# and no statement of the load-bearing §4 segment attributes -- both of whose
# omissions are silent at link -- so their only recourse is to read our src/,
# which §6.1's surviving `ar65`-surgery/no-source-poking language exists to
# make unnecessary. `make consumer-check-shipped` proves the shipped set is
# sufficient.
#
# What is NOT true, and must not be written down again: that any contract
# clause requires this. It does not.
#
# Staged by copy rather than generated: both files are hand-maintained
# sources that a consumer copies into their own tree, and a generator would
# put a second, drifting description of the API between src/ and consumers.
#
# The header ships under the §6.1 canonical <shortname> basename rather than
# its src/ working name. The cfg is a PURPOSE-BUILT consumer template, not a
# copy of either config this repo builds itself with:
#
#   c64.cfg       full demo app at $0801 -- carries app-layer segments a
#                 consumer does not have.
#   lib_only.cfg  library-only verification link at $4000 -- carries a
#                 MANDATORY LOADADDR segment and LIB_POLYVAL_VERIFY_CODE,
#                 both scaffolding for `make lib-verify`'s stub.
#
# Shipping lib_only.cfg was tried and rejected: a consumer linking their own
# stub against polyval.a with it gets `ld65: Warning: Segment 'LOADADDR'
# does not exist`, because only our verify stub emits that segment. Handing
# a consumer a file whose own first line says it is for our internal
# verification build, and which warns on their very first link, is not a
# usable example cfg. src/polyval-example.cfg is maintained as
# the consumer-facing one; `make consumer-check-shipped` links against it so
# it cannot rot. These are §6.5 name surface from this release on.
#
# Kept flat in $(LIB_DIR) rather than a cfg/ subdirectory: a nested output
# directory needs its own order-only prerequisite, and naming only the
# parent is the c64-x25519 defect where `make lib` failed on a warm tree
# whose subdirectory had been cleaned away (their Makefile:242).
LIB_INC     = $(LIB_DIR)/polyval.inc
LIB_EXAMPLE_CFG = $(LIB_DIR)/polyval-example.cfg
LIB_SHIPPED = $(LIB_INC) $(LIB_EXAMPLE_CFG)

$(LIB_INC): $(SRC_DIR)/polyval_api.inc | $(LIB_DIR)
	cp $< $@

$(LIB_EXAMPLE_CFG): $(SRC_DIR)/polyval-example.cfg | $(LIB_DIR)
	cp $< $@

# --- Library archives (c64-lib-contract SPEC §6) --------------------------
# Each archive bundles one consumer use case as a single ar65 `.a` file
# under build/lib/. Consumers fetch one archive and link it directly; no
# source patching, no per-file ca65 chain on the consumer side.
#
# ar65 `a` appends (no replace-all flag), so each recipe `rm -f $@` before
# invoking ar65 to ensure a clean rebuild.
#
# The per-profile POLYVAL archives (lib-polyval-{long,short}) re-invoke
# `make` recursively with POLYVAL_PROFILE pinned. This matters because the
# polyval primitives and data.s use `.if POLYVAL_PROFILE = ...` blocks at
# assemble time, so each profile needs its own .o set. The recursive
# invocation cleans build/ first to avoid mixing .o files assembled under
# different POLYVAL_PROFILE values.
#
# `lib` and `lib-polyval-gcmsiv` produce byte-identical archives today --
# meaning identical CONTENT, one object set archived under two names, not a
# claim that either is byte-reproducible across builds; it is not, see the
# issue #97 block above VERIFY_TARGETS. The two DO compare equal to each
# other however far apart they are archived -- measured 9 s apart, still
# byte-identical, because they share one object set and ar65 adds no clock;
# what does not reproduce is a build that REASSEMBLES. The two names exist
# because consumers semantically want "the GCM-SIV bundle" rather than
# "everything we happen to ship". If a future variant
# ever ships more than the AEAD bundle in `lib`, this split lets us widen
# `lib` without surprising AEAD consumers.

lib:                $(LIB_DIR)/polyval.a
lib-polyval-gcmsiv: $(LIB_DIR)/polyval-gcmsiv.a

$(LIB_DIR)/polyval.a: $(LIB_AEAD_OBJS) | $(LIB_DIR) $(LIB_SHIPPED)
	rm -f $@
	$(AR65) a $@ $(LIB_AEAD_OBJS)
	$(TOOLS_DIR)/check_archive_members.sh $@ $^

$(LIB_DIR)/polyval-gcmsiv.a: $(LIB_AEAD_OBJS) | $(LIB_DIR) $(LIB_SHIPPED)
	rm -f $@
	$(AR65) a $@ $(LIB_AEAD_OBJS)
	$(TOOLS_DIR)/check_archive_members.sh $@ $^

# Per-profile POLYVAL-only archives. Recursive `make` invocations pin
# POLYVAL_PROFILE for the .o build so the resulting archive only contains
# the matching primitive. `make clean` happens first to avoid mixing .o
# files from a prior `make` (which may have been built under the other
# profile or against a stale POLYVAL_PROFILE_OBJ set).
lib-polyval-long:
	$(MAKE) clean
	$(MAKE) POLYVAL_PROFILE=long POLYVAL_NO_AES=1 $(LIB_DIR)/polyval-long.a

lib-polyval-short:
	$(MAKE) clean
	$(MAKE) POLYVAL_PROFILE=short POLYVAL_NO_AES=1 $(LIB_DIR)/polyval-short.a

# The memory-bound configuration (issue #51). Same clean-and-pin shape; the
# archive ships the rolled 4-bit Shoup multiply and the same 256-byte
# polyval_htable as SHORT.
lib-polyval-compact:
	$(MAKE) clean
	$(MAKE) POLYVAL_PROFILE=compact POLYVAL_NO_AES=1 $(LIB_DIR)/polyval-compact.a

# SHORT full-AEAD archive (SPEC §6.1 target for the SHORT+AEAD member-set
# axis — issue #40, contract v0.10.4 §6.3). Same recursive clean-and-pin
# shape as the POLYVAL-only variants above: POLYVAL_PROFILE selects
# polyval_short.o into LIB_AEAD_OBJS, and data.o / lib_manifest.o are
# assembled under the same pin, so the shipped §5 manifest describes this
# archive (SHORT AEAD: RESIDENT 16128 / COLD 3072) per §6.4.
#
# POLYVAL_NO_AES is deliberately NOT set here — this variant ships AES and
# the GCM-SIV glue, so the manifest must enumerate aes_sbox / aes_inv_sbox.
lib-polyval-gcmsiv-short:
	$(MAKE) clean
	$(MAKE) POLYVAL_PROFILE=short $(LIB_DIR)/polyval-gcmsiv-short.a

lib-polyval-gcmsiv-compact:
	$(MAKE) clean
	$(MAKE) POLYVAL_PROFILE=compact $(LIB_DIR)/polyval-gcmsiv-compact.a

$(LIB_DIR)/polyval-long.a: $(LIB_POLYVAL_LONG_OBJS) | $(LIB_DIR) $(LIB_SHIPPED)
	rm -f $@
	$(AR65) a $@ $(LIB_POLYVAL_LONG_OBJS)
	$(TOOLS_DIR)/check_archive_members.sh $@ $^

$(LIB_DIR)/polyval-short.a: $(LIB_POLYVAL_SHORT_OBJS) | $(LIB_DIR) $(LIB_SHIPPED)
	rm -f $@
	$(AR65) a $@ $(LIB_POLYVAL_SHORT_OBJS)
	$(TOOLS_DIR)/check_archive_members.sh $@ $^

$(LIB_DIR)/polyval-compact.a: $(LIB_POLYVAL_COMPACT_OBJS) | $(LIB_DIR) $(LIB_SHIPPED)
	rm -f $@
	$(AR65) a $@ $(LIB_POLYVAL_COMPACT_OBJS)
	$(TOOLS_DIR)/check_archive_members.sh $@ $^

$(LIB_DIR)/polyval-gcmsiv-short.a: $(LIB_AEAD_OBJS) | $(LIB_DIR) $(LIB_SHIPPED)
	rm -f $@
	$(AR65) a $@ $(LIB_AEAD_OBJS)
	$(TOOLS_DIR)/check_archive_members.sh $@ $^

$(LIB_DIR)/polyval-gcmsiv-compact.a: $(LIB_AEAD_OBJS) | $(LIB_DIR) $(LIB_SHIPPED)
	rm -f $@
	$(AR65) a $@ $(LIB_AEAD_OBJS)
	$(TOOLS_DIR)/check_archive_members.sh $@ $^

# --- Shipped-surface guard (issue #79) -------------------------------------
# Proves the three files `make lib` puts in build/lib/ are a COMPLETE and
# SUFFICIENT consumer surface, by assembling and linking a stub that has
# access to nothing else.
#
# The scratch directory is the mechanism, not decoration. Every other build
# in this repo runs with `-I src` on the ca65 command line, so a header that
# quietly depends on another src/ file assembles fine for us and fails only
# for a consumer who never received that file. This recipe copies exactly
# polyval.a + polyval.inc + polyval-example.cfg plus the stub into an empty
# directory and assembles there with NO -I at all: a reachback into src/ is
# then a hard "Cannot open include file" rather than an invisible pass.
#
# It depends on $(LIB_DIR)/polyval.a, so the shipped .inc and .cfg are staged
# by that rule's order-only prerequisites before this runs.
# Unique per invocation (issue #93): a fixed name plus the `rm -rf` at the top
# of the recipe meant two concurrent runs in one tree deleted each other's
# staging directory mid-link.
#
# `:=` and $(shell ...) are both load-bearing. Written as a recursive
# `= ...$$$$`, the PID is expanded ONCE PER RECIPE LINE -- and each line is
# its own shell -- so mkdir created one directory and the next cp targeted a
# different name: "cp: build/shipped-check.46834: Not a directory". Measured,
# not theorised.
CHECK_SHIPPED_DIR := $(BUILD_DIR)/shipped-check.$(shell echo $$$$)

consumer-check-shipped: $(LIB_DIR)/polyval.a
	rm -rf $(CHECK_SHIPPED_DIR)
	mkdir -p $(CHECK_SHIPPED_DIR)
	cp $(LIB_DIR)/polyval.a $(LIB_INC) $(LIB_EXAMPLE_CFG) $(CHECK_SHIPPED_DIR)/
	cp $(TEST_DIR)/consumer_stub_shipped.s $(CHECK_SHIPPED_DIR)/
	cd $(CHECK_SHIPPED_DIR) && \
	    $(CA65) -o consumer_stub_shipped.o consumer_stub_shipped.s && \
	    $(LD65) -C polyval-example.cfg -o consumer_stub_shipped.prg \
	        consumer_stub_shipped.o polyval.a
	@test -s $(CHECK_SHIPPED_DIR)/consumer_stub_shipped.prg
	@echo "consumer-check-shipped: polyval.a + polyval.inc + polyval-example.cfg" \
	      "are a sufficient consumer surface (no src/ on the include path)"
	@# Removed only on SUCCESS: a per-run name would otherwise accumulate under
	@# build/, and on failure the staging tree is exactly what you want to look
	@# at. `make clean` sweeps any left by a failed run.
	@rm -rf $(CHECK_SHIPPED_DIR)

# --- Consumer-stub smoke check --------------------------------------------
# Assembles test/consumer_stub.s against the public .inc surface only and
# links it with the library via lib_only.cfg. Succeeds iff the downstream
# import path is stable. Rehearsal for c64-wireguard / c64-https consumers.
consumer-check: $(CONSUMER_PRG)

$(CONSUMER_PRG): $(BUILD_DIR)/consumer_stub.o $(LIB_OBJECTS) $(LIB_CFG) | $(BUILD_DIR)
	$(LD65) -C $(LIB_CFG) -Ln $(CONSUMER_LBL) -o $(CONSUMER_PRG) \
	    $(BUILD_DIR)/consumer_stub.o $(LIB_OBJECTS)

# --- POLYVAL-only consumer check (issue #47 regression guard) --------------
# Links test/consumer_stub_noaes.s -- which defines its OWN aes_state and
# gcmsiv_tag -- against the real polyval-long.a / polyval-short.a archives.
# If the NO_AES archives ever again export the AES / GCM-SIV BSS block, ld65
# fails here with "Duplicate external identifier".
#
# Runs against EVERY POLYVAL-only archive because data.o is archived into
# each of them; a leak can regress on any profile independently.
consumer-check-noaes:
	$(MAKE) clean
	$(MAKE) POLYVAL_PROFILE=long POLYVAL_NO_AES=1 $(LIB_DIR)/polyval-long.a
	$(CA65) -I $(SRC_DIR) -D POLYVAL_PROFILE=2 -D LIB_POLYVAL_NO_AES=1 \
	    -o $(BUILD_DIR)/consumer_stub_noaes.o $(TEST_DIR)/consumer_stub_noaes.s
	$(LD65) -C $(LIB_CFG) -o $(BUILD_DIR)/consumer_stub_noaes_long.prg \
	    $(BUILD_DIR)/consumer_stub_noaes.o $(LIB_DIR)/polyval-long.a
	$(MAKE) clean
	$(MAKE) POLYVAL_PROFILE=short POLYVAL_NO_AES=1 $(LIB_DIR)/polyval-short.a
	$(CA65) -I $(SRC_DIR) -D POLYVAL_PROFILE=1 -D LIB_POLYVAL_NO_AES=1 \
	    -o $(BUILD_DIR)/consumer_stub_noaes.o $(TEST_DIR)/consumer_stub_noaes.s
	$(LD65) -C $(LIB_CFG) -o $(BUILD_DIR)/consumer_stub_noaes_short.prg \
	    $(BUILD_DIR)/consumer_stub_noaes.o $(LIB_DIR)/polyval-short.a
	$(MAKE) clean
	$(MAKE) POLYVAL_PROFILE=compact POLYVAL_NO_AES=1 $(LIB_DIR)/polyval-compact.a
	$(CA65) -I $(SRC_DIR) -D POLYVAL_PROFILE=3 -D LIB_POLYVAL_NO_AES=1 \
	    -o $(BUILD_DIR)/consumer_stub_noaes.o $(TEST_DIR)/consumer_stub_noaes.s
	$(LD65) -C $(LIB_CFG) -o $(BUILD_DIR)/consumer_stub_noaes_compact.prg \
	    $(BUILD_DIR)/consumer_stub_noaes.o $(LIB_DIR)/polyval-compact.a
	@echo "consumer-check-noaes: polyval-long.a + polyval-short.a + polyval-compact.a link clean"

# --- VICE quick check -----------------------------------------------------
run: all
	x64sc -moncommands $(LABELS) $(PRG)

# --- Clean ----------------------------------------------------------------
# SCRATCH_TREES are the trees this repo's own tooling creates outside
# $(BUILD_DIR). Since #93 gave them per-run names, the literal
# `build-knobcheck` this listed matched nothing -- adversarial review caught
# that the entry was dead and its comment false, so a run killed with SIGKILL
# (which no trap can catch) left a tree nothing would ever sweep.
#
# This REVERSES the position argued in #99, that deletion should stay an
# explicit list because a wrong ignore rule hides a file while a wrong
# `rm -rf` glob deletes someone's directory. That still holds for an
# unbounded `build*`. This is bounded: a fixed prefix plus a dot, matching
# only names our own tooling mints via mktemp. An unmatched glob stays
# literal and `rm -rf` exits 0 on it, so `make clean` is safe on a clean tree
# -- verified under /bin/sh, which is what recipes use and which has neither
# nullglob nor failglob.
#
# ONE prefix for every tool, and check-scratch-prefix asserts it. Two
# prefixes meant three places had to agree with nothing checking they did,
# which is how the first cut of #93 shipped with a `clean` entry that matched
# nothing -- the same shape as #99's .gitignore drift.
SCRATCH_TREES = build-scratch.*

clean:
	rm -rf $(BUILD_DIR) $(SCRATCH_TREES)

# --- No build artifacts in git (issue #99) ---------------------------------
# build-short/ sat TRACKED for two tags -- six artifacts from an unattributed
# configuration, which a submodule-pinning consumer could have linked without
# being able to tell them from the shipped ones. Neither `clean` nor
# .gitignore covered it, because both were hand-maintained lists.
#
# THREE rules, and they are NOT a complete partition -- the residual gap is
# stated below rather than papered over:
#   * by extension, anywhere. This is the guard for an arbitrary BUILD_DIR
#     override: `make BUILD_DIR=outtree lib` produces a tree no ignore
#     pattern can predict, and a plain `git add -A` stages it -- no `-f`
#     needed, because nothing ignores it. Nothing sits upstream of this rule
#     in that case.
#   * by path under build*, which additionally catches generated files whose
#     extensions can never join the alternation because src/ tracks the same
#     suffixes: build/lib/polyval.inc, build/lib/polyval-example.cfg.
#   * by name for .ca65flags, which is generated and can never legitimately
#     be tracked at any path.
#
# RESIDUAL GAP, measured: under a BUILD_DIR override, generated .inc and
# .cfg copies (outtree/lib/polyval.inc, outtree/lib/polyval-example.cfg)
# match none of the three -- the extension rule structurally cannot take
# .inc/.cfg because src/polyval-example.cfg and src/*.inc are legitimately
# tracked, and the path rule keys on `build`. Closing it would need a fourth
# hand-maintained list of generated basenames, which is the drift that
# produced #99 in the first place. Documented instead: if you override
# BUILD_DIR, do not `git add -A`.
#
# `.lib` is deliberately NOT in the alternation: ca65/release/v0.1.0/
# polyval_short.lib is a real ar65 archive, tracked on purpose as a frozen
# historical artifact, hashed in its MANIFEST.txt and marked DO NOT MODIFY in
# CLAUDE.md. Adding `lib` here would turn a clean tree red and the only fix
# would be editing that subtree.
#
# grep's exit status is checked, not swallowed: 0 is a match, 1 is no match,
# and anything above 1 is an ERROR -- a missing or broken grep otherwise
# yields the same empty result as a clean tree. `git ls-files` is checked
# separately for the same reason. Both are issue #86's shape, and adversarial
# review caught this recipe reintroducing it in the very comment that claimed
# it would not.
# --- §5 footprint equates still bound reality (issue #95) ------------------
# LIB_POLYVAL_RESIDENT_BYTES / _COLD_BYTES are hand-maintained constants,
# refreshed by a human at release, and nothing checked them against a
# measurement -- consumer_stub_shipped.s asserts COLD < RESIDENT, which is
# ordering, not bounding. c64-x25519#142 and c64-ChaCha20-Poly1305#126 both
# shipped this defect in the UNSAFE direction on one day. Placed LAST because
# it rebuilds all six configurations; ~6 s against ~1 s for everything above.
check-footprints:
	@python3.13 $(TOOLS_DIR)/check_footprints.py

# --- every minted scratch tree is one `make clean` sweeps (issue #93) ------
# Cheap source scan, no build. It exists because #93's own fix shipped with a
# SCRATCH_TREES entry that matched nothing, and #99 shipped with a .gitignore
# that enumerated two trees and missed a third: two places that must agree,
# with nothing checking they do.
check-scratch-prefix:
	@python3.13 $(TOOLS_DIR)/check_scratch_prefix.py

check-no-tracked-artifacts:
	@files=$$(git ls-files) || { \
	  echo "check-no-tracked-artifacts: 'git ls-files' failed" >&2; exit 1; }; \
	if [ -z "$$files" ]; then \
	  echo "check-no-tracked-artifacts: 'git ls-files' returned nothing -- not a repo?" >&2; \
	  exit 1; \
	fi; \
	bad=$$(printf '%s\n' "$$files" | grep -E '\.(o|a|prg|lbl)$$'); st=$$?; \
	if [ $$st -gt 1 ]; then \
	  echo "check-no-tracked-artifacts: grep failed (exit $$st) -- the check could not run" >&2; \
	  exit 1; \
	fi; \
	inbuild=$$(printf '%s\n' "$$files" | grep -E '^build|(^|/)\.ca65flags$$'); st2=$$?; \
	if [ $$st2 -gt 1 ]; then \
	  echo "check-no-tracked-artifacts: grep failed (exit $$st2) -- the check could not run" >&2; \
	  exit 1; \
	fi; \
	if [ -n "$$bad" ] || [ -n "$$inbuild" ]; then \
	  echo "check-no-tracked-artifacts: build output is tracked in git:" >&2; \
	  printf '%s\n' "$$bad" "$$inbuild" | grep -v '^$$' | sort -u | sed 's/^/  /' >&2; \
	  echo "  (see issue #99; run 'git rm -r --cached <path>')" >&2; \
	  exit 1; \
	fi; \
	echo "check-no-tracked-artifacts: nothing under build*, no .ca65flags, no .o/.a/.prg/.lbl anywhere"


# --- Umbrella verification target (issue #96) ------------------------------
# ONE list. Before this, nothing invoked the gates as a set: `make dist` had
# no prerequisites at all and tools/build_release.sh called none of them, so a
# release could be minted from a tree where every guard failed. The sibling
# case that prompted the check is c64-ChaCha20-Poly1305#119/PR#128, where a
# release script carried its own hand-copied gate list that had drifted and
# shipped tarballs verified with four of six gates. Their conclusion is the
# reason this is a variable and not a second list in the script: "a second
# list is a second thing to forget."
#
# The VICE suite is deliberately NOT here. It needs x64sc and ~3.5 minutes,
# and this machine is shared with other agents' emulator instances (see the
# process-hygiene section in CLAUDE.md). These are build-and-link gates only:
# whole set measured at ~1 second from a cold tree.
#
# The list covers EVERY shipped configuration plus the demo app, not just the
# four consumer gates. The first cut had only the gates, and adversarial
# review broke it in one move: an undefined symbol appended to
# src/main_loop.s left `make` failing while `make verify` printed "all 4
# gates pass" and `make dist` minted a tarball containing source that does
# not assemble. The tarball ships source, so the consumer receives a tree
# that cannot build. A gate set that does not build what ships is not a gate
# set.
#
# Covered here and nowhere else: `all` (the app PRG -- main.s, boot.s,
# main_loop.s, display.s, disk_io.s, gcm_siv_ui.s, strings.s, data_app.s and
# src/c64.cfg are in no other target) and the three AEAD archive variants.
# consumer-check-shipped builds polyval.a, and consumer-check-noaes builds
# the three NO_AES archives, so those six were already reachable.
#
# check-no-tracked-artifacts goes FIRST: it costs one `git ls-files`, needs no
# build, and its failure mode -- generated files committed to the repo -- is
# one a consumer sees in a clone whether or not anything compiles. Deferred
# out of PR #100 only to avoid stacking it on this target's own PR; wired in
# once that merged.
#
# Order matters twice. The profile-pinned lib-polyval-* targets and
# consumer-check-noaes each run `make clean` first, so they go after the
# gates that would otherwise be rebuilt for nothing. And because the last of
# them leaves BUILD_DIR holding COMPACT/NO_AES objects, the recipe ends by
# rebuilding the default tree -- otherwise `make verify` (or a release, which
# depends on it) would silently hand the caller back a non-default build/.
#
# DO NOT ADD AN ARCHIVE-HASH REPRODUCIBILITY CHECK TO THIS LIST (issue #97).
# `build/lib/*.a` and `build/*.o` are NOT byte-reproducible; `build/*.prg` and
# the release tarball ARE. A gate that hashes an archive across two builds is
# red or green depending on when the clock happened to tick, and an
# intermittent red trains people to re-run until green.
#
# MECHANISM, measured 2026-09-07 (ca65/ar65/od65 V2.18, homebrew cc65). Both
# sources of variation are ca65's assembly time; ar65 contributes no clock of
# its own:
#   1. ca65 writes OPT_DATETIME -- the assembly wall-clock second -- into
#      every object, as a 5-byte VARIABLE-LENGTH integer, 7 value bits per
#      byte, low group first (`od65 --dump-all` prints it as `Data: <unix
#      time>`). Decoded from build/data.o at 0-based offset 100 it matched
#      the assembly second exactly in three separate objects.
#   2. ar65's trailing index stores each member's FILE mtime, which for a
#      fresh build is when ca65 wrote the object. Demonstrated in isolation:
#      `touch`ing an unchanged .o and re-archiving changed 3 bytes, all of
#      them inside the index.
# ar65 stores and returns member data VERBATIM. Extracting a member 13 s
# after archiving gave a byte-identical object, and re-archiving unchanged
# objects 31 s later gave a byte-identical archive. Issue #97 attributes the
# stamp to ar65 and says the member objects are reproducible; both are wrong,
# and the second matters -- see the extraction trap below.
#
# HOW MANY BYTES DIFFER is set by how many 7-bit groups of the stamp differ,
# i.e. which 128-second (then 16384-, then 2097152-second) boundaries the two
# builds straddle. NOT by the elapsed interval. Measured:
#   - six clean `make lib` runs gave two distinct polyval.a hashes, split
#     exactly on a second boundary (four at t=1788828363 matching, two at
#     t+1 matching);
#   - that t/t+1 pair differs in exactly 20 bytes for polyval.a's 10 members
#     -- one low group byte per member's OPT_DATETIME plus one per index
#     mtime -- with every byte going 0313 -> 0314 octal, i.e. 0x4B|0x80 ->
#     0x4C|0x80, and 1788828363 mod 128 = 75 = 0x4B;
#   - 20 is not a constant and does not track the interval. A pair 238 s
#     apart differs in 40 bytes because it crosses a 128-boundary twice; a
#     synthetic single-member pair only 2 s apart, straddling one, likewise
#     differs in two stamp bytes rather than one. So "tolerate <= 20 differing
#     bytes for builds within a second" is NOT a workaround -- two builds one
#     second apart can straddle a group boundary too.
#   - `build/polyval.prg` and `build/lib_main.prg` were identical across six
#     clean builds spanning five second boundaries: ld65 does not propagate
#     the stamp. `make dist` was byte-identical across three runs spanning two
#     second boundaries, and ships source only, so no released artifact is
#     affected. Byte-identity receipts in release notes must therefore stay on
#     PRG and tarball hashes; an archive hash in a receipt will not reproduce
#     and will look like a regression.
#
# WHAT IS SAFE TO CHECK, and what this repo does check: the member NAME LIST
# carries no timestamp. `tools/check_archive_members.sh` runs from every
# archive recipe below and asserts `ar65 t` equals that rule's own
# prerequisite list. It is timestamp-immune, so it cannot flake.
#
# If per-member CONTENT comparison is ever wanted on top of that, two traps,
# both measured rather than guessed:
#   - hashing EXTRACTED members does not compare equal across differently
#     timed builds. Not because extraction adds anything -- it does not --
#     but because the objects already differ: the OPT_DATETIME is inside the
#     member data ar65 stored verbatim;
#   - `od65 --dump-all` prints both that stamp and the *source* files'
#     modification times, which are checkout-dependent; a dump comparison
#     must filter both.
# Any such check must also fail loudly when `ar65`/`od65` are missing or the
# member list comes back empty -- an empty member set otherwise compares equal
# to an empty member set and the gate passes vacuously (the #86/#91 shape).
VERIFY_TARGETS = check-no-tracked-artifacts check-scratch-prefix all lib-verify consumer-check \
                 consumer-check-shipped lib-polyval-gcmsiv \
                 lib-polyval-gcmsiv-short lib-polyval-gcmsiv-compact \
                 consumer-check-noaes check-footprints

# SCOPE: this fixes the SCRATCH trees (issue #93). Two concurrent `make
# verify` runs in ONE working tree still collide, because they share
# $(BUILD_DIR) itself -- measured, one of each pair fails with
# "ar65: Error: Read error (file corrupt?)" or "Problem deleting temporary
# library file". Unique scratch names cannot fix that; only a private
# BUILD_DIR per run could, and that would cost the "default build restored"
# property this target deliberately provides. `make -j` within ONE invocation
# is fine -- make serialises its own targets.
verify:
	@for t in $(VERIFY_TARGETS); do \
	  echo "verify: $$t"; \
	  $(MAKE) --no-print-directory $$t >/dev/null || { \
	    echo "verify: FAILED at $$t -- re-run \`make $$t\` to see why" >&2; \
	    exit 1; \
	  }; \
	done
	@$(MAKE) --no-print-directory all >/dev/null || { \
	  echo "verify: FAILED restoring the default build after the pinned targets" >&2; \
	  exit 1; \
	}
	@echo "verify: all $(words $(VERIFY_TARGETS)) targets pass; default build restored"

# --- Reproducible release tarball -----------------------------------------
# `make dist VERSION=vX.Y.Z` produces c64-polyval-<VERSION>.tar.gz at the
# repo root by invoking tools/build_release.sh. The script enforces the
# version-arg regex, cross-checks the VERSION file, stages the canonical
# vendoring set, and stamps docs/RELEASE_NOTES_<VERSION>.md with the
# tarball's own size + SHA256 (two-pass fixed-point). Determinism: fixed
# mtime + owner/group + gzip -n so the same source tree always produces
# a byte-identical tarball.
# `dist` depends on `verify`: a release cannot be minted from a tree where a
# gate fails (issue #96). The gates run before build_release.sh, so a refusal
# costs a second and touches nothing. They build into $(BUILD_DIR), which the
# tarball does not stage, so the artifact is unaffected -- the red/green for
# this change asserts that the tarball hash is byte-identical with and
# without the prerequisite.
dist: verify
	@if [ -z "$(VERSION)" ]; then \
	  echo "usage: make dist VERSION=vX.Y.Z" >&2; \
	  exit 1; \
	fi
	@$(TOOLS_DIR)/build_release.sh $(VERSION)
