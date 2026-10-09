# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Stored witnesses, conditional local bands and optional continuation reserves."""

from extensions.carla.map import (
    _try_winner_seed,
    _winner_seed_room,
    _query_node_step_cost,
    _seed_exact_interval,
    _seed_reference_domain,
)
from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import RoadId, LaneId, LANE_DRIVING
from tests._published_seed_selector import _published_first_pass_with_work
from extensions.carla.road import Road
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import RoadInfoLaneWidth
from extensions.carla.geometry import LINE, SPIRAL, RoadGeometry, with_spiral
from extensions.carla.road_info import RoadInfoGeometry, info_index
from tests.test_carla_cross_candidate_certificates import _road
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _refine_lane_certificate,
    _ClosedInterval,
    _checked_center,
    _continue_lane_certificate,
)
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.curve_bounds import (
    _reference_work,
    _lane_jet,
    _scaled_point_distance_jet,
    _expansion_distance_jet,
)
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _stored_difference,
    _next_down,
    _next_up,
)
from extensions.carla.lane_distance import _refinement_square
from math.vector3 import Vector3
from std.memory import bitcast
from std.math import isfinite
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    assert_raises,
)


def _query() -> Vector3:
    return Vector3(
        bitcast[DType.float32](UInt32(1086398839)),
        bitcast[DType.float32](UInt32(3267792511)),
        bitcast[DType.float32](UInt32(1066359849)),
    )


def _certificate(
    road: Road,
    lane: Int,
    seed: Float64 = bitcast[DType.float64](UInt64(4618441417811709861)),
) raises -> _LaneCertificate:
    var query = _query()
    var q: Array[Float64, 3] = [
        Float64(query.x),
        Float64(query.y),
        Float64(query.z),
    ]
    var terms = 0
    var point = _checked_center(road, 0, lane, seed, terms, 2000000)
    var scale = Float64(0.25)
    var score = _refinement_square[3](point, q, scale)
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(5.62500000000001, 6.000000000000009, 0, 0.0, scale)
    ]
    return _LaneCertificate(
        seed, point^, scale, 0.0, score.high, False, cells^, 0, terms
    )


def test_count_join_public_query_completes_default_budget() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var strict = map.certified_waypoint(_query())
    var nearest = map.certified_closest_waypoint_on_road(_query())
    assert_true(Bool(strict))
    assert_true(Bool(nearest))
    assert_equal(strict.value().road_id.value, 5)
    assert_equal(strict.value().section_id.value, 0)
    assert_equal(strict.value().lane_id.value, -1)
    assert_equal(strict.value().s, nearest.value().s)
    assert_equal(map.certified_waypoint(_query()).value().s, strict.value().s)


def test_retry_room_exact_and_one_short_preserves_frontier() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    ref road = map.roads[map.road_index(RoadId(5))]
    var lane = road.sections[0].lane_index(LaneId(-1))
    var price = _query_node_step_cost(len(road.sections[0].lanes), True, True)
    var reference = _reference_work(road, 5.62500000000001, 6.000000000000009)
    assert_equal(reference, 75)
    for short in range(4):
        var certificate = _certificate(road, lane)
        var old = certificate.copy()
        var terms = certificate.terms
        var policy = MapQueryBudget(4096)
        policy.max_nodes = 116 - Int(short == 1)
        policy.max_terms = 360 * reference - Int(short == 2)
        policy.max_steps = 72 + 17 + 116 * price - Int(short == 3)
        var work = _MapQueryWork(policy)
        var result = _try_winner_seed(
            road,
            0,
            lane,
            5.62500000000001,
            6.000000000000009,
            road,
            0,
            5.62500000000001,
            6.000000000000009,
            _query(),
            certificate,
            0,
            terms,
            1,
            17,
            work,
        )
        assert_equal(len(certificate.cells), 1)
        assert_equal(certificate.cells[0].low, old.cells[0].low)
        assert_equal(certificate.cells[0].high, old.cells[0].high)
        assert_equal(certificate.lower, old.lower)
        assert_false(certificate.exact_witness)
        if short != 0:
            assert_false(result)
            assert_equal(work.nodes, 2)
            assert_equal(work.terms, 2 * reference)
            assert_equal(work.steps, 72 + 2 * price)
            assert_equal(certificate.s, old.s)
        else:
            assert_equal(work.nodes, 90)
            assert_equal(work.terms, 5 * reference + 255 * 40)
            assert_equal(work.steps, 72 + 90 * price)
            var query = _query()
            var q: Array[Float64, 3] = [
                Float64(query.x),
                Float64(query.y),
                Float64(query.z),
            ]
            var order = _wide_point_order(certificate.point, old.point, q)
            assert_true(order <= 0)
            assert_equal(result, order < 0)


def test_full_first_task_reservation_covers_local_seed_and_taylor() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    ref road = map.roads[map.road_index(RoadId(5))]
    var lane = road.sections[0].lane_index(LaneId(-1))
    var target_terms = 0
    var target = _checked_center(road, 0, lane, 5.731, target_terms, 2000000)
    var location = Vector3(
        Float32(target[0]), Float32(target[1]), Float32(target[2])
    )
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var low = Float64(5.7)
    var high = Float64(5.8)
    var reference = _reference_work(road, low, high)
    assert_true(reference > 0)
    for units in [4, 50]:
        var terms = 0
        var point = _checked_center(road, 0, lane, high, terms, 2000000)
        var score = _refinement_square[3](point, query, 0.25)
        var cells: List[_ClosedInterval] = [
            _ClosedInterval(low, high, 0, 0.0, 0.25)
        ]
        var certificate = _LaneCertificate(
            high, point^, 0.25, 0.0, score.high, False, cells^, 0, terms
        )
        if units == 4:
            with assert_raises(contains="quadrature work limit"):
                _continue_lane_certificate(
                    road,
                    0,
                    lane,
                    low,
                    high,
                    location,
                    certificate,
                    None,
                    0.25,
                    max_nodes=3,
                    max_terms=terms + units * reference,
                )
        else:
            _continue_lane_certificate(
                road,
                0,
                lane,
                low,
                high,
                location,
                certificate,
                None,
                0.25,
                max_nodes=3,
                max_terms=terms + units * reference,
            )
            assert_true(certificate.terms - terms >= 45 * reference)
            assert_true(certificate.terms - terms <= 50 * reference)
            assert_true(certificate.nodes <= 3)


