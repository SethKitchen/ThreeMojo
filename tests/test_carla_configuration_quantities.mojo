# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Typed CARLA configuration preserves raw storage and rejects invalid input."""

from extensions.carla.blueprint import ATTRIBUTE_FLOAT, ActorAttributeValue
from extensions.carla.camera_render import (
    RgbCameraSettings,
    rgb_camera_settings,
)
from extensions.carla.cameras import (
    DVSConfig,
    EQUIDISTANT,
    WideAngleLens,
    kannala_brandt_polynomial,
    kannala_brandt_derivative,
)
from extensions.carla.gnss import GnssDescription
from extensions.carla.recorder_packets import RecordedWeather
from extensions.carla.replayer_helper import weather_of, process_weather
from tests.test_carla_world import _world
from extensions.carla.weather import WeatherParameters, weather_preset
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_raises,
)
from units.si import (
    Angle,
    Length,
    Frequency,
    Duration64,
    DEGREE,
    RADIAN,
    METER,
    KILOMETER,
    PER_SECOND,
    SECOND,
)


def _max_finite32() -> Float32:
    # Exact largest finite binary32, independent of SDK MAX semantics.
    return bitcast[DType.float32](UInt32(0x7F7FFFFF))


def _nonfinite() -> List[Float32]:
    return [nan[DType.float32](), inf[DType.float32](), -inf[DType.float32]()]


def test_weather_typed_constructor_and_raw_record() raises:
    var typed = WeatherParameters(
        5,
        6,
        7,
        8,
        Angle(90, DEGREE),
        Angle(-15, DEGREE),
        9,
        Length(2, KILOMETER),
        0.1,
        10,
        1,
        0.03,
        0.0331,
        11,
    )
    var raw = WeatherParameters.from_carla(
        5,
        6,
        7,
        8,
        90,
        -15,
        9,
        2000,
        0.1,
        10,
        1,
        0.03,
        0.0331,
        11,
    )
    assert_equal(typed, raw)
    assert_equal(typed.fog_distance.value, 2000)
    assert_almost_equal(typed.sun_azimuth_angle.to(DEGREE), 90, atol=1e-5)
    var defaults = weather_preset("Default")
    defaults.validate()
    assert_equal(defaults.fog_distance.value, -1)
    assert_almost_equal(defaults.sun_azimuth_angle.to(DEGREE), -1, atol=1e-6)
    var extreme = WeatherParameters(
        150,
        -5,
        0,
        0,
        Angle(400, DEGREE),
        Angle(-100, DEGREE),
        0,
        Length(-5, METER),
        0,
        0,
        0,
        0,
        0,
        0,
    ).clamped()
    assert_equal(extreme.cloudiness, 100)
    assert_equal(extreme.precipitation, 0)
    assert_equal(extreme.fog_distance.value, 0)
    assert_almost_equal(extreme.sun_altitude_angle.to(DEGREE), -90, atol=1e-5)


def test_weather_rejects_every_nonfinite_field() raises:
    for bad in _nonfinite():
        for index in range(14):
            var fields = List[Float32]()
            for _ in range(14):
                fields.append(0)
            fields[index] = bad
            with assert_raises(contains="finite"):
                _ = WeatherParameters.from_carla(
                    fields[0],
                    fields[1],
                    fields[2],
                    fields[3],
                    fields[4],
                    fields[5],
                    fields[6],
                    fields[7],
                    fields[8],
                    fields[9],
                    fields[10],
                    fields[11],
                    fields[12],
                    fields[13],
                )
        with assert_raises(contains="finite"):
            _ = WeatherParameters(
                0,
                0,
                0,
                0,
                Angle(bad),
                Angle(0),
                0,
                Length(0),
                0,
                0,
                0,
                0,
                0,
                0,
            )
        var raw = WeatherParameters()
        raw.fog_distance = Length(bad)
        with assert_raises(contains="finite"):
            raw.validate()


