# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The exact animation clock controls in assets/animation/ are current."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tools.reference_animation_loops import (
    Case,
    PATH,
    controls,
    exact,
    outcome,
    rounded,
)


def test_the_saved_controls_match_the_exact_oracle() raises:
    var made = controls()
    assert_equal(made[0], 3579)
    assert_true(
        Path("assets/animation/loop_reference.txt").read_text() == made[1]
    )


def test_rounding_and_decoding_are_inverse() raises:
    for bits in [
        0,
        1,
        0x007FFFFF,
        0x00800000,
        0x3F800000,
        0x7F7FFFFF,
        0x80000001,
        0xBF800000,
    ]:
        assert_equal(rounded(exact(bits)), bits)


def test_a_large_step_keeps_the_exact_loop_count() raises:
    # A 1.5 second clip advanced by 2**25 seconds stores phase 0.5 and
    # loop count 22,369,621, as the Animation wiki page states.
    var result = outcome(
        Case(0x3FC00000, 0, 0x4C000000, 0x3F800000, 1, -1, 1, 0)
    )
    assert_equal(result[0], 0)
    assert_equal(result[1], 0x3F000000)
    assert_equal(result[3], 22369621)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
