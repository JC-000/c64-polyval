# ---------------------------------------------------------------------------
# ca65/Makefile - sidecar ca65 build for c64-polyval
#
# Targets:
#   all              (default) build build/polyval.prg + build/labels.txt
#                    (full build including app layer)
#   lib              build build/lib_main.prg using lib_only.cfg - library-
#                    only verification link. Fails if any lib .o file
#                    references an app-layer symbol. Not runnable.
#   consumer-check   assemble + link test/consumer_stub.s against lib_only.cfg
#                    to prove the public ABI is stable for downstream ports.
#   run              launch VICE x64sc on the .prg (non-test quick check)
#   clean            remove build/
#
# Variables:
#   POLYVAL_PROFILE=long|short   maps to -D POLYVAL_PROFILE=2|1 for ca65.
#                                Default: long.
# ---------------------------------------------------------------------------

CA65      := ca65
LD65      := ld65
PYTHON    := python3

BUILD     := build
SRC       := src

CFG       := c64.cfg
LIB_CFG   := lib_only.cfg
TARGET    := $(BUILD)/polyval.prg
LBL_RAW   := $(BUILD)/polyval.lbl
LBL_VICE  := $(BUILD)/labels.txt
LIB_TARGET := $(BUILD)/lib_main.prg
LIB_LBL_RAW := $(BUILD)/lib_main.lbl
LIB_LBL_VICE := $(BUILD)/lib_labels.txt
CONSUMER_TARGET := $(BUILD)/consumer_stub.prg
CONSUMER_LBL_RAW := $(BUILD)/consumer_stub.lbl

# Profile: long (default) or short.
POLYVAL_PROFILE ?= long
ifeq ($(POLYVAL_PROFILE),long)
  PROFILE_VAL := 2
else ifeq ($(POLYVAL_PROFILE),short)
  PROFILE_VAL := 1
else
  $(error POLYVAL_PROFILE must be 'long' or 'short', got '$(POLYVAL_PROFILE)')
endif

CA65FLAGS := -I $(SRC) -I $(SRC)/lib -D POLYVAL_PROFILE=$(PROFILE_VAL) -g
LD65FLAGS := -C $(CFG)

# Profile-selected POLYVAL implementation. ACME uses polyval.asm as a
# !source dispatcher that pulls in long or short; under ld65 we pick one
# object at link time instead.
ifeq ($(POLYVAL_PROFILE),long)
  POLYVAL_IMPL := $(SRC)/lib/polyval_long.s
else
  POLYVAL_IMPL := $(SRC)/lib/polyval_short.s
endif

# Library sources (shared between the full build and `make lib`). Keep this
# list explicit -- wildcards hide ordering bugs.
LIB_SRCS := \
    $(SRC)/lib/tables.s \
    $(SRC)/lib/data.s \
    $(SRC)/lib/aes_encrypt.s \
    $(SRC)/lib/aes_decrypt.s \
    $(SRC)/lib/gcm_siv.s \
    $(POLYVAL_IMPL)

# Application sources (full build only, NOT the `make lib` verification).
APP_SRCS := \
    $(SRC)/main.s \
    $(SRC)/zp.s \
    $(SRC)/boot.s \
    $(SRC)/main_loop.s \
    $(SRC)/disk_io.s \
    $(SRC)/display.s \
    $(SRC)/gcm_siv_ui.s \
    $(SRC)/strings.s \
    $(SRC)/data_app.s

SRCS := $(APP_SRCS) $(LIB_SRCS)

OBJS := $(patsubst $(SRC)/%.s,$(BUILD)/%.o,$(SRCS))
LIB_OBJS := $(patsubst $(SRC)/%.s,$(BUILD)/%.o,$(LIB_SRCS)) $(BUILD)/lib_main.o

.PHONY: all run clean lib consumer-check release
.DEFAULT_GOAL := all

all: $(TARGET) $(LBL_VICE)

$(BUILD):
	mkdir -p $(BUILD)
	mkdir -p $(BUILD)/lib

