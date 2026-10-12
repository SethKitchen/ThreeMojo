# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Per-segment curve deviation in the certified lane query (#685, item 1).

Each index segment stores its own certified full-curve distance to its
chord. The map's global deviation is the maximum of these values. The query
keeps the global early stop and skips a candidate whose own lower bound
exceeds the incumbent's upper radius.

The controls run each query twice on one map: with the stored values, and
with the global deviation on every segment. The second run takes the
earlier path: the per-segment test is then the global test, which has
already failed. The answers and certificates must be the same. The work
must not grow.
"""

from extensions.carla.lane_refinement import _LaneCertificate
from extensions.carla.map import Map, Waypoint
from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
from extensions.carla.opendrive import load_opendrive, load_opendrive_file
from extensions.carla.road_info import LANE_DRIVING, LaneId, RoadId, SectionId
from math.vector3 import Vector3
from std.math import isfinite
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

comptime TOWN = "assets/carla/town.xodr"
# One query pair for every STRIDE-th town segment keeps each test short.
comptime STRIDE = 9


def _set_global(mut map: Map) -> List[Float64]:
    # The earlier single deviation on every segment. Returns the stored values.
    var saved = List[Float64]()
    for i in range(len(map._segments)):
        saved.append(map._segments[i].deviation)
        map._segments[i].deviation = map._curve_deviation
    return saved^


def _restore(mut map: Map, saved: List[Float64]):
    for i in range(len(map._segments)):
        map._segments[i].deviation = saved[i]


def _bits(value: Float64) -> UInt64:
    return SIMD[DType.float64, 1](value).to_bits[DType.uint64]()


def _same_answer(
    left: Optional[Tuple[Waypoint, _LaneCertificate]],
    right: Optional[Tuple[Waypoint, _LaneCertificate]],
) raises:
    assert_equal(Bool(left), Bool(right))
    if not left:
        return
    ref a = left.value()
    ref b = right.value()
    assert_true(a[0].road_id == b[0].road_id)
    assert_true(a[0].section_id == b[0].section_id)
    assert_true(a[0].lane_id == b[0].lane_id)
    assert_equal(_bits(a[0].s), _bits(b[0].s))
    assert_equal(_bits(a[1].s), _bits(b[1].s))
    assert_equal(_bits(a[1].upper), _bits(b[1].upper))
    assert_equal(_bits(a[1].lower), _bits(b[1].lower))
    for k in range(3):
        assert_equal(_bits(a[1].point[k]), _bits(b[1].point[k]))


@fieldwise_init
struct _Totals(Copyable, Movable):
    var candidates: Int
    var nodes: Int
    var terms: Int
    var pops: Int
    var skipped: Int


@fieldwise_init
struct _Result(Copyable, Movable):
    var answer: Optional[Tuple[Waypoint, _LaneCertificate]]
    var failed: Bool
    var candidates: Int
    var nodes: Int
    var terms: Int
    var pops: Int


def _query(map: Map, query: Vector3) -> _Result:
    var work = _MapQueryWork(MapQueryBudget())
    var answer: Optional[Tuple[Waypoint, _LaneCertificate]] = None
    var failed = False
    try:
        answer = map._closest_lane_certificate_with_work(
            query, LANE_DRIVING, work
        )
    except:
        failed = True
    return _Result(
        answer^,
        failed,
        work.candidates,
        work.nodes,
        work.terms,
        work.index_pops,
    )


def _compare(
    mut map: Map, queries: List[Vector3]
) raises -> Tuple[_Totals, _Totals]:
    # Same answers, or the same refusal, under one default budget each.
    var fast = _Totals(0, 0, 0, 0, 0)
    var slow = _Totals(0, 0, 0, 0, 0)
    var results = List[_Result]()
    for query in queries:
        results.append(_query(map, query))
    var saved = _set_global(map)
    for i in range(len(queries)):
        var before = _query(map, queries[i])
        ref after = results[i]
        assert_equal(after.failed, before.failed)
        if not after.failed:
            _same_answer(after.answer, before.answer)
        # The skip never costs work, and it never changes the index walk.
        assert_true(after.candidates <= before.candidates)
        assert_equal(after.pops, before.pops)
        fast.candidates += after.candidates
        fast.nodes += after.nodes
        fast.terms += after.terms
        fast.pops += after.pops
        slow.candidates += before.candidates
        slow.nodes += before.nodes
        slow.terms += before.terms
        slow.pops += before.pops
        if after.candidates < before.candidates:
            fast.skipped += 1
    _restore(map, saved)
    return (fast^, slow^)


def _town_queries(map: Map, first: Int) -> List[Vector3]:
    # A segment midpoint, and that point moved off the lane and up.
    var points = List[Vector3]()
    var i = first
    while i < len(map._segments):
        ref segment = map._segments[i]
        var middle = (segment.start + segment.end) * 0.5
        points.append(middle)
        points.append(middle + Vector3(0.7, 0, 0.3))
        i += STRIDE
    return points^


def test_segment_deviation_is_certified_and_at_most_global() raises:
    var map = load_opendrive_file(TOWN)
    var largest = Float64(0)
    var below = 0
    for segment in map._segments:
        assert_true(isfinite(segment.deviation))
        assert_true(segment.deviation >= 0.0)
        assert_true(segment.deviation <= map._curve_deviation)
        largest = max(largest, segment.deviation)
        if segment.deviation < map._curve_deviation:
            below += 1
    # The global value is exactly the largest segment value.
    assert_equal(_bits(largest), _bits(map._curve_deviation))
    # One strongly curved segment sets the global value; most are smaller.
    assert_true(below * 2 > len(map._segments))


def test_global_values_restore_the_earlier_query_path() raises:
    # With the global value on every segment, the new test never skips a
    # candidate that the earlier code kept: it equals the failed stop test.
    var map = load_opendrive_file(TOWN)
    var saved = _set_global(map)
    for segment in map._segments:
        assert_equal(_bits(segment.deviation), _bits(map._curve_deviation))
    _restore(map, saved)
    for i in range(len(map._segments)):
        assert_equal(_bits(map._segments[i].deviation), _bits(saved[i]))


def test_town_answers_unchanged_and_work_drops() raises:
    var map = load_opendrive_file(TOWN)
    var queries = _town_queries(map, 0)
    var totals = _compare(map, queries)
    ref fast = totals[0]
    ref slow = totals[1]
    # The skip saves candidate certifications on the town.
    assert_true(fast.skipped > 0)
    assert_true(fast.candidates < slow.candidates)
    assert_true(fast.nodes <= slow.nodes)
    assert_true(fast.terms <= slow.terms)
    assert_equal(fast.pops, slow.pops)


def test_town_second_subset() raises:
    var map = load_opendrive_file(TOWN)
    var queries = _town_queries(map, 4)
    var totals = _compare(map, queries)
    assert_true(totals[0].candidates <= totals[1].candidates)
    assert_equal(totals[0].pops, totals[1].pops)


def _offset_road(offset_b: String, offset_c: String) raises -> Map:
    # The #302 straight reference line with a sloped or curved lane offset.
    return load_opendrive(
        '<OpenDRIVE><road id="1" length="100" junction="-1">'
        '<planView><geometry s="0" x="0" y="0" hdg="0" length="100">'
        '<line/></geometry></planView><lanes><laneOffset s="0" a="0" b="'
        + offset_b
        + '" c="'
        + offset_c
        + '" d="0"/><laneSection s="0"><left><lane id="1" type="driving">'
        + '<width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>'
        + '<center><lane id="0" type="none"/></center><right>'
        + '<lane id="-1" type="driving">'
        + '<width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>'
        + '<lane id="-2" type="driving">'
        + '<width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>'
        + "</right></laneSection></lanes></road></OpenDRIVE>"
    )


def _probe_queries(map: Map) raises -> List[Vector3]:
    var points = List[Vector3]()
    for lane in [1, -1, -2]:
        for k in range(1, 20):
            var target = Waypoint._from_si(
                RoadId(1), SectionId(0), LaneId(lane), Float64(k) * 5.0
            )
            var at = map.compute_transform(target).location
            points.append(at)
            points.append(at + Vector3(0.2, -0.4, 0.1))
    return points^


def test_offset_lane_probes_keep_their_answers() raises:
    # The #302 offset probes: sloped and curved offsets on a straight line.
    for pair in [("0.2", "0"), ("0", "0.004"), ("0.05", "-0.001")]:
        var map = _offset_road(pair[0], pair[1])
        var queries = _probe_queries(map)
        var totals = _compare(map, queries)
        assert_true(totals[0].candidates <= totals[1].candidates)


def test_nonfinite_segment_deviation_disables_only_its_skip() raises:
    # An unknown deviation gives a zero lower bound: the candidate stays.
    var map = load_opendrive_file(TOWN)
    var queries = _town_queries(map, 7)
    var saved = _set_global(map)
    var expected = List[_Result]()
    for query in queries:
        expected.append(_query(map, query))
    for i in range(len(map._segments)):
        map._segments[i].deviation = Float64.MAX * 2
    assert_false(isfinite(map._segments[0].deviation))
    for i in range(len(queries)):
        var actual = _query(map, queries[i])
        assert_equal(actual.failed, expected[i].failed)
        if not actual.failed:
            _same_answer(actual.answer, expected[i].answer)
        assert_equal(actual.candidates, expected[i].candidates)
    _restore(map, saved)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
