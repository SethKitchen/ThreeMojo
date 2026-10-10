# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Bounded real-input qualification for a proposed optional-bound phase.

Existing production only. No proposed helper exists or is invoked here.
The only scalar lane evaluation is at a separately asserted LINE owner.
A genuine profile-owner mismatch returns the whole-cell unknown enclosure
before SPIRAL quadrature. The large whole reservation is still charged.
This is not a complete lane-search execution or a coverage-completion claim.
"""

from extensions.carla.curve_bounds import (
    _lane_jet_with_proof,
    _reference_work,
    _scaled_point_distance_box,
    _scaled_point_distance_jet,
)
from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.curve_sum2 import (
    _require_sum2_environment,
    _sum2_supported_environment,
)
from extensions.carla.geometry import LINE, SPIRAL, RoadGeometry
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.lane_refinement import (
    _checked_center,
    _expansion_center,
    _search_accuracy,
)
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import _preflight_road_records
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    NO_JUNCTION,
    LaneId,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
    info_index,
)
from math.vector3 import Vector3
from std.math import isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _phase_road(middle: Float64) raises -> Road:
    var curvature = Float64(1e9 - 1)
    for _ in range(6):
        curvature = _next_down(curvature)
    var spiral = RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 2.0)
    spiral.curvature_start = curvature
    spiral.curvature_end = curvature
    var road = Road(
        RoadId(1), "bounded optional-phase inputs", 2.0,
        NO_JUNCTION, RoadId(0), RoadId(0), True,
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(-1.0, CubicPolynomial.constant(2.0))
    )
    road.info.geometries.append(RoadInfoGeometry(-1.0, spiral^))
    road.info.geometries.append(
        RoadInfoGeometry(1.0, RoadGeometry(LINE, 1.0, 4.0, 0.0, 0.0, 1.0))
    )
    # Equal-valued records still have genuinely distinct profile owners.
    road.info.elevations.append(
        RoadInfoElevation(-1.0, CubicPolynomial.constant(2.0))
    )
    road.info.elevations.append(
        RoadInfoElevation(middle, CubicPolynomial.constant(2.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(-1.0, CubicPolynomial.constant(1.0))
    )
    return road^


def test_real_unknown_domain_and_cheap_line_incumbent() raises:
    _require_sum2_environment()
    var low = -bitcast[DType.float64](UInt64(624) << UInt64(52))
    var high = Float64(0.0)
    var middle = low + (high - low) * 0.5
    assert_true(low < middle and middle < high)
    var road = _phase_road(middle)
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)

    # Prove selectors before any producer or scalar evaluator call.
    assert_true(road.info.geometries[0].s < road.info.geometries[1].s)
    assert_true(road.info.elevations[0].s < road.info.elevations[1].s)
    assert_true(road.sections[0].lanes[0].info.widths[0].s <= low)
    assert_equal(info_index(road.info.geometries, low), 0)
    assert_equal(info_index(road.info.geometries, high), 0)
    assert_equal(road.info.geometries[0].geometry.kind, SPIRAL)
    assert_equal(info_index(road.info.elevations, low), 0)
    assert_equal(info_index(road.info.elevations, high), 1)
    assert_equal(info_index(road.info.lane_offsets, low), 0)
    assert_equal(info_index(road.info.lane_offsets, high), 0)
    var best = Float64(1.0)
    assert_equal(info_index(road.info.geometries, best), 1)
    assert_equal(info_index(road.info.elevations, best), 1)
    assert_equal(info_index(road.info.lane_offsets, best), 0)
    assert_equal(info_index(road.sections[0].lanes[0].info.widths, best), 0)
    assert_equal(road.info.geometries[1].geometry.kind, LINE)
    assert_equal(_reference_work(road, best, best), 1)

    var max_terms = Int(5000000016)
    var terms = 0
    # Sole scalar evaluation in the probe: its owner was just proved LINE.
    var best_point = _checked_center(road, 0, 0, best, terms, max_terms)
    assert_equal(terms, 1)
    for axis in range(3):
        assert_true(isfinite(best_point[axis]))
    assert_equal(best_point[0], 4.0)
    assert_equal(best_point[1], 0.0)
    assert_equal(best_point[2], 2.0)
    var location = Vector3(0, 1, 0)
    var query: Array[Float64, 3] = [0.0, 1.0, 0.0]
    var scale = _point_gap_scale(best_point, query)
    assert_true(isfinite(scale) and scale > 0.0)
    var best_bounds = _refinement_square[3](best_point, query, scale)
    assert_true(best_bounds.is_finite())

    var whole_work = _reference_work(road, low, high)
    assert_equal(whole_work, 5000000005)
    assert_true(terms <= max_terms - whole_work)
    terms += whole_work
    assert_equal(terms, 5000000006)
    var before_bound = terms
    # Actual unmodified producer: profile-owner mismatch returns at
    # curve_bounds._lane_jet_model_proof before SPIRAL expression dispatch.
    var point_domain = _lane_jet_with_proof(
        road, 0, 0, low, high, low, best, None
    )
    assert_false(point_domain[0].rounded_value().is_finite())
    assert_false(point_domain[1].rounded_value().is_finite())
    assert_false(point_domain[2].rounded_value().is_finite())
    assert_equal(terms, before_bound)
    var natural = _scaled_point_distance_box(
        point_domain, location, scale
    ).low
    var domain = _scaled_point_distance_jet(point_domain, location, scale)
    assert_equal(natural, 0.0)
    assert_false(domain.rounded_value().is_finite())
    assert_false(domain.second.low > 0.0)
    var tolerance = _search_accuracy(
        road, 0, 0, low, best, best, best_bounds.low, scale, None
    )
    assert_true(isfinite(tolerance) and tolerance >= 0.0)
    assert_true(best_bounds.high > natural)
    assert_true(_next_up(best_bounds.high - natural) > tolerance)

    var center = _expansion_center(low, high, best)
    assert_equal(bitcast[DType.uint64](center), UInt64(0x8000000000000001))
    assert_equal(info_index(road.info.geometries, center), 0)
    assert_equal(_reference_work(road, center, center), -1)
    assert_equal(terms, 5000000006)
    assert_true(_sum2_supported_environment())
    print("PHASE_INPUT_WORK", whole_work, terms, max_terms)
    print("PHASE_INPUT_CENTER", bitcast[DType.uint64](center))
    print("PHASE_INPUT_POLICY", natural, best_bounds.high, scale, tolerance)
    print("NO_SPIRAL_SCALAR_CALLED: sole checked scalar owner is LINE")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
