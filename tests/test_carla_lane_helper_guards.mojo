# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Direct refusal, conservative cover, and budget controls for lane helpers."""

from extensions.carla.curve_interval import _Interval, _Jet, _next_down
from extensions.carla.geometry import ARC, LINE, SPIRAL, RoadGeometry
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _admission_roundoff,
    _axis_lane_minimum,
    _checked_center,
    _exact_lane_certificate,
    _finish_lane_certificate,
    _global_lower,
    _lane_certificate_contains,
    _lane_certificate_dominates_cells,
    _refine_lane_certificate,
    _rounded_axis_lane_minimum,
    _subdivided_lane_box,
    _try_rounded_arc_witness,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import RoadInfoGeometry
from math.vector3 import Vector3
from std.math import inf
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _bounded, _road


def test_unowned_reference_station_is_rejected_before_scalar_work() raises:
    var road = _road()
    var terms = 7
    with assert_raises(contains="cannot resolve the quadrature count"):
        _ = _checked_center(road, 0, 0, -0.5, terms, 100)
    assert_equal(terms, 7)
    with assert_raises(contains="cannot resolve the quadrature count"):
        _ = _refine_lane_certificate(
            road, 0, 0, -1.0, -0.5, Vector3(0, 0, 0), -0.5, 0.0
        )


def test_axis_owner_requires_finite_bounds_and_both_constant_profiles() raises:
    var road = _road()
    with assert_raises(contains="finite nonnegative parameter bounds"):
        _ = _axis_lane_minimum(
            road, 0, 0, inf[DType.float64](), 1.0, Vector3(0, 0, 0)
        )
    for missing_offset in [False, True]:
        road = _road()
        if missing_offset:
            road.info.lane_offsets.clear()
        else:
            road.info.elevations.clear()
        assert_false(
            Bool(_axis_lane_minimum(road, 0, 0, 1.0, 2.0, Vector3(0, 0, 0)))
        )
    road = _road()
    var one = _axis_lane_minimum(road, 0, 0, 1.0, 1.0, Vector3(2, 0, 0))
    assert_true(Bool(one))
    assert_equal(one.value()[0], 1.0)


def test_rounded_axis_endpoints_and_singleton_keep_exact_station() raises:
    var road = _road()
    for values in [
        (Float64(1.0), Float64(2.0), Float32(0.0), Float64(1.0)),
        (Float64(1.0), Float64(2.0), Float32(3.0), Float64(2.0)),
        (Float64(1.5), Float64(1.5), Float32(2.0), Float64(1.5)),
    ]:
        var nodes = 0
        var terms = 0
        var result = _rounded_axis_lane_minimum(
            road,
            0,
            0,
            values[0],
            values[1],
            Vector3(values[2], 0, 0),
            nodes,
            terms,
            100,
            100,
            96,
        )
        assert_true(Bool(result))
        assert_equal(result.value()[0], values[3])
        assert_equal(result.value()[2][0], values[3])
    var nodes = 0
    var terms = 0
    with assert_raises(contains="quadrature work limit"):
        _ = _rounded_axis_lane_minimum(
            road, 0, 0, 1.0, 2.0, Vector3(0, 0, 0), nodes, terms, 100, 0, 96
        )
    assert_equal(nodes, 1)
    assert_equal(terms, 0)


def test_zero_distance_finalization_is_exact_and_empty_nonzero_cover_refuses() raises:
    var zero: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var result = _finish_lane_certificate(
        0.5, zero, zero, _ClosedIntervals(), List[_ClosedInterval](), 7, 11
    )
    assert_true(result.exact_witness)
    assert_equal(result.s, 0.5)
    assert_equal(result.nodes, 7)
    assert_equal(result.terms, 11)
    with assert_raises(contains="lost its possible minimizing cells"):
        _ = _finish_lane_certificate(
            0.5,
            [2.0, 0.0, 0.0],
            zero,
            _ClosedIntervals(),
            List[_ClosedInterval](),
            7,
            11,
        )


