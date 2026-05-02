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

# Mirror bin/kai's full prelude chain so ahu fixtures see the
# same canonical surface as upstream demos. When kaikai adds a
# new top-level stdlib module, both bin/kai and this list need
# the entry. The kaikai Makefile keeps an EXTRA_PRELUDE_FLAGS
# block in stage2/Makefile for the same reason — there is no
# way to ship "all preludes" without enumerating them today.
PRELUDES  = $(addprefix --prelude ,$(wildcard $(STDLIB)/core/*.kai)) \
            --prelude $(STDLIB)/protocols.kai \
            --prelude $(STDLIB)/effects.kai \
            --prelude $(STDLIB)/random.kai \
            --prelude $(STDLIB)/encoding/base64.kai \
            --prelude $(STDLIB)/encoding/hex.kai \
            --prelude $(STDLIB)/encoding/json.kai \
            --prelude $(STDLIB)/collections/map.kai \
            --prelude $(STDLIB)/collections/set.kai \
            --prelude $(STDLIB)/collections/queue.kai \
            --prelude $(STDLIB)/collections/stack.kai \
            --prelude $(STDLIB)/math/numeric.kai \
            --prelude $(STDLIB)/math/int.kai \
            --prelude $(STDLIB)/math/real.kai \
            --prelude $(STDLIB)/decimal.kai \
            --prelude $(STDLIB)/money.kai \
            --prelude $(STDLIB)/uuid.kai \
            --prelude $(STDLIB)/regexp.kai \
            --prelude $(STDLIB)/path.kai

# `--path` resolves dotted module imports. stdlib for `list.X`,
# `string.X`, etc.; src/ for ahu's own modules.
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

# Examples that compile but should not run-and-diff in tier1
# (interactive servers, etc). Listed by directory basename.
TIER1_SKIP_RUN = echo
EXAMPLE_RUN_NAMES = $(filter-out $(TIER1_SKIP_RUN),$(EXAMPLE_NAMES))

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
	for n in $(EXAMPLE_RUN_NAMES); do \
	  bin="$(BUILD)/$$n"; \
	  exp="examples/$$n/main.out.expected"; \
	  out="$(BUILD)/$$n.out"; \
	  if [ ! -f "$$exp" ]; then echo "tier1: missing $$exp"; exit 1; fi; \
	  "$$bin" > "$$out"; \
	  diff -u "$$exp" "$$out" || { echo "tier1: example/$$n FAIL"; exit 1; }; \
	  echo "tier1: example/$$n OK"; \
	done; \
	for n in $(TIER1_SKIP_RUN); do \
	  if [ -x "$(BUILD)/$$n" ]; then echo "tier1: example/$$n compile-only OK"; fi; \
	done

# Pattern rule for tests/ fixtures.
AHU_SRC = $(wildcard src/*.kai) $(wildcard src/ahu/*.kai)

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
