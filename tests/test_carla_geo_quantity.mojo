# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Checked geodesy and V2X quantities preserve CARLA scalar precision."""

from extensions.carla.geo import (
    GeoLocation,
    Ellipsoid,
    OffsetTransform,
    UtmZone,
    TransverseMercatorParams,
    LambertConformalConicParams,
    parse_geo_projection_and_reference,
)
from extensions.carla.sensor_data import gnss_data
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.v2x import (
    CamNoise,
    PropagationParams,
    PathLossModel,
    LOS,
    NLOS_BUILDING,
    speed_value,
    speed_value_meters_per_second,
)
from math.vector3 import Vector3
from std.collections import Dict
from std.math import inf, nan, pi
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle64,
    Length64,
    Angle,
    Length,
    AngularVelocity,
    Acceleration,
    Velocity,
    Frequency,
    DEGREE,
    KILOMETER,
    METER,
)


def _bad64() -> List[Float64]:
    return [nan[DType.float64](), inf[DType.float64](), -inf[DType.float64]()]


def _bad32() -> List[Float32]:
    return [nan[DType.float32](), inf[DType.float32](), -inf[DType.float32]()]


def _bits(value: Float64) -> UInt64:
    return bitcast[DType.uint64](value)


def test_geo_raw_bits_serialization_and_views() raises:
    var latitude = Float64(49.00000000000001)
    var longitude = Float64(8.000000000000002)
    for altitude in [
        Float64(1e300),
        Float64(1e-300),
        Float64(-0.0),
        Float64(0.0),
    ]:
        var location = GeoLocation.from_degrees_meters(
            latitude, longitude, altitude
        )
        assert_equal(_bits(location.latitude_degrees), _bits(latitude))
        assert_equal(_bits(location.longitude_degrees), _bits(longitude))
        assert_equal(_bits(location.altitude_length().value), _bits(altitude))
        assert_equal(
            _bits(location.latitude_angle64().value),
            _bits(latitude * pi / 180.0),
        )
        assert_equal(
            _bits(location.longitude_angle64().value),
            _bits(longitude * pi / 180.0),
        )
        var bytes = gnss_data(location)
        assert_equal(len(bytes), 28)
        for component in range(3):
            var values = [latitude, longitude, altitude]
            for byte in range(8):
                assert_equal(
                    bytes[2 + component * 9 + byte],
                    UInt8(
                        (_bits(values[component]) >> UInt64((7 - byte) * 8))
                        & 255
                    ),
                )
    var zero = GeoLocation.from_degrees_meters(-0.0, -0.0, -0.0)
    assert_equal(_bits(zero.latitude_angle64().value), _bits(-0.0))
    assert_equal(_bits(zero.longitude_angle64().value), _bits(-0.0))
    assert_equal(
        bitcast[DType.uint32](zero.latitude_angle().value), UInt32(0x80000000)
    )
    assert_equal(
        bitcast[DType.uint32](zero.longitude_angle().value), UInt32(0x80000000)
    )
    var typed = GeoLocation(
        Angle64(pi / 4.0), Angle64(pi / 2.0), Length64(2, KILOMETER)
    )
    assert_almost_equal(typed.latitude_degrees, 45.0, atol=1e-13)
    assert_almost_equal(typed.longitude_degrees, 90.0, atol=1e-13)
    assert_equal(typed.altitude_meters, 2000.0)
    var parsed = parse_geo_projection_and_reference(
        (
            "+proj=tmerc +lat_0=49.00000000000001 +lon_0=8.000000000000002"
            " +x_0=100000000.000001 +y_0=-0"
        ),
        Dict[String, Float64](),
    )
    assert_equal(_bits(parsed[1].latitude_degrees), _bits(latitude))
    assert_equal(_bits(parsed[1].longitude_degrees), _bits(longitude))
    assert_equal(
        _bits(parsed[0].transverse_mercator.x_0_length().value),
        _bits(Float64(100000000.000001)),
    )
    assert_equal(
        _bits(parsed[0].transverse_mercator.y_0_length().value), _bits(-0.0)
    )


