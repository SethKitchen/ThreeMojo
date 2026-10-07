# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Sampled fixtures and hostile-state checks for exact internal dispatch cuts."""

from extensions.carla.geometry import PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import RoadInfoGeometry
from extensions.carla.curve_sample_dispatch import (
    _sample_dispatch_cut,
    _try_sample_dispatch_cuts,
)
from std.testing import assert_equal, assert_false
from tests.test_carla_cross_candidate_certificates import _road


def _dispatch_road(origin: Float64 = 0.0) raises -> Road:
    var road = _road()
    var geometry = RoadGeometry(PARAM_POLY3, origin, 0.0, 0.0, 0.0, 3.0)
    for i in range(4):
        geometry.samples.append(_Sample(Float64(i), 0.0, Float64(i), 1.0, 0.0))
    road.length = origin + 3.0
    road.info.geometries[0] = RoadInfoGeometry(origin, geometry^)
    road.info.elevations[0].polynomial = CubicPolynomial(
        0.0, 1.0, 0.0, 0.0, 0.0
    )
    return road^


def _assert_dispatch_refuses_hostile_state(road: Road) raises:
    assert_false(Bool(_sample_dispatch_cut(0.0, 3.0, 1.0)))
    var nodes = 7
    var terms = 5
    assert_false(
        Bool(
            _try_sample_dispatch_cuts(road, 0.9, 2.1, nodes, terms, 100, 10000)
        )
    )
    assert_equal(nodes, 7)
    assert_equal(terms, 5)
