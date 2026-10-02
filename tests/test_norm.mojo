# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent norm and direction oracles across both scalar ranges."""

from math.norm import (
    length2,
    length3,
    length4,
    normalized2,
    normalized3,
    normalized4,
)
from math.quaternion import Quaternion
from math.spherical import Cylindrical, Spherical
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.vector4 import Vector4
from std.math import inf, isfinite, isnan, nan, pi, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import RADIAN


def test_float32_normalization_across_all_binary_exponents() raises:
    # Every normal exponent, plus the smallest subnormal and largest finite.
    var values: List[Float32] = [
        bitcast[DType.float32](UInt32(1)),
        bitcast[DType.float32](UInt32(0x7F7FFFFF)),
    ]
    for exponent in range(1, 255):
        values.append(bitcast[DType.float32](UInt32(exponent) << 23))
    for s in values:
        var n2 = normalized2(s, -s)
        var n3 = normalized3(s, -s, s)
        var n4 = normalized4(s, -s, s, -s)
        assert_almost_equal(n2[0], Float32(1 / sqrt(Float64(2))), atol=1e-6)
        assert_equal(n2[1], -n2[0])
        assert_almost_equal(n3[0], Float32(1 / sqrt(Float64(3))), atol=1e-6)
        assert_equal(n3[1], -n3[0])
        assert_equal(n3[2], n3[0])
        assert_equal(n4[0], Float32(0.5))
        assert_equal(n4[1], Float32(-0.5))
        assert_equal(n4[2], Float32(0.5))
        assert_equal(n4[3], Float32(-0.5))


def test_float64_helpers_preserve_precision_at_extremes() raises:
    var values: List[Float64] = [
        bitcast[DType.float64](UInt64(1)),
        1e-310,
        1e-200,
        1,
        1e200,
        1e308,
    ]
    for exponent in range(1, 2047):
        values.append(bitcast[DType.float64](UInt64(exponent) << 52))
    for s in values:
        var n2 = normalized2(s, -s)
        var n3 = normalized3(s, -s, s)
        var n4 = normalized4(s, -s, s, -s)
        assert_almost_equal(n2[0], 1 / sqrt(Float64(2)), atol=1e-14)
        assert_equal(n2[1], -n2[0])
        assert_almost_equal(n3[0], 1 / sqrt(Float64(3)), atol=1e-14)
        assert_equal(n3[1], -n3[0])
        assert_equal(n3[2], n3[0])
        assert_equal(n4[0], Float64(0.5))
        assert_equal(n4[1], Float64(-0.5))
    assert_almost_equal(
        length2(Float64(3e200), Float64(4e200)) / 1e200, 5, atol=1e-14
    )
    assert_almost_equal(
        length3(Float64(2e-200), Float64(3e-200), Float64(6e-200)) / 1e-200,
        7,
        atol=1e-14,
    )
    assert_almost_equal(
        length4(Float64(1e200), Float64(2e200), Float64(2e200), Float64(4e200))
        / 1e200,
        5,
        atol=1e-14,
    )


def test_lengths_remain_representable_after_square_overflow_or_underflow() raises:
    for s in [Float32(1e-30), Float32(1e30)]:
        assert_almost_equal(length2(3 * s, 4 * s) / s, Float32(5), atol=1e-6)
        assert_almost_equal(
            length3(2 * s, 3 * s, 6 * s) / s, Float32(7), atol=1e-6
        )
        assert_almost_equal(
            length4(s, 2 * s, 2 * s, 4 * s) / s, Float32(5), atol=1e-6
        )
    assert_equal(length2(Float32(3e38), Float32(3e38)), inf[DType.float32]())
    assert_equal(length2(Float32(0), Float32(0)), Float32(0))
    assert_almost_equal(
        Vector2(3e-30, 4e-30).distance_to(Vector2(0, 0)) / 1e-30,
        Float32(5),
        atol=1e-6,
    )
    assert_almost_equal(
        Vector3(2e30, 3e30, 6e30).distance_to(Vector3(0, 0, 0)) / 1e30,
        Float32(7),
        atol=1e-6,
    )
    assert_true(isnan(length2(nan[DType.float32](), Float32(1))))


def test_zero_and_nonfinite_helper_rules_are_explicit() raises:
    var zero = Float32(0)
    var infinite = inf[DType.float32]()
    var invalid = nan[DType.float32]()
    assert_equal(length2(zero, zero), zero)
    assert_equal(length3(zero, zero, zero), zero)
    assert_equal(length4(zero, zero, zero, zero), zero)
    assert_equal(length2(infinite, zero), infinite)
    assert_equal(length3(infinite, zero, zero), infinite)
    assert_equal(length4(infinite, zero, zero, zero), infinite)
    assert_true(isnan(length3(invalid, zero, zero)))
    assert_true(isnan(length4(invalid, zero, zero, zero)))
    assert_equal(normalized2(zero, zero)[0], zero)
    assert_equal(normalized3(zero, zero, zero)[0], zero)
    assert_equal(normalized4(zero, zero, zero, zero)[0], zero)
    var n2 = normalized2(infinite, zero)
    var n3 = normalized3(infinite, zero, zero)
    var n4 = normalized4(infinite, zero, zero, zero)
    assert_true(isnan(n2[0]) and isnan(n3[0]) and isnan(n4[0]))
    assert_equal(n2[1], zero)
    assert_equal(n3[2], zero)
    assert_equal(n4[3], zero)
    n2 = normalized2(invalid, Float32(2))
    n4 = normalized4(invalid, Float32(2), Float32(3), Float32(4))
    assert_true(isnan(n2[0]) and isnan(n4[0]))
    assert_equal(n2[1], Float32(2))
    assert_equal(n4[3], Float32(4))