def test_geo_invalid_raw_and_typed_domains() raises:
    for bad in _bad64():
        with assert_raises():
            _ = GeoLocation(Angle64(bad), Angle64(0), Length64(0))
        with assert_raises():
            _ = GeoLocation.from_degrees_meters(0, bad, 0)
        with assert_raises():
            _ = GeoLocation.from_degrees_meters(0, 0, bad)
        var raw = GeoLocation()
        raw.latitude_degrees = bad
        with assert_raises():
            _ = raw.latitude_angle64()
        with assert_raises():
            _ = raw.latitude_angle()
        raw = GeoLocation()
        raw.longitude_degrees = bad
        with assert_raises():
            _ = raw.longitude_angle64()
        with assert_raises():
            _ = raw.longitude_angle()
        raw = GeoLocation()
        raw.altitude_meters = bad
        with assert_raises():
            _ = raw.altitude_length()
    for latitude in [Float64(-90.0001), Float64(90.0001)]:
        with assert_raises():
            _ = GeoLocation.from_degrees_meters(latitude, 0, 0)
    _ = GeoLocation.from_degrees_meters(-90, 0, 0)
    _ = GeoLocation.from_degrees_meters(90, 0, 0)
    var huge = GeoLocation.from_degrees_meters(0, 1e100, 0)
    _ = huge.longitude_angle64()
    with assert_raises():
        _ = huge.longitude_angle()
    huge.longitude_degrees = 1e308
    with assert_raises():
        _ = huge.longitude_angle64()
    with assert_raises():
        _ = GeoLocation(Angle64(0), Angle64(1e308), Length64(0))


def test_ellipsoid_and_offset_quantities() raises:
    var ellipsoid = Ellipsoid(Length64(6378137.000000001), 298.257223563)
    assert_equal(
        _bits(ellipsoid.semi_major_axis().value),
        _bits(Float64(6378137.000000001)),
    )
    assert_equal(ellipsoid.semi_minor_axis().value, ellipsoid.b_meters())
    ellipsoid.from_b(Length64(ellipsoid.a_meters))
    assert_equal(ellipsoid.semi_minor_axis().value, ellipsoid.a_meters)
    for bad in _bad64():
        with assert_raises():
            _ = Ellipsoid(Length64(bad), 300)
        with assert_raises():
            ellipsoid.from_b(Length64(bad))
        assert_equal(ellipsoid.f_inv, inf[DType.float64]())
    for bad in [Float64(0), Float64(-1)]:
        with assert_raises():
            _ = Ellipsoid(Length64(bad), 300)
        with assert_raises():
            ellipsoid.from_b(Length64(bad))
    for bad in [
        Float64(1),
        Float64(0),
        Float64(-1),
        nan[DType.float64](),
        -inf[DType.float64](),
    ]:
        with assert_raises():
            _ = Ellipsoid(Length64(1), bad)
    with assert_raises():
        ellipsoid.from_b(Length64(ellipsoid.a_meters + 1))
    var raw = Ellipsoid()
    raw.a_meters = -1
    with assert_raises():
        _ = raw.semi_major_axis()
    with assert_raises():
        _ = raw.semi_minor_axis()
    for value in [Float64(1e300), Float64(1e-300), Float64(-0.0)]:
        var offset = OffsetTransform(
            Length64(value), Length64(value), Length64(value), Angle64(-0.0)
        )
        assert_equal(_bits(offset.x_offset().value), _bits(value))
        assert_equal(_bits(offset.y_offset().value), _bits(value))
        assert_equal(_bits(offset.z_offset().value), _bits(value))
    for bad in _bad64():
        for index in range(4):
            var inputs = [Float64(0), Float64(0), Float64(0), Float64(0)]
            inputs[index] = bad
            with assert_raises():
                _ = OffsetTransform.from_meters_radians(
                    inputs[0], inputs[1], inputs[2], inputs[3]
                )
        var offset = OffsetTransform.from_meters_radians(0, 0, 0, 0)
        offset.offset_x_meters = bad
        offset.offset_y_meters = bad
        offset.offset_z_meters = bad
        with assert_raises():
            _ = offset.x_offset()
        with assert_raises():
            _ = offset.y_offset()
        with assert_raises():
            _ = offset.z_offset()
    assert_almost_equal(
        UtmZone(31).central_meridian_angle().value, pi / 60, atol=1e-16
    )
    for zone in [0, 61]:
        with assert_raises():
            _ = UtmZone(zone).central_meridian_angle()


