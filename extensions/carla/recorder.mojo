# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's recorder: a world's frames written in CARLA's log format.

`Recorder.start` begins a recording of a `World`. After each
`World.tick`, `Recorder.record` writes one frame; `Recorder.tick` does
both. `Recorder.stop` ends the recording and writes the file.

```mojo
var recorder = Recorder()
_ = recorder.start(world, "/tmp/run.log", additional_data=True)
for _ in range(100):
    _ = recorder.tick(world)
recorder.stop()
```

**What one frame holds.** As CARLA's recorder does, each frame holds:

- the actors that appeared since the last frame, with their blueprints,
  the parents of those that have one, and the actors that went;
- the hits that a collision sensor saw, once for each pair;
- the doors that opened or closed, and the weather when it changed;
- the pose of each vehicle, walker and plain actor, in centimeters and
  degrees;
- each vehicle's control and lights, each walker's speed in centimeters
  per second, and each traffic light's state, elapsed time and freeze;
- with `additional_data`: each vehicle's and walker's velocities, each
  walker's bones, the time on the machine's clock since the start, and,
  for each new actor, its box, or a sign's or light's trigger volume, a
  vehicle's physics control and a light's stage times.

The first frame also holds every actor that was there at the start, and
the weather. A new actor's pose is the one it was spawned with, in its
parent's frame when it has a parent, as CARLA records it. An actor that
was there at the start has its pose in the world.

**How the recorder learns of events.** CARLA's simulator tells its
recorder of each spawn, removal, attachment, door and weather change as
it happens. The world here does not call out, so `record` compares the
world with what it saw at the last frame. The result is the same frame.

When a recorded collision sensor is destroyed, its private collision-pair
registry is released with the deletion event. Already queued records keep
their order and actor ids. Other sensors keep their own registries.

**Differences from CARLA.**

- The recording stays in memory until `stop`, which writes the whole file.
  `bytes` returns it at any time. An empty name records to memory only.
- An opened or closed door is found by comparing each door, so opening
  all the doors records one event for each door where CARLA records one
  event for all of them.
- A vehicle's physics control is recorded when it spawns. A later change
  is recorded by `add_physics_control`, and a change of a light's times by
  `add_traffic_light_time`: the world does not report them.
- The world has no scene lights, bicycle animation or wheel animation.
  `add_light_scene`, `add_anim_biker` and `add_anim_wheels` record them
  when the caller has them. CARLA's current recorder does not record the
  wheels or the bicycles either.
- The visual time is the world's elapsed time. The platform time is read
  from a monotonic clock.
- CARLA keeps a frame's collisions in a hash set and writes them in the
  set's order. This port writes them in the order they happened.

