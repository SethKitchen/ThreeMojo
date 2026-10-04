# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's shared state and geometry.

- `TrackTraffic` knows which vehicle's path passes each waypoint and each
  geodesic grid, CARLA's `TrackTraffic`.
- `SimulationState` holds each actor's pose, speed, size, speed limit
  and light, CARLA's `SimulationState`.
- The buffer helpers push and pop a vehicle's path and find the target
  point on it, CARLA's `LocalizationUtils`.
- The geometry helpers measure a turn's radius, interpolate along a
  path and shape a large vehicle's wide turn, CARLA's
  `TrafficManagerGeometry`.

A vehicle's path, its buffer, is a list of nodes of the
`InMemoryMap`, nearest first.

**Order.** CARLA keeps actors in hash sets and walks them in hash order.
Here a set of actors is a list, and a query that returns one sorts it by
id.

**Differences from CARLA.** The circle radius uses widened edge lengths
and a checked determinant with an exact fallback. Translation does not
cancel absolute
Float32 squared coordinates. The original absolute near-line threshold
stays in square meters. Radii above `FLT_MAX` use that sentinel.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/TrackTraffic.cpp`,
`SimulationState.cpp`, `LocalizationUtils.cpp`, `TrafficManagerGeometry.cpp`
and `DataStructures.h`.
"""

from extensions.carla.actor import (
    ActorId,
    GREEN,
    TrafficLightState,
)
from extensions.carla.math import make_unit_vector
from extensions.carla.road_info import JuncId
from extensions.carla.traffic_manager_constants import (
    EPSILON,
    INV_MAP_RESOLUTION,
    PI,
)
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    SimpleWaypointIndex,
    WaypointId,
    distance_squared,
)
from extensions.carla.transform import CarlaRotation
from math.matrix_determinant import _sum_products
from math.vector3 import Vector3
from std.collections import Dict
from std.math import cos, sqrt
from units.si import Length, METER, Velocity

# `std::numeric_limits<float>::max()`.
comptime FLOAT_MAX = Float32(3.4028234663852886e38)


def _sorted(var ids: List[Int]) -> List[Int]:
    for i in range(1, len(ids)):
        var j = i
        while j > 0 and ids[j] < ids[j - 1]:
            ids.swap_elements(j, j - 1)
            j -= 1
    return ids^


def _actor_ids(ids: List[Int]) -> List[ActorId]:
    var out = List[ActorId]()
    for id in _sorted(ids.copy()):
        out.append(ActorId(id))
    return out^


def _add(mut set: List[Int], value: Int):
    if value not in set:
        set.append(value)


def _remove(mut set: List[Int], value: Int):
    # Each caller removes a value that the set holds: an actor from its
    # own grid's list, and a waypoint and an actor that each list the
    # other.
    for i in range(len(set)):  # pragma: no branch
        if set[i] == value:
            _ = set.pop(i)
            return


# --- TrackTraffic ------------------------------------------------------------


struct TrackTraffic(Movable):
    """Which paths pass which waypoints and grids, CARLA's `TrackTraffic`."""

    # Waypoint id to the actors whose path passes it.
    var _overlap: Dict[Int, List[Int]]
    # Actor to the waypoint ids its path passes.
    var _occupied: Dict[Int, List[Int]]
    # Actor to the grids its path passes, and grid to its actors.
    var _actor_to_grids: Dict[Int, List[Int]]
    var _grid_to_actors: Dict[Int, List[Int]]
    var _hero_location: Vector3

    def __init__(out self):
        """Create an empty tracker, with the hero at the origin."""
        self._overlap = Dict[Int, List[Int]]()
        self._occupied = Dict[Int, List[Int]]()
        self._actor_to_grids = Dict[Int, List[Int]]()
        self._grid_to_actors = Dict[Int, List[Int]]()
        self._hero_location = Vector3(0, 0, 0)

    def update_passing_vehicle(
        mut self, waypoint_id: WaypointId, actor_id: ActorId
    ) raises:
        """Note that an actor's path passes a waypoint,
        `UpdatePassingVehicle`.

        Args:
            waypoint_id: The waypoint.
            actor_id: The actor.

        Raises:
            Error: If an id is not valid.
        """
        if not (waypoint_id.is_valid() and actor_id.is_valid()):
            raise Error("Waypoint id or actor id is not valid")
        var w = waypoint_id.value
        var a = actor_id.value
        if w not in self._overlap:
            self._overlap[w] = List[Int]()
        _add(self._overlap[w], a)
        if a not in self._occupied:
            self._occupied[a] = List[Int]()
        _add(self._occupied[a], w)

    def remove_passing_vehicle(
        mut self, waypoint_id: WaypointId, actor_id: ActorId
    ) raises:
        """Note that an actor's path left a waypoint,
        `RemovePassingVehicle`.

        Args:
            waypoint_id: The waypoint.
            actor_id: The actor.

        Raises:
            Error: If an id is not valid.
        """
        if not (waypoint_id.is_valid() and actor_id.is_valid()):
            raise Error("Waypoint id or actor id is not valid")
        var w = waypoint_id.value
        var a = actor_id.value
        if w in self._overlap:
            _remove(self._overlap[w], a)
            if len(self._overlap[w]) == 0:
                _ = self._overlap.pop(w)
        if a in self._occupied:
            _remove(self._occupied[a], w)
            if len(self._occupied[a]) == 0:
                _ = self._occupied.pop(a)

    def get_passing_vehicles(self, waypoint_id: WaypointId) -> List[ActorId]:
        """Return the actors whose path passes a waypoint,
        `GetPassingVehicles`.

        Args:
            waypoint_id: The waypoint.

        Returns:
            The actors, by id.
        """
        var found = self._overlap.get(waypoint_id.value)
        if Bool(found):
            return _actor_ids(found.value())
        return List[ActorId]()

    def _clear_grids(mut self, a: Int) raises:
        if a in self._actor_to_grids:
            # CARLA checks that each grid is known. It is: a grid an actor
            # is on lists the actor.
            for grid in self._actor_to_grids[a]:
                _remove(self._grid_to_actors[grid], a)
            _ = self._actor_to_grids.pop(a)

    def update_grid_position(
        mut self,
        actor_id: ActorId,
        buffer: List[SimpleWaypointIndex],
        map: InMemoryMap,
    ) raises:
        """Note the grids a registered vehicle's path passes,
        `UpdateGridPosition`.

        An empty path changes nothing.

        Args:
            actor_id: The vehicle.
            buffer: Its path.
            map: The map the path is on.

        Raises:
            Error: If the id is not valid, or a node is not on the map.
        """
        if not actor_id.is_valid():
            raise Error("Actor id is not valid")
        if len(buffer) == 0:
            return
        var a = actor_id.value
        self._clear_grids(a)
        var grids = List[Int]()
        # An empty path returned above.
        for index in buffer:  # pragma: no branch
            var grid = map.at(index).get_geodesic_grid_id().value
            _add(grids, grid)
            if grid not in self._grid_to_actors:
                self._grid_to_actors[grid] = List[Int]()
            _add(self._grid_to_actors[grid], a)
        self._actor_to_grids[a] = grids^

    def update_unregistered_grid_position(
        mut self,
        actor_id: ActorId,
        waypoints: List[SimpleWaypointIndex],
        map: InMemoryMap,
    ) raises:
        """Note the waypoints and grids an unregistered actor covers,
        `UpdateUnregisteredGridPosition`.

        Args:
            actor_id: The actor.
            waypoints: The nodes under it.
            map: The map the nodes are on.

        Raises:
            Error: If the id is not valid, or a node is not on the map.
        """
        self.delete_actor(actor_id)
        var a = actor_id.value
        var grids = List[Int]()
        for index in waypoints:
            ref node = map.at(index)
            self.update_passing_vehicle(node.id, actor_id)
            var grid = node.get_geodesic_grid_id().value
            _add(grids, grid)
            if grid in self._grid_to_actors:
                _add(self._grid_to_actors[grid], a)
            else:
                self._grid_to_actors[grid] = [a]
        self._actor_to_grids[a] = grids^

    def get_overlapping_vehicles(self, actor_id: ActorId) -> List[ActorId]:
        """Return the actors whose paths share a grid with an actor's,
        `GetOverlappingVehicles`. The actor itself is among them.

        Args:
            actor_id: The actor.

        Returns:
            The actors, by id.
        """
        var out = List[Int]()
        var grids = self._actor_to_grids.get(actor_id.value)
        if Bool(grids):
            for grid in grids.value():
                # A grid an actor is on lists the actor.
                for a in self._grid_to_actors.get(  # pragma: no branch
                    grid, List[Int]()
                ):
                    _add(out, a)
        return _actor_ids(out)

    def is_geo_grid_free(self, grid: JuncId) -> Bool:
        """Return True if no path passes a grid, `IsGeoGridFree`.

        Args:
            grid: The grid.

        Returns:
            Whether the grid has no actors.
        """
        var found = self._grid_to_actors.get(grid.value)
        if Bool(found):
            return len(found.value()) == 0
        return True

    def add_taken_grid(mut self, grid: JuncId, actor_id: ActorId) raises:
        """Claim a grid for an actor if it is unknown, `AddTakenGrid`.

        Args:
            grid: The grid.
            actor_id: The actor.

        Raises:
            Error: If an id is not valid.
        """
        if not (grid.is_valid() and actor_id.is_valid()):
            raise Error("Grid id or actor id is not valid")
        if grid.value not in self._grid_to_actors:
            self._grid_to_actors[grid.value] = [actor_id.value]

    def set_hero_location(mut self, location: Vector3):
        """Set where the hero vehicle is, `SetHeroLocation`.

        Args:
            location: The point, in meters. The origin means no hero.
        """
        self._hero_location = location

    def get_hero_location(self) -> Vector3:
        """Return where the hero vehicle is, `GetHeroLocation`.

        Returns:
            The point, in meters.
        """
        return self._hero_location

    def delete_actor(mut self, actor_id: ActorId) raises:
        """Forget an actor's grids and waypoints, `DeleteActor`.

        Args:
            actor_id: The actor.

        Raises:
            Error: If the id is not valid.
        """
        if not actor_id.is_valid():
            raise Error("Actor id is not valid")
        var a = actor_id.value
        self._clear_grids(a)
        var found = self._occupied.get(a)
        if Bool(found):
            # An actor's list of waypoints is dropped when it empties.
            for w in found.value():  # pragma: no branch
                self.remove_passing_vehicle(WaypointId(w), actor_id)

    def clear(mut self):
        """Forget everything but the hero's location, `Clear`."""
        self._overlap = Dict[Int, List[Int]]()
        self._occupied = Dict[Int, List[Int]]()
        self._actor_to_grids = Dict[Int, List[Int]]()
        self._grid_to_actors = Dict[Int, List[Int]]()


# --- SimulationState ---------------------------------------------------------


@fieldwise_init
struct TrafficActorType(Equatable, ImplicitlyCopyable, Writable):
    """What an actor is to the traffic manager, CARLA's `ActorType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names vehicle, pedestrian or any.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime TRAFFIC_VEHICLE = TrafficActorType(0)
