# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.rasterizer`."""

from math.vector2 import Vector2
from std.math import inf
from render.framebuffer import Color, FloatColor, Framebuffer
from materials.material import BLEND, NO_TEXTURE, OPAQUE
from render.texture import REPEAT, Texture, checkerboard
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from math.vector3 import Vector3
from render.target import RenderTarget
from render.rasterizer import (
    SHADE_TEXTURE,
    SHADE_UV,
    RasterVertex,
    Triangle,
    edge,
    rasterize,
    rasterize_depth,
    rasterize_shaded,
)
from std.testing import (
    TestSuite,
    assert_raises,
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


def test_rasterize_agrees_with_the_predicate_away_from_edges() raises:
    # CCW has corners on whole pixels, so its hypotenuse runs exactly through
    # sample points and the fill rule deliberately excludes some of them --
    # see the quad tests below. Nudged off the grid, no sample point lies on
    # an edge and filling and the geometric predicate must agree everywhere.
    var background = Color(0, 0, 0)
    var foreground = Color(255, 128, 32)
    var nudged = Triangle(
        Vector2(0.13, 0.13), Vector2(4.13, 0.13), Vector2(0.13, 4.13)
    )
    var fb = Framebuffer(8, 8, background)
    rasterize(nudged, fb, foreground)

    var covered = 0
    for y in range(8):
        for x in range(8):
            var p = Vector2(Float32(x) + 0.5, Float32(y) + 0.5)
            if nudged.contains(p):
                covered += 1
                assert_equal(fb.get_pixel(x, y).r, foreground.r)
            else:
                assert_equal(fb.get_pixel(x, y).r, background.r)
    assert_true(covered > 0)


def quad_coverage_counts() raises -> List[Int]:
    """Return how many times each pixel of a two-triangle quad was drawn.

    Returns:
        One count per pixel of a 16x12 image, row-major.

    Raises:
        Error: If a pixel read or write is out of bounds.
    """
    var counts = List[Int](length=16 * 12, fill=0)
    var corners = List[Vector2]()
    corners.append(Vector2(2.0, 2.0))
    corners.append(Vector2(13.0, 2.0))
    corners.append(Vector2(13.0, 9.0))
    corners.append(Vector2(2.0, 9.0))
    var halves = List[Triangle]()
    halves.append(Triangle(corners[0], corners[1], corners[2]))
    halves.append(Triangle(corners[0], corners[2], corners[3]))
    for half in range(2):
        var fb = Framebuffer(16, 12, Color(0, 0, 0))
        rasterize(halves[half], fb, Color(255, 255, 255))
        for y in range(12):
            for x in range(16):
                if fb.get_pixel(x, y).r == 255:
                    counts[y * 16 + x] += 1
    return counts^


def test_a_degenerate_triangle_fills_nothing() raises:
    # Three collinear corners have no area, so there is nothing to fill and
    # the barycentric weights would divide by zero if there were.
    var fb = Framebuffer(6, 6, Color(1, 2, 3))
    rasterize(
        Triangle(Vector2(0, 0), Vector2(2, 2), Vector2(5, 5)),
        fb,
        Color(255, 0, 0),
    )
    for y in range(6):
        for x in range(6):
            assert_equal(fb.get_pixel(x, y).r, UInt8(1))


def test_a_shared_edge_leaves_no_cracks() raises:
    # Two triangles meeting along a diagonal used to miss pixels lying almost
    # exactly on it: the edge function, computed from each triangle's own
    # corner ordering, could round fractionally negative for both. Exact
    # fixed-point arithmetic makes the two orderings negate exactly.
    var counts = quad_coverage_counts()
    for y in range(3, 9):
        for x in range(3, 13):
            assert_true(counts[y * 16 + x] > 0)


def test_a_shared_edge_is_never_drawn_twice() raises:
    # And the top-left fill rule stops exact arithmetic causing the opposite
    # problem, where a pixel on the shared edge satisfies both triangles.
    var counts = quad_coverage_counts()
    for index in range(len(counts)):
        assert_true(counts[index] <= 1)


def test_a_triangle_is_filled_the_same_whichever_way_it_is_wound() raises:
    # The winding is normalized before the fill rule is applied, so reversing
    # the corner order cannot change which pixels come out.
    var forward = Framebuffer(12, 12, Color(0, 0, 0))
    var backward = Framebuffer(12, 12, Color(0, 0, 0))
    var a = Vector2(1.5, 9.5)
    var b = Vector2(9.5, 1.5)
    var c = Vector2(9.5, 9.5)
    rasterize(Triangle(a, b, c), forward, Color(255, 0, 0))
    rasterize(Triangle(a, c, b), backward, Color(255, 0, 0))
    for y in range(12):
        for x in range(12):
            assert_equal(forward.get_pixel(x, y).r, backward.get_pixel(x, y).r)


def test_rasterize_leaves_background_when_nothing_is_covered() raises:
    var background = Color(20, 24, 32)
    var fb = Framebuffer(4, 4, background)
    # A triangle entirely off the left of the viewport.
    var offscreen = Triangle(Vector2(-10, 0), Vector2(-6, 0), Vector2(-10, 4))
    rasterize(offscreen, fb, Color(255, 128, 32))
    for y in range(4):
        for x in range(4):
            assert_equal(fb.get_pixel(x, y).r, background.r)


def flat_vertex(
    point: Vector3,
    color: Color,
    inv_w: Float32 = 1.0,
    blend: Int = OPAQUE,
) -> RasterVertex:
    """Return a raster vertex at `point` in `color`, with no perspective.

    An `inv_w` of one everywhere means the perspective correction has nothing
    to correct, so these tests measure coverage and blending on their own.
    The tests that do care about perspective pass differing values.

    The colour is decoded from sRGB, so that writing a byte in and reading the
    same byte out is the round trip it looks like: the target encodes on the
    way out.

    Whether the surface composites is stated rather than inferred from its
    alpha, because that is how the renderer states it.

    Args:
        point: Screen x and y with NDC depth in z.
        color: The colour at this corner.
        inv_w: Reciprocal of the clip-space w; one means no perspective.
        blend: `OPAQUE` or `BLEND`, stated rather than inferred.

    Returns:
        The corner as the rasterizer wants it.
    """
    return RasterVertex(
        point.x,
        point.y,
        point.z,
        inv_w,
        FloatColor(srgb=color),
        0,
        0,
        NO_TEXTURE,
        blend,
    )


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


def test_a_single_colour_fills_evenly() raises:
    var fb = RenderTarget(6, 6, Color(0, 0, 0))
    var t = covering(0.5)
    rasterize_shaded(
        flat_vertex(t[0], Color(90, 0, 0)),
        flat_vertex(t[1], Color(90, 0, 0)),
        flat_vertex(t[2], Color(90, 0, 0)),
        fb,
    )
    assert_equal(fb.shown(0, 0).r, UInt8(90))
    assert_equal(fb.shown(5, 5).r, UInt8(90))


def test_colour_is_mixed_across_the_face() raises:
    # Red at the left corner, blue at the right: the middle is neither.
    var fb = RenderTarget(9, 9, Color(0, 0, 0))
    rasterize_shaded(
        flat_vertex(Vector3(-5, -5, 0.5), Color(255, 0, 0)),
        flat_vertex(Vector3(20, -5, 0.5), Color(0, 0, 255)),
        flat_vertex(Vector3(-5, 20, 0.5), Color(255, 0, 0)),
        fb,
    )
    var left = fb.shown(0, 0)
    var right = fb.shown(8, 0)
    assert_true(left.r > right.r)
    assert_true(right.b > left.b)


def test_shaded_rasterization_still_respects_depth() raises:
    var fb = RenderTarget(6, 6, Color(0, 0, 0))
    var near = covering(0.1)
    var far = covering(0.9)
    rasterize_shaded(
        flat_vertex(near[0], Color(0, 255, 0)),
        flat_vertex(near[1], Color(0, 255, 0)),
        flat_vertex(near[2], Color(0, 255, 0)),
        fb,
    )
    rasterize_shaded(
        flat_vertex(far[0], Color(255, 0, 0)),
        flat_vertex(far[1], Color(255, 0, 0)),
        flat_vertex(far[2], Color(255, 0, 0)),
        fb,
    )
    assert_equal(fb.shown(0, 0).g, UInt8(255))


def test_a_degenerate_shaded_triangle_draws_nothing() raises:
    var fb = RenderTarget(4, 4, Color(1, 2, 3))
    rasterize_shaded(
        flat_vertex(Vector3(0, 0, 0.5), Color(255, 0, 0)),
        flat_vertex(Vector3(2, 2, 0.5), Color(255, 0, 0)),
        flat_vertex(Vector3(4, 4, 0.5), Color(255, 0, 0)),
        fb,
    )
    assert_equal(fb.shown(2, 2).r, UInt8(1))


def test_alpha_decides_how_much_of_a_surface_shows() raises:
    # Alpha is coverage now, not a channel carried through to the buffer: a
    # translucent triangle is mixed into what is behind it. Interpolated
    # across the face, so one corner nearly vanishes and another is solid.
    var fb = RenderTarget(6, 6, Color(0, 0, 0))
    var t = covering(0.5)
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 255, 255, 0), 1.0, BLEND),
        flat_vertex(t[1], Color(255, 255, 255, 255), 1.0, BLEND),
        flat_vertex(t[2], Color(255, 255, 255, 255), 1.0, BLEND),
        fb,
    )
    # The transparent corner leaves the black background nearly untouched;
    # the opaque corners cover it.
    assert_true(fb.shown(0, 0).r < fb.shown(5, 5).r)
    assert_true(fb.shown(5, 5).r > 200)


