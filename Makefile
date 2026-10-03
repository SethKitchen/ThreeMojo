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
                  postprocessing controls window exporters environments generators extensions \
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
GPU_LIB_SOURCES  := render/gpu.mojo render/gpu_vxgi.mojo
# The suites that import render/gpu.mojo but open no device: they flatten
# vertices, state tables, textures and lights on the host and read the
# layout back. They need MAX installed and no GPU, so CI runs them with
# `make test-gpu-host` on a runner that has none. They were once part of
# tests/test_gpu.mojo, and went stale there for a week: that suite fails
# every device test on a machine without a GPU, so seven failing layout
# assertions among two hundred device failures were not seen.
GPU_HOST_TESTS   := tests/test_gpu_layout.mojo \
                    tests/test_gpu_volume_packing.mojo
GPU_TESTS        := tests/test_gpu.mojo $(GPU_HOST_TESTS)
GPU_ENTRY_POINTS := $(GPU_TESTS) bench/raster_bench.mojo

CPU_LIB_SOURCES  := $(filter-out $(GPU_LIB_SOURCES),$(LIB_SOURCES))
CPU_TESTS        := $(filter-out $(GPU_TESTS),$(TESTS))
CPU_ENTRY_POINTS := $(filter-out $(GPU_ENTRY_POINTS),$(ENTRY_POINTS))
CPU_DOC_SOURCES  := $(CPU_LIB_SOURCES) $(TOOL_LIBS)

# Sources whose coverage is measured. The coverage tool is deliberately absent
# so a bug in it cannot flatter its own numbers.
#
# COVERAGE_EXCLUDE drops a file from measurement entirely: the GPU library
# sources. render/gpu.mojo cannot be instrumented at all under this design: a
# probe writes a record to stderr, and a GPU kernel has no stderr. It is
# covered instead by tests/test_gpu.mojo asserting its output matches the CPU
# rasterizer pixel for pixel, and by tests/test_fillrule.mojo pinning the
# coverage math the two now share. render/gpu_vxgi.mojo is the same: its
# kernels call lights/vxgi_volume.mojo, which the host suites cover.
#
# Five modules used to sit here as well -- render/png.mojo among them -- because
# instrumenting them made the *compile* take minutes. The cause turned out to be
# one construct the instrumenter emitted, a Bool loop flag assigned a constant
# and read after nested loops, and not the modules at all. All five are measured
# again. See coverage/instrument.mojo and docs/mojo-compiler-issue/.
COVERAGE_EXCLUDE := $(GPU_LIB_SOURCES)
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
# reach a measured module runs. A changed test or helper also measures the
# library imported by its affected tests, so lost coverage is checked before
# merge rather than deferred to the full run on main. Removed test imports
# conservatively select the full check, including their former dependencies.
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

# The time limit for one test, in seconds. tools/run_suite.py fails a test
# that takes longer, and stops a suite that hangs. A test over the limit
# means the code under test is slow: make the library faster, not the test
# smaller. It is a performance gate, so do not raise it to get a test green.
TEST_TIMEOUT := 5

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

# CI splits the suites over runners that work at once: `SHARD=i/n` keeps
# group i of n, balanced by the source each suite imports, since a suite's
# CPU time is mostly compilation. See tools/shard.py. Only the suites split:
# formatting, lint, the docs and the compile-fail cases run whole, on one
# runner. `coverage-report` reads the captures of every group, so it checks
# that each suite of the whole list left one.
SHARD ?=
TEST_SUITES := $(CPU_TESTS)
ifneq ($(strip $(SHARD)),)
TEST_SUITES := $(shell python3 tools/shard.py $(SHARD) $(CPU_TESTS) \
                 || echo SHARD_ERROR)
ifneq ($(filter SHARD_ERROR,$(TEST_SUITES)),)
$(error tools/shard.py could not split the suites for SHARD=$(SHARD): it takes I/N with 1 <= I <= N and readable suites)
endif
endif
# Instrumented runtime can outweigh compilation by minutes. Keep CPU
# placement unchanged; coverage uses measured compile-and-run costs and
# starts the longest captures first. Every affected suite is still present.
COVERAGE_SUITES := $(COVERAGE_TESTS)
ifneq ($(strip $(SHARD)),)
ifneq ($(filter coverage coverage-capture,$(MAKECMDGOALS)),)
COVERAGE_SUITES := $(shell python3 tools/coverage_shard.py $(SHARD) $(COVERAGE_TESTS) \
                       || echo SHARD_ERROR)
ifneq ($(filter SHARD_ERROR,$(COVERAGE_SUITES)),)
$(error tools/coverage_shard.py could not split coverage suites for SHARD=$(SHARD))
endif
endif
endif