def test_finalization_discards_strictly_worse_terminal_bounds() raises:
    var closed = _ClosedIntervals()
    closed.add(_ClosedInterval(0.0, 1.0, 0, 0.0, 2.0))
    var terminal: List[_ClosedInterval] = [
        _ClosedInterval(1.0, 1.0, 1, 2.0, 2.0)
    ]
    var result = _finish_lane_certificate(
        0.5, [2.0, 0.0, 0.0], [0.0, 0.0, 0.0], closed, terminal, 7, 11
    )
    assert_equal(len(result.cells), 1)
    assert_equal(result.cells[0].low, 0.0)
    assert_equal(result.cells[0].high, 1.0)


def test_later_strictly_better_witness_can_dominate_all_nonterminal_cells() raises:
    var one = _bounded([1.0, 0.0, 0.0], 1.0, 1.0, low=0.0, high=1.0)
    var two = _bounded([2.0, 0.0, 0.0], 4.0, 4.0, low=0.0, high=1.0)
    assert_true(
        _lane_certificate_dominates_cells(one, 1, two, 0, [0.0, 0.0, 0.0])
    )


def test_unknown_center_derivative_keeps_the_natural_global_bound() raises:
    var domain = _Jet(
        _Interval(1.0, 2.0), _Interval.point(0.0), _Interval.point(0.0), 0.0
    )
    var center = _Jet(
        _Interval.point(1.0),
        _Interval.whole(),
        _Interval.point(0.0),
        inf[DType.float64](),
    )
    assert_equal(_global_lower(domain, center, _Interval(-1.0, 1.0)), 1.0)


def test_exact_and_nonexact_classification_require_width_records() raises:
    var road = _road()
    var point = road._lane_center(0, 0, 0.5)
    road.sections[0].lanes[0].info.widths.clear()
    for exact in [False, True]:
        var certificate = _bounded(point, 0.0, 1.0)
        certificate.exact_witness = exact
        with assert_raises(contains="needs a width record"):
            _ = _lane_certificate_contains(
                road, 0, 0, Vector3(0, 0, 0), certificate
            )
        assert_equal(certificate.nodes, 0)
        assert_equal(certificate.terms, 0)
    var certificate = _bounded(point, 0.0, 1.0)
    certificate.cells.clear()
    with assert_raises(contains="needs possible minimizing cells"):
        _ = _lane_certificate_contains(
            road, 0, 0, Vector3(0, 0, 0), certificate
        )


def test_classification_rejects_unresolved_quadrature_before_spending_terms() raises:
    var road = _road()
    var point = road._lane_center(0, 0, 0.5)
    road.info.geometries[0].geometry.kind = SPIRAL
    var certificate = _bounded(point, 0.0, 100.0, low=0.0, high=4.0)
    with assert_raises(contains="cannot resolve a minimizing cell"):
        _ = _lane_certificate_contains(
            road, 0, 0, Vector3(0, 2, 0), certificate
        )
    assert_equal(certificate.nodes, 1)
    assert_equal(certificate.terms, 0)


def test_strict_three_dimensional_bound_discards_a_nonminimizing_cell() raises:
    var road = _road()
    var certificate = _bounded([0.5, 0.0, 0.0], 0.0, 4.25, low=3.0, high=4.0)
    certificate.cells.append(_ClosedInterval(0.5, 0.5, 0, 0.0, 1.0))
    assert_false(
        _lane_certificate_contains(road, 0, 0, Vector3(0, 2, 0), certificate)
    )
    assert_equal(certificate.nodes, 2)
    assert_equal(certificate.terms, 2)


def test_width_touching_zero_requires_refinement_of_the_minimizing_set() raises:
    var road = _road()
    road.sections[0].lanes[0].info.widths[0].polynomial = CubicPolynomial(
        0, 2, 0, 0, 0
    )
    road.info.lane_offsets[0].polynomial = CubicPolynomial(0, 1, 0, 0, 0)
    var certificate = _bounded([0.5, 0.0, 0.0], 0.0, 0.0, low=0.0, high=1.0)
    assert_true(
        _lane_certificate_contains(
            road, 0, 0, Vector3(0.5, 0, 0), certificate, max_nodes=100
        )
    )
    assert_true(certificate.nodes > 1)


