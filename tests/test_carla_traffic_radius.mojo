# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent circle geometry and curvature-speed regressions for #489.

Circle samples, a right triangle and an isosceles triangle give analytic
radii without using the production side-product formula. The asymmetric
thin triangle reference comes from a 200-digit perpendicular-bisector
intersection on the exact stored Float32 coordinates. Ratio checks use
an absolute tolerance of 2e-7, under two Float32 ulps near one.
"""

from extensions.carla.opendrive import load_opendrive
from extensions.carla.traffic_manager_constants import FRICTION, GRAVITY
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    SimpleWaypointIndex,
)
from extensions.carla.traffic_manager_planning import MotionPlanStage
from extensions.carla.traffic_manager_shared import TrafficManagerShared
from extensions.carla.traffic_manager_state import (
    FLOAT_MAX,
    three_point_circle_radius,
)
from math.vector3 import Vector3
from std.math import sqrt
from std.testing import TestSuite, assert_almost_equal, assert_equal
from test_carla_traffic_manager import straight_town


def _radius_near(
    first: Vector3, middle: Vector3, last: Vector3, expected: Float64
) raises:
    var actual = three_point_circle_radius(first, middle, last).value
    assert_almost_equal(
        Float64(actual) / expected, Float64(1), atol=2e-7, rtol=0
    )


def test_translated_circles_and_both_turn_orientations() raises:
    for center in [
        Vector3(0, 0, 0),
        Vector3(1000, 0, 0),
        Vector3(10000, 0, 0),
        Vector3(-10000, 0, 0),
        Vector3(10000, -20000, 0),
        Vector3(1048576, -1048576, 0),
    ]:
        for radius in [Float32(1), Float32(5), Float32(32)]:
            var a = center + Vector3(radius, 0, 7)
            var b = center + Vector3(0, radius, -9)
            var c = center + Vector3(-radius, 0, 100)
            _radius_near(a, b, c, Float64(radius))
            _radius_near(c, b, a, Float64(radius))
            _radius_near(b, a, c, Float64(radius))


def test_uniform_scale_law_and_extreme_representable_radii() raises:
    for radius in [
        Float32(0.00048828125),
        Float32(0.0009765625),
        Float32(0.03125),
        Float32(1),
        Float32(1048576),
        Float32(1.152921504606847e18),
        Float32(1.2676506002282294e30),
        Float32(1.7014118346046923e38),
        FLOAT_MAX,
    ]:
        _radius_near(
            Vector3(radius, 0, 0),
            Vector3(0, radius, 0),
            Vector3(-radius, 0, 0),
            Float64(radius),
        )
    # A 3-4-5 right triangle has radius half its hypotenuse.
    _radius_near(Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(0, 4, 0), 2.5)


def test_absolute_near_line_threshold_is_retained() raises:
    # EPSILON is 2^-22 square meters; this symmetric determinant is 2h.
    for rise in [
        Float32(0),
        Float32(2.9802322387695312e-8),
        Float32(5.960464477539063e-8),
    ]:
        assert_equal(
            three_point_circle_radius(
                Vector3(0, 0, 0), Vector3(1, rise, 0), Vector3(2, 0, 0)
            ).value,
            FLOAT_MAX,
        )
    var rise = Float32(1.1920928955078125e-7)
    var expected = (1 + Float64(rise) * Float64(rise)) / (2 * Float64(rise))
    _radius_near(
        Vector3(0, 0, 0), Vector3(1, rise, 0), Vector3(2, 0, 0), expected
    )
    # The same law deliberately stops at the retained absolute cutoff.
    for radius in [Float32(0.0001220703125), Float32(0.000244140625)]:
        assert_equal(
            three_point_circle_radius(
                Vector3(radius, 0, 0),
                Vector3(0, radius, 0),
                Vector3(-radius, 0, 0),
            ).value,
            FLOAT_MAX,
        )
    assert_equal(
        three_point_circle_radius(
            Vector3(1, 1, 0), Vector3(1, 1, 2), Vector3(1, 1, 3)
        ).value,
        FLOAT_MAX,
    )
    assert_equal(
        three_point_circle_radius(
            Vector3(-10000, 7, 0), Vector3(-9999, 8, 0), Vector3(-9998, 9, 0)
        ).value,
        FLOAT_MAX,
    )


def test_exact_threshold_comparison_retains_tiny_excess() raises:
    var tiny = Float32(8.271806125530277e-25)  # 2^-80
    var a = Vector3(1, 0, 0)
    var b = Vector3(0, 1.1920928955078125e-7, 0)
    var above = Vector3(tiny, -tiny, 0)
    _radius_near(a, b, above, 0.5000000000000036)
    _radius_near(above, b, a, 0.5000000000000036)
    assert_equal(
        three_point_circle_radius(a, b, Vector3(tiny, tiny, 0)).value, FLOAT_MAX
    )
    assert_equal(
        three_point_circle_radius(a, b, Vector3(0, 0, 0)).value, FLOAT_MAX
    )


def test_shallow_finite_turns_have_no_relative_angle_cutoff() raises:
    var rise = Float32(0.01)
    var expected = (2500 + Float64(rise) * Float64(rise)) / (2 * Float64(rise))
    _radius_near(
        Vector3(0, 0, 0), Vector3(50, rise, 0), Vector3(100, 0, 0), expected
    )
    # The last y coordinate differs from 2 by one stored Float32 ulp.
    _radius_near(
        Vector3(0, 0, 0),
        Vector3(1048576, 1, 0),
        Vector3(2097152, 2.000000238418579, 0),
        4.611686018433679e18,
    )
    # Translating from the distant point rounds two edges to the same
    # Float64 values. The exact-product determinant still keeps the turn.
    var far = Float32(1.2089258196146292e24)  # 2^80
    var a = Vector3(far, far, 0)
    var b = Vector3(1, 0, 0)
    var c = Vector3(0, 1, 0)
    var radius = Float64(far) / sqrt(Float64(2))
    _radius_near(a, b, c, radius)
    _radius_near(b, c, a, radius)
    _radius_near(c, a, b, radius)
    _radius_near(c, b, a, radius)


def test_radius_across_arithmetic_filter_boundary() raises:
    # The perpendicular bisectors meet at ((1-y)/2, (1+y)/2).
    # The arithmetic budget changes path between y=1+4 and y=1+5
    # stored Float32 ulps. Both paths must keep the analytic radius.
    for y in [
        Float32(1.0000003576278687),
        Float32(1.0000004768371582),
        Float32(1.0000005960464478),
    ]:
        var expected = sqrt((1 + Float64(y) * Float64(y)) * 0.5)
        _radius_near(
            Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(1, y, 0), expected
        )
        _radius_near(
            Vector3(1, y, 0), Vector3(1, 1, 0), Vector3(0, 0, 0), expected
        )


def test_unrepresentable_radius_uses_finite_sentinel() raises:
    assert_equal(
        three_point_circle_radius(
            Vector3(0, 0, 0),
            Vector3(1.329227995784916e36, 1, 0),
            Vector3(2.658455991569832e36, 2.000000238418579, 0),
        ).value,
        FLOAT_MAX,
    )


def test_curvature_speed_translation_and_wide_intermediate() raises:
    var map = load_opendrive(straight_town())
    var local = InMemoryMap()
    local.set_up(map)
    var shared = TrafficManagerShared(local^, 42)
    var stage = MotionPlanStage()
    var path: List[SimpleWaypointIndex] = [
        SimpleWaypointIndex(0),
        SimpleWaypointIndex(1),
        SimpleWaypointIndex(2),
    ]
    for radius in [Float32(1), Float32(5), Float32(1.7014118346046923e38)]:
        var expected = sqrt(
            Float64(radius) * Float64(FRICTION) * Float64(GRAVITY.value)
        )
        for origin in [Float32(0), Float32(10000), Float32(-10000)]:
            shared.local_map.waypoints[0].transform.location = Vector3(
                origin + radius, 0, 0
            )
            shared.local_map.waypoints[1].transform.location = Vector3(
                origin, radius, 0
            )
            shared.local_map.waypoints[2].transform.location = Vector3(
                origin - radius, 0, 0
            )
            var speed = stage.get_turn_target_velocity(path, 0.5, shared)
            assert_almost_equal(
                Float64(speed) / expected, Float64(1), atol=2e-7, rtol=0
            )
            # This helper is not the caller's configured-speed clamp.
            assert_equal(min(Float32(0.5), speed), 0.5)
    shared.local_map.waypoints[0].transform.location = Vector3(0, 0, 0)
    shared.local_map.waypoints[1].transform.location = Vector3(1, 0, 0)
    shared.local_map.waypoints[2].transform.location = Vector3(2, 0, 0)
    var expected = sqrt(
        Float64(FLOAT_MAX) * Float64(FRICTION) * Float64(GRAVITY.value)
    )
    var speed = stage.get_turn_target_velocity(path, 8, shared)
    assert_almost_equal(
        Float64(speed) / expected, Float64(1), atol=2e-7, rtol=0
    )
    assert_equal(min(Float32(8), speed), 8.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
