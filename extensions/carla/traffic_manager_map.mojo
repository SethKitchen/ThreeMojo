# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's map, CARLA's `InMemoryMap` and `SimpleWaypoint`.

The traffic manager drives on a graph of waypoints, not on the
OpenDRIVE map. `InMemoryMap.set_up` builds the graph once:

1. It reads the map's topology and makes a segment of each lane of a
   road section, keyed by (road, lane, section). It notes which junction
   roads are real: a junction road is real when two or more junction
   roads leave or enter the same side of a road.
2. It samples every driving lane each 5 m and keeps the lanes more than
   1 m wide.
3. Segment by segment, in the order of their keys, it sorts the
   waypoints the way the lane runs and adds waypoints where two are too
   far apart or turn too much. It links each waypoint to the next and
   gives it a geodesic grid id: a new id each 20 m.
4. It links the last waypoint of each segment to the first of each
   segment after it, and marks the lane changes the road markings allow.
5. It gives each waypoint a road option: straight, left or right through
   a junction, lane follow elsewhere, and road end where the graph ends.

A `SimpleWaypoint` is a node of the graph. The graph keeps its nodes in
a list, and a node names another by its index, a `SimpleWaypointIndex`.
A node's id, a `WaypointId`, is the same for two nodes at the same
place, as CARLA's waypoint hash is.

**The cache.** CARLA saves the graph to a binary file and loads it again
instead of building it. `save` and `load` use CARLA's layout, little
endian: a `uint32` count, then per node its id (`uint64`), road
(`uint32`), section (`uint32`), lane (`int32`), s (`float`), the count
and ids of the next nodes (`uint16`, `uint64` each), the same for the
previous ones, the left and right ids (`uint64`, 0 for none), the grid
id (`int32`), the junction flag (one byte) and the road option (one
byte).

**Differences from CARLA.**

- CARLA's waypoint id is a Boost hash of the road, section, lane and s,
  and the hash differs between Boost versions. Here the id counts the
  distinct places in the order the graph meets them, from 1.
- CARLA keeps the nodes in a Boost R-tree and leaves the order of a
  query's results open. Here the nodes are in `extensions.carla.rtree`'s
  tree, as zero-length segments, and a query lists the nearest first
  and ties in the order the nodes were made.
- Where a junction's end cannot be found, CARLA reads an empty list.
  Here the waypoint keeps its road option.
