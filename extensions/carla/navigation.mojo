# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's pedestrian navigation, `nav/Navigation`: a crowd on a mesh.

A `Navigation` keeps a crowd of agents on a `NavMesh`. A walker agent
walks to a target on the mesh. A vehicle agent is a box that the walkers
keep clear of. `update_crowd` moves the walkers one step, runs the
`WalkerManager`'s routes, and gives a stuck walker a new route.

**The API** is CARLA's: `add_walker`, `add_or_update_vehicle`,
`remove_agent`, `update_vehicles`, `set_walker_max_speed`,
`set_walker_target`, `set_walker_direct_target`, `get_walker_transform`,
`get_walker_position`, `get_walker_speed`, `update_crowd`,
`get_random_location`, `set_pedestrians_cross_factor`, `pause_agent`,
`has_vehicle_near`, `set_walker_look_at`, `get_path` and
`get_agent_route`. CARLA's constants hold: a walker is 1.8 m tall with a
radius of 0.3 m and walks at 1.47 m/s at most, the crowd holds 500
agents, a vehicle's box grows by 0.8 m on each side and 0.2 m more in
front, and a walker that has moved less than 0.5 m in 4 s gets a new
random route. A new walker may cross roads anywhere with the chance
that `set_pedestrians_cross_factor` sets; otherwise it crosses only at
crosswalks. Road costs 10 a meter and grass 1.

A position is where the walker's feet touch the mesh, in CARLA's frame.
`add_walker` takes the walker's center and lowers it by half its height,
as CARLA does.

**The crowd** is this port's own simple crowd steering. CARLA's crowd
comes from a third-party library. Each step does this for each walker
that is not paused:

1. Seek: the desired velocity points at the target at the maximum speed.
   It slows in proportion within 0.6 m of the target, twice the radius.
2. Separation: each other walker nearer than twice the sum of the two
   radii pushes the walker away, by the separation weight times
   (1 - d / range) squared. Each vehicle box nearer than 0.5 m more than
   the radius pushes it away 4 times as hard.
3. The velocity moves toward the desired one by at most the maximum
   acceleration times the step, and stays under the maximum speed.
4. The walker moves, and stays on the polygons its filter allows: it
   takes the nearest point of the mesh. With no polygon near, it stops.

`has_vehicle_near` is true when a vehicle box is within the distance
and not behind the walker, against the direction given.

The yaw of `get_walker_transform` turns toward the heading of the
velocity at up to 6 times the angle a second, as CARLA's does.

The source is CARLA's `LibCarla/source/carla/nav/Navigation.cpp`.

**Differences from CARLA.**

- The crowd's steering and its constants are this port's, as above.
- CARLA loads a baked mesh file. This port builds the mesh from the map,
  `build_navigation_mesh`.
- A walker is never killed by a vehicle, so `is_walker_alive` is always
  true for a walker.
- CARLA gives a blocked walker a new filter in code that never runs; it
  is left out.
- A walker placed where no polygon is near is refused.
"""

from extensions.carla.actor import (
    ActorId,
    GREEN,
    TrafficLightState,
    YELLOW,
)
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.math import rotate_point_on_origin_2d
from extensions.carla.navigation_mesh import (
    AREA_CROSSWALK,
    AREA_ROAD,
    AREA_SIDEWALK,
    MAX_POLYS,
    NavArea,
    NavMesh,
    NavPoint,
    NavPolygonId,
    NavQueryFilter,
    sidewalk_filter,
    walker_filter,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.vector3 import Vector3
from std.math import atan2, sqrt
from std.ffi import external_call
from units.si import (
    DEGREE,
    METER,
    METER_PER_SECOND_SQUARED,
    SECOND,
    Acceleration,
    Angle,
    Duration,
    Length,
    Velocity,
)

comptime MAX_AGENTS = 500
comptime AGENT_HEIGHT = Float32(1.8)
comptime AGENT_RADIUS = Float32(0.3)
comptime AGENT_MAX_SPEED = Float32(1.47)
comptime AGENT_UNBLOCK_DISTANCE = Float32(0.5)
comptime AGENT_UNBLOCK_TIME = 4.0
# CARLA's query box: 2 m across, 4 m up and down.
comptime PICK_EXTENTS = Vector3(2, 2, 4)
# This port's steering constants.
comptime _VEHICLE_CLEARANCE = Float32(0.5)
comptime _VEHICLE_PUSH = Float32(4.0)
comptime _STAY_EXTENTS = Vector3(1, 1, 2)
comptime _TO_DEGREES = Float32(57.29577951308232)


@fieldwise_init
struct VehicleCollisionInfo(ImplicitlyCopyable):
    """A vehicle the walkers keep clear of, `VehicleCollisionInfo`."""

    var id: ActorId
    var transform: CarlaTransform
    var bounding: BoundingBox


struct CrowdAgent(Copyable, Movable):
    """One agent of the crowd: a walker or a vehicle's box."""

    var id: ActorId
    var active: Bool
    var paused: Bool
    var is_vehicle: Bool
    # Where the feet touch the mesh; a vehicle's location.
    var position: Vector3
    var velocity: Vector3
    var desired_velocity: Vector3
    var target: Optional[Vector3]
    var max_speed: Velocity
    var max_acceleration: Acceleration
    var radius: Length
    var height: Length
    var separation_weight: Float32
    # Which of the two walker filters it uses: 1 may cross roads.
    var filter_index: Int
    # A vehicle's box, grown, in the x-y plane.
    var corners: List[Vector3]
    # The polygons from the walker to its target.
    var corridor: List[NavPolygonId]

    def __init__(out self):
        """Create an inactive agent with CARLA's walker parameters."""
        self.id = ActorId(0)
        self.active = False
        self.paused = False
        self.is_vehicle = False
        self.position = Vector3(0, 0, 0)
        self.velocity = Vector3(0, 0, 0)
        self.desired_velocity = Vector3(0, 0, 0)
        self.target = None
        self.max_speed = Velocity(AGENT_MAX_SPEED)
        self.max_acceleration = Acceleration(160, METER_PER_SECOND_SQUARED)
        self.radius = Length(AGENT_RADIUS, METER)
        self.height = Length(AGENT_HEIGHT, METER)
        self.separation_weight = 0.5
        self.filter_index = 0
        self.corners = List[Vector3]()
        self.corridor = List[NavPolygonId]()


