# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Pre-admission and sufficient-budget controls for spatial map work."""

from extensions.carla.geometry import ARC, LINE, RoadGeometry, with_arc
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.map_builder import (
    MapBuilder,
    _junction_box_with_work,
    _check_signals_on_roads_with_work,
)
from extensions.carla.map_search import (
    MapBuildBudget,
    MapQueryBudget,
    _MapBuildWork,
    _MapQueryWork,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    LANE_SHOULDER,
    RoadId,
    RoadInfoLaneWidth,
    JuncId,
    SignalId,
)
from tests.test_carla_junction_bounds import _road as _junction_road, _connect
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_cross_candidate_certificates import _road, _sampled_road
from tests.test_carla_lane_resumption import _three_point_certificate
from extensions.carla.curve_interval import _next_up, _Interval
from extensions.carla.curve_bounds import _lane_jet
from extensions.carla.junction_bounds import _centered_elevation_enclosure


def _map(
    count: Int = 1, budget: MapBuildBudget = MapBuildBudget()
) raises -> Map:
    var roads = List[Road]()
    for i in range(count):
        roads.append(_road(id=i + 1))
    return Map(
        roads^, List[Junction](), List[Signal](), List[Controller](), budget
    )


def test_empty_map_accepts_all_zero_limits() raises:
    var map = _map(0, MapBuildBudget(0, 0, 0, 0))
    var budget = MapQueryBudget(0, 0, 0, 0, 0)
    assert_equal(map.segment_count(), 0)
    assert_false(
        Bool(
            map.certified_closest_waypoint_on_road(
                Vector3(0, 0, 0), budget=budget
            )
        )
    )
    assert_false(Bool(map.certified_waypoint(Vector3(0, 0, 0), budget=budget)))


def test_zero_and_one_segment_boundaries() raises:
    with assert_raises(contains="global segment budget"):
        _ = _map(1, MapBuildBudget(0))
    var one = _map(1, MapBuildBudget(1))
    assert_equal(one.segment_count(), 1)
    with assert_raises(contains="global segment budget"):
        _ = _map(2, MapBuildBudget(1))


def test_construction_steps_are_cumulative_and_exact_at_boundary() raises:
    var reference = _map()
    var steps = reference._construction_work.steps
    assert_true(steps > 1)
    var exact = _map(1, MapBuildBudget(1, max_steps=steps))
    assert_equal(exact._construction_work.steps, steps)
    with assert_raises(contains="step budget"):
        _ = _map(1, MapBuildBudget(1, max_steps=steps - 1))
    with assert_raises(contains="step budget"):
        _ = _map(1, MapBuildBudget(1, max_steps=0))


def test_source_records_are_admitted_before_builder_mutation() raises:
    var builder = MapBuilder()
    builder.roads.append(_road())
    var before = builder.roads[0].id
    with assert_raises(contains="source record budget"):
        _ = builder.build(MapBuildBudget(1, max_records=0))
    assert_equal(len(builder.roads), 1)
    assert_equal(builder.roads[0].id, before)
    var reference = _map()
    var records = reference._construction_work.records
    var exact = _map(1, MapBuildBudget(1, max_records=records))
    assert_equal(exact._construction_work.records, records)
    with assert_raises(contains="source record budget"):
        _ = _map(1, MapBuildBudget(1, max_records=records - 1))


def test_construction_terms_guard_scalar_work_and_proof_headroom() raises:
    with assert_raises(contains="global term budget"):
        _ = _map(1, MapBuildBudget(1, max_terms=0))
    # The proof keeps its original per-segment2M allowance; less headroom
    # refuses explicitly rather than replacing its result with a loose box.
    with assert_raises(contains="global term budget"):
        _ = _map(1, MapBuildBudget(1, max_terms=1999999))
    var enough = _map(1, MapBuildBudget(1, max_terms=2000100))
    assert_equal(enough.segment_count(), 1)
    assert_true(enough._construction_work.terms < 100)


