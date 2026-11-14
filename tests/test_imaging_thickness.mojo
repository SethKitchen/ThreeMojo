# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Distances to the edge of a label, and local thickness."""

from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.thickness import (
    label_distance,
    local_thickness,
    thickness_statistics,
)
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def _map(
    nx: Int, ny: Int, nz: Int, sx: Float64, sy: Float64, sz: Float64
) raises -> LabelMap:
    return LabelMap(ImageVolume(nx, ny, nz, _mm(sx), _mm(sy), _mm(sz)))


def test_distance_is_exact() raises:
    # An irregular label on an anisotropic grid, against brute force.
    var map = _map(7, 6, 5, 0.5, 0.8, 1.3)
    for index in range(map.count()):
        if (index * 37 + index // 7) % 5 != 0:
            map.labels[index] = 3
    var distance = label_distance(map, LabelId(3))
    for k in range(5):
        for j in range(6):
            for i in range(7):
                var at = map.index(i, j, k)
                if map.labels[at] != 3:
                    assert_equal(distance.values[at], 0)
                    continue
                # The nearest voxel outside: in the grid, or just past it.
                var best = 1.0e9
                for kk in range(-1, 6):
                    for jj in range(-1, 7):
                        for ii in range(-1, 8):
                            var outside = not map.contains(ii, jj, kk)
                            if not outside:
                                outside = map.labels[map.index(ii, jj, kk)] != 3
                            if outside:
                                var d = sqrt(
                                    (Float64(ii - i) * 0.5) ** 2
                                    + (Float64(jj - j) * 0.8) ** 2
                                    + (Float64(kk - k) * 1.3) ** 2
                                )
                                best = min(best, d)
                assert_almost_equal(
                    Float64(distance.values[at]), best, atol=1e-5
                )


def test_thickness_holds_each_sphere() raises:
    # The irregular label touches the edges of the grid. Each voxel lies
    # in its own sphere, so its thickness is at least twice its distance.
    var map = _map(7, 6, 5, 0.5, 0.8, 1.3)
    for index in range(map.count()):
        if (index * 37 + index // 7) % 5 != 0:
            map.labels[index] = 3
    var distance = label_distance(map, LabelId(3))
    var thickness = local_thickness(map, LabelId(3))
    for index in range(map.count()):
        if map.labels[index] == 3:
            assert_true(
                thickness.values[index] >= 2 * distance.values[index] - 1e-5
            )


def test_a_slab_is_its_own_thickness() raises:
    # A slab six voxels thick along k, inside the grid.
    var map = _map(20, 20, 10, 0.5, 0.5, 0.5)
    for k in range(2, 8):
        for j in range(2, 18):
            for i in range(2, 18):
                map.set(i, j, k, LabelId(1))
    var thickness = local_thickness(map, LabelId(1))
    for k in range(2, 8):
        for j in range(6, 14):
            for i in range(6, 14):
                assert_almost_equal(thickness.get(i, j, k), 3.0, atol=1e-5)
    assert_equal(thickness.get(0, 0, 0), 0)
    var stats = thickness_statistics(thickness, map, LabelId(1))
    assert_almost_equal(stats.maximum.to(MILLIMETER64), 3.0, atol=1e-5)
    assert_true(stats.mean.to(MILLIMETER64) < 3.0)
    assert_true(stats.mean.to(MILLIMETER64) > 2.5)


def test_thick_slices_limit_the_sphere() raises:
    # Slices 2 mm apart and pixels 0.5 mm wide: the label is 12 mm along
    # k but only 8 mm along i, so the thickness is 8 mm.
    var map = _map(20, 20, 10, 0.5, 0.5, 2.0)
    for k in range(2, 8):
        for j in range(2, 18):
            for i in range(2, 18):
                map.set(i, j, k, LabelId(1))
    var thickness = local_thickness(map, LabelId(1))
    var stats = thickness_statistics(thickness, map, LabelId(1))
    assert_almost_equal(stats.maximum.to(MILLIMETER64), 8.0, atol=1e-5)


def test_a_ball() raises:
    var map = _map(17, 17, 17, 1, 1, 1)
    for k in range(17):
        for j in range(17):
            for i in range(17):
                var r2 = (i - 8) ** 2 + (j - 8) ** 2 + (k - 8) ** 2
                if r2 <= 36:
                    map.set(i, j, k, LabelId(1))
    var thickness = local_thickness(map, LabelId(1))
    # The nearest voxel outside the ball is sqrt(37) voxels from its
    # center, such as the voxel 6 along i and 1 along j.
    var diameter = 2.0 * sqrt(37.0)
    assert_almost_equal(Float64(thickness.get(8, 8, 8)), diameter, atol=1e-5)
    var stats = thickness_statistics(thickness, map, LabelId(1))
    assert_almost_equal(stats.maximum.to(MILLIMETER64), diameter, atol=1e-5)


def test_refusals() raises:
    var map = _map(3, 3, 3, 1, 1, 1)
    with assert_raises(contains="no voxels"):
        _ = label_distance(map, LabelId(1))
    with assert_raises(contains="no voxels"):
        _ = local_thickness(map, LabelId(1))
    with assert_raises(contains="label must be from 0 to 255"):
        _ = label_distance(map, LabelId(256))
    map.set(1, 1, 1, LabelId(1))
    var thickness = local_thickness(map, LabelId(1))
    assert_almost_equal(thickness.get(1, 1, 1), 2.0, atol=1e-6)
    with assert_raises(contains="no voxels"):
        _ = thickness_statistics(thickness, map, LabelId(2))
    with assert_raises(contains="label must be from 0 to 255"):
        _ = thickness_statistics(thickness, map, LabelId(256))
    var other = _map(2, 3, 3, 1, 1, 1)
    with assert_raises(contains="grid"):
        _ = thickness_statistics(thickness, other, LabelId(1))
    # The background is a label like any other.
    assert_true(label_distance(map, BACKGROUND).get(0, 0, 0) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
