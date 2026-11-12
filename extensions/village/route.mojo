# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A follower's way round the houses and the pond: a grid of the
village's open ground, and the shortest way over it.

A follower walks straight at the point it follows, and slides along a
wall it meets at a slant. A house across its way, or a corner, stops it
dead. So the companion and the raiders take the shortest way over a grid
of the ground:

1. **The grid.** `route_grid` lays cells `ROUTE_CELL` meters on a side
   over the village. A cell is closed where a wall of a house, or a
   solid lot, stands within `ROUTE_RADIUS` and half a cell of its middle, or where the
   water is deeper than a follower wades. Each wall and each lot closes
   the cells of its own box, so the grid is quick to lay.
2. **The way.** `find_route` finds the shortest way from cell to cell,
   by the eight cells round each, with A*. A start or an end in a closed
   cell moves to the nearest open one.
3. **The step.** `route_step` gives the point a follower walks to: its
   goal, where the straight way to it is open; else the furthest point of
   the way that it sees straight.

This is not a three.js port. See Extensions.

    var grid = route_grid(terrain, wade, ROUTE_REACH)
    var way = find_route(grid, at, goal)
    var aim = route_step(grid, at, goal, way)
"""

from extensions.village.character import HEADROOM, lot_push
from extensions.village.terrain import Terrain, wall_push
from math.vector3 import Vector3
from std.math import ceil, floor, sqrt
from units.si import METER

comptime ROUTE_CELL = Float32(1)
"""The side of a cell of the grid, in meters."""
comptime ROUTE_RADIUS = Float32(0.4)
"""How far from a wall or a lot a cell's middle must be to be open, in
meters: a follower's radius, and a little more."""
comptime _REACH = ROUTE_RADIUS + ROUTE_CELL / 2
"""How near a wall or a lot a cell's middle closes it: a follower's
radius, and half a cell, so a wall that crosses a cell closes it."""
comptime ROUTE_FOOT = Float32(0.5)
"""The height of the feet that the walls are measured against, in
meters: the ground floor's, under every upper story."""
comptime ROUTE_REACH = Float32(90)
"""How far from the village's middle the grid reaches, each way, in
meters."""
comptime SNAP_REACH = 4
"""How many cells round a closed start or end the nearest open cell is
looked for."""


struct RouteGrid(Movable):
    """The open cells of the village's ground."""

    var x0: Float32
    """The x of the grid's first column's left edge, in meters."""
    var z0: Float32
    """The z of the grid's first row's near edge, in meters."""
    var cols: Int
    """How many cells a row has."""
    var rows: Int
    """How many rows the grid has."""
    var open: List[Bool]
    """Whether each cell is open, row by row."""

    def __init__(out self, x0: Float32, z0: Float32, cols: Int, rows: Int):
        """Lay a grid with every cell open.

        Args:
            x0: The x of its left edge, in meters.
            z0: The z of its near edge, in meters.
            cols: How many cells a row has.
            rows: How many rows it has.
        """
        self.x0 = x0
        self.z0 = z0
        self.cols = cols
        self.rows = rows
        self.open = List[Bool](length=cols * rows, fill=True)

    def cell(self, x: Float32, z: Float32) -> Int:
        """Return the cell a point stands in, or -1 off the grid.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The cell's index, row by row.
        """
        var c = Int(floor((x - self.x0) / ROUTE_CELL))
        var r = Int(floor((z - self.z0) / ROUTE_CELL))
        if c < 0 or r < 0 or c >= self.cols or r >= self.rows:
            return -1
        return r * self.cols + c

    def middle(self, cell: Int) -> Vector3:
        """Return the middle of a cell, on the ground.

        Args:
            cell: The cell's index.

        Returns:
            Its middle, at height zero.
        """
        var c = cell % self.cols
        var r = cell // self.cols
        return Vector3(
            self.x0 + (Float32(c) + 0.5) * ROUTE_CELL,
            0,
            self.z0 + (Float32(r) + 0.5) * ROUTE_CELL,
        )

    def is_open(self, cell: Int) -> Bool:
        """Return whether a cell is on the grid and open.

        Args:
            cell: The cell's index, or -1.

        Returns:
            True for an open cell of the grid.
        """
        return cell >= 0 and self.open[cell]

    def _close_box(
        mut self,
        terrain: Terrain,
        x_low: Float32,
        x_high: Float32,
        z_low: Float32,
        z_high: Float32,
        lot: Int,
        wall: Int,
    ):
        """Close each cell of a box whose middle `lot` or `wall` of the
        terrain pushes: one of the two is -1."""
        var c0 = max(0, Int(floor((x_low - self.x0) / ROUTE_CELL)))
        var c1 = min(self.cols - 1, Int(floor((x_high - self.x0) / ROUTE_CELL)))
        var r0 = max(0, Int(floor((z_low - self.z0) / ROUTE_CELL)))
        var r1 = min(self.rows - 1, Int(floor((z_high - self.z0) / ROUTE_CELL)))
        for r in range(r0, r1 + 1):
            for c in range(c0, c1 + 1):
                var at = self.middle(r * self.cols + c)
                var moved: Vector3
                if lot >= 0:
                    moved = lot_push(terrain.lots[lot], at.x, at.z, _REACH)
                else:
                    moved = wall_push(terrain.walls[wall], at.x, at.z, _REACH)
                if moved.x != at.x or moved.z != at.z:
                    self.open[r * self.cols + c] = False