def test_invalid_or_mutated_policies_are_rejected_on_entry() raises:
    with assert_raises(contains="nonnegative"):
        _ = MapBuildBudget(-1)
    with assert_raises(contains="nonnegative"):
        _ = MapQueryBudget(-1)
    var build = MapBuildBudget()
    build.max_terms = -1
    with assert_raises(contains="nonnegative"):
        _ = _map(0, build)
    var map = _map(0)
    var query = MapQueryBudget()
    query.max_queue_entries = -1
    with assert_raises(contains="nonnegative"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(0, 0, 0), budget=query
        )


def test_counter_guards_do_not_overflow_and_latch_exhaustion() raises:
    comptime top = 9223372036854775807
    var build = _MapBuildWork(MapBuildBudget(top, top, top, top))
    build.step(top)
    with assert_raises(contains="step budget"):
        build.step()
    assert_equal(build.steps, top)
    with assert_raises(contains="already exhausted"):
        build.term(0)
    var query = _MapQueryWork(MapQueryBudget(top, top, top, top, top, top))
    query.charge(top, top)
    with assert_raises(contains="node budget"):
        query.charge(1, 0)
    assert_equal(query.nodes, top)
    assert_equal(query.terms, top)
    with assert_raises(contains="already exhausted"):
        query.candidate()


def test_mutated_consumed_work_is_rejected_before_arithmetic() raises:
    var build = _MapBuildWork(MapBuildBudget())
    build.steps = -1
    with assert_raises(contains="invalid consumed work"):
        build.step()
    var query = _MapQueryWork(MapQueryBudget())
    query.terms = query.policy.max_terms + 1
    with assert_raises(contains="invalid consumed work"):
        _ = query.term_cap()
    query.terms = 0
    with assert_raises(contains="invalid consumed node work"):
        _ = query.node_cap(-1)
    with assert_raises(contains="invalid consumed term work"):
        _ = query.term_cap(2000001)


def test_zero_candidate_budget_is_exhaustion_not_no_lane() raises:
    var map = _map()
    with assert_raises(contains="candidate budget"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(2, 0, 0), budget=MapQueryBudget(0)
        )
    assert_false(
        Bool(
            map.certified_closest_waypoint_on_road(
                Vector3(2, 0, 0), LANE_SHOULDER, MapQueryBudget(0)
            )
        )
    )


def test_query_exact_resources_and_selected_pose_share_one_ledger() raises:
    var map = _map()
    var location = Vector3(2, 0, 0)
    var work = _MapQueryWork(MapQueryBudget())
    var reference = (
        map._closest_lane_certificate_with_work(location, LANE_DRIVING, work)
        .value()
        .copy()
    )
    assert_equal(work.candidates, 1)
    assert_equal(work.nodes, reference[1].nodes + 1)
    assert_equal(work.terms, reference[1].terms + 2)
    var exact = MapQueryBudget(
        work.candidates,
        work.nodes,
        work.terms,
        work.index_pops,
        work.peak_queue_entries,
    )
    var result = map.certified_closest_waypoint_on_road(
        location, budget=exact
    ).value()
    assert_equal(
        bitcast[DType.uint64](result.s), bitcast[DType.uint64](reference[0].s)
    )
    assert_equal(result.road_id, reference[0].road_id)
    exact.max_nodes -= 1
    with assert_raises(contains="node budget"):
        _ = map.certified_closest_waypoint_on_road(location, budget=exact)
    exact.max_nodes += 1
    exact.max_terms -= 1
    with assert_raises(contains="term budget"):
        _ = map.certified_closest_waypoint_on_road(location, budget=exact)


def test_zero_global_refinement_limits_cannot_return_partial_winner() raises:
    var map = _map()
    with assert_raises(contains="interval work limit"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(2, 0, 0), budget=MapQueryBudget(1, max_nodes=0)
        )
    with assert_raises(contains="quadrature work limit"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(2, 0, 0), budget=MapQueryBudget(1, max_terms=0)
        )


