# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent controls for bounded three-point discrete refinement leaves.

Expected station counts, node counts and depths are specified
independently of the enumeration implementation. Reference point comparisons
use the canonical checked scalar graph and the existing exact distance order.
"""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.curve_interval import _next_up
from extensions.carla.geometry import PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_distance import _normalized_square
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _LaneCertificate,
    _checked_center,
    _lane_certificate_contains,
    _lane_certificate_dominates_cells,
    _midpoint,
    _refine_lane_certificate,
    _resume_lane_certificate,
    _run_lane_search,
)
from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
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
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _advance(value: Float64, count: Int) -> Float64:
    return bitcast[DType.float64](bitcast[DType.uint64](value) + UInt64(count))


def _road(plateau: Bool = False, sample_end: Float64 = 1.0) raises -> Road:
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 2.0)
    var left = Float64(0.0) if plateau else Float64(-1.0)
    var right = Float64(0.0) if plateau else Float64(1.0)
    geometry.samples.append(_Sample(left, 2.0, 0.0, 1.0, 0.0))
    geometry.samples.append(_Sample(right, 2.0, sample_end, 1.0, 0.0))
    var road = Road(
        RoadId(1), "tiny-cell", 2.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    # The lane offset cancels its half width. Center y is exactly -2;
    # query (0,0,0) is exactly on the width-4 strict boundary on a plateau.
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(4.0))
    )
    road.info.geometries.append(RoadInfoGeometry(0.0, geometry^))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(2.0))
    )
    return road^


def _loose(
    road: Road,
    low: Float64,
    high: Float64,
    seed: Float64,
    depth: Int = 7,
    nodes: Int = 7,
    terms: Int = 11,
) raises -> _LaneCertificate:
    var reference_terms = 0
    var point = _checked_center(road, 0, 0, seed, reference_terms, 100)
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var upper = _normalized_square[3](point, query, 2.0).high
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(low, high, depth, 0.0, 2.0)
    ]
    # Complete loose original-domain cover; counters represent prior work.
    return _LaneCertificate(
        seed, point^, 2.0, 0.0, upper, False, cells^, nodes, terms
    )


def _unchanged_cover(
    certificate: _LaneCertificate, low: Float64, high: Float64
) raises:
    assert_false(certificate.exact_witness)
    assert_equal(len(certificate.cells), 1)
    assert_equal(certificate.cells[0].low, low)
    assert_equal(certificate.cells[0].high, high)
    assert_equal(certificate.cells[0].depth, 7)


def _check_all_points(
    road: Road,
    low: Float64,
    count: Int,
    certificate: _LaneCertificate,
) raises:
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var terms = 0
    for i in range(count):
        var station = _advance(low, i)
        var point = _checked_center(road, 0, 0, station, terms, 100)
        assert_true(_wide_point_order(certificate.point, point, query) <= 0)
    assert_equal(terms, count)


def test_one_two_three_and_thirty_three_stations_have_exact_source_minima() raises:
    var road = _road()
    # Explicit expected virtual depths and node groups, not solver helpers.
    for spec in [(1, 0, 1), (2, 0, 1), (3, 1, 1), (33, 5, 11)]:
        var count = spec[0]
        var low = Float64(0.5)
        var high = _advance(low, count - 1)
        var expected_terms = 1 if count == 1 else count + 1
        var certificate = _refine_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            high,
            0.0,
            max_nodes=spec[2],
            max_terms=expected_terms,
        )
        assert_true(certificate.exact_witness)
        assert_equal(certificate.s, low)
        assert_equal(certificate.point[0], 0.0)
        assert_equal(certificate.point[1], -2.0)
        assert_equal(certificate.nodes, spec[2])
        assert_equal(certificate.terms, expected_terms)
        for cell in certificate.cells:
            assert_equal(cell.low, cell.high)
            assert_equal(cell.depth, spec[1])
        _check_all_points(road, low, count, certificate)


def test_plateau_keeps_existing_witness_and_original_segment_tie_rule() raises:
    var road = _road(plateau=True)
    var low = Float64(0.5)
    var high = _advance(low, 32)
    var seed = _advance(low, 17)
    var certificate = _refine_lane_certificate(
        road,
        0,
        0,
        low,
        high,
        Vector3(0, 0, 0),
        seed,
        0.0,
        max_nodes=11,
        max_terms=34,
    )
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, seed)
    assert_equal(certificate.nodes, 11)
    assert_equal(certificate.terms, 34)
    assert_equal(len(certificate.cells), 33)
    for i in range(33):
        assert_equal(certificate.cells[i].low, _advance(low, i))
        assert_equal(certificate.cells[i].high, _advance(low, i))
        assert_equal(certificate.cells[i].depth, 5)
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    assert_true(
        _lane_certificate_dominates_cells(certificate, 4, certificate, 5, query)
    )
    assert_false(
        _lane_certificate_dominates_cells(certificate, 5, certificate, 4, query)
    )
    assert_false(
        _lane_certificate_contains(road, 0, 0, Vector3(0, 0, 0), certificate)
    )
    assert_equal(certificate.nodes, 11)
    assert_equal(certificate.terms, 34)


def test_resume_preserves_prior_work_and_virtual_binary_leaf_depth() raises:
    var road = _road()
    var low = Float64(0.5)
    var high = _advance(low, 32)
    var certificate = _loose(road, low, high, high)
    _resume_lane_certificate(
        road,
        0,
        0,
        low,
        high,
        Vector3(0, 0, 0),
        certificate,
        0.0,
        2.0,
        max_nodes=19,
        max_terms=44,
        max_depth=12,
    )
    # One old-cover recheck plus eleven prepaid three-point groups.
    assert_equal(certificate.nodes, 19)
    assert_equal(certificate.terms, 44)
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, low)
    for cell in certificate.cells:
        assert_equal(cell.depth, 12)
    _check_all_points(road, low, 33, certificate)


def test_three_point_node_refuses_fourth_point_without_another_node() raises:
    var road = _road()
    var low = Float64(0.5)
    var high = _advance(low, 3)
    var certificate = _loose(road, low, high, high)
    with assert_raises(contains="interval work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            2.0,
            max_nodes=9,
            max_terms=100,
        )
    assert_equal(certificate.nodes, 9)
    assert_equal(certificate.terms, 14)
    assert_equal(certificate.s, low)
    _unchanged_cover(certificate, low, high)


def test_existing_node_exhaustion_precedes_any_new_scalar_work() raises:
    var road = _road()
    var low = Float64(0.5)
    var high = _advance(low, 3)
    for cap in [7, 8]:
        var certificate = _loose(road, low, high, high)
        with assert_raises(contains="interval work limit"):
            _resume_lane_certificate(
                road,
                0,
                0,
                low,
                high,
                Vector3(0, 0, 0),
                certificate,
                0.0,
                2.0,
                max_nodes=cap,
            )
        assert_equal(certificate.nodes, cap)
        assert_equal(certificate.terms, 11)
        _unchanged_cover(certificate, low, high)


def test_partial_group_term_exhaustion_and_retry_never_reset_work() raises:
    var road = _road()
    var low = Float64(0.5)
    var high = _advance(low, 3)
    var certificate = _loose(road, low, high, high)
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            2.0,
            max_nodes=100,
            max_terms=13,
        )
    assert_equal(certificate.nodes, 9)
    assert_equal(certificate.terms, 13)
    assert_equal(certificate.s, low)
    _unchanged_cover(certificate, low, high)
    var old_nodes = certificate.nodes
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            2.0,
            max_nodes=100,
            max_terms=13,
        )
    assert_true(certificate.nodes > old_nodes)
    assert_equal(certificate.terms, 13)
    _unchanged_cover(certificate, low, high)


def test_original_per_candidate_caps_do_not_become_group_allowances() raises:
    var road = _road()
    var low = Float64(0.5)
    var high = _advance(low, 3)
    var certificate = _loose(road, low, high, high, nodes=16384)
    with assert_raises(contains="interval work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            2.0,
        )
    assert_equal(certificate.nodes, 16384)
    assert_equal(certificate.terms, 11)
    _unchanged_cover(certificate, low, high)
    certificate = _loose(road, low, high, high, terms=2000000)
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            2.0,
        )
    assert_equal(certificate.nodes, 9)
    assert_equal(certificate.terms, 2000000)
    _unchanged_cover(certificate, low, high)


def test_original_depth_refusal_and_spent_scalar_work_remain_observable() raises:
    var road = _road()
    var low = Float64(0.5)
    var high = _advance(low, 2)
    var certificate = _loose(road, low, high, low)
    # Match the unchanged existing resumption control. Insufficient virtual
    # depth must leave the original scalar/refusal path in charge.
    with assert_raises(contains="numerical accuracy limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            2.0,
            max_depth=7,
        )
    assert_true(certificate.nodes > 7)
    assert_true(certificate.terms > 11)
    _unchanged_cover(certificate, low, high)


def test_global_step_derived_node_cap_still_stops_before_fourth_point() raises:
    var road = _road()
    var low = Float64(0.5)
    var high = _advance(low, 3)
    var certificate = _loose(road, low, high, high)
    # L=1, so the unchanged refinement reservation is 100*1+20.
    var work = _MapQueryWork(MapQueryBudget(1, max_steps=1 + 9 * 120))
    work.candidate()
    work.charge(7, 11, 120)
    assert_equal(work.node_cap(7, 120), 9)
    with assert_raises(contains="interval work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            certificate,
            0.0,
            2.0,
            max_nodes=work.node_cap(7, 120),
            max_terms=work.term_cap(11),
        )
    assert_equal(certificate.nodes, 9)
    assert_equal(certificate.terms, 14)
    _unchanged_cover(certificate, low, high)


def test_exported_singletons_keep_individual_classification_debits() raises:
    var road = _road(plateau=True)
    var low = Float64(0.5)
    var high = _advance(low, 32)
    var certificate = _refine_lane_certificate(
        road,
        0,
        0,
        low,
        high,
        Vector3(0, 0, 0),
        high,
        0.0,
        max_nodes=11,
        max_terms=34,
    )
    assert_equal(len(certificate.cells), 33)
    # Safely forget exactness to exercise the ordinary cell-classification
    # consumer on a genuine, fully evaluated singleton cover.
    certificate.exact_witness = False
    with assert_raises(contains="interval work limit"):
        _ = _lane_certificate_contains(
            road,
            0,
            0,
            Vector3(0, 0, 0),
            certificate,
            max_nodes=43,
            max_terms=67,
        )
    assert_equal(certificate.nodes, 11)
    assert_equal(certificate.terms, 34)
    assert_false(
        _lane_certificate_contains(
            road,
            0,
            0,
            Vector3(0, 0, 0),
            certificate,
            max_nodes=44,
            max_terms=67,
        )
    )
    assert_equal(certificate.nodes, 44)
    assert_equal(certificate.terms, 67)


def _fallback_first_sample(road: Road, low: Float64, high: Float64) raises:
    var certificate = _loose(road, low, high, high)
    var middle = _midpoint(low, high)
    assert_true(middle > low and middle < high)
    var reference_terms = 0
    var middle_point = _checked_center(road, 0, 0, middle, reference_terms, 100)
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    assert_true(_wide_point_order(middle_point, certificate.point, query) < 0)
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 7)]
    # The ordinary node samples its midpoint first. One permitted scalar
    # evaluation makes that order observable before any interval arithmetic.
    with assert_raises(contains="quadrature work limit"):
        _run_lane_search(
            road,
            0,
            0,
            low,
            high,
            Vector3(0, 0, 0),
            certificate,
            pending^,
            _ClosedIntervals(),
            List[_ClosedInterval](),
            None,
            100,
            12,
            96,
            None,
        )
    assert_equal(certificate.s, middle)
    assert_equal(certificate.nodes, 8)
    assert_equal(certificate.terms, 12)
    _unchanged_cover(certificate, low, high)


def test_cross_binade_and_thirty_four_points_keep_original_fallback() raises:
    var road = _road()
    # Gap eight across a binade splits 5/3 at its first numeric midpoint.
    var one = bitcast[DType.uint64](Float64(1.0))
    var low = bitcast[DType.float64](one - UInt64(6))
    var high = bitcast[DType.float64](one + UInt64(2))
    var middle = _midpoint(low, high)
    assert_equal(
        bitcast[DType.uint64](middle) - bitcast[DType.uint64](low), UInt64(5)
    )
    assert_equal(
        bitcast[DType.uint64](high) - bitcast[DType.uint64](middle), UInt64(3)
    )
    _fallback_first_sample(road, low, high)
    _fallback_first_sample(road, 0.5, _advance(0.5, 33))


def test_zero_and_subnormal_station_domains_keep_original_fallback() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var end = bitcast[DType.float64](UInt64(8))
    var road = _road(sample_end=end)
    _fallback_first_sample(road, 0.0, end)
    _fallback_first_sample(road, eta * 2.0, eta * 6.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
