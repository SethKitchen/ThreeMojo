# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the three.js `Vector3` and `Vector2` members in
`math.vector3` and `math.vector2`.

The expected numbers come from three.js 0.180, run in node on the same
inputs.
"""

from math.euler import Euler, YXZ
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4, compose, translation
from math.quaternion import Quaternion
from math.utils import SeededRandom
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import inf, isnan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, RADIAN

comptime TOLERANCE = Float64(2e-5)


def assert_vector(got: Vector3, x: Float64, y: Float64, z: Float64) raises:
    """Assert a vector matches three components, within tolerance.

    Args:
        got: The vector to check.
        x: Expected x.
        y: Expected y.
        z: Expected z.

    Raises:
        Error: If a component differs.
    """
    assert_almost_equal(Float64(got.x), x, atol=TOLERANCE)
    assert_almost_equal(Float64(got.y), y, atol=TOLERANCE)
    assert_almost_equal(Float64(got.z), z, atol=TOLERANCE)


def assert_vector2(got: Vector2, x: Float64, y: Float64) raises:
    """Assert a 2D vector matches two components, within tolerance.

    Args:
        got: The vector to check.
        x: Expected x.
        y: Expected y.

    Raises:
        Error: If a component differs.
    """
    assert_almost_equal(Float64(got.x), x, atol=TOLERANCE)
    assert_almost_equal(Float64(got.y), y, atol=TOLERANCE)


def a() -> Vector3:
    """Return the first vector the node run used."""
    return Vector3(1, -2, 3)


def b() -> Vector3:
    """Return the second vector the node run used."""
    return Vector3(-4, 5.5, 0.25)


def placed() raises -> Matrix4:
    """Return three.js's `compose((1, 2, 3), q, (2, 3, 0.5))`, with `q` a
    turn of 0.7 radians about (1, 1, 0)."""
    var axis = Vector3(1, 1, 0)
    axis.normalize()
    return compose(
        Vector3(1, 2, 3),
        Quaternion.from_axis_angle(axis, Angle(0.7, RADIAN)),
        Vector3(2, 3, 0.5),
    )


# --- Vector3 ---------------------------------------------------------------


def test_distances() raises:
    assert_almost_equal(
        Float64(a().distance_to(b())), 9.424038412485382, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(a().distance_to_squared(b())), 88.8125, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(a().manhattan_distance_to(b())), 15.25, atol=TOLERANCE
    )
    assert_equal(a().length_sq(), Float32(14))
    assert_equal(a().manhattan_length(), Float32(6))


def test_angle_to() raises:
    assert_almost_equal(
        Float64(a().angle_to(b()).value), 2.164736760276356, atol=TOLERANCE
    )
    # A zero vector has no direction: three.js answers a right angle.
    assert_almost_equal(
        Float64(Vector3(0, 0, 0).angle_to(a()).value),
        1.5707963267948966,
        atol=TOLERANCE,
    )
    # Parallel vectors round past one; the cosine is clamped.
    assert_almost_equal(
        Float64(Vector3(1, 1, 1).angle_to(Vector3(3, 3, 3)).value),
        0,
        atol=1e-3,
    )


def test_equals() raises:
    assert_true(a() == Vector3(1, -2, 3))
    assert_false(a() == Vector3(0, -2, 3))
    assert_false(a() == Vector3(1, 0, 3))
    assert_false(a() == Vector3(1, -2, 0))
    assert_true(a() != b())
    assert_false(a() != a())


def test_components() raises:
    var v = a()
    assert_equal(v.get_component(0), Float32(1))
    assert_equal(v.get_component(1), Float32(-2))
    assert_equal(v.get_component(2), Float32(3))
    with assert_raises():
        _ = v.get_component(3)
    v.set_component(0, 7)
    v.set_component(1, 8)
    v.set_component(2, 9)
    assert_vector(v, 7, 8, 9)
    with assert_raises():
        v.set_component(-1, 0)


def test_negate_and_scaled_add() raises:
    var v = a()
    v.negate()
    assert_vector(v, -1, 2, -3)
    v.add_scaled_vector(Vector3(1, 1, 1), 2)
    assert_vector(v, 1, 4, -1)
    assert_vector(Vector3(2, 4, 6) / 2, 1, 2, 3)


def test_scalar_add_and_subtract_match_three_js() raises:
    # three.js 0.180: (1, 2, 3).addScalar(0.5) and .subScalar(0.5).
    var v = Vector3(1, 2, 3)
    v.add_scalar(0.5)
    assert_vector(v, 1.5, 2.5, 3.5)
    v = Vector3(1, 2, 3)
    v.sub_scalar(0.5)
    assert_vector(v, 0.5, 1.5, 2.5)
    var w = Vector2(1, 2)
    w.add_scalar(0.5)
    assert_vector2(w, 1.5, 2.5)
    w = Vector2(1, 2)
    w.sub_scalar(0.5)
    assert_vector2(w, 0.5, 1.5)


def test_set_length() raises:
    var v = Vector3(3, 0, 4)
    v.set_length(10)
    assert_vector(v, 6, 0, 8)
    var zero = Vector3(0, 0, 0)
    zero.set_length(5)
    assert_vector(zero, 0, 0, 0)


def test_lerp_and_lerp_vectors() raises:
    var v = a()
    v.lerp(b(), 0.3)
    assert_vector(v, -0.5, 0.25, 2.175)
    var w = Vector3(0, 0, 0)
    w.lerp_vectors(a(), b(), 0.3)
    assert_vector(w, -0.5, 0.25, 2.175)


def test_reflect() raises:
    var v = a()
    v.reflect(Vector3(0.6, 0.8, 0))
    assert_vector(v, 2.2, -0.4, 3)


def test_apply_matrix4() raises:
    var v = a()
    v.apply_matrix4(placed())
    assert_vector(v, 2.742664791947082, -3.7426647919470817, 0.5030177192780476)


def test_apply_matrix3() raises:
    var m = Matrix3()
    m.set(1, 2, 3, 4, 5, 6, 7, 8, 10)
    var v = a()
    v.apply_matrix3(m)
    assert_vector(v, 6, 12, 21)


def test_apply_normal_matrix() raises:
    var v = a()
    v.apply_normal_matrix(Matrix3.normal_matrix(placed()))
    assert_vector(
        v, 0.5110954624602764, -0.5386091367152138, 0.6698370145784782
    )


def test_apply_quaternion_and_axis_angle() raises:
    var axis = Vector3(1, 1, 0)
    axis.normalize()
    var v = a()
    v.apply_quaternion(Quaternion.from_axis_angle(axis, Angle(0.7, RADIAN)))
    assert_vector(v, 2.01385536654499, -3.01385536654499, 0.9279344762352084)
    var w = a()
    w.apply_axis_angle(Vector3(0, 0, 1), Angle(0.5, RADIAN))
    assert_vector(w, 1.8364336390987788, -1.2757395851765425, 3)


def test_apply_euler() raises:
    var v = a()
    v.apply_euler(
        Euler(Angle(0.3, RADIAN), Angle(-0.5, RADIAN), Angle(1.1, RADIAN), YXZ)
    )
    assert_vector(
        v, 0.5905107273414532, -0.9018315617874337, 3.5830150592843877
    )


def test_transform_direction_normalizes() raises:
    var v = a()
    v.transform_direction(placed())
    assert_vector(
        v, 0.2681022756841665, -0.8834868910687819, -0.3841511201110696
    )


def test_project_and_unproject_are_inverse() raises:
    var view = translation(0, 0, -5)
    var projection = Matrix4()
    projection.set(2, 0, 0, 0, 0, 2, 0, 0, 0, 0, -1, -0.2, 0, 0, -1, 0)
    var v = Vector3(0.5, -0.25, 1)
    v.project(view, projection)
    # At depth 4: x is 2 * 0.5 / 4, y is 2 * -0.25 / 4, z is 3.8 / 4.
    assert_vector(v, 0.25, -0.125, 0.95)
    v.unproject(view, projection)
    assert_vector(v, 0.5, -0.25, 1)


def test_min_max_clamp() raises:
    var v = a()
    v.min(b())
    assert_vector(v, -4, -2, 0.25)
    v = a()
    v.max(b())
    assert_vector(v, 1, 5.5, 3)
    v = a()
    v.clamp(Vector3(0, 0, 0), Vector3(2, 2, 2))
    assert_vector(v, 1, 0, 2)
    v = a()
    v.clamp_scalar(-1, 1)
    assert_vector(v, 1, -1, 1)


def test_clamp_length() raises:
    var v = a()
    v.clamp_length(2, 3)
    assert_vector(
        v, 0.8017837257372732, -1.6035674514745464, 2.4053511772118195
    )
    var zero = Vector3(0, 0, 0)
    zero.clamp_length(2, 3)
    assert_vector(zero, 0, 0, 0)


def test_multiply_and_divide() raises:
    var v = a()
    v.multiply(Vector3(2, 3, 4))
    assert_vector(v, 2, -6, 12)
    v.divide(Vector3(2, 3, 4))
    assert_vector(v, 1, -2, 3)
    v.divide(Vector3(0, 1, 1))
    assert_equal(v.x, inf[DType.float32]())


def test_rounding() raises:
    var v = Vector3(1.5, -2.5, -0.5)
    v.round()
    assert_vector(v, 2, -2, 0)
    v = Vector3(1.5, -2.5, -0.5)
    v.floor()
    assert_vector(v, 1, -3, -1)
    v = Vector3(1.5, -2.5, -0.5)
    v.ceil()
    assert_vector(v, 2, -2, 0)
    v = Vector3(1.5, -2.5, -0.5)
    v.round_to_zero()
    assert_vector(v, 1, -2, 0)
    # The largest Float32 below a half rounds down, as Math.round does;
    # adding a half and taking the floor would round it up.
    var edge = Vector3(0.49999997, 0, 0)
    edge.round()
    assert_equal(edge.x, Float32(0))


def test_project_on_vector_and_plane() raises:
    var v = a()
    v.project_on_vector(b())
    assert_vector(
        v, 1.2307692307692308, -1.6923076923076925, -0.07692307692307693
    )
    var zero = a()
    zero.project_on_vector(Vector3(0, 0, 0))
    assert_vector(zero, 0, 0, 0)
    var flat = a()
    flat.project_on_plane(Vector3(0, 0, 2))
    assert_vector(flat, 1, -2, 0)


def test_from_matrix() raises:
    var m = placed()
    assert_vector(Vector3.from_matrix_position(m), 1, 2, 3)
    assert_vector(Vector3.from_matrix_scale(m), 2, 3, 0.5)
    assert_vector(Vector3.from_matrix_column(m, 3), 1, 2, 3)
    with assert_raises():
        _ = Vector3.from_matrix_column(m, 4)
    with assert_raises():
        _ = Vector3.from_matrix_column(m, -1)
    var m3 = Matrix3()
    m3.set(1, 2, 3, 4, 5, 6, 7, 8, 10)
    assert_vector(Vector3.from_matrix3_column(m3, 1), 2, 5, 8)
    with assert_raises():
        _ = Vector3.from_matrix3_column(m3, 3)
    with assert_raises():
        _ = Vector3.from_matrix3_column(m3, -1)


def test_random() raises:
    var generator = SeededRandom(42)
    assert_vector(
        Vector3.random(generator),
        0.6011037519201636,
        0.44829055899754167,
        0.8524657934904099,
    )
    var again = SeededRandom(42)
    assert_vector(
        Vector3.random_direction(again),
        -0.8006051605400811,
        -0.10341888200491667,
        -0.5901998913600748,
    )


# --- Vector2 ---------------------------------------------------------------


def c() -> Vector2:
    """Return the first 2D vector the node run used."""
    return Vector2(3, -4)


def d() -> Vector2:
    """Return the second 2D vector the node run used."""
    return Vector2(-1, 2)


def test_vector2_angles() raises:
    assert_almost_equal(
        Float64(c().angle().value), 5.355890089177974, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(c().angle_to(d()).value), 2.961739153797315, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(Vector2(0, 0).angle_to(d()).value),
        1.5707963267948966,
        atol=TOLERANCE,
    )
    assert_equal(c().cross(d()), Float32(2))


def test_vector2_distances() raises:
    assert_almost_equal(
        Float64(c().distance_to(d())), 7.211102550927978, atol=TOLERANCE
    )
    assert_equal(c().distance_to_squared(d()), Float32(52))
    assert_equal(c().manhattan_distance_to(d()), Float32(10))
    assert_equal(c().length_sq(), Float32(25))
    assert_equal(c().manhattan_length(), Float32(7))


def test_vector2_rotate_around() raises:
    var v = c()
    v.rotate_around(d(), Angle(0.9, RADIAN))
    assert_vector2(v, 6.186401330847558, 1.4036478288859473)


def test_vector2_equals_and_components() raises:
    assert_true(c() == Vector2(3, -4))
    assert_false(c() == Vector2(0, -4))
    assert_false(c() == Vector2(3, 0))
    assert_true(c() != d())
    var v = c()
    assert_equal(v.get_component(0), Float32(3))
    assert_equal(v.get_component(1), Float32(-4))
    with assert_raises():
        _ = v.get_component(2)
    v.set_component(0, 5)
    v.set_component(1, 6)
    assert_vector2(v, 5, 6)
    with assert_raises():
        v.set_component(2, 0)


def test_vector2_arithmetic() raises:
    var v = c()
    v.negate()
    assert_vector2(v, -3, 4)
    v.add_scaled_vector(Vector2(1, 1), 2)
    assert_vector2(v, -1, 6)
    assert_vector2(Vector2(2, 4) / 2, 1, 2)
    v = c()
    v.set_length(10)
    assert_vector2(v, 6, -8)
    v = c()
    v.lerp(d(), 0.5)
    assert_vector2(v, 1, -1)
    v.lerp_vectors(c(), d(), 0.25)
    assert_vector2(v, 2, -2.5)
    v = c()
    v.multiply(Vector2(2, 3))
    assert_vector2(v, 6, -12)
    v.divide(Vector2(2, 3))
    assert_vector2(v, 3, -4)


def test_vector2_apply_matrix3() raises:
    var v = c()
    v.apply_matrix3(Matrix3.translation(1, 2))
    assert_vector2(v, 4, -2)


def test_vector2_min_max_clamp() raises:
    var v = c()
    v.min(d())
    assert_vector2(v, -1, -4)
    v = c()
    v.max(d())
    assert_vector2(v, 3, 2)
    v = c()
    v.clamp(Vector2(0, 0), Vector2(1, 1))
    assert_vector2(v, 1, 0)
    v = c()
    v.clamp_scalar(-2, 2)
    assert_vector2(v, 2, -2)
    v = c()
    v.clamp_length(1, 2)
    assert_vector2(v, 1.2, -1.6)
    var zero = Vector2(0, 0)
    zero.clamp_length(1, 2)
    assert_vector2(zero, 0, 0)


def test_vector2_rounding() raises:
    var v = Vector2(1.5, -2.5)
    v.round()
    assert_vector2(v, 2, -2)
    v = Vector2(1.5, -2.5)
    v.floor()
    assert_vector2(v, 1, -3)
    v = Vector2(1.5, -2.5)
    v.ceil()
    assert_vector2(v, 2, -2)
    v = Vector2(1.5, -2.5)
    v.round_to_zero()
    assert_vector2(v, 1, -2)


def test_vector2_random() raises:
    var generator = SeededRandom(42)
    assert_vector2(
        Vector2.random(generator), 0.6011037519201636, 0.44829055899754167
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
