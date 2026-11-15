# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Values of a second volume fused over a slice on the hot scale."""

from extensions.imaging.fusion import hot_color, overlay_values
from extensions.imaging.ids import I_AXIS, J_AXIS, K_AXIS, SliceAxis
from extensions.imaging.image_volume import ImageVolume
from render.framebuffer import Color, Framebuffer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import MILLIMETER64, Length64


def _mm() -> Length64:
    return Length64(1.0, MILLIMETER64)


def test_hot_scale() raises:
    var dark = hot_color(0)
    assert_equal(dark.r, 0)
    assert_equal(dark.g, 0)
    var red = hot_color(1.0 / 3.0)
    assert_almost_equal(Float64(red.r), 1.0, atol=1e-6)
    assert_almost_equal(Float64(red.g), 0.0, atol=1e-6)
    var yellow = hot_color(2.0 / 3.0)
    assert_almost_equal(Float64(yellow.g), 1.0, atol=1e-6)
    assert_almost_equal(Float64(yellow.b), 0.0, atol=1e-6)
    var white = hot_color(1)
    assert_equal(white.b, 1)
    assert_equal(hot_color(-1).r, 0)
    assert_equal(hot_color(2).b, 1)
    assert_equal(white.a, 1)


def _expected(base: Int, weight: Float64, part: Float64) -> Int:
    """Return a blended byte, as the overlay rounds it."""
    var mixed = (1.0 - weight) * Float64(base) / 255.0 + weight * part
    return Int(mixed * 255.0 + 0.5)


def test_blending() raises:
    # Values 0, 5, 10, 20, -1 and 15 on a slice of 3 by 2 pixels.
    var volume = ImageVolume(3, 2, 1, _mm(), _mm(), _mm())
    var values: List[Float32] = [0, 5, 10, 20, -1, 15]
    for n in range(6):
        volume.values[n] = values[n]
    var image = Framebuffer(3, 2, Color(100, 100, 100))
    overlay_values(image, volume, K_AXIS, 0, 5, 20, 0.5, 1)
    # Below the range, and at its bottom with no weight: unchanged.
    for p in [(0, 0), (1, 0), (1, 1)]:
        assert_equal(Int(image.get_pixel(p[0], p[1]).r), 100)
    # A third of the way: red at the full opacity.
    var third = image.get_pixel(2, 0)
    assert_equal(Int(third.r), _expected(100, 0.5, 1))
    assert_equal(Int(third.g), _expected(100, 0.5, 0))
    # The top: white. Two thirds: yellow.
    assert_equal(Int(image.get_pixel(0, 1).b), _expected(100, 0.5, 1))
    var two = image.get_pixel(2, 1)
    assert_equal(Int(two.g), _expected(100, 0.5, 1))
    assert_equal(Int(two.b), _expected(100, 0.5, 0))
    # A sixth of the way fades in at half the weight.
    var faint = ImageVolume(1, 1, 1, _mm(), _mm(), _mm())
    faint.values[0] = 7.5
    var one = Framebuffer(1, 1, Color(0, 0, 0))
    overlay_values(one, faint, K_AXIS, 0, 5, 20, 1.0, 1)
    assert_equal(Int(one.get_pixel(0, 0).r), _expected(0, 0.5, 0.5))


def test_axes_and_zoom() raises:
    # A volume of 2 by 3 by 4 voxels whose value is its index k * 10.
    var volume = ImageVolume(2, 3, 4, _mm(), _mm(), _mm())
    for k in range(4):
        for j in range(3):
            for i in range(2):
                volume.set(i, j, k, Float32(10 * k + j))
    # Across k at k = 3, zoomed twice: every value is past the top.
    var top = Framebuffer(4, 6, Color(0, 0, 0))
    overlay_values(top, volume, K_AXIS, 3, 0, 10, 1.0, 2)
    assert_equal(Int(top.get_pixel(3, 5).b), 255)
    # Across j at j = 0: pixel y is k. Row 0 holds 0, below the range.
    var front = Framebuffer(2, 4, Color(0, 0, 0))
    overlay_values(front, volume, J_AXIS, 0, 1, 21, 1.0, 1)
    assert_equal(Int(front.get_pixel(1, 0).r), 0)
    assert_equal(Int(front.get_pixel(1, 3).b), 255)
    # Across i at i = 1: pixel x is j and pixel y is k.
    var side = Framebuffer(3, 4, Color(0, 0, 0))
    overlay_values(side, volume, I_AXIS, 1, 25, 32, 1.0, 1)
    assert_equal(Int(side.get_pixel(2, 2).r), 0)
    assert_equal(Int(side.get_pixel(2, 3).b), 255)


def test_refusals() raises:
    var volume = ImageVolume(2, 3, 4, _mm(), _mm(), _mm())
    var image = Framebuffer(2, 3, Color(0, 0, 0))
    with assert_raises(contains="axis"):
        overlay_values(image, volume, SliceAxis(3), 0, 0, 1, 1, 1)
    with assert_raises(contains="slice index"):
        overlay_values(image, volume, K_AXIS, 4, 0, 1, 1, 1)
    with assert_raises(contains="slice index"):
        overlay_values(image, volume, K_AXIS, -1, 0, 1, 1, 1)
    for bad in [
        (1.0, 1.0),
        (-inf[DType.float64](), 1.0),
        (0.0, inf[DType.float64]()),
    ]:
        with assert_raises(contains="range"):
            overlay_values(image, volume, K_AXIS, 0, bad[0], bad[1], 1, 1)
    for opacity in [-0.1, 1.1, nan[DType.float64]()]:
        with assert_raises(contains="opacity"):
            overlay_values(image, volume, K_AXIS, 0, 0, 1, opacity, 1)
    for zoom in [0, 65]:
        with assert_raises(contains="zoom"):
            overlay_values(image, volume, K_AXIS, 0, 0, 1, 1, zoom)
    with assert_raises(contains="size"):
        overlay_values(image, volume, K_AXIS, 0, 0, 1, 1, 2)
    var wide = Framebuffer(3, 3, Color(0, 0, 0))
    with assert_raises(contains="size"):
        overlay_values(wide, volume, K_AXIS, 0, 0, 1, 1, 1)
    var tall = Framebuffer(2, 4, Color(0, 0, 0))
    with assert_raises(contains="size"):
        overlay_values(tall, volume, K_AXIS, 0, 0, 1, 1, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
