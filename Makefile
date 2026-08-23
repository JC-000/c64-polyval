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
#   lib-verify           build $(BUILD_DIR)/lib_main.prg using lib_only.cfg
#                        — library-only verification link at $4000. Fails
#                        if any lib .o references an app-layer symbol. Not
#                        runnable. (Renamed from pre-SPEC-§6 `make lib`.)
#   consumer-check       assemble + link test/consumer_stub.s against the
#                        library to prove the public ABI is callable from a
#                        clean consumer. Output build/consumer_stub.prg.
#   consumer-check-noaes link test/consumer_stub_noaes.s -- a consumer that
#                        owns its own AES/GCM-SIV -- against polyval-long.a
#                        and polyval-short.a. Guards issue #47: the
#                        POLYVAL-only archives must not export the AES /
#                        GCM-SIV BSS block out of the shared data.o.
#   run                  `make all` then launch VICE x64sc with -moncommands.
#   clean                rm -rf build/.
#   dist                 reproducible release tarball.
#
# Variables:
#   POLYVAL_PROFILE=long|short   maps to -D POLYVAL_PROFILE=2|1 for ca65.
#                                Default: long. Selects polyval_long.s vs
#                                polyval_short.s at link time (ca65 has no
#                                ACME-style !source dispatcher).
#
#                                lib-polyval-{long,short} re-invoke `make`
#                                recursively with the right POLYVAL_PROFILE
#                                so the per-profile archives are always
#                                assembled against the matching equate.
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
# `long`  -> -D POLYVAL_PROFILE=2, links polyval_long.o  (table-based, fast)
# `short` -> -D POLYVAL_PROFILE=1, links polyval_short.o (bit-serial, small)
POLYVAL_PROFILE ?= long
ifeq ($(POLYVAL_PROFILE),long)
  PROFILE_VAL        = 2
  POLYVAL_PROFILE_OBJ = polyval_long
else ifeq ($(POLYVAL_PROFILE),short)
  PROFILE_VAL        = 1
  POLYVAL_PROFILE_OBJ = polyval_short
else
  $(error POLYVAL_PROFILE must be 'long' or 'short', got '$(POLYVAL_PROFILE)')
endif

# `-I src` resolves `.include "constants_lib.inc"`, `.include "polyval_api.inc"`,
# and `.include "include/zp.inc"` against the flat src/ layout.
CA65FLAGS = -I $(SRC_DIR) -D POLYVAL_PROFILE=$(PROFILE_VAL) -g

# --- Archive-membership gating (issue #23) --------------------------------
# The POLYVAL-only archives ship no tables.o, so their lib_manifest.o must
# not enumerate the AES S-box tables (§8.0 catch-loop accuracy). This is a
# different axis from POLYVAL_PROFILE — polyval-long.a and polyval-gcmsiv.a
# are both PROFILE=long; only archive membership differs — so it gets its
# own define. Set by the lib-polyval-{long,short} recursive invocations.
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

LIB_MODULES = lib_version zp_config lib_manifest tables data aes_encrypt aes_decrypt gcm_siv $(POLYVAL_PROFILE_OBJ)

MODULES = $(APP_MODULES) $(LIB_MODULES)

OBJECTS     = $(addprefix $(BUILD_DIR)/,$(addsuffix .o,$(MODULES)))
LIB_OBJECTS = $(addprefix $(BUILD_DIR)/,$(addsuffix .o,$(LIB_MODULES)))

# --- Library archive object sets (SPEC §6) --------------------------------
# Each `make lib(-variant)` target builds a single ar65 archive under
# $(LIB_DIR)/. Object-set composition is captured in named variables so the
# inventory is self-describing.
#
# LIB_CORE_OBJS is the shared baseline: every archive carries the SPEC §1
# version equates, the SPEC §2 ZP inventory, and the SPEC §5 aggregate
# manifest equates. None of these emit segment data, so adding them to any
# archive does not grow consumer-side link size — they only contribute
# import-time equates.
LIB_CORE_OBJS = $(BUILD_DIR)/lib_version.o \
                $(BUILD_DIR)/zp_config.o \
                $(BUILD_DIR)/lib_manifest.o

# POLYVAL-only variants: just the chosen polyval primitive plus data.o
# (which provides polyval_h / polyval_temp / polyval_htable[8] / polyval_
# reduce8 buffer reservations). No AES, no GCM-SIV.
LIB_POLYVAL_LONG_OBJS  = $(LIB_CORE_OBJS) $(BUILD_DIR)/data.o \
                         $(BUILD_DIR)/polyval_long.o