# At least a minute: a run of a few affected suites still pays a compile
# that takes longer than a second.
COV_BUDGET := $(shell n=$(words $(COVERAGE_SUITES)); \
                [ $$n -lt 60 ] && n=60; echo $$n)

CACHE_DIR := .cache
# Shell quoting also protects flags that contain spaces or shell punctuation.
quote = '$(subst ','"'"',$(1))'
TOOLCHAIN := $(shell $(MOJO) --version 2>/dev/null || echo "no-mojo")
HASH := $(shell python3 tools/cache_key.py \
          --setting=$(call quote,$(MOJO)) \
          --setting=$(call quote,$(MOJOFLAGS)) \
          --setting=$(call quote,$(TOOLCHAIN)) \
          --setting=$(call quote,$(AFFECTED) $(AFFECTED_CHANGE)) \
          --setting=$(call quote,cpu-tests:$(CPU_TESTS)) \
          --setting=$(call quote,shard:$(SHARD)) \
          --setting=$(call quote,test-timeout:$(TEST_TIMEOUT)) \
          --setting=$(call quote,cpu-entries:$(CPU_ENTRY_POINTS)) \
          --setting=$(call quote,cpu-docs:$(CPU_DOC_SOURCES)) \
          --setting=$(call quote,negative:$(COMPILE_FAIL_RUN)) \
          --setting=$(call quote,format:$(FORMATTED)) \
          --setting=$(call quote,covered:$(COVERED)) \
          --setting=$(call quote,gpu:$(GPU_TESTS) $(GPU_HOST_TESTS) $(GPU_ENTRY_POINTS) $(GPU_LIB_SOURCES)))
ifeq ($(strip $(HASH)),)
$(error Cannot read build inputs for the cache key)
endif

# What the cache key cannot include is whether a GPU is plugged in, which is
# why `test-gpu` is not cached at all. Hardware-dependent tests skip when there
# is no accelerator and the suite still exits successfully, so a cached run
# without one would keep reporting success on a machine that has since grown a
# GPU. Compilation is deterministic given the sources and the compiler, so
# `compile-gpu` and `lint-gpu` stay cached; device execution does not.
# test-gpu has no stamp on purpose -- see the target.
TEST_CPU_STAMP := $(CACHE_DIR)/test-cpu-$(HASH)
TEST_GPU_HOST_STAMP := $(CACHE_DIR)/test-gpu-host-$(HASH)
LINT_CPU_STAMP := $(CACHE_DIR)/lint-cpu-$(HASH)
COMPILE_GPU_STAMP := $(CACHE_DIR)/compile-gpu-$(HASH)
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

.PHONY: test-gpu-device help check check-cpu check-gpu ci test test-cpu test-gpu test-gpu-host \
        docs-check wiki-publish test-tools test-coverage-tool test-portability \
        coverage-instrument coverage-capture coverage-report \
        lint lint-cpu lint-gpu compile-gpu gpu-status docstrings fmt fmt-check coverage \
        compile-fail example animation viewer bench bench-scene bench-examples \
        clean clean-images optimize-images draco-export-check

help:
	@echo "ThreeMojo tasks ($(TOOLCHAIN), inputs hash to $(HASH))"
	@echo
	@echo "  make check      everything                 <- before committing"
	@echo "  make check-cpu  the standard-library-only half ($(words $(CPU_TESTS)) suites)"
	@echo "  make check-gpu  the optional MAX backend ($(words $(GPU_TESTS)) suites)"
	@echo "  make test-gpu-host  the MAX backend's layout suites, no GPU needed"
	@echo "  make compile-gpu  build GPU entry points without running them"
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
	@echo "  make optimize-images  losslessly compress the tracked PNG gallery"
	@echo "  make viewer     orbit a scene in this terminal with the mouse"
	@echo "  make bench      CPU vs GPU rasterization across sizes"
	@echo "  make bench-scene  a textured sphere through the CPU renderer, per stage"
	@echo "  make bench-examples  cataloged examples vs three.js and Mojo 1.0"
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
check-cpu: fmt-check lint-cpu test-cpu compile-fail docs-check test-tools test-coverage-tool test-portability

# The complete GPU check needs MAX and an accelerator. The status line
# comes first so a suite that skipped every hardware test cannot be mistaken
# for one that ran them. Use compile-gpu for a build-only check without a GPU.
check-gpu: gpu-status test-gpu-host
	@.venv/bin/python tools/gpu_status.py --available; rc=$$?; \
	  if [ $$rc -eq 0 ]; then $(MAKE) lint-gpu test-gpu-device; \
	  elif [ $$rc -ne 1 ]; then exit $$rc; fi

