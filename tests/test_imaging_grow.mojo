# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Regions grown from seeds by their own statistics."""

from extensions.imaging.grow import confidence_connected
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from std.math import inf, nan, sin
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length64


def _volume(n: Int) raises -> ImageVolume:
    var mm = Length64(1.0, MILLIMETER64)
    return ImageVolume(n, n, n, mm, mm, mm)


def _box() raises -> ImageVolume:
    """A box of about 100 in a background of about 0, with a little
    texture in both."""
    var volume = _volume(12)
    for k in range(12):
        for j in range(12):
            for i in range(12):
                var texture = 2.0 * sin(Float64(i * 7 + j * 3 + k * 5))
                var inside = (
                    i >= 3
                    and i <= 8
                    and j >= 2
                    and j <= 9
                    and k >= 4
                    and k <= 7
                )
                volume.set(
                    i, j, k, Float32((100.0 if inside else 0.0) + texture)
                )
    return volume^


def test_a_box_grows_to_its_edge() raises:
    var volume = _box()
    var map = confidence_connected(volume, [(5, 5, 5)], 2.5, 3, 1, LabelId(2))
    # 6 by 8 by 4 voxels, and nothing past the edge.
    assert_equal(map.voxels(LabelId(2)), 6 * 8 * 4)
    assert_true(map.get(3, 2, 4) == LabelId(2))
    assert_true(map.get(2, 2, 4) == BACKGROUND)
    # Two seeds in the box, and no iteration, give the same box.
    var two = confidence_connected(
        volume, [(4, 4, 5), (7, 8, 6)], 2.5, 0, 1, LabelId(1)
    )
    assert_equal(two.voxels(LabelId(1)), 6 * 8 * 4)
    # A seed given twice counts once.
    var twice = confidence_connected(
        volume, [(5, 5, 5), (5, 5, 5)], 2.5, 1, 1, LabelId(1)
    )
    assert_equal(twice.voxels(LabelId(1)), 6 * 8 * 4)
    # A seed's box at the grid's corner repeats the edge voxels.
    var corner = confidence_connected(
        volume, [(0, 0, 0)], 2.5, 1, 2, LabelId(1)
    )
    assert_equal(corner.voxels(LabelId(1)), 12 * 12 * 12 - 6 * 8 * 4)


def test_seeds_out_of_range_and_flat_regions() raises:
    # A spike in a ramp is outside the range of its own box: nothing grows.
    var ramp = _volume(5)
    for index in range(ramp.count()):
        ramp.values[index] = Float32(index % 5)
    ramp.set(2, 2, 2, 1000)
    var none = confidence_connected(ramp, [(2, 2, 2)], 1.0, 2, 1, LabelId(1))
    assert_equal(none.voxels(LabelId(1)), 0)
    # So is a dip below the range.
    ramp.set(2, 2, 2, -1000)
    var dip = confidence_connected(ramp, [(2, 2, 2)], 1.0, 2, 1, LabelId(1))
    assert_equal(dip.voxels(LabelId(1)), 0)
    # A box of radius 0 has no spread: only the seed's own value grows,
    # the plane of i = 1.
    var exact = confidence_connected(ramp, [(1, 1, 1)], 3.0, 2, 0, LabelId(1))
    assert_equal(exact.voxels(LabelId(1)), 25)
    # A flat volume fills, and its zero variance stops the iterations.
    var flat = _volume(4)
    var all = confidence_connected(flat, [(0, 0, 0)], 2.0, 5, 1, LabelId(1))
    assert_equal(all.voxels(LabelId(1)), 64)
    # A region of one voxel stops the iterations too.
    var lone = _volume(3)
    for index in range(lone.count()):
        lone.values[index] = Float32(index * 10)
    var one = confidence_connected(lone, [(1, 1, 1)], 0.01, 3, 1, LabelId(1))
    assert_equal(one.voxels(LabelId(1)), 1)
    # A value that is not a number never joins.
    flat.set(3, 3, 3, nan[DType.float32]())
    var holed = confidence_connected(flat, [(0, 0, 0)], 2.0, 1, 1, LabelId(1))
    assert_equal(holed.voxels(LabelId(1)), 63)


def test_refusals() raises:
    var volume = _volume(4)
    var one = LabelId(1)
    with assert_raises(contains="background"):
        _ = confidence_connected(volume, [(0, 0, 0)], 2, 1, 1, BACKGROUND)
    with assert_raises(contains="label"):
        _ = confidence_connected(volume, [(0, 0, 0)], 2, 1, 1, LabelId(256))
    with assert_raises(contains="one seed"):
        _ = confidence_connected(
            volume, List[Tuple[Int, Int, Int]](), 2, 1, 1, one
        )
    with assert_raises(contains="outside"):
        _ = confidence_connected(volume, [(0, 0, 4)], 2, 1, 1, one)
    for bad in [0.0, -1.0, inf[DType.float64]()]:
        with assert_raises(contains="multiplier"):
            _ = confidence_connected(volume, [(0, 0, 0)], bad, 1, 1, one)
    for bad in [-1, 101]:
        with assert_raises(contains="100 times"):
            _ = confidence_connected(volume, [(0, 0, 0)], 2, bad, 1, one)
    for bad in [-1, 17]:
        with assert_raises(contains="16 voxels"):
            _ = confidence_connected(volume, [(0, 0, 0)], 2, 1, bad, one)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
