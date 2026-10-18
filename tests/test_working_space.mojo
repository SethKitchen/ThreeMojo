# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.working_space`."""

from render.framebuffer import Color, FloatColor
from render.target import RenderTarget
from render.working_space import resolve_srgb_working, srgb_working_target
from std.testing import TestSuite, assert_equal, assert_raises


def test_the_background_comes_out_as_it_went_in() raises:
    var target = srgb_working_target(3, 2, Color(7, 8, 15))
    var frame = resolve_srgb_working(target)
    assert_equal(frame.width, 3)
    assert_equal(frame.height, 2)
    for pixel in range(6):
        assert_equal(frame.pixels[pixel * 4], 7)
        assert_equal(frame.pixels[pixel * 4 + 1], 8)
        assert_equal(frame.pixels[pixel * 4 + 2], 15)
        assert_equal(frame.pixels[pixel * 4 + 3], 255)


def test_the_renderers_own_target_decodes_the_background() raises:
    # The difference that this module exists for.
    var target = RenderTarget(1, 1, Color(7, 8, 15))
    var frame = resolve_srgb_working(target)
    assert_equal(frame.pixels[0], 1)
    assert_equal(frame.pixels[1], 1)
    assert_equal(frame.pixels[2], 1)


def test_a_half_clear_white_splat_blends_the_values_it_is_given() raises:
    var target = srgb_working_target(1, 1, Color(7, 8, 15))
    target.blend(0, 0, FloatColor(1.0, 1.0, 1.0, 0.5))
    var frame = resolve_srgb_working(target)
    # Half of the background and half of white, in values: 131, 132, 135.
    assert_equal(frame.pixels[0], 131)
    assert_equal(frame.pixels[1], 132)
    assert_equal(frame.pixels[2], 135)


def test_an_alpha_in_the_background_is_kept() raises:
    var target = srgb_working_target(1, 1, Color(100, 100, 100, 128))
    var frame = resolve_srgb_working(target)
    assert_equal(frame.pixels[0], 100)
    assert_equal(frame.pixels[3], 128)


def test_a_size_that_is_not_positive_is_refused() raises:
    with assert_raises(contains="dimensions must be positive"):
        _ = srgb_working_target(0, 4, Color(0, 0, 0))
    with assert_raises(contains="dimensions must be positive"):
        _ = srgb_working_target(4, 0, Color(0, 0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
