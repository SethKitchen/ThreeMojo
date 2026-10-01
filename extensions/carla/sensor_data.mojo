# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bytes a CARLA sensor sends: its header and its `raw_data`.

The sources are `LibCarla/source/carla/sensor/SensorRegistry.h`,
`s11n/SensorHeaderSerializer.h` and the serializer of each measurement in
`s11n/`, and the records in `sensor/data/` and `rpc/`. Every number is
little-endian, as CARLA's `memcpy` of its structs writes it on x86 and
ARM.

- The header is 48 bytes: the sensor's type as a `uint64`, its place in
  CARLA's sensor registry; the frame as a `uint64`; the timestamp as a
  `double`; and the sensor's transform as six `float`s, x, y, z, pitch,
  yaw and roll.
- An image (RGB, depth, semantic and instance segmentation, normals, and
  their wide-angle forms) is a 12-byte header, the width and height as
  `uint32` and the field of view as a `float`, then 4 bytes a pixel,
  blue, green, red and alpha, row by row from the top.
- An optical flow image has the same header, then two `float`s a pixel.
- An event camera's events follow the same header, 13 bytes each: x and y
  as `uint16`, the time as an `int64` and the polarity as a byte.
- A LiDAR's header is `uint32`s: the horizontal angle's bits, the channel
  count, and the points of each channel. The points follow: x, y, z and
  the intensity as `float`s, or for the semantic LiDAR x, y, z, the
  cosine as `float`s and the object index and tag as `uint32`s.
- A radar's detections are four `float`s each: the velocity, azimuth,
  altitude and depth.
- The IMU, the GNSS, the collision and the obstacle sensors send
  MessagePack: an array of the record's fields in order. A `float` is a
  float 32, a `double` a float 64, an integer and an enum the shortest
  form, a string the shortest string form, and a byte list a bin 8.
- An actor in a collision or obstacle event is `rpc::Actor`: its id, its
  parent's id, its description (the blueprint's uid, its id and its
  attributes), its box and its semantic tags. A map surface is id zero,
  `static.<tag>`, a zero box and its tag, as CARLA describes an actor
  it has not registered.

- A V2X sensor's messages are a copy of CARLA's C++ records, one after
  the other, with no count: `CAMData` is 3168 bytes and `CustomV2XData`
  is 136. The layout is the one that the LP64 ABI of Linux and macOS
  gives: a `long` is 8 bytes, a `bool` 1, and each field sits at a
  multiple of its size. `v2x_cam_data` and `v2x_custom_data` state each
  offset. The port writes zero in each padding byte, in each container
  that the message does not use, and in the fields that CARLA leaves
  unset.

