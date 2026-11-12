# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A follower's way round the houses and the pond."""

from extensions.vegetation.ground import Ground, Lot, Pond
from extensions.village.route import (
    ROUTE_DRIFT,
    ROUTE_REFRESH,
    RouteGrid,
    find_route,
    follow_route,
    no_route,
    route_grid,
    route_step,
    sees,
)
from extensions.village.terrain import Floor, Terrain, WallSpan
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import METER, Length


def _flat() raises -> Ground:
    """Return flat ground with no pond."""
    return Ground(hill_height=Length(0.0, METER))


def _walled() raises -> Terrain:
    """Return flat ground with a wall from z -6 to 6 at x 0, too low to
    stop no one, an upper story's wall, and a solid lot at x 10."""
    var walls: List[WallSpan] = [
        WallSpan(0, -6, 0, 6, 0.1, 0, 3),
        WallSpan(-20, -6, -20, 6, 0.1, 2.75, 5),
    ]
    var lots: List[Lot] = [Lot(10, 0, 2, 2, 0)]
    return Terrain(_flat(), lots^, walls^, List[Floor]())


def test_the_grid_closes_walls_lots_and_deep_water() raises:
    var terrain = _walled()
    var grid = route_grid(terrain, 0.5, 20)
    assert_equal(grid.cols, 40)
    # The wall at x 0 closes its cells; the upper story's wall does not.
    assert_false(grid.is_open(grid.cell(0.2, 0)))
    assert_true(grid.is_open(grid.cell(-19.8, 0)))
    assert_false(grid.is_open(grid.cell(10, 0)))
    assert_true(grid.is_open(grid.cell(5, 0)))
    # Off the grid, on each side, no cell.
    assert_equal(grid.cell(30, 0), -1)
    assert_equal(grid.cell(-30, 0), -1)
    assert_equal(grid.cell(0, -30), -1)
    assert_equal(grid.cell(0, 30), -1)
    # A wall off the grid, past its corner or beside its rows, closes
    # nothing.
    var far: List[WallSpan] = [
        WallSpan(50, 50, 60, 50, 0.1, 0, 3),
        WallSpan(50, -2, 50, 2, 0.1, 0, 3),
    ]
    var off = route_grid(
        Terrain(_flat(), List[Lot](), far^, List[Floor]()), 0.5, 20
    )
    for k in range(len(off.open)):
        assert_true(off.open[k])
    assert_false(grid.is_open(-1))
    # A pond deeper than a follower wades closes its middle.
    var wet = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(0.0, METER),
            Length(0.0, METER),
            Length(5.0, METER),
            Length(2.0, METER),
        ),
    )
    var pond = route_grid(Terrain(wet), 0.5, 20)
    assert_false(pond.is_open(pond.cell(0, 0)))
    assert_true(pond.is_open(pond.cell(15, 15)))


def test_a_way_goes_round_a_wall() raises:
    var terrain = _walled()
    var grid = route_grid(terrain, 0.5, 20)
    var start = Vector3(-3, 0, 0)
    var end = Vector3(3, 0, 0)
    assert_false(sees(grid, start, end))
    var way = find_route(grid, start, end)
    assert_true(len(way) > 0)
    # Each step of the way is open, and it ends at the end's cell.
    for k in range(len(way)):
        assert_true(grid.is_open(grid.cell(way[k].x, way[k].z)))
    var last = way[len(way) - 1]
    assert_equal(grid.cell(last.x, last.z), grid.cell(end.x, end.z))
    # It goes past the wall's end: beyond z 6 or before z -6.
    var past = False
    for k in range(len(way)):
        if abs(way[k].z) > 6:
            past = True
    assert_true(past)
    # The furthest point the follower sees is on the way, not the end.
    var step = route_step(grid, start, end, way)
    assert_true(abs(step.z) > 1)
    # With nothing between, the goal itself; with no way, the goal too.
    assert_true(sees(grid, Vector3(-3, 0, 0), Vector3(-3, 0, 5)))
    var open = Vector3(-3, 0, 5)
    assert_true(route_step(grid, start, open, way) == open)
    assert_true(route_step(grid, start, end, List[Vector3]()) == end)
    # A step back to its own cell is no way.
    assert_equal(len(find_route(grid, start, start)), 0)


