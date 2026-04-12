PRG = build/polyval.prg
LABELS = build/labels.txt

LIB_PRG = build/polyval_lib.prg
LIB_LABELS = build/lib_labels.txt
LIB_RELOC_PRG = build/polyval_lib_reloc.prg
LIB_RELOC_LABELS = build/lib_reloc_labels.txt

SRC = $(wildcard src/*.asm) $(wildcard src/lib/*.asm)
LIB_SRC = $(wildcard src/lib/*.asm)

# POLYVAL build profile: "long" (default, throughput, ~4k cy multiply) or
# "short" (low-latency GCM-SIV, ~19k cy multiply but ~29k cy precompute).
#   make                       -> long (default)
#   make POLYVAL_PROFILE=long
#   make POLYVAL_PROFILE=short
POLYVAL_PROFILE ?= long

# ACME -D takes numeric values, so translate the friendly profile name into
# the matching sentinel value from constants_lib.asm:
#   POLYVAL_PROFILE_SHORT = 1
#   POLYVAL_PROFILE_LONG  = 2
ifeq ($(POLYVAL_PROFILE),long)
POLYVAL_PROFILE_VAL = 2
else ifeq ($(POLYVAL_PROFILE),short)
POLYVAL_PROFILE_VAL = 1
else
$(error POLYVAL_PROFILE must be 'long' or 'short' (got '$(POLYVAL_PROFILE)'))
endif

ACME_FLAGS = -DPOLYVAL_PROFILE=$(POLYVAL_PROFILE_VAL)

.PHONY: all clean run lib lib-reloc-check

all: $(PRG)

$(PRG): $(SRC) | build
	cd src && acme $(ACME_FLAGS) -f cbm -o ../$(PRG) --vicelabels ../$(LABELS) main.asm

# -----------------------------------------------------------------------------
# Library-only verification build.
#
# Assembles src/lib/lib_main.asm, which !source's ONLY files under src/lib/.
# If any library file references an app-side symbol (e.g. chrout,
# input_buffer), this target fails with an unresolved-symbol error. That
# failure IS the check: "is src/lib/ actually self-contained?"
#
# The produced PRG has no BASIC stub and is not meant to be run on a C64.
# -----------------------------------------------------------------------------
lib: $(LIB_PRG) lib-reloc-check

$(LIB_PRG): $(LIB_SRC) | build
	acme -I src $(ACME_FLAGS) -f cbm -o $(LIB_PRG) --vicelabels $(LIB_LABELS) src/lib/lib_main.asm

# Second library build that also drives the POLYVAL_LIB_MEM_BASE relocation
# knob. The default lib_main origin is $C000, so pushing the buffer region
# to $C800 exercises the relocation path end-to-end.
lib-reloc-check: $(LIB_SRC) | build
	acme -I src $(ACME_FLAGS) -DPOLYVAL_LIB_MEM_BASE=49152 -f cbm \
	    -o $(LIB_RELOC_PRG) --vicelabels $(LIB_RELOC_LABELS) src/lib/lib_main.asm

build:
	mkdir -p build

run: $(PRG)
	x64sc -autostart $(PRG)

clean:
	rm -f $(PRG) $(LABELS) $(LIB_PRG) $(LIB_LABELS) $(LIB_RELOC_PRG) $(LIB_RELOC_LABELS)
