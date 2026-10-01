# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A navigation mesh for CARLA's pedestrians, built from the map.

CARLA's walkers find their way on a navigation mesh that a third-party
library builds from the town's geometry offline. This module builds its
own mesh from the map's lanes and crosswalks, with CARLA's area kinds and
flags on top. It uses these well-known patterns:

- **A polygon graph.** Each lane of a lane section is cut across into
  strips at every `resolution` along s, at the section's ends, and at the
  ends of each crosswalk. Each strip is a convex quad from the lane's two
  edges, `Road.lane_corners`, which also raise a sidewalk by its curb. A
  sidewalk quad is `AREA_SIDEWALK`. A quad of a road lane is `AREA_ROAD`,
  or `AREA_CROSSWALK` when its middle lies inside a crosswalk's outline,
  `Map.all_crosswalk_zones`.
- **Shared-edge adjacency.** Two polygons are neighbors where an edge of
  one lies along an edge of the other, within 5 cm, for more than 5 cm,
  and within a climb of 0.5 m. The shared part is the portal between
  them.
- **A* over the polygons.** The search moves from portal middle to portal
  middle. A step costs its length times the area cost of the polygon it
  crosses, as a query filter sets it. The heuristic is the straight
  distance to the goal, which never overestimates while no area costs
  less than 1. When the goal cannot be reached, the path ends at the
  polygon nearest the goal.
- **The funnel algorithm.** The straight path pulls the route tight
  through the portals. A point is added where the route crosses from one
  area kind into another, as CARLA asks for with its area-crossing
  option. Each point carries the area of the polygon the route enters
  there. The end point carries the area of the point before it, as
  CARLA reads it.
- **Area-weighted random points.** A random point picks a polygon with a
  chance in proportion to its area, then a triangle of its fan the same
  way, then a uniform point in the triangle.

