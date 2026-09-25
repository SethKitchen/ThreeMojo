# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.shape`: the triangulation and the flat surface it
fills in.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.extrude import bevel_vector, extrude
from geometries.shape import (
    Contours,
    extent,
    is_clockwise,
    shape_geometry,
    triangulate,
    turn,
)
from math.path import Path, Shape
from math.vector2 import Vector2
from units.si import Length, METER
from std.math import isfinite
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-4)


def polygon(corners: List[Vector2]) raises -> Path:
    """Return the closed path through `corners`, corner after corner."""
    var pen = Path(corners[0])
    for index in range(1, len(corners)):
        pen.line_to(corners[index])
    pen.close_path()
    return pen^


def square(side: Float32) raises -> Shape:
    """Return a square of `side` meters with a corner at the origin."""
    return Shape(
        polygon(
            [
                Vector2(0, 0),
                Vector2(side, 0),
                Vector2(side, side),
                Vector2(0, side),
            ]
        )
    )


def box_path(
    low_x: Float32, low_y: Float32, high_x: Float32, high_y: Float32
) raises -> Path:
    """Return a closed rectangle between two corners."""
    return polygon(
        [
            Vector2(low_x, low_y),
            Vector2(high_x, low_y),
            Vector2(high_x, high_y),
            Vector2(low_x, high_y),
        ]
    )


def filled_area(cut: Contours) raises -> Float32:
    """Return the area the triangles cover, and assert every one of them is
    wound counter-clockwise."""
    var total = Float32(0)
    for triangle in range(cut.triangle_count()):
        var first = cut.points[cut.index[triangle * 3]]
        var second = cut.points[cut.index[triangle * 3 + 1]]
        var third = cut.points[cut.index[triangle * 3 + 2]]
        var doubled = turn(first, second, third)
        assert_true(doubled >= 0, "a triangle is wound backwards")
        total += doubled
    return total / 2


def covered_by(cut: Contours, probe: Vector2) raises -> Int:
    """Return how many triangles cover `probe`, the boundary counting as
    covered. Every triangle is wound counter-clockwise, which `filled_area`
    has asserted."""
    var hits = 0
    for triangle in range(cut.triangle_count()):
        var first = cut.points[cut.index[triangle * 3]]
        var second = cut.points[cut.index[triangle * 3 + 1]]
        var third = cut.points[cut.index[triangle * 3 + 2]]
        if (
            turn(first, second, probe) >= 0
            and turn(second, third, probe) >= 0
            and turn(third, first, probe) >= 0
        ):
            hits += 1
    return hits


def small_l() raises -> Shape:
    """Return a two by two square with a one by one bite out of the far
    corner. Its first diagonal runs corner to corner, straight through the
    notch."""
    return Shape(
        polygon(
            [
                Vector2(0, 0),
                Vector2(2, 0),
                Vector2(2, 1),
                Vector2(1, 1),
                Vector2(1, 2),
                Vector2(0, 2),
            ]
        )
    )


def test_turn_says_which_way() raises:
    var origin = Vector2(0, 0)
    assert_true(turn(origin, Vector2(1, 0), Vector2(0, 1)) > 0)
    assert_true(turn(origin, Vector2(0, 1), Vector2(1, 0)) < 0)
    assert_equal(turn(origin, Vector2(1, 0), Vector2(2, 0)), Float32(0))


def test_a_square_takes_two_triangles() raises:
    var cut = triangulate(square(4), 1)
    assert_equal(cut.contour_count(), 1)
    assert_equal(cut.triangle_count(), 2)
    assert_almost_equal(filled_area(cut), Float32(16), atol=TOLERANCE)


def test_a_triangle_is_clipped_without_a_single_ear() raises:
    # Three corners: there is nothing to clip, and the loop ends at once.
    var cut = triangulate(
        Shape(polygon([Vector2(0, 0), Vector2(4, 0), Vector2(0, 4)])), 1
    )
    assert_equal(cut.triangle_count(), 1)
    assert_almost_equal(filled_area(cut), Float32(8), atol=TOLERANCE)


