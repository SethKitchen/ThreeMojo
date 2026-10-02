# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Physical sensor configuration must fail before sensor state is published."""

from extensions.carla.actor import ActorId, no_rotation
from extensions.carla.blueprint import (
    ATTRIBUTE_BOOL,
    ATTRIBUTE_FLOAT,
    ATTRIBUTE_INT,
    ATTRIBUTE_STRING,
    ActorAttributeValue,
    make_imu_definition,
)
from extensions.carla.cameras import (
    DVSConfig,
    DVSCamera,
    WideAngleLens,
    EQUIDISTANT,
    KANNALA_BRANDT,
)
from extensions.carla.gnss import Gnss, GnssDescription
from extensions.carla.imu import IMU, IMUDescription
from extensions.carla.lidar import LidarDescription
from extensions.carla.radar import Radar, RadarDescription
from extensions.carla.semantic_lidar import (
    lidar_description_from,
    hss_resolution_from,
    hss_points_per_laser,
)
from extensions.carla.obstacle import ObstacleDescription
from extensions.carla.sensor_attributes import (
    attribute_bool,
    attribute_float,
    attribute_string,
)
from extensions.carla.sensor_manager import SensorManager
from extensions.carla.v2x import (
    CamNoise,
    CaService,
    PathLossModel,
    PropagationParams,
)
from math.vector3 import Vector3
from std.math import nan, isfinite
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from tests.test_carla_world import _world, _pose
from tests.test_carla_spawn_atomicity import _counts, _check_counts
from units.si import (
    DEGREE,
    METER,
    SECOND,
    Angle,
    Length,
    Duration,
    Acceleration,
)


def _attributes(name: String, value: String) -> List[ActorAttributeValue]:
    return [ActorAttributeValue(name, ATTRIBUTE_FLOAT, value)]


def _nonfinite() -> List[Float32]:
    return [nan[DType.float32](), Float32.MAX * 2, -Float32.MAX * 2]


def test_shared_float_narrowing_and_compatibility() raises:
    for text in ["nan", "inf", "-inf", "1e39", "-1e39"]:
        with assert_raises(contains="finite in Float32"):
            _ = attribute_float(_attributes("physical", text), "physical", 0)
    for value in _nonfinite():
        with assert_raises(contains="finite in Float32"):
            _ = attribute_float(List[ActorAttributeValue](), "physical", value)
    assert_equal(
        attribute_float(
            _attributes("physical", "3.4028234663852886e38"), "physical", 0
        ),
        Float32(3.4028234663852886e38),
    )
    assert_equal(
        attribute_float(_attributes("physical", "-0"), "physical", 1), 0
    )
    assert_equal(
        attribute_float(
            _attributes("physical", "-12.5 trailing"), "physical", 0
        ),
        -12.5,
    )
    assert_equal(
        attribute_float(_attributes("physical", "nonnumeric"), "physical", 1), 0
    )
    var metadata: List[ActorAttributeValue] = [
        ActorAttributeValue("physical", ATTRIBUTE_STRING, "nan"),
        ActorAttributeValue("role_name", ATTRIBUTE_STRING, "nan"),
        ActorAttributeValue("fixed_rate", ATTRIBUTE_BOOL, "yes"),
    ]
    assert_equal(attribute_float(metadata, "physical", 42), 42)
    assert_equal(attribute_string(metadata, "role_name", ""), "nan")
    assert_false(attribute_bool(metadata, "fixed_rate", True))
    # Blueprint storage remains CARLA-compatible. Consumption rejects NaN.
    var bp = make_imu_definition()
    bp.set_attribute("noise_accel_stddev_x", "nan")
    with assert_raises(contains="finite in Float32"):
        _ = IMUDescription.from_attributes(bp.description())


def test_imu_attributes_reject_nonfinite() raises:
    for field in [
        "noise_accel_stddev_x",
        "noise_accel_stddev_y",
        "noise_accel_stddev_z",
        "noise_gyro_stddev_x",
        "noise_gyro_stddev_y",
        "noise_gyro_stddev_z",
        "noise_gyro_bias_x",
        "noise_gyro_bias_y",
        "noise_gyro_bias_z",
    ]:
        for text in ["nan", "inf", "-inf", "1e39", "-1e39"]:
            with assert_raises(contains="finite in Float32"):
                _ = IMUDescription.from_attributes(_attributes(field, text))