The area kinds and flags, the search limit of 256 polygons and the query
box of 2 m across and 4 m up are CARLA's, from
`LibCarla/source/carla/nav/Navigation.h` and `Navigation.cpp`. The rest
of the numbers are this port's own choices.
"""

from extensions.carla.agents import point_in_polygon
from extensions.carla.map import EPSILON, Map
from extensions.carla.road_info import (
    LANE_BIDIRECTIONAL,
    LANE_BIKING,
    LANE_DRIVING,
    LANE_ENTRY,
    LANE_EXIT,
    LANE_OFF_RAMP,
    LANE_ON_RAMP,
    LANE_PARKING,
    LANE_RESTRICTED,
    LANE_SHOULDER,
    LANE_SIDEWALK,
    LANE_STOP,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.search_queue import _MinCostQueue
from math.vector3 import Vector3
from std.math import cos, floor, isfinite, sin, sqrt
from units.si import METER, Length

# CARLA's `MAX_POLYS`: the longest path a query gives.
comptime MAX_POLYS = 256
# The size of a cell of the polygon grid, in meters.
comptime _CELL = Float32(4)
# Two edges lie along each other within this, in meters.
comptime _ALONG = Float32(0.05)
# The highest step between two neighbors, in meters.
comptime _CLIMB = Float32(0.5)
# Cut points closer than this along s merge, in meters.
comptime _MERGE = 0.01
# Path points closer than this in plan are one point, in meters.
comptime _SAME = 0.01
# A point this close outside an edge is on it, in meters.
comptime _ON_EDGE = 1e-4


# --- kinds ---------------------------------------------------------------------------


@fieldwise_init
struct NavArea(Equatable, ImplicitlyCopyable, Writable):
    """What a polygon is, CARLA's `NavAreas`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of CARLA's five areas.

        Returns:
            Whether the value is from 0 to 4.
        """
        return self.value >= 0 and self.value <= 4


comptime AREA_BLOCK = NavArea(0)
comptime AREA_SIDEWALK = NavArea(1)
comptime AREA_CROSSWALK = NavArea(2)
comptime AREA_ROAD = NavArea(3)
comptime AREA_GRASS = NavArea(4)


@fieldwise_init
struct NavFlags(Equatable, ImplicitlyCopyable, Writable):
    """A mask of polygon kinds, CARLA's `SamplePolyFlags`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the mask fits CARLA's 16 bits.

        Returns:
            Whether the value is from 0 to 0xffff.
        """
        return self.value >= 0 and self.value <= 0xFFFF

    def __and__(self, other: Self) -> Self:
        """Return the bits in both masks.

        Args:
            other: The other mask.

        Returns:
            The bitwise and.
        """
        return NavFlags(self.value & other.value)

    def __or__(self, other: Self) -> Self:
        """Return the bits in either mask.

        Args:
            other: The other mask.

        Returns:
            The bitwise or.
        """
        return NavFlags(self.value | other.value)


comptime FLAG_NONE = NavFlags(0x01)
comptime FLAG_SIDEWALK = NavFlags(0x02)
comptime FLAG_CROSSWALK = NavFlags(0x04)
comptime FLAG_ROAD = NavFlags(0x08)
comptime FLAG_GRASS = NavFlags(0x10)
comptime FLAG_ALL = NavFlags(0xFFFF)
comptime FLAG_WALKABLE = NavFlags(0x02 | 0x04 | 0x10 | 0x08)


def flags_of(area: NavArea) raises -> NavFlags:
    """Return the flag of an area, as CARLA's mesh builder tags it.

    Args:
        area: The area.

    Returns:
        `FLAG_SIDEWALK`, `FLAG_CROSSWALK`, `FLAG_ROAD`, `FLAG_GRASS`, or
        `FLAG_NONE` for a block.

    Raises:
        Error: If the area is not valid.
    """
    if not area.is_valid():
        raise Error("Navigation area is not valid")
    if area == AREA_BLOCK:
        return FLAG_NONE
    return NavFlags(1 << area.value)


struct NavQueryFilter(ImplicitlyCopyable, Writable):
    """Which polygons a query may use and what each area costs, a query
    filter."""

    var include: NavFlags
    var exclude: NavFlags
    # The cost of each area, by the area's value.
    var costs: SIMD[DType.float64, 8]

    def __init__(out self):
        """Create a filter that takes every polygon at a cost of 1."""
        self.include = FLAG_ALL
        self.exclude = NavFlags(0)
        self.costs = SIMD[DType.float64, 8](1.0)

    def __init__(out self, include: NavFlags, exclude: NavFlags) raises:
        """Create a filter from two masks, at a cost of 1 everywhere.

        Args:
            include: A polygon needs one of these flags.
            exclude: A polygon may have none of these.

        Raises:
            Error: If a mask is not valid.
        """
        if not (include.is_valid() and exclude.is_valid()):
            raise Error("Navigation flags are not valid")
        self = NavQueryFilter()
        self.include = include
        self.exclude = exclude

    def passes(self, flags: NavFlags) -> Bool:
        """Return True if a polygon with these flags may be used.

        Args:
            flags: The polygon's flags.

        Returns:
            Whether it has an included flag and no excluded one.
        """
        return (flags & self.include).value != 0 and (
            flags & self.exclude
        ).value == 0

    def set_area_cost(mut self, area: NavArea, cost: Float64) raises:
        """Set what one meter in an area costs.

        Args:
            area: The area.
            cost: The cost. It must be finite and at least 1, so the
                search's heuristic stays a lower bound.

        Raises:
            Error: If the area is not valid, the cost is not finite, or
                the cost is less than 1.
        """
        if not area.is_valid():
            raise Error("Navigation area is not valid")
        if not isfinite(cost) or cost < 1.0:
            raise Error("An area cost must be at least 1 and finite")
        self.costs[area.value] = cost

    def area_cost(self, area: NavArea) raises -> Float64:
        """Return what one meter in an area costs.

        Args:
            area: The area.

        Returns:
            The cost.

        Raises:
            Error: If the area is not valid, its cost is not finite, or
                its cost is less than 1.
        """
        if not area.is_valid():
            raise Error("Navigation area is not valid")
        var cost = self.costs[area.value]
        if not isfinite(cost) or cost < 1.0:
            raise Error("An area cost must be at least 1 and finite")
        return cost


def sidewalk_filter() -> NavQueryFilter:
    """Return CARLA's filter for random locations: sidewalks only.

    Returns:
        A filter that includes `FLAG_SIDEWALK` and excludes nothing.
    """
    var f = NavQueryFilter()
    f.include = FLAG_SIDEWALK
    return f


def walker_filter(can_cross_roads: Bool) -> NavQueryFilter:
    """Return one of CARLA's two walker filters.

    Both include every walkable polygon, and cost 10 a meter on a road and
    1 on grass. Filter 0 keeps walkers off the roads, so they cross only
    at crosswalks. Filter 1 lets them cross anywhere.

    Args:
        can_cross_roads: Whether this is filter 1.

    Returns:
        The filter.
    """
    var f = NavQueryFilter()
    f.include = FLAG_WALKABLE
    f.exclude = FLAG_NONE if can_cross_roads else FLAG_ROAD
    f.costs[AREA_ROAD.value] = 10.0
    f.costs[AREA_GRASS.value] = 1.0
    return f


# --- polygons ------------------------------------------------------------------------


@fieldwise_init
struct NavPolygonId(Equatable, ImplicitlyCopyable, Writable):
    """A polygon of a `NavMesh`: its index. -1 names none."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is an index or names none.

        Returns:
            Whether the value is -1 or more.
        """
        return self.value >= -1


comptime NO_POLYGON = NavPolygonId(-1)


@fieldwise_init
struct NavPortal(ImplicitlyCopyable):
    """The edge a polygon shares with a neighbor."""

    var neighbor: Int
    # The shared part, in the order of the polygon's own edge.
    var a: Vector3
    var b: Vector3


@fieldwise_init
struct NavPoint(ImplicitlyCopyable, Writable):
    """A point of a straight path and the area it enters."""

    var location: Vector3
    var area: NavArea

    def write_to(self, mut writer: Some[Writer]):
        """Write the point and its area.

        Args:
            writer: The destination.
        """
        writer.write(
            "NavPoint(",
            self.location.x,
            ", ",
            self.location.y,
            ", ",
            self.location.z,
            ", area=",
            self.area.value,
            ")",
        )


def _cross(o: Vector3, a: Vector3, b: Vector3) -> Float64:
    # The z part of (a - o) x (b - o) in the x-y plane.
    return (Float64(a.x) - Float64(o.x)) * (Float64(b.y) - Float64(o.y)) - (
        Float64(a.y) - Float64(o.y)
    ) * (Float64(b.x) - Float64(o.x))


def _signed_area(vertices: List[Vector3]) -> Float64:
    var total = 0.0
    # Every caller passes three corners at least.
    for i in range(1, len(vertices) - 1):  # pragma: no branch
        total += _cross(vertices[0], vertices[i], vertices[i + 1])
    return total / 2.0


struct NavPolygon(Copyable, Movable):
    """A convex polygon of the mesh, counter-clockwise in the x-y plane."""

    var vertices: List[Vector3]
    var area: NavArea
    var flags: NavFlags
    var portals: List[NavPortal]
    # The mean of the corners.
    var center: Vector3
    # The plan area, in square meters.
    var size: Float64

    def __init__(out self, var vertices: List[Vector3], area: NavArea) raises:
        """Create a polygon.

        Args:
            vertices: The corners of a convex polygon, in either turn.
            area: What it is.

        Raises:
            Error: If there are fewer than three corners, the area is not
                valid, or the polygon has no area.
        """
        if len(vertices) < 3:
            raise Error("A polygon needs three corners")
        self.flags = flags_of(area)
        var signed = _signed_area(vertices)
        if abs(signed) < 1e-6:
            raise Error("A polygon needs an area")
        if signed < 0.0:
            vertices.reverse()
        self.size = abs(signed)
        var sum = Vector3(0, 0, 0)
        # Three corners at least, checked above.
        for v in vertices:  # pragma: no branch
            sum = sum + v
        self.center = sum / Float32(len(vertices))
        self.vertices = vertices^
        self.area = area
        self.portals = List[NavPortal]()

    def contains(self, point: Vector3) -> Bool:
        """Return True if a point lies inside in the x-y plane.

        Args:
            point: The point.

        Returns:
            Whether it is on the inner side of every edge, or within
            0.1 mm of one.
        """
        var n = len(self.vertices)
        # A polygon has three corners at least.
        for i in range(n):  # pragma: no branch
            var a = self.vertices[i]
            var b = self.vertices[(i + 1) % n]
            if _cross(a, b, point) < -_ON_EDGE * _distance_2d(a, b):
                return False
        return True

    def height_at(self, point: Vector3) -> Float32:
        """Return the polygon's height under a point.

        Args:
            point: A point inside the polygon in the x-y plane.

        Returns:
            The height of the fan triangle that holds the point best: the
            one whose smallest barycentric weight is largest.
        """
        var best_z = self.vertices[0].z
        var best_score = -Float64.MAX
        # A polygon has one fan triangle at least.
        for i in range(1, len(self.vertices) - 1):  # pragma: no branch
            var a = self.vertices[0]
            var b = self.vertices[i]
            var c = self.vertices[i + 1]
            var area = _cross(a, b, c)
            var u = _cross(point, b, c) / area
            var v = _cross(a, point, c) / area
            var w = 1.0 - u - v
            var score = min(u, min(v, w))
            if score > best_score:
                best_score = score
                best_z = Float32(
                    u * Float64(a.z) + v * Float64(b.z) + w * Float64(c.z)
                )
        return best_z

    def closest_point(self, point: Vector3) -> Vector3:
        """Return the point of the polygon nearest a point.

        Args:
            point: The point.

        Returns:
            The point itself at the polygon's height when it lies inside
            in the x-y plane, else the nearest point of the border.
        """
        if self.contains(point):
            return Vector3(point.x, point.y, self.height_at(point))
        var best = self.vertices[0]
        var best_d = Float64.MAX
        var n = len(self.vertices)
        # A polygon has three corners at least.
        for i in range(n):  # pragma: no branch
            var c = _closest_on_segment(
                self.vertices[i], self.vertices[(i + 1) % n], point
            )
            var d = _distance_2d(c, point)
            if d < best_d:
                best_d = d
                best = c
        return best


def _distance_2d(a: Vector3, b: Vector3) -> Float64:
    var dx = Float64(a.x) - Float64(b.x)
    var dy = Float64(a.y) - Float64(b.y)
    return sqrt(dx * dx + dy * dy)


def _distance(a: Vector3, b: Vector3) -> Float64:
    var dx = Float64(a.x) - Float64(b.x)
    var dy = Float64(a.y) - Float64(b.y)
    var dz = Float64(a.z) - Float64(b.z)
    return sqrt(dx * dx + dy * dy + dz * dz)


def _lerp(a: Vector3, b: Vector3, t: Float64) -> Vector3:
    return Vector3(
        Float32(Float64(a.x) + (Float64(b.x) - Float64(a.x)) * t),
        Float32(Float64(a.y) + (Float64(b.y) - Float64(a.y)) * t),
        Float32(Float64(a.z) + (Float64(b.z) - Float64(a.z)) * t),
    )


def _param(a: Vector3, b: Vector3, p: Vector3) -> Float64:
    # Where p projects on a-b in the x-y plane: 0 at a, 1 at b.
    var dx = Float64(b.x) - Float64(a.x)
    var dy = Float64(b.y) - Float64(a.y)
    var len2 = dx * dx + dy * dy
    return (
        (Float64(p.x) - Float64(a.x)) * dx + (Float64(p.y) - Float64(a.y)) * dy
    ) / len2


def _closest_on_segment(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
    return _lerp(a, b, min(max(_param(a, b, p), 0.0), 1.0))


def _cell(x: Float32) -> Int:
    return Int(floor(x / _CELL))


def _cell_key(i: Int, j: Int) -> Int:
    return i * 1000003 + j


# --- the mesh ----------------------------------------------------------------------------


struct _SearchNode(ImplicitlyCopyable):
    var cost: Float64
    var total: Float64
    var heuristic: Float64
    var parent: Int
    var position: Vector3
    var open: Bool
    var closed: Bool

    def __init__(out self):
        self.cost = 0.0
        self.total = 0.0
        self.heuristic = 0.0
        self.parent = -1
        self.position = Vector3(0, 0, 0)
        self.open = False
        self.closed = False


struct NavMesh(Movable):
    """CARLA's pedestrian navigation mesh: polygons and their portals."""

    var polygons: List[NavPolygon]
    var _grid: Dict[Int, List[Int]]

    def __init__(out self):
        """Create an empty mesh."""
        self.polygons = List[NavPolygon]()
        self._grid = Dict[Int, List[Int]]()

    def add_polygon(
        mut self, var vertices: List[Vector3], area: NavArea
    ) raises -> NavPolygonId:
        """Add a convex polygon. Call `connect` after the last one.

        Args:
            vertices: The corners, in either turn.
            area: What it is.

        Returns:
            Its id.

        Raises:
            Error: If `NavPolygon` refuses it.
        """
        var polygon = NavPolygon(vertices^, area)
        var id = len(self.polygons)
        var lo_x = polygon.vertices[0].x
        var hi_x = lo_x
        var lo_y = polygon.vertices[0].y
        var hi_y = lo_y
        # A polygon has three corners at least.
        for v in polygon.vertices:  # pragma: no branch
            lo_x = min(lo_x, v.x)
            hi_x = max(hi_x, v.x)
            lo_y = min(lo_y, v.y)
            hi_y = max(hi_y, v.y)
        # The low end of a range is never past its high end.
        for i in range(
            _cell(lo_x - _ALONG), _cell(hi_x + _ALONG) + 1
        ):  # pragma: no branch
            for j in range(
                _cell(lo_y - _ALONG), _cell(hi_y + _ALONG) + 1
            ):  # pragma: no branch
                var key = _cell_key(i, j)
                if key not in self._grid:
                    self._grid[key] = List[Int]()
                self._grid[key].append(id)
        self.polygons.append(polygon^)
        return NavPolygonId(id)

    def _near(self, lo: Vector3, hi: Vector3) raises -> List[Int]:
        # The polygons in the grid cells of a box, each once.
        var seen = Dict[Int, Bool]()
        var out = List[Int]()
        # Every caller passes a box whose low corner is not past its high.
        for i in range(_cell(lo.x), _cell(hi.x) + 1):  # pragma: no branch
            for j in range(_cell(lo.y), _cell(hi.y) + 1):  # pragma: no branch
                var cell = self._grid.get(_cell_key(i, j))
                if not Bool(cell):
                    continue
                # A cell is made with its first polygon.
                for p in cell.value():  # pragma: no branch
                    if p not in seen:
                        seen[p] = True
                        out.append(p)
        sort(out)
        return out^

    def connect(mut self) raises:
        """Find the portals between the polygons: shared-edge adjacency.

        Raises:
            Error: Never in practice; a grid lookup raises only on a
                missing key.
        """
        for p in range(len(self.polygons)):
            self.polygons[p].portals.clear()
            var n = len(self.polygons[p].vertices)
            var box_lo = self.polygons[p].vertices[0]
            var box_hi = box_lo
            # A polygon has three corners at least.
            for v in self.polygons[p].vertices:  # pragma: no branch
                box_lo = Vector3(min(box_lo.x, v.x), min(box_lo.y, v.y), 0)
                box_hi = Vector3(max(box_hi.x, v.x), max(box_hi.y, v.y), 0)
            var pad = Vector3(_ALONG, _ALONG, 0)
            # The polygon's own cells hold it.
            var near = self._near(box_lo - pad, box_hi + pad)
            for q in near:  # pragma: no branch
                if q == p:
                    continue
                var best = -1.0
                var portal = NavPortal(q, Vector3(0, 0, 0), Vector3(0, 0, 0))
                # A polygon has three corners at least.
                for i in range(n):  # pragma: no branch
                    var a = self.polygons[p].vertices[i]
                    var b = self.polygons[p].vertices[(i + 1) % n]
                    var shared = self._shared(a, b, q)
                    if Bool(shared) and shared.value()[2] > best:
                        best = shared.value()[2]
                        portal = NavPortal(
                            q, shared.value()[0], shared.value()[1]
                        )
                if best > 0.0:
                    self.polygons[p].portals.append(portal)

    def _shared(
        self, a: Vector3, b: Vector3, q: Int
    ) -> Optional[Tuple[Vector3, Vector3, Float64]]:
        # The part of edge a-b that lies along an edge of polygon q.
        var length = _distance_2d(a, b)
        if length < Float64(_ALONG):
            return None
        var m = len(self.polygons[q].vertices)
        var best = Optional[Tuple[Vector3, Vector3, Float64]](None)
        # A polygon has three corners at least.
        for j in range(m):  # pragma: no branch
            var c = self.polygons[q].vertices[j]
            var d = self.polygons[q].vertices[(j + 1) % m]
            var off_c = abs(_cross(a, b, c)) / length
            var off_d = abs(_cross(a, b, d)) / length
            if off_c > Float64(_ALONG) or off_d > Float64(_ALONG):
                continue
            var tc = _param(a, b, c)
            var td = _param(a, b, d)
            var lo = max(min(tc, td), 0.0)
            var hi = min(max(tc, td), 1.0)
            if (hi - lo) * length <= Float64(_ALONG):
                continue
            var pa = _lerp(a, b, lo)
            var pb = _lerp(a, b, hi)
            var qa = _lerp(c, d, _param(c, d, pa))
            var qb = _lerp(c, d, _param(c, d, pb))
            if abs(pa.z - qa.z) > _CLIMB or abs(pb.z - qb.z) > _CLIMB:
                continue
            best = (pa, pb, (hi - lo) * length)
        return best

    def polygon_count(self) -> Int:
        """Return how many polygons the mesh has.

        Returns:
            The count.
        """
        return len(self.polygons)

    def _check(self, id: NavPolygonId) raises -> Int:
        if not id.is_valid() or id.value < 0 or id.value >= len(self.polygons):
            raise Error("Navigation polygon id names no polygon")
        return id.value

    def area_of(self, id: NavPolygonId) raises -> NavArea:
        """Return a polygon's area kind.

        Args:
            id: The polygon.

        Returns:
            Its area.

        Raises:
            Error: If the id names no polygon.
        """
        return self.polygons[self._check(id)].area

    def closest_point_on_polygon(
        self, id: NavPolygonId, point: Vector3
    ) raises -> Vector3:
        """Return the point of a polygon nearest a point.

        Args:
            id: The polygon.
            point: The point.

        Returns:
            `NavPolygon.closest_point`.

        Raises:
            Error: If the id names no polygon.
        """
        return self.polygons[self._check(id)].closest_point(point)

    def find_nearest_polygon(
        self,
        center: Vector3,
        filter: NavQueryFilter,
        half_extents: Vector3 = Vector3(2, 2, 4),
    ) raises -> Optional[Tuple[NavPolygonId, Vector3]]:
        """Return the usable polygon nearest a point, and its nearest point.

        Args:
            center: The point.
            filter: Which polygons may be used.
            half_extents: How far to look: across in x and y, and up and
                down in z. CARLA's query box is 2 m across and 4 m up.

        Returns:
            The polygon whose nearest point is closest, the lowest id on a
            tie, and that point; None if no polygon is in the box. Over a
            polygon, the distance is the height left after a climb of
            0.5 m, as a walker steps down a curb.

        Raises:
            Error: Never in practice; a grid lookup raises only on a
                missing key.
        """
        var best = Optional[Tuple[NavPolygonId, Vector3]](None)
        var best_d = Float64.MAX
        var flat = Vector3(half_extents.x, half_extents.y, 0)
        for p in self._near(center - flat, center + flat):
            if not filter.passes(self.polygons[p].flags):
                continue
            var c = self.polygons[p].closest_point(center)
            if (
                abs(c.x - center.x) > half_extents.x
                or abs(c.y - center.y) > half_extents.y
                or abs(c.z - center.z) > half_extents.z
            ):
                continue
            var d = _distance(c, center)
            if self.polygons[p].contains(center):
                # Over the polygon, a step within the climb is no distance.
                d = max(
                    abs(Float64(c.z) - Float64(center.z)) - Float64(_CLIMB), 0.0
                )
            if d < best_d:
                best_d = d
                best = (NavPolygonId(p), c)
        return best

    def find_path(
        self,
        start: NavPolygonId,
        end: NavPolygonId,
        start_point: Vector3,
        end_point: Vector3,
        filter: NavQueryFilter,
        max_polygons: Int = MAX_POLYS,
    ) raises -> List[NavPolygonId]:
        """Return the polygons of the cheapest route, A* over the polygons.

        Args:
            start: The polygon at the start.
            end: The polygon at the goal.
            start_point: The start.
            end_point: The goal.
            filter: Which polygons may be used, and their costs.
            max_polygons: The most polygons to return, from the start.

        Returns:
            The polygons from the start to the goal, or to the polygon
            nearest the goal when the goal cannot be reached.

        Raises:
            Error: If an id names no polygon, an area cost is invalid,
                or a search score is NaN.
        """
        var s = self._check(start)
        var e = self._check(end)
        var nodes = List[_SearchNode]()
        # The mesh has the start polygon, checked above.
        for _ in range(len(self.polygons)):  # pragma: no branch
            nodes.append(_SearchNode())
        nodes[s].position = start_point
        nodes[s].heuristic = _distance(start_point, end_point)
        nodes[s].total = nodes[s].heuristic
        nodes[s].open = True
        var best = s
        var open = _MinCostQueue()
        open.push(nodes[s].total, s)
        while len(open) > 0:
            var entry = open.pop()
            var current = entry[1]
            # A cheaper route can supersede a queued score. Closed nodes
            # can reopen, so check both membership and the current score.
            if not nodes[current].open or entry[0] != nodes[current].total:
                continue
            nodes[current].open = False
            nodes[current].closed = True
            if current == e:
                best = e
                break
            var here = nodes[current].position
            var cost_here = filter.area_cost(self.polygons[current].area)
            for portal in self.polygons[current].portals:
                var n = portal.neighbor
                if not filter.passes(self.polygons[n].flags):
                    continue
                var mid = _lerp(portal.a, portal.b, 0.5)
                var cost = (
                    nodes[current].cost + _distance(here, mid) * cost_here
                )
                var heuristic = _distance(mid, end_point)
                if n == e:
                    cost += heuristic * filter.area_cost(self.polygons[n].area)
                    heuristic = 0.0
                if (nodes[n].open or nodes[n].closed) and cost >= nodes[n].cost:
                    continue
                nodes[n].cost = cost
                nodes[n].heuristic = heuristic
                nodes[n].total = cost + heuristic
                nodes[n].parent = current
                nodes[n].position = mid
                nodes[n].open = True
                nodes[n].closed = False
                open.push(nodes[n].total, n)
                if heuristic < nodes[best].heuristic:
                    best = n
        var reversed = List[Int]()
        var at = best
        while at >= 0:
            reversed.append(at)
            at = nodes[at].parent
        var out = List[NavPolygonId]()
        # The path holds the start at least.
        for i in range(len(reversed) - 1, -1, -1):  # pragma: no branch
            if len(out) == max_polygons:
                break
            out.append(NavPolygonId(reversed[i]))
        return out^

    def _portal(self, a: Int, b: Int) raises -> Tuple[Vector3, Vector3]:
        # The left and right ends of the portal from a to b, as a walker
        # going from a into b sees them.
        for portal in self.polygons[a].portals:
            if portal.neighbor == b:
                return (portal.b, portal.a)
        raise Error("Two polygons of the path are not neighbors")

    def find_straight_path(
        self,
        start: Vector3,
        end: Vector3,
        path: List[NavPolygonId],
        max_points: Int = MAX_POLYS,
        margin: Length = Length(0, METER),
    ) raises -> List[NavPoint]:
        """Pull a polygon path tight with the funnel algorithm.

        Args:
            start: The start, inside the first polygon.
            end: The goal, inside the last polygon.
            path: The polygons, each a neighbor of the next.
            max_points: The most points to return.
            margin: How far to keep from each portal's ends: each portal
                shrinks by this at each end, or to its middle when it is
                shorter than twice this. A walker keeps its radius clear
                of the edges this way.

        Returns:
            The start, each corner, a point at each change of area kind,
            and the goal. A point carries the area of the polygon it
            enters; the goal carries the area of the point before it.

        Raises:
            Error: If the path is empty, an id names no polygon, or two
                polygons in a row are not neighbors.
        """
        if len(path) == 0:
            raise Error("A straight path needs a polygon path")
        var polys = List[Int]()
        # Not empty, checked above.
        for p in path:  # pragma: no branch
            polys.append(self._check(p))
        var n = len(polys)
        var lefts = List[Vector3]()
        var rights = List[Vector3]()
        lefts.append(start)
        rights.append(start)
        for k in range(1, n):
            var portal = self._portal(polys[k - 1], polys[k])
            var length = _distance_2d(portal[0], portal[1])
            var cut = min(Float64(margin.value) / length, 0.5)
            lefts.append(_lerp(portal[0], portal[1], cut))
            rights.append(_lerp(portal[1], portal[0], cut))
        lefts.append(end)
        rights.append(end)
        # The corners, each with the index of the portal it lies on.
        var corners = List[Tuple[Vector3, Int]]()
        corners.append((start, 0))
        var apex = start
        var left = start
        var right = start
        var apex_i: Int
        var left_i = 0
        var right_i = 0
        var i = 1
        while i <= n:
            var l = lefts[i]
            var r = rights[i]
            if _cross(apex, right, r) >= 0.0:
                if apex == right or _cross(apex, left, r) < 0.0:
                    right = r
                    right_i = i
                else:
                    corners.append((left, left_i))
                    apex = left
                    apex_i = left_i
                    right = apex
                    right_i = apex_i
                    i = apex_i + 1
                    continue
            if _cross(apex, left, l) <= 0.0:
                if apex == left or _cross(apex, right, l) > 0.0:
                    left = l
                    left_i = i
                else:
                    corners.append((right, right_i))
                    apex = right
                    apex_i = right_i
                    left = apex
                    left_i = apex_i
                    i = apex_i + 1
                    continue
            i += 1
        corners.append((end, n))
        return self._with_crossings(corners, polys, lefts, rights, max_points)

    def _with_crossings(
        self,
        corners: List[Tuple[Vector3, Int]],
        polys: List[Int],
        lefts: List[Vector3],
        rights: List[Vector3],
        max_points: Int,
    ) -> List[NavPoint]:
        var out = List[NavPoint]()
        var n = len(polys)
        out.append(NavPoint(corners[0][0], self.polygons[polys[0]].area))
        # The corners hold the start and the goal at least.
        for c in range(1, len(corners)):  # pragma: no branch
            var a = corners[c - 1][0]
            var b = corners[c][0]
            for k in range(corners[c - 1][1] + 1, corners[c][1]):
                var before = self.polygons[polys[k - 1]].area
                var after = self.polygons[polys[k]].area
                if before == after:
                    continue
                var point = _intersect(a, b, lefts[k], rights[k])
                if _distance_2d(point, out[len(out) - 1].location) < _SAME:
                    out[len(out) - 1].area = after
                    continue
                out.append(NavPoint(point, after))
            var last = out[len(out) - 1]
            var area = last.area
            if corners[c][1] < n:
                area = self.polygons[polys[corners[c][1]]].area
            if _distance_2d(b, last.location) < _SAME:
                # The same place: the last point takes the new area.
                out[len(out) - 1].area = area
                continue
            out.append(NavPoint(b, area))
        while len(out) > max_points:
            _ = out.pop()
        return out^

    def find_random_point(
        self, filter: NavQueryFilter, mut random: SensorRandom
    ) -> Optional[Tuple[NavPolygonId, Vector3]]:
        """Return a random point of the usable polygons, uniform by area.

        Args:
            filter: Which polygons may be used.
            random: The generator. It draws four numbers.

        Returns:
            The polygon and the point, or None if no polygon may be used.
        """
        var total = 0.0
        for p in self.polygons:
            if filter.passes(p.flags):
                total += p.size
        if total == 0.0:
            return None
        var pick = Float64(random.uniform()) * total
        var chosen = -1
        # A polygon passed, so the mesh has one at least.
        for i in range(len(self.polygons)):  # pragma: no branch
            if filter.passes(self.polygons[i].flags):
                chosen = i
                pick -= self.polygons[i].size
                if pick < 0.0:
                    break
        ref poly = self.polygons[chosen]
        var fan = 0.0
        # A polygon has one fan triangle at least.
        for k in range(1, len(poly.vertices) - 1):  # pragma: no branch
            fan += _cross(
                poly.vertices[0], poly.vertices[k], poly.vertices[k + 1]
            )
        var t = Float64(random.uniform()) * fan
        var tri = 1
        # A polygon has one fan triangle at least.
        for k in range(1, len(poly.vertices) - 1):  # pragma: no branch
            tri = k
            t -= _cross(
                poly.vertices[0], poly.vertices[k], poly.vertices[k + 1]
            )
            if t < 0.0:
                break
        var u = Float64(random.uniform())
        var v = Float64(random.uniform())
        if u + v > 1.0:
            u = 1.0 - u
            v = 1.0 - v
        var a = poly.vertices[0]
        var b = poly.vertices[tri]
        var c = poly.vertices[tri + 1]
        var point = Vector3(
            Float32(
                Float64(a.x)
                + u * (Float64(b.x) - Float64(a.x))
                + v * (Float64(c.x) - Float64(a.x))
            ),
            Float32(
                Float64(a.y)
                + u * (Float64(b.y) - Float64(a.y))
                + v * (Float64(c.y) - Float64(a.y))
            ),
            Float32(
                Float64(a.z)
                + u * (Float64(b.z) - Float64(a.z))
                + v * (Float64(c.z) - Float64(a.z))
            ),
        )
        return (NavPolygonId(chosen), point)


