# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Resampling volumes and label maps on a new spacing or another grid."""

from extensions.imaging.ids import LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.resample import (
    resample_labels,
    resample_labels_onto,
    resample_onto,
    resample_volume,
)
from extensions.sdf.vector import V3, cross, dot, normalize, v3
from std.math import floor, inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def _ramp() raises -> ImageVolume:
    """A linear field on 0.5 by 0.5 by 3 mm voxels: 2 x + 3 y - z, in mm."""
    var volume = ImageVolume(9, 7, 5, _mm(0.5), _mm(0.5), _mm(3))
    for k in range(5):
        for j in range(7):
            for i in range(9):
                var value = (
                    2 * 0.5 * Float64(i) + 3 * 0.5 * Float64(j) - 3 * Float64(k)
                )
                volume.set(i, j, k, Float32(value))
    volume.origin = v3(0.01, 0.02, -0.03)
    volume.window_width = 77
    return volume^


def test_a_linear_field_is_kept() raises:
    var volume = _ramp()
    # Cubic voxels of 1 mm: the extent is 4 by 3 by 12 mm.
    var cubic = resample_volume(volume, _mm(1), _mm(1), _mm(1))
    assert_equal(cubic.nx, 5)
    assert_equal(cubic.ny, 4)
    assert_equal(cubic.nz, 13)
    assert_equal(cubic.window_width, 77)
    assert_almost_equal(cubic.origin.z, -0.03, atol=1e-15)
    for k in range(13):
        for j in range(4):
            for i in range(5):
                var exact = 2 * Float64(i) + 3 * Float64(j) - Float64(k)
                assert_almost_equal(
                    Float64(cubic.get(i, j, k)), exact, atol=1e-4
                )
    # Each new voxel lies where the old field has its value.
    var p = cubic.patient_point(3, 2, 7)
    var q = volume.voxel_point(p)
    assert_almost_equal(
        Float64(volume.trilinear(q.x, q.y, q.z)),
        Float64(cubic.get(3, 2, 7)),
        atol=1e-4,
    )


def test_a_step_that_does_not_divide() raises:
    # 12 mm along k in steps of 5 mm: voxels at 0, 5 and 10 mm.
    var cubic = resample_volume(_ramp(), _mm(0.5), _mm(0.5), _mm(5))
    assert_equal(cubic.nz, 3)
    assert_almost_equal(Float64(cubic.get(0, 0, 2)), -10.0, atol=1e-4)


def test_labels_take_the_nearest_voxel() raises:
    var volume = ImageVolume(4, 1, 3, _mm(1), _mm(1), _mm(3))
    var map = LabelMap(volume)
    map.set(1, 0, 1, LabelId(2))
    map.set(3, 0, 2, LabelId(5))
    var fine = resample_labels(map, _mm(1), _mm(1), _mm(1))
    assert_equal(fine.nz, 7)
    # Slice 1 of 3 mm covers the new slices nearest to 3 mm: 2, 3 and 4.
    assert_true(fine.get(1, 0, 2) == LabelId(2))
    assert_true(fine.get(1, 0, 3) == LabelId(2))
    assert_true(fine.get(1, 0, 4) == LabelId(2))
    assert_true(fine.get(1, 0, 1) == LabelId(0))
    assert_true(fine.get(3, 0, 6) == LabelId(5))
    assert_equal(fine.voxels(LabelId(2)), 3)


def test_refusals() raises:
    var volume = _ramp()
    with assert_raises(contains="spacing must be positive"):
        _ = resample_volume(volume, _mm(0), _mm(1), _mm(1))
    with assert_raises(contains="spacing must be positive"):
        _ = resample_volume(
            volume, _mm(1), Length64(inf[DType.float64](), METER), _mm(1)
        )
    with assert_raises(contains="spacing must be positive"):
        _ = resample_labels(LabelMap(volume), _mm(1), _mm(1), _mm(-1))
    with assert_raises(contains="2^28 voxels"):
        _ = resample_volume(volume, _mm(1e-4), _mm(1e-4), _mm(1e-3))