def test_a_triangle_above_the_viewport_touches_no_rows() raises:
    # Entirely above the image, so its bounding box has no rows at all and
    # the row loop itself must run zero times, not just the column loop.
    # All three rasterizers, since each has its own pair of loops. The
    # shaded one draws into a linear target now, so it needs its own buffer.
    var fb = Framebuffer(4, 4, Color(1, 2, 3))
    rasterize(
        Triangle(Vector2(0, -10), Vector2(4, -10), Vector2(0, -6)),
        fb,
        Color(255, 0, 0),
    )
    rasterize_depth(
        Vector3(0, -10, 0.5),
        Vector3(4, -10, 0.5),
        Vector3(0, -6, 0.5),
        fb,
        Color(255, 0, 0),
    )
    var lit = RenderTarget(4, 4, Color(1, 2, 3))
    rasterize_shaded(
        flat_vertex(Vector3(0, -10, 0.5), Color(255, 0, 0)),
        flat_vertex(Vector3(4, -10, 0.5), Color(255, 0, 0)),
        flat_vertex(Vector3(0, -6, 0.5), Color(255, 0, 0)),
        lit,
    )
    for y in range(4):
        for x in range(4):
            assert_equal(fb.get_pixel(x, y).r, UInt8(1))
            assert_equal(lit.shown(x, y).r, UInt8(1))