def test_recorded_weather_keeps_raw_units_and_fails_before_publish() raises:
    var record = RecordedWeather(
        5, 6, 7, 8, 90, -15, 9, 2000, 0.1, 10, 1, 0.03, 0.0331, 11
    )
    var typed = weather_of(record)
    assert_equal(typed.fog_distance.value, 2000)
    assert_almost_equal(typed.sun_azimuth_angle.to(DEGREE), 90, atol=1e-5)
    assert_almost_equal(typed.sun_altitude_angle.to(DEGREE), -15, atol=1e-5)
    assert_equal(record.fields()[4], 90)
    assert_equal(record.fields()[7], 2000)
    var world = _world()
    process_weather(world, record)
    assert_equal(world.get_weather(), typed)
    for bad in _nonfinite():
        record.fog_distance = bad
        with assert_raises(contains="finite"):
            process_weather(world, record)
        assert_equal(world.get_weather(), typed)


def test_rgb_typed_views_and_units() raises:
    var settings = RgbCameraSettings()
    assert_equal(settings.shutter_frequency().to(PER_SECOND), 200)
    assert_equal(settings.exposure_up_rate().to(PER_SECOND), 3)
    assert_equal(settings.exposure_down_rate().to(PER_SECOND), 1)
    assert_equal(settings.depth_blur_distance().to(METER), 1000)
    settings.set_shutter_speed(Frequency(125, PER_SECOND))
    settings.set_exposure_speed_up(Frequency(0.5, PER_SECOND))
    settings.set_exposure_speed_down(Frequency(0, PER_SECOND))
    settings.set_depth_blur_distance(Length(250, METER))
    assert_equal(settings.shutter_speed, 125)
    assert_equal(settings.exposure_speed_up, 0.5)
    assert_equal(settings.exposure_speed_down, 0)
    assert_equal(settings.blur_amount, 0.25)
    assert_equal(settings.depth_blur_distance().value, 250)
    # Frequency has the same SI storage, including Float32's low bit.
    var bits = UInt32(0x3F800001)
    settings.set_shutter_speed(Frequency(bitcast[DType.float32](bits)))
    assert_equal(
        bitcast[DType.uint32](settings.shutter_frequency().value), bits
    )
    settings.set_exposure_speed_up(Frequency(-0.0))
    assert_equal(
        bitcast[DType.uint32](settings.exposure_speed_up), UInt32(0x80000000)
    )


def test_rgb_bad_typed_values_do_not_change_raw_fields() raises:
    var settings = RgbCameraSettings()
    var bad_values = _nonfinite()
    bad_values.append(-1)
    for bad in bad_values:
        with assert_raises():
            settings.set_shutter_speed(Frequency(bad))
        with assert_raises():
            settings.set_exposure_speed_up(Frequency(bad))
        with assert_raises():
            settings.set_exposure_speed_down(Frequency(bad))
        with assert_raises():
            settings.set_depth_blur_distance(Length(bad))
        assert_equal(settings.shutter_speed, 200)
        assert_equal(settings.exposure_speed_up, 3)
        assert_equal(settings.exposure_speed_down, 1)
        assert_equal(settings.blur_amount, 1)
        var raw = RgbCameraSettings()
        raw.shutter_speed = bad
        raw.exposure_speed_up = bad
        raw.exposure_speed_down = bad
        raw.blur_amount = bad
        with assert_raises():
            _ = raw.shutter_frequency()
        with assert_raises():
            _ = raw.exposure_up_rate()
        with assert_raises():
            _ = raw.exposure_down_rate()
        with assert_raises():
            _ = raw.depth_blur_distance()
    with assert_raises(contains="positive"):
        settings.set_shutter_speed(Frequency(0))
    with assert_raises(contains="negative"):
        settings.set_depth_blur_distance(
            Length(-bitcast[DType.float32](UInt32(1)))
        )
    settings.blur_amount = _max_finite32()
    with assert_raises(contains="finite"):
        _ = settings.depth_blur_distance()
    for field in ["exposure_speed_up", "exposure_speed_down", "blur_amount"]:
        with assert_raises(contains="negative"):
            _ = rgb_camera_settings(
                [ActorAttributeValue(field, ATTRIBUTE_FLOAT, "-1")]
            )


