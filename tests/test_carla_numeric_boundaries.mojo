# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA numeric boundaries: checked zones, exact norms and angle remainders."""

from extensions.carla.bounding_box import BoundingBox
from extensions.carla.geo import (
    TRANSVERSE_MERCATOR,
    UtmZone,
    parse_geo_projection_and_reference,
    parse_geo_reference,
)
from extensions.carla.math import (
    Vector3DInt,
    _wrapped_degrees,
    rotations_equal,
    transforms_equal,
)
from extensions.carla.transform import (
    CarlaRotation,
    CarlaTransform,
    _wrap_degrees,
)
from loaders.xml import parse_xml
from math.vector3 import Vector3
from std.collections import Dict
from std.ffi import external_call
from std.math import hypot, inf, isfinite, isnan, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, Angle, Length


def _rot(pitch: Float32, yaw: Float32, roll: Float32) -> CarlaRotation:
    var out = CarlaRotation(
        Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)
    )
    out.pitch = pitch
    out.yaw = yaw
    out.roll = roll
    return out


def test_utm_zone_domain_and_fractional_policy() raises:
    var texts: List[String] = [
        "1",
        "1.0000000000000002",
        "1.5",
        "31.5",
        "59.99999999999999",
        "60",
        "60.00000000000001",
        "60.5",
        "60.99999999999999",
        "31",
        "0031",
        "3.1e1",
        "310e-1",
        "31suffix",
        "31.5suffix",
    ]
    var zones: List[Int] = [
        1,
        1,
        1,
        31,
        59,
        60,
        60,
        60,
        60,
        31,
        31,
        31,
        31,
        31,
        31,
    ]
    var offsets = Dict[String, Float64]()
    for i in range(len(texts)):
        var result = parse_geo_projection_and_reference(
            "+proj=utm +zone=" + texts[i], offsets
        )
        ref p = result[0].universal_transverse_mercator
        assert_true(p.zone == UtmZone(zones[i]))
        assert_true(p.north)
        var longitude = Float64(6 * zones[i] - 183)
        assert_equal(result[1].longitude_degrees, longitude)
        # The returned reference lies on the selected zone's central meridian.
        var point = result[0].geo_location_to_transform(result[1])
        assert_equal(point.x, Float32(500000))
        assert_equal(point.y, Float32(0))
        var roundtrip = result[0].transform_to_geo_location(point)
        assert_true(abs(roundtrip.longitude_degrees - longitude) < 1e-12)
    var missing = parse_geo_projection_and_reference("+proj=utm", offsets)
    assert_true(missing[0].universal_transverse_mercator.zone == UtmZone(31))
    assert_equal(missing[1].longitude_degrees, Float64(0))
    var unknown = parse_geo_projection_and_reference(
        "+proj=unknown +zone=inf", offsets
    )
    assert_true(unknown[0].projection_type == TRANSVERSE_MERCATOR)
    var no_proj = parse_geo_projection_and_reference(
        "+zone=4294967297", offsets
    )
    assert_true(no_proj[0].projection_type == TRANSVERSE_MERCATOR)
    # The last duplicate parameter still wins.
    var duplicate = parse_geo_projection_and_reference(
        "+proj=utm +zone=4294967297 +zone=60.5", offsets
    )
    assert_true(duplicate[0].universal_transverse_mercator.zone == UtmZone(60))
    var document = parse_xml(
        "<OpenDRIVE><header><geoReference>+proj=utm +zone=1.5"
        " +south</geoReference></header></OpenDRIVE>"
    )
    var parsed = parse_geo_reference(document)
    assert_true(parsed[0].universal_transverse_mercator.zone == UtmZone(1))
    assert_false(parsed[0].universal_transverse_mercator.north)
    assert_equal(parsed[1].longitude_degrees, Float64(-177))


