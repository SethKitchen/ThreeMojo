# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The connected pieces of a label, numbered by size."""

from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, keep_largest, label_pieces
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import CUBIC_METER, MILLIMETER64, Length64


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def _box(mut map: LabelMap, low: Int, size: Int, label: Int) raises:
    for k in range(low, low + size):
        for j in range(low, low + size):
            for i in range(low, low + size):
                map.set(i, j, k, LabelId(label))


def test_pieces_by_size() raises:
    var map = LabelMap(ImageVolume(12, 12, 12, _mm(1), _mm(2), _mm(0.5)))
    _box(map, 0, 2, 1)
    _box(map, 4, 3, 1)
    map.set(10, 10, 10, LabelId(1))
    # A voxel that touches the small cube at a corner only is a piece of
    # its own: pieces connect through faces.
    map.set(2, 2, 2, LabelId(1))
    # Another label is not part of any piece.
    map.set(11, 0, 0, LabelId(7))
    var pieces = label_pieces(map, LabelId(1))
    assert_equal(len(pieces.sizes), 4)
    assert_equal(pieces.sizes[0], 27)
    assert_equal(pieces.sizes[1], 8)
    assert_equal(pieces.sizes[2], 1)
    assert_equal(pieces.sizes[3], 1)
    assert_true(pieces.map.get(5, 5, 5) == LabelId(1))
    assert_true(pieces.map.get(0, 0, 0) == LabelId(2))
    # Of the two single voxels, the one with the lower index comes first.
    assert_true(pieces.map.get(2, 2, 2) == LabelId(3))
    assert_true(pieces.map.get(10, 10, 10) == LabelId(4))
    assert_true(pieces.map.get(11, 0, 0) == BACKGROUND)
    assert_almost_equal(
        pieces.volumes[0].to(CUBIC_METER), 27 * 1e-9, rtol=1e-12
    )
    assert_equal(keep_largest(map, LabelId(1)).voxels(LabelId(1)), 27)


def test_only_255_pieces_get_a_label() raises:
    # 256 single voxels, none touching another by a face.
    var map = LabelMap(ImageVolume(32, 16, 1, _mm(1), _mm(1), _mm(1)))
    for j in range(16):
        for i in range(32):
            if (i + j) % 2 == 0:
                map.set(i, j, 0, LabelId(1))
    var pieces = label_pieces(map, LabelId(1))
    assert_equal(len(pieces.sizes), 256)
    var labeled = 0
    for index in range(pieces.map.count()):
        if pieces.map.labels[index] != 0:
            labeled += 1
    assert_equal(labeled, 255)
    # The last voxel, of the highest index, is the one left out.
    assert_true(pieces.map.get(31, 15, 0) == BACKGROUND)


def test_refusals() raises:
    var map = LabelMap(ImageVolume(2, 2, 2, _mm(1), _mm(1), _mm(1)))
    var whole = map.copy()
    _box(whole, 0, 2, 4)
    var one = label_pieces(whole, LabelId(4))
    assert_equal(len(one.sizes), 1)
    assert_true(one.map.get(1, 1, 1) == LabelId(1))
    with assert_raises(contains="no voxels"):
        _ = label_pieces(map, LabelId(1))
    with assert_raises(contains="other than the background"):
        _ = label_pieces(map, BACKGROUND)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