def test_a_triangle_beside_the_viewport_touches_no_columns() raises:
    # Entirely to the left: the bounding box has rows but no columns, so the
    # column loop is what runs zero times this time.
    # All three rasterizers, since each has its own pair of loops. The
    # shaded one draws into a linear target now, so it needs its own buffer.
    var fb = Framebuffer(4, 4, Color(1, 2, 3))
    rasterize(
        Triangle(Vector2(-10, 0), Vector2(-6, 0), Vector2(-10, 4)),
        fb,
        Color(255, 0, 0),
    )
    rasterize_depth(
        Vector3(-10, 0, 0.5),
        Vector3(-6, 0, 0.5),
        Vector3(-10, 4, 0.5),
        fb,
        Color(255, 0, 0),
    )
    var lit = RenderTarget(4, 4, Color(1, 2, 3))
    rasterize_shaded(
        flat_vertex(Vector3(-10, 0, 0.5), Color(255, 0, 0)),
        flat_vertex(Vector3(-6, 0, 0.5), Color(255, 0, 0)),
        flat_vertex(Vector3(-10, 4, 0.5), Color(255, 0, 0)),
        lit,
    )
    for y in range(4):
        for x in range(4):
            assert_equal(fb.get_pixel(x, y).r, UInt8(1))
            assert_equal(lit.shown(x, y).r, UInt8(1))


# --- perspective-correct interpolation --------------------------------------


def wide_triangle() -> List[Vector3]:
    """Return a triangle spanning a 9x9 image, for interpolation tests."""
    var corners = List[Vector3]()
    corners.append(Vector3(-5, -5, 0.5))
    corners.append(Vector3(20, -5, 0.5))
    corners.append(Vector3(-5, 20, 0.5))
    return corners^


