# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's sensors against numbers from outside the port.

The rays meet `_Planes`, a ground plane and a wall worked by hand. The
expected numbers come from:

- Hand calculation: the LiDAR and radar geometry, the lens models, the
  IMU's parabola, the compass, the event camera's crossings.
- A C++ program built with GCC 13 and the GNU C++ library: the draws of
  `std::minstd_rand` through `std::uniform_real_distribution<float>` and
  `std::normal_distribution<float>`, and CARLA's LiDAR post-processing,
  radar rays, IMU, GNSS and fading noise written as CARLA writes them.
- A Python model of CARLA's `PathLossModel.cpp` for the V2X losses.
- Python's `struct` and a MessagePack writer written from the
  specification for the bytes of `sensor_data`.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.carla.actor import (
    ActorId,
    NO_ACTOR,
)
from extensions.carla.blueprint import (
    ATTRIBUTE_BOOL,
    ATTRIBUTE_FLOAT,
    ATTRIBUTE_INT,
    ATTRIBUTE_STRING,
    ActorAttributeValue,
    default_blueprint_library,
)
from extensions.carla.cameras import (
    CameraGeometry,
    CameraKind,
    CameraModel,
    DEPTH_IMAGE,
    DVSCamera,
    DVSConfig,
    DVSEvent,
    EQUIDISTANT,
    EQUISOLID,
    INSTANCE_IMAGE,
    KANNALA_BRANDT,
    NORMALS_IMAGE,
    ORTHOGRAPHIC,
    PERSPECTIVE,
    SEMANTIC_IMAGE,
    SHADED_IMAGE,
    STEREOGRAPHIC,
    WideAngleLens,
    camera_model_of,
    compute_angle,
    compute_distance,
    encode_normal,
    gray,
    kannala_brandt_derivative,
    kannala_brandt_polynomial,
    optical_flow,
    render_camera,
)
from extensions.carla.geo import (
    GeoLocation,
    GeoProjection,
)
from extensions.carla.gnss import (
    Gnss,
    GnssDescription,
)
from extensions.carla.imu import (
    Accelerometer,
    FLOAT_MAX,
    IMU,
    IMUDescription,
    IMUMeasurement,
    compass,
)
from extensions.carla.lidar import LidarDescription
from extensions.carla.pointcloud import (
    LidarDetection,
    SemanticLidarDetection,
)
from extensions.carla.radar import (
    Radar,
    RadarDescription,
    RadarDetection,
)
from extensions.carla.semantic_lidar import (
    LidarMeasurement,
    SemanticLidarMeasurement,
    hss_points_per_laser,
    hss_resolution_from,
    lidar_description_from,
    round_half_from_zero,
    scan_hss_lidar,
    scan_ray_cast_lidar,
    scan_semantic_lidar,
    semantic_detection,
)
from extensions.carla.sensor import (
    BUILDING,
    BUS,
    CAR,
    CameraIntrinsics,
    OTHER_OBJECT,
    PEDESTRIAN,
    ROAD,
    SKY,
    SemanticTag,
    UNLABELED,
    decode_depth,
)
from extensions.carla.sensor_attributes import (
    attribute_bool,
    attribute_float,
    attribute_int,
    attribute_string,
)
from extensions.carla.sensor_data import (
    ByteWriter,
    IMU_SENSOR,
    SensorType,
    dvs_data,
    gnss_data,
    image_data,
    imu_data,
    lidar_data,
    optical_flow_data,
    radar_data,
    semantic_lidar_data,
    sensor_header,
    static_actor_id,
    v2x_cam_data,
    v2x_custom_data,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.sensor_rays import (
    MeshRays,
    RayScene,
    SensorHit,
)
from extensions.carla.transform import (
    CarlaRotation,
    CarlaTransform,
    carla_to_three,
)
from extensions.carla.v2x import (
    CAM,
    CONTAINER_NOTHING,
    CONTAINER_RSU,
    CONTAINER_VEHICLE,
    CUSTOM_V2X_MAX_BYTES,
    CustomV2XMessage,
    HighFrequencyContainer,
    ItsPduHeader,
    LowFrequencyContainer,
    MESSAGE_CAM,
    MESSAGE_CUSTOM,
    ReceivedCam,
    ReceivedCustom,
    ReferencePosition,
    ContainerKind,
    GEOMETRIC,
    HIGHWAY,
    LOS,
    MessageId,
    NLOS_BUILDING,
    NLOS_VEHICLE,
    PathLossKind,
    PathLossModel,
    PathState,
    PropagationParams,
    ROLE_DEFAULT,
    ROLE_EMERGENCY,
    ROLE_PUBLIC_TRANSPORT,
    RURAL,
    STATION_BUS,
    STATION_CYCLIST,
    STATION_LIGHT_TRUCK,
    STATION_MOTORCYCLE,
    STATION_PASSENGER_CAR,
    STATION_PEDESTRIAN,
    STATION_ROAD_SIDE_UNIT,
    STATION_SPECIAL_VEHICLES,
    STATION_TRAM,
    STATION_UNKNOWN,
    Scenario,
    StationType,
    URBAN,
    VehicleRole,
    WINNER,
    custom_message,
    round_half_away,
    speed_value,
    station_type_of,
    vehicle_role_of,
)
from geometries.box import cube
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import (
    Color,
    Framebuffer,
)
from std.math import (
    cos,
    inf,
    nan,
    pi,
    sin,
    sqrt,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Duration64,
    DEGREE,
    PER_METER,
    RADIAN,
    SECOND,
    Acceleration,
    Angle,
    Duration,
    InverseLength,
    Length,
    METER,
)


def _deg(value: Float32) -> Angle:
    return Angle(value, DEGREE)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _s(value: Float32) -> Duration:
    return Duration(value, SECOND)


def _rot(pitch: Float32, yaw: Float32, roll: Float32) -> CarlaRotation:
    return CarlaRotation(_deg(pitch), _deg(yaw), _deg(roll))


def _pose(
    x: Float32, y: Float32, z: Float32, yaw: Float32 = 0
) -> CarlaTransform:
    return CarlaTransform(_m(x), _m(y), _m(z), _rot(0, yaw, 0))


def _near(
    a: Vector3, x: Float32, y: Float32, z: Float32, tol: Float64 = 1e-5
) raises:
    assert_almost_equal(a.x, x, atol=tol)
    assert_almost_equal(a.y, y, atol=tol)
    assert_almost_equal(a.z, z, atol=tol)


def _hex(bytes: List[UInt8]) -> String:
    comptime digits = "0123456789abcdef"
    var out = String()
    for b in bytes:
        out += digits[byte=Int(b >> 4)]
        out += digits[byte=Int(b & 15)]
    return out^


struct _Planes(RayScene):
    """The ground z = 0, a road, and a wall at x = `wall` facing the
    origin, building 7, moving at `wall_velocity`."""

    var ground: Bool
    var wall: Float32
    var wall_velocity: Vector3

    def __init__(out self, ground: Bool, wall: Float32):
        self.ground = ground
        self.wall = wall
        self.wall_velocity = Vector3(0, 0, 0)

    def cast_ray(
        mut self, origin: Vector3, direction: Vector3, far: Length
    ) raises -> SensorHit:
        var unit = direction / direction.length()
        var best = SensorHit.miss()
        if self.ground and unit.z < 0:
            var t = -origin.z / unit.z
            if t <= far.value:
                best = SensorHit(
                    True,
                    _m(t),
                    origin + unit * t,
                    Vector3(0, 0, 1),
                    NO_ACTOR,
                    ROAD,
                    Vector3(0, 0, 0),
                    Vector3(0, 0, 0),
                )
        if self.wall > 0 and unit.x > 0:
            var t = (self.wall - origin.x) / unit.x
            if t <= far.value and (not best.hit or t < best.distance.value):
                best = SensorHit(
                    True,
                    _m(t),
                    origin + unit * t,
                    Vector3(-1, 0, 0),
                    ActorId(7),
                    BUILDING,
                    self.wall_velocity,
                    self.wall_velocity,
                )
        return best


# --- the engine ------------------------------------------------------------------


def test_minstd_rand_matches_the_standard() raises:
    # `std::minstd_rand` seeded with 0 or 2^31 - 1 starts from state 1.
    var zero = SensorRandom(0)
    assert_equal(Int(zero.next()), 48271)
    assert_equal(Int(zero.next()), 182605794)
    assert_equal(Int(zero.next()), 1291394886)
    var top = SensorRandom(2147483647)
    assert_equal(Int(top.next()), 48271)
    var answer = SensorRandom(42)
    assert_equal(Int(answer.next()), 2027382)
    # A negative seed wraps through the unsigned 64-bit type.
    var negative = SensorRandom(-1)
    assert_equal(Int(negative.next()), 144813)


def test_distributions_match_the_gnu_library() raises:
    var r = SensorRandom(42)
    assert_almost_equal(r.uniform(), 0.000944072846, atol=1e-12)
    assert_almost_equal(r.uniform(), 0.571362853, atol=1e-8)
    r = SensorRandom(42)
    assert_almost_equal(r.uniform_in(2, 5), 2.00283217, atol=1e-6)
    r = SensorRandom(42)
    assert_almost_equal(r.normal(1, 2), 0.296966851, atol=1e-5)
    assert_almost_equal(r.normal(1, 2), 1.48987615, atol=1e-5)
    assert_equal(Int(r.next()), 1350734175)
    # A deviation of zero still draws.
    r = SensorRandom(42)
    assert_equal(r.normal(0, 0), 0)
    assert_equal(Int(r.next()), 1404753842)


def test_uniform_stays_below_one() raises:
    # The last state rounds to 2^31 in a `Float32`: the result is the
    # float below one, as the GNU library clamps it.
    var r = SensorRandom(0)
    r.state = 247665088  # times 48271 is 2^31 - 2, modulo 2^31 - 1
    assert_equal(r.uniform(), 0.99999994039535522)


# --- attributes ------------------------------------------------------------------


def test_attributes_read_as_carla_reads_them() raises:
    var a: List[ActorAttributeValue] = [
        ActorAttributeValue("f", ATTRIBUTE_FLOAT, "3.5f"),
        ActorAttributeValue("i", ATTRIBUTE_INT, "12abc"),
        ActorAttributeValue("b", ATTRIBUTE_BOOL, "True"),
        ActorAttributeValue("b2", ATTRIBUTE_BOOL, "no"),
        ActorAttributeValue("s", ATTRIBUTE_STRING, "urban"),
    ]
    assert_equal(attribute_float(a, "f", 1), 3.5)
    assert_equal(attribute_float(a, "missing", 1), 1)
    # A mistyped attribute gives the default, as CARLA's reader does.
    assert_equal(attribute_float(a, "i", 2), 2)
    assert_equal(attribute_int(a, "i", 0), 12)
    assert_equal(attribute_int(a, "f", 7), 7)
    assert_true(attribute_bool(a, "b", False))
    assert_false(attribute_bool(a, "b2", True))
    assert_true(attribute_bool(a, "s", True))
    assert_equal(attribute_string(a, "s", "x"), "urban")
    assert_equal(attribute_string(a, "b", "x"), "x")
    assert_equal(attribute_string(a, "none", "x"), "x")


# --- the LiDARs ------------------------------------------------------------------


def _lidar() -> LidarDescription:
    # Two lasers, at 0 and -30 degrees, 90 degrees across, two rays each
    # in a 0.1 s tick: at -45 and 0 degrees from a start of zero.
    var d = LidarDescription()
    d.channels = 2
    d.upper_fov = _deg(0)
    d.lower_fov = _deg(-30)
    d.horizontal_fov = _deg(90)
    d.points_per_second = 40
    d.range = _m(20)
    return d


def test_semantic_lidar_casts_carlas_rays() raises:
    var scene = _Planes(True, 10)
    var sensor = _pose(0, 0, 2)
    var m = scan_semantic_lidar(scene, sensor, _lidar(), _s(0.1), _deg(0))
    var out = m.value().copy()
    assert_equal(out.channel_count, 2)
    assert_equal(out.points_per_channel[0], 2)
    assert_equal(out.points_per_channel[1], 2)
    # The sweep of 90 degrees wraps back to zero.
    assert_almost_equal(out.horizontal_angle.to(RADIAN), 0, atol=1e-6)
    var c30 = Float32(sqrt(3.0) / 2)
    var d = out.detections.copy()
    # The flat laser meets the wall at x = 10; its local z is zero.
    _near(d[0].point, 10, -10, 0, 1e-4)
    assert_almost_equal(d[0].cos_inc_angle, 0.70710678, atol=1e-5)
    assert_equal(Int(d[0].object_idx), 7)
    assert_equal(Int(d[0].object_tag), BUILDING.value)
    _near(d[1].point, 10, 0, 0, 1e-4)
    assert_almost_equal(d[1].cos_inc_angle, 1, atol=1e-6)
    # The lower laser meets the road 4 m away, at a cosine of sin 30.
    _near(d[2].point, 4 * c30 * 0.70710678, -4 * c30 * 0.70710678, -2, 1e-4)
    assert_almost_equal(d[2].cos_inc_angle, 0.5, atol=1e-5)
    assert_equal(Int(d[2].object_idx), 0)
    assert_equal(Int(d[2].object_tag), ROAD.value)
    _near(d[3].point, 4 * c30, 0, -2, 1e-4)
    # From 30 degrees, the rays point at -15 and 30 and the next tick
    # starts at 120 mod 90 = 30 degrees.
    var turned = (
        scan_semantic_lidar(scene, sensor, _lidar(), _s(0.1), _deg(30))
        .value()
        .copy()
    )
    assert_almost_equal(
        turned.horizontal_angle.to(RADIAN), Float32(pi / 6), atol=1e-5
    )
    var az = Float32(-15 * pi / 180)
    _near(turned.detections[0].point, 10, 10 * sin(az) / cos(az), 0, 1e-3)


def test_semantic_lidar_edges() raises:
    var scene = _Planes(False, 0)
    var d = _lidar()
    # 1 point a second is no ray a laser in a 0.1 s tick.
    d.points_per_second = 1
    assert_false(
        Bool(scan_semantic_lidar(scene, _pose(0, 0, 2), d, _s(0.1), _deg(0)))
    )
    d.points_per_second = 40
    var empty = (
        scan_semantic_lidar(scene, _pose(0, 0, 2), d, _s(0.1), _deg(0))
        .value()
        .copy()
    )
    assert_equal(len(empty.detections), 0)
    with assert_raises(contains="tick must be positive"):
        _ = scan_semantic_lidar(scene, _pose(0, 0, 2), d, _s(0), _deg(0))
    d.channels = 0
    with assert_raises(contains="at least one channel"):
        _ = scan_semantic_lidar(scene, _pose(0, 0, 2), d, _s(0.1), _deg(0))
    # A hit at the sensor itself has no way back.
    var at = SensorHit(
        True,
        _m(0),
        Vector3(1, 2, 3),
        Vector3(0, 0, 1),
        ActorId(3),
        CAR,
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
    )
    var detection = semantic_detection(_pose(1, 2, 3), at)
    assert_equal(detection.cos_inc_angle, 0)
    assert_equal(Int(detection.object_idx), 3)
    assert_equal(round_half_from_zero(2.5), 3)
    assert_equal(round_half_from_zero(-2.5), -3)
    assert_equal(round_half_from_zero(-2.4), -2)


def test_ray_cast_lidar_drops_as_carla_does() raises:
    var scene = _Planes(True, 10)
    var d = _lidar()
    d.atmosphere_attenuation = InverseLength(0.1, PER_METER)
    d.dropoff_intensity_limit = 0.5
    d.dropoff_zero_intensity = 1.0
    d.noise_stddev = _m(0.1)
    var rng = SensorRandom(19)
    var out = (
        scan_ray_cast_lidar(scene, _pose(0, 0, 2), d, _s(0.1), _deg(0), rng)
        .value()
        .copy()
    )
    # Seed 19 keeps rays 1 and 3 before the cast. Ray 1 meets the wall
    # with an intensity of exp(-1) and is dropped after its noise; ray 3
    # meets the road with exp(-0.4), above the limit.
    assert_equal(out.points_per_channel[0], 0)
    assert_equal(out.points_per_channel[1], 1)
    assert_equal(len(out.detections), 1)
    _near(out.detections[0].point, 3.47138405, 0, -2.00420451, 1e-4)
    assert_almost_equal(out.detections[0].intensity, 0.670320034, atol=1e-6)
    # Without drop-off or noise every hit stays, with its intensity.
    var plain = _lidar()
    plain.dropoff_general_rate = 0
    var all = (
        scan_ray_cast_lidar(scene, _pose(0, 0, 2), plain, _s(0.1), _deg(0), rng)
        .value()
        .copy()
    )
    assert_equal(len(all.detections), 4)
    assert_almost_equal(all.detections[1].intensity, 0.960789442, atol=1e-6)
    # Seed 6 keeps rays 1 and 2; ray 1's drawn keep passes.
    var drawn = SensorRandom(6)
    var both = (
        scan_ray_cast_lidar(scene, _pose(0, 0, 2), d, _s(0.1), _deg(0), drawn)
        .value()
        .copy()
    )
    assert_equal(both.points_per_channel[0], 1)
    assert_equal(both.points_per_channel[1], 1)
    _near(both.detections[0].point, 9.96550846, 0, 0, 1e-4)
    _near(both.detections[1].point, 2.52896142, -2.52896142, -2.06488848, 1e-4)
    plain.points_per_second = 1
    assert_false(
        Bool(
            scan_ray_cast_lidar(
                scene, _pose(0, 0, 2), plain, _s(0.1), _deg(0), rng
            )
        )
    )


def test_hss_lidar_fixed_sweep() raises:
    var scene = _Planes(True, 10)
    var d = _lidar()
    d.dropoff_general_rate = 0
    var rng = SensorRandom(0)
    var out = (
        scan_hss_lidar(scene, _pose(0, 0, 2), d, _deg(45), rng).value().copy()
    )
    # 90 / 45 = 2 rays a laser, at -45 and 0 degrees; no turn.
    assert_equal(len(out.detections), 4)
    _near(out.detections[1].point, 10, 0, 0, 1e-4)
    assert_equal(out.horizontal_angle.value, 0)
    # A step is snapped to 0.01 degrees and is 0.01 at least.
    assert_equal(hss_points_per_laser(d, _deg(0.004)), 9000)
    assert_equal(hss_points_per_laser(d, _deg(0.456)), 196)
    d.horizontal_fov = _deg(-10)
    assert_false(Bool(scan_hss_lidar(scene, _pose(0, 0, 2), d, _deg(1), rng)))
    # A limit of zero turns the intensity drop-off into beta alone.
    var zero = _lidar()
    zero.dropoff_general_rate = 0
    zero.dropoff_intensity_limit = 0
    zero.dropoff_zero_intensity = 0
    zero.atmosphere_attenuation = InverseLength(1, PER_METER)
    var kept = (
        scan_hss_lidar(scene, _pose(0, 0, 2), zero, _deg(45), rng)
        .value()
        .copy()
    )
    assert_equal(len(kept.detections), 4)
    zero.channels = 0
    with assert_raises(contains="at least one channel"):
        _ = scan_hss_lidar(scene, _pose(0, 0, 2), zero, _deg(45), rng)
    zero.channels = 1
    zero.range = _m(0)
    with assert_raises(contains="positive range"):
        _ = scan_hss_lidar(scene, _pose(0, 0, 2), zero, _deg(45), rng)


def test_lidar_settings_come_from_the_blueprints() raises:
    var library = default_blueprint_library()
    var semantic = lidar_description_from(
        library.at("sensor.lidar.ray_cast_semantic").description()
    )
    assert_equal(semantic.channels, 64)
    assert_almost_equal(semantic.range.value, 50, atol=1e-6)
    assert_equal(semantic.points_per_second, 600000)
    assert_almost_equal(semantic.rotation_frequency.value, 60, atol=1e-6)
    assert_almost_equal(semantic.lower_fov.to(DEGREE), -30, atol=1e-4)
    # The semantic LiDAR has no drop-off: CARLA's defaults stay.
    assert_almost_equal(semantic.dropoff_general_rate, 0.45, atol=1e-6)
    var hss = library.at("sensor.lidar.hss_lidar").description()
    assert_almost_equal(hss_resolution_from(hss).to(DEGREE), 0.1, atol=1e-5)
    assert_almost_equal(
        lidar_description_from(hss).horizontal_fov.to(DEGREE), 120, atol=1e-4
    )
    # Without the range the default is 10 m, as `SetLidar` has it.
    var bare = lidar_description_from(List[ActorAttributeValue]())
    assert_almost_equal(bare.range.value, 10, atol=1e-6)
    assert_almost_equal(
        hss_resolution_from(List[ActorAttributeValue]()).to(DEGREE),
        0.1,
        atol=1e-5,
    )


# --- radar, IMU and GNSS -------------------------------------------------------------


def test_radar_matches_carlas_rays() raises:
    var scene = _Planes(False, 10)
    scene.wall_velocity = Vector3(5, 0, 0)
    var d = RadarDescription()
    d.points_per_second = 4
    d.noise_seed = 3
    # From the origin to x = 1 in 0.5 s: the radar moves at 2 m/s, the
    # wall at 5 m/s.
    var radar = Radar(d, Vector3(0, 0, 0))
    var out = radar.measure(scene, _pose(1, 0, 0), _s(0.5))
    assert_equal(len(out), 2)
    assert_almost_equal(out[0].velocity, 3, atol=1e-5)
    assert_almost_equal(out[0].azimuth.to(RADIAN), -5.78599327e-07, atol=1e-7)
    assert_almost_equal(out[0].altitude.to(RADIAN), 1.80594434e-05, atol=1e-7)
    assert_almost_equal(out[0].depth.value, 9, atol=1e-4)
    assert_almost_equal(out[1].velocity, 2.93270779, atol=1e-5)
    assert_almost_equal(out[1].azimuth.to(RADIAN), -0.0976990536, atol=1e-6)
    assert_almost_equal(out[1].altitude.to(RADIAN), -0.188676015, atol=1e-6)
    assert_almost_equal(out[1].depth.value, 9.20650864, atol=1e-4)
    assert_true(out[0] == out[0])
    assert_false(out[0] == out[1])
    assert_true(String(out[0]).startswith("RadarDetection(velocity="))
    # Too short a tick for a ray.
    radar.description.points_per_second = 1
    assert_equal(len(radar.measure(scene, _pose(1, 0, 0), _s(0.5))), 0)
    radar.description.points_per_second = 4
    # Nothing ahead gives no detection; a zero tick or range is refused.
    var none = _Planes(False, 0)
    assert_equal(len(radar.measure(none, _pose(1, 0, 0), _s(0.5))), 0)
    with assert_raises(contains="tick must be positive"):
        _ = radar.measure(none, _pose(1, 0, 0), _s(0))
    radar.description.range = _m(0)
    with assert_raises(contains="positive range"):
        _ = radar.measure(none, _pose(1, 0, 0), _s(0.5))


def test_radar_ray_at_its_own_origin() raises:
    # A wall through the radar: the hit is where the radar stands.
    var scene = _Planes(False, 1)
    var d = RadarDescription()
    d.points_per_second = 2
    var radar = Radar(d, Vector3(1, 0, 0))
    var out = radar.measure(scene, _pose(1, 0, 0), _s(0.5))
    assert_equal(len(out), 1)
    assert_equal(out[0].velocity, 0)


def test_radar_settings() raises:
    var library = default_blueprint_library()
    var d = RadarDescription.from_attributes(
        library.at("sensor.other.radar").description()
    )
    assert_almost_equal(d.horizontal_fov.to(DEGREE), 30, atol=1e-4)
    assert_almost_equal(d.vertical_fov.to(DEGREE), 30, atol=1e-4)
    assert_almost_equal(d.range.value, 100, atol=1e-5)
    assert_equal(d.points_per_second, 1500)
    assert_equal(d.noise_seed, 0)
    assert_equal(d.points_in(_s(0.05)), 75)


def test_accelerometer_is_the_parabolas_curvature() raises:
    var a = Accelerometer()
    var g = Acceleration(9.81)
    var none = _rot(0, 0, 0)
    # The first reading: two zero locations and the largest step, so
    # only gravity is left.
    _near(a.step(Vector3(1, 2, 3), _s(0.1), g, none), 0, 0, 9.81, 1e-5)
    # Through 0, 1 and 1.1 m 0.1 s apart: (1.1 - 2 + 0) / 0.01 = -90.
    _near(
        a.step(Vector3(1.1, 2, 3), _s(0.1), g, none), -90, -200, -290.19, 1e-2
    )
    # A steady speed has no acceleration.
    _near(a.step(Vector3(1.2, 2, 3), _s(0.1), g, none), 0, 0, 9.81, 1e-2)
    # Turned by 90 degrees of yaw, the world's x is the sensor's -y.
    _near(
        a.step(Vector3(1.4, 2, 3), _s(0.1), g, _rot(0, 90, 0)),
        0,
        -10,
        9.81,
        1e-2,
    )
    assert_equal(FLOAT_MAX, 3.4028234663852886e38)


def test_compass_turns_from_north() raises:
    assert_equal(compass(Vector3(0, -1, 0)).value, 0)
    assert_almost_equal(compass(Vector3(1, 0, 0)).value, pi / 2, atol=1e-6)
    assert_almost_equal(compass(Vector3(0, 1, 0)).value, pi, atol=1e-6)
    assert_almost_equal(compass(Vector3(-1, 0, 0)).value, 3 * pi / 2, atol=1e-5)
    assert_almost_equal(compass(Vector3(0, 0, 1)).value, pi / 2, atol=1e-6)


def test_imu_noise_and_gyroscope() raises:
    var d = IMUDescription()
    d.noise_seed = 11
    d.accelerometer_stddev = Vector3(0.1, 0.2, 0.3)
    d.gyroscope_stddev = Vector3(0.01, 0.02, 0.03)
    d.gyroscope_bias = Vector3(1, 2, 3)
    var imu = IMU(d)
    # The parent spins about the world's x at 1 rad/s with a yaw of 90,
    # which is its own -y; the sensor sits turned by -90 of yaw, where
    # that is -x.
    var m = imu.measure(
        Vector3(0, 0, 0),
        _rot(0, 0, 0),
        _rot(0, -90, 0),
        Vector3(1, 0, 0),
        _rot(0, 90, 0),
        _s(0.1),
        Acceleration(9.81),
    )
    _near(
        m.accelerometer,
        0.121453583,
        -0.135959923,
        9.81 - 0.337073445,
        1e-5,
    )
    _near(
        m.gyroscope,
        -1 + 1 + 0.00833075121,
        2 + 0.046344351,
        3 + 0.0146250399,
        1e-5,
    )
    assert_almost_equal(m.compass.value, 0.5 * pi, atol=1e-6)
    assert_true(String(m).startswith("IMUMeasurement(accelerometer="))
    var library = default_blueprint_library()
    var plain = IMUDescription.from_attributes(
        library.at("sensor.other.imu").description()
    )
    assert_equal(plain.noise_seed, 0)
    assert_equal(plain.gyroscope_bias.z, 0)


def test_gnss_adds_bias_and_noise() raises:
    var d = GnssDescription()
    d.noise_seed = 5
    d.latitude_stddev = 0.5
    d.longitude_stddev = 0.25
    d.altitude_stddev = 2
    d.latitude_bias = 1
    d.longitude_bias = 2
    d.altitude_bias = 3
    var gnss = Gnss(d)
    # The default projection puts the origin at latitude and longitude 0.
    var at = gnss.measure(Vector3(0, 0, 5), GeoProjection())
    assert_almost_equal(at.latitude_degrees, 1 - 0.00847983174, atol=1e-6)
    assert_almost_equal(at.longitude_degrees, 2 + 0.0457753986, atol=1e-6)
    assert_almost_equal(at.altitude_meters, 8 + 2.27591276, atol=1e-5)
    var library = default_blueprint_library()
    var plain = GnssDescription.from_attributes(
        library.at("sensor.other.gnss").description()
    )
    assert_equal(plain.latitude_bias, 0)
    var clean = Gnss(plain)
    var zero = clean.measure(Vector3(0, 0, 0), GeoProjection())
    assert_equal(zero.latitude_degrees, 0)
    var bad = GeoProjection()
    bad.projection_type.value = 9
    with assert_raises():
        _ = clean.measure(Vector3(0, 0, 0), bad)


# --- lenses and cameras ------------------------------------------------------------


def test_camera_models() raises:
    assert_equal(camera_model_of("perspective"), PERSPECTIVE)
    assert_equal(camera_model_of("stereographic"), STEREOGRAPHIC)
    assert_equal(camera_model_of("equidistant"), EQUIDISTANT)
    assert_equal(camera_model_of("equisolid"), EQUISOLID)
    assert_equal(camera_model_of("orthographic"), ORTHOGRAPHIC)
    assert_equal(camera_model_of("kannala-brandt"), KANNALA_BRANDT)
    assert_equal(camera_model_of("fisheye"), PERSPECTIVE)
    assert_true(KANNALA_BRANDT.is_valid())
    assert_false(CameraModel(6).is_valid())
    assert_false(CameraModel(-1).is_valid())
    var none = List[Float32]()
    assert_almost_equal(
        compute_angle(PERSPECTIVE, 1, none).value, pi / 4, atol=1e-6
    )
    assert_almost_equal(
        compute_angle(STEREOGRAPHIC, 2, none).value, pi / 2, atol=1e-6
    )
    assert_almost_equal(
        compute_angle(EQUIDISTANT, 0.3, none).value, 0.3, atol=1e-7
    )
    assert_almost_equal(
        compute_angle(EQUISOLID, 1, none).value, pi / 3, atol=1e-6
    )
    assert_almost_equal(compute_angle(EQUISOLID, 4, none).value, pi, atol=1e-6)
    assert_almost_equal(
        compute_angle(EQUISOLID, -4, none).value, -pi, atol=1e-6
    )
    assert_almost_equal(
        compute_angle(ORTHOGRAPHIC, 0.5, none).value, pi / 6, atol=1e-6
    )
    assert_almost_equal(
        compute_angle(ORTHOGRAPHIC, -3, none).value, -pi / 2, atol=1e-6
    )
    # theta + 0.1 theta^3 = 1.1 at theta = 1.
    var k: List[Float32] = [0.1]
    assert_almost_equal(
        compute_angle(KANNALA_BRANDT, 1.1, k).value, 1, atol=1e-5
    )
    with assert_raises(contains="six models"):
        _ = compute_angle(CameraModel(7), 1, none)
    # 90 degrees on 600 rows: half the height over the model's distance
    # of 45 degrees.
    assert_almost_equal(
        compute_distance(PERSPECTIVE, _deg(90), 600, none), 300, atol=1e-3
    )
    assert_almost_equal(
        compute_distance(STEREOGRAPHIC, _deg(90), 600, none),
        362.13203,
        atol=1e-2,
    )
    assert_almost_equal(
        compute_distance(EQUIDISTANT, _deg(90), 600, none), 381.97186, atol=1e-2
    )
    assert_almost_equal(
        compute_distance(EQUISOLID, _deg(90), 600, none), 391.96927, atol=1e-2
    )
    assert_almost_equal(
        compute_distance(ORTHOGRAPHIC, _deg(90), 600, none),
        424.26407,
        atol=1e-2,
    )
    assert_almost_equal(
        compute_distance(KANNALA_BRANDT, _deg(90), 600, k), 359.77838, atol=1e-2
    )
    with assert_raises(contains="six models"):
        _ = compute_distance(CameraModel(7), _deg(90), 600, none)
    # Without coefficients the Kannala-Brandt angle is the distance.
    assert_almost_equal(
        compute_angle(KANNALA_BRANDT, 0.7, none).value, 0.7, atol=1e-6
    )
    assert_equal(kannala_brandt_derivative(0.3, none), 1)
    var two: List[Float32] = [0.1, 0.2]
    assert_almost_equal(kannala_brandt_polynomial(0.5, two), 0.51875, atol=1e-6)
    assert_almost_equal(kannala_brandt_derivative(0.5, two), 1.1375, atol=1e-6)


def test_wide_angle_lens_rays() raises:
    # 4 by 2 pixels and 90 degrees: the perspective focal length is 1.
    var lens = WideAngleLens(PERSPECTIVE, List[Float32](), 4, 2, _deg(90))
    assert_almost_equal(lens.focal_length, 1, atol=1e-6)
    _near(lens.pixel_ray(2, 1).direction, 1, 0, 0)
    var r = Float32(sqrt(0.5))
    _near(lens.pixel_ray(3, 1).direction, r, r, 0)
    _near(lens.pixel_ray(2, 2).direction, r, 0, -r)
    # The perspective switch: the pinhole view of the same field.
    var flat = WideAngleLens(EQUIDISTANT, List[Float32](), 4, 2, _deg(90))
    flat.perspective = True
    var third = Float32(1 / sqrt(3.0))
    _near(flat.pixel_ray(3, 2).direction, third, third, -third)
    # The equirectangular switch: the center looks forward, and the
    # offset turns it toward right.
    var sphere = WideAngleLens(PERSPECTIVE, List[Float32](), 4, 2, _deg(90))
    sphere.equirectangular = True
    _near(sphere.pixel_ray(2, 1).direction, 1, 0, 0)
    _near(sphere.pixel_ray(0, 0).direction, 0, 0, 1)
    sphere.longitude_offset = _deg(90)
    _near(sphere.pixel_ray(2, 1).direction, 0, 1, 0)
    # The mask: an equidistant 90 degrees ends at 45 degrees from forward.
    var masked = WideAngleLens(EQUIDISTANT, List[Float32](), 4, 2, _deg(90))
    masked.fov_mask = True
    assert_equal(masked.pixel_ray(2 + 1.5, 1).weight, 0)
    assert_equal(masked.pixel_ray(2, 1).weight, 1)
    masked.fov_fade_size = 10
    # 40 degrees from forward is 5 into the 10-degree fade.
    var u = Float32(40 * pi / 180) * masked.focal_length
    assert_almost_equal(masked.pixel_ray(2 + u, 1).weight, 0.5, atol=1e-4)
    with assert_raises(contains="positive size"):
        _ = WideAngleLens(PERSPECTIVE, List[Float32](), 0, 2, _deg(90))
    with assert_raises(contains="positive size"):
        _ = WideAngleLens(PERSPECTIVE, List[Float32](), 4, 0, _deg(90))


def test_wide_angle_lens_from_attributes() raises:
    var library = default_blueprint_library()
    var plain = WideAngleLens.from_attributes(
        library.at("sensor.camera.rgb_fisheye").description()
    )
    assert_equal(plain.model, PERSPECTIVE)
    assert_equal(plain.width, 800)
    assert_almost_equal(plain.focal_length, 300, atol=1e-3)
    assert_false(plain.fov_mask)
    var a = library.at("sensor.camera.depth_fisheye").description()
    for i in range(len(a)):
        if a[i].id == "camera_model":
            a[i].value = "kannala-brandt"
        elif a[i].id == "fov":
            a[i].value = "0"
        elif a[i].id == "equirectangular" or a[i].id == "fov_mask":
            a[i].value = "true"
        elif a[i].id == "longitude_offset":
            a[i].value = "30"
        elif a[i].id == "fov_fade_size":
            a[i].value = "5"
    var kb = WideAngleLens.from_attributes(a)
    assert_equal(kb.model, KANNALA_BRANDT)
    assert_equal(len(kb.coefficients), 4)
    assert_almost_equal(kb.coefficients[0], 0.083092, atol=1e-6)
    # A fov of zero keeps 90 degrees.
    assert_almost_equal(kb.fov.to(DEGREE), 90, atol=1e-4)
    assert_almost_equal(kb.longitude_offset.to(DEGREE), 30, atol=1e-4)
    assert_equal(kb.fov_fade_size, 5)
    for i in range(len(a)):
        if a[i].id == "focal_length":
            a[i].value = "250"
    assert_equal(WideAngleLens.from_attributes(a).focal_length, 250)


def _geometry() raises -> CameraGeometry:
    # 2 by 2 pixels at 90 degrees: a focal length of one pixel.
    return CameraGeometry.pinhole(CameraIntrinsics(2, 2, _deg(90)))


def test_ground_truth_images() raises:
    var scene = _Planes(False, 10)
    var cam = _pose(0, 0, 0)
    var depth = render_camera(scene, DEPTH_IMAGE, cam, _geometry())
    # Planar depth 10 m: code round(0.01 (2^24 - 1)) = 167772.
    var p = depth.get_pixel(0, 0)
    assert_equal(Int(p.r), 92)
    assert_equal(Int(p.g), 143)
    assert_equal(Int(p.b), 2)
    assert_almost_equal(
        decode_depth(depth.get_pixel(1, 1)).value, 10, atol=1e-3
    )
    var semantic = render_camera(scene, SEMANTIC_IMAGE, cam, _geometry())
    assert_equal(Int(semantic.get_pixel(1, 0).r), BUILDING.value)
    assert_equal(Int(semantic.get_pixel(1, 0).g), 0)
    var instance = render_camera(scene, INSTANCE_IMAGE, cam, _geometry())
    assert_equal(Int(instance.get_pixel(0, 1).r), BUILDING.value)
    assert_equal(Int(instance.get_pixel(0, 1).g), 7)
    assert_equal(Int(instance.get_pixel(0, 1).b), 0)
    # The wall faces the camera: (0, 0, 1) in the view frame.
    var normals = render_camera(scene, NORMALS_IMAGE, cam, _geometry())
    assert_equal(Int(normals.get_pixel(0, 0).r), 128)
    assert_equal(Int(normals.get_pixel(0, 0).g), 128)
    assert_equal(Int(normals.get_pixel(0, 0).b), 255)
    # 70 gray at a cosine of 1 / sqrt(1.5): 70 (0.2 + 0.8 0.8165) = 59.7,
    # rounded to 60.
    var shaded = render_camera(scene, SHADED_IMAGE, cam, _geometry())
    assert_equal(Int(shaded.get_pixel(0, 0).r), 60)
    with assert_raises(contains="five images"):
        _ = render_camera(scene, CameraKind(5), cam, _geometry())


def test_images_of_nothing() raises:
    var scene = _Planes(False, 0)
    var cam = _pose(0, 0, 0)
    var depth = render_camera(scene, DEPTH_IMAGE, cam, _geometry())
    assert_equal(Int(depth.get_pixel(0, 0).b), 255)
    var semantic = render_camera(scene, SEMANTIC_IMAGE, cam, _geometry())
    assert_equal(Int(semantic.get_pixel(0, 0).r), SKY.value)
    var instance = render_camera(scene, INSTANCE_IMAGE, cam, _geometry())
    assert_equal(Int(instance.get_pixel(0, 0).r), SKY.value)
    assert_equal(Int(instance.get_pixel(0, 0).g), 0)
    var normals = render_camera(scene, NORMALS_IMAGE, cam, _geometry())
    assert_equal(Int(normals.get_pixel(0, 0).b), 128)
    var shaded = render_camera(scene, SHADED_IMAGE, cam, _geometry())
    assert_equal(Int(shaded.get_pixel(0, 0).b), 180)
    var n = encode_normal(Vector3(1, -1, 0))
    assert_equal(Int(n.r), 255)
    assert_equal(Int(n.g), 0)
    assert_equal(Int(n.b), 128)


def test_lens_camera_masks_and_fades() raises:
    var lens = WideAngleLens(EQUIDISTANT, List[Float32](), 4, 2, _deg(90))
    lens.fov_mask = True
    lens.fov_fade_size = 20
    var geometry = CameraGeometry.wide_angle(lens^)
    var scene = _Planes(False, 10)
    var image = render_camera(scene, SEMANTIC_IMAGE, _pose(0, 0, 0), geometry)
    # Column 3 is 1.5 focal lengths out, past the 45-degree edge: black.
    assert_equal(Int(image.get_pixel(3, 1).r), 0)
    # Column 2's center is 0.5 / 1.2732 focal lengths across and down,
    # 31.82 degrees out: 13.18 of the 20-degree fade is left, so the tag
    # 3 is scaled by 0.659, to 2.
    assert_equal(Int(image.get_pixel(2, 1).r), 2)


def test_optical_flow_moves_with_the_point() raises:
    var scene = _Planes(False, 10)
    scene.wall_velocity = Vector3(0, 1, 0)
    var k = CameraIntrinsics(2, 2, _deg(90))
    var cam = _pose(0, 0, 0)
    var flow = optical_flow(scene, cam, cam, k, _s(0.5))
    assert_equal(len(flow), 8)
    # Pixel (1, 1) sees (10, 5, -5); 0.5 s ago it was at y = 4.5, column
    # 1.45: a move of 0.05 of a pixel, 0.05 in normalized units.
    assert_almost_equal(flow[6], 0.05, atol=1e-5)
    assert_almost_equal(flow[7], 0, atol=1e-6)
    # Behind the last frame's camera, or a miss, has no move.
    var behind = optical_flow(scene, cam, _pose(0, 0, 0, 180), k, _s(0.5))
    assert_equal(behind[6], 0)
    var nothing = _Planes(False, 0)
    assert_equal(optical_flow(nothing, cam, cam, k, _s(0.5))[0], 0)


def test_mesh_rays_meet_a_scene() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(cube(_m(2)))
    var material = assets.materials.add(Material(Color(200, 200, 200)))
    var scene = Scene()
    var node = Object3D()
    var at = carla_to_three(Vector3(10, 0, 1))
    node.set_position(at.x, at.y, at.z)
    var id = scene.add(node^)
    scene.add_mesh(Mesh(geometry, material, id))
    var far_node = Object3D()
    var behind = carla_to_three(Vector3(20, 0, 1))
    far_node.set_position(behind.x, behind.y, behind.z)
    var far_id = scene.add(far_node^)
    scene.add_mesh(Mesh(geometry, material, far_id))
    scene.update()
    var rays = MeshRays(
        Pointer(to=scene),
        Pointer(to=assets),
        [ActorId(4), ActorId(5)],
        [CAR, BUILDING],
        [Vector3(1, 0, 0), Vector3(0, 0, 0)],
    )
    # The nearer cube's face is at x = 9, facing back.
    var hit = rays.cast_ray(Vector3(0, 0, 1), Vector3(2, 0, 0), _m(100))
    assert_true(hit.hit)
    assert_almost_equal(hit.distance.value, 9, atol=1e-4)
    _near(hit.point, 9, 0, 1, 1e-4)
    _near(hit.normal, -1, 0, 0, 1e-5)
    assert_equal(hit.actor, ActorId(4))
    assert_equal(hit.tag, CAR)
    _near(hit.actor_velocity, 1, 0, 0)
    # From past both, looking back: the second cube is nearer.
    var far_back = rays.cast_ray(Vector3(30, 0, 1), Vector3(-1, 0, 0), _m(100))
    assert_equal(far_back.actor, ActorId(5))
    assert_almost_equal(far_back.distance.value, 9, atol=1e-4)
    # From between them looking back, only the first cube is behind.
    var back = rays.cast_ray(Vector3(15, 0, 1), Vector3(-1, 0, 0), _m(100))
    assert_equal(back.actor, ActorId(4))
    var up = rays.cast_ray(Vector3(0, 0, 1), Vector3(0, 0, 1), _m(100))
    assert_false(up.hit)
    with assert_raises(contains="needs a direction"):
        _ = rays.cast_ray(Vector3(0, 0, 1), Vector3(0, 0, 0), _m(100))
    var empty = Scene()
    empty.update()
    var none = MeshRays(
        Pointer(to=empty),
        Pointer(to=assets),
        List[ActorId](),
        List[SemanticTag](),
        List[Vector3](),
    )
    assert_false(none.cast_ray(Vector3(0, 0, 1), Vector3(1, 0, 0), _m(100)).hit)
    with assert_raises(contains="one actor, tag and velocity"):
        _ = MeshRays(
            Pointer(to=scene),
            Pointer(to=assets),
            List[ActorId](),
            [CAR, BUILDING],
            [Vector3(1, 0, 0), Vector3(0, 0, 0)],
        )

    with assert_raises(contains="one actor, tag and velocity"):
        _ = MeshRays(
            Pointer(to=scene),
            Pointer(to=assets),
            [ActorId(1), ActorId(2)],
            List[SemanticTag](),
            [Vector3(1, 0, 0), Vector3(0, 0, 0)],
        )
    with assert_raises(contains="one actor, tag and velocity"):
        _ = MeshRays(
            Pointer(to=scene),
            Pointer(to=assets),
            [ActorId(1), ActorId(2)],
            [CAR, BUILDING],
            List[Vector3](),
        )


# --- the event camera ----------------------------------------------------------------


def _frame(values: List[Int]) raises -> Framebuffer:
    var out = Framebuffer(len(values), 1, Color(0, 0, 0))
    for i in range(len(values)):
        var v = UInt8(values[i])
        out.set_pixel(i, 0, Color(v, v, v))
    return out^


def _linear(threshold: Float32) -> DVSConfig:
    var c = DVSConfig()
    c.use_log = False
    c.positive_threshold = threshold
    c.negative_threshold = threshold
    return c


def test_event_camera_crossings() raises:
    # Without the log, a gray of 100 reads 99.99 and 200 reads 199.98.
    assert_almost_equal(gray(Color(100, 100, 100)), 99.99, atol=1e-4)
    assert_almost_equal(gray(Color(255, 0, 0)), 76.2195, atol=1e-4)
    var dvs = DVSCamera(_linear(30), 1, 1, 0)
    assert_equal(len(dvs.simulate(_frame([100]), Duration64(1.0))), 0)
    # Crossings at 129.99, 159.99 and 189.99 of the rise to 199.98, at
    # 30, 60 and 90 hundredths-of-99.99 of the 0.1 s tick.
    var up = dvs.simulate(_frame([200]), Duration64(1.1))
    assert_equal(len(up), 3)
    assert_true(up[0].pol)
    assert_equal(up[0].x, 0)
    assert_almost_equal(Float64(up[0].t), 1030003000.3, atol=8)
    assert_almost_equal(Float64(up[1].t), 1060006000.6, atol=8)
    assert_almost_equal(Float64(up[2].t), 1090009000.9, atol=8)
    # Down to 109.989 from the last crossing, 189.99: 159.99 and 129.99.
    var down = dvs.simulate(_frame([110]), Duration64(1.2))
    assert_equal(len(down), 2)
    assert_false(down[0].pol)
    # No change, no events.
    assert_equal(len(dvs.simulate(_frame([110]), Duration64(1.3))), 0)
    assert_true(String(up[0]).startswith("Event(x=0, y=0, t="))


def test_event_camera_refractory_period() raises:
    var config = _linear(30)
    config.refractory_period_ns = 40000000
    var dvs = DVSCamera(config, 1, 1, 0)
    _ = dvs.simulate(_frame([100]), Duration64(1.0))
    # The second crossing comes 30 ms after the first and is dropped;
    # the third, 60 ms after, is kept.
    var up = dvs.simulate(_frame([200]), Duration64(1.1))
    assert_equal(len(up), 2)
    assert_almost_equal(Float64(up[1].t), 1090009000.9, atol=8)


def test_event_camera_time_going_back() raises:
    # A frame from before the last event: its crossings fall before that
    # event and give none, though the reference still moves.
    var dvs = DVSCamera(_linear(30), 1, 1, 0)
    _ = dvs.simulate(_frame([100]), Duration64(1.0))
    assert_equal(len(dvs.simulate(_frame([200]), Duration64(1.1))), 3)
    assert_equal(len(dvs.simulate(_frame([110]), Duration64(0.5))), 0)


def test_event_camera_sorts_by_time() raises:
    var dvs = DVSCamera(_linear(90), 2, 1, 0)
    _ = dvs.simulate(_frame([100, 100]), Duration64(1.0))
    # Pixel 0 crosses 189.99 at 0.9 of its rise; pixel 1 at 0.6 of its
    # rise to 249.975, so it comes first.
    var events = dvs.simulate(_frame([200, 250]), Duration64(1.1))
    assert_equal(len(events), 2)
    assert_equal(events[0].x, 1)
    assert_equal(events[1].x, 0)
    assert_true(events[0].t < events[1].t)


def test_event_camera_log_and_noise() raises:
    var config = DVSConfig()
    var dvs = DVSCamera(config, 1, 1, 0)
    _ = dvs.simulate(_frame([100]), Duration64(0.0))
    # log(0.001 + 99.99 / 255) = -0.93365 up to log(0.001 + 199.98 / 255)
    # = -0.24176: crossings at -0.63365 and -0.33365.
    assert_equal(len(dvs.simulate(_frame([200]), Duration64(0.1))), 2)
    var noisy = config
    noisy.sigma_positive_threshold = 1e-6
    noisy.sigma_negative_threshold = 1e-6
    var jitter = DVSCamera(noisy, 1, 1, 1)
    _ = jitter.simulate(_frame([100]), Duration64(0.0))
    assert_equal(len(jitter.simulate(_frame([200]), Duration64(0.1))), 2)
    # Down to log(0.001 + 109.989 / 255) = -0.83857: one crossing.
    assert_equal(len(jitter.simulate(_frame([110]), Duration64(0.2))), 1)


def test_event_camera_settings() raises:
    var library = default_blueprint_library()
    var c = DVSConfig.from_attributes(
        library.at("sensor.camera.dvs").description()
    )
    assert_almost_equal(c.positive_threshold, 0.3, atol=1e-7)
    assert_almost_equal(c.log_eps, 0.001, atol=1e-9)
    assert_true(c.use_log)
    # Without the thresholds, CARLA's fallback of 0.5.
    var bare = DVSConfig.from_attributes(List[ActorAttributeValue]())
    assert_almost_equal(bare.negative_threshold, 0.5, atol=1e-7)
    with assert_raises(contains="positive size"):
        _ = DVSCamera(c, 0, 1, 0)
    with assert_raises(contains="positive size"):
        _ = DVSCamera(c, 1, 0, 0)
    var zero = c
    zero.negative_threshold = 0
    with assert_raises(contains="thresholds must be positive"):
        _ = DVSCamera(zero, 1, 1, 0)
    var dvs = DVSCamera(c, 2, 1, 0)
    with assert_raises(contains="must be its size"):
        _ = dvs.simulate(_frame([1]), Duration64(0))
    with assert_raises(contains="must be its size"):
        _ = dvs.simulate(Framebuffer(2, 2, Color(0, 0, 0)), Duration64(0))


def test_event_camera_time_keeps_float64_and_is_checked() raises:
    # A microsecond tick a million seconds in keeps its Float64 digits.
    var dvs = DVSCamera(_linear(30), 1, 1, 0)
    _ = dvs.simulate(_frame([100]), Duration64(1.0e6))
    var up = dvs.simulate(_frame([200]), Duration64(1.0e6 + 1.0e-6))
    assert_equal(len(up), 3)
    assert_equal(up[0].t, 1000000000000000 + 300)
    assert_equal(up[2].t, 1000000000000000 + 900)
    # Nonfinite, negative and too-large times are refused before use.
    for bad in [inf[DType.float64](), nan[DType.float64](), -1.0, 9.3e9]:
        with assert_raises(contains="time must be finite"):
            _ = dvs.simulate(_frame([100]), Duration64(bad))
    _ = dvs.simulate(_frame([100]), Duration64(9.2e9))


# --- V2X ---------------------------------------------------------------------------


def test_v2x_kinds_are_checked() raises:
    assert_true(NLOS_VEHICLE.is_valid())
    assert_false(PathState(3).is_valid())
    assert_false(PathState(-1).is_valid())
    assert_true(GEOMETRIC.is_valid())
    assert_false(PathLossKind(2).is_valid())
    assert_true(URBAN.is_valid())
    assert_false(Scenario(3).is_valid())
    assert_false(Scenario(-1).is_valid())
    assert_true(STATION_ROAD_SIDE_UNIT.is_valid())
    assert_true(STATION_TRAM.is_valid())
    assert_false(StationType(12).is_valid())
    assert_false(StationType(16).is_valid())
    assert_false(StationType(-1).is_valid())
    assert_true(MessageId(7).is_valid())
    assert_false(MessageId(8).is_valid())
    assert_false(MessageId(-1).is_valid())
    assert_true(VehicleRole(15).is_valid())
    assert_false(VehicleRole(16).is_valid())
    assert_false(VehicleRole(-1).is_valid())
    assert_true(ContainerKind(2).is_valid())
    assert_false(ContainerKind(3).is_valid())
    assert_false(ContainerKind(-1).is_valid())


def test_propagation_settings() raises:
    var library = default_blueprint_library()
    var a = library.at("sensor.other.v2x").description()
    var p = PropagationParams.from_attributes(a)
    # The scenario and the model start at their first recommended values.
    assert_equal(p.scenario, HIGHWAY)
    assert_equal(p.model, WINNER)
    assert_equal(p.transmit_power, 21.5)
    assert_equal(p.receiver_sensitivity, -99)
    assert_almost_equal(p.frequency_ghz, 5.9, atol=1e-6)
    assert_equal(p.combined_antenna_gain, 10)
    assert_almost_equal(p.path_loss_exponent, 2.7, atol=1e-6)
    assert_equal(p.reference_distance.value, 1)
    assert_equal(p.filter_distance.value, 500)
    assert_true(p.use_etsi_fading)
    for i in range(len(a)):
        if a[i].id == "scenario":
            a[i].value = "rural"
        elif a[i].id == "path_loss_model":
            a[i].value = "geometric"
    p = PropagationParams.from_attributes(a)
    assert_equal(p.scenario, RURAL)
    assert_equal(p.model, GEOMETRIC)
    for i in range(len(a)):
        if a[i].id == "scenario":
            a[i].value = "urban"
        elif a[i].id == "path_loss_model":
            a[i].value = "other"
    p = PropagationParams.from_attributes(a)
    assert_equal(p.scenario, URBAN)
    assert_equal(p.model, GEOMETRIC)
    var bad = PropagationParams()
    bad.scenario = Scenario(4)
    with assert_raises(contains="must be valid"):
        _ = PathLossModel(bad)
    bad = PropagationParams()
    bad.model = PathLossKind(4)
    with assert_raises(contains="must be valid"):
        _ = PathLossModel(bad)
    bad = PropagationParams()
    bad.frequency_ghz = 0
    with assert_raises(contains="must be positive"):
        _ = PathLossModel(bad)
    bad = PropagationParams()
    bad.reference_distance = _m(0)
    with assert_raises(contains="must be positive"):
        _ = PathLossModel(bad)


def test_path_loss_formulas() raises:
    var model = PathLossModel(PropagationParams())
    assert_almost_equal(model.wavelength, 0.0508122801956209, atol=1e-12)
    assert_almost_equal(model.fspl_d0, 47.86482238769531, atol=1e-4)
    assert_almost_equal(
        model.winner(NLOS_BUILDING, 100), 111.41909790039062, atol=1e-4
    )
    assert_almost_equal(model.winner(LOS, 100), 86.19950866699219, atol=1e-4)
    model.params.scenario = RURAL
    assert_almost_equal(
        model.winner(NLOS_VEHICLE, 100), 86.19950866699219, atol=1e-4
    )
    model.params.scenario = HIGHWAY
    assert_almost_equal(model.winner(LOS, 100), 87.8170394897461, atol=1e-4)
    with assert_raises(contains="LOS, NLOSb or NLOSv"):
        _ = model.winner(PathState(5), 100)
    assert_almost_equal(
        model.two_ray(20, 1.5, 1.5), 72.78307333462539, atol=1e-9
    )
    assert_almost_equal(model.two_ray(20, 2, 1), 75.13185685336987, atol=1e-9)
    assert_almost_equal(
        model.two_ray_simple(1000, 2, 1), 113.97940063476562, atol=1e-4
    )
    assert_almost_equal(
        model.vehicle_loss(10, 10, 1), 21.848760113014812, atol=1e-9
    )
    assert_equal(model.vehicle_loss(10, 10, -1), 0)
    assert_almost_equal(
        model.vehicle_loss(10, 10, -0.01), 5.790726349100767, atol=1e-9
    )
    var obstacles: List[Vector3] = [Vector3(5, 0, 0.5), Vector3(10, 0, 1.0)]
    assert_almost_equal(
        model.nlos_vehicle_loss(Vector3(0, 0, 0), Vector3(20, 0, 0), obstacles),
        21.848760113014812,
        atol=1e-5,
    )
    assert_equal(
        model.nlos_vehicle_loss(
            Vector3(0, 0, 0), Vector3(20, 0, 0), List[Vector3]()
        ),
        0,
    )
    # The largest loss wins in any order.
    var reversed: List[Vector3] = [Vector3(10, 0, 1.0), Vector3(5, 0, 0.5)]
    assert_almost_equal(
        model.nlos_vehicle_loss(Vector3(0, 0, 0), Vector3(20, 0, 0), reversed),
        21.848760113014812,
        atol=1e-5,
    )


def test_shadow_fading_follows_etsi() raises:
    var model = PathLossModel(PropagationParams())
    var expected: List[Float32] = [
        3.3,
        4.25,
        5.2,
        6.8,
        6.8,
        6.8,
        3.8,
        4.55,
        5.3,
    ]
    var scenarios = [HIGHWAY, RURAL, URBAN]
    for s in range(3):
        for sc in range(3):
            model.params.scenario = scenarios[sc]
            assert_equal(
                model.fading_stddev(PathState(s)), expected[s * 3 + sc]
            )
    model.params.use_etsi_fading = False
    model.params.custom_fading_stddev = 2.5
    assert_equal(model.fading_stddev(LOS), 2.5)
    with assert_raises(contains="LOS, NLOSb or NLOSv"):
        _ = model.fading_stddev(PathState(3))


def test_link_loss_and_power() raises:
    var model = PathLossModel(PropagationParams())
    var rng = SensorRandom(9)
    var obstacles: List[Vector3] = [Vector3(5, 0, 0.5), Vector3(10, 0, 1.0)]
    var a = Vector3(0, 0, 0)
    var b = Vector3(20, 0, 0)
    # Urban geometric: the two-ray loss, then the log-distance loss, each
    # with a draw of the ETSI fading.
    assert_almost_equal(
        model.loss(LOS, a, b, 20, 1.5, 1.5, obstacles, rng),
        72.78307342529297 - 1.87104273,
        atol=1e-4,
    )
    assert_almost_equal(
        model.loss(NLOS_BUILDING, a, b, 20, 1.5, 1.5, obstacles, rng),
        82.99263000488281 + 6.88598442,
        atol=1e-4,
    )
    model.params.use_etsi_fading = False
    assert_almost_equal(
        model.loss(NLOS_VEHICLE, a, b, 20, 1.5, 1.5, obstacles, rng),
        95.73418426513672,
        atol=1e-4,
    )
    model.params.model = WINNER
    assert_almost_equal(
        model.loss(NLOS_VEHICLE, a, b, 20, 1.5, 1.5, obstacles, rng),
        96.37547302246094,
        atol=1e-4,
    )
    assert_almost_equal(
        model.loss(LOS, a, b, 100, 1.5, 1.5, obstacles, rng),
        86.19950866699219,
        atol=1e-4,
    )
    assert_equal(model.received_power(21.5, 70).value(), -38.5)
    assert_false(Bool(model.received_power(21.5, 200)))


def test_cam_helpers() raises:
    assert_equal(speed_value(200), 16382)
    assert_equal(speed_value(163.82), 16382)
    assert_equal(speed_value(12.5), 1250)
    assert_equal(speed_value(0), 0)
    assert_equal(speed_value(-1), 16383)
    assert_equal(round_half_away(2.5), 3)
    assert_equal(round_half_away(-2.5), -3)
    assert_equal(round_half_away(-2.4), -2)
    assert_equal(station_type_of(CAR, "emergency"), STATION_SPECIAL_VEHICLES)
    assert_equal(station_type_of(PEDESTRIAN, ""), STATION_PEDESTRIAN)
    assert_equal(station_type_of(SemanticTag(19), ""), STATION_CYCLIST)
    assert_equal(station_type_of(SemanticTag(18), ""), STATION_MOTORCYCLE)
    assert_equal(station_type_of(CAR, "taxi"), STATION_PASSENGER_CAR)
    assert_equal(station_type_of(BUS, ""), STATION_BUS)
    assert_equal(station_type_of(SemanticTag(15), ""), STATION_LIGHT_TRUCK)
    assert_equal(station_type_of(SemanticTag(17), ""), STATION_TRAM)
    for t in [3, 4, 5, 6, 7, 8]:
        assert_equal(
            station_type_of(SemanticTag(t), ""), STATION_ROAD_SIDE_UNIT
        )
    assert_equal(station_type_of(UNLABELED, ""), STATION_UNKNOWN)
    assert_equal(station_type_of(ROAD, ""), STATION_UNKNOWN)
    assert_equal(vehicle_role_of(STATION_BUS), ROLE_PUBLIC_TRANSPORT)
    assert_equal(vehicle_role_of(STATION_TRAM), ROLE_PUBLIC_TRANSPORT)
    assert_equal(vehicle_role_of(STATION_SPECIAL_VEHICLES), ROLE_EMERGENCY)
    assert_equal(vehicle_role_of(STATION_PASSENGER_CAR), ROLE_DEFAULT)
    var data = List[UInt8](length=CUSTOM_V2X_MAX_BYTES, fill=7)
    var message = custom_message(12, data)
    assert_equal(message.header.protocol_version, 2)
    assert_equal(message.header.message_id.value, 0)
    assert_equal(message.header.station_id, 12)
    assert_equal(len(message.data), 100)
    data.append(1)
    with assert_raises(contains="100 bytes at most"):
        _ = custom_message(12, data)


# --- the bytes -------------------------------------------------------------------------


def test_header_and_images_bytes() raises:
    assert_equal(
        _hex(
            sensor_header(
                IMU_SENSOR,
                42,
                1.5,
                CarlaTransform(_m(1), _m(2), _m(3), _rot(10, 20, 0)),
            )
        ),
        "05000000000000002a00000000000000000000000000f83f0000803f0000004000004040000020410000a04100000000",
    )
    with assert_raises(contains="place in the registry"):
        _ = sensor_header(SensorType(26), 0, 0, _pose(0, 0, 0))
    assert_false(SensorType(-1).is_valid())
    var image = Framebuffer(2, 1, Color(0, 0, 0))
    image.set_pixel(0, 0, Color(1, 2, 3, 4))
    image.set_pixel(1, 0, Color(5, 6, 7, 8))
    assert_equal(
        _hex(image_data(image, 90)), "02000000010000000000b4420302010407060508"
    )
    assert_equal(
        _hex(optical_flow_data(1, 1, 90, [0.5, -0.25])),
        "01000000010000000000b4420000003f000080be",
    )
    with assert_raises(contains="two numbers a pixel"):
        _ = optical_flow_data(1, 1, 90, [0.5])
    assert_equal(
        _hex(optical_flow_data(0, 0, 90, List[Float32]())),
        "00000000000000000000b442",
    )
    assert_equal(
        _hex(dvs_data(0, 0, 90, List[DVSEvent]())), "00000000000000000000b442"
    )
    assert_equal(
        _hex(
            dvs_data(
                2,
                1,
                90,
                [DVSEvent(1, 0, 123456789, True), DVSEvent(0, 0, -5, False)],
            )
        ),
        "02000000010000000000b4420100000015cd5b07000000000100000000fbffffffffffffff00",
    )


def test_point_cloud_bytes() raises:
    var lidar = LidarMeasurement(2, Angle(0.5, RADIAN))
    lidar.points_per_channel[0] = 1
    lidar.detections.append(LidarDetection(Vector3(1, 2, 3), 0.9))
    assert_equal(
        _hex(lidar_data(lidar)),
        "0000003f0200000001000000000000000000803f00000040000040406666663f",
    )
    var semantic = SemanticLidarMeasurement(2, Angle(0.5, RADIAN))
    semantic.points_per_channel[0] = 1
    semantic.detections.append(
        SemanticLidarDetection(Vector3(1, 2, 3), 0.75, 7, 14)
    )
    assert_equal(
        _hex(semantic_lidar_data(semantic)),
        "0000003f0200000001000000000000000000803f00000040000040400000403f070000000e000000",
    )
    # Nothing measured is a header alone.
    assert_equal(_hex(radar_data(List[RadarDetection]())), "")
    assert_equal(
        _hex(lidar_data(LidarMeasurement(0, Angle(0, RADIAN)))),
        "0000000000000000",
    )
    assert_equal(
        _hex(
            semantic_lidar_data(SemanticLidarMeasurement(0, Angle(0, RADIAN)))
        ),
        "0000000000000000",
    )
    assert_equal(
        _hex(
            radar_data(
                [
                    RadarDetection(
                        -1.5,
                        Angle(0.25, RADIAN),
                        Angle(-0.125, RADIAN),
                        _m(12.5),
                    )
                ]
            )
        ),
        "0000c0bf0000803e000000be00004841",
    )


def test_message_pack_bytes() raises:
    assert_equal(
        _hex(
            imu_data(
                IMUMeasurement(
                    Vector3(1, 2, 3),
                    Vector3(0.5, 0.25, 0.125),
                    Angle(1.5, RADIAN),
                )
            )
        ),
        "9393ca3f800000ca40000000ca4040000093ca3f000000ca3e800000ca3e000000ca3fc00000",
    )
    assert_equal(
        _hex(gnss_data(GeoLocation(49.0, 8.0, 12.5))),
        "93cb4048800000000000cb4020000000000000cb4029000000000000",
    )
    var w = ByteWriter()
    w.pack_uint(5)
    w.pack_uint(200)
    w.pack_uint(300)
    w.pack_uint(70000)
    w.pack_uint(8589934592)
    assert_equal(_hex(w^.finish()), "05ccc8cd012cce00011170cf0000000200000000")
    var s = ByteWriter()
    s.pack_str("ab")
    s.pack_str(String("x") * 40)
    s.pack_str(String("y") * 300)
    var text = _hex(s^.finish())
    assert_true(text.startswith("a26162d928787878"))
    assert_equal(text.byte_length(), 2 * (3 + 42 + 303))
    assert_true("da012c7979" in text)
    var a = ByteWriter()
    a.pack_array(3)
    a.pack_array(20)
    a.pack_bin([1, 2, 3])
    a.pack_bin(List[UInt8]())
    a.big(5, 0)
    assert_equal(_hex(a^.finish()), "93dc0014c403010203c400")


def test_static_actor_ids() raises:
    assert_equal(static_actor_id(ROAD), "static.road")
    assert_equal(static_actor_id(PEDESTRIAN), "static.pedestrian")
    assert_equal(static_actor_id(BUS), "static.bu")
    assert_equal(static_actor_id(CAR), "static.car")
    assert_equal(static_actor_id(UNLABELED), "static.unknown")
    assert_equal(static_actor_id(OTHER_OBJECT), "static.unknown")
    with assert_raises(contains="not valid"):
        _ = static_actor_id(SemanticTag(30))


def _fnv(bytes: List[UInt8]) -> UInt64:
    """FNV-1a, 64 bits."""
    var h = UInt64(1469598103934665603)
    for b in bytes:
        h ^= UInt64(b)
        h *= UInt64(1099511628211)
    return h


def _long_at(bytes: List[UInt8], at: Int) -> Int:
    var v = UInt64(0)
    for i in range(8):
        v |= UInt64(bytes[at + i]) << UInt64(8 * i)
    return Int(Int64(v))


def test_v2x_bytes() raises:
    # The expected sizes, offsets and FNV-1a hashes come from a C++
    # program that includes CARLA's `LibITS.h` and `V2XData.h`, zeroes
    # each record, fills the same fields and hashes its bytes (g++,
    # x86-64 Linux).
    var vehicle_high = HighFrequencyContainer(
        CONTAINER_VEHICLE,
        1234,
        10,
        567,
        3,
        1,
        45,
        4,
        19,
        -12,
        102,
        30001,
        7,
        0,
        -250,
        8,
        True,
        7,
        True,
        98,
        0,
    )
    var vehicle = CAM(
        ItsPduHeader(2, MESSAGE_CAM, 17),
        12345,
        STATION_PASSENGER_CAR,
        ReferencePosition(523456780, 134567890, 4095, 4095, 3601, 3456, 15),
        vehicle_high,
        LowFrequencyContainer(
            CONTAINER_VEHICLE, ROLE_EMERGENCY, UInt8(0xA2), 0
        ),
    )
    var rsu_high = HighFrequencyContainer.nothing()
    rsu_high.present = CONTAINER_RSU
    rsu_high.protected_zone_count = 16
    var rsu = CAM(
        ItsPduHeader(2, MESSAGE_CAM, 99),
        7,
        STATION_ROAD_SIDE_UNIT,
        ReferencePosition(-10, 20, 4095, 4095, 3601, -30, 15),
        rsu_high,
        LowFrequencyContainer(CONTAINER_NOTHING, ROLE_DEFAULT, 0, 0),
    )
    var one = v2x_cam_data([ReceivedCam(-71.5, vehicle)])
    assert_equal(len(one), 3168)
    assert_equal(_fnv(one), UInt64(15776130105727079206))
    # The station id at 24, the vehicle's yaw rate at 112 + 104 and its
    # role at 1544.
    assert_equal(_long_at(one, 24), 17)
    assert_equal(_long_at(one, 216), -250)
    assert_equal(_long_at(one, 1544), 6)
    var two = v2x_cam_data(
        [ReceivedCam(-71.5, vehicle), ReceivedCam(-80.25, rsu)]
    )
    assert_equal(len(two), 2 * 3168)
    assert_equal(_fnv(two), UInt64(4781070639683829901))
    # The roadside unit's zone count at 376 and its first latitude at
    # 384 + 24.
    assert_equal(_long_at(two, 3168 + 376), 16)
    assert_equal(_long_at(two, 3168 + 408), 50)
    assert_equal(len(v2x_cam_data(List[ReceivedCam]())), 0)

    var custom = CustomV2XMessage(
        ItsPduHeader(2, MESSAGE_CUSTOM, 42), [1, 2, 3, 250]
    )
    var bytes = v2x_custom_data([ReceivedCustom(-60.5, custom.copy())])
    assert_equal(len(bytes), 136)
    assert_equal(_fnv(bytes), UInt64(14913453552708276273))
    assert_equal(Int(bytes[32]), 4)
    assert_equal(Int(bytes[36]), 250)
    assert_equal(len(v2x_custom_data(List[ReceivedCustom]())), 0)
    # An empty payload: the length byte is zero and so is the rest.
    var empty = v2x_custom_data(
        [
            ReceivedCustom(
                -60.5,
                CustomV2XMessage(
                    ItsPduHeader(2, MESSAGE_CUSTOM, 42), List[UInt8]()
                ),
            )
        ]
    )
    assert_equal(len(empty), 136)
    for i in range(32, 136):
        assert_equal(Int(empty[i]), 0)
    var too_long = List[UInt8]()
    for _ in range(CUSTOM_V2X_MAX_BYTES + 1):
        too_long.append(1)
    with assert_raises(contains="100 bytes"):
        _ = v2x_custom_data(
            [
                ReceivedCustom(
                    -60.5,
                    CustomV2XMessage(
                        ItsPduHeader(2, MESSAGE_CUSTOM, 42), too_long^
                    ),
                )
            ]
        )


def test_normal_radius_cannot_be_zero_for_this_engine() raises:
    # IEEE Float32 rounds draw-1 to 2^30 exactly on this closed interval.
    # Its two midpoint ties round to the even 2^30 significand.
    assert_true(Float32(1073741791) < Float32(1073741824))
    assert_true(Float32(1073741889) > Float32(1073741824))
    for state in range(1073741793, 1073741890):
        assert_equal(Float32(state - 1) / Float32(2147483648), 0.5)
        var random = SensorRandom(1)
        random.state = UInt64(state)
        assert_true(random.uniform() != 0.5)
    # Nonzero centered draws are at least 2^-24; squares cannot underflow.
    var step = Float32(0.000000059604644775390625)
    assert_true(step * step > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