The source is CARLA's simulator plugin, `Carla/Recorder/
CarlaRecorder.cpp`, `Carla/Game/CarlaEpisode.cpp` (spawns, removals and
attachments), `Carla/Sensor/CollisionSensor.cpp` (collisions) and
`Carla/Weather/Weather.cpp` (weather).
"""

from extensions.carla.actor import (
    ActorId,
    GREEN,
    NO_ACTOR,
    RED,
    YELLOW,
    OTHER_ACTOR,
    TRAFFIC_LIGHT_ACTOR,
    TRAFFIC_SIGN_ACTOR,
    VEHICLE_ACTOR,
    WALKER_ACTOR,
    rotation_matrix,
    rotation_of,
)
from extensions.carla.collision import CollisionSensor
from extensions.carla.recorder_packets import (
    LogVector,
    NOT_AN_ACTOR,
    PACKET_PLATFORM_TIME,
    PACKET_VISUAL_TIME,
    RecordedAnimBiker,
    RecordedAnimVehicle,
    RecordedAnimWalker,
    RecordedAnimWheels,
    RecordedAttribute,
    RecordedBone,
    RecordedBoundingBox,
    RecordedCollision,
    RecordedDescription,
    RecordedDoorVehicle,
    RecordedEventAdd,
    RecordedEventDel,
    RecordedEventParent,
    RecordedKinematics,
    RecordedLightScene,
    RecordedLightVehicle,
    RecordedPosition,
    RecordedTrafficLight,
    RecordedTrafficLightTime,
    RecordedWalkerBones,
    RecordedWeather,
    RecorderFrames,
    RecorderInfo,
    anim_bikers_packet,
    anim_vehicles_packet,
    anim_walkers_packet,
    anim_wheels_packet,
    bounding_boxes_packet,
    collisions_packet,
    doors_packet,
    events_add_packet,
    events_del_packet,
    events_parent_packet,
    kinematics_packet,
    light_scenes_packet,
    light_vehicles_packet,
    positions_packet,
    states_packet,
    time_packet,
    traffic_light_times_packet,
    trigger_volumes_packet,
    walker_bones_packet,
    weathers_packet,
)
from extensions.carla.recorder_physics import (
    RecordedPhysicsControl,
    physics_controls_packet,
)
from extensions.carla.recorder_query import MAGIC, recorder_file_path
from extensions.carla.sensor_data import ByteWriter
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.vehicle import VehicleDoor
from extensions.carla.weather import WeatherParameters
from extensions.carla.world import World
from std.collections import Dict
from std.ffi import external_call
from std.pathlib import Path
from std.time import perf_counter_ns
from units.si import DEGREE, METER, SECOND, METER_PER_SECOND

# The version CARLA writes in the header.
comptime RECORDER_VERSION = 1


def now_seconds() -> Int:
    """Return the time as C's `std::time(0)` does.

    Returns:
        Whole seconds since 1970-01-01 00:00:00 UTC.
    """
    return external_call["time", Int](0)


def recorder_rotation(r: CarlaRotation) -> CarlaRotation:
    """Return a rotation as CARLA stores and records it.

    CARLA keeps an actor's turn as a quaternion and records the pitch, yaw
    and roll that it gives back: the pitch from -90 to 90 degrees, the yaw
    and the roll within a half turn either way.

    Args:
        r: The rotation.

    Returns:
        Each angle wrapped into [-180, 180) degrees when the pitch is
        within a quarter turn; else the same turn read back from its
        matrix, with the pitch within a quarter turn.
    """
    var n = r.normalized()
    if n.pitch >= -90 and n.pitch <= 90:
        return n
    return rotation_of(rotation_matrix(r))


def _position(id: ActorId, t: CarlaTransform) -> RecordedPosition:
    return RecordedPosition(
        id,
        LogVector.from_meters(t.location),
        LogVector.from_rotation(recorder_rotation(t.rotation)),
    )


def weather_record(w: WeatherParameters) -> RecordedWeather:
    """Return the weather as the recorder writes it.

    Args:
        w: The weather.

    Returns:
        The fourteen numbers: the sun's angles in degrees and the fog's
        distance in meters.
    """
    return RecordedWeather(
        w.cloudiness,
        w.precipitation,
        w.precipitation_deposits,
        w.wind_intensity,
        w.sun_azimuth_angle.to(DEGREE),
        w.sun_altitude_angle.to(DEGREE),
        w.fog_density,
        w.fog_distance.to(METER),
        w.fog_falloff,
        w.wetness,
        w.scattering_intensity,
        w.mie_scattering_scale,
        w.rayleigh_scattering_scale,
        w.dust_storm,
    )


struct Recorder(Movable):
    """CARLA's recorder, `ACarlaRecorder`."""

    var enabled: Bool
    # Whether to record the velocities, bones, boxes and setups too.
    var additional_data: Bool
    # Where `stop` writes the file, or empty for memory only.
    var path: String
    var info: RecorderInfo
    var out: ByteWriter
    var frames: RecorderFrames
    var next_collision_id: Int
    var first_tick: Bool
    var start_ns: Int
    # This frame's records.
    var events_add: List[RecordedEventAdd]
    var events_del: List[RecordedEventDel]
    var events_parent: List[RecordedEventParent]
    var collisions: List[RecordedCollision]
    var positions: List[RecordedPosition]
    var states: List[RecordedTrafficLight]
    var vehicles: List[RecordedAnimVehicle]
    var wheels: List[RecordedAnimWheels]
    var walkers: List[RecordedAnimWalker]
    var bikers: List[RecordedAnimBiker]
    var light_vehicles: List[RecordedLightVehicle]
    var light_scenes: List[RecordedLightScene]
    var kinematics: List[RecordedKinematics]
    var bounding_boxes: List[RecordedBoundingBox]
    var trigger_volumes: List[RecordedBoundingBox]
    var physics_controls: List[RecordedPhysicsControl]
    var traffic_light_times: List[RecordedTrafficLightTime]
    var walker_bones: List[RecordedWalkerBones]
    var doors: List[RecordedDoorVehicle]
    var weathers: List[RecordedWeather]
    # What the world was at the last frame.
    var _alive: List[Bool]
    var _doors: Dict[Int, List[Bool]]
    var _weather: WeatherParameters
    var _sensors: Dict[Int, CollisionSensor]

    def __init__(out self):
        """Create a recorder that is not recording."""
        self.enabled = False
        self.additional_data = False
        self.path = ""
        self.info = RecorderInfo(RECORDER_VERSION, MAGIC, 0, "")
        self.out = ByteWriter()
        self.frames = RecorderFrames()
        self.next_collision_id = 0
        self.first_tick = True
        self.start_ns = 0
        self.events_add = List[RecordedEventAdd]()
        self.events_del = List[RecordedEventDel]()
        self.events_parent = List[RecordedEventParent]()
        self.collisions = List[RecordedCollision]()
        self.positions = List[RecordedPosition]()
        self.states = List[RecordedTrafficLight]()
        self.vehicles = List[RecordedAnimVehicle]()
        self.wheels = List[RecordedAnimWheels]()
        self.walkers = List[RecordedAnimWalker]()
        self.bikers = List[RecordedAnimBiker]()
        self.light_vehicles = List[RecordedLightVehicle]()
        self.light_scenes = List[RecordedLightScene]()
        self.kinematics = List[RecordedKinematics]()
        self.bounding_boxes = List[RecordedBoundingBox]()
        self.trigger_volumes = List[RecordedBoundingBox]()
        self.physics_controls = List[RecordedPhysicsControl]()
        self.traffic_light_times = List[RecordedTrafficLightTime]()
        self.walker_bones = List[RecordedWalkerBones]()
        self.doors = List[RecordedDoorVehicle]()
        self.weathers = List[RecordedWeather]()
        self._alive = List[Bool]()
        self._doors = Dict[Int, List[Bool]]()
        self._weather = WeatherParameters()
        self._sensors = Dict[Int, CollisionSensor]()

    def is_enabled(self) -> Bool:
        """Return whether a recording runs, `IsEnabled`.

        Returns:
            True between `start` and `stop`.
        """
        return self.enabled

    def bytes(self) -> List[UInt8]:
        """Return the recording so far.

        Returns:
            The file's bytes: the header and every frame written.
        """
        return self.out.bytes.copy()

    # --- start and stop -------------------------------------------------------

    def begin(
        mut self,
        name: String,
        map_name: String = "",
        additional_data: Bool = False,
        date: Int = -1,
        saved_dir: String = "",
    ) raises -> String:
        """Start an empty recording: write the header and turn on.

        `start` does this, then records the world's actors. A recording
        that runs is stopped first.

        Args:
            name: The file: a path, a name in `saved_dir`, or empty to
                record to memory only.
            map_name: The map's name for the header.
            additional_data: Whether to record the velocities, bones,
                boxes, setups and platform time too.
            date: The date for the header in seconds since 1970, or -1 for
                now.
            saved_dir: The folder of a bare name.

        Returns:
            The file's path, or empty for memory only.

        Raises:
            Error: If a running recording's file cannot be written.
        """
        self.stop()
        self.next_collision_id = 0
        self.path = ""
        if name.byte_length() > 0:
            self.path = recorder_file_path(name, saved_dir)
        self.out = ByteWriter()
        self.info = RecorderInfo(
            RECORDER_VERSION,
            MAGIC,
            date if date >= 0 else now_seconds(),
            map_name,
        )
        self.info.write(self.out)
        self.frames.reset()
        self.start_ns = perf_counter_ns()
        self.first_tick = True
        self.enabled = True
        self.additional_data = additional_data
        self._sensors = Dict[Int, CollisionSensor]()
        self._alive = List[Bool]()
        self._doors = Dict[Int, List[Bool]]()
        return self.path

    def start(
        mut self,
        world: World,
        name: String,
        map_name: String = "",
        additional_data: Bool = False,
        date: Int = -1,
        saved_dir: String = "",
    ) raises -> String:
        """Start a recording of a world, `Start`.

        A recording that runs is stopped first. The header is written, and
        every actor in the world is recorded as made in the first frame,
        at its pose in the world.

        Args:
            world: The world to record.
            name: The file: a path, a name in `saved_dir`, or empty to
                record to memory only.
            map_name: The map's name for the header.
            additional_data: Whether to record the velocities, bones,
                boxes, setups and platform time too.
            date: The date for the header in seconds since 1970, or -1 for
                now.
            saved_dir: The folder of a bare name.

        Returns:
            The file's path, or empty for memory only.

        Raises:
            Error: If a running recording's file cannot be written, or an
                actor cannot be read.
        """
        _ = self.begin(name, map_name, additional_data, date, saved_dir)
        self._weather = world.weather
        # The spectator is always in the list.
        for i in range(len(world.actors)):  # pragma: no branch
            var id = ActorId(i + 1)
            var alive = world.is_alive(id)
            self._alive.append(alive)
            if alive:
                self._add_actor(world, id, world.get_transform(id))
                self._note_doors(world, id)
        return self.path

    def stop(mut self) raises:
        """Stop the recording, `Stop`, and write the file.

        Raises:
            Error: If the file cannot be written.
        """
        if self.enabled and self.path.byte_length() > 0:
            Path(self.path).write_bytes(self.out.bytes)
        self.enabled = False
        self._clear()

    def _clear(mut self):
        """Drop this frame's records, `Clear`."""
        self.events_add = List[RecordedEventAdd]()
        self.events_del = List[RecordedEventDel]()
        self.events_parent = List[RecordedEventParent]()
        self.collisions = List[RecordedCollision]()
        self.positions = List[RecordedPosition]()
        self.states = List[RecordedTrafficLight]()
        self.vehicles = List[RecordedAnimVehicle]()
        self.wheels = List[RecordedAnimWheels]()
        self.walkers = List[RecordedAnimWalker]()
        self.bikers = List[RecordedAnimBiker]()
        self.light_vehicles = List[RecordedLightVehicle]()
        self.light_scenes = List[RecordedLightScene]()
        self.kinematics = List[RecordedKinematics]()
        self.bounding_boxes = List[RecordedBoundingBox]()
        self.trigger_volumes = List[RecordedBoundingBox]()
        self.physics_controls = List[RecordedPhysicsControl]()
        self.traffic_light_times = List[RecordedTrafficLightTime]()
        self.walker_bones = List[RecordedWalkerBones]()
        self.doors = List[RecordedDoorVehicle]()
        self.weathers = List[RecordedWeather]()

    # --- events ---------------------------------------------------------------

    def _add_actor(
        mut self, world: World, id: ActorId, transform: CarlaTransform
    ) raises:
        """`CreateRecorderEventAdd`: the actor, then what goes with it."""
        var actor = world.actor(id)
        var uid = 0
        var found = world.blueprints.find(actor.type_id)
        if Bool(found):
            uid = found.value().uid
        var attributes = List[RecordedAttribute]()
        for a in actor.attributes:
            if a.id.byte_length() > 0:
                attributes.append(RecordedAttribute(a.type, a.id, a.value))
        self.events_add.append(
            RecordedEventAdd(
                id,
                actor.kind,
                LogVector.from_meters(transform.location),
                LogVector.from_rotation(recorder_rotation(transform.rotation)),
                RecordedDescription(uid, actor.type_id, attributes^),
            )
        )
        if actor.kind == VEHICLE_ACTOR:
            self.add_physics_control(world, id)
        if actor.kind == TRAFFIC_LIGHT_ACTOR:
            self.add_traffic_light_time(world, id)
        if (
            actor.kind == TRAFFIC_LIGHT_ACTOR
            or actor.kind == TRAFFIC_SIGN_ACTOR
        ):
            self._add_trigger_volume(world, id)
        else:
            var box = actor.bounding_box
            self.bounding_boxes.append(
                RecordedBoundingBox(
                    id,
                    LogVector.from_meters(box.location),
                    LogVector.from_meters(box.extent),
                )
            )

    def _add_trigger_volume(mut self, world: World, id: ActorId) raises:
        """`AddTriggerVolume`: the last box of a sign or a light, in the
        world."""
        if not self.additional_data:
            return
        var actor = world.actor(id)
        var boxes = (
            world.traffic_lights.lights[actor.handle].boxes.copy()
        ) if actor.kind == TRAFFIC_LIGHT_ACTOR else (
            world.signs[actor.handle].effect_boxes.copy()
        )
        if len(boxes) == 0:
            return
        var top = boxes[len(boxes) - 1]
        self.trigger_volumes.append(
            RecordedBoundingBox(
                id,
                LogVector.from_meters(top.transform.location),
                LogVector.from_meters(top.extent),
            )
        )

    def add_physics_control(mut self, world: World, id: ActorId) raises:
        """Record a vehicle's physics control, `AddPhysicsControl`.

        Only a recording with additional data keeps it.

        Args:
            world: The world.
            id: The vehicle.

        Raises:
            Error: If the actor is not a vehicle.
        """
        if self.enabled and self.additional_data:
            self.physics_controls.append(
                RecordedPhysicsControl.from_control(
                    id, world.get_physics_control(id)
                )
            )

    def add_traffic_light_time(mut self, world: World, id: ActorId) raises:
        """Record a light's stage times, `AddTrafficLightTime`.

        Only a recording with additional data keeps them.

        Args:
            world: The world.
            id: The traffic light.

        Raises:
            Error: If the actor is not a traffic light.
        """
        if self.enabled and self.additional_data:
            self.traffic_light_times.append(
                RecordedTrafficLightTime(
                    id,
                    world.get_light_time(id, GREEN).to(SECOND),
                    world.get_light_time(id, YELLOW).to(SECOND),
                    world.get_light_time(id, RED).to(SECOND),
                )
            )

    def add_collision(
        mut self, world: World, actor1: ActorId, actor2: ActorId
    ) raises:
        """Record a hit between two actors, `AddCollision`.

        A pair is kept once a frame; a later hit of the same pair still
        takes a collision id.

        Args:
            world: The world.
            actor1: The first actor, or `NO_ACTOR` for something that is
                not an actor.
            actor2: The second actor, or `NO_ACTOR`.

        Raises:
            Error: If an actor is not in the world.
        """
        if not self.enabled:
            return
        var id = self.next_collision_id
        self.next_collision_id += 1
        var a = NOT_AN_ACTOR
        var b = NOT_AN_ACTOR
        var hero_a = False
        var hero_b = False
        if actor1 != NO_ACTOR:
            a = actor1
            hero_a = world.actor(actor1).role_name() == "hero"
        if actor2 != NO_ACTOR:
            b = actor2
            hero_b = world.actor(actor2).role_name() == "hero"
        for c in self.collisions:
            if c.database_id1 == a and c.database_id2 == b:
                return
        self.collisions.append(RecordedCollision(id, a, b, hero_a, hero_b))

    def add_light_scene(mut self, light: RecordedLightScene):
        """Record a scene light's change, `AddEventLightSceneChanged`.

        Args:
            light: The light's id, intensity, color, switch and group.
        """
        if self.enabled:
            self.light_scenes.append(light)

    def add_anim_biker(mut self, biker: RecordedAnimBiker):
        """Record a two-wheeler's animation, `AddAnimBiker`.

        Args:
            biker: The record.
        """
        if self.enabled:
            self.bikers.append(biker)

    def add_anim_wheels(mut self, wheels: RecordedAnimWheels):
        """Record a vehicle's wheels, `AddAnimVehicleWheels`.

        Args:
            wheels: The record.
        """
        if self.enabled:
            self.wheels.append(wheels.copy())

    def _note_doors(mut self, world: World, id: ActorId) raises:
        var actor = world.actor(id)
        if actor.kind == VEHICLE_ACTOR:
            self._doors[id.value] = world.vehicles[
                actor.handle
            ].doors_open.copy()

    def _find_events(mut self, world: World) raises:
        """Compare the world with the last frame: spawns, removals,
        parents, doors, weather and the collision sensors' hits."""
        # The spectator is always in the list.
        for i in range(len(world.actors)):  # pragma: no branch
            var id = ActorId(i + 1)
            var alive = world.is_alive(id)
            var was = i < len(self._alive) and self._alive[i]
            if alive and not was:
                var actor = world.actor(id)
                self._add_actor(world, id, actor.local_transform)
                if actor.parent != NO_ACTOR:
                    self.events_parent.append(
                        RecordedEventParent(id, actor.parent)
                    )
                self._note_doors(world, id)
            elif was and not alive:
                self.events_del.append(RecordedEventDel(id))
                if id.value in self._doors:
                    _ = self._doors.pop(id.value)
                if id.value in self._sensors:
                    _ = self._sensors.pop(id.value)
            if i < len(self._alive):
                self._alive[i] = alive
            else:
                self._alive.append(alive)
            if alive and id.value in self._doors:
                var now = world.vehicles[
                    world.actor(id).handle
                ].doors_open.copy()
                ref before = self._doors[id.value]
                for d in range(len(now)):
                    if now[d] != before[d]:
                        self.doors.append(
                            RecordedDoorVehicle(id, VehicleDoor(d), now[d])
                        )
                self._doors[id.value] = now^
        if world.weather != self._weather:
            self._weather = world.weather
            self.weathers.append(weather_record(world.weather))
        # The spectator is always in the list.
        for i in range(len(world.actors)):  # pragma: no branch
            var id = ActorId(i + 1)
            if not world.is_alive(id):
                continue
            var actor = world.actor(id)
            if actor.type_id != "sensor.other.collision":
                continue
            if actor.parent == NO_ACTOR:
                continue
            if not (id.value in self._sensors):
                self._sensors[id.value] = CollisionSensor()
            var hits = self._sensors[id.value].collect(world, actor.parent)
            for h in hits:
                self.add_collision(world, h.actor, h.other_actor)

    # --- one frame ------------------------------------------------------------

    def record(mut self, world: World) raises:
        """Record the world's state as one frame, `Ticking` and `Write`.

        Call it after each `World.tick`. It does nothing when no recording
        runs.

        Args:
            world: The world, just ticked.

        Raises:
            Error: If an actor cannot be read.
        """
        if not self.enabled:
            return
        self._find_events(world)
        # The spectator is always in the list.
        for i in range(len(world.actors)):  # pragma: no branch
            var id = ActorId(i + 1)
            if not world.is_alive(id):
                continue
            var kind = world.actor(id).kind
            if kind == OTHER_ACTOR:
                self.positions.append(_position(id, world.get_transform(id)))
            elif kind == VEHICLE_ACTOR:
                self.positions.append(_position(id, world.get_transform(id)))
                var c = world.get_control(id)
                self.vehicles.append(
                    RecordedAnimVehicle(
                        id, c.steer, c.throttle, c.brake, c.hand_brake, c.gear
                    )
                )
                self.light_vehicles.append(
                    RecordedLightVehicle(id, world.get_light_state(id))
                )
                if self.additional_data:
                    self._add_kinematics(world, id)
            elif kind == WALKER_ACTOR:
                self.positions.append(_position(id, world.get_transform(id)))
                var speed = world.get_walker_control(id).speed
                self.walkers.append(
                    RecordedAnimWalker(id, speed.to(METER_PER_SECOND) * 100)
                )
                if self.additional_data:
                    self._add_kinematics(world, id)
                    self._add_bones(world, id)
            elif kind == TRAFFIC_LIGHT_ACTOR:
                self._add_light_state(world, id)
        if self.first_tick:
            self.weathers.append(weather_record(world.weather))
            self.first_tick = False
        var elapsed = perf_counter_ns() - self.start_ns
        # CARLA counts whole microseconds.
        var platform = Float64(elapsed // 1000) / 1000000.0
        self.write_frame(world.delta_seconds, world.elapsed_seconds, platform)

    def tick(mut self, mut world: World) raises -> Int:
        """Tick the world and record the frame.

        Args:
            world: The world.

        Returns:
            The world's new frame.

        Raises:
            Error: If the world cannot tick, or an actor cannot be read.
        """
        var frame = world.tick()
        self.record(world)
        return frame

    def _add_kinematics(mut self, world: World, id: ActorId) raises:
        self.kinematics.append(
            RecordedKinematics(
                id,
                LogVector.from_vector(world.get_velocity(id)),
                LogVector.from_vector(world.get_angular_velocity(id)),
            )
        )

    def _add_bones(mut self, world: World, id: ActorId) raises:
        var out = world.get_bones_transform(id)
        var bones = List[RecordedBone]()
        for b in out.bone_transforms:
            bones.append(
                RecordedBone(
                    b.bone_name,
                    LogVector.from_meters(b.relative.location),
                    LogVector.from_rotation(
                        recorder_rotation(b.relative.rotation)
                    ),
                )
            )
        self.walker_bones.append(RecordedWalkerBones(id, bones^))

    def _add_light_state(mut self, world: World, id: ActorId) raises:
        """`AddTrafficLightState`: only a light with a controller and a
        group."""
        var h = world.actor(id).handle
        ref lights = world.traffic_lights
        var c = lights.lights[h].controller
        if c < 0 or lights.controllers[c].group < 0:
            return
        self.states.append(
            RecordedTrafficLight(
                id,
                lights.groups[lights.controllers[c].group].frozen,
                lights.controllers[c].elapsed.to(SECOND),
                lights.lights[h].state,
            )
        )

    def write_frame(
        mut self,
        delta_seconds: Float64,
        visual_time: Float64,
        platform_time: Float64,
    ) raises:
        """Write the records gathered so far as one frame, `Write`.

        `record` gathers a world's records and calls this. The packets go
        in CARLA's order, and the records are then dropped.

        Args:
            delta_seconds: The tick's duration; the first frame has none.
            visual_time: The time of the visual effects, in seconds.
            platform_time: The machine's time since the start, in seconds;
                written only with additional data.

        Raises:
            Error: If a record is refused.
        """
        self.frames.set_frame(delta_seconds)
        self.frames.write_start(self.out)
        time_packet(self.out, PACKET_VISUAL_TIME, visual_time)
        events_add_packet(self.out, self.events_add)
        events_del_packet(self.out, self.events_del)
        events_parent_packet(self.out, self.events_parent)
        collisions_packet(self.out, self.collisions)
        doors_packet(self.out, self.doors)
        positions_packet(self.out, self.positions)
        states_packet(self.out, self.states)
        anim_vehicles_packet(self.out, self.vehicles)
        anim_walkers_packet(self.out, self.walkers)
        light_vehicles_packet(self.out, self.light_vehicles)
        light_scenes_packet(self.out, self.light_scenes)
        anim_wheels_packet(self.out, self.wheels)
        anim_bikers_packet(self.out, self.bikers)
        weathers_packet(self.out, self.weathers)
        if self.additional_data:
            kinematics_packet(self.out, self.kinematics)
            bounding_boxes_packet(self.out, self.bounding_boxes)
            trigger_volumes_packet(self.out, self.trigger_volumes)
            time_packet(self.out, PACKET_PLATFORM_TIME, platform_time)
            physics_controls_packet(self.out, self.physics_controls)
            traffic_light_times_packet(self.out, self.traffic_light_times)
            walker_bones_packet(self.out, self.walker_bones)
        self.frames.write_end(self.out)
        self._clear()