def test_equal_inv_w_everywhere_is_plain_screen_linear_blending() raises:
    # The correction divides by the interpolated inv_w, so a constant value
    # cancels completely whatever it is. If it did not, every orthographic-ish
    # triangle would shade differently depending on how far away it happened
    # to be.
    var t = wide_triangle()
    var ones = RenderTarget(9, 9, Color(0, 0, 0))
    var halves = RenderTarget(9, 9, Color(0, 0, 0))
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 0, 0), 1.0),
        flat_vertex(t[1], Color(0, 0, 255), 1.0),
        flat_vertex(t[2], Color(255, 0, 0), 1.0),
        ones,
    )
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 0, 0), 0.5),
        flat_vertex(t[1], Color(0, 0, 255), 0.5),
        flat_vertex(t[2], Color(255, 0, 0), 0.5),
        halves,
    )
    for y in range(9):
        for x in range(9):
            assert_equal(ones.shown(x, y).r, halves.shown(x, y).r)
            assert_equal(ones.shown(x, y).b, halves.shown(x, y).b)


def test_the_nearer_corner_holds_more_of_the_screen() raises:
    # A corner four times further away has a quarter the inv_w. Halfway across
    # the screen the surface is only a fifth of the way to it, so the near
    # colour should still dominate there — which screen-linear blending gets
    # wrong by putting the two exactly even.
    var t = wide_triangle()
    var linear = RenderTarget(9, 9, Color(0, 0, 0))
    var correct = RenderTarget(9, 9, Color(0, 0, 0))
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 0, 0), 1.0),
        flat_vertex(t[1], Color(0, 0, 255), 1.0),
        flat_vertex(t[2], Color(255, 0, 0), 1.0),
        linear,
    )
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 0, 0), 1.0),
        flat_vertex(t[1], Color(0, 0, 255), 0.25),
        flat_vertex(t[2], Color(255, 0, 0), 1.0),
        correct,
    )
    # Somewhere along the red-to-blue edge the two must disagree.
    var differences = 0
    for y in range(9):
        for x in range(9):
            if correct.shown(x, y).r != linear.shown(x, y).r:
                differences += 1
                # Wherever they differ, the near red is stronger and the far
                # blue weaker than the naive blend said.
                assert_true(correct.shown(x, y).r > linear.shown(x, y).r)
                assert_true(correct.shown(x, y).b < linear.shown(x, y).b)
    assert_true(differences > 0, "the correction changed nothing")


def test_depth_is_interpolated_affinely_not_corrected() raises:
    # NDC depth is already linear in screen space — that is what the
    # projection buys — so it must be interpolated with the plain weights.
    # Putting it through inv_w as well would be a second, wrong divide, and
    # the depth buffer would stop agreeing with itself between triangles.
    var t = wide_triangle()
    var flat = RenderTarget(9, 9, Color(0, 0, 0))
    var sloped = RenderTarget(9, 9, Color(0, 0, 0))
    rasterize_shaded(
        RasterVertex(t[0].x, t[0].y, 0.1, 1.0, FloatColor(1, 1, 1), 0, 0),
        RasterVertex(t[1].x, t[1].y, 0.9, 1.0, FloatColor(1, 1, 1), 0, 0),
        RasterVertex(t[2].x, t[2].y, 0.5, 1.0, FloatColor(1, 1, 1), 0, 0),
        flat,
    )
    # Same corners and depths, wildly different w. Depth must not notice.
    rasterize_shaded(
        RasterVertex(t[0].x, t[0].y, 0.1, 1.0, FloatColor(1, 1, 1), 0, 0),
        RasterVertex(t[1].x, t[1].y, 0.9, 0.05, FloatColor(1, 1, 1), 0, 0),
        RasterVertex(t[2].x, t[2].y, 0.5, 4.0, FloatColor(1, 1, 1), 0, 0),
        sloped,
    )
    for y in range(9):
        for x in range(9):
            assert_equal(flat.depth_at(x, y), sloped.depth_at(x, y))


def test_a_zero_inv_w_falls_back_to_screen_linear() raises:
    # Nothing in this renderer produces it — clipping removes the near plane
    # and everything behind it — but a divide by an interpolated zero would
    # give infinities rather than an error, so the guard is exercised.
    var t = wide_triangle()
    var fb = RenderTarget(9, 9, Color(0, 0, 0))
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 0, 0), 0.0),
        flat_vertex(t[1], Color(0, 0, 255), 0.0),
        flat_vertex(t[2], Color(255, 0, 0), 0.0),
        fb,
    )
    var left = fb.shown(0, 0)
    var right = fb.shown(8, 0)
    assert_true(left.r > right.r)
    assert_true(right.b > left.b)


