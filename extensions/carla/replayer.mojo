# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's replayer: a recording played back into a world.

`Replayer.replay_file` opens a recording, makes its actors in the world
up to the start time, and returns CARLA's text. Each `Replayer.tick`
then moves the replay on by the tick's time, times the time factor.
`Replayer.step` ticks the world first.

```mojo
var replayer = Replayer()
print(replayer.replay_file(world, "/tmp/run.log", Duration(0, SECOND)))
while replayer.is_enabled():
    _ = replayer.step(world)
```

**Time.** The replay's time starts at the start time. A negative start
time counts back from the end. The replay stops, and keeps its actors,
when its time reaches the start time plus the duration, or the end with
a duration of zero.

**Between frames.** Frame k holds the poses at its time t(k). While the
replay's time is in frame k, from t(k) to t(k) + d(k), each actor is
placed between its pose in frame k - 1 and its pose in frame k, at the
fraction (time - t(k)) / d(k). So the replay shows frame k - 1's poses at
t(k), one frame behind the recording, as CARLA's does. An actor with no
pose in frame k - 1 takes its pose in frame k. At a time factor of 2 or
more, each actor takes its pose in frame k - 1, with no interpolation.

**Ids.** A replayed actor gets a new id from the world. The replayer maps
each recorded id to the world's id, and every record goes to the mapped
actor.

**Options.** These are CARLA's:

- `follow_id` puts the spectator at `follow_offset` in the frame of that
  recorded actor after each move.
- `time_factor` plays faster or slower.
- `ignore_hero` leaves the actors whose `role_name` is `hero` to the
  world. `ignore_spectator`, on by default, leaves the spectator alone.
- `replay_sensors` makes the recorded sensors, and `replay_weather` sets
  the recorded weather.

**Differences from CARLA.**

- The replayer does not load a map: it plays into the world it is given,
  and the header's map name is not checked. There is no map override.
- The replayer reads the whole recording into memory when it starts.
- The visual time, the scene lights, the bicycles' animation and the
  wheels' animation go into the replayer's own fields, since the world
  has none. See `replayer_helper` for the rest.

