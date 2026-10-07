# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Native-query parity and accuracy for the sampled full-domain box cover."""

from extensions.carla.lane_box_cover import _lane_cover_can_improve
from extensions.carla.lane_refinement import (
    _checked_center,
    _lane_box_can_improve,
    _certificate_within_gap,
    _scaled_accuracy,
)
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.curve_interval import _next_up
from extensions.carla.lane_distance import _refinement_square
from extensions.carla.road_info import LANE_DRIVING
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
    var found = map.certified_closest_waypoint_on_road(query).value()
    assert_equal(found.road_id.value, 5)
    assert_equal(found.lane_id.value, 1)
    assert_equal(found.section_id, winner.section_id)
    # An approximate distance certificate does not promise one historical
    # station word. Check its unchanged final-gap rule and its objective
    # against the same fixed feasible witness used by the cover controls.
    var selected = map._closest_lane_certificate(query, LANE_DRIVING)
    ref certified = selected.value()
    ref certificate = certified[1]
    assert_equal(
        bitcast[DType.uint64](certified[0].s), bitcast[DType.uint64](found.s)
    )
    var target: Array[Float64, 3] = [
        Float64(query.x),
        Float64(query.y),
        Float64(query.z),
    ]
    var score = _refinement_square[3](
        certificate.point, target, certificate.scale
    )
    ref segment = map._segments[569]
    var allowance = _scaled_accuracy(
        map.roads[at[0]],
        at[1],
        at[2],
        min(segment.first.s, segment.second.s),
        max(segment.first.s, segment.second.s),
        found.s,
        score.low,
        certificate.scale,
    )
    assert_true(
        _certificate_within_gap(
            certificate.lower,
            certificate.scale,
            certificate.scale,
            certificate.upper,
            allowance,
        )
    )
    var feasible_score = _refinement_square[3](
        witness, target, certificate.scale
    )
    assert_true(_next_up(score.high - feasible_score.low) <= allowance)

    # Remove only the optional covers from this construction snapshot.
    # Full-center boxes, scalar geometry and all query limits stay intact.
    # Exact station/pose parity checks the cover's admission-only promise
    # without replacing the old golden word with a new solver trace.
    var pose = map.compute_transform(found)
    for index in range(len(map._segments)):
        map._segments[index].cover_index = -1
    var without_cover = map.certified_closest_waypoint_on_road(query).value()
    assert_equal(without_cover.road_id, found.road_id)
    assert_equal(without_cover.section_id, found.section_id)
    assert_equal(without_cover.lane_id, found.lane_id)
    assert_equal(
        bitcast[DType.uint64](without_cover.s), bitcast[DType.uint64](found.s)
    )
    var plain_pose = map.compute_transform(without_cover)
    assert_equal(
        bitcast[DType.uint32](plain_pose.location.x),
        bitcast[DType.uint32](pose.location.x),
    )
    assert_equal(
        bitcast[DType.uint32](plain_pose.location.y),
        bitcast[DType.uint32](pose.location.y),
    )
    assert_equal(
        bitcast[DType.uint32](plain_pose.location.z),
        bitcast[DType.uint32](pose.location.z),
    )
    assert_equal(
        bitcast[DType.uint32](plain_pose.rotation.yaw),
        bitcast[DType.uint32](pose.rotation.yaw),
    )
    assert_equal(
        bitcast[DType.uint32](plain_pose.rotation.pitch),
        bitcast[DType.uint32](pose.rotation.pitch),
    )
    assert_equal(
        bitcast[DType.uint32](plain_pose.rotation.roll),
        bitcast[DType.uint32](pose.rotation.roll),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