def _intersect(a: Vector3, b: Vector3, p: Vector3, q: Vector3) -> Vector3:
    # Where segment a-b crosses the line of portal p-q, as a point of the
    # portal, in the x-y plane.
    var denom = _cross(Vector3(0, 0, 0), b - a, q - p)
    if denom == 0.0:
        return _lerp(p, q, 0.5)
    var t = _cross(Vector3(0, 0, 0), p - a, b - a) / denom
    return _lerp(p, q, min(max(t, 0.0), 1.0))


# --- building from a map -------------------------------------------------------------------


comptime _ROAD_LANES = (
    LANE_DRIVING.value
    | LANE_STOP.value
    | LANE_SHOULDER.value
    | LANE_BIKING.value
    | LANE_RESTRICTED.value
    | LANE_PARKING.value
    | LANE_BIDIRECTIONAL.value
    | LANE_ENTRY.value
    | LANE_EXIT.value
    | LANE_OFF_RAMP.value
    | LANE_ON_RAMP.value
)


def crosswalk_outlines(map: Map) raises -> List[List[Vector3]]:
    """Split the map's crosswalk corners into outlines.

    An outline closes where a corner repeats its first; the repeat is
    dropped. Corners left over at the end make one more outline.

    Args:
        map: The map.

    Returns:
        The outlines, in CARLA's frame.

    Raises:
        Error: If `Map.all_crosswalk_zones` does.
    """
    var out = List[List[Vector3]]()
    var current = List[Vector3]()
    for p in map.all_crosswalk_zones():
        if len(current) >= 3 and p == current[0]:
            out.append(current^)
            current = List[Vector3]()
        else:
            current.append(p)
    if len(current) >= 3:
        out.append(current^)
    return out^


