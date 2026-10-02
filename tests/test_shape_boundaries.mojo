# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whole sampled hole boundaries, independent surface oracles, and #490."""

from core.buffer_geometry import BufferGeometry
from geometries.extrude import extrude
from geometries.shape import extract_points, shape_geometry, triangulate
from math.path import Path, Shape
from math.vector2 import Vector2
from tests.test_shape import box_path, polygon, square
from units.si import Length, METER
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def refuse(shape: Shape, divisions: Int = 1) raises:
    """Require rejection at the shared boundary and every public builder."""
    with assert_raises():
        _ = extract_points(shape, divisions)
    with assert_raises():
        _ = triangulate(shape, divisions)
    with assert_raises():
        _ = shape_geometry(shape, divisions)
    with assert_raises():
        _ = extrude(shape, Length(1, METER), curve_segments=divisions)


def notched_points() -> List[Vector2]:
    """Return the area-28 outline around an open two-by-four notch."""
    return [
        Vector2(0, 0),
        Vector2(6, 0),
        Vector2(6, 6),
        Vector2(4, 6),
        Vector2(4, 2),
        Vector2(2, 2),
        Vector2(2, 6),
        Vector2(0, 6),
    ]


def test_hole_with_first_corner_inside_cannot_escape_outline() raises:
    var shape = square(4)
    shape.add_hole(box_path(3, 1, 5, 3))
    refuse(shape)


def test_inside_corners_cannot_bridge_a_concave_notch() raises:
    var outside = notched_points()
    var hole: List[Vector2] = [
        Vector2(1, 4),
        Vector2(5, 4),
        Vector2(5, 5),
        Vector2(1, 5),
    ]
    # Every starting corner and both windings must give the same refusal.
    for _ in range(2):
        for start in range(4):
            var rotated = List[Vector2]()
            for at in range(4):
                rotated.append(hole[(start + at) % 4])
            var shape = Shape(polygon(outside))
            shape.add_hole(polygon(rotated))
            refuse(shape)
        outside.reverse()
        hole.reverse()


def test_crossed_holes_are_refused_even_when_first_corners_are_apart() raises:
    for reverse in range(2):
        var shape = square(8)
        var horizontal = box_path(1, 3, 7, 4)
        var vertical = box_path(3, 1, 4, 7)
        if reverse == 0:
            shape.add_hole(horizontal^)
            shape.add_hole(vertical^)
        else:
            shape.add_hole(vertical^)
            shape.add_hole(horizontal^)
        refuse(shape)


def test_holes_cannot_touch_any_outline_side_or_corner() raises:
    var cases: List[List[Vector2]] = [
        [Vector2(1, 1), Vector2(4, 1), Vector2(3, 2)],
        [Vector2(1, 1), Vector2(1, 0), Vector2(3, 1)],
        [Vector2(1, 1), Vector2(0, 2), Vector2(1, 3)],
        [Vector2(1, 1), Vector2(3, 4), Vector2(1, 3)],
        [Vector2(1, 1), Vector2(4, 4), Vector2(1, 3)],
        [Vector2(1, 1), Vector2(4, 1), Vector2(4, 3), Vector2(1, 3)],
    ]
    for points in cases:
        var shape = square(4)
        shape.add_hole(polygon(points))
        refuse(shape)


def test_holes_cannot_touch_each_other_or_coincide() raises:
    var cases: List[List[Vector2]] = [
        [Vector2(3, 3), Vector2(5, 3), Vector2(5, 5), Vector2(3, 5)],
        [Vector2(3, 1), Vector2(5, 1), Vector2(5, 3), Vector2(3, 3)],
        [Vector2(1, 1), Vector2(3, 1), Vector2(3, 3), Vector2(1, 3)],
        [Vector2(2, 3), Vector2(4, 5), Vector2(1, 5)],
    ]
    for points in cases:
        var shape = square(8)
        shape.add_hole(box_path(1, 1, 3, 3))
        shape.add_hole(polygon(points))
        refuse(shape)


def test_nested_holes_are_refused_in_both_input_orders() raises:
    for reverse in range(2):
        var shape = square(8)
        if reverse == 0:
            shape.add_hole(box_path(1, 1, 7, 7))
            shape.add_hole(box_path(2, 2, 3, 3))
        else:
            shape.add_hole(box_path(2, 2, 3, 3))
            shape.add_hole(box_path(1, 1, 7, 7))
        refuse(shape)


def test_original_samples_are_checked_before_tolerance_cleaning() raises:
    var shape = square(4)
    shape.add_hole(
        polygon(
            [
                Vector2(1, 1),
                Vector2(3.9999998, 1),
                Vector2(4.0000005, 2),
                Vector2(3.9999998, 3),
                Vector2(1, 3),
            ]
        )
    )
    refuse(shape)


