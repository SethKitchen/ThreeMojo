# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's recorder file: its header, its packets and their records.

A recording is a file info header, then one frame after another. Every
number is little-endian, as CARLA writes the bytes of its C++ values on
x86 and ARM. The header is:

| Field | Bytes |
|---|---|
| version, 1 | `uint16` |
| magic, `CARLA_RECORDER` | string |
| date, seconds since 1970 | `int64` |
| map name | string |

A string is its UTF-8 length as a `uint16`, then its bytes. A vector is
three `double`s.

Each packet is an id byte, the size of the rest as a `uint32`, and the
rest. A frame starts with a `FrameStart` packet: the frame's number as a
`uint64`, its duration and the time since the recording started as
`double`s. CARLA writes -1 as the duration, and writes the real duration
when the next frame starts: so the last frame keeps -1. A `FrameEnd`
packet, with nothing in it, ends the frame.

Most packets hold a `uint16` count and that many records. The records
keep CARLA's own units: a location in centimeters, a rotation as the
roll, pitch and yaw in degrees, in that order, a walker's speed in
centimeters per second. The records here keep the file's numbers as they
are, in the file's own types, so a file read and written again is the
same bytes, and a query prints what CARLA prints. `LogVector` turns a
location or a rotation into the world's units.

`RecorderPacketId` names the 25 packets. CARLA writes these in each frame,
in this order: `FrameStart`, `VisualTime`, `EventAdd`, `EventDel`,
`EventParent`, `Collision`, `VehicleDoor`, `Position`, `State`,
`AnimVehicle`, `AnimWalker`, `VehicleLight`, `SceneLight`,
`AnimVehicleWheels`, `AnimBiker` and `Weather`; with additional data
also `Kinematics`, `BoundingBox`, `TriggerVolume`, `PlatformTime`,
`PhysicsControl`, `TrafficLightTime` and `WalkerBones`; and `FrameEnd`.
`SceneLight`, `Weather`, `Kinematics`, `TriggerVolume`, `PhysicsControl`
and `TrafficLightTime` are left out when they have no record.
`FrameCounter` is defined, but CARLA never writes it.

