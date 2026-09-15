# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.quaternion` and `math.euler`."""

from math.euler import XYZ, XZY, YXZ, YZX, ZXY, ZYX, Euler
from math.matrix4 import Matrix4, rotation_x, rotation_y, rotation_z
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Angle, DEGREE

comptime TOLERANCE = Float64(1e-5)


def assert_point(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point matches the given components, within tolerance."""
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


def assert_same_matrix(
    a: Matrix4, b: Matrix4, tolerance: Float64 = TOLERANCE
) raises:
    """Assert two matrices agree element by element."""
    for index in range(16):
        assert_almost_equal(
            a.elements[index], b.elements[index], atol=tolerance
        )


def assert_same_rotation(a: Quaternion, b: Quaternion) raises:
    """Assert two quaternions are the same rotation, sign included or not."""
    # q and -q rotate identically, so compare what they do rather than the
    # numbers.
    assert_same_matrix(a.to_matrix(), b.to_matrix())


# --- construction and conversion -------------------------------------------


def test_the_identity_rotates_nothing() raises:
    var q = Quaternion.identity()
    assert_point(q.rotate(Vector3(1, 2, 3)), 1, 2, 3)
    assert_same_matrix(q.to_matrix(), Matrix4())


def test_an_axis_angle_about_z_turns_x_onto_y() raises:
    var q = Quaternion.from_axis_angle(Vector3(0, 0, 1), Angle(90.0, DEGREE))
    assert_point(q.rotate(Vector3(1, 0, 0)), 0, 1, 0)
    assert_same_matrix(q.to_matrix(), rotation_z(Angle(90.0, DEGREE)))


def test_to_matrix_agrees_with_the_axis_rotations() raises:
    var angle = Angle(37.0, DEGREE)
    assert_same_matrix(
        Quaternion.from_axis_angle(Vector3(1, 0, 0), angle).to_matrix(),
        rotation_x(angle),
    )
    assert_same_matrix(
        Quaternion.from_axis_angle(Vector3(0, 1, 0), angle).to_matrix(),
        rotation_y(angle),
    )


def test_from_matrix_round_trips_through_every_branch() raises:
    # `from_matrix` picks a formula by whichever diagonal term is largest.
    # A small turn keeps the trace positive. A near half turn makes the
    # trace negative, and which diagonal term then wins follows the axis:
    # straight along one axis, or tilted so that the terms are ordered
    # every way the two comparisons can go.
    var tilt = Float32(0.8660254)
    var nearly_half = Angle(170.0, DEGREE)
    var cases = [
        Quaternion.from_axis_angle(Vector3(0, 0, 1), Angle(30.0, DEGREE)),
        Quaternion.from_axis_angle(Vector3(1, 0, 0), nearly_half),
        Quaternion.from_axis_angle(Vector3(0, 1, 0), nearly_half),
        Quaternion.from_axis_angle(Vector3(0, 0, 1), nearly_half),
        Quaternion.from_axis_angle(Vector3(0.5, tilt, 0), nearly_half),
        Quaternion.from_axis_angle(Vector3(0.5, 0, tilt), nearly_half),
    ]
    for q in cases:
        assert_same_rotation(Quaternion.from_matrix(q.to_matrix()), q)


def test_rotate_agrees_with_the_matrix() raises:
    var q = Euler(
        Angle(31.0, DEGREE), Angle(-47.0, DEGREE), Angle(113.0, DEGREE), XYZ
    ).to_quaternion()
    var v = Vector3(0.3, -1.2, 2.5)
    var by_matrix = q.to_matrix().transform_direction(v)
    assert_point(q.rotate(v), by_matrix.x, by_matrix.y, by_matrix.z)


# --- composition -------------------------------------------------------------


def test_multiplying_composes_like_the_matrices() raises:
    var a = Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(40.0, DEGREE))
    var b = Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(75.0, DEGREE))
    var product = a
    product.multiply(b)
    var expected = a.to_matrix()
    expected.multiply(b.to_matrix())
    assert_same_matrix(product.to_matrix(), expected)


def test_premultiply_reverses_the_order() raises:
    var a = Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(40.0, DEGREE))
    var b = Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(75.0, DEGREE))
    var product = a
    product.premultiply(b)
    var expected = b.to_matrix()
    expected.multiply(a.to_matrix())
    assert_same_matrix(product.to_matrix(), expected)


def test_the_conjugate_undoes_the_rotation() raises:
    var q = Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(75.0, DEGREE))
    var back = q
    back.multiply(q.conjugate())
    assert_same_rotation(back, Quaternion.identity())


def test_normalizing_restores_unit_length() raises:
    var q = Quaternion(2, 0, 0, 2)
    q.normalize()
    assert_almost_equal(q.length(), Float32(1), atol=TOLERANCE)
    assert_almost_equal(q.x, Float32(0.7071068), atol=TOLERANCE)


def test_normalizing_zero_gives_the_identity() raises:
    var q = Quaternion(0, 0, 0, 0)
    q.normalize()
    assert_equal(q.w, Float32(1))
    assert_equal(q.x, Float32(0))


# --- slerp -------------------------------------------------------------------


def test_slerp_ends_are_the_ends() raises:
    var a = Quaternion.identity()
    var b = Quaternion.from_axis_angle(Vector3(0, 0, 1), Angle(90.0, DEGREE))
    assert_same_rotation(a.slerp(b, 0), a)
    assert_same_rotation(a.slerp(b, 1), b)


def test_slerp_halfway_is_half_the_turn() raises:
    var a = Quaternion.identity()
    var b = Quaternion.from_axis_angle(Vector3(0, 0, 1), Angle(90.0, DEGREE))
    var half = a.slerp(b, 0.5)
    assert_same_matrix(half.to_matrix(), rotation_z(Angle(45.0, DEGREE)))


def test_slerp_takes_the_short_way_round() raises:
    # -b is the same rotation as b, pointing the other way in four space.
    # Blending towards it must still be the 45 degree turn, not a 135 one.
    var a = Quaternion.identity()
    var b = Quaternion.from_axis_angle(Vector3(0, 0, 1), Angle(90.0, DEGREE))
    var flipped = Quaternion(-b.x, -b.y, -b.z, -b.w)
    var half = a.slerp(flipped, 0.5)
    assert_same_matrix(half.to_matrix(), rotation_z(Angle(45.0, DEGREE)))


def test_slerp_between_identical_rotations_stays_put() raises:
    var a = Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(20.0, DEGREE))
    assert_same_rotation(a.slerp(a, 0.3), a)
    # The identity with itself has a dot product of exactly one.
    var same = Quaternion.identity().slerp(Quaternion.identity(), 0.7)
    assert_equal(same.w, Float32(1))


def test_slerp_between_nearly_identical_rotations_blends_straight() raises:
    # A tenth of a degree apart: close enough that the arc is treated as a
    # line, far enough that Float32 can tell the two apart.
    var a = Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(20.0, DEGREE))
    var b = Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(20.1, DEGREE))
    var between = a.slerp(b, 0.5)
    assert_almost_equal(between.length(), Float32(1), atol=TOLERANCE)
    assert_same_matrix(between.to_matrix(), rotation_x(Angle(20.05, DEGREE)))


# --- euler -------------------------------------------------------------------


def test_every_euler_order_agrees_between_quaternion_and_matrix() raises:
    var orders = [XYZ, YXZ, ZXY, ZYX, YZX, XZY]
    for order in orders:
        var euler = Euler(
            Angle(31.0, DEGREE),
            Angle(-47.0, DEGREE),
            Angle(113.0, DEGREE),
            order,
        )
        assert_same_matrix(
            euler.to_quaternion().to_matrix(), euler.to_matrix(), Float64(1e-4)
        )


def test_xyz_is_x_then_y_then_z_on_the_turned_axes() raises:
    var euler = Euler(
        Angle(90.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE), XYZ
    )
    # Rx * Ry: +y is left alone by Ry and carried onto +z by Rx.
    assert_point(euler.to_quaternion().rotate(Vector3(0, 1, 0)), 0, 0, 1)


def test_the_six_orders_are_six_rotations() raises:
    var orders = [XYZ, YXZ, ZXY, ZYX, YZX, XZY]
    var matrices = List[Matrix4]()
    for order in orders:
        matrices.append(
            Euler(
                Angle(31.0, DEGREE),
                Angle(-47.0, DEGREE),
                Angle(113.0, DEGREE),
                order,
            ).to_matrix()
        )
    for left in range(len(matrices)):
        for right in range(left + 1, len(matrices)):
            var differ = False
            for index in range(16):
                if (
                    abs(
                        matrices[left].elements[index]
                        - matrices[right].elements[index]
                    )
                    > 1e-4
                ):
                    differ = True
            assert_true(differ, "two orders gave the same matrix")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
