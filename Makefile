# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

# Development tasks for ThreeMojo. Run `make help` for the list.
#
# Results are cached on a hash of the source contents, so re-running a task
# whose inputs have not changed costs nothing. Use `make -B <task>` to force.

MOJO := .venv/bin/mojo
# -I . puts the repo root on the import path so `from math.vector3 import ...`
# resolves. Without it Mojo reports "unable to locate module".
MOJOFLAGS := -I .

# Every mojo invocation prints a harmless "Failed to initialize Crashpad"
# warning we want to strip. Piping to sed would discard mojo's exit status,
# and `.SHELLFLAGS := -o pipefail` is not an option: macOS ships GNU Make 3.81
# and .SHELLFLAGS was only added in 3.82, so it is silently ignored. Instead
# capture the output, save $? immediately, then filter. `run` is a call-style
# variable: $(call run,<command>) leaves the status in $$rc.
define run
out=$$($(1) 2>&1); rc=$$?; echo "$$out" | sed '/Crashpad/d'
endef

# --- sources ----------------------------------------------------------------
# Library modules have no main(), so they are checked with `mojo doc`.
LIB_SOURCES  := $(shell find math render units cameras core geometries \
                  objects renderers \
                  -name '*.mojo' \
                  -not -name '__init__.mojo')
