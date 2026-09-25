# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the three.js `Quaternion`, `Matrix4`, `Matrix3` and
`MathUtils` members added to `math.quaternion`, `math.matrix4`,
`math.matrix3` and `math.utils`.

The expected numbers come from three.js 0.180, run in node on the same
inputs.
"""

from math.euler import XYZ, XZY, YXZ, ZYX, Euler, EulerOrder
from math.matrix3 import Matrix3
from math.matrix4 import (
    Matrix4,
    basis,
    compose,
    rotation_axis,
    rotation_from_euler,
    rotation_from_quaternion,
    scaling,
    shear,
    translation,
)
from math.quaternion import Quaternion
from math.utils import (
    ComponentType,
    FLOAT32_COMPONENT,
    INT16_COMPONENT,
    INT32_COMPONENT,
    INT8_COMPONENT,
    PROPER_XYX,
    PROPER_XZX,
    PROPER_YXY,
    PROPER_YZY,
    PROPER_ZXZ,
    PROPER_ZYZ,
    ProperEulerOrder,
    SeededRandom,
    UINT16_COMPONENT,
    UINT32_COMPONENT,
    UINT8_COMPONENT,
    denormalize,
    generate_uuid,
    normalize,
    quaternion_from_proper_euler,
)
from math.vector3 import Vector3
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


def assert_quaternion(
    got: Quaternion, x: Float64, y: Float64, z: Float64, w: Float64
) raises:
    """Assert a quaternion matches four components, within tolerance.

    Args:
        got: The quaternion to check.
        x: Expected x.
        y: Expected y.
        z: Expected z.
        w: Expected w.

    Raises:
        Error: If a component differs.
    """
    assert_almost_equal(Float64(got.x), x, atol=TOLERANCE)
    assert_almost_equal(Float64(got.y), y, atol=TOLERANCE)
    assert_almost_equal(Float64(got.z), z, atol=TOLERANCE)
    assert_almost_equal(Float64(got.w), w, atol=TOLERANCE)


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


def assert_elements(got: Matrix4, expected: List[Float64]) raises:
    """Assert a matrix's sixteen elements, in storage order.

    Args:
        got: The matrix to check.
        expected: The elements three.js stores, column by column.

    Raises:
        Error: If an element differs.
    """
    for index in range(16):
        assert_almost_equal(
            Float64(got.elements[index]), expected[index], atol=TOLERANCE
        )


def turn() -> Quaternion:
    """Return a turn of 0.7 radians about (1, 1, 0)."""
    var axis = Vector3(1, 1, 0)
    axis.normalize()
    return Quaternion.from_axis_angle(axis, Angle(0.7, RADIAN))


def placed() -> Matrix4:
    """Return the transform the node run composed."""
    return compose(Vector3(1, 2, 3), turn(), Vector3(2, 3, 0.5))


def first() -> Quaternion:
    """Return a turn of 0.8 radians about y."""
    return Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(0.8, RADIAN))


def second() raises -> Quaternion:
    """Return the rotation of the Euler angles (0.2, 0.4, -0.3), XYZ."""
    return Quaternion.from_euler(
        Euler(Angle(0.2, RADIAN), Angle(0.4, RADIAN), Angle(-0.3, RADIAN), XYZ)
    )


# --- Quaternion ------------------------------------------------------------


def test_quaternion_from_euler() raises:
    assert_quaternion(
        second(),
        0.06720426558332449,
        0.21007864836692947,
        -0.1261165070864851,
        0.9671841473204751,
    )


def test_quaternion_angle_to() raises:
    assert_almost_equal(
        Float64(first().angle_to(second()).value),
        0.4688843890869345,
        atol=TOLERANCE,
    )
    assert_almost_equal(Float64(first().angle_to(first()).value), 0, atol=1e-3)


def test_quaternion_rotate_towards() raises:
    var q = first()
    q.rotate_towards(second(), Angle(0.1, RADIAN))
    assert_quaternion(
        q,
        0.01445891730494113,
        0.3526389090671857,
        -0.027133815553576714,
        0.9352542411428982,
    )
    # A step past the angle arrives.
    var far = first()
    far.rotate_towards(second(), Angle(3.0, RADIAN))
    assert_quaternion(
        far,
        0.06720426558332449,
        0.21007864836692947,
        -0.1261165070864851,
        0.9671841473204751,
    )
    # Already there: nothing moves.
    var there = Quaternion.identity()
    there.rotate_towards(Quaternion.identity(), Angle(0.1, RADIAN))
    assert_true(there == Quaternion.identity())


def test_quaternion_slerp_quaternions() raises:
    assert_quaternion(
        Quaternion.slerp_quaternions(first(), second(), 0.25),
        0.01694625944297523,
        0.3462135277703059,
        -0.031801598166109696,
        0.9374634263979649,
    )


def test_quaternion_invert_and_multiply() raises:
    var q = second()
    q.invert()
    assert_quaternion(
        q,
        -0.06720426558332449,
        -0.21007864836692947,
        0.1261165070864851,
        0.9671841473204751,
    )
    assert_quaternion(second() * q, 0, 0, 0, 1)
    assert_almost_equal(Float64(q.length_sq()), 1, atol=TOLERANCE)


def test_quaternion_equals() raises:
    var q = Quaternion(1, 2, 3, 4)
    assert_true(q == Quaternion(1, 2, 3, 4))
    assert_false(q == Quaternion(0, 2, 3, 4))
    assert_false(q == Quaternion(1, 0, 3, 4))
    assert_false(q == Quaternion(1, 2, 0, 4))
    assert_false(q == Quaternion(1, 2, 3, 0))
    assert_true(q != Quaternion(-1, -2, -3, -4))


def test_quaternion_random() raises:
    var generator = SeededRandom(42)
    assert_quaternion(
        Quaternion.random(generator),
        -0.2279189775205658,
        -0.3091717098888092,
        0.2947273484548031,
        -0.874986619076664,
    )


# --- Matrix4 ---------------------------------------------------------------


def test_compose() raises:
    assert_elements(
        placed(),
        [
            1.7648421872844884,
            0.23515781271551153,
            -0.9110613904121713,
            0,
            0.3527367190732673,
            2.6472632809267327,
            1.366592085618257,
            0,
            0.22776534760304282,
            -0.22776534760304282,
            0.38242109364224425,
            0,
            1,
            2,
            3,
            1,
        ],
    )
    assert_almost_equal(Float64(placed().determinant()), 3, atol=1e-4)


def test_decompose() raises:
    var position = Vector3(0, 0, 0)
    var rotation = Quaternion.identity()
    var size = Vector3(0, 0, 0)
    placed().decompose(position, rotation, size)
    assert_vector(position, 1, 2, 3)
    assert_quaternion(
        rotation, 0.24246536490574866, 0.2424653649057487, 0, 0.9393727128473791
    )
    assert_vector(size, 2, 3, 0.5)
    # A mirror comes out as a negative x scale, as in three.js.
    var mirrored = placed()
    mirrored.scale(Vector3(-1, 1, 1))
    mirrored.decompose(position, rotation, size)
    assert_quaternion(
        rotation, 0.24246536490574866, 0.2424653649057487, 0, 0.9393727128473791
    )
    assert_vector(size, -2, 3, 0.5)


def test_decompose_refuses_a_flat_axis() raises:
    var position = Vector3(0, 0, 0)
    var rotation = Quaternion.identity()
    var size = Vector3(0, 0, 0)
    with assert_raises():
        scaling(0, 1, 1).decompose(position, rotation, size)
    with assert_raises():
        scaling(1, 0, 1).decompose(position, rotation, size)
    with assert_raises():
        scaling(1, 1, 0).decompose(position, rotation, size)


def test_rotation_axis() raises:
    var axis = Vector3(1, 2, 3)
    axis.normalize()
    assert_elements(
        rotation_axis(axis, Angle(1.2, RADIAN)),
        [
            0.40790362915691125,
            0.8383855202400405,
            -0.3615582232123308,
            0,
            -0.6562020215190902,
            0.544541253197624,
            0.5223731717079474,
            0,
            0.6348334712937563,
            0.024177324454903837,
            0.7722706265988121,
            0,
            0,
            0,
            0,
            1,
        ],
    )


def test_rotation_from_quaternion_and_euler() raises:
    assert_true(rotation_from_quaternion(turn()) == turn().to_matrix())
    var euler = Euler(
        Angle(0.2, RADIAN), Angle(0.4, RADIAN), Angle(-0.3, RADIAN), XYZ
    )
    assert_true(rotation_from_euler(euler) == euler.to_matrix())


def test_shear_and_basis() raises:
    var m = shear(1, 2, 3, 4, 5, 6)
    # A point on x moves along y by xy and along z by xz.
    assert_vector(m.transform_point(Vector3(1, 0, 0)), 1, 1, 2)
    assert_vector(m.transform_point(Vector3(0, 1, 0)), 3, 1, 4)
    assert_vector(m.transform_point(Vector3(0, 0, 1)), 5, 6, 1)
    var frame = basis(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9))
    var x = Vector3(0, 0, 0)
    var y = Vector3(0, 0, 0)
    var z = Vector3(0, 0, 0)
    frame.extract_basis(x, y, z)
    assert_vector(x, 1, 2, 3)
    assert_vector(y, 4, 5, 6)
    assert_vector(z, 7, 8, 9)


def test_scale_position_and_scalar() raises:
    var m = translation(1, 2, 3)
    m.scale(Vector3(2, 3, 4))
    assert_vector(m.transform_point(Vector3(1, 1, 1)), 3, 5, 7)
    m.set_position(Vector3(-1, -2, -3))
    assert_vector(Vector3.from_matrix_position(m), -1, -2, -3)
    var other = Matrix4()
    other.copy_position(m)
    assert_vector(Vector3.from_matrix_position(other), -1, -2, -3)
    var doubled = Matrix4()
    doubled.multiply_scalar(2)
    assert_equal(doubled.elements[0], Float32(2))
    assert_equal(doubled.elements[15], Float32(2))


def test_equals_and_product() raises:
    assert_true(placed() == placed())
    assert_false(placed() != placed())
    assert_true(placed() != Matrix4())
    var product = translation(1, 0, 0) * scaling(2, 2, 2)
    assert_vector(product.transform_point(Vector3(1, 1, 1)), 3, 2, 2)


def test_look_at() raises:
    var m = Matrix4()
    m.look_at(Vector3(1, 2, 3), Vector3(4, -1, 0), Vector3(0, 1, 0))
    assert_elements(
        m,
        [
            0.7071067811865475,
            0,
            0.7071067811865475,
            0,
            0.40824829046386296,
            0.8164965809277259,
            -0.40824829046386296,
            0,
            -0.5773502691896257,
            0.5773502691896257,
            0.5773502691896257,
            0,
            0,
            0,
            0,
            1,
        ],
    )


def test_look_at_degenerate() raises:
    # An eye on its target looks down -z.
    var same = Matrix4()
    same.look_at(Vector3(1, 2, 3), Vector3(1, 2, 3), Vector3(0, 1, 0))
    assert_true(same == Matrix4())
    # Up along the view: z is nudged along x when up is z.
    var up_z = Matrix4()
    up_z.look_at(Vector3(0, 0, 3), Vector3(0, 0, 0), Vector3(0, 0, 1))
    assert_elements(
        up_z,
        [
            0,
            1,
            0,
            0,
            -1,
            0,
            0.0001,
            0,
            0.0001,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
        ],
    )
    # And along z otherwise.
    var up_y = Matrix4()
    up_y.look_at(Vector3(0, 3, 0), Vector3(0, 0, 0), Vector3(0, 1, 0))
    assert_elements(
        up_y,
        [
            1,
            0,
            0,
            0,
            0,
            0.0001,
            -1,
            0,
            0,
            1,
            0.0001,
            0,
            0,
            0,
            0,
            1,
        ],
    )


# --- Matrix3 ---------------------------------------------------------------


def test_matrix3_basis_scalar_and_product() raises:
    var m = Matrix3()
    m.set(1, 2, 3, 4, 5, 6, 7, 8, 10)
    var x = Vector3(0, 0, 0)
    var y = Vector3(0, 0, 0)
    var z = Vector3(0, 0, 0)
    m.extract_basis(x, y, z)
    assert_vector(x, 1, 4, 7)
    assert_vector(y, 2, 5, 8)
    assert_vector(z, 3, 6, 10)
    var product = m * Matrix3()
    assert_true(product == m)
    product.multiply_scalar(2)
    assert_equal(product.elements[8], Float32(20))


# --- MathUtils --------------------------------------------------------------


def test_generate_uuid() raises:
    var generator = SeededRandom(42)
    assert_equal(
        generate_uuid(generator), "7befe199-892b-4372-bf32-3bdaacb073ab"
    )


def test_proper_euler() raises:
    var a = Angle(0.3, RADIAN)
    var b = Angle(0.7, RADIAN)
    var c = Angle(-0.4, RADIAN)
    var p = 0.3221088436188455
    var q = 0.11757890635775578
    var r = -0.046949067823655474
    var w = 0.9381987415642455
    assert_quaternion(
        quaternion_from_proper_euler(a, b, c, PROPER_XYX), r, p, q, w
    )
    assert_quaternion(
        quaternion_from_proper_euler(a, b, c, PROPER_YZY), q, r, p, w
    )
    assert_quaternion(
        quaternion_from_proper_euler(a, b, c, PROPER_ZXZ), p, q, r, w
    )
    assert_quaternion(
        quaternion_from_proper_euler(a, b, c, PROPER_XZX), r, -q, p, w
    )
    assert_quaternion(
        quaternion_from_proper_euler(a, b, c, PROPER_YXY), p, r, -q, w
    )
    assert_quaternion(
        quaternion_from_proper_euler(a, b, c, PROPER_ZYZ), -q, p, r, w
    )
    with assert_raises():
        _ = quaternion_from_proper_euler(a, b, c, ProperEulerOrder(6))
    with assert_raises():
        _ = quaternion_from_proper_euler(a, b, c, ProperEulerOrder(-1))


def test_denormalize() raises:
    assert_almost_equal(
        denormalize(128, UINT8_COMPONENT), 0.5019607843137255, atol=1e-12
    )
    assert_equal(denormalize(-128, INT8_COMPONENT), -1)
    assert_equal(denormalize(-32768, INT16_COMPONENT), -1)
    assert_equal(denormalize(0.25, FLOAT32_COMPONENT), 0.25)
    assert_equal(denormalize(65535, UINT16_COMPONENT), 1)
    assert_equal(denormalize(4294967295, UINT32_COMPONENT), 1)
    assert_equal(denormalize(2147483647, INT32_COMPONENT), 1)
    with assert_raises():
        _ = denormalize(1, ComponentType(7))
    with assert_raises():
        _ = denormalize(1, ComponentType(-1))


def test_normalize() raises:
    assert_equal(normalize(0.5, UINT8_COMPONENT), 128)
    assert_equal(normalize(-0.5, INT8_COMPONENT), -63)
    assert_equal(normalize(0.5, UINT16_COMPONENT), 32768)
    assert_equal(normalize(0.25, FLOAT32_COMPONENT), 0.25)
    with assert_raises():
        _ = normalize(1, ComponentType(7))


def test_reorder_keeps_the_rotation_and_matches_three_js() raises:
    var euler = Euler(
        Angle(0.1, RADIAN), Angle(0.2, RADIAN), Angle(0.3, RADIAN), XYZ
    )
    var before = euler.to_quaternion()
    euler.reorder(ZYX)
    assert_true(euler.order == ZYX)
    assert_almost_equal(
        euler.x.to(RADIAN), Float32(0.15641951308019914), atol=TOLERANCE
    )
    assert_almost_equal(
        euler.y.to(RADIAN), Float32(0.16002722043161824), atol=TOLERANCE
    )
    assert_almost_equal(
        euler.z.to(RADIAN), Float32(0.322609690576475), atol=TOLERANCE
    )
    var after = euler.to_quaternion()
    assert_quaternion(
        after,
        Float64(before.x),
        Float64(before.y),
        Float64(before.z),
        Float64(before.w),
    )
    var other = Euler(
        Angle(0.5, RADIAN), Angle(-1.0, RADIAN), Angle(2.0, RADIAN), YXZ
    )
    other.reorder(XZY)
    assert_almost_equal(
        other.x.to(RADIAN), Float32(-1.9670278632567404), atol=TOLERANCE
    )
    assert_almost_equal(
        other.y.to(RADIAN), Float32(-2.2462866410970936), atol=TOLERANCE
    )
    assert_almost_equal(
        other.z.to(RADIAN), Float32(0.3293335053559902), atol=TOLERANCE
    )
    with assert_raises():
        other.reorder(EulerOrder(0, 0, 1))
    assert_true(other.order == XZY)


def test_set_from_matrix3_matches_three_js() raises:
    var small = Matrix3()
    small.set(1, 2, 3, 4, 5, 6, 7, 8, 9)
    var big = translation(5, 6, 7)
    big.elements[3] = 2
    big.set_from_matrix3(small)
    var expected: List[Float32] = [
        1,
        4,
        7,
        0,
        2,
        5,
        8,
        0,
        3,
        6,
        9,
        0,
        0,
        0,
        0,
        1,
    ]
    for index in range(16):
        assert_equal(big.elements[index], expected[index])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
