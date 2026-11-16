# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Overlap and surface distances of two segmentations."""

from extensions.imaging.compare import (
    LabelOverlap,
    compare_labels,
    label_overlaps,
    mean_dice,
    percentile,
    surface_voxels,
)
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import CUBIC_METER, METER, MILLIMETER64, Length64

comptime MM = 0.001


def _map(nx: Int, ny: Int, nz: Int, sx: Float64) raises -> LabelMap:
    var mm = Length64(1.0, MILLIMETER64)
    return LabelMap(ImageVolume(nx, ny, nz, Length64(sx, MILLIMETER64), mm, mm))


def _fill(
    mut map: LabelMap,
    label: Int,
    i0: Int,
    i1: Int,
    j0: Int,
    j1: Int,
    k0: Int,
    k1: Int,
) raises:
    for k in range(k0, k1):
        for j in range(j0, j1):
            for i in range(i0, i1):
                map.set(i, j, k, LabelId(label))


def _mask(map: LabelMap, label: Int) -> List[Bool]:
    var out = List[Bool]()
    for index in range(map.count()):
        out.append(map.labels[index] == UInt8(label))
    return out^


def _brute(
    map: LabelMap, from_surface: List[Bool], to_surface: List[Bool]
) -> List[Float64]:
    """Return each directed surface distance by a search of every pair."""
    var sx = map.spacing_x.to(METER)
    var sy = map.spacing_y.to(METER)
    var sz = map.spacing_z.to(METER)
    var out = List[Float64]()
    for a in range(map.count()):
        if not from_surface[a]:
            continue
        var ai = a % map.nx
        var aj = (a // map.nx) % map.ny
        var ak = a // (map.nx * map.ny)
        var best = inf[DType.float64]()
        for b in range(map.count()):
            if not to_surface[b]:
                continue
            var di = Float64(ai - b % map.nx) * sx
            var dj = Float64(aj - (b // map.nx) % map.ny) * sy
            var dk = Float64(ak - b // (map.nx * map.ny)) * sz
            best = min(best, sqrt(di * di + dj * dj + dk * dk))
        out.append(best)
    return out^


def test_one_label_against_itself() raises:
    var first = _map(12, 12, 12, 1.0)
    _fill(first, 1, 3, 8, 3, 8, 3, 8)
    var second = _map(12, 12, 12, 1.0)
    _fill(second, 4, 3, 8, 3, 8, 3, 8)
    var c = compare_labels(first, LabelId(1), second, LabelId(4))
    assert_equal(c.first_voxels, 125)
    assert_equal(c.shared_voxels, 125)
    assert_equal(c.dice, 1.0)
    assert_equal(c.jaccard, 1.0)
    assert_equal(c.hausdorff.to(METER), 0.0)
    assert_equal(c.hausdorff_95.to(METER), 0.0)
    assert_equal(c.mean_surface_distance.to(METER), 0.0)
    assert_almost_equal(
        c.first_volume.to(CUBIC_METER), 125 * MM * MM * MM, rtol=1e-12
    )


def test_a_shifted_box() raises:
    # Two boxes of 4 by 4 by 4 voxels, 2 voxels apart along i, with voxels
    # 0.5 mm wide along i: half of each overlaps the other.
    var map = _map(12, 10, 10, 0.5)
    _fill(map, 1, 2, 6, 2, 6, 2, 6)
    var second = map.copy()
    for index in range(second.count()):
        second.labels[index] = 0
    _fill(second, 2, 4, 8, 2, 6, 2, 6)
    var c = compare_labels(map, LabelId(1), second, LabelId(2))
    assert_equal(c.shared_voxels, 32)
    assert_almost_equal(c.dice, 0.5)
    assert_almost_equal(c.jaccard, 1.0 / 3.0)
    # The far faces are the shift apart: 2 voxels of 0.5 mm.
    assert_almost_equal(c.hausdorff.to(METER), 1.0 * MM, rtol=1e-12)
    # The surface distances match a search of every pair.
    var surface_a = surface_voxels(map, _mask(map, 1))
    var surface_b = surface_voxels(second, _mask(second, 2))
    var ab = _brute(map, surface_a, surface_b)
    var ba = _brute(map, surface_b, surface_a)
    var sum = 0.0
    for d in ab:
        sum += d
    for d in ba:
        sum += d
    assert_almost_equal(
        c.mean_surface_distance.to(METER),
        sum / Float64(len(ab) + len(ba)),
        rtol=1e-12,
    )
    var both = ab.copy()
    both.extend(ba.copy())
    assert_almost_equal(
        c.hausdorff_95.to(METER), percentile(both, 95), rtol=1e-12
    )


def test_two_labels_of_one_map() raises:
    # Side by side, with no overlap.
    var map = _map(12, 8, 8, 1.0)
    _fill(map, 1, 1, 5, 2, 6, 2, 6)
    _fill(map, 2, 5, 9, 2, 6, 2, 6)
    var c = compare_labels(map, LabelId(1), map, LabelId(2))
    assert_equal(c.shared_voxels, 0)
    assert_equal(c.dice, 0.0)
    assert_equal(c.jaccard, 0.0)
    assert_almost_equal(c.hausdorff.to(METER), 4 * MM, rtol=1e-12)
    assert_true(c.mean_surface_distance.to(METER) > 0)


def test_surface_voxels() raises:
    # A cube of 3 voxels inside the grid: all but its center.
    var map = _map(7, 7, 7, 1.0)
    _fill(map, 1, 2, 5, 2, 5, 2, 5)
    var count = 0
    for flag in surface_voxels(map, _mask(map, 1)):
        if flag:
            count += 1
    assert_equal(count, 26)
    # A label that fills the grid: the edge is its surface.
    var full = _map(4, 4, 4, 1.0)
    _fill(full, 1, 0, 4, 0, 4, 0, 4)
    count = 0
    for flag in surface_voxels(full, _mask(full, 1)):
        if flag:
            count += 1
    assert_equal(count, 56)
    with assert_raises(contains="one flag per voxel"):
        _ = surface_voxels(full, List[Bool]())


def test_percentiles() raises:
    var values: List[Float64] = [4, 1, 3, 2]
    assert_almost_equal(percentile(values, 50), 2.5)
    # Rank 0.95 * 3 = 2.85, between 3 and 4.
    assert_almost_equal(percentile(values, 95), 3.85)
    assert_equal(percentile(values, 100), 4.0)
    assert_equal(percentile(values, 0), 1.0)
    var one: List[Float64] = [7]
    assert_equal(percentile(one, 95), 7.0)
    with assert_raises(contains="at least one value"):
        _ = percentile(List[Float64](), 50)
    with assert_raises(contains="from 0 to 100"):
        _ = percentile(values, -1)
    with assert_raises(contains="from 0 to 100"):
        _ = percentile(values, 101)
    with assert_raises(contains="from 0 to 100"):
        _ = percentile(values, nan[DType.float64]())


def test_a_table_of_many_labels() raises:
    # Label 1 matches, label 2 overlaps by half, label 3 is only in the
    # first map, and label 5 only in the second.
    var first = _map(12, 8, 8, 1.0)
    var second = _map(12, 8, 8, 1.0)
    _fill(first, 1, 0, 2, 0, 2, 0, 2)
    _fill(second, 1, 0, 2, 0, 2, 0, 2)
    _fill(first, 2, 4, 8, 0, 2, 0, 2)
    _fill(second, 2, 6, 10, 0, 2, 0, 2)
    _fill(first, 3, 0, 1, 5, 6, 5, 6)
    _fill(second, 5, 11, 12, 7, 8, 7, 8)
    var table = label_overlaps(first, second)
    assert_equal(len(table), 4)
    assert_equal(table[0].label.value, 1)
    assert_equal(table[0].dice, 1.0)
    assert_equal(table[1].label.value, 2)
    assert_equal(table[1].first_voxels, 16)
    assert_equal(table[1].shared_voxels, 8)
    assert_almost_equal(table[1].dice, 0.5)
    assert_almost_equal(table[1].jaccard, 1.0 / 3.0)
    assert_equal(table[2].label.value, 3)
    assert_equal(table[2].second_voxels, 0)
    assert_equal(table[2].dice, 0.0)
    assert_equal(table[3].label.value, 5)
    assert_equal(table[3].first_voxels, 0)
    assert_almost_equal(mean_dice(table), 1.5 / 4.0)
    # Each entry agrees with the comparison of its label alone.
    var alone = compare_labels(first, LabelId(2), second, LabelId(2))
    assert_almost_equal(table[1].dice, alone.dice)
    # Two empty maps have no label to list.
    assert_equal(len(label_overlaps(_map(4, 4, 4, 1.0), _map(4, 4, 4, 1.0))), 0)
    with assert_raises(contains="at least one label"):
        _ = mean_dice(List[LabelOverlap]())
    with assert_raises(contains="different grids"):
        _ = label_overlaps(first, _map(12, 8, 9, 1.0))
    with assert_raises(contains="different grids"):
        _ = label_overlaps(first, _map(11, 8, 8, 1.0))
    with assert_raises(contains="different grids"):
        _ = label_overlaps(first, _map(12, 9, 8, 1.0))


def test_refusals() raises:
    var map = _map(8, 8, 8, 1.0)
    _fill(map, 1, 2, 5, 2, 5, 2, 5)
    with assert_raises(contains="different grids"):
        _ = compare_labels(map, LabelId(1), _map(9, 8, 8, 1.0), LabelId(1))
    with assert_raises(contains="different grids"):
        _ = compare_labels(map, LabelId(1), _map(8, 9, 8, 1.0), LabelId(1))
    with assert_raises(contains="different grids"):
        _ = compare_labels(map, LabelId(1), _map(8, 8, 9, 1.0), LabelId(1))
    var wide = map.copy()
    wide.spacing_x = Length64(2.0, MILLIMETER64)
    with assert_raises(contains="different spacings"):
        _ = compare_labels(map, LabelId(1), wide, LabelId(1))
    var tall = map.copy()
    tall.spacing_y = Length64(2.0, MILLIMETER64)
    with assert_raises(contains="different spacings"):
        _ = compare_labels(map, LabelId(1), tall, LabelId(1))
    var deep = map.copy()
    deep.spacing_z = Length64(2.0, MILLIMETER64)
    with assert_raises(contains="different spacings"):
        _ = compare_labels(map, LabelId(1), deep, LabelId(1))
    with assert_raises(contains="background"):
        _ = compare_labels(map, BACKGROUND, map, LabelId(1))
    with assert_raises(contains="no voxels"):
        _ = compare_labels(map, LabelId(1), map, LabelId(9))
    with assert_raises(contains="label"):
        _ = compare_labels(map, LabelId(1), map, LabelId(256))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
