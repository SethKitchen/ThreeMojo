# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent interruption, ownership, tie and cumulative-ledger controls."""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.curve_interval import _next_up
from extensions.carla.geometry import _Sample
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _LaneExclusionGoal,
    _ClosedInterval,
    _ClosedIntervals,
    _beats_external_witness,
    _pause_lane_search,
    _refine_lane_certificate,
    _continue_lane_certificate,
    _checked_center,
    _exact_lane_certificate,
    _rebase_lower,
)
from extensions.carla.map import (
    Map,
    Junction,
    Signal,
    Controller,
    _query_node_step_cost,
)
from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from tests.test_carla_cross_candidate_certificates import _sampled_road
from tests._spiral_domain_controls import _bits
from tests._published_lane_refinement import (
    _refine_lane_certificate as _published_refine,
    _continue_lane_certificate as _published_continue,
    _LaneExclusionGoal as _PublishedGoal,
)


def _query(location: Vector3) -> Array[Float64, 3]:
    return [Float64(location.x), Float64(location.y), Float64(location.z)]


def _goal(
    point: Array[Float64, 3], location: Vector3, earlier_incumbent: Bool
) raises -> _LaneExclusionGoal:
    var exact = _exact_lane_certificate(0.0, point, _query(location), 0, 0)
    return _LaneExclusionGoal(exact.upper, exact.scale, earlier_incumbent)


def _station(low: Float64, offset: Int) -> Float64:
    return bitcast[DType.float64](bitcast[DType.uint64](low) + UInt64(offset))


def _seed(
    road: Road, location: Vector3, low: Float64, high: Float64, station: Float64
) raises -> _LaneCertificate:
    # The original staged producer owns and prepays this initial scalar.
    return _refine_lane_certificate(
        road, 0, 0, low, high, location, station, 0.0, seed_only=True
    )


def _assert_cover(
    certificate: _LaneCertificate, low: Float64, high: Float64
) raises:
    # Sorting endpoints establishes whole-interval coverage. A sampled grid
    # alone would not detect a missing gap between adjacent retained cells.
    var used = List[Bool](length=len(certificate.cells), fill=False)
    var frontier = low
    for _ in range(len(certificate.cells)):
        var next = -1
        for i in range(len(certificate.cells)):
            if not used[i]:
                if (
                    next < 0
                    or certificate.cells[i].low < certificate.cells[next].low
                ):
                    next = i
        assert_true(next >= 0)
        var cell = certificate.cells[next]
        assert_true(cell.low >= low and cell.high <= high)
        assert_true(cell.low <= frontier)
        frontier = max(frontier, cell.high)
        used[next] = True
    assert_true(frontier >= high)


def _double_minimum_road() raises -> Road:
    var road = _sampled_road(1.0)
    ref geometry = road.info.geometries[0].geometry
    geometry.samples.clear()
    # Initial s=0 is far away; s=.5 beats the external witness, but the
    # endpoint at s=1 and an earlier interior root are closer still.
    geometry.samples.append(_Sample(-2, 1, 0, 1, 0))
    geometry.samples.append(_Sample(1, 1, 0.5, 1, 0))
    geometry.samples.append(_Sample(0, 1, 1, 1, 0))
    return road^


def test_external_order_uses_exact_distance_and_original_index_ties() raises:
    var query: Array[Float64, 3] = [0, 0, 0]
    var location = Vector3(0, 0, 0)
    for scale in [Float64(1e-200), Float64(1), Float64(1e200)]:
        var point: Array[Float64, 3] = [scale, 0, 0]
        var other: Array[Float64, 3] = [-scale, 0, 0]
        assert_true(
            _beats_external_witness(
                point, query, _goal(other, location, False), other.copy()
            )
        )
        assert_false(
            _beats_external_witness(
                point, query, _goal(other, location, True), other.copy()
            )
        )
        var farther: Array[Float64, 3] = [2 * scale, 0, 0]
        assert_true(
            _beats_external_witness(
                point, query, _goal(farther, location, True), farther.copy()
            )
        )
        assert_false(
            _beats_external_witness(
                farther, query, _goal(point, location, False), point.copy()
            )
        )
        assert_false(_beats_external_witness(point, query, None, other.copy()))
        assert_false(
            _beats_external_witness(
                point, query, _goal(other, location, False), None
            )
        )


