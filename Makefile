# ahu Makefile.
#
# Drives the `kai` frontend from the PATH against ahu fixtures. The
# kaikai installation (compiler, stdlib, preludes, C linker) is
# fully resolved by the `kai` wrapper itself — this Makefile only
# does fixture discovery, fixture compilation, and tier1 diffing.
# Portable across any machine with `kai` on the PATH; no dev
# checkout of kaikai required.
#
# Backend pin: `KAI_BACKEND ?= c` is exported below to work around
# kaikai#570 — the LLVM backend in kaikai 0.56.x segfaults at runtime
# on `spawn_actor`, taking down every fixture that touches a cell or
# restart helper. The C backend produces working binaries for all 13
# fixtures. Drop the export once kaikai#570 lands. See
# `docs/known-regressions.md`.

export KAI_BACKEND ?= c

KAI ?= kai

BUILD = build

# Fixture discovery. Two layouts:
#   tests/<name>.kai          -> binary $(BUILD)/<name>,
#                                expected tests/<name>.out.expected
#   examples/<name>/main.kai  -> binary $(BUILD)/<name>,
#                                expected examples/<name>/main.out.expected
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

AHU_SRC = $(wildcard ahu/*.kai)

.PHONY: tier0 tier1 tier1-fixtures clean

# Tier 0 — fast pre-commit sanity. Compiles every fixture; green
# means the ahu modules typecheck and every fixture's source is
# accepted by the kaikai typer.
tier0: $(ALL_BINS)
	@echo "tier0: ahu modules + $(words $(ALL_BINS)) fixtures compile."

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
$(BUILD)/%: tests/%.kai $(AHU_SRC) kai.toml | $(BUILD)
	$(KAI) build $< -o $@

# Pattern rule for examples/<name>/main.kai fixtures.
$(BUILD)/%: examples/%/main.kai $(AHU_SRC) kai.toml | $(BUILD)
	$(KAI) build $< -o $@

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