def vehicle_box(info: VehicleCollisionInfo) -> List[Vector3]:
    """Return the box the walkers keep clear of, as CARLA builds it.

    The box's half size grows by 0.8 m, and its front by 0.2 m more. It
    turns by the vehicle's yaw and moves to the vehicle's location.

    Args:
        info: The vehicle.

    Returns:
        Four corners, counter-clockwise in the x-y plane.
    """
    var hx = info.bounding.extent.x + 0.8
    var hy = info.bounding.extent.y + 0.8
    var yaw = Angle(info.transform.rotation.yaw, DEGREE)
    var at = info.transform.location
    var out = List[Vector3]()
    # The list of corners is a constant.
    for c in [  # pragma: no branch
        Vector3(-hx, -hy, 0),
        Vector3(hx + 0.2, -hy, 0),
        Vector3(hx + 0.2, hy, 0),
        Vector3(-hx, hy, 0),
    ]:
        var p = rotate_point_on_origin_2d(c, yaw)
        out.append(Vector3(p.x + at.x, p.y + at.y, at.z))
    return out^


def _flat(v: Vector3) -> Vector3:
    return Vector3(v.x, v.y, 0)


def _length(v: Vector3) -> Float32:
    return sqrt(v.x * v.x + v.y * v.y + v.z * v.z)


def _closest_on_box(corners: List[Vector3], p: Vector3) -> Tuple[Vector3, Bool]:
    # The nearest point of a box's border in the x-y plane, and whether
    # the point is inside.
    var inside = True
    var best = corners[0]
    var best_d = Float32.MAX
    # A box has four sides.
    for i in range(4):  # pragma: no branch
        var a = corners[i]
        var b = corners[(i + 1) % 4]
        var ab = b - a
        var cross = ab.x * (p.y - a.y) - ab.y * (p.x - a.x)
        if cross < 0:
            inside = False
        var t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / (
            ab.x * ab.x + ab.y * ab.y
        )
        t = min(max(t, 0), 1)
        var c = Vector3(a.x + ab.x * t, a.y + ab.y * t, p.z)
        var d = _length(_flat(c - p))
        if d < best_d:
            best_d = d
            best = c
    return (best, inside)


