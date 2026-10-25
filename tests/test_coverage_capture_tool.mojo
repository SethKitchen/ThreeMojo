# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A coverage capture keeps each probe record once."""

from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program, shell_quote


def _capture(script: String, seconds: Float64) raises -> Int:
    """Run one shell script under the capture tool."""
    var ran = run_program(["sh", "-c", script], seconds, merge_errors=False)
    return ran.status


def test_duplicate_probes_are_kept_once() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "out=$(mktemp); err=$(mktemp).txt.gz; sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" -- sh -c '
            + "'printf"
            ' "hello\\nCOVLINE:module:2:T\\nCOVLINE:module:2:T\\nCOVBRANCH:module:3:T\\nnote\\n"'
            " >&2' >/tmp/coverage-capture-progress.$$"
            + '; status=$?; gzip -dc "$err"; exit $status',
        ],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 0)
    assert_equal(
        ran.output,
        "hello\nCOVLINE:module:2:T\nCOVLINE:module:3:T\nCOVBRANCH:module:3:T\nnote\n",
    )


def test_a_past_deadline_exits_124() raises:
    var status = _capture(
        "out=$(mktemp); err=$(mktemp).txt.gz; THREEMOJO_COVERAGE_DEADLINE=1 sh"
        " tools/tool.sh "
        + shell_quote(tool_mojo())
        + ' coverage_io capture --out "$out" --err "$err" -- true',
        20.0,
    )
    assert_equal(status, 124)


def test_a_short_deadline_stops_sleep() raises:
    var status = _capture(
        "out=$(mktemp); err=$(mktemp).txt.gz; d=$(python3 -c 'import time;"
        " print(repr(time.monotonic()+0.3))'); "
        + "THREEMOJO_COVERAGE_DEADLINE=$d sh tools/tool.sh "
        + shell_quote(tool_mojo())
        + ' coverage_io capture --out "$out" --err "$err" -- sleep 5',
        20.0,
    )
    assert_equal(status, 124)


def test_report_replays_captures_in_name_order() raises:
    var ran = run_program(
        [
            "sh",
            "-c",
            "dir=$(mktemp -d); printf 'hello\\n' | gzip -n -1 >"
            ' "$dir/b.txt.gz"; '
            + "printf 'world\\n' | gzip -n -1 > \"$dir/a.txt.gz\"; "
            + "sh tools/tool.sh "
            + shell_quote(tool_mojo())
            + ' coverage_io report --capture-dir "$dir" -- python3 -c '
            + "'import sys\n"
            + "for path in sys.argv[1:]:\n"
            + '    handle = open(path, "rb")\n'
            + "    sys.stdout.buffer.write(handle.read())\n"
            + "    handle.close()\n'",
        ],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 0)
    assert_equal(ran.output, "world\nhello\n")


def test_progress_reports_the_first_probe_and_a_running_line() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "out=$(mktemp); err=$(mktemp).txt.gz; sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --progress-seconds 0.02 --out "$out"'
            + ' --err "$err" -- sh -c \'printf "COVLINE:m:1:T\\n" >&2;'
            + " sleep 0.12'",
        ],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 0)
    assert_true(ran.output.find("start;") >= 0)
    assert_true(ran.output.find("waiting for probes") >= 0)
    assert_true(ran.output.find("first probe;") >= 0)
    assert_true(ran.output.find("runtime probes observed") >= 0)
    assert_true(ran.output.find("running;") >= 0)
    assert_true(ran.output.find("complete (exit 0)") >= 0)


def test_a_missing_command_prints_aborted() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "out=$(mktemp); err=$(mktemp).txt.gz; sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" --'
            + " /no/such/coverage-command",
        ],
        20.0,
        merge_errors=False,
    )
    assert_true(ran.status != 0)
    assert_true(ran.output.find("aborted;") >= 0)


def test_usage_exits_2() raises:
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "coverage_io"],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 2)
    assert_true(ran.errors.find("usage: coverage_io capture ") >= 0)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_io"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