def test_projection_quantity_constructors() raises:
    var tm = TransverseMercatorParams(
        Angle64(0.5),
        Angle64(1),
        1,
        Length64(1e300),
        Length64(-0.0),
        Ellipsoid(),
    )
    assert_almost_equal(tm.lat_0_angle().value, 0.5, atol=1e-15)
    assert_almost_equal(tm.lon_0_angle().value, 1.0, atol=1e-15)
    assert_equal(tm.x_0_length().value, 1e300)
    assert_equal(_bits(tm.y_0_length().value), _bits(-0.0))
    var lcc = LambertConformalConicParams(
        Angle64(0.5),
        Angle64(0.25),
        Angle64(0.75),
        Angle64(1),
        Length64(1e-300),
        Length64(-0.0),
        Ellipsoid(),
    )
    assert_almost_equal(lcc.lat_0_angle().value, 0.5, atol=1e-15)
    assert_almost_equal(lcc.lat_1_angle().value, 0.25, atol=1e-15)
    assert_almost_equal(lcc.lat_2_angle().value, 0.75, atol=1e-15)
    assert_almost_equal(lcc.lon_0_angle().value, 1.0, atol=1e-15)
    assert_equal(lcc.x_0_length().value, 1e-300)
    assert_equal(_bits(lcc.y_0_length().value), _bits(-0.0))
    for scale in [
        Float64(0),
        Float64(-1),
        nan[DType.float64](),
        inf[DType.float64](),
    ]:
        with assert_raises():
            _ = TransverseMercatorParams.from_degrees_meters(
                0, 0, scale, 0, 0, Ellipsoid()
            )


def test_transversemercatorparams_raw_refusals() raises:
    for bad in _bad64():
        var record = TransverseMercatorParams()
        record.lat_0_degrees = bad
        with assert_raises():
            _ = record.lat_0_angle()
        with assert_raises():
            record.validate()
        record = TransverseMercatorParams()
        record.lon_0_degrees = bad
        with assert_raises():
            _ = record.lon_0_angle()
        with assert_raises():
            record.validate()
        record = TransverseMercatorParams()
        record.x_0_meters = bad
        with assert_raises():
            _ = record.x_0_length()
        with assert_raises():
            record.validate()
        record = TransverseMercatorParams()
        record.y_0_meters = bad
        with assert_raises():
            _ = record.y_0_length()
        with assert_raises():
            record.validate()


def test_lambertconformalconicparams_raw_refusals() raises:
    for bad in _bad64():
        var record = LambertConformalConicParams()
        record.lat_0_degrees = bad
        with assert_raises():
            _ = record.lat_0_angle()
        with assert_raises():
            record.validate()
        record = LambertConformalConicParams()
        record.lat_1_degrees = bad
        with assert_raises():
            _ = record.lat_1_angle()
        with assert_raises():
            record.validate()
        record = LambertConformalConicParams()
        record.lat_2_degrees = bad
        with assert_raises():
            _ = record.lat_2_angle()
        with assert_raises():
            record.validate()
        record = LambertConformalConicParams()
        record.lon_0_degrees = bad
        with assert_raises():
            _ = record.lon_0_angle()
        with assert_raises():
            record.validate()
        record = LambertConformalConicParams()
        record.x_0_meters = bad
        with assert_raises():
            _ = record.x_0_length()
        with assert_raises():
            record.validate()
        record = LambertConformalConicParams()
        record.y_0_meters = bad
        with assert_raises():
            _ = record.y_0_length()
        with assert_raises():
            record.validate()


