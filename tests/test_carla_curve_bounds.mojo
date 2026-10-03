# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Required controls for evaluator bounds, transitions, and exhaustion."""

from extensions.carla.curve_bounds import (
    _lane_jet,
    _reference_work,
    _spiral_counts,
)
from extensions.carla.curve_interval import _Jet
from extensions.carla.geometry import (
    ARC,
    LINE,
    PARAM_POLY3,
    SPIRAL,
    RoadGeometry,
    _Sample,
    with_arc,
    with_spiral,
)
from extensions.carla.lane_refinement import _chord_error, _refine_lane
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _road(
    var geometry: RoadGeometry,
    offset: CubicPolynomial = CubicPolynomial.constant(0.0),
    width: Float64 = 0.0002,
) raises -> Road:
    var road = Road(
        RoadId(1),
        "bounded",
        geometry.length,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(width))
    )
    road.info.geometries.append(RoadInfoGeometry(0.0, geometry^))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, offset))
    return road^


def test_tiny_curvature_uses_the_same_stable_reference_and_lane_recipe() raises:
    for curvature in [-1e-18, 1e-18]:
        var geometry = with_arc(
            RoadGeometry(ARC, 0.0, 0.0, 0.0, 0.0, 1.0), curvature
        )
        var point = geometry.pos_at(0.001)
        assert_almost_equal(point.x, 0.001, atol=1e-18)
        assert_almost_equal(
            point.y, 0.5 * curvature * 0.001 * 0.001, atol=1e-37
        )
        var lane = geometry._arc_offset(0.001, 0.0)
        assert_equal(lane.x, point.x)
        assert_equal(lane.y, point.y)
        var road = _road(geometry^, width=0.0)
        var bounds = _lane_jet(road, 0, 0, 0.0009, 0.0011)
        assert_true(bounds[0].rounded_value().contains(point.x))
        assert_true(bounds[1].rounded_value().contains(point.y))


def test_collapsed_reversed_and_vertical_arc_centers_keep_orientation() raises:
    for curvature in [-0.01, 0.01]:
        var geometry = with_arc(
            RoadGeometry(ARC, 0.0, 0.0, 0.0, 0.0, 100.0), curvature
        )
        var radius = 1.0 / curvature
        for s in [0.0, 0.01, 20.0, 99.0]:
            var point = geometry._arc_offset(s, -radius)
            assert_equal(point.x, 0.0)
            assert_equal(point.y, radius)
            var derivative = geometry._arc_offset_derivative(s, -radius, 0.0)
            assert_equal(derivative[0], 0.0)
            assert_equal(derivative[1], 0.0)
        var road = _road(geometry^, CubicPolynomial.constant(1.0 + radius), 2.0)
        assert_almost_equal(
            road.lane_transform(0, 0, 0.0).rotation.yaw, 0.0, atol=1e-6
        )
        road.info.elevations[0] = RoadInfoElevation(
            0.0, CubicPolynomial(0.0, 0.1, 0.0, 0.0, 0.0)
        )
        assert_almost_equal(
            road.lane_transform(0, 0, 0.0).rotation.pitch, -90.0, atol=1e-6
        )


def test_actual_gauss_piece_transitions_are_enclosed_without_unit_speed() raises:
    var geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 4.0), 0.01, 0.01
    )
    var threshold = 1.0 / 1.01
    var counts = _spiral_counts(
        geometry, _Jet.variable(threshold - 1e-8, threshold + 1e-8)
    )
    assert_equal(counts[0], 2)
    assert_equal(counts[1], 3)
    var road = _road(geometry^)
    assert_equal(_reference_work(road, threshold - 1e-8, threshold + 1e-8), 25)
    var bound = _lane_jet(road, 0, 0, threshold - 1e-8, threshold + 1e-8)
    assert_false(bound[0].first.is_finite())
    for delta in [-1e-8, -1e-12, 0.0, 1e-12, 1e-8]:
        var point = road._lane_point(0, 0, threshold + delta)
        assert_true(bound[0].rounded_value().contains(point.x))
        assert_true(bound[1].rounded_value().contains(point.y))


def test_sampled_stationary_tangent_retains_both_sides_and_the_exact_point() raises:
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0)
    geometry.samples.append(_Sample(0.0, 0.0, 0.0, -1.0, 0.0))
    geometry.samples.append(_Sample(1.0, 0.0, 1.0, 1.0, 0.0))
    var road = _road(geometry^)
    var bound = _lane_jet(road, 0, 0, 0.49, 0.51)
    assert_false(bound[1].first.is_finite())
    for s in [0.49, 0.499999999, 0.5, 0.500000001, 0.51]:
        var point = road._lane_point(0, 0, s)
        assert_true(bound[0].rounded_value().contains(point.x))
        assert_true(bound[1].rounded_value().contains(point.y))
    var location = Vector3(0.5, 0.0001, 0.0)
    var seed = road._lane_distance_squared(0, 0, 0.5, location)
    var nearest = _refine_lane(road, 0, 0, 0.0, 1.0, location, 0.5, seed)
    assert_almost_equal(nearest[0], 0.5, atol=2e-4)


def test_between_quarter_deviation_is_not_the_sampled_one_millimeter() raises:
    var amplitude = 0.001 / 0.046875
    var road = _road(
        RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0),
        CubicPolynomial(0.0, amplitude * 0.5, -amplitude * 1.5, amplitude, 0.0),
    )
    var first = road.lane_transform(0, 0, 0.0).location
    var last = road.lane_transform(0, 0, 1.0).location
    var bound = _chord_error(road, 0, 0, 0.0, 1.0, first, last)
    # Independent cubic extrema are (3 +/- sqrt(3))/6, not quarter points.
    assert_true(bound >= 0.0010264004785593347)
    for s in [0.25, 0.5, 0.75]:
        var offset = amplitude * s * (s - 0.5) * (s - 1.0)
        assert_true(abs(offset) <= 0.001000000000000001)


def test_local_work_and_accuracy_exhaustion_are_explicit_errors() raises:
    var geometry = with_arc(
        RoadGeometry(ARC, 0.0, 0.0, 0.0, 0.0, 0.001001), 0.001
    )
    var road = _road(
        geometry^,
        CubicPolynomial(0.00039575, -6.7925, 18200.0, -13000000.0, 0.0),
    )
    var query = Vector3(0.0009, 0.0005525, 0.0)
    var distance = road._lane_distance_squared(0, 0, 0.0, query)
    with assert_raises():
        _ = _refine_lane(
            road, 0, 0, 0.0, 0.001, query, 0.0, distance, max_nodes=0
        )
    with assert_raises():
        _ = _refine_lane(
            road, 0, 0, 0.0, 0.001, query, 0.0, distance, max_terms=0
        )
    with assert_raises():
        _ = _refine_lane(
            road, 0, 0, 0.0, 0.001, query, 0.0, distance, max_depth=0
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
