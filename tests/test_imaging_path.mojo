# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Centered paths through labels."""

from extensions.imaging.curved import curved_reformat
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.path import label_path
from extensions.sdf.vector import distance, v3
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64

comptime MM = 0.001


def _volume(n: Int) raises -> ImageVolume:
    var mm = Length64(1.0, MILLIMETER64)
    return ImageVolume(n, n, n, mm, mm, mm)


def _tube(
    mut map: LabelMap, axis: Int, a: Int, b: Int, at1: Int, at2: Int
) raises:
    """Fill a round tube of radius 3 voxels along one axis."""
    for t in range(a, b + 1):
        for u in range(-3, 4):
            for w in range(-3, 4):
                if u * u + w * w > 9:
                    continue
                if axis == 0:
                    map.set(t, at1 + u, at2 + w, LabelId(1))
                else:
                    map.set(at1 + u, t, at2 + w, LabelId(1))


def test_a_straight_tube_follows_its_axis() raises:
    var volume = _volume(24)
    var map = LabelMap(volume)
    _tube(map, 0, 2, 20, 8, 8)
    var path = label_path(map, volume, LabelId(1), (2, 8, 8), (20, 8, 8))
    assert_equal(len(path), 19)
    for k in range(19):
        assert_almost_equal(path[k].x, Float64(2 + k) * MM, atol=1e-12)
        assert_almost_equal(path[k].y, 8 * MM, atol=1e-12)
        assert_almost_equal(path[k].z, 8 * MM, atol=1e-12)
    # A start off the axis goes to the axis, and ends on it.
    var off = label_path(map, volume, LabelId(1), (2, 10, 8), (20, 8, 8))
    assert_almost_equal(off[0].y, 10 * MM, atol=1e-12)
    assert_almost_equal(off[len(off) - 1].x, 20 * MM, atol=1e-12)
    assert_almost_equal(off[len(off) // 2].y, 8 * MM, atol=1e-12)


def test_a_bent_tube() raises:
    var volume = _volume(26)
    var map = LabelMap(volume)
    _tube(map, 0, 3, 18, 5, 8)
    _tube(map, 1, 5, 21, 18, 8)
    var path = label_path(map, volume, LabelId(1), (3, 5, 8), (18, 21, 8))
    assert_true(len(path) > 20)
    # Each step goes to a neighbor, and every point is in the label.
    for k in range(1, len(path)):
        var step = distance(path[k], path[k - 1])
        assert_true(step > 0.5 * MM and step < sqrt(3.0) * MM + 1e-12)
    for p in path:
        var i = Int(p.x / MM + 0.5)
        var j = Int(p.y / MM + 0.5)
        var k = Int(p.z / MM + 0.5)
        assert_true(map.get(i, j, k) == LabelId(1))
        # It stays in the middle plane of the tubes.
        assert_equal(k, 8)
    # The path straightens into a curved reformat.
    var image = curved_reformat(
        volume, path, v3(0, 0, 1), 2, Length64(0.5, MILLIMETER64), 0
    )
    assert_equal(image.ny, 5)
    # A line along the grid's edge: the grid stops the neighbors.
    var edge = LabelMap(volume)
    for i in range(6):
        edge.set(i, 0, 0, LabelId(1))
    var along = label_path(edge, volume, LabelId(1), (0, 0, 0), (5, 0, 0))
    assert_equal(len(along), 6)
    # One voxel is a path of one point.
    var one = label_path(map, volume, LabelId(1), (3, 5, 8), (3, 5, 8))
    assert_equal(len(one), 1)


def test_refusals() raises:
    var volume = _volume(12)
    var map = LabelMap(volume)
    _tube(map, 0, 1, 4, 5, 5)
    _tube(map, 0, 7, 10, 5, 5)
    with assert_raises(contains="No path"):
        _ = label_path(map, volume, LabelId(1), (1, 5, 5), (10, 5, 5))
    with assert_raises(contains="outside the grid"):
        _ = label_path(map, volume, LabelId(1), (-1, 5, 5), (4, 5, 5))
    with assert_raises(contains="outside the grid"):
        _ = label_path(map, volume, LabelId(1), (1, 5, 5), (12, 5, 5))
    with assert_raises(contains="outside the label"):
        _ = label_path(map, volume, LabelId(1), (0, 0, 0), (4, 5, 5))
    with assert_raises(contains="outside the label"):
        _ = label_path(map, volume, LabelId(1), (1, 5, 5), (0, 0, 0))
    with assert_raises(contains="background"):
        _ = label_path(map, volume, BACKGROUND, (0, 0, 0), (1, 1, 1))
    with assert_raises(contains="different grids"):
        _ = label_path(map, _volume(8), LabelId(1), (1, 5, 5), (4, 5, 5))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