LIB_POLYVAL_SHORT_OBJS = $(LIB_CORE_OBJS) $(BUILD_DIR)/data.o \
                         $(BUILD_DIR)/polyval_short.o

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
PIN_$(LIB_DIR)/polyval.a              = long
PIN_$(LIB_DIR)/polyval-gcmsiv.a       = long
PIN_$(LIB_DIR)/polyval-gcmsiv-short.a = short
PIN_$(LIB_DIR)/polyval-long.a         = long-noaes
PIN_$(LIB_DIR)/polyval-short.a        = short-noaes

$(foreach g,$(MAKECMDGOALS),$(if $(PIN_$(g)),$(if $(filter $(PIN_$(g)),$(POLYVAL_PIN)),,\
  $(error goal `$(g)` builds the '$(PIN_$(g))' configuration, but this invocation \
    is '$(POLYVAL_PIN)' (POLYVAL_PROFILE=$(POLYVAL_PROFILE)$(if $(POLYVAL_NO_AES), \
    POLYVAL_NO_AES=$(POLYVAL_NO_AES))). Use the phony target, which cleans and pins \
    for you: `make lib` / `lib-polyval-gcmsiv` (LONG AEAD), \
    `lib-polyval-gcmsiv-short` (SHORT AEAD), `lib-polyval-long` / \
    `lib-polyval-short` (POLYVAL-only). For a SHORT full-AEAD *PRG*, \
    `make POLYVAL_PROFILE=short`))))

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
# SPEC §6.3's looks-reachable rule -- a knob naming an axis MUST select it or
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
    `lib-polyval-gcmsiv-short` (SHORT AEAD), `lib-polyval-long` / \
    `lib-polyval-short` (POLYVAL-only), or `make POLYVAL_PROFILE=short` \
    for a SHORT full-AEAD PRG. CONTRACT_DEFINES remains correct for \
    non-member-set defines such as LIB_NO_BARE_EXPORTS and \
    ZP_CONFIG_NO_EXPORTS)
endif

.PHONY: all lib lib-verify lib-polyval-long lib-polyval-short \
        lib-polyval-gcmsiv lib-polyval-gcmsiv-short consumer-check \
        consumer-check-noaes run clean dist
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
# `lib` and `lib-polyval-gcmsiv` produce byte-identical archives today;
# the two names exist because consumers semantically want "the GCM-SIV
# bundle" rather than "everything we happen to ship". If a future variant
# ever ships more than the AEAD bundle in `lib`, this split lets us widen
# `lib` without surprising AEAD consumers.

lib:                $(LIB_DIR)/polyval.a
lib-polyval-gcmsiv: $(LIB_DIR)/polyval-gcmsiv.a

$(LIB_DIR)/polyval.a: $(LIB_AEAD_OBJS) | $(LIB_DIR)
	rm -f $@
	$(AR65) a $@ $(LIB_AEAD_OBJS)

$(LIB_DIR)/polyval-gcmsiv.a: $(LIB_AEAD_OBJS) | $(LIB_DIR)
	rm -f $@
	$(AR65) a $@ $(LIB_AEAD_OBJS)

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

$(LIB_DIR)/polyval-long.a: $(LIB_POLYVAL_LONG_OBJS) | $(LIB_DIR)
	rm -f $@
	$(AR65) a $@ $(LIB_POLYVAL_LONG_OBJS)

$(LIB_DIR)/polyval-short.a: $(LIB_POLYVAL_SHORT_OBJS) | $(LIB_DIR)
	rm -f $@
	$(AR65) a $@ $(LIB_POLYVAL_SHORT_OBJS)

$(LIB_DIR)/polyval-gcmsiv-short.a: $(LIB_AEAD_OBJS) | $(LIB_DIR)
	rm -f $@
	$(AR65) a $@ $(LIB_AEAD_OBJS)

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
# Runs against BOTH POLYVAL-only archives because data.o is archived into
# each of them; a leak can regress on either profile independently.
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
	@echo "consumer-check-noaes: polyval-long.a + polyval-short.a link clean"

# --- VICE quick check -----------------------------------------------------
run: all
	x64sc -moncommands $(LABELS) $(PRG)

# --- Clean ----------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR)

# --- Reproducible release tarball -----------------------------------------
# `make dist VERSION=vX.Y.Z` produces c64-polyval-<VERSION>.tar.gz at the
# repo root by invoking tools/build_release.sh. The script enforces the
# version-arg regex, cross-checks the VERSION file, stages the canonical
# vendoring set, and stamps docs/RELEASE_NOTES_<VERSION>.md with the
# tarball's own size + SHA256 (two-pass fixed-point). Determinism: fixed
# mtime + owner/group + gzip -n so the same source tree always produces
# a byte-identical tarball.
dist:
	@if [ -z "$(VERSION)" ]; then \
	  echo "usage: make dist VERSION=vX.Y.Z" >&2; \
	  exit 1; \
	fi
	@$(TOOLS_DIR)/build_release.sh $(VERSION)