def test_radio_quantity_views_and_formulas() raises:
    var params = PropagationParams()
    params.set_carrier_frequency(Frequency(4e9))
    assert_equal(params.frequency_ghz, 4)
    assert_equal(params.carrier_frequency().value, 4e9)
    var model = PathLossModel(params)
    assert_equal(model.carrier_frequency().value, 4e9)
    assert_equal(model.wavelength_length().value, model.wavelength)
    assert_equal(
        model.winner(LOS, Length64(100)), model.winner_meters(LOS, 100)
    )
    assert_equal(
        model.two_ray(Length64(20), Length64(1.5), Length64(1.5)),
        model.two_ray_meters(20, 1.5, 1.5),
    )
    assert_equal(
        model.two_ray_simple(Length64(1000), Length64(2), Length64(1)),
        model.two_ray_simple_meters(1000, 2, 1),
    )
    assert_equal(
        model.vehicle_loss(Length64(10), Length64(10), Length64(-1)),
        model.vehicle_loss_meters(10, 10, -1),
    )
    var first = SensorRandom(42)
    var second = SensorRandom(42)
    assert_equal(
        model.loss(
            NLOS_BUILDING,
            Vector3(0, 0, 0),
            Vector3(20, 0, 0),
            Length64(20),
            Length64(1.5),
            Length64(1.5),
            List[Vector3](),
            first,
        ),
        model.loss_meters(
            NLOS_BUILDING,
            Vector3(0, 0, 0),
            Vector3(20, 0, 0),
            20,
            1.5,
            1.5,
            List[Vector3](),
            second,
        ),
    )
    assert_equal(speed_value(Velocity(12.5)), 1250)
    assert_equal(speed_value(Velocity(-1)), 16383)
    assert_equal(speed_value(Velocity(-0.0)), 0)
    assert_equal(speed_value(Velocity(1e30)), 16382)
    for bad in _bad32():
        with assert_raises():
            _ = speed_value(Velocity(bad))
        with assert_raises():
            _ = speed_value_meters_per_second(bad)
        with assert_raises():
            params.set_carrier_frequency(Frequency(bad))
        assert_equal(params.frequency_ghz, 4)
        var raw = params
        raw.frequency_ghz = bad
        with assert_raises():
            _ = raw.carrier_frequency()
    params.frequency_ghz = 1e38
    with assert_raises():
        _ = params.carrier_frequency()
    for bad in [Float32(0), Float32(-1), Float32(1e-40)]:
        with assert_raises():
            params.set_carrier_frequency(Frequency(bad))


def test_radio_invalid_dimensions_and_singular_computation() raises:
    var model = PathLossModel(PropagationParams())
    for bad in _bad64():
        with assert_raises():
            _ = model.winner(LOS, Length64(bad))
        with assert_raises():
            _ = model.two_ray(Length64(20), Length64(bad), Length64(1))
        with assert_raises():
            _ = model.two_ray_simple(Length64(20), Length64(1), Length64(bad))
        with assert_raises():
            _ = model.vehicle_loss(Length64(10), Length64(10), Length64(bad))
        var raw = model
        raw.wavelength = bad
        with assert_raises():
            _ = raw.wavelength_length()
        raw.frequency = bad
        with assert_raises():
            _ = raw.carrier_frequency()
    for distance in [Float64(0), Float64(-1)]:
        with assert_raises():
            _ = model.winner(LOS, Length64(distance))
        with assert_raises():
            _ = model.two_ray_simple(
                Length64(distance), Length64(1), Length64(1)
            )
        with assert_raises():
            _ = model.vehicle_loss(Length64(distance), Length64(1), Length64(1))
    with assert_raises():
        _ = model.two_ray(Length64(1), Length64(2), Length64(1))
    with assert_raises():
        _ = model.two_ray(Length64(20), Length64(-1), Length64(1))
    with assert_raises():
        _ = model.two_ray_simple(Length64(20), Length64(0), Length64(1))
    with assert_raises():
        _ = model.two_ray(Length64(1e300), Length64(1), Length64(1))
    with assert_raises():
        _ = model.vehicle_loss(Length64(1e-300), Length64(1e-300), Length64(1))


