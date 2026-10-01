# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's three recorder queries, with CARLA's text.

- `show_recorder_file_info` lists the recording frame by frame: the
  actors made and removed, the parents, the collisions and the weather.
  With `show_all` it lists every packet it knows, and every frame.
- `show_recorder_collisions` lists each collision between two kinds of
  actor, once when it starts.
- `show_recorder_actors_blocked` lists each actor that moved less than a
  distance for at least a time, the longest first.

Each query reads a recording as bytes or from a file, and returns the
text that CARLA's server returns, byte for byte. The numbers are written
as a C++ stream writes them; see `recorder_format`.

CARLA's queries keep some behavior that looks like a slip. This port
keeps it too, so the text is the same:

- The last `FrameEnd` is read twice. A stream reads its end only when a
  read fails, so the loop runs once more with the last packet's header.
  The file-info query therefore ends its last frame with two newlines.
- A removed actor is not the one the collision and blocked queries
  forget. They forget the actor of the last `EventAdd` record read.
- A frame's duration is -1 in the last frame. The blocked query adds it
  to the time of each actor that did not move in that frame.
- After the collision query prints a collision, its stream keeps
  `std::fixed` with no digits. So its last line then writes the duration
  with no fraction.

**Differences from CARLA.**

- CARLA's queries keep their last frame between calls. Each query here
  starts from frame zero.
- The blocked query lists the actors that are still stopped at the end
  in the order they first appeared. CARLA lists those with equal times in
  the order of its hash map, which C++ does not define.
- A file that does not end with a frame's end prints only what it holds;
  CARLA prints the last record again.

The categories of the collision query are CARLA's: `o` other, `v`
vehicle, `w` walker, `t` traffic light, `h` hero and `a` any. CARLA
picks an actor's category by its kind as an index into that list, so a
traffic sign is `h` and a sensor is `a`, as in CARLA.