def test_smooth_root_exact_and_one_short_keeps_two_setup_path() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    ref road = map.roads[map.road_index(RoadId(5))]
    var lane = road.sections[0].lane_index(LaneId(-1))
    var low = Float64(5.7)
    var high = Float64(5.8)
    var price = _query_node_step_cost(len(road.sections[0].lanes), True, True)
    var reference = _reference_work(road, low, high)
    assert_true(reference > 0)
    var location = _query()
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    for short in range(4):
        var terms = 0
        var point = _checked_center(road, 0, lane, 5.75, terms, 2000000)
        var score = _refinement_square[3](point, query, 0.25)
        var cells: List[_ClosedInterval] = [
            _ClosedInterval(low, high, 0, 0.0, 0.25)
        ]
        var certificate = _LaneCertificate(
            5.75, point^, 0.25, 0.0, score.high, False, cells^, 0, terms
        )
        var policy = MapQueryBudget(4096)
        policy.max_nodes = 113 - Int(short == 1)
        policy.max_terms = 357 * reference - Int(short == 2)
        policy.max_steps = 60 + 17 + 113 * price - Int(short == 3)
        var work = _MapQueryWork(policy)
        var result = _try_winner_seed(
            road,
            0,
            lane,
            low,
            high,
            road,
            0,
            low,
            high,
            location,
            certificate,
            0,
            terms,
            1,
            17,
            work,
        )
        if short != 0:
            assert_false(result)
            assert_equal(work.nodes, 0)
            assert_equal(work.terms, 0)
            assert_equal(work.steps, 60)
            assert_equal(certificate.s, 5.75)
        else:
            assert_true(result)
            assert_equal(work.nodes, 87)
            assert_equal(work.terms, 257 * reference)
            assert_equal(work.steps, 60 + 87 * price)
        assert_equal(len(certificate.cells), 1)
        assert_equal(certificate.cells[0].low, low)
        assert_equal(certificate.cells[0].high, high)
        assert_equal(certificate.lower, 0.0)
        assert_false(certificate.exact_witness)


def test_unresolved_local_band_keeps_every_paid_attempt() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    ref road = map.roads[map.road_index(RoadId(5))]
    var lane = road.sections[0].lane_index(LaneId(-1))
    var certificate = _certificate(road, lane, 5.913)
    var original = certificate.copy()
    var reference = _reference_work(road, 5.62500000000001, 6.000000000000009)
    var price = _query_node_step_cost(len(road.sections[0].lanes), True, True)
    var work = _MapQueryWork(MapQueryBudget())
    assert_false(
        _try_winner_seed(
            road,
            0,
            lane,
            5.62500000000001,
            6.000000000000009,
            road,
            0,
            5.62500000000001,
            6.000000000000009,
            _query(),
            certificate,
            0,
            original.terms,
            1,
            17,
            work,
        )
    )
    assert_equal(work.nodes, 5)
    assert_equal(work.terms, 5 * reference)
    assert_equal(work.steps, 72 + 5 * price)
    assert_equal(certificate.s, original.s)
    assert_equal(certificate.terms, original.terms + work.terms)
    assert_equal(len(certificate.cells), 1)
    assert_equal(certificate.cells[0].low, original.cells[0].low)
    assert_equal(certificate.cells[0].high, original.cells[0].high)
    assert_equal(certificate.lower, original.lower)


def test_first_competitor_pass_keeps_published_work_without_seed_batch() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var query = Vector3(
        bitcast[DType.float32](UInt32(1092315480)),
        bitcast[DType.float32](UInt32(3268224514)),
        bitcast[DType.float32](UInt32(1067030938)),
    )
    var published_work = _MapQueryWork(MapQueryBudget())
    var published = (
        _published_first_pass_with_work(
            map, query, LANE_DRIVING, published_work
        )
        .value()
        .copy()
    )
    assert_equal(published[2], 1)
    assert_equal(published_work.candidates, 2)
    assert_false(published[1].exact_witness)
    var work = _MapQueryWork(MapQueryBudget())
    var current = (
        map._closest_lane_certificate_with_work(query, LANE_DRIVING, work)
        .value()
        .copy()
    )
    assert_equal(work.nodes, published_work.nodes)
    assert_equal(work.terms, published_work.terms)
    assert_equal(work.steps, published_work.steps)
    assert_equal(work.index_pops, published_work.index_pops)
    assert_equal(work.candidates, published_work.candidates)
    assert_equal(current[0].s, published[0].s)
    assert_equal(current[0].road_id, published[0].road_id)
    assert_equal(current[0].lane_id, published[0].lane_id)
    for axis in range(3):
        assert_equal(current[1].point[axis], published[1].point[axis])
    # This is a real eligible SPIRAL pair. An eager attempt would consume
    # the complete 87-node batch even if it did not improve the witness.
    ref road = map.roads[map.road_index(RoadId(5))]
    var lane = road.sections[0].lane_index(LaneId(1))
    var probe = published[1].copy()
    var seed_work = _MapQueryWork(MapQueryBudget())
    _ = _try_winner_seed(
        road,
        0,
        lane,
        10.00000000000005,
        10.50000000000005,
        road,
        0,
        9.50000000000005,
        10.00000000000005,
        query,
        probe,
        0,
        0,
        1,
        10000,
        seed_work,
    )
    assert_equal(seed_work.nodes, 87)


