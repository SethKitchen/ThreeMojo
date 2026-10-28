# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Smoothing the edges of a game's frame, as FXAA does, on every core."""

from extensions.vegetation.noise import hash01
from render.framebuffer import Framebuffer
from render.game_smooth import smooth_edges
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _frame(width: Int, height: Int, step: Bool) raises -> Framebuffer:
    """Return a frame of noise, or one that is white right of a diagonal
    and black left of it, with a gray blue channel."""
    var pixels = List[UInt8]()
    for y in range(height):
        for x in range(width):
            var value = UInt8(255) if x > y else UInt8(0)
            if not step:
                value = UInt8(Int(hash01(x, y, 5) * 255))
            pixels.append(value)
            pixels.append(value)
            pixels.append(UInt8(Int(hash01(x, y, 9) * 255)) if not step else 90)
            pixels.append(255)
    return Framebuffer(width, height, pixels^)


def test_a_flat_frame_keeps_its_colors() raises:
    var flat = Framebuffer(12, 7, List[UInt8](length=12 * 7 * 4, fill=128))
    var before = flat.pixels.copy()
    smooth_edges(flat, 4)
    assert_true(flat.pixels == before)


def test_a_stair_step_edge_is_blended_and_the_rest_is_not() raises:
    var frame = _frame(24, 16, True)
    var depth = frame.depth.copy()
    smooth_edges(frame, 3)
    var blended = 0
    for y in range(16):
        for x in range(24):
            var red = Int(frame.pixels[(y * 24 + x) * 4])
            var alpha = Int(frame.pixels[(y * 24 + x) * 4 + 3])
            assert_equal(alpha, 255)
            if abs(x - y) > 2:
                # Far from the edge, a pixel keeps its color.
                assert_equal(red, 255 if x > y else 0)
            elif red > 0 and red < 255:
                blended += 1
    # Along the diagonal, the steps are mixed.
    assert_true(blended > 10)
    assert_true(frame.depth == depth)


def test_every_count_of_workers_smooths_the_same_frame() raises:
    var one = _frame(37, 23, False)
    var original = one.pixels.copy()
    smooth_edges(one, 1)
    # Noise has edges everywhere, and the frame changes.
    assert_false(one.pixels == original)
    for workers in [2, 4, 7, 64]:
        var many = _frame(37, 23, False)
        smooth_edges(many, workers)
        assert_true(many.pixels == one.pixels)
    # A frame of two pixels with more tasks than pixels.
    var tiny = _frame(1, 2, False)
    var alone = _frame(1, 2, False)
    smooth_edges(tiny, 8)
    smooth_edges(alone, 1)
    assert_true(tiny.pixels == alone.pixels)


def test_a_frame_whose_pixels_do_not_match_is_refused() raises:
    var frame = _frame(4, 4, True)
    frame.pixels.resize(8, 0)
    with assert_raises(contains="match its size"):
        smooth_edges(frame, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