# --- texture coordinates at the fragment ------------------------------------


def uv_vertex(
    x: Float32, y: Float32, inv_w: Float32, u: Float32, v: Float32
) -> RasterVertex:
    """Return a raster vertex carrying texture coordinates and no colour."""
    return RasterVertex(x, y, 0.5, inv_w, FloatColor(0, 0, 0), u, v)


def test_uv_mode_writes_texture_coordinates_as_red_and_green() raises:
    # A right triangle covering the image, u growing with x and v with y.
    var fb = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_shaded(
        uv_vertex(-1, -1, 1, 0, 0),
        uv_vertex(40, -1, 1, 1, 0),
        uv_vertex(-1, 40, 1, 0, 1),
        fb,
        SHADE_UV,
    )
    # Near the (0,0) corner both channels are low; along +x red climbs and
    # along +y green does.
    assert_true(fb.shown(1, 1).r < 40)
    assert_true(fb.shown(1, 1).g < 40)
    assert_true(fb.shown(12, 1).r > fb.shown(1, 1).r)
    assert_true(fb.shown(1, 12).g > fb.shown(1, 1).g)
    # u varies along x only, so moving down must not change red.
    assert_equal(fb.shown(4, 1).r, fb.shown(4, 6).r)


def test_lit_mode_ignores_texture_coordinates() raises:
    # The colour path must not start depending on uv just because it is there.
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    var t = covering(0.5)
    rasterize_shaded(
        RasterVertex(t[0].x, t[0].y, 0.5, 1, FloatColor(0, 1, 0), 1, 1),
        RasterVertex(t[1].x, t[1].y, 0.5, 1, FloatColor(0, 1, 0), 1, 1),
        RasterVertex(t[2].x, t[2].y, 0.5, 1, FloatColor(0, 1, 0), 1, 1),
        fb,
    )
    assert_equal(fb.shown(4, 4).r, UInt8(0))
    assert_equal(fb.shown(4, 4).g, UInt8(255))


def test_texture_coordinates_are_perspective_corrected_too() raises:
    # The reason uv reaches the fragment at all. A far corner has a smaller
    # inv_w, so the surface runs out of texture faster across the screen than
    # an affine interpolation would say -- the classic warped floor.
    var affine = RenderTarget(16, 16, Color(0, 0, 0))
    var correct = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_shaded(
        uv_vertex(-1, -1, 1.0, 0, 0),
        uv_vertex(40, -1, 1.0, 1, 0),
        uv_vertex(-1, 40, 1.0, 0, 1),
        affine,
        SHADE_UV,
    )
    rasterize_shaded(
        uv_vertex(-1, -1, 1.0, 0, 0),
        uv_vertex(40, -1, 0.2, 1, 0),
        uv_vertex(-1, 40, 1.0, 0, 1),
        correct,
        SHADE_UV,
    )
    var differences = 0
    for y in range(16):
        for x in range(16):
            if correct.shown(x, y).r != affine.shown(x, y).r:
                differences += 1
                # The far corner's u arrives later across the screen, so the
                # corrected value is the smaller one.
                assert_true(correct.shown(x, y).r < affine.shown(x, y).r)
    assert_true(differences > 0, "the correction changed nothing")


def test_an_unmapped_triangle_reads_as_the_texture_origin() raises:
    # A geometry with no uv attribute gets zeroes, which is a defined place
    # rather than whatever was left in the buffer.
    var fb = RenderTarget(8, 8, Color(90, 90, 90))
    var t = covering(0.5)
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 255, 255)),
        flat_vertex(t[1], Color(255, 255, 255)),
        flat_vertex(t[2], Color(255, 255, 255)),
        fb,
        SHADE_UV,
    )
    assert_equal(fb.shown(4, 4).r, UInt8(0))
    assert_equal(fb.shown(4, 4).g, UInt8(0))


