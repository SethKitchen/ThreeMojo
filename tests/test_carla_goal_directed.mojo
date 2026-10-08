# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whole-domain exclusion preserves local work, ties, and winner accuracy."""

from extensions.carla.geometry import _Sample
from extensions.carla.lane_refinement import (
    _LaneExclusionGoal,
    _continue_lane_certificate,
    _goal_excludes,
    _refine_lane_certificate,
    _resume_lane_certificate,
    _scaled_accuracy,
    _rebase_lower,
)
from extensions.carla.map import (
    Controller,
    Junction,
    Map,
    Signal,
    _query_node_step_cost,
)
from extensions.carla.road import Road
from extensions.carla.road_info import LANE_DRIVING, RoadId
from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
from tests.test_carla_cross_candidate_certificates import _road, _sampled_road
from math.vector3 import Vector3
from std.math import inf
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_goal_equality_uses_original_segment_index_and_outward_units() raises:
    assert_true(_goal_excludes(4.0, 1.0, _LaneExclusionGoal(4.0, 1.0, True)))
    assert_false(_goal_excludes(4.0, 1.0, _LaneExclusionGoal(4.0, 1.0, False)))
    assert_true(_goal_excludes(5.0, 1.0, _LaneExclusionGoal(4.0, 1.0, False)))
    assert_false(_goal_excludes(0.0, 1.0, _LaneExclusionGoal(1.0, 1.0, True)))
    assert_false(_goal_excludes(4.0, 1.0, None))
    assert_true(_goal_excludes(2.0, 4.0, _LaneExclusionGoal(4.0, 2.0, False)))
    # Outward rescaling must not manufacture equality at a boundary.
    assert_false(_goal_excludes(16.0, 0.5, _LaneExclusionGoal(4.0, 1.0, True)))


def test_seed_retains_the_complete_domain_and_actual_work() raises:
    var road = _sampled_road(1.0)
    var seed = _refine_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        Vector3(0, 0, 0),
        0.1,
        0.0,
        seed_only=True,
    )
    assert_false(seed.exact_witness)
    assert_equal(len(seed.cells), 1)
    assert_equal(seed.cells[0].low, 0.0)
    assert_equal(seed.cells[0].high, 1.0)
    assert_equal(seed.cells[0].lower, 0.0)
    assert_true(seed.terms > 0)
    assert_equal(seed.nodes, 1)
    var spent = seed.terms
    with assert_raises(contains="quadrature work limit"):
        _continue_lane_certificate(
            road,
            0,
            0,
            0.0,
            1.0,
            Vector3(0, 0, 0),
            seed,
            None,
            seed.scale,
            max_terms=spent,
        )
    assert_equal(seed.terms, spent)
    assert_true(seed.nodes > 0)
    # An exception retains the older whole-domain cover for safe inspection.
    assert_equal(seed.cells[0].low, 0.0)
    assert_equal(seed.cells[0].high, 1.0)


def test_goal_closed_minimum_is_not_accurate_and_reopens_for_winner() raises:
    var road = _sampled_road(1.0)
    road.info.geometries[0].geometry.samples[1] = _Sample(
        1.0, 4.0, 1.0, 1.0, 0.0
    )
    var location = Vector3(0, 0, 0)
    var result = _refine_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        location,
        0.9,
        0.0,
        seed_only=True,
    )
    var seed_terms = result.terms
    _continue_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        location,
        result,
        None,
        result.scale,
        goal=_LaneExclusionGoal(1.0, 1.0, True),
    )
    assert_false(result.exact_witness)
    assert_true(result.terms > seed_terms)
    assert_true(len(result.cells) > 0)
    var tolerance = _scaled_accuracy(
        road,
        0,
        0,
        0.0,
        1.0,
        result.s,
        result.lower,
        result.scale,
    )
    assert_true(result.upper - result.lower > tolerance)
    for cell in result.cells:
        assert_true(
            _goal_excludes(
                cell.lower, cell.scale, _LaneExclusionGoal(1.0, 1.0, True)
            )
        )
    var before_nodes = result.nodes
    var before_terms = result.terms
    _continue_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        location,
        result,
        None,
        result.scale,
    )
    assert_true(result.nodes > before_nodes)
    assert_true(result.terms > before_terms)
    tolerance = _scaled_accuracy(
        road,
        0,
        0,
        0.0,
        1.0,
        result.s,
        result.lower,
        result.scale,
    )
    assert_true(result.upper - result.lower <= tolerance)


