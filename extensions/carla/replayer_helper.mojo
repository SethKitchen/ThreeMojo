# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the replayer does to a world for each record,
`CarlaReplayerHelper`.

Each function takes the world and one record, already given the ids of
the world's actors, and changes the world as CARLA's replayer helper
changes its episode:

- `process_event_add` spawns the actor of an `EventAdd` record, or finds
  the traffic light or sign that is already there.
- `process_event_del` and `process_event_parent` remove and attach.
- `process_position` moves an actor to a recorded pose, or between two.
- The others set a light's state, a vehicle's control, lights and doors,
  a walker's speed and bones, and the weather.
- `process_finish` hands the vehicles back to physics, stopped.

**Between two poses.** The location moves in a straight line. Each of the
pitch, yaw and roll moves the shorter way round: from 170 to -170 degrees
it passes 180, not 0. At a fraction of zero the actor takes the first
pose as it is.

**Differences from CARLA.**

- CARLA turns off a replayed vehicle's or walker's physics and its
  collisions. The world here cannot, so the helper turns off its gravity
  and stops it. The replayer then sets its pose after the world's tick,
  so the recorded pose wins.
- A vehicle or a walker spawns 1000 m above its place and then moves
  there, as CARLA spawns it 1 km up. So actors that appear in the same
  frame do not meet another's box on the way.
- The world cannot attach a vehicle or a walker, or remove a traffic
  light, a sign or the spectator. Those events do nothing.
- The world has no scene lights and no bicycle or wheel animation, so the
  replayer keeps those records for a renderer to read.
- CARLA also hands its vehicles to its autopilot at the end, and removes
  the movable props of its map at the start. The world has neither.