**Not written.** The lane invasion sensor runs on the client and sends
nothing. The stream token that CARLA puts in a sensor's actor record is
a network handle; it is written empty.
"""

from extensions.carla.actor import (
    Actor,
    ActorId,
    NO_ACTOR,
)
from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.cameras import DVSEvent
from extensions.carla.collision import CollisionMeasurement
from extensions.carla.geo import GeoLocation
from extensions.carla.imu import IMUMeasurement
from extensions.carla.obstacle import ObstacleMeasurement

from extensions.carla.radar import RadarDetection
from extensions.carla.semantic_lidar import (
    LidarMeasurement,
    SemanticLidarMeasurement,
)
from extensions.carla.sensor import SemanticTag
from extensions.carla.transform import CarlaTransform
from extensions.carla.v2x import (
    CAM,
    CONTAINER_RSU,
    CONTAINER_VEHICLE,
    CUSTOM_V2X_MAX_BYTES,
    RSU_ZONE_LATITUDE,
    RSU_ZONE_LONGITUDE,
    ItsPduHeader,
    ReceivedCam,
    ReceivedCustom,
)
from extensions.carla.world import World
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from std.memory import bitcast
from units.si import (
    RADIAN,
    Angle,
)


@fieldwise_init
struct SensorType(Equatable, ImplicitlyCopyable, Writable):
    """A sensor's place in CARLA's `SensorRegistry`, the header's first
    field."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the registry's 26 places.

        Returns:
            Whether the value is from 0 to 25.
        """
        return self.value >= 0 and self.value <= 25


comptime COLLISION_SENSOR = SensorType(0)
comptime DEPTH_CAMERA = SensorType(1)
comptime NORMALS_CAMERA = SensorType(2)
comptime DVS_CAMERA = SensorType(3)
comptime GNSS_SENSOR = SensorType(4)
comptime IMU_SENSOR = SensorType(5)
comptime LANE_INVASION_SENSOR = SensorType(6)
comptime OBSTACLE_SENSOR = SensorType(7)
comptime OPTICAL_FLOW_CAMERA = SensorType(8)
comptime RADAR_SENSOR = SensorType(9)
comptime SEMANTIC_LIDAR = SensorType(10)
comptime RAY_CAST_LIDAR = SensorType(11)
comptime RSS_SENSOR = SensorType(12)
comptime RGB_CAMERA = SensorType(13)
comptime SEMANTIC_CAMERA = SensorType(14)
comptime INSTANCE_CAMERA = SensorType(15)
comptime WORLD_OBSERVER = SensorType(16)
comptime RGB_WIDE_ANGLE_CAMERA = SensorType(17)
comptime DEPTH_WIDE_ANGLE_CAMERA = SensorType(18)
comptime INSTANCE_WIDE_ANGLE_CAMERA = SensorType(19)
comptime SEMANTIC_WIDE_ANGLE_CAMERA = SensorType(20)
comptime GBUFFER_UINT8 = SensorType(21)
comptime GBUFFER_FLOAT = SensorType(22)
comptime HSS_LIDAR = SensorType(23)
comptime V2X_SENSOR = SensorType(24)
comptime CUSTOM_V2X_SENSOR = SensorType(25)


struct ByteWriter(Movable):
    """Little-endian bytes, and MessagePack on top of them."""

    var bytes: List[UInt8]

    def __init__(out self):
        """Start with no bytes."""
        self.bytes = List[UInt8]()

    def finish(deinit self) -> List[UInt8]:
        """Give up the bytes.

        Returns:
            Everything written.
        """
        return self.bytes^

    def u8(mut self, value: UInt8):
        """Write one byte.

        Args:
            value: The byte.
        """
        self.bytes.append(value)

    def _unsigned(mut self, value: UInt64, count: Int):
        # The callers write 2, 4 or 8 bytes.
        for i in range(count):  # pragma: no branch
            self.bytes.append(UInt8((value >> UInt64(8 * i)) & 0xFF))

    def u16(mut self, value: Int):
        """Write a `uint16`.

        Args:
            value: Its low 16 bits are written.
        """
        self._unsigned(UInt64(value & 0xFFFF), 2)

    def u32(mut self, value: Int):
        """Write a `uint32`.

        Args:
            value: Its low 32 bits are written.
        """
        self._unsigned(UInt64(value & 0xFFFFFFFF), 4)

    def u64(mut self, value: UInt64):
        """Write a `uint64`.

        Args:
            value: The number.
        """
        self._unsigned(value, 8)

    def i64(mut self, value: Int):
        """Write an `int64` in two's complement.

        Args:
            value: The number.
        """
        self._unsigned(UInt64(Int64(value)), 8)

    def f32(mut self, value: Float32):
        """Write a `float`'s bits.

        Args:
            value: The number.
        """
        self._unsigned(UInt64(bitcast[DType.uint32](value)), 4)

    def zeros(mut self, count: Int):
        """Write zero bytes, as padding or as an unused field.

        Args:
            count: How many.
        """
        # Every caller writes at least one byte.
        for _ in range(count):  # pragma: no branch
            self.bytes.append(0)

    def f64(mut self, value: Float64):
        """Write a `double`'s bits.

        Args:
            value: The number.
        """
        self._unsigned(bitcast[DType.uint64](value), 8)

    def big(mut self, value: UInt64, count: Int):
        """Write an unsigned number big-endian, as MessagePack does.

        Args:
            value: The number.
            count: How many bytes.
        """
        for i in range(count - 1, -1, -1):
            self.bytes.append(UInt8((value >> UInt64(8 * i)) & 0xFF))

    def pack_array(mut self, count: Int):
        """Start a MessagePack array.

        Args:
            count: How many items follow. A fixarray up to 15, else an
                array 16.
        """
        if count < 16:
            self.u8(UInt8(0x90 | count))
        else:
            self.u8(0xDC)
            self.big(UInt64(count), 2)

    def pack_uint(mut self, value: UInt64):
        """Write a MessagePack unsigned integer in its shortest form.

        Args:
            value: The number.
        """
        if value < 128:
            self.u8(UInt8(value))
        elif value < 256:
            self.u8(0xCC)
            self.big(value, 1)
        elif value < 65536:
            self.u8(0xCD)
            self.big(value, 2)
        elif value < 4294967296:
            self.u8(0xCE)
            self.big(value, 4)
        else:
            self.u8(0xCF)
            self.big(value, 8)

    def pack_float(mut self, value: Float32):
        """Write a MessagePack float 32.

        Args:
            value: The number.
        """
        self.u8(0xCA)
        self.big(UInt64(bitcast[DType.uint32](value)), 4)

    def pack_double(mut self, value: Float64):
        """Write a MessagePack float 64.

        Args:
            value: The number.
        """
        self.u8(0xCB)
        self.big(bitcast[DType.uint64](value), 8)

    def pack_str(mut self, text: String):
        """Write a MessagePack string in its shortest form.

        Args:
            text: The text, as UTF-8.
        """
        var n = text.byte_length()
        if n < 32:
            self.u8(UInt8(0xA0 | n))
        elif n < 256:
            self.u8(0xD9)
            self.big(UInt64(n), 1)
        else:
            self.u8(0xDA)
            self.big(UInt64(n), 2)
        for b in text.as_bytes():
            self.u8(b)

    def pack_bin(mut self, data: List[UInt8]):
        """Write MessagePack bin 8 data.

        Args:
            data: Up to 255 bytes.
        """
        self.u8(0xC4)
        self.big(UInt64(len(data)), 1)
        for b in data:
            self.u8(b)

    def pack_vector(mut self, v: Vector3):
        """Write a `Vector3D`: an array of three float 32s.

        Args:
            v: The vector.
        """
        self.pack_array(3)
        self.pack_float(v.x)
        self.pack_float(v.y)
        self.pack_float(v.z)


def sensor_header(
    type: SensorType, frame: Int, timestamp: Float64, transform: CarlaTransform
) raises -> List[UInt8]:
    """Write a message's header, `SensorHeaderSerializer::Serialize`.

    Args:
        type: The sensor's registry place.
        frame: The frame.
        timestamp: The simulation time, in seconds.
        transform: The sensor's pose.

    Returns:
        The 48 bytes.

    Raises:
        Error: If the type is not valid.
    """
    if not type.is_valid():
        raise Error("A sensor type must name a place in the registry")
    var w = ByteWriter()
    w.u64(UInt64(type.value))
    w.u64(UInt64(frame))
    w.f64(timestamp)
    w.f32(transform.location.x)
    w.f32(transform.location.y)
    w.f32(transform.location.z)
    w.f32(transform.rotation.pitch)
    w.f32(transform.rotation.yaw)
    w.f32(transform.rotation.roll)
    return w^.finish()


def _image_header(mut w: ByteWriter, width: Int, height: Int, fov: Float32):
    w.u32(width)
    w.u32(height)
    w.f32(fov)


def image_data(image: Framebuffer, fov: Float32) raises -> List[UInt8]:
    """Write an image, `ImageSerializer`.

    Args:
        image: The image.
        fov: The number CARLA writes as the field of view: degrees for a
            pinhole camera, the vertical fov in radians for a wide-angle
            one.

    Returns:
        The 12-byte header, then blue, green, red and alpha a pixel.

    Raises:
        Error: Never for a valid image; a pixel read is passed on.
    """
    var w = ByteWriter()
    _image_header(w, image.width, image.height, fov)
    for y in range(image.height):  # pragma: no branch
        for x in range(image.width):  # pragma: no branch
            var c = image.get_pixel(x, y)
            w.u8(c.b)
            w.u8(c.g)
            w.u8(c.r)
            w.u8(c.a)
    return w^.finish()


def optical_flow_data(
    width: Int, height: Int, fov: Float32, flow: List[Float32]
) raises -> List[UInt8]:
    """Write an optical flow image, `OpticalFlowImageSerializer`.

    Args:
        width: Pixels across.
        height: Pixels down.
        fov: The horizontal field of view, in degrees.
        flow: Two numbers a pixel.

    Returns:
        The 12-byte header, then the numbers as `float`s.

    Raises:
        Error: If `flow` does not hold two numbers a pixel.
    """
    if len(flow) != 2 * width * height:
        raise Error("An optical flow image needs two numbers a pixel")
    var w = ByteWriter()
    _image_header(w, width, height, fov)
    for f in flow:
        w.f32(f)
    return w^.finish()


def dvs_data(
    width: Int, height: Int, fov: Float32, events: List[DVSEvent]
) -> List[UInt8]:
    """Write an event camera's events, `DVSEventArraySerializer`.

    Args:
        width: Pixels across.
        height: Pixels down.
        fov: The horizontal field of view, in degrees.
        events: The events.

    Returns:
        The 12-byte header, then 13 packed bytes an event.
    """
    var w = ByteWriter()
    _image_header(w, width, height, fov)
    for e in events:
        w.u16(e.x)
        w.u16(e.y)
        w.i64(e.t)
        w.u8(UInt8(1) if e.pol else UInt8(0))
    return w^.finish()


def _lidar_header(
    mut w: ByteWriter, angle: Angle, channels: Int, counts: List[Int]
):
    w.f32(angle.to(RADIAN))
    w.u32(channels)
    for c in counts:
        w.u32(c)


def lidar_data(measurement: LidarMeasurement) -> List[UInt8]:
    """Write a ray-cast LiDAR's measurement, `LidarSerializer`.

    Args:
        measurement: The measurement.

    Returns:
        The header of `uint32`s, then x, y, z and the intensity a point.
    """
    var w = ByteWriter()
    _lidar_header(
        w,
        measurement.horizontal_angle,
        measurement.channel_count,
        measurement.points_per_channel,
    )
    for d in measurement.detections:
        w.f32(d.point.x)
        w.f32(d.point.y)
        w.f32(d.point.z)
        w.f32(d.intensity)
    return w^.finish()


def semantic_lidar_data(measurement: SemanticLidarMeasurement) -> List[UInt8]:
    """Write a semantic LiDAR's measurement, `SemanticLidarSerializer`.

    Args:
        measurement: The measurement.

    Returns:
        The header of `uint32`s, then 24 packed bytes a point.
    """
    var w = ByteWriter()
    _lidar_header(
        w,
        measurement.horizontal_angle,
        measurement.channel_count,
        measurement.points_per_channel,
    )
    for d in measurement.detections:
        w.f32(d.point.x)
        w.f32(d.point.y)
        w.f32(d.point.z)
        w.f32(d.cos_inc_angle)
        w.u32(Int(d.object_idx))
        w.u32(Int(d.object_tag))
    return w^.finish()


def radar_data(detections: List[RadarDetection]) -> List[UInt8]:
    """Write a radar's detections, `RadarSerializer`.

    Args:
        detections: The detections.

    Returns:
        Four `float`s a detection: velocity, azimuth and altitude in
        radians, and depth in meters.
    """
    var w = ByteWriter()
    for d in detections:
        w.f32(d.velocity)
        w.f32(d.azimuth.to(RADIAN))
        w.f32(d.altitude.to(RADIAN))
        w.f32(d.depth.value)
    return w^.finish()


def imu_data(measurement: IMUMeasurement) -> List[UInt8]:
    """Write an IMU reading, `IMUSerializer`: MessagePack of
    [accelerometer, gyroscope, compass].

    Args:
        measurement: The reading.

    Returns:
        The bytes.
    """
    var w = ByteWriter()
    w.pack_array(3)
    w.pack_vector(measurement.accelerometer)
    w.pack_vector(measurement.gyroscope)
    w.pack_float(measurement.compass.to(RADIAN))
    return w^.finish()


def gnss_data(location: GeoLocation) -> List[UInt8]:
    """Write a GNSS reading, `GnssSerializer`: MessagePack of
    [latitude, longitude, altitude] as doubles.

    Args:
        location: The reading.

    Returns:
        The bytes.
    """
    var w = ByteWriter()
    w.pack_array(3)
    w.pack_double(location.latitude_degrees)
    w.pack_double(location.longitude_degrees)
    w.pack_double(location.altitude_meters)
    return w^.finish()


# `ATagger::GetTagAsString` of each tag.
comptime _TAG_NAMES: Array[StaticString, 30] = [
    "None",
    "Roads",
    "Sidewalks",
    "Buildings",
    "Walls",
    "Fences",
    "Poles",
    "TrafficLight",
    "TrafficSigns",
    "Vegetation",
    "Terrain",
    "Sky",
    "Pedestrians",
    "Rider",
    "Car",
    "Truck",
    "Bus",
    "Train",
    "Motorcycle",
    "Bicycle",
    "Static",
    "Dynamic",
    "Other",
    "Water",
    "RoadLines",
    "Ground",
    "Bridge",
    "RailTrack",
    "GuardRail",
    "Rock",
]


def static_actor_id(tag: SemanticTag) raises -> String:
    """Return the id CARLA gives an unregistered actor,
    `CarlaGetRelevantTagAsString`.

    Args:
        tag: The actor's tag.

    Returns:
        "static." and the tag's name in lower case with a last "s" cut,
        or "static.unknown" for no tag and for "Other".

    Raises:
        Error: If the tag is not valid.
    """
    if not tag.is_valid():
        raise Error("Semantic tag is not valid")
    if tag.value == 0 or tag.value == 22:
        return "static.unknown"
    var names = materialize[_TAG_NAMES]()
    var name = String(names[tag.value]).lower()
    if name.endswith("s"):
        var cut = String(name[byte = : name.byte_length() - 1])
        name = cut
    return "static." + name


def _pack_box(mut w: ByteWriter, box: BoundingBox):
    w.pack_array(3)
    w.pack_vector(box.location)
    w.pack_vector(box.extent)
    w.pack_array(3)
    w.pack_float(box.rotation.pitch)
    w.pack_float(box.rotation.yaw)
    w.pack_float(box.rotation.roll)


def _pack_actor(
    mut w: ByteWriter,
    id: Int,
    parent: Int,
    uid: Int,
    type_id: String,
    attributes: List[ActorAttributeValue],
    box: BoundingBox,
    tags: List[SemanticTag],
):
    w.pack_array(6)
    w.pack_uint(UInt64(id))
    w.pack_uint(UInt64(parent))
    w.pack_array(3)
    w.pack_uint(UInt64(uid))
    w.pack_str(type_id)
    w.pack_array(len(attributes))
    for a in attributes:
        w.pack_array(3)
        w.pack_str(a.id)
        w.pack_uint(UInt64(a.type.value))
        w.pack_str(a.value)
    _pack_box(w, box)
    var bytes = List[UInt8]()
    for t in tags:
        bytes.append(UInt8(t.value))
    w.pack_bin(bytes)
    w.pack_bin(List[UInt8]())


def pack_actor(
    mut w: ByteWriter, world: World, id: ActorId, surface: SemanticTag
) raises:
    """Write an actor as `rpc::Actor`, `SerializeActor`.

    Args:
        w: Where to write.
        world: The world.
        id: The actor, or `NO_ACTOR` for a map surface.
        surface: The map surface's tag, when `id` is `NO_ACTOR`.

    Raises:
        Error: If the actor is not alive, or the surface's tag is not
            valid.
    """
    if id == NO_ACTOR:
        _pack_actor(
            w,
            0,
            0,
            0,
            static_actor_id(surface),
            List[ActorAttributeValue](),
            BoundingBox(Vector3(0, 0, 0)),
            [surface],
        )
        return
    var a = world.actor(id)
    var uid = 0
    var found = world.blueprints.find(a.type_id)
    if Bool(found):
        uid = found.value().uid
    _pack_actor(
        w,
        id.value,
        a.parent.value,
        uid,
        a.type_id,
        a.attributes,
        a.bounding_box,
        a.semantic_tags,
    )


def collision_data(
    world: World, measurement: CollisionMeasurement
) raises -> List[UInt8]:
    """Write a collision, `CollisionEventSerializer`: MessagePack of
    [self actor, other actor, normal impulse].

    Args:
        world: The world.
        measurement: The collision.

    Returns:
        The bytes.

    Raises:
        Error: If an actor is not alive.
    """
    var w = ByteWriter()
    w.pack_array(3)
    pack_actor(w, world, measurement.actor, measurement.other_tag)
    pack_actor(w, world, measurement.other_actor, measurement.other_tag)
    w.pack_vector(measurement.normal_impulse)
    return w^.finish()


def obstacle_data(
    world: World, measurement: ObstacleMeasurement
) raises -> List[UInt8]:
    """Write an obstacle, `ObstacleDetectionEventSerializer`: MessagePack
    of [self actor, other actor, distance].

    Args:
        world: The world.
        measurement: The detection.

    Returns:
        The bytes.

    Raises:
        Error: If an actor is not alive.
    """
    var w = ByteWriter()
    w.pack_array(3)
    pack_actor(w, world, measurement.actor, measurement.other_tag)
    pack_actor(w, world, measurement.other_actor, measurement.other_tag)
    w.pack_float(measurement.distance.value)
    return w^.finish()


# The sizes of CARLA's V2X records in the LP64 ABI.
comptime CAM_DATA_BYTES = 3168
comptime CUSTOM_V2X_DATA_BYTES = 136
# `ProtectedCommunicationZonesRSU::data` and `PathHistory::data`.
comptime _ZONE_SLOTS = 16
comptime _PATH_POINT_BYTES = 40 * 40


def _its_header(mut w: ByteWriter, header: ItsPduHeader):
    w.i64(header.protocol_version)
    w.i64(header.message_id.value)
    w.i64(header.station_id)


def _flag(mut w: ByteWriter, value: Bool):
    """A `bool` and the 7 bytes that align the `long` after it."""
    w.u8(UInt8(Int(value)))
    w.zeros(7)


def _vehicle_high_frequency(mut w: ByteWriter, cam: CAM):
    """`BasicVehicleContainerHighFrequency`: 264 bytes."""
    var h = cam.high_frequency
    if h.present != CONTAINER_VEHICLE:
        w.zeros(264)
        return
    w.i64(h.heading)
    w.i64(h.heading_confidence)
    w.i64(h.speed)
    w.i64(h.speed_confidence)
    w.i64(h.drive_direction)
    w.i64(h.vehicle_length)
    w.i64(h.vehicle_length_confidence)
    w.i64(h.vehicle_width)
    w.i64(h.longitudinal_acceleration)
    w.i64(h.acceleration_confidence)
    w.i64(h.curvature)
    w.i64(h.curvature_confidence)
    w.i64(h.curvature_calculation_mode)
    w.i64(h.yaw_rate)
    w.i64(h.yaw_rate_confidence)
    # The acceleration control and the lane position are not available:
    # two flags and a byte at 120, then the lane position at 128.
    w.zeros(16)
    # The steering wheel angle is not available.
    _flag(w, False)
    w.zeros(16)
    _flag(w, h.lateral_acceleration_available)
    w.i64(h.lateral_acceleration)
    w.i64(h.acceleration_confidence)
    _flag(w, h.vertical_acceleration_available)
    w.i64(h.vertical_acceleration)
    w.i64(h.acceleration_confidence)
    # The performance class and the tolling zone are not available.
    _flag(w, False)
    w.zeros(8)
    _flag(w, False)
    w.zeros(32)


def _rsu_high_frequency(mut w: ByteWriter, cam: CAM):
    """`RSUContainerHighFrequency`: a count and 16 zones of 72 bytes."""
    var h = cam.high_frequency
    var count = h.protected_zone_count if h.present == CONTAINER_RSU else 0
    w.i64(count)
    # A constant 16 slots.
    for i in range(_ZONE_SLOTS):  # pragma: no branch
        if i >= count:
            w.zeros(72)
            continue
        # A tolling zone, type 0, with no expiry time, radius or id.
        w.i64(0)
        w.i64(0)
        _flag(w, False)
        w.i64(RSU_ZONE_LATITUDE)
        w.i64(RSU_ZONE_LONGITUDE)
        w.i64(0)
        _flag(w, False)
        w.i64(0)
        _flag(w, False)


def v2x_cam_data(messages: List[ReceivedCam]) -> List[UInt8]:
    """Write what a V2X sensor heard, `CAMDataSerializer`.

    Each message is CARLA's `CAMData`, 3168 bytes. The offsets are:

    - 0: the power in dBm, a `float`, and 4 bytes of padding.
    - 8: the ITS header, three `long`s: protocol, message id, station id.
    - 32: the generation delta time.
    - 40: the basic container: the station type, then the latitude,
      longitude, the two semi-axes, the orientation, the altitude and its
      confidence.
    - 104: the high-frequency container's kind. The vehicle container
      follows at 112 and the roadside container at 376.
    - 1536: the low-frequency container's kind, then the vehicle role at
      1544, the exterior lights at 1552 and the path history at 1560: its
      count and 40 points of 40 bytes.

    A `long` is 8 bytes and a flag is 1 byte followed by 7 of padding.

    Args:
        messages: The messages, with the power each arrived with.

    Returns:
        The records, one after the other.
    """
    var w = ByteWriter()
    for m in messages:
        var cam = m.message
        w.f32(m.power)
        w.zeros(4)
        _its_header(w, cam.header)
        w.i64(cam.generation_delta_time)
        w.i64(cam.station_type.value)
        var p = cam.reference_position
        w.i64(p.latitude)
        w.i64(p.longitude)
        w.i64(p.semi_major_confidence)
        w.i64(p.semi_minor_confidence)
        w.i64(p.semi_major_orientation)
        w.i64(p.altitude)
        w.i64(p.altitude_confidence)
        w.i64(cam.high_frequency.present.value)
        _vehicle_high_frequency(w, cam)
        _rsu_high_frequency(w, cam)
        var low = cam.low_frequency
        w.i64(low.present.value)
        if low.present == CONTAINER_VEHICLE:
            w.i64(low.vehicle_role.value)
            w.u8(low.exterior_lights)
            w.zeros(7)
            w.i64(low.path_points)
        else:
            w.zeros(24)
        w.zeros(_PATH_POINT_BYTES)
    return w^.finish()


def v2x_custom_data(messages: List[ReceivedCustom]) raises -> List[UInt8]:
    """Write what a custom V2X sensor heard, `CustomV2XDataSerializer`.

    Each message is CARLA's `CustomV2XData`, 136 bytes: the power as a
    `float` and 4 bytes of padding; the ITS header at 8, three `long`s;
    the payload's length as one byte at 32; the 100 payload bytes at 33,
    zero past the length; and 3 bytes of padding.

    Args:
        messages: The messages, with the power each arrived with.

    Returns:
        The records, one after the other.

    Raises:
        Error: If a payload has more than 100 bytes.
    """
    var w = ByteWriter()
    for m in messages:
        if len(m.message.data) > CUSTOM_V2X_MAX_BYTES:
            raise Error("A custom V2X message holds 100 bytes at most")
        w.f32(m.power)
        w.zeros(4)
        _its_header(w, m.message.header)
        var data = m.message.data.copy()
        w.u8(UInt8(len(data)))
        for b in data:
            w.u8(b)
        w.zeros(CUSTOM_V2X_MAX_BYTES - len(data) + 3)
    return w^.finish()
