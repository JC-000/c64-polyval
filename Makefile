PRG = build/polyval.prg
LABELS = build/labels.txt

SRC = $(wildcard src/*.asm)

# POLYVAL build profile: "long" (default, throughput, ~4k cy multiply) or
# "short" (low-latency GCM-SIV, ~19k cy multiply but ~29k cy precompute).
#   make                       -> long (default)
#   make POLYVAL_PROFILE=long
#   make POLYVAL_PROFILE=short
POLYVAL_PROFILE ?= long

# ACME -D takes numeric values, so translate the friendly profile name into
# the matching sentinel value from constants.asm:
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

.PHONY: all clean run

all: $(PRG)

$(PRG): $(SRC) | build
	cd src && acme $(ACME_FLAGS) -f cbm -o ../$(PRG) --vicelabels ../$(LABELS) main.asm

build:
	mkdir -p build

run: $(PRG)
	x64sc -autostart $(PRG)

clean:
	rm -f $(PRG) $(LABELS)