def test_gnss_attributes_reject_nonfinite() raises:
    for field in [
        "noise_lat_stddev",
        "noise_lat_bias",
        "noise_lon_stddev",
        "noise_lon_bias",
        "noise_alt_stddev",
        "noise_alt_bias",
    ]:
        for text in ["nan", "inf", "-inf", "1e39", "-1e39"]:
            with assert_raises(contains="finite in Float32"):
                _ = GnssDescription.from_attributes(_attributes(field, text))


def test_radar_attributes_reject_nonfinite() raises:
    for field in ["horizontal_fov", "vertical_fov", "range"]:
        for text in ["nan", "inf", "-inf", "1e39", "-1e39"]:
            with assert_raises(contains="finite in Float32"):
                _ = RadarDescription.from_attributes(_attributes(field, text))


def test_dvs_attributes_reject_nonfinite() raises:
    for field in [
        "positive_threshold",
        "negative_threshold",
        "sigma_positive_threshold",
        "sigma_negative_threshold",
        "log_eps",
    ]:
        for text in ["nan", "inf", "-inf", "1e39", "-1e39"]:
            with assert_raises(contains="finite in Float32"):
                _ = DVSConfig.from_attributes(_attributes(field, text))


def test_v2x_attributes_reject_nonfinite() raises:
    for field in [
        "transmit_power",
        "receiver_sensitivity",
        "combined_antenna_gain",
        "frequency_ghz",
        "d_ref",
        "filter_distance",
        "path_loss_exponent",
        "custom_fading_stddev",
    ]:
        for text in ["nan", "inf", "-inf", "1e39", "-1e39"]:
            with assert_raises(contains="finite in Float32"):
                _ = PropagationParams.from_attributes(_attributes(field, text))


def test_cam_noise_attributes_reject_nonfinite() raises:
    for field in [
        "noise_lat_stddev",
        "noise_lat_bias",
        "noise_lon_stddev",
        "noise_lon_bias",
        "noise_alt_stddev",
        "noise_alt_bias",
        "noise_head_stddev",
        "noise_head_bias",
        "noise_yawrate_stddev",
        "noise_yawrate_bias",
        "noise_vel_stddev_x",
        "noise_accel_stddev_x",
        "noise_accel_stddev_y",
        "noise_accel_stddev_z",
    ]:
        for text in ["nan", "inf", "-inf", "1e39", "-1e39"]:
            with assert_raises(contains="finite in Float32"):
                _ = CamNoise.from_attributes(_attributes(field, text))


def test_imu_constructor_checks_direct_description() raises:
    for value in _nonfinite():
        var d = IMUDescription()
        d.accelerometer_stddev.x = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)
        d = IMUDescription()
        d.accelerometer_stddev.y = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)
        d = IMUDescription()
        d.accelerometer_stddev.z = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)
        d = IMUDescription()
        d.gyroscope_stddev.x = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)
        d = IMUDescription()
        d.gyroscope_stddev.y = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)
        d = IMUDescription()
        d.gyroscope_stddev.z = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)
        d = IMUDescription()
        d.gyroscope_bias.x = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)
        d = IMUDescription()
        d.gyroscope_bias.y = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)
        d = IMUDescription()
        d.gyroscope_bias.z = value
        with assert_raises(contains="finite in Float32"):
            _ = IMU(d)


def test_gnss_constructor_checks_direct_description() raises:
    for value in _nonfinite():
        var d = GnssDescription()
        d.latitude_stddev = value
        with assert_raises(contains="finite in Float32"):
            _ = Gnss(d)
        d = GnssDescription()
        d.latitude_bias = value
        with assert_raises(contains="finite in Float32"):
            _ = Gnss(d)
        d = GnssDescription()
        d.longitude_stddev = value
        with assert_raises(contains="finite in Float32"):
            _ = Gnss(d)
        d = GnssDescription()
        d.longitude_bias = value
        with assert_raises(contains="finite in Float32"):
            _ = Gnss(d)
        d = GnssDescription()
        d.altitude_stddev = value
        with assert_raises(contains="finite in Float32"):
            _ = Gnss(d)
        d = GnssDescription()
        d.altitude_bias = value
        with assert_raises(contains="finite in Float32"):
            _ = Gnss(d)


