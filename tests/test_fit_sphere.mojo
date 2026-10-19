# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `cameras.fit_sphere`."""

from cameras.fit_sphere import (
    FARTHEST,
    FIT_MARGIN,
    NEAREST,
    fit_distance,
    fit_sphere,
)
from cameras.perspective_camera import PerspectiveCamera
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-5)


def _camera(degrees: Float32) raises -> PerspectiveCamera:
    """Return a camera with a field of view, looking down -z from the origin.

    Args:
        degrees: The vertical field of view, in degrees.

    Returns:
        The camera.

    Raises:
        Error: If the camera is refused.
    """
    return PerspectiveCamera(
        Angle(degrees, DEGREE),
        Float32(1.5),
        Length(0.1, METER),
        Length(100.0, METER),
    )


def test_a_ninety_degree_view_stands_off_by_the_radius_over_sine_45() raises:
    var distance = fit_distance(Length(2.0, METER), Angle(90.0, DEGREE))
    assert_almost_equal(Float64(distance.value), 2.8284271, atol=TOLERANCE)


def test_a_fifty_degree_view_matches_the_three_js_example() raises:
    # radius / sin(25 degrees), the example's `distance` before its margin.
    var distance = fit_distance(Length(1.0, METER), Angle(50.0, DEGREE))
    assert_almost_equal(Float64(distance.value), 2.3662016, atol=TOLERANCE)


