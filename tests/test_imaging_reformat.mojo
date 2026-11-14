# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Oblique multiplanar reformats of image volumes."""

from extensions.imaging.ids import K_AXIS, MONOCHROME1
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.overlay import render_slice
from extensions.imaging.reformat import oblique_slice
from extensions.sdf.vector import V3, normalize, v3
from std.math import inf, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _field(p: V3) -> Float64:
    """A linear field of patient position, in meters: 1000 (2x + 3y - z)."""
    return 1000.0 * (2 * p.x + 3 * p.y - p.z)


def _turned() raises -> ImageVolume:
    """A 9 by 8 by 7 volume of 2 mm voxels, turned and placed, holding
    the linear field."""
    var spacing = Length64(2, MILLIMETER64)
    var volume = ImageVolume(9, 8, 7, spacing, spacing, spacing)
    volume.axis_x = v3(0, 1, 0)
    volume.axis_y = v3(0, 0, 1)
    volume.axis_z = v3(1, 0, 0)
    volume.origin = v3(0.01, -0.02, 0.03)
    for k in range(7):
        for j in range(8):
            for i in range(9):
                var p = volume.patient_point(Float64(i), Float64(j), Float64(k))
                volume.set(i, j, k, Float32(_field(p)))
    volume.window_center = 5
    volume.window_width = 50
    volume.photometric = MONOCHROME1
    return volume^


def test_voxel_point_inverts_patient_point() raises:
    var volume = _turned()
    var q = volume.voxel_point(volume.patient_point(1.5, 2.25, 3))
    assert_almost_equal(q.x, 1.5, atol=1e-12)
    assert_almost_equal(q.y, 2.25, atol=1e-12)
    assert_almost_equal(q.z, 3, atol=1e-12)


def test_oblique_slice_matches_the_field() raises:
    var volume = _turned()
    var center = volume.patient_point(4, 3.5, 3)
    var right = normalize(v3(1, 1, 0))
    var down = normalize(v3(1, -1, 1))
    var slice = oblique_slice(
        volume,
        center,
        v3(1, 1, 0),
        v3(1, -1, 1),
        5,
        4,
        Length64(1, MILLIMETER64),
        -1000,
    )
    assert_equal(slice.nx, 5)
    assert_equal(slice.ny, 4)
    assert_equal(slice.nz, 1)
    assert_equal(slice.window_width, 50)
    assert_true(slice.photometric == MONOCHROME1)
    # Trilinear sampling is exact for a linear field.
    var worst = 0.0
    for y in range(4):
        for x in range(5):
            var p = slice.patient_point(Float64(x), Float64(y), 0)
            worst = max(worst, abs(Float64(slice.get(x, y, 0)) - _field(p)))
    assert_true(worst < 1e-3)
    # The slice is centered: its middle is the center point.
    var middle = slice.patient_point(2, 1.5, 0)
    assert_almost_equal(middle.x, center.x, atol=1e-12)
    assert_true(abs(slice.axis_x.x - right.x) < 1e-12)
    assert_true(abs(slice.axis_y.z - down.z) < 1e-12)
    # It draws as a slice.
    var image = render_slice(slice, K_AXIS, 0)
    assert_equal(image.width, 5)


def test_points_outside_take_the_outside_value() raises:
    var volume = _turned()
    var corner = volume.patient_point(0, 0, 0)
    # A slice through the first voxel reaches below the box at one corner,
    # and into it at the other.
    var slice = oblique_slice(
        volume,
        corner,
        v3(1, 0, 0),
        v3(0, 1, 0),
        3,
        3,
        Length64(2, MILLIMETER64),
        -1000,
    )
    assert_equal(slice.get(0, 0, 0), -1000)
    assert_almost_equal(slice.get(1, 1, 0), Float32(_field(corner)), atol=1e-3)
    var inner = slice.patient_point(2, 2, 0)
    assert_almost_equal(slice.get(2, 2, 0), Float32(_field(inner)), atol=1e-3)
    var far = volume.patient_point(8, 7, 6)
    var beyond = oblique_slice(
        volume,
        far,
        v3(0, 1, 0),
        v3(0, 0, 1),
        3,
        1,
        Length64(2, MILLIMETER64),
        -1000,
    )
    assert_equal(beyond.get(2, 0, 0), -1000)
    assert_true(beyond.get(1, 0, 0) != -1000)


def test_reformat_refusals() raises:
    var volume = _turned()
    var c = volume.patient_point(4, 4, 3)
    var mm = Length64(1, MILLIMETER64)
    with assert_raises(contains="finite center"):
        _ = oblique_slice(
            volume,
            v3(inf[DType.float64](), 0, 0),
            v3(1, 0, 0),
            v3(0, 1, 0),
            2,
            2,
            mm,
            0,
        )
    with assert_raises(contains="right direction"):
        _ = oblique_slice(volume, c, v3(0, 0, 0), v3(0, 1, 0), 2, 2, mm, 0)
    with assert_raises(contains="down direction"):
        _ = oblique_slice(
            volume, c, v3(1, 0, 0), v3(0, inf[DType.float64](), 0), 2, 2, mm, 0
        )
    with assert_raises(contains="must be square"):
        _ = oblique_slice(volume, c, v3(1, 0, 0), v3(1, 1, 0), 2, 2, mm, 0)
    with assert_raises(contains="8192 pixels"):
        _ = oblique_slice(volume, c, v3(1, 0, 0), v3(0, 1, 0), 0, 2, mm, 0)
    with assert_raises(contains="8192 pixels"):
        _ = oblique_slice(volume, c, v3(1, 0, 0), v3(0, 1, 0), 2, 0, mm, 0)
    with assert_raises(contains="8192 pixels"):
        _ = oblique_slice(volume, c, v3(1, 0, 0), v3(0, 1, 0), 8193, 2, mm, 0)
    with assert_raises(contains="8192 pixels"):
        _ = oblique_slice(volume, c, v3(1, 0, 0), v3(0, 1, 0), 2, 8193, mm, 0)
    with assert_raises(contains="spacing must be positive"):
        _ = oblique_slice(
            volume, c, v3(1, 0, 0), v3(0, 1, 0), 2, 2, Length64(0, METER), 0
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