# Per-file assembly. `$@` is the .o, `$<` is the .s.
$(BUILD)/%.o: $(SRC)/%.s | $(BUILD)
	@mkdir -p $(dir $@)
	$(CA65) $(CA65FLAGS) -o $@ $<

# Link: emit .prg + raw .lbl (ld65 format), then shim to VICE format.
$(TARGET) $(LBL_RAW): $(OBJS) $(CFG) | $(BUILD)
	$(LD65) $(LD65FLAGS) -Ln $(LBL_RAW) -o $(TARGET) $(OBJS)

$(LBL_VICE): $(LBL_RAW) tools/vice_label_shim.py
	$(PYTHON) tools/vice_label_shim.py $(LBL_RAW) $(LBL_VICE)

run: all
	x64sc $(TARGET)

clean:
	rm -rf $(BUILD)

# ---------------------------------------------------------------------------
# Library-only verification build.
#
# Links ONLY the lib .o files + a minimal stub that jsr's every public
# symbol, using lib_only.cfg (which omits the LOADADDR/app-segment slop and
# places code at $4000). If any lib file accidentally references an app-
# layer symbol, ld65 errors out with "unresolved external" -- that's the
# test. The produced .prg is NOT runnable; existence IS the verification.
# ---------------------------------------------------------------------------
lib: $(LIB_TARGET)

$(LIB_TARGET) $(LIB_LBL_RAW): $(LIB_OBJS) $(LIB_CFG) | $(BUILD)
	$(LD65) -C $(LIB_CFG) -Ln $(LIB_LBL_RAW) -o $(LIB_TARGET) $(LIB_OBJS)

$(LIB_LBL_VICE): $(LIB_LBL_RAW) tools/vice_label_shim.py
	$(PYTHON) tools/vice_label_shim.py $(LIB_LBL_RAW) $(LIB_LBL_VICE)

# ---------------------------------------------------------------------------
# Consumer-stub smoke check.
#
# Assembles test/consumer_stub.s (which imports the public API surface via
# the .inc files and does nothing but jsr each entry point) and links it
# against the library using lib_only.cfg. Succeeds iff the downstream
# import path is stable. Intended as a rehearsal for c64-wireguard /
# c64-https consumer integration.
# ---------------------------------------------------------------------------
consumer-check: $(CONSUMER_TARGET)

$(BUILD)/consumer_stub.o: test/consumer_stub.s | $(BUILD)
	@mkdir -p $(dir $@)
	$(CA65) $(CA65FLAGS) -o $@ $<

$(CONSUMER_TARGET): $(BUILD)/consumer_stub.o $(patsubst $(SRC)/%.s,$(BUILD)/%.o,$(LIB_SRCS)) $(LIB_CFG) | $(BUILD)
	$(LD65) -C $(LIB_CFG) -Ln $(CONSUMER_LBL_RAW) -o $(CONSUMER_TARGET) \
	    $(BUILD)/consumer_stub.o \
	    $(patsubst $(SRC)/%.s,$(BUILD)/%.o,$(LIB_SRCS))

# ---------------------------------------------------------------------------
# Release artifact build.
#
# Produces release/v0.1.0/ with ar65-packaged libraries for both POLYVAL
# profiles, public headers, an example consumer, and attestation files.
# Idempotent at the content level: running `make release` twice yields
# archives with identical contents and sizes. The ar65 archiver embeds a
# small amount of build-time metadata per module (~2 B each), so the
# raw .lib bytes will differ in ~12 positions between runs even though
# every object module within the archive is bit-exact. This is ar65
# behavior, not something this Makefile controls.
#
# Release .o files are built WITHOUT -g into release_build/ so debug info
# does not bloat the shipped archive. The main app `build/` tree is
# untouched.
# ---------------------------------------------------------------------------
RELEASE_VER  := v0.1.0
RELEASE_DIR  := release/$(RELEASE_VER)
RELBUILD     := $(BUILD)/release_long
RELBUILDS    := $(BUILD)/release_short
REL_CA65FLAGS_LONG  := -I $(SRC) -I $(SRC)/lib -D POLYVAL_PROFILE=2
REL_CA65FLAGS_SHORT := -I $(SRC) -I $(SRC)/lib -D POLYVAL_PROFILE=1

