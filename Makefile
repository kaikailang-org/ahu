# ahu Makefile.
#
# Wraps the kaikai compiler driver against the ahu sources.
# `KAI_HOME` points at a kaikai checkout (defaults to the sibling
# `lnds/kaikai` location used during development).
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

# Fixture discovery. Two layouts:
#   tests/<name>.kai          → binary $(BUILD)/<name>,
#                               expected tests/<name>.out.expected
#   examples/<name>/main.kai  → binary $(BUILD)/<name>,
#                               expected examples/<name>/main.out.expected
TEST_KAI       = $(wildcard tests/*.kai)
EXAMPLE_KAI    = $(wildcard examples/*/main.kai)

TEST_NAMES     = $(patsubst tests/%.kai,%,$(TEST_KAI))
EXAMPLE_NAMES  = $(patsubst examples/%/main.kai,%,$(EXAMPLE_KAI))

TEST_BINS      = $(addprefix $(BUILD)/,$(TEST_NAMES))
EXAMPLE_BINS   = $(addprefix $(BUILD)/,$(EXAMPLE_NAMES))
ALL_BINS       = $(TEST_BINS) $(EXAMPLE_BINS)

.PHONY: tier0 tier1 tier1-fixtures clean

# Tier 0 — fast pre-commit sanity. Compiles every fixture; green
# means the cell module typechecks and every fixture's source is
# accepted by the kaikai typer.
tier0: $(ALL_BINS)
	@echo "tier0: cell module + $(words $(ALL_BINS)) fixtures compile."

# Tier 1 — gated by CI. Tier 0 plus running each fixture and
# diffing stdout against its .out.expected sibling.
tier1: tier0 tier1-fixtures
	@echo "tier1: $(words $(ALL_BINS)) fixtures pass."

tier1-fixtures: $(ALL_BINS)
	@set -e; \
	for n in $(TEST_NAMES); do \
	  bin="$(BUILD)/$$n"; \
	  exp="tests/$$n.out.expected"; \
	  out="$(BUILD)/$$n.out"; \
	  if [ ! -f "$$exp" ]; then echo "tier1: missing $$exp"; exit 1; fi; \
	  "$$bin" > "$$out"; \
	  diff -u "$$exp" "$$out" || { echo "tier1: $$n FAIL"; exit 1; }; \
	  echo "tier1: $$n OK"; \
	done; \
	for n in $(EXAMPLE_NAMES); do \
	  bin="$(BUILD)/$$n"; \
	  exp="examples/$$n/main.out.expected"; \
	  out="$(BUILD)/$$n.out"; \
	  if [ ! -f "$$exp" ]; then echo "tier1: missing $$exp"; exit 1; fi; \
	  "$$bin" > "$$out"; \
	  diff -u "$$exp" "$$out" || { echo "tier1: example/$$n FAIL"; exit 1; }; \
	  echo "tier1: example/$$n OK"; \
	done

# Pattern rule for tests/ fixtures.
AHU_SRC = $(wildcard src/*.kai)

$(BUILD)/%: tests/%.kai $(AHU_SRC) | $(BUILD)
	$(KAIC2) $(PATH_FLAGS) $(PRELUDES) $< > $(BUILD)/$*.c
	$(CC) $(CFLAGS) $(BUILD)/$*.c -o $@

# Pattern rule for examples/<name>/main.kai fixtures.
$(BUILD)/%: examples/%/main.kai $(AHU_SRC) | $(BUILD)
	$(KAIC2) $(PATH_FLAGS) $(PRELUDES) $< > $(BUILD)/$*.c
	$(CC) $(CFLAGS) $(BUILD)/$*.c -o $@

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