The source is CARLA's simulator plugin, `Carla/Recorder/
CarlaReplayer.cpp` and `CarlaRecorder.cpp`.
"""

from extensions.carla.actor import ActorId, NO_ACTOR, no_rotation
from extensions.carla.recorder_format import c_fixed, c_general
from extensions.carla.recorder_packets import (
    LogReader,
    PACKET_ANIM_BIKER,
    PACKET_ANIM_VEHICLE,
    PACKET_ANIM_VEHICLE_WHEELS,
    PACKET_ANIM_WALKER,
    PACKET_EVENT_ADD,
    PACKET_EVENT_DEL,
    PACKET_EVENT_PARENT,
    PACKET_FRAME_END,
    PACKET_FRAME_START,
    PACKET_POSITION,
    PACKET_SCENE_LIGHT,
    PACKET_STATE,
    PACKET_VEHICLE_DOOR,
    PACKET_VEHICLE_LIGHT,
    PACKET_VISUAL_TIME,
    PACKET_WALKER_BONES,
    PACKET_WEATHER,
    RecordedAnimBiker,
    RecordedAnimVehicle,
    RecordedAnimWalker,
    RecordedAnimWheels,
    RecordedDoorVehicle,
    RecordedEventAdd,
    RecordedEventDel,
    RecordedEventParent,
    RecordedLightScene,
    RecordedLightVehicle,
    RecordedPosition,
    RecordedTrafficLight,
    RecordedWalkerBones,
    RecordedWeather,
    RecorderFrame,
    RecorderInfo,
)
from extensions.carla.recorder_query import recorder_file_path
from extensions.carla.replayer_helper import (
    CREATED,
    REUSED,
    is_hero,
    process_anim_vehicle,
    process_door_vehicle,
    process_event_add,
    process_event_del,
    process_event_parent,
    process_finish,
    process_light_vehicle,
    process_position,
    process_state_traffic_light,
    process_walker_bones,
    process_weather,
    set_camera_position,
    set_walker_speed,
)
from extensions.carla.transform import CarlaTransform
from extensions.carla.world import World
from std.collections import Dict
from std.pathlib import Path
from units.si import SECOND, Duration, Length


def _identity() -> CarlaTransform:
    return CarlaTransform(Length(0), Length(0), Length(0), no_rotation())


struct Replayer(Movable):
    """CARLA's replayer, `CarlaReplayer`."""

    var enabled: Bool
    var replay_sensors: Bool
    var replay_weather: Bool
    var reader: LogReader
    var header_id: Int
    var header_size: Int
    var info: RecorderInfo
    var frame: RecorderFrame
    # The poses of the frame before and of this frame.
    var curr_pos: List[RecordedPosition]
    var prev_pos: List[RecordedPosition]
    # Recorded id to the world's id.
    var mapped_id: Dict[Int, Int]
    # In seconds.
    var current_time: Float64
    var time_to_stop: Float64
    var total_time: Float64
    var follow_id: ActorId
    var follow_offset: CarlaTransform
    var time_factor: Float64
    var ignore_hero: Bool
    var ignore_spectator: Bool
    # By the world's id: whether the actor is a hero.
    var is_hero_map: Dict[Int, Bool]
    # What the world has no place for.
    var visual_time: Float64
    var scene_lights: Dict[Int, RecordedLightScene]
    var bikers: Dict[Int, RecordedAnimBiker]
    var wheels: Dict[Int, RecordedAnimWheels]

    def __init__(out self):
        """Create a replayer that is not replaying: time factor 1, heroes
        replayed, the spectator left alone."""
        self.enabled = False
        self.replay_sensors = False
        self.replay_weather = False
        self.reader = LogReader(List[UInt8]())
        self.header_id = 0
        self.header_size = 0
        self.info = RecorderInfo(0, "", 0, "")
        self.frame = RecorderFrame(0, 0, 0)
        self.curr_pos = List[RecordedPosition]()
        self.prev_pos = List[RecordedPosition]()
        self.mapped_id = Dict[Int, Int]()
        self.current_time = 0
        self.time_to_stop = 0
        self.total_time = 0
        self.follow_id = NO_ACTOR
        self.follow_offset = _identity()
        self.time_factor = 1
        self.ignore_hero = False
        self.ignore_spectator = True
        self.is_hero_map = Dict[Int, Bool]()
        self.visual_time = 0
        self.scene_lights = Dict[Int, RecordedLightScene]()
        self.bikers = Dict[Int, RecordedAnimBiker]()
        self.wheels = Dict[Int, RecordedAnimWheels]()

    def is_enabled(self) -> Bool:
        """Return whether a replay runs, `IsEnabled`.

        Returns:
            True from the start until the replay stops.
        """
        return self.enabled

    def set_time_factor(mut self, factor: Float64):
        """Set the replay's speed, `SetTimeFactor`.

        Args:
            factor: The recording's seconds for each second of the world.
        """
        self.time_factor = factor

    def set_ignore_hero(mut self, ignore: Bool):
        """Leave heroes to the world, `SetIgnoreHero`.

        Args:
            ignore: Whether to leave them.
        """
        self.ignore_hero = ignore

    def set_ignore_spectator(mut self, ignore: Bool):
        """Leave the spectator alone, `SetIgnoreSpectator`.

        Args:
            ignore: Whether to leave it.
        """
        self.ignore_spectator = ignore

    def mapped(self, recorded: ActorId) -> ActorId:
        """Return the world's id of a recorded actor.

        Args:
            recorded: The id in the recording.

        Returns:
            The world's id, or `NO_ACTOR` for an actor not replayed.
        """
        return ActorId(self.mapped_id.get(recorded.value, 0))

    # --- the file -------------------------------------------------------------

    def _read_header(mut self):
        """`ReadHeader`: keep the last id and size when the read fails."""
        var id = self.reader.u8()
        if not self.reader.failed:
            self.header_id = id
        var size = self.reader.u32()
        if not self.reader.failed:
            self.header_size = size

    def _rewind(mut self):
        """`Rewind`: back to the start, with no frame and no ids."""
        self.current_time = 0
        self.total_time = 0
        self.time_to_stop = 0
        self.reader.seek(0)
        self.frame.elapsed = -1
        self.frame.duration_this = 0
        self.mapped_id = Dict[Int, Int]()
        self.is_hero_map = Dict[Int, Bool]()
        self.info = RecorderInfo.read(self.reader)

    def _get_total_time(mut self) -> Float64:
        """`GetTotalTime`: the last frame's time; the place is kept."""
        var at = self.reader.pos
        while True:
            self._read_header()
            if self.reader.failed:
                break
            if self.header_id == PACKET_FRAME_START.value:
                self.frame = RecorderFrame.read(self.reader)
            else:
                self.reader.skip(self.header_size)
        self.reader.seek(at)
        return self.frame.elapsed

    def replay_file(
        mut self,
        mut world: World,
        name: String,
        time_start: Duration = Duration(0, SECOND),
        duration: Duration = Duration(0, SECOND),
        follow_id: ActorId = NO_ACTOR,
        follow_offset: CarlaTransform = _identity(),
        replay_sensors: Bool = False,
        replay_weather: Bool = False,
        saved_dir: String = "",
    ) raises -> String:
        """Start replaying a file, `ReplayFile`.

        Args:
            world: The world to replay into.
            name: The file: a path, or a name in `saved_dir`.
            time_start: Where to start; below zero, back from the end.
            duration: How long to play, or zero to the end.
            follow_id: The recorded actor the spectator follows, or
                `NO_ACTOR`.
            follow_offset: The spectator's pose in that actor's frame.
            replay_sensors: Whether to make the recorded sensors.
            replay_weather: Whether to set the recorded weather.
            saved_dir: The folder of a bare name.

        Returns:
            CARLA's text: the file, the total time, the times played and
            the time factor, and what is ignored.

        Raises:
            Error: If the file cannot be read, or the world refuses a
                record.
        """
        var path = recorder_file_path(name, saved_dir)
        if not Path(path).exists():
            if self.enabled:
                self.stop(world)
            return (
                "Replaying File: "
                + path
                + "\nFile "
                + path
                + " not found on server\n"
            )
        return self.replay_bytes(
            world,
            Path(path).read_bytes(),
            path,
            time_start,
            duration,
            follow_id,
            follow_offset,
            replay_sensors,
            replay_weather,
        )

    def replay_bytes(
        mut self,
        mut world: World,
        var bytes: List[UInt8],
        name: String,
        time_start: Duration = Duration(0, SECOND),
        duration: Duration = Duration(0, SECOND),
        follow_id: ActorId = NO_ACTOR,
        follow_offset: CarlaTransform = _identity(),
        replay_sensors: Bool = False,
        replay_weather: Bool = False,
    ) raises -> String:
        """Start replaying a recording held in memory.

        Args:
            world: The world to replay into.
            bytes: The recording.
            name: The name to print as the file's.
            time_start: Where to start; below zero, back from the end.
            duration: How long to play, or zero to the end.
            follow_id: The recorded actor the spectator follows, or
                `NO_ACTOR`.
            follow_offset: The spectator's pose in that actor's frame.
            replay_sensors: Whether to make the recorded sensors.
            replay_weather: Whether to set the recorded weather.

        Returns:
            CARLA's text, as `replay_file` returns it.

        Raises:
            Error: If the world refuses a record.
        """
        if self.enabled:
            self.stop(world)
        var out = "Replaying File: " + name + "\n"
        self.reader = LogReader(bytes^)
        self._rewind()
        self.total_time = self._get_total_time()
        out += "Total time recorded: " + c_general(self.total_time) + "\n"
        var start = Float64(time_start.to(SECOND))
        if start < 0:
            start = max(self.total_time + start, 0.0)
        var length = Float64(duration.to(SECOND))
        if length > 0:
            self.time_to_stop = start + length
        else:
            self.time_to_stop = self.total_time
        out += (
            "Replaying from "
            + c_general(start)
            + " s - "
            + c_general(self.time_to_stop)
            + " s ("
            + c_general(self.total_time)
            + " s) at "
            + c_fixed(self.time_factor, 1)
            + "x\n"
        )
        if self.ignore_hero:
            out += "Ignoring Hero vehicle\n"
        if self.ignore_spectator:
            out += "Ignoring Spectator camera\n"
        self.follow_id = follow_id
        self.follow_offset = follow_offset
        self.replay_sensors = replay_sensors
        self.replay_weather = replay_weather
        self._process_to_time(world, start, True)
        self.enabled = True
        return out

    def stop(mut self, mut world: World, keep_actors: Bool = False) raises:
        """Stop the replay, `Stop`.

        Without `keep_actors`, the rest of the recording's events run
        first, so the actors it removes go. The world then gets its
        actors back: see `process_finish`.

        Args:
            world: The world.
            keep_actors: Whether to keep the actors the rest of the
                recording removes.

        Raises:
            Error: If the world refuses a record.
        """
        if not self.enabled:
            return
        self.enabled = False
        if not keep_actors:
            self._process_to_time(world, self.total_time, False)
        var heroes = List[ActorId]()
        for entry in self.is_hero_map.items():
            if entry.value:
                heroes.append(ActorId(entry.key))
        process_finish(world, self.ignore_hero, heroes)

    def tick(mut self, mut world: World, delta: Duration) raises:
        """Move the replay on, `Tick`.

        Args:
            world: The world.
            delta: The world's tick, scaled by the time factor.

        Raises:
            Error: If the world refuses a record.
        """
        if self.enabled:
            self._process_to_time(
                world, Float64(delta.to(SECOND)) * self.time_factor, False
            )

    def step(mut self, mut world: World) raises -> Int:
        """Tick the world, then move the replay on by the tick.

        The recorded poses are set after the world's physics, so they are
        the poses the world ends the tick with.

        Args:
            world: The world.

        Returns:
            The world's new frame.

        Raises:
            Error: If the world cannot tick, or refuses a record.
        """
        var frame = world.tick()
        if self.enabled:
            self._process_to_time(
                world, world.delta_seconds * self.time_factor, False
            )
        return frame

    # --- the frames -----------------------------------------------------------

    def _process_to_time(
        mut self, mut world: World, time: Float64, first_time: Bool
    ) raises:
        """`ProcessToTime`: read up to the frame that holds the new time."""
        var per = 0.0
        var new_time = self.current_time + time
        var found = False
        var exit_loop = False
        if (
            new_time >= self.frame.elapsed
            and new_time < self.frame.elapsed + self.frame.duration_this
        ):
            per = (new_time - self.frame.elapsed) / self.frame.duration_this
            found = True
            exit_loop = True
        while not self.reader.failed and not exit_loop:
            self._read_header()
            var id = self.header_id
            if self.reader.failed and id != PACKET_FRAME_END.value:
                break
            if id == PACKET_FRAME_START.value:
                self.frame = RecorderFrame.read(self.reader)
                if new_time < self.frame.elapsed + self.frame.duration_this:
                    per = (
                        new_time - self.frame.elapsed
                    ) / self.frame.duration_this
                    found = True
            elif id == PACKET_VISUAL_TIME.value:
                self.visual_time = self.reader.f64()
            elif id == PACKET_EVENT_ADD.value:
                self._events_add(world)
            elif id == PACKET_EVENT_DEL.value:
                self._events_del(world)
            elif id == PACKET_EVENT_PARENT.value:
                self._events_parent(world)
            elif id == PACKET_WEATHER.value:
                self._weather(world)
            elif id == PACKET_FRAME_END.value:
                if found:
                    exit_loop = True
            elif found and self._frame_packet(world, id, first_time):
                pass
            else:
                self.reader.skip(self.header_size)
        if self.enabled and found:
            self._update_positions(world, per)
        self.current_time = new_time
        if self.current_time >= self.time_to_stop:
            self.stop(world, True)

    def _frame_packet(
        mut self, mut world: World, id: Int, first_time: Bool
    ) raises -> Bool:
        """The packets read only in the frame that holds the time."""
        var total: Int
        if id == PACKET_POSITION.value:
            self._positions(first_time)
        elif id == PACKET_STATE.value:
            total = self.reader.u16()
            for _ in range(total):
                var s = RecordedTrafficLight.read(self.reader)
                s.database_id = self.mapped(s.database_id)
                _ = process_state_traffic_light(world, s)
        elif id == PACKET_ANIM_VEHICLE.value:
            total = self.reader.u16()
            for _ in range(total):
                var v = RecordedAnimVehicle.read(self.reader)
                v.database_id = self.mapped(v.database_id)
                if not self._skip_hero(v.database_id):
                    process_anim_vehicle(world, v)
        elif id == PACKET_ANIM_VEHICLE_WHEELS.value:
            total = self.reader.u16()
            for _ in range(total):
                var v = RecordedAnimWheels.read(self.reader)
                v.database_id = self.mapped(v.database_id)
                if not self._skip_hero(v.database_id):
                    self.wheels[v.database_id.value] = v^
        elif id == PACKET_ANIM_WALKER.value:
            total = self.reader.u16()
            for _ in range(total):
                var w = RecordedAnimWalker.read(self.reader)
                w.database_id = self.mapped(w.database_id)
                if not self._skip_hero(w.database_id):
                    set_walker_speed(world, w.database_id, w.speed)
        elif id == PACKET_ANIM_BIKER.value:
            total = self.reader.u16()
            for _ in range(total):
                var b = RecordedAnimBiker.read(self.reader)
                b.database_id = self.mapped(b.database_id)
                if not self._skip_hero(b.database_id):
                    self.bikers[b.database_id.value] = b
        elif id == PACKET_VEHICLE_LIGHT.value:
            total = self.reader.u16()
            for _ in range(total):
                var l = RecordedLightVehicle.read(self.reader)
                l.database_id = self.mapped(l.database_id)
                if not self._skip_hero(l.database_id):
                    process_light_vehicle(world, l)
        elif id == PACKET_VEHICLE_DOOR.value:
            total = self.reader.u16()
            for _ in range(total):
                var d = RecordedDoorVehicle.read(self.reader)
                d.database_id = self.mapped(d.database_id)
                if not self._skip_hero(d.database_id):
                    process_door_vehicle(world, d)
        elif id == PACKET_SCENE_LIGHT.value:
            total = self.reader.u16()
            for _ in range(total):
                var s = RecordedLightScene.read(self.reader)
                self.scene_lights[s.light_id.value] = s
        elif id == PACKET_WALKER_BONES.value:
            total = self.reader.u16()
            for _ in range(total):
                var w = RecordedWalkerBones.read(self.reader)
                w.database_id = self.mapped(w.database_id)
                if not self._skip_hero(w.database_id):
                    process_walker_bones(world, w)
        else:
            return False
        return True

    def _skip_hero(self, id: ActorId) -> Bool:
        return self.ignore_hero and self.is_hero_map.get(id.value, False)

    def _events_add(mut self, mut world: World) raises:
        """`ProcessEventsAdd`: make each actor and map its id."""
        var total = self.reader.u16()
        for _ in range(total):
            var e = RecordedEventAdd.read(self.reader)
            var result = process_event_add(
                world,
                e.location,
                e.rotation,
                e.description,
                self.ignore_hero,
                self.ignore_spectator,
                self.replay_sensors,
            )
            if result[0] == CREATED or result[0] == REUSED:
                self.mapped_id[e.database_id.value] = result[1].value
                self.is_hero_map[result[1].value] = is_hero(e.description)

    def _events_del(mut self, mut world: World) raises:
        """`ProcessEventsDel`: remove each actor and forget its id."""
        var total = self.reader.u16()
        for _ in range(total):
            var e = RecordedEventDel.read(self.reader)
            _ = process_event_del(world, self.mapped(e.database_id))
            if e.database_id.value in self.mapped_id:
                _ = self.mapped_id.pop(e.database_id.value)

    def _events_parent(mut self, mut world: World) raises:
        """`ProcessEventsParent`: attach each child."""
        var total = self.reader.u16()
        for _ in range(total):
            var e = RecordedEventParent.read(self.reader)
            _ = process_event_parent(
                world,
                self.mapped(e.database_id),
                self.mapped(e.database_id_parent),
            )

    def _weather(mut self, mut world: World):
        """`ProcessWeather`: read each weather; set it when asked."""
        var total = self.reader.u16()
        for _ in range(total):
            var w = RecordedWeather.read(self.reader)
            if self.replay_weather:
                process_weather(world, w)

    def _positions(mut self, first_time: Bool):
        """`ProcessPositions`: this frame's poses become the last."""
        self.prev_pos = self.curr_pos^
        self.curr_pos = List[RecordedPosition]()
        var total = self.reader.u16()
        for _ in range(total):
            var p = RecordedPosition.read(self.reader)
            var found = self.mapped_id.get(p.database_id.value)
            if Bool(found):
                p.database_id = ActorId(found.value())
            self.curr_pos.append(p)
        if first_time:
            self.prev_pos = List[RecordedPosition]()

    def _update_positions(mut self, mut world: World, per: Float64) raises:
        """`UpdatePositions`: place each actor between its two poses."""
        var follow = NO_ACTOR
        if self.follow_id != NO_ACTOR:
            follow = self.mapped(self.follow_id)
        for pos in self.curr_pos:
            if self._skip_hero(pos.database_id):
                continue
            if self.ignore_spectator and pos.database_id.value == 1:
                continue
            var before = -1
            for i in range(len(self.prev_pos)):
                if self.prev_pos[i].database_id == pos.database_id:
                    before = i
            if before >= 0:
                var fraction = 0.0 if self.time_factor >= 2.0 else per
                _ = process_position(
                    world, self.prev_pos[before], pos, fraction
                )
            else:
                _ = process_position(world, pos, pos, 0.0)
        if follow != NO_ACTOR:
            _ = set_camera_position(world, follow, self.follow_offset)
