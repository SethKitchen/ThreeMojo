# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's localization stage, CARLA's `LocalizationStage`.

Each step, each vehicle's path (its buffer) is brought up to date:

1. A path whose first node is more than 20 m away is dropped. The nodes
   behind the vehicle are dropped.
2. The vehicle is at a junction's entrance when its first node is not in
   a junction and the node 5 m on is, or when it has just entered one.
3. Past the horizon, the speed times 2 s (4 s above 60 km/h) and at
   least 15 m, the far end is cut back, but not into a junction.
4. A lane change is chosen: a forced one, a random one, a keep-right
   one, or, with auto lane change on, one around a slower vehicle ahead
   in the lane with a free lane beside it. The path then restarts in
   the new lane, a speed-dependent 5 m to 20 m on.
5. The path grows to the horizon: along an imported path, along an
   imported route, or through random choices at forks.
6. At a junction's entrance, the path grows past the junction to the
   first node 4 m clear of it, the safe point. A bus or a truck notes
   the length of its turn for the wide-turn offset.

The random draws are CARLA's, in CARLA's order: three for the lane
changes above 5 m/s (keep right, right, left), one more when both
lane changes win, and one at each fork.

**Differences from CARLA.** Where CARLA reads past the end of an empty
list, which is undefined, this port raises an error, stops the walk, or
uses the path's first node, as each docstring says. Graph walks stop at
repeated waypoints. A path never adds a place it already contains.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/LocalizationStage.cpp`.
"""

from extensions.carla.actor import ActorId, NO_ACTOR
from extensions.carla.traffic_manager_constants import (
    FIFTYPERC,
    HIGH_SPEED_HORIZON_RATE,
    HIGHWAY_SPEED,
    HORIZON_RATE,
    INTER_LANE_CHANGE_DISTANCE,
    JUNCTION_LOOK_AHEAD,
    LARGE_VEHICLES_JUNCTION_MAX_RADIUS,
    MAX_START_DISTANCE,
    MAX_WPT_DISTANCE,
    MAXIMUM_LANE_OBSTACLE_CURVATURE,
    MAXIMUM_LANE_OBSTACLE_DISTANCE,
    MIN_JUNCTION_LENGTH,
    MIN_LANE_CHANGE_SPEED,
    MIN_WPT_DISTANCE,
    MINIMUM_HORIZON_LENGTH,
    MINIMUM_LANE_CHANGE_DISTANCE,
    SAFE_DISTANCE_AFTER_JUNCTION,
)
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    NO_SIMPLE_WAYPOINT,
    ROAD_OPTION_CHANGE_LANE_LEFT,
    ROAD_OPTION_CHANGE_LANE_RIGHT,
    ROAD_OPTION_LANE_FOLLOW,
    ROAD_OPTION_LEFT,
    ROAD_OPTION_RIGHT,
    ROAD_OPTION_VOID,
    RoadOption,
    SimpleWaypointIndex,
    distance_squared,
)
from extensions.carla.traffic_manager_shared import (
    LocalizationData,
    TrafficAction,
    TrafficManagerShared,
)
from extensions.carla.traffic_manager_state import (
    FLOAT_MAX,
    deviation_dot_product,
    get_target_waypoint,
    pop_waypoint,
    push_waypoint,
    three_point_circle_radius,
)
from math.vector3 import Vector3
from std.collections import Dict, Optional, Set
from units.si import Length

comptime _DEAD_END = (
    "This map has dead-end roads, please change the set_open_street_map"
    " parameter to true"
)
comptime _ROUTE_MISSED = (
    "We couldn't find the RoadOption you were looking for. This route might"
    " diverge from the one expected."
)
# CARLA's roundabout exception at the center of Town03, 30 m across.
comptime _TOWN03 = "Carla/Maps/Town03"
comptime _TOWN03_RADIUS = Float32(30.0)


def first_next(
    map: InMemoryMap, index: SimpleWaypointIndex
) raises -> SimpleWaypointIndex:
    """Return the first node after a node, CARLA's
    `GetNextWaypoint().front()`.

    Args:
        map: The map.
        index: The node.

    Returns:
        The first node after it, or `NO_SIMPLE_WAYPOINT` at a dead end,
        where CARLA reads past the end of an empty list. `map.at` refuses
        `NO_SIMPLE_WAYPOINT`, so a walk that goes on from there raises.

    Raises:
        Error: If the index names no node.
    """
    ref nexts = map.at(index).next_waypoints
    if len(nexts) == 0:
        return NO_SIMPLE_WAYPOINT
    return nexts[0]


def _pop_all(
    actor: ActorId,
    mut shared: TrafficManagerShared,
    mut buffer: List[SimpleWaypointIndex],
) raises:
    var count = len(buffer)
    # Each caller has read the path's first node.
    for _ in range(count):  # pragma: no branch
        pop_waypoint(actor, shared.track_traffic, buffer, shared.local_map)


def _pop_all_but_first(
    actor: ActorId,
    mut shared: TrafficManagerShared,
    mut buffer: List[SimpleWaypointIndex],
) raises:
    var count = len(buffer)
    for _ in range(count - 1):
        pop_waypoint(
            actor, shared.track_traffic, buffer, shared.local_map, False
        )


def _push(
    actor: ActorId,
    mut shared: TrafficManagerShared,
    mut buffer: List[SimpleWaypointIndex],
    waypoint: SimpleWaypointIndex,
) raises:
    push_waypoint(
        actor, shared.track_traffic, buffer, shared.local_map, waypoint
    )


def _span_squared(
    map: InMemoryMap, buffer: List[SimpleWaypointIndex]
) raises -> Float32:
    """The squared distance from the path's first node to its last."""
    return map.at(buffer[len(buffer) - 1]).distance_squared(
        map.at(buffer[0]).location()
    )


def _buffer_places(
    map: InMemoryMap, buffer: List[SimpleWaypointIndex]
) raises -> Set[Int]:
    var visited = Set[Int]()
    for waypoint in buffer:
        visited.add(map.at(waypoint).id.value)
    return visited^


def _push_unvisited(
    actor: ActorId,
    mut shared: TrafficManagerShared,
    mut buffer: List[SimpleWaypointIndex],
    waypoint: SimpleWaypointIndex,
    mut visited: Set[Int],
) raises -> Bool:
    var id = shared.local_map.at(waypoint).id.value
    if id in visited:
        return False
    _push(actor, shared, buffer, waypoint)
    visited.add(id)
    return True


def _in(list: List[Int], value: Int) -> Bool:
    return value in list


def _drop(mut list: List[Int], value: Int):
    for i in range(len(list)):
        if list[i] == value:
            _ = list.pop(i)
            return


struct LocalizationStage(Movable):
    """The localization stage, CARLA's `LocalizationStage`."""

    # The node each vehicle last changed lanes to.
    var last_lane_change_swpt: Dict[Int, SimpleWaypointIndex]
    # CARLA keeps this set and never fills it.
    var vehicles_at_junction: List[Int]
    # For each vehicle at a junction's entrance: the junction's end and
    # the safe point after it.
    var vehicles_at_junction_entrance: Dict[
        Int, Tuple[SimpleWaypointIndex, SimpleWaypointIndex]
    ]
    var large_vehicles_at_junction_entrance: List[Int]
    var large_vehicles_at_junction: List[Int]

    def __init__(out self):
        """Create an empty stage."""
        self.last_lane_change_swpt = Dict[Int, SimpleWaypointIndex]()
        self.vehicles_at_junction = List[Int]()
        self.vehicles_at_junction_entrance = Dict[
            Int, Tuple[SimpleWaypointIndex, SimpleWaypointIndex]
        ]()
        self.large_vehicles_at_junction_entrance = List[Int]()
        self.large_vehicles_at_junction = List[Int]()

    def update(mut self, index: Int, mut shared: TrafficManagerShared) raises:
        """Bring one vehicle's path up to date, `Update`.

        Args:
            index: The vehicle's place in `shared.vehicle_id_list`.
            shared: The traffic manager's state.

        Raises:
            Error: If the index is out of range, the vehicle is not
                tracked, or a walk reads past a dead end.
        """
        if index < 0 or index >= len(shared.vehicle_id_list):
            raise Error("The vehicle index is out of range")
        var actor = shared.vehicle_id_list[index]
        var a = actor.value
        var location = shared.simulation_state.get_location(actor)
        var heading = shared.simulation_state.get_heading(actor)
        var speed = shared.simulation_state.get_velocity(actor).length()
        var horizon_length = max(
            speed * HORIZON_RATE.value, MINIMUM_HORIZON_LENGTH.value
        )
        if speed > HIGHWAY_SPEED.value:
            horizon_length = max(
                speed * HIGH_SPEED_HORIZON_RATE.value,
                MINIMUM_HORIZON_LENGTH.value,
            )
        var horizon_square = horizon_length * horizon_length
        var buffer = shared.buffer_map.pop(a, List[SimpleWaypointIndex]())
        # A path too far from the vehicle is dropped.
        if (
            len(buffer) > 0
            and distance_squared(
                shared.local_map.at(buffer[0]).location(), location
            )
            > MAX_START_DISTANCE.value * MAX_START_DISTANCE.value
        ):
            _pop_all(actor, shared, buffer)
        var is_at_junction_entrance = False
        if len(buffer) > 0:
            # The nodes behind the vehicle are dropped.
            var dot = deviation_dot_product(
                location, heading, shared.local_map.at(buffer[0]).location()
            )
            while dot <= 0.0 and len(buffer) > 0:
                pop_waypoint(
                    actor, shared.track_traffic, buffer, shared.local_map
                )
                if len(buffer) > 0:
                    dot = deviation_dot_product(
                        location,
                        heading,
                        shared.local_map.at(buffer[0]).location(),
                    )
            if len(buffer) > 0:
                is_at_junction_entrance = self._at_junction_entrance(
                    shared.local_map, buffer, location
                )
            # The far end is cut back past twice the horizon.
            while (
                not is_at_junction_entrance
                and len(buffer) > 0
                and _span_squared(shared.local_map, buffer)
                > horizon_square + horizon_square
                and not shared.local_map.at(
                    buffer[len(buffer) - 1]
                ).check_junction()
            ):
                pop_waypoint(
                    actor,
                    shared.track_traffic,
                    buffer,
                    shared.local_map,
                    False,
                )
        if len(buffer) == 0:
            _push(
                actor, shared, buffer, shared.local_map.get_waypoint(location)
            )
        self._lane_change(actor, location, speed, shared, buffer)
        var path = shared.parameters.get_custom_path(actor)
        var route = shared.parameters.get_imported_route(actor)
        if len(path) > 0:
            self._import_path(path^, buffer, actor, horizon_square, shared)
        elif len(route) > 0:
            self._import_route(route^, buffer, actor, horizon_square, shared)
        else:
            self._extend_randomly(actor, horizon_square, shared, buffer)
        self._extend_and_find_safe_space(
            actor, is_at_junction_entrance, shared, buffer
        )
        self._handle_large_vehicle_junction(
            actor, is_at_junction_entrance, shared, buffer
        )
        var output = LocalizationData(
            NO_SIMPLE_WAYPOINT, NO_SIMPLE_WAYPOINT, is_at_junction_entrance
        )
        if is_at_junction_entrance:
            var points = self.vehicles_at_junction_entrance[a]
            output.junction_end_point = points[0]
            output.safe_point = points[1]
        shared.localization_frame[index] = output
        shared.track_traffic.update_grid_position(
            actor, buffer, shared.local_map
        )
        shared.buffer_map[a] = buffer^

    def _at_junction_entrance(
        self,
        map: InMemoryMap,
        buffer: List[SimpleWaypointIndex],
        location: Vector3,
    ) raises -> Bool:
        var look_ahead = get_target_waypoint(buffer, map, JUNCTION_LOOK_AHEAD)[
            0
        ]
        ref front = map.at(buffer[0])
        var front_junction = front.check_junction()
        var entrance = (
            not front_junction and map.at(look_ahead).check_junction()
        )
        if not entrance and len(front.previous_waypoints) == 1:
            entrance = (
                not map.at(front.previous_waypoints[0]).check_junction()
                and front_junction
            )
        if (
            entrance
            and map.name == _TOWN03
            and location.length_sq() < _TOWN03_RADIUS * _TOWN03_RADIUS
        ):
            entrance = False
        return entrance

    def _lane_change(
        mut self,
        actor: ActorId,
        location: Vector3,
        speed: Float32,
        mut shared: TrafficManagerShared,
        mut buffer: List[SimpleWaypointIndex],
    ) raises:
        var a = actor.value
        var info = shared.parameters.get_force_lane_change(actor)
        var force = info.change_lane
        var direction = info.direction
        # The keep-right rule and the random lane changes.
        if not force and speed > MIN_LANE_CHANGE_SPEED.value:
            var keep_slow = shared.parameters.get_keep_slow_lane_percentage(
                actor
            )
            var random_left = (
                shared.parameters.get_random_left_lane_change_percentage(actor)
            )
            var random_right = (
                shared.parameters.get_random_right_lane_change_percentage(actor)
            )
            var is_rht = shared.local_map.at(buffer[0]).is_rht
            var is_keep_slow = Float64(keep_slow) > shared.random_device.next()
            var is_right = Float64(random_right) >= shared.random_device.next()
            var is_left = Float64(random_left) >= shared.random_device.next()
            var left_change = is_left if is_rht else (is_keep_slow or is_left)
            var right_change = (
                is_keep_slow or is_right
            ) if is_rht else is_right
            if left_change and right_change:
                force = True
                direction = Float64(FIFTYPERC) > shared.random_device.next()
            elif right_change:
                force = True
                direction = True
            elif left_change:
                force = True
                direction = False
        var front = buffer[0]
        var reach = max(Float32(10.0) * speed, INTER_LANE_CHANGE_DISTANCE.value)
        var lane_change_distance = reach * reach
        var recently_not_executed = a not in self.last_lane_change_swpt
        var done_with_previous = True
        if not recently_not_executed:
            var last = self.last_lane_change_swpt[a]
            done_with_previous = (
                distance_squared(shared.local_map.at(last).location(), location)
                > lane_change_distance
            )
            if done_with_previous:
                _ = self.last_lane_change_swpt.pop(a)
        var auto_or_force = (
            shared.parameters.get_auto_lane_change(actor) or force
        )
        var front_not_junction = not shared.local_map.at(front).check_junction()
        if (
            auto_or_force
            and front_not_junction
            and (recently_not_executed or done_with_previous)
        ):
            var change_over_point = self._assign_lane_change(
                actor, location, speed, force, direction, shared, buffer
            )
            if change_over_point.is_some():
                self.last_lane_change_swpt[a] = change_over_point
                _pop_all(actor, shared, buffer)
                _push(actor, shared, buffer, change_over_point)

    def _assign_lane_change(
        self,
        actor: ActorId,
        location: Vector3,
        speed: Float32,
        force: Bool,
        direction: Bool,
        shared: TrafficManagerShared,
        buffer: List[SimpleWaypointIndex],
    ) raises -> SimpleWaypointIndex:
        """CARLA's `AssignLaneChange`, with the vehicle's own path passed
        in: it is out of the buffer map while it is updated."""
        ref map = shared.local_map
        var change_over_point = NO_SIMPLE_WAYPOINT
        var current = buffer[0]
        var left = map.at(current).next_left_waypoint
        var right = map.at(current).next_right_waypoint
        var blocking = shared.track_traffic.get_overlapping_vehicles(actor)
        var obstacle_too_close = False
        var minimum_squared_distance = FLOAT_MAX
        var obstacle = NO_ACTOR
        var i = 0
        while i < len(blocking) and not obstacle_too_close and not force:
            var other = blocking[i]
            i += 1
            var other_buffer = shared.buffer(other)
            if len(other_buffer) == 0:
                continue
            ref mine = map.at(current)
            ref theirs = map.at(other_buffer[0])
            var other_location = theirs.location()
            var reference_heading = mine.forward_vector()
            var to_other = other_location - mine.location()
            if (
                not mine.check_junction()
                and not theirs.check_junction()
                and theirs.waypoint.road_id == mine.waypoint.road_id
                and theirs.waypoint.lane_id == mine.waypoint.lane_id
                and reference_heading.dot(to_other) > 0.0
                and reference_heading.dot(theirs.forward_vector())
                > MAXIMUM_LANE_OBSTACLE_CURVATURE
            ):
                var squared = distance_squared(location, other_location)
                if squared > (
                    MINIMUM_LANE_CHANGE_DISTANCE.value
                    * MINIMUM_LANE_CHANGE_DISTANCE.value
                ):
                    if squared < minimum_squared_distance and squared < (
                        MAXIMUM_LANE_OBSTACLE_DISTANCE.value
                        * MAXIMUM_LANE_OBSTACLE_DISTANCE.value
                    ):
                        minimum_squared_distance = squared
                        obstacle = other
                else:
                    obstacle_too_close = True
        # CARLA tests `force` last; the loop above finds no obstacle when
        # it is set, so testing it first is the same.
        if force:
            if direction and right.is_some():
                change_over_point = right
            elif not direction and left.is_some():
                change_over_point = left
        elif not obstacle_too_close and obstacle != NO_ACTOR:
            ref theirs = map.at(shared.buffer(obstacle)[0])
            var candidates = [
                theirs.next_left_waypoint,
                theirs.next_right_waypoint,
            ]
            var distant_left_free = False
            var distant_right_free = False
            var left_right = True
            # The two sides, always.
            for candidate in candidates:  # pragma: no branch
                if (
                    candidate.is_some()
                    and len(
                        shared.track_traffic.get_passing_vehicles(
                            map.at(candidate).id
                        )
                    )
                    == 0
                ):
                    if left_right:
                        distant_left_free = True
                    else:
                        distant_right_free = True
                left_right = not left_right
            if (
                distant_right_free
                and right.is_some()
                and len(
                    shared.track_traffic.get_passing_vehicles(map.at(right).id)
                )
                == 0
            ):
                change_over_point = right
            elif (
                distant_left_free
                and left.is_some()
                and len(
                    shared.track_traffic.get_passing_vehicles(map.at(left).id)
                )
                == 0
            ):
                change_over_point = left
        if change_over_point.is_some():
            var change_over_distance = min(
                max(Float32(1.5) * speed, MIN_WPT_DISTANCE.value),
                MAX_WPT_DISTANCE.value,
            )
            var start = map.at(change_over_point).location()
            var visited = Set[Int]()
            visited.add(change_over_point.value)
            while (
                map.at(change_over_point).distance_squared(start)
                < change_over_distance * change_over_distance
                and not map.at(change_over_point).check_junction()
            ):
                var nexts = map.at(change_over_point).next_waypoints.copy()
                if len(nexts) == 0:
                    break
                if nexts[0].value in visited:
                    break
                change_over_point = nexts[0]
                visited.add(change_over_point.value)
        return change_over_point

    def _extend_randomly(
        self,
        actor: ActorId,
        horizon_square: Float32,
        mut shared: TrafficManagerShared,
        mut buffer: List[SimpleWaypointIndex],
    ) raises:
        var visited = _buffer_places(shared.local_map, buffer)
        while _span_squared(shared.local_map, buffer) <= horizon_square:
            var furthest = buffer[len(buffer) - 1]
            var nexts = shared.local_map.at(furthest).next_waypoints.copy()
            var selection = 0
            if len(nexts) > 1:
                var sample = shared.random_device.next()
                selection = Int(sample * Float64(len(nexts)) * 0.01)
            elif len(nexts) == 0:
                if not shared.parameters.get_osm_mode():
                    print(_DEAD_END)
                shared.marked_for_removal.append(actor)
                break
            var chosen = nexts[selection]
            if not _push_unvisited(actor, shared, buffer, chosen, visited):
                break

    def _extend_and_find_safe_space(
        mut self,
        actor: ActorId,
        is_at_junction_entrance: Bool,
        mut shared: TrafficManagerShared,
        mut buffer: List[SimpleWaypointIndex],
    ) raises:
        """CARLA's `ExtendAndFindSafeSpace`. Where CARLA reads a junction
        start it never found, the path's first node stands in."""
        var a = actor.value
        var known = a in self.vehicles_at_junction_entrance
        var ready = False
        if known:
            ready = self.vehicles_at_junction_entrance[a][1].is_some()
        # A later fork choice can escape a cycle. Do not let an earlier
        # incomplete walk hide the exit and safe point now in the buffer.
        if is_at_junction_entrance and not ready:
            var junction_end_point = NO_SIMPLE_WAYPOINT
            var safe_point = NO_SIMPLE_WAYPOINT
            var entered = False
            var past = False
            var found = False
            var current = buffer[0]
            var begin = buffer[0]
            var safe_squared = (
                SAFE_DISTANCE_AFTER_JUNCTION.value
                * SAFE_DISTANCE_AFTER_JUNCTION.value
            )
            var i = 0
            while i < len(buffer) and not found:
                current = buffer[i]
                i += 1
                var in_junction = shared.local_map.at(current).check_junction()
                if not entered and in_junction:
                    entered = True
                    begin = current
                if entered and not past and not in_junction:
                    past = True
                    junction_end_point = current
                if (
                    past
                    and shared.local_map.at(
                        junction_end_point
                    ).distance_squared(shared.local_map.at(current).location())
                    > safe_squared
                ):
                    found = True
                    safe_point = current
            if not found:
                var abort = False
                var visited = _buffer_places(shared.local_map, buffer)
                while not past and not abort:
                    var nexts = shared.local_map.at(
                        current
                    ).next_waypoints.copy()
                    if len(nexts) > 0:
                        if not _push_unvisited(
                            actor, shared, buffer, nexts[0], visited
                        ):
                            abort = True
                            break
                        current = nexts[0]
                        if not shared.local_map.at(current).check_junction():
                            past = True
                            junction_end_point = current
                    else:
                        abort = True
                while not found and not abort:
                    var nexts = shared.local_map.at(
                        current
                    ).next_waypoints.copy()
                    if (
                        shared.local_map.at(
                            junction_end_point
                        ).distance_squared(
                            shared.local_map.at(current).location()
                        )
                        > safe_squared
                        or len(nexts) > 1
                        or shared.local_map.at(current).check_junction()
                    ):
                        found = True
                        safe_point = current
                    elif len(nexts) > 0:
                        if not _push_unvisited(
                            actor, shared, buffer, nexts[0], visited
                        ):
                            break
                        current = nexts[0]
                    else:
                        abort = True
            if (
                junction_end_point.is_some()
                and safe_point.is_some()
                and shared.local_map.at(begin).distance_squared(
                    shared.local_map.at(junction_end_point).location()
                )
                < MIN_JUNCTION_LENGTH.value * MIN_JUNCTION_LENGTH.value
            ):
                junction_end_point = NO_SIMPLE_WAYPOINT
                safe_point = NO_SIMPLE_WAYPOINT
            self.vehicles_at_junction_entrance[a] = (
                junction_end_point,
                safe_point,
            )
        elif not is_at_junction_entrance and known:
            _ = self.vehicles_at_junction_entrance.pop(a)

    def _handle_large_vehicle_junction(
        mut self,
        actor: ActorId,
        is_at_junction_entrance: Bool,
        mut shared: TrafficManagerShared,
        buffer: List[SimpleWaypointIndex],
    ) raises:
        var a = actor.value
        if a not in shared.large_vehicles:
            return
        ref map = shared.local_map
        var is_at_junction = map.at(buffer[0]).check_junction()
        if (
            is_at_junction_entrance
            and not _in(self.large_vehicles_at_junction_entrance, a)
            and not _in(self.large_vehicles_at_junction, a)
        ):
            self.large_vehicles_at_junction_entrance.append(a)
            var radius = three_point_circle_radius(
                map.at(buffer[0]).location(),
                map.at(buffer[len(buffer) // 2]).location(),
                map.at(buffer[len(buffer) - 1]).location(),
            )
            if radius.value > LARGE_VEHICLES_JUNCTION_MAX_RADIUS.value:
                return
            var entered = False
            var junction_length = Float32(0.0)
            var straight = True
            # The path is not empty.
            for i in range(len(buffer)):  # pragma: no branch
                ref current = map.at(buffer[i])
                if not entered and current.check_junction():
                    entered = True
                if i > 0 and entered:
                    junction_length += current.distance(
                        map.at(buffer[i - 1]).location()
                    )
                    if straight:
                        var option = current.road_option
                        if option == ROAD_OPTION_RIGHT:
                            shared.large_vehicles[a].turn_right = True
                            straight = False
                        elif option == ROAD_OPTION_LEFT:
                            shared.large_vehicles[a].turn_right = False
                            straight = False
                if entered and not current.check_junction():
                    break
            if not straight:
                shared.large_vehicles[a].junction_length = Length(
                    junction_length
                )
        elif is_at_junction and _in(
            self.large_vehicles_at_junction_entrance, a
        ):
            _drop(self.large_vehicles_at_junction_entrance, a)
            self.large_vehicles_at_junction.append(a)
        elif not is_at_junction and _in(self.large_vehicles_at_junction, a):
            _drop(self.large_vehicles_at_junction, a)
            shared.large_vehicles[a].junction_length = Length(0)

    def _import_path(
        mut self,
        var path: List[Vector3],
        mut buffer: List[SimpleWaypointIndex],
        actor: ActorId,
        horizon_square: Float32,
        mut shared: TrafficManagerShared,
    ) raises:
        if shared.parameters.get_upload_path(actor):
            _pop_all_but_first(actor, shared, buffer)
            shared.parameters.remove_upload_path(actor, False)
        var imported = shared.local_map.get_waypoint(path[0])
        var visited = _buffer_places(shared.local_map, buffer)
        while (
            len(path) > 0
            and _span_squared(shared.local_map, buffer) <= horizon_square
        ):
            var latest = buffer[len(buffer) - 1]
            var nexts = shared.local_map.at(latest).next_waypoints.copy()
            var selection = 0
            if len(nexts) > 1:
                selection = _closest_branch(shared.local_map, nexts, imported)
            elif len(nexts) == 0:
                if not shared.parameters.get_osm_mode():
                    print(_DEAD_END)
                shared.marked_for_removal.append(actor)
                break
            var chosen = nexts[selection]
            if (
                shared.local_map.at(chosen).distance_squared(
                    shared.local_map.at(imported).location()
                )
                < 30.0
            ):
                if shared.local_map.at(imported).id.value not in visited:
                    if (
                        shared.local_map.at(chosen).id
                        != shared.local_map.at(imported).id
                        and imported
                        in shared.local_map.at(chosen).next_waypoints
                    ):
                        if not _push_unvisited(
                            actor, shared, buffer, chosen, visited
                        ):
                            break
                    _push(actor, shared, buffer, imported)
                    visited.add(shared.local_map.at(imported).id.value)
                # A point already in the buffer is reached, too. Consume
                # it without duplicating its passing-vehicle ownership.
                _ = path.pop(0)
                if len(path) > 0:
                    imported = shared.local_map.get_waypoint(path[0])
            else:
                if not _push_unvisited(actor, shared, buffer, chosen, visited):
                    break
        if len(path) == 0:
            shared.parameters.remove_upload_path(actor, True)
        else:
            shared.parameters.update_upload_path(actor, path^)

    def _import_route(
        mut self,
        var route: List[RoadOption],
        mut buffer: List[SimpleWaypointIndex],
        actor: ActorId,
        horizon_square: Float32,
        mut shared: TrafficManagerShared,
    ) raises:
        if shared.parameters.get_upload_route(actor):
            _pop_all_but_first(actor, shared, buffer)
            shared.parameters.remove_imported_route(actor, False)
        var next_option = route[0]
        var visited = _buffer_places(shared.local_map, buffer)
        while (
            len(route) > 0
            and _span_squared(shared.local_map, buffer) <= horizon_square
        ):
            var latest = buffer[len(buffer) - 1]
            var latest_option = shared.local_map.at(latest).road_option
            var nexts = shared.local_map.at(latest).next_waypoints.copy()
            var selection = 0
            if len(nexts) > 1:
                for i in range(len(nexts)):  # pragma: no branch
                    if shared.local_map.at(nexts[i]).road_option == next_option:
                        selection = i
                        break
                    elif i == len(nexts) - 1:
                        print(_ROUTE_MISSED)
            elif len(nexts) == 0:
                if not shared.parameters.get_osm_mode():
                    print(_DEAD_END)
                shared.marked_for_removal.append(actor)
                break
            var chosen = nexts[selection]
            if not _push_unvisited(actor, shared, buffer, chosen, visited):
                break
            var chosen_option = shared.local_map.at(chosen).road_option
            if latest_option != chosen_option and next_option == chosen_option:
                _ = route.pop(0)
                if len(route) > 0:
                    next_option = route[0]
        if len(route) == 0:
            shared.parameters.remove_imported_route(actor, True)
        else:
            shared.parameters.update_imported_route(actor, route^)

    def remove_actor(mut self, actor: ActorId) raises:
        """Forget a vehicle and its junction entrance record, `RemoveActor`.

        Unlike CARLA, no junction indices survive actor removal.

        Args:
            actor: The vehicle.

        Raises:
            Error: Never; the lookups are checked.
        """
        var a = actor.value
        if a in self.last_lane_change_swpt:
            _ = self.last_lane_change_swpt.pop(a)
        if a in self.vehicles_at_junction_entrance:
            _ = self.vehicles_at_junction_entrance.pop(a)
        _drop(self.vehicles_at_junction, a)
        _drop(self.large_vehicles_at_junction_entrance, a)
        _drop(self.large_vehicles_at_junction, a)

    def reset(mut self):
        """Forget every vehicle, `Reset`."""
        self.vehicles_at_junction_entrance = Dict[
            Int, Tuple[SimpleWaypointIndex, SimpleWaypointIndex]
        ]()
        self.last_lane_change_swpt = Dict[Int, SimpleWaypointIndex]()
        self.vehicles_at_junction = List[Int]()
        self.large_vehicles_at_junction_entrance = List[Int]()
        self.large_vehicles_at_junction = List[Int]()

    def _lane_change_action(
        self, actor: ActorId, shared: TrafficManagerShared
    ) raises -> TrafficAction:
        var last = self.last_lane_change_swpt[actor.value]
        var heading = shared.simulation_state.get_heading(actor)
        var relative = (
            shared.simulation_state.get_location(actor)
            - shared.local_map.at(last).location()
        )
        var option = ROAD_OPTION_CHANGE_LANE_RIGHT
        if heading.x * relative.y - heading.y * relative.x > 0.0:
            option = ROAD_OPTION_CHANGE_LANE_LEFT
        return TrafficAction(option, shared.local_map.at(last).waypoint)

    def compute_next_action(
        self, actor: ActorId, shared: TrafficManagerShared
    ) raises -> TrafficAction:
        """Return a vehicle's next move, `ComputeNextAction`.

        Args:
            actor: The vehicle.
            shared: The traffic manager's state.

        Returns:
            The first road option on its path that is not lane follow, or
            its lane change if that comes sooner; lane follow at the path's
            end otherwise; void for a vehicle with no path.

        Raises:
            Error: If the vehicle's path is empty or it is not tracked.
        """
        var a = actor.value
        if a not in shared.buffer_map:
            return TrafficAction(ROAD_OPTION_VOID, None)
        var buffer = shared.buffer(actor)
        if len(buffer) == 0:
            raise Error("A vehicle's path is empty")
        ref map = shared.local_map
        var action = TrafficAction(
            ROAD_OPTION_LANE_FOLLOW, map.at(buffer[len(buffer) - 1]).waypoint
        )
        var is_lane_change = a in self.last_lane_change_swpt
        if is_lane_change:
            action = self._lane_change_action(actor, shared)
        # The path is not empty.
        for index in buffer:  # pragma: no branch
            var option = map.at(index).road_option
            if option != ROAD_OPTION_LANE_FOLLOW:
                if not is_lane_change:
                    return TrafficAction(option, map.at(index).waypoint)
                var actual = shared.simulation_state.get_location(actor)
                var lane_change = distance_squared(
                    actual,
                    map.at(self.last_lane_change_swpt[a]).location(),
                )
                var other = distance_squared(actual, map.at(index).location())
                if lane_change < other:
                    return action
                return TrafficAction(option, map.at(index).waypoint)
        return action

    def compute_action_buffer(
        self, actor: ActorId, shared: TrafficManagerShared
    ) raises -> List[TrafficAction]:
        """Return a vehicle's moves along its path, `ComputeActionBuffer`.

        Each change of road option along the path is one move. A lane
        change goes in before the first move whose node, counted by the
        move's place in the list, is farther than it, as CARLA counts.

        Args:
            actor: The vehicle.
            shared: The traffic manager's state.

        Returns:
            The moves, or none for a vehicle with no path.

        Raises:
            Error: If the vehicle's path is empty or it is not tracked.
        """
        var out = List[TrafficAction]()
        var a = actor.value
        if a not in shared.buffer_map:
            return out^
        var buffer = shared.buffer(actor)
        if len(buffer) == 0:
            raise Error("A vehicle's path is empty")
        ref map = shared.local_map
        var last_option = map.at(buffer[0]).road_option
        out.append(TrafficAction(last_option, map.at(buffer[0]).waypoint))
        # The path is not empty.
        for index in buffer:  # pragma: no branch
            var option = map.at(index).road_option
            if option != last_option:
                out.append(TrafficAction(option, map.at(index).waypoint))
                last_option = option
        if a in self.last_lane_change_swpt:
            var lane_change = self._lane_change_action(actor, shared)
            var front = map.at(buffer[0]).location()
            var lane_change_distance = distance_squared(
                front, map.at(self.last_lane_change_swpt[a]).location()
            )
            # The list holds one move at least.
            for i in range(len(out)):  # pragma: no branch
                var action_distance = distance_squared(
                    front, map.at(buffer[i]).location()
                )
                if i == len(out) - 1:
                    out.append(lane_change)
                    break
                elif action_distance > lane_change_distance:
                    out.insert(i, lane_change)
                    break
        return out^


def _branch_end(
    map: InMemoryMap, start: SimpleWaypointIndex
) raises -> SimpleWaypointIndex:
    # Follow the first successor through a junction and far enough past
    # it. A branch without such an end cannot rank an imported path.
    var end = start
    var entered = False
    var past = False
    var visited = Set[Int]()
    visited.add(end.value)
    while True:
        if map.at(end).check_junction():
            entered = True
        elif entered:
            past = True
        if (
            past
            and map.at(start).distance_squared(map.at(end).location()) >= 50.0
        ):
            return end
        var next = first_next(map, end)
        if not next.is_some():
            return NO_SIMPLE_WAYPOINT
        if next.value in visited:
            return NO_SIMPLE_WAYPOINT
        end = next
        visited.add(end.value)


def _closest_branch(
    map: InMemoryMap,
    nexts: List[SimpleWaypointIndex],
    imported: SimpleWaypointIndex,
) raises -> Int:
    """CARLA's choice of fork for an imported path: the branch whose end
    past the junction is on the imported point's road, or else nearest
    it. Cyclic or disconnected branches have no end and are skipped.
    If none has an end, keep the first branch."""
    var imported_road = map.at(imported).waypoint.road_id
    var min_distance = FLOAT_MAX
    var selection = 0
    for k in range(len(nexts)):  # pragma: no branch
        var end = _branch_end(map, nexts[k])
        if not end.is_some():
            continue
        if map.at(end).waypoint.road_id == imported_road:
            return k
        var distance = map.at(end).distance_squared(map.at(imported).location())
        if distance < min_distance:
            min_distance = distance
            selection = k
    return selection
