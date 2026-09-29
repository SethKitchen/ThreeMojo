# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's global route planner: a lane graph and an A* search on it.

`GlobalRoutePlanner` turns the map's topology into a directed graph and
finds routes on it.

1. **Topology.** Each pair of the map's topology is a lane piece from an
   entry waypoint to an exit waypoint. The planner samples the piece every
   `sampling_resolution`, and stops one resolution short of the exit.
2. **Graph.** Each entry and exit location, rounded to whole meters, is a
   node. Each piece is an edge whose weight is its number of samples plus
   one. An edge keeps the forward vectors at its ends, the unit vector
   from its entry to its exit, and whether it is in a junction.
3. **Loose ends.** A piece whose exit lane starts no piece gets an extra
   edge along the rest of that lane, to a node with a negative id.
4. **Lane changes.** Where a mark lets a vehicle cross to a driving lane
   of the same road, an edge of weight zero joins the piece's entry to
   the start of the piece beside it. Each piece gets one such edge at
   most on each side.

`trace_route` finds the nodes of the origin's and the destination's
lane pieces, runs A* between them, and walks the edges. The heuristic is
the straight distance between node locations. It adds the samples of
each lane-follow edge. A lane-change edge adds the current waypoint and a
waypoint five samples along the new lane.

Each step of the route gets a road option. An edge that enters a
junction from outside one is a turn. The planner compares the forward
vector at the end of the edge before the junction with the one at the
end of the junction's last edge. Within 35 degrees the turn is straight.
Otherwise it is left or right, judged against the other ways out of the
same node. The edges inside the junction keep the decision.

