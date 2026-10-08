# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Hostile-state refusal before optional seeding work or floating arithmetic."""

from extensions.carla.map import _try_winner_seed, _seed_reference_domain
from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
from extensions.carla.lane_refinement import _LaneCertificate
from extensions.carla.road import Road
from extensions.carla.road_info import LaneId
from tests.test_carla_winner_seed_recovery import _query, _certificate
from std.testing import assert_equal, assert_raises


def _winner_seed_fp_fixture(road: Road) raises -> Tuple[Int, _LaneCertificate]:
    var lane = road.sections[0].lane_index(LaneId(-1))
    return (lane, _certificate(road, lane))


def _assert_winner_seed_refuses_hostile_state(
    road: Road, lane: Int, original: _LaneCertificate
) raises:
    var certificate = original.copy()
    var work = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="Canonical lane arithmetic"):
        _ = _try_winner_seed(
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
    with assert_raises(contains="Canonical lane arithmetic"):
        _ = _seed_reference_domain(
            road.info.geometries[0].geometry,
            road.info.geometries[0].s,
            5.62500000000001,
            6.000000000000009,
        )
    assert_equal(work.nodes, 0)
    assert_equal(work.terms, 0)
    assert_equal(work.steps, 0)
    assert_equal(certificate.nodes, original.nodes)
    assert_equal(certificate.terms, original.terms)
    assert_equal(certificate.s, original.s)
