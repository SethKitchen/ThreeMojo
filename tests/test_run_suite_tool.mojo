# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Each test of a suite has a time limit, and only complete results pass.

The suites here are small shell programs that print what `TestSuite`
prints. Each run gets a private temporary directory that is removed after
any outcome.
"""

from std.os import getenv, setenv, unsetenv
from std.os.path import realpath
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._process import run_program
from tools.run_suite import (
    TIMED_OUT,
    budget,
    count_tests,
    fixed,
    general,
    parse_options,
    result_errors,
    run,
    slow_tests,
    strip_color,
)

comptime OUTPUT = (
    "\x1b[92mRunning\x1b[0m 3 tests for tests/test_a.mojo\n"
    "    \x1b[92mPASS\x1b[0m [ 4999.000 ] test_fast\n"
    "    \x1b[91mFAIL\x1b[0m [ 5000.500 ] test_slow\n"
    "    PASS [ 12.000 ] test_quick\n"
    "--------\n"
    "Summary [ 10011.500 ] 3 tests run: 2 passed , 1 failed , 0 skipped\n"
)


def _success(name: String = "test_a", milliseconds: Int = 1) -> String:
    """Return the output of a suite whose one test passed."""
    return (
        "Running 1 tests for suite.mojo\n    PASS [ "
        + String(milliseconds)
        + ".0 ] "
        + name
        + "\nSummary [ 1.0 ] 1 tests run: 1 passed , 0 failed , 0 skipped"
    )


def _program(
    output: String, status: Int = 0, before: String = ""
) -> List[String]:
    """Return a shell program that runs `before`, prints, and exits."""
    return [
        "sh",
        "-c",
        before + 'printf "%s\\n" "$1"; exit ' + String(status),
        "suite",
        output,
    ]


def _run(
    seconds: Float64, var program: List[String]
) raises -> Tuple[Int, String]:
    """Run a program as a suite that defines one test."""
    var tree = Tree()
    tree.write("test_a.mojo", "def test_a():\n    pass\n")
    var arguments: List[String] = [
        "--seconds",
        String(seconds),
        "--suite",
        tree.root + "/test_a.mojo",
        "--",
    ]
    arguments.extend(program^)
    var outcome = run(parse_options(arguments))
    tree.close()
    return outcome^


def _results_only(var program: List[String]) raises -> Int:
    """Run a program with `--results-only`, and return the status."""
    var arguments: List[String] = [
        "--results-only",
        "--suite",
        "unused.mojo",
        "--",
    ]
    arguments.extend(program^)
    return run(parse_options(arguments))[0]


def test_results_only_keeps_the_output_and_child_failure_checks() raises:
    assert_equal(_results_only(_program("", 0)), 1)
    assert_equal(_results_only(_program("FAIL [ 1.0 ] test_bad", 0)), 1)
    assert_equal(
        _results_only(
            _program("SKIP (no accelerator): test_a\n" + _success(), 0)
        ),
        0,
    )
    assert_equal(_results_only(_program(_success(milliseconds=6000), 0)), 0)
    assert_equal(_results_only(_program(_success(), 7)), 7)


def test_counts_only_test_functions() raises:
    var text = (
        "def test_a() raises:\n    pass\n\ndef helper():\n    pass\n"
        + "def test_b():\n    pass\n    def test_nested():\n        pass\n"
        + "def\ttest_c (x: Int):\n    pass\n# def test_d():\ndef test_e\n"
    )
    assert_equal(count_tests(text), 3)


def test_reports_each_result_over_the_limit() raises:
    var slow = slow_tests(OUTPUT, 5.0)
    assert_equal(len(slow), 1)
    assert_equal(slow[0].name, "test_slow")
    assert_equal(slow[0].milliseconds, 5000.5)
    assert_equal(len(slow_tests(OUTPUT, 6.0)), 0)


def test_the_budget_covers_every_test_and_startup() raises:
    assert_equal(budget(5.0, 3), 20.0)
    assert_equal(budget(5.0, 0), 10.0)


def test_numbers_are_written_as_python_wrote_them() raises:
    assert_equal(general(5.0), "5")
    assert_equal(general(0.1), "0.1")
    assert_equal(general(0.2), "0.2")
    assert_equal(fixed(5.0005), "5.00")
    assert_equal(fixed(12.345), "12.35")
    assert_equal(fixed(0.04), "0.04")


def test_passes_a_fast_suite() raises:
    var outcome = _run(5, _program(_success()))
    assert_equal(outcome[0], 0, outcome[1])
    assert_true(outcome[1].startswith("Running 1 tests"))


def test_fails_a_slow_test() raises:
    var outcome = _run(5, _program(_success(milliseconds=5001)))
    assert_equal(outcome[0], 1)
    assert_true(
        outcome[1].endswith(
            ": test_a took 5.00s, over the 5s limit for one test.\n"
        )
    )


def test_keeps_the_suite_exit_code() raises:
    assert_equal(_run(5, ["sh", "-c", "exit 3"])[0], 3)


def test_stops_a_hung_suite() raises:
    var outcome = _run(0.1, ["sh", "-c", "sleep 5"])
    assert_equal(outcome[0], TIMED_OUT)
    assert_true(
        outcome[1].endswith(
            "stopped after 0.2s. A test hangs or takes longer than 0.1s.\n"
        )
    )


def test_the_private_directory_is_removed_after_every_outcome() raises:
    var tree = Tree()
    var marker = tree.root + "/root.txt"
    var setup = (
        '[ "$THREEMOJO_TEST_TMPDIR" = "$TMPDIR" ] || exit 9; '
        + 'printf "%s" "$THREEMOJO_TEST_TMPDIR" > "$2"; '
        + 'printf fixture > "$TMPDIR/fixture.bin"; '
    )
    var cases = [
        (_success(), 0, 5.0, 0),
        (String(), 3, 5.0, 3),
    ]
    for entry in cases:
        var program = _program(entry[0], entry[1], setup)
        program.append(marker)
        assert_equal(_run(entry[2], program^)[0], entry[3])
        var root = tree.read("root.txt")
        assert_true(root.byte_length() > 0)
        assert_false(Path(root).exists(), root)
    var hung: List[String] = [
        "sh",
        "-c",
        setup + "sleep 5",
        "suite",
        "",
        marker,
    ]
    assert_equal(_run(0.1, hung^)[0], TIMED_OUT)
    assert_false(Path(tree.read("root.txt")).exists())
    tree.close()


def test_the_private_directory_is_under_tmpdir_and_resolved() raises:
    var tree = Tree()
    tree.write("parent/.keep", "")
    _ = run_program(
        ["ln", "-s", tree.root + "/parent", tree.root + "/alias"], 10
    )
    var saved = getenv("TMPDIR")
    _ = setenv("TMPDIR", tree.root + "/alias")
    var program: List[String] = [
        "sh",
        "-c",
        'printf "%s" "$TMPDIR" > "$1"; printf "%s\\n" "$2"',
        "suite",
        tree.root + "/root.txt",
        _success(),
    ]
    var outcome = _run(5, program^)
    if saved:
        _ = setenv("TMPDIR", saved)
    else:
        _ = unsetenv("TMPDIR")
    assert_equal(outcome[0], 0, outcome[1])
    var root = tree.read("root.txt")
    var parent = realpath(tree.root + "/parent")
    assert_true(root.startswith(parent + "/threemojo-test-"), root)
    assert_false(Path(root).exists())
    var left = run_program(["ls", "-A", tree.root + "/parent"], 10)
    assert_equal(left.output, ".keep\n")
    tree.close()


def test_an_empty_or_failed_zero_exit_cannot_pass() raises:
    assert_equal(_run(5, ["sh", "-c", "true"])[0], 1)
    assert_equal(_run(5, _program("    FAIL [ 1.0 ] test_a"))[0], 1)


def test_complete_colored_results_are_required() raises:
    assert_equal(len(result_errors(_success())), 0)
    assert_equal(
        len(result_errors(_success().replace("PASS", "\x1b[92mPASS\x1b[0m"))), 0
    )
    assert_true(len(result_errors(OUTPUT)) > 0)
    var lines = _success().split("\n")
    var reversed = (
        String(lines[2]) + "\n" + String(lines[1]) + "\n" + String(lines[0])
    )
    for broken in [
        String(),
        String("Running 1 tests for suite.mojo"),
        String(_success()[byte = : _success().find("Summary")]),
        _success().replace("Running 1", "Running 2"),
        reversed,
        _success().replace("1 passed", "0 passed"),
        _success().replace("1 tests run", "2 tests run"),
        _success().replace("    PASS [ 1.0 ] test_a\n", ""),
        _success() + "\n" + _success(),
        String(
            "Running 0 tests for suite.mojo\n"
            "Summary [ 0.0 ] 0 tests run: 0 passed , 0 failed , 0 skipped"
        ),
        _success().replace("PASS [ 1.0 ]", "PASS [ nan ]"),
    ]:
        assert_true(len(result_errors(broken)) > 0, broken)


def test_runtime_counts_can_include_imported_tests() raises:
    var output = (
        "Running 2 tests for suite.mojo\n"
        + "PASS [ 1.0 ] test_a\nPASS [ 2.0 ] test_imported\n"
        + "Summary [ 3.0 ] 2 tests run: 2 passed , 0 failed , 0 skipped"
    )
    # The suite's source defines one test; the run reports two.
    assert_equal(_run(5, _program(output))[0], 0)


def test_skips_and_device_notices_keep_their_own_policy() raises:
    var skipped = (
        "Running 1 tests for suite.mojo\nSKIP [ 0.0 ] test_device\n"
        + "Summary [ 0.0 ] 1 tests run: 0 passed , 0 failed , 1 skipped"
    )
    assert_equal(len(result_errors(skipped)), 0)
    assert_equal(
        len(result_errors("SKIP (no accelerator): device test\n" + _success())),
        0,
    )


def test_color_codes_are_removed() raises:
    assert_equal(strip_color("\x1b[1;92mPASS\x1b[0m [x\x1b[m"), "PASS [x")
    assert_equal(strip_color("\x1b[92 kept"), "\x1b[92 kept")


def test_the_command_line_needs_one_mode_a_suite_and_a_program() raises:
    with assert_raises(contains="one of --seconds and --results-only"):
        _ = parse_options(["--suite", "a.mojo", "--", "true"])
    with assert_raises(contains="one of --seconds and --results-only"):
        _ = parse_options(
            ["--seconds", "5", "--results-only", "--suite", "a.mojo", "true"]
        )
    with assert_raises(contains="give --suite and a program"):
        _ = parse_options(["--seconds", "5", "--", "true"])
    with assert_raises(contains="give --suite and a program"):
        _ = parse_options(["--seconds", "5", "--suite", "a.mojo"])
    with assert_raises(contains="must not be negative"):
        _ = parse_options(["--seconds", "-1", "--suite", "a.mojo", "true"])
    with assert_raises(contains="unknown option"):
        _ = parse_options(["--fast", "--suite", "a.mojo", "true"])
    var options = parse_options(
        ["--seconds", "2.5", "--suite", "a.mojo", "--", "x", "--y"]
    )
    assert_equal(options.seconds, 2.5)
    assert_equal(" ".join(options.command), "x --y")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
