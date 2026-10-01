# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare complete searches on sparse and wide-frontier route graphs.

The test suite supplies the independent linear-selection oracle. Graph
construction is outside the timed region; no map or geometry lookup runs
inside either search. Node positions are close enough that the geometric
heuristic stays below the positive edge costs.
"""

from tests.test_carla_agents import _graph, _linear_route, _link
from std.time import perf_counter_ns


def _bench(count: Int, wide: Bool) raises:
    var graph = _graph()
    for i in range(count):
        _ = graph._node_of(
            String(i), SIMD[DType.float64, 4](Float64(i) * 0.000001, 0, 0, 0)
        )
    if wide:
        for i in range(1, count - 1):
            _link(graph, 0, i, 1)
            _link(graph, i, count - 1, count)
    else:
        for i in range(count - 1):
            _link(graph, i, i + 1, 1)
    var start = perf_counter_ns()
    var want = _linear_route(graph, 0, count - 1)
    var linear_ns = perf_counter_ns() - start
    start = perf_counter_ns()
    var got = graph._search(0, count - 1)
    var heap_ns = perf_counter_ns() - start
    if len(got) != len(want):
        raise Error("Route lengths differ")
    for i in range(len(want)):
        if got[i].value != want[i].value:
            raise Error("Routes differ")
    print(
        count, "nodes; wide", wide, "linear ns", linear_ns, "heap ns", heap_ns
    )


def main() raises:
    for count in [100, 1000, 10000]:
        _bench(count, False)
        _bench(count, True)
