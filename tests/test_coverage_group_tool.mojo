# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A coverage group shares one deadline and stops when the time is gone."""

from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program


def _run(script: String, seconds: Float64) raises -> Int:
    """Run one shell script under the built tool and return its status."""
    var ran = run_program(["sh", "-c", script], seconds, merge_errors=False)
    return ran.status


def test_a_finished_command_keeps_its_status() raises:
    var mojo = tool_mojo()
    var status = _run(
        "sh tools/tool.sh " + mojo + " coverage_group --seconds 2 -- true",
        10,
    )
    assert_equal(status, 0)


def test_a_past_deadline_exits_124() raises:
    var mojo = tool_mojo()
    var status = _run(
        "THREEMOJO_COVERAGE_DEADLINE=1 sh tools/tool.sh "
        + mojo
        + " coverage_group --seconds 10 -- true",
        10,
    )
    assert_equal(status, 124)


def test_the_alarm_stops_a_slow_command() raises:
    var mojo = tool_mojo()
    var status = _run(
        "sh tools/tool.sh " + mojo + " coverage_group --seconds 0.3 -- sleep 5",
        4,
    )
    assert_equal(status, 142)
    var usage = run_program(
        ["sh", "tools/tool.sh", mojo, "coverage_group"],
        20,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_true(usage.errors.find("usage: coverage_group ") >= 0)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_group"],
        120,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
