# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure bounded search work and peak requested allocation bytes.

Linux/ELF with pinned Mojo 1.1.0 for allocation measurements. Build navigation_allocations.c
as a shared library, load it with LD_PRELOAD, and pass its path here.
Graph construction is outside each measurement. Assertions check work bounds.
The allocation hook excludes allocator metadata and other threads.
"""

from extensions.carla.agents_route import GlobalRoutePlanner, RouteNodeId
from extensions.carla.navigation_mesh import NavPolygonId, NavQueryFilter
from extensions.carla.navigation_search import (
    NavigationSearchBudget,
    NavigationSearchReport,
    SEARCH_EXHAUSTED,
    SEARCH_SUCCESS,
)
from math.vector3 import Vector3
from std.ffi import OwnedDLHandle
from std.sys import argv
from std.testing import assert_equal, assert_true
from std.time import perf_counter_ns
from tests.test_carla_navigation_search_budget import _mesh, _portal
from tests.test_carla_route_search import _graph, _link, _node


def _report(
    kind: String,
    count: Int,
    ns: Int,
    bytes: UInt64,
    report: NavigationSearchReport,
    library: OwnedDLHandle,
) raises:
    assert_true(bytes > 0)
    assert_equal(library.call["navigation_allocations_overflow", UInt64](), 0)
    print(
        kind,
        "graph",
        count,
        "ns",
        ns,
        "peak requested bytes",
        bytes,
        "total requested bytes",
        library.call["navigation_allocations_total", UInt64](),
        "allocations",
        library.call["navigation_allocations_calls", UInt64](),
        "nodes",
        report.discovered,
        "expansions",
        report.expanded,
        "queue peak",
        report.queue_peak,
        "pops",
        report.popped,
        "edges",
        report.examined,
    )


def _bench(count: Int, library: OwnedDLHandle) raises:
    var graph = _graph()
    var mesh = _mesh(count)
    for i in range(count):
        _ = _node(graph, Float64(i))
    for i in range(1, count):
        _link(graph, 0, i, 1)
        _portal(mesh, 0, i, Float32(i))
    var budget = NavigationSearchBudget(64, 64, 64, 64, 32)
    # Warm the runtime and dynamic symbol lookups outside the measured query.
    _ = graph.search_nodes(RouteNodeId(0), RouteNodeId(count - 1), budget)
    _ = library.call["navigation_allocations_end", UInt64]()
    _ = library.call["navigation_allocations_begin", UInt64]()
    var start = perf_counter_ns()
    var route = graph.search_nodes(
        RouteNodeId(0), RouteNodeId(count - 1), budget
    )
    var ns = perf_counter_ns() - start
    var bytes = library.call["navigation_allocations_end", UInt64]()
    assert_equal(route.report.status, SEARCH_EXHAUSTED)
    assert_equal(route.report.discovered, 33)
    assert_equal(route.report.examined, 32)
    assert_equal(route.report.queue_peak, 32)
    _report("route-wide", count, ns, bytes, route.report, library)
    _ = library.call["navigation_allocations_begin", UInt64]()
    start = perf_counter_ns()
    var nav = mesh.find_path_result(
        NavPolygonId(0),
        NavPolygonId(count - 1),
        Vector3(0, 0, 0),
        Vector3(Float32(count), 0, 0),
        NavQueryFilter(),
        256,
        budget,
    )
    ns = perf_counter_ns() - start
    bytes = library.call["navigation_allocations_end", UInt64]()
    assert_equal(nav.report.status, SEARCH_EXHAUSTED)
    assert_equal(nav.report.discovered, 33)
    assert_equal(nav.report.examined, 32)
    assert_equal(nav.report.queue_peak, 32)
    _report("mesh-wide", count, ns, bytes, nav.report, library)
    _ = library.call["navigation_allocations_begin", UInt64]()
    start = perf_counter_ns()
    var same = mesh.find_path_result(
        NavPolygonId(count - 1),
        NavPolygonId(count - 1),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        NavQueryFilter(),
        256,
        NavigationSearchBudget(1, 0, 1, 1, 0),
    )
    ns = perf_counter_ns() - start
    bytes = library.call["navigation_allocations_end", UInt64]()
    assert_equal(same.report.status, SEARCH_SUCCESS)
    assert_equal(same.report.discovered, 1)
    assert_equal(same.report.expanded, 0)
    assert_equal(same.report.examined, 0)
    _report("mesh-same", count, ns, bytes, same.report, library)
    # Keep graph destruction outside the timed and allocation scopes.
    _ = graph^
    _ = mesh^


def main() raises:
    var args = argv()
    if len(args) != 2:
        raise Error(
            "Pass the path of the preloaded navigation allocation library"
        )
    var library = OwnedDLHandle(String(args[1]))
    assert_equal(library.call["navigation_allocations_selftest", UInt64](), 1)
    for count in [1000, 10000, 100000]:
        _bench(count, library)