The source is CARLA's `PythonAPI/carla/agents/navigation/
global_route_planner.py`. The search and the cases where the Python
fails follow CARLA's C++ port, `LibCarla/source/carla/agents/navigation/
GlobalRoutePlanner.cpp`:

- The A* search pops the lowest cost first and, of equal costs, the
  lowest node id. With no route, the search gives no nodes and the trace
  is empty.
- A piece whose first sample fails keeps an empty path.
- An undecided turn is `OPTION_VOID`.
- The side edges of a turn with no chord vector are left out.

The Python rounds with numpy's `round`, which rounds a half to even.
This port does the same.
"""

from extensions.carla.agents_local_planner import PlanItem, plan_item
from extensions.carla.agents_misc import (
    OPTION_CHANGE_LANE_LEFT,
    OPTION_CHANGE_LANE_RIGHT,
    OPTION_LANE_FOLLOW,
    OPTION_LEFT,
    OPTION_RIGHT,
    OPTION_STRAIGHT,
    OPTION_VOID,
    RoadOption,
)
from extensions.carla.map import Map, Waypoint
from extensions.carla.road_info import CHANGE_LEFT, CHANGE_RIGHT, LANE_DRIVING
from math.vector3 import Vector3
from std.ffi import external_call
from std.math import floor, sqrt
from units.si import DEGREE, METER, RADIAN, Angle, Length

# `math.radians(35)`.
comptime _THRESHOLD = 35.0 * 3.14159265358979323846 / 180.0
comptime _INT32_MIN = -2147483648
comptime _INT32_MAX = 2147483647


@fieldwise_init
struct RouteNodeId(Equatable, ImplicitlyCopyable, Writable):
    """A node of the route graph. Locations are numbered from 0 in the
    order they are met; loose ends are numbered -1, -2 and so on."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this fits CARLA's `int` node id.

        Returns:
            Whether the value is a 32-bit signed integer.
        """
        return self.value >= _INT32_MIN and self.value <= _INT32_MAX


struct RouteEdge(Copyable, Movable):
    """An edge of the route graph, with CARLA's edge attributes."""

    var source: RouteNodeId
    var target: RouteNodeId
    # The number of samples plus one; zero for a lane change.
    var length: Int
    var path: List[Waypoint]
    var entry_waypoint: Waypoint
    var exit_waypoint: Waypoint
    var entry_vector: Optional[Vector3]
    var exit_vector: Optional[Vector3]
    var net_vector: Optional[Vector3]
    var intersection: Bool
    var type: RoadOption
    var change_waypoint: Optional[Waypoint]

    def __init__(
        out self,
        source: RouteNodeId,
        target: RouteNodeId,
        entry_waypoint: Waypoint,
        exit_waypoint: Waypoint,
    ):
        """Create an empty lane-follow edge.

        Args:
            source: The start node.
            target: The end node.
            entry_waypoint: Where the edge starts.
            exit_waypoint: Where it ends.
        """
        self.source = source
        self.target = target
        self.length = 0
        self.path = List[Waypoint]()
        self.entry_waypoint = entry_waypoint
        self.exit_waypoint = exit_waypoint
        self.entry_vector = None
        self.exit_vector = None
        self.net_vector = None
        self.intersection = False
        self.type = OPTION_LANE_FOLLOW
        self.change_waypoint = None


struct _Segment(Copyable, Movable):
    var entry: Waypoint
    var exit: Waypoint
    var entry_key: String
    var exit_key: String
    var entry_xyz: SIMD[DType.float64, 4]
    var exit_xyz: SIMD[DType.float64, 4]
    var path: List[Waypoint]

    def __init__(out self, entry: Waypoint, exit: Waypoint):
        self.entry = entry
        self.exit = exit
        self.entry_key = String()
        self.exit_key = String()
        self.entry_xyz = SIMD[DType.float64, 4](0)
        self.exit_xyz = SIMD[DType.float64, 4](0)
        self.path = List[Waypoint]()


struct _Node(Copyable, Movable):
    var id: RouteNodeId
    var vertex: SIMD[DType.float64, 4]
    # Indices into the edge list, in the order the edges were added.
    var out_edges: List[Int]

    def __init__(out self, id: RouteNodeId, vertex: SIMD[DType.float64, 4]):
        self.id = id
        self.vertex = vertex
        self.out_edges = List[Int]()


def round_half_even(value: Float64) -> Float64:
    """Round to a whole number, a half to the even neighbor, as numpy's
    `round` does.

    Args:
        value: The number.

    Returns:
        The nearest whole number, with -0 turned into 0.
    """
    var r = floor(value + 0.5)
    if r - value == 0.5 and floor(r / 2.0) * 2.0 != r:
        r -= 1.0
    return r + 0.0


def _xyz(location: Vector3) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](
        round_half_even(Float64(location.x)),
        round_half_even(Float64(location.y)),
        round_half_even(Float64(location.z)),
        0,
    )


def _key(xyz: SIMD[DType.float64, 4]) -> String:
    return String(xyz[0], ",", xyz[1], ",", xyz[2])


def _lane_key(w: Waypoint) -> String:
    return String(
        w.road_id.value, "/", w.section_id.value, "/", w.lane_id.value
    )


def _distance(a: Vector3, b: Vector3) -> Float64:
    # `Location.distance`: a single-precision length.
    return Float64(a.distance_to(b))


def _cross_z(a: Vector3, b: Vector3) -> Float64:
    return Float64(a.x) * Float64(b.y) - Float64(a.y) * Float64(b.x)


def turn_option(
    deviation: Angle,
    next_cross: Float64,
    crosses: List[Float64],
    threshold: Angle = Angle(35, DEGREE),
) -> RoadOption:
    """Name a turn into a junction, the last part of `_turn_decision`.

    Args:
        deviation: The angle between the heading before the junction and
            the heading at its end.
        next_cross: The z part of the cross product of the two headings:
            plus turns right in CARLA's frame.
        crosses: The same for the chord of each other way out of the
            junction's entry. CARLA puts a 0 in an empty list.
        threshold: The deviation below which the turn is straight.

    Returns:
        `OPTION_STRAIGHT` below the threshold; else `OPTION_LEFT` left of
        every other way and `OPTION_RIGHT` right of every one; else by the
        sign of the cross product; `OPTION_VOID` when it is zero.
    """
    var lowest = 0.0
    var highest = 0.0
    if len(crosses) > 0:
        lowest = crosses[0]
        highest = crosses[0]
    for c in crosses:
        lowest = min(lowest, c)
        highest = max(highest, c)
    if deviation.value < threshold.value:
        return OPTION_STRAIGHT
    if next_cross < lowest:
        return OPTION_LEFT
    if next_cross > highest:
        return OPTION_RIGHT
    if next_cross < 0.0:
        return OPTION_LEFT
    if next_cross > 0.0:
        return OPTION_RIGHT
    return OPTION_VOID


struct GlobalRoutePlanner(Movable):
    """CARLA's `GlobalRoutePlanner`: a route graph of a map."""

    var sampling_resolution: Length
    var _topology: List[_Segment]
    var _nodes: List[_Node]
    var _node_index: Dict[Int, Int]
    var _edges: List[RouteEdge]
    var _id_map: Dict[String, Int]
    var _road_id_to_edge: Dict[String, Tuple[Int, Int]]
    var _intersection_end_node: Int
    var _previous_decision: RoadOption

    def __init__(out self, map: Map, sampling_resolution: Length) raises:
        """Build the graph of a map, `GlobalRoutePlanner.__init__`.

        Args:
            map: The map.
            sampling_resolution: The spacing of the samples.

        Raises:
            Error: If the resolution is not more than zero, or a map query
                fails.
        """
        if not (sampling_resolution.value > 0.0):
            raise Error("The sampling resolution must be more than zero")
        self.sampling_resolution = sampling_resolution
        self._topology = List[_Segment]()
        self._nodes = List[_Node]()
        self._node_index = Dict[Int, Int]()
        self._edges = List[RouteEdge]()
        self._id_map = Dict[String, Int]()
        self._road_id_to_edge = Dict[String, Tuple[Int, Int]]()
        self._intersection_end_node = -1
        self._previous_decision = OPTION_VOID
        self._build_topology(map)
        self._build_graph(map)
        self._find_loose_ends(map)
        self._lane_change_link(map)

    # --- building ---------------------------------------------------------------

    def _resolution(self) -> Float64:
        return Float64(self.sampling_resolution.value)

    def _build_topology(mut self, map: Map) raises:
        var res = self._resolution()
        for pair in map.generate_topology():
            var segment = _Segment(pair[0], pair[1])
            var l1 = map.compute_transform(pair[0]).location
            var l2 = map.compute_transform(pair[1]).location
            segment.entry_xyz = _xyz(l1)
            segment.exit_xyz = _xyz(l2)
            segment.entry_key = _key(segment.entry_xyz)
            segment.exit_key = _key(segment.exit_xyz)
            var first = map.next(pair[0], res)
            if _distance(l1, l2) > res:
                # The exit is more than one resolution away along the lane,
                # so the first step stays on it.
                var w = first[0]
                while _distance(map.compute_transform(w).location, l2) > res:
                    segment.path.append(w)
                    var step = map.next(w, res)
                    if len(step) == 0:
                        break
                    w = step[0]
            else:
                if len(first) == 0:
                    continue
                segment.path.append(first[0])
            self._topology.append(segment^)

    def _node_of(mut self, key: String, xyz: SIMD[DType.float64, 4]) -> Int:
        var found = self._id_map.get(key)
        if Bool(found):
            return found.value()
        var id = len(self._id_map)
        self._id_map[key] = id
        self._node_index[id] = len(self._nodes)
        self._nodes.append(_Node(RouteNodeId(id), xyz))
        return id

    def _add_edge(
        mut self, n1: Int, n2: Int, entry: Waypoint, exit: Waypoint
    ) raises -> Int:
        # A second edge between the same nodes updates the first, as a
        # directed graph keeps one edge per pair.
        var e = self._find_edge(n1, n2)
        if e >= 0:
            self._edges[e].entry_waypoint = entry
            self._edges[e].exit_waypoint = exit
            return e
        self._edges.append(
            RouteEdge(RouteNodeId(n1), RouteNodeId(n2), entry, exit)
        )
        var index = len(self._edges) - 1
        self._nodes[self._node_index[n1]].out_edges.append(index)
        return index

    def _find_edge(self, n1: Int, n2: Int) -> Int:
        var at = self._node_index.get(n1)
        if not Bool(at):
            return -1
        for e in self._nodes[at.value()].out_edges:
            if self._edges[e].target.value == n2:
                return e
        return -1

    def _edge_index(self, n1: Int, n2: Int) raises -> Int:
        var e = self._find_edge(n1, n2)
        if e < 0:
            raise Error("The graph has no such edge")
        return e

    def _build_graph(mut self, map: Map) raises:
        for s in range(len(self._topology)):
            var entry = self._topology[s].entry
            var exit = self._topology[s].exit
            var entry_key = self._topology[s].entry_key
            var exit_key = self._topology[s].exit_key
            var n1 = self._node_of(entry_key, self._topology[s].entry_xyz)
            var n2 = self._node_of(exit_key, self._topology[s].exit_xyz)
            self._road_id_to_edge[_lane_key(entry)] = (n1, n2)
            var t1 = map.compute_transform(entry)
            var t2 = map.compute_transform(exit)
            var e = self._add_edge(n1, n2, entry, exit)
            ref edge = self._edges[e]
            edge.length = len(self._topology[s].path) + 1
            edge.path = self._topology[s].path.copy()
            edge.entry_vector = t1.rotation.forward_vector()
            edge.exit_vector = t2.rotation.forward_vector()
            var chord = t2.location - t1.location
            edge.net_vector = chord / chord.length()
            edge.intersection = map.is_junction(entry.road_id)
            edge.type = OPTION_LANE_FOLLOW

    def _find_loose_ends(mut self, map: Map) raises:
        var count = 0
        var res = self._resolution()
        for s in range(len(self._topology)):
            var end = self._topology[s].exit
            var key = _lane_key(end)
            if key in self._road_id_to_edge:
                continue
            count += 1
            var n1 = self._id_map[self._topology[s].exit_key]
            var n2 = -count
            self._road_id_to_edge[key] = (n1, n2)
            var path = List[Waypoint]()
            var nexts = map.next(end, res)
            while (
                len(nexts) > 0
                and nexts[0].road_id == end.road_id
                and nexts[0].section_id == end.section_id
                and nexts[0].lane_id == end.lane_id
            ):
                var reached = nexts[0]
                path.append(reached)
                nexts = map.next(reached, res)
            if len(path) == 0:
                continue
            var tail = path[len(path) - 1]
            var at = map.compute_transform(tail).location
            self._node_index[n2] = len(self._nodes)
            self._nodes.append(
                _Node(
                    RouteNodeId(n2),
                    SIMD[DType.float64, 4](
                        Float64(at.x), Float64(at.y), Float64(at.z), 0
                    ),
                )
            )
            var e = self._add_edge(n1, n2, end, tail)
            ref edge = self._edges[e]
            edge.length = len(path) + 1
            edge.path = path^
            edge.intersection = map.is_junction(end.road_id)

    def _lane_change_link(mut self, map: Map) raises:
        for s in range(len(self._topology)):
            if map.is_junction(self._topology[s].entry.road_id):
                continue
            var left_found = False
            var right_found = False
            var source = self._id_map[self._topology[s].entry_key]
            for w in self._topology[s].path.copy():
                if left_found and right_found:
                    break
                if not right_found:
                    var mark = map.right_lane_marking(w)
                    if (
                        Bool(mark)
                        and (mark.value().lane_change & CHANGE_RIGHT).value != 0
                    ):
                        right_found = self._link(
                            map, source, w, map.right(w), True
                        )
                if not left_found:
                    var mark = map.left_lane_marking(w)
                    if (
                        Bool(mark)
                        and (mark.value().lane_change & CHANGE_LEFT).value != 0
                    ):
                        left_found = self._link(
                            map, source, w, map.left(w), False
                        )

    def _link(
        mut self,
        map: Map,
        source: Int,
        waypoint: Waypoint,
        side: Optional[Waypoint],
        right: Bool,
    ) raises -> Bool:
        if not Bool(side):
            return False
        var next = side.value()
        if not (
            map.lane_type(next) == LANE_DRIVING
            and waypoint.road_id == next.road_id
        ):
            return False
        var segment = self._localize(map, map.compute_transform(next).location)
        if not Bool(segment):
            return False
        var e = self._add_edge(source, segment.value()[0], waypoint, next)
        ref edge = self._edges[e]
        edge.intersection = False
        edge.exit_vector = None
        edge.path = List[Waypoint]()
        edge.length = 0
        edge.type = (
            OPTION_CHANGE_LANE_RIGHT if right else OPTION_CHANGE_LANE_LEFT
        )
        edge.change_waypoint = next
        return True

    # --- queries ----------------------------------------------------------------

    def node_count(self) -> Int:
        """Return how many nodes the graph has.

        Returns:
            The count, loose ends included.
        """
        return len(self._nodes)

    def edge_count(self) -> Int:
        """Return how many edges the graph has.

        Returns:
            The count.
        """
        return len(self._edges)

    def vertex(self, id: RouteNodeId) raises -> Vector3:
        """Return a node's location.

        Args:
            id: The node.

        Returns:
            Its rounded location, or a loose end's exact location.

        Raises:
            Error: If the id is not valid or names no node.
        """
        if not id.is_valid():
            raise Error("Route node id is not valid")
        var at = self._node_index.get(id.value)
        if not Bool(at):
            raise Error("The graph has no such node")
        var v = self._nodes[at.value()].vertex
        return Vector3(Float32(v[0]), Float32(v[1]), Float32(v[2]))

    def edge(self, n1: RouteNodeId, n2: RouteNodeId) raises -> RouteEdge:
        """Return the edge between two nodes.

        Args:
            n1: The start node.
            n2: The end node.

        Returns:
            A copy of the edge.

        Raises:
            Error: If an id is not valid, or there is no such edge.
        """
        if not (n1.is_valid() and n2.is_valid()):
            raise Error("Route node id is not valid")
        return self._edges[self._edge_index(n1.value, n2.value)].copy()

    def successors(self, id: RouteNodeId) raises -> List[RouteNodeId]:
        """Return the nodes an edge from a node leads to.

        Args:
            id: The node.

        Returns:
            The nodes, in the order their edges were added.

        Raises:
            Error: If `vertex` would.
        """
        _ = self.vertex(id)
        var out = List[RouteNodeId]()
        for e in self._nodes[self._node_index[id.value]].out_edges:
            out.append(self._edges[e].target)
        return out^

    def localize(
        self, map: Map, location: Vector3
    ) raises -> Optional[Tuple[RouteNodeId, RouteNodeId]]:
        """Return the edge of the lane piece under a point, `_localize`.

        Args:
            map: The map.
            location: The point.

        Returns:
            The start and end node, or None if the nearest driving lane
            has no piece.

        Raises:
            Error: If a map query fails.
        """
        var found = self._localize(map, location)
        if not Bool(found):
            return None
        return (RouteNodeId(found.value()[0]), RouteNodeId(found.value()[1]))

    def _localize(
        self, map: Map, location: Vector3
    ) raises -> Optional[Tuple[Int, Int]]:
        var w = map.closest_waypoint_on_road(location)
        if not Bool(w):
            return None
        return self._road_id_to_edge.get(_lane_key(w.value()))

    def _heuristic(self, a: Int, b: Int) raises -> Float64:
        var d = (
            self._nodes[self._node_index[a]].vertex
            - self._nodes[self._node_index[b]].vertex
        )
        return sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])

    def path_search(
        self, map: Map, origin: Vector3, destination: Vector3
    ) raises -> List[RouteNodeId]:
        """Find the nodes of a route, `_path_search`.

        Args:
            map: The map.
            origin: Where the route starts.
            destination: Where it ends.

        Returns:
            The nodes from the origin's piece to the destination's, then
            the end node of the destination's piece. Empty if a point has
            no piece or no route joins them.

        Raises:
            Error: If a map query fails.
        """
        var start = self._localize(map, origin)
        var end = self._localize(map, destination)
        var out = List[RouteNodeId]()
        if not (Bool(start) and Bool(end)):
            return out^
        out = self._search(start.value()[0], end.value()[0])
        if len(out) > 0:
            out.append(RouteNodeId(end.value()[1]))
        return out^

    def _search(self, source: Int, target: Int) raises -> List[RouteNodeId]:
        # A* with the straight-line heuristic. The open list holds
        # (cost, node) entries; the lowest cost comes out first, and of
        # equal costs the lowest node id. A node comes out once; a later
        # entry for it is skipped.
        var out = List[RouteNodeId]()
        var open = List[Tuple[Float64, Int]]()
        var g = Dict[Int, Float64]()
        var came_from = Dict[Int, Int]()
        var closed = Dict[Int, Bool]()
        g[source] = 0.0
        open.append((self._heuristic(source, target), source))
        while len(open) > 0:
            var best = 0
            for i in range(1, len(open)):
                if open[i][0] < open[best][0] or (
                    open[i][0] == open[best][0] and open[i][1] < open[best][1]
                ):
                    best = i
            var current = open.pop(best)[1]
            if current == target:
                var nodes = List[Int]()
                nodes.append(current)
                var n = current
                while n != source:
                    n = came_from[n]
                    nodes.append(n)
                # The list holds the target at least.
                for i in range(len(nodes) - 1, -1, -1):  # pragma: no branch
                    out.append(RouteNodeId(nodes[i]))
                return out^
            if current in closed:
                continue
            closed[current] = True
            var g_current = g[current]
            for e in self._nodes[self._node_index[current]].out_edges:
                var neighbor = self._edges[e].target.value
                var tentative = g_current + Float64(self._edges[e].length)
                var known = g.get(neighbor)
                if not Bool(known) or tentative < known.value():
                    g[neighbor] = tentative
                    came_from[neighbor] = current
                    open.append(
                        (
                            tentative + self._heuristic(neighbor, target),
                            neighbor,
                        )
                    )
        return out^

    def _successive_last_intersection_edge(
        self, index: Int, route: List[Int]
    ) -> Tuple[Int, Int]:
        var last_edge = -1
        var last_node = -1
        # The caller checked that `index` has a next node.
        for i in range(index, len(route) - 1):  # pragma: no branch
            var candidate = self._find_edge(route[i], route[i + 1])
            if candidate < 0:
                break
            if route[i] == route[index]:
                last_edge = candidate
            if (
                self._edges[candidate].type == OPTION_LANE_FOLLOW
                and self._edges[candidate].intersection
            ):
                last_edge = candidate
                last_node = route[i + 1]
            else:
                break
        return (last_node, last_edge)

    def turn_decision(
        mut self,
        index: Int,
        route: List[RouteNodeId],
        threshold: Angle = Angle(35, DEGREE),
    ) raises -> RoadOption:
        """Return the road option of one step of a route, `_turn_decision`.

        The planner remembers the last decision and the end of the last
        junction, so the steps inside a junction keep its turn.

        Args:
            index: The step: from `route[index]` to `route[index + 1]`.
            route: The nodes of the route.
            threshold: The deviation below which a turn is straight.

        Returns:
            The road option.

        Raises:
            Error: If the index has no next node.
        """
        if index < 0 or index + 1 >= len(route):
            raise Error("The route has no step at that index")
        var nodes = List[Int]()
        # The route has two nodes at least, checked above.
        for n in route:  # pragma: no branch
            nodes.append(n.value)
        return self._turn(index, nodes, Float64(threshold.to(DEGREE)))

    def _turn(
        mut self, index: Int, route: List[Int], threshold_degrees: Float64
    ) raises -> RoadOption:
        var current = route[index]
        var next = route[index + 1]
        var next_edge = self._find_edge(current, next)
        if next_edge < 0:
            self._previous_decision = OPTION_VOID
            return OPTION_VOID
        var decision: RoadOption
        if index == 0:
            decision = self._edges[next_edge].type
        elif (
            self._previous_decision != OPTION_VOID
            and self._intersection_end_node > 0
            and self._intersection_end_node != route[index - 1]
            and self._edges[next_edge].type == OPTION_LANE_FOLLOW
            and self._edges[next_edge].intersection
        ):
            decision = self._previous_decision
        else:
            self._intersection_end_node = -1
            # Every step but the last is an edge of the search.
            var current_edge = self._edge_index(route[index - 1], current)
            if not (
                self._edges[current_edge].type == OPTION_LANE_FOLLOW
                and not self._edges[current_edge].intersection
                and self._edges[next_edge].type == OPTION_LANE_FOLLOW
                and self._edges[next_edge].intersection
            ):
                decision = self._edges[next_edge].type
            else:
                var tail = self._successive_last_intersection_edge(index, route)
                self._intersection_end_node = tail[0]
                # The first step of the tail is `next_edge` itself.
                next_edge = tail[1]
                var cv_opt = self._edges[current_edge].exit_vector
                var nv_opt = self._edges[next_edge].exit_vector
                if not (Bool(cv_opt) and Bool(nv_opt)):
                    self._previous_decision = self._edges[next_edge].type
                    return self._edges[next_edge].type
                decision = self._compare(
                    current,
                    next,
                    cv_opt.value(),
                    nv_opt.value(),
                    threshold_degrees,
                )
        self._previous_decision = decision
        return decision

    def _compare(
        self,
        current: Int,
        next: Int,
        cv: Vector3,
        nv: Vector3,
        threshold_degrees: Float64,
    ) raises -> RoadOption:
        var crosses = List[Float64]()
        # `current` has the edge to `next` at least.
        var out_edges = self._nodes[self._node_index[current]].out_edges.copy()
        for e in out_edges:  # pragma: no branch
            ref select = self._edges[e]
            if (
                select.type == OPTION_LANE_FOLLOW
                and select.target.value != next
                and Bool(select.net_vector)
            ):
                crosses.append(_cross_z(cv, select.net_vector.value()))
        var cv_len = sqrt(
            Float64(cv.x) * Float64(cv.x)
            + Float64(cv.y) * Float64(cv.y)
            + Float64(cv.z) * Float64(cv.z)
        )
        var nv_len = sqrt(
            Float64(nv.x) * Float64(nv.x)
            + Float64(nv.y) * Float64(nv.y)
            + Float64(nv.z) * Float64(nv.z)
        )
        var cosine = (
            Float64(cv.x) * Float64(nv.x)
            + Float64(cv.y) * Float64(nv.y)
            + Float64(cv.z) * Float64(nv.z)
        ) / (cv_len * nv_len)
        cosine = min(max(cosine, -1.0), 1.0)
        return turn_option(
            Angle(Float32(external_call["acos", Float64](cosine)), RADIAN),
            _cross_z(cv, nv),
            crosses,
            Angle(Float32(threshold_degrees), DEGREE),
        )

    def _find_closest_in_list(
        self, map: Map, current: Waypoint, waypoints: List[Waypoint]
    ) raises -> Int:
        var at = map.compute_transform(current).location
        var min_distance = Float64.MAX
        var closest = -1
        for i in range(len(waypoints)):
            var d = _distance(map.compute_transform(waypoints[i]).location, at)
            if d < min_distance:
                min_distance = d
                closest = i
        return closest

    def trace_route(
        mut self, map: Map, origin: Vector3, destination: Vector3
    ) raises -> List[PlanItem]:
        """Return the waypoints of a route and their road options,
        `trace_route`.

        Args:
            map: The map the planner was built on.
            origin: Where the route starts.
            destination: Where it ends.

        Returns:
            The plan. Empty when no route joins the two points.

        Raises:
            Error: If a map query fails.
        """
        var out = List[PlanItem]()
        var nodes = self.path_search(map, origin, destination)
        var route = List[Int]()
        for n in nodes:
            route.append(n.value)
        var current_opt = map.closest_waypoint_on_road(origin)
        var destination_opt = map.closest_waypoint_on_road(destination)
        if len(route) < 2:
            return out^
        var current = current_opt.value()
        var target = destination_opt.value()
        var res = self._resolution()
        # The route has two nodes at least, checked above.
        for i in range(len(route) - 1):  # pragma: no branch
            var option = self._turn(i, route, 35.0)
            var e = self._find_edge(route[i], route[i + 1])
            if e < 0:
                continue
            # An edge is a lane follow or a lane change, never void.
            if self._edges[e].type != OPTION_LANE_FOLLOW:
                out.append(plan_item(map, current, option))
                # A lane change ends on a lane that starts a piece.
                var pair = self._road_id_to_edge[
                    _lane_key(self._edges[e].exit_waypoint)
                ]
                ref next_edge = self._edges[self._edge_index(pair[0], pair[1])]
                if len(next_edge.path) > 0:
                    var closest = self._find_closest_in_list(
                        map, current, next_edge.path
                    )
                    closest = min(len(next_edge.path) - 1, closest + 5)
                    current = next_edge.path[closest]
                else:
                    current = next_edge.exit_waypoint
                out.append(plan_item(map, current, option))
                continue
            var path = List[Waypoint]()
            path.append(self._edges[e].entry_waypoint)
            for w in self._edges[e].path:
                path.append(w)
            path.append(self._edges[e].exit_waypoint)
            var closest = self._find_closest_in_list(map, current, path)
            var last = len(route) - i <= 2
            # The path holds the entry and the exit at least.
            for k in range(closest, len(path)):  # pragma: no branch
                current = path[k]
                out.append(plan_item(map, current, option))
                var at = map.compute_transform(current).location
                if last and _distance(at, destination) < 2.0 * res:
                    break
                if (
                    last
                    and current.road_id == target.road_id
                    and current.section_id == target.section_id
                    and current.lane_id == target.lane_id
                    and closest > self._find_closest_in_list(map, target, path)
                ):
                    break
        return out^
