# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Matching positive cases and exact adjacent-domain proof controls."""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.geometry import ARC, LINE, RoadGeometry
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _LaneExclusionGoal,
    _axis_lane_minimum,
    _lane_certificate_contains,
    _resume_lane_certificate,
    _rounded_axis_lane_minimum,
    _run_lane_search,
    _subdivided_lane_box,
    _try_rounded_arc_witness,
)
from extensions.carla.road_info import RoadInfoGeometry
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _road


def test_axis_interior_and_valid_gap_resumption_preserve_the_true_minimum() raises:
    var road = _road()
    var axis = _axis_lane_minimum(road, 0, 0, 1.0, 2.0, Vector3(1.5, 0, 0))
    assert_true(Bool(axis))
    assert_equal(axis.value()[0], 1.5)
    var certificate = _whole_certificate(
        road, Vector3(0.5, 0, 0), 0.0, 1.0, 0.5
    )
    _resume_lane_certificate(
        road, 0, 0, 0.0, 1.0, Vector3(0.5, 0, 0), certificate, 0.0, 1.0
    )
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, 0.5)


def test_half_ulp_inverse_miss_is_recovered_by_actual_bit_midpoint() raises:
    var road = _road()
    road.info.geometries[0].geometry.x = -1.1102230246251565e-16
    # q=1, x0=-2^-53: RN(q-x0)=1 maps to next_down(1), but
    # s=next_up(1) maps to exactly 1 by ties-to-even rounding.
    var axis = _axis_lane_minimum(road, 0, 0, 0.5, 2.0, Vector3(1, 0, 0))
    assert_true(Bool(axis))
    assert_equal(axis.value()[0], _next_up(Float64(1.0)))
    assert_equal(axis.value()[2][0], 1.0)
    assert_true(axis.value()[3] > 1)
    var nodes = 0
    var terms = 0
    var rounded = _rounded_axis_lane_minimum(
        road, 0, 0, 0.5, 2.0, Vector3(1, 0, 0), nodes, terms, 100, 1000, 96
    )
    assert_true(Bool(rounded))
    assert_equal(rounded.value()[0], _next_up(Float64(1.0)))
    assert_equal(rounded.value()[2][0], 1.0)
    assert_true(nodes > 2)


def test_finite_axis_owner_survives_overflow_of_the_optional_inverse_seed() raises:
    var reach = bitcast[DType.float64](UInt64(0x7FE8000000000000))
    var start = bitcast[DType.float64](UInt64(0x7FCFFFFFFFFFFFFE))
    var high = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var road = _road()
    road.length = high
    road.info.geometries[0] = RoadInfoGeometry(
        start, RoadGeometry(LINE, start, -reach, 0.0, 0.0, reach)
    )
    # RN(high-start)=reach, so the finite high endpoint is x=0.
    # RN(RN(-1+reach)+start) overflows at the upper rounding tie.
    # The inverse is optional: the exact stored bracket still has a minimum.
    var result = _axis_lane_minimum(road, 0, 0, start, high, Vector3(-1, 0, 0))
    assert_true(Bool(result))
    assert_equal(result.value()[0], high)
    assert_equal(result.value()[2][0], 0.0)
    assert_true(result.value()[3] > 1)


def test_adjacent_translated_grid_uses_exact_full_distance_order() raises:
    var road = _road()
    var base = Float64(1e20)
    road.length = base + 81920.0
    road.info.geometries[0] = RoadInfoGeometry(
        base, RoadGeometry(LINE, base, 0.0, 0.0, 0.0, 81920.0)
    )
    var nodes = 0
    var terms = 0
    var rounded = _rounded_axis_lane_minimum(
        road,
        0,
        0,
        base + 16384.0,
        base + 81920.0,
        Vector3(25000, 0, 0),
        nodes,
        terms,
        100,
        1000,
        96,
    )
    assert_true(Bool(rounded))
    # The adjacent images are 16384 and 32768. Exact integer distances
    # are 8616 and 7768, so the upper station is the unique minimizer.
    assert_equal(rounded.value()[0], base + 32768.0)
    assert_equal(rounded.value()[2][0], 32768.0)


def test_ordinary_nonadjacent_search_keeps_a_finite_endpoint_minimum() raises:
    var road = _road()
    var certificate = _whole_certificate(road, Vector3(0, 0, 0), 1.0, 2.0, 2.0)
    var pending: List[Tuple[Float64, Float64, Int]] = [
        (Float64(1.0), Float64(2.0), 0)
    ]
    _run_lane_search(
        road,
        0,
        0,
        1.0,
        2.0,
        Vector3(0, 0, 0),
        certificate,
        pending^,
        _ClosedIntervals(),
        List[_ClosedInterval](),
        None,
        100,
        1000,
        96,
    )
    assert_equal(certificate.s, 1.0)
    assert_equal(certificate.point[0], 1.0)
    assert_true(len(certificate.cells) > 0)


