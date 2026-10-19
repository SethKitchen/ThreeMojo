# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exercise the GPU compile-only Make recipes without invoking Mojo.

Each test copies the maintained recipes and GPU lists from the `Makefile`
into a temporary project. A shell script stands in for the compiler.
"""

from std.collections import Set
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._make_recipe import (
    LOG_ARGUMENTS,
    clean_command,
    read_calls,
    section,
)
from tools.compile_fail import shell_split
from tools._process import ProcessResult, run_program, shell_quote

comptime GPU_ENTRIES = [
    "tests/test_gpu.mojo",
    "tests/test_gpu_water.mojo",
    "tests/test_gpu_layout.mojo",
    "tests/test_gpu_volume_packing.mojo",
    "tests/test_capi_water_gpu.mojo",
    "bench/raster_bench.mojo",
    "bench/water_gpu_bench.mojo",
    "bench/hair_frame_bench.mojo",
    "tools/gpu_status.mojo",
]
"""The maintained GPU entry points."""

comptime GPU_LIBRARIES = [
    "render/gpu.mojo",
    "render/gpu_vxgi.mojo",
    "extensions/water/gpu.mojo",
    "window/capi_water_gpu.mojo",
]
"""The maintained GPU library modules."""


@fieldwise_init
struct Outcome(Movable):
    """What the recipes did."""

    var results: List[ProcessResult]
    """Each make run's result."""
    var calls: List[List[String]]
    """Each compiler call's arguments."""
    var stamps: Set[String]
    """The stamp files left."""


def _gpu_lists(source: String) -> String:
    """Return the `GPU_...` list assignments, with continuations joined."""
    var joined = source.replace("\\\n", " ")
    var out = List[String]()
    for line in joined.splitlines():
        var text = String(line)
        for name in [
            "GPU_LIB_SOURCES",
            "GPU_HOST_TESTS",
            "GPU_TESTS",
            "GPU_ENTRY_POINTS",
        ]:
            if text.startswith(name):
                var rest = String(text[byte = name.byte_length() :]).lstrip()
                if rest.startswith(":="):
                    out.append(text)
    return "\n".join(out)


def _gpu_inputs(extra_entry: Bool) -> String:
    """Supply source inventories for the Makefile's GPU naming filters."""
    var libraries = List[String]()
    for name in materialize[GPU_LIBRARIES]():
        libraries.append(name)
    libraries.extend(
        [
            "render/gpgpu_sort.mojo",
            "render/gpu/helper.mojo",
            "window/capi_gpu_host.mojo",
        ]
    )
    var tests = List[String]()
    for name in materialize[GPU_ENTRIES]():
        if name.startswith("tests/"):
            tests.append(name)
    tests.extend(
        [
            "tests/test_cpu.mojo",
            "tests/test_gpu_new_device.mojo",
            "tests/test_new_device_gpu_helper.mojo",
        ]
    )
    if extra_entry:
        tests.append("tests/test_new_device_gpu.mojo")
    return (
        "LIB_SOURCES := "
        + " ".join(libraries)
        + "\nTESTS := "
        + " ".join(tests)
        + "\n"
    )


def run_recipe(
    targets: List[String],
    failed_source: String = "",
    extra_entry: Bool = False,
    outer: Bool = False,
) raises -> Outcome:
    var source = Path("Makefile").read_text()
    var recipe = section(
        source, "compile-gpu: $(COMPILE_GPU_STAMP)\n", "\n# mojo format"
    )
    var root = mkdtemp(prefix="gpu compile ")
    Path(root + "/compiler.sh").write_text(
        LOG_ARGUMENTS
        + 'for last in "$@"; do :; done\n'
        + "failed="
        + shell_quote(failed_source)
        + "\n"
        + 'if [ -n "$failed" ] && [ "$last" = "$failed" ]; then\n'
        + '  echo "compile error from $last"\n'
        + "  exit 7\n"
        + "fi\n"
    )
    Path(root + "/Makefile").write_text(
        "JOBS := 1\nMOJO := sh compiler.sh\n"
        + "MOJOFLAGS := -I . --target-accelerator=sm_80\n"
        + "COMPILE_GPU_STAMP := compile-gpu-stamp\n"
        + "LINT_GPU_STAMP := lint-gpu-stamp\n"
        + "stamp = touch $(1)-stamp\n"
        + _gpu_inputs(extra_entry)
        + _gpu_lists(source)
        + "\n"
        + recipe
        + "\n"
    )
    var results = List[ProcessResult]()
    # Parent make overrides must never replace the harmless stub.
    for target in targets:
        var command: List[String] = ["make", "-s"]
        command.extend(shell_split(target))
        results.append(
            run_program(
                clean_command([], command, outer),
                30,
                merge_errors=False,
                directory=root,
            )
        )
    var calls = read_calls(root + "/invocations")
    var stamps = Set[String]()
    for name in ["compile-gpu-stamp", "lint-gpu-stamp"]:
        if Path(root + "/" + name).exists():
            stamps.add(name)
    _ = run_program(["rm", "-rf", root], 10)
    return Outcome(results^, calls^, stamps^)


