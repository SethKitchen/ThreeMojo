# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Navigation budget boundaries, deterministic partial paths, and work bounds."""

from extensions.carla.agents_route import GlobalRoutePlanner, RouteNodeId
from extensions.carla.navigation import (
    Navigation,
    WalkerManager,
    WalkerRoutePoint,
    ignore_event,
    WALKER_IN_EVENT,
    WALKER_IDLE,
    WALKER_STOP,
)
from extensions.carla.actor import ActorId
from extensions.carla.opendrive import load_opendrive_file
from units.si import Length, METER, Duration, SECOND
from extensions.carla.navigation_mesh import (
    AREA_SIDEWALK,
    AREA_GRASS,
    NavArea,
    NavMesh,
    NavPolygon,
    NavPolygonId,
    NavPortal,
    NavQueryFilter,
)
from extensions.carla.navigation_search import (
    NavigationSearchBudget,
    NavigationSearchLimit,
    NavigationSearchReport,
    NavigationSearchStatus,
    SEARCH_SUCCESS,
    SEARCH_UNREACHABLE,
    SEARCH_EXHAUSTED,
    SEARCH_TRUNCATED,
    SEARCH_LIMIT_NONE,
    SEARCH_LIMIT_NODES,
    SEARCH_LIMIT_EXPANSIONS,
    SEARCH_LIMIT_QUEUE,
    SEARCH_LIMIT_POPS,
    SEARCH_LIMIT_EDGES,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_route_search import (
    _graph,
    _link,
    _node,
    _all_pairs,
    _cost,
)
from tests.test_carla_navigation import _rect, _linear_path, _ids, _street


def _budget(which: Int, value: Int) raises -> NavigationSearchBudget:
    var budget = NavigationSearchBudget(64, 64, 64, 64, 256)
    if which == 0:
        budget.max_nodes = value
    elif which == 1:
        budget.max_expansions = value
    elif which == 2:
        budget.max_queue_entries = value
    elif which == 3:
        budget.max_pops = value
    else:
        budget.max_edges = value
    return budget


def _mesh(count: Int) raises -> NavMesh:
    var mesh = NavMesh()
    for _ in range(count):
        mesh.polygons.append(NavPolygon(_rect(0, 0, 1, 1), AREA_SIDEWALK))
    return mesh^


def _portal(mut mesh: NavMesh, a: Int, b: Int, x: Float32):
    mesh.polygons[a].portals.append(
        NavPortal(b, Vector3(x, 0, 0), Vector3(x, 0, 0))
    )


def _path(
    mesh: NavMesh, budget: NavigationSearchBudget, maximum: Int = 256
) raises:
    var result = mesh.find_path_result(
        NavPolygonId(0),
        NavPolygonId(1),
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        NavQueryFilter(),
        maximum,
        budget,
    )
    assert_true(result.report.discovered <= budget.max_nodes)
    assert_true(result.report.expanded <= budget.max_expansions)
    assert_true(result.report.queue_peak <= budget.max_queue_entries)
    assert_true(result.report.popped <= budget.max_pops)
    assert_true(result.report.examined <= budget.max_edges)


def test_zero_limits_stop_before_corresponding_operation() raises:
    var graph = _graph()
    _ = _node(graph, 0)
    _ = _node(graph, 1)
    _link(graph, 0, 1, 1)
    var mesh = _mesh(2)
    _portal(mesh, 0, 1, 1)
    var reasons: List[NavigationSearchLimit] = [
        SEARCH_LIMIT_NODES,
        SEARCH_LIMIT_EXPANSIONS,
        SEARCH_LIMIT_QUEUE,
        SEARCH_LIMIT_POPS,
        SEARCH_LIMIT_EDGES,
    ]
    for i in range(5):
        var budget = _budget(i, 0)
        var route = graph.search_nodes(RouteNodeId(0), RouteNodeId(1), budget)
        var nav = mesh.find_path_result(
            NavPolygonId(0),
            NavPolygonId(1),
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            NavQueryFilter(),
            256,
            budget,
        )
        assert_equal(route.report.status, SEARCH_EXHAUSTED)
        assert_equal(nav.report.status, SEARCH_EXHAUSTED)
        assert_equal(route.report.limit, reasons[i])
        assert_equal(nav.report.limit, reasons[i])
        assert_equal(route.report.discovered, nav.report.discovered)
        assert_equal(route.report.popped, nav.report.popped)
        assert_equal(route.report.expanded, nav.report.expanded)
        assert_equal(route.report.examined, nav.report.examined)
        if i == 0 or i == 2:
            assert_equal(route.report.discovered, 0)
            assert_equal(len(nav.polygons), 0)
        else:
            assert_equal(route.report.discovered, 1)
            assert_equal(_ids(nav.polygons), "0 ")
        _path(mesh, budget)
        with assert_raises(contains="budget exhausted"):
            _ = graph._search(0, 1, budget)
        with assert_raises(contains="budget exhausted"):
            _ = mesh.find_path(
                NavPolygonId(0),
                NavPolygonId(1),
                Vector3(0, 0, 0),
                Vector3(1, 0, 0),
                NavQueryFilter(),
                256,
                budget,
            )


def test_one_limits_and_same_node_policy() raises:
    var graph = _graph()
    _ = _node(graph, 0)
    _ = _node(graph, 1)
    _link(graph, 0, 1, 1)
    var mesh = _mesh(2)
    _portal(mesh, 0, 1, 1)
    for i in range(5):
        var budget = _budget(i, 1)
        var route = graph.search_nodes(RouteNodeId(0), RouteNodeId(1), budget)
        var nav = mesh.find_path_result(
            NavPolygonId(0),
            NavPolygonId(1),
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            NavQueryFilter(),
            256,
            budget,
        )
        var status = SEARCH_EXHAUSTED if i == 0 or i == 3 else SEARCH_SUCCESS
        assert_equal(route.report.status, status)
        assert_equal(nav.report.status, status)
        _path(mesh, budget)
    var single = NavigationSearchBudget(1, 0, 1, 1, 0)
    var route = graph.search_nodes(RouteNodeId(0), RouteNodeId(0), single)
    var nav = mesh.find_path_result(
        NavPolygonId(0),
        NavPolygonId(0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        NavQueryFilter(),
        256,
        single,
    )
    assert_equal(route.report.status, SEARCH_SUCCESS)
    assert_equal(nav.report.status, SEARCH_SUCCESS)
    assert_equal(route.report.discovered, 1)
    assert_equal(route.report.popped, 1)
    assert_equal(route.report.expanded, 0)
    assert_equal(route.report.examined, 0)
    assert_equal(len(route.nodes), 1)
    for i in [0, 2, 3]:
        var zero = _budget(i, 0)
        var same = graph.search_nodes(RouteNodeId(0), RouteNodeId(0), zero)
        var same_nav = mesh.find_path_result(
            NavPolygonId(0),
            NavPolygonId(0),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0),
            NavQueryFilter(),
            256,
            zero,
        )
        assert_equal(same.report.status, SEARCH_EXHAUSTED)
        assert_equal(same_nav.report.status, SEARCH_EXHAUSTED)


def test_stale_queue_entries_consume_pop_and_storage_budgets() raises:
    var graph = _graph()
    for i in range(4):
        _ = _node(graph, Float64(i))
    _link(graph, 0, 1, 10)
    _link(graph, 0, 2, 1)
    _link(graph, 2, 1, 1)
    var result = graph.search_nodes(RouteNodeId(0), RouteNodeId(3))
    assert_equal(result.report.status, SEARCH_UNREACHABLE)
    assert_equal(result.report.discovered, 3)
    assert_equal(result.report.expanded, 3)
    assert_equal(result.report.examined, 3)
    assert_equal(result.report.popped, 4)
    assert_equal(result.report.stale, 1)
    assert_equal(result.report.queue_peak, 2)
    assert_equal(len(result.nodes), 0)
    var limited = graph.search_nodes(
        RouteNodeId(0), RouteNodeId(3), _budget(3, 3)
    )
    assert_equal(limited.report.status, SEARCH_EXHAUSTED)
    assert_equal(limited.report.limit, SEARCH_LIMIT_POPS)
    assert_equal(limited.report.popped, 3)
    assert_equal(limited.nodes[len(limited.nodes) - 1].value, 1)
    var small = graph.search_nodes(
        RouteNodeId(0), RouteNodeId(3), _budget(2, 1)
    )
    assert_equal(small.report.limit, SEARCH_LIMIT_QUEUE)
    assert_equal(small.report.discovered, 2)
    assert_equal(small.report.queue_peak, 1)


def test_output_truncation_does_not_hide_search_termination() raises:
    var mesh = _mesh(3)
    _portal(mesh, 0, 1, 1)
    for maximum in [0, 1, 2]:
        var result = mesh.find_path_result(
            NavPolygonId(0),
            NavPolygonId(1),
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            NavQueryFilter(),
            maximum,
        )
        assert_equal(
            result.report.status,
            SEARCH_TRUNCATED if maximum < 2 else SEARCH_SUCCESS,
        )
        assert_equal(result.report.output_truncated, maximum < 2)
        assert_equal(result.report.limit, SEARCH_LIMIT_NONE)
        assert_equal(result.report.popped, 2)
        assert_equal(len(result.polygons), maximum)
    var unreachable = mesh.find_path_result(
        NavPolygonId(0),
        NavPolygonId(2),
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        NavQueryFilter(),
        0,
    )
    assert_equal(unreachable.report.status, SEARCH_UNREACHABLE)
    assert_true(unreachable.report.output_truncated)
    var exhausted = mesh.find_path_result(
        NavPolygonId(0),
        NavPolygonId(2),
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        NavQueryFilter(),
        0,
        _budget(3, 1),
    )
    assert_equal(exhausted.report.status, SEARCH_EXHAUSTED)
    assert_true(exhausted.report.output_truncated)
    assert_equal(exhausted.report.limit, SEARCH_LIMIT_POPS)


def test_invalid_budget_status_limit_and_output_boundaries() raises:
    var graph = _graph()
    _ = _node(graph, 0)
    var mesh = _mesh(1)
    for i in range(5):
        var invalid = _budget(i, -1)
        with assert_raises(contains="must be nonnegative"):
            _ = graph.search_nodes(RouteNodeId(0), RouteNodeId(0), invalid)
        with assert_raises(contains="must be nonnegative"):
            _ = mesh.find_path_result(
                NavPolygonId(0),
                NavPolygonId(0),
                Vector3(0, 0, 0),
                Vector3(0, 0, 0),
                NavQueryFilter(),
                256,
                invalid,
            )
    with assert_raises(contains="must be nonnegative"):
        _ = NavigationSearchBudget(-1)
    with assert_raises(contains="output limit"):
        _ = mesh.find_path_result(
            NavPolygonId(0),
            NavPolygonId(0),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0),
            NavQueryFilter(),
            -1,
        )
    with assert_raises(contains="id is not valid"):
        _ = graph.search_nodes(RouteNodeId(2147483648), RouteNodeId(0))
    with assert_raises(contains="id is not valid"):
        _ = graph.search_nodes(RouteNodeId(0), RouteNodeId(-2147483649))
    with assert_raises(contains="no such node"):
        _ = graph.search_nodes(RouteNodeId(1), RouteNodeId(0))
    with assert_raises(contains="no such node"):
        _ = graph.search_nodes(RouteNodeId(0), RouteNodeId(1))
    for i in [-1, 4]:
        assert_false(NavigationSearchStatus(i).is_valid())
    for i in range(4):
        assert_true(NavigationSearchStatus(i).is_valid())
    for i in [-1, 6]:
        assert_false(NavigationSearchLimit(i).is_valid())
    for i in range(6):
        assert_true(NavigationSearchLimit(i).is_valid())
    var report = NavigationSearchReport()
    for i in [-1, 0, 6]:
        with assert_raises(contains="limit is not valid"):
            _ = report._exhaust(NavigationSearchLimit(i))
    report.status = NavigationSearchStatus(4)
    with assert_raises(contains="status is not valid"):
        report._truncate(True)


