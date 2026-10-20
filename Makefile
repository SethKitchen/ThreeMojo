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
# CPU lint builds may select a target; mojo doc does not accept target flags.
LINT_CPU_BUILD_FLAGS ?=
LINT_CPU_PROGRESS ?= 0

# Every mojo invocation prints a harmless "Failed to initialize Crashpad"
# warning we want to strip. Piping to sed would discard mojo's exit status,
# and `.SHELLFLAGS := -o pipefail` is not an option: macOS ships GNU Make 3.81
# and .SHELLFLAGS was only added in 3.82, so it is silently ignored. Instead
# capture the output, save $? immediately, then filter. `run` is a call-style
# variable: $(call run,<command>) leaves the status in $$rc.
define run
out=$$($(1) 2>&1); rc=$$?; echo "$$out" | sed '/Crashpad/d'
endef

# Shell quoting also protects flags that contain spaces or shell punctuation.
quote = '$(subst ','"'"',$(1))'
# The project tools are Mojo programs. `$(TOOL) NAME ARGUMENT...` runs
# tools/NAME.mojo. tools/tool.sh builds each program once, into .cache/tools/,
# because this Makefile runs some of them many times while it parses. The
# tools have their own compiler, so a test can give MOJO a stand-in. The
# command must not start with an assignment such as `MOJO=...`: then make
# passes it to the shell as one argument, and the cache key's argument
# lists are longer than one argument can be.
TOOL_MOJO := $(if $(wildcard .venv/bin/mojo),.venv/bin/mojo,mojo)
TOOL = sh tools/tool.sh $(call quote,$(TOOL_MOJO))

# --- sources ----------------------------------------------------------------
# Library modules have no main(), so they are checked with `mojo doc`.
LIB_SOURCES  := $(shell find math render units cameras core geometries helpers \
                  objects renderers materials lights loaders animation \
                  postprocessing controls window exporters environments generators extensions \
                  -name '*.mojo' \
                  -not -name '__init__.mojo')
# The coverage tool splits the same way: importable modules, plus two CLIs.
TOOL_CLIS    := coverage/build_cli.mojo coverage/report_cli.mojo
# Modules prefixed with '_' in tests/ and tools/ are import-only helpers, not
# CLI entry points, so a new helper needs no edit here. Keep the two older
# named fixtures in the same inventory. Lint their docs, format them, and copy
# them unchanged beside instrumented test suites.
TEST_HELPER_LIBS := $(wildcard tests/_*.mojo) tests/carla_fixed_s_fixture.mojo \
                    tests/exact_predicates_oracle.mojo
