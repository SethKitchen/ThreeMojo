# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact ratios and widened independent controls for norm consumers."""

from geometries.tube_painter import TubePainter
from math.bounds import Plane
from math.matrix2 import Box2
from math.ray import Ray
from math.space_curve import Point3, length3, normalized3, point3
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import inf, isfinite, isnan, nan, pi, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import RADIAN


def test_space_curve_directions_cover_binary_exponents() raises:
    var values: List[Float64] = [
        bitcast[DType.float64](UInt64(1)),
        bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF)),
    ]
    for exponent in range(1, 2047):
        values.append(bitcast[DType.float64](UInt64(exponent) << 52))
    for scale in values:
        var unit = normalized3(point3(scale, -scale, scale))
        # Independent symmetry: each squared component must be one third.
        assert_almost_equal(
            unit[0], Float64(0.57735026918962576451), atol=1e-14
        )
        assert_equal(unit[1], -unit[0])
        assert_equal(unit[2], unit[0])
        assert_equal(unit[3], Float64(0))
    for scale in [Float64(1e-200), Float64(1), Float64(1e200)]:
        var point = point3(2 * scale, -3 * scale, 6 * scale)
        var unit = normalized3(point)
        assert_almost_equal(length3(point) / scale, Float64(7), atol=1e-14)
        assert_almost_equal(unit[0], Float64(2.0 / 7), atol=1e-14)
        assert_almost_equal(unit[1], Float64(-3.0 / 7), atol=1e-14)
        assert_almost_equal(unit[2], Float64(6.0 / 7), atol=1e-14)
    var mixed = normalized3(point3(1e308, 1, 1e-308))
    assert_equal(mixed[0], Float64(1))
    assert_true(mixed[1] > 0)
    assert_equal(mixed[2], Float64(0))


def test_space_curve_keeps_ordinary_and_nonfinite_arithmetic() raises:
    var point = point3(1.25, -2.5, 3.75)
    var inverse = 1 / sqrt(
        point[0] * point[0] + point[1] * point[1] + point[2] * point[2]
    )
    var unit = normalized3(point)
    for axis in range(4):
        assert_equal(unit[axis], point[axis] * inverse)
    var zero = normalized3(Point3(-0.0, 0.0, -0.0, -0.0))
    assert_equal(bitcast[DType.uint64](zero[0]), UInt64(0x8000000000000000))
    assert_equal(bitcast[DType.uint64](zero[2]), UInt64(0x8000000000000000))
    assert_equal(bitcast[DType.uint64](zero[3]), UInt64(0x8000000000000000))
    var infinite = inf[DType.float64]()
    for point in [
        point3(infinite, 2, 3),
        point3(2, infinite, 3),
        point3(2, 3, infinite),
    ]:
        var got = normalized3(point)
        for axis in range(3):
            if isfinite(point[axis]):
                assert_equal(got[axis], Float64(0))
            else:
                assert_true(isnan(got[axis]))
    var invalid = normalized3(point3(nan[DType.float64](), 2, 3))
    for axis in range(4):
        assert_true(isnan(invalid[axis]))


def test_plane_normal_and_constant_share_a_safe_divisor() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    for scale in [
        tiny,
        Float32(1e-30),
        Float32(1),
        Float32(1e30),
        Float32(3e38),
    ]:
        var plane = Plane(Vector3(scale, -scale, 0), -scale)
        assert_almost_equal(
            plane.normal.x, Float32(0.70710678118654752440), atol=1e-6
        )
        assert_equal(plane.normal.y, -plane.normal.x)
        assert_equal(plane.normal.z, Float32(0))
        assert_almost_equal(
            plane.constant, Float32(-0.70710678118654752440), atol=1e-6
        )
    var unrepresentable = Plane(Vector3(tiny, 0, 0), 1)
    assert_true(unrepresentable.normal == Vector3(1, 0, 0))
    assert_equal(unrepresentable.constant, inf[DType.float32]())
    with assert_raises():
        _ = Plane(Vector3(0, 0, 0), 1)
    var invalid = Plane(Vector3(nan[DType.float32](), 1, 2), 3)
    assert_true(isnan(invalid.normal.x))
    assert_true(isnan(invalid.normal.y))
    assert_true(isnan(invalid.constant))