def test_radar_constructor_checks_direct_description() raises:
    for value in _nonfinite():
        var d = RadarDescription()
        d.horizontal_fov.value = value
        with assert_raises(contains="finite in Float32"):
            _ = Radar(d, Vector3(0, 0, 0))
        d = RadarDescription()
        d.vertical_fov.value = value
        with assert_raises(contains="finite in Float32"):
            _ = Radar(d, Vector3(0, 0, 0))
        d = RadarDescription()
        d.range.value = value
        with assert_raises(contains="finite in Float32"):
            _ = Radar(d, Vector3(0, 0, 0))


def test_v2x_constructor_checks_direct_description() raises:
    for value in _nonfinite():
        var d = PropagationParams()
        d.transmit_power = value
        with assert_raises(contains="finite in Float32"):
            _ = PathLossModel(d)
        d = PropagationParams()
        d.receiver_sensitivity = value
        with assert_raises(contains="finite in Float32"):
            _ = PathLossModel(d)
        d = PropagationParams()
        d.combined_antenna_gain = value
        with assert_raises(contains="finite in Float32"):
            _ = PathLossModel(d)
        d = PropagationParams()
        d.frequency_ghz = value
        with assert_raises(contains="finite in Float32"):
            _ = PathLossModel(d)
        d = PropagationParams()
        d.reference_distance.value = value
        with assert_raises(contains="finite in Float32"):
            _ = PathLossModel(d)
        d = PropagationParams()
        d.filter_distance.value = value
        with assert_raises(contains="finite in Float32"):
            _ = PathLossModel(d)
        d = PropagationParams()
        d.path_loss_exponent = value
        with assert_raises(contains="finite in Float32"):
            _ = PathLossModel(d)
        d = PropagationParams()
        d.custom_fading_stddev = value
        with assert_raises(contains="finite in Float32"):
            _ = PathLossModel(d)


def test_dvs_constructor_checks_direct_description() raises:
    for value in _nonfinite():
        var d = DVSConfig()
        d.positive_threshold = value
        with assert_raises(contains="finite in Float32"):
            _ = DVSCamera(d, 1, 1, 0)
        d = DVSConfig()
        d.negative_threshold = value
        with assert_raises(contains="finite in Float32"):
            _ = DVSCamera(d, 1, 1, 0)
        d = DVSConfig()
        d.sigma_positive_threshold = value
        with assert_raises(contains="finite in Float32"):
            _ = DVSCamera(d, 1, 1, 0)
        d = DVSConfig()
        d.sigma_negative_threshold = value
        with assert_raises(contains="finite in Float32"):
            _ = DVSCamera(d, 1, 1, 0)
        d = DVSConfig()
        d.log_eps = value
        with assert_raises(contains="finite in Float32"):
            _ = DVSCamera(d, 1, 1, 0)


def test_noise_domains_allow_zero_and_signed_biases() raises:
    for field in [
        "noise_accel_stddev_x",
        "noise_accel_stddev_y",
        "noise_accel_stddev_z",
        "noise_gyro_stddev_x",
        "noise_gyro_stddev_y",
        "noise_gyro_stddev_z",
    ]:
        with assert_raises(contains="negative"):
            _ = IMUDescription.from_attributes(_attributes(field, "-0.1"))
    for field in ["noise_lat_stddev", "noise_lon_stddev", "noise_alt_stddev"]:
        with assert_raises(contains="negative"):
            _ = GnssDescription.from_attributes(_attributes(field, "-0.1"))
    for field in [
        "noise_lat_stddev",
        "noise_lon_stddev",
        "noise_alt_stddev",
        "noise_head_stddev",
        "noise_vel_stddev_x",
        "noise_yawrate_stddev",
        "noise_accel_stddev_x",
        "noise_accel_stddev_y",
        "noise_accel_stddev_z",
    ]:
        with assert_raises(contains="negative"):
            _ = CamNoise.from_attributes(_attributes(field, "-0.1"))
    var imu = IMUDescription.from_attributes(
        _attributes("noise_gyro_bias_x", "-1")
    )
    assert_equal(imu.gyroscope_bias.x, -1)
    assert_equal(imu.accelerometer_stddev.x, 0)
    var gnss = GnssDescription.from_attributes(
        _attributes("noise_lat_bias", "-1")
    )
    assert_equal(gnss.latitude_bias, -1)
    var noise = CamNoise.from_attributes(
        _attributes("noise_yawrate_bias", "-1")
    )
    assert_equal(noise.yaw_rate_bias, -1)