def test_gnss_typed_constructor_and_setters() raises:
    var settings = GnssDescription(
        9,
        Angle(0.5, DEGREE),
        Angle(-2, DEGREE),
        Angle(0.25, DEGREE),
        Angle(3, DEGREE),
        Length(0.125, KILOMETER),
        Length(-20, METER),
    )
    assert_equal(settings.noise_seed, 9)
    assert_almost_equal(settings.latitude_stddev, 0.5, atol=1e-6)
    assert_almost_equal(settings.longitude_bias, 3, atol=1e-6)
    assert_equal(settings.altitude_stddev, 125)
    assert_equal(settings.altitude_bias, -20)
    settings.set_latitude_noise(Angle(0.125, RADIAN), Angle(-0.25, RADIAN))
    settings.set_longitude_noise(Angle(1, DEGREE), Angle(2, DEGREE))
    settings.set_altitude_noise(Length(2, METER), Length(-3, METER))
    assert_almost_equal(
        settings.latitude_stddev_angle().value, 0.125, atol=1e-7
    )
    assert_almost_equal(settings.latitude_bias_angle().value, -0.25, atol=1e-7)
    assert_almost_equal(
        settings.longitude_stddev_angle().to(DEGREE), 1, atol=1e-6
    )
    assert_almost_equal(
        settings.longitude_bias_angle().to(DEGREE), 2, atol=1e-6
    )
    assert_equal(settings.altitude_stddev_length().value, 2)
    assert_equal(settings.altitude_bias_length().value, -3)


def test_gnss_bad_noise_is_transactional() raises:
    var settings = GnssDescription()
    for bad in _nonfinite():
        with assert_raises(contains="finite"):
            settings.set_latitude_noise(Angle(bad), Angle(2))
        with assert_raises(contains="finite"):
            settings.set_latitude_noise(Angle(1), Angle(bad))
        assert_equal(settings.latitude_stddev, 0)
        assert_equal(settings.latitude_bias, 0)
        with assert_raises(contains="finite"):
            settings.set_longitude_noise(Angle(bad), Angle(2))
        with assert_raises(contains="finite"):
            settings.set_longitude_noise(Angle(1), Angle(bad))
        assert_equal(settings.longitude_stddev, 0)
        assert_equal(settings.longitude_bias, 0)
        with assert_raises(contains="finite"):
            settings.set_altitude_noise(Length(bad), Length(2))
        with assert_raises(contains="finite"):
            settings.set_altitude_noise(Length(1), Length(bad))
        assert_equal(settings.altitude_stddev, 0)
        assert_equal(settings.altitude_bias, 0)
    for huge in [_max_finite32(), -_max_finite32()]:
        with assert_raises(contains="finite"):
            settings.set_latitude_noise(Angle(0), Angle(huge))
        with assert_raises(contains="finite"):
            settings.set_longitude_noise(Angle(0), Angle(huge))
    with assert_raises(contains="negative"):
        settings.set_latitude_noise(Angle(-1), Angle(2))
    assert_equal(settings.latitude_stddev, 0)
    assert_equal(settings.latitude_bias, 0)
    with assert_raises(contains="negative"):
        settings.set_longitude_noise(Angle(-1), Angle(2))
    assert_equal(settings.longitude_stddev, 0)
    assert_equal(settings.longitude_bias, 0)
    with assert_raises(contains="negative"):
        settings.set_altitude_noise(Length(-1), Length(2))
    assert_equal(settings.altitude_stddev, 0)
    assert_equal(settings.altitude_bias, 0)
    with assert_raises(contains="negative"):
        _ = GnssDescription(
            0, Angle(-1), Angle(0), Angle(0), Angle(0), Length(0), Length(0)
        )