def test_seed_and_continuation_keep_original_local_caps() raises:
    var road = _sampled_road(1.0)
    var result = _refine_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        Vector3(0, 0, 0),
        0.1,
        0.0,
        seed_only=True,
    )
    result.nodes = 16384
    with assert_raises(contains="interval work limit"):
        _continue_lane_certificate(
            road,
            0,
            0,
            0.0,
            1.0,
            Vector3(0, 0, 0),
            result,
            None,
            result.scale,
        )
    assert_equal(result.nodes, 16384)
    result.nodes = 0
    result.terms = 2000000
    with assert_raises(contains="quadrature work limit"):
        _continue_lane_certificate(
            road,
            0,
            0,
            0.0,
            1.0,
            Vector3(0, 0, 0),
            result,
            None,
            result.scale,
        )
    assert_equal(result.terms, 2000000)
    var work = _MapQueryWork(MapQueryBudget())
    work.charge(100, 300)
    assert_equal(work.node_cap(100), 16384)
    assert_equal(work.term_cap(300), 2000000)


def test_original_resume_rejects_invalid_requested_gaps() raises:
    var road = _sampled_road(1.0)
    var result = _refine_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        Vector3(0, 0, 0),
        0.1,
        0.0,
        seed_only=True,
    )
    for gap in [Float64(-1.0), inf[DType.float64]()]:
        with assert_raises(contains="finite nonnegative gap"):
            _resume_lane_certificate(
                road,
                0,
                0,
                0.0,
                1.0,
                Vector3(0, 0, 0),
                result,
                gap,
                result.scale,
            )


def test_staged_scalar_seed_reserves_global_profile_steps_before_evaluation() raises:
    var roads = List[Road]()
    roads.append(_sampled_road(1.0))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var location = Vector3(0, 0, 0)
    var work = _MapQueryWork(MapQueryBudget())
    work.candidate()
    var result = map._nearest_on_segment_certificate(
        0,
        location,
        work,
        seed_only=True,
    )
    assert_equal(result[1].nodes, 1)
    assert_equal(work.nodes, result[1].nodes)
    assert_equal(work.terms, result[1].terms)
    assert_true(work.steps >= _query_node_step_cost(1))
    var short = _MapQueryWork(MapQueryBudget(1, max_steps=work.steps - 1))
    short.candidate()
    with assert_raises(contains="interval work limit"):
        _ = map._nearest_on_segment_certificate(
            0,
            location,
            short,
            seed_only=True,
        )
    assert_equal(short.nodes, 0)
    assert_equal(short.terms, 0)


def test_zero_distance_winner_cannot_hide_an_admitted_seed_profile() raises:
    var roads = List[Road]()
    roads.append(_sampled_road(1.0))
    var sampled = _sampled_road(1.0)
    sampled.id = RoadId(2)
    roads.append(sampled^)
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    # Restrict both cached domains to the same interior subinterval. The
    # original index boxes still cover it, and the seed is exactly s=0.5.
    for i in range(len(map._segments)):
        map._segments[i].first.s = 0.25
        map._segments[i].second.s = 0.75
    var location = Vector3(0, -2, 0)
    var work = _MapQueryWork(MapQueryBudget())
    var result = (
        map._closest_lane_certificate_with_work(
            location,
            LANE_DRIVING,
            work,
        )
        .value()
        .copy()
    )
    assert_equal(work.candidates, 2)
    assert_equal(result[0].road_id, RoadId(1))
    assert_true(result[1].exact_witness)
    # The selected exact witness and selected pose are not the entire bill:
    # the excluded non-axis seed reserves its own profile node at admission.
    assert_true(work.nodes > result[1].nodes + 1)