def test_strict_external_witness_does_not_reset_support_refinement_depth() raises:
    var road = _road()
    road.info.geometries[0].geometry.x = 0.1
    var location = Vector3(-1, 0, 0)
    var query: Array[Float64, 3] = [-1.0, 0.0, 0.0]
    var certificate = _whole_certificate(road, location, 1.0, 2.0, 2.0)
    var nearest = road._lane_center(0, 0, 1.0)
    var external = nearest.copy()
    external[0] = _next_down(external[0])
    var scale = _point_gap_scale(external, query)
    var goal = _LaneExclusionGoal(
        _refinement_square[3](external, query, scale).high, scale, False
    )
    var pending: List[Tuple[Float64, Float64, Int]] = [
        (Float64(1.0), Float64(2.0), 0)
    ]
    with assert_raises(contains="numerical accuracy limit"):
        _run_lane_search(
            road,
            0,
            0,
            1.0,
            2.0,
            location,
            certificate,
            pending^,
            _ClosedIntervals(),
            List[_ClosedInterval](),
            (Float64(0.0), Float64(1.0)),
            100,
            1000,
            0,
            None,
            goal,
            external.copy(),
        )
    assert_equal(certificate.s, 1.0)
    assert_equal(certificate.point[0], nearest[0])
    assert_equal(certificate.nodes, 1)


def test_record_join_subdivision_keeps_its_prepaid_node_limit() raises:
    var road = _road()
    road.info.geometries.append(
        RoadInfoGeometry(0.5, RoadGeometry(LINE, 0.5, 10.0, 0.0, 0.0, 3.5))
    )
    var result = _subdivided_lane_box(road, 0, 0, 0.25, 0.75, 100, max_nodes=1)
    assert_false(result[0][0].is_finite())
    assert_equal(result[1], 0)


def test_adjacent_zero_record_join_encloses_both_finite_outputs() raises:
    var road = _road()
    var high = bitcast[DType.float64](UInt64(1))
    road.info.geometries.append(
        RoadInfoGeometry(high, RoadGeometry(LINE, high, 10.0, 0.0, 0.0, 3.5))
    )
    var result = _subdivided_lane_box(road, 0, 0, 0.0, high, 2, max_nodes=1)
    assert_true(result[0][0].contains(0.0))
    assert_true(result[0][0].contains(10.0))
    assert_equal(result[1], 2)


def test_adjacent_strict_width_boundary_remains_explicitly_unresolved() raises:
    var road = _road()
    var low = _next_down(Float64(0.5))
    var certificate = _whole_certificate(
        road, Vector3(0.5, 1, 0), low, 0.5, 0.5
    )
    with assert_raises(contains="unresolved over a possible minimizing cell"):
        _ = _lane_certificate_contains(
            road, 0, 0, Vector3(0.5, 1, 0), certificate
        )
    assert_equal(certificate.nodes, 1)


def test_adjacent_arc_optional_proof_is_transactional_for_exact_endpoint_minima() raises:
    var road = _road()
    road.info.geometries[0].geometry.kind = ARC
    road.info.geometries[0].geometry.curvature_start = 0.125
    for low in [Float64(1.0), _next_up(Float64(1.0))]:
        var high = _next_up(low)
        for location in [
            Vector3(0, 0, 0),
            Vector3(1, 1, 0),
            Vector3(2, 0, 0),
            Vector3(-1, -1, 0),
        ]:
            var query: Array[Float64, 3] = [
                Float64(location.x),
                Float64(location.y),
                Float64(location.z),
            ]
            var first = road._lane_center(0, 0, low)
            var last = road._lane_center(0, 0, high)
            var best = (
                high if _wide_point_order(last, first, query) < 0 else low
            )
            var certificate = _whole_certificate(
                road, location, low, high, best
            )
            var original = certificate.point.copy()
            var proved = _try_rounded_arc_witness(
                road, 0, 0, low, high, query, certificate, 100, 1000, 96
            )
            assert_equal(certificate.s, best)
            for axis in range(3):
                assert_equal(certificate.point[axis], original[axis])
            assert_equal(certificate.exact_witness, proved)
            assert_equal(len(certificate.cells), 1)
            if not proved:
                assert_equal(certificate.cells[0].low, low)
                assert_equal(certificate.cells[0].high, high)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
