# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Label surfaces written as STL files in millimeters."""

from core.buffer_geometry import BufferGeometry
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.printing import label_stl, printable_stl
from extensions.imaging.smooth import enclosed_volume, smooth_surface
from extensions.imaging.labels import label_surface
from geometries.box import box
from loaders.stl import is_binary_stl, parse_stl
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import CUBIC_METER, METER, MILLIMETER64, Length, Length64


def test_a_box_prints_in_millimeters() raises:
    var cube = box(
        Length(0.02, METER), Length(0.03, METER), Length(0.04, METER)
    )
    var bytes = printable_stl(cube)
    assert_true(is_binary_stl(bytes))
    var model = parse_stl(bytes)
    assert_equal(model.geometry.triangle_count(), 12)
    var bounds = model.geometry.bounding_box()
    # A box of 20 by 30 by 40 mm, centered on the origin.
    assert_almost_equal(Float64(bounds.max.x - bounds.min.x), 20.0, atol=1e-4)
    assert_almost_equal(Float64(bounds.max.z - bounds.min.z), 40.0, atol=1e-4)
    with assert_raises(contains="position"):
        _ = printable_stl(BufferGeometry())


def test_a_label_prints_its_smoothed_surface() raises:
    var mm = Length64(1.0, MILLIMETER64)
    var map = LabelMap(ImageVolume(8, 8, 8, mm, mm, mm))
    for k in range(2, 6):
        for j in range(2, 6):
            for i in range(2, 6):
                map.set(i, j, k, LabelId(3))
    var bytes = label_stl(map, LabelId(3), 5)
    var model = parse_stl(bytes)
    var smooth = smooth_surface(label_surface(map, LabelId(3)), 5)
    assert_equal(model.geometry.triangle_count(), smooth.triangle_count())
    # The file's bounds are the surface's, in millimeters.
    var bounds = model.geometry.bounding_box()
    var meters = smooth.bounding_box()
    assert_almost_equal(
        Float64(bounds.max.x - bounds.min.x),
        Float64(meters.max.x - meters.min.x) * 1000,
        rtol=1e-5,
    )
    assert_true(Float64(bounds.max.x - bounds.min.x) > 3)
    # The file's volume in cubic millimeters is the surface's.
    assert_true(enclosed_volume(model.geometry).to(CUBIC_METER) > 0)
    assert_almost_equal(
        enclosed_volume(model.geometry).to(CUBIC_METER),
        enclosed_volume(smooth).to(CUBIC_METER) * 1e9,
        rtol=1e-4,
    )
    with assert_raises(contains="background"):
        _ = label_stl(map, BACKGROUND, 5)
    with assert_raises(contains="negative"):
        _ = label_stl(map, LabelId(3), -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
