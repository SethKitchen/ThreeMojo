# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CCD oracle reproduces the saved entry-time fixtures."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tools.physics_ccd_reference import (
    DD,
    Case,
    INSIDE,
    MISS,
    check,
    oracle,
)

comptime FIXTURE = "docs/validation/continuous-collision-292-reference.json"


def test_the_saved_fixtures_reproduce() raises:
    var outcome = check(FIXTURE)
    assert_equal(outcome[0], 0, outcome[1])
    assert_equal(
        outcome[1], "23 independent double-double CCD references reproduced\n"
    )


def test_a_changed_time_or_input_is_a_mismatch() raises:
    var text = Path(FIXTURE).read_text()
    var directory = mkdtemp()
    for change in [
        ("0.0984988668292722", "0.0984988668292723"),
        ('"feature": "edge"', '"feature": "edge", "extra": 1'),
        ("-6.404607772827148", "-6.404607772827149"),
    ]:
        var path = directory + "/fixture.json"
        Path(path).write_text(text.replace(change[0], change[1]))
        assert_equal(check(path)[0], 1, change[0])
    # Labels are metadata: a changed label still reproduces.
    var path = directory + "/labels.json"
    Path(path).write_text(text.replace('"feature": "edge"', '"feature": "x"'))
    assert_equal(check(path)[0], 0)


def test_double_double_keeps_the_rounding_error() raises:
    var third = DD(1.0) / DD(3.0)
    var back = third * DD(3.0) - DD(1.0)
    assert_true(abs(back.hi) < 1e-31)
    assert_true((DD(1.0) + DD(1e-20)) > DD(1.0))
    assert_true(DD(1.0) - DD(1e-40) < DD(1.0))


def test_the_oracle_reports_overlap_backface_and_entry() raises:
    var triangle: List[List[Float64]] = [
        [0.0, 0.0, 0.0],
        [4.0, 0.0, 0.0],
        [0.0, 4.0, 0.0],
    ]
    # A unit sphere falls onto the triangle's face from z = 3.
    var entry = oracle(
        Case([1.0, 1.0, 3.0], [0.0, 0.0, -4.0], 1.0, triangle.copy())
    )
    assert_true(abs(entry - 0.5) < 1e-15)
    assert_equal(
        oracle(Case([1.0, 1.0, 0.5], [0.0, 0.0, -4.0], 1.0, triangle.copy())),
        INSIDE,
    )
    assert_equal(
        oracle(Case([1.0, 1.0, -3.0], [0.0, 0.0, 4.0], 1.0, triangle.copy())),
        MISS,
    )
    assert_equal(
        oracle(Case([1.0, 1.0, 3.0], [0.0, 0.0, 1.0], 1.0, triangle.copy())),
        MISS,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
