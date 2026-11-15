# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Holes of a label filled in three dimensions and in slices."""

from extensions.imaging.holes import fill_holes, fill_slice_holes
from extensions.imaging.ids import (
    BACKGROUND,
    CORNERS,
    Connectivity,
    EDGES,
    FACES,
    I_AXIS,
    J_AXIS,
    K_AXIS,
    LabelId,
    SliceAxis,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import MILLIMETER64, Length64


def _map(n: Int) raises -> LabelMap:
    var mm = Length64(1.0, MILLIMETER64)
    return LabelMap(ImageVolume(n, n, n, mm, mm, mm))


def test_a_hollow_cube() raises:
    var map = _map(7)
    for k in range(7):
        for j in range(7):
            for i in range(7):
                var far = max(abs(i - 3), max(abs(j - 3), abs(k - 3)))
                if far == 2:
                    map.set(i, j, k, LabelId(1))
    assert_equal(map.voxels(LabelId(1)), 125 - 27)
    var full = fill_holes(map, LabelId(1))
    assert_equal(full.voxels(LabelId(1)), 125)
    # A voxel of another label in the hole keeps its label.
    map.set(3, 3, 3, LabelId(2))
    var kept = fill_holes(map, LabelId(1), CORNERS)
    assert_equal(kept.voxels(LabelId(1)), 124)
    assert_true(kept.get(3, 3, 3) == LabelId(2))
    # The input does not change.
    assert_equal(map.voxels(LabelId(1)), 98)
    # A label with no voxels closes nothing off.
    assert_equal(fill_holes(map, LabelId(5)).voxels(LabelId(5)), 0)


def test_connectivity_of_the_outside() raises:
    var map = _map(5)
    var one = LabelId(1)
    # A wall of the six face neighbors of the center.
    for k in range(1, 4):
        for j in range(1, 4):
            for i in range(1, 4):
                if abs(i - 2) + abs(j - 2) + abs(k - 2) == 1:
                    map.set(i, j, k, one)
    assert_equal(fill_holes(map, one, FACES).voxels(one), 7)
    assert_equal(fill_holes(map, one, EDGES).voxels(one), 6)
    assert_equal(fill_holes(map, one, CORNERS).voxels(one), 6)
    # Add the twelve edge neighbors.
    for k in range(1, 4):
        for j in range(1, 4):
            for i in range(1, 4):
                if abs(i - 2) + abs(j - 2) + abs(k - 2) == 2:
                    map.set(i, j, k, one)
    assert_equal(fill_holes(map, one, EDGES).voxels(one), 19)
    assert_equal(fill_holes(map, one, CORNERS).voxels(one), 18)
    # And the eight corners.
    for k in [1, 3]:
        for j in [1, 3]:
            for i in [1, 3]:
                map.set(i, j, k, one)
    assert_equal(fill_holes(map, one, CORNERS).voxels(one), 27)


def test_the_grid_edge() raises:
    var map = _map(5)
    var one = LabelId(1)
    for k in range(5):
        for j in range(5):
            for i in range(5):
                if min(i, min(j, k)) == 0 or max(i, max(j, k)) == 4:
                    map.set(i, j, k, one)
    # A label on the grid's edge closes off the inside.
    assert_equal(fill_holes(map, one).voxels(one), 125)
    # A gap on the edge opens it.
    map.set(0, 2, 2, BACKGROUND)
    assert_equal(fill_holes(map, one).voxels(one), 97)


def test_slices() raises:
    var one = LabelId(1)
    var axes = [I_AXIS, J_AXIS, K_AXIS]
    for along in range(3):
        # A tube along one axis, open at both ends.
        var map = _map(5)
        for a in range(5):
            for b in range(5):
                for c in range(5):
                    var at: List[Int] = [a, b, c]
                    var u = at[(along + 1) % 3]
                    var v = at[(along + 2) % 3]
                    if max(abs(u - 2), abs(v - 2)) == 1:
                        map.set(a, b, c, one)
        assert_equal(fill_holes(map, one).voxels(one), 40)
        for across in range(3):
            var filled = fill_slice_holes(map, one, axes[across])
            assert_equal(filled.voxels(one), 45 if across == along else 40)
    # A diamond in a slice closes its center by faces only.
    var map = _map(5)
    for p in [(2, 1), (1, 2), (3, 2), (2, 3)]:
        map.set(p[0], p[1], 2, one)
    assert_equal(fill_slice_holes(map, one, K_AXIS).voxels(one), 5)
    assert_equal(fill_slice_holes(map, one, K_AXIS, EDGES).voxels(one), 4)
    assert_equal(fill_slice_holes(map, one, K_AXIS, CORNERS).voxels(one), 4)
    # In three dimensions the center reaches the slices above and below.
    assert_equal(fill_holes(map, one).voxels(one), 4)


def test_refusals() raises:
    var map = _map(3)
    with assert_raises(contains="background"):
        _ = fill_holes(map, BACKGROUND)
    with assert_raises(contains="background"):
        _ = fill_slice_holes(map, BACKGROUND, K_AXIS)
    with assert_raises(contains="label"):
        _ = fill_holes(map, LabelId(300))
    with assert_raises(contains="connectivity"):
        _ = fill_holes(map, LabelId(1), Connectivity(3))
    with assert_raises(contains="axis"):
        _ = fill_slice_holes(map, LabelId(1), SliceAxis(3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
