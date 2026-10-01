# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sensors of a CARLA world: spawn one, listen to it, and read its
measurements on each tick.

`SensorManager.tick` steps the world and gives the measurements of that
tick, as CARLA's sensor manager runs each sensor after the physics,
`Carla/Sensor/SensorManager.cpp` and `Sensor.cpp` of CARLA's simulator
plugin. A sensor reads its settings from its actor's attributes, which
come from the world's blueprint library.

**One tick.**

1. Each V2X sensor that is due makes its cooperative awareness message,
   and each custom V2X sensor moves the messages sent since the last
   tick to its outbox, before the physics, as CARLA's pre-physics step
   does.
2. The world ticks.
3. Each sensor that is due measures, in the order it was listened to.
   The V2X sensors hear the messages that the others sent in step 1.

**When a sensor is due.** A sensor keeps the time since its last
measurement. It is due on the first tick that brings that time to its
`sensor_tick` or more; a `sensor_tick` of zero is every tick. Its
measurement uses that time as its tick. This is an interval timer, the
usual pattern for a fixed-step loop. The collision and lane invasion
sensors do not tick: they report on every world tick, as CARLA's event
and client-side sensors do.

**What each sensor gives.** Every measurement has the frame, the
simulation time, the sensor's transform, the 48-byte header and the
`raw_data` bytes of `extensions.carla.sensor_data`, and its own record:

| Blueprint | Record |
|---|---|
| `sensor.camera.depth`, `semantic_segmentation`, `instance_segmentation`, `normals` | `image` |
| `sensor.camera.rgb` | `image`: the shaded stand-in of `cameras.render_camera` |
| `sensor.camera.*_fisheye` | `image`, through the wide-angle lens |
| `sensor.camera.optical_flow` | `flow` |
| `sensor.camera.dvs` | `events`, only on a tick with events |
| `sensor.lidar.ray_cast`, `hss_lidar` | `lidar` |
| `sensor.lidar.ray_cast_semantic` | `semantic_lidar` |
| `sensor.other.radar` | `radar` |
| `sensor.other.imu` | `imu` |
| `sensor.other.gnss` | `gnss` |
| `sensor.other.collision` | `collision`, one a hit |
| `sensor.other.lane_invasion` | `lane_invasion`, only when a mark is crossed |
| `sensor.other.obstacle` | `obstacle`, only when something is ahead |
| `sensor.other.v2x` | `cams`, only when one is heard |
| `sensor.other.v2x_custom` | `custom`, only when one is heard |

A LiDAR tick with no points to fire gives the last measurement again, as
CARLA does. The rays are cast against the world's colliders with
`sensor_rays.WorldRays`.
"""

from extensions.carla.actor import (
    ActorId,
    NO_ACTOR,
    VEHICLE_ACTOR,
    no_rotation,
)
from extensions.carla.blueprint import ActorBlueprint
from extensions.carla.cameras import (
    CameraGeometry,
    CameraKind,
    DEPTH_IMAGE,
    DVSCamera,
    DVSConfig,
    DVSEvent,
    INSTANCE_IMAGE,
    NORMALS_IMAGE,
    SEMANTIC_IMAGE,
    SHADED_IMAGE,
    WideAngleLens,
    optical_flow,
    render_camera,
)
from extensions.carla.collision import (
    CollisionMeasurement,
    CollisionSensor,
)
from extensions.carla.geo import GeoLocation
from extensions.carla.gnss import (
    Gnss,
    GnssDescription,
)
from extensions.carla.imu import (
    IMU,
    IMUDescription,
    IMUMeasurement,
)
from extensions.carla.lane_invasion import (
    LaneInvasionEvent,
    LaneInvasionSensor,
)
from extensions.carla.lidar import LidarDescription
from extensions.carla.obstacle import (
    ObstacleDescription,
    ObstacleMeasurement,
    detect_obstacle,
)
from extensions.carla.radar import (
    Radar,
    RadarDescription,
    RadarDetection,
)
from extensions.carla.semantic_lidar import (
    LidarMeasurement,
    SemanticLidarMeasurement,
    hss_resolution_from,
    lidar_description_from,
    scan_hss_lidar,
    scan_ray_cast_lidar,
    scan_semantic_lidar,
)
from extensions.carla.sensor import CameraIntrinsics
from extensions.carla.sensor_attributes import (
    attribute_bool,
    attribute_float,
    attribute_int,
    attribute_string,
)
from extensions.carla.sensor_data import (
    SensorType,
    collision_data,
    dvs_data,
    gnss_data,
    image_data,
    imu_data,
    lidar_data,
    obstacle_data,
    optical_flow_data,
    radar_data,
    semantic_lidar_data,
    sensor_header,
    v2x_cam_data,
    v2x_custom_data,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.sensor_rays import WorldRays
from extensions.carla.transform import CarlaTransform
from extensions.carla.v2x import (
    CAM,
    CaService,
    CamNoise,
    CustomV2XMessage,
    PathLossModel,
    PropagationParams,
    ReceivedCam,
    ReceivedCustom,
    custom_message,
    simulate_channel,
)
from extensions.carla.world import World
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from units.si import (
    DEGREE,
    RADIAN,
    SECOND,
    Angle,
    Duration,
)


@fieldwise_init
struct SensorKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of CARLA's sensors a listened actor is."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the 22 sensors this manager runs.

        Returns:
            Whether the value is from 0 to 21.
        """
        return self.value >= 0 and self.value <= 21


