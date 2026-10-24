# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The lint log and the format id match the old Python text."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tools._process import run_program, shell_quote
from tools.shell_log import (
    command_line,
    join_words,
    limit_line,
    start_line,
    utc_stamp,
    uuid4_hex,
)


def _words(items: List[String]) -> List[String]:
    """Return a list of the given words."""
    var words = List[String]()
    for item in items:
        words.append(item)
    return words^


def test_words_are_quoted_as_a_shell_command() raises:
    var words = _words(["a", "b c", "it's"])
    assert_equal(
        join_words(words), "a " + shell_quote("b c") + " " + shell_quote("it's")
    )
    assert_equal(command_line(words), "command: " + join_words(words))
    assert_equal(join_words(List[String]()), "")
    assert_equal(command_line(List[String]()), "command: ")


def test_a_long_line_keeps_4084_code_points() raises:
    var body = String()
    var count = 0
    while count < 4096:
        body += "a"
        count += 1
    assert_equal(limit_line(body), body)
    var suffix = " [truncated]"
    var longer = body + "é"
    var cut = limit_line(longer)
    assert_true(cut.endswith(suffix))
    assert_equal(cut.byte_length(), 4084 + suffix.byte_length())
    var marks = String()
    var expected = String()
    var marks_count = 0
    while marks_count < 4097:
        marks += "é"
        if marks_count < 4084:
            expected += "é"
        marks_count += 1
    assert_equal(limit_line(marks), expected + " [truncated]")


def test_a_start_line_carries_the_utc_time_and_the_command() raises:
    var line = start_line("lint-build-start:", _words(["mojo", "a b"]))
    var stamp = utc_stamp()
    assert_equal(stamp.byte_length(), 20)
    assert_equal(String(stamp[byte=10:11]), "T")
    assert_true(stamp.endswith("Z"))
    assert_true(line.startswith(String(stamp[byte=:10])))
    assert_true(line.find(" lint-build-start: mojo 'a b'") >= 0)


def test_uuid4_is_32_hex_digits_with_version_and_variant() raises:
    var first = uuid4_hex()
    var second = uuid4_hex()
    assert_equal(first.byte_length(), 32)
    assert_equal(second.byte_length(), 32)
    assert_true(first != second)
    var digits = "0123456789abcdef".as_bytes()
    for byte in first.as_bytes():
        var found = False
        for digit in digits:
            if byte == digit:
                found = True
                break
        assert_true(found)
    assert_equal(String(first[byte=12:13]), "4")
    var variant = String(first[byte=16:17])
    assert_true(
        variant == "8" or variant == "9" or variant == "a" or variant == "b"
    )


def test_the_makefile_no_longer_calls_python_for_these_lines() raises:
    var source = Path("Makefile").read_text()
    assert_equal(source.find("python3 -c"), -1)
    assert_equal(source.find("import uuid"), -1)
    assert_true(source.find("$(TOOL) shell_log uuid") >= 0)
    assert_true(
        source.find("$$THREEMOJO_SHELL_LOG start lint-build-start:") >= 0
    )
    assert_true(source.find("$$THREEMOJO_SHELL_LOG start lint-doc-start:") >= 0)
    assert_true(source.find('$$THREEMOJO_SHELL_LOG command "$$@"') >= 0)


def test_the_program_prints_each_line_and_refuses_a_bad_request() raises:
    var program = "/tmp/shell-log"
    var ident = run_program([program, "uuid"], 10, merge_errors=False)
    assert_equal(ident.status, 0, ident.errors)
    assert_equal(ident.output.byte_length(), 33)
    assert_equal(ident.errors, "")
    var command = run_program(
        [program, "command", "a", "b c"], 10, merge_errors=False
    )
    assert_equal(command.status, 0)
    assert_equal(command.output, "")
    assert_equal(command.errors, "command: a 'b c'\n")
    var started = run_program(
        [program, "start", "lint-doc-start:", "mojo"], 10, merge_errors=False
    )
    assert_equal(started.status, 0, started.errors)
    assert_true(started.output.find(" lint-doc-start: mojo\n") >= 0)
    var missing = run_program([program], 10, merge_errors=False)
    assert_equal(missing.status, 2)
    assert_true(missing.errors.startswith("shell_log: usage:"))
    var unknown = run_program([program, "nope"], 10, merge_errors=False)
    assert_equal(unknown.status, 2)
    assert_true(unknown.errors.find("unknown argument nope") >= 0)


def main() raises:
    var built = run_program(
        [
            ".venv/bin/mojo",
            "build",
            "-I",
            ".",
            "--Werror",
            "-o",
            "/tmp/shell-log",
            "tools/shell_log.mojo",
        ],
        120,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