def test_a_positive_representable_gap_is_not_contact() raises:
    var shape = square(4)
    shape.add_hole(box_path(1, 1, 3.9999998, 3))
    var sampled = extract_points(shape, 1)
    assert_equal(sampled.holes[0][1].x, Float32(3.9999998))
    assert_true(triangulate(shape, 1).triangle_count() > 0)


def test_curved_hole_samples_cannot_escape_or_touch() raises:
    for x in [Float32(5), Float32(7)]:
        var hole = Path(Vector2(1, 1))
        hole.cubic_to(Vector2(x, 1), Vector2(x, 3), Vector2(1, 3))
        hole.line_to(Vector2(0.5, 3))
        hole.line_to(Vector2(0.5, 1))
        hole.close_path()
        var shape = square(4)
        shape.add_hole(hole^)
        refuse(shape, 8)


def projected_area(geometry: BufferGeometry, bound: Float64) raises -> Float64:
    """Sum absolute projected areas without using any library predicate.

    Walls of an unbeveled extrusion contribute zero. Each cap contributes
    its area. Check every triangle's bounds and every arithmetic result.
    """
    var area = Float64(0)
    for triangle in range(geometry.triangle_count()):
        var a = geometry.corner(triangle, 0)
        var b = geometry.corner(triangle, 1)
        var c = geometry.corner(triangle, 2)
        for point in [a, b, c]:
            assert_true(point.x >= 0)
            assert_true(point.y >= 0)
            assert_true(Float64(point.x) <= bound)
            assert_true(Float64(point.y) <= bound)
        var x1 = Float64(b.x) - Float64(a.x)
        var y1 = Float64(b.y) - Float64(a.y)
        var x2 = Float64(c.x) - Float64(a.x)
        var y2 = Float64(c.y) - Float64(a.y)
        area += abs(x1 * y2 - y1 * x2) / 2
    return area


def test_valid_concave_outline_and_multiple_holes_keep_area_and_bounds() raises:
    var shape = Shape(polygon(notched_points()))
    shape.add_hole(box_path(0.5, 3, 1.5, 5))
    shape.add_hole(box_path(4.5, 3, 5.5, 5))
    var flat = shape_geometry(shape, 1)
    assert_equal(projected_area(flat, 6), Float64(24))
    # Independent axis-aligned notch oracle: triangle centers and edge
    # midpoints must stay out of the empty open notch.
    for triangle in range(flat.triangle_count()):
        var a = flat.corner(triangle, 0)
        var b = flat.corner(triangle, 1)
        var c = flat.corner(triangle, 2)
        for point in [(a + b + c) / 3, (a + b) / 2, (b + c) / 2, (c + a) / 2]:
            assert_true(point.x <= 2 or point.x >= 4 or point.y <= 2)
    var solid = extrude(shape, Length(2, METER), curve_segments=1)
    assert_equal(projected_area(solid, 6), Float64(48))


def test_valid_concave_hole_and_second_hole_keep_area_and_samples() raises:
    var shape = square(8)
    var hole: List[Vector2] = [
        Vector2(1, 1),
        Vector2(5, 1),
        Vector2(5, 2),
        Vector2(2, 2),
        Vector2(2, 5),
        Vector2(1, 5),
    ]
    shape.add_hole(polygon(hole))
    shape.add_hole(box_path(6, 6, 7, 7))
    var sampled = extract_points(shape, 1)
    assert_equal(len(sampled.holes[0]), 7)
    for at in range(6):
        assert_true(sampled.holes[0][at] == hole[at])
    assert_equal(projected_area(shape_geometry(shape, 1), 8), Float64(56))
    assert_equal(
        projected_area(extrude(shape, Length(1, METER), curve_segments=1), 8),
        Float64(112),
    )


def test_disjoint_diagonal_boundaries_can_have_overlapping_boxes() raises:
    var shape = Shape(
        polygon(
            [
                Vector2(0, 0),
                Vector2(8, 0),
                Vector2(0, 8),
            ]
        )
    )
    shape.add_hole(
        polygon(
            [
                Vector2(1, 1),
                Vector2(3, 1),
                Vector2(1, 3),
            ]
        )
    )
    shape.add_hole(
        polygon(
            [
                Vector2(4, 1),
                Vector2(5, 1),
                Vector2(4, 2),
            ]
        )
    )
    assert_equal(projected_area(shape_geometry(shape, 1), 8), Float64(29.5))
    assert_equal(
        projected_area(extrude(shape, Length(1, METER), curve_segments=1), 8),
        Float64(59),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