comptime DEPTH_SENSOR = SensorKind(0)
comptime SEMANTIC_SENSOR = SensorKind(1)
comptime INSTANCE_SENSOR = SensorKind(2)
comptime NORMALS_SENSOR = SensorKind(3)
comptime OPTICAL_FLOW_SENSOR = SensorKind(4)
comptime DVS_SENSOR = SensorKind(5)
comptime RGB_SENSOR = SensorKind(6)
comptime RGB_FISHEYE_SENSOR = SensorKind(7)
comptime DEPTH_FISHEYE_SENSOR = SensorKind(8)
comptime SEMANTIC_FISHEYE_SENSOR = SensorKind(9)
comptime INSTANCE_FISHEYE_SENSOR = SensorKind(10)
comptime RAY_CAST_LIDAR_SENSOR = SensorKind(11)
comptime SEMANTIC_LIDAR_SENSOR = SensorKind(12)
comptime HSS_LIDAR_SENSOR = SensorKind(13)
comptime RADAR = SensorKind(14)
comptime GNSS = SensorKind(15)
comptime IMU_KIND = SensorKind(16)
comptime COLLISION = SensorKind(17)
comptime LANE_INVASION = SensorKind(18)
comptime OBSTACLE = SensorKind(19)
comptime V2X = SensorKind(20)
comptime CUSTOM_V2X = SensorKind(21)

# Each kind's blueprint id and registry place, in the order of the kinds.
comptime _IDS: Array[StaticString, 22] = [
    "sensor.camera.depth",
    "sensor.camera.semantic_segmentation",
    "sensor.camera.instance_segmentation",
    "sensor.camera.normals",
    "sensor.camera.optical_flow",
    "sensor.camera.dvs",
    "sensor.camera.rgb",
    "sensor.camera.rgb_fisheye",
    "sensor.camera.depth_fisheye",
    "sensor.camera.semantic_segmentation_fisheye",
    "sensor.camera.instance_segmentation_fisheye",
    "sensor.lidar.ray_cast",
    "sensor.lidar.ray_cast_semantic",
    "sensor.lidar.hss_lidar",
    "sensor.other.radar",
    "sensor.other.gnss",
    "sensor.other.imu",
    "sensor.other.collision",
    "sensor.other.lane_invasion",
    "sensor.other.obstacle",
    "sensor.other.v2x",
    "sensor.other.v2x_custom",
]
comptime _TYPES: Array[Int, 22] = [
    1, 14, 15, 2, 8, 3, 13, 17, 18, 20, 19, 11, 10, 23, 9, 4, 5, 0, 6, 7, 24, 25
]  # fmt: skip


