# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Curved planar reformats along a path."""

from extensions.imaging.curved import curved_reformat
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.sdf.vector import V3, v3
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Length64

comptime MM = 0.001


def _field() raises -> ImageVolume:
    # A linear field: exact under trilinear interpolation.
    var mm = Length64(1.0, MILLIMETER64)
    var volume = ImageVolume(16, 16, 12, mm, mm, mm)
    for k in range(12):
        for j in range(16):
            for i in range(16):
                volume.set(i, j, k, Float32(10 * i + 100 * j + 1000 * k))
    volume.window_center = 40
    volume.window_width = 400
    return volume^


def _f(x: Float64, y: Float64, z: Float64) -> Float64:
    return 10 * x + 100 * y + 1000 * z


def _mm(x: Float64, y: Float64, z: Float64) -> V3:
    return v3(x, y, z) * MM


def test_a_straight_path_is_a_plane() raises:
    var path: List[V3] = [_mm(2, 5, 5), _mm(12, 5, 5)]
    var image = curved_reformat(
        _field(), path, v3(0, 0, 1), 2, Length64(1.0, MILLIMETER64), -1
    )
    assert_equal(image.nx, 11)
    assert_equal(image.ny, 5)
    assert_equal(image.window_width, 400.0)
    for y in range(5):
        for x in range(11):
            assert_almost_equal(
                Float64(image.values[x + 11 * y]),
                _f(2 + Float64(x), 5, 5 + 2 - Float64(y)),
                atol=1e-3,
            )


def test_a_bent_path() raises:
    # 6 mm along x, then 7 mm along y: 14 columns, the corner at column 6.
    var path: List[V3] = [_mm(2, 2, 5), _mm(8, 2, 5), _mm(8, 9, 5)]
    var image = curved_reformat(
        _field(), path, v3(0, 0, 2), 1, Length64(1.0, MILLIMETER64), -1
    )
    assert_equal(image.nx, 14)
    assert_equal(image.ny, 3)
    var middle = image.nx
    assert_almost_equal(
        Float64(image.values[middle + 0]), _f(2, 2, 5), atol=1e-3
    )
    assert_almost_equal(
        Float64(image.values[middle + 6]), _f(8, 2, 5), atol=1e-3
    )
    assert_almost_equal(
        Float64(image.values[middle + 10]), _f(8, 6, 5), atol=1e-3
    )
    assert_almost_equal(
        Float64(image.values[middle + 13]), _f(8, 9, 5), atol=1e-3
    )
    # Row 0 is one step up, along z.
    assert_almost_equal(Float64(image.values[10]), _f(8, 6, 6), atol=1e-3)
    # An up direction that leans along the path keeps only its square part.
    var leaning = curved_reformat(
        _field(), path, v3(1, 0, 1), 1, Length64(1.0, MILLIMETER64), -1
    )
    assert_almost_equal(Float64(leaning.values[2]), _f(4, 2, 6), atol=1e-3)


def test_points_outside_the_volume() raises:
    var path: List[V3] = [_mm(2, 5, 9), _mm(6, 5, 9)]
    var image = curved_reformat(
        _field(), path, v3(0, 0, 1), 3, Length64(1.0, MILLIMETER64), -7
    )
    # Rows 0 and 1 lie at z = 12 and 11 mm, past the last slice at 11 mm.
    assert_equal(image.values[0], Float32(-7))
    assert_almost_equal(
        Float64(image.values[image.nx]), _f(2, 5, 11), atol=1e-3
    )


def test_refusals() raises:
    var volume = _field()
    var mm = Length64(1.0, MILLIMETER64)
    var up = v3(0, 0, 1)
    var one: List[V3] = [_mm(1, 1, 1)]
    with assert_raises(contains="two or more points"):
        _ = curved_reformat(volume, one, up, 1, mm, 0)
    var bad: List[V3] = [_mm(1, 1, 1), v3(inf[DType.float64](), 0, 0)]
    with assert_raises(contains="finite points"):
        _ = curved_reformat(volume, bad, up, 1, mm, 0)
    var path: List[V3] = [_mm(1, 1, 1), _mm(5, 1, 1)]
    with assert_raises(contains="rows on each side"):
        _ = curved_reformat(volume, path, up, -1, mm, 0)
    with assert_raises(contains="rows on each side"):
        _ = curved_reformat(volume, path, up, 4097, mm, 0)
    with assert_raises(contains="spacing"):
        _ = curved_reformat(volume, path, up, 1, Length64(0.0, MILLIMETER64), 0)
    with assert_raises(contains="cannot be zero"):
        _ = curved_reformat(volume, path, v3(0, 0, 0), 1, mm, 0)
    with assert_raises(contains="cannot be zero"):
        _ = curved_reformat(
            volume, path, v3(inf[DType.float64](), 0, 0), 1, mm, 0
        )
    var repeated: List[V3] = [_mm(1, 1, 1), _mm(1, 1, 1)]
    with assert_raises(contains="are one"):
        _ = curved_reformat(volume, repeated, up, 1, mm, 0)
    with assert_raises(contains="along a segment"):
        _ = curved_reformat(volume, path, v3(1, 0, 0), 1, mm, 0)
    var far: List[V3] = [v3(0, 0, 0), v3(10, 0, 0)]
    with assert_raises(contains="8192 columns"):
        _ = curved_reformat(volume, far, up, 1, mm, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
