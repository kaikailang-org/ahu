# ahu Makefile.
#
# Wraps the kaikai compiler driver against the ahu sources.
# Requires `KAI_HOME` to point at a kaikai checkout (defaults to
# the sibling `lnds/kaikai` location used during development).
# Override on the command line: `make tier1 KAI_HOME=/path/to/kaikai`.

KAI_HOME ?= ../kaikai
KAIC2     = $(KAI_HOME)/stage2/kaic2
STAGE0    = $(KAI_HOME)/stage0
STDLIB    = $(KAI_HOME)/stdlib

# Auto-loaded preludes mirror what `bin/kai` selects in kaikai.
PRELUDES  = $(addprefix --prelude ,$(wildcard $(STDLIB)/core/*.kai)) \
            --prelude $(STDLIB)/protocols.kai \
            --prelude $(STDLIB)/effects.kai \
            --prelude $(STDLIB)/random.kai

PATH_FLAGS = --path $(STDLIB) --path src

CC       ?= cc
CFLAGS   += -std=c99 -O0 -g -I $(STAGE0)

BUILD     = build

.PHONY: tier0 tier1 clean

# Tier 0 — fast pre-commit sanity. Compiles the cell module and
# the counter example. ~5-10s once kaic2 is built.
tier0: $(BUILD)/counter
	@echo "tier0: ahu cell module compiles, counter example builds."

# Tier 1 — gated by CI. Builds + runs the counter example and
# diffs against the expected output.
tier1: $(BUILD)/counter
	@echo "tier1: running counter example..."
	@$(BUILD)/counter > $(BUILD)/counter.out
	@diff -u examples/counter/main.out.expected $(BUILD)/counter.out
	@echo "tier1: counter example output matches."

$(BUILD)/counter: examples/counter/main.kai src/cell.kai | $(BUILD)
	$(KAIC2) $(PATH_FLAGS) $(PRELUDES) examples/counter/main.kai > $(BUILD)/counter.c
	$(CC) $(CFLAGS) $(BUILD)/counter.c -o $@

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
