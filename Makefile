# ---------------------------------------------------------------------------
# Makefile - top-level ca65 build for c64-polyval
#
# Targets:
#   all              (default) build $(BUILD_DIR)/polyval.prg + labels.txt
#                    (full app + library at $0801).
#   lib              build $(BUILD_DIR)/lib_main.prg using lib_only.cfg -
#                    library-only verification link at $4000. Fails if any
#                    lib .o references an app-layer symbol. Not runnable.
#   consumer-check   assemble + link test/consumer_stub.s against the
#                    library to prove the public ABI is callable from a
#                    clean consumer. Output build/consumer_stub.prg.
#   run              `make all` then launch VICE x64sc with -moncommands.
#   clean            rm -rf build/.
#   dist             reproducible release tarball (Phase 3b implements).
#
# Variables:
#   POLYVAL_PROFILE=long|short   maps to -D POLYVAL_PROFILE=2|1 for ca65.
#                                Default: long. Selects polyval_long.s vs
#                                polyval_short.s at link time (ca65 has no
#                                ACME-style !source dispatcher).
# ---------------------------------------------------------------------------

CA65   = ca65
LD65   = ld65
PYTHON = python3

SRC_DIR   = src
BUILD_DIR = build
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

# --- Module ordering ------------------------------------------------------
# Order matters for ld65 segment layout. Recovered from the old
# ca65/Makefile: APP_MODULES come first, then library modules, then the
# profile-selected polyval implementation last.
APP_MODULES = main zp boot main_loop disk_io display gcm_siv_ui strings data_app

LIB_MODULES = lib_version zp_config tables data aes_encrypt aes_decrypt gcm_siv $(POLYVAL_PROFILE_OBJ)

MODULES = $(APP_MODULES) $(LIB_MODULES)

OBJECTS     = $(addprefix $(BUILD_DIR)/,$(addsuffix .o,$(MODULES)))
LIB_OBJECTS = $(addprefix $(BUILD_DIR)/,$(addsuffix .o,$(LIB_MODULES)))

.PHONY: all lib consumer-check run clean dist
.DEFAULT_GOAL := all

all: $(PRG) $(LABELS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

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
lib: $(LIB_PRG) $(LIB_LABELS)

$(LIB_PRG) $(LIB_LBL_RAW): $(LIB_OBJECTS) $(BUILD_DIR)/lib_main.o $(LIB_CFG) | $(BUILD_DIR)
	$(LD65) -C $(LIB_CFG) -Ln $(LIB_LBL_RAW) -o $(LIB_PRG) \
	    $(LIB_OBJECTS) $(BUILD_DIR)/lib_main.o

$(LIB_LABELS): $(LIB_LBL_RAW) $(TOOLS_DIR)/vice_label_shim.py
	$(PYTHON) $(TOOLS_DIR)/vice_label_shim.py $(LIB_LBL_RAW) $(LIB_LABELS)

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