def test_radar_domains() raises:
    for field in ["horizontal_fov", "vertical_fov"]:
        for value in ["-1", "180", "181"]:
            with assert_raises():
                _ = RadarDescription.from_attributes(_attributes(field, value))
    for value in ["-1", "0"]:
        with assert_raises(contains="positive"):
            _ = RadarDescription.from_attributes(_attributes("range", value))
    var d = RadarDescription()
    d.points_per_second = -1
    with assert_raises(contains="negative"):
        _ = Radar(d, Vector3(0, 0, 0))
    d.points_per_second = 0
    d.horizontal_fov = Angle(0, DEGREE)
    d.vertical_fov = Angle(0, DEGREE)
    _ = Radar(d, Vector3(0, 0, 0))


def test_lidar_attributes_and_direct_nonfinite() raises:
    for field in [
        "range",
        "rotation_frequency",
        "upper_fov",
        "lower_fov",
        "horizontal_fov",
        "atmosphere_attenuation_rate",
        "dropoff_general_rate",
        "dropoff_intensity_limit",
        "dropoff_zero_intensity",
        "noise_stddev",
    ]:
        for text in ["nan", "inf", "-inf", "1e39"]:
            with assert_raises(contains="finite in Float32"):
                _ = lidar_description_from(_attributes(field, text))
    for text in ["nan", "inf", "1e39"]:
        with assert_raises():
            _ = hss_resolution_from(_attributes("horizontal_resolution", text))
    assert_true(
        hss_resolution_from(_attributes("horizontal_resolution", "0.01")).value
        > 0
    )
    var d = LidarDescription()
    d.dropoff_general_rate = 0
    d.dropoff_zero_intensity = 1
    d.atmosphere_attenuation.value = 0
    d.noise_stddev.value = 0
    d.upper_fov = d.lower_fov
    d.validate()
    d = LidarDescription()
    d.range.value = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.rotation_frequency.value = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.upper_fov.value = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.lower_fov.value = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.horizontal_fov.value = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.atmosphere_attenuation.value = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.dropoff_general_rate = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.dropoff_intensity_limit = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.dropoff_zero_intensity = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()
    d = LidarDescription()
    d.noise_stddev.value = nan[DType.float32]()
    with assert_raises(contains="finite in Float32"):
        d.validate()


def test_rotating_lidar_domains() raises:
    for value in ["0", "-1"]:
        with assert_raises():
            _ = lidar_description_from(_attributes("rotation_frequency", value))
        with assert_raises():
            _ = lidar_description_from(
                _attributes("dropoff_intensity_limit", value)
            )
    for value in ["0", "-1", "361"]:
        with assert_raises():
            _ = lidar_description_from(_attributes("horizontal_fov", value))
    var d = LidarDescription()
    d.points_per_second = 0
    with assert_raises():
        d.validate()
    d = LidarDescription()
    d.horizontal_fov = Angle(360, DEGREE)
    d.validate()


def test_hss_clamping_and_domains() raises:
    var d = LidarDescription()
    d.rotation_frequency.value = 0
    d.points_per_second = 0
    d.horizontal_fov = Angle(-1, DEGREE)
    d.dropoff_intensity_limit = 0
    d.validate(False)
    assert_equal(
        hss_points_per_laser(
            d, hss_resolution_from(_attributes("horizontal_resolution", "0"))
        ),
        0,
    )
    d.horizontal_fov = Angle(1, DEGREE)
    assert_equal(
        hss_points_per_laser(
            d, hss_resolution_from(_attributes("horizontal_resolution", "-1"))
        ),
        100,
    )
    for value in _nonfinite():
        with assert_raises(contains="finite"):
            _ = hss_points_per_laser(d, Angle(value, DEGREE))
    d.dropoff_intensity_limit = -1
    with assert_raises(contains="negative"):
        d.validate(False)