def test_index_pops_and_queue_are_guarded_before_work() raises:
    var map = _map()
    with assert_raises(contains="index pop budget"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(2, 0, 0), budget=MapQueryBudget(1, max_index_pops=0)
        )
    with assert_raises(contains="index queue budget"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(2, 0, 0), budget=MapQueryBudget(1, max_queue_entries=0)
        )
    var many = _map(40)
    with assert_raises(contains="index queue budget"):
        _ = many.certified_closest_waypoint_on_road(
            Vector3(2, 0, 0), budget=MapQueryBudget(40, max_queue_entries=1)
        )


def test_large_equal_candidate_set_is_cumulative_and_deterministic() raises:
    var map = _map(40)
    var location = Vector3(2, 0, 0)
    var work = _MapQueryWork(MapQueryBudget())
    var reference = (
        map._closest_lane_certificate_with_work(location, LANE_DRIVING, work)
        .value()
        .copy()
    )
    assert_equal(work.candidates, 40)
    assert_equal(reference[0].road_id, RoadId(1))
    var policy = MapQueryBudget(39)
    with assert_raises(contains="candidate budget"):
        _ = map.certified_closest_waypoint_on_road(location, budget=policy)
    policy.max_candidates = 40
    policy.max_nodes = work.nodes - 1
    with assert_raises():
        _ = map.certified_closest_waypoint_on_road(location, budget=policy)
    policy.max_nodes = work.nodes
    policy.max_terms = work.terms
    var sufficient = map.certified_closest_waypoint_on_road(
        location, budget=policy
    ).value()
    assert_equal(sufficient.road_id, reference[0].road_id)
    assert_equal(
        bitcast[DType.uint64](sufficient.s),
        bitcast[DType.uint64](reference[0].s),
    )


def test_strict_query_uses_same_limits_and_keeps_boundary_outside() raises:
    var map = _map()
    var work = _MapQueryWork(MapQueryBudget())
    _ = map._closest_lane_certificate_with_work(
        Vector3(2, 0, 0), LANE_DRIVING, work
    )
    var exact = MapQueryBudget(
        work.candidates,
        work.nodes,
        work.terms,
        work.index_pops,
        work.peak_queue_entries,
    )
    assert_true(Bool(map.certified_waypoint(Vector3(2, 0, 0), budget=exact)))
    assert_false(Bool(map.certified_waypoint(Vector3(2, 1, 0))))
    exact.max_terms -= 1
    with assert_raises(contains="term budget"):
        _ = map.certified_waypoint(Vector3(2, 0, 0), budget=exact)


def test_many_short_width_records_are_bounded_before_boundary_allocation() raises:
    var road = _road()
    for i in range(1, 80):
        road.sections[0].lanes[0].info.widths.append(
            RoadInfoLaneWidth(Float64(i) * 0.05, CubicPolynomial.constant(2.0))
        )
    var roads = List[Road]()
    roads.append(road.copy())
    with assert_raises(contains="source record budget"):
        _ = Map(
            roads^,
            List[Junction](),
            List[Signal](),
            List[Controller](),
            MapBuildBudget(100, max_records=20),
        )
    roads = List[Road]()
    roads.append(road^)
    with assert_raises(contains="step budget"):
        _ = Map(
            roads^,
            List[Junction](),
            List[Signal](),
            List[Controller](),
            MapBuildBudget(100, max_steps=100),
        )


def test_curved_width_and_high_turn_exhaust_before_unbounded_subdivision() raises:
    var road = _road()
    road.sections[0].lanes[0].info.widths[0].polynomial = CubicPolynomial(
        2, 0, 1, 0, 0
    )
    var roads = List[Road]()
    roads.append(road^)
    with assert_raises(contains="step budget"):
        _ = Map(
            roads^,
            List[Junction](),
            List[Signal](),
            List[Controller](),
            MapBuildBudget(1000, max_steps=30),
        )
    var turning = _road()
    turning.info.geometries[0].geometry = with_arc(
        RoadGeometry(ARC, 0, 0, 0, 0, 4), 100.0
    )
    roads = List[Road]()
    roads.append(turning^)
    with assert_raises(contains="step budget"):
        _ = Map(
            roads^,
            List[Junction](),
            List[Signal](),
            List[Controller](),
            MapBuildBudget(1000, max_steps=30),
        )


