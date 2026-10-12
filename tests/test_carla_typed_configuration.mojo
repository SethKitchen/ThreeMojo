# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Typed CARLA configuration and Float64 radio distances (#333).

The typed constructors of `GnssDescription`, `CamNoise` and
`WeatherParameters` must store what the raw constructors store. The
`Length64` overloads of `PathLossModel` must give the same bits as the
raw `Float64` forms, for a large distance with a small step and for a
tiny distance.
"""

from extensions.carla.gnss import GnssDescription
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.v2x import (
    CamNoise,
    LOS,
    NLOS_BUILDING,
    PathLossModel,
    PropagationParams,
)
from extensions.carla.weather import WeatherParameters
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Acceleration,
    Angle,
    AngularVelocity,
    DEGREE,
    Length,
    Length64,
    METER,
    Velocity,
)


def _degrees(value: Float32) -> Angle:
    return Angle(value, DEGREE)


def test_gnss_typed_settings_store_degrees_and_meters() raises:
    var d = GnssDescription(
        7,
        _degrees(0.25),
        _degrees(-0.5),
        _degrees(1.5),
        _degrees(2),
        Length(3, METER),
        Length(-4, METER),
    )
    assert_equal(d.noise_seed, 7)
    # An angle goes through radians, so allow one unit in the last place.
    assert_almost_equal(d.latitude_stddev, 0.25, atol=1e-7)
    assert_almost_equal(d.latitude_bias, -0.5, atol=1e-7)
    assert_almost_equal(d.longitude_stddev, 1.5, atol=2e-7)
    assert_almost_equal(d.longitude_bias, 2, atol=3e-7)
    # A length in meters is exact.
    assert_equal(d.altitude_stddev, 3)
    assert_equal(d.altitude_bias, -4)


def test_gnss_typed_settings_refuse_a_bad_deviation() raises:
    with assert_raises(contains="cannot be negative"):
        _ = GnssDescription(
            0,
            _degrees(-1),
            _degrees(0),
            _degrees(0),
            _degrees(0),
            Length(0, METER),
            Length(0, METER),
        )
    with assert_raises(contains="finite"):
        _ = GnssDescription(
            0,
            _degrees(0),
            _degrees(0),
            _degrees(0),
            _degrees(0),
            Length(Float32.MAX, METER).scaled(2),
            Length(0, METER),
        )


def _noise(latitude_stddev: Angle) raises -> CamNoise:
    return CamNoise(
        latitude_stddev,
        _degrees(0.5),
        _degrees(-0.25),
        _degrees(0.75),
        Length(2, METER),
        Length(-1, METER),
        _degrees(3),
        _degrees(-3),
        Velocity(0.5),
        AngularVelocity(0.125),
        AngularVelocity(-0.0625),
        Acceleration(0.25),
        Acceleration(0.5),
        Acceleration(1),
    )


def test_cam_noise_typed_settings_store_carla_units() raises:
    var n = _noise(_degrees(0.125))
    assert_almost_equal(n.latitude_stddev, 0.125, atol=1e-7)
    assert_almost_equal(n.longitude_stddev, 0.5, atol=1e-7)
    assert_almost_equal(n.latitude_bias, -0.25, atol=1e-7)
    assert_almost_equal(n.longitude_bias, 0.75, atol=1e-7)
    assert_equal(n.altitude_stddev, 2)
    assert_equal(n.altitude_bias, -1)
    assert_almost_equal(n.heading_stddev, 3, atol=3e-7)
    assert_almost_equal(n.heading_bias, -3, atol=3e-7)
    # SI units with a unit scale are exact.
    assert_equal(n.velocity_stddev, 0.5)
    assert_equal(n.yaw_rate_stddev, 0.125)
    assert_equal(n.yaw_rate_bias, -0.0625)
    assert_true(n.acceleration_stddev == Vector3(0.25, 0.5, 1))
    with assert_raises(contains="cannot be negative"):
        _ = _noise(_degrees(-1))


def test_weather_typed_constructor_matches_the_raw_one() raises:
    var raw = WeatherParameters(
        10, 20, 30, 40, 123.5, -15.25, 50, 75.5, 0.2, 60, 1, 0.03, 0.0331, 5
    )
    var typed = WeatherParameters(
        10,
        20,
        30,
        40,
        _degrees(123.5),
        _degrees(-15.25),
        50,
        Length(75.5, METER),
        0.2,
        60,
        1,
        0.03,
        0.0331,
        5,
    )
    assert_true(raw == typed)
    var other = WeatherParameters(
        10,
        20,
        30,
        40,
        _degrees(123.5),
        _degrees(-15.25),
        50,
        Length(75.25, METER),
        0.2,
        60,
        1,
        0.03,
        0.0331,
        5,
    )
    assert_false(raw == other)


def test_path_loss_keeps_every_float64_digit() raises:
    var model = PathLossModel(PropagationParams())
    # 1e7 m plus 1e-6 m: a Float32 length cannot hold the step.
    var far = 1.0e7 + 1.0e-6
    assert_equal(Float32(far), Float32(1.0e7))
    var tiny = 3.0e-300
    for distance in [far, 1.0e7, 1.5, tiny]:
        var typed = Length64(distance, METER)
        assert_equal(typed.value, distance)
        assert_equal(
            model.two_ray(typed, Length64(1.5), Length64(1.5)),
            model.two_ray(distance, 1.5, 1.5),
        )
        assert_equal(
            model.two_ray_simple(typed, Length64(1.5), Length64(1.5)),
            model.two_ray_simple(distance, 1.5, 1.5),
        )
        assert_equal(model.winner(LOS, typed), model.winner(LOS, distance))
    # The far step changes the raw Float64 result, and the typed form
    # keeps that change.
    assert_true(
        model.two_ray(Length64(far), Length64(1.5), Length64(1.5))
        != model.two_ray(Length64(1.0e7), Length64(1.5), Length64(1.5))
    )


def test_path_loss_link_typed_and_raw_agree() raises:
    var model = PathLossModel(PropagationParams())
    var source = Vector3(0, 0, 0)
    var destination = Vector3(100, 0, 0)
    for state in [LOS, NLOS_BUILDING]:
        var a = SensorRandom(5)
        var b = SensorRandom(5)
        var typed = model.loss(
            state,
            source,
            destination,
            Length64(100.000000001),
            Length64(1.5),
            Length64(1.5),
            List[Vector3](),
            a,
        )
        var raw = model.loss(
            state,
            source,
            destination,
            100.000000001,
            1.5,
            1.5,
            List[Vector3](),
            b,
        )
        assert_equal(typed, raw)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