def route_grid(terrain: Terrain, wade: Float32, reach: Float32) -> RouteGrid:
    """Lay the grid of the village's open ground.

    Args:
        terrain: The ground, the houses' walls and the solid lots.
        wade: How deep a follower wades, in meters.
        reach: How far from the village's middle the grid reaches, each
            way, in meters.

    Returns:
        The grid: a cell is closed where a wall of the ground floor or a
        solid lot stands within `ROUTE_RADIUS` and half a cell of its
        middle, or where the water is deeper than `wade`.
    """
    var count = Int(ceil(2 * reach / ROUTE_CELL))
    var grid = RouteGrid(-reach, -reach, count, count)
    for index in range(len(terrain.lots)):
        ref lot = terrain.lots[index]
        var span = (
            sqrt(
                lot.half_width * lot.half_width
                + lot.half_depth * lot.half_depth
            )
            + _REACH
        )
        grid._close_box(
            terrain,
            lot.x - span,
            lot.x + span,
            lot.z - span,
            lot.z + span,
            index,
            -1,
        )
    for index in range(len(terrain.walls)):
        ref wall = terrain.walls[index]
        if not wall.blocks(ROUTE_FOOT, ROUTE_FOOT + HEADROOM):
            continue
        var pad = wall.half_thickness + _REACH
        grid._close_box(
            terrain,
            min(wall.x0, wall.x1) - pad,
            max(wall.x0, wall.x1) + pad,
            min(wall.z0, wall.z1) - pad,
            max(wall.z0, wall.z1) + pad,
            -1,
            index,
        )
    ref ground = terrain.ground
    var level = ground.water_level()
    var pond = ground.pond.radius.to(METER)
    if pond > 0:
        for cell in range(len(grid.open)):  # pragma: no branch
            var at = grid.middle(cell)
            if level - terrain.height_at(at.x, at.z, ROUTE_FOOT) > wade:
                grid.open[cell] = False
    return grid^


def _nearest_open(grid: RouteGrid, cell: Int) -> Int:
    """Return the open cell nearest a cell, within `SNAP_REACH`, or -1."""
    if grid.is_open(cell):
        return cell
    if cell < 0:
        return -1
    var c = cell % grid.cols
    var r = cell // grid.cols
    var best = -1
    var least = Int.MAX
    for dr in range(-SNAP_REACH, SNAP_REACH + 1):  # pragma: no branch
        for dc in range(-SNAP_REACH, SNAP_REACH + 1):  # pragma: no branch
            var nc = c + dc
            var nr = r + dr
            if nc < 0 or nr < 0 or nc >= grid.cols or nr >= grid.rows:
                continue
            var other = nr * grid.cols + nc
            var far = dc * dc + dr * dr
            if grid.open[other] and far < least:
                least = far
                best = other
    return best