def test_goal_continuation_reserves_extra_steps_at_the_exact_boundary() raises:
    var roads = List[Road]()
    roads.append(_sampled_road(1.0))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var location = Vector3(0, 0, 0)
    var seed_work = _MapQueryWork(MapQueryBudget())
    var seeded = map._nearest_on_segment_certificate(
        0,
        location,
        seed_work,
        seed_only=True,
    )
    var seed = seeded[1].copy()
    var result = seed.copy()
    var work = _MapQueryWork(MapQueryBudget())
    work.charge(seed.nodes, seed.terms, _query_node_step_cost(1))
    var previous_steps = work.steps
    var goal = _LaneExclusionGoal(1.0, 1.0, True)
    map._resume_on_segment_certificate(
        0,
        location,
        result,
        None,
        result.scale,
        work,
        goal,
    )
    assert_equal(_query_node_step_cost(1, True), _query_node_step_cost(1) + 6)
    assert_true(
        work.steps
        >= previous_steps
        + (result.nodes - seed.nodes) * _query_node_step_cost(1, True)
    )
    var exact = _MapQueryWork(MapQueryBudget(1, max_steps=work.steps))
    exact.charge(seed.nodes, seed.terms, _query_node_step_cost(1))
    result = seed.copy()
    map._resume_on_segment_certificate(
        0,
        location,
        result,
        None,
        result.scale,
        exact,
        goal,
    )
    assert_equal(exact.steps, work.steps)
    var short = _MapQueryWork(MapQueryBudget(1, max_steps=work.steps - 1))
    short.charge(seed.nodes, seed.terms, _query_node_step_cost(1))
    result = seed.copy()
    with assert_raises(contains="interval work limit"):
        map._resume_on_segment_certificate(
            0,
            location,
            result,
            None,
            result.scale,
            short,
            goal,
        )


def test_invalid_external_goals_are_rejected_before_continuation() raises:
    var road = _sampled_road(1.0)
    var location = Vector3(0, 0, 0)
    var seed = _refine_lane_certificate(
        road,
        0,
        0,
        0.0,
        1.0,
        location,
        0.1,
        0.0,
        seed_only=True,
    )
    for upper in [Float64(-1.0), inf[DType.float64]()]:
        with assert_raises(contains="finite nonnegative upper bound"):
            _continue_lane_certificate(
                road,
                0,
                0,
                0.0,
                1.0,
                location,
                seed,
                None,
                seed.scale,
                goal=_LaneExclusionGoal(upper, 1.0, True),
            )
    for scale in [Float64(-1.0), Float64(0.0), Float64(3.0)]:
        with assert_raises(contains="positive power-of-two scale"):
            _continue_lane_certificate(
                road,
                0,
                0,
                0.0,
                1.0,
                location,
                seed,
                None,
                seed.scale,
                goal=_LaneExclusionGoal(1.0, scale, True),
            )


def test_seed_singleton_reuses_its_prepaid_scalar_leaf() raises:
    var road = _sampled_road(1.0)
    var result = _refine_lane_certificate(
        road,
        0,
        0,
        0.5,
        0.5,
        Vector3(0, 0, 0),
        0.5,
        0.0,
        max_nodes=1,
        seed_only=True,
    )
    assert_true(result.exact_witness)
    assert_equal(result.nodes, 1)
    assert_equal(result.s, 0.5)
    with assert_raises(contains="interval work limit"):
        _ = _refine_lane_certificate(
            road,
            0,
            0,
            0.5,
            0.5,
            Vector3(0, 0, 0),
            0.5,
            0.0,
            max_nodes=0,
            seed_only=True,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