- A cast of a NaN angle to an integer is undefined in C++. It is zero
  here, as x86 gives.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/InMemoryMap.cpp`,
`SimpleWaypoint.cpp` and `CachedSimpleWaypoint.cpp`.
"""

from extensions.carla.map import Map, Waypoint
from extensions.carla.math import vector_angle
from extensions.carla.road_info import (
    CHANGE_BOTH,
    CHANGE_LEFT,
    CHANGE_RIGHT,
    JuncId,
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    SectionId,
)
from extensions.carla.rtree import SegmentCloudRtree
from extensions.carla.traffic_manager_constants import (
    MAP_RESOLUTION,
    MAX_GEODESIC_GRID_LENGTH,
    MAX_WPT_DISTANCE_SQUARED,
    MAX_WPT_RADIANS,
    MIN_LANE_WIDTH,
    STRAIGHT_DEG,
    DELTA,
    Z_DELTA,
)
from extensions.carla.transform import CarlaTransform
from math.bounds import Box3
from math.vector3 import Vector3
from std.collections import Dict, Optional, Set
from std.math import isnan
from std.memory import bitcast
from std.pathlib import Path
from units.si import DEGREE, Length, METER


# --- ids ------------------------------------------------------------------


@fieldwise_init
struct RoadOption(Equatable, ImplicitlyCopyable, Writable):
    """What a vehicle does at a waypoint, CARLA's `RoadOption`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of CARLA's eight options.

        Returns:
            Whether the value is from 0 to 7.
        """
        return self.value >= 0 and self.value <= 7


comptime ROAD_OPTION_VOID = RoadOption(0)
comptime ROAD_OPTION_LEFT = RoadOption(1)
comptime ROAD_OPTION_RIGHT = RoadOption(2)
comptime ROAD_OPTION_STRAIGHT = RoadOption(3)
comptime ROAD_OPTION_LANE_FOLLOW = RoadOption(4)
comptime ROAD_OPTION_CHANGE_LANE_LEFT = RoadOption(5)
comptime ROAD_OPTION_CHANGE_LANE_RIGHT = RoadOption(6)
comptime ROAD_OPTION_ROAD_END = RoadOption(7)


@fieldwise_init
struct SimpleWaypointIndex(Equatable, ImplicitlyCopyable, Writable):
    """A node of the traffic manager's graph: its index in
    `InMemoryMap.waypoints`. -1 names no node, as CARLA's null pointer."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a node's index or names none.

        Returns:
            Whether the value is -1 or more.
        """
        return self.value >= -1

    def is_some(self) -> Bool:
        """Return True if this names a node.

        Returns:
            Whether the value is 0 or more.
        """
        return self.value >= 0


comptime NO_SIMPLE_WAYPOINT = SimpleWaypointIndex(-1)


@fieldwise_init
struct WaypointId(Equatable, ImplicitlyCopyable, Writable):
    """A place's id, CARLA's `SimpleWaypoint::GetId`: 64 bits, 0 for
    none."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits CARLA's 64 bits.

        Returns:
            Whether the value is 0 or more.
        """
        return self.value >= 0


# --- one node ---------------------------------------------------------------


def distance_squared(a: Vector3, b: Vector3) -> Float32:
    """Return the squared distance between two points, CARLA's
    `Math::DistanceSquared`.

    Args:
        a: A point, in meters.
        b: Another point, in meters.

    Returns:
        The squared distance, in square meters, summed as CARLA sums it.
    """
    var dx = b.x - a.x
    var dy = b.y - a.y
    var dz = b.z - a.z
    return dx * dx + dy * dy + dz * dz


struct SimpleWaypoint(Copyable, Movable):
    """A node of the graph, CARLA's `SimpleWaypoint`."""

    var waypoint: Waypoint
    # The waypoint's pose, as CARLA's client waypoint caches it.
    var transform: CarlaTransform
    var id: WaypointId
    var next_waypoints: List[SimpleWaypointIndex]
    var previous_waypoints: List[SimpleWaypointIndex]
    var next_left_waypoint: SimpleWaypointIndex
    var next_right_waypoint: SimpleWaypointIndex
    var road_option: RoadOption
    var geodesic_grid_id: JuncId
    # Whether the traffic manager treats the node as in a junction.
    var is_junction: Bool
    # Whether the node's road is a junction road, and its junction.
    var road_is_junction: Bool
    var junction_id: JuncId
    # Whether traffic keeps right on the node's road.
    var is_rht: Bool

    def __init__(out self, map: Map, waypoint: Waypoint, id: WaypointId) raises:
        """Wrap a map waypoint, `SimpleWaypoint(waypoint)`.

        Args:
            map: The map the waypoint is on.
            waypoint: The waypoint.
            id: Its place's id.

        Raises:
            Error: If the waypoint is not on the map.
        """
        self.waypoint = waypoint
        self.transform = map.compute_transform(waypoint)
        self.id = id
        self.next_waypoints = List[SimpleWaypointIndex]()
        self.previous_waypoints = List[SimpleWaypointIndex]()
        self.next_left_waypoint = NO_SIMPLE_WAYPOINT
        self.next_right_waypoint = NO_SIMPLE_WAYPOINT
        self.road_option = ROAD_OPTION_VOID
        self.geodesic_grid_id = JuncId(0)
        self.is_junction = False
        ref road = map.road(waypoint.road_id)
        self.road_is_junction = road.is_junction
        self.junction_id = road.junction_id
        self.is_rht = road.is_rht

    def location(self) -> Vector3:
        """Return where the node is, `GetLocation`.

        Returns:
            The point, in meters.
        """
        return self.transform.location

    def forward_vector(self) -> Vector3:
        """Return the way the lane runs, `GetForwardVector`.

        Returns:
            A unit vector.
        """
        return self.transform.rotation.forward_vector()

    def get_geodesic_grid_id(self) -> JuncId:
        """Return the node's grid, `GetGeodesicGridId`.

        Returns:
            The junction's id on a junction road, else the grid id.
        """
        if self.road_is_junction:
            return self.junction_id
        return self.geodesic_grid_id

    def check_junction(self) -> Bool:
        """Return whether the node is in a real junction, `CheckJunction`.

        Returns:
            The junction flag.
        """
        return self.is_junction

    def check_intersection(self) -> Bool:
        """Return whether the graph forks here, `CheckIntersection`.

        Returns:
            Whether more than one node follows.
        """
        return len(self.next_waypoints) > 1

    def distance(self, location: Vector3) -> Float32:
        """Return the distance to a point, `Distance`.

        Args:
            location: The point, in meters.

        Returns:
            The distance, in meters.
        """
        return (location - self.location()).length()

    def distance_squared(self, location: Vector3) -> Float32:
        """Return the squared distance to a point, `DistanceSquared`.

        Args:
            location: The point, in meters.

        Returns:
            The squared distance, in square meters.
        """
        return distance_squared(self.location(), location)


# --- the cache record ---------------------------------------------------------


struct CachedSimpleWaypoint(Copyable, Movable):
    """One node as the cache file holds it, CARLA's
    `CachedSimpleWaypoint`."""

    var waypoint_id: Int
    var road_id: Int
    var section_id: Int
    var lane_id: Int
    var s: Float32
    var next_waypoints: List[Int]
    var previous_waypoints: List[Int]
    var next_left_waypoint: Int
    var next_right_waypoint: Int
    var geodesic_grid_id: Int
    var is_junction: Bool
    var road_option: Int

    def __init__(out self):
        """Create an empty record."""
        self.waypoint_id = 0
        self.road_id = 0
        self.section_id = 0
        self.lane_id = 0
        self.s = 0
        self.next_waypoints = List[Int]()
        self.previous_waypoints = List[Int]()
        self.next_left_waypoint = 0
        self.next_right_waypoint = 0
        self.geodesic_grid_id = 0
        self.is_junction = False
        self.road_option = 0

    def write(self, mut out: List[UInt8]):
        """Append the record in CARLA's layout, `Write`.

        Args:
            out: The bytes to append to.
        """
        _put(out, UInt64(self.waypoint_id), 8)
        _put(out, UInt64(self.road_id), 4)
        _put(out, UInt64(self.section_id), 4)
        _put(out, UInt64(self.lane_id) & 0xFFFFFFFF, 4)
        _put(out, UInt64(bitcast[DType.uint32](self.s)), 4)
        _put(out, UInt64(len(self.next_waypoints)), 2)
        for id in self.next_waypoints:
            _put(out, UInt64(id), 8)
        _put(out, UInt64(len(self.previous_waypoints)), 2)
        for id in self.previous_waypoints:
            _put(out, UInt64(id), 8)
        _put(out, UInt64(self.next_left_waypoint), 8)
        _put(out, UInt64(self.next_right_waypoint), 8)
        _put(out, UInt64(self.geodesic_grid_id) & 0xFFFFFFFF, 4)
        _put(out, UInt64(1 if self.is_junction else 0), 1)
        _put(out, UInt64(self.road_option), 1)

    def read(mut self, content: List[UInt8], mut start: Int) raises:
        """Read the record at an offset, `Read(content, start)`.

        Args:
            content: The bytes.
            start: Where the record starts. It moves past the record.

        Raises:
            Error: If the bytes end inside the record.
        """
        self.waypoint_id = Int(_get(content, start, 8))
        self.road_id = Int(_get(content, start, 4))
        self.section_id = Int(_get(content, start, 4))
        self.lane_id = _signed32(_get(content, start, 4))
        self.s = bitcast[DType.float32](UInt32(_get(content, start, 4)))
        var total_next = Int(_get(content, start, 2))
        for _ in range(total_next):
            self.next_waypoints.append(Int(_get(content, start, 8)))
        var total_previous = Int(_get(content, start, 2))
        for _ in range(total_previous):
            self.previous_waypoints.append(Int(_get(content, start, 8)))
        self.next_left_waypoint = Int(_get(content, start, 8))
        self.next_right_waypoint = Int(_get(content, start, 8))
        self.geodesic_grid_id = _signed32(_get(content, start, 4))
        self.is_junction = _get(content, start, 1) != 0
        self.road_option = Int(_get(content, start, 1))


def _put(mut out: List[UInt8], value: UInt64, size: Int):
    for k in range(size):  # pragma: no branch
        out.append(UInt8((value >> UInt64(8 * k)) & 0xFF))


def _get(content: List[UInt8], mut start: Int, size: Int) raises -> UInt64:
    if start + size > len(content):
        raise Error("The traffic manager's map cache ends too early")
    var value = UInt64(0)
    for k in range(size):  # pragma: no branch
        value |= UInt64(content[start + k]) << UInt64(8 * k)
    start += size
    return value


def _signed32(value: UInt64) -> Int:
    if value >= 0x80000000:
        return Int(value) - 0x100000000
    return Int(value)


# --- the graph ------------------------------------------------------------------


@fieldwise_init
struct _SegmentKey(ImplicitlyCopyable):
    var road: Int
    var lane: Int
    var section: Int

    def before(self, other: Self) -> Bool:
        if self.road != other.road:
            return self.road < other.road
        if self.lane != other.lane:
            return self.lane < other.lane
        return self.section < other.section

    def text(self) -> String:
        return String(self.road, ":", self.lane, ":", self.section)


def _segment_key(waypoint: Waypoint) -> _SegmentKey:
    return _SegmentKey(
        waypoint.road_id.value,
        waypoint.lane_id.value,
        waypoint.section_id.value,
    )


struct _Links(Copyable, Movable):
    var predecessors: List[_SegmentKey]
    var successors: List[_SegmentKey]

    def __init__(out self):
        self.predecessors = List[_SegmentKey]()
        self.successors = List[_SegmentKey]()


def to_int16(value: Float64) -> Int:
    """Return C++'s `static_cast<int16_t>` of a value in range.

    Args:
        value: The value.

    Returns:
        The value rounded toward zero; zero for a NaN, as x86 gives.
    """
    if isnan(value):
        return 0
    return Int(value)


def c_remainder(a: Int, b: Int) -> Int:
    """Return C++'s `a % b`, whose sign follows `a`.

    Args:
        a: The dividend.
        b: The divisor. It must not be zero.

    Returns:
        The remainder of a over b, with the quotient rounded toward
        zero.
    """
    var r = a % b
    if r != 0 and ((r < 0) != (a < 0)):
        r -= b
    return r


struct InMemoryMap(Movable):
    """The traffic manager's graph of waypoints, CARLA's `InMemoryMap`."""

    # CARLA's map name, which one check of the localization reads.
    var name: String
    var waypoints: List[SimpleWaypoint]
    var _tree: SegmentCloudRtree
    var _ids: Dict[Waypoint, Int]

    def __init__(out self, name: String = ""):
        """Create an empty graph.

        Args:
            name: The map's name, as CARLA's `Map::GetName` gives it.
        """
        self.name = name
        self.waypoints = List[SimpleWaypoint]()
        self._tree = SegmentCloudRtree()
        self._ids = Dict[Waypoint, Int]()

    # --- nodes ------------------------------------------------------------------

    def _check(self, index: SimpleWaypointIndex) raises -> Int:
        if not index.is_some() or index.value >= len(self.waypoints):
            raise Error("The index names no node of the traffic manager's map")
        return index.value

    def at(
        self, index: SimpleWaypointIndex
    ) raises -> ref[origin_of(self.waypoints[0])] SimpleWaypoint:
        """Return a node.

        Args:
            index: The node's index.

        Returns:
            The node.

        Raises:
            Error: If the index names no node.
        """
        return self.waypoints[self._check(index)]

    def size(self) -> Int:
        """Return how many nodes the graph has.

        Returns:
            The count.
        """
        return len(self.waypoints)

    def get_dense_topology(self) -> List[SimpleWaypointIndex]:
        """Return every node, `GetDenseTopology`.

        Returns:
            Their indices, in order.
        """
        var out = List[SimpleWaypointIndex]()
        for i in range(len(self.waypoints)):
            out.append(SimpleWaypointIndex(i))
        return out^

    def _id_of(mut self, waypoint: Waypoint) -> WaypointId:
        var found = self._ids.get(waypoint)
        if Bool(found):
            return WaypointId(found.value())
        var id = len(self._ids) + 1
        self._ids[waypoint] = id
        return WaypointId(id)

    def add_waypoint(
        mut self, map: Map, waypoint: Waypoint
    ) raises -> SimpleWaypointIndex:
        """Add a node for a map waypoint, unlinked.

        Args:
            map: The map.
            waypoint: The waypoint.

        Returns:
            The new node's index.

        Raises:
            Error: If the waypoint is not on the map.
        """
        var id = self._id_of(waypoint)
        self.waypoints.append(SimpleWaypoint(map, waypoint, id))
        return SimpleWaypointIndex(len(self.waypoints) - 1)

    def set_next_waypoints(
        mut self, index: SimpleWaypointIndex, nexts: List[SimpleWaypointIndex]
    ) raises -> Int:
        """Append nodes that follow a node, `SetNextWaypoint`.

        Args:
            index: The node.
            nexts: The nodes that follow it.

        Returns:
            How many were added.

        Raises:
            Error: If an index names no node.
        """
        var i = self._check(index)
        for n in nexts:
            _ = self._check(n)
            self.waypoints[i].next_waypoints.append(n)
        return len(nexts)

    def set_previous_waypoints(
        mut self,
        index: SimpleWaypointIndex,
        previous: List[SimpleWaypointIndex],
    ) raises -> Int:
        """Append nodes that lead to a node, `SetPreviousWaypoint`.

        Args:
            index: The node.
            previous: The nodes that lead to it.

        Returns:
            How many were added.

        Raises:
            Error: If an index names no node.
        """
        var i = self._check(index)
        for p in previous:
            _ = self._check(p)
            self.waypoints[i].previous_waypoints.append(p)
        return len(previous)

    def _side_cross(self, i: Int, other: Int) -> Float32:
        var heading = self.waypoints[i].transform.rotation.forward_vector()
        var relative = (
            self.waypoints[i].location() - self.waypoints[other].location()
        )
        return heading.x * relative.y - heading.y * relative.x

    def set_left_waypoint(
        mut self, index: SimpleWaypointIndex, left: SimpleWaypointIndex
    ) raises:
        """Link the node a vehicle can change left to, `SetLeftWaypoint`.

        The link is made only if the node is on the left, as the cross
        product of the heading and the offset says.

        Args:
            index: The node.
            left: The node on the lane to the left.

        Raises:
            Error: If an index names no node.
        """
        var i = self._check(index)
        var o = self._check(left)
        if self._side_cross(i, o) > 0.0:
            self.waypoints[i].next_left_waypoint = left

    def set_right_waypoint(
        mut self, index: SimpleWaypointIndex, right: SimpleWaypointIndex
    ) raises:
        """Link the node a vehicle can change right to, `SetRightWaypoint`.

        Args:
            index: The node.
            right: The node on the lane to the right.

        Raises:
            Error: If an index names no node.
        """
        var i = self._check(index)
        var o = self._check(right)
        if self._side_cross(i, o) < 0.0:
            self.waypoints[i].next_right_waypoint = right

    # --- building -----------------------------------------------------------------

    def set_up(mut self, map: Map) raises:
        """Build the graph from a map, `InMemoryMap::SetUp`.

        Args:
            map: The map.

        Raises:
            Error: If the graph is not empty, or a map query fails.
        """
        if len(self.waypoints) != 0:
            raise Error("The traffic manager's map is already built")
        # 1. The segments' topology, and which junction roads are real.
        var links = Dict[String, _Links]()
        var in_paths = Dict[Int, List[Int]]()
        var out_paths = Dict[Int, List[Int]]()
        var real_junction = Set[Int]()
        for pair in map.generate_topology():
            var waypoint = pair[0]
            var successor = pair[1]
            var key = _segment_key(waypoint)
            var next_key = _segment_key(successor)
            if key.text() == next_key.text():
                continue
            if key.text() not in links:
                links[key.text()] = _Links()
            if next_key.text() not in links:
                links[next_key.text()] = _Links()
            links[key.text()].successors.append(next_key)
            links[next_key.text()].predecessors.append(key)
            var waypoint_is_junction = map.is_junction(waypoint.road_id)
            var successor_is_junction = map.is_junction(successor.road_id)
            if waypoint_is_junction and not successor_is_junction:
                var std_road = successor.road_id.value
                if successor.lane_id.value < 0:
                    std_road = -std_road
                _add_path(
                    in_paths, real_junction, std_road, waypoint.road_id.value
                )
            if not waypoint_is_junction and successor_is_junction:
                var std_road = waypoint.road_id.value
                if waypoint.lane_id.value < 0:
                    std_road = -std_road
                _add_path(
                    out_paths, real_junction, std_road, successor.road_id.value
                )
        # 2. The samples, grouped by segment.
        var segments = Dict[String, List[SimpleWaypointIndex]]()
        var keys = List[_SegmentKey]()
        for w in map.generate_waypoints(Float64(MAP_RESOLUTION.value)):
            if map.lane_width_meters(w) > Float64(MIN_LANE_WIDTH.value):
                var key = _segment_key(w)
                if key.text() not in segments:
                    segments[key.text()] = List[SimpleWaypointIndex]()
                    keys.append(key)
                segments[key.text()].append(self.add_waypoint(map, w))
        _sort_keys(keys)
        # 3. Each segment, in the order of its key: sort it the way the
        # lane runs, fill its gaps, and give out the grid ids.
        var grid_counter = -1
        var dense = List[SimpleWaypointIndex]()
        for key in keys:
            grid_counter += 1
            var list = self._order_segment(map, segments[key.text()].copy())
            var edge = self.waypoints[list[0].value].location()
            for i in range(len(list) - 1):
                ref current = self.waypoints[list[i].value]
                if distance_squared(edge, current.location()) > (
                    MAX_GEODESIC_GRID_LENGTH.value
                    * MAX_GEODESIC_GRID_LENGTH.value
                ):
                    grid_counter += 1
                    edge = current.location()
                current.geodesic_grid_id = JuncId(grid_counter)
            self.waypoints[list[len(list) - 1].value].geodesic_grid_id = JuncId(
                grid_counter
            )
            # A segment has at least the sample that made it.
            for index in list:  # pragma: no branch
                ref swp = self.waypoints[index.value]
                if swp.road_is_junction and not (
                    swp.waypoint.road_id.value in real_junction
                ):
                    swp.is_junction = False
                else:
                    swp.is_junction = swp.road_is_junction
                dense.append(index)
            segments[key.text()] = list^
        # The nodes in CARLA's dense-topology order, and the segments
        # renumbered to match.
        self._reorder(dense)
        var remap = Dict[Int, Int]()
        for i in range(len(dense)):
            remap[dense[i].value] = i
        for key in keys:
            var fresh = List[SimpleWaypointIndex]()
            # A segment has at least the sample that made it.
            for index in segments[key.text()]:  # pragma: no branch
                fresh.append(SimpleWaypointIndex(remap[index.value]))
            segments[key.text()] = fresh^
        # The links inside each segment.
        for key in keys:
            var list = segments[key.text()].copy()
            for i in range(len(list) - 1):
                _ = self.set_next_waypoints(list[i], [list[i + 1]])
                _ = self.set_previous_waypoints(list[i + 1], [list[i]])
        self.set_up_spatial_tree()
        # 4. The links between segments.
        for key in keys:
            ref list = segments[key.text()]
            var successors = _neighbors(key, links, segments, True)
            var predecessors = _neighbors(key, links, segments, False)
            _ = self.set_previous_waypoints(list[0], predecessors)
            _ = self.set_next_waypoints(list[len(list) - 1], successors)
        # The lane changes.
        for i in range(len(self.waypoints)):
            if not self.waypoints[i].check_junction():
                self._find_and_link_lane_change(map, i)
        # Any node with nothing after it takes its neighbor's next nodes.
        for i in range(len(self.waypoints)):
            if len(self.waypoints[i].next_waypoints) != 0:
                continue
            var neighbor = self.waypoints[i].next_right_waypoint
            if not neighbor.is_some():
                neighbor = self.waypoints[i].next_left_waypoint
            if neighbor.is_some():
                var nexts = self.waypoints[neighbor.value].next_waypoints.copy()
                _ = self.set_next_waypoints(SimpleWaypointIndex(i), nexts)
                for n in nexts:
                    _ = self.set_previous_waypoints(n, [SimpleWaypointIndex(i)])
        # 5. The road options.
        self.set_up_road_option(map)

    def _order_segment(
        mut self, map: Map, var list: List[SimpleWaypointIndex]
    ) raises -> List[SimpleWaypointIndex]:
        # Sort by s: the samples of a lane come in order of s already, but
        # sort as CARLA does. Insertion sort, stable.
        for i in range(1, len(list)):
            var j = i
            while (
                j > 0
                and self.waypoints[list[j].value].waypoint.s
                < self.waypoints[list[j - 1].value].waypoint.s
            ):
                list.swap_elements(j, j - 1)
                j -= 1
        if not map.is_positive_direction(
            self.waypoints[list[0].value].waypoint
        ):
            list.reverse()
        # Add waypoints where two are too far apart or turn too much.
        var i = 0
        while i < len(list) - 1:
            ref a = self.waypoints[list[i].value]
            ref b = self.waypoints[list[i + 1].value]
            var distance = abs(a.waypoint.s - b.waypoint.s)
            var angle = vector_angle(a.forward_vector(), b.forward_vector())
            var angle_splits = to_int16(
                Float64(angle.value / MAX_WPT_RADIANS.value)
            )
            var distance_splits = to_int16(
                distance * distance / MAX_WPT_DISTANCE_SQUARED
            )
            var max_splits = max(angle_splits, distance_splits)
            for _ in range(max_splits):
                var nexts = map.next(
                    self.waypoints[list[i].value].waypoint,
                    distance / Float64(max_splits + 1),
                )
                if len(nexts) == 0:
                    break
                i += 1
                list.insert(i, self.add_waypoint(map, nexts[0]))
            i += 1
        return list^

    def _reorder(mut self, order: List[SimpleWaypointIndex]):
        var fresh = List[SimpleWaypoint]()
        for index in order:
            fresh.append(self.waypoints[index.value].copy())
        self.waypoints = fresh^

    def set_up_spatial_tree(mut self):
        """Index every node for the nearest-node queries,
        `SetUpSpatialTree`. A graph linked by hand needs this before a
        query."""
        self._tree = SegmentCloudRtree()
        for i in range(len(self.waypoints)):
            var at = self.waypoints[i].location()
            self._tree.insert_element(at, at, i, i)

    def _find_and_link_lane_change(mut self, map: Map, i: Int) raises:
        var raw = self.waypoints[i].waypoint
        var change = map.lane_change(raw)
        if change == CHANGE_RIGHT or change == CHANGE_BOTH:
            var right = map.right(raw)
            if self._can_change(map, raw, right):
                var closest = self.get_waypoint(
                    map.compute_transform(right.value()).location
                )
                self.set_right_waypoint(SimpleWaypointIndex(i), closest)
        if change == CHANGE_LEFT or change == CHANGE_BOTH:
            var left = map.left(raw)
            if self._can_change(map, raw, left):
                var closest = self.get_waypoint(
                    map.compute_transform(left.value()).location
                )
                self.set_left_waypoint(SimpleWaypointIndex(i), closest)

    def _can_change(
        self, map: Map, raw: Waypoint, side: Optional[Waypoint]
    ) raises -> Bool:
        if not Bool(side):
            return False
        var other = side.value()
        return (
            map.lane_type(other) == LANE_DRIVING
            and other.lane_id.value * raw.lane_id.value > 0
        )

    def set_up_road_option(mut self, map: Map) raises:
        """Give each node its road option, `SetUpRoadOption`.

        Args:
            map: The map, for the landmarks near a junction.

        Raises:
            Error: If a map query fails.
        """
        for i in range(len(self.waypoints)):
            var nexts = self.waypoints[i].next_waypoints.copy()
            var count = len(nexts)
            if count == 0:
                self.waypoints[i].road_option = ROAD_OPTION_ROAD_END
            elif count > 1 or (
                not self.waypoints[i].check_junction()
                and self.waypoints[nexts[0].value].check_junction()
            ):
                var found_landmark = False
                if count <= 1:
                    found_landmark = _junction_landmark(
                        map, self.waypoints[i].waypoint
                    )
                    if not found_landmark:
                        self.waypoints[i].road_option = ROAD_OPTION_LANE_FOLLOW
                if found_landmark or count > 1:
                    self.waypoints[i].road_option = ROAD_OPTION_LANE_FOLLOW
                    # A node with no next nodes took the first branch.
                    for n in nexts:  # pragma: no branch
                        self._assign_turn(n)
            elif self.waypoints[i].road_option == ROAD_OPTION_VOID:
                self.waypoints[i].road_option = ROAD_OPTION_LANE_FOLLOW

    def _assign_turn(mut self, start: SimpleWaypointIndex):
        var traversed = List[Int]()
        var end = start.value
        while self.waypoints[end].check_junction():
            traversed.append(end)
            if len(self.waypoints[end].next_waypoints) == 0:
                break
            end = self.waypoints[end].next_waypoints[0].value
        if len(traversed) == 0:
            return
        var current_angle = to_int16(
            Float64(self.waypoints[traversed[0]].transform.rotation.yaw)
        )
        var end_angle = to_int16(
            Float64(
                self.waypoints[
                    traversed[len(traversed) - 1]
                ].transform.rotation.yaw
            )
        )
        var diff = Float32(c_remainder(end_angle - current_angle, 360))
        var straight_deg = STRAIGHT_DEG.to(DEGREE)
        var straight = (
            (diff < straight_deg and diff > -straight_deg)
            or (diff > 360 - straight_deg and diff <= 360)
            or (diff < -360 + straight_deg and diff >= -360)
        )
        var right = (diff >= straight_deg and diff <= 180) or (
            diff <= -180 and diff >= -360 + straight_deg
        )
        var option = ROAD_OPTION_LEFT
        if straight:
            option = ROAD_OPTION_STRAIGHT
        elif right:
            option = ROAD_OPTION_RIGHT
        # An empty walk returned above.
        for t in traversed:  # pragma: no branch
            self.waypoints[t].road_option = option

    # --- queries ------------------------------------------------------------------

    def get_waypoint(self, location: Vector3) raises -> SimpleWaypointIndex:
        """Return the node nearest a point, `InMemoryMap::GetWaypoint`.

        Args:
            location: The point, in meters.

        Returns:
            The nearest node; of nodes as near, the first made.

        Raises:
            Error: If the graph is empty.
        """
        var found = self._tree.get_nearest_neighbours(location, 1)
        if len(found) == 0:
            raise Error("The traffic manager's map is empty")
        return SimpleWaypointIndex(found[0].start_value)

    def get_waypoints_in_delta(
        self, location: Vector3, n_points: Int, random_sample: Length
    ) raises -> List[SimpleWaypointIndex]:
        """Return nodes in a ring around a point, `GetWaypointsInDelta`.

        A node counts when it is strictly inside the square that reaches
        `random_sample` plus 25 m from the point in x and y, and not
        strictly inside the square that reaches `random_sample`, both
        500 m up and down, and it is not in a junction.

        Args:
            location: The ring's center, in meters.
            n_points: How many nodes to return at most.
            random_sample: The ring's inner half width.

        Returns:
            Up to `n_points` nodes, in the order they were made.

        Raises:
            Error: If `n_points` is negative.
        """
        if n_points < 0:
            raise Error("A node count must not be negative")
        var r = random_sample.value
        var outer = r + DELTA.value
        var low = Vector3(
            location.x - outer, location.y - outer, location.z - Z_DELTA.value
        )
        var high = Vector3(
            location.x + outer, location.y + outer, location.z + Z_DELTA.value
        )
        var inner_low = Vector3(
            location.x - r, location.y - r, location.z - Z_DELTA.value
        )
        var inner_high = Vector3(
            location.x + r, location.y + r, location.z + Z_DELTA.value
        )
        var out = List[SimpleWaypointIndex]()
        for element in self._tree.get_intersections(Box3(low, high)):
            if len(out) >= n_points:
                break
            var at = element.start
            if not _strictly_within(at, low, high):
                continue
            if _strictly_within(at, inner_low, inner_high):
                continue
            if self.waypoints[element.start_value].check_junction():
                continue
            out.append(SimpleWaypointIndex(element.start_value))
        return out^

    # --- the cache ------------------------------------------------------------------

    def save(self) -> List[UInt8]:
        """Return the graph in CARLA's cache layout, `Save`.

        Returns:
            The bytes.
        """
        var out = List[UInt8]()
        _put(out, UInt64(len(self.waypoints)), 4)
        for i in range(len(self.waypoints)):
            self._cached(i).write(out)
        return out^

    def _cached(self, i: Int) -> CachedSimpleWaypoint:
        ref swp = self.waypoints[i]
        var record = CachedSimpleWaypoint()
        record.waypoint_id = swp.id.value
        record.road_id = swp.waypoint.road_id.value
        record.section_id = swp.waypoint.section_id.value
        record.lane_id = swp.waypoint.lane_id.value
        record.s = Float32(swp.waypoint.s)
        for n in swp.next_waypoints:
            record.next_waypoints.append(self.waypoints[n.value].id.value)
        for p in swp.previous_waypoints:
            record.previous_waypoints.append(self.waypoints[p.value].id.value)
        if swp.next_left_waypoint.is_some():
            record.next_left_waypoint = self.waypoints[
                swp.next_left_waypoint.value
            ].id.value
        if swp.next_right_waypoint.is_some():
            record.next_right_waypoint = self.waypoints[
                swp.next_right_waypoint.value
            ].id.value
        record.geodesic_grid_id = swp.get_geodesic_grid_id().value
        record.is_junction = swp.is_junction
        record.road_option = swp.road_option.value
        return record^

    def save_file(self, path: String) raises:
        """Write the graph to a cache file, `Save(path)`.

        Args:
            path: The file.

        Raises:
            Error: If the file cannot be written.
        """
        Path(path).write_bytes(self.save())

    def load(mut self, map: Map, content: List[UInt8]) raises -> Bool:
        """Rebuild the graph from CARLA's cache layout, `Load`.

        Each node's waypoint comes from its road, lane and s. A node whose
        id is repeated links to the last node with that id.

        Args:
            map: The map the cache was made from.
            content: The bytes.

        Returns:
            True, as CARLA's.

        Raises:
            Error: If the graph is not empty, the bytes end too early, a
                record's place is not on the map, a road option is not
                valid, or a link names an id no record has.
        """
        if len(self.waypoints) != 0:
            raise Error("The traffic manager's map is already built")
        var pos = 0
        var total = Int(_get(content, pos, 4))
        var records = List[CachedSimpleWaypoint]()
        var id_to_index = Dict[Int, Int]()
        for i in range(total):
            var record = CachedSimpleWaypoint()
            record.read(content, pos)
            var option = RoadOption(record.road_option)
            if not option.is_valid():
                raise Error("A cached road option is not valid")
            var found = map.waypoint_xodr(
                RoadId(record.road_id),
                LaneId(record.lane_id),
                Length(record.s, METER),
            )
            if not Bool(found):
                raise Error("A cached waypoint is not on the map")
            var index = self.add_waypoint(map, found.value())
            ref swp = self.waypoints[index.value]
            swp.geodesic_grid_id = JuncId(record.geodesic_grid_id)
            swp.is_junction = record.is_junction
            swp.road_option = option
            id_to_index[record.waypoint_id] = i
            records.append(record^)
        for i in range(len(records)):
            var nexts = List[SimpleWaypointIndex]()
            for id in records[i].next_waypoints:
                nexts.append(_lookup(id_to_index, id))
            var previous = List[SimpleWaypointIndex]()
            for id in records[i].previous_waypoints:
                previous.append(_lookup(id_to_index, id))
            _ = self.set_next_waypoints(SimpleWaypointIndex(i), nexts)
            _ = self.set_previous_waypoints(SimpleWaypointIndex(i), previous)
            if records[i].next_left_waypoint > 0:
                self.set_left_waypoint(
                    SimpleWaypointIndex(i),
                    _lookup(id_to_index, records[i].next_left_waypoint),
                )
            if records[i].next_right_waypoint > 0:
                self.set_right_waypoint(
                    SimpleWaypointIndex(i),
                    _lookup(id_to_index, records[i].next_right_waypoint),
                )
        self.set_up_spatial_tree()
        return True

    def load_file(mut self, map: Map, path: String) raises -> Bool:
        """Rebuild the graph from a cache file.

        Args:
            map: The map the cache was made from.
            path: The file.

        Returns:
            True, as CARLA's.

        Raises:
            Error: If the file cannot be read, or `load` fails.
        """
        var bytes = Path(path).read_bytes()
        var content = List[UInt8]()
        for b in bytes:
            content.append(b)
        return self.load(map, content)


def cook(map: Map, name: String = "") raises -> List[UInt8]:
    """Build a map's graph and return its cache, `InMemoryMap::Cook`.

    Args:
        map: The map.
        name: The map's name.

    Returns:
        The cache's bytes.

    Raises:
        Error: If `set_up` fails.
    """
    var local = InMemoryMap(name)
    local.set_up(map)
    return local.save()


def _lookup(ids: Dict[Int, Int], id: Int) raises -> SimpleWaypointIndex:
    var found = ids.get(id)
    if not Bool(found):
        raise Error("A cached link names no cached waypoint")
    return SimpleWaypointIndex(found.value())


def _strictly_within(p: Vector3, low: Vector3, high: Vector3) -> Bool:
    return (
        low.x < p.x
        and p.x < high.x
        and low.y < p.y
        and p.y < high.y
        and low.z < p.z
        and p.z < high.z
    )


def _add_path(
    mut paths: Dict[Int, List[Int]],
    mut real_junction: Set[Int],
    std_road: Int,
    path: Int,
) raises:
    if std_road not in paths:
        paths[std_road] = List[Int]()
    ref list = paths[std_road]
    if path not in list:
        list.append(path)
    if len(list) >= 2:
        for p in list:  # pragma: no branch
            real_junction.add(p)


def _sort_keys(mut keys: List[_SegmentKey]):
    for i in range(1, len(keys)):
        var j = i
        while j > 0 and keys[j].before(keys[j - 1]):
            keys.swap_elements(j, j - 1)
            j -= 1


def _neighbors(
    key: _SegmentKey,
    links: Dict[String, _Links],
    segments: Dict[String, List[SimpleWaypointIndex]],
    successors: Bool,
) raises -> List[SimpleWaypointIndex]:
    """CARLA's `GetSuccessors` and `GetPredecessors`: the first node of
    each segment after (the last of each before), through segments that
    have no nodes."""
    var out = List[SimpleWaypointIndex]()
    var found = links.get(key.text())
    if not Bool(found):
        return out^
    var others = (
        found.value()
        .successors.copy() if successors else found.value()
        .predecessors.copy()
    )
    for other in others:
        var list = segments.get(other.text())
        if not Bool(list):
            out.extend(_neighbors(other, links, segments, successors))
        elif successors:
            out.append(list.value()[0])
        else:
            out.append(list.value()[len(list.value()) - 1])
    return out^


def _junction_landmark(map: Map, waypoint: Waypoint) raises -> Bool:
    """Whether a light, a stop sign or a yield sign is within 15 m."""
    for landmark in map.landmarks_in_distance(waypoint, 15.0):
        var type = map.signal(landmark.reference.signal_id).type
        if type == "1000001" or type == "206" or type == "205":
            return True
    return False
