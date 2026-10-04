# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact native-query regression for the sampled full-domain box cover."""

from extensions.carla.lane_box_cover import _lane_cover_can_improve
from extensions.carla.lane_refinement import (
    _checked_center,
    _lane_box_can_improve,
)
from extensions.carla.opendrive import load_opendrive_file
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_complete_cover_excludes_far_competitor_and_keeps_neighbors() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var query = Vector3(
        bitcast[DType.float32](UInt32(1111325104)),
        bitcast[DType.float32](UInt32(3270936819)),
        bitcast[DType.float32](UInt32(1074094146)),
    )
    var winner = map.segment(569)[2]
    assert_equal(winner.road_id.value, 5)
    assert_equal(winner.lane_id.value, 1)
    winner.s = bitcast[DType.float64](UInt64(4632515166679192352))
    var at = map._locate(winner)
    var terms = 0
    # Use the pinned actual native witness, independently of whether the
    # new query path decides to refine or exclude any competitor.
    var witness = _checked_center(
        map.roads[at[0]], at[1], at[2], winner.s, terms, 2000000
    )
    for index in [567, 568, 569]:
        ref segment = map._segments[index]
        assert_true(segment.cover_index >= 0)
        # The original full box is too loose to exclude all three.
        assert_true(_lane_box_can_improve(segment.bounds, query, witness))
        assert_equal(
            _lane_cover_can_improve(
                map._sampled_covers[segment.cover_index], query, witness
            ),
            index != 567,
        )
    # Admission does not create a witness or change the winning identity.
    var found = map.closest_waypoint_on_road(query).value()
    assert_equal(found.road_id.value, 5)
    assert_equal(found.lane_id.value, 1)
    assert_equal(bitcast[DType.uint64](found.s), UInt64(4632515166679192352))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