struct Navigation(Movable):
    """CARLA's pedestrian navigation: a crowd on a mesh."""

    var mesh: NavMesh
    var ready: Bool
    var agents: List[CrowdAgent]
    var filters: List[NavQueryFilter]
    var mapped_walkers: Dict[Int, Int]
    var mapped_vehicles: Dict[Int, Int]
    var mapped_by_index: Dict[Int, Int]
    var yaw_walkers: Dict[Int, Float32]
    var blocked_positions: Dict[Int, Vector3]
    var time_to_unblock: Float64
    var delta_seconds: Float64
    var probability_crossing: Float32
    var random: SensorRandom

    def __init__(out self, var mesh: NavMesh) raises:
        """Load a mesh and create the crowd, `Load` and `CreateCrowd`.

        Args:
            mesh: The mesh. With no polygon, the navigation is not ready
                and every call does nothing.

        Raises:
            Error: Never; the filters are constants.
        """
        self.ready = mesh.polygon_count() > 0
        self.mesh = mesh^
        self.agents = List[CrowdAgent]()
        self.filters = List[NavQueryFilter]()
        self.filters.append(walker_filter(False))
        self.filters.append(walker_filter(True))
        self.mapped_walkers = Dict[Int, Int]()
        self.mapped_vehicles = Dict[Int, Int]()
        self.mapped_by_index = Dict[Int, Int]()
        self.yaw_walkers = Dict[Int, Float32]()
        self.blocked_positions = Dict[Int, Vector3]()
        self.time_to_unblock = 0.0
        self.delta_seconds = 0.0
        self.probability_crossing = 0.0
        self.random = SensorRandom(0)

    def set_seed(mut self, seed: Int):
        """Seed the random numbers, `SetSeed`.

        Args:
            seed: The seed.
        """
        self.random = SensorRandom(seed)

    def set_pedestrians_cross_factor(mut self, percentage: Float32):
        """Set the chance that a new walker may cross roads anywhere,
        `SetPedestriansCrossFactor`.

        Args:
            percentage: 0 keeps every walker to crosswalks; 1 lets every
                walker cross anywhere when that is shorter.
        """
        self.probability_crossing = percentage

    # --- paths ------------------------------------------------------------------

    def get_path(
        self,
        from_location: Vector3,
        to: Vector3,
        filter: Optional[NavQueryFilter] = None,
    ) raises -> Optional[List[NavPoint]]:
        """Return the points of a path, `GetPath`.

        Args:
            from_location: The start.
            to: The goal.
            filter: The filter; None walks everywhere walkable, with a
                road costing 10 and grass 1.

        Returns:
            The straight path with its area crossings, or None if an end
            has no polygon near.

        Raises:
            Error: If a mesh query fails.
        """
        var f = walker_filter(True)
        if Bool(filter):
            f = filter.value()
        return self._route(from_location, to, f)

    def get_agent_route(
        self, id: ActorId, from_location: Vector3, to: Vector3
    ) raises -> Optional[List[NavPoint]]:
        """Return a walker's path with its own filter, `GetAgentRoute`.

        Args:
            id: The walker.
            from_location: The start.
            to: The goal.

        Returns:
            The straight path, or None if the walker is not in the crowd
            or an end has no polygon near.

        Raises:
            Error: If a mesh query fails.
        """
        var index = self.mapped_walkers.get(id.value)
        if not Bool(index):
            return None
        return self._route(
            from_location,
            to,
            self.filters[self.agents[index.value()].filter_index],
        )

    def _route(
        self, from_location: Vector3, to: Vector3, filter: NavQueryFilter
    ) raises -> Optional[List[NavPoint]]:
        if not self.ready:
            return None
        var start = self.mesh.find_nearest_polygon(
            from_location, filter, PICK_EXTENTS
        )
        var end = self.mesh.find_nearest_polygon(to, filter, PICK_EXTENTS)
        if not (Bool(start) and Bool(end)):
            return None
        var polys = self.mesh.find_path(
            start.value()[0], end.value()[0], from_location, to, filter
        )
        var goal = to
        var last = polys[len(polys) - 1]
        if last != end.value()[0]:
            goal = self.mesh.closest_point_on_polygon(last, to)
        return self.mesh.find_straight_path(from_location, goal, polys)

    # --- agents -----------------------------------------------------------------

    def _slot(self) -> Int:
        for i in range(len(self.agents)):
            if not self.agents[i].active:
                return i
        if len(self.agents) < MAX_AGENTS:
            return len(self.agents)
        return -1

    def _place(mut self, var agent: CrowdAgent) -> Int:
        var i = self._slot()
        if i < 0:
            return -1
        agent.active = True
        if i == len(self.agents):
            self.agents.append(agent^)
        else:
            self.agents[i] = agent^
        return i

    def add_walker(
        mut self,
        mut manager: WalkerManager,
        id: ActorId,
        from_location: Vector3,
    ) raises -> Bool:
        """Add a walker to the crowd, `AddWalker`.

        It may cross roads anywhere with the crossing chance. It stands on
        the mesh below its center, half its height lower.

        Args:
            manager: The walker manager, which gets the walker too.
            id: The walker.
            from_location: The walker's center.

        Returns:
            False if the navigation is not ready, the crowd is full, or no
            polygon is near.

        Raises:
            Error: If a mesh query fails.
        """
        if not self.ready:
            return False
        var agent = CrowdAgent()
        agent.id = id
        if Float32(self.random.uniform()) <= self.probability_crossing:
            agent.filter_index = 1
        var feet = Vector3(
            from_location.x,
            from_location.y,
            from_location.z - AGENT_HEIGHT / 2.0,
        )
        var placed = self.mesh.find_nearest_polygon(
            feet, self.filters[agent.filter_index], PICK_EXTENTS
        )
        if not Bool(placed):
            return False
        agent.position = placed.value()[1]
        var index = self._place(agent^)
        if index < 0:
            return False
        self.mapped_walkers[id.value] = index
        self.mapped_by_index[index] = id.value
        self.yaw_walkers[id.value] = 0.0
        _ = manager.add_walker(id)
        return True

    def add_or_update_vehicle(
        mut self, info: VehicleCollisionInfo
    ) raises -> Bool:
        """Add a vehicle's box to the crowd, or move it,
        `AddOrUpdateVehicle`.

        Args:
            info: The vehicle.

        Returns:
            False if the navigation is not ready or the crowd is full.

        Raises:
            Error: Never in practice; a lookup raises only on a missing
                key.
        """
        if not self.ready:
            return False
        var corners = vehicle_box(info)
        var known = self.mapped_vehicles.get(info.id.value)
        if Bool(known):
            ref agent = self.agents[known.value()]
            agent.position = info.transform.location
            agent.corners = corners^
            return True
        var agent = CrowdAgent()
        agent.id = info.id
        agent.is_vehicle = True
        agent.position = info.transform.location
        agent.radius = Length(2, METER)
        agent.max_acceleration = Acceleration(0, METER_PER_SECOND_SQUARED)
        agent.separation_weight = 100.0
        agent.corners = corners^
        var index = self._place(agent^)
        if index < 0:
            return False
        self.mapped_vehicles[info.id.value] = index
        self.mapped_by_index[index] = info.id.value
        return True

    def remove_agent(
        mut self, mut manager: WalkerManager, id: ActorId
    ) raises -> Bool:
        """Remove a walker or a vehicle from the crowd, `RemoveAgent`.

        Args:
            manager: The walker manager, which forgets a walker too.
            id: The actor.

        Returns:
            False if the navigation is not ready or the actor is not in
            the crowd.

        Raises:
            Error: Never in practice; a lookup raises only on a missing
                key.
        """
        if not self.ready:
            return False
        var walker = self.mapped_walkers.get(id.value)
        if Bool(walker):
            self.agents[walker.value()].active = False
            _ = manager.remove_walker(id)
            _ = self.mapped_walkers.pop(id.value)
            _ = self.mapped_by_index.pop(walker.value())
            return True
        var vehicle = self.mapped_vehicles.get(id.value)
        if Bool(vehicle):
            self.agents[vehicle.value()].active = False
            _ = self.mapped_vehicles.pop(id.value)
            _ = self.mapped_by_index.pop(vehicle.value())
            return True
        return False

    def update_vehicles(
        mut self,
        mut manager: WalkerManager,
        vehicles: List[VehicleCollisionInfo],
    ) raises -> Bool:
        """Add, move and remove the vehicles' boxes, `UpdateVehicles`.

        Args:
            manager: The walker manager.
            vehicles: Every vehicle there is now.

        Returns:
            True.

        Raises:
            Error: Never in practice; a lookup raises only on a missing
                key.
        """
        var stale = Dict[Int, Bool]()
        for entry in self.mapped_vehicles.items():
            stale[entry.key] = True
        for v in vehicles:
            _ = self.add_or_update_vehicle(v)
            _ = stale.pop(v.id.value, False)
        for entry in stale.items():
            _ = self.remove_agent(manager, ActorId(entry.key))
        return True

    def _walker(self, id: ActorId) -> Int:
        # The walker's index, or -1.
        if not self.ready:
            return -1
        var index = self.mapped_walkers.get(id.value)
        if not Bool(index):
            return -1
        return index.value()

    def set_walker_max_speed(
        mut self, id: ActorId, max_speed: Velocity
    ) -> Bool:
        """Change a walker's top speed, `SetWalkerMaxSpeed`.

        Args:
            id: The walker.
            max_speed: The new top speed.

        Returns:
            False if the walker is not in the crowd.
        """
        var i = self._walker(id)
        if i < 0:
            return False
        self.agents[i].max_speed = max_speed
        return True

    def set_walker_target(
        mut self, mut manager: WalkerManager, id: ActorId, to: Vector3
    ) raises -> Bool:
        """Send a walker along a route with events, `SetWalkerTarget`.

        Args:
            manager: The walker manager, which plans the route.
            id: The walker.
            to: The goal.

        Returns:
            False if the walker is not in the crowd.

        Raises:
            Error: If a mesh query fails.
        """
        if self._walker(id) < 0:
            return False
        return manager.set_walker_route_to(self, id, to)

    def set_walker_direct_target(
        mut self, id: ActorId, to: Vector3
    ) raises -> Bool:
        """Send a walker straight to a point, `SetWalkerDirectTarget`.

        Args:
            id: The walker.
            to: The point.

        Returns:
            False if the walker is not in the crowd or no polygon is near
            the point.

        Raises:
            Error: If a mesh query fails.
        """
        return self.set_walker_direct_target_index(self._walker(id), to)

    def set_walker_direct_target_index(
        mut self, index: Int, to: Vector3
    ) raises -> Bool:
        """Send a crowd agent straight to a point,
        `SetWalkerDirectTargetIndex`.

        CARLA finds the point's polygon with filter 0, whatever the
        agent's own filter.

        Args:
            index: The agent's index, or -1.
            to: The point.

        Returns:
            False for -1, or if no polygon is near the point.

        Raises:
            Error: If a mesh query fails.
        """
        if not self.ready or index < 0:
            return False
        var at = self.mesh.find_nearest_polygon(
            to, self.filters[0], PICK_EXTENTS
        )
        if not Bool(at):
            return False
        self.agents[index].target = at.value()[1]
        self._plan(index)
        return True

    def _plan(mut self, i: Int) raises:
        # The corridor: the polygons from the agent to its target.
        self.agents[i].corridor.clear()
        var f = self.filters[self.agents[i].filter_index]
        var at = self.agents[i].position
        var goal = self.agents[i].target.value()
        # The agent stands on a polygon its filter allows, and its target
        # was found with filter 0, which every walker filter allows.
        var start = self.mesh.find_nearest_polygon(at, f, PICK_EXTENTS)
        var end = self.mesh.find_nearest_polygon(goal, f, PICK_EXTENTS)
        var path = self.mesh.find_path(
            start.value()[0], end.value()[0], at, goal, f
        )
        var last = path[len(path) - 1]
        if last != end.value()[0]:
            self.agents[i].target = self.mesh.closest_point_on_polygon(
                last, goal
            )
        self.agents[i].corridor = path^

    def _corner(mut self, i: Int) raises -> Vector3:
        # The next corner of the straight path along the corridor.
        var at = self.agents[i].position
        var goal = self.agents[i].target.value()
        var k = -1
        # A plan leaves one polygon at least in the corridor.
        for j in range(len(self.agents[i].corridor)):  # pragma: no branch
            var p = self.agents[i].corridor[j].value
            if self.mesh.polygons[p].contains(at):
                k = j
                break
        if k < 0:
            self._plan(i)
            k = 0
        var rest = List[NavPolygonId]()
        # `k` is an index of the corridor.
        for j in range(k, len(self.agents[i].corridor)):  # pragma: no branch
            rest.append(self.agents[i].corridor[j])
        self.agents[i].corridor = rest.copy()
        var points = self.mesh.find_straight_path(
            at, goal, rest, MAX_POLYS, self.agents[i].radius
        )
        if len(points) < 2:
            return goal
        return points[1].location

    def get_walker_transform(mut self, id: ActorId) -> Optional[CarlaTransform]:
        """Return a walker's pose, `GetWalkerTransform`.

        The yaw turns toward the heading of the velocity, or of the
        desired velocity when the walker barely moves, by the shortest
        way, at up to 6 times the angle a second at 1.5 m/s and more.

        Args:
            id: The walker.

        Returns:
            Its feet on the mesh and its yaw, or None if it is not in the
            crowd.
        """
        var i = self._walker(id)
        if i < 0:
            return None
        ref agent = self.agents[i]
        var v = agent.velocity
        if abs(v.x) <= 0.1 and abs(v.y) <= 0.1:
            v = agent.desired_velocity
        var yaw = atan2(v.y, v.x) * _TO_DEGREES
        var speed = _length(v)
        var previous = self.yaw_walkers.get(id.value, 0.0)
        var shortest = (
            external_call["fmodf", Float32](
                yaw - previous + Float32(540.0), Float32(360.0)
            )
            - 180.0
        )
        var rotation_speed = min(speed / 1.5, 1.0) * 6.0
        var new_yaw = previous + shortest * rotation_speed * Float32(
            self.delta_seconds
        )
        self.yaw_walkers[id.value] = new_yaw
        var t = CarlaTransform(
            Length(agent.position.x, METER),
            Length(agent.position.y, METER),
            Length(agent.position.z, METER),
            CarlaRotation(
                Angle(0, DEGREE), Angle(new_yaw, DEGREE), Angle(0, DEGREE)
            ),
        )
        return t

    def get_walker_position(self, id: ActorId) -> Optional[Vector3]:
        """Return where a walker's feet are, `GetWalkerPosition`.

        Args:
            id: The walker.

        Returns:
            The position, or None if it is not in the crowd.
        """
        var i = self._walker(id)
        if i < 0:
            return None
        return self.agents[i].position

    def get_walker_speed(self, id: ActorId) -> Velocity:
        """Return a walker's speed, `GetWalkerSpeed`.

        Args:
            id: The walker.

        Returns:
            The length of its velocity, or zero if it is not in the crowd.
        """
        var i = self._walker(id)
        if i < 0:
            return Velocity(0)
        return Velocity(_length(self.agents[i].velocity))

    def get_walker_velocity(self, id: ActorId) -> Vector3:
        """Return a walker's velocity.

        Args:
            id: The walker.

        Returns:
            The velocity in m/s, or zero if it is not in the crowd.
        """
        var i = self._walker(id)
        if i < 0:
            return Vector3(0, 0, 0)
        return self.agents[i].velocity

    def get_random_location(
        mut self, filter: Optional[NavQueryFilter] = None
    ) -> Optional[Vector3]:
        """Return a random point of the mesh, `GetRandomLocation`.

        Args:
            filter: Where the point may be; None means sidewalks only.

        Returns:
            The point, or None if the navigation is not ready or no
            polygon passes.
        """
        if not self.ready:
            return None
        var f = sidewalk_filter()
        if Bool(filter):
            f = filter.value()
        var found = self.mesh.find_random_point(f, self.random)
        if not Bool(found):
            return None
        return found.value()[1]

    def pause_agent(mut self, id: ActorId, pause: Bool):
        """Stop or free a walker, `PauseAgent`.

        Args:
            id: The walker.
            pause: Whether it stands still.
        """
        var i = self._walker(id)
        if i < 0:
            return
        self.agents[i].paused = pause

    def has_vehicle_near(
        self, id: ActorId, distance: Length, direction: Vector3
    ) -> Bool:
        """Return whether a vehicle is close ahead of a walker,
        `HasVehicleNear`.

        Args:
            id: The walker, or a vehicle of the crowd.
            distance: How close.
            direction: Ahead: where the walker is going.

        Returns:
            Whether a vehicle's box is within the distance and not behind
            the walker along the direction.
        """
        var i = self.mapped_walkers.get(id.value)
        if not Bool(i):
            i = self.mapped_vehicles.get(id.value)
            if not Bool(i):
                return False
        var at = self.agents[i.value()].position
        # The actor is one of the agents.
        for j in range(len(self.agents)):  # pragma: no branch
            if j == i.value():
                continue
            ref other = self.agents[j]
            if not (other.active and other.is_vehicle):
                continue
            var near = _closest_on_box(other.corners, at)
            var to = _flat(near[0] - at)
            if near[1]:
                return True
            if _length(to) <= distance.value and (
                to.x * direction.x + to.y * direction.y >= 0
            ):
                return True
        return False

    def set_walker_look_at(mut self, id: ActorId, location: Vector3) -> Bool:
        """Turn a walker toward a point, `SetWalkerLookAt`.

        CARLA sets the velocity to a ten-thousandth of the way there.

        Args:
            id: The walker, or a vehicle of the crowd.
            location: The point.

        Returns:
            False if the actor is not in the crowd.
        """
        var i = self.mapped_walkers.get(id.value)
        if not Bool(i):
            i = self.mapped_vehicles.get(id.value)
            if not Bool(i):
                return False
        ref agent = self.agents[i.value()]
        var v = (location - agent.position) * Float32(0.0001)
        agent.velocity = v
        agent.desired_velocity = v
        return True

    def is_walker_alive(self, id: ActorId) -> Optional[Bool]:
        """Return whether a walker lives, `IsWalkerAlive`.

        Args:
            id: The walker.

        Returns:
            True, or None if it is not in the crowd. Vehicles never kill
            walkers here.
        """
        if self._walker(id) < 0:
            return None
        return True

    # --- the step ---------------------------------------------------------------

    def _steer(mut self, i: Int, dt: Float32) raises:
        var desired = Vector3(0, 0, 0)
        var max_speed = self.agents[i].max_speed.value
        if Bool(self.agents[i].target) and not self.agents[i].paused:
            var corner = self._corner(i)
            ref walker = self.agents[i]
            var to = _flat(corner - walker.position)
            var d = _length(to)
            var left = _length(_flat(walker.target.value() - walker.position))
            if d > 1e-3:
                var slow = 2.0 * walker.radius.value
                desired = to * (max_speed * min(left / slow, 1.0) / d)
        ref agent = self.agents[i]
        var push = Vector3(0, 0, 0)
        # The walker is one of the agents.
        for j in range(len(self.agents)):  # pragma: no branch
            ref other = self.agents[j]
            if j == i or not other.active:
                continue
            if other.is_vehicle:
                var near = _closest_on_box(other.corners, agent.position)
                var reach = agent.radius.value + _VEHICLE_CLEARANCE
                var away = _flat(agent.position - near[0])
                var d = _length(away)
                if near[1]:
                    away = _flat(near[0] - agent.position)
                    d = 0
                if d < reach:
                    var k = 1.0 - d / reach
                    var size = max(_length(away), Float32(1e-6))
                    push = push + away * (_VEHICLE_PUSH * k * k / size)
                continue
            var away = _flat(agent.position - other.position)
            var d = _length(away)
            var reach = 2.0 * (agent.radius.value + other.radius.value)
            if d > 0 and d < reach:
                var k = 1.0 - d / reach
                push = push + away * (agent.separation_weight * k * k / d)
        desired = desired + push * max_speed
        var speed = _length(desired)
        if speed > max_speed:
            desired = desired * (max_speed / speed)
        if agent.paused:
            desired = Vector3(0, 0, 0)
        var dv = desired - agent.velocity
        var most = agent.max_acceleration.value * dt
        var change = _length(dv)
        if change > most:
            dv = dv * (most / change)
        agent.desired_velocity = desired
        agent.velocity = agent.velocity + dv

    def _move(mut self, i: Int, dt: Float32) raises:
        var f = self.filters[self.agents[i].filter_index]
        var next = self.agents[i].position + self.agents[i].velocity * dt
        var on = self.mesh.find_nearest_polygon(next, f, _STAY_EXTENTS)
        if not Bool(on):
            self.agents[i].velocity = Vector3(0, 0, 0)
            return
        self.agents[i].position = on.value()[1]

    def update_crowd(
        mut self, mut manager: WalkerManager, delta: Duration
    ) raises:
        """Advance the crowd and the routes one step, `UpdateCrowd`.

        Every 4 s, each walker that has moved less than 0.5 m since the
        last check gets a new route to a random point.

        Args:
            manager: The walker manager.
            delta: The step.

        Raises:
            Error: If a mesh query fails.
        """
        if not self.ready:
            return
        self.delta_seconds = Float64(delta.value)
        var dt = delta.value
        for i in range(len(self.agents)):
            if self.agents[i].active and not self.agents[i].is_vehicle:
                self._steer(i, dt)
        for i in range(len(self.agents)):
            if self.agents[i].active and not self.agents[i].is_vehicle:
                self._move(i, dt)
        _ = manager.update(self, delta)
        self.time_to_unblock += self.delta_seconds
        if self.time_to_unblock < AGENT_UNBLOCK_TIME:
            return
        self.time_to_unblock = 0.0
        for i in range(len(self.agents)):
            ref agent = self.agents[i]
            if not agent.active or agent.paused or agent.is_vehicle:
                continue
            var previous = self.blocked_positions.get(i, Vector3(0, 0, 0))
            var current = agent.position
            self.blocked_positions[i] = current
            var moved = current - previous
            if (
                moved.x * moved.x + moved.y * moved.y + moved.z * moved.z
                < AGENT_UNBLOCK_DISTANCE * AGENT_UNBLOCK_DISTANCE
            ):
                var location = self.get_random_location()
                if Bool(location):
                    _ = manager.set_walker_route_to(
                        self, ActorId(self.mapped_by_index[i]), location.value()
                    )