def test_large_wide_graph_work_is_independent_of_unvisited_size() raises:
    var graph = _graph()
    var mesh = _mesh(10000)
    for i in range(10000):
        _ = _node(graph, Float64(i))
    for i in range(1, 10000):
        _link(graph, 0, i, 1)
        _portal(mesh, 0, i, Float32(i))
    var budget = NavigationSearchBudget(32, 32, 32, 32, 7)
    var result = graph.search_nodes(RouteNodeId(0), RouteNodeId(9999), budget)
    var nav = mesh.find_path_result(
        NavPolygonId(0),
        NavPolygonId(9999),
        Vector3(0, 0, 0),
        Vector3(9999, 0, 0),
        NavQueryFilter(),
        256,
        budget,
    )
    assert_equal(result.report.limit, SEARCH_LIMIT_EDGES)
    assert_equal(nav.report.limit, SEARCH_LIMIT_EDGES)
    assert_equal(result.report.discovered, 8)
    assert_equal(nav.report.discovered, 8)
    assert_equal(result.report.examined, 7)
    assert_equal(nav.report.examined, 7)
    assert_equal(result.report.expanded, 1)
    assert_equal(nav.report.expanded, 1)
    assert_equal(result.report.queue_peak, 7)
    assert_equal(nav.report.queue_peak, 7)
    assert_equal(_ids(nav.polygons), "0 7 ")
    assert_equal(len(result.nodes), 1)
    # Graph-wide size does not enter a same-node query either.
    var tiny = mesh.find_path_result(
        NavPolygonId(9999),
        NavPolygonId(9999),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        NavQueryFilter(),
        256,
        NavigationSearchBudget(1, 0, 1, 1, 0),
    )
    assert_equal(tiny.report.discovered, 1)
    assert_equal(tiny.report.examined, 0)