def test_improving_midpoint_yields_without_hiding_a_later_minimum() raises:
    var road = _double_minimum_road()
    var location = Vector3(0, 0, 0)
    var external: Array[Float64, 3] = [1.5, -1, 0]
    var certificate = _seed(road, location, 0.0, 1.0, 0.0)
    # A valid positive original-domain lower bound in its original scale.
    certificate.lower = 0.125
    certificate.cells[0].lower = 0.125
    var entry_scale = certificate.scale
    var entry_nodes = certificate.nodes
    var entry_terms = certificate.terms
    _continue_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        location,
        certificate,
        None,
        certificate.scale,
        goal=_goal(external, location, True),
        external_witness=external.copy(),
    )
    _bits(certificate.s, 0.5)
    assert_false(certificate.exact_witness)
    assert_equal(certificate.nodes, entry_nodes + 2)
    assert_equal(certificate.terms, entry_terms + 1)
    assert_equal(len(certificate.cells), 1)
    _assert_cover(certificate, 0.0, 1.0)
    _bits(certificate.cells[0].lower, 0.125)
    _bits(certificate.cells[0].scale, entry_scale)
    assert_equal(certificate.cells[0].depth, 0)
    var paused_point = certificate.point.copy()
    _continue_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        location,
        certificate,
        None,
        certificate.scale,
    )
    assert_true(
        _wide_point_order(certificate.point, paused_point, _query(location)) < 0
    )
    # The unsearched endpoint is evaluated before any lower-bound closure.
    _bits(certificate.s, 1.0)
    _bits(certificate.point[0], 0.0)
    _bits(certificate.point[1], -1.0)


def test_pause_packs_current_pending_closed_and_terminal_without_gaps() raises:
    var closed = _ClosedIntervals()
    closed.add(_ClosedInterval(0.0, 0.2, 3, 0.1, 2.0))
    var terminal: List[_ClosedInterval] = [
        _ClosedInterval(0.5, 0.5, 7, 0.25, 2.0)
    ]
    var pending: List[Tuple[Float64, Float64, Int]] = [
        (0.2, 0.4, 4),
        (0.8, 1.0, 5),
    ]
    var point: Array[Float64, 3] = [1, -1, 0]
    var query: Array[Float64, 3] = [0, 0, 0]
    var result = _pause_lane_search(
        0.5,
        point,
        query,
        closed^,
        terminal,
        pending,
        (0.4, 0.8, 6),
        0.125,
        2.0,
        17,
        31,
    )
    assert_false(result.exact_witness)
    assert_equal(result.nodes, 17)
    assert_equal(result.terms, 31)
    assert_equal(len(result.cells), 5)
    _assert_cover(result, 0.0, 1.0)
    var found = 0
    for cell in result.cells:
        if cell.low == 0.2 or cell.low == 0.8 or cell.low == 0.4:
            _bits(cell.lower, 0.125)
            _bits(cell.scale, 2.0)
            if cell.low == 0.2:
                assert_equal(cell.depth, 4)
            elif cell.low == 0.8:
                assert_equal(cell.depth, 5)
            else:
                assert_equal(cell.depth, 6)
            found += 1
        elif cell.low == 0.5:
            assert_equal(cell.depth, 7)
            _bits(cell.high, cell.low)
    assert_equal(found, 3)
    assert_true(result.lower <= _rebase_lower(0.125, 2.0, result.scale))