# The coverage tool splits the same way: importable modules, plus two CLIs.
TOOL_CLIS    := coverage/build_cli.mojo coverage/report_cli.mojo
TOOL_LIBS    := $(filter-out $(TOOL_CLIS),$(wildcard coverage/*.mojo))
# Anything with a main() can be compiled, which also type-checks its imports.
# tests/compile_fail is deliberately excluded: those files must NOT compile,
# which is the point of them, so linting them would always fail.
ENTRY_POINTS := $(shell find tests examples bench -name '*.mojo' \
                  -not -path 'tests/compile_fail/*') $(TOOL_CLIS)
COMPILE_FAIL := $(wildcard tests/compile_fail/*.mojo)
DOC_SOURCES  := $(LIB_SOURCES) $(TOOL_LIBS)
TESTS        := $(wildcard tests/test_*.mojo)
SOURCES      := $(DOC_SOURCES) $(ENTRY_POINTS)
FORMATTED    := $(SOURCES) $(COMPILE_FAIL)

# Sources whose coverage is measured. The coverage tool is deliberately absent
# so a bug in it cannot flatter its own numbers.
#
# COVERAGE_EXCLUDE drops a file from measurement entirely. render/png.mojo is
# excluded because instrumenting it makes the suite take minutes: the cost is
# in compiling the instrumented copy, not in running it. The module is still
# fully tested by tests/test_png.mojo -- it is the coverage *measurement* that
# is impractical, and the exclusion is listed here rather than hidden so the
# gap stays visible.
#
# render/gpu.mojo is excluded for a harder reason than speed: the probes write
# to stderr, and there is no stderr inside a GPU kernel. Instrumenting device
# code cannot work at all under this design.
# render/gpu.mojo is the one module that cannot be measured under this design:
# a probe writes to stderr, and a GPU kernel has no stderr. It is covered
# instead by tests asserting its output matches the CPU rasterizer exactly.
#
# Four other modules used to sit here because instrumenting them made the
# *compile* take minutes. The cause turned out to be one construct the
# instrumenter emitted -- a Bool loop flag assigned a constant and read after
# nested loops -- and not the modules at all. See coverage/instrument.mojo.
COVERAGE_EXCLUDE := render/gpu.mojo
COVERED := $(filter-out $(COVERAGE_EXCLUDE),$(LIB_SOURCES))
COV_DIR := coverage/build
# Rendered images land here. Gitignored, but kept between runs so they can be
# looked at; `make clean` removes it.
OUT_DIR := out

# --- caching ----------------------------------------------------------------
# A task's result is keyed on the content of every file that can affect it, so
# a task re-runs only when something relevant changed. Content rather than
# mtime, so `make fmt` rewriting a file byte-identically keeps the cache warm
# and a fresh `git clone` does not throw it away.
# Test suites are independent processes, and every one pays a fixed compile
# cost of roughly a third of a second whatever it contains. Running them at
# once turns that floor from a sum into a maximum.
JOBS ?= $(shell sysctl -n hw.logicalcpu 2> /dev/null \
          || nproc 2> /dev/null || echo 4)

# One second per test suite. Coverage slower than that is a bug in the
# instrumentation rather than a slow machine, and should fail loudly instead
# of hanging. perl's alarm is used because macOS ships no `timeout`.
# tests/test_gpu.mojo is left out of the coverage run: it exercises
# render/gpu.mojo, which cannot be instrumented at all, so it contributes no
# records while costing a Metal shader compile and a pixel-by-pixel image
# comparison. It still runs in `make test`, where its job is to prove the GPU
# and CPU rasterizers agree.
COVERAGE_TESTS := $(filter-out tests/test_gpu.mojo,$(TESTS))
COV_BUDGET := $(words $(COVERAGE_TESTS))

CACHE_DIR := .cache
HASHER    := $(shell command -v shasum > /dev/null 2>&1 \
               && echo "shasum -a 256" || echo "sha256sum")
INPUTS    := $(SOURCES) $(COMPILE_FAIL) Makefile
HASH      := $(shell cat $(INPUTS) 2>/dev/null | $(HASHER) | cut -c1-12)

TEST_STAMP := $(CACHE_DIR)/test-$(HASH)
LINT_STAMP := $(CACHE_DIR)/lint-$(HASH)
FMT_STAMP  := $(CACHE_DIR)/fmt-$(HASH)
COV_STAMP  := $(CACHE_DIR)/coverage-$(HASH)
NEG_STAMP  := $(CACHE_DIR)/compile-fail-$(HASH)

# Record a task as done, dropping that task's older stamps so the cache does
# not grow one file per edit.
define stamp
mkdir -p $(CACHE_DIR) && rm -f $(CACHE_DIR)/$(1)-* \
  && touch $(CACHE_DIR)/$(1)-$(HASH)
endef

.PHONY: help check test lint docstrings fmt fmt-check coverage \
        compile-fail example animation bench clean clean-images

help:
	@echo "ThreeMojo tasks (inputs hash to $(HASH), $(COV_BUDGET) tests)"
	@echo
	@echo "  make check      fmt-check + lint + test   <- before committing"
	@echo "  make test       run every tests/test_*.mojo suite"
	@echo "  make lint       compile with warnings promoted to errors"
	@echo "  make fmt        reformat sources in place"
	@echo "  make fmt-check  verify formatting, changing nothing"
	@echo "  make coverage   line / branch / condition / MC-DC coverage"
	@echo "  make compile-fail  assert unit errors are rejected"
	@echo "  make docstrings strict docstring audit (not part of check)"
	@echo "  make example    render out/triangle.png"
	@echo "  make animation  render the animated examples into out/"
	@echo "  make bench      CPU vs GPU rasterization across sizes"
	@echo "  make clean      remove the coverage build and the cache"
	@echo "  make clean-images  remove the rendered images in out/"
	@echo
	@echo "Cached tasks re-run only when a source file's content changes."
	@echo "Force one with 'make -B <task>'."

check: fmt-check lint test compile-fail

# --- cached tasks -----------------------------------------------------------
test: $(TEST_STAMP)
$(TEST_STAMP):
	@printf '%s\n' $(TESTS) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) run $(MOJOFLAGS) "$$1" 2>&1); rc=$$?; \
	             printf "%s\n" "$$out" | sed "/Crashpad/d"; exit $$rc' _ {} \
	  || { echo "Some suites FAILED."; exit 1; }
	@echo "All suites passed."
	@$(call stamp,test)

lint: $(LINT_STAMP)
$(LINT_STAMP):
	@printf '%s\n' $(ENTRY_POINTS) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) build $(MOJOFLAGS) --Werror -o /dev/null "$$1" \
	               2>&1); rc=$$?; printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@printf '%s\n' $(DOC_SOURCES) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) doc $(MOJOFLAGS) --Werror -o /dev/null "$$1" \
	               2>&1); rc=$$?; printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@echo "No warnings."
	@$(call stamp,lint)

# mojo format has no --check flag, so format a scratch copy and diff it.
fmt-check: $(FMT_STAMP)
$(FMT_STAMP):
	@fail=0; tmp=$$(mktemp -d); \
	for f in $(FORMATTED); do \
	  cp "$$f" "$$tmp/candidate.mojo"; \
	  $(call run,$(MOJO) format -q "$$tmp/candidate.mojo"); \
	  if [ $$rc -ne 0 ]; then fail=1; continue; fi; \
	  if ! diff -q "$$f" "$$tmp/candidate.mojo" > /dev/null; then \
	    echo "needs formatting: $$f"; fail=1; \
	  fi; \
	done; \
	rm -rf "$$tmp"; \
	if [ $$fail -ne 0 ]; then echo "Run 'make fmt'."; exit 1; fi; \
	echo "All files formatted."
	@$(call stamp,fmt)

# Instrument the library, run the suite against the instrumented copies, then
# compare what ran against what could have run. `-I $(COV_DIR)` comes first so
# library imports resolve to the instrumented copies; `-I .` backfills the rest
# (the first -I wins). Probe records go to stderr, keeping stdout untouched.
coverage: $(COV_STAMP)
$(COV_STAMP):
	@rm -rf $(COV_DIR)
	@for f in $(COVERED); do mkdir -p "$(COV_DIR)/$$(dirname $$f)"; done
	@$(call run,$(MOJO) run $(MOJOFLAGS) coverage/build_cli.mojo \
	  $(COV_DIR) $(COVERED)); \
	[ $$rc -eq 0 ] || exit 1
	@# Excluded modules are copied through unchanged. Without them the build
	@# tree is an incomplete package and imports fail to resolve, since the
	@# first -I wins and never falls back to the real tree.
	@for f in $(COVERAGE_EXCLUDE); do \
	  mkdir -p "$(COV_DIR)/$$(dirname $$f)"; cp "$$f" "$(COV_DIR)/$$f"; \
	done
	@mkdir -p $(COV_DIR)/hits
	@# One file per suite rather than a shared append: probe records must not
	@# interleave mid-line, and MC-DC needs each decision's records in order.
	@printf '%s\n' $(COVERAGE_TESTS) \
	  | perl -e 'alarm shift; exec @ARGV' $(COV_BUDGET) \
	      xargs -P $(JOBS) -I {} \
	      sh -c 'name=$$(basename "$$1" .mojo); \
	             $(MOJO) run -I $(COV_DIR) $(MOJOFLAGS) "$$1" \
	               2> $(COV_DIR)/hits/$$name.txt > /dev/null' _ {} \
	  || { rc=$$?; \
	       if [ $$rc -eq 142 ]; then \
	         echo "Coverage exceeded its $(COV_BUDGET)s budget (one second per" \
	              "suite). Something is being instrumented that should not be."; \
	       else \
	         echo "A suite failed under instrumentation (exit $$rc); coverage" \
	              "not measured. Run it with -I $(COV_DIR) to see why."; \
	       fi; exit 1; }
	@cat $(COV_DIR)/hits/*.txt > $(COV_DIR)/hits.txt
	@$(call run,$(MOJO) run $(MOJOFLAGS) coverage/report_cli.mojo \
	  $(COV_DIR)/manifest.txt $(COV_DIR)/hits.txt); \
	[ $$rc -eq 0 ] || exit 1
	@$(call stamp,coverage)

# The units system's value is what it *rejects*, and a rejection cannot be
# tested from inside a test suite: a file exercising one would not build. So
# each case lives in its own file that must fail to compile, and this target
# fails if any of them ever starts compiling.
compile-fail: $(NEG_STAMP)
$(NEG_STAMP):
	@fail=0; \
	for f in $(COMPILE_FAIL); do \
	  if $(MOJO) build $(MOJOFLAGS) -o /dev/null "$$f" > /dev/null 2>&1; then \
	    echo "compiled but should not have: $$f"; fail=1; \
	  fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	echo "All $(words $(COMPILE_FAIL)) unit errors rejected."
	@$(call stamp,compile-fail)

# --- uncached tasks ---------------------------------------------------------
# fmt rewrites files, so caching it would be caching a side effect.
fmt:
	@$(call run,$(MOJO) format -q $(FORMATTED)); \
	[ $$rc -eq 0 ] || exit 1; \
	echo "Formatted $(words $(FORMATTED)) files."

# Opt-in: demands Args/Returns/Raises sections and a docstring on every public
# symbol, stdlib-style. Strict enough that it is not part of `make check`.
docstrings:
	@fail=0; \
	for f in $(DOC_SOURCES); do \
	  $(call run,$(MOJO) doc $(MOJOFLAGS) --Werror \
	    --diagnose-missing-doc-strings -o /dev/null "$$f"); \
	  [ $$rc -eq 0 ] || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	echo "Docstrings complete."

bench:
	@$(call run,$(MOJO) run $(MOJOFLAGS) bench/raster_bench.mojo); \
	[ $$rc -eq 0 ] || exit 1

example: $(OUT_DIR)/triangle.png

animation: $(OUT_DIR)/spin.png $(OUT_DIR)/cube.png $(OUT_DIR)/cubes.png

$(OUT_DIR)/cube.png: $(LIB_SOURCES) examples/cube.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/cube.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/cubes.png: $(LIB_SOURCES) examples/cubes.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/cubes.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/spin.png: $(LIB_SOURCES) examples/spin.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/spin.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/triangle.png: $(LIB_SOURCES) examples/triangle.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/triangle.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Deliberately leaves $(OUT_DIR) alone: the rendered images are there to be
# looked at, and a folder that keeps emptying itself is no use to watch.
# `make clean-images` removes them when you actually want them gone.
clean:
	@rm -rf $(COV_DIR) $(CACHE_DIR)
	@echo "Removed the coverage build and the cache; kept $(OUT_DIR)."

clean-images:
	@rm -rf $(OUT_DIR)
	@echo "Removed $(OUT_DIR)."
