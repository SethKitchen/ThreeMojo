# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.vector4`."""

from math.matrix4 import Matrix4, scaling, translation
from math.projection import perspective
from math.quaternion import Quaternion
from math.vector3 import Vector3
from math.vector4 import Vector4
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import RADIAN

comptime TOLERANCE = Float64(1e-6)


def assert_components(
    got: Vector4, x: Float32, y: Float32, z: Float32, w: Float32
) raises:
    """Assert a vector matches the given components, within tolerance.

    Args:
        got: The vector to check.
        x: Expected x.
        y: Expected y.
        z: Expected z.
        w: Expected w.

    Raises:
        Error: If any component differs.
    """
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)
    assert_almost_equal(got.w, w, atol=TOLERANCE)


def test_a_vector_from_a_vector3_is_a_position_unless_told_otherwise() raises:
    var position = Vector4(of=Vector3(1, 2, 3))
    assert_components(position, 1, 2, 3, 1)
    var direction = Vector4(of=Vector3(1, 2, 3), w=0)
    assert_components(direction, 1, 2, 3, 0)
    var back = direction.xyz()
    assert_equal(back.x, Float32(1))
    assert_equal(back.y, Float32(2))
    assert_equal(back.z, Float32(3))


def test_dot_and_length_take_all_four_components() raises:
    assert_equal(Vector4(1, 2, 3, 4).dot(Vector4(5, 6, 7, 8)), Float32(70))
    assert_equal(Vector4(2, 0, 0, 0).dot(Vector4(0, 0, 0, 5)), Float32(0))
    assert_equal(Vector4(1, 2, 2, 4).length(), Float32(5))
    assert_equal(Vector4(0, 0, 0, 0).length(), Float32(0))


def test_add_and_sub_mutate_in_place() raises:
    var v = Vector4(1, 2, 3, 4)
    v.add(Vector4(10, 20, 30, 40))
    assert_components(v, 11, 22, 33, 44)
    v.sub(Vector4(1, 2, 3, 4))
    assert_components(v, 10, 20, 30, 40)


def test_assignment_copies_rather_than_aliases() raises:
    var a = Vector4(1, 0, 0, 0)
    var b = a
    b.add(Vector4(0, 0, 0, 1))
    assert_equal(a.w, Float32(0))
    assert_equal(b.w, Float32(1))


def test_normalize_gives_unit_length() raises:
    var v = Vector4(0, 3, 0, 4)
    v.normalize()
    assert_almost_equal(v.length(), Float32(1), atol=TOLERANCE)
    assert_components(v, 0, 0.6, 0, 0.8)


def test_normalize_leaves_zero_vector_unchanged() raises:
    var v = Vector4(0, 0, 0, 0)
    v.normalize()
    assert_true(v.x == 0 and v.y == 0 and v.z == 0 and v.w == 0)


def test_operators_agree_with_the_mutating_methods() raises:
    var a = Vector4(1, 2, 3, 4)
    var b = Vector4(10, 20, 30, 40)
    var summed = a
    summed.add(b)
    assert_components(a + b, summed.x, summed.y, summed.z, summed.w)
    var lessened = b
    lessened.sub(a)
    assert_components(b - a, lessened.x, lessened.y, lessened.z, lessened.w)
    assert_components(a * 2, 2, 4, 6, 8)
    assert_components(-a, -1, -2, -3, -4)
    # And the operands are left alone.
    assert_components(a, 1, 2, 3, 4)


def test_a_position_is_moved_by_a_translation_and_a_direction_is_not() raises:
    var moved = translation(5, 6, 7)
    var position = Vector4(of=Vector3(1, 2, 3))
    position.apply_matrix4(moved)
    assert_components(position, 6, 8, 10, 1)
    var direction = Vector4(of=Vector3(1, 2, 3), w=0)
    direction.apply_matrix4(moved)
    assert_components(direction, 1, 2, 3, 0)


def test_a_projection_leaves_the_divisor_in_w() raises:
    # A perspective matrix copies minus the depth into w. Where
    # `transform_point` divides by it and `transform_w` reports it, this
    # keeps the whole product: the clip-space coordinate.
    var projection = perspective(-1, 1, 1, -1, 1, 10)
    var point = Vector3(0.5, -0.25, -4)
    var clip = Vector4(of=point)
    clip.apply_matrix4(projection)
    assert_almost_equal(clip.w, Float32(4), atol=TOLERANCE)
    assert_almost_equal(clip.w, projection.transform_w(point), atol=TOLERANCE)
    var divided = projection.transform_point(point)
    assert_almost_equal(clip.x / clip.w, divided.x, atol=TOLERANCE)
    assert_almost_equal(clip.y / clip.w, divided.y, atol=TOLERANCE)
    assert_almost_equal(clip.z / clip.w, divided.z, atol=TOLERANCE)


# The rest of this file holds the vector to three.js 0.180's `Vector4`,
# run in Node on the same inputs.