def test_clamp_uncertainty_on_either_owner_declines_before_producers() raises:
    for back in range(3):
        var road = _road()
        var rate = bitcast[DType.float64](
            UInt64(0x3FEFFFFFFFFFFFFF) - UInt64(back)
        )
        road.info.geometries[0] = RoadInfoGeometry(
            0.1,
            with_spiral(
                RoadGeometry(SPIRAL, 0.1, 0.0, 0.0, 0.0, 1.0), 0.0, rate
            ),
        )
        for side in range(3):
            var low = Float64(0.2)
            var high = Float64(0.3)
            var target_low = Float64(0.2)
            var target_high = Float64(0.3)
            if side == 0:
                low = 1.09
                high = 1.2
            elif side == 1:
                target_low = 1.09
                target_high = 1.2
            else:
                low = 0.1
                high = 0.2
            var seed = low + 0.5 * (high - low)
            var terms = 0
            var point = _checked_center(road, 0, 0, seed, terms, 2000000)
            var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
            var score = _refinement_square[3](point, query, 1.0)
            var cells: List[_ClosedInterval] = [
                _ClosedInterval(low, high, 0, 0.0, 1.0)
            ]
            var certificate = _LaneCertificate(
                seed, point^, 1.0, 0.0, score.high, False, cells^, 0, terms
            )
            var work = _MapQueryWork(MapQueryBudget())
            assert_false(
                _try_winner_seed(
                    road,
                    0,
                    0,
                    low,
                    high,
                    road,
                    0,
                    target_low,
                    target_high,
                    Vector3(0, 0, 0),
                    certificate,
                    0,
                    0,
                    1,
                    0,
                    work,
                )
            )
            assert_equal(work.nodes, 0)
            assert_equal(work.terms, 0)
            assert_equal(work.steps, 60)
            assert_equal(certificate.s, seed)
            assert_equal(certificate.terms, terms)
            assert_equal(len(certificate.cells), 1)
            assert_equal(certificate.cells[0].low, low)
            assert_equal(certificate.cells[0].high, high)


def test_exact_range_membership_checks_the_whole_interval() raises:
    var minimum = bitcast[DType.float64](UInt64(0x26F0000000000000))
    var maximum = bitcast[DType.float64](UInt64(0x58F0000000000000))
    assert_true(_seed_exact_interval(_Interval(-0.0, 0.0)))
    assert_true(_seed_exact_interval(_Interval(minimum, maximum)))
    assert_true(_seed_exact_interval(_Interval(-maximum, -minimum)))
    assert_false(_seed_exact_interval(_Interval(0.0, minimum)))
    assert_false(_seed_exact_interval(_Interval(-minimum, 0.0)))
    assert_false(_seed_exact_interval(_Interval(-minimum, minimum)))
    assert_false(_seed_exact_interval(_Interval(_next_down(minimum), minimum)))
    assert_false(
        _seed_exact_interval(_Interval(-minimum, -_next_down(minimum)))
    )
    assert_false(_seed_exact_interval(_Interval(maximum, _next_up(maximum))))
    assert_false(_seed_exact_interval(_Interval(-_next_up(maximum), -maximum)))
    assert_false(_seed_exact_interval(_Interval(2.0, 1.0)))
    assert_false(_seed_exact_interval(_Interval.whole()))


def test_uniform_reference_predicate_declines_arithmetic_path_changes() raises:
    var minimum = bitcast[DType.float64](UInt64(0x26F0000000000000))
    var geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 1.0), 0.0, 0.0
    )
    assert_true(_seed_reference_domain(geometry, 0.0, 0.2, 0.3))
    geometry.curvature_start = 0.25
    geometry.curvature_end = 0.5
    assert_true(_seed_reference_domain(geometry, 0.1, 0.2, 0.3))
    geometry.curvature_start = 0.5
    geometry.curvature_end = 0.25
    assert_true(_seed_reference_domain(geometry, 0.1, 0.2, 0.3))
    # The tight-sum counterexample's parent includes values just outside
    # the exact endpoint domain. Point admissibility alone is insufficient.
    geometry.curvature_start = bitcast[DType.float64](UInt64(675) << UInt64(52))
    geometry.curvature_end = 1.0
    assert_false(_seed_reference_domain(geometry, 0.0, minimum * 0.5, minimum))
    assert_false(
        _seed_reference_domain(geometry, _next_down(minimum), 0.2, 0.3)
    )
    geometry.curvature_start = _next_down(minimum)
    assert_false(_seed_reference_domain(geometry, 0.0, 0.2, 0.3))
    geometry.curvature_start = 0.0
    geometry.curvature_end = _next_down(minimum)
    assert_false(_seed_reference_domain(geometry, 0.0, 0.2, 0.3))
    geometry.curvature_end = minimum
    assert_false(_seed_reference_domain(geometry, 0.0, 0.2, 0.3))
    geometry.curvature_end = 0.0
    geometry.length = 0.0
    assert_false(_seed_reference_domain(geometry, 0.0, 0.2, 0.3))
    geometry.length = bitcast[DType.float64](UInt64(0x7FF0000000000000))
    assert_false(_seed_reference_domain(geometry, 0.0, 0.2, 0.3))
    geometry.length = bitcast[DType.float64](UInt64(1078) << UInt64(52))
    var origin = bitcast[DType.float64](UInt64(1063) << UInt64(52))
    var low = bitcast[DType.float64](UInt64(1077) << UInt64(52))
    assert_false(_seed_reference_domain(geometry, origin, low, _next_up(low)))


def _seed_road(id: Int = 1) raises -> Road:
    var road = _road(id=id)
    road.info.geometries[0].geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 4.0), 0.0, 0.0
    )
    return road^


def _produced_seed(
    road: Road, low: Float64, high: Float64, mut work: _MapQueryWork
) raises -> _LaneCertificate:
    # Match the seed-only refiner admission and debit in Map's segment query.
    var price = _query_node_step_cost(len(road.sections[0].lanes))
    var result = _refine_lane_certificate(
        road,
        0,
        0,
        low,
        high,
        Vector3(0, 1, 0),
        low,
        0.0,
        max_nodes=work.node_cap(step_cost=price),
        max_terms=work.term_cap(),
        seed_only=True,
    )
    work.charge(result.nodes, result.terms, price)
    return result^


