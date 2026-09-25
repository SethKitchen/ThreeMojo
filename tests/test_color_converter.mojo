# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.color_converter`.

The expected numbers come from three.js 0.180's `ColorConverter`, run in
Node on the same inputs.
"""

from render.color_converter import HSV, get_hsv, set_hsv
from render.framebuffer import FloatColor
from std.testing import TestSuite, assert_almost_equal

comptime TOLERANCE = Float64(1e-6)


def assert_rgb(got: FloatColor, r: Float32, g: Float32, b: Float32) raises:
    """Assert a color's red, green and blue, within tolerance.

    Args:
        got: The color to check.
        r: Expected red.
        g: Expected green.
        b: Expected blue.

    Raises:
        Error: If any channel differs.
    """
    assert_almost_equal(got.r, r, atol=TOLERANCE)
    assert_almost_equal(got.g, g, atol=TOLERANCE)
    assert_almost_equal(got.b, b, atol=TOLERANCE)


def assert_hsv(got: HSV, h: Float32, s: Float32, v: Float32) raises:
    """Assert hue, saturation and value, within tolerance.

    Args:
        got: The three numbers to check.
        h: Expected hue.
        s: Expected saturation.
        v: Expected value.

    Raises:
        Error: If any of the three differs.
    """
    assert_almost_equal(got.hue, h, atol=TOLERANCE)
    assert_almost_equal(got.saturation, s, atol=TOLERANCE)
    assert_almost_equal(got.value, v, atol=TOLERANCE)


def test_set_hsv_matches_three_js() raises:
    var color = FloatColor(0, 0, 0, 0.5)
    set_hsv(color, 0.3, 0.6, 0.8)
    assert_rgb(color, 0.41599999999999987, 0.8, 0.31999999999999984)
    assert_almost_equal(color.a, Float32(0.5), atol=TOLERANCE)
    set_hsv(color, 1.25, 0.5, 0.25)
    assert_rgb(color, 0.18750000000000003, 0.25, 0.125)
    # The hue wraps, and the saturation and value clamp.
    set_hsv(color, -0.25, 1.5, 1.5)
    assert_rgb(color, 0.49999999999999956, 0, 1)
    set_hsv(color, 0.6, 0, 0.5)
    assert_rgb(color, 0.5, 0.5, 0.5)
    set_hsv(color, 0.1, 1, 1)
    assert_rgb(color, 1, 0.6000000000000005, 0)


def test_black_and_white_have_no_saturation() raises:
    # three.js divides zero by zero for both and gives a color that is
    # not a number.
    var color = FloatColor(0.5, 0.5, 0.5)
    set_hsv(color, 0.3, 0.5, 0)
    assert_rgb(color, 0, 0, 0)
    set_hsv(color, 0.3, 0, 1)
    assert_rgb(color, 1, 1, 1)
    assert_hsv(get_hsv(FloatColor(0, 0, 0)), 0, 0, 0)


def test_get_hsv_matches_three_js() raises:
    assert_hsv(get_hsv(FloatColor(0.2, 0.4, 0.8)), 0.611111111111111, 0.75, 0.8)
    assert_hsv(
        get_hsv(FloatColor(0.9, 0.1, 0.3)),
        0.9583333333333334,
        0.888888888888889,
        0.9,
    )
    assert_hsv(get_hsv(FloatColor(0.5, 0.5, 0.5)), 0, 0, 0.5)


def test_hsv_round_trips() raises:
    var color = FloatColor(0, 0, 0)
    set_hsv(color, 0.7, 0.4, 0.6)
    assert_hsv(get_hsv(color), 0.7, 0.4, 0.6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
