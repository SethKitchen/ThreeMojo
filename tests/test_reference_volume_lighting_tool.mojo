# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The volume-light reference agrees with its saved r186 fixture.

The fixture's digits came from the Python reference that the tool replaces.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tools.reference_volume_lighting import (
    compare,
    distance_attenuation,
    f,
    i,
    larger,
    run,
    smaller,
)


def test_the_saved_fixture_matches() raises:
    var outcome = run(".", False)
    assert_equal(outcome[0], 0, outcome[1])
    assert_equal(
        outcome[1],
        (
            "checked 5 direct cases and 20 ray scenes:"
            " assets/volume_lighting/r186.json\n"
        ),
    )


def test_floats_compare_within_the_tolerance() raises:
    assert_equal(compare('{"a": [1.0, 2]}', '{"a": [1.00000000000001, 2]}'), "")
    assert_equal(compare("[0.5]", "[1]"), "line 1: 1 != 0.5")
    # An int must be the same int, and a float accepts an int.
    assert_equal(compare("[0]", "[0.0]"), "line 1: 0.0 != 0")
    assert_equal(compare("[1.0]", "[1]"), "")
    assert_equal(compare("[1.0]", "[1.0, 2]"), "line 1: , != ]")
    assert_equal(compare("[true]", "[true]\n"), "")
    assert_equal(compare("[1]", "[1] 2"), "the fixture's structure differs")


def test_min_and_max_keep_python_int_results() raises:
    # min(1, 1.0) is the int 1, and 1 - max(0, 1) is the int 0.
    var top = i(1) - larger(i(0), smaller(i(1), f(1.0)))
    assert_true(top.whole)
    assert_equal(top.value, 0.0)
    assert_false((i(1) - larger(i(0), smaller(i(1), f(0.5)))).whole)


def test_attenuation_cuts_off_smoothly() raises:
    assert_equal(distance_attenuation(f(2.0), i(2), i(0)).value, 0.25)
    assert_equal(distance_attenuation(f(8.0), i(2), i(8)).value, 0.0)
    # The 0.01 floor stops a light at its own position from diverging.
    assert_equal(distance_attenuation(f(0.0), i(2), i(0)).value, 100.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