# For CI, where a cache hit from a previous commit is exactly what you do not
# want. `-B` forces every recipe to run regardless of its stamp.
ci:
	@$(MAKE) -B check

# --- cached tasks -----------------------------------------------------------
test: test-cpu test-gpu

# Each suite also has its own stamp, in $(SUITE_STAMPS), named by a key
# over the files the suite imports and the assets it quotes: see
# tools/suite_key.py. A change to one module builds and runs only the
# suites that reach it, and `make -B` drops every stamp. CI starts with no
# cache, so this is for local runs; CI narrows the suites with AFFECTED.
SUITE_STAMPS := $(CACHE_DIR)/suites
# `make -B` puts a B in the first word of MAKEFLAGS.
FORCED := $(findstring B,$(firstword -$(MAKEFLAGS)))

# Each suite is built once, with warnings as errors, and the program is
# run. The build is the suite's lint, so `lint-cpu` leaves the suites to
# this: building a suite to check it and again to run it compiled the
# whole library twice for every suite, and was most of CI's hour.
BIN_DIR := $(CACHE_DIR)/bin
test-cpu: $(TEST_CPU_STAMP)
$(TEST_CPU_STAMP):
	@mkdir -p $(BIN_DIR) $(SUITE_STAMPS)
	@$(if $(FORCED),rm -f $(SUITE_STAMPS)/*)
	@python3 tools/suite_key.py --stamps $(SUITE_STAMPS) \
	    --setting=$(call quote,$(MOJO)) \
	    --setting=$(call quote,$(MOJOFLAGS)) \
	    --setting=$(call quote,$(TOOLCHAIN)) \
	    --setting=$(call quote,test-timeout:$(TEST_TIMEOUT)) \
	    $(TEST_SUITES) > $(CACHE_DIR)/suites-to-run || exit 1
	@xargs -n 2 -P $(JOBS) \
	      sh -c '[ "$$#" -eq 0 ] && exit 0; \
	             name=$$(basename "$$1" .mojo); bin=$(BIN_DIR)/$$name; \
	             out=$$($(MOJO) build $(MOJOFLAGS) --Werror -o "$$bin" "$$1" \
	                    2>&1 && python3 tools/run_suite.py \
	                      --seconds $(TEST_TIMEOUT) --suite "$$1" -- "$$bin"); \
	             rc=$$?; rm -f "$$bin"; \
	             printf "%s\n" "$$out" | sed "/Crashpad/d"; \
	             if [ $$rc -eq 0 ]; then \
	               rm -f $(SUITE_STAMPS)/"$$name"-*; \
	               touch $(SUITE_STAMPS)/"$$name-$$2"; \
	             fi; exit $$rc' _ < $(CACHE_DIR)/suites-to-run \
	  || { echo "Some CPU suites FAILED."; exit 1; }
	@echo "All $(words $(TEST_SUITES)) CPU suites passed."
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
test-gpu: gpu-status test-gpu-host
	@.venv/bin/python tools/gpu_status.py --available; rc=$$?; \
	  if [ $$rc -eq 0 ]; then $(MAKE) test-gpu-device; \
	  elif [ $$rc -ne 1 ]; then exit $$rc; fi

test-gpu-device:
	@printf '%s\n' $(filter-out $(GPU_HOST_TESTS),$(GPU_TESTS)) \
	  | perl -e 'alarm shift; exec @ARGV' $(GPU_BUDGET) \
	      xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$(python3 tools/run_suite.py --results-only \
	               --suite "$$1" -- $(MOJO) run $(MOJOFLAGS) "$$1" 2>&1); rc=$$?; \
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
	@echo "GPU device suites passed."

# The GPU suites that open no device. Cached, unlike test-gpu: nothing they
# do depends on the hardware, so a stamp from another machine is as good.
test-gpu-host: $(TEST_GPU_HOST_STAMP)
$(TEST_GPU_HOST_STAMP):
	@printf '%s\n' $(GPU_HOST_TESTS) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$(python3 tools/run_suite.py --results-only \
	               --suite "$$1" -- $(MOJO) run $(MOJOFLAGS) "$$1" 2>&1); rc=$$?; \
	             printf "%s\n" "$$out" | sed "/Crashpad/d"; exit $$rc' _ {} \
	  || { echo "Some GPU host suites FAILED."; exit 1; }
	@echo "All $(words $(GPU_HOST_TESTS)) GPU host suites passed."
	@$(call stamp,test-gpu-host)

gpu-status:
	@.venv/bin/python tools/gpu_status.py

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

# Compile all maintained GPU entry points without opening a device. A
# machine without a GPU must select an architecture, for example:
# make compile-gpu MOJOFLAGS="-I . --target-accelerator=sm_80"
# Keep that flag out of mojo doc: the pinned toolchain does not accept it.
compile-gpu: $(COMPILE_GPU_STAMP)
$(COMPILE_GPU_STAMP):
	@printf '%s\n' $(GPU_ENTRY_POINTS) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) build $(MOJOFLAGS) --Werror -o /dev/null "$$1" \
	               2>&1); rc=$$?; printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@echo "GPU entry points compiled (not run)."
	@$(call stamp,compile-gpu)

lint-gpu: $(LINT_GPU_STAMP)
$(LINT_GPU_STAMP): $(COMPILE_GPU_STAMP)
	@printf '%s\n' $(GPU_LIB_SOURCES) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$($(MOJO) doc $(MOJOFLAGS) --Werror -o /dev/null "$$1" \
	               2>&1); rc=$$?; printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@echo "No warnings (GPU)."
	@$(call stamp,lint-gpu)

# mojo format has no --check flag, so format scratch copies and diff them.
# One invocation avoids paying compiler startup once for every source file.
fmt-check: $(FMT_STAMP)
$(FMT_STAMP):
	@fail=0; tmp=$$(mktemp -d) || exit 1; \
	trap 'rm -rf "$$tmp"' 0; \
	set --; \
	for f in $(FORMATTED); do \
	  mkdir -p "$$tmp/$$(dirname "$$f")" || exit 1; \
	  cp "$$f" "$$tmp/$$f" || exit 1; \
	  set -- "$$@" "$$tmp/$$f"; \
	done; \
	if [ $$# -gt 0 ]; then \
	  $(call run,$(MOJO) format -q "$$@"); \
	  [ $$rc -eq 0 ] || exit $$rc; \
	fi; \
	for f in $(FORMATTED); do \
	  if ! diff -q "$$f" "$$tmp/$$f" > /dev/null; then \
	    echo "needs formatting: $$f"; fail=1; \
	  fi; \
	done; \
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
	@$(MAKE) --no-print-directory coverage-instrument
	@$(MAKE) --no-print-directory coverage-capture
	@$(MAKE) --no-print-directory coverage-report
	@$(call stamp,coverage)

# The three steps of `coverage`, which CI runs apart: every runner of a
# sharded run instruments the same tree and captures its own suites, and one
# more runner instruments the tree again, gathers every capture into
# $(COV_DIR)/hits, and reports. Instrumenting takes seconds; the suites take
# the time.
coverage-instrument:
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
	@# with itself is still not attempted. Every suite is copied, not only
	@# this runner's group: a suite can import another.
	@mkdir -p $(COV_DIR)/coverage
	@cp coverage/*.mojo $(COV_DIR)/coverage/
	@mkdir -p $(COV_DIR)/tests
	@[ -z "$(strip $(TESTS))" ] || cp $(TESTS) $(COV_DIR)/tests/
	@mkdir -p $(COV_DIR)/hits
endif

coverage-capture:
ifneq ($(strip $(COVERED)),)
	@[ -f $(COV_DIR)/manifest.txt ] || \
	  { echo "Run 'make coverage-instrument' first."; exit 1; }
	@# Exact streams are compressed as they arrive. MC-DC record order stays
	@# intact, without keeping tens of gigabytes of repeated probes on disk.
	@printf '%s\n' $(COVERAGE_SUITES) \
	  | perl -e 'alarm shift; exec @ARGV' $(COV_BUDGET) \
	      xargs -P $(JOBS) -I {} \
	      sh -c 'name=$$(basename "$$1" .mojo); \
	             python3 tools/coverage_io.py capture \
	               --out "$(COV_DIR)/hits/$$name.out" \
	               --err "$(COV_DIR)/hits/$$name.txt.gz" -- \
	               $(MOJO) run -I $(COV_DIR) "$(COV_DIR)/tests/$$name.mojo"' _ {} \
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
	@echo "Captured $(words $(COVERAGE_SUITES)) suites under instrumentation."
endif

coverage-report:
ifneq ($(strip $(COVERED)),)
	@[ -f $(COV_DIR)/manifest.txt ] || \
	  { echo "Run 'make coverage-instrument' first."; exit 1; }
	@# A capture from every suite of the whole list, not only this runner's
	@# group: a group whose captures went missing must not pass by silence.
	@missing=0; for f in $(COVERAGE_TESTS); do \
	  name=$$(basename "$$f" .mojo); \
	  if [ ! -f "$(COV_DIR)/hits/$$name.txt.gz" ]; then \
	    echo "No capture from $$name."; missing=1; \
	  fi; \
	done; [ $$missing -eq 0 ] || exit 1
	@# FIFOs feed the original bytes to the reporter one suite at a time.
	@python3 tools/coverage_io.py report --capture-dir $(COV_DIR)/hits -- \
	  $(MOJO) run $(MOJOFLAGS) coverage/report_cli.mojo $(COV_DIR)/manifest.txt
endif

# The units system's value is what it *rejects*, and a rejection cannot be
# tested from inside a test suite: a file exercising one would not build. So
# each case lives in its own file that must fail to compile, and this target
# fails if any of them ever starts compiling. The helper first builds a
# valid control and distinguishes source rejections from infrastructure errors.
compile-fail: $(NEG_STAMP)
$(NEG_STAMP):
	@python3 tools/compile_fail.py --compiler=$(call quote,$(MOJO)) \
	  --flags=$(call quote,$(MOJOFLAGS)) $(COMPILE_FAIL_RUN)
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

# Uncached: the point is a fresh measurement. Writes this host's
# bench/results-<linux|macos>.json and fills its tables on
# docs/wiki/Benchmarks.md.
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

# Reuse the import graph used by the suite cache. Keep extensions in the
# lint/coverage lists, but do not rebuild a cube for an unrelated anatomy edit.
# The writer uses atomic replacement, so concurrent make processes are safe.
EXAMPLE_INPUTS_STATUS := $(shell python3 tools/example_inputs.py \
                          --output $(CACHE_DIR)/example-inputs.mk || echo failed)
ifneq ($(strip $(EXAMPLE_INPUTS_STATUS)),)
$(error Cannot read example prerequisites)
endif
include $(CACHE_DIR)/example-inputs.mk

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
           $(OUT_DIR)/animated.png $(OUT_DIR)/computation.png \
           $(OUT_DIR)/lightmap.png $(OUT_DIR)/svg.png \
           $(OUT_DIR)/models.png $(OUT_DIR)/mathaddons.png \
           $(OUT_DIR)/hooks.png $(OUT_DIR)/sculptor.png \
           $(OUT_DIR)/tslfunctions.png $(OUT_DIR)/gaussian.png \
           $(OUT_DIR)/vxgi.png $(OUT_DIR)/lighting.png \
           $(OUT_DIR)/lofts.png $(OUT_DIR)/generators.png \
           $(OUT_DIR)/computenodes.png \
           $(OUT_DIR)/femur.png $(OUT_DIR)/tibia.png \
           $(OUT_DIR)/fibula.png $(OUT_DIR)/patella.png \
           $(OUT_DIR)/knee.png $(OUT_DIR)/muscles.png \
           $(OUT_DIR)/leg.png $(OUT_DIR)/legs.png \
           $(OUT_DIR)/foot.png $(OUT_DIR)/limb.png \
           $(OUT_DIR)/vessels.png $(OUT_DIR)/lymph.png \
           $(OUT_DIR)/nerves.png $(OUT_DIR)/integument.png \
           $(OUT_DIR)/pelvis.png $(OUT_DIR)/torso.png \
           $(OUT_DIR)/arm.png $(OUT_DIR)/hand.png \
           $(OUT_DIR)/head.png \
           $(OUT_DIR)/water.png \
           $(OUT_DIR)/carla_towns.png \
           $(OUT_DIR)/game_humanoid.png \
           $(OUT_DIR)/hairstyles.png \
           $(OUT_DIR)/genomes.png \
           $(OUT_DIR)/family.png \
           $(OUT_DIR)/talking.png \
           $(OUT_DIR)/carla.png \
           $(OUT_DIR)/carla_town.png \
           $(OUT_DIR)/expressions.png

# A chrome ball under a sky, reflecting a cube camera's view of two boxes.
$(OUT_DIR)/mirror.png: $(EXAMPLE_INPUTS_mirror)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/mirror.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A split screen: two viewports and two scissors drawing into one target.
$(OUT_DIR)/split.png: $(EXAMPLE_INPUTS_split)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/split.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A grid, the axes, a box around a cube and a second camera's frustum.
$(OUT_DIR)/helpers.png: $(EXAMPLE_INPUTS_outlines)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/outlines.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/lines.png: $(EXAMPLE_INPUTS_lines)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lines.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/cube.png: $(EXAMPLE_INPUTS_cube)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/cube.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/cubes.png: $(EXAMPLE_INPUTS_cubes)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/cubes.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Translucent panes over a solid cube: blending, sorting and linear light.
$(OUT_DIR)/glass.png: $(EXAMPLE_INPUTS_glass)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/glass.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Three colored lamps on a coarse sphere: many lights, and per-fragment shading.
$(OUT_DIR)/lamps.png: $(EXAMPLE_INPUTS_lamps)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lamps.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A cube wearing a PNG somebody else's encoder wrote: the decoder end to end.
$(OUT_DIR)/photo.png: $(EXAMPLE_INPUTS_photo) assets/brick.png
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/photo.mojo assets/brick.png $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A receding floor, half mipmapped and half not: minification and aliasing.
$(OUT_DIR)/floor.png: $(EXAMPLE_INPUTS_floor)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/floor.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A checkerboard cube: scene graph, culling, depth, uv and sampling together.
$(OUT_DIR)/textured.png: $(EXAMPLE_INPUTS_textured)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/textured.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Two frames, perspective-correct and affine, of the same prepared triangles.
$(OUT_DIR)/uv.png: $(EXAMPLE_INPUTS_uv)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/uv.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/spin.png: $(EXAMPLE_INPUTS_spin)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/spin.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/triangle.png: $(EXAMPLE_INPUTS_triangle)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/triangle.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/first_scene.png: $(EXAMPLE_INPUTS_first_scene)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/first_scene.mojo); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/lit_scene.png: $(EXAMPLE_INPUTS_lit_scene)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lit_scene.mojo); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/rotations.png: $(EXAMPLE_INPUTS_rotations)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/rotations.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/cameras.png: $(EXAMPLE_INPUTS_ortho)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/ortho.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/geometry.png: $(EXAMPLE_INPUTS_geometry)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/geometry.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/instances.png: $(EXAMPLE_INPUTS_instances)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/instances.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/raycast.png: $(EXAMPLE_INPUTS_raycast)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/raycast.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/curves.png: $(EXAMPLE_INPUTS_curves)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/curves.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/keyframes.png: $(EXAMPLE_INPUTS_keyframes)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/keyframes.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/skinning.png: $(EXAMPLE_INPUTS_skinning)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/skinning.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Ten spheres from chalk to mirror and from dielectric to metal, under a sky.
$(OUT_DIR)/physical.png: $(EXAMPLE_INPUTS_physical)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/physical.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/phong.png: $(EXAMPLE_INPUTS_phong)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/phong.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/fog.png: $(EXAMPLE_INPUTS_fog)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/fog.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/culling.png: $(EXAMPLE_INPUTS_culling)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/culling.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/clipping.png: $(EXAMPLE_INPUTS_clipping)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/clipping.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/gpu_backend.png: $(EXAMPLE_INPUTS_gpu_backend)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/gpu_backend.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/exposure.png: $(EXAMPLE_INPUTS_exposure)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/exposure.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/model.png: $(EXAMPLE_INPUTS_model) assets/cube.obj
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/model.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/math.png: $(EXAMPLE_INPUTS_orbit)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/orbit.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/units.png: $(EXAMPLE_INPUTS_clock)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/clock.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/chain.png: $(EXAMPLE_INPUTS_chain)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/chain.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/additive.png: $(EXAMPLE_INPUTS_additive)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/additive.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/normals.png: $(EXAMPLE_INPUTS_normals)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/normals.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/fragments.png: $(EXAMPLE_INPUTS_fragments)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/fragments.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/coverage.png: $(EXAMPLE_INPUTS_edges)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/edges.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/sprites.png: $(EXAMPLE_INPUTS_sprites)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/sprites.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/stereo.png: $(EXAMPLE_INPUTS_stereo)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/stereo.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/television.png: $(EXAMPLE_INPUTS_television)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/television.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A cube's shadow swings across a floor as a directional lamp orbits.
$(OUT_DIR)/shadows.png: $(EXAMPLE_INPUTS_shadows)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/shadows.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A ribbon eight pixels wide, drawn as triangles, turns with a box.
$(OUT_DIR)/wide.png: $(EXAMPLE_INPUTS_wide)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/wide.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Bloom and a vignette over a dark knot and two emissive spheres.
$(OUT_DIR)/postprocessing.png: $(EXAMPLE_INPUTS_bloom)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/bloom.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Translate handles on a cube, redrawn as the camera orbits.
$(OUT_DIR)/controls.png: $(EXAMPLE_INPUTS_gizmo)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/gizmo.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A scene written as three.js JSON and read back before it is drawn.
$(OUT_DIR)/scenejson.png: $(EXAMPLE_INPUTS_json_scene)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/json_scene.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A knot written to glTF and read back before it is drawn.
$(OUT_DIR)/exporters.png: $(EXAMPLE_INPUTS_reloaded)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/reloaded.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A glass sphere refracts three colored boxes.
$(OUT_DIR)/transmission.png: $(EXAMPLE_INPUTS_gem)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/gem.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Distance from a point, packed into the color of a sphere.
$(OUT_DIR)/distance.png: $(EXAMPLE_INPUTS_distance)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/distance.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Three cubes in fog. The middle material has fog turned off.
$(OUT_DIR)/unfogged.png: $(EXAMPLE_INPUTS_unfogged)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/unfogged.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A float color attachment above a normal attachment.
$(OUT_DIR)/targets.png: $(EXAMPLE_INPUTS_targets)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/targets.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Sheen, iridescence and anisotropy on three spheres.
$(OUT_DIR)/layers.png: $(EXAMPLE_INPUTS_layers)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/layers.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A node graph tints a sphere and pushes its vertices.
$(OUT_DIR)/nodes.png: $(EXAMPLE_INPUTS_graph)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/graph.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# UASTC and ETC1S images decoded from KTX2 files.
$(OUT_DIR)/ktx2.png: $(EXAMPLE_INPUTS_basis) assets/ktx2/uastc_rgb_zstd_mips.ktx2 \
	assets/ktx2/etc1s_rgb.ktx2 assets/ktx2/uastc_gradient.ktx2
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/basis.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Clearcoat bands and a specular color map on two spheres.
$(OUT_DIR)/coats.png: $(EXAMPLE_INPUTS_coats)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/coats.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A metal ball whose sky was written as scene JSON and read back.
$(OUT_DIR)/environment.png: $(EXAMPLE_INPUTS_skyjson)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/skyjson.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Preetham's daylight sky, with the sun crossing above a sphere.
$(OUT_DIR)/sky.png: $(EXAMPLE_INPUTS_daylight)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/daylight.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# One box, a different material on each face.
$(OUT_DIR)/faces.png: $(EXAMPLE_INPUTS_faces)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/faces.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# The Utah teapot, from the geometry addons.
$(OUT_DIR)/teapot.png: $(EXAMPLE_INPUTS_utah)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/utah.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Two metaballs joined by marching cubes.
$(OUT_DIR)/blobs.png: $(EXAMPLE_INPUTS_blobs)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/blobs.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A morph flip-book beside a gyroscope.
$(OUT_DIR)/animated.png: $(EXAMPLE_INPUTS_flipbook)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/flipbook.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A ripple field computed one step a frame.
$(OUT_DIR)/computation.png: $(EXAMPLE_INPUTS_ripples)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/ripples.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A light map that gathers a walking lamp.
$(OUT_DIR)/lightmap.png: $(EXAMPLE_INPUTS_baked)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/baked.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# An SVG drawing of an icosahedron and a box, filled into a PNG.
$(OUT_DIR)/svg.png: $(EXAMPLE_INPUTS_diagram)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/diagram.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# An LDraw model loaded from the parts library.
$(OUT_DIR)/models.png: $(EXAMPLE_INPUTS_bricks) assets/ldraw/scene.mpd
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/bricks.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A height field from simplex noise.
$(OUT_DIR)/mathaddons.png: $(EXAMPLE_INPUTS_terrain)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/terrain.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# An override material, refused by the middle sphere.
$(OUT_DIR)/hooks.png: $(EXAMPLE_INPUTS_override)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/override.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# An inflated knob on a turning sphere.
$(OUT_DIR)/sculptor.png: $(EXAMPLE_INPUTS_clay)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/clay.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Voronoi cells on a turning sphere.
$(OUT_DIR)/tslfunctions.png: $(EXAMPLE_INPUTS_cells)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/cells.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A cloud of Gaussian splats.
$(OUT_DIR)/gaussian.png: $(EXAMPLE_INPUTS_cloud)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/cloud.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Bounced light in a colored corner.
$(OUT_DIR)/vxgi.png: $(EXAMPLE_INPUTS_bounce)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/bounce.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A low sun and its two shadow cascades.
$(OUT_DIR)/lighting.png: $(EXAMPLE_INPUTS_sunlight)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/sunlight.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A vase skinned through loft sections.
$(OUT_DIR)/lofts.png: $(EXAMPLE_INPUTS_vase)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/vase.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A tree grown from a seed.
$(OUT_DIR)/generators.png: $(EXAMPLE_INPUTS_sapling)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/sapling.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Points stepped by a compute kernel.
$(OUT_DIR)/computenodes.png: $(EXAMPLE_INPUTS_particles)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/particles.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/femur.png: $(EXAMPLE_INPUTS_femur)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/femur.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/tibia.png: $(EXAMPLE_INPUTS_tibia)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/tibia.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/fibula.png: $(EXAMPLE_INPUTS_fibula)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/fibula.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/patella.png: $(EXAMPLE_INPUTS_patella)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/patella.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/knee.png: $(EXAMPLE_INPUTS_knee)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/knee.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/muscles.png: $(EXAMPLE_INPUTS_muscles)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/muscles.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/leg.png: $(EXAMPLE_INPUTS_leg)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/leg.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/legs.png: $(EXAMPLE_INPUTS_legs)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/legs.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/foot.png: $(EXAMPLE_INPUTS_foot)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/foot.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/limb.png: $(EXAMPLE_INPUTS_limb)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/limb.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# The lower body: the pelvis, both legs and both feet, with skin and without.
$(OUT_DIR)/pelvis.png: $(EXAMPLE_INPUTS_pelvis)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/pelvis.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A body below the neck, arms included, with skin and without.
$(OUT_DIR)/torso.png: $(EXAMPLE_INPUTS_torso)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/torso.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# An arm and its hand, with skin and without.
$(OUT_DIR)/arm.png: $(EXAMPLE_INPUTS_arm)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/arm.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A hand and its fingers, with skin and without.
$(OUT_DIR)/hand.png: $(EXAMPLE_INPUTS_hand)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/hand.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# A neck and a head, with skin and without.
$(OUT_DIR)/head.png: $(EXAMPLE_INPUTS_head)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/head.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/vessels.png: $(EXAMPLE_INPUTS_vessels)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/vessels.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/lymph.png: $(EXAMPLE_INPUTS_lymph)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lymph.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/nerves.png: $(EXAMPLE_INPUTS_nerves)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/nerves.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/integument.png: $(EXAMPLE_INPUTS_integument)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/integument.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/water.png: $(EXAMPLE_INPUTS_water) assets/pebbles.jpg
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/water.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/carla_towns.png: $(EXAMPLE_INPUTS_carla_towns) assets/carla/ATTRIBUTION.md assets/carla/tools/carla_assets.py
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/carla_towns.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@ $(patsubst %.png,%_*.png,$@)
	@python3 assets/carla/tools/carla_assets.py credits --all --output $(@:.png=.credits.md)

$(OUT_DIR)/game_humanoid.png: $(EXAMPLE_INPUTS_game_humanoid)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/game_humanoid.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/hairstyles.png: $(EXAMPLE_INPUTS_hairstyles)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/hairstyles.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/genomes.png: $(EXAMPLE_INPUTS_genomes)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/genomes.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/family.png: $(EXAMPLE_INPUTS_family)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/family.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/talking.png: $(EXAMPLE_INPUTS_talking)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/talking.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

$(OUT_DIR)/carla.png: $(EXAMPLE_INPUTS_carla) assets/carla/ATTRIBUTION.md assets/carla/tools/carla_assets.py
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/carla.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@ $(patsubst %.png,%_*.png,$@)
	@python3 assets/carla/tools/carla_assets.py credits --all --output $(@:.png=.credits.md)

$(OUT_DIR)/carla_town.png: $(EXAMPLE_INPUTS_carla_town) assets/carla/ATTRIBUTION.md assets/carla/tools/carla_assets.py
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/carla_town.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@ $(patsubst %.png,%_*.png,$@)
	@python3 assets/carla/tools/carla_assets.py credits --all --output $(@:.png=.credits.md)

$(OUT_DIR)/expressions.png: $(EXAMPLE_INPUTS_expressions)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/expressions.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@python3 tools/optimize_png.py $@

# Existing tracked gallery files keep their identity and history. New renders
# are ignored; use an explicit git add -f only for a reviewed documentation image.
optimize-images:
	@git ls-files -z -- 'out/*.png' | xargs -0 python3 tools/optimize_png.py

# Deliberately leaves $(OUT_DIR) alone: the rendered images are there to be
# looked at, and a folder that keeps emptying itself is no use to watch.
# `make clean-images` removes them when you actually want them gone.
clean:
	@rm -rf $(COV_DIR) $(CACHE_DIR)
	@echo "Removed the coverage build and the cache; kept $(OUT_DIR)."

clean-images:
	@rm -rf $(OUT_DIR)
	@echo "Removed $(OUT_DIR)."

# Parser and cache regressions run without the Mojo compiler.
test-tools:
	@python3 -m unittest discover -s tools -p 'test_*.py'
	@python3 -m unittest discover -s assets/carla/tools -p 'test_*.py'

# Native source-to-source regression: compile first, then enforce the normal
# five-second limit on each executed test. test-tools remains compiler-free.
test-coverage-tool:
	@python3 tools/check_coverage_grouping.py --mojo $(MOJO)
	@python3 tools/check_coverage_protocol.py --mojo $(MOJO)
	@python3 tools/check_coverage_sources.py --mojo $(MOJO)
	@python3 tools/check_coverage_loops.py --mojo $(MOJO)

# Subprocess-only contracts need native children with different environments.
test-portability:
	@python3 tools/check_portability.py --mojo $(MOJO)