def _same_certificate_except_work(
    before: _LaneCertificate,
    after: _LaneCertificate,
    nodes: Int,
    terms: Int,
) raises:
    assert_equal(after.s, before.s)
    assert_equal(after.point, before.point)
    assert_equal(after.scale, before.scale)
    assert_equal(after.lower, before.lower)
    assert_equal(after.upper, before.upper)
    assert_equal(after.exact_witness, before.exact_witness)
    assert_equal(after.nodes, before.nodes + nodes)
    assert_equal(after.terms, before.terms + terms)
    assert_equal(len(after.cells), len(before.cells))
    for i in range(len(before.cells)):
        assert_equal(after.cells[i].low, before.cells[i].low)
        assert_equal(after.cells[i].high, before.cells[i].high)
        assert_equal(after.cells[i].depth, before.cells[i].depth)
        assert_equal(after.cells[i].lower, before.cells[i].lower)
        assert_equal(after.cells[i].scale, before.cells[i].scale)


def _attempt(
    road: Road,
    target_road: Road,
    low: Float64,
    high: Float64,
    mut certificate: _LaneCertificate,
    target: _LaneCertificate,
    followup: Int,
    mut work: _MapQueryWork,
) raises -> Bool:
    return _try_winner_seed(
        road,
        0,
        0,
        low,
        high,
        target_road,
        0,
        low,
        high,
        Vector3(0, 1, 0),
        certificate,
        target.nodes,
        target.terms,
        len(target.cells),
        followup,
        work,
    )


def test_seed_reference_rejects_a_zero_local_distance() raises:
    var road = _seed_road()
    ref geometry = road.info.geometries[0].geometry
    assert_false(_seed_reference_domain(geometry, 0.25, 0.25, 0.25))
    assert_true(_seed_reference_domain(geometry, 0.25, 0.5, 0.75))


def test_optional_seed_declines_an_unpaid_entry_kernel() raises:
    var road = _seed_road()
    var target_road = _seed_road(2)
    var work = _MapQueryWork(MapQueryBudget())
    var certificate = _produced_seed(road, 0.25, 0.3, work)
    var target = _produced_seed(target_road, 0.25, 0.3, work)
    var before = certificate.copy()
    var entry_steps = work.steps
    work.policy.max_steps = entry_steps + 59
    assert_false(
        _attempt(road, target_road, 0.25, 0.3, certificate, target, 0, work)
    )
    _same_certificate_except_work(before, certificate, 0, 0)
    assert_equal(work.steps, entry_steps)
    assert_equal(work.nodes, before.nodes + target.nodes)
    assert_equal(work.terms, before.terms + target.terms)
    assert_false(work.exhausted)


def test_optional_seed_preserves_each_short_local_node_prefix() raises:
    var road = _seed_road()
    var target_road = _seed_road(2)
    for available in [12, 13]:
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, 0.25, 0.3, work)
        var target = _produced_seed(target_road, 0.25, 0.3, work)
        var before = certificate.copy()
        var entry_steps = work.steps
        work.policy.max_nodes = work.nodes + available
        assert_false(
            _attempt(road, target_road, 0.25, 0.3, certificate, target, 0, work)
        )
        _same_certificate_except_work(before, certificate, 0, 0)
        assert_equal(work.steps, entry_steps + 60)
        assert_equal(work.nodes, before.nodes + target.nodes)
        assert_equal(work.terms, before.terms + target.terms)
        assert_false(work.exhausted)


def test_optional_seed_reserves_followup_before_its_own_steps() raises:
    var road = _seed_road()
    var target_road = _seed_road(2)
    var price = _query_node_step_cost(1, True, True)
    for followup in [113 * price + 1, 13 * price + 1]:
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, 0.25, 0.3, work)
        var target = _produced_seed(target_road, 0.25, 0.3, work)
        var before = certificate.copy()
        var entry_steps = work.steps
        work.policy.max_steps = entry_steps + 60 + 113 * price
        assert_false(
            _attempt(
                road,
                target_road,
                0.25,
                0.3,
                certificate,
                target,
                followup,
                work,
            )
        )
        _same_certificate_except_work(before, certificate, 0, 0)
        assert_equal(work.steps, entry_steps + 60)
        assert_equal(work.nodes, before.nodes + target.nodes)
        assert_equal(work.terms, before.terms + target.terms)
        assert_false(work.exhausted)


def test_optional_seed_declines_one_short_winner_term_reserve() raises:
    var road = _seed_road()
    var target_road = _seed_road(2)
    var work = _MapQueryWork(MapQueryBudget())
    var certificate = _produced_seed(road, 0.25, 0.3, work)
    var target = _produced_seed(target_road, 0.25, 0.3, work)
    var before = certificate.copy()
    var entry_steps = work.steps
    var reference = _reference_work(road, 0.25, 0.3)
    assert_equal(reference, 10)
    work.policy.max_terms = work.terms + 307 * reference - 1
    assert_false(
        _attempt(road, target_road, 0.25, 0.3, certificate, target, 0, work)
    )
    _same_certificate_except_work(before, certificate, 0, 0)
    assert_equal(work.steps, entry_steps + 60)
    assert_equal(work.nodes, before.nodes + target.nodes)
    assert_equal(work.terms, before.terms + target.terms)
    assert_false(work.exhausted)