def test_a_clockwise_outline_is_turned_around() raises:
    var cut = triangulate(
        Shape(
            polygon(
                [
                    Vector2(0, 0),
                    Vector2(0, 4),
                    Vector2(4, 4),
                    Vector2(4, 0),
                ]
            )
        ),
        1,
    )
    assert_almost_equal(filled_area(cut), Float32(16), atol=TOLERANCE)


def test_a_concave_outline_keeps_its_notch() raises:
    # An L: the corner at (1, 1) turns the other way, and no ear may be
    # clipped across it.
    var cut = triangulate(
        Shape(
            polygon(
                [
                    Vector2(0, 0),
                    Vector2(4, 0),
                    Vector2(4, 1),
                    Vector2(1, 1),
                    Vector2(1, 4),
                    Vector2(0, 4),
                ]
            )
        ),
        1,
    )
    assert_equal(cut.triangle_count(), 4)
    assert_almost_equal(filled_area(cut), Float32(7), atol=TOLERANCE)


def test_a_notch_on_the_first_diagonal_is_not_clipped_across() raises:
    # The corner at (1, 1) sits exactly on the diagonal from (0, 2) to
    # (2, 0). A strictly-inside test does not see it, the ear is clipped
    # across the notch, and the triangles cover three and a half square
    # meters of a three square meter shape with one wound backwards.
    for divisions in [1, 12, 50]:
        var cut = triangulate(small_l(), divisions)
        assert_almost_equal(filled_area(cut), Float32(3), atol=TOLERANCE)
        for triangle in range(cut.triangle_count()):
            var first = cut.points[cut.index[triangle * 3]]
            var second = cut.points[cut.index[triangle * 3 + 1]]
            var third = cut.points[cut.index[triangle * 3 + 2]]
            assert_true(
                turn(first, second, third) > 0, "a triangle has no area"
            )
        # Two points in the bite, which nothing may cover.
        assert_equal(covered_by(cut, Vector2(1.5, 1.1)), 0)
        assert_equal(covered_by(cut, Vector2(1.5, 1.5)), 0)
        # And one in the shape, which something must.
        assert_true(covered_by(cut, Vector2(0.5, 0.5)) > 0)


def test_is_clockwise_reads_the_signed_area() raises:
    # three.js's `ShapeUtils.isClockWise`: the area is below zero.
    var counter: List[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
    assert_false(is_clockwise(counter))
    counter.reverse()
    assert_true(is_clockwise(counter))
    # No area is not clockwise.
    assert_false(is_clockwise([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)]))


def test_extent_is_the_box_around_a_contour() raises:
    var points: List[Vector2] = [
        Vector2(1, 1),
        Vector2(4, 1),
        Vector2(4, 5),
    ]
    assert_almost_equal(extent(points, 0, 3), Float32(5), atol=TOLERANCE)
    assert_almost_equal(extent(points, 0, 1), Float32(0), atol=TOLERANCE)


def test_a_small_shape_survives_any_sample_count() raises:
    # Five millimeters on a side. A fixed area threshold called its true
    # corners flat at twelve runs an edge and threw the shape away, and
    # sampling it more finely made it disappear rather than improve.
    for divisions in [1, 4, 12, 24, 100]:
        var cut = triangulate(square(0.005), divisions)
        assert_equal(cut.triangle_count(), 2)
        assert_almost_equal(
            filled_area(cut), Float32(2.5e-5), atol=Float64(1e-12)
        )


def test_a_large_shape_is_measured_the_same_way() raises:
    # The same L a kilometer across. A tolerance taken as a share of the
    # shape answers both the same way.
    var cut = triangulate(square(2000), 4)
    assert_equal(cut.triangle_count(), 2)
    assert_almost_equal(filled_area(cut), Float32(4000000), atol=Float64(1))


def test_a_hole_is_seamed_in_and_left_empty() raises:
    var plate = square(4)
    plate.add_hole(box_path(1, 1, 3, 3))
    var cut = triangulate(plate, 1)
    assert_equal(cut.contour_count(), 2)
    assert_almost_equal(filled_area(cut), Float32(12), atol=TOLERANCE)


def test_a_hole_given_the_other_way_round_is_turned_around() raises:
    var plate = square(4)
    plate.add_hole(
        polygon([Vector2(1, 1), Vector2(1, 3), Vector2(3, 3), Vector2(3, 1)])
    )
    var cut = triangulate(plate, 1)
    assert_almost_equal(filled_area(cut), Float32(12), atol=TOLERANCE)


