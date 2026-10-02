# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Axis-isolated numerical boundaries for vector angles and projections."""

from cameras.orthographic_camera import OrthographicCamera
from math.projection import orthographic, perspective
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import inf, pi
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def test_vector2_scaled_axis_angles_distinguish_nonzero_y() raises:
    # Squaring these finite vectors overflows, requiring robust normalization.
    # A zero x coordinate must not make a nonzero y vector count as zero.
    var y = Vector2(0, 1e30)
    var x = Vector2(1e30, 0)
    assert_almost_equal(y.angle_to(y).value, Float32(0), atol=1e-6)
    assert_almost_equal(x.angle_to(y).value, Float32(pi / 2), atol=1e-6)
    assert_almost_equal(
        y.angle_to(Vector2(0, -1e30)).value, Float32(pi), atol=1e-6
    )
    assert_almost_equal(
        y.angle_to(Vector2(0, 0)).value, Float32(pi / 2), atol=1e-6
    )
    assert_almost_equal(
        Vector2(0, 0).angle_to(y).value, Float32(pi / 2), atol=1e-6
    )


def test_vector3_scaled_axis_angles_distinguish_each_nonzero_component() raises:
    var x = Vector3(1e30, 0, 0)
    var y = Vector3(0, 1e30, 0)
    var z = Vector3(0, 0, 1e30)
    for axis in [x, y, z]:
        assert_almost_equal(axis.angle_to(axis).value, Float32(0), atol=1e-6)
        assert_almost_equal(
            axis.angle_to(Vector3(0, 0, 0)).value, Float32(pi / 2), atol=1e-6
        )
        assert_almost_equal(
            Vector3(0, 0, 0).angle_to(axis).value, Float32(pi / 2), atol=1e-6
        )
    assert_almost_equal(x.angle_to(y).value, Float32(pi / 2), atol=1e-6)
    assert_almost_equal(x.angle_to(z).value, Float32(pi / 2), atol=1e-6)
    assert_almost_equal(
        z.angle_to(Vector3(0, 0, -1e30)).value, Float32(pi), atol=1e-6
    )


def test_perspective_isolates_each_underflowing_screen_scale() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    # Finite differences and depth coefficient leave only x or y zero.
    with assert_raises(contains="representable"):
        _ = perspective(-8, 8, tiny, -tiny, tiny, 1)
    with assert_raises(contains="representable"):
        _ = perspective(-tiny, tiny, 8, -8, tiny, 1)
    var valid = perspective(-tiny, tiny, tiny, -tiny, tiny, 1)
    assert_equal(valid.elements[0], Float32(1))
    assert_equal(valid.elements[5], Float32(1))
    assert_equal(valid.elements[14], -2 * tiny)


def test_orthographic_recovers_each_overflowing_extent_independently() raises:
    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    for axis in range(3):
        var bounds: Array[Float32, 6] = [-1, 1, 1, -1, -1, 1]
        if axis == 0:
            bounds[0] = -largest
            bounds[1] = largest
        elif axis == 1:
            bounds[2] = largest
            bounds[3] = -largest
        else:
            bounds[4] = -largest
            bounds[5] = largest
        var matrix = orthographic(
            bounds[0], bounds[1], bounds[2], bounds[3], bounds[4], bounds[5]
        )
        assert_true(matrix.is_finite())
        for component in range(3):
            var expected = Float32(1)
            if component == axis:
                expected = Float32(Float64(1) / Float64(largest))
            if component == 2:
                expected = -expected
            assert_equal(matrix.elements[component * 5], expected)
            assert_equal(matrix.elements[12 + component], Float32(0))


def test_orthographic_smallest_extent_is_not_representable() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    for axis in range(3):
        var bounds: Array[Float32, 6] = [0, 1, 1, 0, 0, 1]
        if axis == 0:
            bounds[1] = tiny
        elif axis == 1:
            bounds[2] = tiny
        else:
            bounds[5] = tiny
        with assert_raises(contains="representable"):
            _ = orthographic(
                bounds[0], bounds[1], bounds[2], bounds[3], bounds[4], bounds[5]
            )


def test_positive_infinite_orthographic_zoom_is_rejected() raises:
    var camera = OrthographicCamera(
        Length(-1, METER),
        Length(1, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(0, METER),
        Length(10, METER),
    )
    camera.zoom = inf[DType.float32]()
    with assert_raises(contains="zoom must be positive"):
        camera.validate()
    camera.zoom = 2
    camera.validate()
    assert_equal(camera.zoom, Float32(2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