def _profile_boundary(low: Float64, high: Float64, proposals: Bool) raises:
    var road = _seed_road()
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(high, CubicPolynomial.constant(4.0))
    )
    var target_road = _seed_road(2)
    var work = _MapQueryWork(MapQueryBudget())
    var certificate = _produced_seed(road, low, high, work)
    var target = _produced_seed(target_road, low, high, work)
    var entry_steps = work.steps
    assert_false(certificate.exact_witness)
    assert_equal(certificate.s, low)
    assert_equal(certificate.point[0], low)
    assert_equal(certificate.point[1], 0.0)
    assert_equal(certificate.point[2], 0.0)
    var before = certificate.copy()
    var price = _query_node_step_cost(1, True, True)
    var reference = _reference_work(road, low, high)
    assert_equal(reference, 10)
    assert_false(
        _attempt(road, target_road, low, high, certificate, target, 0, work)
    )
    var nodes = 88 if proposals else 3
    var terms = 258 * reference if proposals else 3 * reference
    _same_certificate_except_work(before, certificate, nodes, terms)
    assert_equal(work.nodes, before.nodes + target.nodes + nodes)
    assert_equal(work.terms, before.terms + target.terms + terms)
    assert_equal(work.steps, entry_steps + 72 + nodes * price)
    assert_false(work.exhausted)


def test_optional_seed_declines_a_collapsed_adjacent_profile_band() raises:
    _profile_boundary(0.25, _next_up(0.25), False)


def test_optional_seed_declines_a_stationary_adjacent_profile_band() raises:
    var low = _next_up(0.25)
    _profile_boundary(low, _next_up(low), False)


def test_optional_seed_stops_retrying_after_the_band_becomes_smooth() raises:
    _profile_boundary(0.25, 0.3, True)


# These controls call the optional helper on actual charged certificates.
# They do not claim the complete public Map metadata-prefix path.


def _assert_optional_seed_debits(
    before: _LaneCertificate,
    certificate: _LaneCertificate,
    target_before: _LaneCertificate,
    target: _LaneCertificate,
    entry_steps: Int,
    price: Int,
    nodes: Int,
    terms: Int,
    work: _MapQueryWork,
) raises:
    _same_certificate_except_work(before, certificate, nodes, terms)
    _same_certificate_except_work(target_before, target, 0, 0)
    assert_equal(work.nodes, before.nodes + target_before.nodes + nodes)
    assert_equal(work.terms, before.terms + target_before.terms + terms)
    assert_equal(work.steps, entry_steps + 60 + nodes * price)
    assert_false(work.exhausted)


def test_optional_seed_reserves_both_owners_at_the_global_node_boundary() raises:
    var road = _seed_road()
    var target_road = _seed_road(2)
    var price = _query_node_step_cost(1, True, True)
    var reference = _reference_work(road, 0.25, 0.3)
    assert_equal(reference, 10)
    for available in [112, 113]:
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, 0.25, 0.3, work)
        var target = _produced_seed(target_road, 0.25, 0.3, work)
        assert_equal(len(certificate.cells), 1)
        assert_equal(len(target.cells), 1)
        assert_false(certificate.exact_witness)
        assert_equal(certificate.s, 0.25)
        assert_equal(certificate.point[0], 0.25)
        assert_equal(certificate.point[1], 0.0)
        assert_equal(certificate.point[2], 0.0)
        var before = certificate.copy()
        var target_before = target.copy()
        var entry_steps = work.steps
        work.policy.max_nodes = work.nodes + available
        assert_false(
            _attempt(road, target_road, 0.25, 0.3, certificate, target, 0, work)
        )
        var nodes = 87 if available == 113 else 0
        var terms = 257 * reference if available == 113 else 0
        _assert_optional_seed_debits(
            before,
            certificate,
            target_before,
            target,
            entry_steps,
            price,
            nodes,
            terms,
            work,
        )


def test_optional_seed_declines_only_the_expensive_target_node_prefix() raises:
    var road = _seed_road()
    var target_road = _seed_road(2)
    # Positive-side lanes preserve the selected negative lane at index zero.
    for id in range(1, 15):
        var lane = target_road.sections[0].add_lane(LaneId(id))
        target_road.sections[0].lanes[lane].type = LANE_DRIVING
        target_road.sections[0].lanes[lane].info.widths.append(
            RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
        )
    assert_equal(len(target_road.sections[0].lanes), 15)
    assert_equal(target_road.sections[0].lanes[0].id, LaneId(-1))
    var price = _query_node_step_cost(1, True, True)
    var target_price = _query_node_step_cost(15, True, True)
    assert_equal(price, 182)
    assert_equal(target_price, 1582)
    assert_equal((13 * target_price - 1) // price, 112)
    assert_equal((13 * target_price - 1) // target_price, 12)
    for short in [True, False]:
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, 0.25, 0.3, work)
        var target = _produced_seed(target_road, 0.25, 0.3, work)
        assert_equal(len(certificate.cells), 1)
        assert_equal(len(target.cells), 1)
        assert_equal(target.point, certificate.point)
        var before = certificate.copy()
        var target_before = target.copy()
        var entry_steps = work.steps
        var available = (
            13 * target_price - 1 if short else 100 * price + 13 * target_price
        )
        work.policy.max_steps = entry_steps + 60 + available
        assert_false(
            _attempt(road, target_road, 0.25, 0.3, certificate, target, 0, work)
        )
        var nodes = 0 if short else 87
        var terms = 0 if short else 2570
        _assert_optional_seed_debits(
            before,
            certificate,
            target_before,
            target,
            entry_steps,
            price,
            nodes,
            terms,
            work,
        )


def test_optional_seed_declines_only_the_target_term_reserve() raises:
    var road = _seed_road()
    var target_road = _seed_road(2)
    target_road.info.geometries[0].geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 4.0), 74.0, 74.0
    )
    var low = Float64(0.25)
    var high = Float64(0.2501)
    var price = _query_node_step_cost(1, True, True)
    var reference = _reference_work(road, low, high)
    var target_reference = _reference_work(target_road, low, high)
    assert_equal(reference, 10)
    assert_equal(target_reference, 100)
    assert_true(
        _seed_reference_domain(
            target_road.info.geometries[0].geometry, 0.0, low, high
        )
    )
    # 4999 fails the target's own 50F prefix. 5000 passes both local term
    # checks but cannot reserve both owners. 8070 admits the full reserve.
    for available in [4999, 5000, 8070]:
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, low, high, work)
        var target = _produced_seed(target_road, low, high, work)
        assert_equal(len(certificate.cells), 1)
        assert_equal(len(target.cells), 1)
        assert_false(target.exact_witness)
        assert_equal(target.s, low)
        assert_equal(target.terms, target_reference)
        var before = certificate.copy()
        var target_before = target.copy()
        var entry_steps = work.steps
        work.policy.max_terms = work.terms + available
        assert_false(
            _attempt(road, target_road, low, high, certificate, target, 0, work)
        )
        var nodes = 87 if available == 8070 else 0
        var terms = 257 * reference if available == 8070 else 0
        _assert_optional_seed_debits(
            before,
            certificate,
            target_before,
            target,
            entry_steps,
            price,
            nodes,
            terms,
            work,
        )


