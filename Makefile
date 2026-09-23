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
LIB_SOURCES  := $(shell find math render units cameras core geometries helpers \
                  objects renderers materials lights loaders animation \
                  postprocessing controls window exporters environments extensions \
                  -name '*.mojo' \
                  -not -name '__init__.mojo')
# The coverage tool splits the same way: importable modules, plus two CLIs.
TOOL_CLIS    := coverage/build_cli.mojo coverage/report_cli.mojo
TOOL_LIBS    := $(filter-out $(TOOL_CLIS),$(wildcard coverage/*.mojo))
# Anything with a main() can be compiled, which also type-checks its imports.
# tests/compile_fail is deliberately excluded: those files must NOT compile,
# which is the point of them, so linting them would always fail.
ENTRY_POINTS := $(shell find tests examples bench tools -name '*.mojo' \
                  -not -path 'tests/compile_fail/*' \
                  -not -path 'bench/mojo10/*') $(TOOL_CLIS)
COMPILE_FAIL := $(wildcard tests/compile_fail/*.mojo)
DOC_SOURCES  := $(LIB_SOURCES) $(TOOL_LIBS)
TESTS        := $(wildcard tests/test_*.mojo)
SOURCES      := $(DOC_SOURCES) $(ENTRY_POINTS)
FORMATTED    := $(SOURCES) $(COMPILE_FAIL)

# --- the optional GPU backend -----------------------------------------------
# Everything that needs MAX installed, kept in one list so the rest of the
# project can be built and tested without it. `make check-cpu` is the whole
# library minus these; `make check-gpu` is these alone.
#
# The split is not cosmetic. The README calls this project standard-library
# only, and that is true of every file except the ones below: `render/gpu.mojo`
# imports `max.gpu.host`, and what imports it inherits the dependency. Leaving
# them in the default lists meant CPU-only development could not be checked
# without MAX, and the claim could rot without anything noticing.
GPU_LIB_SOURCES  := render/gpu.mojo
# The suites that import render/gpu.mojo but open no device: they flatten
# vertices, state tables, textures and lights on the host and read the
# layout back. They need MAX installed and no GPU, so CI runs them with
# `make test-gpu-host` on a runner that has none. They were once part of
# tests/test_gpu.mojo, and went stale there for a week: that suite fails
# every device test on a machine without a GPU, so seven failing layout
# assertions among two hundred device failures were not seen.
GPU_HOST_TESTS   := tests/test_gpu_layout.mojo
GPU_TESTS        := tests/test_gpu.mojo $(GPU_HOST_TESTS)
GPU_ENTRY_POINTS := $(GPU_TESTS) bench/raster_bench.mojo tools/gpu_status.mojo

CPU_LIB_SOURCES  := $(filter-out $(GPU_LIB_SOURCES),$(LIB_SOURCES))
CPU_TESTS        := $(filter-out $(GPU_TESTS),$(TESTS))
CPU_ENTRY_POINTS := $(filter-out $(GPU_ENTRY_POINTS),$(ENTRY_POINTS))
CPU_DOC_SOURCES  := $(CPU_LIB_SOURCES) $(TOOL_LIBS)

# Sources whose coverage is measured. The coverage tool is deliberately absent
# so a bug in it cannot flatter its own numbers.
#
# COVERAGE_EXCLUDE drops a file from measurement entirely, and exactly one file
# is on it. render/gpu.mojo cannot be instrumented at all under this design: a
# probe writes a record to stderr, and a GPU kernel has no stderr. It is
# covered instead by tests/test_gpu.mojo asserting its output matches the CPU
# rasterizer pixel for pixel, and by tests/test_fillrule.mojo pinning the
# coverage math the two now share.
#
# Five modules used to sit here as well -- render/png.mojo among them -- because
# instrumenting them made the *compile* take minutes. The cause turned out to be
# one construct the instrumenter emitted, a Bool loop flag assigned a constant
# and read after nested loops, and not the modules at all. All five are measured
# again. See coverage/instrument.mojo and docs/mojo-compiler-issue/.
COVERAGE_EXCLUDE := render/gpu.mojo
COVERED := $(filter-out $(COVERAGE_EXCLUDE),$(LIB_SOURCES))
COV_DIR := coverage/build
# Rendered images land here. The APNG figures are committed for the wiki;
# `make animation` rewrites them when an example changes.
OUT_DIR := out

# --- affected ---------------------------------------------------------------
# `make check-cpu AFFECTED=origin/main` checks only what the change since that
# ref can reach, as nx's "affected" does. tools/affected.py walks the import
# graph: a suite, an example or a module is checked when it imports a changed
# module, directly or through others, or quotes a changed asset's path.
# Formatting reads each file alone, so it checks the changed files only. A
# change to this Makefile, the CI workflow, the coverage tool or a file the
# script cannot place checks everything. CI checks a pull request this way,
# and checks everything on a push to main.
#
# Coverage stays exact for each module it measures: every suite that can
# reach a measured module runs. What it cannot see is a test change that
# lowers the coverage of a module the change did not reach. The full run on
# main sees that.
AFFECTED :=
COMPILE_FAIL_RUN := $(COMPILE_FAIL)
ifneq ($(strip $(AFFECTED)),)
affected = $(shell python3 tools/affected.py --base $(AFFECTED) $(1))
AFFECTED_CHANGE  := $(shell python3 tools/affected.py --base $(AFFECTED) --list)
FORMATTED        := $(shell python3 tools/affected.py --base $(AFFECTED) \
                      --changed $(FORMATTED))
CPU_ENTRY_POINTS := $(call affected,$(CPU_ENTRY_POINTS))
CPU_DOC_SOURCES  := $(call affected,$(CPU_DOC_SOURCES))
CPU_TESTS        := $(call affected,$(CPU_TESTS))
COMPILE_FAIL_RUN := $(call affected,$(COMPILE_FAIL))
COVERED          := $(call affected,$(COVERED))
$(info Affected since $(AFFECTED): $(words $(CPU_TESTS)) suites, \
  $(words $(CPU_ENTRY_POINTS)) entry points, $(words $(COVERED)) measured \
  modules, $(words $(FORMATTED)) changed files.)
endif
# What the coverage build copies through uninstrumented: the excluded module,
# and in an AFFECTED run every module the change does not reach.
COVERAGE_PASSTHROUGH := $(filter-out $(COVERED),$(LIB_SOURCES))

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

# One second per test suite, as a *hang* detector. The instrumenter once
# emitted a construct that sent the compiler superlinear and turned a
# five-second run into a ten-minute one, and a tight budget catches that
# immediately instead of appearing to hang.
#
# It is deliberately calibrated to a fast development machine, which means it
# is not a portable performance gate: a 2-core CI runner blows through it doing
# nothing wrong. Override it there -- `make coverage COV_BUDGET=300` -- where
# the point is to catch a genuine hang rather than to measure a machine. A
# command-line assignment beats the one below without needing `?=`.
#
# perl's alarm is used because macOS ships no `timeout`.
# tests/test_gpu.mojo is left out of the coverage run: it exercises
# render/gpu.mojo, which cannot be instrumented at all, so it contributes no
# records while costing a Metal shader compile and a pixel-by-pixel image
# comparison. It still runs in `make test`, where its job is to prove the GPU
# and CPU rasterizers agree. tests/test_gpu_layout.mojo is left out for the
# same reason, and because it needs MAX, which the coverage run does not
# install. It runs in `make test` and in CI as `make test-gpu-host`.
COVERAGE_TESTS := $(CPU_TESTS)
# At least a minute: a run of a few affected suites still pays a compile
# that takes longer than a second.
COV_BUDGET := $(shell n=$(words $(COVERAGE_TESTS)); \
                [ $$n -lt 60 ] && n=60; echo $$n)

CACHE_DIR := .cache
HASHER    := $(shell command -v shasum > /dev/null 2>&1 \
               && echo "shasum -a 256" || echo "sha256sum")
INPUTS    := $(SOURCES) $(COMPILE_FAIL) Makefile
# The compiler is an input too. Hashing only the sources meant that upgrading
# Mojo left every success stamp eligible for reuse, so `make check` could pass
# without having compiled a line against the new toolchain. Costs one process
# launch (about 40ms) per make invocation, which is worth not lying about what
# has been checked.
TOOLCHAIN := $(shell $(MOJO) --version 2>/dev/null || echo "no-mojo")
# An AFFECTED run checks a part, so its stamps are keyed on the change as
# well: a partial run must never stand in for a whole one.
HASH      := $(shell { cat $(INPUTS) 2>/dev/null; echo "$(TOOLCHAIN)"; \
                echo "$(AFFECTED) $(AFFECTED_CHANGE)"; } \
               | $(HASHER) | cut -c1-12)

# What the cache key cannot include is whether a GPU is plugged in, which is
# why `test-gpu` is not cached at all. Hardware-dependent tests skip when there
# is no accelerator and the suite still exits successfully, so a cached run
# without one would keep reporting success on a machine that has since grown a
# GPU. Compilation is deterministic given the sources and the compiler, so
# `lint-gpu` is still cached; only running against the device is not.
# test-gpu has no stamp on purpose -- see the target.
TEST_CPU_STAMP := $(CACHE_DIR)/test-cpu-$(HASH)
TEST_GPU_HOST_STAMP := $(CACHE_DIR)/test-gpu-host-$(HASH)
LINT_CPU_STAMP := $(CACHE_DIR)/lint-cpu-$(HASH)
LINT_GPU_STAMP := $(CACHE_DIR)/lint-gpu-$(HASH)
FMT_STAMP  := $(CACHE_DIR)/fmt-$(HASH)
COV_STAMP  := $(CACHE_DIR)/coverage-$(HASH)
NEG_STAMP  := $(CACHE_DIR)/compile-fail-$(HASH)

# Record a task as done, dropping that task's older stamps so the cache does
# not grow one file per edit.
define stamp
mkdir -p $(CACHE_DIR) && rm -f $(CACHE_DIR)/$(1)-* \
  && touch $(CACHE_DIR)/$(1)-$(HASH)
endef

.PHONY: help check check-cpu check-gpu ci test test-cpu test-gpu test-gpu-host \
        docs-check wiki-publish \
        lint lint-cpu lint-gpu gpu-status docstrings fmt fmt-check coverage \
        compile-fail example animation viewer bench bench-scene bench-examples \
        clean clean-images draco-export-check

help:
	@echo "ThreeMojo tasks ($(TOOLCHAIN), inputs hash to $(HASH))"
	@echo
	@echo "  make check      everything                 <- before committing"
	@echo "  make check-cpu  the standard-library-only half ($(words $(CPU_TESTS)) suites)"
	@echo "  make check-gpu  the optional MAX backend ($(words $(GPU_TESTS)) suites)"
	@echo "  make test-gpu-host  the MAX backend's layout suites, no GPU needed"
	@echo "  make ci         check, ignoring the cache"
	@echo "  make test       run every tests/test_*.mojo suite"
	@echo "  make lint       compile with warnings promoted to errors, but the suites"
	@echo "  make fmt        reformat sources in place"
	@echo "  make fmt-check  verify formatting, changing nothing"
	@echo "  make coverage   line / branch / condition / MC-DC coverage"
	@echo "  make compile-fail  assert unit errors are rejected"
	@echo "  make docstrings strict docstring audit (not part of check)"
	@echo "  make docs-check check the documentation against the writing rules"
	@echo "  make wiki-publish  copy docs/wiki/ to the GitHub wiki"
	@echo "  make example    render out/triangle.png"
	@echo "  make animation  render the animated examples into out/"
	@echo "  make viewer     orbit a scene in this terminal with the mouse"
	@echo "  make bench      CPU vs GPU rasterization across sizes"
	@echo "  make bench-scene  a textured sphere through the CPU renderer, per stage"
	@echo "  make bench-examples  each example vs three.js, and vs Mojo 1.0"
	@echo "  make draco-export-check  every Draco export against three.js (not in check)"
	@echo "  make clean      remove the coverage build and the cache"
	@echo "  make clean-images  remove the rendered images in out/"
	@echo
	@echo "Cached tasks re-run only when a source file's content changes."
	@echo "Force one with 'make -B <task>'."

check: check-cpu check-gpu

# The half that needs nothing but the Mojo toolchain. This is what to run when
# MAX is not installed, and what proves the no-dependencies claim is still
# true.
check-cpu: fmt-check lint-cpu test-cpu compile-fail docs-check

# The half that needs MAX and, to be worth anything, a GPU. The status line
# comes first so a suite that skipped every hardware test cannot be mistaken
# for one that ran them.
check-gpu: gpu-status lint-gpu test-gpu

# For CI, where a cache hit from a previous commit is exactly what you do not
# want. `-B` forces every recipe to run regardless of its stamp.
ci:
	@$(MAKE) -B check

# --- cached tasks -----------------------------------------------------------
test: test-cpu test-gpu

# Each suite is built once, with warnings as errors, and the program is
# run. The build is the suite's lint, so `lint-cpu` leaves the suites to
# this: building a suite to check it and again to run it compiled the
# whole library twice for every suite, and was most of CI's hour.
BIN_DIR := $(CACHE_DIR)/bin
test-cpu: $(TEST_CPU_STAMP)
$(TEST_CPU_STAMP):
	@mkdir -p $(BIN_DIR)
	@printf '%s\n' $(CPU_TESTS) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'bin=$(BIN_DIR)/$$(basename "$$1" .mojo); \
	             out=$$($(MOJO) build $(MOJOFLAGS) --Werror -o "$$bin" "$$1" \
	                    2>&1 && "$$bin" 2>&1); rc=$$?; rm -f "$$bin"; \
	             printf "%s\n" "$$out" | sed "/Crashpad/d"; exit $$rc' _ {} \
	  || { echo "Some CPU suites FAILED."; exit 1; }
	@echo "All $(words $(CPU_TESTS)) CPU suites passed."
	@$(call stamp,test-cpu)

# Deliberately uncached: the one thing that decides whether this suite tests
# anything -- an accelerator being present -- is not in the cache key and
# cannot easily be put there. Running it every time costs a few seconds and
# removes a way to be told "passed" by a stamp written on different hardware.
#
# Budgeted, because the failure mode a GPU backend actually has is a hang: a
# driver waiting on a device event that never fires shows no CPU, no output
# and no error, and looks exactly like a slow kernel compile. One did, for
# ten minutes, before docs/max-gpu-teardown-issue/ was understood. The
# budget is generous -- the suite takes seconds -- so exceeding it means
# something is stuck rather than slow. Override with `make test-gpu
# GPU_BUDGET=600` on a machine whose first kernel compile is genuinely slow.
GPU_BUDGET := 300
test-gpu:
	@printf '%s\n' $(GPU_TESTS) \
	  | perl -e 'alarm shift; exec @ARGV' $(GPU_BUDGET) \
	      xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) run $(MOJOFLAGS) "$$1" 2>&1); rc=$$?; \
	             printf "%s\n" "$$out" | sed "/Crashpad/d"; exit $$rc' _ {} \
	  || { rc=$$?; \
	       if [ $$rc -eq 142 ]; then \
	         echo "GPU suite exceeded its $(GPU_BUDGET)s budget. The suite" \
	              "takes seconds when it runs at all, so this is a hang, not a" \
	              "slow machine: see docs/max-gpu-teardown-issue/ for the one" \
	              "already found, and run the suite by hand under 'timeout'."; \
	       else \
	         echo "Some GPU suites FAILED."; \
	       fi; exit 1; }
	@echo "All $(words $(GPU_TESTS)) GPU suites passed."

# The GPU suites that open no device. Cached, unlike test-gpu: nothing they
# do depends on the hardware, so a stamp from another machine is as good.
test-gpu-host: $(TEST_GPU_HOST_STAMP)
$(TEST_GPU_HOST_STAMP):
	@printf '%s\n' $(GPU_HOST_TESTS) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) run $(MOJOFLAGS) "$$1" 2>&1); rc=$$?; \
	             printf "%s\n" "$$out" | sed "/Crashpad/d"; exit $$rc' _ {} \
	  || { echo "Some GPU host suites FAILED."; exit 1; }
	@echo "All $(words $(GPU_HOST_TESTS)) GPU host suites passed."
	@$(call stamp,test-gpu-host)

gpu-status:
	@$(call run,$(MOJO) run $(MOJOFLAGS) tools/gpu_status.mojo); \
	[ $$rc -eq 0 ] || exit 1

lint: lint-cpu lint-gpu

# The suites are linted where `test-cpu` builds them.
lint-cpu: $(LINT_CPU_STAMP)
$(LINT_CPU_STAMP):
	@printf '%s\n' $(filter-out $(CPU_TESTS),$(CPU_ENTRY_POINTS)) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) build $(MOJOFLAGS) --Werror -o /dev/null "$$1" \
	               2>&1); rc=$$?; printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@printf '%s\n' $(CPU_DOC_SOURCES) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) doc $(MOJOFLAGS) --Werror -o /dev/null "$$1" \
	               2>&1); rc=$$?; printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@echo "No warnings (CPU)."
	@$(call stamp,lint-cpu)

lint-gpu: $(LINT_GPU_STAMP)
$(LINT_GPU_STAMP):
	@printf '%s\n' $(GPU_ENTRY_POINTS) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) build $(MOJOFLAGS) --Werror -o /dev/null "$$1" \
	               2>&1); rc=$$?; printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@printf '%s\n' $(GPU_LIB_SOURCES) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) doc $(MOJOFLAGS) --Werror -o /dev/null "$$1" \
	               2>&1); rc=$$?; printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@echo "No warnings (GPU)."
	@$(call stamp,lint-gpu)

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
# compare what ran against what could have run. Probe records go to stderr,
# keeping stdout untouched.
#
# **The whole run happens inside $(COV_DIR).** Mojo 1.1 resolves a module
# beside the file being compiled before it looks at any `-I` path, so a suite
# run from the repo root imports the *real* library however the search path
# is ordered: `-I $(COV_DIR) -I .` measured nothing at all and reported a
# clean zero. Copying the suites and the probe runtime into the build tree
# makes the instrumented copies the ones beside them, which is the only
# arrangement the new rule can resolve the way this needs.
coverage: $(COV_STAMP)
$(COV_STAMP):
	@rm -rf $(COV_DIR)
ifeq ($(strip $(COVERED)),)
	@echo "No measured module is affected; coverage not measured."
else
	@for f in $(COVERED); do mkdir -p "$(COV_DIR)/$$(dirname $$f)"; done
	@$(call run,$(MOJO) run $(MOJOFLAGS) coverage/build_cli.mojo \
	  $(COV_DIR) $(COVERED)); \
	[ $$rc -eq 0 ] || exit 1
	@# Unmeasured modules are copied through unchanged. Without them the
	@# build tree is an incomplete package and imports fail to resolve,
	@# since the first -I wins and never falls back to the real tree.
	@for f in $(COVERAGE_PASSTHROUGH); do \
	  mkdir -p "$(COV_DIR)/$$(dirname $$f)"; cp "$$f" "$(COV_DIR)/$$f"; \
	done
	@# The coverage tool itself, and the suites that drive it, both copied
	@# in so that every import a suite makes resolves beside it. The whole
	@# package rather than the probe runtime alone: the tool's own suites
	@# test the instrumenter, the scanner and the report. See the note
	@# above. These copies are never instrumented, so measuring the tool
	@# with itself is still not attempted.
	@mkdir -p $(COV_DIR)/coverage
	@cp coverage/*.mojo $(COV_DIR)/coverage/
	@mkdir -p $(COV_DIR)/tests
	@[ -z "$(strip $(COVERAGE_TESTS))" ] || cp $(COVERAGE_TESTS) $(COV_DIR)/tests/
	@mkdir -p $(COV_DIR)/hits
	@# One file per suite rather than a shared append: probe records must not
	@# interleave mid-line, and MC-DC needs each decision's records in order.
	@printf '%s\n' $(COVERAGE_TESTS) \
	  | perl -e 'alarm shift; exec @ARGV' $(COV_BUDGET) \
	      xargs -P $(JOBS) -I {} \
	      sh -c 'name=$$(basename "$$1" .mojo); \
	             $(MOJO) run -I $(COV_DIR) "$(COV_DIR)/tests/$$name.mojo" \
	               2> $(COV_DIR)/hits/$$name.txt > $(COV_DIR)/hits/$$name.out \
	             || { echo "$$name failed under instrumentation:"; \
	                  tail -n 30 $(COV_DIR)/hits/$$name.out; \
	                  grep -v "^COV" $(COV_DIR)/hits/$$name.txt | tail -n 30; \
	                  exit 1; }' _ {} \
	  || { rc=$$?; \
	       if [ $$rc -eq 142 ]; then \
	         echo "Coverage exceeded its $(COV_BUDGET)s budget (one second per" \
	              "suite). Either something is being instrumented that should" \
	              "not be, or this machine is slower than the budget assumes:" \
	              "re-run with 'make coverage COV_BUDGET=300' to tell them" \
	              "apart."; \
	       else \
	         echo "A suite failed under instrumentation (exit $$rc); coverage" \
	              "not measured. Run its copy under $(COV_DIR)/tests to see" \
	              "why."; \
	       fi; exit 1; }
	@# Mesh suites write gigabytes of repeated probe records. The report
	@# only needs each line id once and each distinct MC-DC vector once.
	@# The raw captures stay in separate files. One concatenated read of
	@# them fails on macOS once they pass two gigabytes. The report reads
	@# the compact stream instead.
	@python3 coverage/compact_hits.py $(COV_DIR)/hits > $(COV_DIR)/hits.txt
	@$(call run,$(MOJO) run $(MOJOFLAGS) coverage/report_cli.mojo \
	  $(COV_DIR)/manifest.txt $(COV_DIR)/hits.txt); \
	[ $$rc -eq 0 ] || exit 1
endif
	@$(call stamp,coverage)

# The units system's value is what it *rejects*, and a rejection cannot be
# tested from inside a test suite: a file exercising one would not build. So
# each case lives in its own file that must fail to compile, and this target
# fails if any of them ever starts compiling.
compile-fail: $(NEG_STAMP)
$(NEG_STAMP):
	@fail=0; \
	for f in $(COMPILE_FAIL_RUN); do \
	  if $(MOJO) build $(MOJOFLAGS) -o /dev/null "$$f" > /dev/null 2>&1; then \
	    echo "compiled but should not have: $$f"; fail=1; \
	  fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	echo "All $(words $(COMPILE_FAIL_RUN)) unit errors rejected."
	@$(call stamp,compile-fail)

# --- documentation ----------------------------------------------------------
# The wiki pages live in docs/wiki/ so that they are versioned, reviewed and
# checked with the code. Uncached: the check takes a second, and the docs are
# not part of the source hash the cache is keyed on.
DOCS := README.md CONTRIBUTING.md $(wildcard docs/wiki/*.md)
WIKI_REMOTE := https://github.com/SethKitchen/ThreeMojo.wiki.git

docs-check:
	@$(call run,$(MOJO) run $(MOJOFLAGS) tools/doc_lint.mojo $(DOCS)); \
	[ $$rc -eq 0 ] || exit 1

# Replaces every page in the wiki with the copies in docs/wiki/. GitHub
# creates the wiki repository when its first page is saved in the browser, so
# that one step is manual; after it, this target and the CI job keep the
# wiki in step with main.
wiki-publish:
	@rm -rf $(CACHE_DIR)/wiki; \
	git clone -q $(WIKI_REMOTE) $(CACHE_DIR)/wiki || { \
	  echo "The wiki repository does not exist yet. Create the Home page in the" \
	       "browser once, then run this again."; exit 1; }; \
	rm -f $(CACHE_DIR)/wiki/*.md; \
	cp docs/wiki/*.md $(CACHE_DIR)/wiki/; \
	mkdir -p $(CACHE_DIR)/wiki/out; \
	cp -f $(OUT_DIR)/*.png $(CACHE_DIR)/wiki/out/ 2>/dev/null || true; \
	name=$$(git config user.name || echo "ThreeMojo"); \
	email=$$(git config user.email || echo "threemojo@users.noreply.github.com"); \
	from=$$(git rev-parse --short HEAD 2>/dev/null || echo "docs/wiki"); \
	cd $(CACHE_DIR)/wiki && git add -A && \
	if git diff --cached --quiet; then echo "Wiki already up to date."; \
	else git -c user.name="$$name" -c user.email="$$email" \
	  commit -q -m "Publish docs/wiki from $$from" \
	  && git push -q && echo "Wiki published."; fi

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

# Standard library only, unlike `bench`: a whole scene through the CPU
# renderer, with the transform stage and the rasterization stage timed apart
# and the frame repeated with one worker per core.
bench-scene:
	@$(call run,$(MOJO) run $(MOJOFLAGS) bench/scene_bench.mojo); \
	[ $$rc -eq 0 ] || exit 1

# Uncached: the point is a fresh measurement. Writes bench/results.json and
# fills the tables on docs/wiki/Benchmarks.md.
bench-examples:
	@python3 tools/bench_examples.py

example: $(OUT_DIR)/triangle.png

# Interactive, so it needs a terminal and is not part of `animation`. Not run
# through `run`: that captures the output, and this output is the window.
viewer:
	@$(MOJO) run $(MOJOFLAGS) examples/viewer.mojo

# All 323 Draco exports against three.js. The suite checks a subset.
draco-export-check:
	@$(MOJO) run $(MOJOFLAGS) tools/draco_export_check.mojo

animation: $(OUT_DIR)/spin.png $(OUT_DIR)/cube.png $(OUT_DIR)/cubes.png \
           $(OUT_DIR)/uv.png $(OUT_DIR)/textured.png $(OUT_DIR)/glass.png \
           $(OUT_DIR)/floor.png $(OUT_DIR)/photo.png \
           $(OUT_DIR)/lamps.png $(OUT_DIR)/first_scene.png \
           $(OUT_DIR)/lit_scene.png $(OUT_DIR)/rotations.png \
           $(OUT_DIR)/cameras.png $(OUT_DIR)/geometry.png \
           $(OUT_DIR)/instances.png $(OUT_DIR)/raycast.png \
           $(OUT_DIR)/curves.png $(OUT_DIR)/keyframes.png \
           $(OUT_DIR)/skinning.png $(OUT_DIR)/phong.png \
           $(OUT_DIR)/fog.png $(OUT_DIR)/culling.png \
           $(OUT_DIR)/clipping.png $(OUT_DIR)/gpu_backend.png \
           $(OUT_DIR)/exposure.png $(OUT_DIR)/model.png \
           $(OUT_DIR)/math.png $(OUT_DIR)/units.png \
           $(OUT_DIR)/chain.png $(OUT_DIR)/additive.png \
           $(OUT_DIR)/normals.png $(OUT_DIR)/fragments.png \
           $(OUT_DIR)/coverage.png $(OUT_DIR)/lines.png \
           $(OUT_DIR)/helpers.png $(OUT_DIR)/split.png \
           $(OUT_DIR)/mirror.png $(OUT_DIR)/physical.png \
           $(OUT_DIR)/sprites.png $(OUT_DIR)/stereo.png \
           $(OUT_DIR)/television.png $(OUT_DIR)/shadows.png \
           $(OUT_DIR)/wide.png $(OUT_DIR)/postprocessing.png \
           $(OUT_DIR)/controls.png $(OUT_DIR)/scenejson.png \
           $(OUT_DIR)/exporters.png $(OUT_DIR)/transmission.png \
           $(OUT_DIR)/distance.png $(OUT_DIR)/unfogged.png \
           $(OUT_DIR)/targets.png $(OUT_DIR)/layers.png \
           $(OUT_DIR)/nodes.png $(OUT_DIR)/ktx2.png \
           $(OUT_DIR)/coats.png $(OUT_DIR)/environment.png \
           $(OUT_DIR)/sky.png $(OUT_DIR)/faces.png \
           $(OUT_DIR)/teapot.png $(OUT_DIR)/blobs.png \
           $(OUT_DIR)/femur.png $(OUT_DIR)/tibia.png \
           $(OUT_DIR)/fibula.png $(OUT_DIR)/patella.png \
           $(OUT_DIR)/knee.png $(OUT_DIR)/muscles.png \
           $(OUT_DIR)/leg.png $(OUT_DIR)/legs.png \
           $(OUT_DIR)/vessels.png $(OUT_DIR)/lymph.png \
           $(OUT_DIR)/nerves.png $(OUT_DIR)/integument.png \
           $(OUT_DIR)/water.png

# A chrome ball under a sky, reflecting a cube camera's view of two boxes.
$(OUT_DIR)/mirror.png: $(LIB_SOURCES) examples/mirror.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/mirror.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A split screen: two viewports and two scissors drawing into one target.
$(OUT_DIR)/split.png: $(LIB_SOURCES) examples/split.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/split.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A grid, the axes, a box around a cube and a second camera's frustum.
$(OUT_DIR)/helpers.png: $(LIB_SOURCES) examples/outlines.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/outlines.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/lines.png: $(LIB_SOURCES) examples/lines.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lines.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/cube.png: $(LIB_SOURCES) examples/cube.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/cube.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/cubes.png: $(LIB_SOURCES) examples/cubes.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/cubes.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Translucent panes over a solid cube: blending, sorting and linear light.
$(OUT_DIR)/glass.png: $(LIB_SOURCES) examples/glass.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/glass.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Three colored lamps on a coarse sphere: many lights, and per-fragment shading.
$(OUT_DIR)/lamps.png: $(LIB_SOURCES) examples/lamps.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lamps.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A cube wearing a PNG somebody else's encoder wrote: the decoder end to end.
$(OUT_DIR)/photo.png: $(LIB_SOURCES) examples/photo.mojo assets/brick.png
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/photo.mojo assets/brick.png $@); \
	[ $$rc -eq 0 ] || exit 1

# A receding floor, half mipmapped and half not: minification and aliasing.
$(OUT_DIR)/floor.png: $(LIB_SOURCES) examples/floor.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/floor.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A checkerboard cube: scene graph, culling, depth, uv and sampling together.
$(OUT_DIR)/textured.png: $(LIB_SOURCES) examples/textured.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/textured.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Two frames, perspective-correct and affine, of the same prepared triangles.
$(OUT_DIR)/uv.png: $(LIB_SOURCES) examples/uv.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/uv.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/spin.png: $(LIB_SOURCES) examples/spin.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/spin.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/triangle.png: $(LIB_SOURCES) examples/triangle.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/triangle.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/first_scene.png: $(LIB_SOURCES) examples/first_scene.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/first_scene.mojo); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/lit_scene.png: $(LIB_SOURCES) examples/lit_scene.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lit_scene.mojo); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/rotations.png: $(LIB_SOURCES) examples/rotations.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/rotations.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/cameras.png: $(LIB_SOURCES) examples/ortho.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/ortho.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/geometry.png: $(LIB_SOURCES) examples/geometry.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/geometry.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/instances.png: $(LIB_SOURCES) examples/instances.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/instances.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/raycast.png: $(LIB_SOURCES) examples/raycast.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/raycast.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/curves.png: $(LIB_SOURCES) examples/curves.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/curves.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/keyframes.png: $(LIB_SOURCES) examples/keyframes.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/keyframes.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/skinning.png: $(LIB_SOURCES) examples/skinning.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/skinning.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Ten spheres from chalk to mirror and from dielectric to metal, under a sky.
$(OUT_DIR)/physical.png: $(LIB_SOURCES) examples/physical.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/physical.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/phong.png: $(LIB_SOURCES) examples/phong.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/phong.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/fog.png: $(LIB_SOURCES) examples/fog.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/fog.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/culling.png: $(LIB_SOURCES) examples/culling.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/culling.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/clipping.png: $(LIB_SOURCES) examples/clipping.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/clipping.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/gpu_backend.png: $(LIB_SOURCES) examples/gpu_backend.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/gpu_backend.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/exposure.png: $(LIB_SOURCES) examples/exposure.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/exposure.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/model.png: $(LIB_SOURCES) examples/model.mojo assets/cube.obj
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/model.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/math.png: $(LIB_SOURCES) examples/orbit.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/orbit.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/units.png: $(LIB_SOURCES) examples/clock.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/clock.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/chain.png: $(LIB_SOURCES) examples/chain.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/chain.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/additive.png: $(LIB_SOURCES) examples/additive.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/additive.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/normals.png: $(LIB_SOURCES) examples/normals.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/normals.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/fragments.png: $(LIB_SOURCES) examples/fragments.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/fragments.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/coverage.png: $(LIB_SOURCES) examples/edges.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/edges.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/sprites.png: $(LIB_SOURCES) examples/sprites.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/sprites.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/stereo.png: $(LIB_SOURCES) examples/stereo.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/stereo.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/television.png: $(LIB_SOURCES) examples/television.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/television.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A cube's shadow swings across a floor as a directional lamp orbits.
$(OUT_DIR)/shadows.png: $(LIB_SOURCES) examples/shadows.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/shadows.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A ribbon eight pixels wide, drawn as triangles, turns with a box.
$(OUT_DIR)/wide.png: $(LIB_SOURCES) examples/wide.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/wide.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Bloom and a vignette over a dark knot and two emissive spheres.
$(OUT_DIR)/postprocessing.png: $(LIB_SOURCES) examples/bloom.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/bloom.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Translate handles on a cube, redrawn as the camera orbits.
$(OUT_DIR)/controls.png: $(LIB_SOURCES) examples/gizmo.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/gizmo.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A scene written as three.js JSON and read back before it is drawn.
$(OUT_DIR)/scenejson.png: $(LIB_SOURCES) examples/json_scene.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/json_scene.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A knot written to glTF and read back before it is drawn.
$(OUT_DIR)/exporters.png: $(LIB_SOURCES) examples/reloaded.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/reloaded.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A glass sphere refracts three colored boxes.
$(OUT_DIR)/transmission.png: $(LIB_SOURCES) examples/gem.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/gem.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Distance from a point, packed into the color of a sphere.
$(OUT_DIR)/distance.png: $(LIB_SOURCES) examples/distance.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/distance.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Three cubes in fog. The middle material has fog turned off.
$(OUT_DIR)/unfogged.png: $(LIB_SOURCES) examples/unfogged.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/unfogged.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A float color attachment above a normal attachment.
$(OUT_DIR)/targets.png: $(LIB_SOURCES) examples/targets.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/targets.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Sheen, iridescence and anisotropy on three spheres.
$(OUT_DIR)/layers.png: $(LIB_SOURCES) examples/layers.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/layers.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A node graph tints a sphere and pushes its vertices.
$(OUT_DIR)/nodes.png: $(LIB_SOURCES) examples/graph.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/graph.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# UASTC and ETC1S images decoded from KTX2 files.
$(OUT_DIR)/ktx2.png: $(LIB_SOURCES) examples/basis.mojo assets/ktx2/uastc_rgb_zstd_mips.ktx2 \
	assets/ktx2/etc1s_rgb.ktx2 assets/ktx2/uastc_gradient.ktx2
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/basis.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Clearcoat bands and a specular color map on two spheres.
$(OUT_DIR)/coats.png: $(LIB_SOURCES) examples/coats.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/coats.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# A metal ball whose sky was written as scene JSON and read back.
$(OUT_DIR)/environment.png: $(LIB_SOURCES) examples/skyjson.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/skyjson.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Preetham's daylight sky, with the sun crossing above a sphere.
$(OUT_DIR)/sky.png: $(LIB_SOURCES) examples/daylight.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/daylight.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# One box, a different material on each face.
$(OUT_DIR)/faces.png: $(LIB_SOURCES) examples/faces.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/faces.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# The Utah teapot, from the geometry addons.
$(OUT_DIR)/teapot.png: $(LIB_SOURCES) examples/utah.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/utah.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Two metaballs joined by marching cubes.
$(OUT_DIR)/blobs.png: $(LIB_SOURCES) examples/blobs.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/blobs.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/femur.png: $(LIB_SOURCES) examples/femur.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/femur.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/tibia.png: $(LIB_SOURCES) examples/tibia.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/tibia.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/fibula.png: $(LIB_SOURCES) examples/fibula.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/fibula.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/patella.png: $(LIB_SOURCES) examples/patella.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/patella.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/knee.png: $(LIB_SOURCES) examples/knee.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/knee.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/muscles.png: $(LIB_SOURCES) examples/muscles.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/muscles.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/leg.png: $(LIB_SOURCES) examples/leg.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/leg.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/legs.png: $(LIB_SOURCES) examples/legs.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/legs.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/vessels.png: $(LIB_SOURCES) examples/vessels.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/vessels.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/lymph.png: $(LIB_SOURCES) examples/lymph.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lymph.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/nerves.png: $(LIB_SOURCES) examples/nerves.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/nerves.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/integument.png: $(LIB_SOURCES) examples/integument.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/integument.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

$(OUT_DIR)/water.png: $(LIB_SOURCES) examples/water.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/water.mojo $@); \
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