def test_utm_rejects_before_narrowing() raises:
    var invalid: List[String] = [
        "-1",
        "-0",
        "0",
        "0.5",
        "0.9999999999999999",
        "61",
        "61.00000000000001",
        "2147483647",
        "2147483648",
        "-2147483648",
        "-2147483649",
        "4294967296",
        "4294967297",
        "4294967356",
        "4294967357",
        "8589934593",
        "-4294967295",
        "-4294967236",
        "-4294967235",
        "9223372036854775807",
        "-9223372036854775808",
        "1e300",
        "-1e300",
        "inf",
        "Infinity",
        "-inf",
        "nan",
        "-NaN",
        "1e3",
        "31e-3",
    ]
    var offsets = Dict[String, Float64]()
    for text in invalid:
        with assert_raises(contains="UTM zone"):
            _ = parse_geo_projection_and_reference(
                "+proj=utm +zone=" + text, offsets
            )
    var text_cases: List[String] = [
        "",
        "north",
        "+31",
        "+Infinity",
        "1e999",
        "-1e999",
        "1e-999",
    ]
    for text in text_cases:
        with assert_raises():
            _ = parse_geo_projection_and_reference(
                "+proj=utm +zone=" + text, offsets
            )
    with assert_raises(contains="UTM zone"):
        _ = parse_geo_reference(
            parse_xml(
                "<OpenDRIVE><header><geoReference>+proj=utm"
                " +zone=4294967297</geoReference></header></OpenDRIVE>"
            )
        )


def test_integer_norm_full_domain() raises:
    # Independently computed exact squares of the components and neighbors.
    var values: List[Int32] = [
        -2147483648,
        -2147483647,
        -1,
        0,
        1,
        2147483646,
        2147483647,
    ]
    var squares: List[UInt64] = [
        4611686018427387904,
        4611686014132420609,
        1,
        0,
        1,
        4611686009837453316,
        4611686014132420609,
    ]
    for i in range(len(values)):
        for j in range(len(values)):
            for k in range(len(values)):
                var vector = Vector3DInt(values[i], values[j], values[k])
                var squared = vector.squared_length()
                comptime assert type_of(squared) == UInt64
                assert_equal(squared, squares[i] + squares[j] + squares[k])
                var length = vector.length()
                comptime assert type_of(length) == Float64
                assert_true(isfinite(length))
                assert_true(length >= 0)
                # Independent scaled libm hypot; allow its two rounding steps too.
                var xy = hypot(Float64(values[i]), Float64(values[j]))
                var reference = hypot(xy, Float64(values[k]))
                assert_true(
                    abs(length - reference) <= reference * 8.881784197001252e-16
                )
    assert_equal(Vector3DInt(0, 0, 0).length(), Float64(0))
    assert_equal(Vector3DInt(3, -4, 12).length(), Float64(13))
    assert_equal(Vector3DInt(-2147483648, 0, 0).length(), Float64(2147483648))
    assert_equal(Vector3DInt(2147483647, 0, 0).length(), Float64(2147483647))
    # Decimal square roots computed to 80 digits from exact integer sums.
    var min_two = Vector3DInt(-2147483648, -2147483648, 0).length()
    var max_two = Vector3DInt(2147483647, 2147483647, 0).length()
    var min_three = Vector3DInt(-2147483648, -2147483648, -2147483648).length()
    var max_three = Vector3DInt(2147483647, 2147483647, 2147483647).length()
    assert_true(
        abs(min_two - 3037000499.976049692451388530026308346745)
        <= 3037000499.97605 * 4.440892098500626e-16
    )
    assert_true(
        abs(max_two - 3037000498.561836130078293481224619622535)
        <= 3037000498.56184 * 4.440892098500626e-16
    )
    assert_true(
        abs(min_three - 3719550786.759358621568687257581284603984)
        <= 3719550786.75936 * 4.440892098500626e-16
    )
    assert_true(
        abs(max_three - 3719550785.027307813999809964053838262478)
        <= 3719550785.02731 * 4.440892098500626e-16
    )


def _check_remainder(angle: Float32) raises:
    # Widen first and use the Float64 library remainder as the oracle.
    var reference = external_call["fmod", Float64](Float64(angle), Float64(360))
    if reference < -180:
        reference += 360
    if reference >= 180:
        reference -= 360
    var expected = Float32(reference)
    var actual = _wrap_degrees(angle)
    assert_true(actual >= -180 and actual < 180)
    assert_equal(bitcast[DType.uint32](actual), bitcast[DType.uint32](expected))
    assert_equal(
        bitcast[DType.uint32](_wrapped_degrees(angle)),
        bitcast[DType.uint32](expected),
    )
    var rotation = _rot(angle, angle, angle)
    var normalized = rotation.normalized()
    assert_equal(
        bitcast[DType.uint32](normalized.pitch), bitcast[DType.uint32](expected)
    )
    assert_equal(
        bitcast[DType.uint32](normalized.yaw), bitcast[DType.uint32](expected)
    )
    assert_equal(
        bitcast[DType.uint32](normalized.roll), bitcast[DType.uint32](expected)
    )
    assert_true(rotations_equal(rotation, _rot(expected, expected, expected)))
    assert_true(rotations_equal(rotation, normalized))