HELPER_LIBS  := $(wildcard tools/_*.mojo) $(TEST_HELPER_LIBS)
TOOL_LIBS    := $(filter-out $(TOOL_CLIS),$(wildcard coverage/*.mojo)) $(HELPER_LIBS)
# Anything with a main() can be compiled, which also type-checks its imports.
# tests/compile_fail is deliberately excluded: those files must NOT compile,
# which is the point of them, so linting them would always fail.
ENTRY_POINTS := $(filter-out $(HELPER_LIBS),$(shell find tests examples bench tools -name '*.mojo' \
                  -not -path 'tests/compile_fail/*' \
                  -not -path 'bench/mojo10/*')) $(TOOL_CLIS)
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
# A library source that needs MAX is named gpu.mojo, gpu_*.mojo or *_gpu.mojo,
# and a new one needs no edit here. Today they are render/gpu.mojo,
# render/gpu_vxgi.mojo, extensions/water/gpu.mojo and window/capi_water_gpu.mojo.
GPU_LIB_SOURCES  := $(foreach f,$(LIB_SOURCES),$(if $(filter gpu.mojo gpu_%.mojo %_gpu.mojo,$(notdir $(f))),$(f)))
# The suites that import render/gpu.mojo but open no device: they flatten
# vertices, state tables, textures and lights on the host and read the
# layout back. They need MAX installed and no GPU, so CI runs them with
# `make test-gpu-host` on a runner that has none. They were once part of
# tests/test_gpu.mojo, and went stale there for a week: that suite fails
# every device test on a machine without a GPU, so seven failing layout
# assertions among two hundred device failures were not seen.
GPU_HOST_TESTS   := tests/test_gpu_layout.mojo \
                    tests/test_gpu_volume_packing.mojo
# A suite that opens a device and is not listed above is named test_*_gpu.mojo.
GPU_TESTS        := tests/test_gpu.mojo tests/test_gpu_water.mojo $(GPU_HOST_TESTS) \
                    $(filter tests/test_%_gpu.mojo,$(TESTS))
GPU_ENTRY_POINTS := $(GPU_TESTS) bench/raster_bench.mojo bench/water_gpu_bench.mojo bench/hair_frame_bench.mojo \
                    tools/gpu_status.mojo

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
# ref can reach, as nx's "affected" does. tools/affected.mojo walks the import
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
affected = $(shell $(TOOL) affected --base $(AFFECTED) $(1))
AFFECTED_CHANGE  := $(shell $(TOOL) affected --base $(AFFECTED) --list)
FORMATTED        := $(shell $(TOOL) affected --base $(AFFECTED) \
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
# What the coverage build copies through uninstrumented: excluded libraries,
# maintained benchmark and tool modules imported by tests, and in an AFFECTED run every
# library the change does not reach. Explicitly measured helpers stay instrumented.
COVERAGE_PASSTHROUGH := $(filter-out $(COVERED),$(LIB_SOURCES) $(HELPER_LIBS) \
                         $(filter bench/% tools/%,$(ENTRY_POINTS)))

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

# The time limit for one test, in seconds. tools/run_suite.mojo fails a test
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
# CPU time is mostly compilation. See tools/shard.mojo. Only the suites split:
# formatting, lint, the docs and the compile-fail cases run whole, on one
# runner. `coverage-report` reads the captures of every group, so it checks
# that each suite of the whole list left one.
SHARD ?=
TEST_SUITES := $(CPU_TESTS)
ifneq ($(strip $(SHARD)),)
TEST_SUITES := $(shell $(TOOL) shard $(SHARD) $(CPU_TESTS) \
                 || echo SHARD_ERROR)
ifneq ($(filter SHARD_ERROR,$(TEST_SUITES)),)
$(error tools/shard.mojo could not split the suites for SHARD=$(SHARD): it takes I/N with 1 <= I <= N and readable suites)
endif
endif
# Instrumented runtime can outweigh compilation by minutes. Keep CPU
# placement unchanged; coverage uses measured compile-and-run costs and
# starts the longest captures first. Every affected suite is still present.
COVERAGE_SUITES := $(COVERAGE_TESTS)
ifneq ($(strip $(SHARD)),)
ifneq ($(filter coverage coverage-capture,$(MAKECMDGOALS)),)
COVERAGE_SUITES := $(shell $(TOOL) coverage_shard $(SHARD) $(COVERAGE_TESTS) \
                       || echo SHARD_ERROR)
ifneq ($(filter SHARD_ERROR,$(COVERAGE_SUITES)),)
$(error tools/coverage_shard.mojo could not split coverage suites for SHARD=$(SHARD))
endif
endif
endif

# At least a minute: a run of a few affected suites still pays a compile
# that takes longer than a second.
COV_BUDGET := $(shell n=$(words $(COVERAGE_SUITES)); \
                [ $$n -lt 60 ] && n=60; echo $$n)

# Explicit coverage transport/execution profile. Raw retains the historical
# JIT path plus the narrow native-fixture repair. Compiled profiles preserve
# source argv0 and arguments, but use a temporary native executable.
COV_PROFILE ?= raw
ifeq ($(filter $(COV_PROFILE),raw aot aot-hits),)
$(error COV_PROFILE must be raw, aot, or aot-hits)
endif
ifeq ($(COV_PROFILE),raw)
COVERAGE_RUN = python3 tools/native_test_support.py run --root $(COV_DIR)
else
COVERAGE_RUN = python3 tools/coverage_hit_aot.py --profile $(COV_PROFILE) --root $(COV_DIR)
endif

CACHE_DIR := .cache
TOOLCHAIN := $(shell $(MOJO) --version 2>/dev/null || echo "no-mojo")
# Native test fixtures are test-only. Their compiler identity also invalidates
# suite stamps; a missing compiler is a build failure, never a skipped suite.
export CC
NATIVE_TOOLCHAIN := $(shell python3 tools/native_test_support.py fingerprint \
                       --cc $(call quote,$(CC)) 2>/dev/null || echo "no-native-compiler")
HASH := $(shell $(TOOL) cache_key \
          --setting=$(call quote,$(MOJO)) \
          --setting=$(call quote,$(MOJOFLAGS)) \
          --setting=$(call quote,lint-cpu-build-flags:$(LINT_CPU_BUILD_FLAGS)) \
          --setting=$(call quote,$(TOOLCHAIN)) \
          --setting=$(call quote,native-tests:$(NATIVE_TOOLCHAIN)) \
          --setting=$(call quote,$(AFFECTED) $(AFFECTED_CHANGE)) \
          --setting=$(call quote,cpu-tests:$(CPU_TESTS)) \
          --setting=$(call quote,shard:$(SHARD)) \
          --setting=$(call quote,test-timeout:$(TEST_TIMEOUT)) \
          --setting=$(call quote,cpu-entries:$(CPU_ENTRY_POINTS)) \
          --setting=$(call quote,cpu-docs:$(CPU_DOC_SOURCES)) \
          --setting=$(call quote,negative:$(COMPILE_FAIL_RUN)) \
          --setting=$(call quote,format:$(FORMATTED)) \
          --setting=$(call quote,coverage-profile:$(COV_PROFILE)) \
          --setting=$(call quote,coverage-loop-proof-schema:constant-loops-v2) \
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

.PHONY: test-gpu-device help check check-cpu check-gpu ci test test-cpu test-gpu test-gpu-host check-gpu-air \
        docs-check wiki-publish test-tools test-coverage-tool test-portability \
        coverage-instrument coverage-capture coverage-report \
        lint lint-cpu lint-gpu compile-gpu gpu-status docstrings fmt fmt-check coverage \
        compile-fail example animation viewer bench bench-scene bench-examples \
        clean clean-images optimize-images draco-export-check audio-game-humanoid \
        repository-check

help:
	@echo "ThreeMojo tasks ($(TOOLCHAIN), inputs hash to $(HASH))"
	@echo
	@echo "  make check      everything                 <- before committing"
	@echo "  make check-cpu  the standard-library-only half ($(words $(CPU_TESTS)) suites)"
	@echo "  make check-gpu  the optional MAX backend ($(words $(GPU_TESTS)) suites)"
	@echo "  make test-gpu-host  the MAX backend's layout suites, no GPU needed"
	@echo "  make check-gpu-air  every Metal kernel call matches its callee, no GPU needed"
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

# The standard-library production half does not need MAX. Native test-only
# fixtures also use a host C compiler; they are never linked into production.
check-cpu: fmt-check lint-cpu test-cpu compile-fail docs-check test-tools test-coverage-tool test-portability

# The complete GPU check needs MAX and an accelerator. The status line
# comes first so a suite that skipped every hardware test cannot be mistaken
# for one that ran them. Use compile-gpu for a build-only check without a GPU.
check-gpu: gpu-status test-gpu-host check-gpu-air
	@$(TOOL) gpu_status --available; rc=$$?; \
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
# tools/suite_key.mojo. A change to one module builds and runs only the
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
	@$(TOOL) suite_key --stamps $(SUITE_STAMPS) \
	    --setting=$(call quote,$(MOJO)) \
	    --setting=$(call quote,$(MOJOFLAGS)) \
	    --setting=$(call quote,$(TOOLCHAIN)) \
	    --setting=$(call quote,native-tests:$(NATIVE_TOOLCHAIN)) \
	    --setting=$(call quote,test-timeout:$(TEST_TIMEOUT)) \
	    $(TEST_SUITES) > $(CACHE_DIR)/suites-to-run || exit 1
	@sh tools/tool.sh $(TOOL_MOJO) --build run_suite
	@sh tools/tool.sh $(TOOL_MOJO) --build compiler_telemetry
	@xargs -n 2 -P $(JOBS) \
	      sh -c '[ "$$#" -eq 0 ] && exit 0; \
	             name=$$(basename "$$1" .mojo); bin=$(BIN_DIR)/$$name; \
	             exec 3>&1; \
	             progress() { printf "%s suite=%s %s\n" \
	               "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$1" "$$2" >&3; }; \
	             progress "$$1" "build-start: $(MOJO) build $(MOJOFLAGS) --Werror -o $$bin $$1"; \
	             out=$$(sh tools/tool.sh $(TOOL_MOJO) compiler_telemetry --suite "$$1" --log-fd 3 -- \
	                    python3 tools/native_test_support.py run --root . \
	                      --suite "$$1" --cache $(CACHE_DIR)/native -- \
	                      $(MOJO) build $(MOJOFLAGS) --Werror -o "$$bin" "$$1" \
	                    2>&1; build_rc=$$?; \
	                    progress "$$1" "build-end: exit=$$build_rc"; \
	                    [ $$build_rc -eq 0 ] || exit $$build_rc; \
	                    progress "$$1" "run-start: run_suite --seconds $(TEST_TIMEOUT) --suite $$1 -- $$bin"; \
	                    sh tools/tool.sh $(TOOL_MOJO) run_suite \
	                      --seconds $(TEST_TIMEOUT) --suite "$$1" -- "$$bin"; \
	                    run_rc=$$?; \
	                    progress "$$1" "run-end: exit=$$run_rc"; \
	                    exit $$run_rc); \
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
	@$(TOOL) gpu_status --available; rc=$$?; \
	  if [ $$rc -eq 0 ]; then $(MAKE) test-gpu-device; \
	  elif [ $$rc -ne 1 ]; then exit $$rc; fi

test-gpu-device:
	@sh tools/tool.sh $(TOOL_MOJO) --build run_suite
	@printf '%s\n' $(filter-out $(GPU_HOST_TESTS),$(GPU_TESTS)) \
	  | perl -e 'alarm shift; exec @ARGV' $(GPU_BUDGET) \
	      xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$(sh tools/tool.sh $(TOOL_MOJO) run_suite --results-only \
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
	@sh tools/tool.sh $(TOOL_MOJO) --build run_suite
	@printf '%s\n' $(GPU_HOST_TESTS) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'out=$$(sh tools/tool.sh $(TOOL_MOJO) run_suite --results-only \
	               --suite "$$1" -- $(MOJO) run $(MOJOFLAGS) "$$1" 2>&1); rc=$$?; \
	             printf "%s\n" "$$out" | sed "/Crashpad/d"; exit $$rc' _ {} \
	  || { echo "Some GPU host suites FAILED."; exit 1; }
	@echo "All $(words $(GPU_HOST_TESTS)) GPU host suites passed."
	@$(call stamp,test-gpu-host)

gpu-status:
	@$(TOOL) gpu_status

lint: lint-cpu lint-gpu

# The suites are linted where `test-cpu` builds them.
# On failure, name the source and quote the actual argv; keep normal output quiet.
lint-cpu: $(LINT_CPU_STAMP)
$(LINT_CPU_STAMP):
	@printf '%s\n' $(filter-out $(CPU_TESTS),$(CPU_ENTRY_POINTS)) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'source=$$1; set -- $(MOJO) build $(MOJOFLAGS) $(LINT_CPU_BUILD_FLAGS) \
	               --Werror -o /dev/null "$$source"; \
	             if [ "$(LINT_CPU_PROGRESS)" = 1 ]; then \
	               python3 -c "import datetime, shlex, sys; line = datetime.datetime.now(datetime.timezone.utc).strftime(\"%Y-%m-%dT%H:%M:%SZ\") + \" lint-build-start: \" + shlex.join(sys.argv[1:]); print(line if len(line) <= 4096 else line[:4084] + \" [truncated]\", flush=True)" "$$@"; \
	             fi; \
	             out=$$("$$@" 2>&1); rc=$$?; \
	             if [ "$(LINT_CPU_PROGRESS)" = 1 ]; then \
	               printf "%s lint-build-end: source=%s exit=%s\n" "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$source" "$$rc"; \
	             fi; \
	             if [ $$rc -ne 0 ]; then \
	               printf "lint-cpu failed: %s (exit %s)\n" "$$source" "$$rc" >&2; \
	               python3 -c "import shlex, sys; print(\"command: \" + shlex.join(sys.argv[1:]), file=sys.stderr)" "$$@"; \
	             fi; \
	             printf "%s" "$$out" | sed "/Crashpad/d"; \
	             exit $$rc' _ {} \
	  || exit 1
	@printf '%s\n' $(CPU_DOC_SOURCES) \
	  | xargs -P $(JOBS) -I {} \
	      sh -c 'source=$$1; set -- $(MOJO) doc $(MOJOFLAGS) \
	               --Werror -o /dev/null "$$source"; \
	             if [ "$(LINT_CPU_PROGRESS)" = 1 ]; then \
	               python3 -c "import datetime, shlex, sys; line = datetime.datetime.now(datetime.timezone.utc).strftime(\"%Y-%m-%dT%H:%M:%SZ\") + \" lint-doc-start: \" + shlex.join(sys.argv[1:]); print(line if len(line) <= 4096 else line[:4084] + \" [truncated]\", flush=True)" "$$@"; \
	             fi; \
	             out=$$("$$@" 2>&1); rc=$$?; \
	             if [ "$(LINT_CPU_PROGRESS)" = 1 ]; then \
	               printf "%s lint-doc-end: source=%s exit=%s\n" "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$source" "$$rc"; \
	             fi; \
	             if [ $$rc -ne 0 ]; then \
	               printf "lint-cpu failed: %s (exit %s)\n" "$$source" "$$rc" >&2; \
	               python3 -c "import shlex, sys; print(\"command: \" + shlex.join(sys.argv[1:]), file=sys.stderr)" "$$@"; \
	             fi; \
	             printf "%s" "$$out" | sed "/Crashpad/d"; \
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
# Keep each recipe below the shell's argument limit. GNU Make 3.81 has no
# $(file ...) function, so write the selected paths in small recipe lines.
# The manifest also lets the copy and diff loops share exactly one selection.
# Each make process owns its manifest. Keep it outside stamp(fmt)'s fmt-*
# cleanup so concurrent checks cannot remove or overwrite another selection.
FMT_RUN_ID := $(shell python3 -c 'import uuid; print(uuid.uuid4().hex)')
FMT_INPUTS := $(CACHE_DIR)/format-inputs-$(FMT_RUN_ID)
define write-format-inputs
$(if $(strip $(1)),@printf '%s\n' $(foreach f,$(wordlist 1,4,$(1)),$(call quote,$(f))) >> $(FMT_INPUTS)
$(call write-format-inputs,$(wordlist 5,$(words $(1)),$(1))))
endef

fmt-check: $(FMT_STAMP)
$(FMT_STAMP):
	@test -n "$(FMT_RUN_ID)" || { echo "Cannot name formatter inputs."; exit 1; }
	@mkdir -p $(CACHE_DIR)
	@: > $(FMT_INPUTS)
	$(call write-format-inputs,$(FORMATTED))
	@fail=0; tmp=$$(mktemp -d) || { rm -f $(FMT_INPUTS); exit 1; }; \
	trap 'rm -rf "$$tmp"; rm -f $(FMT_INPUTS)' 0; \
	format_batch() { \
	  [ $$# -gt 0 ] || return 0; \
	  $(call run,$(MOJO) format -q "$$@"); \
	  return $$rc; \
	}; \
	set --; size=0; copied=0; \
	while IFS= read -r f; do \
	  mkdir -p "$$tmp/$$(dirname "$$f")" || exit 1; \
	  cp "$$f" "$$tmp/$$f" || exit 1; \
	  path="$$tmp/$$f"; \
	  if [ $$# -ge 64 ] || [ $$((size + $${#path} + 1)) -gt 8192 ]; then \
	    format_batch "$$@" || exit $$?; \
	    set --; size=0; \
	  fi; \
	  set -- "$$@" "$$path"; size=$$((size + $${#path} + 1)); \
	  copied=$$((copied + 1)); \
	done < $(FMT_INPUTS) || exit $$?; \
	[ $$copied -eq $(words $(FORMATTED)) ] || { echo "Incomplete formatter inputs."; exit 1; }; \
	format_batch "$$@" || exit $$?; \
	checked=0; \
	while IFS= read -r f; do \
	  if ! diff -q "$$f" "$$tmp/$$f" > /dev/null; then \
	    echo "needs formatting: $$f"; fail=1; \
	  fi; \
	  checked=$$((checked + 1)); \
	done < $(FMT_INPUTS) || exit $$?; \
	[ $$checked -eq $(words $(FORMATTED)) ] || { echo "Incomplete formatter inputs."; exit 1; }; \
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
	@# Full CI discovers sources with find; its filesystem order is not stable.
	@# Keep duplicate-input rejection before make's canonical sort deduplicates.
	@[ "$(words $(COVERED))" -eq "$(words $(sort $(COVERED)))" ] || \
	  { echo "Coverage requires distinct source identities."; exit 1; }
	@for f in $(sort $(COVERED)); do mkdir -p "$(COV_DIR)/$$(dirname $$f)"; done
	@python3 tools/coverage_loop_proofs.py begin --root . --build $(COV_DIR) \
	  --compiler=$(call quote,$(TOOLCHAIN)) --flags=$(call quote,$(MOJOFLAGS)) \
	  --mojo=$(call quote,$(MOJO)) --sources $(sort $(COVERED))
	@$(call run,$(MOJO) run $(MOJOFLAGS) coverage/build_cli.mojo \
	  $(COV_DIR) $(sort $(COVERED))); \
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
	@python3 tools/native_test_support.py copy --root . --destination $(COV_DIR)
	@python3 tools/coverage_loop_proofs.py seal --root . --build $(COV_DIR) \
	  --compiler=$(call quote,$(TOOLCHAIN)) --flags=$(call quote,$(MOJOFLAGS)) \
	  --mojo=$(call quote,$(MOJO)) --capture-cache=$(call quote,$(CACHE_DIR)/native-coverage) \
	  --suites $(COVERAGE_TESTS)
	@mkdir -p $(COV_DIR)/hits
endif

coverage-capture:
ifneq ($(strip $(COVERED)),)
	@[ -f $(COV_DIR)/manifest.txt ] || \
	  { echo "Run 'make coverage-instrument' first."; exit 1; }
	@# Exact streams are compressed as they arrive. MC-DC record order stays
	@# intact, without keeping tens of gigabytes of repeated probes on disk.
	@printf '%s\n' $(COVERAGE_SUITES) \
	  | python3 tools/coverage_io.py group --seconds $(COV_BUDGET) -- \
	      xargs -P $(JOBS) -I {} \
	      sh -c 'name=$$(basename "$$1" .mojo); \
	             python3 tools/coverage_io.py capture \
	               --out "$(COV_DIR)/hits/$$name.out" \
	               --err "$(COV_DIR)/hits/$$name.txt.gz" \
	               --loop-proof "$(COV_DIR)/loop-proofs.json" --loop-proof-root . -- \
	               $(COVERAGE_RUN) \
	                 --suite "$(COV_DIR)/tests/$$name.mojo" --cache $(CACHE_DIR)/native-coverage \
	                 -- \
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
	@python3 tools/coverage_io.py report --capture-dir $(COV_DIR)/hits \
	  --loop-proof-root . --loop-proof-build $(COV_DIR) \
	  --compiler=$(call quote,$(TOOLCHAIN)) --flags=$(call quote,$(MOJOFLAGS)) \
	  --mojo=$(call quote,$(MOJO)) --capture-cache=$(call quote,$(CACHE_DIR)/native-coverage) \
	  --suites $(COVERAGE_TESTS) -- \
	  $(MOJO) run $(MOJOFLAGS) coverage/report_cli.mojo $(COV_DIR)/manifest.txt
endif

# The units system's value is what it *rejects*, and a rejection cannot be
# tested from inside a test suite: a file exercising one would not build. So
# each case lives in its own file that must fail to compile, and this target
# fails if any of them ever starts compiling. The helper first builds a
# valid control and distinguishes source rejections from infrastructure errors.
compile-fail: $(NEG_STAMP)
$(NEG_STAMP):
	@$(MOJO) run $(MOJOFLAGS) tools/compile_fail.mojo --compiler=$(call quote,$(MOJO)) \
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
	@$(TOOL) bench_examples

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
EXAMPLE_INPUTS_STATUS := $(shell $(TOOL) example_inputs \
                          --output $(CACHE_DIR)/example-inputs.mk || echo failed)
ifneq ($(strip $(EXAMPLE_INPUTS_STATUS)),)
$(error Cannot read example prerequisites)
endif
include $(CACHE_DIR)/example-inputs.mk

# This example writes a GLB, so it has a separate non-image target.
audio-game-humanoid: $(OUT_DIR)/audio-character.glb

$(OUT_DIR)/audio-character.glb: $(EXAMPLE_INPUTS_audio_game_humanoid)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/audio_game_humanoid.mojo $@); \
	[ $$rc -eq 0 ] || exit 1

# Every gallery image renders and compresses the same way, so one template
# writes each rule. examples/gallery.mk lists the images.
define GALLERY_RULE
GALLERY_IMAGES += $$(OUT_DIR)/$(1).png
$$(OUT_DIR)/$(1).png: $$(EXAMPLE_INPUTS_$(2)) $(3)
	@mkdir -p $$(OUT_DIR)
	@$$(call run,$$(MOJO) run $$(MOJOFLAGS) examples/$(2).mojo $$@); \
	[ $$$$rc -eq 0 ] || exit 1
	@$$(MOJO) run $$(MOJOFLAGS) tools/optimize_png.mojo $$@
endef
gallery = $(eval $(call GALLERY_RULE,$(strip $(1)),$(strip $(2)),$(strip $(3))))
GALLERY_IMAGES :=
include examples/gallery.mk

animation: $(GALLERY_IMAGES) \
           $(OUT_DIR)/photo.png \
           $(OUT_DIR)/first_scene.png \
           $(OUT_DIR)/lit_scene.png \
           $(OUT_DIR)/ktx2.png \
           $(OUT_DIR)/carla_towns.png \
           $(OUT_DIR)/carla.png \
           $(OUT_DIR)/carla_town.png

# A cube wearing a PNG somebody else's encoder wrote: the decoder end to end.
$(OUT_DIR)/photo.png: $(EXAMPLE_INPUTS_photo) assets/brick.png
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/photo.mojo assets/brick.png $@); \
	[ $$rc -eq 0 ] || exit 1
	@$(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo $@

$(OUT_DIR)/triangle.png: $(EXAMPLE_INPUTS_triangle)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/triangle.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@$(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo $@

$(OUT_DIR)/first_scene.png: $(EXAMPLE_INPUTS_first_scene)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/first_scene.mojo); \
	[ $$rc -eq 0 ] || exit 1
	@$(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo $@

$(OUT_DIR)/lit_scene.png: $(EXAMPLE_INPUTS_lit_scene)
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/lit_scene.mojo); \
	[ $$rc -eq 0 ] || exit 1
	@$(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo $@

# UASTC and ETC1S images decoded from KTX2 files.
$(OUT_DIR)/ktx2.png: $(EXAMPLE_INPUTS_basis) assets/ktx2/uastc_rgb_zstd_mips.ktx2 \
	assets/ktx2/etc1s_rgb.ktx2 assets/ktx2/uastc_gradient.ktx2
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/basis.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@$(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo $@

$(OUT_DIR)/carla_towns.png: $(EXAMPLE_INPUTS_carla_towns) assets/carla/ATTRIBUTION.md tools/carla_assets.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/carla_towns.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@$(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo $@ $(patsubst %.png,%_*.png,$@)
	@$(TOOL) carla_assets credits --all --output $(@:.png=.credits.md)

$(OUT_DIR)/carla.png: $(EXAMPLE_INPUTS_carla) assets/carla/ATTRIBUTION.md tools/carla_assets.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/carla.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@$(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo $@ $(patsubst %.png,%_*.png,$@)
	@$(TOOL) carla_assets credits --all --output $(@:.png=.credits.md)

$(OUT_DIR)/carla_town.png: $(EXAMPLE_INPUTS_carla_town) assets/carla/ATTRIBUTION.md tools/carla_assets.mojo
	@mkdir -p $(OUT_DIR)
	@$(call run,$(MOJO) run $(MOJOFLAGS) examples/carla_town.mojo $@); \
	[ $$rc -eq 0 ] || exit 1
	@$(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo $@ $(patsubst %.png,%_*.png,$@)
	@$(TOOL) carla_assets credits --all --output $(@:.png=.credits.md)

# Existing tracked gallery files keep their identity and history. New renders
# are ignored; use an explicit git add -f only for a reviewed documentation image.
optimize-images:
	@git ls-files -z -- 'out/*.png' | xargs -0 $(MOJO) run $(MOJOFLAGS) tools/optimize_png.mojo

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
# The #333 oracle modules each copy whole roots and replay proofs; one after
# another they exceed a CI job's time limit, so they run a module per process.
# TOOLS_SHARD=I/N splits the oracle tests over N runners; the first runner
# also runs the two quick discoveries and the read-only spiral check.
TOOLS_SHARD ?=
test-tools:
	@$(if $(filter-out 1/%,$(TOOLS_SHARD)),:,python3 -m unittest discover -s tools -p 'test_*.py')
	@$(if $(filter-out 1/%,$(TOOLS_SHARD)),:,python3 -m unittest discover -s assets/carla/tools -p 'test_*.py')
	@python3 tools/parallel_unittest.py --jobs $(JOBS) $(if $(TOOLS_SHARD),--shard $(TOOLS_SHARD)) tools/carla_lane_oracle
	@$(if $(filter-out 1/%,$(TOOLS_SHARD)),:,python3 tools/carla_lane_oracle/spiral_moments.py --check)
	@$(if $(filter-out 1/%,$(TOOLS_SHARD)),:,$(MAKE) --no-print-directory repository-check)

# The negative-fixture manifest names exactly tests/compile_fail, no job
# regenerates it, the recorded three.js fixture hashes match, the gallery
# draws every example, and CI guards each job with its planner flag. These
# read repository files that the Mojo suite cache does not track, so they run
# here.
repository-check:
	@$(MOJO) run $(MOJOFLAGS) tools/compile_fail.mojo --check-repository
	@$(MOJO) run $(MOJOFLAGS) tools/fixture_manifest.mojo
	@$(TOOL) example_inputs --check-repository
	@$(TOOL) ci_scope check-workflow

# Native source-to-source regression: compile first, then enforce the normal
# five-second limit on each executed test. test-tools remains compiler-free.
test-coverage-tool:
	@python3 tools/check_coverage_grouping.py --mojo $(MOJO)
	@python3 tools/check_coverage_protocol.py --mojo $(MOJO)
	@$(TOOL) check_coverage_sources --mojo $(MOJO)
	@$(TOOL) check_coverage_loops --mojo $(MOJO)
	@python3 tools/check_coverage_loop_proofs.py --mojo $(MOJO)
	@python3 tools/check_coverage_hit_profile.py --mojo $(MOJO)

# Subprocess-only contracts need native children with different environments.
# Metal kernels as AIR, emitted for a Metal target without a GPU or Apple's
# toolchain. A call whose types differ from its callee's crashes Apple's
# linker with only "failed to compile metallib" (modular/modular#7238).
check-gpu-air:
	@$(TOOL) check_air_calls --mojo $(MOJO)

test-portability:
	@$(TOOL) check_portability --mojo $(MOJO)