The source is CARLA's simulator plugin, `Carla/Recorder/
CarlaRecorderQuery.cpp` and `CarlaRecorderHelpers.cpp`.
"""

from extensions.carla.actor import ActorId
from extensions.carla.recorder_format import (
    c_date,
    c_fixed,
    c_general,
    pad_left,
    pad_right,
)
from extensions.carla.recorder_packets import (
    LogReader,
    LogVector,
    NOT_AN_ACTOR,
    PACKET_ANIM_VEHICLE,
    PACKET_ANIM_WALKER,
    PACKET_BOUNDING_BOX,
    PACKET_COLLISION,
    PACKET_EVENT_ADD,
    PACKET_EVENT_DEL,
    PACKET_EVENT_PARENT,
    PACKET_FRAME_END,
    PACKET_FRAME_START,
    PACKET_KINEMATICS,
    PACKET_PHYSICS_CONTROL,
    PACKET_PLATFORM_TIME,
    PACKET_POSITION,
    PACKET_SCENE_LIGHT,
    PACKET_STATE,
    PACKET_TRAFFIC_LIGHT_TIME,
    PACKET_TRIGGER_VOLUME,
    PACKET_VEHICLE_DOOR,
    PACKET_VEHICLE_LIGHT,
    PACKET_WALKER_BONES,
    PACKET_WEATHER,
    RecordedAnimVehicle,
    RecordedAnimWalker,
    RecordedBoundingBox,
    RecordedCollision,
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
    RecorderFrame,
    RecorderInfo,
)
from extensions.carla.recorder_physics import (
    RecordedPhysicsControl,
    physics_control_text,
)
from extensions.carla.vehicle import (
    DOOR_ALL,
    DOOR_FRONT_LEFT,
    DOOR_FRONT_RIGHT,
    DOOR_HOOD,
    DOOR_REAR_LEFT,
    DOOR_REAR_RIGHT,
    DOOR_TRUNK,
    LIGHT_BRAKE,
    LIGHT_FOG,
    LIGHT_HIGH_BEAM,
    LIGHT_INTERIOR,
    LIGHT_LEFT_BLINKER,
    LIGHT_LOW_BEAM,
    LIGHT_POSITION,
    LIGHT_REVERSE,
    LIGHT_RIGHT_BLINKER,
    LIGHT_SPECIAL1,
    LIGHT_SPECIAL2,
    VehicleLightState,
)
from std.collections import Dict
from std.pathlib import Path
from units.si import CENTIMETER, SECOND, Duration, Length

comptime MAGIC = "CARLA_RECORDER"


@fieldwise_init
struct CollisionCategory(Equatable, ImplicitlyCopyable, Writable):
    """A kind of actor the collision query keeps: the character code of
    `o`, `v`, `w`, `t`, `h` or `a`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of CARLA's six categories.

        Returns:
            Whether the value is the code of `o`, `v`, `w`, `t`, `h` or
            `a`.
        """
        return (
            self.value == 111
            or self.value == 118
            or self.value == 119
            or self.value == 116
            or self.value == 104
            or self.value == 97
        )


comptime CATEGORY_OTHER = CollisionCategory(111)
comptime CATEGORY_VEHICLE = CollisionCategory(118)
comptime CATEGORY_WALKER = CollisionCategory(119)
comptime CATEGORY_TRAFFIC_LIGHT = CollisionCategory(116)
comptime CATEGORY_HERO = CollisionCategory(104)
comptime CATEGORY_ANY = CollisionCategory(97)


def recorder_file_path(name: String, saved_dir: String) -> String:
    """Return where a recording is, `GetRecorderFilename`.

    Args:
        name: The name given. With a `/`, a `\\` or a `:` it is a path, as
            it is.
        saved_dir: The folder of a bare name, with its separator at the
            end. CARLA uses its project's saved folder.

    Returns:
        The path.
    """
    if "\\" in name or "/" in name or ":" in name:
        return name
    return saved_dir + name


# --- shared pieces ---------------------------------------------------------------


struct _Header(ImplicitlyCopyable):
    """The last packet header, kept when a read of the next one fails."""

    var id: Int
    var size: Int

    def __init__(out self):
        self.id = 0
        self.size = 0

    def read(mut self, mut r: LogReader):
        """`ReadHeader`: read the id and the size into the fields that the
        file still holds."""
        var id = r.u8()
        if not r.failed:
            self.id = id
        var size = r.u32()
        if not r.failed:
            self.size = size


def _head(mut r: LogReader, mut out: String) -> Bool:
    """`CheckFileInfo`: read the header, print it, and check the magic."""
    var info = RecorderInfo.read(r)
    if info.magic != MAGIC:
        out += "File is not a CARLA recorder\n"
        return False
    out += "Version: " + String(info.version) + "\n"
    out += "Map: " + info.map_file + "\n"
    out += "Date: " + c_date(info.date) + "\n\n"
    return True


def _v(v: LogVector) -> String:
    return c_general(v.x) + ", " + c_general(v.y) + ", " + c_general(v.z)


def _g(value: Float32) -> String:
    return c_general(Float64(value))


def _bool(value: Bool) -> String:
    return "1" if value else "0"


def _frame_line(frame: RecorderFrame) -> String:
    return (
        "Frame "
        + String(frame.id)
        + " at "
        + c_general(frame.elapsed)
        + " seconds\n"
    )


def _tail(frame: RecorderFrame, duration: String) -> String:
    return (
        "\nFrames: "
        + String(frame.id)
        + "\nDuration: "
        + duration
        + " seconds\n"
    )


def light_names(state: VehicleLightState) -> String:
    """Name the lights that are on, as the file-info query does.

    Args:
        state: The lights.

    Returns:
        The names in CARLA's order, with a space between them, or `None`.
        The interior light comes before the fog lights.
    """
    var names = List[String]()
    var lights: List[VehicleLightState] = [
        LIGHT_POSITION,
        LIGHT_LOW_BEAM,
        LIGHT_HIGH_BEAM,
        LIGHT_BRAKE,
        LIGHT_RIGHT_BLINKER,
        LIGHT_LEFT_BLINKER,
        LIGHT_REVERSE,
        LIGHT_INTERIOR,
        LIGHT_FOG,
        LIGHT_SPECIAL1,
        LIGHT_SPECIAL2,
    ]
    var labels: List[String] = [
        "Position",
        "LowBeam",
        "HighBeam",
        "Brake",
        "RightBlinker",
        "LeftBlinker",
        "Reverse",
        "Interior",
        "Fog",
        "Special1",
        "Special2",
    ]
    for i in range(len(lights)):  # pragma: no branch
        if state.has(lights[i]):
            names.append(labels[i])
    if len(names) == 0:
        return "None"
    return " ".join(names)


def _door_name(door: Int) -> String:
    """The line of an opened door, or nothing for a door CARLA has no
    name for."""
    if door == DOOR_FRONT_LEFT.value:
        return " Front Left \n"
    if door == DOOR_FRONT_RIGHT.value:
        return " Front Right \n"
    if door == DOOR_REAR_LEFT.value:
        return " Rear Left \n"
    if door == DOOR_REAR_RIGHT.value:
        return " Rear Right \n"
    if door == DOOR_HOOD.value:
        return " Hood \n"
    if door == DOOR_TRUNK.value:
        return " Trunk \n"
    if door == DOOR_ALL.value:
        return " All \n"
    return ""


def _box_line(b: RecordedBoundingBox) -> String:
    return (
        "  Id: "
        + String(b.database_id.value)
        + " origin: ("
        + _v(b.origin)
        + ") extension: ("
        + _v(b.extension)
        + ")\n"
    )


def _weather_line(w: RecordedWeather) -> String:
    var names: List[String] = [
        "Cloudiness",
        "Precipitation",
        "PrecipitationDeposits",
        "WindIntensity",
        "SunAzimuthAngle",
        "SunAltitudeAngle",
        "FogDensity",
        "FogDistance",
        "FogFalloff",
        "Wetness",
        "ScatteringIntensity",
        "MieScatteringScale",
        "RayleighScatteringScale",
        "DustStorm",
    ]
    var values = w.fields()
    var out = String(" ")
    for i in range(len(names)):  # pragma: no branch
        out += " " + names[i] + ": " + _g(values[i])
    return out + "\n"


# --- file info -------------------------------------------------------------------


struct _InfoPrinter:
    """The frame line is printed once, before a frame's first record."""

    var frame: RecorderFrame
    var printed: Bool

    def __init__(out self):
        self.frame = RecorderFrame(0, 0, 0)
        self.printed = False

    def count(mut self, mut r: LogReader, mut out: String) -> Int:
        """Read a packet's count; print the frame line before a record."""
        var total = r.u16()
        if total > 0 and not self.printed:
            out += _frame_line(self.frame)
            self.printed = True
        return total


def query_info(var bytes: List[UInt8], show_all: Bool = False) raises -> String:
    """List a recording, `CarlaRecorderQuery::QueryInfo`.

    Args:
        bytes: The recording.
        show_all: Whether to list every frame and every packet this query
            knows, not only the events, collisions and weather.

    Returns:
        CARLA's text: the header, then each frame with something to show,
        then the number of frames and the recording's duration.

    Raises:
        Error: If a record holds a kind that is not valid.
    """
    var r = LogReader(bytes^)
    var out = String()
    if not _head(r, out):
        return out
    var header = _Header()
    var p = _InfoPrinter()
    while not r.failed:
        header.read(r)
        var id = header.id
        if r.failed and id != PACKET_FRAME_END.value:
            break
        if id == PACKET_FRAME_START.value:
            p.frame = RecorderFrame.read(r)
            p.printed = False
            if show_all:
                out += _frame_line(p.frame)
                p.printed = True
        elif id == PACKET_EVENT_ADD.value:
            var total = p.count(r, out)
            for _ in range(total):
                var e = RecordedEventAdd.read(r)
                out += (
                    " Create "
                    + String(e.database_id.value)
                    + ": "
                    + e.description.id
                    + " ("
                    + String(e.type.value)
                    + ") at ("
                    + _v(e.location)
                    + ")\n"
                )
                for a in e.description.attributes:
                    out += "  " + a.id + " = " + a.value + "\n"
        elif id == PACKET_WEATHER.value:
            var total = p.count(r, out)
            out += " Weathers: " + String(total) + "\n"
            for _ in range(total):
                out += _weather_line(RecordedWeather.read(r))
        elif id == PACKET_EVENT_DEL.value:
            var total = p.count(r, out)
            for _ in range(total):
                var e = RecordedEventDel.read(r)
                out += " Destroy " + String(e.database_id.value) + "\n"
        elif id == PACKET_EVENT_PARENT.value:
            var total = p.count(r, out)
            for _ in range(total):
                var e = RecordedEventParent.read(r)
                out += (
                    " Parenting "
                    + String(e.database_id.value)
                    + " with "
                    + String(e.database_id_parent.value)
                    + " (parent)\n"
                )
        elif id == PACKET_COLLISION.value:
            var total = p.count(r, out)
            for _ in range(total):
                var c = RecordedCollision.read(r)
                out += (
                    " Collision id "
                    + String(c.id)
                    + " between "
                    + String(c.database_id1.value)
                )
                if c.is_actor1_hero:
                    out += " (hero) "
                out += " with " + String(c.database_id2.value)
                if c.is_actor2_hero:
                    out += " (hero) "
                out += "\n"
        elif id == PACKET_FRAME_END.value:
            out += "\n"
        elif show_all:
            _info_all(id, header.size, r, p, out)
        else:
            r.skip(header.size)
    return out + _tail(p.frame, c_general(p.frame.elapsed))


def _info_all(
    id: Int, size: Int, mut r: LogReader, mut p: _InfoPrinter, mut out: String
) raises:
    """The packets that only `show_all` lists."""
    if id == PACKET_POSITION.value:
        var total = p.count(r, out)
        out += " Positions: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedPosition.read(r)
            out += (
                "  Id: "
                + String(e.database_id.value)
                + " Location: ("
                + _v(e.location)
                + ") Rotation: ("
                + _v(e.rotation)
                + ")\n"
            )
    elif id == PACKET_STATE.value:
        var total = p.count(r, out)
        out += " State traffic lights: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedTrafficLight.read(r)
            out += (
                "  Id: "
                + String(e.database_id.value)
                + " state: "
                + chr(0x30 + e.state.value)
                + " frozen: "
                + _bool(e.is_frozen)
                + " elapsedTime: "
                + _g(e.elapsed_time)
                + "\n"
            )
    elif id == PACKET_ANIM_VEHICLE.value:
        var total = p.count(r, out)
        out += " Vehicle animations: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedAnimVehicle.read(r)
            out += (
                "  Id: "
                + String(e.database_id.value)
                + " Steering: "
                + _g(e.steering)
                + " Throttle: "
                + _g(e.throttle)
                + " Brake: "
                + _g(e.brake)
                + " Handbrake: "
                + _bool(e.handbrake)
                + " Gear: "
                + String(e.gear.value)
                + "\n"
            )
    elif id == PACKET_ANIM_WALKER.value:
        var total = p.count(r, out)
        out += " Walker animations: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedAnimWalker.read(r)
            out += (
                "  Id: "
                + String(e.database_id.value)
                + " speed: "
                + _g(e.speed)
                + "\n"
            )
    elif id == PACKET_VEHICLE_DOOR.value:
        var total = p.count(r, out)
        out += " Vehicle door animations: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedDoorVehicle.read(r)
            out += "  Id: " + String(e.database_id.value) + "\n"
            out += "  Doors opened: " + _door_name(e.doors.value)
    elif id == PACKET_VEHICLE_LIGHT.value:
        var total = p.count(r, out)
        out += " Vehicle light animations: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedLightVehicle.read(r)
            out += (
                "  Id: "
                + String(e.database_id.value)
                + " "
                + light_names(e.state)
                + "\n"
            )
    elif id == PACKET_SCENE_LIGHT.value:
        var total = p.count(r, out)
        out += " Scene light changes: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedLightScene.read(r)
            out += (
                "  Id: "
                + String(e.light_id.value)
                + " enabled: "
                + ("True" if e.on else "False")
                + " intensity: "
                + _g(e.intensity)
                + " RGB_color: ("
                + _g(e.color.x)
                + ", "
                + _g(e.color.y)
                + ", "
                + _g(e.color.z)
                + ")\n"
            )
    elif id == PACKET_KINEMATICS.value:
        var total = p.count(r, out)
        out += " Dynamic actors: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedKinematics.read(r)
            out += (
                "  Id: "
                + String(e.database_id.value)
                + " linear_velocity: ("
                + _v(e.linear_velocity)
                + ") angular_velocity: ("
                + _v(e.angular_velocity)
                + ")\n"
            )
    elif id == PACKET_BOUNDING_BOX.value:
        var total = p.count(r, out)
        out += " Actor bounding boxes: " + String(total) + "\n"
        for _ in range(total):
            out += _box_line(RecordedBoundingBox.read(r))
    elif id == PACKET_TRIGGER_VOLUME.value:
        var total = p.count(r, out)
        out += " Actor trigger volumes: " + String(total) + "\n"
        for _ in range(total):
            out += _box_line(RecordedBoundingBox.read(r))
    elif id == PACKET_PLATFORM_TIME.value:
        # With `show_all` the frame's line is already out.
        out += " Current platform time: " + c_general(r.f64()) + "\n"
    elif id == PACKET_PHYSICS_CONTROL.value:
        var total = p.count(r, out)
        out += " Physics Control events: " + String(total) + "\n"
        for _ in range(total):
            out += physics_control_text(RecordedPhysicsControl.read(r))
    elif id == PACKET_TRAFFIC_LIGHT_TIME.value:
        var total = p.count(r, out)
        out += " Traffic Light time events: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedTrafficLightTime.read(r)
            out += (
                "  Id: "
                + String(e.database_id.value)
                + " green_time: "
                + _g(e.green_time)
                + " yellow_time: "
                + _g(e.yellow_time)
                + " red_time: "
                + _g(e.red_time)
                + "\n"
            )
    elif id == PACKET_WALKER_BONES.value:
        var total = p.count(r, out)
        out += " Walkers Bones: " + String(total) + "\n"
        for _ in range(total):
            var e = RecordedWalkerBones.read(r)
            out += "  Id: " + String(e.database_id.value) + "\n"
            for b in e.bones:
                out += (
                    '     Bone: "'
                    + b.name
                    + '" relative: Loc('
                    + _v(b.location)
                    + ") Rot("
                    + _v(b.rotation)
                    + ")\n"
                )
    else:
        r.skip(size)


# --- collisions ------------------------------------------------------------------


@fieldwise_init
struct _Seen(Copyable, Movable):
    var type: Int
    var name: String


def _category(actors: Dict[Int, _Seen], id: ActorId) -> Int:
    """An actor's category code: its kind as an index into `ovwtha`."""
    if id == NOT_AN_ACTOR:
        return 111
    var codes: List[Int] = [111, 118, 119, 116, 104, 97]
    var found = actors.get(id.value)
    if Bool(found):
        return codes[found.value().type]
    return 111


def _name(actors: Dict[Int, _Seen], id: ActorId) -> String:
    var found = actors.get(id.value)
    if Bool(found):
        return found.value().name
    return ""


def _keeps(category: CollisionCategory, code: Int, hero: Bool) -> Bool:
    return (
        category == CATEGORY_ANY
        or category.value == code
        or (category == CATEGORY_HERO and hero)
    )


def query_collisions(
    var bytes: List[UInt8],
    category1: CollisionCategory = CATEGORY_ANY,
    category2: CollisionCategory = CATEGORY_ANY,
) raises -> String:
    """List the collisions, `CarlaRecorderQuery::QueryCollisions`.

    A collision shows when the first actor is in the first category and
    the second in the second. It shows once, in the frame it starts: a
    pair that collided in the frame before does not show again.

    Args:
        bytes: The recording.
        category1: The first actor's category.
        category2: The second actor's category.

    Returns:
        CARLA's text: the header, a table of time, categories, ids and
        blueprint ids, then the number of frames and the duration.

    Raises:
        Error: If a category is not valid, or a record holds a kind that
            is not valid.
    """
    if not (category1.is_valid() and category2.is_valid()):
        raise Error("Recorder: a collision category is not valid")
    var r = LogReader(bytes^)
    var out = String()
    if not _head(r, out):
        return out
    out += pad_right("Time", 8) + " " + pad_right("Types", 6)
    out += " " + pad_right("Id", 6) + " " + pad_left("Actor 1", 35)
    out += " " + pad_right("Id", 6) + " " + pad_left("Actor 2", 35) + "\n"
    var actors = Dict[Int, _Seen]()
    var old = List[Int]()
    var new = List[Int]()
    var frame = RecorderFrame(0, 0, 0)
    var last_added = 0
    var fixed = False
    var header = _Header()
    while not r.failed:
        header.read(r)
        var id = header.id
        if r.failed and id != PACKET_FRAME_END.value:
            break
        if id == PACKET_FRAME_START.value:
            frame = RecorderFrame.read(r)
            old = new^
            new = List[Int]()
        elif id == PACKET_EVENT_ADD.value:
            var total = r.u16()
            for _ in range(total):
                var e = RecordedEventAdd.read(r)
                last_added = e.database_id.value
                actors[last_added] = _Seen(e.type.value, e.description.id)
        elif id == PACKET_EVENT_DEL.value:
            var total = r.u16()
            for _ in range(total):
                _ = RecordedEventDel.read(r)
                # CARLA forgets the last actor added, not this one.
                if last_added in actors:
                    _ = actors.pop(last_added)
        elif id == PACKET_COLLISION.value:
            var total = r.u16()
            for _ in range(total):
                var c = RecordedCollision.read(r)
                var type1 = _category(actors, c.database_id1)
                var type2 = _category(actors, c.database_id2)
                if not (
                    _keeps(category1, type1, c.is_actor1_hero)
                    and _keeps(category2, type2, c.is_actor2_hero)
                ):
                    continue
                var pair = (c.database_id1.value << 32) + c.database_id2.value
                if not (pair in old):
                    out += pad_right(c_fixed(frame.elapsed, 0), 8)
                    out += "   " + chr(type1) + " " + chr(type2) + " "
                    out += " " + pad_right(String(c.database_id1.value), 6)
                    out += " " + pad_left(_name(actors, c.database_id1), 35)
                    out += " " + pad_right(String(c.database_id2.value), 6)
                    out += " " + pad_left(_name(actors, c.database_id2), 35)
                    out += "\n"
                    fixed = True
                if not (pair in new):
                    new.append(pair)
        elif id != PACKET_FRAME_END.value:
            r.skip(header.size)
    var duration = c_fixed(frame.elapsed, 0) if fixed else c_general(
        frame.elapsed
    )
    return out + _tail(frame, duration)


# --- blocked actors --------------------------------------------------------------


@fieldwise_init
struct _Stop(Copyable, Movable):
    var name: String
    var last_position: LogVector
    var time: Float64
    var duration: Float64


def _blocked_line(id: Int, s: _Stop) raises -> String:
    return (
        pad_right(c_fixed(s.time, 0), 8)
        + " "
        + pad_right(String(id), 6)
        + " "
        + pad_left(s.name, 35)
        + " "
        + pad_right(c_fixed(s.duration, 0), 10)
        + "\n"
    )


def _insert_result(
    mut results: List[Tuple[Float64, String]], duration: Float64, line: String
):
    """Keep the results longest first, and equal ones in the order they
    came, as a `std::multimap` with `std::greater` does."""
    var at = len(results)
    for i in range(len(results)):
        if results[i][0] < duration:
            at = i
            break
    results.insert(at, (duration, line))


def query_blocked(
    var bytes: List[UInt8],
    min_time: Duration = Duration(30, SECOND),
    min_distance: Length = Length(10, CENTIMETER),
) raises -> String:
    """List the actors that stood still, `CarlaRecorderQuery::QueryBlocked`.

    An actor stands still while each recorded position is less than the
    distance from the one where it last moved. It shows when it stood
    still for the time or longer.

    Args:
        bytes: The recording.
        min_time: The shortest stop to show. CARLA's default is 30 s.
        min_distance: The move that ends a stop. CARLA's default is 10 cm.

    Returns:
        CARLA's text: the header, a table of the time the stop started,
        the id, the blueprint id and the stop's duration, the longest
        first, then the number of frames and the duration.

    Raises:
        Error: If a record holds a kind that is not valid.
    """
    var min_seconds = Float64(min_time.to(SECOND))
    var min_cm = Float64(min_distance.to(CENTIMETER))
    var r = LogReader(bytes^)
    var out = String()
    if not _head(r, out):
        return out
    out += pad_right("Time", 8) + " " + pad_right("Id", 6) + " "
    out += pad_left("Actor", 35) + " " + pad_right("Duration", 10) + "\n"
    var actors = Dict[Int, _Stop]()
    var results = List[Tuple[Float64, String]]()
    var frame = RecorderFrame(0, 0, 0)
    var last_added = 0
    var header = _Header()
    while not r.failed:
        header.read(r)
        var id = header.id
        if r.failed and id != PACKET_FRAME_END.value:
            break
        if id == PACKET_FRAME_START.value:
            frame = RecorderFrame.read(r)
        elif id == PACKET_EVENT_ADD.value:
            var total = r.u16()
            for _ in range(total):
                var e = RecordedEventAdd.read(r)
                last_added = e.database_id.value
                actors[last_added] = _Stop(
                    e.description.id, LogVector(0, 0, 0), 0, 0
                )
        elif id == PACKET_EVENT_DEL.value:
            var total = r.u16()
            for _ in range(total):
                _ = RecordedEventDel.read(r)
                # CARLA forgets the last actor added, not this one.
                if last_added in actors:
                    _ = actors.pop(last_added)
        elif id == PACKET_POSITION.value:
            var total = r.u16()
            for _ in range(total):
                var pos = RecordedPosition.read(r)
                var key = pos.database_id.value
                if not (key in actors):
                    actors[key] = _Stop("", LogVector(0, 0, 0), 0, 0)
                ref s = actors[key]
                if s.last_position.distance(pos.location) < min_cm:
                    if s.duration == 0:
                        s.time = frame.elapsed
                    s.duration += frame.duration_this
                else:
                    if s.duration >= min_seconds:
                        _insert_result(
                            results, s.duration, _blocked_line(key, s)
                        )
                    s.duration = 0
                    s.last_position = pos.location
        elif id != PACKET_FRAME_END.value:
            r.skip(header.size)
    for entry in actors.items():
        if entry.value.duration >= min_seconds:
            _insert_result(
                results,
                entry.value.duration,
                _blocked_line(entry.key, entry.value),
            )
    for line in results:
        out += line[1]
    return out + _tail(frame, c_general(frame.elapsed))


# --- the file forms --------------------------------------------------------------


def _open(path: String, mut bytes: List[UInt8]) raises -> Bool:
    var p = Path(path)
    if not p.exists():
        return False
    bytes = p.read_bytes()
    return True


def show_recorder_file_info(
    name: String, show_all: Bool = False, saved_dir: String = ""
) raises -> String:
    """List a recording file, the client's `show_recorder_file_info`.

    Args:
        name: The file: a path, or a name in `saved_dir`.
        show_all: Whether to list every frame and packet.
        saved_dir: The folder of a bare name.

    Returns:
        CARLA's text, or `File <path> not found on server` and a newline.

    Raises:
        Error: If the file cannot be read, or a record is refused.
    """
    var path = recorder_file_path(name, saved_dir)
    var bytes = List[UInt8]()
    if not _open(path, bytes):
        return "File " + path + " not found on server\n"
    return query_info(bytes^, show_all)


def show_recorder_collisions(
    name: String,
    category1: CollisionCategory,
    category2: CollisionCategory,
    saved_dir: String = "",
) raises -> String:
    """List a file's collisions, the client's `show_recorder_collisions`.

    Args:
        name: The file: a path, or a name in `saved_dir`.
        category1: The first actor's category.
        category2: The second actor's category.
        saved_dir: The folder of a bare name.

    Returns:
        CARLA's text, or `File <path> not found on server` and a newline.

    Raises:
        Error: If the file cannot be read, a category is not valid, or a
            record is refused.
    """
    var path = recorder_file_path(name, saved_dir)
    var bytes = List[UInt8]()
    if not _open(path, bytes):
        return "File " + path + " not found on server\n"
    return query_collisions(bytes^, category1, category2)


def show_recorder_actors_blocked(
    name: String,
    min_time: Duration = Duration(30, SECOND),
    min_distance: Length = Length(10, CENTIMETER),
    saved_dir: String = "",
) raises -> String:
    """List a file's blocked actors, the client's
    `show_recorder_actors_blocked`.

    Args:
        name: The file: a path, or a name in `saved_dir`.
        min_time: The shortest stop to show.
        min_distance: The move that ends a stop.
        saved_dir: The folder of a bare name.

    Returns:
        CARLA's text, or `File <path> not found on server` and a newline.

    Raises:
        Error: If the file cannot be read, or a record is refused.
    """
    var path = recorder_file_path(name, saved_dir)
    var bytes = List[UInt8]()
    if not _open(path, bytes):
        return "File " + path + " not found on server\n"
    return query_blocked(bytes^, min_time, min_distance)
