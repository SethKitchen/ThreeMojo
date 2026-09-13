# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.rasterizer`."""

from math.vector2 import Vector2
from render.framebuffer import Color, Framebuffer
from math.vector3 import Vector3
from render.rasterizer import Triangle, edge, rasterize, rasterize_depth
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)

# Counter-clockwise on screen (y grows downward), so area2 is positive.
comptime CCW = Triangle(Vector2(0, 0), Vector2(4, 0), Vector2(0, 4))
# Same triangle with two vertices swapped, exercising the negative-area branch.
comptime CW = Triangle(Vector2(0, 0), Vector2(0, 4), Vector2(4, 0))


def test_edge_is_positive_left_of_the_line() raises:
    var value = edge(Vector2(0, 0), Vector2(4, 0), Vector2(2, 1))
    assert_true(value > 0)


def test_edge_is_negative_right_of_the_line() raises:
    var value = edge(Vector2(0, 0), Vector2(4, 0), Vector2(2, -1))
    assert_true(value < 0)


def test_edge_is_zero_on_the_line() raises:
    assert_equal(edge(Vector2(0, 0), Vector2(4, 0), Vector2(2, 0)), Float32(0))


def test_area2_is_twice_the_area() raises:
    assert_equal(CCW.area2(), Float32(16))


def test_area2_is_negative_for_opposite_winding() raises:
    assert_equal(CW.area2(), Float32(-16))


def test_contains_interior_point_counter_clockwise() raises:
    assert_true(CCW.contains(Vector2(1, 1)))


def test_contains_interior_point_clockwise() raises:
    # Covers the `area > 0` guard's false branch.
    assert_true(CW.contains(Vector2(1, 1)))


def test_boundary_points_are_inclusive() raises:
    assert_true(CCW.contains(Vector2(2, 0)))  # on edge a->b
    assert_true(CCW.contains(Vector2(2, 2)))  # on edge b->c
    assert_true(CCW.contains(Vector2(0, 2)))  # on edge c->a
    assert_true(CCW.contains(Vector2(0, 0)))  # on a vertex


def test_boundary_points_are_inclusive_for_either_winding() raises:
    assert_true(CW.contains(Vector2(2, 0)))
    assert_true(CW.contains(Vector2(2, 2)))


def test_excludes_points_outside() raises:
    assert_false(CCW.contains(Vector2(3, 3)))
    assert_false(CCW.contains(Vector2(-1, 1)))
    assert_false(CW.contains(Vector2(3, 3)))


def test_degenerate_triangle_contains_nothing() raises:
    # Three collinear points have zero area; even a point on the line is out.
    var line = Triangle(Vector2(0, 0), Vector2(2, 2), Vector2(4, 4))
    assert_equal(line.area2(), Float32(0))
    assert_false(line.contains(Vector2(1, 1)))


def test_rasterize_covers_exactly_the_pixels_inside() raises:
    var background = Color(0, 0, 0)
    var foreground = Color(255, 128, 32)
    var fb = Framebuffer(8, 8, background)
    rasterize(CCW, fb, foreground)

    var covered = 0
    for y in range(8):
        for x in range(8):
            # Recheck against the predicate at the same sample point.
            var p = Vector2(Float32(x) + 0.5, Float32(y) + 0.5)
            if CCW.contains(p):
                covered += 1
                assert_equal(fb.get_pixel(x, y).r, foreground.r)
            else:
                assert_equal(fb.get_pixel(x, y).r, background.r)
    # Centers land inside when x + y <= 3, so 4 + 3 + 2 + 1 pixels. Note this
    # exceeds the true area of 8 — center sampling is not area-exact.
    assert_equal(covered, 10)


def test_rasterize_leaves_background_when_nothing_is_covered() raises:
    var background = Color(20, 24, 32)
    var fb = Framebuffer(4, 4, background)
    # A triangle entirely off the left of the viewport.
    var offscreen = Triangle(Vector2(-10, 0), Vector2(-6, 0), Vector2(-10, 4))
    rasterize(offscreen, fb, Color(255, 128, 32))
    for y in range(4):
        for x in range(4):
            assert_equal(fb.get_pixel(x, y).r, background.r)


def covering(z: Float32) raises -> List[Vector3]:
    """Return a triangle covering any small viewport, flat at depth `z`.

    Args:
        z: The NDC depth for all three corners.

    Returns:
        Three corners suitable for `rasterize_depth`.

    Raises:
        Error: Never.
    """
    var corners = List[Vector3]()
    corners.append(Vector3(-10, -10, z))
    corners.append(Vector3(40, -10, z))
    corners.append(Vector3(-10, 40, z))
    return corners^


def test_a_nearer_triangle_drawn_second_wins() raises:
    var fb = Framebuffer(4, 4, Color(0, 0, 0))
    var far = covering(0.9)
    var near = covering(0.1)
    rasterize_depth(far[0], far[1], far[2], fb, Color(255, 0, 0))
    rasterize_depth(near[0], near[1], near[2], fb, Color(0, 255, 0))
    assert_equal(fb.get_pixel(0, 0).g, UInt8(255))


def test_a_further_triangle_drawn_second_is_rejected() raises:
    # The point of depth: the result does not depend on submission order.
    var fb = Framebuffer(4, 4, Color(0, 0, 0))
    var near = covering(0.1)
    var far = covering(0.9)
    rasterize_depth(near[0], near[1], near[2], fb, Color(0, 255, 0))
    rasterize_depth(far[0], far[1], far[2], fb, Color(255, 0, 0))
    assert_equal(fb.get_pixel(0, 0).g, UInt8(255))
    # Interpolated, not copied: the barycentric weights sum to 1 only to
    # within rounding, so even a flat triangle's depth is approximate.
    assert_almost_equal(fb.depth_at(0, 0), Float32(0.1), atol=Float64(1e-6))


def test_depth_is_interpolated_across_the_triangle() raises:
    # A triangle tilted in depth: near on the left, far on the right.
    var fb = Framebuffer(8, 8, Color(0, 0, 0))
    rasterize_depth(
        Vector3(-10, -10, 0.0),
        Vector3(40, -10, 1.0),
        Vector3(-10, 40, 0.0),
        fb,
        Color(9, 9, 9),
    )
    assert_true(fb.depth_at(0, 0) < fb.depth_at(7, 0))


def test_a_degenerate_triangle_draws_nothing() raises:
    var fb = Framebuffer(4, 4, Color(1, 2, 3))
    rasterize_depth(
        Vector3(0, 0, 0.5),
        Vector3(2, 2, 0.5),
        Vector3(4, 4, 0.5),
        fb,
        Color(255, 0, 0),
    )
    assert_equal(fb.get_pixel(2, 2).r, UInt8(1))


def test_depth_rasterization_covers_the_same_pixels_as_the_flat_one() raises:
    # The two must agree on coverage; only the depth test differs.
    var flat_target = Framebuffer(8, 8, Color(0, 0, 0))
    var depth_target = Framebuffer(8, 8, Color(0, 0, 0))
    var triangle = Triangle(Vector2(1, 6), Vector2(4, 1), Vector2(7, 6))
    rasterize(triangle, flat_target, Color(255, 128, 32))
    rasterize_depth(
        Vector3(1, 6, 0.5),
        Vector3(4, 1, 0.5),
        Vector3(7, 6, 0.5),
        depth_target,
        Color(255, 128, 32),
    )
    for y in range(8):
        for x in range(8):
            assert_equal(
                flat_target.get_pixel(x, y).r, depth_target.get_pixel(x, y).r
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