def _cuts(map: Map, road: Int) -> List[Float64]:
    # The s of each crosswalk's two ends along a road.
    var out = List[Float64]()
    for cw in map.roads[road].info.crosswalks:
        # With no corner, the two cuts fall off the road and are dropped.
        var h = cw.heading
        var lo = Float64.MAX
        var hi = -Float64.MAX
        # The parser gives every crosswalk its outline.
        for p in cw.points:  # pragma: no branch
            var u = p.u - 1.0 if p.u < 0.0 else p.u + 1.0
            var along = -cw.t * sin(h) + u * cos(h) + p.v * sin(h)
            lo = min(lo, along)
            hi = max(hi, along)
        out.append(cw.s + lo)
        out.append(cw.s + hi)
    return out^


def _stations(
    start: Float64, end: Float64, step: Float64, cuts: List[Float64]
) -> List[Float64]:
    var all = List[Float64]()
    var s = start + EPSILON
    while s < end - EPSILON:
        all.append(s)
        s += step
    all.append(end - EPSILON)
    for c in cuts:
        if c > start + EPSILON and c < end - EPSILON:
            all.append(c)
    sort(all)
    var out = List[Float64]()
    # The end of the section is always a station.
    for v in all:  # pragma: no branch
        if len(out) == 0 or v - out[len(out) - 1] > _MERGE:
            out.append(v)
    return out^