The sources are CARLA's simulator plugin, `Carla/Recorder/
CarlaRecorder.h`, `CarlaRecorderHelpers.cpp`, `CarlaRecorderInfo.h`,
`CarlaRecorderFrames.cpp` and the file of each packet:
`CarlaRecorderEventAdd.cpp`, `CarlaRecorderEventDel.cpp`,
`CarlaRecorderEventParent.cpp`, `CarlaRecorderCollision.cpp`,
`CarlaRecorderPosition.cpp`, `CarlaRecorderState.cpp`,
`CarlaRecorderAnimVehicle.cpp`, `CarlaRecorderAnimVehicleWheels.cpp`,
`CarlaRecorderAnimWalker.cpp`, `CarlaRecorderAnimBiker.cpp`,
`CarlaRecorderLightVehicle.cpp`, `CarlaRecorderLightScene.cpp`,
`CarlaRecorderDoorVehicle.cpp`, `CarlaRecorderKinematics.cpp`,
`CarlaRecorderBoundingBox.cpp`, `CarlaRecorderPlatformTime.cpp`,
`CarlaRecorderTraficLightTime.cpp`, `CarlaRecorderVisualTime.cpp`,
`CarlaRecorderFrameCounter.cpp`, `CarlaRecorderWalkerBones.cpp` and
`CarlaRecorderWeather.cpp`. The physics control record is in
`recorder_physics`.
"""

from extensions.carla.actor import ActorId, ActorKind, TrafficLightState
from extensions.carla.blueprint import ActorAttributeType
from extensions.carla.physics.vehicle_control import Gear
from extensions.carla.sensor_data import ByteWriter
from extensions.carla.transform import CarlaRotation
from extensions.carla.vehicle import (
    VehicleDoor,
    VehicleLightState,
    VehicleWheelLocation,
)
from math.vector3 import Vector3
from math.vector4 import Vector4
from std.math import sqrt
from std.memory import bitcast
from units.si import DEGREE, Angle

comptime _INT32_MIN = -2147483648
comptime _INT32_MAX = 2147483647


# --- ids and kinds --------------------------------------------------------------


@fieldwise_init
struct RecorderPacketId(Equatable, ImplicitlyCopyable, Writable):
    """A packet's id byte, CARLA's `CarlaRecorderPacketId`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of CARLA's 25 packets.

        Returns:
            Whether the value is from 0 to 24.
        """
        return self.value >= 0 and self.value <= 24


comptime PACKET_FRAME_START = RecorderPacketId(0)
comptime PACKET_FRAME_END = RecorderPacketId(1)
comptime PACKET_EVENT_ADD = RecorderPacketId(2)
comptime PACKET_EVENT_DEL = RecorderPacketId(3)
comptime PACKET_EVENT_PARENT = RecorderPacketId(4)
comptime PACKET_COLLISION = RecorderPacketId(5)
comptime PACKET_POSITION = RecorderPacketId(6)
comptime PACKET_STATE = RecorderPacketId(7)
comptime PACKET_ANIM_VEHICLE = RecorderPacketId(8)
comptime PACKET_ANIM_WALKER = RecorderPacketId(9)
comptime PACKET_VEHICLE_LIGHT = RecorderPacketId(10)
comptime PACKET_SCENE_LIGHT = RecorderPacketId(11)
comptime PACKET_KINEMATICS = RecorderPacketId(12)
comptime PACKET_BOUNDING_BOX = RecorderPacketId(13)
comptime PACKET_PLATFORM_TIME = RecorderPacketId(14)
comptime PACKET_PHYSICS_CONTROL = RecorderPacketId(15)
comptime PACKET_TRAFFIC_LIGHT_TIME = RecorderPacketId(16)
comptime PACKET_TRIGGER_VOLUME = RecorderPacketId(17)
comptime PACKET_FRAME_COUNTER = RecorderPacketId(18)
comptime PACKET_WALKER_BONES = RecorderPacketId(19)
comptime PACKET_VISUAL_TIME = RecorderPacketId(20)
comptime PACKET_ANIM_VEHICLE_WHEELS = RecorderPacketId(21)
comptime PACKET_ANIM_BIKER = RecorderPacketId(22)
comptime PACKET_VEHICLE_DOOR = RecorderPacketId(23)
comptime PACKET_WEATHER = RecorderPacketId(24)


@fieldwise_init
struct SceneLightId(Equatable, ImplicitlyCopyable, Writable):
    """A scene light's id, CARLA's light id: a signed 32-bit number."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits a signed 32-bit number.

        Returns:
            Whether the value is from -2^31 to 2^31 - 1. CARLA's lights
            start at -1, no id.
        """
        return self.value >= _INT32_MIN and self.value <= _INT32_MAX


@fieldwise_init
struct SceneLightGroup(Equatable, ImplicitlyCopyable, Writable):
    """What a scene light lights, CARLA's `rpc::LightState::LightGroup`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a group.

        Returns:
            Whether the value is from 0 to 4.
        """
        return self.value >= 0 and self.value <= 4


comptime LIGHT_GROUP_NONE = SceneLightGroup(0)
comptime LIGHT_GROUP_VEHICLE = SceneLightGroup(1)
comptime LIGHT_GROUP_STREET = SceneLightGroup(2)
comptime LIGHT_GROUP_BUILDING = SceneLightGroup(3)
comptime LIGHT_GROUP_OTHER = SceneLightGroup(4)

# The actor id CARLA records for a hit on something that is not an actor.
comptime NOT_AN_ACTOR = ActorId(4294967295)

# The frame duration CARLA writes before it knows it.
comptime UNKNOWN_DURATION = Float64(-1)


def _check_id(id: ActorId) raises:
    if not id.is_valid():
        raise Error("Recorder: an actor id must fit 32 bits")


# --- vectors ---------------------------------------------------------------------


@fieldwise_init
struct LogVector(Equatable, ImplicitlyCopyable, Writable):
    """Three `double`s: a location in centimeters, a velocity or a
    rotation's roll, pitch and yaw in degrees."""

    var x: Float64
    var y: Float64
    var z: Float64

    @staticmethod
    def from_meters(v: Vector3) -> LogVector:
        """Return a location in meters as the file's centimeters.

        Args:
            v: The location in meters.

        Returns:
            Each part times 100.
        """
        return LogVector(
            Float64(v.x) * 100, Float64(v.y) * 100, Float64(v.z) * 100
        )

    def to_meters(self) -> Vector3:
        """Return the file's centimeters as a location in meters.

        Returns:
            Each part over 100.
        """
        return Vector3(
            Float32(self.x / 100), Float32(self.y / 100), Float32(self.z / 100)
        )

    @staticmethod
    def from_vector(v: Vector3) -> LogVector:
        """Widen a vector to the file's `double`s as it is.

        Args:
            v: The vector.

        Returns:
            The same numbers.
        """
        return LogVector(Float64(v.x), Float64(v.y), Float64(v.z))

    def to_vector(self) -> Vector3:
        """Narrow the file's `double`s to a vector as they are.

        Returns:
            The same numbers, rounded to `Float32`.
        """
        return Vector3(Float32(self.x), Float32(self.y), Float32(self.z))

    @staticmethod
    def from_rotation(r: CarlaRotation) -> LogVector:
        """Return a rotation as the file holds it: roll, pitch and yaw.

        Args:
            r: The rotation.

        Returns:
            The roll as x, the pitch as y and the yaw as z, in degrees.
        """
        return LogVector(Float64(r.roll), Float64(r.pitch), Float64(r.yaw))

    def to_rotation(self) -> CarlaRotation:
        """Return the file's roll, pitch and yaw as a rotation.

        Returns:
            The pitch from y, the yaw from z and the roll from x.
        """
        return CarlaRotation(
            Angle(Float32(self.y), DEGREE),
            Angle(Float32(self.z), DEGREE),
            Angle(Float32(self.x), DEGREE),
        )

    def distance(self, other: LogVector) -> Float64:
        """Return the distance to another vector, in the file's units.

        Args:
            other: The other vector.

        Returns:
            The length of the difference.
        """
        var dx = self.x - other.x
        var dy = self.y - other.y
        var dz = self.z - other.z
        return sqrt(dx * dx + dy * dy + dz * dz)


# --- reading ---------------------------------------------------------------------


struct LogReader(Movable):
    """Reads a recording as C++'s `std::ifstream` reads it.

    A read past the end reads nothing, and sets `failed`, as a stream's
    fail and end-of-file bits: the read's value is zero. A skip moves the
    position as `seekg` does, past the end too; the next read then fails.
    """

    var bytes: List[UInt8]
    var pos: Int
    var failed: Bool

    def __init__(out self, var bytes: List[UInt8]):
        """Start reading at the first byte.

        Args:
            bytes: The whole recording.
        """
        self.bytes = bytes^
        self.pos = 0
        self.failed = False

    def seek(mut self, pos: Int):
        """Go to a byte and clear the failure, `clear` and `seekg`.

        Args:
            pos: The byte's offset from the start.
        """
        self.failed = False
        self.pos = pos

    def skip(mut self, count: Int):
        """Move past bytes, `seekg` from the current position.

        Args:
            count: How many bytes. A failed reader stays failed.
        """
        self.pos += count

    def _take(mut self, count: Int) -> Int:
        """Claim `count` bytes; return where they start, or -1."""
        if self.failed or self.pos + count > len(self.bytes):
            self.failed = True
            self.pos = max(self.pos, len(self.bytes))
            return -1
        var at = self.pos
        self.pos += count
        return at

    def _unsigned(mut self, count: Int) -> UInt64:
        var at = self._take(count)
        if at < 0:
            return 0
        var value = UInt64(0)
        # Every read is of one byte or more.
        for i in range(count):  # pragma: no branch
            value |= UInt64(self.bytes[at + i]) << UInt64(8 * i)
        return value

    def u8(mut self) -> Int:
        """Read a byte.

        Returns:
            The byte, 0 to 255.
        """
        return Int(self._unsigned(1))

    def boolean(mut self) -> Bool:
        """Read a `bool` byte.

        Returns:
            Whether the byte is not zero.
        """
        return self._unsigned(1) != 0

    def u16(mut self) -> Int:
        """Read a `uint16`.

        Returns:
            The number.
        """
        return Int(self._unsigned(2))

    def u32(mut self) -> Int:
        """Read a `uint32`.

        Returns:
            The number.
        """
        return Int(self._unsigned(4))

    def i32(mut self) -> Int:
        """Read an `int32`.

        Returns:
            The number, with its sign.
        """
        return Int(Int32(UInt32(self._unsigned(4))))

    def u64(mut self) -> UInt64:
        """Read a `uint64`.

        Returns:
            The number.
        """
        return self._unsigned(8)

    def i64(mut self) -> Int:
        """Read an `int64`.

        Returns:
            The number, with its sign.
        """
        return Int(Int64(self._unsigned(8)))

    def f32(mut self) -> Float32:
        """Read a `float`.

        Returns:
            The number.
        """
        return bitcast[DType.float32](UInt32(self._unsigned(4)))

    def f64(mut self) -> Float64:
        """Read a `double`.

        Returns:
            The number.
        """
        return bitcast[DType.float64](self._unsigned(8))

    def vector(mut self) -> LogVector:
        """Read three `double`s.

        Returns:
            The vector.
        """
        var x = self.f64()
        var y = self.f64()
        var z = self.f64()
        return LogVector(x, y, z)

    def string(mut self) -> String:
        """Read a string: a `uint16` length and that many bytes.

        Returns:
            The text, or empty text with `failed` set if the bytes are
            incomplete or are not valid UTF-8.
        """
        var n = self.u16()
        var at = self._take(n)
        if at < 0:
            return String()
        var part = List[UInt8]()
        for i in range(n):
            part.append(self.bytes[at + i])
        try:
            return String(from_utf8=Span(part))
        except:
            self.failed = True
            return String()


# --- writing ---------------------------------------------------------------------


def write_string(mut w: ByteWriter, text: String):
    """Write a string as CARLA does: a `uint16` length and the bytes.

    Args:
        w: Where the bytes go.
        text: The text, as UTF-8.
    """
    w.u16(text.byte_length())
    for b in text.as_bytes():
        w.u8(b)


def write_vector(mut w: ByteWriter, v: LogVector):
    """Write three `double`s, as CARLA writes a vector.

    Args:
        w: Where the bytes go.
        v: The vector.
    """
    w.f64(v.x)
    w.f64(v.y)
    w.f64(v.z)


def write_packet(
    mut w: ByteWriter, id: RecorderPacketId, body: List[UInt8]
) raises:
    """Write a packet: the id byte, the body's size and the body.

    Args:
        w: Where the bytes go.
        id: The packet's id.
        body: What follows the size.

    Raises:
        Error: If the id is not valid.
    """
    if not id.is_valid():
        raise Error("Recorder: the packet id is not valid")
    w.u8(UInt8(id.value))
    w.u32(len(body))
    for b in body:
        w.u8(b)


# --- the file info and the frame -------------------------------------------------


@fieldwise_init
struct RecorderInfo(Copyable, Movable):
    """The file's header, `CarlaRecorderInfo`."""

    var version: Int
    var magic: String
    # Seconds since 1970-01-01 UTC, C's `time_t`.
    var date: Int
    var map_file: String

    def write(self, mut w: ByteWriter):
        """Write the header.

        Args:
            w: Where the bytes go.
        """
        w.u16(self.version)
        write_string(w, self.magic)
        w.i64(self.date)
        write_string(w, self.map_file)

    @staticmethod
    def read(mut r: LogReader) -> RecorderInfo:
        """Read the header.

        Args:
            r: The reader, at the start of the file.

        Returns:
            The header.
        """
        var version = r.u16()
        var magic = r.string()
        var date = r.i64()
        var map_file = r.string()
        return RecorderInfo(version, magic, date, map_file)


@fieldwise_init
struct RecorderFrame(ImplicitlyCopyable):
    """A frame's number and times, `CarlaRecorderFrame`, in seconds."""

    var id: UInt64
    var duration_this: Float64
    var elapsed: Float64

    @staticmethod
    def read(mut r: LogReader) -> RecorderFrame:
        """Read a frame record.

        Args:
            r: The reader, past the packet's header.

        Returns:
            The frame.
        """
        var id = r.u64()
        var duration = r.f64()
        var elapsed = r.f64()
        return RecorderFrame(id, duration, elapsed)


struct RecorderFrames(Movable):
    """The frame counter and where the last duration goes,
    `CarlaRecorderFrames`."""

    var frame: RecorderFrame
    # Where the last frame's duration sits, or zero before any frame.
    var offset_previous_frame: Int

    def __init__(out self):
        """Start before the first frame."""
        self.frame = RecorderFrame(0, 0, 0)
        self.offset_previous_frame = 0

    def reset(mut self):
        """Start again before the first frame, `Reset`."""
        self.frame = RecorderFrame(0, 0, 0)
        self.offset_previous_frame = 0

    def set_frame(mut self, delta_seconds: Float64):
        """Count a frame, `SetFrame`.

        The first frame has no duration and starts at zero. Each later
        frame's duration is the tick's, and the time adds it up.

        Args:
            delta_seconds: The tick's duration in seconds.
        """
        if self.frame.id == 0:
            self.frame.elapsed = 0
            self.frame.duration_this = 0
        else:
            self.frame.duration_this = delta_seconds
            self.frame.elapsed += delta_seconds
        self.frame.id += 1

    def write_start(mut self, mut w: ByteWriter) raises:
        """Write the `FrameStart` packet, `WriteStart`.

        The duration is written as -1. The duration of this frame is the
        previous frame's time to the next, so it goes back into the
        previous frame's record.

        Args:
            w: The recording so far.

        Raises:
            Error: Never; a packet id is always valid here.
        """
        var body = ByteWriter()
        body.u64(self.frame.id)
        body.f64(UNKNOWN_DURATION)
        body.f64(self.frame.elapsed)
        var offset = len(w.bytes) + 5 + 8
        write_packet(w, PACKET_FRAME_START, body^.finish())
        if self.offset_previous_frame > 0:
            var bits = bitcast[DType.uint64](self.frame.duration_this)
            for i in range(8):  # pragma: no branch
                w.bytes[self.offset_previous_frame + i] = UInt8(
                    (bits >> UInt64(8 * i)) & 0xFF
                )
        self.offset_previous_frame = offset

    def write_end(self, mut w: ByteWriter) raises:
        """Write the empty `FrameEnd` packet, `WriteEnd`.

        Args:
            w: The recording so far.

        Raises:
            Error: Never; a packet id is always valid here.
        """
        write_packet(w, PACKET_FRAME_END, List[UInt8]())


# --- event records ---------------------------------------------------------------


@fieldwise_init
struct RecordedAttribute(Copyable, Movable):
    """One attribute an actor was made with, `CarlaRecorderActorAttribute`."""

    var type: ActorAttributeType
    var id: String
    var value: String


@fieldwise_init
struct RecordedDescription(Copyable, Movable):
    """An actor's blueprint, `CarlaRecorderActorDescription`."""

    # The blueprint's number in its library.
    var uid: Int
    var id: String
    var attributes: List[RecordedAttribute]


@fieldwise_init
struct RecordedEventAdd(Copyable, Movable):
    """An actor that appeared, `CarlaRecorderEventAdd`."""

    var database_id: ActorId
    var type: ActorKind
    var location: LogVector
    var rotation: LogVector
    var description: RecordedDescription

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id, the kind or an attribute's type is not
                valid.
        """
        _check_id(self.database_id)
        if not self.type.is_valid():
            raise Error("Recorder: the actor kind is not valid")
        w.u32(self.database_id.value)
        w.u8(UInt8(self.type.value))
        write_vector(w, self.location)
        write_vector(w, self.rotation)
        w.u32(self.description.uid)
        write_string(w, self.description.id)
        w.u16(len(self.description.attributes))
        for a in self.description.attributes:
            if not a.type.is_valid():
                raise Error("Recorder: the attribute type is not valid")
            w.u8(UInt8(a.type.value))
            write_string(w, a.id)
            write_string(w, a.value)

    @staticmethod
    def read(mut r: LogReader) raises -> RecordedEventAdd:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.

        Raises:
            Error: If the kind or an attribute's type is not valid.
        """
        var id = ActorId(r.u32())
        var kind = ActorKind(r.u8())
        if not kind.is_valid():
            raise Error("Recorder: the actor kind is not valid")
        var location = r.vector()
        var rotation = r.vector()
        var uid = r.u32()
        var name = r.string()
        var total = r.u16()
        var attributes = List[RecordedAttribute]()
        for _ in range(total):
            var t = ActorAttributeType(r.u8())
            if not t.is_valid():
                raise Error("Recorder: the attribute type is not valid")
            var aid = r.string()
            var value = r.string()
            attributes.append(RecordedAttribute(t, aid, value))
        return RecordedEventAdd(
            id,
            kind,
            location,
            rotation,
            RecordedDescription(uid, name, attributes^),
        )


@fieldwise_init
struct RecordedEventDel(ImplicitlyCopyable):
    """An actor that went, `CarlaRecorderEventDel`."""

    var database_id: ActorId

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)

    @staticmethod
    def read(mut r: LogReader) -> RecordedEventDel:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        return RecordedEventDel(ActorId(r.u32()))


@fieldwise_init
struct RecordedEventParent(ImplicitlyCopyable):
    """An actor attached to another, `CarlaRecorderEventParent`."""

    var database_id: ActorId
    var database_id_parent: ActorId

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If an id is not valid.
        """
        _check_id(self.database_id)
        _check_id(self.database_id_parent)
        w.u32(self.database_id.value)
        w.u32(self.database_id_parent.value)

    @staticmethod
    def read(mut r: LogReader) -> RecordedEventParent:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var child = ActorId(r.u32())
        var parent = ActorId(r.u32())
        return RecordedEventParent(child, parent)


@fieldwise_init
struct RecordedCollision(ImplicitlyCopyable):
    """A hit between two actors, `CarlaRecorderCollision`. An id of
    `NOT_AN_ACTOR` is something that is not an actor."""

    var id: Int
    var database_id1: ActorId
    var database_id2: ActorId
    var is_actor1_hero: Bool
    var is_actor2_hero: Bool

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If an id is not valid.
        """
        _check_id(self.database_id1)
        _check_id(self.database_id2)
        w.u32(self.id)
        w.u32(self.database_id1.value)
        w.u32(self.database_id2.value)
        w.u8(UInt8(Int(self.is_actor1_hero)))
        w.u8(UInt8(Int(self.is_actor2_hero)))

    @staticmethod
    def read(mut r: LogReader) -> RecordedCollision:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = r.u32()
        var a = ActorId(r.u32())
        var b = ActorId(r.u32())
        var hero_a = r.boolean()
        var hero_b = r.boolean()
        return RecordedCollision(id, a, b, hero_a, hero_b)


# --- state records ---------------------------------------------------------------


@fieldwise_init
struct RecordedPosition(ImplicitlyCopyable):
    """Where an actor is, `CarlaRecorderPosition`."""

    var database_id: ActorId
    # In centimeters.
    var location: LogVector
    # Roll, pitch and yaw in degrees.
    var rotation: LogVector

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        write_vector(w, self.location)
        write_vector(w, self.rotation)

    @staticmethod
    def read(mut r: LogReader) -> RecordedPosition:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var location = r.vector()
        var rotation = r.vector()
        return RecordedPosition(id, location, rotation)


@fieldwise_init
struct RecordedTrafficLight(ImplicitlyCopyable):
    """A traffic light's state, `CarlaRecorderStateTrafficLight`."""

    var database_id: ActorId
    var is_frozen: Bool
    # Seconds in the current stage.
    var elapsed_time: Float32
    var state: TrafficLightState

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id or the state is not valid.
        """
        _check_id(self.database_id)
        if not self.state.is_valid():
            raise Error("Recorder: the traffic light state is not valid")
        w.u32(self.database_id.value)
        w.u8(UInt8(Int(self.is_frozen)))
        w.f32(self.elapsed_time)
        w.u8(UInt8(self.state.value))

    @staticmethod
    def read(mut r: LogReader) raises -> RecordedTrafficLight:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.

        Raises:
            Error: If the state is not valid.
        """
        var id = ActorId(r.u32())
        var frozen = r.boolean()
        var elapsed = r.f32()
        var state = TrafficLightState(r.u8())
        if not state.is_valid():
            raise Error("Recorder: the traffic light state is not valid")
        return RecordedTrafficLight(id, frozen, elapsed, state)


@fieldwise_init
struct RecordedAnimVehicle(ImplicitlyCopyable):
    """A vehicle's control, `CarlaRecorderAnimVehicle`."""

    var database_id: ActorId
    var steering: Float32
    var throttle: Float32
    var brake: Float32
    var handbrake: Bool
    var gear: Gear

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        w.f32(self.steering)
        w.f32(self.throttle)
        w.f32(self.brake)
        w.u8(UInt8(Int(self.handbrake)))
        w.u32(self.gear.value)

    @staticmethod
    def read(mut r: LogReader) -> RecordedAnimVehicle:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var steering = r.f32()
        var throttle = r.f32()
        var brake = r.f32()
        var handbrake = r.boolean()
        var gear = Gear(r.i32())
        return RecordedAnimVehicle(
            id, steering, throttle, brake, handbrake, gear
        )


@fieldwise_init
struct RecordedWheel(ImplicitlyCopyable):
    """One wheel's pose, CARLA's `WheelInfo`."""

    var location: VehicleWheelLocation
    # Degrees.
    var steering_angle: Float32
    # Degrees.
    var tire_rotation: Float32


@fieldwise_init
struct RecordedAnimWheels(Copyable, Movable):
    """A vehicle's wheels, `CarlaRecorderAnimWheels`."""

    var database_id: ActorId
    var wheels: List[RecordedWheel]

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id or a wheel's place is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        w.u32(len(self.wheels))
        for wheel in self.wheels:
            if not wheel.location.is_valid():
                raise Error("Recorder: the wheel location is not valid")
            w.u8(UInt8(wheel.location.value))
            w.f32(wheel.steering_angle)
            w.f32(wheel.tire_rotation)

    @staticmethod
    def read(mut r: LogReader) raises -> RecordedAnimWheels:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.

        Raises:
            Error: If a wheel's place is not valid.
        """
        var id = ActorId(r.u32())
        var count = r.u32()
        var wheels = List[RecordedWheel]()
        for _ in range(count):
            var at = VehicleWheelLocation(r.u8())
            if not at.is_valid():
                raise Error("Recorder: the wheel location is not valid")
            var steer = r.f32()
            var spin = r.f32()
            wheels.append(RecordedWheel(at, steer, spin))
        return RecordedAnimWheels(id, wheels^)


@fieldwise_init
struct RecordedAnimWalker(ImplicitlyCopyable):
    """A walker's speed, `CarlaRecorderAnimWalker`."""

    var database_id: ActorId
    # Centimeters per second.
    var speed: Float32

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        w.f32(self.speed)

    @staticmethod
    def read(mut r: LogReader) -> RecordedAnimWalker:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var speed = r.f32()
        return RecordedAnimWalker(id, speed)


@fieldwise_init
struct RecordedAnimBiker(ImplicitlyCopyable):
    """A two-wheeler's speed and engine, `CarlaRecorderAnimBiker`."""

    var database_id: ActorId
    var forward_speed: Float32
    # The engine's speed over its top speed.
    var engine_rotation: Float32

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        w.f32(self.forward_speed)
        w.f32(self.engine_rotation)

    @staticmethod
    def read(mut r: LogReader) -> RecordedAnimBiker:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var speed = r.f32()
        var engine = r.f32()
        return RecordedAnimBiker(id, speed, engine)


@fieldwise_init
struct RecordedLightVehicle(ImplicitlyCopyable):
    """A vehicle's lights, `CarlaRecorderLightVehicle`."""

    var database_id: ActorId
    var state: VehicleLightState

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id or the light state is not valid.
        """
        _check_id(self.database_id)
        if not self.state.is_valid():
            raise Error("Recorder: the light state is not valid")
        w.u32(self.database_id.value)
        w.u32(self.state.value)

    @staticmethod
    def read(mut r: LogReader) -> RecordedLightVehicle:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var state = VehicleLightState(r.u32())
        return RecordedLightVehicle(id, state)


@fieldwise_init
struct RecordedLightScene(ImplicitlyCopyable):
    """A scene light's setting, `CarlaRecorderLightScene`."""

    var light_id: SceneLightId
    var intensity: Float32
    # Linear red, green, blue and alpha as x, y, z and w.
    var color: Vector4
    var on: Bool
    var type: SceneLightGroup

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id or the group is not valid.
        """
        if not (self.light_id.is_valid() and self.type.is_valid()):
            raise Error("Recorder: the scene light id or group is not valid")
        w.u32(self.light_id.value)
        w.f32(self.intensity)
        w.f32(self.color.x)
        w.f32(self.color.y)
        w.f32(self.color.z)
        w.f32(self.color.w)
        w.u8(UInt8(Int(self.on)))
        w.u8(UInt8(self.type.value))

    @staticmethod
    def read(mut r: LogReader) raises -> RecordedLightScene:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.

        Raises:
            Error: If the group is not valid.
        """
        var id = SceneLightId(r.i32())
        var intensity = r.f32()
        var red = r.f32()
        var green = r.f32()
        var blue = r.f32()
        var alpha = r.f32()
        var on = r.boolean()
        var group = SceneLightGroup(r.u8())
        if not group.is_valid():
            raise Error("Recorder: the scene light group is not valid")
        return RecordedLightScene(
            id, intensity, Vector4(red, green, blue, alpha), on, group
        )


@fieldwise_init
struct RecordedDoorVehicle(ImplicitlyCopyable):
    """A door opened or closed, `CarlaRecorderDoorVehicle`."""

    var database_id: ActorId
    var doors: VehicleDoor
    var is_open: Bool

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id or the door is not valid.
        """
        _check_id(self.database_id)
        if not self.doors.is_valid():
            raise Error("Recorder: the door is not valid")
        w.u32(self.database_id.value)
        w.u8(UInt8(self.doors.value))
        w.u8(UInt8(Int(self.is_open)))

    @staticmethod
    def read(mut r: LogReader) -> RecordedDoorVehicle:
        """Read the record. A door that is not valid is kept: CARLA's
        query prints no name for it.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var door = VehicleDoor(r.u8())
        var open = r.boolean()
        return RecordedDoorVehicle(id, door, open)


@fieldwise_init
struct RecordedKinematics(ImplicitlyCopyable):
    """An actor's velocities, `CarlaRecorderKinematics`."""

    var database_id: ActorId
    # Meters per second.
    var linear_velocity: LogVector
    # Degrees per second.
    var angular_velocity: LogVector

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        write_vector(w, self.linear_velocity)
        write_vector(w, self.angular_velocity)

    @staticmethod
    def read(mut r: LogReader) -> RecordedKinematics:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var linear = r.vector()
        var angular = r.vector()
        return RecordedKinematics(id, linear, angular)


@fieldwise_init
struct RecordedBoundingBox(ImplicitlyCopyable):
    """An actor's box or a sign's trigger volume,
    `CarlaRecorderActorBoundingBox`."""

    var database_id: ActorId
    # The middle, in centimeters: in the actor's frame for a box, in the
    # world for a trigger volume.
    var origin: LogVector
    # The half size, in centimeters.
    var extension: LogVector

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        write_vector(w, self.origin)
        write_vector(w, self.extension)

    @staticmethod
    def read(mut r: LogReader) -> RecordedBoundingBox:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var origin = r.vector()
        var extension = r.vector()
        return RecordedBoundingBox(id, origin, extension)


@fieldwise_init
struct RecordedTrafficLightTime(ImplicitlyCopyable):
    """A light's stage times in seconds, `CarlaRecorderTrafficLightTime`."""

    var database_id: ActorId
    var green_time: Float32
    var yellow_time: Float32
    var red_time: Float32

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        w.f32(self.green_time)
        w.f32(self.yellow_time)
        w.f32(self.red_time)

    @staticmethod
    def read(mut r: LogReader) -> RecordedTrafficLightTime:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var green = r.f32()
        var yellow = r.f32()
        var red = r.f32()
        return RecordedTrafficLightTime(id, green, yellow, red)


@fieldwise_init
struct RecordedBone(Copyable, Movable):
    """One bone of a walker, `CarlaRecorderWalkerBone`."""

    var name: String
    # In its parent's frame, in centimeters.
    var location: LogVector
    # Roll, pitch and yaw in degrees.
    var rotation: LogVector


@fieldwise_init
struct RecordedWalkerBones(Copyable, Movable):
    """A walker's bones, `CarlaRecorderWalkerBones`."""

    var database_id: ActorId
    var bones: List[RecordedBone]

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id is not valid.
        """
        _check_id(self.database_id)
        w.u32(self.database_id.value)
        w.u16(len(self.bones))
        for b in self.bones:
            write_string(w, b.name)
            write_vector(w, b.location)
            write_vector(w, b.rotation)

    @staticmethod
    def read(mut r: LogReader) -> RecordedWalkerBones:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var id = ActorId(r.u32())
        var total = r.u16()
        var bones = List[RecordedBone]()
        for _ in range(total):
            var name = r.string()
            var location = r.vector()
            var rotation = r.vector()
            bones.append(RecordedBone(name, location, rotation))
        return RecordedWalkerBones(id, bones^)


@fieldwise_init
struct RecordedWeather(Equatable, ImplicitlyCopyable):
    """The weather, `CarlaRecorderWeather`: fourteen `float`s in CARLA's
    units, the sun's angles in degrees and the fog's distance in meters.
    """

    var cloudiness: Float32
    var precipitation: Float32
    var precipitation_deposits: Float32
    var wind_intensity: Float32
    var sun_azimuth_angle: Float32
    var sun_altitude_angle: Float32
    var fog_density: Float32
    var fog_distance: Float32
    var fog_falloff: Float32
    var wetness: Float32
    var scattering_intensity: Float32
    var mie_scattering_scale: Float32
    var rayleigh_scattering_scale: Float32
    var dust_storm: Float32

    def fields(self) -> List[Float32]:
        """Return the fourteen numbers in the file's order.

        Returns:
            The fields, cloudiness first and dust storm last.
        """
        return [
            self.cloudiness,
            self.precipitation,
            self.precipitation_deposits,
            self.wind_intensity,
            self.sun_azimuth_angle,
            self.sun_altitude_angle,
            self.fog_density,
            self.fog_distance,
            self.fog_falloff,
            self.wetness,
            self.scattering_intensity,
            self.mie_scattering_scale,
            self.rayleigh_scattering_scale,
            self.dust_storm,
        ]

    def write(self, mut w: ByteWriter):
        """Write the record.

        Args:
            w: Where the bytes go.
        """
        for f in self.fields():  # pragma: no branch
            w.f32(f)

    @staticmethod
    def read(mut r: LogReader) -> RecordedWeather:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.
        """
        var f = List[Float32]()
        for _ in range(14):  # pragma: no branch
            f.append(r.f32())
        return RecordedWeather(
            f[0],
            f[1],
            f[2],
            f[3],
            f[4],
            f[5],
            f[6],
            f[7],
            f[8],
            f[9],
            f[10],
            f[11],
            f[12],
            f[13],
        )


# --- packets of records ------------------------------------------------------------


def _count(mut w: ByteWriter, n: Int):
    """Write a record count as CARLA does: a `uint16`, cut to 16 bits."""
    w.u16(n)


def events_add_packet(
    mut w: ByteWriter, records: List[RecordedEventAdd]
) raises:
    """Write an `EventAdd` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_EVENT_ADD, body^.finish())


def events_del_packet(
    mut w: ByteWriter, records: List[RecordedEventDel]
) raises:
    """Write an `EventDel` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_EVENT_DEL, body^.finish())


def events_parent_packet(
    mut w: ByteWriter, records: List[RecordedEventParent]
) raises:
    """Write an `EventParent` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_EVENT_PARENT, body^.finish())


def collisions_packet(
    mut w: ByteWriter, records: List[RecordedCollision]
) raises:
    """Write a `Collision` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_COLLISION, body^.finish())


def positions_packet(mut w: ByteWriter, records: List[RecordedPosition]) raises:
    """Write a `Position` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_POSITION, body^.finish())


def states_packet(
    mut w: ByteWriter, records: List[RecordedTrafficLight]
) raises:
    """Write a `State` packet of traffic lights.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_STATE, body^.finish())


def anim_vehicles_packet(
    mut w: ByteWriter, records: List[RecordedAnimVehicle]
) raises:
    """Write an `AnimVehicle` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_ANIM_VEHICLE, body^.finish())


def anim_wheels_packet(
    mut w: ByteWriter, records: List[RecordedAnimWheels]
) raises:
    """Write an `AnimVehicleWheels` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_ANIM_VEHICLE_WHEELS, body^.finish())


def anim_walkers_packet(
    mut w: ByteWriter, records: List[RecordedAnimWalker]
) raises:
    """Write an `AnimWalker` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_ANIM_WALKER, body^.finish())


def anim_bikers_packet(
    mut w: ByteWriter, records: List[RecordedAnimBiker]
) raises:
    """Write an `AnimBiker` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_ANIM_BIKER, body^.finish())


def light_vehicles_packet(
    mut w: ByteWriter, records: List[RecordedLightVehicle]
) raises:
    """Write a `VehicleLight` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_VEHICLE_LIGHT, body^.finish())


def light_scenes_packet(
    mut w: ByteWriter, records: List[RecordedLightScene]
) raises:
    """Write a `SceneLight` packet, or nothing with no record.

    Args:
        w: Where the bytes go.
        records: The records.

    Raises:
        Error: If a record is refused.
    """
    if len(records) == 0:
        return
    var body = ByteWriter()
    _count(body, len(records))
    # There is a record, checked above.
    for r in records:  # pragma: no branch
        r.write(body)
    write_packet(w, PACKET_SCENE_LIGHT, body^.finish())


def doors_packet(mut w: ByteWriter, records: List[RecordedDoorVehicle]) raises:
    """Write a `VehicleDoor` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_VEHICLE_DOOR, body^.finish())


def kinematics_packet(
    mut w: ByteWriter, records: List[RecordedKinematics]
) raises:
    """Write a `Kinematics` packet, or nothing with no record.

    Args:
        w: Where the bytes go.
        records: The records.

    Raises:
        Error: If a record is refused.
    """
    if len(records) == 0:
        return
    var body = ByteWriter()
    _count(body, len(records))
    # There is a record, checked above.
    for r in records:  # pragma: no branch
        r.write(body)
    write_packet(w, PACKET_KINEMATICS, body^.finish())


def bounding_boxes_packet(
    mut w: ByteWriter, records: List[RecordedBoundingBox]
) raises:
    """Write a `BoundingBox` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_BOUNDING_BOX, body^.finish())


def trigger_volumes_packet(
    mut w: ByteWriter, records: List[RecordedBoundingBox]
) raises:
    """Write a `TriggerVolume` packet, or nothing with no record.

    Args:
        w: Where the bytes go.
        records: The records.

    Raises:
        Error: If a record is refused.
    """
    if len(records) == 0:
        return
    var body = ByteWriter()
    _count(body, len(records))
    # There is a record, checked above.
    for r in records:  # pragma: no branch
        r.write(body)
    write_packet(w, PACKET_TRIGGER_VOLUME, body^.finish())


def traffic_light_times_packet(
    mut w: ByteWriter, records: List[RecordedTrafficLightTime]
) raises:
    """Write a `TrafficLightTime` packet, or nothing with no record.

    Args:
        w: Where the bytes go.
        records: The records.

    Raises:
        Error: If a record is refused.
    """
    if len(records) == 0:
        return
    var body = ByteWriter()
    _count(body, len(records))
    # There is a record, checked above.
    for r in records:  # pragma: no branch
        r.write(body)
    write_packet(w, PACKET_TRAFFIC_LIGHT_TIME, body^.finish())


def walker_bones_packet(
    mut w: ByteWriter, records: List[RecordedWalkerBones]
) raises:
    """Write a `WalkerBones` packet.

    Args:
        w: Where the bytes go.
        records: The records, maybe none.

    Raises:
        Error: If a record is refused.
    """
    var body = ByteWriter()
    _count(body, len(records))
    for r in records:
        r.write(body)
    write_packet(w, PACKET_WALKER_BONES, body^.finish())


def weathers_packet(mut w: ByteWriter, records: List[RecordedWeather]) raises:
    """Write a `Weather` packet, or nothing with no record.

    Args:
        w: Where the bytes go.
        records: The records.

    Raises:
        Error: Never; a packet id is always valid here.
    """
    if len(records) == 0:
        return
    var body = ByteWriter()
    _count(body, len(records))
    # There is a record, checked above.
    for r in records:  # pragma: no branch
        r.write(body)
    write_packet(w, PACKET_WEATHER, body^.finish())


def time_packet(mut w: ByteWriter, id: RecorderPacketId, time: Float64) raises:
    """Write a packet of one `double`: `PlatformTime` or `VisualTime`.

    Args:
        w: Where the bytes go.
        id: The packet's id.
        time: The time in seconds.

    Raises:
        Error: If the id is not valid.
    """
    var body = ByteWriter()
    body.f64(time)
    write_packet(w, id, body^.finish())


def frame_counter_packet(mut w: ByteWriter, counter: UInt64) raises:
    """Write a `FrameCounter` packet, `CarlaRecorderFrameCounter`.

    CARLA defines it but does not write it; a reader skips it.

    Args:
        w: Where the bytes go.
        counter: The frame counter.

    Raises:
        Error: Never; a packet id is always valid here.
    """
    var body = ByteWriter()
    body.u64(counter)
    write_packet(w, PACKET_FRAME_COUNTER, body^.finish())