def test_interrupted_finite_leaf_keeps_whole_cell_depth_and_tie_direction() raises:
    var road = _sampled_road(1.0)
    var low = Float64(0.5)
    var high = _station(low, 6)
    var location = Vector3(1.7763568394002505e-15, -2, 0)
    var ignored_terms = 0
    var external = _checked_center(
        road, 0, 0, _station(low, 3), ignored_terms, 100
    )
    for earlier_incumbent in [False, True]:
        var certificate = _seed(road, location, low, high, low)
        certificate.cells[0].depth = 7
        var entry_nodes = certificate.nodes
        var entry_terms = certificate.terms
        var entry_scale = certificate.scale
        _continue_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            location,
            certificate,
            0.0,
            certificate.scale,
            goal=_goal(external, location, earlier_incumbent),
            external_witness=external.copy(),
        )
        var offset = 4 if earlier_incumbent else 3
        _bits(certificate.s, _station(low, offset))
        assert_false(certificate.exact_witness)
        assert_equal(certificate.nodes, entry_nodes + 3)
        assert_equal(certificate.terms, entry_terms + offset + 1)
        assert_equal(len(certificate.cells), 1)
        _assert_cover(certificate, low, high)
        assert_equal(certificate.cells[0].depth, 7)
        _bits(certificate.cells[0].lower, 0.0)
        _bits(certificate.cells[0].scale, entry_scale)
        var spent_nodes = certificate.nodes
        var spent_terms = certificate.terms
        _continue_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            location,
            certificate,
            0.0,
            certificate.scale,
        )
        assert_true(certificate.exact_witness)
        _bits(certificate.s, high)
        assert_equal(certificate.nodes, spent_nodes + 4)
        assert_equal(certificate.terms, spent_terms + 7)
        for cell in certificate.cells:
            _bits(cell.low, cell.high)
            assert_equal(cell.depth, 10)


def test_zero_distance_yield_stays_nonexact_until_ordinary_resume() raises:
    var road = _sampled_road(1.0)
    var location = Vector3(0, -2, 0)
    var external: Array[Float64, 3] = [0.5, -2, 0]
    var certificate = _seed(road, location, 0.0, 1.0, 0.0)
    _continue_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        location,
        certificate,
        None,
        certificate.scale,
        goal=_goal(external, location, True),
        external_witness=external.copy(),
    )
    _bits(certificate.s, 0.5)
    assert_false(certificate.exact_witness)
    _assert_cover(certificate, 0.0, 1.0)
    _continue_lane_certificate(
        road, 0, 0, 0.0, 1.0, location, certificate, None, certificate.scale
    )
    assert_true(certificate.exact_witness)


def test_no_external_path_matches_untouched_published_solver() raises:
    for scale in [Float64(1e-100), Float64(1.0), Float64(1e100)]:
        var road = _sampled_road(scale)
        for location in [
            Vector3(0, 0, 0),
            Vector3(0.25, 1, 0),
            Vector3(4, -2, 0),
        ]:
            var old = _published_refine(
                road, 0, 0, 0.0, 1.0, location, 0.1, 0.0
            )
            var actual = _refine_lane_certificate(
                road, 0, 0, 0.0, 1.0, location, 0.1, 0.0
            )
            _bits(actual.s, old.s)
            _bits(actual.scale, old.scale)
            _bits(actual.lower, old.lower)
            _bits(actual.upper, old.upper)
            assert_equal(actual.nodes, old.nodes)
            assert_equal(actual.terms, old.terms)
            assert_equal(actual.exact_witness, old.exact_witness)
            assert_equal(len(actual.cells), len(old.cells))
            for axis in range(3):
                _bits(actual.point[axis], old.point[axis])
            for i in range(len(actual.cells)):
                _bits(actual.cells[i].low, old.cells[i].low)
                _bits(actual.cells[i].high, old.cells[i].high)
                _bits(actual.cells[i].lower, old.cells[i].lower)
                _bits(actual.cells[i].scale, old.cells[i].scale)
                assert_equal(actual.cells[i].depth, old.cells[i].depth)
    var road = _sampled_road(1.0)
    var location = Vector3(0, 0, 0)
    var old = _published_refine(
        road, 0, 0, 0.0, 1.0, location, 0.1, 0.0, seed_only=True
    )
    var actual = _seed(road, location, 0.0, 1.0, 0.1)
    var external: Array[Float64, 3] = [0.25, -2, 0]
    var goal = _goal(external, location, True)
    _published_continue(
        road,
        0,
        0,
        0.0,
        1.0,
        location,
        old,
        None,
        old.scale,
        goal=_PublishedGoal(goal.upper, goal.scale, goal.allow_equal),
    )
    _continue_lane_certificate(
        road, 0, 0, 0.0, 1.0, location, actual, None, actual.scale, goal=goal
    )
    _bits(actual.s, old.s)
    _bits(actual.lower, old.lower)
    _bits(actual.upper, old.upper)
    assert_equal(actual.nodes, old.nodes)
    assert_equal(actual.terms, old.terms)
    assert_equal(len(actual.cells), len(old.cells))


