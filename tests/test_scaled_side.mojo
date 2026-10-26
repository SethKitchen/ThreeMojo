# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A side times a `Float32` scale: the whole sizes JavaScript gets, and
every whole side past 2^24."""

from math.utils import EXACT_SIDES, scaled_side
from postprocessing.display_nodes import scaled_size
from postprocessing.shaders import god_rays_size
from renderers.ascii_effect import ascii_size
from std.testing import TestSuite, assert_equal


def test_an_ordinary_side_scales_to_javascripts_size() raises:
    # 0.9 and 0.7 are stored a little low. The `Float32` products round
    # back up to the whole sizes.
    assert_equal(scaled_side(1000, 0.9), 900)
    assert_equal(scaled_side(-1000, 0.9), -900)
    assert_equal(god_rays_size(1000, 0.9), 900)
    assert_equal(god_rays_size(10, 0.7), 7)
    assert_equal(ascii_size(1000, 0.9), 900)
    assert_equal(scaled_size(5, 0.9), 5)


def test_a_side_past_two_to_the_24_keeps_its_whole_value() raises:
    var odd = EXACT_SIDES * 4 + 1
    assert_equal(scaled_side(odd, 1), Float64(odd))
    assert_equal(scaled_side(-odd, 1), Float64(-odd))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