def _set(var names: List[String]) -> Set[String]:
    var out = Set[String]()
    for name in names:
        out.add(name)
    return out^


def _entries() -> List[String]:
    var out = List[String]()
    for name in materialize[GPU_ENTRIES]():
        out.append(name)
    return out^


def test_all_entries_build_with_explicit_target_without_running() raises:
    var outcome = run_recipe(["compile-gpu"], extra_entry=True)
    ref result = outcome.results[0]
    assert_equal(result.status, 0, result.output + result.errors)
    var last = Set[String]()
    for call in outcome.calls:
        last.add(call[len(call) - 1])
    var expected = _entries()
    expected.append("tests/test_new_device_gpu.mojo")
    assert_true(last == _set(expected^))
    for call in outcome.calls:
        var head = List[String]()
        for index in range(len(call) - 1):
            head.append(call[index])
        var expected_head: List[String] = [
            "build",
            "-I",
            ".",
            "--target-accelerator=sm_80",
            "--Werror",
            "-o",
            "/dev/null",
        ]
        assert_true(head == expected_head)
    assert_true(outcome.stamps == _set(["compile-gpu-stamp"]))
    assert_true(result.output.find("compiled (not run)") >= 0)


def _fails_without_stamping(entry: String) raises:
    var outcome = run_recipe(["compile-gpu"], failed_source=entry)
    ref result = outcome.results[0]
    assert_true(result.status != 0, entry)
    assert_true(result.output.find("compile error from " + entry) >= 0, entry)
    assert_equal(len(outcome.stamps), 0, entry)
    assert_equal(result.output.find("compiled (not run)"), -1, entry)


def test_any_entry_compile_error_fails_without_stamping() raises:
    for entry in materialize[GPU_ENTRIES]():
        _fails_without_stamping(entry)


def test_cache_hit_skips_build_and_force_rebuilds() raises:
    var outcome = run_recipe(["compile-gpu", "compile-gpu", "-B compile-gpu"])
    for index in range(len(outcome.results)):
        ref result = outcome.results[index]
        assert_equal(result.status, 0, result.output + result.errors)
    assert_equal(len(outcome.calls), 2 * len(materialize[GPU_ENTRIES]()))
    assert_equal(outcome.results[1].output.find("compiled (not run)"), -1)
    assert_true(outcome.results[2].output.find("compiled (not run)") >= 0)
    assert_true(outcome.stamps == _set(["compile-gpu-stamp"]))


def test_lint_reuses_the_compile_step_and_still_checks_library_docs() raises:
    var outcome = run_recipe(['lint-gpu MOJOFLAGS="-I ."'])
    ref result = outcome.results[0]
    assert_equal(result.status, 0, result.output + result.errors)
    var entries = len(materialize[GPU_ENTRIES]())
    var libraries = len(materialize[GPU_LIBRARIES]())
    assert_equal(len(outcome.calls), entries + libraries)
    for index in range(len(outcome.calls)):
        assert_equal(
            outcome.calls[index][0], "build" if index < entries else "doc"
        )
    var docs = Set[String]()
    for call in outcome.calls:
        if call[0] == "doc":
            docs.add(call[len(call) - 1])
    var expected = List[String]()
    for name in materialize[GPU_LIBRARIES]():
        expected.append(name)
    assert_true(docs == _set(expected^))
    assert_true(outcome.stamps == _set(["compile-gpu-stamp", "lint-gpu-stamp"]))
    for call in outcome.calls:
        assert_equal(call[1], "-I")
        assert_equal(call[2], ".")
        for word in call:
            assert_true(word != "--target-accelerator=sm_80")


def test_failed_compile_also_blocks_lint_docs_and_success_stamp() raises:
    var outcome = run_recipe(["lint-gpu"], failed_source="tests/test_gpu.mojo")
    ref result = outcome.results[0]
    assert_true(result.status != 0)
    for call in outcome.calls:
        assert_equal(call[0], "build")
    assert_equal(len(outcome.stamps), 0)
    assert_equal(result.output.find("No warnings (GPU)"), -1)


def test_outer_make_overrides_cannot_replace_the_fixture_compiler() raises:
    var outcome = run_recipe(["compile-gpu"], outer=True)
    ref result = outcome.results[0]
    assert_equal(result.status, 0, result.output + result.errors)
    assert_equal(len(outcome.calls), len(materialize[GPU_ENTRIES]()))
    assert_true(outcome.stamps == _set(["compile-gpu-stamp"]))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
