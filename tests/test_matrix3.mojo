# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.matrix3`."""

from math.matrix3 import Matrix3
from math.matrix4 import Matrix4, rotation_z, scaling, translation
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE

# Rotations produce exact zeros only by luck, so an absolute tolerance.
comptime TOLERANCE = Float64(1e-6)


def assert_same(got: Matrix3, expected: Matrix3) raises:
    """Assert two matrices agree element by element.

    Args:
        got: The matrix to check.
        expected: The matrix it should match.

    Raises:
        Error: If any element differs.
    """
    for index in range(9):
        assert_almost_equal(
            got.elements[index], expected.elements[index], atol=TOLERANCE
        )


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


def assert_flat(got: Vector2, x: Float32, y: Float32) raises:
    """Assert a 2D point matches the given components, within tolerance.

    Args:
        got: The point to check.
        x: Expected x.
        y: Expected y.

    Raises:
        Error: If either component differs.
    """
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)


def counted() -> Matrix3:
    """Return the matrix whose elements read 1 to 9 on paper."""
    var m = Matrix3()
    m.set(1, 2, 3, 4, 5, 6, 7, 8, 9)
    return m^


def invertible() -> Matrix3:
    """Return a matrix with a determinant of one and no zeros to hide
    behind."""
    var m = Matrix3()
    m.set(2, 1, 1, 1, 2, 1, 1, 1, 2)
    return m^


# --- construction and elements ----------------------------------------------


def test_a_new_matrix_is_the_identity() raises:
    var m = Matrix3()
    for row in range(3):
        for column in range(3):
            if row == column:
                assert_equal(m.get(row, column), Float32(1))
            else:
                assert_equal(m.get(row, column), Float32(0))


def test_set_takes_row_major_arguments() raises:
    # The whole point: arguments read like the matrix on paper, and land
    # transposed in memory.
    var m = counted()
    assert_equal(m.get(0, 0), Float32(1))
    assert_equal(m.get(0, 1), Float32(2))
    assert_equal(m.get(0, 2), Float32(3))
    assert_equal(m.get(1, 0), Float32(4))
    assert_equal(m.get(2, 2), Float32(9))
    assert_equal(m.elements[0], Float32(1))
    assert_equal(m.elements[1], Float32(4))
    assert_equal(m.elements[3], Float32(2))
    assert_equal(m.elements[8], Float32(9))


def test_put_writes_one_element() raises:
    var m = Matrix3()
    m.put(1, 2, 42.0)
    assert_equal(m.get(1, 2), Float32(42))
    assert_equal(m.elements[7], Float32(42))


def test_out_of_range_indices_are_rejected() raises:
    # All four edges of the guard, each its own case.
    var m = Matrix3()
    with assert_raises():
        _ = m.get(3, 0)
    with assert_raises():
        _ = m.get(0, 3)
    with assert_raises():
        _ = m.get(-1, 0)
    with assert_raises():
        _ = m.get(0, -1)


def test_out_of_range_writes_are_rejected() raises:
    var m = Matrix3()
    with assert_raises():
        m.put(-1, 0, 1.0)
    with assert_raises():
        m.put(3, 0, 1.0)
    with assert_raises():
        m.put(0, -1, 1.0)
    with assert_raises():
        m.put(0, 3, 1.0)


def test_a_copy_is_a_separate_value() raises:
    var a = counted()
    var b = Matrix3(copy=a)
    b.put(0, 0, 100.0)
    assert_equal(a.get(0, 0), Float32(1))
    assert_equal(b.get(0, 0), Float32(100))


def test_identity_resets_a_modified_matrix() raises:
    var m = counted()
    m.identity()
    assert_same(m, Matrix3())


def test_transpose_swaps_rows_and_columns() raises:
    var m = counted()
    m.transpose()
    var expected = Matrix3()
    expected.set(1, 4, 7, 2, 5, 8, 3, 6, 9)
    assert_same(m, expected)
    m.transpose()
    assert_same(m, counted())


# --- products ---------------------------------------------------------------


def test_multiply_applies_the_right_hand_matrix_first() raises:
    # Scale after moving: the move is scaled too.
    var m = Matrix3.scaling(2, 2)
    m.multiply(Matrix3.translation(1, 0))
    assert_flat(m.transform_point(Vector2(0, 0)), 2, 0)
    # Move after scaling: the move is not.
    var n = Matrix3.translation(1, 0)
    n.multiply(Matrix3.scaling(2, 2))
    assert_flat(n.transform_point(Vector2(0, 0)), 1, 0)


