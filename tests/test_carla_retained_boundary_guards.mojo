# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Validated boundary fixtures for sample dispatch and junction work.

The sample fixture checks the raw helper's refusal, not a reachable absent
Optional in the wrapper. The junction fixture checks the real work ledger.
"""

from extensions.carla.curve_bounds import _sample_index
from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.curve_sample_dispatch import (
    _sample_dispatch_cut,
    _try_sample_dispatch_cuts,
)
from extensions.carla.geometry import LINE, RoadGeometry, _Sample
from extensions.carla.junction_bounds import _lane_section_box_with_work
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import _preflight_road_records
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import LaneId, RoadInfoLaneWidth, SectionId
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._sample_dispatch_controls import _dispatch_road
from tests._spiral_domain_controls import _road


def test_validated_length_sample_refuses_raw_cut_without_wrapper_unwrap() raises:
    var road = _dispatch_road()
    # Sorted ordinary storage has an internal sample at length and one past
    # length. Run the actual map preflight, rather than restating its rules.
    road.info.geometries[0].geometry.samples.append(
        _Sample(4.0, 0.0, 4.0, 1.0, 0.0)
    )
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)
    ref geometry = road.info.geometries[0].geometry
    assert_equal(geometry.length, 3.0)
    assert_equal(geometry.samples[3].s, geometry.length)
    assert_equal(_sample_index(geometry, geometry.length), 2)
    for local in [3.0, 4.0]:
        assert_false(Bool(_sample_dispatch_cut(0.0, geometry.length, local)))
    for high in [3.0, _next_up(3.0), 4.0]:
        var nodes = 0
        var terms = 0
        var cuts = _try_sample_dispatch_cuts(
            road, 2.5, high, nodes, terms, 8, 32
        )
        assert_false(Bool(cuts))
        # d is clamped to length. No selected threshold reaches sample[3].
        assert_equal(nodes, 0)
        assert_equal(terms, 0)
    var nodes = 0
    var terms = 0
    var cuts = _try_sample_dispatch_cuts(road, 1.9, 3.0, nodes, terms, 5, 16)
    assert_true(Bool(cuts))
    assert_equal(cuts.value()[0], _next_up(2.0))
    assert_equal(cuts.value()[2], 1)
    assert_equal(nodes, 1)
    assert_equal(terms, 8)


def _adjacent_section_road() raises -> Road:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, _next_up(1.0)))
    var section = road.add_section(SectionId(1), 1.0)
    _ = road.sections[section].add_lane(LaneId(-1))
    road.sections[section].lanes[0].info.widths.append(
        RoadInfoLaneWidth(1.0, CubicPolynomial.constant(3.5))
    )
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)
    return road^


def test_adjacent_section_has_singleton_proposal_and_no_open_interior() raises:
    var road = _adjacent_section_road()
    var low = Float64(1.0)
    var high = _next_up(low)
    # The proposal guard sees high > low BEFORE decrement. Its span is the
    # valid singleton [low, low]. Only the later open interior is reversed.
    assert_true(high > low)
    assert_equal(_next_down(high), low)
    assert_true(_next_up(low) > _next_down(high))
    var work = _MapBuildWork(MapBuildBudget())
    var box = _lane_section_box_with_work(road, 1, 0, work)
    for station in [low, high]:
        var point = road._lane_center(1, 0, station)
        assert_true(
            box.contains_point(
                Vector3(Float32(point[0]), Float32(point[1]), Float32(point[2]))
            )
        )
    # Two section scans; seven reserved boundary entries and their sort;
    # one proposal with two poses; two canonical endpoints; no open cell.
    assert_equal(work.steps, 56)
    assert_equal(work.terms, 6)
    assert_equal(work.records, 0)
    assert_equal(work.segments, 0)
    assert_false(work.exhausted)


def test_adjacent_section_fits_exact_budget_without_empty_cell_work() raises:
    var road = _adjacent_section_road()
    var work = _MapBuildWork(MapBuildBudget(0, 56, 6, 0))
    var box = _lane_section_box_with_work(road, 1, 0, work)
    assert_false(box.is_empty())
    assert_equal(work.steps, 56)
    assert_equal(work.terms, 6)
    assert_false(work.exhausted)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