def test_two_holes_are_seamed_in_one_after_another() raises:
    var plate = square(4)
    plate.add_hole(box_path(0.5, 0.5, 1.5, 1.5))
    plate.add_hole(box_path(2.5, 2.5, 3.5, 3.5))
    var cut = triangulate(plate, 1)
    assert_equal(cut.contour_count(), 3)
    assert_almost_equal(filled_area(cut), Float32(14), atol=TOLERANCE)


def test_a_seam_goes_around_a_hole_in_its_way() raises:
    # The bar lies between the block and the nearest edge, so the shortest
    # pair that can see each other is not the shortest pair.
    var plate = square(10)
    plate.add_hole(box_path(4, 4, 6, 6))
    plate.add_hole(box_path(0.5, 2, 9.5, 2.5))
    var cut = triangulate(plate, 1)
    assert_almost_equal(filled_area(cut), Float32(91.5), atol=TOLERANCE)


def test_a_curve_is_sampled_into_the_outline() raises:
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(4, 0))
    pen.quadratic_to(Vector2(4, 4), Vector2(0, 4))
    pen.close_path()
    var coarse = triangulate(Shape(Path(copy=pen)), 1)
    var fine = triangulate(Shape(pen^), 8)
    assert_true(fine.triangle_count() > coarse.triangle_count())
    # A finer sample of a curve that bulges outward covers more.
    assert_true(filled_area(fine) > filled_area(coarse))


# --- what is refused --------------------------------------------------------


def test_a_contour_of_two_points_is_refused() raises:
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(1, 0))
    pen.close_path()
    with assert_raises():
        _ = triangulate(Shape(pen^), 1)


def test_a_contour_drawn_in_a_line_is_refused() raises:
    # Three points in a line are one edge, and one edge is not a contour.
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(1, 0))
    pen.line_to(Vector2(2, 0))
    pen.close_path()
    with assert_raises():
        _ = triangulate(Shape(pen^), 1)


def test_a_contour_with_no_area_is_refused() raises:
    # A bow tie: four corners, none of them in a line with its neighbors,
    # and two halves that cancel each other out exactly.
    with assert_raises():
        _ = triangulate(
            Shape(
                polygon(
                    [
                        Vector2(0, 0),
                        Vector2(2, 0),
                        Vector2(0, 2),
                        Vector2(2, 2),
                    ]
                )
            ),
            1,
        )


def test_an_outline_that_crosses_itself_is_filled_as_three_js_fills_it() raises:
    # earcut fills a crossing outline rather than refuse it, as three.js
    # does: every corner is kept, and some triangles are cut.
    var cut = triangulate(
        Shape(
            polygon(
                [
                    Vector2(2, 1),
                    Vector2(4, 4),
                    Vector2(3, 2),
                    Vector2(2, 5),
                    Vector2(0, 2),
                    Vector2(0, 5),
                ]
            )
        ),
        1,
    )
    assert_equal(len(cut.points), 6)
    assert_true(cut.triangle_count() > 0)


def test_a_hole_outside_the_outline_is_refused() raises:
    var plate = square(4)
    plate.add_hole(box_path(20, 20, 21, 21))
    with assert_raises():
        _ = triangulate(plate, 1)


def test_a_hole_inside_another_hole_is_refused() raises:
    var plate = square(4)
    plate.add_hole(box_path(1, 1, 3, 3))
    plate.add_hole(box_path(1.5, 1.5, 2.5, 2.5))
    with assert_raises():
        _ = triangulate(plate, 1)


def test_a_shape_needs_at_least_one_division() raises:
    with assert_raises():
        _ = triangulate(square(4), 0)


# --- the geometry -----------------------------------------------------------


def test_shape_geometry_is_flat_and_faces_the_camera() raises:
    var geometry = shape_geometry(square(4), 1)
    assert_equal(geometry.vertex_count(), 4)
    assert_equal(geometry.triangle_count(), 2)
    ref positions = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    ref uvs = geometry.attribute_view(String(UV))
    for vertex in range(geometry.vertex_count()):
        assert_equal(positions.component(vertex, 2), Float32(0))
        assert_equal(normals.component(vertex, 0), Float32(0))
        assert_equal(normals.component(vertex, 1), Float32(0))
        assert_equal(normals.component(vertex, 2), Float32(1))
        # three.js's default generator: the texture coordinate is the point.
        assert_equal(uvs.component(vertex, 0), positions.component(vertex, 0))
        assert_equal(uvs.component(vertex, 1), positions.component(vertex, 1))


