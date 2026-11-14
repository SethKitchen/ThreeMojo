# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Dilation, erosion, opening and closing of labels by a ball."""

from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.morphology import (
    close_label,
    dilate_label,
    erode_label,
    open_label,
)
from extensions.imaging.thickness import seed_distances
from std.math import inf
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


def _map(n: Int, sz: Float64) raises -> LabelMap:
    return LabelMap(ImageVolume(n, n, n, _mm(1), _mm(1), _mm(sz)))


def _cube(mut map: LabelMap, low: Int, high: Int) raises:
    for k in range(low, high):
        for j in range(low, high):
            for i in range(low, high):
                map.set(i, j, k, LabelId(1))


def test_dilate_a_voxel() raises:
    var map = _map(9, 1)
    map.set(4, 4, 4, LabelId(1))
    # The voxels within 2 mm of a voxel: the lattice points of a ball.
    assert_equal(dilate_label(map, LabelId(1), _mm(2)).voxels(LabelId(1)), 33)
    # Slices 2 mm apart: the ball reaches one slice up and one down.
    var thick = _map(9, 2)
    thick.set(4, 4, 4, LabelId(1))
    assert_equal(dilate_label(thick, LabelId(1), _mm(2)).voxels(LabelId(1)), 15)
    # A radius of zero changes nothing.
    assert_equal(dilate_label(map, LabelId(1), _mm(0)).voxels(LabelId(1)), 1)


def test_dilation_keeps_other_labels() raises:
    var map = _map(5, 1)
    map.set(2, 2, 2, LabelId(1))
    map.set(3, 2, 2, LabelId(2))
    var grown = dilate_label(map, LabelId(1), _mm(1))
    assert_true(grown.get(3, 2, 2) == LabelId(2))
    assert_true(grown.get(1, 2, 2) == LabelId(1))


def test_erode_a_cube() raises:
    var map = _map(11, 1)
    _cube(map, 2, 9)
    assert_equal(map.voxels(LabelId(1)), 343)
    assert_equal(erode_label(map, LabelId(1), _mm(1)).voxels(LabelId(1)), 125)
    assert_equal(erode_label(map, LabelId(1), _mm(1.5)).voxels(LabelId(1)), 125)
    # The grid's edge counts as outside: a full grid shrinks too.
    var full = _map(3, 1)
    _cube(full, 0, 3)
    assert_equal(erode_label(full, LabelId(1), _mm(1)).voxels(LabelId(1)), 1)


def test_open_removes_a_spike() raises:
    var map = _map(15, 1)
    _cube(map, 2, 9)
    for i in range(9, 14):
        map.set(i, 5, 5, LabelId(1))
    var opened = open_label(map, LabelId(1), _mm(1))
    # The spike goes. The cube loses its edges and corners, which a ball
    # of 1 mm cannot reach from the eroded core. The face voxel under the
    # spike has no voxel outside within 1 mm, so it stays in the core,
    # and the spike's first voxel comes back with it.
    assert_true(opened.get(12, 5, 5) == BACKGROUND)
    assert_true(opened.get(10, 5, 5) == BACKGROUND)
    assert_true(opened.get(9, 5, 5) == LabelId(1))
    assert_equal(opened.voxels(LabelId(1)), 343 - 12 * 5 - 8 + 1)


def test_close_fills_a_hole() raises:
    var map = _map(11, 1)
    _cube(map, 2, 9)
    map.set(5, 5, 5, BACKGROUND)
    var closed = close_label(map, LabelId(1), _mm(1))
    assert_true(closed.get(5, 5, 5) == LabelId(1))
    assert_equal(closed.voxels(LabelId(1)), 343)
    # A label that fills the grid keeps every voxel.
    var full = _map(3, 1)
    _cube(full, 0, 3)
    assert_equal(close_label(full, LabelId(1), _mm(1)).voxels(LabelId(1)), 27)


def test_seed_distances() raises:
    var map = _map(3, 1)
    var none = List[Bool](length=27, fill=False)
    var far = seed_distances(map, none, False)
    assert_equal(far[13].to(METER), inf[DType.float64]())
    var edge = seed_distances(map, none, True)
    assert_almost_equal(edge[13].to(METER), 0.002, atol=1e-12)
    with assert_raises(contains="one flag per voxel"):
        _ = seed_distances(map, List[Bool](), True)


def test_refusals() raises:
    var map = _map(3, 1)
    with assert_raises(contains="other than the background"):
        _ = dilate_label(map, BACKGROUND, _mm(1))
    with assert_raises(contains="label must be from 0 to 255"):
        _ = erode_label(map, LabelId(256), _mm(1))
    with assert_raises(contains="radius must be zero or more"):
        _ = open_label(map, LabelId(1), _mm(-1))
    with assert_raises(contains="radius must be zero or more"):
        _ = close_label(map, LabelId(1), Length64(inf[DType.float64](), METER))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
