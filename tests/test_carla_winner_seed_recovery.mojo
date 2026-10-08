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
from extensions.carla.geometry import SPIRAL, RoadGeometry, with_spiral
from extensions.carla.road_info import RoadInfoGeometry
from tests.test_carla_cross_candidate_certificates import _road
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _ClosedInterval,
    _checked_center,
    _continue_lane_certificate,
)
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.curve_bounds import _reference_work
from extensions.carla.curve_interval import _Interval, _next_down, _next_up
from extensions.carla.lane_distance import _refinement_square
from math.vector3 import Vector3
from std.memory import bitcast
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