def test_interruption_never_resets_local_caps_or_failed_work() raises:
    var road = _sampled_road(1.0)
    var low = Float64(0.5)
    var high = _station(low, 6)
    var location = Vector3(1.7763568394002505e-15, -2, 0)
    var terms = 0
    var external = _checked_center(road, 0, 0, _station(low, 3), terms, 100)
    var goal = _goal(external, location, False)
    var certificate = _seed(road, location, low, high, low)
    var entry_nodes = certificate.nodes
    var entry_terms = certificate.terms
    with assert_raises(contains="interval work limit"):
        _continue_lane_certificate(
            road,
            0,
            0,
            low,
            high,
            location,
            certificate,
            0.0,
            certificate.scale,
            max_nodes=entry_nodes + 2,
            goal=goal,
            external_witness=external.copy(),
        )
    assert_equal(certificate.nodes, entry_nodes + 2)
    assert_equal(certificate.terms, entry_terms + 3)
    _assert_cover(certificate, low, high)
    var retained_nodes = certificate.nodes
    var retained_terms = certificate.terms
    _continue_lane_certificate(
        road,
        0,
        0,
        low,
        high,
        location,
        certificate,
        0.0,
        certificate.scale,
        goal=goal,
        external_witness=external.copy(),
    )
    assert_false(certificate.exact_witness)
    assert_equal(certificate.nodes, retained_nodes + 3)
    assert_equal(certificate.terms, retained_terms + 4)
    certificate.nodes = 16384
    with assert_raises(contains="interval work limit"):
        _continue_lane_certificate(
            road, 0, 0, low, high, location, certificate, 0.0, certificate.scale
        )
    assert_equal(certificate.nodes, 16384)
    certificate.nodes = 0
    certificate.terms = 2000000
    with assert_raises(contains="quadrature work limit"):
        _continue_lane_certificate(
            road, 0, 0, low, high, location, certificate, 0.0, certificate.scale
        )
    assert_equal(certificate.terms, 2000000)


def _two_call_work(map: Map, policy: MapQueryBudget) raises -> _MapQueryWork:
    var location = Vector3(0, 0, 0)
    var low = min(map._segments[0].first.s, map._segments[0].second.s)
    var high = max(map._segments[0].first.s, map._segments[0].second.s)
    # Map splits at the sampled source boundary s=.5. Its first real
    # owner cell still contains the first improving midpoint and later
    # unsearched minimum s=1/3.
    assert_true(low < 0.25 and high > 0.4)
    var certificate = _seed(map.roads[0], location, low, high, low)
    var external: Array[Float64, 3] = [1.5, -1, 0]
    var work = _MapQueryWork(policy)
    work.candidate()
    work.charge(certificate.nodes, certificate.terms, _query_node_step_cost(1))
    map._resume_on_segment_certificate(
        0,
        location,
        certificate,
        None,
        certificate.scale,
        work,
        _goal(external, location, True),
        external.copy(),
    )
    assert_false(certificate.exact_witness)
    assert_equal(certificate.nodes, 3)
    # Candidate 1 + staged seed 136 + locate/profile 4 + old-cell scan 4
    # + external invocation 6 + packing 6 + two goal nodes at 182 = 521.
    assert_equal(work.steps, 521)
    var yielded_point = certificate.point.copy()
    map._resume_on_segment_certificate(
        0, location, certificate, None, certificate.scale, work
    )
    assert_true(
        _wide_point_order(certificate.point, yielded_point, _query(location))
        < 0
    )
    assert_equal(work.nodes, certificate.nodes)
    assert_equal(work.terms, certificate.terms)
    # Ordinary continuation retains eight entry units; its node includes
    # the sixteen separately reviewed dispatch eligibility/routing units.
    assert_equal(work.steps, 529 + 136 * (certificate.nodes - 3))
    return work