def test_plane_point_constant_avoids_intermediate_range_loss() raises:
    # The raw dot rounds to zero, but the normalized constant is representable.
    var tiny = Plane.from_normal_and_point(
        Vector3(1e-10, 0, 0), Vector3(1e-36, 0, 0)
    )
    assert_equal(tiny.constant, Float32(-1e-36))
    # Products overflow before cancelling, while the final constant is zero.
    var cancelled = Plane.from_normal_and_point(
        Vector3(3e38, 3e38, 0), Vector3(2, -2, 0)
    )
    assert_equal(cancelled.constant, Float32(0))
    # One residual product survives cancellation in a third component.
    var normal = Vector3(1e30, 1e30, 1)
    var point = Vector3(1e10, -1e10, 2)
    var plane = Plane.from_normal_and_point(normal, point)
    var norm = sqrt(
        Float64(normal.x) * Float64(normal.x)
        + Float64(normal.y) * Float64(normal.y)
        + 1
    )
    assert_almost_equal(Float64(plane.constant) * norm, Float64(-2), atol=1e-6)
    var a = Float32(1e20)
    for axis in range(3):
        var n = Vector3(a, 1, -a)
        var p = Vector3(a, 1, a)
        if axis == 1:
            n = Vector3(1, -a, a)
            p = Vector3(1, a, a)
        elif axis == 2:
            n = Vector3(-a, a, 1)
            p = Vector3(a, a, 1)
        var kept = Plane.from_normal_and_point(n, p)
        # Products are exact in Float64, but their sum needs an expansion.
        # The exact stored-input dot is one in every component order.
        assert_almost_equal(
            Float64(kept.constant) * Float64(a),
            Float64(-0.70710678118654752440),
            atol=1e-7,
        )
    var small_a = Float32(1e10)
    var ordinary_cancel = Plane.from_normal_and_point(
        Vector3(small_a, 1, -small_a), Vector3(small_a, 1, small_a)
    )
    assert_almost_equal(
        Float64(ordinary_cancel.constant) * Float64(small_a),
        Float64(-0.70710678118654752440),
        atol=1e-7,
    )
    var ordinary = Plane.from_normal_and_point(
        Vector3(0, 3, 0), Vector3(1, 2, 3)
    )
    assert_equal(ordinary.constant, Float32(-2))


def test_plane_constant_near_cancellation_and_representable_limit() raises:
    var cancelled = Plane.from_normal_and_point(
        Vector3(1, 1, 1), Vector3(1, -1, 1e-7)
    )
    assert_almost_equal(
        Float64(cancelled.constant) / Float64(Float32(1e-7)),
        Float64(-0.57735026918962576451),
        atol=1e-7,
    )
    var plane = Plane.from_normal_and_point(
        Vector3(0.1810031235218048, 0.474552184343338, 0.30779924988746643),
        Vector3(
            1.037101667208097e38, 2.7190628738269835e38, 1.7636110888398267e38
        ),
    )
    assert_true(isfinite(plane.constant))
    assert_equal(plane.constant, -bitcast[DType.float32](UInt32(0x7F7FFFFE)))


def test_plane_point_constant_limit_bit_neighbors() raises:
    var expected = [
        UInt32(0x7F7FFFFD),
        UInt32(0x7F7FFFFD),
        UInt32(0x7F7FFFFE),
        UInt32(0x7F7FFFFF),
        UInt32(0x7F800000),
        UInt32(0x7F800000),
        UInt32(0x7F800000),
    ]
    for offset in range(-3, 4):
        var plane = Plane.from_normal_and_point(
            Vector3(0.125, 0.125, 0.1875),
            Vector3(
                bitcast[DType.float32](UInt32(0x7EF85B41)),
                bitcast[DType.float32](UInt32(0x7EF85B41)),
                bitcast[DType.float32](UInt32(0x7F3A4471 + offset)),
            ),
        )
        # Exact Float32 input products divided by sqrt(17)/16, evaluated
        # independently at 150 Decimal digits before the Float32 rounding.
        assert_equal(
            bitcast[DType.uint32](-plane.constant), expected[offset + 3]
        )
    var recovered = Plane(
        Vector3(0.05, 0.25, 0.1), bitcast[DType.float32](UInt32(0x7E8C378B))
    )
    assert_equal(recovered.constant, bitcast[DType.float32](UInt32(0x7F7FFFFF)))
    var overflow = Plane(
        Vector3(0.1, 0.15, 0.05), bitcast[DType.float32](UInt32(0x7E3F92A7))
    )
    assert_equal(overflow.constant, inf[DType.float32]())
    var infinite = Plane(Vector3(0.125, 0.125, 0.1875), inf[DType.float32]())
    assert_equal(infinite.constant, inf[DType.float32]())
    var impossible = Plane(Vector3(0.125, 0.125, 0.1875), 3e38)
    assert_equal(impossible.constant, inf[DType.float32]())


def test_plane_point_nonfinite_factors_keep_ieee_results() raises:
    for axis in range(3):
        var normal = Vector3(1, 2, 3)
        normal.set_component(axis, nan[DType.float32]())
        var plane = Plane.from_normal_and_point(normal, Vector3(4, 5, 6))
        assert_true(isnan(plane.constant))
        var point = Vector3(4, 5, 6)
        point.set_component(axis, nan[DType.float32]())
        plane = Plane.from_normal_and_point(Vector3(1, 2, 3), point)
        assert_true(isnan(plane.constant))