The source is CARLA's simulator plugin, `Carla/Recorder/
CarlaReplayerHelper.cpp`.
"""

from extensions.carla.actor import (
    ActorId,
    ActorKind,
    NO_ACTOR,
    TRAFFIC_LIGHT_ACTOR,
    TRAFFIC_SIGN_ACTOR,
    VEHICLE_ACTOR,
    WALKER_ACTOR,
    compose,
)
from extensions.carla.physics.vehicle_control import Gear, VehicleControl
from extensions.carla.physics.walker import WalkerControl
from extensions.carla.recorder_packets import (
    LogVector,
    RecordedAnimVehicle,
    RecordedDescription,
    RecordedDoorVehicle,
    RecordedLightVehicle,
    RecordedPosition,
    RecordedTrafficLight,
    RecordedWalkerBones,
    RecordedWeather,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.walker import BoneTransformDataIn, WalkerBoneControlIn
from extensions.carla.weather import WeatherParameters
from extensions.carla.world import World
from math.vector3 import Vector3
from units.si import SECOND, Duration, Length, Velocity

# What `process_event_add` did.
comptime NOT_CREATED = 0
comptime CREATED = 1
comptime REUSED = 2
comptime IGNORED = 3

# How far above its place a vehicle or a walker spawns, in meters.
comptime _SPAWN_LIFT = Float32(1000)


def is_hero(description: RecordedDescription) -> Bool:
    """Return whether a blueprint's `role_name` is `hero`.

    Args:
        description: The recorded blueprint.

    Returns:
        True for a hero.
    """
    for a in description.attributes:
        if a.id == "role_name" and a.value == "hero":
            return True
    return False


def recorded_transform(
    location: LogVector, rotation: LogVector
) -> CarlaTransform:
    """Return a recorded pose in the world's units.

    Args:
        location: The location in centimeters.
        rotation: The roll, pitch and yaw in degrees.

    Returns:
        The pose in meters and degrees.
    """
    var out = CarlaTransform(
        Length(0), Length(0), Length(0), rotation.to_rotation()
    )
    out.location = location.to_meters()
    return out


def _truncated(v: Float64) -> Int:
    """C's cast of a `double` to an `int`: the whole part."""
    return Int(v)


def find_traffic_sign_at(world: World, location: LogVector) raises -> ActorId:
    """Find a traffic light or sign by its place, `FindTrafficSignAt`.

    Args:
        world: The world.
        location: The recorded place, in centimeters.

    Returns:
        The first light or sign whose place, cut to whole centimeters,
        is the recorded place cut the same way; or `NO_ACTOR`.

    Raises:
        Error: If a pose cannot be read.
    """
    var x = _truncated(location.x)
    var y = _truncated(location.y)
    var z = _truncated(location.z)
    # The spectator is always in the list.
    for i in range(len(world.actors)):  # pragma: no branch
        var id = ActorId(i + 1)
        if not world.is_alive(id):
            continue
        var kind = world.actors[i].kind
        if kind != TRAFFIC_LIGHT_ACTOR and kind != TRAFFIC_SIGN_ACTOR:
            continue
        var at = LogVector.from_meters(world.get_location(id))
        if (
            _truncated(at.x) == x
            and _truncated(at.y) == y
            and _truncated(at.z) == z
        ):
            return id
    return NO_ACTOR


def _spawn(
    mut world: World,
    location: LogVector,
    rotation: LogVector,
    description: RecordedDescription,
) raises -> ActorId:
    """Spawn from the world's blueprint with the recorded values."""
    var found = world.blueprints.find(description.id)
    if not Bool(found):
        return NO_ACTOR
    var blueprint = found.value().copy()
    for a in description.attributes:
        if not blueprint.contains_attribute(a.id):
            continue
        if not blueprint.attribute(a.id).is_modifiable:
            continue
        try:
            blueprint.set_attribute(a.id, a.value)
        except:
            # A value the blueprint refuses keeps the blueprint's own.
            pass
    var pose = recorded_transform(location, rotation)
    var physical = description.id.startswith(
        "vehicle."
    ) or description.id.startswith("walker.")
    var spawn_pose = pose
    if physical:
        spawn_pose.location.z += _SPAWN_LIFT
    var made = world.try_spawn_actor(blueprint, spawn_pose)
    if not Bool(made):
        return NO_ACTOR
    var id = made.value()
    if physical:
        world.set_transform(id, pose)
    return id


def process_event_add(
    mut world: World,
    location: LogVector,
    rotation: LogVector,
    description: RecordedDescription,
    ignore_hero: Bool,
    ignore_spectator: Bool,
    replay_sensors: Bool,
) raises -> Tuple[Int, ActorId]:
    """Make the actor of an `EventAdd` record, `ProcessReplayerEventAdd`.

    A hero is ignored when heroes are, and the spectator when it is. A
    traffic light or sign is not made: the one at the recorded place is
    used. A sensor is made only when sensors are replayed. A vehicle or a
    walker that is made has its gravity turned off and stands still.

    Args:
        world: The world.
        location: The recorded place, in centimeters.
        rotation: The recorded roll, pitch and yaw.
        description: The recorded blueprint.
        ignore_hero: Whether to leave heroes out.
        ignore_spectator: Whether to leave the spectator out.
        replay_sensors: Whether to make sensors.

    Returns:
        What was done, `NOT_CREATED`, `CREATED`, `REUSED` or `IGNORED`,
        and the actor, or `NO_ACTOR`.

    Raises:
        Error: If the world refuses an operation.
    """
    var hero = is_hero(description)
    if (ignore_hero and hero) or (
        ignore_spectator and description.id.startswith("spectator")
    ):
        return (IGNORED, NO_ACTOR)
    var result = NOT_CREATED
    var id = NO_ACTOR
    if description.id.startswith("traffic."):
        id = find_traffic_sign_at(world, location)
        if id != NO_ACTOR:
            result = REUSED
    elif replay_sensors or not description.id.startswith("sensor."):
        id = _spawn(world, location, rotation, description)
        if id != NO_ACTOR:
            result = CREATED
    if result == NOT_CREATED:
        return (NOT_CREATED, NO_ACTOR)
    # An ignored hero returned above, so every vehicle and walker here is
    # replayed: CARLA's branch for an ignored hero cannot run.
    var kind = world.actors[id.value - 1].kind
    if kind == VEHICLE_ACTOR or kind == WALKER_ACTOR:
        world.set_enable_gravity(id, False)
        world.set_target_velocity(id, Vector3(0, 0, 0))
    return (result, id)


def process_event_del(mut world: World, id: ActorId) raises -> Bool:
    """Remove an actor, `ProcessReplayerEventDel`.

    Args:
        world: The world.
        id: The actor.

    Returns:
        Whether the actor was removed.

    Raises:
        Error: If a pose cannot be read.
    """
    return world.destroy_actor(id)


def process_event_parent(
    mut world: World, child: ActorId, parent: ActorId
) raises -> Bool:
    """Attach an actor to another, `ProcessReplayerEventParent`.

    The child keeps its pose as its pose in the parent's frame, as a rigid
    attachment that keeps the relative transform does. The child was
    spawned at the pose it was spawned with, which is in the parent's
    frame.

    Args:
        world: The world.
        child: The actor to attach.
        parent: The actor it follows.

    Returns:
        Whether the child was attached: False when either is not alive,
        or the child is a vehicle or a walker.

    Raises:
        Error: Never; the checks come first.
    """
    if not (world.is_alive(child) and world.is_alive(parent)):
        return False
    ref c = world.actors[child.value - 1]
    if c.kind == VEHICLE_ACTOR or c.kind == WALKER_ACTOR:
        return False
    c.parent = parent
    return True


def lerp_angle(a: Float64, b: Float64, fraction: Float64) -> Float64:
    """Move from one angle to another the shorter way round.

    Args:
        a: The first angle, in degrees.
        b: The second angle, in degrees.
        fraction: How far, from 0 to 1.

    Returns:
        The first angle plus the fraction of the turn from it to the
        second, where that turn is
        wrapped into (-180, 180] degrees. The result is not wrapped.
    """
    var turn = b - a
    turn = turn - 360.0 * Float64(Int(turn / 360.0))
    if turn > 180:
        turn -= 360
    elif turn <= -180:
        turn += 360
    return a + turn * fraction


def interpolated_transform(
    pos1: RecordedPosition, pos2: RecordedPosition, per: Float64
) -> CarlaTransform:
    """Return the pose between two records, as the helper sets it.

    Args:
        pos1: The first record.
        pos2: The second record.
        per: The fraction of the way, from 0 to 1. At 0 the first pose is
            taken as it is.

    Returns:
        The pose in meters and degrees.
    """
    if per == 0.0:
        return recorded_transform(pos1.location, pos1.rotation)
    var a = pos1.location
    var b = pos2.location
    var location = LogVector(
        a.x + (b.x - a.x) * per,
        a.y + (b.y - a.y) * per,
        a.z + (b.z - a.z) * per,
    )
    var r1 = pos1.rotation
    var r2 = pos2.rotation
    var rotation = LogVector(
        lerp_angle(r1.x, r2.x, per),
        lerp_angle(r1.y, r2.y, per),
        lerp_angle(r1.z, r2.z, per),
    )
    return recorded_transform(location, rotation)


def process_position(
    mut world: World,
    pos1: RecordedPosition,
    pos2: RecordedPosition,
    per: Float64,
) raises -> Bool:
    """Move an actor to a recorded pose, `ProcessReplayerPosition`.

    Args:
        world: The world.
        pos1: The first record; its id names the actor.
        pos2: The second record.
        per: The fraction of the way from the first to the second.

    Returns:
        Whether the actor is alive and moved.

    Raises:
        Error: If the world refuses the move.
    """
    if not world.is_alive(pos1.database_id):
        return False
    world.set_transform(
        pos1.database_id, interpolated_transform(pos1, pos2, per)
    )
    return True


def process_state_traffic_light(
    mut world: World, state: RecordedTrafficLight
) raises -> Bool:
    """Set a traffic light, `ProcessReplayerStateTrafficLight`.

    Args:
        world: The world.
        state: The record, with the world's id.

    Returns:
        Whether the actor is a traffic light that is alive.

    Raises:
        Error: If the state is not valid.
    """
    var id = state.database_id
    if not world.is_alive(id):
        return False
    if world.actors[id.value - 1].kind != TRAFFIC_LIGHT_ACTOR:
        return False
    world.set_traffic_light_state(id, state.state)
    var h = world.actors[id.value - 1].handle
    var c = world.traffic_lights.lights[h].controller
    if c >= 0:
        ref controller = world.traffic_lights.controllers[c]
        controller.elapsed = Duration(state.elapsed_time, SECOND)
        if controller.group >= 0:
            world.traffic_lights.groups[
                controller.group
            ].frozen = state.is_frozen
    return True


def _is(world: World, id: ActorId, kind: ActorKind) -> Bool:
    return world.is_alive(id) and world.actors[id.value - 1].kind == kind


def process_anim_vehicle(mut world: World, vehicle: RecordedAnimVehicle) raises:
    """Apply a recorded control, `ProcessReplayerAnimVehicle`.

    Args:
        world: The world.
        vehicle: The record, with the world's id.

    Raises:
        Error: If the gear is not valid.
    """
    if not _is(world, vehicle.database_id, VEHICLE_ACTOR):
        return
    var control = VehicleControl()
    control.throttle = vehicle.throttle
    control.steer = vehicle.steering
    control.brake = vehicle.brake
    control.hand_brake = vehicle.handbrake
    control.reverse = vehicle.gear.value < 0
    control.gear = vehicle.gear
    control.manual_gear_shift = False
    world.apply_control(vehicle.database_id, control)


def process_door_vehicle(mut world: World, door: RecordedDoorVehicle) raises:
    """Open or close a door, `ProcessReplayerDoorVehicle`.

    Args:
        world: The world.
        door: The record, with the world's id. A door that is not valid
            does nothing.

    Raises:
        Error: Never; the checks come first.
    """
    if not (
        _is(world, door.database_id, VEHICLE_ACTOR) and door.doors.is_valid()
    ):
        return
    if door.is_open:
        world.open_door(door.database_id, door.doors)
    else:
        world.close_door(door.database_id, door.doors)


def process_light_vehicle(mut world: World, light: RecordedLightVehicle) raises:
    """Set a vehicle's lights, `ProcessReplayerLightVehicle`.

    Args:
        world: The world.
        light: The record, with the world's id.

    Raises:
        Error: If the light state is not valid.
    """
    if _is(world, light.database_id, VEHICLE_ACTOR):
        world.set_light_state(light.database_id, light.state)


def weather_of(record: RecordedWeather) -> WeatherParameters:
    """Return a recorded weather as the world's weather.

    Args:
        record: The record.

    Returns:
        The weather.
    """
    return WeatherParameters(
        record.cloudiness,
        record.precipitation,
        record.precipitation_deposits,
        record.wind_intensity,
        record.sun_azimuth_angle,
        record.sun_altitude_angle,
        record.fog_density,
        record.fog_distance,
        record.fog_falloff,
        record.wetness,
        record.scattering_intensity,
        record.mie_scattering_scale,
        record.rayleigh_scattering_scale,
        record.dust_storm,
    )


def process_weather(mut world: World, record: RecordedWeather):
    """Set the weather, `ProcessReplayerWeather`.

    Args:
        world: The world.
        record: The record.
    """
    world.set_weather(weather_of(record))


def set_walker_speed(mut world: World, id: ActorId, speed: Float32) raises:
    """Set a walker's speed, `SetWalkerSpeed`.

    Args:
        world: The world.
        id: The walker.
        speed: The speed in centimeters per second. The walker faces
            forward, CARLA's default control.

    Raises:
        Error: Never; the check comes first.
    """
    if not _is(world, id, WALKER_ACTOR):
        return
    var control = WalkerControl()
    control.speed = Velocity(speed / 100)
    world.apply_walker_control(id, control)


def process_walker_bones(mut world: World, walker: RecordedWalkerBones) raises:
    """Pose a walker's bones, `ProcessReplayerWalkerBones`.

    Args:
        world: The world.
        walker: The record, with the world's id.

    Raises:
        Error: If the pose cannot be blended.
    """
    if not _is(world, walker.database_id, WALKER_ACTOR):
        return
    var bones = List[BoneTransformDataIn]()
    for b in walker.bones:
        bones.append(
            BoneTransformDataIn(
                b.name, recorded_transform(b.location, b.rotation)
            )
        )
    world.set_bones_transform(walker.database_id, WalkerBoneControlIn(bones^))
    world.blend_pose(walker.database_id, 1)


def set_camera_position(
    mut world: World, id: ActorId, offset: CarlaTransform
) raises -> Bool:
    """Put the spectator behind an actor, `SetCameraPosition`.

    Args:
        world: The world.
        id: The actor to follow.
        offset: The spectator's pose in the actor's frame.

    Returns:
        Whether the actor and the spectator are alive.

    Raises:
        Error: If a pose cannot be read.
    """
    var spectator = world.get_spectator()
    if not (world.is_alive(id) and world.is_alive(spectator)):
        return False
    world.set_transform(spectator, compose(world.get_transform(id), offset))
    return True


def process_finish(
    mut world: World, ignore_hero: Bool, heroes: List[ActorId]
) raises:
    """Hand the actors back to the world, `ProcessReplayerFinish`.

    Each vehicle, but an ignored hero, gets its gravity back, stops, and
    gets a control with every pedal released in first gear. Each walker
    stops.

    Args:
        world: The world.
        ignore_hero: Whether heroes were left out of the replay.
        heroes: The replayed actors that are heroes.

    Raises:
        Error: If the world refuses an operation.
    """
    # The spectator is always in the list.
    for i in range(len(world.actors)):  # pragma: no branch
        var id = ActorId(i + 1)
        if not world.is_alive(id):
            continue
        var kind = world.actors[i].kind
        if kind == VEHICLE_ACTOR:
            if ignore_hero and id in heroes:
                continue
            world.set_enable_gravity(id, True)
            world.set_target_velocity(id, Vector3(0, 0, 0))
            var control = VehicleControl()
            control.gear = Gear(1)
            world.apply_control(id, control)
        elif kind == WALKER_ACTOR:
            set_walker_speed(world, id, 0)