def test_shape_geometry_carries_a_hole_through() raises:
    var plate = square(4)
    plate.add_hole(box_path(1, 1, 3, 3))
    var geometry = shape_geometry(plate, 1)
    assert_equal(geometry.vertex_count(), 8)
    assert_equal(geometry.triangle_count(), 8)


def test_shape_geometry_refuses_what_triangulate_refuses() raises:
    with assert_raises():
        _ = shape_geometry(square(4), 0)


# --- the extrusion ----------------------------------------------------------


def moved(before: Vector2, point: Vector2, after: Vector2) -> Vector2:
    """Return `bevel_vector` of a point as a `Vector2`."""
    var out = bevel_vector(point, before, after)
    return Vector2(Float32(out[0]), Float32(out[1]))


def assert_near(got: Vector2, x: Float32, y: Float32) raises:
    """Assert a vector's two numbers."""
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)


def test_a_point_in_a_line_moves_as_get_bevel_vec_moves_it() raises:
    # Running on: one unit square to the run, to its left.
    assert_near(moved(Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)), 0, 1)
    assert_near(moved(Vector2(2, 0), Vector2(1, 0), Vector2(0, 0)), 0, -1)
    assert_near(moved(Vector2(0, 0), Vector2(0, 1), Vector2(0, 2)), -1, 0)
    # Folding straight back: along the run, by the square root of two.
    var root = Float32(1.4142135)
    assert_near(moved(Vector2(0, 0), Vector2(1, 0), Vector2(0, 0)), root, 0)
    assert_near(moved(Vector2(1, 0), Vector2(0, 0), Vector2(1, 0)), -root, 0)
    assert_near(moved(Vector2(0, 0), Vector2(0, 1), Vector2(0, 0)), 0, root)
    # A next point on top of this one has no direction, which three.js
    # reads as folding back.
    assert_near(moved(Vector2(0, 0), Vector2(0, 1), Vector2(0, 1)), 0, root)


def closed_volume(geometry: BufferGeometry) raises -> Float32:
    """Return the volume a closed surface encloses.

    Every triangle makes a cone back to the origin, and the signed volumes
    of those cones add up to the volume inside. A surface that is not
    closed, or one with a face wound the wrong way, gives a number that is
    not the volume, which is what makes this worth asserting on.
    """
    var total = Float32(0)
    for triangle in range(geometry.triangle_count()):
        var first = geometry.corner(triangle, 0)
        var second = geometry.corner(triangle, 1)
        var third = geometry.corner(triangle, 2)
        var crossed = second
        crossed.cross(third)
        total += first.dot(crossed)
    return total / 6


def test_a_square_extrudes_into_a_box() raises:
    var solid = extrude(square(4), Length(2, METER))
    # Two triangles a cap, two caps, and four walls of two triangles each.
    assert_equal(solid.triangle_count(), 12)
    assert_equal(solid.vertex_count(), 36)
    assert_almost_equal(closed_volume(solid), Float32(32), atol=TOLERANCE)
    var box = solid.bounding_box()
    assert_almost_equal(box.min.z, Float32(0), atol=TOLERANCE)
    assert_almost_equal(box.max.z, Float32(2), atol=TOLERANCE)
    assert_almost_equal(box.max.x, Float32(4), atol=TOLERANCE)


def test_steps_cut_the_walls_up_without_changing_the_solid() raises:
    var one = extrude(square(4), Length(2, METER))
    var three = extrude(square(4), Length(2, METER), steps=3)
    assert_equal(three.triangle_count(), 4 + 4 * 3 * 2)
    assert_almost_equal(
        closed_volume(three), closed_volume(one), atol=TOLERANCE
    )


def test_a_hole_becomes_a_shaft_through_the_solid() raises:
    var plate = square(4)
    plate.add_hole(box_path(1, 1, 3, 3))
    var solid = extrude(plate, Length(2, METER))
    # Sixteen cap triangles, and eight walls of two triangles each.
    assert_equal(solid.triangle_count(), 16 + 16)
    assert_almost_equal(closed_volume(solid), Float32(24), atol=TOLERANCE)