def test_premultiply_is_the_other_order() raises:
    var m = Matrix3.translation(1, 0)
    m.premultiply(Matrix3.scaling(2, 2))
    var n = Matrix3.scaling(2, 2)
    n.multiply(Matrix3.translation(1, 0))
    assert_same(m, n)


def test_multiplying_by_the_identity_changes_nothing() raises:
    var m = counted()
    m.multiply(Matrix3())
    assert_same(m, counted())
    m.premultiply(Matrix3())
    assert_same(m, counted())


def test_a_product_agrees_with_the_matrix4_product() raises:
    # The same two matrices at either size multiply to the same corner.
    var a = counted()
    var b = invertible()
    var small = Matrix3(copy=a)
    small.multiply(b)
    var big = a.as_matrix4()
    big.multiply(b.as_matrix4())
    assert_same(small, Matrix3.from_matrix4(big))


# --- determinant and inverse -----------------------------------------------


def test_the_determinant() raises:
    assert_equal(Matrix3().determinant(), Float32(1))
    assert_equal(Matrix3.scaling(2, 3).determinant(), Float32(6))
    # Rows 1 to 9 are linearly dependent.
    assert_equal(counted().determinant(), Float32(0))
    assert_equal(invertible().determinant(), Float32(4))


def test_the_inverse_undoes_the_matrix() raises:
    var m = invertible()
    var inverse = Matrix3(copy=m)
    inverse.invert()
    m.multiply(inverse)
    assert_same(m, Matrix3())
    var expected = Matrix3()
    expected.set(0.75, -0.25, -0.25, -0.25, 0.75, -0.25, -0.25, -0.25, 0.75)
    assert_same(inverse, expected)


def test_inverting_a_scale_reciprocates_it() raises:
    var m = Matrix3.scaling(2, 4)
    m.invert()
    assert_same(m, Matrix3.scaling(0.5, 0.25))


def test_a_singular_matrix_inverts_to_all_zeros() raises:
    # Conspicuous by design, as `Matrix4.invert` is.
    var m = counted()
    m.invert()
    for index in range(9):
        assert_equal(m.elements[index], Float32(0))


# --- the corner of a Matrix4 -------------------------------------------------


