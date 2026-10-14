# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `tools.process`: status, output order, quoting and time limit."""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from std.time import perf_counter_ns

from tools.process import run_program, shell_quote


def _sh(script: String) -> List[String]:
    """Return the arguments that run `script` in a POSIX shell."""
    var arguments = List[String]()
    arguments.append("sh")
    arguments.append("-c")
    arguments.append(script)
    return arguments^


def test_status_and_combined_output_in_order() raises:
    var result = run_program(
        _sh("echo one; echo two 1>&2; echo three; exit 3"), 10
    )
    assert_equal(result.status, 3)
    assert_equal(result.output, "one\ntwo\nthree\n")
    assert_false(result.timed_out)


def test_a_signal_is_128_plus_its_number() raises:
    var result = run_program(_sh("kill -TERM $$"), 10)
    assert_equal(result.status, 128 + 15)
    assert_false(result.timed_out)


def test_the_time_limit_stops_the_program() raises:
    var start = perf_counter_ns()
    var result = run_program(_sh("echo started; exec sleep 30"), 0.3)
    var seconds = Float64(perf_counter_ns() - start) / 1e9
    assert_true(result.timed_out)
    assert_equal(result.status, 128 + 9)
    assert_equal(result.output, "started\n")
    assert_true(seconds < 5)


def test_arguments_keep_spaces_quotes_and_empty_words() raises:
    var arguments = _sh('printf "[%s]" "$@"')
    arguments.append("sh")
    arguments.append("a b")
    arguments.append("it's")
    arguments.append("")
    arguments.append("$HOME")
    var result = run_program(arguments, 10)
    assert_equal(result.status, 0)
    assert_equal(result.output, "[a b][it's][][$HOME]")


def test_input_is_empty() raises:
    var result = run_program(_sh("cat; echo done"), 10)
    assert_equal(result.output, "done\n")


def test_a_missing_program_reports_a_failure() raises:
    var arguments = List[String]()
    arguments.append("/nonexistent/threemojo-no-such-program")
    var result = run_program(arguments, 10)
    assert_equal(result.status, 127)
    assert_true(result.output.byte_length() > 0)
    assert_false(result.timed_out)


def test_invalid_utf8_output_is_replaced() raises:
    var result = run_program(_sh("printf 'a\\377b'"), 10)
    assert_equal(result.output, "a�b")


def test_bad_requests_are_refused() raises:
    with assert_raises(contains="needs a program"):
        _ = run_program(List[String](), 10)
    with assert_raises(contains="positive time limit"):
        _ = run_program(_sh("true"), 0)
    with assert_raises(contains="positive time limit"):
        _ = run_program(_sh("true"), Float64.MAX * -1)


def test_shell_quote_matches_python() raises:
    assert_equal(shell_quote("abc-1.2/x_y@z%+=:,"), "abc-1.2/x_y@z%+=:,")
    assert_equal(shell_quote(""), "''")
    assert_equal(shell_quote("a b"), "'a b'")
    assert_equal(shell_quote("it's"), "'it'\"'\"'s'")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