def test_ordinary_lengths_and_components_keep_direct_arithmetic() raises:
    for s in [Float32(0.001), Float32(1), Float32(123.45)]:
        var x = s
        var y = 2 * s
        var z = -3 * s
        var w = 4 * s
        var direct2 = sqrt(x * x + y * y)
        var direct3 = sqrt(x * x + y * y + z * z)
        var direct4 = sqrt(x * x + y * y + z * z + w * w)
        assert_equal(length2(x, y), direct2)
        assert_equal(length3(x, y, z), direct3)
        assert_equal(length4(x, y, z, w), direct4)
        assert_equal(normalized2(x, y)[0], x / direct2)
        assert_equal(normalized3(x, y, z)[1], y / direct3)
        assert_equal(normalized4(x, y, z, w)[3], w / direct4)


def test_vector_and_quaternion_normalization_keep_directions() raises:
    for s in [
        bitcast[DType.float32](UInt32(1)),
        Float32(1e-30),
        Float32(1e30),
        Float32(3e38),
    ]:
        var a = Vector2(s, -s)
        var b = Vector3(s, -s, s)
        var c = Vector4(s, -s, s, -s)
        var q = Quaternion(s, -s, s, -s)
        a.normalize()
        b.normalize()
        c.normalize()
        q.normalize()
        assert_almost_equal(a.length(), Float32(1), atol=1e-6)
        assert_almost_equal(b.length(), Float32(1), atol=1e-6)
        assert_true(c == Vector4(0.5, -0.5, 0.5, -0.5))
        assert_true(q == Quaternion(0.5, -0.5, 0.5, -0.5))
    var q = Quaternion(0, 0, 0, 0)
    q.normalize()
    assert_true(q == Quaternion.identity())
    q = Quaternion(nan[DType.float32](), 1, 2, 3)
    q.normalize()
    assert_true(isnan(q.x) and isnan(q.y) and isnan(q.z) and isnan(q.w))
    var zero = normalized4(Float32(-0.0), Float32(0), Float32(0), Float32(0))
    assert_equal(bitcast[DType.uint32](zero[0]), UInt32(0x80000000))
    var invalid = normalized3(nan[DType.float32](), Float32(2), Float32(3))
    assert_true(isnan(invalid[0]))
    assert_equal(invalid[1], Float32(2))


def test_vector_angles_and_clamped_lengths_are_scale_independent() raises:
    for s in [
        bitcast[DType.float32](UInt32(1)),
        Float32(1e-30),
        Float32(1e10),
        Float32(1e30),
        Float32(3e38),
    ]:
        var a = Vector2(s, 0)
        var b = Vector3(s, 0, 0)
        assert_equal(a.angle_to(a).to(RADIAN), Float32(0))
        assert_equal(b.angle_to(b).to(RADIAN), Float32(0))
        assert_almost_equal(a.angle_to(-a).to(RADIAN), Float32(pi), atol=1e-6)
        assert_almost_equal(
            b.angle_to(Vector3(0, s, 0)).to(RADIAN), Float32(pi / 2), atol=1e-6
        )
        a.clamp_length(2, 2)
        b.clamp_length(2, 2)
        var c = Vector4(s, 0, 0, 0)
        c.clamp_length(2, 2)
        assert_true(a == Vector2(2, 0))
        assert_true(b == Vector3(2, 0, 0))
        assert_true(c == Vector4(2, 0, 0, 0))
    assert_almost_equal(
        Vector3(0, 0, 0).angle_to(Vector3(1, 0, 0)).to(RADIAN),
        Float32(pi / 2),
        atol=1e-6,
    )


def test_coordinate_conversions_keep_extreme_radii_and_angles() raises:
    for s in [Float32(1e-30), Float32(1e30)]:
        var spherical = Spherical.from_vector3(Vector3(s, s, 0))
        assert_almost_equal(
            spherical.radius / s, Float32(sqrt(Float64(2))), atol=1e-6
        )
        assert_almost_equal(
            spherical.phi.to(RADIAN), Float32(pi / 4), atol=1e-6
        )
        var cylindrical = Cylindrical.from_vector3(Vector3(3 * s, 7, 4 * s))
        assert_almost_equal(cylindrical.radius / s, Float32(5), atol=1e-6)
    var spherical = Spherical.from_vector3(Vector3(3e38, 3e38, 0))
    assert_equal(spherical.radius, inf[DType.float32]())
    assert_almost_equal(spherical.phi.to(RADIAN), Float32(pi / 4), atol=1e-6)


def test_zero_vector_angles_are_symmetric_at_every_scale() raises:
    for scale in [Float32(1), Float32(1e-30), Float32(1e30)]:
        var zero2 = Vector2(0, 0)
        var axis2 = Vector2(scale, 0)
        var zero3 = Vector3(0, 0, 0)
        var axis3 = Vector3(scale, 0, 0)
        for angle in [
            zero2.angle_to(axis2).to(RADIAN),
            axis2.angle_to(zero2).to(RADIAN),
            zero3.angle_to(axis3).to(RADIAN),
            axis3.angle_to(zero3).to(RADIAN),
        ]:
            assert_true(isfinite(angle))
            assert_almost_equal(angle, Float32(pi / 2), atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
