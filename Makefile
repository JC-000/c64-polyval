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

# --- Unpinned AEAD archive profile guard (issue #40) ----------------------
# `lib` and `lib-polyval-gcmsiv` do not clean before building, so they are
# only safe under the default profile. The pattern rules do not track
# POLYVAL_PROFILE as a dependency (the profile-switch gotcha in CLAUDE.md),
# so `make lib POLYVAL_PROFILE=short` over a LONG build/ tree reuses the
# stale LONG data.o and lib_manifest.o while assembling a fresh
# polyval_short.o — an archive whose §6.4 manifest describes the wrong
# profile. ar65 cannot notice, so it would exit 0 and ship.
#
# SHORT+AEAD is reachable through its own §6.1 target instead
# (lib-polyval-gcmsiv-short), which pins the profile behind a `make clean`
# exactly as lib-polyval-{long,short} do. That target names
# polyval-gcmsiv-short.a as its goal, so it is not caught here.
#
# Parse-time rather than a recipe line: failing before any object is built
# avoids leaving a half-built tree that a later build would mix in turn.
AEAD_ARCHIVE_GOALS = lib lib-polyval-gcmsiv \
                     $(LIB_DIR)/polyval.a $(LIB_DIR)/polyval-gcmsiv.a
ifneq ($(POLYVAL_PROFILE),long)
  ifneq ($(filter $(AEAD_ARCHIVE_GOALS),$(MAKECMDGOALS)),)
    $(error `lib` / `lib-polyval-gcmsiv` build the LONG AEAD archive and do not \
      clean first, so they require POLYVAL_PROFILE=long (got '$(POLYVAL_PROFILE)'). \
      For the SHORT full-AEAD archive use `make lib-polyval-gcmsiv-short`; \
      for the SHORT POLYVAL-only archive use `make lib-polyval-short`; \
      for a SHORT full-AEAD *PRG* use `make POLYVAL_PROFILE=short`)
  endif
endif

.PHONY: all lib lib-verify lib-polyval-long lib-polyval-short \
        lib-polyval-gcmsiv lib-polyval-gcmsiv-short consumer-check run clean dist
.DEFAULT_GOAL := all

all: $(PRG) $(LABELS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(LIB_DIR): | $(BUILD_DIR)
	mkdir -p $(LIB_DIR)

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
lib-verify: $(LIB_PRG) $(LIB_LABELS)

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