def test_cam_latitude_typed_noise() raises:
    var noise = CamNoise()
    noise.set_latitude_noise(Angle(0.25), Angle(-0.0))
    assert_almost_equal(noise.latitude_stddev_angle().value, 0.25, atol=1e-7)
    assert_equal(
        bitcast[DType.uint32](noise.latitude_bias_angle().value),
        UInt32(0x80000000),
    )
    var saved = noise.latitude_stddev
    for bad in _bad32():
        with assert_raises():
            noise.set_latitude_noise(Angle(bad), Angle(1))
        assert_equal(noise.latitude_stddev, saved)
        var raw = noise
        raw.latitude_stddev = bad
        with assert_raises():
            _ = raw.latitude_stddev_angle()
        with assert_raises():
            noise.set_latitude_noise(Angle(1), Angle(bad))
        assert_equal(noise.latitude_stddev, saved)
        raw = noise
        raw.latitude_bias = bad
        with assert_raises():
            _ = raw.latitude_bias_angle()
    with assert_raises():
        noise.set_latitude_noise(Angle(-1), Angle(0))
    noise.latitude_stddev = -1
    with assert_raises():
        _ = noise.latitude_stddev_angle()
    with assert_raises():
        noise.set_latitude_noise(Angle(3e38), Angle(0))
    with assert_raises():
        noise.set_latitude_noise(Angle(0), Angle(3e38))


def test_cam_longitude_typed_noise() raises:
    var noise = CamNoise()
    noise.set_longitude_noise(Angle(0.25), Angle(-0.0))
    assert_almost_equal(noise.longitude_stddev_angle().value, 0.25, atol=1e-7)
    assert_equal(
        bitcast[DType.uint32](noise.longitude_bias_angle().value),
        UInt32(0x80000000),
    )
    var saved = noise.longitude_stddev
    for bad in _bad32():
        with assert_raises():
            noise.set_longitude_noise(Angle(bad), Angle(1))
        assert_equal(noise.longitude_stddev, saved)
        var raw = noise
        raw.longitude_stddev = bad
        with assert_raises():
            _ = raw.longitude_stddev_angle()
        with assert_raises():
            noise.set_longitude_noise(Angle(1), Angle(bad))
        assert_equal(noise.longitude_stddev, saved)
        raw = noise
        raw.longitude_bias = bad
        with assert_raises():
            _ = raw.longitude_bias_angle()
    with assert_raises():
        noise.set_longitude_noise(Angle(-1), Angle(0))
    noise.longitude_stddev = -1
    with assert_raises():
        _ = noise.longitude_stddev_angle()
    with assert_raises():
        noise.set_longitude_noise(Angle(3e38), Angle(0))
    with assert_raises():
        noise.set_longitude_noise(Angle(0), Angle(3e38))


def test_cam_altitude_typed_noise() raises:
    var noise = CamNoise()
    noise.set_altitude_noise(Length(0.25), Length(-0.0))
    assert_almost_equal(noise.altitude_stddev_length().value, 0.25, atol=1e-7)
    assert_equal(
        bitcast[DType.uint32](noise.altitude_bias_length().value),
        UInt32(0x80000000),
    )
    var saved = noise.altitude_stddev
    for bad in _bad32():
        with assert_raises():
            noise.set_altitude_noise(Length(bad), Length(1))
        assert_equal(noise.altitude_stddev, saved)
        var raw = noise
        raw.altitude_stddev = bad
        with assert_raises():
            _ = raw.altitude_stddev_length()
        with assert_raises():
            noise.set_altitude_noise(Length(1), Length(bad))
        assert_equal(noise.altitude_stddev, saved)
        raw = noise
        raw.altitude_bias = bad
        with assert_raises():
            _ = raw.altitude_bias_length()
    with assert_raises():
        noise.set_altitude_noise(Length(-1), Length(0))
    noise.altitude_stddev = -1
    with assert_raises():
        _ = noise.altitude_stddev_length()


def test_cam_heading_typed_noise() raises:
    var noise = CamNoise()
    noise.set_heading_noise(Angle(0.25), Angle(-0.0))
    assert_almost_equal(noise.heading_stddev_angle().value, 0.25, atol=1e-7)
    assert_equal(
        bitcast[DType.uint32](noise.heading_bias_angle().value),
        UInt32(0x80000000),
    )
    var saved = noise.heading_stddev
    for bad in _bad32():
        with assert_raises():
            noise.set_heading_noise(Angle(bad), Angle(1))
        assert_equal(noise.heading_stddev, saved)
        var raw = noise
        raw.heading_stddev = bad
        with assert_raises():
            _ = raw.heading_stddev_angle()
        with assert_raises():
            noise.set_heading_noise(Angle(1), Angle(bad))
        assert_equal(noise.heading_stddev, saved)
        raw = noise
        raw.heading_bias = bad
        with assert_raises():
            _ = raw.heading_bias_angle()
    with assert_raises():
        noise.set_heading_noise(Angle(-1), Angle(0))
    noise.heading_stddev = -1
    with assert_raises():
        _ = noise.heading_stddev_angle()
    with assert_raises():
        noise.set_heading_noise(Angle(3e38), Angle(0))
    with assert_raises():
        noise.set_heading_noise(Angle(0), Angle(3e38))