def test_angle_remainders_and_neighbors() raises:
    assert_equal(_wrap_degrees(Float32(1e10)), Float32(-80))
    assert_equal(_wrap_degrees(Float32(-1e10)), Float32(80))
    # Every finite exponent, with endpoint and interior significands, both signs.
    for exponent in range(255):
        var mantissa_cases: List[UInt32] = [0, 1, 0x3FFFFF, 0x7FFFFE, 0x7FFFFF]
        for mantissa in mantissa_cases:
            var bits = UInt32(exponent) << 23 | mantissa
            _check_remainder(bitcast[DType.float32](bits))
            _check_remainder(bitcast[DType.float32](bits | 0x80000000))
    var center_cases: List[Float32] = [180, 360, 540, 720, 1e10]
    for center in center_cases:
        var bits = bitcast[DType.uint32](center)
        for delta in range(-1, 2):
            var neighbor = UInt32(Int64(bits) + Int64(delta))
            _check_remainder(bitcast[DType.float32](neighbor))
            _check_remainder(bitcast[DType.float32](neighbor | 0x80000000))
    var angle_cases: List[Float32] = [
        0,
        -0.0,
        1,
        -1,
        45.5,
        -45.5,
        179.5,
        -179.5,
        180,
        -180,
        360,
        -360,
    ]
    for angle in angle_cases:
        _check_remainder(angle)
    assert_true(rotations_equal(_rot(180, -180, 540), _rot(-180, 180, -540)))
    assert_true(rotations_equal(_rot(-0.0, -360, 720), _rot(0, 0, -0.0)))
    for axis in range(3):
        var large = _rot(0, 0, 0)
        var small = large
        if axis == 0:
            large.pitch = 1e10
            small.pitch = -80
        elif axis == 1:
            large.yaw = 1e10
            small.yaw = -80
        else:
            large.roll = 1e10
            small.roll = -80
        assert_true(rotations_equal(large, small))
        assert_false(rotations_equal(large, _rot(0, 0, 0)))
        var a = CarlaTransform(
            Length(0, METER), Length(0, METER), Length(0, METER), large
        )
        var b = CarlaTransform(
            Length(0, METER), Length(0, METER), Length(0, METER), small
        )
        assert_true(transforms_equal(a, b))
        var box_a = BoundingBox(Vector3(0, 0, 0), Vector3(1, 1, 1), large)
        var box_b = BoundingBox(Vector3(0, 0, 0), Vector3(1, 1, 1), small)
        assert_true(box_a == box_b)
        box_b.rotation = _rot(0, 0, 0)
        assert_false(box_a == box_b)


def test_nonfinite_rotations_never_compare_equal() raises:
    var angle_cases: List[Float32] = [
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
        bitcast[DType.float32](UInt32(0xFFC00001)),
    ]
    for angle in angle_cases:
        assert_true(isnan(_wrap_degrees(angle)))
        assert_true(isnan(_wrapped_degrees(angle)))
        var all = _rot(angle, angle, angle).normalized()
        assert_true(isnan(all.pitch))
        assert_true(isnan(all.yaw))
        assert_true(isnan(all.roll))
        for axis in range(3):
            var invalid = _rot(0, 0, 0)
            if axis == 0:
                invalid.pitch = angle
            elif axis == 1:
                invalid.yaw = angle
            else:
                invalid.roll = angle
            assert_false(rotations_equal(invalid, invalid))
            assert_false(rotations_equal(invalid, _rot(0, 0, 0)))
            assert_false(rotations_equal(_rot(0, 0, 0), invalid))
            var t = CarlaTransform(
                Length(0, METER), Length(0, METER), Length(0, METER), invalid
            )
            assert_false(transforms_equal(t, t))
            var box = BoundingBox(Vector3(0, 0, 0), Vector3(1, 1, 1), invalid)
            assert_false(box == box)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