def test_perspective_correct_uv_has_the_exact_value_it_should() raises:
    # The gradient tests above show the correction points the right way; this
    # pins the number. A wrong formula can easily still produce a gradient in
    # the expected direction.
    #
    # Corners at (0.5,0.5) (4.5,0.5) (0.5,4.5) put pixel (1,1)'s centre at
    # barycentric (1/2, 1/4, 1/4) exactly, on the subpixel grid. With
    # inv_w of 1, 1/2 and 1/4 the denominator is 11/16, so
    #     u = (1/4 * 1 * 1/2) / (11/16) = 2/11
    #     v = (1/4 * 1 * 1/4) / (11/16) = 1/11
    # which quantize to 46 and 23.
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_shaded(
        uv_vertex(0.5, 0.5, 1.0, 0, 0),
        uv_vertex(4.5, 0.5, 0.5, 1, 0),
        uv_vertex(0.5, 4.5, 0.25, 0, 1),
        fb,
        SHADE_UV,
    )
    assert_equal(fb.shown(1, 1).r, UInt8(46))
    assert_equal(fb.shown(1, 1).g, UInt8(23))


def test_the_same_triangle_without_perspective_gives_the_flat_answer() raises:
    # The same corners with every inv_w at one leave the plain screen-space
    # weights, so both channels are 1/4 -- 64 after quantization.
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_shaded(
        uv_vertex(0.5, 0.5, 1.0, 0, 0),
        uv_vertex(4.5, 0.5, 1.0, 1, 0),
        uv_vertex(0.5, 4.5, 1.0, 0, 1),
        fb,
        SHADE_UV,
    )
    assert_equal(fb.shown(1, 1).r, UInt8(64))
    assert_equal(fb.shown(1, 1).g, UInt8(64))


# --- sampling a texture -----------------------------------------------------


def lit_uv_vertex(
    x: Float32,
    y: Float32,
    inv_w: Float32,
    u: Float32,
    v: Float32,
    texture: TextureId = NO_TEXTURE,
) -> RasterVertex:
    """Return a white raster vertex carrying texture coordinates.

    White, unlike `uv_vertex`, because modulating a texture by black is
    black -- correct, and useless for seeing what was sampled.
    """
    return RasterVertex(x, y, 0.5, inv_w, FloatColor(1, 1, 1), u, v, texture)


def mapped_quad(
    size: Float32, texture: TextureId = NO_TEXTURE
) -> List[RasterVertex]:
    """Return two triangles covering a square image, mapped once across it.

    One oversized triangle would be simpler and would not do: it covers the
    image but stretches uv far beyond it, so the whole viewport lands inside
    a single texel and every checkerboard square looks the same. The mapping
    has to span exactly what is drawn.

    Args:
        size: The image's width and height in pixels.
        texture: Which texture every corner names.

    Returns:
        Six raster vertices, two triangles' worth.
    """
    var top_left = lit_uv_vertex(0, 0, 1, 0, 1, texture)
    var top_right = lit_uv_vertex(size, 0, 1, 1, 1, texture)
    var bottom_right = lit_uv_vertex(size, size, 1, 1, 0, texture)
    var bottom_left = lit_uv_vertex(0, size, 1, 0, 0, texture)
    var corners = List[RasterVertex]()
    corners.append(top_left)
    corners.append(top_right)
    corners.append(bottom_right)
    corners.append(top_left)
    corners.append(bottom_right)
    corners.append(bottom_left)
    return corners^


def test_a_texture_replaces_a_white_surface() raises:
    # Modulation against white leaves the texel alone, which is what makes
    # "show me the image" the simple case rather than a special one.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(8, 2, Color(255, 0, 0), Color(0, 0, 255))
    )
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    var quad = mapped_quad(8, board)
    for triangle in range(2):
        rasterize_shaded(
            quad[triangle * 3],
            quad[triangle * 3 + 1],
            quad[triangle * 3 + 2],
            fb,
            SHADE_TEXTURE,
            textures,
        )
    # Top-left quadrant is the light square, top-right the dark one.
    assert_equal(fb.shown(1, 1).r, UInt8(255))
    assert_equal(fb.shown(1, 1).b, UInt8(0))
    assert_equal(fb.shown(6, 1).b, UInt8(255))
    assert_equal(fb.shown(6, 1).r, UInt8(0))