def test_optional_seed_declines_an_unresolved_target_reference_count() raises:
    var road = _seed_road()
    var target_road = _seed_road(2)
    var price = _query_node_step_cost(1, True, True)
    for target_high in [Float64(3.9), Float64(0.3)]:
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, 0.25, 0.3, work)
        var target = _produced_seed(target_road, 0.25, target_high, work)
        assert_false(target.exact_witness)
        assert_equal(target.s, 0.25)
        assert_equal(target.point, certificate.point)
        assert_equal(len(target.cells), 1)
        assert_equal(target.cells[0].high, target_high)
        assert_true(
            _seed_reference_domain(
                target_road.info.geometries[0].geometry, 0.0, 0.25, target_high
            )
        )
        var reference = _reference_work(target_road, 0.25, target_high)
        assert_equal(reference, -1 if target_high == 3.9 else 10)
        var before = certificate.copy()
        var target_before = target.copy()
        var entry_steps = work.steps
        assert_false(
            _try_winner_seed(
                road,
                0,
                0,
                0.25,
                0.3,
                target_road,
                0,
                0.25,
                target_high,
                Vector3(0, 1, 0),
                certificate,
                target.nodes,
                target.terms,
                len(target.cells),
                0,
                work,
            )
        )
        var nodes = 0 if target_high == 3.9 else 87
        var terms = 0 if target_high == 3.9 else 2570
        _assert_optional_seed_debits(
            before,
            certificate,
            target_before,
            target,
            entry_steps,
            price,
            nodes,
            terms,
            work,
        )


def test_optional_seed_declines_real_exact_and_zero_origin_certificates() raises:
    for kind in range(3):
        var road = _seed_road()
        var target_road = _seed_road(2)
        var low = Float64(0.25)
        var high = Float64(0.3)
        if kind == 0:
            # The regular LINE producer certifies a non-singleton minimum.
            road = _road()
        elif kind == 1:
            low = 0.0
        else:
            # The SPIRAL singleton producer also returns an exact witness.
            high = low
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, low, high, work)
        var target = _produced_seed(target_road, low, high, work)
        assert_equal(certificate.exact_witness, kind != 1)
        assert_equal(certificate.s, low)
        assert_equal(certificate.point[0], low)
        assert_equal(certificate.point[1], 0.0)
        assert_equal(certificate.point[2], 0.0)
        var before = certificate.copy()
        var target_before = target.copy()
        var entry_steps = work.steps
        assert_false(
            _attempt(road, target_road, low, high, certificate, target, 0, work)
        )
        _assert_optional_seed_debits(
            before,
            certificate,
            target_before,
            target,
            entry_steps,
            _query_node_step_cost(1, True, True),
            0,
            0,
            work,
        )


def test_optional_seed_declines_changed_geometry_owners_and_line_targets() raises:
    for kind in range(3):
        var road = _seed_road()
        var target_road = _seed_road(2)
        if kind == 0:
            # Low-level root controls can cross a record boundary. Map's
            # normal construction splits these roots before querying them.
            road.info.geometries[0].geometry.length = 0.3
            road.info.geometries.append(
                RoadInfoGeometry(
                    0.3,
                    with_spiral(
                        RoadGeometry(SPIRAL, 0.3, 0.3, 0.0, 0.0, 3.7),
                        0.0,
                        0.0,
                    ),
                )
            )
        elif kind == 1:
            target_road.info.geometries[0].geometry.length = 0.3
            target_road.info.geometries.append(
                RoadInfoGeometry(
                    0.3,
                    with_spiral(
                        RoadGeometry(SPIRAL, 0.3, 0.3, 0.0, 0.0, 3.7),
                        0.0,
                        0.0,
                    ),
                )
            )
        else:
            target_road = _road(id=2)
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, 0.25, 0.3, work)
        var target = _produced_seed(target_road, 0.25, 0.3, work)
        assert_false(certificate.exact_witness)
        assert_equal(certificate.s, 0.25)
        assert_equal(certificate.point, target.point)
        assert_equal(len(certificate.cells), 1)
        assert_equal(len(target.cells), 1)
        var before = certificate.copy()
        var target_before = target.copy()
        var entry_steps = work.steps
        assert_false(
            _attempt(road, target_road, 0.25, 0.3, certificate, target, 0, work)
        )
        _assert_optional_seed_debits(
            before,
            certificate,
            target_before,
            target,
            entry_steps,
            _query_node_step_cost(1, True, True),
            0,
            0,
            work,
        )