def test_boundary_classification_keeps_depth_and_node_limits() raises:
    var road = _road()
    var certificate = _whole_certificate(
        road, Vector3(0.5, 1, 0), 0.0, 1.0, 0.5
    )
    certificate.cells[0].depth = 96
    with assert_raises(contains="unresolved over a possible minimizing cell"):
        _ = _lane_certificate_contains(
            road, 0, 0, Vector3(0.5, 1, 0), certificate
        )
    certificate = _whole_certificate(road, Vector3(0.5, 1, 0), 0.0, 1.0, 0.5)
    with assert_raises(contains="interval work limit"):
        _ = _lane_certificate_contains(
            road, 0, 0, Vector3(0.5, 1, 0), certificate, max_nodes=2
        )
    assert_equal(certificate.nodes, 2)


def test_rounded_arc_proof_refuses_changed_witness_and_unknown_boxes() raises:
    var road = _road()
    road.info.geometries[0].geometry.kind = ARC
    road.info.geometries[0].geometry.curvature_start = 0.125
    road.info.geometries[0].geometry.x = 16.0
    road.info.geometries[0].geometry.y = 8.0
    for corrupt_witness in [False, True]:
        road.info.geometries[
            0
        ].geometry.curvature_start = 0.125 if corrupt_witness else 1.0
        var certificate = _whole_certificate(
            road, Vector3(0, 0, 0), 1.0, 2.0, 1.0
        )
        if corrupt_witness:
            certificate.point[0] += 1.0
        var terms = certificate.terms
        assert_false(
            _try_rounded_arc_witness(
                road, 0, 0, 1.0, 2.0, [0.0, 0.0, 0.0], certificate, 100, 100, 96
            )
        )
        assert_false(certificate.exact_witness)
        assert_equal(certificate.s, 1.0)
        assert_equal(len(certificate.cells), 1)
        assert_equal(certificate.nodes, 1)
        assert_equal(certificate.terms, terms + 2)


def test_adjacent_record_join_encloses_both_stored_endpoints_with_atomic_budget() raises:
    var road = _road()
    road.info.geometries.append(
        RoadInfoGeometry(0.5, RoadGeometry(LINE, 0.5, 10.0, 0.0, 0.0, 3.5))
    )
    var low = _next_down(Float64(0.5))
    for budget in [0, 1, 2]:
        var result = _subdivided_lane_box(
            road, 0, 0, low, 0.5, budget, max_nodes=1
        )
        if budget < 2:
            assert_false(result[0][0].is_finite())
            assert_equal(result[1], 0)
        else:
            assert_true(result[0][0].contains(low))
            assert_true(result[0][0].contains(10.0))
            assert_equal(result[1], 2)


def test_adjacent_join_refuses_either_unresolved_endpoint_count() raises:
    var road = _road()
    var low = _next_down(Float64(0.5))
    road.info.geometries[0].s = 0.5
    var result = _subdivided_lane_box(road, 0, 0, low, 0.5, 100, max_nodes=1)
    assert_false(result[0][0].is_finite())
    assert_equal(result[1], 0)
    road = _road()
    var geometry = RoadGeometry(SPIRAL, 0.5, 10.0, 0.0, 0.0, 3.5)
    geometry.curvature_start = inf[DType.float64]()
    geometry.curvature_end = inf[DType.float64]()
    road.info.geometries.append(RoadInfoGeometry(0.5, geometry^))
    result = _subdivided_lane_box(road, 0, 0, low, 0.5, 100, max_nodes=1)
    assert_false(result[0][0].is_finite())
    assert_equal(result[1], 0)


def test_admission_allowance_is_outward_for_exact_binary_inputs() raises:
    var result = _admission_roundoff(2.0, 3.0)
    assert_true(result >= 5.0 / 70368744177664.0)
    assert_true(result < 6.0 / 70368744177664.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