def test_a_closed_end_moves_to_the_nearest_open_cell() raises:
    var terrain = _walled()
    var grid = route_grid(terrain, 0.5, 20)
    # The lot's middle is closed: the way ends beside it.
    var way = find_route(grid, Vector3(5, 0, 0), Vector3(10, 0, 0))
    assert_true(len(way) > 0)
    var last = way[len(way) - 1]
    assert_true(grid.is_open(grid.cell(last.x, last.z)))
    # Off the grid, or shut in, there is no way.
    assert_equal(len(find_route(grid, Vector3(50, 0, 0), Vector3(5, 0, 0))), 0)
    var boxed = RouteGrid(0, 0, 12, 12)
    for k in range(len(boxed.open)):
        boxed.open[k] = False
    boxed.open[boxed.cell(1, 1)] = True
    boxed.open[boxed.cell(10, 10)] = True
    assert_equal(
        len(find_route(boxed, Vector3(1, 0, 1), Vector3(10, 0, 10))), 0
    )
    # A closed start or end at a corner of the grid moves to an open
    # cell beside it; an end off the grid has no way.
    var corner = RouteGrid(0, 0, 3, 3)
    corner.open[corner.cell(0.5, 0.5)] = False
    corner.open[corner.cell(2.5, 2.5)] = False
    var round = find_route(corner, Vector3(0.5, 0, 0.5), Vector3(2.5, 0, 2.5))
    assert_true(len(round) > 0)
    assert_equal(
        len(find_route(corner, Vector3(1.5, 0, 1.5), Vector3(9, 0, 9))), 0
    )
    # A way down the grid's right edge.
    var edge = RouteGrid(0, 0, 4, 4)
    var down = find_route(edge, Vector3(3.5, 0, 0.5), Vector3(3.5, 0, 3.5))
    assert_equal(len(down), 3)
    # A straight way from off the grid sees across it.
    assert_true(sees(edge, Vector3(-5, 0, 0.5), Vector3(3.5, 0, 0.5)))
    # A closed start with no open cell near it has no way either.
    assert_equal(
        len(find_route(boxed, Vector3(5.5, 0, 5.5), Vector3(10, 0, 10))), 0
    )


def test_a_diagonal_step_does_not_cut_a_closed_corner() raises:
    var grid = RouteGrid(0, 0, 4, 4)
    # Closed cells at (1, 0) and (0, 1): the way from (0, 0) to (1, 1)
    # cannot step across their corner, and there is no other.
    grid.open[grid.cell(1.5, 0.5)] = False
    grid.open[grid.cell(0.5, 1.5)] = False
    assert_equal(
        len(find_route(grid, Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 1.5))), 0
    )
    # One side open: the way goes round it.
    grid.open[grid.cell(1.5, 0.5)] = True
    var way = find_route(grid, Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 1.5))
    assert_equal(len(way), 2)


def test_a_follower_keeps_its_way_and_finds_it_again() raises:
    var terrain = _walled()
    var grid = route_grid(terrain, 0.5, 20)
    var route = no_route()
    var at = Vector3(-3, 0, 0)
    # A goal it sees: straight there, with no way kept.
    var open = Vector3(-3, 0, 8)
    assert_true(follow_route(grid, route, at, open, 1, 0.1) == open)
    assert_equal(len(route.way), 0)
    # A goal past the wall: a point of its way, `keep` past.
    var goal = Vector3(4, 0, 0)
    var aim = follow_route(grid, route, at, goal, 1, 0.1)
    assert_true(len(route.way) > 0)
    assert_false(aim == goal)
    var kept = len(route.way)
    # Kept a moment, found again after `ROUTE_REFRESH`, or once the goal
    # moves `ROUTE_DRIFT`.
    _ = follow_route(grid, route, at, goal, 1, 0.1)
    assert_almost_equal(route.age, 0.1, atol=1e-6)
    _ = follow_route(grid, route, at, goal, 1, ROUTE_REFRESH + 0.1)
    assert_equal(route.age, 0)
    assert_equal(len(route.way), kept)
    _ = follow_route(
        grid, route, at, goal + Vector3(0, 0, ROUTE_DRIFT + 1), 1, 0.1
    )
    assert_equal(route.age, 0)
    # A follower within `keep` of its goal, whose way is empty, follows
    # the goal; one standing on its way's point follows it.
    var shut = RouteGrid(0, 0, 6, 1)
    shut.open[shut.cell(2.5, 0.5)] = False
    var none = no_route()
    var stuck = Vector3(4.5, 0, 0.5)
    assert_true(
        follow_route(shut, none, Vector3(0.5, 0, 0.5), stuck, 0, 0.1) == stuck
    )
    # It keeps a search that found no way, and does not search each frame:
    # the search read the whole grid.
    assert_equal(len(none.way), 0)
    assert_equal(none.age, 0)
    assert_true(
        follow_route(shut, none, Vector3(0.5, 0, 0.5), stuck, 0, 0.1) == stuck
    )
    assert_almost_equal(none.age, 0.1, atol=1e-6)
    # After `ROUTE_REFRESH` it searches again.
    _ = follow_route(
        shut, none, Vector3(0.5, 0, 0.5), stuck, 0, ROUTE_REFRESH + 0.1
    )
    assert_equal(none.age, 0)
    # A follower that sees its goal, and then does not, finds its way at
    # once.
    var lost = no_route()
    var here = Vector3(-3, 0, 0)
    _ = follow_route(grid, lost, here, goal, 1, 0.1)
    assert_true(len(lost.way) > 0)
    assert_true(follow_route(grid, lost, here, open, 1, 0.1) == open)
    assert_equal(len(lost.way), 0)
    _ = follow_route(grid, lost, here, goal, 1, 0.1)
    assert_true(len(lost.way) > 0)
    assert_equal(lost.age, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