def test_the_distance_refuses_a_radius_that_is_not_positive() raises:
    for radius in [
        Float32(0),
        Float32(-1),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises(contains="radius"):
            _ = fit_distance(Length(radius, METER), Angle(50.0, DEGREE))


def test_the_distance_refuses_a_field_of_view_outside_zero_to_pi() raises:
    for degrees in [Float32(0), Float32(-5), Float32(180), Float32(200)]:
        with assert_raises(contains="field of view"):
            _ = fit_distance(Length(1.0, METER), Angle(degrees, DEGREE))
    with assert_raises(contains="field of view"):
        _ = fit_distance(
            Length(1.0, METER), Angle(nan[DType.float32](), DEGREE)
        )


def test_the_camera_stands_at_the_margin_on_the_chosen_side() raises:
    var camera = _camera(50.0)
    var distance = fit_sphere(
        camera, Vector3(1, 2, 3), Length(1.0, METER), Vector3(0, 0, 4)
    )
    assert_almost_equal(
        Float64(distance.value), 2.3662016 * Float64(FIT_MARGIN), atol=TOLERANCE
    )
    assert_almost_equal(Float64(camera.position.x), 1.0, atol=TOLERANCE)
    assert_almost_equal(Float64(camera.position.y), 2.0, atol=TOLERANCE)
    assert_almost_equal(
        Float64(camera.position.z),
        3.0 + Float64(distance.value),
        atol=TOLERANCE,
    )
    assert_equal(camera.target.x, 1.0)
    assert_equal(camera.target.y, 2.0)
    assert_equal(camera.target.z, 3.0)


def test_the_direction_is_normalized_and_the_margin_is_a_factor() raises:
    var camera = _camera(90.0)
    var distance = fit_sphere(
        camera,
        Vector3(0, 0, 0),
        Length(1.0, METER),
        Vector3(0, 3, 4),
        margin=2.0,
    )
    assert_almost_equal(Float64(distance.value), 1.4142136 * 2, atol=TOLERANCE)
    assert_almost_equal(
        Float64(camera.position.y), 0.6 * Float64(distance.value), atol=1e-4
    )
    assert_almost_equal(
        Float64(camera.position.z), 0.8 * Float64(distance.value), atol=1e-4
    )


def test_the_fit_refuses_a_margin_that_is_not_positive() raises:
    var camera = _camera(50.0)
    for margin in [
        Float32(0),
        Float32(-1),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises(contains="margin"):
            _ = fit_sphere(
                camera,
                Vector3(0, 0, 0),
                Length(1.0, METER),
                Vector3(0, 0, 1),
                margin=margin,
            )


def test_the_fit_refuses_a_direction_that_is_zero_or_not_finite() raises:
    var camera = _camera(50.0)
    for side in [
        Vector3(0, 0, 0),
        Vector3(inf[DType.float32](), 0, 0),
        Vector3(nan[DType.float32](), 1, 0),
    ]:
        with assert_raises(contains="direction"):
            _ = fit_sphere(camera, Vector3(0, 0, 0), Length(1.0, METER), side)


def test_the_planes_follow_the_tight_distance_and_ignore_the_margin() raises:
    var camera = _camera(50.0)
    # A sphere of radius 100 is 236.62 meters off when it fits: the near plane
    # is a thousandth of that, and the far plane ten times it.
    _ = fit_sphere(
        camera,
        Vector3(0, 0, 0),
        Length(100.0, METER),
        Vector3(0, 0, 1),
        margin=3.0,
    )
    assert_almost_equal(Float64(camera.near.value), 0.23662016, atol=1e-5)
    assert_almost_equal(Float64(camera.far.value), 2366.2016, atol=1e-2)


def test_a_small_sphere_leaves_the_planes_at_their_least() raises:
    var camera = _camera(50.0)
    _ = fit_sphere(
        camera, Vector3(0, 0, 0), Length(0.01, METER), Vector3(0, 0, 1)
    )
    assert_equal(camera.near.value, NEAREST)
    assert_equal(camera.far.value, FARTHEST)


def test_the_fit_leaves_the_camera_alone_when_it_refuses() raises:
    var camera = _camera(50.0)
    camera.place(Vector3(7, 8, 9), Vector3(0, 0, 0))
    with assert_raises():
        _ = fit_sphere(
            camera, Vector3(0, 0, 0), Length(-1.0, METER), Vector3(0, 0, 1)
        )
    assert_equal(camera.position.x, 7.0)
    assert_equal(camera.position.y, 8.0)
    assert_equal(camera.position.z, 9.0)


def test_the_distance_refuses_finite_inputs_that_overflow() raises:
    with assert_raises(contains="fit distance"):
        _ = fit_distance(Length(3e38, METER), Angle(1, DEGREE))


def test_the_fit_refuses_nonfinite_centers_without_changing_the_camera() raises:
    for center in [
        Vector3(nan[DType.float32](), 0, 0),
        Vector3(0, inf[DType.float32](), 0),
        Vector3(0, 0, -inf[DType.float32]()),
    ]:
        var camera = _camera(90)
        camera.place(Vector3(7, 8, 9), Vector3(1, 2, 3))
        with assert_raises(contains="center"):
            _ = fit_sphere(camera, center, Length(1, METER), Vector3(0, 0, 1))
        _assert_unchanged(camera)


def _assert_unchanged(camera: PerspectiveCamera) raises:
    assert_equal(camera.position.x, 7.0)
    assert_equal(camera.position.y, 8.0)
    assert_equal(camera.position.z, 9.0)
    assert_equal(camera.target.x, 1.0)
    assert_equal(camera.target.y, 2.0)
    assert_equal(camera.target.z, 3.0)
    assert_equal(camera.near.value, Float32(0.1))
    assert_equal(camera.far.value, 100.0)


def test_the_fit_checks_derived_values_before_changing_the_camera() raises:
    var camera = _camera(90)
    camera.place(Vector3(7, 8, 9), Vector3(1, 2, 3))
    with assert_raises(contains="fit distance"):
        _ = fit_sphere(
            camera,
            Vector3(0, 0, 0),
            Length(2, METER),
            Vector3(0, 0, 1),
            margin=3e38,
        )
    _assert_unchanged(camera)
    with assert_raises(contains="far plane"):
        _ = fit_sphere(
            camera, Vector3(0, 0, 0), Length(3e37, METER), Vector3(0, 0, 1)
        )
    _assert_unchanged(camera)
    with assert_raises(contains="position"):
        _ = fit_sphere(
            camera,
            Vector3(0, 0, 3e38),
            Length(1e37, METER),
            Vector3(0, 0, 1),
            margin=10,
        )
    _assert_unchanged(camera)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