def test_camera_domains() raises:
    for field in ["positive_threshold", "negative_threshold", "log_eps"]:
        with assert_raises(contains="positive"):
            _ = DVSConfig.from_attributes(_attributes(field, "0"))
    for field in ["sigma_positive_threshold", "sigma_negative_threshold"]:
        with assert_raises(contains="negative"):
            _ = DVSConfig.from_attributes(_attributes(field, "-1"))
    var dvs = DVSConfig()
    dvs.refractory_period_ns = -1
    with assert_raises(contains="negative"):
        _ = DVSCamera(dvs, 1, 1, 0)
    for value in _nonfinite():
        with assert_raises(contains="finite"):
            _ = WideAngleLens(
                EQUIDISTANT, List[Float32](), 1, 1, Angle(value, DEGREE)
            )
        with assert_raises(contains="finite"):
            _ = WideAngleLens(KANNALA_BRANDT, [value], 1, 1, Angle(90, DEGREE))
    with assert_raises(contains="360"):
        _ = WideAngleLens(
            EQUIDISTANT, List[Float32](), 1, 1, Angle(361, DEGREE)
        )
    _ = WideAngleLens(EQUIDISTANT, List[Float32](), 1, 1, Angle(360, DEGREE))
    with assert_raises(contains="negative"):
        _ = WideAngleLens.from_attributes(_attributes("focal_length", "-1"))
    var a = _attributes("fov_fade_size", "-1")
    a.append(ActorAttributeValue("fov_mask", ATTRIBUTE_BOOL, "true"))
    with assert_raises(contains="negative"):
        _ = WideAngleLens.from_attributes(a)
    # The documented zero-fov fallback stays 90 degrees.
    assert_true(
        WideAngleLens.from_attributes(_attributes("fov", "0")).focal_length > 0
    )


def test_v2x_domains_and_cam_construction() raises:
    for field in ["frequency_ghz", "d_ref"]:
        for value in ["0", "-1"]:
            with assert_raises(contains="positive"):
                _ = PropagationParams.from_attributes(_attributes(field, value))
    for field in [
        "filter_distance",
        "path_loss_exponent",
        "custom_fading_stddev",
    ]:
        with assert_raises(contains="negative"):
            _ = PropagationParams.from_attributes(_attributes(field, "-1"))
        _ = PropagationParams.from_attributes(_attributes(field, "0"))
    _ = PropagationParams.from_attributes(_attributes("transmit_power", "-1"))
    _ = PropagationParams.from_attributes(
        _attributes("combined_antenna_gain", "-1")
    )
    var world = _world()
    var owner = world.spawn_actor(
        world.blueprints.at("sensor.other.v2x"), _pose(0, 0, 0, 0)
    )
    for value in _nonfinite():
        with assert_raises(contains="finite"):
            _ = CaService(world, owner, value, 1, False, CamNoise(), 0)
        with assert_raises(contains="finite"):
            _ = CaService(world, owner, 0.1, value, False, CamNoise(), 0)
    with assert_raises(contains="positive"):
        _ = CaService(world, owner, 0, 1, False, CamNoise(), 0)
    with assert_raises(contains="positive"):
        _ = CaService(world, owner, 0.1, -1, False, CamNoise(), 0)
    with assert_raises(contains="must not exceed"):
        _ = CaService(world, owner, 2, 1, False, CamNoise(), 0)
    var noise = CamNoise()
    noise.heading_bias = nan[DType.float32]()
    with assert_raises(contains="finite"):
        _ = CaService(world, owner, 0.1, 1, False, noise, 0)
    _ = CaService(world, owner, 1, 1, False, CamNoise(), 0)


def test_obstacle_domains() raises:
    for field in ["distance", "hit_radius"]:
        for value in ["nan", "inf", "1e39", "-1"]:
            with assert_raises():
                _ = ObstacleDescription.from_attributes(
                    _attributes(field, value)
                )
        _ = ObstacleDescription.from_attributes(_attributes(field, "0"))