def _field(p: V3) -> Float64:
    """A linear field of patient position, in mm: 2 x - y + 0.5 z + 7."""
    return 1000 * (2 * p.x - p.y + 0.5 * p.z) + 7


def _turned_source() raises -> ImageVolume:
    """A volume turned in patient space, holding the linear field."""
    var volume = ImageVolume(12, 10, 8, _mm(2), _mm(2.5), _mm(3))
    volume.origin = v3(-0.004, 0.003, -0.002)
    var a = normalize(v3(1, 0.3, 0))
    var b = normalize(cross(v3(0, 0, 1), a))
    volume.axis_x = a
    volume.axis_y = b
    volume.axis_z = cross(a, b)
    for k in range(8):
        for j in range(10):
            for i in range(12):
                var p = volume.patient_point(Float64(i), Float64(j), Float64(k))
                volume.set(i, j, k, Float32(_field(p)))
    volume.window_center = 50
    volume.window_width = 300
    return volume^


def test_onto_another_grid() raises:
    var source = _turned_source()
    # A finer grid of other axes, partly outside the source.
    var target = ImageVolume(30, 26, 12, _mm(0.9), _mm(1.1), _mm(2))
    target.origin = v3(-0.006, 0.0, -0.001)
    var inside = 0
    var outside = 0
    var out = resample_onto(source, target, -1000)
    assert_equal(out.nx, 30)
    assert_equal(out.window_width, 300.0)
    assert_true(out.spacing_y.to(METER) == target.spacing_y.to(METER))
    for k in range(12):
        for j in range(26):
            for i in range(30):
                var p = target.patient_point(Float64(i), Float64(j), Float64(k))
                var q = source.voxel_point(p)
                var held = (
                    q.x >= 0
                    and q.y >= 0
                    and q.z >= 0
                    and q.x <= 11
                    and q.y <= 9
                    and q.z <= 7
                )
                var value = Float64(out.get(i, j, k))
                if held:
                    # A linear field is exact under trilinear blending.
                    assert_almost_equal(value, _field(p), atol=1e-3)
                    inside += 1
                else:
                    assert_equal(value, -1000.0)
                    outside += 1
    assert_true(inside > 1000 and outside > 1000)
    # Onto its own grid, a volume is the same.
    var same = resample_onto(source, source, 0)
    for index in range(source.count()):
        assert_almost_equal(
            Float64(same.values[index]),
            Float64(source.values[index]),
            atol=1e-3,
        )


def test_labels_onto_another_grid() raises:
    var source = _turned_source()
    var map = LabelMap(source)
    for k in range(2, 6):
        for j in range(3, 7):
            for i in range(4, 9):
                map.set(i, j, k, LabelId(3))
    # Onto its own grid, a map is the same.
    var same = resample_labels_onto(map, source, source)
    for index in range(map.count()):
        assert_equal(same.labels[index], map.labels[index])
    # Onto a finer grid: each voxel takes its nearest source voxel.
    var target = ImageVolume(40, 36, 20, _mm(0.7), _mm(0.8), _mm(1.5))
    target.origin = v3(-0.004, 0.001, -0.003)
    var fine = resample_labels_onto(map, source, target)
    var count = 0
    for k in range(20):
        for j in range(36):
            for i in range(40):
                var p = target.patient_point(Float64(i), Float64(j), Float64(k))
                var q = source.voxel_point(p)
                var x = Int(floor(q.x + 0.5))
                var y = Int(floor(q.y + 0.5))
                var z = Int(floor(q.z + 0.5))
                var expected = UInt8(0)
                if map.contains(x, y, z):
                    expected = map.labels[map.index(x, y, z)]
                assert_equal(fine.labels[fine.index(i, j, k)], expected)
                if expected == 3:
                    count += 1
    assert_true(count > 100)
    with assert_raises(contains="different grids"):
        _ = resample_labels_onto(map, target, target)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