def test_lengths_match_three_js() raises:
    var a = Vector4(1.5, -2.25, 3, -0.5)
    assert_equal(a.length_sq(), Float32(16.5625))
    assert_equal(a.manhattan_length(), Float32(7.25))
    var b = a
    b.set_length(2)
    assert_components(
        b,
        0.7371541402007414,
        -1.105731210301112,
        1.4743082804014829,
        -0.24571804673358047,
    )
    var zero = Vector4(0, 0, 0, 0)
    zero.set_length(2)
    assert_true(zero == Vector4(0, 0, 0, 0))


def test_lerp_multiply_and_divide_match_three_js() raises:
    var a = Vector4(1.5, -2.25, 3, -0.5)
    var b = Vector4(-4, 0.5, 2, 8)
    var v = a
    v.lerp(b, 0.25)
    assert_components(v, 0.125, -1.5625, 2.75, 1.625)
    v.lerp_vectors(a, b, 0.75)
    assert_components(v, -2.625, -0.1875, 2.25, 5.875)
    v = a
    v.multiply(b)
    assert_components(v, -6, -1.125, 6, -4)
    v = a
    v.divide(b)
    assert_components(v, -0.375, -4.5, 1.5, -0.0625)
    assert_components(a / 4, 0.375, -0.5625, 0.75, -0.125)


def test_min_max_and_clamp_match_three_js() raises:
    var a = Vector4(1.5, -2.25, 3, -0.5)
    var b = Vector4(-4, 0.5, 2, 8)
    var v = a
    v.min(b)
    assert_components(v, -4, -2.25, 2, -0.5)
    v = a
    v.max(b)
    assert_components(v, 1.5, 0.5, 3, 8)
    v = Vector4(5, -5, 1, 9)
    v.clamp(Vector4(-1, -1, -1, -1), Vector4(2, 3, 4, 5))
    assert_components(v, 2, -1, 1, 5)
    v = a
    v.clamp_scalar(-1, 2)
    assert_components(v, 1.5, -1, 2, -0.5)
    v = a
    v.clamp_length(1, 2)
    assert_components(
        v,
        0.7371541402007414,
        -1.105731210301112,
        1.4743082804014829,
        -0.24571804673358047,
    )
    v = a
    v.clamp_length(5, 6)
    assert_components(
        v,
        1.8428853505018536,
        -2.7643280257527802,
        3.6857707010037073,
        -0.6142951168339512,
    )
    v = Vector4(0, 0, 0, 0)
    v.clamp_length(1, 2)
    assert_components(v, 0, 0, 0, 0)


def test_rounding_matches_three_js() raises:
    var r = Vector4(1.5, -2.5, 2.4999, -0.4)
    var v = r
    v.floor()
    assert_components(v, 1, -3, 2, -1)
    v = r
    v.ceil()
    assert_components(v, 2, -2, 3, 0)
    v = r
    v.round()
    assert_components(v, 2, -2, 2, 0)
    v = r
    v.round_to_zero()
    assert_components(v, 1, -2, 2, 0)


def test_negate_scaled_add_and_components_match_three_js() raises:
    var a = Vector4(1.5, -2.25, 3, -0.5)
    var v = a
    v.negate()
    assert_components(v, -1.5, 2.25, -3, 0.5)
    v = a
    v.add_scaled_vector(Vector4(-4, 0.5, 2, 8), 0.5)
    assert_components(v, -0.5, -2, 4, 3.5)
    for index in range(4):
        v.set_component(index, Float32(index * 10))
    for index in range(4):
        assert_equal(v.get_component(index), Float32(index * 10))
    with assert_raises():
        _ = v.get_component(4)
    with assert_raises():
        v.set_component(-1, 1)
    assert_components(v, 0, 10, 20, 30)


def test_equality_is_every_component() raises:
    var a = Vector4(1, 2, 3, 4)
    assert_true(a == Vector4(1, 2, 3, 4))
    assert_false(a != Vector4(1, 2, 3, 4))
    assert_true(a != Vector4(0, 2, 3, 4))
    assert_true(a != Vector4(1, 0, 3, 4))
    assert_true(a != Vector4(1, 2, 0, 4))
    assert_true(a != Vector4(1, 2, 3, 0))


def test_axis_angle_from_a_quaternion_matches_three_js() raises:
    var v = Vector4(0, 0, 0, 0)
    v.set_axis_angle_from_quaternion(Quaternion(0.2, 0.4, -0.4, 0.8))
    assert_components(
        v,
        0.33333334713070534,
        0.6666666942614107,
        -0.6666666942614107,
        1.2870021778501384,
    )
    assert_almost_equal(
        v.axis_angle().to(RADIAN), Float32(1.2870021778501384), atol=TOLERANCE
    )
    v.set_axis_angle_from_quaternion(Quaternion.identity())
    assert_components(v, 1, 0, 0, 0)


