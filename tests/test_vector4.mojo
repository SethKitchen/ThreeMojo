# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.vector4`."""

from math.matrix4 import translation
from math.projection import perspective
from math.vector3 import Vector3
from math.vector4 import Vector4
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)

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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