def _octile(grid: RouteGrid, a: Int, b: Int) -> Float32:
    """Return the length of the shortest way between two cells over the
    eight neighbors, with nothing closed, in cells."""
    var dx = abs(a % grid.cols - b % grid.cols)
    var dz = abs(a // grid.cols - b // grid.cols)
    var short = min(dx, dz)
    var long = max(dx, dz)
    return Float32(long - short) + Float32(short) * 1.41421356


def _push(mut heap: List[Int], cost: List[Float32], cell: Int):
    """Add a cell to a binary heap ordered by `cost`."""
    heap.append(cell)
    var k = len(heap) - 1
    while k > 0:
        var up = (k - 1) // 2
        if cost[heap[up]] <= cost[heap[k]]:
            break
        var held = heap[up]
        heap[up] = heap[k]
        heap[k] = held
        k = up


def _pop(mut heap: List[Int], cost: List[Float32]) -> Int:
    """Take the cell of least `cost` from a binary heap."""
    var top = heap[0]
    var last = heap.pop()
    if len(heap) == 0:
        return top
    heap[0] = last
    var k = 0
    while True:
        var left = 2 * k + 1
        if left >= len(heap):
            break
        var least = left
        var right = left + 1
        if right < len(heap) and cost[heap[right]] < cost[heap[left]]:
            least = right
        if cost[heap[k]] <= cost[heap[least]]:
            break
        var held = heap[least]
        heap[least] = heap[k]
        heap[k] = held
        k = least
    return top


def find_route(grid: RouteGrid, start: Vector3, end: Vector3) -> List[Vector3]:
    """Return the shortest way over the grid's open cells from one point
    to another.

    Args:
        grid: The grid.
        start: Where the way starts.
        end: Where it ends.

    Returns:
        The middle of each cell of the way after the first, in turn, the
        last the end's own cell; empty where either point is off the grid,
        has no open cell within `SNAP_REACH`, or no way joins them. A
        diagonal step does not cut a closed corner.
    """
    var from_ = _nearest_open(grid, grid.cell(start.x, start.z))
    var to = _nearest_open(grid, grid.cell(end.x, end.z))
    var way = List[Vector3]()
    if from_ < 0 or to < 0:
        return way^
    var count = len(grid.open)
    var spent = List[Float32](length=count, fill=Float32(1.0e30))
    var guess = List[Float32](length=count, fill=Float32(1.0e30))
    var came = List[Int](length=count, fill=-1)
    var done = List[Bool](length=count, fill=False)
    var heap = List[Int]()
    spent[from_] = 0
    guess[from_] = _octile(grid, from_, to)
    _push(heap, guess, from_)
    var step_x: List[Int] = [1, -1, 0, 0, 1, 1, -1, -1]
    var step_z: List[Int] = [0, 0, 1, -1, 1, -1, 1, -1]
    while len(heap) > 0:
        var here = _pop(heap, guess)
        if here == to:
            break
        if done[here]:
            continue
        done[here] = True
        var c = here % grid.cols
        var r = here // grid.cols
        for k in range(8):
            var sx = step_x[k]
            var sz = step_z[k]
            var nc = c + sx
            var nr = r + sz
            if nc < 0 or nr < 0 or nc >= grid.cols or nr >= grid.rows:
                continue
            var next = nr * grid.cols + nc
            if not grid.open[next] or done[next]:
                continue
            # A diagonal step needs both cells beside it open.
            var diagonal = sx != 0 and sz != 0
            if diagonal:
                if not grid.open[r * grid.cols + nc]:
                    continue
                if not grid.open[nr * grid.cols + c]:
                    continue
            var cost = spent[here] + (
                Float32(1.41421356) if diagonal else Float32(1)
            )
            if cost < spent[next]:
                spent[next] = cost
                guess[next] = cost + _octile(grid, next, to)
                came[next] = here
                _push(heap, guess, next)
    if came[to] < 0 and to != from_:
        return way^
    var back = List[Int]()
    var at = to
    while at != from_:
        back.append(at)
        at = came[at]
    for k in range(len(back) - 1, -1, -1):
        way.append(grid.middle(back[k]))
    return way^


def sees(grid: RouteGrid, a: Vector3, b: Vector3) -> Bool:
    """Return whether the straight way between two points crosses only
    open cells of the grid.

    Args:
        grid: The grid.
        a: One point.
        b: The other.

    Returns:
        True when each point of the way, a quarter cell apart, stands in
        an open cell, or off the grid.
    """
    var dx = b.x - a.x
    var dz = b.z - a.z
    var long = sqrt(dx * dx + dz * dz)
    var steps = Int(ceil(long / (ROUTE_CELL / 4))) + 1
    for k in range(steps + 1):  # pragma: no branch
        var t = Float32(k) / Float32(steps)
        var cell = grid.cell(a.x + dx * t, a.z + dz * t)
        if cell >= 0 and not grid.open[cell]:
            return False
    return True


def route_step(
    grid: RouteGrid, at: Vector3, goal: Vector3, way: List[Vector3]
) -> Vector3:
    """Return the point a follower walks to on its way to a goal.

    Args:
        grid: The grid.
        at: Where the follower stands.
        goal: The point it follows.
        way: The way from it to the goal: see `find_route`.

    Returns:
        `goal` where the follower sees it straight, or the way is empty;
        else the furthest point of the way that it sees straight, or the
        way's first point, at the follower's height.
    """
    if len(way) == 0 or sees(grid, at, goal):
        return goal
    var best = way[0]
    for k in range(len(way)):  # pragma: no branch
        if sees(grid, at, way[k]):
            best = way[k]
    return Vector3(best.x, at.y, best.z)


comptime ROUTE_REFRESH = Float32(1)
"""How long a follower keeps its way before it finds it again, in
seconds."""
comptime ROUTE_DRIFT = Float32(2)
"""How far its goal may move from the way's end before a follower finds
its way again, in meters."""
comptime _STALE = ROUTE_REFRESH + 1
"""The age of a way that a follower must find at once, in seconds."""


@fieldwise_init
struct Route(Copyable, Movable):
    """The way a follower keeps to its goal."""

    var way: List[Vector3]
    """The way's points: see `find_route`."""
    var goal: Vector3
    """The goal the way was found to."""
    var age: Float32
    """How long ago it was found, in seconds."""


def no_route() -> Route:
    """Return a follower that keeps no way.

    Returns:
        An empty way, old enough that the follower finds its way at once.
    """
    return Route(List[Vector3](), Vector3(0, 0, 0), _STALE)


def follow_route(
    grid: RouteGrid,
    mut route: Route,
    at: Vector3,
    goal: Vector3,
    keep: Float32,
    seconds: Float32,
) -> Vector3:
    """Return the point a follower walks to, round the houses and the pond
    to its goal.

    The follower finds its way again after `ROUTE_REFRESH`, or once its
    goal has moved `ROUTE_DRIFT` from the way's end. It keeps a search
    that found no way as long as one that found a way. A search that
    finds no way reads the whole grid, so the follower must not repeat
    it each frame.

    Args:
        grid: The grid.
        route: The way the follower keeps.
        at: Where it stands.
        goal: The point it follows.
        keep: How far from what it follows it stops, in meters.
        seconds: The frame's time.

    Returns:
        `goal` where the follower sees the spot `keep` short of it
        straight, or no way leads there. Else a point of the way to that
        spot, `keep` past it on the follower's way, so that it walks on
        to it.
    """
    # The goal lies `keep` past the spot the follower stops at: the way
    # leads to the spot, which can stand outside a house the goal is in.
    var gx = goal.x - at.x
    var gz = goal.z - at.z
    var far = sqrt(gx * gx + gz * gz)
    var spot = goal
    if far > keep:
        spot = Vector3(
            goal.x - gx / far * keep, goal.y, goal.z - gz / far * keep
        )
    if sees(grid, at, spot):
        route.way.clear()
        # Once the spot is out of sight, the follower finds its way at once.
        route.age = _STALE
        return goal
    route.age += seconds
    var dx = route.goal.x - spot.x
    var dz = route.goal.z - spot.z
    var drift = sqrt(dx * dx + dz * dz)
    if route.age > ROUTE_REFRESH or drift > ROUTE_DRIFT:
        route.way = find_route(grid, at, spot)
        route.goal = spot
        route.age = 0
    var aim = route_step(grid, at, spot, route.way)
    if len(route.way) == 0:
        return goal
    var ax = aim.x - at.x
    var az = aim.z - at.z
    # A follower that stands on the point walks to the point itself.
    var long = max(sqrt(ax * ax + az * az), Float32(1.0e-4))
    return Vector3(aim.x + ax / long * keep, aim.y, aim.z + az / long * keep)