def test_invalid_mutated_geometry_domain_fails_before_any_sampling() raises:
    var road = _road()
    road.info.geometries[0].geometry.length = inf[DType.float64]()
    var roads = List[Road]()
    roads.append(road^)
    with assert_raises(contains="invalid finite domain"):
        _ = Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def _junction_builder() raises -> MapBuilder:
    var builder = MapBuilder()
    var r = _junction_road(builder, 1, 4.0, -1)
    builder.add_road_geometry_line(r, 0, 0, 0, 0, 4)
    _connect(builder, [1])
    return builder^


def test_whole_builder_shares_preflight_index_and_junction_work() raises:
    var builder = _junction_builder()
    var reference = builder.build()
    var steps = reference._construction_work.steps
    var exact_builder = _junction_builder()
    var exact = exact_builder.build(MapBuildBudget(10, max_steps=steps))
    assert_equal(exact._construction_work.steps, steps)
    assert_true(
        exact.junctions[0].bounding_box.min
        == reference.junctions[0].bounding_box.min
    )
    var refused = _junction_builder()
    with assert_raises(contains="step budget"):
        _ = refused.build(MapBuildBudget(10, max_steps=steps - 1))


def test_junction_enumeration_and_conflict_traversal_charge_before_allocation() raises:
    var builder = _junction_builder()
    var map = builder.build()
    var work = _MapBuildWork(MapBuildBudget(10, max_steps=0))
    with assert_raises(contains="step budget"):
        _ = _junction_box_with_work(map, JuncId(7), work)
    assert_equal(work.steps, 0)
    work = _MapBuildWork(MapBuildBudget(10, max_steps=0))
    with assert_raises(contains="step budget"):
        _ = map._compute_junction_conflicts_with_work(JuncId(7), work)
    assert_equal(work.steps, 0)


def test_builder_sign_queries_share_global_combined_step_and_term_budget() raises:
    var map = _map()
    var location = Vector3(2, 0, 0)
    var generous = _MapBuildWork(MapBuildBudget())
    var first = map._closest_lane_with_build_work(
        location, LANE_DRIVING, generous
    ).value()
    assert_equal(first.road_id, RoadId(1))
    var steps = generous.steps
    var terms = generous.terms
    var work = _MapBuildWork(
        MapBuildBudget(10, max_steps=steps, max_terms=terms)
    )
    _ = map._closest_lane_with_build_work(location, LANE_DRIVING, work)
    assert_equal(work.steps, steps)
    assert_equal(work.terms, terms)
    with assert_raises():
        _ = map._closest_lane_with_build_work(location, LANE_DRIVING, work)
    work = _MapBuildWork(MapBuildBudget(10, max_steps=steps - 1))
    with assert_raises():
        _ = map._closest_lane_with_build_work(location, LANE_DRIVING, work)


def test_sign_relocation_has_no_independent_budget_reset() raises:
    var map = _map()
    map.signals.append(
        Signal(
            RoadId(1),
            SignalId("budget"),
            2,
            0,
            "stop",
            "no",
            "+",
            0,
            "",
            "206",
            "",
            0,
            "",
            0,
            0,
            "",
            0,
            0,
            0,
        )
    )
    map.signals[0].transform.location = Vector3(2, 0, 0)
    # The CARLA query admits the sign; its lane pose then needs terms.
    var work = _MapBuildWork(MapBuildBudget(10, max_terms=0))
    with assert_raises(contains="global term budget"):
        _check_signals_on_roads_with_work(map, work)
    assert_true(map.signals[0].transform.location == Vector3(2, 0, 0))


def test_conservative_sort_reservation_avoids_multiplication_overflow() raises:
    comptime top = 9223372036854775807
    var work = _MapBuildWork(MapBuildBudget(top, top, top, top))
    with assert_raises(contains="step budget"):
        work.step_product(top, top)
    assert_equal(work.steps, 0)
    work = _MapBuildWork(MapBuildBudget(top, top, top, top))
    with assert_raises(contains="step budget"):
        work.sort_work(top)
    assert_equal(work.steps, top)