def test_plane_infinite_factors_and_signed_zero_constant() raises:
    for axis in range(3):
        var normal = Vector3(1, 2, 3)
        normal.set_component(axis, inf[DType.float32]())
        var plane = Plane(normal, 2)
        assert_true(isnan(plane.normal.get_component(axis)))
        assert_equal(plane.constant, Float32(0))
        plane = Plane.from_normal_and_point(normal, Vector3(4, 5, 6))
        assert_true(isnan(plane.constant))
        var point = Vector3(4, 5, 6)
        point.set_component(axis, inf[DType.float32]())
        plane = Plane.from_normal_and_point(Vector3(1, 2, 3), point)
        assert_equal(plane.constant, -inf[DType.float32]())
    var zero = Plane(Vector3(3e38, 3e38, -0.0), -0.0)
    assert_equal(bitcast[DType.uint32](zero.normal.z), UInt32(0x80000000))
    assert_equal(bitcast[DType.uint32](zero.constant), UInt32(0x80000000))


def test_ray_look_at_widens_before_subtraction() raises:
    var ray = Ray(Vector3(-3e38, 0, 0), Vector3(1, 0, 0))
    ray.look_at(Vector3(3e38, 3e38, 0))
    assert_almost_equal(
        ray.direction.x, Float32(0.89442719099991587856), atol=1e-6
    )
    assert_almost_equal(
        ray.direction.y, Float32(0.44721359549995793928), atol=1e-6
    )
    assert_equal(ray.direction.z, Float32(0))
    var tiny = bitcast[DType.float32](UInt32(1))
    ray = Ray(Vector3(0, 0, 0), Vector3(tiny, tiny, 0))
    ray.look_at(Vector3(tiny, -tiny, 0))
    assert_almost_equal(
        ray.direction.x, Float32(0.70710678118654752440), atol=1e-6
    )
    assert_equal(ray.direction.y, -ray.direction.x)
    ray.look_at(Vector3(3, 4, 0))
    assert_almost_equal(ray.direction.x, Float32(0.6), atol=1e-6)
    assert_almost_equal(ray.direction.y, Float32(0.8), atol=1e-6)
    with assert_raises():
        ray.look_at(Vector3(0, 0, 0))


def test_ray_nonfinite_points_keep_existing_normalization_rules() raises:
    for axis in range(3):
        for invalid in [inf[DType.float32](), nan[DType.float32]()]:
            var point = Vector3(2, 3, 4)
            point.set_component(axis, invalid)
            var ray = Ray(Vector3(0, 0, 0), Vector3(1, 0, 0))
            ray.look_at(point)
            assert_true(isnan(ray.direction.get_component(axis)))
            var other_axis = (axis + 1) % 3
            var expected = point.get_component(other_axis) if isnan(
                invalid
            ) else Float32(0)
            assert_equal(ray.direction.get_component(other_axis), expected)
            ray = Ray(point, Vector3(1, 0, 0))
            ray.look_at(Vector3(0, 0, 0))
            assert_true(isnan(ray.direction.get_component(axis)))
            assert_equal(ray.direction.get_component(other_axis), -expected)


def test_box2_distances_keep_extreme_finite_gaps() raises:
    var box = Box2(Vector2(0, 0), Vector2(0, 0))
    for scale in [Float32(1e-30), Float32(1), Float32(1e30)]:
        assert_almost_equal(
            box.distance_to_point(Vector2(3 * scale, 4 * scale)) / scale,
            Float32(5),
            atol=1e-6,
        )
    var tiny = bitcast[DType.float32](UInt32(1))
    assert_equal(box.distance_to_point(Vector2(tiny, 0)), tiny)
    box = Box2(Vector2(-3e38, 0), Vector2(-3e38, 0))
    assert_equal(box.distance_to_point(Vector2(3e38, 0)), inf[DType.float32]())


def test_tube_painter_keeps_nonzero_subnormal_strokes() raises:
    var painter = TubePainter()
    painter.line_to(Vector3(bitcast[DType.float32](UInt32(1)), 0, 0))
    assert_true(painter.count() > 0)
    var count = painter.count()
    painter.line_to(Vector3(bitcast[DType.float32](UInt32(1)), 0, 0))
    assert_equal(painter.count(), count)


def test_vector2_zero_angle_obeys_signed_atan2() raises:
    assert_equal(Vector2(0.0, 0.0).angle().to(RADIAN), Float32(0))
    assert_equal(Vector2(-0.0, -0.0).angle().to(RADIAN), Float32(pi))
    assert_equal(Vector2(-0.0, 0.0).angle().to(RADIAN), Float32(pi))
    assert_equal(Vector2(0.0, -0.0).angle().to(RADIAN), 2 * Float32(pi))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