# --- walker events, nav/WalkerEvent ------------------------------------------------


@fieldwise_init
struct EventResult(Equatable, ImplicitlyCopyable, Writable):
    """What an event says after a step, `EventResult`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for continue, end or time out.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime EVENT_CONTINUE = EventResult(0)
comptime EVENT_END = EventResult(1)
comptime EVENT_TIME_OUT = EventResult(2)


@fieldwise_init
struct WalkerEventKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of CARLA's three walker events, the `WalkerEvent` variant."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for ignore, wait or stop and check.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime EVENT_IGNORE = WalkerEventKind(0)
comptime EVENT_WAIT = WalkerEventKind(1)
comptime EVENT_STOP_AND_CHECK = WalkerEventKind(2)


@fieldwise_init
struct WalkerEvent(ImplicitlyCopyable):
    """What a walker does at a route point, `WalkerEvent`."""

    var kind: WalkerEventKind
    # The time left, for a wait and a stop and check.
    var time: Duration
    # Whether a stop and check still has to find its traffic light.
    var check_for_traffic_light: Bool
    var actor: Optional[ActorId]


def ignore_event() -> WalkerEvent:
    """Return `WalkerEventIgnore`: go on at once.

    Returns:
        The event.
    """
    return WalkerEvent(EVENT_IGNORE, Duration(0, SECOND), False, None)


def wait_event(duration: Duration) -> WalkerEvent:
    """Return `WalkerEventWait`: stand for a while.

    Args:
        duration: How long.

    Returns:
        The event.
    """
    return WalkerEvent(EVENT_WAIT, duration, False, None)


def stop_and_check_event(duration: Duration) -> WalkerEvent:
    """Return `WalkerEventStopAndCheck`: wait at a road for a clear way.

    Args:
        duration: How long before giving up.

    Returns:
        The event, which still has to find its traffic light.
    """
    return WalkerEvent(EVENT_STOP_AND_CHECK, duration, True, None)


# --- the walker manager, nav/WalkerManager -------------------------------------------


@fieldwise_init
struct WalkerState(Equatable, ImplicitlyCopyable, Writable):
    """Where a walker is on its route, `WalkerState`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for idle, walking, in an event or stopped.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3


