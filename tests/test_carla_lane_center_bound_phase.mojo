# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Direct optional-center bound controls with real numerical inputs.

The refusal fixture executes the extracted numerical phase.
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
from extensions.carla.curve_interval import _Interval, _next_down, _next_up
from extensions.carla.curve_sum2 import (
    _require_sum2_environment,
    _sum2_supported_environment,
)
from extensions.carla.geometry import LINE, SPIRAL, RoadGeometry
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.lane_refinement import (
    _LaneBoundClose,
    _LaneBoundContract,
    _LaneBoundDiscard,
    _LaneBoundPolicy,
    _LaneBoundProposal,
    _LaneExpansionContext,
    _try_lane_center_bound,
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
    info_index_meters as info_index,
)
from math.vector3 import Vector3
from std.math import isfinite
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_cross_candidate_certificates import _road
from tests._lazy_taylor_controls import _diagonal_road, _whole_certificate
from tests._spiral_acceptance_controls import _capture_acceptance_proof


def _phase_road(middle: Float64) raises -> Road:
    var curvature = Float64(1e9 - 1)
    for _ in range(6):
        curvature = _next_down(curvature)
    var spiral = RoadGeometry.from_meters(SPIRAL, 0.0, 0.0, 0.0, 0.0, 2.0)
    spiral.curvature_start = curvature
    spiral.curvature_end = curvature
    var road = Road._from_si(
        RoadId(1),
        "bounded optional-phase inputs",
        2.0,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section_meters(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth._from_si(-1.0, CubicPolynomial._constant_si(2.0))
    )
    road.info.geometries.append(RoadInfoGeometry._from_si(-1.0, spiral^))
    road.info.geometries.append(
        RoadInfoGeometry._from_si(
            1.0, RoadGeometry.from_meters(LINE, 1.0, 4.0, 0.0, 0.0, 1.0)
        )
    )
    # Equal-valued records still have genuinely distinct profile owners.
    road.info.elevations.append(
        RoadInfoElevation._from_si(-1.0, CubicPolynomial._constant_si(2.0))
    )
    road.info.elevations.append(
        RoadInfoElevation._from_si(middle, CubicPolynomial._constant_si(2.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset._from_si(-1.0, CubicPolynomial._constant_si(1.0))
    )
    return road^


def test_real_center_count_refusal_preserves_ledger_and_empty_caches() raises:
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
    var natural = _scaled_point_distance_box(point_domain, location, scale).low
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
    var context = _LaneExpansionContext(
        0, 0, _Interval(low, best), location, None, None, None, None, None
    )
    var nodes = 0
    var proposal = _try_lane_center_bound(
        road,
        context,
        _Interval(low, high),
        best,
        domain,
        natural,
        whole_work,
        _LaneBoundPolicy(best_bounds.high, scale, tolerance, None),
        nodes,
        terms,
        16,
        max_terms,
    )
    assert_false(Bool(proposal))
    assert_equal(nodes, 0)
    assert_equal(terms, 5000000006)
    assert_false(Bool(context.cached_fast))
    assert_false(Bool(context.cached_expansion))
    assert_true(_sum2_supported_environment())
    print("PHASE_INPUT_WORK", whole_work, terms, max_terms)
    print("PHASE_INPUT_CENTER", bitcast[DType.uint64](center))
    print("PHASE_INPUT_POLICY", natural, best_bounds.high, scale, tolerance)
    print("NO_SPIRAL_SCALAR_CALLED: sole checked scalar owner is LINE")


def _proposal_values(
    proposal: _LaneBoundProposal,
) -> Tuple[Float64, Float64, Float64]:
    if proposal.isa[_LaneBoundDiscard]():
        var value = proposal[_LaneBoundDiscard]
        return (value.lower, value.support.low, value.support.high)
    if proposal.isa[_LaneBoundClose]():
        var value = proposal[_LaneBoundClose]
        return (value.lower, value.support.low, value.support.high)
    var value = proposal[_LaneBoundContract]
    return (value.lower, value.support.low, value.support.high)


def _check_line_phase(best: Float64, external: Bool) raises:
    _require_sum2_environment()
    var road = _road()
    var location = Vector3(1, 1, 0)
    var query: Array[Float64, 3] = [1.0, 1.0, 0.0]
    var terms = 0
    var point = _checked_center(road, 0, 0, best, terms, 100)
    var scale = _point_gap_scale(point, query)
    var score = _refinement_square[3](point, query, scale)
    var whole_work = _reference_work(road, 0.0, 2.0)
    assert_equal(whole_work, 1)
    terms += whole_work
    var whole = _lane_jet_with_proof(road, 0, 0, 0.0, 2.0, 0.0, 2.0, None)
    var natural = _scaled_point_distance_box(whole, location, scale).low
    var domain = _scaled_point_distance_jet(whole, location, scale)
    var tolerance = _search_accuracy(
        road, 0, 0, 0.0, 2.0, best, score.low, scale, None
    )
    var witness: Optional[Array[Float64, 3]] = None
    if external:
        # A checked point from a separate road supplies a genuine witness.
        var other = _road(id=2, y=-1.0)
        witness = _checked_center(other, 0, 0, best, terms, 100)
    var context = _LaneExpansionContext(
        0,
        0,
        _Interval(0.0, 2.0),
        location,
        None,
        None,
        witness^,
        None,
        None,
    )
    var nodes = 0
    var before_terms = terms
    var policy = _LaneBoundPolicy(score.high, scale, tolerance, None)
    var result = _try_lane_center_bound(
        road,
        context,
        _Interval(0.0, 2.0),
        best,
        domain,
        natural,
        whole_work,
        policy,
        nodes,
        terms,
        100,
        100,
    )
    assert_equal(nodes, 0)
    assert_equal(terms, before_terms + 1)
    assert_false(Bool(context.cached_fast))
    if best == 1.0:
        assert_true(Bool(result))
        assert_true(result.value().isa[_LaneBoundClose]())
        var close = result.value()[_LaneBoundClose]
        assert_equal(close.support.low, 0.0)
        assert_equal(close.support.high, 2.0)
        assert_true(close.lower <= score.high)
    elif not external:
        # An admitted but inconclusive attempt keeps its charged center work.
        assert_false(Bool(result))
        assert_false(Bool(context.cached_expansion))
    if external:
        assert_true(Bool(context.cached_expansion))
        var cached = context.cached_expansion.value()
        assert_equal(
            cached[0], bitcast[DType.uint64](_expansion_center(0.0, 2.0, best))
        )
        assert_equal(cached[1], bitcast[DType.uint64](scale))
        before_terms = terms
        var repeated = _try_lane_center_bound(
            road,
            context,
            _Interval(0.0, 2.0),
            best,
            domain,
            natural,
            whole_work,
            policy,
            nodes,
            terms,
            100,
            100,
        )
        assert_equal(terms, before_terms + 1)
        assert_equal(nodes, 0)
        assert_equal(Bool(result), Bool(repeated))
        if result:
            assert_equal(
                result.value().isa[_LaneBoundDiscard](),
                repeated.value().isa[_LaneBoundDiscard](),
            )
            assert_equal(
                result.value().isa[_LaneBoundClose](),
                repeated.value().isa[_LaneBoundClose](),
            )
            assert_equal(
                result.value().isa[_LaneBoundContract](),
                repeated.value().isa[_LaneBoundContract](),
            )
            var first_values = _proposal_values(result.value())
            var next_values = _proposal_values(repeated.value())
            for values in [
                (first_values[0], next_values[0]),
                (first_values[1], next_values[1]),
                (first_values[2], next_values[2]),
            ]:
                assert_equal(
                    bitcast[DType.uint64](values[0]),
                    bitcast[DType.uint64](values[1]),
                )
        # An admission error preserves the populated cache and spent ledger.
        before_terms = terms
        with assert_raises(contains="quadrature work limit"):
            _ = _try_lane_center_bound(
                road,
                context,
                _Interval(0.0, 2.0),
                best,
                domain,
                natural,
                whole_work,
                policy,
                nodes,
                terms,
                100,
                before_terms,
            )
        assert_equal(nodes, 0)
        assert_equal(terms, before_terms)
        assert_false(Bool(context.cached_fast))
        var after = context.cached_expansion.value()
        assert_equal(after[0], cached[0])
        assert_equal(after[1], cached[1])
        for values in [
            (after[2].value.low, cached[2].value.low),
            (after[2].value.high, cached[2].value.high),
            (after[2].first.low, cached[2].first.low),
            (after[2].first.high, cached[2].first.high),
            (after[2].second.low, cached[2].second.low),
            (after[2].second.high, cached[2].second.high),
            (after[2].error, cached[2].error),
        ]:
            assert_equal(
                bitcast[DType.uint64](values[0]),
                bitcast[DType.uint64](values[1]),
            )
    assert_true(_sum2_supported_environment())


def test_real_line_inconclusion_retains_center_debit() raises:
    _check_line_phase(2.0, False)


def test_real_line_close_proposes_original_whole_support() raises:
    _check_line_phase(1.0, False)


def test_real_line_cache_reuse_and_admission_error_preserve_words() raises:
    _check_line_phase(2.0, True)


def test_grouped_reservation_error_publishes_consumed_center_work() raises:
    _require_sum2_environment()
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var low = Float64(0.4)
    var high = Float64(0.7)
    var proof = _capture_acceptance_proof(road, low, high)
    var certificate = _whole_certificate(road, location, low, high, high)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var scale = _point_gap_scale(certificate.point, query)
    var score = _refinement_square[3](certificate.point, query, scale)
    var whole_work = _reference_work(road, low, high)
    assert_true(whole_work > 0)
    certificate.terms += whole_work
    var whole = _lane_jet_with_proof(road, 0, 0, low, high, low, high, proof)
    var natural = _scaled_point_distance_box(whole, location, scale).low
    var domain = _scaled_point_distance_jet(whole, location, scale)
    var tolerance = _search_accuracy(
        road,
        0,
        0,
        low,
        high,
        certificate.s,
        score.low,
        scale,
        (Float64(0.0), Float64(1.0)),
    )
    assert_equal(tolerance, 0.0)
    assert_true(domain.error > tolerance * 0.25)
    var center_s = _expansion_center(low, high, certificate.s)
    var center_work = _reference_work(road, center_s, center_s)
    assert_true(center_work > 0)
    var before_terms = certificate.terms
    var before_nodes = certificate.nodes
    var max_terms = before_terms + center_work
    var context = _LaneExpansionContext(
        0,
        0,
        _Interval(low, high),
        location,
        proof,
        None,
        None,
        None,
        None,
    )
    # Initial center work fits and is debited. Fast proof lacks its required
    # fallback headroom. The real positive domain error requests a grouped
    # refresh, whose whole reservation then fails at the unchanged limit.
    with assert_raises(contains="quadrature work limit"):
        _ = _try_lane_center_bound(
            road,
            context,
            _Interval(low, high),
            certificate.s,
            domain,
            natural,
            whole_work,
            _LaneBoundPolicy(score.high, scale, tolerance, None),
            certificate.nodes,
            certificate.terms,
            100,
            max_terms,
        )
    assert_equal(certificate.terms, before_terms + center_work)
    assert_equal(certificate.nodes, before_nodes)
    assert_false(Bool(context.cached_fast))
    assert_false(Bool(context.cached_expansion))
    assert_true(_sum2_supported_environment())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