def test_from_matrix4_takes_the_upper_left_corner() raises:
    var big = Matrix4()
    big.set(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    var corner = Matrix3.from_matrix4(big)
    var expected = Matrix3()
    expected.set(1, 2, 3, 5, 6, 7, 9, 10, 11)
    assert_same(corner, expected)


def test_as_matrix4_puts_the_matrix_in_the_corner_and_nothing_else() raises:
    var big = counted().as_matrix4()
    assert_same(Matrix3.from_matrix4(big), counted())
    # The translation column and the bottom row are the identity's.
    for index in [3, 7, 11, 12, 13, 14]:
        assert_equal(big.elements[index], Float32(0))
    assert_equal(big.elements[15], Float32(1))
    assert_true(big.is_affine())


def test_a_rotation_is_its_own_normal_matrix() raises:
    var rotation = rotation_z(Angle(37.0, DEGREE))
    assert_same(Matrix3.normal_matrix(rotation), Matrix3.from_matrix4(rotation))


def test_a_non_uniform_scale_tilts_the_normal_the_other_way() raises:
    # Stretching x by two tilts a 45-degree surface towards the x axis, so
    # its normal must tilt away from it: (1, 1, 0) becomes (0.5, 1, 0).
    var normal = Matrix3.normal_matrix(scaling(2, 1, 1))
    assert_point(normal.transform(Vector3(1, 1, 0)), 0.5, 1, 0)


def test_the_normal_matrix_agrees_with_matrix4s_at_every_element() raises:
    var transform = translation(3, -2, 5)
    transform.multiply(rotation_z(Angle(30.0, DEGREE)))
    transform.multiply(scaling(2, 0.5, 3))
    var small = Matrix3.normal_matrix(transform)
    var big = transform.normal_matrix()
    assert_same(small, Matrix3.from_matrix4(big))


def test_a_collapsed_transform_has_no_normal_matrix() raises:
    with assert_raises():
        _ = Matrix3.normal_matrix(scaling(1, 0, 1))


# --- vectors ----------------------------------------------------------------


def test_transform_turns_a_vector() raises:
    var quarter = Matrix3.from_matrix4(rotation_z(Angle(90.0, DEGREE)))
    assert_point(quarter.transform(Vector3(1, 0, 0)), 0, 1, 0)
    assert_point(quarter.transform(Vector3(0, 0, 2)), 0, 0, 2)


def test_transform_point_moves_a_2d_point() raises:
    # A Vector2 is taken with a third coordinate of one, so the last column
    # reaches it; a Vector3 with z = 0 is not moved by the same matrix.
    var moved = Matrix3.translation(5, -3)
    assert_flat(moved.transform_point(Vector2(1, 1)), 6, -2)
    assert_point(moved.transform(Vector3(1, 1, 0)), 1, 1, 0)


# --- 2D transforms ----------------------------------------------------------


def test_the_2d_builders() raises:
    assert_flat(Matrix3.translation(2, 3).transform_point(Vector2(1, 1)), 3, 4)
    assert_flat(Matrix3.scaling(2, 3).transform_point(Vector2(1, 1)), 2, 3)
    # A quarter turn counter-clockwise takes +x to +y.
    assert_flat(
        Matrix3.rotation(Angle(90.0, DEGREE)).transform_point(Vector2(1, 0)),
        0,
        1,
    )


def test_scale_rotate_and_translate_apply_after_the_matrix() raises:
    var m = Matrix3.translation(1, 0)
    m.scale(2, 2)
    assert_flat(m.transform_point(Vector2(0, 0)), 2, 0)
    m.translate(0, 5)
    assert_flat(m.transform_point(Vector2(0, 0)), 2, 5)
    # `rotate` turns by the negative of the angle, three.js's sign: a
    # quarter turn takes (2, 5) to (5, -2).
    m.rotate(Angle(90.0, DEGREE))
    assert_flat(m.transform_point(Vector2(0, 0)), 5, -2)


def test_the_uv_transform_with_nothing_set_is_the_identity() raises:
    var m = Matrix3.uv_transform(
        Vector2(0, 0), Vector2(1, 1), Angle(0.0, DEGREE), Vector2(0, 0)
    )
    assert_same(m, Matrix3())


def test_the_uv_transform_repeats_offsets_and_turns() raises:
    # Repeat alone scales about the origin.
    var repeated = Matrix3.uv_transform(
        Vector2(0, 0), Vector2(2, 3), Angle(0.0, DEGREE), Vector2(0, 0)
    )
    assert_flat(repeated.transform_point(Vector2(0.5, 0.5)), 1, 1.5)
    # Offset alone moves.
    var shifted = Matrix3.uv_transform(
        Vector2(0.25, 0.1), Vector2(1, 1), Angle(0.0, DEGREE), Vector2(0, 0)
    )
    assert_flat(shifted.transform_point(Vector2(0.5, 0.5)), 0.75, 0.6)
    # A quarter turn about the center turns the coordinates clockwise, so
    # the image appears turned counter-clockwise: the point right of the
    # center goes below it.
    var turned = Matrix3.uv_transform(
        Vector2(0, 0), Vector2(1, 1), Angle(90.0, DEGREE), Vector2(0.5, 0.5)
    )
    assert_flat(turned.transform_point(Vector2(1, 0.5)), 0.5, 0)
    assert_flat(turned.transform_point(Vector2(0.5, 0.5)), 0.5, 0.5)


def test_the_uv_transform_is_the_pieces_composed() raises:
    # three.js's closed form is: move the center to the origin, turn by the
    # negative angle, scale, and move the center back plus the offset.
    var offset = Vector2(0.3, -0.2)
    var repeat = Vector2(2, 0.5)
    var angle = Angle(33.0, DEGREE)
    var center = Vector2(0.4, 0.6)
    var pieces = Matrix3.translation(-center.x, -center.y)
    pieces.rotate(angle)
    pieces.scale(repeat.x, repeat.y)
    pieces.translate(center.x + offset.x, center.y + offset.y)
    assert_same(Matrix3.uv_transform(offset, repeat, angle, center), pieces)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