def test_reopened_mesh_nodes_and_generous_budget_match_linear_oracle() raises:
    # A real connected 3x3 mesh, with portal positions from shared edges.
    # Portal-state costs require node 3 to reopen through node 0.
    var mesh = NavMesh()
    var areas: List[Int] = [1, 2, 3, 2, 2, 4, 4, 1, 3]
    var filter = NavQueryFilter()
    filter.set_area_cost(NavArea(1), 1)
    filter.set_area_cost(NavArea(2), 2)
    filter.set_area_cost(NavArea(3), 5)
    filter.set_area_cost(NavArea(4), 10)
    for i in range(9):
        var x = Float32(i % 3)
        var y = Float32(i // 3)
        _ = mesh.add_polygon(_rect(x, y, x + 1, y + 1), NavArea(areas[i]))
    mesh.connect()
    var start = Vector3(2.5, 0.5, 0)
    var end = Vector3(0.5, 2.5, 0)
    var result = mesh.find_path_result(
        NavPolygonId(2), NavPolygonId(6), start, end, filter
    )
    assert_equal(result.report.status, SEARCH_SUCCESS)
    assert_equal(result.report.reopened, 1)
    var want = _linear_path(mesh, 2, 6, start, end, filter, 256)
    assert_equal(_ids(result.polygons), _ids(want))
    var stopped = mesh.find_path_result(
        NavPolygonId(2),
        NavPolygonId(6),
        start,
        end,
        filter,
        256,
        NavigationSearchBudget(64, result.report.expanded - 1, 64, 64, 256),
    )
    assert_equal(stopped.report.status, SEARCH_EXHAUSTED)
    assert_equal(stopped.report.limit, SEARCH_LIMIT_EXPANSIONS)
    for a in range(9):
        for b in range(9):
            start = Vector3(Float32(a % 3) + 0.5, Float32(a // 3) + 0.5, 0)
            end = Vector3(Float32(b % 3) + 0.5, Float32(b // 3) + 0.5, 0)
            var actual = mesh.find_path_result(
                NavPolygonId(a), NavPolygonId(b), start, end, filter
            )
            want = _linear_path(mesh, a, b, start, end, filter, 256)
            assert_equal(_ids(actual.polygons), _ids(want))


def test_route_generous_limits_match_independent_all_pairs() raises:
    for seed in range(8):
        var graph = _graph()
        for i in range(12):
            _ = _node(graph, Float64(i))
        for a in range(12):
            for b in range(12):
                if seed % 3 == 0 and (a == 11 or b == 11):
                    continue
                if (a * 7 + b * 13 + seed) % 11 < 3:
                    _link(graph, a, b, (a * 3 + b + seed) % 5)
        var distances = _all_pairs(graph)
        for a in range(12):
            for b in range(12):
                var route = graph.search_nodes(RouteNodeId(a), RouteNodeId(b))
                var want = distances[a * 12 + b]
                if want < 0:
                    assert_equal(route.report.status, SEARCH_UNREACHABLE)
                    assert_equal(len(route.nodes), 0)
                else:
                    assert_equal(route.report.status, SEARCH_SUCCESS)
                    assert_equal(_cost(graph, route.nodes), want)


def test_mesh_stale_filtered_edges_and_first_discovered_partial_tie() raises:
    var mesh = _mesh(4)
    # Node 1 is first reached at x=10, then improved through node 2 at x=2.
    # The disconnected goal forces both the current and stale score to pop.
    _portal(mesh, 0, 1, 10)
    _portal(mesh, 0, 2, 1)
    _portal(mesh, 2, 1, 2)
    mesh.polygons[0].area = NavArea(2)
    var weighted = NavQueryFilter()
    weighted.set_area_cost(NavArea(2), 2)
    var result = mesh.find_path_result(
        NavPolygonId(0),
        NavPolygonId(3),
        Vector3(0, 0, 0),
        Vector3(20, 0, 0),
        weighted,
    )
    assert_equal(result.report.status, SEARCH_UNREACHABLE)
    assert_equal(result.report.stale, 1)
    assert_equal(result.report.reopened, 0)
    var tie = _mesh(4)
    # Both portal positions have the same heuristic. First discovery wins,
    # even though the lower-id node pops first on the score tie.
    _portal(tie, 0, 2, 1)
    _portal(tie, 0, 1, 1)
    var partial = tie.find_path_result(
        NavPolygonId(0),
        NavPolygonId(3),
        Vector3(0, 0, 0),
        Vector3(3, 0, 0),
        NavQueryFilter(),
    )
    assert_equal(_ids(partial.polygons), "0 2 ")
    var filter = NavQueryFilter()
    filter.exclude = tie.polygons[1].flags
    var excluded = tie.find_path_result(
        NavPolygonId(0),
        NavPolygonId(3),
        Vector3(0, 0, 0),
        Vector3(3, 0, 0),
        filter,
        256,
        _budget(4, 1),
    )
    assert_equal(excluded.report.limit, SEARCH_LIMIT_EDGES)
    assert_equal(excluded.report.examined, 1)
    assert_equal(excluded.report.discovered, 1)


def test_public_wrappers_forward_budget_and_raise_on_exhaustion() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    var start = Vector3(5.3, 1.75, 0)
    var end = Vector3(78.25, 35.3, 0)
    var budget = NavigationSearchBudget(0)
    var result = graph.path_search_result(map, start, end, budget)
    assert_equal(result.report.status, SEARCH_EXHAUSTED)
    assert_equal(len(result.nodes), 0)
    with assert_raises(contains="budget exhausted"):
        _ = graph.path_search(map, start, end, budget)
    with assert_raises(contains="budget exhausted"):
        _ = graph.trace_route(map, start, end, budget)
    var success = graph.path_search_result(map, start, end)
    var ordinary = graph.path_search(map, start, end)
    assert_equal(success.report.status, SEARCH_SUCCESS)
    assert_equal(len(success.nodes), len(ordinary))
    for i in range(len(ordinary)):
        assert_equal(success.nodes[i], ordinary[i])
    assert_true(
        len(graph.trace_route(map, start, end, NavigationSearchBudget(64))) > 0
    )
    var nav = Navigation(_street(), budget)
    var manager = WalkerManager()
    with assert_raises(contains="budget exhausted"):
        _ = nav.get_path(Vector3(1, 1, 0), Vector3(1, 7, 0))
    assert_true(nav.add_walker(manager, ActorId(1), Vector3(1, 1, 0.9)))
    with assert_raises(contains="budget exhausted"):
        _ = nav.get_agent_route(ActorId(1), Vector3(1, 1, 0), Vector3(1, 7, 0))
    with assert_raises(contains="budget exhausted"):
        _ = nav.set_walker_target(manager, ActorId(1), Vector3(1, 7, 0))
    nav.search_budget = NavigationSearchBudget(64)
    assert_true(Bool(nav.get_path(Vector3(1, 1, 0), Vector3(1, 7, 0))))
    assert_true(nav.set_walker_target(manager, ActorId(1), Vector3(1, 7, 0)))
    nav.search_budget.max_pops = -1
    with assert_raises(contains="must be nonnegative"):
        _ = nav.get_path(Vector3(1, 1, 0), Vector3(1, 7, 0))
    with assert_raises(contains="must be nonnegative"):
        _ = Navigation(_street(), _budget(0, -1))


def test_default_policy_is_finite_and_explicit() raises:
    var defaults = NavigationSearchBudget()
    assert_equal(defaults.max_nodes, 4096)
    assert_equal(defaults.max_expansions, 8192)
    assert_equal(defaults.max_queue_entries, 8192)
    assert_equal(defaults.max_pops, 32768)
    assert_equal(defaults.max_edges, 65536)


def test_partial_best_record_rule_preserves_baseline_when_position_changes() raises:
    var mesh = _mesh(5)
    mesh.polygons[0].area = NavArea(2)
    var filter = NavQueryFilter()
    filter.set_area_cost(NavArea(2), 2)
    _portal(mesh, 0, 1, 10)
    _portal(mesh, 0, 2, 1)
    _portal(mesh, 0, 3, 5)
    _portal(mesh, 2, 1, 2)
    var start = Vector3(0, 0, 0)
    var goal = Vector3(20, 0, 0)
    var result = mesh.find_path_result(
        NavPolygonId(0), NavPolygonId(4), start, goal, filter
    )
    assert_equal(result.report.status, SEARCH_UNREACHABLE)
    assert_equal(_ids(result.polygons), "0 2 1 ")
    assert_equal(
        _ids(result.polygons),
        _ids(_linear_path(mesh, 0, 4, start, goal, filter, 256)),
    )


def test_failed_direct_target_and_crowd_replan_preserve_existing_route() raises:
    var nav = Navigation(_street())
    var manager = WalkerManager()
    var id = ActorId(20)
    assert_true(nav.add_walker(manager, id, Vector3(1, 0.5, 0.9)))
    var old_target = Vector3(9, 1.5, 0)
    assert_true(nav.set_walker_direct_target(id, old_target))
    var old_corridor = _ids(nav.agents[0].corridor)
    nav.search_budget = NavigationSearchBudget(0)
    with assert_raises(contains="budget exhausted"):
        _ = nav.set_walker_direct_target(id, Vector3(1, 7, 0))
    assert_true(nav.agents[0].target.value() == old_target)
    assert_equal(_ids(nav.agents[0].corridor), old_corridor)
    with assert_raises(contains="budget exhausted"):
        nav._plan(0)
    assert_true(nav.agents[0].target.value() == old_target)
    assert_equal(_ids(nav.agents[0].corridor), old_corridor)
    # Event-driven point advancement must not commit state before its search.
    manager.walkers[id.value].route.append(
        WalkerRoutePoint(ignore_event(), Vector3(1, 0.5, 0), AREA_SIDEWALK)
    )
    manager.walkers[id.value].route.append(
        WalkerRoutePoint(ignore_event(), Vector3(1, 7, 0), AREA_SIDEWALK)
    )
    manager.walkers[id.value].current_index = 0
    manager.walkers[id.value].state = WALKER_IN_EVENT
    nav.pause_agent(id, True)
    with assert_raises(contains="budget exhausted"):
        _ = manager.set_walker_next_point(nav, id)
    assert_equal(manager.walkers[id.value].current_index, 0)
    assert_equal(manager.walkers[id.value].state, WALKER_IN_EVENT)
    assert_true(nav.agents[0].paused)
    assert_true(nav.agents[0].target.value() == old_target)
    manager.walkers[id.value].route.clear()
    manager.walkers[id.value].state = WALKER_IDLE
    nav.pause_agent(id, False)
    nav.search_budget = NavigationSearchBudget()
    var before = nav.get_walker_position(id).value()
    for _ in range(20):
        nav.update_crowd(manager, Duration(0.05, SECOND))
    var after = nav.get_walker_position(id).value()
    assert_true(after.x > before.x + 1)
    assert_true(after.y < 1)
    assert_true(nav.agents[0].target.value() == old_target)


def test_later_route_failure_restores_existing_and_new_walker_records() raises:
    for existing in [False, True]:
        var mesh = NavMesh()
        _ = mesh.add_polygon(_rect(0, 0, 1, 1), AREA_GRASS)
        _ = mesh.add_polygon(_rect(1, 0, 2, 1), AREA_SIDEWALK)
        mesh.connect()
        var nav = Navigation(mesh^)
        var manager = WalkerManager()
        var id = ActorId(32)
        assert_true(nav.add_walker(manager, id, Vector3(0.5, 0.5, 0.9)))
        if existing:
            assert_true(
                nav.set_walker_target(manager, id, Vector3(1.5, 0.5, 0))
            )
        var previous = manager.walkers[id.value].copy()
        var target = nav.agents[0].target
        var corridor = _ids(nav.agents[0].corridor)
        var paused = nav.agents[0].paused
        nav.search_budget = NavigationSearchBudget(1)
        # This first same-polygon query succeeds. Its one-point route
        # then attempts a random sidewalk route, which needs node 1.
        var initial = nav.get_agent_route(
            id, Vector3(0.5, 0.5, 0), Vector3(0.5, 0.5, 0)
        )
        assert_equal(len(initial.value()), 1)
        with assert_raises(contains="budget exhausted"):
            _ = manager.set_walker_route_to(nav, id, Vector3(0.5, 0.5, 0))
        ref actual = manager.walkers[id.value]
        assert_true(actual.from_location == previous.from_location)
        assert_true(actual.to == previous.to)
        assert_equal(actual.current_index, previous.current_index)
        assert_equal(actual.state, previous.state)
        assert_equal(len(actual.route), len(previous.route))
        for i in range(len(previous.route)):
            assert_true(actual.route[i].location == previous.route[i].location)
        assert_equal(Bool(nav.agents[0].target), Bool(target))
        if Bool(target):
            assert_true(nav.agents[0].target.value() == target.value())
        assert_equal(_ids(nav.agents[0].corridor), corridor)
        assert_equal(nav.agents[0].paused, paused)
        nav.search_budget = NavigationSearchBudget()
        assert_true(manager.set_walker_route_to(nav, id, Vector3(1.5, 0.5, 0)))


def test_end_of_route_without_random_destination_stops_normally() raises:
    var mesh = NavMesh()
    _ = mesh.add_polygon(_rect(0, 0, 1, 1), AREA_GRASS)
    var nav = Navigation(mesh^)
    var manager = WalkerManager()
    var id = ActorId(45)
    assert_true(nav.add_walker(manager, id, Vector3(0.5, 0.5, 0.9)))
    assert_true(manager.set_walker_next_point(nav, id))
    assert_equal(manager.walkers[id.value].current_index, 1)
    assert_equal(manager.walkers[id.value].state, WALKER_STOP)
    assert_true(nav.agents[0].paused)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