def test_count_join_public_step_caps_decline_each_followup_prefix() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var query = _query()
    var expected = map.certified_closest_waypoint_on_road(query)
    assert_true(Bool(expected))
    var default_work = _MapQueryWork(MapQueryBudget())
    var default_result = map._closest_lane_certificate_with_work(
        query, LANE_DRIVING, default_work
    )
    assert_true(Bool(default_result))
    assert_equal(default_result.value()[0].road_id, expected.value().road_id)
    assert_equal(
        default_result.value()[0].section_id, expected.value().section_id
    )
    assert_equal(default_result.value()[0].lane_id, expected.value().lane_id)
    assert_equal(default_result.value()[0].s, expected.value().s)
    assert_false(default_work.exhausted)
    var policy = MapQueryBudget()
    policy.max_steps = 100000
    var work = _MapQueryWork(policy)
    var sufficient = map._closest_lane_certificate_with_work(
        query, LANE_DRIVING, work
    )
    assert_true(Bool(sufficient))
    assert_equal(sufficient.value()[0].road_id, expected.value().road_id)
    assert_equal(sufficient.value()[0].section_id, expected.value().section_id)
    assert_equal(sufficient.value()[0].lane_id, expected.value().lane_id)
    assert_equal(sufficient.value()[0].s, expected.value().s)
    # A nonbinding cap preserves the same mode's result and actual ledger.
    # Supported arithmetic modes may visit a different spatial-index path.
    assert_equal(work.steps, default_work.steps)
    assert_equal(work.nodes, default_work.nodes)
    assert_equal(work.terms, default_work.terms)
    assert_equal(work.nodes, 111)
    assert_equal(work.terms, 17817)
    assert_equal(work.candidates, default_work.candidates)
    assert_equal(work.index_pops, default_work.index_pops)
    assert_equal(work.peak_queue_entries, default_work.peak_queue_entries)
    assert_equal(work.exhausted, default_work.exhausted)
    assert_true(work.steps <= policy.max_steps)
    var refusal_policy = MapQueryBudget()
    refusal_policy.max_steps = 7889
    var refusal_work = _MapQueryWork(refusal_policy)
    with assert_raises(
        contains="Lane refinement exhausted its interval work limit"
    ):
        _ = map._closest_lane_certificate_with_work(
            query, LANE_DRIVING, refusal_work
        )
    assert_equal(refusal_work.nodes, 14)
    assert_equal(refusal_work.terms, 4990)
    assert_false(refusal_work.exhausted)
    assert_true(refusal_work.steps > 0)
    assert_true(refusal_work.steps <= refusal_policy.max_steps)
    # With the metadata-refusal control above, these fixed public caps reach
    # metadata, candidate, winner and target prefix refusals in both modes.
    # Prefix estimates do not debit work. Each decline reaches the same
    # ordinary continuation and preserves every actual consumed counter.
    for limit in [7910, 7913, 7917, 7919, 7922, 7925]:
        policy.max_steps = limit
        work = _MapQueryWork(policy)
        with assert_raises(
            contains="Lane refinement exhausted its interval work limit"
        ):
            _ = map._closest_lane_certificate_with_work(
                query, LANE_DRIVING, work
            )
        assert_equal(work.steps, refusal_work.steps)
        assert_equal(work.nodes, 14)
        assert_equal(work.terms, 4990)
        assert_equal(work.candidates, refusal_work.candidates)
        assert_equal(work.index_pops, refusal_work.index_pops)
        assert_equal(work.peak_queue_entries, refusal_work.peak_queue_entries)
        assert_false(work.exhausted)
        assert_true(work.steps <= policy.max_steps)


def _finite_width_overflow_road(
    b: Float64, c: Float64, d: Float64
) raises -> Road:
    var road = _seed_road()
    road.length = 0.375
    road.info.geometries[0].geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 0.375), 0.0, 0.0
    )
    var polynomial = CubicPolynomial(2.0, b, c, d, 0.0)
    assert_true(isfinite(polynomial.a))
    assert_true(isfinite(polynomial.b))
    assert_true(isfinite(polynomial.c))
    assert_true(isfinite(polynomial.d))
    road.sections[0].lanes[0].info.widths[0] = RoadInfoLaneWidth(
        0.0, polynomial
    )
    return road^


def test_optional_seed_preserves_finite_center_when_first_derivative_overflows() raises:
    # The canonical Float64 center remains finite. This helper control does
    # not require a representable public Float32 pose for this large curve.
    var road = _finite_width_overflow_road(1.5e308, 5.0e307, 0.0)
    var target_road = _seed_road(2)
    var low = Float64(0.3)
    var high = Float64(0.35)
    var work = _MapQueryWork(MapQueryBudget())
    var certificate = _produced_seed(road, low, high, work)
    var target = _produced_seed(target_road, low, high, work)
    var before = certificate.copy()
    var target_before = target.copy()
    var entry_steps = work.steps
    for coordinate in certificate.point:
        assert_true(isfinite(coordinate))
    assert_false(certificate.exact_witness)
    assert_true(
        _seed_reference_domain(road.info.geometries[0].geometry, 0.0, low, high)
    )
    var reference = _reference_work(road, low, high)
    assert_equal(reference, 10)
    var center = _expansion_distance_jet(
        road, 0, 0, certificate.s, Vector3(0, 1, 0), certificate.scale
    )
    assert_false(center.first.is_finite())
    assert_false(
        _attempt(road, target_road, low, high, certificate, target, 0, work)
    )
    _assert_optional_seed_debits(
        before,
        certificate,
        target_before,
        target,
        entry_steps,
        _query_node_step_cost(1, True, True),
        2,
        2 * reference,
        work,
    )


def test_optional_seed_preserves_finite_first_derivative_when_second_overflows() raises:
    var road = _finite_width_overflow_road(0.0, 6.0e307, 4.0e307)
    var target_road = _seed_road(2)
    var low = Float64(0.25)
    var high = Float64(0.3)
    var work = _MapQueryWork(MapQueryBudget())
    var certificate = _produced_seed(road, low, high, work)
    var target = _produced_seed(target_road, low, high, work)
    var before = certificate.copy()
    var target_before = target.copy()
    var entry_steps = work.steps
    for coordinate in certificate.point:
        assert_true(isfinite(coordinate))
    assert_false(certificate.exact_witness)
    assert_true(
        _seed_reference_domain(road.info.geometries[0].geometry, 0.0, low, high)
    )
    var reference = _reference_work(road, low, high)
    assert_equal(reference, 10)
    var domain = _scaled_point_distance_jet(
        _lane_jet(road, 0, 0, low, high), Vector3(0, 1, 0), certificate.scale
    )
    var center = _expansion_distance_jet(
        road, 0, 0, certificate.s, Vector3(0, 1, 0), certificate.scale
    )
    assert_true(center.first.is_finite())
    assert_true(domain.first.is_finite())
    assert_false(domain.second.is_finite())
    assert_false(
        _attempt(road, target_road, low, high, certificate, target, 0, work)
    )
    _same_certificate_except_work(before, certificate, 5, 5 * reference)
    _same_certificate_except_work(target_before, target, 0, 0)
    assert_equal(work.nodes, before.nodes + target_before.nodes + 5)
    assert_equal(work.terms, before.terms + target_before.terms + 5 * reference)
    assert_equal(
        work.steps, entry_steps + 72 + 5 * _query_node_step_cost(1, True, True)
    )
    assert_false(work.exhausted)


