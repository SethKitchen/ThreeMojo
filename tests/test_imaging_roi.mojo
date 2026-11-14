# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The values inside a circle on a slice."""

from extensions.imaging.ids import I_AXIS, J_AXIS, K_AXIS, SliceAxis
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.roi import circle_statistics
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Length64, SQUARE_METER

comptime MM = 0.001


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def _volume(sx: Float64) raises -> ImageVolume:
    var volume = ImageVolume(16, 16, 12, _mm(sx), _mm(1.0), _mm(1.0))
    for k in range(12):
        for j in range(16):
            for i in range(16):
                volume.set(i, j, k, Float32(10 * i + 1000 * k))
    return volume^


def test_a_uniform_disc() raises:
    var volume = ImageVolume(16, 16, 4, _mm(1.0), _mm(1.0), _mm(1.0))
    for index in range(volume.nx * volume.ny * volume.nz):
        volume.values[index] = 40
    # A radius of 2 pixels holds the 13 lattice points of the disc.
    var s = circle_statistics(volume, K_AXIS, 2, 8, 8, _mm(2.0))
    assert_equal(s.pixels, 13)
    assert_almost_equal(s.area.to(SQUARE_METER), 13 * MM * MM, rtol=1e-12)
    assert_equal(s.mean, 40.0)
    assert_equal(s.deviation, 0.0)
    assert_equal(s.minimum, 40.0)
    assert_equal(s.maximum, 40.0)


def test_a_ramp() raises:
    # Across a ramp of 10 per pixel, a disc gives its center value.
    var volume = _volume(1.0)
    var s = circle_statistics(volume, K_AXIS, 3, 8, 8, _mm(3.0))
    assert_equal(s.pixels, 29)
    assert_almost_equal(s.mean, 3080.0, rtol=1e-12)
    assert_equal(s.minimum, 3050.0)
    assert_equal(s.maximum, 3110.0)
    # The sample deviation, by a sum over the same pixels.
    var squares = 0.0
    for dj in range(-3, 4):
        for di in range(-3, 4):
            if di * di + dj * dj <= 9:
                squares += Float64(10 * di) ** 2
    assert_almost_equal(s.deviation, sqrt(squares / 28.0), rtol=1e-12)


def test_other_axes_and_pixels() raises:
    # Pixels 0.5 mm wide: a radius of 1 mm reaches 2 pixels along i and 1
    # along k, so 7 pixels in all.
    var volume = _volume(0.5)
    var s = circle_statistics(volume, J_AXIS, 5, 8, 6, _mm(1.0))
    assert_equal(s.pixels, 7)
    assert_almost_equal(s.area.to(SQUARE_METER), 3.5 * MM * MM, rtol=1e-12)
    assert_almost_equal(s.mean, 80.0 + 6000.0, rtol=1e-12)
    # One pixel of a slice across i: its value, and no deviation.
    var one = circle_statistics(volume, I_AXIS, 3, 4, 7, _mm(0.4))
    assert_equal(one.pixels, 1)
    assert_equal(one.mean, 30.0 + 7000.0)
    assert_equal(one.deviation, 0.0)
    # A circle at a corner keeps the pixels of the grid.
    var corner = circle_statistics(_volume(1.0), K_AXIS, 0, 0, 0, _mm(2.0))
    assert_equal(corner.pixels, 6)
    # A center between two pixels takes both.
    var between = circle_statistics(_volume(1.0), K_AXIS, 0, 8.5, 8, _mm(0.5))
    assert_equal(between.pixels, 2)
    assert_almost_equal(between.mean, 85.0)


def test_refusals() raises:
    var volume = _volume(1.0)
    var r = _mm(1.0)
    with assert_raises(contains="axis"):
        _ = circle_statistics(volume, SliceAxis(3), 0, 1, 1, r)
    with assert_raises(contains="slice index"):
        _ = circle_statistics(volume, K_AXIS, -1, 1, 1, r)
    with assert_raises(contains="slice index"):
        _ = circle_statistics(volume, K_AXIS, 12, 1, 1, r)
    with assert_raises(contains="slice index"):
        _ = circle_statistics(volume, J_AXIS, 16, 1, 1, r)
    with assert_raises(contains="finite"):
        _ = circle_statistics(volume, K_AXIS, 0, inf[DType.float64](), 1, r)
    with assert_raises(contains="finite"):
        _ = circle_statistics(volume, K_AXIS, 0, 1, nan[DType.float64](), r)
    with assert_raises(contains="radius"):
        _ = circle_statistics(volume, K_AXIS, 0, 1, 1, _mm(0.0))
    with assert_raises(contains="radius"):
        _ = circle_statistics(
            volume,
            K_AXIS,
            0,
            1,
            1,
            Length64(inf[DType.float64](), MILLIMETER64),
        )
    with assert_raises(contains="No pixel"):
        _ = circle_statistics(volume, K_AXIS, 0, 1e300, 1e300, r)
    with assert_raises(contains="No pixel"):
        _ = circle_statistics(volume, K_AXIS, 0, -1e300, -1e300, r)
    # Rows in range, columns out of range.
    with assert_raises(contains="No pixel"):
        _ = circle_statistics(volume, K_AXIS, 0, 1e300, 1, r)
    with assert_raises(contains="No pixel"):
        _ = circle_statistics(volume, K_AXIS, 0, 5.5, 5.5, _mm(0.1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
