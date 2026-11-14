# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The principal axes, equivalent ellipsoid and slice areas of labels."""

from extensions.imaging.ids import (
    BACKGROUND,
    I_AXIS,
    J_AXIS,
    K_AXIS,
    LabelId,
    SliceAxis,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.shape import label_shape, slice_areas
from extensions.sdf.vector import dot, v3
from std.math import cos, pi, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import CUBIC_METER, Length64, METER, SQUARE_METER

comptime MM = 0.001


def _volume(n: Int, sz: Float64) raises -> ImageVolume:
    var mm = Length64(1.0, MILLIMETER64)
    return ImageVolume(n, n, n, mm, mm, Length64(sz, MILLIMETER64))


def _box(volume: ImageVolume) raises -> LabelMap:
    # 10 by 6 by 4 voxels from (2, 3, 1).
    var map = LabelMap(volume)
    for k in range(1, 5):
        for j in range(3, 9):
            for i in range(2, 12):
                map.set(i, j, k, LabelId(2))
    return map^


def test_a_box_has_the_moments_of_a_box() raises:
    # Voxels of 1 by 1 by 2 mm: the box is 10 by 6 by 8 mm.
    var volume = _volume(16, 2.0)
    var shape = label_shape(_box(volume), volume, LabelId(2))
    assert_equal(shape.voxels, 240)
    assert_almost_equal(
        shape.volume.to(CUBIC_METER), 480.0 * MM * MM * MM, rtol=1e-12
    )
    # The centroid is the middle of the voxel centers.
    assert_almost_equal(shape.center.x, 6.5 * MM, rtol=1e-12)
    assert_almost_equal(shape.center.y, 5.5 * MM, rtol=1e-12)
    assert_almost_equal(shape.center.z, 5.0 * MM, rtol=1e-12)
    # A side L has the variance L^2 / 12, so a semi-axis of sqrt(5 / 12) L.
    var sides: List[Float64] = [10.0, 8.0, 6.0]
    var directions = [v3(1, 0, 0), v3(0, 0, 1), v3(0, 1, 0)]
    for k in range(3):
        assert_almost_equal(
            shape.semi_axis(k).to(METER),
            sqrt(5.0 / 12.0) * sides[k] * MM,
            rtol=1e-9,
        )
        assert_almost_equal(abs(dot(shape.axes[k], directions[k])), 1.0)
    with assert_raises(contains="0, 1 or 2"):
        _ = shape.semi_axis(3)
    with assert_raises(contains="0, 1 or 2"):
        _ = shape.semi_axis(-1)


def test_the_axes_follow_the_patient_frame() raises:
    var volume = _volume(16, 2.0)
    var map = _box(volume)
    # Columns run along patient y, and rows along patient -x.
    volume.axis_x = v3(0, 1, 0)
    volume.axis_y = v3(-1, 0, 0)
    volume.origin = v3(0.1, 0.2, 0.3)
    var shape = label_shape(map, volume, LabelId(2))
    assert_almost_equal(abs(shape.axes[0].y), 1.0)
    assert_almost_equal(abs(shape.axes[2].x), 1.0)
    assert_almost_equal(shape.center.x, 0.1 - 5.5 * MM, rtol=1e-12)
    assert_almost_equal(shape.center.y, 0.2 + 6.5 * MM, rtol=1e-12)
    assert_almost_equal(shape.center.z, 0.3 + 5.0 * MM, rtol=1e-12)


def test_a_turned_ellipsoid() raises:
    # Semi-axes of 20, 12 and 8 mm, turned 30 degrees about z, in 1 mm
    # voxels.
    var volume = _volume(64, 1.0)
    var map = LabelMap(volume)
    var turn = pi / 6
    var c = cos(turn)
    var s = sin(turn)
    for k in range(64):
        for j in range(64):
            for i in range(64):
                var x = Float64(i) - 32
                var y = Float64(j) - 32
                var z = Float64(k) - 32
                var u = c * x + s * y
                var v = -s * x + c * y
                if (u / 20) ** 2 + (v / 12) ** 2 + (z / 8) ** 2 <= 1:
                    map.set(i, j, k, LabelId(1))
    var shape = label_shape(map, volume, LabelId(1))
    var expected: List[Float64] = [20.0, 12.0, 8.0]
    for k in range(3):
        assert_almost_equal(
            shape.semi_axis(k).to(METER), expected[k] * MM, rtol=0.02
        )
    # The long axis lies within a degree of its direction.
    assert_true(abs(dot(shape.axes[0], v3(c, s, 0))) > cos(pi / 180))
    assert_true(abs(shape.axes[2].z) > cos(pi / 180))


def test_slice_areas() raises:
    var volume = _volume(16, 2.0)
    var map = _box(volume)
    var axial = slice_areas(map, LabelId(2), K_AXIS)
    assert_equal(len(axial), 16)
    for k in range(16):
        var expected = 0.0
        if k >= 1 and k <= 4:
            expected = 60.0 * MM * MM
        assert_almost_equal(axial[k].to(SQUARE_METER), expected, rtol=1e-12)
    # Across i, each slice is 6 rows by 4 slices of 1 by 2 mm.
    var across = slice_areas(map, LabelId(2), I_AXIS)
    assert_almost_equal(across[2].to(SQUARE_METER), 48.0 * MM * MM, rtol=1e-12)
    assert_almost_equal(across[1].to(SQUARE_METER), 0.0)
    var rows = slice_areas(map, LabelId(2), J_AXIS)
    assert_almost_equal(rows[3].to(SQUARE_METER), 80.0 * MM * MM, rtol=1e-12)


def test_refusals() raises:
    var volume = _volume(16, 2.0)
    var map = _box(volume)
    with assert_raises(contains="background"):
        _ = label_shape(map, volume, BACKGROUND)
    with assert_raises(contains="no voxels"):
        _ = label_shape(map, volume, LabelId(7))
    with assert_raises(contains="label"):
        _ = label_shape(map, volume, LabelId(300))
    with assert_raises(contains="different grids"):
        _ = label_shape(map, _volume(8, 2.0), LabelId(2))
    with assert_raises(contains="background"):
        _ = slice_areas(map, BACKGROUND, K_AXIS)
    with assert_raises(contains="label"):
        _ = slice_areas(map, LabelId(-1), K_AXIS)
    with assert_raises(contains="axis"):
        _ = slice_areas(map, LabelId(2), SliceAxis(3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
