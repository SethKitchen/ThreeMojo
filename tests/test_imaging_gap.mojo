# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Distances between two labels."""

from extensions.imaging.gap import distance_from_label, label_gap, volume_within
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.measure import label_statistics
from std.math import inf, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import CUBIC_METER, METER, MILLIMETER64, Length64


def _map() raises -> LabelMap:
    """Return an empty map of 10 by 8 by 6 voxels of 0.5 by 0.8 by 2 mm."""
    return LabelMap(
        ImageVolume(
            10,
            8,
            6,
            Length64(0.5, MILLIMETER64),
            Length64(0.8, MILLIMETER64),
            Length64(2.0, MILLIMETER64),
        )
    )


def _boxes() raises -> LabelMap:
    """Return two boxes along i: label 1 at i 2 to 3, label 2 at i 7 to 8."""
    var map = _map()
    for k in range(1, 4):
        for j in range(2, 5):
            for i in [2, 3]:
                map.set(i, j, k, LabelId(1))
            for i in [7, 8]:
                map.set(i, j, k, LabelId(2))
    return map^


def test_the_gap_of_two_boxes() raises:
    var map = _boxes()
    var gap = label_gap(map, LabelId(1), LabelId(2))
    # Four voxels of 0.5 mm along i.
    assert_almost_equal(gap.distance.to(MILLIMETER64), 2.0)
    assert_equal(gap.first_voxel[0], 3)
    assert_equal(gap.first_voxel[1], 2)
    assert_equal(gap.first_voxel[2], 1)
    assert_equal(gap.second_voxel[0], 7)
    assert_equal(gap.second_voxel[1], 2)
    assert_equal(gap.second_voxel[2], 1)
    # The gap is the same both ways.
    var back = label_gap(map, LabelId(2), LabelId(1))
    assert_almost_equal(back.distance.to(MILLIMETER64), 2.0)
    assert_equal(back.first_voxel[0], 7)
    # The distance map, read at the voxels of the second box.
    var stats = label_statistics(
        map, distance_from_label(map, LabelId(1)), LabelId(2)
    )
    assert_almost_equal(stats.minimum, 2.0, rtol=1e-6)
    assert_almost_equal(stats.mean, 2.25, rtol=1e-6)
    assert_almost_equal(stats.maximum, 2.5, rtol=1e-6)


def test_a_slanted_and_a_touching_pair() raises:
    var map = _map()
    map.set(1, 1, 1, LabelId(3))
    map.set(4, 5, 2, LabelId(4))
    var gap = label_gap(map, LabelId(3), LabelId(4))
    var expected = sqrt(1.5**2 + 3.2**2 + 2.0**2)
    assert_almost_equal(gap.distance.to(MILLIMETER64), expected)
    # A voxel of label 3 nearer to the far one moves the gap.
    map.set(4, 5, 4, LabelId(3))
    gap = label_gap(map, LabelId(3), LabelId(4))
    assert_almost_equal(gap.distance.to(MILLIMETER64), 4.0)
    assert_equal(gap.first_voxel[2], 4)
    # Two labels that share a face are one spacing apart.
    map.set(4, 5, 3, LabelId(3))
    gap = label_gap(map, LabelId(3), LabelId(4))
    assert_almost_equal(gap.distance.to(MILLIMETER64), 2.0)
    assert_equal(gap.first_voxel[2], 3)


def test_the_distance_map() raises:
    var map = _map()
    var seeds: List[Tuple[Int, Int, Int]] = [(1, 1, 1), (8, 6, 4), (5, 0, 0)]
    for s in seeds:
        map.set(s[0], s[1], s[2], LabelId(2))
    map.set(0, 7, 5, LabelId(5))
    var field = distance_from_label(map, LabelId(2))
    # Every voxel against a search of every seed.
    for k in range(6):
        for j in range(8):
            for i in range(10):
                var least = inf[DType.float64]()
                for s in seeds:
                    var d = sqrt(
                        (Float64(i - s[0]) * 0.5) ** 2
                        + (Float64(j - s[1]) * 0.8) ** 2
                        + (Float64(k - s[2]) * 2.0) ** 2
                    )
                    least = min(least, d)
                assert_almost_equal(
                    Float64(field.get(i, j, k)), least, rtol=1e-6
                )
    assert_equal(field.get(1, 1, 1), 0)


def test_volume_within() raises:
    var map = _boxes()
    var voxel = 0.5 * 0.8 * 2.0 * 1e-9
    var one = LabelId(1)
    var two = LabelId(2)
    # The nine voxels at i = 7 are 2 mm away, and those at i = 8 are 2.5 mm.
    var near = volume_within(map, one, two, Length64(2.0, MILLIMETER64))
    assert_almost_equal(near.to(CUBIC_METER), 9 * voxel, rtol=1e-12)
    var all = volume_within(map, one, two, Length64(2.5, MILLIMETER64))
    assert_almost_equal(all.to(CUBIC_METER), 18 * voxel, rtol=1e-12)
    var none = volume_within(map, one, two, Length64(1.9, MILLIMETER64))
    assert_equal(none.to(CUBIC_METER), 0.0)
    assert_equal(
        volume_within(map, one, two, Length64(0, METER)).to(CUBIC_METER), 0.0
    )


def test_refusals() raises:
    var map = _boxes()
    var one = LabelId(1)
    var two = LabelId(2)
    with assert_raises(contains="background"):
        _ = distance_from_label(map, BACKGROUND)
    with assert_raises(contains="no voxels"):
        _ = distance_from_label(map, LabelId(9))
    with assert_raises(contains="label"):
        _ = distance_from_label(map, LabelId(256))
    with assert_raises(contains="background"):
        _ = label_gap(map, one, BACKGROUND)
    with assert_raises(contains="no voxels"):
        _ = label_gap(map, LabelId(9), two)
    with assert_raises(contains="different"):
        _ = label_gap(map, one, one)
    with assert_raises(contains="different"):
        _ = volume_within(map, two, two, Length64(1, METER))
    with assert_raises(contains="limit"):
        _ = volume_within(map, one, two, Length64(-1, METER))
    with assert_raises(contains="limit"):
        _ = volume_within(map, one, two, Length64(inf[DType.float64](), METER))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