comptime TRAFFIC_PEDESTRIAN = TrafficActorType(1)
comptime TRAFFIC_ANY = TrafficActorType(2)


@fieldwise_init
struct KinematicState(ImplicitlyCopyable):
    """An actor's motion, CARLA's `KinematicState`."""

    var location: Vector3
    var rotation: CarlaRotation
    # In m/s.
    var velocity: Vector3
    var speed_limit: Velocity
    var physics_enabled: Bool
    var is_dormant: Bool
    # Where a vehicle without physics was last moved to.
    var hybrid_end_location: Vector3


@fieldwise_init
struct TrafficLightInfo(ImplicitlyCopyable):
    """The light an actor obeys, CARLA's traffic-manager
    `TrafficLightState` record. The name differs because `actor` already
    has a `TrafficLightState`, the color."""

    var tl_state: TrafficLightState
    var at_traffic_light: Bool


@fieldwise_init
struct StaticAttributes(ImplicitlyCopyable):
    """An actor's kind and half size, CARLA's `StaticAttributes`."""

    var actor_type: TrafficActorType
    var half_length: Length
    var half_width: Length
    var half_height: Length


struct SimulationState(Movable):
    """Every tracked actor's state, CARLA's `SimulationState`."""

    var _actors: List[Int]
    var _kinematic: Dict[Int, KinematicState]
    var _attributes: Dict[Int, StaticAttributes]
    var _lights: Dict[Int, TrafficLightInfo]

    def __init__(out self):
        """Create an empty state."""
        self._actors = List[Int]()
        self._kinematic = Dict[Int, KinematicState]()
        self._attributes = Dict[Int, StaticAttributes]()
        self._lights = Dict[Int, TrafficLightInfo]()

    def add_actor(
        mut self,
        actor_id: ActorId,
        kinematic_state: KinematicState,
        attributes: StaticAttributes,
        tl_state: TrafficLightInfo,
    ) raises:
        """Start tracking an actor, `AddActor`.

        An actor already tracked keeps its old records, as a
        `std::unordered_map::insert` does.

        Args:
            actor_id: The actor.
            kinematic_state: Its motion.
            attributes: Its kind and size.
            tl_state: Its light.

        Raises:
            Error: If the id or the kind is not valid.
        """
        if not (actor_id.is_valid() and attributes.actor_type.is_valid()):
            raise Error("Actor id or actor type is not valid")
        var a = actor_id.value
        if a in self._actors:
            return
        self._actors.append(a)
        self._kinematic[a] = kinematic_state
        self._attributes[a] = attributes
        self._lights[a] = tl_state

    def contains_actor(self, actor_id: ActorId) -> Bool:
        """Return True if an actor is tracked, `ContainsActor`.

        Args:
            actor_id: The actor.

        Returns:
            Whether it is.
        """
        return actor_id.value in self._actors

    def remove_actor(mut self, actor_id: ActorId) raises:
        """Stop tracking an actor, `RemoveActor`.

        Args:
            actor_id: The actor. An untracked one is ignored.

        Raises:
            Error: Never; the records of an actor are kept together.
        """
        var a = actor_id.value
        if a not in self._actors:
            return
        _remove(self._actors, a)
        _ = self._kinematic.pop(a)
        _ = self._attributes.pop(a)
        _ = self._lights.pop(a)

    def reset(mut self):
        """Stop tracking every actor, `Reset`."""
        self._actors = List[Int]()
        self._kinematic = Dict[Int, KinematicState]()
        self._attributes = Dict[Int, StaticAttributes]()
        self._lights = Dict[Int, TrafficLightInfo]()

    def _get(self, actor_id: ActorId) raises -> Int:
        if actor_id.value not in self._actors:
            raise Error("The traffic manager does not track the actor")
        return actor_id.value

    def update_kinematic_state(
        mut self, actor_id: ActorId, state: KinematicState
    ) raises:
        """Replace an actor's motion, `UpdateKinematicState`.

        Args:
            actor_id: The actor.
            state: Its new motion.

        Raises:
            Error: If the actor is not tracked.
        """
        self._kinematic[self._get(actor_id)] = state

    def update_kinematic_hybrid_end_location(
        mut self, actor_id: ActorId, location: Vector3
    ) raises:
        """Note where a vehicle without physics was moved to,
        `UpdateKinematicHybridEndLocation`.

        Args:
            actor_id: The vehicle.
            location: The point, in meters.

        Raises:
            Error: If the actor is not tracked.
        """
        self._kinematic[self._get(actor_id)].hybrid_end_location = location

    def update_traffic_light_state(
        mut self, actor_id: ActorId, var state: TrafficLightInfo
    ) raises:
        """Replace an actor's light, `UpdateTrafficLightState`.

        A vehicle at a green light keeps green while it stays at a light,
        so the yellow never reaches it: CARLA does this so that a vehicle
        whose rear is still in the light's box does not stop in the
        junction.

        Args:
            actor_id: The actor.
            state: Its new light.

        Raises:
            Error: If the actor is not tracked.
        """
        var a = self._get(actor_id)
        var previous = self._lights[a]
        if previous.at_traffic_light and previous.tl_state == GREEN:
            state.tl_state = GREEN
        self._lights[a] = state

    def get_kinematic_state(self, actor_id: ActorId) raises -> KinematicState:
        """Return an actor's motion.

        Args:
            actor_id: The actor.

        Returns:
            The record.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._kinematic[self._get(actor_id)]

    def get_location(self, actor_id: ActorId) raises -> Vector3:
        """Return where an actor is, `GetLocation`.

        Args:
            actor_id: The actor.

        Returns:
            The point, in meters.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._kinematic[self._get(actor_id)].location

    def get_hybrid_end_location(self, actor_id: ActorId) raises -> Vector3:
        """Return where a vehicle without physics was moved to,
        `GetHybridEndLocation`.

        Args:
            actor_id: The vehicle.

        Returns:
            The point, in meters.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._kinematic[self._get(actor_id)].hybrid_end_location

    def get_rotation(self, actor_id: ActorId) raises -> CarlaRotation:
        """Return how an actor is turned, `GetRotation`.

        Args:
            actor_id: The actor.

        Returns:
            The rotation.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._kinematic[self._get(actor_id)].rotation

    def get_heading(self, actor_id: ActorId) raises -> Vector3:
        """Return where an actor faces, `GetHeading`.

        Args:
            actor_id: The actor.

        Returns:
            The rotation's forward vector.

        Raises:
            Error: If the actor is not tracked.
        """
        return self.get_rotation(actor_id).forward_vector()

    def get_velocity(self, actor_id: ActorId) raises -> Vector3:
        """Return an actor's velocity, `GetVelocity`.

        Args:
            actor_id: The actor.

        Returns:
            The velocity, in m/s.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._kinematic[self._get(actor_id)].velocity

    def get_speed_limit(self, actor_id: ActorId) raises -> Velocity:
        """Return the speed limit an actor obeys, `GetSpeedLimit`.

        Args:
            actor_id: The actor.

        Returns:
            The limit.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._kinematic[self._get(actor_id)].speed_limit

    def is_physics_enabled(self, actor_id: ActorId) raises -> Bool:
        """Return True if physics moves an actor, `IsPhysicsEnabled`.

        Args:
            actor_id: The actor.

        Returns:
            The flag.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._kinematic[self._get(actor_id)].physics_enabled

    def is_dormant(self, actor_id: ActorId) raises -> Bool:
        """Return True if an actor is dormant, `IsDormant`.

        Args:
            actor_id: The actor.

        Returns:
            The flag.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._kinematic[self._get(actor_id)].is_dormant

    def get_tls(self, actor_id: ActorId) raises -> TrafficLightInfo:
        """Return the light an actor obeys, `GetTLS`.

        Args:
            actor_id: The actor.

        Returns:
            The record.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._lights[self._get(actor_id)]

    def get_type(self, actor_id: ActorId) raises -> TrafficActorType:
        """Return what an actor is, `GetType`.

        Args:
            actor_id: The actor.

        Returns:
            Its type.

        Raises:
            Error: If the actor is not tracked.
        """
        return self._attributes[self._get(actor_id)].actor_type

    def get_dimensions(self, actor_id: ActorId) raises -> Vector3:
        """Return an actor's half size, `GetDimensions`.

        Args:
            actor_id: The actor.

        Returns:
            The half length, width and height, in meters.

        Raises:
            Error: If the actor is not tracked.
        """
        ref a = self._attributes[self._get(actor_id)]
        return Vector3(
            a.half_length.value, a.half_width.value, a.half_height.value
        )


# --- LocalizationUtils --------------------------------------------------------


def deviation_cross_product(
    reference_location: Vector3, heading_vector: Vector3, target: Vector3
) -> Float32:
    """Return how far a target is to the side, `DeviationCrossProduct`.

    Args:
        reference_location: The vehicle, in meters.
        heading_vector: Where it faces.
        target: The target, in meters.

    Returns:
        The z of the heading crossed with the unit vector to the target.
    """
    var next = make_unit_vector(target - reference_location, EPSILON)
    return heading_vector.x * next.y - heading_vector.y * next.x


def deviation_dot_product(
    reference_location: Vector3, heading_vector: Vector3, target: Vector3
) -> Float32:
    """Return how far a target is ahead, `DeviationDotProduct`.

    Args:
        reference_location: The vehicle, in meters.
        heading_vector: Where it faces.
        target: The target, in meters.

    Returns:
        The dot of the level unit heading and the level unit vector to the
        target, clamped to [0, 1].
    """
    var next = target - reference_location
    next.z = 0
    next = make_unit_vector(next, EPSILON)
    var flat = make_unit_vector(
        Vector3(heading_vector.x, heading_vector.y, 0), EPSILON
    )
    var dot = next.x * flat.x + next.y * flat.y + next.z * flat.z
    return max(Float32(0.0), min(dot, Float32(1.0)))


def push_waypoint(
    actor_id: ActorId,
    mut track_traffic: TrackTraffic,
    mut buffer: List[SimpleWaypointIndex],
    map: InMemoryMap,
    waypoint: SimpleWaypointIndex,
) raises:
    """Add a node to the end of a path, `PushWaypoint`.

    Args:
        actor_id: The vehicle.
        track_traffic: The tracker, told the vehicle passes the node.
        buffer: The path.
        map: The map.
        waypoint: The node.

    Raises:
        Error: If the node is not on the map or the id is not valid.
    """
    var id = map.at(waypoint).id
    buffer.append(waypoint)
    track_traffic.update_passing_vehicle(id, actor_id)


def pop_waypoint(
    actor_id: ActorId,
    mut track_traffic: TrackTraffic,
    mut buffer: List[SimpleWaypointIndex],
    map: InMemoryMap,
    front: Bool = True,
) raises:
    """Remove a node from one end of a path, `PopWaypoint`.

    Args:
        actor_id: The vehicle.
        track_traffic: The tracker, told the vehicle no longer passes the
            node.
        buffer: The path. It must not be empty.
        map: The map.
        front: True for the nearest node, False for the farthest.

    Raises:
        Error: If the path is empty.
    """
    if len(buffer) == 0:
        raise Error("A waypoint buffer is empty")
    var removed = buffer.pop(0) if front else buffer.pop()
    track_traffic.remove_passing_vehicle(map.at(removed).id, actor_id)


def get_target_waypoint(
    buffer: List[SimpleWaypointIndex],
    map: InMemoryMap,
    target_point_distance: Length,
) raises -> Tuple[SimpleWaypointIndex, Int]:
    """Return the first node a distance from the path's start,
    `GetTargetWaypoint`.

    The scan starts at the node the distance over the map's resolution
    gives. If the path is shorter, the last node is the target.

    CARLA scans backward when the start is already too far. That scan
    never runs: the first node is at no distance from itself. So a zero
    distance gives the scan's start.

    Args:
        buffer: The path. It must not be empty.
        map: The map.
        target_point_distance: How far along.

    Returns:
        The node and its index in the path.

    Raises:
        Error: If the path is empty.
    """
    if len(buffer) == 0:
        raise Error("A waypoint buffer is empty")
    var target = buffer[0]
    var front = map.at(buffer[0]).location()
    var start = Int(abs(target_point_distance.value * INV_MAP_RESOLUTION))
    var index = start
    if start < len(buffer):
        var power = target_point_distance.value * target_point_distance.value
        var i = start
        while (
            i < len(buffer)
            and distance_squared(front, map.at(target).location()) < power
        ):
            target = buffer[i]
            index = i
            i += 1
    else:
        target = buffer[len(buffer) - 1]
        index = len(buffer) - 1
    return (target, index)


# --- TrafficManagerGeometry ----------------------------------------------------


def three_point_circle_radius(
    first: Vector3, middle: Vector3, last: Vector3
) -> Length:
    """Return the radius of the circle through three points in plan,
    `GetThreePointCircleRadius`.

    Args:
        first: A point, in meters.
        middle: Another.
        last: A third.

    Returns:
        The radius in meters. Return `FLT_MAX` when twice the absolute
        plan determinant is at most `EPSILON` square meters, including
        repeated points, or when the radius exceeds the Float32 range.
        Finite points above that absolute cutoff keep their radius even
        when their turn angle is small. The z coordinates are ignored.

    """
    var x1 = Float64(first.x)
    var y1 = Float64(first.y)
    var x2 = Float64(middle.x)
    var y2 = Float64(middle.y)
    var x3 = Float64(last.x)
    var y3 = Float64(last.y)
    var x12 = x1 - x2
    var y12 = y1 - y2
    var x13 = x1 - x3
    var y13 = y1 - y3
    var left = x12 * y13
    var right = y12 * x13
    var determinant = left - right
    var products = abs(left) + abs(right)
    # Each product has two rounded shifts and one multiplication. With
    # u=2**-53, its error is at most gamma(3) times its exact magnitude.
    # The subtraction adds at most u*(abs(left)+abs(right)). Thus 8*u
    # times the rounded product sum bounds the determinant error, with
    # room for the sum and the filter comparisons to round too.
    var error = Float64(8.881784197001252e-16) * products
    var cutoff = Float64(EPSILON) * 0.5
    if abs(determinant) + error < cutoff:
        return Length(FLOAT_MAX)
    # Bound determinant error by 2**-28 of its computed magnitude.
    # Side squares, their product, sqrt and division add at most nine
    # factors of (1 +/- u). The wide radius error is therefore below
    # 2**-27 relative, one eighth of Float32's unit roundoff, before
    # conversion. This budget admits ordinary shallow road curves.
    # The lower bound must also clear the original absolute cutoff.
    # Every uncertain case uses exact products; this rejects no new turn.
    if (
        error > abs(determinant) * Float64(3.725290298461914e-9)
        or abs(determinant) - error <= cutoff
    ):
        # Expand (middle-first) cross (last-first) into exact coordinate
        # products. This also retains a short edge beside a distant point.
        determinant = _sum_products[6](
            [x1, x2, x3, -x1, -x2, -x3], [y2, y3, y1, y3, y1, y2]
        )
        var sign = Float64(1)
        if determinant < 0:
            sign = -1
        # Keep CARLA's <= EPSILON test. Subtract the threshold inside the
        # expansion so a rounded tie cannot hide a small nonzero excess.
        var above_threshold = _sum_products[7](
            [
                sign * x1,
                sign * x2,
                sign * x3,
                -sign * x1,
                -sign * x2,
                -sign * x3,
                -Float64(EPSILON),
            ],
            [2 * y2, 2 * y3, 2 * y1, 2 * y3, 2 * y1, 2 * y2, 1],
        )
        if above_threshold <= 0:
            return Length(FLOAT_MAX)
    var x23 = x2 - x3
    var y23 = y2 - y3
    var a2 = x12 * x12 + y12 * y12
    var b2 = x13 * x13 + y13 * y13
    var c2 = x23 * x23 + y23 * y23
    # R = abc / (4 area). Finite Float32 differences have magnitude
    # below 2**129, so a2*b2*c2 is below 2**777 and fits Float64.
    # Even subnormal Float32 edges have squares in normal Float64 range.
    var radius = sqrt(a2 * b2 * c2) / (2 * abs(determinant))
    if radius > Float64(FLOAT_MAX):
        return Length(FLOAT_MAX)
    return Length(Float32(radius))


def interpolate_buffer_at(
    locations: List[Vector3], target_distance: Length, vehicle: Vector3
) -> Tuple[Vector3, Int]:
    """Return the point a distance from a vehicle along its path,
    `InterpolateBufferAt`.

    The point lies on the segment between the last node nearer than the
    distance and the first node as far or farther, where the distance
    from the vehicle, taken as linear along the segment, reaches the
    target.

    Args:
        locations: The path's nodes, in meters.
        target_distance: The distance.
        vehicle: The vehicle, in meters.

    Returns:
        The point and the index of the segment's first node. An empty
        path gives the vehicle and 0; a path of one node gives it and 0;
        a target past the last node gives the last node.
    """
    if len(locations) == 0:
        return (vehicle, 0)
    if len(locations) == 1:
        return (locations[0], 0)
    var target_square = target_distance.value * target_distance.value
    var closest = 0
    var farthest = 0
    var found = False
    for i in range(len(locations)):  # pragma: no branch
        if distance_squared(vehicle, locations[i]) < target_square:
            closest = i
        else:
            farthest = i
            found = True
            break
    if not found:
        return (locations[len(locations) - 1], len(locations) - 1)
    if closest == 0 and farthest == 0:
        farthest = 1
    var close = locations[closest]
    var far = locations[farthest]
    var close_distance = (close - vehicle).length()
    var far_distance = (far - vehicle).length()
    var span = far_distance - close_distance
    if abs(span) <= EPSILON:
        return (close, closest)
    var t = (target_distance.value - close_distance) / span
    return (
        Vector3(
            close.x + (far.x - close.x) * t,
            close.y + (far.y - close.y) * t,
            close.z + (far.z - close.z) * t,
        ),
        closest,
    )


def get_target_data(
    buffer: List[SimpleWaypointIndex],
    map: InMemoryMap,
    target_distance: Length,
    vehicle: Vector3,
) raises -> Tuple[Vector3, Int]:
    """Return `interpolate_buffer_at` of a path, `GetTargetData`.

    Args:
        buffer: The path.
        map: The map.
        target_distance: The distance.
        vehicle: The vehicle, in meters.

    Returns:
        The point and the index of the segment's first node.

    Raises:
        Error: If a node is not on the map.
    """
    var locations = List[Vector3]()
    for index in buffer:
        locations.append(map.at(index).location())
    return interpolate_buffer_at(locations, target_distance, vehicle)


def large_vehicle_junction_offset_profile(
    t: Float32,
    max_offset: Length,
    max_offset_point: Float32,
    inboard_scale: Float32,
) -> Length:
    """Return a large vehicle's side offset through a junction,
    `LargeVehicleJunctionOffsetProfile`.

    The offset starts at zero, swings out to minus the full offset, comes
    back in to the full offset and ends at zero, along cosine ramps. The
    inward part is scaled down.

    Args:
        t: The share of the junction still ahead, clamped to [0, 1].
        max_offset: The full offset.
        max_offset_point: Where the ramps end, as a share.
        inboard_scale: The share of the inward offset kept.

    Returns:
        The offset; positive is inward.
    """
    var tc = min(max(t, Float32(0.0)), Float32(1.0))
    var m = max_offset.value
    var offset: Float32
    if tc < max_offset_point:
        var a = tc / max_offset_point
        offset = m * Float32(0.5) * (Float32(1.0) - cos(PI * a))
    elif tc < Float32(1.0) - max_offset_point:
        var a = (tc - max_offset_point) / (
            Float32(1.0) - Float32(2.0) * max_offset_point
        )
        offset = m * cos(PI * a)
    else:
        var a = (tc - (Float32(1.0) - max_offset_point)) / max_offset_point
        offset = -m * Float32(0.5) * (Float32(1.0) + cos(PI * a))
    if offset > 0.0:
        offset *= inboard_scale
    return Length(offset)


def large_vehicle_offset_magnitude(
    vehicle_length: Length,
    reference_length: Length,
    gain: Float32,
    offset_cap: Length,
) -> Length:
    """Return how far a large vehicle swings out,
    `LargeVehicleOffsetMagnitude`.

    Args:
        vehicle_length: The vehicle's full length.
        reference_length: The length at or below which there is no swing.
        gain: Meters of swing per meter of length past the reference.
        offset_cap: The most swing.

    Returns:
        The gain times the extra length, clamped to [0, cap].
    """
    var scaled = gain * (vehicle_length.value - reference_length.value)
    return Length(min(max(scaled, Float32(0.0)), offset_cap.value))


@fieldwise_init
struct Neighbor(ImplicitlyCopyable):
    """A nearby vehicle for `is_offset_side_occupied`: where it is and how
    big."""

    var location: Vector3
    var radius: Length


def is_offset_side_occupied(
    ego_location: Vector3,
    ego_forward: Vector3,
    offset_direction: Vector3,
    offset_magnitude: Length,
    lateral_clearance: Length,
    longitudinal_window: Length,
    neighbors: List[Neighbor],
) -> Bool:
    """Return True if a vehicle stands where a wide turn would swing,
    `IsOffsetSideOccupied`.

    Args:
        ego_location: The turning vehicle, in meters.
        ego_forward: Where it faces.
        offset_direction: The way it would swing.
        offset_magnitude: How far it would swing.
        lateral_clearance: The extra room it needs to the side.
        longitudinal_window: How far ahead and behind counts as alongside.
        neighbors: The vehicles near it.

    Returns:
        Whether a neighbor is on the swing side and alongside.
    """
    for n in neighbors:
        var rx = n.location.x - ego_location.x
        var ry = n.location.y - ego_location.y
        var lateral = rx * offset_direction.x + ry * offset_direction.y
        var longitudinal = rx * ego_forward.x + ry * ego_forward.y
        var radius = n.radius.value
        var on_side = (
            lateral > -radius
            and lateral
            <= offset_magnitude.value + lateral_clearance.value + radius
        )
        var alongside = abs(longitudinal) <= longitudinal_window.value + radius
        if on_side and alongside:
            return True
    return False