def test_a_texture_is_modulated_by_the_lighting() raises:
    # Half-lit white surface, fully white texture: half the light, which is
    # what a display shows as 188. Not 128 -- that is half the *byte*, and a
    # byte is not proportional to light.
    var pixels = List[UInt8](length=4, fill=255)
    var textures = TextureStore()
    var white = textures.add(Texture(1, 1, pixels^, REPEAT))
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    var t = covering(0.5)
    var grey = FloatColor(0.5, 0.5, 0.5)
    rasterize_shaded(
        RasterVertex(t[0].x, t[0].y, 0.5, 1, grey, 0, 0, white),
        RasterVertex(t[1].x, t[1].y, 0.5, 1, grey, 0, 0, white),
        RasterVertex(t[2].x, t[2].y, 0.5, 1, grey, 0, 0, white),
        fb,
        SHADE_TEXTURE,
        textures,
    )
    assert_equal(fb.shown(4, 4).r, UInt8(188))


def test_no_texture_leaves_the_lighting_untouched() raises:
    # The default is the blank texture, which samples as white, so
    # SHADE_TEXTURE with nothing set must match SHADE_LIT exactly.
    var lit = RenderTarget(8, 8, Color(0, 0, 0))
    var textured = RenderTarget(8, 8, Color(0, 0, 0))
    var t = covering(0.5)
    var green = FloatColor(0.0, 0.6, 0.2)
    rasterize_shaded(
        RasterVertex(t[0].x, t[0].y, 0.5, 1, green, 0, 0),
        RasterVertex(t[1].x, t[1].y, 0.5, 1, green, 0, 0),
        RasterVertex(t[2].x, t[2].y, 0.5, 1, green, 0, 0),
        lit,
    )
    rasterize_shaded(
        RasterVertex(t[0].x, t[0].y, 0.5, 1, green, 0, 0),
        RasterVertex(t[1].x, t[1].y, 0.5, 1, green, 0, 0),
        RasterVertex(t[2].x, t[2].y, 0.5, 1, green, 0, 0),
        textured,
        SHADE_TEXTURE,
    )
    for y in range(8):
        for x in range(8):
            assert_equal(lit.shown(x, y).g, textured.shown(x, y).g)


def test_a_texture_is_sampled_with_perspective_correct_coordinates() raises:
    # The coordinates a texture is looked up with are the corrected ones, so
    # a checkerboard on a receding surface bends the way a real one does.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(8, 2, Color(255, 0, 0), Color(0, 0, 255))
    )
    var correct = RenderTarget(16, 16, Color(0, 0, 0))
    var affine = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_shaded(
        lit_uv_vertex(-1, -1, 1.0, 0, 1, board),
        lit_uv_vertex(40, -1, 0.2, 1, 1, board),
        lit_uv_vertex(-1, 40, 1.0, 0, 0, board),
        correct,
        SHADE_TEXTURE,
        textures,
    )
    rasterize_shaded(
        lit_uv_vertex(-1, -1, 1.0, 0, 1, board),
        lit_uv_vertex(40, -1, 1.0, 1, 1, board),
        lit_uv_vertex(-1, 40, 1.0, 0, 0, board),
        affine,
        SHADE_TEXTURE,
        textures,
    )
    var differing = 0
    for y in range(16):
        for x in range(16):
            if correct.shown(x, y).r != affine.shown(x, y).r:
                differing += 1
    assert_true(differing > 0, "the correction did not reach the sampling")


def test_an_unknown_shading_mode_is_refused() raises:
    # Refused rather than guessed at. Left unchecked the two rasterizers
    # disagreed about it -- the CPU's last branch treated anything
    # unrecognised as textured, the GPU's treated it as lit -- which is the
    # worst kind of divergence: silent, and only on input nobody meant to
    # write. `Renderer.set_shading` checks too, but it is not the only caller.
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    var t = covering(0.5)
    with assert_raises():
        rasterize_shaded(
            flat_vertex(t[0], Color(255, 0, 0)),
            flat_vertex(t[1], Color(255, 0, 0)),
            flat_vertex(t[2], Color(255, 0, 0)),
            fb,
            42,
        )
    with assert_raises():
        rasterize_shaded(
            flat_vertex(t[0], Color(255, 0, 0)),
            flat_vertex(t[1], Color(255, 0, 0)),
            flat_vertex(t[2], Color(255, 0, 0)),
            fb,
            -1,
        )


# --- blending ---------------------------------------------------------------