def sensor_kind_of(blueprint_id: String) -> Optional[SensorKind]:
    """Return the sensor a blueprint id names.

    Args:
        blueprint_id: Such as "sensor.other.imu".

    Returns:
        The kind, or None for a blueprint this manager does not run.
    """
    var ids = materialize[_IDS]()
    # The table is a constant and not empty.
    for i in range(22):  # pragma: no branch
        if String(ids[i]) == blueprint_id:
            return SensorKind(i)
    return None


def sensor_type_of(kind: SensorKind) raises -> SensorType:
    """Return a sensor's place in CARLA's registry.

    Args:
        kind: The sensor.

    Returns:
        The place its header names.

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("A sensor kind must name one of 22 sensors")
    return SensorType(materialize[_TYPES]()[kind.value])


struct SensorMeasurement(Copyable, Movable):
    """What one sensor gives on one tick."""

    var sensor: ActorId
    var kind: SensorKind
    var frame: Int
    # In seconds of simulation time.
    var timestamp: Float64
    var transform: CarlaTransform
    # The 48-byte header and the measurement's bytes.
    var header: List[UInt8]
    var raw_data: List[UInt8]
    # A camera's image: its size and RGBA bytes, row by row from the top.
    var width: Int
    var height: Int
    var pixels: List[UInt8]
    var flow: List[Float32]
    var events: List[DVSEvent]
    var lidar: Optional[LidarMeasurement]
    var semantic_lidar: Optional[SemanticLidarMeasurement]
    var radar: List[RadarDetection]
    var imu: Optional[IMUMeasurement]
    var gnss: Optional[GeoLocation]
    var collision: Optional[CollisionMeasurement]
    var lane_invasion: Optional[LaneInvasionEvent]
    var obstacle: Optional[ObstacleMeasurement]
    var cams: List[ReceivedCam]
    var custom: List[ReceivedCustom]

    def __init__(
        out self, world: World, sensor: ActorId, kind: SensorKind
    ) raises:
        """Start an empty measurement stamped with the world's tick.

        Args:
            world: The world.
            sensor: The sensor.
            kind: What it is.

        Raises:
            Error: If the sensor is not alive or the kind is not valid.
        """
        self.sensor = sensor
        self.kind = kind
        self.frame = world.frame
        self.timestamp = world.elapsed_seconds
        self.transform = world.get_transform(sensor)
        self.header = sensor_header(
            sensor_type_of(kind), self.frame, self.timestamp, self.transform
        )
        self.raw_data = List[UInt8]()
        self.width = 0
        self.height = 0
        self.pixels = List[UInt8]()
        self.flow = List[Float32]()
        self.events = List[DVSEvent]()
        self.lidar = None
        self.semantic_lidar = None
        self.radar = List[RadarDetection]()
        self.imu = None
        self.gnss = None
        self.collision = None
        self.lane_invasion = None
        self.obstacle = None
        self.cams = List[ReceivedCam]()
        self.custom = List[ReceivedCustom]()

    def image(self) raises -> Framebuffer:
        """Return a camera's image.

        Returns:
            The image.

        Raises:
            Error: If the measurement holds no image.
        """
        if self.width == 0:
            raise Error("This measurement holds no image")
        return Framebuffer(self.width, self.height, self.pixels.copy())


struct _Slot(Movable):
    """One listened sensor and its state between ticks."""

    var id: ActorId
    var kind: SensorKind
    var sensor_tick: Float64
    var since: Float64
    var due: Bool
    var rng: SensorRandom
    var lidar: LidarDescription
    var hss_resolution: Angle
    var angle: Angle
    var last_lidar: Optional[LidarMeasurement]
    var last_semantic: Optional[SemanticLidarMeasurement]
    var geometry: Optional[CameraGeometry]
    var fov_field: Float32
    var previous_camera: CarlaTransform
    var dvs: Optional[DVSCamera]
    var radar: Optional[Radar]
    var imu: Optional[IMU]
    var gnss: Optional[Gnss]
    var collision: CollisionSensor
    var lane: Optional[LaneInvasionSensor]
    var obstacle: ObstacleDescription
    var channel: Optional[PathLossModel]
    var ca_service: Optional[CaService]
    var sent: Optional[CAM]
    var channel_id: String
    var outbox: List[CustomV2XMessage]
    var next_outbox: List[CustomV2XMessage]
    var transmit_power: Float32

    def __init__(
        out self, id: ActorId, kind: SensorKind, transform: CarlaTransform
    ):
        self.id = id
        self.kind = kind
        self.sensor_tick = 0
        self.since = 0
        self.due = False
        self.rng = SensorRandom(0)
        self.lidar = LidarDescription()
        self.hss_resolution = Angle(0.1, DEGREE)
        self.angle = Angle(0, RADIAN)
        self.last_lidar = None
        self.last_semantic = None
        self.geometry = None
        self.fov_field = 0
        self.previous_camera = transform
        self.dvs = None
        self.radar = None
        self.imu = None
        self.gnss = None
        self.collision = CollisionSensor()
        self.lane = None
        self.obstacle = ObstacleDescription()
        self.channel = None
        self.ca_service = None
        self.sent = None
        self.channel_id = String()
        self.outbox = List[CustomV2XMessage]()
        self.next_outbox = List[CustomV2XMessage]()
        self.transmit_power = 0


def _image_kind(kind: SensorKind) -> CameraKind:
    if kind == DEPTH_SENSOR or kind == DEPTH_FISHEYE_SENSOR:
        return DEPTH_IMAGE
    if kind == SEMANTIC_SENSOR or kind == SEMANTIC_FISHEYE_SENSOR:
        return SEMANTIC_IMAGE
    if kind == INSTANCE_SENSOR or kind == INSTANCE_FISHEYE_SENSOR:
        return INSTANCE_IMAGE
    if kind == NORMALS_SENSOR:
        return NORMALS_IMAGE
    return SHADED_IMAGE


def _is_camera(kind: SensorKind) -> Bool:
    return kind.value <= INSTANCE_FISHEYE_SENSOR.value


def _is_fisheye(kind: SensorKind) -> Bool:
    return (
        kind.value >= RGB_FISHEYE_SENSOR.value
        and kind.value <= INSTANCE_FISHEYE_SENSOR.value
    )


struct SensorManager(Movable):
    """The listened sensors of one world, `FSensorManager`."""

    var slots: List[_Slot]
    # Milliseconds from 2004 to the start, for the CAMs' generation time.
    var generation_delta0: Int

    def __init__(out self, generation_delta0: Int = 0):
        """Create a manager with no sensors.

        Args:
            generation_delta0: Milliseconds from 2004-01-01 to the start of
                the simulation. CARLA reads it from the wall clock.
        """
        self.slots = List[_Slot]()
        self.generation_delta0 = generation_delta0

    def spawn_sensor(
        mut self,
        mut world: World,
        blueprint: ActorBlueprint,
        transform: CarlaTransform,
        parent: ActorId = NO_ACTOR,
    ) raises -> ActorId:
        """Spawn a sensor and listen to it.

        Args:
            world: The world.
            blueprint: A `sensor.*` blueprint of the world's library, with
                any attributes set.
            transform: Where, in the parent's frame or in the world.
            parent: The actor to attach it to, or `NO_ACTOR`.

        Returns:
            The sensor's id.

        Raises:
            Error: If the spawn fails, or `listen` refuses the sensor.
        """
        var id = world.spawn_actor(blueprint, transform, parent)
        self.listen(world, id)
        return id

    def _find(self, id: ActorId) -> Int:
        for i in range(len(self.slots)):
            if self.slots[i].id == id:
                return i
        return -1

    def is_listening(self, id: ActorId) -> Bool:
        """Return whether a sensor is listened to, `IsListening`.

        Args:
            id: The sensor.

        Returns:
            Whether it is.
        """
        return self._find(id) >= 0

    def stop(mut self, id: ActorId):
        """Stop listening to a sensor, `Stop`.

        Args:
            id: The sensor. A sensor not listened to is ignored.
        """
        var i = self._find(id)
        if i >= 0:
            _ = self.slots.pop(i)

    def listen(mut self, world: World, id: ActorId) raises:
        """Listen to a spawned sensor, `Listen`.

        Args:
            world: The world.
            id: The sensor.

        Raises:
            Error: If the actor is not alive, is not a sensor this manager
                runs, is already listened to, or its settings are refused;
                or a lane invasion sensor's parent is not a vehicle.
        """
        var record = world.actor(id)
        var kind = sensor_kind_of(record.type_id)
        if not Bool(kind):
            raise Error("This actor is not a sensor: " + record.type_id)
        if self.is_listening(id):
            raise Error("The sensor is already listened to")
        var k = kind.value()
        ref a = record.attributes
        var slot = _Slot(id, k, world.get_transform(id))
        slot.sensor_tick = Float64(attribute_float(a, "sensor_tick", 0))
        slot.rng = SensorRandom(attribute_int(a, "noise_seed", 0))
        if _is_camera(k):
            var fov = attribute_float(a, "fov", 90)
            if _is_fisheye(k):
                var lens = WideAngleLens.from_attributes(a)
                slot.fov_field = lens.fov.to(RADIAN)
                slot.geometry = CameraGeometry.wide_angle(lens^)
            else:
                slot.fov_field = fov
                slot.geometry = CameraGeometry.pinhole(
                    CameraIntrinsics(
                        attribute_int(a, "image_size_x", 800),
                        attribute_int(a, "image_size_y", 600),
                        Angle(fov, DEGREE),
                    )
                )
            if k == DVS_SENSOR:
                slot.dvs = DVSCamera(
                    DVSConfig.from_attributes(a),
                    slot.geometry.value().width,
                    slot.geometry.value().height,
                    0,
                )
        elif k == RAY_CAST_LIDAR_SENSOR or k == SEMANTIC_LIDAR_SENSOR:
            slot.lidar = lidar_description_from(a)
            slot.lidar.validate()
        elif k == HSS_LIDAR_SENSOR:
            slot.lidar = lidar_description_from(a)
            slot.hss_resolution = hss_resolution_from(a)
        elif k == RADAR:
            slot.radar = Radar(
                RadarDescription.from_attributes(a), world.get_location(id)
            )
        elif k == GNSS:
            slot.gnss = Gnss(GnssDescription.from_attributes(a))
        elif k == IMU_KIND:
            slot.imu = IMU(IMUDescription.from_attributes(a))
        elif k == LANE_INVASION:
            if (
                record.parent == NO_ACTOR
                or world.actor(record.parent).kind != VEHICLE_ACTOR
            ):
                raise Error("A lane invasion sensor must be on a vehicle")
            slot.lane = LaneInvasionSensor(
                world.get_bounding_box(record.parent)
            )
        elif k == OBSTACLE:
            slot.obstacle = ObstacleDescription.from_attributes(a)
        elif k == V2X or k == CUSTOM_V2X:
            var params = PropagationParams.from_attributes(a)
            slot.transmit_power = params.transmit_power
            slot.channel = PathLossModel(params)
            slot.channel_id = attribute_string(a, "channel_id", "Default")
            if k == V2X:
                var owner = record.parent if record.parent != NO_ACTOR else id
                slot.ca_service = CaService(
                    world,
                    owner,
                    attribute_float(a, "gen_cam_min", 0.1),
                    attribute_float(a, "gen_cam_max", 1.0),
                    attribute_bool(a, "fixed_rate", False),
                    CamNoise.from_attributes(a),
                    self.generation_delta0,
                )
        self.slots.append(slot^)

    def send(mut self, world: World, id: ActorId, data: List[UInt8]) raises:
        """Queue a custom V2X message for the next tick,
        `ACustomV2XSensor::Send`.

        Args:
            world: The world.
            id: A listened `sensor.other.v2x_custom`.
            data: Up to 100 bytes.

        Raises:
            Error: If the sensor is not a listened custom V2X sensor, or
                the payload is too long.
        """
        var i = self._find(id)
        if i < 0 or self.slots[i].kind != CUSTOM_V2X:
            raise Error("Only a listened custom V2X sensor can send")
        var parent = world.actor(id).parent
        var station = parent.value if parent != NO_ACTOR else 0
        self.slots[i].next_outbox.append(custom_message(station, data))

    def tick(mut self, mut world: World) raises -> List[SensorMeasurement]:
        """Step the world, and measure each sensor that is due.

        Args:
            world: The world. It needs `fixed_delta_seconds`.

        Returns:
            The measurements of this tick, in the order the sensors were
            listened to.

        Raises:
            Error: If the world's tick fails, or a sensor that is not
                alive any more is still listened to.
        """
        if not Bool(world.settings.fixed_delta_seconds):
            raise Error("A tick needs fixed_delta_seconds")
        var dt = Float64(world.settings.fixed_delta_seconds.value().value)
        var projection = world.map.geo_projection.copy()
        for i in range(len(self.slots)):
            ref s = self.slots[i]
            s.since += dt
            s.due = s.since >= s.sensor_tick
            if s.kind == COLLISION or s.kind == LANE_INVASION:
                s.due = True
            if not s.due:
                continue
            if s.kind == V2X:
                s.sent = s.ca_service.value().trigger(
                    world, projection, Duration(Float32(s.since), SECOND), s.rng
                )
            elif s.kind == CUSTOM_V2X:
                s.outbox = s.next_outbox.copy()
                s.next_outbox.clear()
        _ = world.tick()
        var out = List[SensorMeasurement]()
        var rays = WorldRays(Pointer(to=world))
        for i in range(len(self.slots)):
            if not self.slots[i].due:
                continue
            var tick = Duration(Float32(self.slots[i].since), SECOND)
            self.slots[i].since = 0
            self._measure(world, rays, i, tick, out)
        return out^

    def _measure(
        mut self,
        world: World,
        mut rays: WorldRays,
        i: Int,
        tick: Duration,
        mut out: List[SensorMeasurement],
    ) raises:
        ref s = self.slots[i]
        var k = s.kind
        var m = SensorMeasurement(world, s.id, k)
        var pose = m.transform
        if _is_camera(k):
            ref geometry = s.geometry.value()
            if k == OPTICAL_FLOW_SENSOR:
                var k_matrix = geometry.intrinsics.value()
                m.flow = optical_flow(
                    rays, pose, s.previous_camera, k_matrix, tick
                )
                s.previous_camera = pose
                m.raw_data = optical_flow_data(
                    geometry.width, geometry.height, s.fov_field, m.flow
                )
            else:
                var image = render_camera(rays, _image_kind(k), pose, geometry)
                if k == DVS_SENSOR:
                    m.events = s.dvs.value().simulate(
                        image, world.elapsed_seconds
                    )
                    if len(m.events) == 0:
                        return
                    m.raw_data = dvs_data(
                        geometry.width, geometry.height, s.fov_field, m.events
                    )
                else:
                    m.raw_data = image_data(image, s.fov_field)
                    m.width = image.width
                    m.height = image.height
                    m.pixels = image.pixels.copy()
        elif k == RAY_CAST_LIDAR_SENSOR or k == HSS_LIDAR_SENSOR:
            var scan: Optional[LidarMeasurement]
            if k == HSS_LIDAR_SENSOR:
                scan = scan_hss_lidar(
                    rays, pose, s.lidar, s.hss_resolution, s.rng
                )
            else:
                scan = scan_ray_cast_lidar(
                    rays, pose, s.lidar, tick, s.angle, s.rng
                )
            if Bool(scan):
                s.angle = scan.value().horizontal_angle
                s.last_lidar = scan^
            if not Bool(s.last_lidar):
                return
            m.raw_data = lidar_data(s.last_lidar.value())
            m.lidar = s.last_lidar.copy()
        elif k == SEMANTIC_LIDAR_SENSOR:
            var scan = scan_semantic_lidar(rays, pose, s.lidar, tick, s.angle)
            if Bool(scan):
                s.angle = scan.value().horizontal_angle
                s.last_semantic = scan^
            if not Bool(s.last_semantic):
                return
            m.raw_data = semantic_lidar_data(s.last_semantic.value())
            m.semantic_lidar = s.last_semantic.copy()
        elif k == RADAR:
            m.radar = s.radar.value().measure(rays, pose, tick)
            m.raw_data = radar_data(m.radar)
        elif k == GNSS:
            var g = s.gnss.value().measure(
                pose.location, world.map.geo_projection
            )
            m.raw_data = gnss_data(g)
            m.gnss = g
        elif k == IMU_KIND:
            var parent = world.actor(s.id).parent
            var spin = Vector3(0, 0, 0)
            var parent_rotation = no_rotation()
            var relative = no_rotation()
            if parent != NO_ACTOR:
                parent_rotation = world.get_transform(parent).rotation
                relative = world.actor(s.id).local_transform.rotation
                var body = world.actor(parent).body
                if body.value >= 0:
                    spin = world.physics.angular_velocity(body)
            var reading = s.imu.value().measure(
                pose.location,
                pose.rotation,
                relative,
                spin,
                parent_rotation,
                tick,
                world.imu_gravity,
            )
            m.raw_data = imu_data(reading)
            m.imu = reading
        elif k == COLLISION:
            var parent = world.actor(s.id).parent
            if parent == NO_ACTOR:
                return
            for hit in s.collision.collect(world, parent):
                var each = SensorMeasurement(world, s.id, k)
                each.raw_data = collision_data(world, hit)
                each.collision = hit
                out.append(each^)
            return
        elif k == LANE_INVASION:
            var parent = world.actor(s.id).parent
            var event = s.lane.value().tick(
                world.map,
                world.frame,
                world.elapsed_seconds,
                world.get_transform(parent),
            )
            if not Bool(event):
                return
            m.transform = event.value().transform
            m.lane_invasion = event^
        elif k == OBSTACLE:
            var found = detect_obstacle(world, s.id, s.obstacle)
            if not Bool(found):
                return
            m.raw_data = obstacle_data(world, found.value())
            m.obstacle = found
        else:
            self._hear(world, i, m)
            if len(m.cams) == 0 and len(m.custom) == 0:
                return
            if self.slots[i].kind == CUSTOM_V2X:
                m.raw_data = v2x_custom_data(m.custom)
            else:
                m.raw_data = v2x_cam_data(m.cams)
        out.append(m^)

    def _hear(mut self, world: World, i: Int, mut m: SensorMeasurement) raises:
        """`PostPhysTick` of the V2X sensors: hear the others."""
        var senders = List[ActorId]()
        var powers = List[Float32]()
        var at = List[Int]()
        var custom = self.slots[i].kind == CUSTOM_V2X
        var order = List[Int]()
        # The receiver is in the list.
        for j in range(len(self.slots)):  # pragma: no branch
            order.append(j)
        # By actor id, as the ordering of the senders.
        for a in range(1, len(order)):
            var v = order[a]
            var b = a - 1
            while (
                b >= 0
                and self.slots[order[b]].id.value > self.slots[v].id.value
            ):
                order[b + 1] = order[b]
                b -= 1
            order[b + 1] = v
        # The receiver is in the list.
        for j in order:  # pragma: no branch
            ref other = self.slots[j]
            if j == i or other.kind != self.slots[i].kind:
                continue
            if custom:
                if (
                    other.channel_id != self.slots[i].channel_id
                    or len(other.outbox) == 0
                ):
                    continue
            elif not Bool(other.sent):
                continue
            senders.append(other.id)
            powers.append(other.transmit_power)
            at.append(j)
        if len(senders) == 0:
            return
        var heard = simulate_channel(
            world,
            self.slots[i].channel.value(),
            self.slots[i].id,
            senders,
            powers,
            self.slots[i].rng,
        )
        for h in heard:
            var j = at[senders.index(h.sender)]
            if custom:
                # A sender with an empty outbox is left out above.
                for msg in self.slots[j].outbox:  # pragma: no branch
                    m.custom.append(ReceivedCustom(h.power, msg.copy()))
            else:
                m.cams.append(ReceivedCam(h.power, self.slots[j].sent.value()))
