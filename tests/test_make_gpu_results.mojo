# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The GPU suite recipes pass only complete, passing results.

Each test copies one GPU recipe from the Makefile into a small project. A
stand-in for `mojo run` prints the given output and exits with the given
status. No GPU and no Mojo compiler is used.
"""

from std.os import getenv, setenv, unsetenv
from std.os.path import isfile
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from tests._tree import Tree, copy_suite_runner, tool_mojo
from tools._process import ProcessResult, run_program

comptime PASS = (
    "Running 1 tests for stub.mojo\nPASS [ 1.0 ] test_stub\n"
    "Summary [ 1.0 ] 1 tests run: 1 passed , 0 failed , 0 skipped\n"
)


def _fail() -> String:
    """Return the output of a suite whose one test failed."""
    return (
        String(PASS)
        .replace("PASS [", "FAIL [")
        .replace("1 passed , 0 failed", "0 passed , 1 failed")
    )


def _run(
    device: Bool, output: String, status: Int
) raises -> Tuple[ProcessResult, Bool]:
    """Run one GPU recipe, and return make's result and whether it stamped."""
    var source = Path("Makefile").read_text()
    var start: Int
    var end: Int
    var target: String
    if device:
        start = source.find("test-gpu-device:\n")
        end = source.find("\n# The GPU suites", start)
        target = "test-gpu-device"
    else:
        start = source.find("$(TEST_GPU_HOST_STAMP):\n")
        end = source.find("\ngpu-status:", start)
        target = "host"
    assert_true(start >= 0 and end > start)
    var tree = Tree()
    copy_suite_runner(tree)
    tree.write("output.txt", output)
    tree.write("stub.sh", "cat output.txt\nexit " + String(status) + "\n")
    tree.write(
        "Makefile",
        "JOBS := 1\nGPU_BUDGET := 10\nMOJO := sh stub.sh\n"
        + "TOOL_MOJO := "
        + tool_mojo()
        + "\nMOJOFLAGS :=\nGPU_HOST_TESTS := host.mojo\n"
        + "GPU_TESTS := device.mojo host.mojo\nTEST_GPU_HOST_STAMP := host\n"
        + "stamp = touch passed-stamp\n"
        + String(source[byte=start:end])
        + "\n",
    )
    var command: List[String] = ["env"]
    # A parent `make MOJO=...` exports its overrides to every child. The
    # project owns its Makefile and must use its own stand-in.
    for name in [
        "MAKEFLAGS",
        "MFLAGS",
        "MAKEOVERRIDES",
        "MAKELEVEL",
        "MAKEFILES",
        "GNUMAKEFLAGS",
    ]:
        command.append("-u")
        command.append(name)
    command.extend(["make", "-s", target])
    var result = run_program(command, 5, directory=tree.root)
    var stamped = isfile(tree.root + "/passed-stamp")
    tree.close()
    return (result^, stamped)


def test_outer_make_overrides_cannot_replace_the_stand_in() raises:
    var outer = [
        ("MAKEFLAGS", "-- MOJO=nonexistent-outer-compiler"),
        ("MAKEOVERRIDES", "MOJO=nonexistent-outer-compiler"),
        ("MFLAGS", "-e"),
        ("GNUMAKEFLAGS", "-e"),
        ("MAKEFILES", "nonexistent-outer-include"),
        ("MAKELEVEL", "7"),
    ]
    var saved = List[String]()
    for entry in outer:
        saved.append(getenv(entry[0]))
        _ = setenv(entry[0], entry[1])
    for device in [False, True]:
        var outcome = _run(device, PASS, 0)
        assert_equal(outcome[0].status, 0, outcome[0].output)
        assert_equal(outcome[1], not device)
    for index in range(len(outer)):
        if saved[index]:
            _ = setenv(outer[index][0], saved[index])
        else:
            _ = unsetenv(outer[index][0])


def test_empty_failed_and_malformed_output_cannot_pass() raises:
    for device in [False, True]:
        for output in [
            String(),
            _fail(),
            String(PASS).replace("1 tests run", "2 tests run"),
        ]:
            var outcome = _run(device, output, 0)
            assert_true(outcome[0].status != 0, output)
            assert_false(outcome[1])
            assert_true(outcome[0].output.find("suites passed.") < 0)


def test_valid_results_and_device_skip_notices_are_kept() raises:
    for device in [False, True]:
        var outcome = _run(device, "SKIP (no accelerator): notice\n" + PASS, 0)
        assert_equal(outcome[0].status, 0, outcome[0].output)
        assert_equal(outcome[1], not device)
        assert_true(
            outcome[0].output.find("SKIP (no accelerator): notice") >= 0
        )


def test_a_child_failure_is_not_hidden_by_valid_output() raises:
    for device in [False, True]:
        var outcome = _run(device, PASS, 7)
        assert_true(outcome[0].status != 0)
        assert_false(outcome[1])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
