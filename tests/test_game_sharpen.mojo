# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sharpening a stretched frame: edges gain contrast, flat areas keep
their color, and the result stays in the neighborhood's range."""

from render.framebuffer import Framebuffer
from render.game_sharpen import sharpen
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _edge(width: Int, height: Int) raises -> Framebuffer:
    """Return a frame whose left half is dark gray and right half light
    gray, with a soft column between."""
    var pixels = List[UInt8]()
    for _ in range(height):
        for x in range(width):
            var v = 60 if x < width // 2 else 200
            if x == width // 2:
                v = 130
            pixels.append(UInt8(v))
            pixels.append(UInt8(v))
            pixels.append(UInt8(v))
            pixels.append(255)
    return Framebuffer(width, height, pixels^)


def test_an_edge_gains_contrast_and_a_flat_area_keeps_its_color() raises:
    var width = 40
    var frame = _edge(width, 6)
    sharpen(frame, 1)
    var row = 2 * width * 4
    # The pixels beside the soft column move apart.
    var left = Int(frame.pixels[row + (width // 2 - 1) * 4])
    var right = Int(frame.pixels[row + (width // 2 + 1) * 4])
    assert_true(left < 60)
    assert_true(right > 200)
    # A flat pixel far from the edge, and every alpha, do not change.
    assert_equal(Int(frame.pixels[row + 3 * 4]), 60)
    assert_equal(Int(frame.pixels[row + 3 * 4 + 3]), 255)
    # The border is kept.
    var soft = _edge(width, 6)
    assert_equal(frame.pixels[0 : width * 4], soft.pixels[0 : width * 4])


def test_no_strength_and_a_tiny_frame_leave_the_frame_alone() raises:
    var frame = _edge(40, 6)
    var before = frame.pixels.copy()
    sharpen(frame, 0)
    assert_equal(frame.pixels, before)
    var tiny = _edge(2, 2)
    var tiny_before = tiny.pixels.copy()
    sharpen(tiny, 1)
    assert_equal(tiny.pixels, tiny_before)


def test_a_bad_strength_or_size_is_refused() raises:
    var frame = _edge(8, 8)
    with assert_raises(contains="from 0 to 1"):
        sharpen(frame, 1.5)
    with assert_raises(contains="from 0 to 1"):
        sharpen(frame, -0.1)
    frame.pixels = List[UInt8](length=4, fill=0)
    with assert_raises(contains="match"):
        sharpen(frame, 0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
