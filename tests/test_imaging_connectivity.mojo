# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Pieces, largest pieces and grown regions with 6, 18 and 26 neighbors."""

from extensions.imaging.ids import (
    CORNERS,
    Connectivity,
    EDGES,
    FACES,
    LabelId,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import (
    LabelMap,
    keep_largest,
    label_pieces,
    region_grow,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import MILLIMETER64, Length64


def _volume(n: Int) raises -> ImageVolume:
    var mm = Length64(1.0, MILLIMETER64)
    return ImageVolume(n, n, n, mm, mm, mm)


def _count(map: LabelMap, connectivity: Connectivity) raises -> Int:
    return len(label_pieces(map, LabelId(1), connectivity).sizes)


def test_neighbor_counts() raises:
    assert_equal(FACES.neighbors(), 6)
    assert_equal(EDGES.neighbors(), 18)
    assert_equal(CORNERS.neighbors(), 26)


def test_which_voxels_touch() raises:
    var volume = _volume(6)
    # Two voxels that share an edge.
    var edge = LabelMap(volume)
    edge.set(2, 2, 2, LabelId(1))
    edge.set(3, 3, 2, LabelId(1))
    assert_equal(_count(edge, FACES), 2)
    assert_equal(_count(edge, EDGES), 1)
    assert_equal(_count(edge, CORNERS), 1)
    # Two voxels that share a corner only.
    var corner = LabelMap(volume)
    corner.set(2, 2, 2, LabelId(1))
    corner.set(3, 3, 3, LabelId(1))
    assert_equal(_count(corner, FACES), 2)
    assert_equal(_count(corner, EDGES), 2)
    assert_equal(_count(corner, CORNERS), 1)
    # The default is faces.
    assert_equal(len(label_pieces(corner, LabelId(1)).sizes), 2)


def test_a_full_grid_is_one_piece() raises:
    # Every voxel of a small grid, so each neighbor test meets every edge.
    var map = LabelMap(_volume(3))
    for index in range(map.count()):
        map.labels[index] = 1
    for connectivity in [FACES, EDGES, CORNERS]:
        var pieces = label_pieces(map, LabelId(1), connectivity)
        assert_equal(len(pieces.sizes), 1)
        assert_equal(pieces.sizes[0], 27)


def test_a_slanted_vessel() raises:
    # A diagonal line of 6 voxels and a pair of voxels that share a face.
    var volume = _volume(10)
    var map = LabelMap(volume)
    for t in range(6):
        map.set(1 + t, 1 + t, 1 + t, LabelId(1))
    map.set(8, 1, 8, LabelId(1))
    map.set(8, 2, 8, LabelId(1))
    # By faces, the pair is the largest piece; by corners, the line is.
    var by_faces = keep_largest(map, LabelId(1), FACES)
    assert_true(by_faces.get(8, 1, 8) == LabelId(1))
    assert_true(by_faces.get(1, 1, 1) == LabelId(0))
    var by_corners = keep_largest(map, LabelId(1), CORNERS)
    assert_true(by_corners.get(6, 6, 6) == LabelId(1))
    assert_true(by_corners.get(8, 1, 8) == LabelId(0))
    assert_equal(len(label_pieces(map, LabelId(1), CORNERS).sizes), 2)
    assert_equal(label_pieces(map, LabelId(1), CORNERS).sizes[0], 6)
    # A bright diagonal grows from its end with corners, and not with faces.
    var bright = volume.copy()
    for t in range(6):
        bright.set(1 + t, 1 + t, 1 + t, Float32(100))
    var faces = region_grow(bright, 1, 1, 1, 50, 150, LabelId(2))
    var corners = region_grow(bright, 1, 1, 1, 50, 150, LabelId(2), CORNERS)
    var grown_faces = 0
    var grown_corners = 0
    for index in range(faces.count()):
        if faces.labels[index] == 2:
            grown_faces += 1
        if corners.labels[index] == 2:
            grown_corners += 1
    assert_equal(grown_faces, 1)
    assert_equal(grown_corners, 6)


def test_refusals() raises:
    var volume = _volume(4)
    var map = LabelMap(volume)
    map.set(1, 1, 1, LabelId(1))
    var bad = Connectivity(3)
    with assert_raises(contains="connectivity"):
        _ = label_pieces(map, LabelId(1), bad)
    with assert_raises(contains="connectivity"):
        _ = keep_largest(map, LabelId(1), bad)
    var values = volume.copy()
    values.set(1, 1, 1, Float32(1))
    with assert_raises(contains="connectivity"):
        _ = region_grow(values, 1, 1, 1, 0, 2, LabelId(1), bad)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
