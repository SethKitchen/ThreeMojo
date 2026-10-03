# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure default search headroom on the project's ordinary map fixtures."""

from extensions.carla.agents_route import GlobalRoutePlanner
from extensions.carla.navigation_mesh import (
    build_navigation_mesh,
    NavPolygonId,
    walker_filter,
)
from extensions.carla.navigation_search import (
    NavigationSearchReport,
    SEARCH_EXHAUSTED,
)
from extensions.carla.opendrive import load_opendrive, load_opendrive_file
from extensions.carla.map import Map
from math.vector3 import Vector3
from std.testing import assert_true
from units.si import Length, METER
from tests.test_carla_agents import TWO_LANE
from tests.test_carla_navigation_world import LONG_ROAD


def _max(mut peak: NavigationSearchReport, got: NavigationSearchReport) raises:
    assert_true(got.status != SEARCH_EXHAUSTED)
    peak.discovered = max(peak.discovered, got.discovered)
    peak.expanded = max(peak.expanded, got.expanded)
    peak.queue_peak = max(peak.queue_peak, got.queue_peak)
    peak.popped = max(peak.popped, got.popped)
    peak.examined = max(peak.examined, got.examined)


def _show(
    name: String,
    kind: String,
    count: Int,
    queries: Int,
    peak: NavigationSearchReport,
):
    print(
        name,
        kind,
        "graph",
        count,
        "queries",
        queries,
        "peak nodes",
        peak.discovered,
        "expansions",
        peak.expanded,
        "queue",
        peak.queue_peak,
        "pops",
        peak.popped,
        "edges",
        peak.examined,
    )


def _bench(name: String, map: Map) raises:
    for resolution in [2, 5]:
        var graph = GlobalRoutePlanner(map, Length(Float32(resolution), METER))
        var peak = NavigationSearchReport()
        for source in graph._nodes:
            for target in graph._nodes:
                var result = graph.search_nodes(source.id, target.id)
                _max(peak, result.report)
        _show(
            name,
            String("route@", resolution),
            graph.node_count(),
            graph.node_count() * graph.node_count(),
            peak,
        )
    var mesh = build_navigation_mesh(map)
    var count = mesh.polygon_count()
    var peak = NavigationSearchReport()
    # Reproducible stratified endpoint samples, with both walker filters.
    for i in range(128):
        var a = (i * 37) % count
        var b = (i * 83 + count // 2) % count
        var start = mesh.polygons[a].center
        var end = mesh.polygons[b].center
        var result = mesh.find_path_result(
            NavPolygonId(a),
            NavPolygonId(b),
            start,
            end,
            walker_filter(i % 2 == 0),
        )
        _max(peak, result.report)
    _show(name, "mesh", count, 128, peak)


def main() raises:
    _bench("town", load_opendrive_file("assets/carla/town.xodr"))
    _bench("long-road", load_opendrive(LONG_ROAD))
    _bench("two-lane", load_opendrive(TWO_LANE))