REL_LIB_SRC_NAMES := tables data aes_encrypt aes_decrypt gcm_siv
REL_LONG_OBJS     := $(addprefix $(RELBUILD)/,  $(addsuffix .o,$(REL_LIB_SRC_NAMES))) $(RELBUILD)/polyval_long.o
REL_SHORT_OBJS    := $(addprefix $(RELBUILDS)/, $(addsuffix .o,$(REL_LIB_SRC_NAMES))) $(RELBUILDS)/polyval_short.o

release: | $(BUILD)
	@echo "Building release $(RELEASE_VER)..."
	mkdir -p $(RELBUILD) $(RELBUILDS)
	mkdir -p $(RELEASE_DIR)/include $(RELEASE_DIR)/examples $(RELEASE_DIR)/attestation
	# Assemble LONG profile release .o files (no -g).
	$(CA65) $(REL_CA65FLAGS_LONG) -o $(RELBUILD)/tables.o       $(SRC)/lib/tables.s
	$(CA65) $(REL_CA65FLAGS_LONG) -o $(RELBUILD)/data.o         $(SRC)/lib/data.s
	$(CA65) $(REL_CA65FLAGS_LONG) -o $(RELBUILD)/aes_encrypt.o  $(SRC)/lib/aes_encrypt.s
	$(CA65) $(REL_CA65FLAGS_LONG) -o $(RELBUILD)/aes_decrypt.o  $(SRC)/lib/aes_decrypt.s
	$(CA65) $(REL_CA65FLAGS_LONG) -o $(RELBUILD)/gcm_siv.o      $(SRC)/lib/gcm_siv.s
	$(CA65) $(REL_CA65FLAGS_LONG) -o $(RELBUILD)/polyval_long.o $(SRC)/lib/polyval_long.s
	# Assemble SHORT profile release .o files (no -g).
	$(CA65) $(REL_CA65FLAGS_SHORT) -o $(RELBUILDS)/tables.o        $(SRC)/lib/tables.s
	$(CA65) $(REL_CA65FLAGS_SHORT) -o $(RELBUILDS)/data.o          $(SRC)/lib/data.s
	$(CA65) $(REL_CA65FLAGS_SHORT) -o $(RELBUILDS)/aes_encrypt.o   $(SRC)/lib/aes_encrypt.s
	$(CA65) $(REL_CA65FLAGS_SHORT) -o $(RELBUILDS)/aes_decrypt.o   $(SRC)/lib/aes_decrypt.s
	$(CA65) $(REL_CA65FLAGS_SHORT) -o $(RELBUILDS)/gcm_siv.o       $(SRC)/lib/gcm_siv.s
	$(CA65) $(REL_CA65FLAGS_SHORT) -o $(RELBUILDS)/polyval_short.o $(SRC)/lib/polyval_short.s
	# Package archives. `rm -f` first so `ar65 r` is idempotent (ar65
	# always *adds*; we want a fresh archive each invocation).
	rm -f $(RELEASE_DIR)/polyval_long.lib $(RELEASE_DIR)/polyval_short.lib
	ar65 r $(RELEASE_DIR)/polyval_long.lib  $(REL_LONG_OBJS)
	ar65 r $(RELEASE_DIR)/polyval_short.lib $(REL_SHORT_OBJS)
	# Copy verbatim headers. abi_v1.inc / test_probes.inc are maintained
	# in-tree under release/v0.1.0/include/ and are NOT regenerated by
	# this target (their content is the release promise itself).
	cp $(SRC)/lib/constants_lib.inc $(RELEASE_DIR)/include/constants_lib.inc
	cp $(SRC)/lib/polyval_api.inc   $(RELEASE_DIR)/include/polyval_api.inc
	@echo "Release $(RELEASE_VER) built under $(RELEASE_DIR)/"
	@ls -la $(RELEASE_DIR)/*.lib