def test_the_caps_face_away_from_each_other() raises:
    var solid = extrude(square(4), Length(2, METER))
    ref normals = solid.attribute_view(String(NORMAL))
    # The back cap's two triangles come first and the front cap's two
    # next, as three.js's `buildLidFaces` writes them.
    assert_almost_equal(normals.component(0, 2), Float32(-1), atol=TOLERANCE)
    assert_almost_equal(normals.component(3, 2), Float32(-1), atol=TOLERANCE)
    assert_almost_equal(normals.component(6, 2), Float32(1), atol=TOLERANCE)


def test_a_cap_is_textured_by_where_its_points_are() raises:
    var solid = extrude(square(4), Length(2, METER))
    ref positions = solid.attribute_view(String(POSITION))
    ref uvs = solid.attribute_view(String(UV))
    for vertex in range(6):
        assert_equal(uvs.component(vertex, 0), positions.component(vertex, 0))
        assert_equal(uvs.component(vertex, 1), positions.component(vertex, 1))


def test_a_wall_is_measured_along_whichever_axis_it_covers() raises:
    var solid = extrude(square(4), Length(2, METER))
    ref positions = solid.attribute_view(String(POSITION))
    ref uvs = solid.attribute_view(String(UV))
    # Past the two caps every vertex is on a wall, and a square has walls
    # of both kinds: two that run along x and two that run along y.
    var along_x = 0
    var along_y = 0
    for vertex in range(12, solid.vertex_count()):
        assert_equal(
            uvs.component(vertex, 1), 1 - positions.component(vertex, 2)
        )
        if uvs.component(vertex, 0) == positions.component(vertex, 0):
            along_x += 1
        if uvs.component(vertex, 0) == positions.component(vertex, 1):
            along_y += 1
    assert_true(along_x > 0)
    assert_true(along_y > 0)


def test_a_bevel_stands_the_body_out_past_the_end_faces() raises:
    var plain = extrude(square(4), Length(2, METER))
    var rounded = extrude(
        square(4),
        Length(2, METER),
        bevel_enabled=True,
        bevel_thickness=Length(0.5, METER),
        bevel_size=Length(0.25, METER),
        bevel_segments=2,
    )
    var box = rounded.bounding_box()
    # The bevel reaches past both ends, and the body stands out all round.
    assert_almost_equal(box.min.z, Float32(-0.5), atol=TOLERANCE)
    assert_almost_equal(box.max.z, Float32(2.5), atol=TOLERANCE)
    assert_almost_equal(box.min.x, Float32(-0.25), atol=TOLERANCE)
    assert_almost_equal(box.max.x, Float32(4.25), atol=TOLERANCE)
    # Still one closed solid, and a larger one than the square prism.
    assert_true(closed_volume(rounded) > closed_volume(plain))
    # And smaller than the box it sits in, because the ends are cut back.
    assert_true(closed_volume(rounded) < Float32(4.5 * 4.5 * 3))


def test_a_bevel_offset_moves_the_end_faces_out_too() raises:
    var lipped = extrude(
        square(4),
        Length(2, METER),
        bevel_enabled=True,
        bevel_thickness=Length(0.5, METER),
        bevel_size=Length(0.25, METER),
        bevel_offset=Length(0.5, METER),
        bevel_segments=2,
    )
    var box = lipped.bounding_box()
    assert_almost_equal(box.min.x, Float32(-0.75), atol=TOLERANCE)


def test_a_bevel_around_a_hole_narrows_the_shaft() raises:
    var plate = square(6)
    plate.add_hole(box_path(2, 2, 4, 4))
    var solid = extrude(
        plate,
        Length(2, METER),
        bevel_enabled=True,
        bevel_thickness=Length(0.25, METER),
        bevel_size=Length(0.25, METER),
        bevel_segments=2,
    )
    assert_true(closed_volume(solid) > Float32(0))


