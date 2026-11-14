# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Co-occurrence matrices and Haralick texture features."""

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
from extensions.imaging.texture import cooccurrence_matrix, texture_features
from std.math import inf, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Length64


def _checker() raises -> Tuple[ImageVolume, LabelMap]:
    var mm = Length64(1.0, MILLIMETER64)
    var volume = ImageVolume(4, 4, 3, mm, mm, mm)
    for k in range(3):
        for j in range(4):
            for i in range(4):
                volume.set(i, j, k, Float32((i + j + k) % 2))
    var map = LabelMap(volume)
    for index in range(map.count()):
        map.labels[index] = 1
    return (volume^, map^)


def test_a_checkerboard() raises:
    var parts = _checker()
    ref volume = parts[0]
    ref map = parts[1]
    # Neighbors along x always differ.
    var across = cooccurrence_matrix(
        volume, map, LabelId(1), K_AXIS, 0, 1, 0, 2, 0, 2
    )
    assert_equal(across[1], 12)
    assert_almost_equal(across[0][1], 0.5)
    var f = texture_features(across[0], across[1])
    assert_almost_equal(f.contrast, 1.0)
    assert_almost_equal(f.dissimilarity, 1.0)
    assert_almost_equal(f.homogeneity, 0.5)
    assert_almost_equal(f.asm, 0.5)
    assert_almost_equal(f.energy, sqrt(0.5))
    assert_almost_equal(f.correlation, -1.0)
    # Diagonal neighbors are always the same.
    var diagonal = cooccurrence_matrix(
        volume, map, LabelId(1), K_AXIS, 0, 1, 1, 2, 0, 2
    )
    assert_equal(diagonal[1], 9)
    var g = texture_features(diagonal[0], diagonal[1])
    assert_almost_equal(g.contrast, 0.0)
    assert_almost_equal(g.homogeneity, 1.0)
    assert_almost_equal(g.correlation, 1.0)
    # The other axes see the same board.
    for axis in [J_AXIS, I_AXIS]:
        var other = cooccurrence_matrix(
            volume, map, LabelId(1), axis, 1, 1, 0, 2, 0, 2
        )
        assert_almost_equal(texture_features(other[0], other[1]).contrast, 1.0)


def test_levels_labels_and_a_flat_region() raises:
    var mm = Length64(1.0, MILLIMETER64)
    var volume = ImageVolume(5, 1, 1, mm, mm, mm)
    var values: List[Float32] = [-5, 10, 30, 60, 100]
    for i in range(5):
        volume.set(i, 0, 0, values[i])
    var map = LabelMap(volume)
    for i in range(4):
        map.set(i, 0, 0, LabelId(1))
    # Four levels over 0 to 100: -5 is level 0, and 100 would be level 3.
    var m = cooccurrence_matrix(
        volume, map, LabelId(1), K_AXIS, 0, 1, 0, 4, 0, 100
    )
    # The last voxel is not in the label: three pairs, 0-0, 0-1 and 1-2.
    assert_equal(m[1], 3)
    assert_almost_equal(m[0][0 * 4 + 0], 2.0 / 6.0)
    assert_almost_equal(m[0][0 * 4 + 1], 1.0 / 6.0)
    assert_almost_equal(m[0][1 * 4 + 2], 1.0 / 6.0)
    map.set(4, 0, 0, LabelId(1))
    var top = cooccurrence_matrix(
        volume, map, LabelId(1), K_AXIS, 0, 1, 0, 4, 0, 100
    )
    assert_almost_equal(top[0][2 * 4 + 3], 1.0 / 8.0)
    # A flat region has no spread: its correlation is 1.
    var flat = ImageVolume(3, 3, 1, mm, mm, mm)
    var all = LabelMap(flat)
    for index in range(all.count()):
        all.labels[index] = 2
    var plain = cooccurrence_matrix(
        flat, all, LabelId(2), K_AXIS, 0, 0, 1, 8, 0, 1
    )
    var f = texture_features(plain[0], plain[1])
    assert_almost_equal(f.asm, 1.0)
    assert_almost_equal(f.correlation, 1.0)
    # A negative offset counts the same pairs.
    var back = cooccurrence_matrix(
        flat, all, LabelId(2), K_AXIS, 0, -1, 0, 8, 0, 1
    )
    assert_equal(back[1], 6)
    var up = cooccurrence_matrix(
        flat, all, LabelId(2), K_AXIS, 0, 0, -1, 8, 0, 1
    )
    assert_equal(up[1], 6)
    # A matrix of one's own need not be symmetric: when the second gray
    # level has no spread, the correlation is 1.
    var lopsided: List[Float64] = [0.5, 0.0, 0.5, 0.0]
    assert_almost_equal(texture_features(lopsided, 1).correlation, 1.0)


def test_refusals() raises:
    var parts = _checker()
    ref volume = parts[0]
    ref map = parts[1]
    var one = LabelId(1)
    with assert_raises(contains="background"):
        _ = cooccurrence_matrix(
            volume, map, BACKGROUND, K_AXIS, 0, 1, 0, 2, 0, 2
        )
    with assert_raises(contains="axis"):
        _ = cooccurrence_matrix(
            volume, map, one, SliceAxis(4), 0, 1, 0, 2, 0, 2
        )
    with assert_raises(contains="slice index"):
        _ = cooccurrence_matrix(volume, map, one, K_AXIS, 3, 1, 0, 2, 0, 2)
    with assert_raises(contains="slice index"):
        _ = cooccurrence_matrix(volume, map, one, J_AXIS, -1, 1, 0, 2, 0, 2)
    with assert_raises(contains="slice index"):
        _ = cooccurrence_matrix(volume, map, one, I_AXIS, 4, 1, 0, 2, 0, 2)
    with assert_raises(contains="offset"):
        _ = cooccurrence_matrix(volume, map, one, K_AXIS, 0, 0, 0, 2, 0, 2)
    with assert_raises(contains="gray levels"):
        _ = cooccurrence_matrix(volume, map, one, K_AXIS, 0, 1, 0, 1, 0, 2)
    with assert_raises(contains="gray levels"):
        _ = cooccurrence_matrix(volume, map, one, K_AXIS, 0, 1, 0, 257, 0, 2)
    with assert_raises(contains="range"):
        _ = cooccurrence_matrix(volume, map, one, K_AXIS, 0, 1, 0, 2, 2, 2)
    with assert_raises(contains="range"):
        _ = cooccurrence_matrix(
            volume, map, one, K_AXIS, 0, 1, 0, 2, -inf[DType.float64](), 2
        )
    with assert_raises(contains="range"):
        _ = cooccurrence_matrix(
            volume, map, one, K_AXIS, 0, 1, 0, 2, 0, inf[DType.float64]()
        )
    with assert_raises(contains="No pair"):
        _ = cooccurrence_matrix(volume, map, one, K_AXIS, 0, 4, 0, 2, 0, 2)
    with assert_raises(contains="No pair"):
        _ = cooccurrence_matrix(volume, map, one, K_AXIS, 0, 0, 4, 2, 0, 2)
    with assert_raises(contains="No pair"):
        _ = cooccurrence_matrix(volume, map, one, K_AXIS, 0, -4, -4, 2, 0, 2)
    with assert_raises(contains="square"):
        _ = texture_features([0.5, 0.5, 0.0], 1)
    with assert_raises(contains="square"):
        _ = texture_features(List[Float64](), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