def test_nonexact_strict_classification_uses_the_query_remainder() raises:
    var roads = List[Road]()
    roads.append(_sampled_road(1.0))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var location = Vector3(0, -2, 1)
    var work = _MapQueryWork(MapQueryBudget())
    var result = (
        map._closest_lane_certificate_with_work(location, LANE_DRIVING, work)
        .value()
        .copy()
    )
    assert_false(result[1].exact_witness)
    var exhausted = MapQueryBudget(work.candidates, max_nodes=work.nodes)
    with assert_raises(contains="classification exhausted"):
        _ = map.certified_waypoint(location, budget=exhausted)
    assert_true(Bool(map.certified_waypoint(location)))


def test_resumption_uses_global_remainder_without_resetting_candidate_caps() raises:
    var roads = List[Road]()
    roads.append(_sampled_road(1.0))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var high = _next_up(_next_up(0.5))
    map._segments[0].first.s = 0.5
    map._segments[0].second.s = high
    var certificate = _three_point_certificate(map.roads[0])
    var work = _MapQueryWork(MapQueryBudget(1, max_nodes=certificate.nodes))
    work.charge(certificate.nodes, certificate.terms)
    with assert_raises(contains="interval work limit"):
        map._resume_on_segment_certificate(
            0, Vector3(0, 0, 0), certificate, 0.0, 8.0, work
        )
    assert_equal(certificate.nodes, 7)
    assert_equal(work.nodes, 7)
    work = _MapQueryWork(MapQueryBudget())
    work.charge(certificate.nodes, certificate.terms)
    map._resume_on_segment_certificate(
        0, Vector3(0, 0, 0), certificate, 0.0, 8.0, work
    )
    assert_true(certificate.exact_witness)
    assert_equal(work.nodes, certificate.nodes)
    assert_equal(work.terms, certificate.terms)


def test_centered_junction_elevation_keeps_global_coefficients_and_roundoff() raises:
    var road = _road()
    road.info.elevations[0].polynomial = CubicPolynomial(0, 0, 0, 1, 100000)
    var point = _lane_jet(road, 0, 0, 100000.0, 100001.0)
    var original = point[2].rounded_value()
    var work = _MapBuildWork(MapBuildBudget())
    var bounded = _centered_elevation_enclosure(
        road, 100000.0, 100001.0, original, point[2].error, work
    )
    assert_true(bounded.width() < original.width())
    assert_equal(work.terms, 128)
    for i in range(65):
        var delta = Float64(i) / 64.0
        var station = 100000.0 + delta
        assert_true(
            bounded.contains(
                road.info.elevations[0].polynomial.evaluate(station)
            )
        )
        # All stored coefficients and these dyadic parameters are exact.
        assert_true(bounded.contains(delta * delta * delta))
    var enlarged = _centered_elevation_enclosure(
        road, 100000.0, 100001.0, original, point[2].error + 32.0, work
    )
    assert_true(enlarged.contains(-32.0))
    assert_true(enlarged.contains(33.0))


def test_centered_enclosure_proof_work_is_admitted_before_arithmetic() raises:
    var road = _road()
    var work = _MapBuildWork(MapBuildBudget(10, max_terms=127))
    with assert_raises(contains="term budget"):
        _ = _centered_elevation_enclosure(
            road, 0.0, 1.0, _Interval(-1, 1), 0.0, work
        )
    assert_equal(work.terms, 0)


def test_centered_enclosure_rejects_invalid_roundoff_without_narrowing() raises:
    var road = _road()
    var work = _MapBuildWork(MapBuildBudget())
    var bounded = _centered_elevation_enclosure(
        road, 0.0, 1.0, _Interval(-1, 1), -1.0, work
    )
    assert_equal(bounded.low, -1.0)
    assert_equal(bounded.high, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
