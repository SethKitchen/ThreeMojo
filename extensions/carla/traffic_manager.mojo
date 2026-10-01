# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's traffic manager, in the same process as the world.

The traffic manager drives the vehicles registered with it: each step
it reads the world, runs its five stages and sends one command a
vehicle back to the world.

```mojo
var tm = TrafficManagerLocal(world)
tm.set_synchronous_mode(True)
tm.register_vehicles(world, [car])
tm.set_percentage_speed_difference(car, -20.0)
for _ in range(100):
    _ = tm.tick(world)
```

`tick` is CARLA's synchronous loop: the world ticks, and then the
traffic manager steps, so its commands act on the next tick.

**One step** (CARLA's `TrafficManagerLocal::Step`):

1. ALSM, the actor life-cycle manager, finds the actors that came and
   went, finds the hero (a vehicle with the role name "hero"), reads
   every actor's pose, speed, size, speed limit and light, turns physics
   off for the registered vehicles out of the hero's hybrid radius, and
   destroys a registered vehicle that has not moved for 90 s (180 s at a
   red light), one each 10 s.
2. Localization, collision, traffic lights, motion planning and vehicle
   lights run for each registered vehicle, in that order.
3. The commands go to the world.

**What the world lacks.** The world has no `set_simulate_physics`. To
turn a vehicle's physics off, the traffic manager makes its body
kinematic and stops it; the body then moves only where the traffic
manager puts it. The world never makes an actor dormant, as CARLA's
large maps do; a caller can mark one with `ACTOR_DORMANT`.

**Not ported.** The remote traffic manager and its RPC server and
client, the worker thread of asynchronous mode (`step` is called by
hand instead), and the wall-clock wait of asynchronous hybrid mode.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/TrafficManagerLocal.cpp`,
`ALSM.cpp`, `AtomicActorSet.h` and `TrafficManager.cpp`.
"""

from extensions.carla.actor import (
    ACTOR_DORMANT,
    ActorId,
    NO_ACTOR,
    RED,
    TrafficLightState,
)
from extensions.carla.physics.body import DYNAMIC, KINEMATIC
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.traffic_manager_collision import CollisionStage
from extensions.carla.traffic_manager_constants import (
    BLOCKED_TIME_THRESHOLD,
    DELTA_TIME_BETWEEN_DESTRUCTIONS,
    INV_HYBRID_DT,
    RED_TL_BLOCKED_TIME_THRESHOLD,
    STOPPED_VELOCITY_THRESHOLD,
)
from extensions.carla.traffic_manager_localization import LocalizationStage
from extensions.carla.traffic_manager_map import InMemoryMap, RoadOption
from extensions.carla.traffic_manager_parameters import Parameters
from extensions.carla.traffic_manager_pid import (
    LATERAL_HIGHWAY_PARAM,
    LATERAL_PARAM,
    LONGITUDINAL_HIGHWAY_PARAM,
    LONGITUDINAL_PARAM,
    PIDParameters,
)
from extensions.carla.traffic_manager_planning import (
    MotionPlanStage,
    TrafficLightStage,
    VehicleLightStage,
)
from extensions.carla.traffic_manager_random import RandomGenerator
from extensions.carla.traffic_manager_shared import (
    APPLY_TRANSFORM,
    APPLY_VEHICLE_CONTROL,
    LargeVehicle,
    NO_COMMAND,
    SET_VEHICLE_LIGHT_STATE,
    TrafficAction,
    TrafficCommand,
    TrafficManagerShared,
)
from extensions.carla.traffic_manager_state import (
    KinematicState,
    StaticAttributes,
    TRAFFIC_ANY,
    TRAFFIC_PEDESTRIAN,
    TRAFFIC_VEHICLE,
    TrafficLightInfo,
)
from extensions.carla.traffic_manager_map import SimpleWaypointIndex
from extensions.carla.world import World
from math.vector3 import Vector3
from std.collections import Dict, Optional
from std.math import isnan
from std.time import perf_counter_ns
from units.si import Duration, Length, METER, Velocity
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR


# --- the registered vehicles ---------------------------------------------------


struct ActorSet(Movable):
    """The registered vehicles, CARLA's `AtomicActorSet`: ids in order,
    and a counter that moves on each change."""

    var ids: List[Int]
    var state: Int

    def __init__(out self):
        """Create an empty set."""
        self.ids = List[Int]()
        self.state = 0

    def get_id_list(self) -> List[ActorId]:
        """Return the ids, `GetIDList`.

        Returns:
            The ids, from the lowest.
        """
        var out = List[ActorId]()
        for id in self.ids:
            out.append(ActorId(id))
        return out^

    def insert(mut self, actors: List[ActorId]) raises:
        """Add vehicles, `Insert`. The counter moves once.

        Args:
            actors: The vehicles.

        Raises:
            Error: If an id is not valid.
        """
        for actor in actors:
            if not actor.is_valid():
                raise Error("Actor id is not valid")
            if actor.value in self.ids:
                continue
            var k = len(self.ids)
            while k > 0 and self.ids[k - 1] > actor.value:
                k -= 1
            self.ids.insert(k, actor.value)
        self.state += 1

    def remove(mut self, actors: List[ActorId]):
        """Remove vehicles, `Remove`. The counter moves once.

        Args:
            actors: The vehicles; unknown ones are ignored.
        """
        for actor in actors:
            for i in range(len(self.ids)):
                if self.ids[i] == actor.value:
                    _ = self.ids.pop(i)
                    break
        self.state += 1

    def destroy(mut self, actor: ActorId, mut world: World) raises:
        """Destroy a vehicle in the world and forget it, `Destroy`. The
        counter moves only if it was here.

        Args:
            actor: The vehicle.
            world: The world.

        Raises:
            Error: If the world fails to destroy it.
        """
        if actor.value in self.ids:
            _ = world.destroy_actor(actor)
            self.remove([actor])

    def contains(self, actor: ActorId) -> Bool:
        """Return True if a vehicle is here, `Contains`.

        Args:
            actor: The vehicle.

        Returns:
            Whether it is.
        """
        return actor.value in self.ids

    def size(self) -> Int:
        """Return how many vehicles are here, `Size`.

        Returns:
            The count.
        """
        return len(self.ids)

    def clear(mut self):
        """Forget every vehicle, `Clear`. The counter stays."""
        self.ids = List[Int]()


# --- the world adapter ----------------------------------------------------------


def set_simulate_physics(
    mut world: World, actor: ActorId, enabled: Bool
) raises:
    """Turn an actor's physics on or off, CARLA's `SetSimulatePhysics`.

    The world has no such call. Off makes the body kinematic and stops
    it; on makes it dynamic again. An actor without a body is left as it
    is.

    Args:
        world: The world.
        actor: The actor.
        enabled: True for on.

    Raises:
        Error: If the id names no living actor.
    """
    var body = world.actor(actor).body
    if body.value < 0:
        return
    ref b = world.physics.world.bodies[body.value]
    if enabled:
        b.kind = DYNAMIC
    else:
        b.kind = KINEMATIC
        b.linear_velocity = Vector3(0, 0, 0)
        b.angular_velocity = Vector3(0, 0, 0)


def is_physics_enabled(world: World, actor: ActorId) raises -> Bool:
    """Return True if physics moves an actor's body.

    Args:
        world: The world.
        actor: The actor.

    Returns:
        Whether it has a dynamic body.

    Raises:
        Error: If the id names no living actor.
    """
    var body = world.actor(actor).body
    return (
        body.value >= 0
        and world.physics.world.bodies[body.value].kind == DYNAMIC
    )


def _pedal(value: Float32) -> Float32:
    if isnan(value):
        return 0.0
    return value


def apply_batch(mut world: World, commands: List[TrafficCommand]) raises:
    """Send commands to the world, CARLA's `ApplyBatchSync`.

    A teleport of a vehicle without physics also stops its body. A NaN
    pedal, which CARLA passes on, goes to the world as zero, since the
    world refuses it.

    Args:
        world: The world.
        commands: The commands, in order.

    Raises:
        Error: If a command's kind is not valid, or the world refuses a
            command.
    """
    for command in commands:
        if not command.kind.is_valid():
            raise Error("A traffic manager command's kind is not valid")
        if command.kind == APPLY_VEHICLE_CONTROL:
            var control = command.control
            control.throttle = _pedal(control.throttle)
            control.brake = _pedal(control.brake)
            world.apply_control(command.actor, control)
        elif command.kind == APPLY_TRANSFORM:
            world.set_transform(command.actor, command.transform)
            if not is_physics_enabled(world, command.actor):
                set_simulate_physics(world, command.actor, False)
        elif command.kind == SET_VEHICLE_LIGHT_STATE:
            world.set_light_state(command.actor, command.light_state)


def _is_dormant(world: World, actor: ActorId) raises -> Bool:
    return world.actor(actor).state == ACTOR_DORMANT


# --- ALSM ----------------------------------------------------------------------


def _drop(mut list: List[Int], value: Int):
    for i in range(len(list)):
        if list[i] == value:
            _ = list.pop(i)
            return


struct ALSM(Movable):
    """The actor life-cycle manager, CARLA's `ALSM`."""

    # The actors the traffic manager does not drive, in order found.
    var unregistered_actors: List[Int]
    # When each registered vehicle last moved, in seconds.
    var idle_time: Dict[Int, Float64]
    var hero_actors: List[Int]
    var elapsed_last_actor_destruction: Float64
    var current_time: Float64
    var has_physics_enabled: Dict[Int, Bool]

    def __init__(out self):
        """Create an empty manager."""
        self.unregistered_actors = List[Int]()
        self.idle_time = Dict[Int, Float64]()
        self.hero_actors = List[Int]()
        self.elapsed_last_actor_destruction = 0.0
        self.current_time = 0.0
        self.has_physics_enabled = Dict[Int, Bool]()

    def update(
        mut self,
        mut world: World,
        mut registered: ActorSet,
        mut shared: TrafficManagerShared,
        mut localization: LocalizationStage,
        mut collision: CollisionStage,
        mut traffic_light: TrafficLightStage,
        mut motion_plan: MotionPlanStage,
    ) raises:
        """Bring the tracked actors up to date, `ALSM::Update`.

        Args:
            world: The world.
            registered: The registered vehicles.
            shared: The traffic manager's state.
            localization: The localization stage.
            collision: The collision stage.
            traffic_light: The traffic-light stage.
            motion_plan: The motion-planning stage.

        Raises:
            Error: If a world query fails.
        """
        var hybrid = shared.parameters.get_hybrid_physics_mode()
        self.current_time = world.get_snapshot().timestamp.elapsed_seconds
        var actors = world.get_actors()
        var alive = List[Int]()
        # The spectator is always alive.
        for actor in actors:  # pragma: no branch
            alive.append(actor.value)
        # The actors that are gone.
        var gone_registered = List[Int]()
        for id in registered.ids:
            if id not in alive:
                gone_registered.append(id)
        var gone_unregistered = List[Int]()
        for id in self.unregistered_actors:
            if id not in alive or registered.contains(ActorId(id)):
                gone_unregistered.append(id)
        for id in gone_registered:
            self.remove_actor(
                ActorId(id),
                True,
                registered,
                shared,
                localization,
                collision,
                traffic_light,
                motion_plan,
            )
        for id in gone_unregistered:
            self.remove_actor(
                ActorId(id),
                False,
                registered,
                shared,
                localization,
                collision,
                traffic_light,
                motion_plan,
            )
        for id in gone_registered:
            _drop(self.hero_actors, id)
        # The actors that are new, and the hero.
        # The spectator is always alive.
        for actor in actors:  # pragma: no branch
            ref record = world.actors[actor.value - 1]
            if (
                record.type_id.startswith("v")
                and actor.value not in self.hero_actors
            ):
                if record.role_name() == "hero":
                    self.hero_actors.append(actor.value)
            if (
                not registered.contains(actor)
                and actor.value not in self.unregistered_actors
            ):
                self.unregistered_actors.append(actor.value)
        var max_idle = (NO_ACTOR, self.current_time)
        self._update_registered(world, registered, shared, hybrid, max_idle)
        if (
            self.is_vehicle_stuck(max_idle[0], shared)
            and self.current_time - self.elapsed_last_actor_destruction
            > Float64(DELTA_TIME_BETWEEN_DESTRUCTIONS.value)
            and max_idle[0].value not in self.hero_actors
        ):
            registered.destroy(max_idle[0], world)
            self.remove_actor(
                max_idle[0],
                True,
                registered,
                shared,
                localization,
                collision,
                traffic_light,
                motion_plan,
            )
            self.elapsed_last_actor_destruction = self.current_time
        if shared.parameters.get_osm_mode():
            var marked = shared.marked_for_removal.copy()
            for actor in marked:
                registered.destroy(actor, world)
                self.remove_actor(
                    actor,
                    True,
                    registered,
                    shared,
                    localization,
                    collision,
                    traffic_light,
                    motion_plan,
                )
            shared.marked_for_removal = List[ActorId]()
        self._update_unregistered(world, shared)

    def _update_registered(
        mut self,
        mut world: World,
        registered: ActorSet,
        mut shared: TrafficManagerShared,
        hybrid: Bool,
        mut max_idle: Tuple[ActorId, Float64],
    ) raises:
        var hero_present = len(self.hero_actors) != 0
        var radius = shared.parameters.get_hybrid_physics_radius().value
        var respawn = shared.parameters.get_respawn_dormant_vehicles()
        if respawn and not hero_present:
            shared.track_traffic.set_hero_location(Vector3(0, 0, 0))
        for hero in self.hero_actors.copy():
            if respawn:
                shared.track_traffic.set_hero_location(
                    world.get_location(ActorId(hero))
                )
            self._update_data(
                world,
                ActorId(hero),
                shared,
                hybrid,
                hero_present,
                radius * radius,
            )
        for id in registered.ids:
            if id not in self.hero_actors:
                self._update_data(
                    world,
                    ActorId(id),
                    shared,
                    hybrid,
                    hero_present,
                    radius * radius,
                )
                self._update_idle_time(max_idle, ActorId(id), shared)

    def _update_data(
        mut self,
        mut world: World,
        actor: ActorId,
        mut shared: TrafficManagerShared,
        hybrid: Bool,
        hero_present: Bool,
        radius_square: Float32,
    ) raises:
        var a = actor.value
        var transform = world.get_transform(actor)
        var location = transform.location
        var velocity = world.get_velocity(actor)
        var present = shared.simulation_state.contains_actor(actor)
        if a not in self.idle_time and self.current_time != 0.0:
            self.idle_time[a] = self.current_time
        var in_range = False
        if hero_present and hybrid:
            # There is a hero here.
            for hero in self.hero_actors:  # pragma: no branch
                if shared.simulation_state.contains_actor(ActorId(hero)):
                    var at = shared.simulation_state.get_location(ActorId(hero))
                    var d = location - at
                    if d.dot(d) < radius_square:
                        in_range = True
                        break
        var enable = in_range if hybrid else True
        var known = self.has_physics_enabled.get(a)
        if (
            not Bool(known) or known.value() != enable
        ) and a not in self.hero_actors:
            set_simulate_physics(world, actor, enable)
            self.has_physics_enabled[a] = enable
            if enable and present:
                world.set_target_velocity(
                    actor, shared.simulation_state.get_velocity(actor)
                )
        if present and not shared.simulation_state.is_physics_enabled(actor):
            var previous = shared.simulation_state.get_location(actor)
            var end = shared.simulation_state.get_hybrid_end_location(actor)
            velocity = (end - previous) * Float32(INV_HYBRID_DT)
        var kinematic = KinematicState(
            location,
            transform.rotation,
            velocity,
            world.get_speed_limit(actor),
            enable,
            _is_dormant(world, actor),
            Vector3(0, 0, 0),
        )
        var light = TrafficLightInfo(
            world.get_traffic_light_state(actor),
            world.is_at_traffic_light(actor),
        )
        if present:
            shared.simulation_state.update_kinematic_state(actor, kinematic)
            shared.simulation_state.update_traffic_light_state(actor, light)
        else:
            var extent = world.get_bounding_box(actor).extent
            shared.simulation_state.add_actor(
                actor,
                kinematic,
                StaticAttributes(
                    TRAFFIC_VEHICLE,
                    Length(extent.x),
                    Length(extent.y),
                    Length(extent.z),
                ),
                light,
            )

    def _update_unregistered(
        mut self, world: World, mut shared: TrafficManagerShared
    ) raises:
        # The spectator is never registered: registering it makes
        # `_update_data` raise before this runs.
        for id in self.unregistered_actors:  # pragma: no branch
            var actor = ActorId(id)
            var record = world.actor(actor)
            var transform = world.get_transform(actor)
            var location = transform.location
            var kinematic = KinematicState(
                location,
                transform.rotation,
                world.get_velocity(actor),
                Velocity(-1.0, KILOMETER_PER_HOUR),
                True,
                _is_dormant(world, actor),
                Vector3(0, 0, 0),
            )
            var nearest = List[SimpleWaypointIndex]()
            var absent = not shared.simulation_state.contains_actor(actor)
            var extent = record.bounding_box.extent
            if record.type_id.startswith("v"):
                kinematic.speed_limit = world.get_speed_limit(actor)
                var light = TrafficLightInfo(
                    world.get_traffic_light_state(actor),
                    world.is_at_traffic_light(actor),
                )
                if absent:
                    shared.simulation_state.add_actor(
                        actor,
                        kinematic,
                        StaticAttributes(
                            TRAFFIC_VEHICLE,
                            Length(extent.x),
                            Length(extent.y),
                            Length(extent.z),
                        ),
                        light,
                    )
                else:
                    shared.simulation_state.update_kinematic_state(
                        actor, kinematic
                    )
                    shared.simulation_state.update_traffic_light_state(
                        actor, light
                    )
                var heading = transform.rotation.forward_vector()
                # Three corners, always.
                for corner in [  # pragma: no branch
                    location + heading * extent.x,
                    location,
                    location + heading * -extent.x,
                ]:
                    nearest.append(shared.local_map.get_waypoint(corner))
            elif record.type_id.startswith("w"):
                if absent:
                    shared.simulation_state.add_actor(
                        actor,
                        kinematic,
                        StaticAttributes(
                            TRAFFIC_PEDESTRIAN,
                            Length(extent.x),
                            Length(extent.y),
                            Length(extent.z),
                        ),
                        TrafficLightInfo(TrafficLightState(0), False),
                    )
                else:
                    shared.simulation_state.update_kinematic_state(
                        actor, kinematic
                    )
                nearest.append(shared.local_map.get_waypoint(location))
            shared.track_traffic.update_unregistered_grid_position(
                actor, nearest, shared.local_map
            )

    def _update_idle_time(
        mut self,
        mut max_idle: Tuple[ActorId, Float64],
        actor: ActorId,
        shared: TrafficManagerShared,
    ) raises:
        var a = actor.value
        if a not in self.idle_time:
            return
        var v = shared.simulation_state.get_velocity(actor)
        if v.dot(v) > (
            STOPPED_VELOCITY_THRESHOLD.value * STOPPED_VELOCITY_THRESHOLD.value
        ):
            self.idle_time[a] = self.current_time
        if max_idle[0] == NO_ACTOR or max_idle[1] > self.idle_time[a]:
            max_idle = (actor, self.idle_time[a])

    def is_vehicle_stuck(
        self, actor: ActorId, shared: TrafficManagerShared
    ) raises -> Bool:
        """Return True if a vehicle has been still too long,
        `IsVehicleStuck`.

        Args:
            actor: The vehicle.
            shared: The traffic manager's state.

        Returns:
            Whether it has been idle 180 s, or 90 s away from a red light.

        Raises:
            Error: If an idle vehicle is not tracked.
        """
        var since = self.idle_time.get(actor.value)
        if not Bool(since):
            return False
        var delta = self.current_time - since.value()
        var light = shared.simulation_state.get_tls(actor)
        return delta >= Float64(RED_TL_BLOCKED_TIME_THRESHOLD.value) or (
            delta >= Float64(BLOCKED_TIME_THRESHOLD.value)
            and light.tl_state != RED
        )

    def add_actor(
        mut self, world: World, actor: ActorId, mut shared: TrafficManagerShared
    ) raises:
        """Note a new registered vehicle's size class, `ALSM::AddActor`.

        A vehicle whose `base_type` is "bus" or "truck", in any case, is a
        large vehicle.

        Args:
            world: The world.
            actor: The vehicle.
            shared: The traffic manager's state.

        Raises:
            Error: If the id names no living actor.
        """
        var base_type = world.actor(actor).attribute("base_type")
        if Bool(base_type):
            var value = base_type.value().value.lower()
            if value == "bus" or value == "truck":
                shared.large_vehicles[actor.value] = LargeVehicle(
                    Length(0), False
                )

    def remove_actor(
        mut self,
        actor: ActorId,
        registered_actor: Bool,
        mut registered: ActorSet,
        mut shared: TrafficManagerShared,
        mut localization: LocalizationStage,
        mut collision: CollisionStage,
        mut traffic_light: TrafficLightStage,
        mut motion_plan: MotionPlanStage,
    ) raises:
        """Forget an actor everywhere, `ALSM::RemoveActor`.

        Args:
            actor: The actor.
            registered_actor: Whether it is a registered vehicle.
            registered: The registered vehicles.
            shared: The traffic manager's state.
            localization: The localization stage.
            collision: The collision stage.
            traffic_light: The traffic-light stage.
            motion_plan: The motion-planning stage.

        Raises:
            Error: If the id is not valid.
        """
        var a = actor.value
        if registered_actor:
            registered.remove([actor])
            if a in shared.buffer_map:
                _ = shared.buffer_map.pop(a)
            if a in self.idle_time:
                _ = self.idle_time.pop(a)
            localization.remove_actor(actor)
            collision.remove_actor(actor)
            traffic_light.remove_actor(actor)
            motion_plan.remove_actor(actor)
            if a in shared.large_vehicles:
                _ = shared.large_vehicles.pop(a)
        else:
            _drop(self.unregistered_actors, a)
            _drop(self.hero_actors, a)
        shared.track_traffic.delete_actor(actor)
        shared.simulation_state.remove_actor(actor)

    def reset(mut self, world: World):
        """Forget the unregistered actors and the heroes, `ALSM::Reset`.

        Args:
            world: The world, for the time now.
        """
        self.unregistered_actors = List[Int]()
        self.idle_time = Dict[Int, Float64]()
        self.hero_actors = List[Int]()
        self.elapsed_last_actor_destruction = 0.0
        self.current_time = world.get_snapshot().timestamp.elapsed_seconds


# --- the traffic manager ------------------------------------------------------------


def _clock_seed() -> UInt64:
    return UInt64(perf_counter_ns())


struct TrafficManagerLocal(Movable):
    """CARLA's `TrafficManagerLocal`: the traffic manager of one world."""

    var shared: TrafficManagerShared
    var registered_vehicles: ActorSet
    var registered_vehicles_state: Int
    var localization_stage: LocalizationStage
    var collision_stage: CollisionStage
    var traffic_light_stage: TrafficLightStage
    var motion_plan_stage: MotionPlanStage
    var vehicle_light_stage: VehicleLightStage
    var alsm: ALSM
    var last_frame: Int
    var seed: UInt64
    var map_name: String

    def __init__(
        out self,
        world: World,
        perc_difference_from_limit: Float32 = 0.0,
        seed: Optional[UInt64] = None,
        map_name: String = "",
        cache: Optional[List[UInt8]] = None,
        longitudinal: PIDParameters = LONGITUDINAL_PARAM,
        longitudinal_highway: PIDParameters = LONGITUDINAL_HIGHWAY_PARAM,
        lateral: PIDParameters = LATERAL_PARAM,
        lateral_highway: PIDParameters = LATERAL_HIGHWAY_PARAM,
    ) raises:
        """Create a traffic manager for a world, as CARLA's constructor
        and `SetupLocalMap` do.

        Args:
            world: The world.
            perc_difference_from_limit: The global speed difference, in
                percent.
            seed: The random seed; a clock reading by default, as CARLA
                takes the time.
            map_name: The map's name, as CARLA's `Map::GetName` gives it.
            cache: A saved `InMemoryMap`, to load instead of building one.
            longitudinal: The speed loop's gains at or below 60 km/h.
            longitudinal_highway: The speed loop's gains above 60 km/h.
            lateral: The heading loop's gains at or below 60 km/h.
            lateral_highway: The heading loop's gains above 60 km/h.

        Raises:
            Error: If the map cannot be built or the cache cannot be read.
        """
        self.seed = seed.value() if Bool(seed) else _clock_seed()
        self.map_name = map_name
        self.shared = TrafficManagerShared(
            _local_map(world, map_name, cache), self.seed
        )
        self.registered_vehicles = ActorSet()
        self.registered_vehicles_state = -1
        self.localization_stage = LocalizationStage()
        self.collision_stage = CollisionStage()
        self.traffic_light_stage = TrafficLightStage()
        self.motion_plan_stage = MotionPlanStage(
            longitudinal, longitudinal_highway, lateral, lateral_highway
        )
        self.vehicle_light_stage = VehicleLightStage()
        self.alsm = ALSM()
        self.last_frame = 0
        self.shared.parameters.set_global_percentage_speed_difference(
            perc_difference_from_limit
        )

    # --- running -------------------------------------------------------------------

    def step(mut self, mut world: World) raises:
        """Run one step and send its commands, `Step`.

        In asynchronous mode, a step on a frame already stepped does
        nothing.

        Args:
            world: The world.

        Raises:
            Error: If a stage or a command fails.
        """
        var synchronous = self.shared.parameters.get_synchronous_mode()
        self.shared.parameters.set_max_boundaries(
            Length(20.0), world.get_settings().actor_active_distance
        )
        var timestamp = world.get_snapshot().timestamp
        if not synchronous:
            if timestamp.frame == self.last_frame:
                return
            self.last_frame = timestamp.frame
        self.alsm.update(
            world,
            self.registered_vehicles,
            self.shared,
            self.localization_stage,
            self.collision_stage,
            self.traffic_light_stage,
            self.motion_plan_stage,
        )
        if (
            self.registered_vehicles_state != self.registered_vehicles.state
            or len(self.shared.vehicle_id_list)
            != self.registered_vehicles.size()
        ):
            self.shared.vehicle_id_list = self.registered_vehicles.get_id_list()
            self.registered_vehicles_state = self.registered_vehicles.state
        self.shared.reset_frames()
        var count = len(self.shared.vehicle_id_list)
        for i in range(count):
            self.localization_stage.update(i, self.shared)
        for i in range(count):
            self.collision_stage.update(i, self.shared)
        self.collision_stage.clear_cycle_cache()
        self.vehicle_light_stage.update_world_info(
            world.get_vehicles_light_states(), world.get_weather()
        )
        for i in range(count):
            self.traffic_light_stage.update(i, self.shared, timestamp)
            self.motion_plan_stage.update(i, self.shared, world.map, timestamp)
            self.vehicle_light_stage.update(i, self.shared)
        apply_batch(world, self.shared.control_frame)

    def synchronous_tick(mut self, mut world: World) raises -> Bool:
        """Step once if in synchronous mode, `SynchronousTick`.

        Args:
            world: The world.

        Returns:
            True, as CARLA's.

        Raises:
            Error: If the step fails.
        """
        if self.shared.parameters.get_synchronous_mode():
            self.step(world)
        return True

    def tick(mut self, mut world: World) raises -> Int:
        """Tick the world, then step, as CARLA's client `World::Tick` does
        with a traffic manager running.

        Args:
            world: The world.

        Returns:
            The world's new frame.

        Raises:
            Error: If the world's tick or the step fails.
        """
        var frame = world.tick()
        _ = self.synchronous_tick(world)
        return frame

    def stop(mut self):
        """Forget every vehicle and all state, `Stop`."""
        self.shared.vehicle_id_list = List[ActorId]()
        self.registered_vehicles.clear()
        self.registered_vehicles_state = -1
        self.shared.track_traffic.clear()
        self.shared.simulation_state.reset()
        self.localization_stage.reset()
        self.collision_stage.reset()
        self.traffic_light_stage.reset()
        self.motion_plan_stage.reset()
        self.shared.buffer_map = Dict[Int, List[SimpleWaypointIndex]]()
        self.shared.localization_frame.clear()
        self.shared.collision_frame.clear()
        self.shared.tl_frame.clear()
        self.shared.control_frame.clear()

    def release(mut self):
        """Stop and drop the map, `Release`."""
        self.stop()
        self.shared.local_map = InMemoryMap(self.map_name)

    def reset(mut self, world: World) raises:
        """Release and build the map again for a world, `Reset`.

        Args:
            world: The world, perhaps with a new map.

        Raises:
            Error: If the map cannot be built.
        """
        self.release()
        self.shared.local_map = _local_map(world, self.map_name, None)

    # --- vehicles --------------------------------------------------------------------

    def register_vehicles(mut self, world: World, actors: List[ActorId]) raises:
        """Hand vehicles to the traffic manager, `RegisterVehicles`.

        Args:
            world: The world.
            actors: The vehicles.

        Raises:
            Error: If an id is not valid or names no living actor.
        """
        self.registered_vehicles.insert(actors)
        for actor in actors:
            self.alsm.add_actor(world, actor, self.shared)

    def unregister_vehicles(mut self, actors: List[ActorId]) raises:
        """Take vehicles back from the traffic manager,
        `UnregisterVehicles`.

        Args:
            actors: The vehicles.

        Raises:
            Error: If an id is not valid.
        """
        for actor in actors:
            self.alsm.remove_actor(
                actor,
                True,
                self.registered_vehicles,
                self.shared,
                self.localization_stage,
                self.collision_stage,
                self.traffic_light_stage,
                self.motion_plan_stage,
            )

    def get_registered_vehicles_ids(self) -> List[ActorId]:
        """Return the registered vehicles, `GetRegisteredVehiclesIDs`.

        Returns:
            Their ids, from the lowest.
        """
        return self.registered_vehicles.get_id_list()

    def get_next_action(self, actor: ActorId) raises -> TrafficAction:
        """Return a vehicle's next move, `GetNextAction`.

        Args:
            actor: The vehicle.

        Returns:
            Its next road option and where.

        Raises:
            Error: If its path is empty.
        """
        return self.localization_stage.compute_next_action(actor, self.shared)

    def get_action_buffer(self, actor: ActorId) raises -> List[TrafficAction]:
        """Return a vehicle's moves along its path, `GetActionBuffer`.

        Args:
            actor: The vehicle.

        Returns:
            The moves.

        Raises:
            Error: If its path is empty.
        """
        return self.localization_stage.compute_action_buffer(actor, self.shared)

    def check_all_frozen(
        self, world: World, lights: List[ActorId]
    ) raises -> Bool:
        """Return True if every light is frozen at red, `CheckAllFrozen`.

        Args:
            world: The world.
            lights: The traffic lights.

        Returns:
            Whether each light is frozen and red; True for no lights.

        Raises:
            Error: If an id names no traffic light.
        """
        for light in lights:
            if (
                not world.is_frozen(light)
                or world.get_traffic_light_state_of(light) != RED
            ):
                return False
        return True

    # --- settings ------------------------------------------------------------------

    def parameters(ref self) -> ref[self.shared.parameters] Parameters:
        """Return the settings, for the getters.

        Returns:
            The settings.
        """
        return self.shared.parameters

    def set_synchronous_mode(mut self, mode: Bool):
        """Turn synchronous mode on or off, `SetSynchronousMode`.

        Args:
            mode: True for on.
        """
        self.shared.parameters.set_synchronous_mode(mode)

    def set_synchronous_mode_time_out(mut self, time: Duration):
        """Set the synchronous time out,
        `SetSynchronousModeTimeOutInMiliSecond`.

        Args:
            time: The time out.
        """
        self.shared.parameters.set_synchronous_mode_time_out(time)

    def set_random_device_seed(mut self, seed: UInt64, mut world: World):
        """Seed the random draws again and reset the lights,
        `SetRandomDeviceSeed`.

        Args:
            seed: The seed.
            world: The world, whose lights reset.
        """
        self.seed = seed
        self.shared.random_device = RandomGenerator(seed)
        world.reset_all_traffic_lights()

    def set_percentage_speed_difference(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """See `Parameters.set_percentage_speed_difference`.

        Args:
            actor: The vehicle.
            percentage: The difference.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_percentage_speed_difference(
            actor, percentage
        )

    def set_desired_speed(mut self, actor: ActorId, value: Velocity) raises:
        """See `Parameters.set_desired_speed`.

        Args:
            actor: The vehicle.
            value: The speed.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_desired_speed(actor, value)

    def set_global_percentage_speed_difference(mut self, percentage: Float32):
        """See `Parameters.set_global_percentage_speed_difference`.

        Args:
            percentage: The difference.
        """
        self.shared.parameters.set_global_percentage_speed_difference(
            percentage
        )

    def set_lane_offset(mut self, actor: ActorId, offset: Length) raises:
        """See `Parameters.set_lane_offset`.

        Args:
            actor: The vehicle.
            offset: The offset.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_lane_offset(actor, offset)

    def set_global_lane_offset(mut self, offset: Length):
        """See `Parameters.set_global_lane_offset`.

        Args:
            offset: The offset.
        """
        self.shared.parameters.set_global_lane_offset(offset)

    def set_large_vehicle_wide_turn(
        mut self, actor: ActorId, enable: Bool
    ) raises:
        """See `Parameters.set_large_vehicle_wide_turn`.

        Args:
            actor: The vehicle.
            enable: True for on.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_large_vehicle_wide_turn(actor, enable)

    def set_global_large_vehicle_wide_turn(mut self, enable: Bool):
        """See `Parameters.set_global_large_vehicle_wide_turn`.

        Args:
            enable: True for on.
        """
        self.shared.parameters.set_global_large_vehicle_wide_turn(enable)

    def set_update_vehicle_lights(
        mut self, actor: ActorId, do_update: Bool
    ) raises:
        """See `Parameters.set_update_vehicle_lights`.

        Args:
            actor: The vehicle.
            do_update: True to let the traffic manager switch them.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_update_vehicle_lights(actor, do_update)

    def set_collision_detection(
        mut self, reference_actor: ActorId, other_actor: ActorId, detect: Bool
    ) raises:
        """See `Parameters.set_collision_detection`.

        Args:
            reference_actor: The vehicle.
            other_actor: The other actor.
            detect: True to avoid it.

        Raises:
            Error: If an id is not valid.
        """
        self.shared.parameters.set_collision_detection(
            reference_actor, other_actor, detect
        )

    def set_force_lane_change(mut self, actor: ActorId, direction: Bool) raises:
        """See `Parameters.set_force_lane_change`.

        Args:
            actor: The vehicle.
            direction: True for right, False for left.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_force_lane_change(actor, direction)

    def set_auto_lane_change(mut self, actor: ActorId, enable: Bool) raises:
        """See `Parameters.set_auto_lane_change`.

        Args:
            actor: The vehicle.
            enable: True for on.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_auto_lane_change(actor, enable)

    def set_distance_to_leading_vehicle(
        mut self, actor: ActorId, distance: Length
    ) raises:
        """See `Parameters.set_distance_to_leading_vehicle`.

        Args:
            actor: The vehicle.
            distance: The gap.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_distance_to_leading_vehicle(actor, distance)

    def set_global_distance_to_leading_vehicle(mut self, distance: Length):
        """See `Parameters.set_global_distance_to_leading_vehicle`.

        Args:
            distance: The gap.
        """
        self.shared.parameters.set_global_distance_to_leading_vehicle(distance)

    def set_percentage_ignore_walkers(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """See `Parameters.set_percentage_ignore_walkers`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_percentage_ignore_walkers(actor, percentage)

    def set_percentage_ignore_vehicles(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """See `Parameters.set_percentage_ignore_vehicles`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_percentage_ignore_vehicles(actor, percentage)

    def set_percentage_running_light(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """See `Parameters.set_percentage_running_light`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_percentage_running_light(actor, percentage)

    def set_percentage_running_sign(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """See `Parameters.set_percentage_running_sign`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_percentage_running_sign(actor, percentage)

    def set_keep_slow_lane_percentage(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """See `Parameters.set_keep_slow_lane_percentage`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_keep_slow_lane_percentage(actor, percentage)

    def set_random_left_lane_change_percentage(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """See `Parameters.set_random_left_lane_change_percentage`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_random_left_lane_change_percentage(
            actor, percentage
        )

    def set_random_right_lane_change_percentage(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """See `Parameters.set_random_right_lane_change_percentage`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_random_right_lane_change_percentage(
            actor, percentage
        )

    def set_hybrid_physics_mode(mut self, mode_switch: Bool):
        """See `Parameters.set_hybrid_physics_mode`.

        Args:
            mode_switch: True for on.
        """
        self.shared.parameters.set_hybrid_physics_mode(mode_switch)

    def set_hybrid_physics_radius(mut self, radius: Length):
        """See `Parameters.set_hybrid_physics_radius`.

        Args:
            radius: The radius.
        """
        self.shared.parameters.set_hybrid_physics_radius(radius)

    def set_osm_mode(mut self, mode_switch: Bool):
        """See `Parameters.set_osm_mode`.

        Args:
            mode_switch: True for on.
        """
        self.shared.parameters.set_osm_mode(mode_switch)

    def set_custom_path(
        mut self, actor: ActorId, var path: List[Vector3], empty_buffer: Bool
    ) raises:
        """See `Parameters.set_custom_path`.

        Args:
            actor: The vehicle.
            path: The points.
            empty_buffer: True to drop its path first.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.set_custom_path(actor, path^, empty_buffer)

    def remove_upload_path(mut self, actor: ActorId, remove_path: Bool) raises:
        """See `Parameters.remove_upload_path`.

        Args:
            actor: The vehicle.
            remove_path: True to drop the points, False the flag.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.remove_upload_path(actor, remove_path)

    def update_upload_path(
        mut self, actor: ActorId, var path: List[Vector3]
    ) raises:
        """See `Parameters.update_upload_path`.

        Args:
            actor: The vehicle.
            path: The points.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.update_upload_path(actor, path^)

    def set_imported_route(
        mut self,
        actor: ActorId,
        var route: List[RoadOption],
        empty_buffer: Bool,
    ) raises:
        """See `Parameters.set_imported_route`.

        Args:
            actor: The vehicle.
            route: The road options.
            empty_buffer: True to drop its path first.

        Raises:
            Error: If the id or a road option is not valid.
        """
        self.shared.parameters.set_imported_route(actor, route^, empty_buffer)

    def remove_imported_route(
        mut self, actor: ActorId, remove_path: Bool
    ) raises:
        """See `Parameters.remove_imported_route`.

        Args:
            actor: The vehicle.
            remove_path: True to drop the route, False the flag.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.remove_imported_route(actor, remove_path)

    def update_imported_route(
        mut self, actor: ActorId, var route: List[RoadOption]
    ) raises:
        """See `Parameters.update_imported_route`.

        Args:
            actor: The vehicle.
            route: The road options.

        Raises:
            Error: If the id is not valid.
        """
        self.shared.parameters.update_imported_route(actor, route^)

    def set_respawn_dormant_vehicles(mut self, mode_switch: Bool):
        """See `Parameters.set_respawn_dormant_vehicles`.

        Args:
            mode_switch: True for on.
        """
        self.shared.parameters.set_respawn_dormant_vehicles(mode_switch)

    def set_boundaries_respawn_dormant_vehicles(
        mut self, lower_bound: Length, upper_bound: Length
    ):
        """See `Parameters.set_boundaries_respawn_dormant_vehicles`.

        Args:
            lower_bound: The nearest.
            upper_bound: The farthest.
        """
        self.shared.parameters.set_boundaries_respawn_dormant_vehicles(
            lower_bound, upper_bound
        )

    def set_max_boundaries(mut self, lower: Length, upper: Length):
        """See `Parameters.set_max_boundaries`.

        Args:
            lower: The least lower bound.
            upper: The most upper bound.
        """
        self.shared.parameters.set_max_boundaries(lower, upper)


def _local_map(
    world: World, name: String, cache: Optional[List[UInt8]]
) raises -> InMemoryMap:
    """CARLA's `SetupLocalMap`: load the cache if there is one, else build
    the map."""
    var local = InMemoryMap(name)
    if Bool(cache) and len(cache.value()) != 0:
        _ = local.load(world.map, cache.value())
    else:
        local.set_up(world.map)
    return local^
