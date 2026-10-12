# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The certified lane query on the town, and what #685's items could save.

Issue 685 lists performance items for the opt-in certified query. This
bench measures the query on `assets/carla/town.xodr`:

- Item 1, per-segment curve deviation: the query as built, and the same
  queries with the global deviation on every segment. The second run takes
  the earlier code path, so the two give the gain of item 1. The bench
  counts the queries whose answers differ; that count must be zero. A run
  with the global deviation set to zero bounds any further gain. Its
  answers are not trusted; only its time and work are reported.
- Item 6, endpoint centers evaluated again at each node: the cost of one
  center evaluation, times two evaluations for each refined node.

The queries are each segment's midpoint and that point moved 0.7 m to the
side and 0.3 m up, in the order the map stores its segments. Each run
times every query three times after one warm-up pass.

Run it with `mojo run -I . bench/carla_certified_query_bench.mojo`.
"""

from extensions.carla.lane_refinement import _LaneCertificate, _checked_center
from extensions.carla.map import Map, Waypoint
from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import LANE_DRIVING
from math.vector3 import Vector3
from std.time import perf_counter_ns


def _queries(map: Map) -> List[Vector3]:
    var points = List[Vector3]()
    for segment in map._segments:
        var middle = (segment.start + segment.end) * 0.5
        points.append(middle)
        points.append(middle + Vector3(0.7, 0, 0.3))
    return points^


def _answers(
    map: Map, queries: List[Vector3]
) -> List[Optional[Tuple[Waypoint, Float64, Float64]]]:
    # The waypoint and the certified bounds, or None for a refusal.
    var result = List[Optional[Tuple[Waypoint, Float64, Float64]]]()
    for query in queries:
        var work = _MapQueryWork(MapQueryBudget())
        try:
            var found = map._closest_lane_certificate_with_work(
                query, LANE_DRIVING, work
            )
            if found:
                ref value = found.value()
                result.append((value[0], value[1].lower, value[1].upper))
            else:
                result.append(None)
        except:
            result.append(None)
    return result^


def _differences(
    a: List[Optional[Tuple[Waypoint, Float64, Float64]]],
    b: List[Optional[Tuple[Waypoint, Float64, Float64]]],
) -> Int:
    var count = 0
    for i in range(len(a)):
        if Bool(a[i]) != Bool(b[i]):
            count += 1
        elif a[i]:
            ref x = a[i].value()
            ref y = b[i].value()
            if x[0] != y[0] or x[0].s != y[0].s or x[1] != y[1] or x[2] != y[2]:
                count += 1
    return count


@fieldwise_init
struct _Run(Copyable, Movable):
    var times: List[Float64]
    var nodes: Int
    var candidates: Int
    var terms: Int
    var pops: Int


def _run(map: Map, queries: List[Vector3]) raises -> _Run:
    var times = List[Float64]()
    var nodes = 0
    var candidates = 0
    var terms = 0
    var pops = 0
    for round in range(4):
        for query in queries:
            var work = _MapQueryWork(MapQueryBudget())
            var start = perf_counter_ns()
            _ = map._closest_lane_certificate_with_work(
                query, LANE_DRIVING, work
            )
            var elapsed = Float64(perf_counter_ns() - start) / 1000
            # The first round warms up.
            if round > 0:
                times.append(elapsed)
            if round == 1:
                nodes += work.nodes
                candidates += work.candidates
                terms += work.terms
                pops += work.index_pops
    sort(times)
    return _Run(times^, nodes, candidates, terms, pops)


def _report(name: String, run: _Run, count: Int):
    var total = Float64(0)
    for t in run.times:
        total += t
    print(
        name,
        ",",
        total / Float64(len(run.times)),
        ",",
        run.times[len(run.times) // 2],
        ",",
        run.times[len(run.times) * 95 // 100],
        ",",
        Float64(run.nodes) / Float64(count),
        ",",
        Float64(run.candidates) / Float64(count),
        ",",
        Float64(run.terms) / Float64(count),
        ",",
        Float64(run.pops) / Float64(count),
        sep="",
    )


def main() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var queries = _queries(map)
    print("segments", len(map._segments), "queries", len(queries))
    print("curve_deviation_m", map._curve_deviation)
    print(
        "run,mean_us,p50_us,p95_us,nodes_per_query,candidates_per_query,"
        "terms_per_query,index_pops_per_query"
    )
    var base = _run(map, queries)
    _report("certified", base, len(queries))
    var answers = _answers(map, queries)
    # Item 1: the global deviation on every segment is the earlier path.
    var stored = List[Float64]()
    for i in range(len(map._segments)):
        stored.append(map._segments[i].deviation)
        map._segments[i].deviation = map._curve_deviation
    var before = _run(map, queries)
    _report("global-deviation", before, len(queries))
    var before_answers = _answers(map, queries)
    for i in range(len(map._segments)):
        map._segments[i].deviation = stored[i]
    print("answer_differences", _differences(answers, before_answers))
    # The gain of any tighter deviation is at most this.
    var deviation = map._curve_deviation
    map._curve_deviation = 0
    var tight = _run(map, queries)
    map._curve_deviation = deviation
    _report("zero-deviation-bound", tight, len(queries))
    # Item 6: the cost of one center evaluation.
    var first = map._segments[0].first
    ref road = map.road(first.road_id)
    # The center takes the lane's index in its section, not its id.
    var section = first.section_id.value
    var lane = 0
    for k in range(len(road.sections[section].lanes)):
        if road.sections[section].lanes[k].id == first.lane_id:
            lane = k
    var calls = 100000
    var terms = 0
    var start = perf_counter_ns()
    for k in range(calls):
        var s = first.s + Float64(k % 100) * 1e-4
        var point = _checked_center(
            road,
            section,
            lane,
            s,
            terms,
            1 << 60,
        )
        if point[0] != point[0]:
            print("nan")
    var per_center = Float64(perf_counter_ns() - start) / 1000 / Float64(calls)
    print("center_eval_us", per_center)
    print(
        "item6_saving_bound_us_per_query",
        2 * per_center * Float64(base.nodes) / Float64(len(queries)),
    )