def test_exact_multicall_step_boundary_includes_pause_packing_and_resume() raises:
    var roads = List[Road]()
    roads.append(_double_minimum_road())
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    assert_equal(_query_node_step_cost(1, True, True), 182)
    assert_equal(_query_node_step_cost(1, True, False), 142)
    assert_equal(_query_node_step_cost(1, False, False), 136)
    var reference = _two_call_work(map, MapQueryBudget())
    var exact = _two_call_work(
        map, MapQueryBudget(1, max_steps=reference.steps)
    )
    assert_equal(exact.steps, reference.steps)
    assert_equal(exact.nodes, reference.nodes)
    assert_equal(exact.terms, reference.terms)
    with assert_raises():
        _ = _two_call_work(
            map, MapQueryBudget(1, max_steps=reference.steps - 1)
        )


def test_goal_yield_step_reservations_precede_each_scalar() raises:
    var roads = List[Road]()
    roads.append(_double_minimum_road())
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var location = Vector3(0, 0, 0)
    var low = min(map._segments[0].first.s, map._segments[0].second.s)
    var high = max(map._segments[0].first.s, map._segments[0].second.s)
    var external: Array[Float64, 3] = [1.5, -1, 0]
    # 156 stops at the old-cell packing reservation; 338 cannot prepay even
    # one 182-unit node; 520 prepays the recheck but not the scalar root.
    for limit in [156, 338, 520, 521]:
        var certificate = _seed(map.roads[0], location, low, high, low)
        var work = _MapQueryWork(MapQueryBudget(1, max_steps=limit))
        work.candidate()
        work.charge(1, 1, _query_node_step_cost(1))
        if limit == 521:
            map._resume_on_segment_certificate(
                0,
                location,
                certificate,
                None,
                certificate.scale,
                work,
                _goal(external, location, True),
                external.copy(),
            )
            assert_equal(work.steps, 521)
            assert_equal(certificate.nodes, 3)
            assert_equal(certificate.terms, 2)
            assert_false(certificate.exact_witness)
        else:
            with assert_raises():
                map._resume_on_segment_certificate(
                    0,
                    location,
                    certificate,
                    None,
                    certificate.scale,
                    work,
                    _goal(external, location, True),
                    external.copy(),
                )
            assert_equal(certificate.terms, 1)
            assert_equal(certificate.nodes, 2 if limit == 520 else 1)
            _bits(certificate.s, low)
            _assert_cover(certificate, low, high)


def test_external_validation_and_cost_overflow_precede_search() raises:
    var road = _sampled_road(1.0)
    var location = Vector3(0, 0, 0)
    var certificate = _seed(road, location, 0.0, 1.0, 0.0)
    var external: Array[Float64, 3] = [1, 0, 0]
    var nodes = certificate.nodes
    var terms = certificate.terms
    with assert_raises(contains="matching goal"):
        _continue_lane_certificate(
            road,
            0,
            0,
            0.0,
            1.0,
            location,
            certificate,
            None,
            certificate.scale,
            external_witness=external.copy(),
        )
    assert_equal(certificate.nodes, nodes)
    assert_equal(certificate.terms, terms)
    var goal = _goal(external, location, True)
    external[1] = inf[DType.float64]()
    with assert_raises():
        _continue_lane_certificate(
            road,
            0,
            0,
            0.0,
            1.0,
            location,
            certificate,
            None,
            certificate.scale,
            goal=goal,
            external_witness=external.copy(),
        )
    assert_equal(certificate.nodes, nodes)
    assert_equal(certificate.terms, terms)
    comptime largest = 9223372036854775807
    var lanes = (largest - 82) // 100
    assert_true(_query_node_step_cost(lanes, True, True) <= largest)
    with assert_raises(contains="not representable"):
        _ = _query_node_step_cost(lanes + 1, True, True)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
