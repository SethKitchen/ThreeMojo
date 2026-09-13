# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.matrix4`."""

from math.matrix4 import (
    Matrix4,
    rotation_x,
    rotation_y,
    rotation_z,
    scaling,
    translation,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, RADIAN


# cos(90 degrees) is -4.37e-08 rather than 0, and a *relative* tolerance can
# never be met against an expected zero. Rotations produce exact zeros only by
# luck, so these comparisons need an absolute tolerance.
comptime TOLERANCE = Float64(1e-6)


def assert_point(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point matches the given components, within tolerance.

    Args:
        got: The point to check.
        x: Expected x.
        y: Expected y.
        z: Expected z.

    Raises:
        Error: If any component differs.
    """
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


def assert_same(got: Matrix4, expected: Matrix4) raises:
    """Assert two matrices agree element by element.

    Args:
        got: The matrix to check.
        expected: The matrix it should match.

    Raises:
        Error: If any element differs.
    """
    for index in range(16):
        assert_almost_equal(
            got.elements[index], expected.elements[index], atol=TOLERANCE
        )


def test_a_new_matrix_is_the_identity() raises:
    var m = Matrix4()
    for row in range(4):
        for column in range(4):
            if row == column:
                assert_equal(m.get(row, column), Float32(1))
            else:
                assert_equal(m.get(row, column), Float32(0))


def test_set_takes_row_major_arguments() raises:
    # The whole point: arguments read like the matrix on paper.
    var m = Matrix4()
    m.set(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    assert_equal(m.get(0, 1), Float32(2))
    assert_equal(m.get(1, 0), Float32(5))
    assert_equal(m.get(0, 3), Float32(4))


def test_storage_is_column_major() raises:
    # ...but memory is transposed from how the call reads.
    var m = Matrix4()
    m.set(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    assert_equal(m.elements[0], Float32(1))
    assert_equal(m.elements[1], Float32(5))
    assert_equal(m.elements[4], Float32(2))
    assert_equal(m.elements[12], Float32(4))


def test_translation_occupies_the_last_column() raises:
    # Where a GPU or OpenGL expects to find it.
    var t = translation(5, 6, 7)
    assert_equal(t.elements[12], Float32(5))
    assert_equal(t.elements[13], Float32(6))
    assert_equal(t.elements[14], Float32(7))


def test_get_and_put_round_trip() raises:
    var m = Matrix4()
    m.put(2, 3, 42.0)
    assert_equal(m.get(2, 3), Float32(42))


def test_out_of_range_indices_are_rejected() raises:
    var m = Matrix4()
    with assert_raises():
        _ = m.get(4, 0)
    with assert_raises():
        _ = m.get(0, 4)
    with assert_raises():
        _ = m.get(-1, 0)
    with assert_raises():
        _ = m.get(0, -1)


def test_out_of_range_writes_are_rejected() raises:
    var m = Matrix4()
    with assert_raises():
        m.put(4, 0, 1.0)
    with assert_raises():
        m.put(0, -1, 1.0)


def test_identity_resets_a_modified_matrix() raises:
    var m = scaling(2, 3, 4)
    m.identity()
    assert_same(m, Matrix4())


def test_assignment_copies_rather_than_aliases() raises:
    var a = translation(1, 2, 3)
    var b = a
    b.put(0, 0, 99.0)
    assert_equal(a.get(0, 0), Float32(1))
    assert_equal(b.get(0, 0), Float32(99))


def test_transpose_swaps_rows_and_columns() raises:
    var m = Matrix4()
    m.set(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    m.transpose()
    assert_equal(m.get(0, 1), Float32(5))
    assert_equal(m.get(1, 0), Float32(2))
    assert_equal(m.get(3, 0), Float32(4))


def test_transposing_twice_restores_the_original() raises:
    var m = translation(1, 2, 3)
    var original = m
    m.transpose()
    m.transpose()
    assert_same(m, original)


def test_multiplying_by_the_identity_changes_nothing() raises:
    var m = translation(1, 2, 3)
    var original = m
    m.multiply(Matrix4())
    assert_same(m, original)


def test_multiplication_is_not_commutative() raises:
    # Scaling then translating is not translating then scaling.
    var left = translation(1, 0, 0)
    left.multiply(scaling(2, 2, 2))
    var right = scaling(2, 2, 2)
    right.multiply(translation(1, 0, 0))
    assert_true(left.get(0, 3) != right.get(0, 3))


def test_the_right_hand_matrix_applies_first() raises:
    # m = translate * scale, so a point is scaled, then translated.
    var m = translation(10, 0, 0)
    m.multiply(scaling(2, 2, 2))
    assert_point(m.transform_point(Vector3(1, 0, 0)), 12, 0, 0)


def test_premultiply_reverses_the_order() raises:
    var m = scaling(2, 2, 2)
    m.premultiply(translation(10, 0, 0))
    # Same as translation * scaling: scale first.
    assert_point(m.transform_point(Vector3(1, 0, 0)), 12, 0, 0)


def test_multiplication_matches_a_worked_example() raises:
    var a = Matrix4()
    a.set(1, 2, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    var b = Matrix4()
    b.set(1, 0, 0, 0, 3, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    a.multiply(b)
    # Row 0 of the product is [1*1 + 2*3, 1*0 + 2*1, 0, 0].
    assert_equal(a.get(0, 0), Float32(7))
    assert_equal(a.get(0, 1), Float32(2))


def test_determinant_of_the_identity_is_one() raises:
    assert_equal(Matrix4().determinant(), Float32(1))


def test_determinant_of_a_scale_is_the_volume_factor() raises:
    assert_almost_equal(scaling(2, 3, 4).determinant(), Float32(24))


def test_determinant_of_a_translation_is_one() raises:
    # Moving something does not change its volume.
    assert_almost_equal(translation(5, 6, 7).determinant(), Float32(1))


def test_determinant_of_a_rotation_is_one() raises:
    assert_almost_equal(
        rotation_z(Angle(37.0, DEGREE)).determinant(), Float32(1)
    )


def test_a_flattened_matrix_has_zero_determinant() raises:
    assert_equal(scaling(1, 1, 0).determinant(), Float32(0))


def test_inverting_a_translation_negates_it() raises:
    var m = translation(5, 6, 7)
    m.invert()
    assert_point(m.transform_point(Vector3(5, 6, 7)), 0, 0, 0)


def test_a_matrix_times_its_inverse_is_the_identity() raises:
    var m = translation(1, 2, 3)
    m.multiply(scaling(2, 4, 8))
    var inverse = m
    inverse.invert()
    m.multiply(inverse)
    assert_same(m, Matrix4())


def test_inverting_twice_restores_the_original() raises:
    var m = scaling(2, 4, 8)
    var original = m
    m.invert()
    m.invert()
    assert_same(m, original)


def test_a_singular_matrix_inverts_to_all_zeros() raises:
    # Conspicuous by design: everything collapses to the origin.
    var m = scaling(1, 1, 0)
    m.invert()
    for index in range(16):
        assert_equal(m.elements[index], Float32(0))


def test_transform_point_applies_translation() raises:
    assert_point(
        translation(5, 6, 7).transform_point(Vector3(1, 2, 3)), 6, 8, 10
    )


def test_transform_direction_ignores_translation() raises:
    # A direction has no position, so moving the world must not move it.
    assert_point(
        translation(5, 6, 7).transform_direction(Vector3(1, 2, 3)), 1, 2, 3
    )


def test_transform_direction_still_applies_rotation() raises:
    var r = rotation_z(Angle(90.0, DEGREE))
    assert_point(r.transform_direction(Vector3(1, 0, 0)), 0, 1, 0)


def test_transform_point_applies_scale() raises:
    assert_point(scaling(2, 3, 4).transform_point(Vector3(1, 1, 1)), 2, 3, 4)


def test_perspective_divide_happens() raises:
    # A matrix whose bottom row is not [0 0 0 1] makes w vary with z.
    var m = Matrix4()
    m.set(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0)
    # w becomes z = 2, so x and y are halved.
    assert_point(m.transform_point(Vector3(4, 6, 2)), 2, 3, 1)


def test_rotation_about_x() raises:
    var r = rotation_x(Angle(90.0, DEGREE))
    assert_point(r.transform_point(Vector3(0, 1, 0)), 0, 0, 1)


def test_rotation_about_y() raises:
    var r = rotation_y(Angle(90.0, DEGREE))
    assert_point(r.transform_point(Vector3(0, 0, 1)), 1, 0, 0)


def test_rotation_about_z() raises:
    var r = rotation_z(Angle(90.0, DEGREE))
    assert_point(r.transform_point(Vector3(1, 0, 0)), 0, 1, 0)


def test_rotation_leaves_its_own_axis_alone() raises:
    assert_point(
        rotation_z(Angle(37.0, DEGREE)).transform_point(Vector3(0, 0, 5)),
        0,
        0,
        5,
    )


def test_four_quarter_turns_return_to_the_start() raises:
    var m = Matrix4()
    for _ in range(4):
        m.multiply(rotation_y(Angle(90.0, DEGREE)))
    assert_point(m.transform_point(Vector3(1, 2, 3)), 1, 2, 3)


def test_radians_and_degrees_agree() raises:
    var from_degrees = rotation_z(Angle(180.0, DEGREE))
    var from_radians = rotation_z(Angle(3.14159265, RADIAN))
    assert_same(from_degrees, from_radians)


def test_a_composed_transform_applies_in_the_written_order() raises:
    # Move to the origin, spin, move back: rotation about (10, 0, 0).
    var m = translation(10, 0, 0)
    m.multiply(rotation_z(Angle(90.0, DEGREE)))
    m.multiply(translation(-10, 0, 0))
    assert_point(m.transform_point(Vector3(10, 0, 0)), 10, 0, 0)
    assert_point(m.transform_point(Vector3(11, 0, 0)), 10, 1, 0)


def test_a_zero_w_leaves_the_point_undivided() raises:
    # A degenerate projection gives w = 0. Dividing would be infinity, so the
    # divide is skipped rather than poisoning the result with NaN.
    var m = Matrix4()
    m.set(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0)
    assert_point(m.transform_point(Vector3(4, 6, 2)), 4, 6, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