def build_navigation_mesh(
    map: Map, resolution: Length = Length(2, METER)
) raises -> NavMesh:
    """Build the pedestrian mesh of a map.

    Args:
        map: The map.
        resolution: The longest strip along a lane.

    Returns:
        The mesh, connected.

    Raises:
        Error: If the resolution is not more than zero, or a map query
            fails.
    """
    if not (resolution.value > 0.0):
        raise Error("The mesh resolution must be more than zero")
    var mesh = NavMesh()
    var outlines = crosswalk_outlines(map)
    var step = Float64(resolution.value)
    for r in range(len(map.roads)):
        ref road = map.roads[r]
        var cuts = _cuts(map, r)
        # The parser gives every road a lane section.
        for sec in range(len(road.sections)):  # pragma: no branch
            var s0 = road.sections[sec].s
            var stations = _stations(
                s0, s0 + road.section_length(sec), step, cuts
            )
            # A lane section holds lane 0 at least.
            for ln in range(len(road.sections[sec].lanes)):  # pragma: no branch
                ref lane = road.sections[sec].lanes[ln]
                var sidewalk = lane.type == LANE_SIDEWALK
                if lane.id.value == 0 or not (
                    sidewalk or (lane.type.value & _ROAD_LANES) != 0
                ):
                    continue
                # A section's start and end are two stations.
                for k in range(len(stations) - 1):  # pragma: no branch
                    var a = road.lane_corners(sec, ln, stations[k])
                    var b = road.lane_corners(sec, ln, stations[k + 1])
                    var quad = List[Vector3]()
                    quad.append(a[0])
                    quad.append(a[1])
                    quad.append(b[1])
                    quad.append(b[0])
                    if abs(_signed_area(quad)) < 1e-6:
                        continue
                    var area = AREA_SIDEWALK
                    if not sidewalk:
                        area = AREA_ROAD
                        var mid = (a[0] + a[1] + b[0] + b[1]) * Float32(0.25)
                        for outline in outlines:
                            if point_in_polygon(mid, outline):
                                area = AREA_CROSSWALK
                    _ = mesh.add_polygon(quad^, area)
    mesh.connect()
    return mesh^