def test_invalid_configuration_preserves_spawn_and_listen_state() raises:
    var world = _world()
    var manager = SensorManager()
    var existing = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.imu"), _pose(0, 0, 0, 0)
    )
    var cases: List[String] = [
        "sensor.other.imu",
        "noise_accel_stddev_x",
        "nan",
        "sensor.other.gnss",
        "noise_alt_stddev",
        "inf",
        "sensor.other.radar",
        "range",
        "1e39",
        "sensor.other.radar",
        "points_per_second",
        "-1",
        "sensor.lidar.ray_cast",
        "noise_stddev",
        "-1",
        "sensor.lidar.hss_lidar",
        "range",
        "-1",
        "sensor.lidar.hss_lidar",
        "horizontal_resolution",
        "nan",
        "sensor.camera.depth",
        "fov",
        "nan",
        "sensor.camera.dvs",
        "sigma_positive_threshold",
        "-1",
        "sensor.camera.rgb_fisheye",
        "focal_length",
        "-1",
        "sensor.other.v2x",
        "noise_head_stddev",
        "-1",
        "sensor.other.v2x",
        "gen_cam_min",
        "2",
        "sensor.other.v2x_custom",
        "filter_distance",
        "-1",
        "sensor.other.obstacle",
        "hit_radius",
        "-1",
        "sensor.other.imu",
        "sensor_tick",
        "-1",
        "sensor.other.imu",
        "sensor_tick",
        "inf",
    ]
    for i in range(0, len(cases), 3):
        var bp = world.blueprints.at(cases[i])
        # A copied or externally built actor description can bypass the
        # blueprint setter's finite-overflow check. Consumption must check it.
        for j in range(len(bp.attributes)):
            if bp.attributes[j].id == cases[i + 1]:
                bp.attributes[j].value = cases[i + 2]
        var before = _counts(world)
        var slots = len(manager.slots)
        var next_id = len(world.actors) + 1
        with assert_raises():
            _ = manager.spawn_sensor(world, bp, _pose(0, 0, 0, 0))
        _check_counts(world, before)
        assert_equal(len(manager.slots), slots)
        assert_true(manager.is_listening(existing))
        assert_false(world.is_alive(ActorId(next_id)))
        # A separately spawned actor stays alive if listen rejects it.
        var actor = world.spawn_actor(bp, _pose(0, 0, 0, 0))
        assert_equal(actor.value, next_id)
        with assert_raises():
            manager.listen(world, actor)
        assert_true(world.is_alive(actor))
        assert_equal(len(manager.slots), slots)
        assert_false(manager.is_listening(actor))
    _ = manager.tick(world)


def test_seeded_valid_imu_output_stays_finite_and_repeatable() raises:
    var d = IMUDescription()
    d.noise_seed = 42
    d.accelerometer_stddev = Vector3(0.1, 0.2, 0.3)
    d.gyroscope_stddev = Vector3(0.01, 0.02, 0.03)
    d.gyroscope_bias = Vector3(-0.2, 0, 0.2)
    var a = IMU(d)
    var b = IMU(d)
    for i in range(5):
        var location = Vector3(Float32(i) * 0.01, 0, 0)
        var x = a.measure(
            location,
            no_rotation(),
            no_rotation(),
            Vector3(0, 0, 0),
            no_rotation(),
            Duration(0.05, SECOND),
            Acceleration(9.81),
        )
        var y = b.measure(
            location,
            no_rotation(),
            no_rotation(),
            Vector3(0, 0, 0),
            no_rotation(),
            Duration(0.05, SECOND),
            Acceleration(9.81),
        )
        assert_true(x.accelerometer == y.accelerometer)
        assert_true(x.gyroscope == y.gyroscope)
        assert_equal(x.compass.value, y.compass.value)
        assert_true(isfinite(x.accelerometer.x))
        assert_true(isfinite(x.accelerometer.y))
        assert_true(isfinite(x.accelerometer.z))
        assert_true(isfinite(x.gyroscope.x))
        assert_true(isfinite(x.gyroscope.y))
        assert_true(isfinite(x.gyroscope.z))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