def _matrix(values: List[Float32]) -> Matrix4:
    """Return a matrix from its sixteen elements, column by column."""
    var m = Matrix4()
    for index in range(16):
        m.elements[index] = values[index]
    return m^


def test_axis_angle_from_a_rotation_matrix_matches_three_js() raises:
    # makeRotationAxis((1, 2, 3) normalized, 1.2), rounded to Float32.
    var turned = _matrix(
        [
            0.40790364146232605,
            0.8383855223655701,
            -0.3615582287311554,
            0,
            -0.6562020182609558,
            0.5445412397384644,
            0.5223731994628906,
            0,
            0.6348334550857544,
            0.024177324026823044,
            0.7722706198692322,
            0,
            0,
            0,
            0,
            1,
        ]
    )
    var v = Vector4(0, 0, 0, 0)
    v.set_axis_angle_from_rotation_matrix(turned)
    assert_components(
        v, 0.267261256900893, 0.5345224778294613, 0.8017837247380418, 1.2
    )
    v.set_axis_angle_from_rotation_matrix(Matrix4())
    assert_components(v, 1, 0, 0, 0)


def test_a_half_turn_takes_its_axis_from_the_largest_diagonal() raises:
    var v = Vector4(0, 0, 0, 0)
    var pi32 = Float32(3.141592653589793)
    v.set_axis_angle_from_rotation_matrix(scaling(1, -1, -1))
    assert_components(v, 1, 0, 0, pi32)
    v.set_axis_angle_from_rotation_matrix(scaling(-1, 1, -1))
    assert_components(v, 0, 1, 0, pi32)
    v.set_axis_angle_from_rotation_matrix(scaling(-1, -1, 1))
    assert_components(v, 0, 0, 1, pi32)
    # A half turn about (0, 1, 1): y and z tie, and z wins, as in three.js.
    var about = _matrix([-1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1])
    v.set_axis_angle_from_rotation_matrix(about)
    assert_components(v, 0, 0.7071067811865476, 0.7071067811865475, pi32)
    # x largest but not above z: z is taken.
    v.set_axis_angle_from_rotation_matrix(scaling(1, -1, 1))
    assert_components(v, 0, 0, 1, pi32)


def test_a_half_turn_too_small_to_divide_by_takes_a_fixed_axis() raises:
    # Not rotations, but the numbers three.js gives for them.
    var v = Vector4(0, 0, 0, 0)
    var pi32 = Float32(3.141592653589793)
    v.set_axis_angle_from_rotation_matrix(scaling(-0.99, -1, -1))
    assert_components(v, 0, 0.707106781, 0.707106781, pi32)
    v.set_axis_angle_from_rotation_matrix(scaling(-1, -0.99, -1))
    assert_components(v, 0.707106781, 0, 0.707106781, pi32)
    v.set_axis_angle_from_rotation_matrix(scaling(-1, -1, -1))
    assert_components(v, 0.707106781, 0.707106781, 0, pi32)


def test_symmetry_and_the_identity_are_tested_entry_by_entry() raises:
    var v = Vector4(0, 0, 0, 0)
    # Each mirrored pair breaks the symmetry on its own.
    for pair in range(3):
        var m = Matrix4()
        var entry = [4, 8, 9][pair]
        m.elements[entry] = 0.5
        v.set_axis_angle_from_rotation_matrix(m)
        assert_true(v != Vector4(1, 0, 0, 0))
        assert_almost_equal(v.xyz().length(), Float32(1), atol=TOLERANCE)
    # Each pair's sum, and the trace, keep a symmetric matrix from the
    # identity on its own.
    for pair in range(3):
        var m = Matrix4()
        var entry = [4, 8, 9][pair]
        var mirror = [1, 2, 6][pair]
        m.elements[entry] = 0.3
        m.elements[mirror] = 0.3
        v.set_axis_angle_from_rotation_matrix(m)
        assert_almost_equal(v.w, Float32(3.141592653589793), atol=TOLERANCE)
    var m = Matrix4()
    m.elements[0] = 0.5
    v.set_axis_angle_from_rotation_matrix(m)
    assert_almost_equal(v.w, Float32(3.141592653589793), atol=TOLERANCE)


def test_a_nearly_symmetric_matrix_keeps_three_js_guard() raises:
    # Off-diagonal pairs a hair past the threshold: `s` is below a
    # thousandth only for a matrix that is symmetric, so the guard's
    # fallback is not reached here.
    var m = Matrix4()
    m.elements[4] = 0.006
    m.elements[1] = -0.006
    var v = Vector4(0, 0, 0, 0)
    v.set_axis_angle_from_rotation_matrix(m)
    assert_components(v, 0, 0, -1, 0)


def test_the_position_of_a_matrix_is_its_last_column() raises:
    var m = translation(1, 2, 3)
    m.elements[15] = 4
    var v = Vector4(0, 0, 0, 0)
    v.set_from_matrix_position(m)
    assert_components(v, 1, 2, 3, 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