comptime WALKER_IDLE = WalkerState(0)
comptime WALKER_WALKING = WalkerState(1)
comptime WALKER_IN_EVENT = WalkerState(2)
comptime WALKER_STOP = WalkerState(3)


@fieldwise_init
struct WalkerRoutePoint(ImplicitlyCopyable):
    """A point of a route and its event, `WalkerRoutePoint`."""

    var event: WalkerEvent
    var location: Vector3
    var area: NavArea


struct WalkerInfo(Copyable, Movable):
    """A walker's route, `WalkerInfo`."""

    var from_location: Vector3
    var to: Vector3
    var current_index: Int
    var state: WalkerState
    var route: List[WalkerRoutePoint]

    def __init__(out self):
        """Create an idle walker with no route."""
        self.from_location = Vector3(0, 0, 0)
        self.to = Vector3(0, 0, 0)
        self.current_index = 0
        self.state = WALKER_IDLE
        self.route = List[WalkerRoutePoint]()


def route_points(path: List[NavPoint]) -> List[WalkerRoutePoint]:
    """Turn a straight path into route points with events, as
    `SetWalkerRoute` does.

    Args:
        path: The points and the areas they enter.

    Returns:
        A point with no event for each point off the roads. A stop and
        check of 60 s for the first point on a road or a crosswalk after
        one off them; the next points on roads and crosswalks are left
        out. The path starts as if on a sidewalk.
    """
    var out = List[WalkerRoutePoint]()
    var previous = AREA_SIDEWALK
    for p in path:
        if p.area == AREA_ROAD or p.area == AREA_CROSSWALK:
            if previous != AREA_CROSSWALK and previous != AREA_ROAD:
                out.append(
                    WalkerRoutePoint(
                        stop_and_check_event(Duration(60, SECOND)),
                        p.location,
                        p.area,
                    )
                )
        else:
            out.append(WalkerRoutePoint(ignore_event(), p.location, p.area))
        previous = p.area
    return out^