def _assert_reference_count_descendants(
    origin: Float64,
    length: Float64,
    curvature_start: Float64,
    curvature_end: Float64,
    low: Float64,
    high: Float64,
) raises -> Int:
    # Only the actual count graph runs here, not quadrature or lane search.
    # An optional leading LINE keeps translated records owned on the whole road.
    var road = _seed_road()
    road.length = origin + length
    road.info.geometries.clear()
    if origin > 0.0:
        road.info.geometries.append(
            RoadInfoGeometry(
                0.0, RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, origin)
            )
        )
    road.info.geometries.append(
        RoadInfoGeometry(
            origin,
            with_spiral(
                RoadGeometry(SPIRAL, origin, origin, 0.0, 0.0, length),
                curvature_start,
                curvature_end,
            ),
        )
    )
    var owner = len(road.info.geometries) - 1
    ref geometry = road.info.geometries[owner].geometry
    assert_equal(info_index(road.info.geometries, low), owner)
    assert_equal(info_index(road.info.geometries, high), owner)
    assert_true(_seed_reference_domain(geometry, origin, low, high))
    var reference = _reference_work(road, low, high)
    assert_true(reference > 0)
    var middle = low + 0.5 * (high - low)
    var spans: List[Tuple[Float64, Float64]] = [
        (low, low),
        (high, high),
        (middle, middle),
        (low, middle),
        (middle, high),
    ]
    var band_low = low
    var band_high = high
    for _ in range(3):
        band_low = band_low + 0.5 * (middle - band_low)
        band_high = middle + 0.5 * (band_high - middle)
        spans.append((band_low, band_high))
    for span in spans:
        assert_true(low <= span[0] and span[0] <= span[1] and span[1] <= high)
        assert_equal(info_index(road.info.geometries, span[0]), owner)
        assert_equal(info_index(road.info.geometries, span[1]), owner)
        assert_true(_seed_reference_domain(geometry, origin, span[0], span[1]))
        var actual = _reference_work(road, span[0], span[1])
        assert_true(actual > 0)
        assert_true(actual <= reference)
    return reference


def test_optional_seed_count_admission_is_hereditary_on_real_records() raises:
    # Explicit one-piece and adjacent-two-piece root controls.
    assert_equal(
        _assert_reference_count_descendants(0.0, 16.0, 0.0, 0.0, 0.25, 0.3), 10
    )
    assert_equal(
        _assert_reference_count_descendants(0.0, 16.0, 0.0, 0.0, 0.5, 1.5), 25
    )
    var curvatures: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (0.125, 0.125),
        (0.0, 0.5),
        (0.125, 0.375),
        (-0.125, -0.375),
        (0.125, -0.375),
        (-0.125, 0.375),
    ]
    for curve in curvatures:
        _ = _assert_reference_count_descendants(
            0.0, 16.0, curve[0], curve[1], 2.0, 2.125
        )
        _ = _assert_reference_count_descendants(
            0.0, 16.0, curve[0], curve[1], 2.0, 2.7
        )
    _ = _assert_reference_count_descendants(0.1, 16.0, 0.125, 0.375, 2.1, 2.225)
    _ = _assert_reference_count_descendants(1.0, 16.0, 0.125, 0.375, 2.0, 2.125)
    var parent_distance = _stored_difference(
        _Jet.variable(2.0, 2.125), _Jet.constant(1.0)
    )
    var child_distance = _stored_difference(
        _Jet.variable(2.0, 2.0), _Jet.constant(1.0)
    )
    assert_true(parent_distance.error > 0.0)
    assert_equal(child_distance.error, 0.0)
    var minimum = bitcast[DType.float64](UInt64(623) << UInt64(52))
    var maximum = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    _ = _assert_reference_count_descendants(
        0.0, 16.0 * minimum, maximum, maximum, minimum, _next_up(minimum)
    )
    _ = _assert_reference_count_descendants(
        minimum,
        16.0 * minimum,
        maximum,
        maximum,
        2.0 * minimum,
        _next_up(2.0 * minimum),
    )
    _ = _assert_reference_count_descendants(
        0.0, 16.0, 0.0, 16.0 * minimum, 1.0, 1.125
    )
    _ = _assert_reference_count_descendants(
        0.0, 1.0, 0.0, maximum, minimum, _next_up(minimum)
    )
    _ = _assert_reference_count_descendants(
        0.0, 1.0, 0.0, -maximum, minimum, _next_up(minimum)
    )
    _ = _assert_reference_count_descendants(
        0.0, 16.0, -1.0, 15.0, 1.0, _next_up(1.0)
    )
    # The actual final sum may retain a subnormal allowance at cancellation.
    # It is consumed only by ordinary interval expansion, not a tight product.
    var distance = _stored_difference(
        _Jet.variable(1.0, 1.0), _Jet.constant(0.0)
    )
    var rate = (Float64(15.0) - Float64(-1.0)) / Float64(16.0)
    var curvature = _Jet.constant(-1.0) + _Jet.constant(rate) * distance
    assert_true(curvature.value.is_point(0.0))
    assert_equal(curvature.error, bitcast[DType.float64](UInt64(4)))
    assert_equal(curvature.rounded_value().low, -curvature.error)
    assert_equal(curvature.rounded_value().high, curvature.error)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
