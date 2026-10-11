# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The certified lane query on the town, and what #685's items could save.

Issue 685 lists performance items for the opt-in certified query. This
bench measures the query on `assets/carla/town.xodr` and bounds the gain
of two of them without changing a pinned source:

- Item 1, one global curve deviation: the same queries with the deviation
  set to zero. A per-segment deviation can only lie between the two, so
  the difference bounds its gain. The answers of the zero-deviation run
  are not trusted; only its time and work are reported.
- Item 6, endpoint centers evaluated again at each node: the cost of one
  center evaluation, times two evaluations for each refined node.

The queries are each segment's midpoint and that point moved 0.7 m to the
side and 0.3 m up, in the order the map stores its segments. Each run
times every query three times after one warm-up pass.

Run it with `mojo run -I . bench/carla_certified_query_bench.mojo`.
"""

from extensions.carla.lane_refinement import _checked_center
from extensions.carla.map import Map
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
    # Item 1: the gain of any tighter deviation is at most this.
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