def test_cam_yaw_rate_typed_noise() raises:
    var noise = CamNoise()
    noise.set_yaw_rate_noise(AngularVelocity(0.25), AngularVelocity(-0.0))
    assert_almost_equal(
        noise.yaw_rate_stddev_angular_velocity().value, 0.25, atol=1e-7
    )
    assert_equal(
        bitcast[DType.uint32](noise.yaw_rate_bias_angular_velocity().value),
        UInt32(0x80000000),
    )
    var saved = noise.yaw_rate_stddev
    for bad in _bad32():
        with assert_raises():
            noise.set_yaw_rate_noise(AngularVelocity(bad), AngularVelocity(1))
        assert_equal(noise.yaw_rate_stddev, saved)
        var raw = noise
        raw.yaw_rate_stddev = bad
        with assert_raises():
            _ = raw.yaw_rate_stddev_angular_velocity()
        with assert_raises():
            noise.set_yaw_rate_noise(AngularVelocity(1), AngularVelocity(bad))
        assert_equal(noise.yaw_rate_stddev, saved)
        raw = noise
        raw.yaw_rate_bias = bad
        with assert_raises():
            _ = raw.yaw_rate_bias_angular_velocity()
    with assert_raises():
        noise.set_yaw_rate_noise(AngularVelocity(-1), AngularVelocity(0))
    noise.yaw_rate_stddev = -1
    with assert_raises():
        _ = noise.yaw_rate_stddev_angular_velocity()


def test_cam_velocity_acceleration_precision_and_domains() raises:
    var noise = CamNoise()
    var low_bit = bitcast[DType.float32](UInt32(0x3F800001))
    noise.set_velocity_noise(Velocity(low_bit))
    assert_equal(
        bitcast[DType.uint32](noise.velocity_stddev_velocity().value),
        UInt32(0x3F800001),
    )
    noise.set_acceleration_noise(
        Acceleration(low_bit), Acceleration(1e-30), Acceleration(-0.0)
    )
    var deviations = noise.acceleration_deviations()
    assert_equal(bitcast[DType.uint32](deviations[0].value), UInt32(0x3F800001))
    assert_equal(deviations[1].value, Float32(1e-30))
    assert_equal(bitcast[DType.uint32](deviations[2].value), UInt32(0x80000000))
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
        Float32(-1),
    ]:
        with assert_raises():
            noise.set_velocity_noise(Velocity(bad))
        assert_equal(noise.velocity_stddev, low_bit)
        var raw = noise
        raw.velocity_stddev = bad
        with assert_raises():
            _ = raw.velocity_stddev_velocity()
        for component in range(3):
            var values = [Float32(1), Float32(2), Float32(3)]
            values[component] = bad
            with assert_raises():
                noise.set_acceleration_noise(
                    Acceleration(values[0]),
                    Acceleration(values[1]),
                    Acceleration(values[2]),
                )
            assert_equal(noise.acceleration_stddev.x, low_bit)
            raw.acceleration_stddev = Vector3(values[0], values[1], values[2])
            with assert_raises():
                _ = raw.acceleration_deviations()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


def test_inverse_flattening_underflow_refuses_before_update() raises:
    var ellipsoid = Ellipsoid(Length64(1e300), 300)
    var saved = ellipsoid.f_inv
    with assert_raises():
        ellipsoid.from_b_meters(1e-300)
    assert_equal(ellipsoid.f_inv, saved)


def test_link_loss_refusal_preserves_random_state() raises:
    var model = PathLossModel(PropagationParams())
    var rng = SensorRandom(42)
    var saved = rng.state
    with assert_raises():
        _ = model.loss_meters(
            LOS,
            Vector3(0, 0, 0),
            Vector3(20, 0, 0),
            20,
            0,
            0,
            List[Vector3](),
            rng,
        )
    assert_equal(rng.state, saved)
