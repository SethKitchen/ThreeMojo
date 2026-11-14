# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Crops of volumes and label maps to boxes of voxels."""

from extensions.imaging.crop import (
    VoxelBox,
    crop_labels,
    crop_volume,
    label_box,
)
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.sdf.vector import distance, v3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _volume() raises -> ImageVolume:
    var volume = ImageVolume(
        10,
        8,
        6,
        Length64(0.5, MILLIMETER64),
        Length64(0.8, MILLIMETER64),
        Length64(2.0, MILLIMETER64),
    )
    volume.origin = v3(0.1, -0.2, 0.05)
    volume.axis_x = v3(0, 1, 0)
    volume.axis_y = v3(-1, 0, 0)
    volume.window_center = 40
    volume.window_width = 400
    for k in range(6):
        for j in range(8):
            for i in range(10):
                volume.set(i, j, k, Float32(i + 10 * j + 100 * k))
    return volume^


def test_a_crop_keeps_values_and_place() raises:
    var volume = _volume()
    var box = VoxelBox(2, 1, 3, 6, 5, 4)
    var part = crop_volume(volume, box)
    assert_equal(part.nx, 5)
    assert_equal(part.ny, 5)
    assert_equal(part.nz, 2)
    assert_equal(part.window_width, 400.0)
    for k in range(2):
        for j in range(5):
            for i in range(5):
                assert_equal(part.get(i, j, k), volume.get(i + 2, j + 1, k + 3))
                # The same voxel has the same patient position.
                var p = part.patient_point(Float64(i), Float64(j), Float64(k))
                var q = volume.patient_point(
                    Float64(i + 2), Float64(j + 1), Float64(k + 3)
                )
                assert_true(distance(p, q) < 1e-15)
    # One voxel is a crop too.
    var one = crop_volume(volume, VoxelBox(9, 7, 5, 9, 7, 5))
    assert_equal(one.get(0, 0, 0), Float32(9 + 70 + 500))


def test_label_boxes_and_crops() raises:
    var volume = _volume()
    var map = LabelMap(volume)
    map.set(3, 2, 1, LabelId(4))
    map.set(5, 4, 2, LabelId(4))
    map.set(9, 0, 0, LabelId(1))
    var box = label_box(map, LabelId(4), 0)
    assert_equal(box.low_i, 3)
    assert_equal(box.high_j, 4)
    assert_equal(box.high_k, 2)
    # A margin grows the box, and the grid's edge cuts it.
    var grown = label_box(map, LabelId(4), 2)
    assert_equal(grown.low_i, 1)
    assert_equal(grown.low_k, 0)
    assert_equal(grown.high_i, 7)
    assert_equal(grown.high_j, 6)
    assert_equal(grown.high_k, 4)
    var wide = label_box(map, LabelId(1), 20)
    assert_equal(wide.low_i, 0)
    assert_equal(wide.high_i, 9)
    assert_equal(wide.high_j, 7)
    assert_equal(wide.high_k, 5)
    var labels = crop_labels(map, grown)
    assert_equal(labels.nx, 7)
    # The grown box starts at (1, 0, 0).
    assert_equal(grown.low_j, 0)
    assert_true(labels.get(2, 2, 1) == LabelId(4))
    assert_true(labels.get(4, 4, 2) == LabelId(4))
    assert_equal(labels.voxels(LabelId(4)), 2)
    # The crops of a volume and its map share a grid.
    var part = crop_volume(volume, grown)
    assert_equal(part.nx * part.ny * part.nz, labels.count())


def test_refusals() raises:
    var volume = _volume()
    var map = LabelMap(volume)
    map.set(3, 2, 1, LabelId(4))
    for box in [
        VoxelBox(-1, 0, 0, 1, 1, 1),
        VoxelBox(0, -1, 0, 1, 1, 1),
        VoxelBox(0, 0, -1, 1, 1, 1),
        VoxelBox(0, 0, 0, 10, 1, 1),
        VoxelBox(0, 0, 0, 1, 8, 1),
        VoxelBox(0, 0, 0, 1, 1, 6),
    ]:
        with assert_raises(contains="inside the grid"):
            _ = crop_volume(volume, box)
    for box in [
        VoxelBox(2, 0, 0, 1, 1, 1),
        VoxelBox(0, 2, 0, 1, 1, 1),
        VoxelBox(0, 0, 2, 1, 1, 1),
    ]:
        with assert_raises(contains="at least one voxel"):
            _ = crop_labels(map, box)
    with assert_raises(contains="background"):
        _ = label_box(map, BACKGROUND, 0)
    with assert_raises(contains="no voxels"):
        _ = label_box(map, LabelId(7), 0)
    with assert_raises(contains="margin"):
        _ = label_box(map, LabelId(4), -1)
    with assert_raises(contains="label"):
        _ = label_box(map, LabelId(400), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