@fieldwise_init
struct WalkerTrafficLight(ImplicitlyCopyable):
    """A place where a traffic light stops traffic, and the light's state
    now."""

    var actor: ActorId
    var location: Vector3
    var state: TrafficLightState


struct WalkerManager(Movable):
    """The walkers' routes with events, `WalkerManager`.

    A route's points come from the navigation's straight path. A point on
    a sidewalk, or on anything but a road or a crosswalk, needs no event.
    The first point of a road or a crosswalk after a safe area is a stop
    and check of up to 60 s: the walker stands while the traffic light
    nearest it lets cars go, green or yellow, then waits until no vehicle
    is within 6 m ahead toward the end of the crosswalk. The other points
    on a road or a crosswalk are left out, as CARLA leaves them. A walker
    within 1 m of a point runs its event and then goes on to the next
    point. At the end, or when a stop and check times out, it gets a new
    route to a random point.

    Where CARLA plans a new route again and again while a route has fewer
    than two points, this port plans once more and then waits.
    """

    var walkers: Dict[Int, WalkerInfo]
    # The walkers' ids in the order they were added.
    var order: List[Int]
    var traffic_lights: List[WalkerTrafficLight]

    def __init__(out self):
        """Create a manager with no walkers and no lights."""
        self.walkers = Dict[Int, WalkerInfo]()
        self.order = List[Int]()
        self.traffic_lights = List[WalkerTrafficLight]()

    def add_walker(mut self, id: ActorId) -> Bool:
        """Give a walker an empty route, `AddWalker`.

        Args:
            id: The walker.

        Returns:
            True.
        """
        if id.value not in self.walkers:
            self.order.append(id.value)
        self.walkers[id.value] = WalkerInfo()
        return True

    def remove_walker(mut self, id: ActorId) raises -> Bool:
        """Forget a walker's route, `RemoveWalker`.

        Args:
            id: The walker.

        Returns:
            False if the walker has no route.

        Raises:
            Error: Never in practice; the order holds every walker.
        """
        if id.value not in self.walkers:
            return False
        _ = self.walkers.pop(id.value)
        # The walker is in the order, since it has a route.
        for i in range(len(self.order)):  # pragma: no branch
            if self.order[i] == id.value:
                _ = self.order.pop(i)
                break
        return True

    def set_traffic_lights(mut self, var lights: List[WalkerTrafficLight]):
        """Set the places where lights stop traffic,
        `GetAllTrafficLightWaypoints`.

        Args:
            lights: One entry for each stop waypoint of each light.
        """
        self.traffic_lights = lights^

    def set_light_state(mut self, actor: ActorId, state: TrafficLightState):
        """Tell the manager a light's state.

        Args:
            actor: The light.
            state: Its state now.
        """
        for i in range(len(self.traffic_lights)):
            if self.traffic_lights[i].actor == actor:
                self.traffic_lights[i].state = state

    def get_traffic_light_affecting(
        self, position: Vector3, max_distance: Optional[Length] = None
    ) -> Optional[WalkerTrafficLight]:
        """Return the light whose stop place is nearest a point,
        `GetTrafficLightAffecting`.

        Args:
            position: The point.
            max_distance: How far the place may be; None for any.

        Returns:
            The light, or None if there is none within the distance.
        """
        var best = Optional[WalkerTrafficLight](None)
        var best_d = Float32.MAX
        for light in self.traffic_lights:
            var d = position.distance_to_squared(light.location)
            if d < best_d:
                best_d = d
                best = light
        if Bool(max_distance) and best_d > (
            max_distance.value().value * max_distance.value().value
        ):
            return None
        return best

    def update(mut self, mut nav: Navigation, delta: Duration) raises -> Bool:
        """Advance every walker's route one step, `Update`.

        Args:
            nav: The navigation.
            delta: The step.

        Returns:
            True.

        Raises:
            Error: If a mesh query fails.
        """
        for id in self.order.copy():
            var state = self.walkers[id].state
            if state == WALKER_WALKING:
                ref info = self.walkers[id]
                var target = info.route[info.current_index].location
                var current = nav.get_walker_position(ActorId(id))
                if Bool(current) and (
                    current.value().distance_to_squared(target) <= 1.0
                ):
                    info.state = WALKER_IN_EVENT
            elif state == WALKER_IN_EVENT:
                var result = self._execute_event(nav, ActorId(id), delta)
                if result == EVENT_END:
                    _ = self.set_walker_next_point(nav, ActorId(id))
                elif result == EVENT_TIME_OUT:
                    _ = self.set_walker_route(nav, ActorId(id))
            elif state == WALKER_STOP:
                self.walkers[id].state = WALKER_IDLE
        return True

    def set_walker_route(
        mut self, mut nav: Navigation, id: ActorId
    ) raises -> Bool:
        """Send a walker to a random point, `SetWalkerRoute(id)`.

        Args:
            nav: The navigation.
            id: The walker.

        Returns:
            False if there is no random point or the walker has no route.

        Raises:
            Error: If a mesh query fails.
        """
        return self._route_to_random(nav, id, True)

    def _route_to_random(
        mut self, mut nav: Navigation, id: ActorId, replan: Bool
    ) raises -> Bool:
        var location = nav.get_random_location()
        if not Bool(location):
            return False
        return self._route_to(nav, id, location.value(), replan)

    def set_walker_route_to(
        mut self, mut nav: Navigation, id: ActorId, to: Vector3
    ) raises -> Bool:
        """Plan a walker's route with events, `SetWalkerRoute(id, to)`.

        Args:
            nav: The navigation.
            id: The walker.
            to: The goal.

        Returns:
            False if the walker has no route.

        Raises:
            Error: If a mesh query fails.
        """
        return self._route_to(nav, id, to, True)

    def _route_to(
        mut self, mut nav: Navigation, id: ActorId, to: Vector3, replan: Bool
    ) raises -> Bool:
        if id.value not in self.walkers:
            return False
        var start = nav.get_walker_position(id)
        var path = List[NavPoint]()
        if Bool(start):
            var found = nav.get_agent_route(id, start.value(), to)
            if Bool(found):
                path = found.value().copy()
        ref info = self.walkers[id.value]
        info.from_location = start.or_else(Vector3(0, 0, 0))
        info.to = to
        info.current_index = 0
        info.state = WALKER_IDLE
        info.route = route_points(path)
        _ = self._next_point(nav, id, replan)
        return True

    def set_walker_next_point(
        mut self, mut nav: Navigation, id: ActorId
    ) raises -> Bool:
        """Send a walker to its next route point, `SetWalkerNextPoint`.

        Past the last point the walker stops and gets a new random route.

        Args:
            nav: The navigation.
            id: The walker.

        Returns:
            False if the walker has no route.

        Raises:
            Error: If a mesh query fails.
        """
        return self._next_point(nav, id, True)

    def _next_point(
        mut self, mut nav: Navigation, id: ActorId, replan: Bool
    ) raises -> Bool:
        if id.value not in self.walkers:
            return False
        ref info = self.walkers[id.value]
        info.current_index += 1
        if info.current_index < len(info.route):
            info.state = WALKER_WALKING
            var target = info.route[info.current_index].location
            nav.pause_agent(id, False)
            _ = nav.set_walker_direct_target(id, target)
            return True
        info.state = WALKER_STOP
        nav.pause_agent(id, True)
        if replan:
            _ = self._route_to_random(nav, id, False)
        return True

    def get_walker_next_point(self, id: ActorId) -> Optional[Vector3]:
        """Return the point a walker goes to, `GetWalkerNextPoint`.

        Args:
            id: The walker.

        Returns:
            The point, or None if the walker has no route or is past its
            end.
        """
        var info = self.walkers.get(id.value)
        if not Bool(info):
            return None
        ref route = info.value().route
        var i = info.value().current_index
        if i < len(route):
            return route[i].location
        return None

    def get_walker_crosswalk_end(self, id: ActorId) -> Optional[Vector3]:
        """Return where the crosswalk a walker is on ends,
        `GetWalkerCrosswalkEnd`.

        Args:
            id: The walker.

        Returns:
            The first route point from the current one that is not on a
            crosswalk, or None.
        """
        var info = self.walkers.get(id.value)
        if not Bool(info):
            return None
        ref route = info.value().route
        for i in range(info.value().current_index, len(route)):
            if route[i].area != AREA_CROSSWALK:
                return route[i].location
        return None

    def _execute_event(
        mut self, mut nav: Navigation, id: ActorId, delta: Duration
    ) raises -> EventResult:
        # The visitor of `WalkerEventVisitor`. The event changes in place.
        var index = self.walkers[id.value].current_index
        var event = self.walkers[id.value].route[index].event
        var result = self._visit(nav, id, delta, event)
        self.walkers[id.value].route[index].event = event
        return result

    def _visit(
        self,
        mut nav: Navigation,
        id: ActorId,
        delta: Duration,
        mut event: WalkerEvent,
    ) -> EventResult:
        if event.kind == EVENT_IGNORE:
            return EVENT_END
        event.time = event.time - delta
        if event.kind == EVENT_WAIT:
            if event.time.value <= 0.0:
                return EVENT_END
            return EVENT_CONTINUE
        if event.time.value <= 0.0:
            return EVENT_TIME_OUT
        nav.pause_agent(id, True)
        var at = nav.get_walker_position(id).or_else(Vector3(0, 0, 0))
        if event.check_for_traffic_light:
            var light = self.get_traffic_light_affecting(at)
            if Bool(light):
                event.actor = light.value().actor
            event.check_for_traffic_light = False
        if Bool(event.actor):
            var state = GREEN
            # The event's light came from this list.
            for l in self.traffic_lights:  # pragma: no branch
                if l.actor == event.actor.value():
                    state = l.state
            if state == GREEN or state == YELLOW:
                return EVENT_CONTINUE
        nav.pause_agent(id, False)
        var end = self.get_walker_crosswalk_end(id).or_else(Vector3(0, 0, 0))
        var direction = end - at
        if not nav.has_vehicle_near(id, Length(6, METER), direction):
            return EVENT_END
        return EVENT_CONTINUE