def test_a_half_transparent_white_over_black_is_half_the_light() raises:
    # The number the colour space exists for. Half the light of white over
    # black displays as 188; 128 would be half the *byte*, which is 21.6% of
    # the light and the answer a renderer that blends in sRGB gives.
    var fb = RenderTarget(6, 6, Color(0, 0, 0))
    var t = covering(0.5)
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 255, 255, 128), 1.0, BLEND),
        flat_vertex(t[1], Color(255, 255, 255, 128), 1.0, BLEND),
        flat_vertex(t[2], Color(255, 255, 255, 128), 1.0, BLEND),
        fb,
    )
    # 128/255 is the coverage, not a colour, so it is not decoded.
    var share = Float32(128) / 255
    var expected = FloatColor(share, share, share, 1.0).encode()
    assert_equal(fb.shown(3, 3).r, expected.r)
    assert_true(fb.shown(3, 3).r > 180)


def test_a_transparent_surface_does_not_claim_the_depth() raises:
    # Two panes one behind the other both show, which is the whole point: a
    # translucent surface is hidden by what is in front of it without hiding
    # what is behind it.
    var fb = RenderTarget(6, 6, Color(0, 0, 0))
    var far = covering(0.8)
    var near = covering(0.2)
    rasterize_shaded(
        flat_vertex(far[0], Color(255, 0, 0, 128), 1.0, BLEND),
        flat_vertex(far[1], Color(255, 0, 0, 128), 1.0, BLEND),
        flat_vertex(far[2], Color(255, 0, 0, 128), 1.0, BLEND),
        fb,
    )
    var behind_only = fb.shown(3, 3).r
    rasterize_shaded(
        flat_vertex(near[0], Color(0, 0, 255, 128), 1.0, BLEND),
        flat_vertex(near[1], Color(0, 0, 255, 128), 1.0, BLEND),
        flat_vertex(near[2], Color(0, 0, 255, 128), 1.0, BLEND),
        fb,
    )
    # The red pane is still contributing under the blue one.
    assert_true(fb.shown(3, 3).r > 0)
    assert_true(fb.shown(3, 3).r < behind_only)
    assert_true(fb.shown(3, 3).b > 0)
    # And the depth buffer still says nothing is there, so an opaque surface
    # behind both would still draw.
    assert_equal(fb.depth_at(3, 3), inf[DType.float32]())


def test_an_opaque_surface_in_front_hides_a_transparent_one() raises:
    var fb = RenderTarget(6, 6, Color(0, 0, 0))
    var near = covering(0.2)
    var far = covering(0.8)
    rasterize_shaded(
        flat_vertex(near[0], Color(0, 255, 0)),
        flat_vertex(near[1], Color(0, 255, 0)),
        flat_vertex(near[2], Color(0, 255, 0)),
        fb,
    )
    rasterize_shaded(
        flat_vertex(far[0], Color(255, 0, 0, 128), 1.0, BLEND),
        flat_vertex(far[1], Color(255, 0, 0, 128), 1.0, BLEND),
        flat_vertex(far[2], Color(255, 0, 0, 128), 1.0, BLEND),
        fb,
    )
    assert_equal(fb.shown(3, 3).r, UInt8(0))
    assert_equal(fb.shown(3, 3).g, UInt8(255))


def test_a_fully_transparent_surface_changes_nothing() raises:
    var fb = RenderTarget(6, 6, Color(40, 50, 60))
    var t = covering(0.5)
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 255, 255, 0), 1.0, BLEND),
        flat_vertex(t[1], Color(255, 255, 255, 0), 1.0, BLEND),
        flat_vertex(t[2], Color(255, 255, 255, 0), 1.0, BLEND),
        fb,
    )
    assert_equal(fb.shown(3, 3).r, UInt8(40))
    assert_equal(fb.shown(3, 3).g, UInt8(50))
    assert_equal(fb.shown(3, 3).b, UInt8(60))


def test_an_opaque_surface_still_claims_the_depth() raises:
    # The other side of the depth rule, so blending cannot have been made
    # unconditional.
    var fb = RenderTarget(6, 6, Color(0, 0, 0))
    var t = covering(0.5)
    rasterize_shaded(
        flat_vertex(t[0], Color(255, 255, 255)),
        flat_vertex(t[1], Color(255, 255, 255)),
        flat_vertex(t[2], Color(255, 255, 255)),
        fb,
    )
    assert_almost_equal(fb.depth_at(3, 3), Float32(0.5), atol=Float64(1e-6))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
