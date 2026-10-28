# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A straight spline bend matches the reviewed Hermite frame."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_bend import bend_text


comptime _REQUEST = '{"points":[[0,0,0],[0.5,0.1,-0.2],[1,0,0]],"normals":[[0,1,0],[0,0,1],[1,0,0]],"forward_axis":0,"start":[0,0,0],"end":[100,0,0],"start_tangent":[100,0,0],"end_tangent":[100,0,0],"start_roll":0,"end_roll":0,"start_scale":[1,1],"end_scale":[1,1]}'
"""A one-meter segment on a straight 100 cm Hermite line."""
comptime _BENT = '{"points":[[0.0,0.0,0.0],[50.0,-20.0,10.0],[100.0,0.0,0.0]],"normals":[[0.0,0.0,1.0],[0.0,1.0,0.0],[1.0,0.0,0.0]]}'
"""The bent points and normals for `_REQUEST`."""


def test_a_straight_spline_keeps_the_hermite_line() raises:
    assert_equal(bend_text(_REQUEST), _BENT)
    with assert_raises():
        _ = bend_text('{"points":[],"normals":[]}')


def test_the_command_prints_the_bent_points() raises:
    var directory = mkdtemp(prefix="town bend ")
    var path = directory + "/bend.json"
    Path(path).write_text(_REQUEST)
    var result = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_bend", path],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(result.output, _BENT + "\n")
    assert_true(result.errors.find("Crashpad") < 0)
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_bend"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_bend"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
