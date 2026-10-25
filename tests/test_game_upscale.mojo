# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stretching a small frame to the window: bilinear, by pixel centers, on
every core."""

from render.framebuffer import Framebuffer
from render.game_upscale import upscale, upscale_into
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_raises


def _ramp(width: Int, height: Int) raises -> Framebuffer:
    """Return a frame whose red rises across, green down, blue fixed."""
    var pixels = List[UInt8]()
    for y in range(height):
        for x in range(width):
            pixels.append(UInt8(x * 255 // max(1, width - 1)))
            pixels.append(UInt8(y * 255 // max(1, height - 1)))
            pixels.append(77)
            pixels.append(255)
    return Framebuffer(width, height, pixels^)


def test_a_frame_is_stretched_between_its_pixel_centers() raises:
    var small = _ramp(2, 2)
    var big = upscale(small, 4, 4, 3)
    assert_equal(big.width, 4)
    assert_equal(big.height, 4)
    # The outer pixels hold the edges; the inner ones mix a quarter and
    # three quarters.
    assert_equal(Int(big.pixels[0]), 0)
    assert_equal(Int(big.pixels[4]), 64)
    assert_equal(Int(big.pixels[8]), 191)
    assert_equal(Int(big.pixels[12]), 255)
    assert_equal(Int(big.pixels[4 * 4 + 1]), 64)
    assert_equal(Int(big.pixels[2]), 77)
    assert_equal(Int(big.pixels[3]), 255)
    assert_equal(big.depth[5], inf[DType.float32]())


def test_a_wide_frame_uses_every_lane_and_one_worker() raises:
    var small = _ramp(7, 3)
    var serial = upscale(small, 37, 70, 1)
    var parallel = upscale(small, 37, 70, 8)
    assert_equal(serial.pixels, parallel.pixels)
    # A frame of one pixel fills the window.
    var dot = upscale(_ramp(1, 1), 5, 5, 0)
    for i in range(25):
        assert_equal(Int(dot.pixels[i * 4 + 2]), 77)


def test_a_bad_size_is_refused() raises:
    with assert_raises(contains="positive"):
        _ = upscale(_ramp(2, 2), 0, 4, 1)
    with assert_raises(contains="positive"):
        _ = upscale(_ramp(2, 2), 4, -1, 1)
    var target = Framebuffer(4, 4, List[UInt8](length=64, fill=0))
    target.pixels = List[UInt8](length=4, fill=0)
    with assert_raises(contains="match"):
        upscale_into(_ramp(2, 2), target, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