def test_an_extrusion_refuses_what_it_cannot_build() raises:
    with assert_raises():
        _ = extrude(square(4), Length(0, METER))
    with assert_raises():
        _ = extrude(square(4), Length(2, METER), steps=0)
    with assert_raises():
        _ = extrude(square(4), Length(2, METER), curve_segments=0)
    with assert_raises():
        _ = extrude(
            square(4),
            Length(2, METER),
            bevel_enabled=True,
            bevel_segments=0,
        )
    with assert_raises():
        _ = extrude(
            square(4),
            Length(2, METER),
            bevel_enabled=True,
            bevel_thickness=Length(0, METER),
        )
    with assert_raises():
        _ = extrude(
            square(4),
            Length(2, METER),
            bevel_enabled=True,
            bevel_size=Length(-1, METER),
        )


def thin_triangle() raises -> Shape:
    """Return a triangle ten meters long and a millimeter thick. Its point
    is sharp enough that the two outward normals there come out opposite in
    Float32, and their dot product rounds to exactly minus one."""
    return Shape(polygon([Vector2(0, 0), Vector2(10, 0), Vector2(0, 0.001)]))


def assert_all_finite(geometry: BufferGeometry) raises:
    """Assert every number in the geometry is a number."""
    ref positions = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    for vertex in range(geometry.vertex_count()):
        for part in range(3):
            assert_true(
                isfinite(positions.component(vertex, part)),
                "a position is not a number",
            )
            assert_true(
                isfinite(normals.component(vertex, part)),
                "a normal is not a number",
            )


def test_a_sharp_corner_extrudes_without_a_bevel() raises:
    # The miter at the point is not a number, and multiplying it by an
    # inset of zero does not make it one. Without a bevel there is no
    # inset, so there is no miter to work out.
    var solid = extrude(thin_triangle(), Length(2, METER))
    assert_all_finite(solid)
    assert_almost_equal(closed_volume(solid), Float32(0.01), atol=Float64(1e-6))


def test_a_sharp_corner_bevels_to_the_miter_limit() raises:
    # The two normals at the point come out opposite, so the exact miter
    # is not a number. three.js moves such a corner along its incoming
    # edge by the square root of two bevel widths, and so does this: the
    # solid is finite and only a little longer than the outline.
    var solid = extrude(
        thin_triangle(),
        Length(2, METER),
        bevel_enabled=True,
        bevel_thickness=Length(0.1, METER),
        bevel_size=Length(0.05, METER),
        bevel_segments=2,
    )
    assert_all_finite(solid)
    var box = solid.bounding_box()
    assert_true(box.max.x > 10)
    assert_true(box.max.x < 10 + 0.05 * 1.5)


def test_a_bevel_stands_a_sharp_corner_out_no_further_than_three_js() raises:
    # An equilateral corner turns sixty degrees, where the exact miter is
    # twice the bevel width; three.js caps it at the square root of two,
    # so the beveled solid reaches less far past the point than the miter
    # would take it.
    var spike = Shape(
        polygon([Vector2(0, 0), Vector2(4, 0), Vector2(2, 3.4641)])
    )
    var solid = extrude(
        spike,
        Length(1, METER),
        bevel_enabled=True,
        bevel_thickness=Length(0.5, METER),
        bevel_size=Length(0.5, METER),
        bevel_segments=1,
    )
    var box = solid.bounding_box()
    # Straight up from the top point: the exact miter would reach 1.0
    # past it, the capped one reaches about 0.707.
    assert_almost_equal(box.max.y, Float32(3.4641 + 0.7071), atol=Float64(1e-3))
    # And a right angle is where the two agree: the square's corners still
    # stand out by exactly the bevel size along each axis.
    var square_box = extrude(
        square(4),
        Length(1, METER),
        bevel_enabled=True,
        bevel_thickness=Length(0.5, METER),
        bevel_size=Length(0.25, METER),
        bevel_segments=1,
    ).bounding_box()
    assert_almost_equal(square_box.max.x, Float32(4.25), atol=TOLERANCE)


def test_an_ordinary_bevel_is_still_all_numbers() raises:
    var plate = square(6)
    plate.add_hole(box_path(2, 2, 4, 4))
    var solid = extrude(
        plate,
        Length(2, METER),
        bevel_enabled=True,
        bevel_thickness=Length(0.25, METER),
        bevel_size=Length(0.25, METER),
        bevel_segments=3,
    )
    assert_all_finite(solid)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