def test_gnss_views_check_mutable_raw_fields() raises:
    for bad in _nonfinite():
        var settings = GnssDescription()
        settings.latitude_stddev = bad
        with assert_raises(contains="finite"):
            _ = settings.latitude_stddev_angle()
        settings.latitude_bias = bad
        with assert_raises(contains="finite"):
            _ = settings.latitude_bias_angle()
        settings.longitude_stddev = bad
        with assert_raises(contains="finite"):
            _ = settings.longitude_stddev_angle()
        settings.longitude_bias = bad
        with assert_raises(contains="finite"):
            _ = settings.longitude_bias_angle()
        settings.altitude_stddev = bad
        with assert_raises(contains="finite"):
            _ = settings.altitude_stddev_length()
        settings.altitude_bias = bad
        with assert_raises(contains="finite"):
            _ = settings.altitude_bias_length()
    var negative = GnssDescription()
    negative.latitude_stddev = -1
    with assert_raises(contains="negative"):
        _ = negative.latitude_stddev_angle()
    negative.longitude_stddev = -1
    with assert_raises(contains="negative"):
        _ = negative.longitude_stddev_angle()
    negative.altitude_stddev = -1
    with assert_raises(contains="negative"):
        _ = negative.altitude_stddev_length()


def test_wide_angle_fade_adapter() raises:
    var lens = WideAngleLens(
        EQUIDISTANT, List[Float32](), 4, 2, Angle(90, DEGREE)
    )
    assert_equal(lens.fade_angle().value, 0)
    lens.set_fov_fade_size(Angle(0.25, RADIAN))
    assert_almost_equal(lens.fade_angle().value, 0.25, atol=1e-7)
    var before = lens.fov_fade_size
    var bad_values = _nonfinite()
    bad_values.append(-1)
    bad_values.append(_max_finite32())
    for bad in bad_values:
        with assert_raises():
            lens.set_fov_fade_size(Angle(bad))
        assert_equal(lens.fov_fade_size, before)
    for bad in _nonfinite():
        lens.fov_fade_size = bad
        with assert_raises(contains="finite"):
            _ = lens.fade_angle()
    lens.fov_fade_size = -1
    with assert_raises(contains="negative"):
        _ = lens.fade_angle()


def test_typed_lens_polynomial() raises:
    assert_almost_equal(
        kannala_brandt_polynomial(Angle(0.5), [0.1, 0.2]), 0.51875, atol=1e-6
    )
    assert_almost_equal(
        kannala_brandt_derivative(Angle(0.5), [0.1, 0.2]), 1.1375, atol=1e-6
    )
    assert_equal(kannala_brandt_polynomial(Angle(0.5), List[Float32]()), 0.5)
    assert_equal(kannala_brandt_derivative(Angle(0.5), List[Float32]()), 1)
    for bad in _nonfinite():
        with assert_raises(contains="finite"):
            _ = kannala_brandt_polynomial(Angle(bad), List[Float32]())
        with assert_raises(contains="finite"):
            _ = kannala_brandt_derivative(Angle(bad), List[Float32]())
        with assert_raises(contains="finite"):
            _ = kannala_brandt_polynomial(Angle(0.5), [bad])
        with assert_raises(contains="finite"):
            _ = kannala_brandt_derivative(Angle(0.5), [bad])


def test_dvs_refractory_duration() raises:
    var config = DVSConfig()
    assert_equal(config.refractory_duration().value, 0)
    config.set_refractory_period(Duration64(2.75e-9, SECOND))
    assert_equal(config.refractory_period_ns, 2)
    assert_equal(config.refractory_duration().value, Float64(2e-9))
    config.set_refractory_period(Duration64(100000000.000001))
    assert_equal(config.refractory_period_ns, 100000000000000992)
    assert_equal(config.refractory_duration().value, Float64(100000000.000001))
    config.set_refractory_period(Duration64(9.2e9))
    assert_equal(config.refractory_period_ns, 9200000000000000000)
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
        Float64(-1),
        Float64(9.2e9 + 1),
    ]:
        with assert_raises():
            config.set_refractory_period(Duration64(bad))
        assert_equal(config.refractory_period_ns, 9200000000000000000)
    config.set_refractory_period(Duration64(-0.0))
    assert_equal(config.refractory_period_ns, 0)
    config.refractory_period_ns = -1
    with assert_raises(contains="negative"):
        _ = config.refractory_duration()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
