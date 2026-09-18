# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.rasterizer`."""

from core.layers import Layers
from materials.material import (
    BASIC,
    DEPTH,
    LAMBERT,
    NORMALS,
    PHONG,
    TOON,
    Blending,
    MaterialKind,
    depth_material,
    normal_material,
)
from math.vector2 import Vector2
from std.math import inf
from render.framebuffer import Color, FloatColor, Framebuffer
from materials.material import BLEND, NO_TEXTURE, OPAQUE
from render.texture import (
    COVERAGE,
    IGNORED,
    NEAREST,
    REPEAT,
    Alpha,
    Texture,
    checkerboard,
)
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from lights.light import directional_light
from lights.lighting import Lighting
from core.fog import LINEAR_FOG, FogKind, FogView, exp2_fog, linear_fog
from render.tonemap import REINHARD_TONE_MAPPING, tone_map
from std.math import nan
from units.si import InverseLength, Length, METER, PER_METER
from core.object3d import NodeId, Object3D
from core.scene import Scene
from math.vector3 import Vector3
from render.target import RenderTarget
from render.srgb import LINEAR, SRGB, ColorSpace
from render.rasterizer import (
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    RasterVertex,
    ShadeMode,
    Triangle,
    check_alpha_map,
    check_gradient_map,
    check_triangle_state,
    data_color,
    gradient_ramp,
    interpolate_alpha,
    edge,
    mip_level,
    packed_depth,
    packed_normal,
    rasterize,
    rasterize_depth,
    rasterize_all,
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
    blend: Blending = OPAQUE,
) -> RasterVertex:
    """Return a raster vertex at `point` in `color`, with no perspective.

    An `inv_w` of one everywhere means the perspective correction has nothing
    to correct, so these tests measure coverage and blending on their own.
    The tests that do care about perspective pass differing values.

    The color is decoded from sRGB, so that writing a byte in and reading the
    same byte out is the round trip it looks like: the target encodes on the
    way out.

    Whether the surface composites is stated rather than inferred from its
    alpha, because that is how the renderer states it.

    Args:
        point: Screen x and y with NDC depth in z.
        color: The color at this corner.
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


def test_a_single_color_fills_evenly() raises:
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


def test_color_is_mixed_across_the_face() raises:
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
    # color should still dominate there — which screen-linear blending gets
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
    """Return a raster vertex carrying texture coordinates and no color."""
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
    # The color path must not start depending on uv just because it is there.
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
    # Corners at (0.5,0.5) (4.5,0.5) (0.5,4.5) put pixel (1,1)'s center at
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
    var gray = FloatColor(0.5, 0.5, 0.5)
    rasterize_shaded(
        RasterVertex(t[0].x, t[0].y, 0.5, 1, gray, 0, 0, white),
        RasterVertex(t[1].x, t[1].y, 0.5, 1, gray, 0, 0, white),
        RasterVertex(t[2].x, t[2].y, 0.5, 1, gray, 0, 0, white),
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


# --- blending ---------------------------------------------------------------


def test_a_half_transparent_white_over_black_is_half_the_light() raises:
    # The number the color space exists for. Half the light of white over
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
    # 128/255 is the coverage, not a color, so it is not decoded.
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


# --- Mip level selection ----------------------------------------------------


def test_one_texel_per_pixel_is_the_full_size_image() raises:
    # A 64-wide texture mapped so a pixel steps 1/64 across it covers exactly
    # one texel, and log2(1) is zero.
    assert_almost_equal(
        mip_level(Vector2(1.0 / 64, 0), Vector2(0, 1.0 / 64), 64, 64),
        Float32(0),
        atol=Float64(1e-6),
    )


def test_a_pixel_covering_four_texels_is_two_levels_down() raises:
    # Four texels across, and the chain halves each level, so two halvings.
    assert_almost_equal(
        mip_level(Vector2(4.0 / 64, 0), Vector2(0, 4.0 / 64), 64, 64),
        Float32(2),
        atol=Float64(1e-6),
    )


def test_a_magnified_surface_asks_for_a_level_below_zero() raises:
    # Less than a texel per pixel: no level of the chain is sharper than the
    # image already is, and `sample_level` reads level zero.
    assert_true(
        mip_level(Vector2(0.25 / 64, 0), Vector2(0, 0.25 / 64), 64, 64) < 0
    )


def test_the_longer_footprint_edge_decides_the_level() raises:
    # A surface seen edge-on is compressed in one direction only. Taking the
    # shorter edge, or an average, would leave the compressed direction
    # aliasing; the longer one is what has to stop sparkling.
    assert_almost_equal(
        mip_level(Vector2(8.0 / 64, 0), Vector2(0, 1.0 / 64), 64, 64),
        Float32(3),
        atol=Float64(1e-6),
    )
    # And the same footprint the other way round gives the same answer.
    assert_almost_equal(
        mip_level(Vector2(1.0 / 64, 0), Vector2(0, 8.0 / 64), 64, 64),
        Float32(3),
        atol=Float64(1e-6),
    )


def test_a_footprint_is_measured_in_texels_not_in_uv() raises:
    # The same uv step over a texture twice as wide covers twice as many
    # texels, and so is one level further down.
    var step = Vector2(1.0 / 64, 0)
    var flat = Vector2(0, 1.0 / 64)
    assert_almost_equal(
        mip_level(step, flat, 128, 64) - mip_level(step, flat, 64, 64),
        Float32(1),
        atol=Float64(1e-6),
    )


def test_a_degenerate_footprint_asks_for_the_full_size_image() raises:
    # A triangle collapsed to nothing moves no distance in uv, and log2(0) is
    # negative infinity, which is not a level.
    assert_equal(mip_level(Vector2(0, 0), Vector2(0, 0), 64, 64), Float32(0))


# --- Mipmapped sampling -----------------------------------------------------


def drawn_quad(
    corners: List[RasterVertex], size: Int, textures: TextureStore
) raises -> RenderTarget:
    """Return a target with two textured triangles drawn into it."""
    var fb = RenderTarget(size, size, Color(0, 0, 0))
    for triangle in range(2):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            fb,
            SHADE_TEXTURE,
            textures,
        )
    return fb^


def test_a_minified_surface_reads_down_the_chain() raises:
    # A 32-texel board of two-texel squares squeezed into 8 pixels: four
    # texels to a pixel, so level two, where one texel spans four squares and
    # is their average. Without the chain every pixel would be one of the two
    # extreme colors; with it nothing is extreme.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            32,
            16,
            Color(255, 0, 0),
            Color(0, 0, 255),
            REPEAT,
            NEAREST,
            mipmapped=True,
        )
    )
    var fb = drawn_quad(mapped_quad(8, board), 8, textures)
    for y in range(8):
        for x in range(8):
            var shown = fb.shown(x, y)
            assert_true(
                shown.r > 20 and shown.b > 20,
                "a minified pixel took one texel instead of their average",
            )


def test_the_same_surface_without_a_chain_takes_a_single_texel() raises:
    # The control: identical in every way but the chain, and every pixel is
    # one of the two colors outright. This is what the test above is the
    # absence of, and without it that one would pass on a blurry bug.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(32, 16, Color(255, 0, 0), Color(0, 0, 255))
    )
    var fb = drawn_quad(mapped_quad(8, board), 8, textures)
    var extreme = 0
    for y in range(8):
        for x in range(8):
            var shown = fb.shown(x, y)
            if shown.r < 20 or shown.b < 20:
                extreme += 1
    assert_equal(extreme, 64)


def test_a_magnified_surface_still_reads_the_full_size_image() raises:
    # The chain must not blur what is already too big: two texels across
    # sixteen pixels stays two hard squares.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            2,
            2,
            Color(255, 0, 0),
            Color(0, 0, 255),
            REPEAT,
            NEAREST,
            mipmapped=True,
        )
    )
    var fb = drawn_quad(mapped_quad(16, board), 16, textures)
    assert_equal(fb.shown(2, 2).r, UInt8(255))
    assert_equal(fb.shown(2, 2).b, UInt8(0))
    assert_equal(fb.shown(13, 2).b, UInt8(255))
    assert_equal(fb.shown(13, 2).r, UInt8(0))


def test_a_mipmapped_surface_drawn_the_other_way_round_looks_the_same() raises:
    # Winding decides the sign of the area, and the two barycentric weights
    # that swap with it. The fragment loop already handles that; the
    # neighbor lookups mip selection needs are a second place it has to be
    # got right, and getting it wrong there would pick a level from a
    # footprint with two axes exchanged.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            32,
            16,
            Color(255, 0, 0),
            Color(0, 0, 255),
            REPEAT,
            NEAREST,
            mipmapped=True,
        )
    )
    var forwards = mapped_quad(8, board)
    var backwards = List[RasterVertex]()
    for triangle in range(2):  # pragma: no branch
        backwards.append(forwards[triangle * 3])
        backwards.append(forwards[triangle * 3 + 2])
        backwards.append(forwards[triangle * 3 + 1])

    var one = drawn_quad(forwards, 8, textures)
    var other = drawn_quad(backwards, 8, textures)
    for y in range(8):
        for x in range(8):
            assert_equal(one.shown(x, y).r, other.shown(x, y).r)
            assert_equal(one.shown(x, y).b, other.shown(x, y).b)


def test_a_mipmapped_surface_with_no_depth_at_all_still_samples() raises:
    # Every corner at inv_w zero: the perspective correction has nothing to
    # divide by and falls back to the plain barycentric weights. Reachable
    # only through a caller that built raster vertices by hand, but the
    # division is there and has to have an answer.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            16,
            4,
            Color(255, 0, 0),
            Color(0, 0, 255),
            REPEAT,
            NEAREST,
            mipmapped=True,
        )
    )
    var flat = List[RasterVertex]()
    for corner in mapped_quad(8, board):
        flat.append(
            RasterVertex(
                corner.x,
                corner.y,
                corner.z,
                0,
                corner.color,
                corner.u,
                corner.v,
                corner.texture,
            )
        )
    var fb = drawn_quad(flat, 8, textures)
    assert_true(fb.shown(4, 4).r > 0 or fb.shown(4, 4).b > 0)


# --- Per-triangle state -----------------------------------------------------


def stated_corner(
    point: Vector3, texture: TextureId, blend: Blending
) -> RasterVertex:
    """Return a white corner carrying a given texture and blend policy."""
    return RasterVertex(
        point.x, point.y, 0.5, 1, FloatColor(1, 1, 1), 0, 0, texture, blend
    )


def test_both_blend_policies_are_accepted() raises:
    # Each operand of the check has to be able to decide the outcome alone.
    var textures = TextureStore()
    var t = covering(0.5)
    for policy in [OPAQUE, BLEND]:
        var fb = RenderTarget(8, 8, Color(0, 0, 0))
        rasterize_shaded(
            stated_corner(t[0], NO_TEXTURE, policy),
            stated_corner(t[1], NO_TEXTURE, policy),
            stated_corner(t[2], NO_TEXTURE, policy),
            fb,
            SHADE_TEXTURE,
            textures,
        )
        assert_equal(fb.shown(4, 4).r, UInt8(255))


def test_corners_that_disagree_about_blending_are_rejected() raises:
    # Both backends read the policy from the first corner because it comes
    # from the material and is the same on all three. If that stops being
    # true there is no single answer, and guessing is how the two drift apart.
    var textures = TextureStore()
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    var t = covering(0.5)
    with assert_raises():
        rasterize_shaded(
            stated_corner(t[0], NO_TEXTURE, OPAQUE),
            stated_corner(t[1], NO_TEXTURE, BLEND),
            stated_corner(t[2], NO_TEXTURE, OPAQUE),
            fb,
            SHADE_TEXTURE,
            textures,
        )
    with assert_raises():
        rasterize_shaded(
            stated_corner(t[0], NO_TEXTURE, OPAQUE),
            stated_corner(t[1], NO_TEXTURE, OPAQUE),
            stated_corner(t[2], NO_TEXTURE, BLEND),
            fb,
            SHADE_TEXTURE,
            textures,
        )


def test_an_unknown_blend_policy_is_refused_even_when_agreed() raises:
    # `Blending(7)` constructs -- a struct's fields are open -- and the two
    # backends once read it in opposite directions. Agreement between the
    # corners is not enough; the value has to be one of the two. A texture
    # id below zero that is not `NO_TEXTURE` is the same kind of nonsense.
    var textures = TextureStore()
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    var t = covering(0.5)
    with assert_raises():
        rasterize_shaded(
            stated_corner(t[0], NO_TEXTURE, Blending(7)),
            stated_corner(t[1], NO_TEXTURE, Blending(7)),
            stated_corner(t[2], NO_TEXTURE, Blending(7)),
            fb,
            SHADE_TEXTURE,
            textures,
        )
    with assert_raises():
        rasterize_shaded(
            stated_corner(t[0], TextureId(-3), OPAQUE),
            stated_corner(t[1], TextureId(-3), OPAQUE),
            stated_corner(t[2], TextureId(-3), OPAQUE),
            fb,
            SHADE_TEXTURE,
            textures,
        )


def test_an_unknown_shading_mode_is_refused() raises:
    assert_true(SHADE_LIT.is_valid())
    assert_true(SHADE_UV.is_valid())
    assert_true(SHADE_TEXTURE.is_valid())
    assert_false(ShadeMode(99).is_valid())
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    var t = covering(0.5)
    var corners = List[RasterVertex]()
    for index in range(3):
        corners.append(stated_corner(t[index], NO_TEXTURE, OPAQUE))
    with assert_raises():
        rasterize_shaded(corners[0], corners[1], corners[2], fb, ShadeMode(99))
    with assert_raises():
        rasterize_all(corners, fb, ShadeMode(99))
    with assert_raises():
        rasterize_all(corners, fb, ShadeMode(99), workers=2)


def test_malformed_state_is_refused_whether_or_not_it_is_visible() raises:
    # A band skips triangles outside its rows before the rasterizer sees
    # them, so an off-screen triangle with bad metadata used to raise on one
    # worker and pass on several. The answer must not depend on where the
    # triangle is or how many threads there are.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var corners = List[RasterVertex]()
    corners.append(stated_corner(Vector3(0, -100, 0), NO_TEXTURE, Blending(7)))
    corners.append(stated_corner(Vector3(8, -100, 0), NO_TEXTURE, Blending(7)))
    corners.append(stated_corner(Vector3(0, -92, 0), NO_TEXTURE, Blending(7)))
    for workers in [1, 2, 4, 16]:
        with assert_raises():
            rasterize_all(corners, target, workers=workers)
    # And a disagreement, which is what the check was first written for.
    corners[1] = stated_corner(Vector3(8, -100, 0), NO_TEXTURE, BLEND)
    corners[0] = stated_corner(Vector3(0, -100, 0), NO_TEXTURE, OPAQUE)
    corners[2] = stated_corner(Vector3(0, -92, 0), NO_TEXTURE, OPAQUE)
    for workers in [1, 4]:
        with assert_raises():
            rasterize_all(corners, target, workers=workers)


def test_corners_that_disagree_about_their_kind_are_rejected() raises:
    # The material kind is per triangle, like the blend policy, and read
    # from the first corner; so the other two have to agree with it.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var a = RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1))
    var b = RasterVertex(6, 0, 0.5, 1, FloatColor(1, 1, 1))
    var c = RasterVertex(0, 6, 0.5, 1, FloatColor(1, 1, 1))
    var unlit_b = RasterVertex(6, 0, 0.5, 1, FloatColor(1, 1, 1), kind=BASIC)
    var unlit_c = RasterVertex(0, 6, 0.5, 1, FloatColor(1, 1, 1), kind=BASIC)
    with assert_raises():
        rasterize_shaded(a, unlit_b, c, target)
    with assert_raises():
        rasterize_shaded(a, b, unlit_c, target)
    # Agreeing on any of the four is fine.
    var unlit_a = RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1), kind=BASIC)
    rasterize_shaded(unlit_a, unlit_b, unlit_c, target)
    rasterize_shaded(a, b, c, target)


def test_corners_that_disagree_about_their_emissive_map_are_rejected() raises:
    # Per triangle like the texture, and read from the first corner.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var white = FloatColor(1, 1, 1)
    var a = RasterVertex(0, 0, 0.5, 1, white, emissive_map=TextureId(0))
    var b = RasterVertex(6, 0, 0.5, 1, white, emissive_map=TextureId(0))
    var c = RasterVertex(0, 6, 0.5, 1, white, emissive_map=TextureId(0))
    with assert_raises():
        rasterize_shaded(a, RasterVertex(6, 0, 0.5, 1, white), c, target)
    with assert_raises():
        rasterize_shaded(a, b, RasterVertex(0, 6, 0.5, 1, white), target)
    # Agreeing is fine, and in SHADE_LIT the map is never opened.
    rasterize_shaded(a, b, c, target)
    # An id nothing can hold is refused whether or not it is sampled.
    var held = RasterVertex(0, 0, 0.5, 1, white, emissive_map=TextureId(-2))
    var held_b = RasterVertex(6, 0, 0.5, 1, white, emissive_map=TextureId(-2))
    var held_c = RasterVertex(0, 6, 0.5, 1, white, emissive_map=TextureId(-2))
    with assert_raises():
        rasterize_shaded(held, held_b, held_c, target)


def glowing_corner(
    x: Float32,
    y: Float32,
    u: Float32,
    v: Float32,
    glow: FloatColor,
    map: TextureId = NO_TEXTURE,
) -> RasterVertex:
    """Return a white lit corner that gives off `glow`, mapped at (u, v)."""
    return RasterVertex(
        x,
        y,
        0.5,
        1,
        FloatColor(1, 1, 1),
        u,
        v,
        NO_TEXTURE,
        OPAQUE,
        Vector3(0, 0, 1),
        Vector3(0, 0, 0),
        LAMBERT,
        glow,
        map,
    )


def glowing_quad(glow: FloatColor, map: TextureId) -> List[RasterVertex]:
    """Return two triangles covering an eight-pixel square, mapped once."""
    var corners = List[RasterVertex]()
    corners.append(glowing_corner(0, 0, 0, 1, glow, map))
    corners.append(glowing_corner(8, 0, 1, 1, glow, map))
    corners.append(glowing_corner(8, 8, 1, 0, glow, map))
    corners.append(glowing_corner(0, 0, 0, 1, glow, map))
    corners.append(glowing_corner(8, 8, 1, 0, glow, map))
    corners.append(glowing_corner(0, 8, 0, 0, glow, map))
    return corners^


def draw_quad(
    corners: List[RasterVertex],
    mode: ShadeMode,
    textures: TextureStore,
    lighting: Lighting,
) raises -> RenderTarget:
    """Return an eight-pixel target with `corners` drawn into it."""
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    for triangle in range(len(corners) // 3):
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            mode,
            textures,
            lighting,
        )
    return target^


def test_the_emissive_is_added_after_the_lights() raises:
    # Half light on a white surface gives half; a glow of a quarter red on
    # top gives three quarters red, and the light does not scale the glow.
    var half = Lighting(ambient=FloatColor(0.5, 0.5, 0.5, 1.0))
    var target = draw_quad(
        glowing_quad(FloatColor(0.25, 0.0, 0.0), NO_TEXTURE),
        SHADE_LIT,
        TextureStore(),
        half,
    )
    var expected = FloatColor(0.75, 0.5, 0.5, 1.0).encode()
    var shown = target.shown(4, 4)
    assert_equal(shown.r, expected.r)
    assert_equal(shown.g, expected.g)
    assert_equal(shown.b, expected.b)
    assert_equal(shown.a, UInt8(255))


def test_an_emissive_map_glows_only_where_it_is_bright() raises:
    # No light at all, so only the glow shows: through a white-and-black
    # board it shows in the light squares and not in the dark ones.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(8, 2, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED)
    )
    var dark = Lighting(ambient=FloatColor(0.0, 0.0, 0.0, 1.0))
    var quad = glowing_quad(FloatColor(1.0, 0.5, 0.0), board)
    var target = draw_quad(quad, SHADE_TEXTURE, textures, dark)
    var glow = FloatColor(1.0, 0.5, 0.0, 1.0).encode()
    # Top left and bottom right are the light squares.
    assert_equal(target.shown(2, 2).r, glow.r)
    assert_equal(target.shown(2, 2).g, glow.g)
    assert_equal(target.shown(6, 6).g, glow.g)
    assert_equal(target.shown(6, 2).r, UInt8(0))
    assert_equal(target.shown(2, 6).r, UInt8(0))
    # SHADE_LIT ignores the map, as it ignores the material's, and keeps the
    # glow everywhere.
    var flat = draw_quad(quad, SHADE_LIT, textures, dark)
    assert_equal(flat.shown(6, 2).r, glow.r)
    assert_equal(flat.shown(2, 6).g, glow.g)


def test_an_emissive_map_that_reads_alpha_as_coverage_is_refused() raises:
    # Filtered as coverage, a map's low alpha would darken the glow, so only
    # a texture built to ignore its alpha is accepted, and only where the
    # map is opened: SHADE_LIT never reads it.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(8, 2, Color(255, 255, 255), Color(0, 0, 0))
    )
    var dark = Lighting(ambient=FloatColor(0.0, 0.0, 0.0, 1.0))
    var quad = glowing_quad(FloatColor(1.0, 1.0, 1.0), board)
    with assert_raises():
        _ = draw_quad(quad, SHADE_TEXTURE, textures, dark)
    var flat = draw_quad(quad, SHADE_LIT, textures, dark)
    assert_equal(flat.shown(4, 4).r, UInt8(255))


def test_corners_that_disagree_about_their_texture_are_rejected() raises:
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(4, 2, Color(255, 0, 0), Color(0, 0, 255))
    )
    var fb = RenderTarget(8, 8, Color(0, 0, 0))
    var t = covering(0.5)
    with assert_raises():
        rasterize_shaded(
            stated_corner(t[0], board, OPAQUE),
            stated_corner(t[1], NO_TEXTURE, OPAQUE),
            stated_corner(t[2], board, OPAQUE),
            fb,
            SHADE_TEXTURE,
            textures,
        )
    with assert_raises():
        rasterize_shaded(
            stated_corner(t[0], board, OPAQUE),
            stated_corner(t[1], board, OPAQUE),
            stated_corner(t[2], NO_TEXTURE, OPAQUE),
            fb,
            SHADE_TEXTURE,
            textures,
        )


# --- Per-fragment shading ---------------------------------------------------


def lit_along_z() raises -> Lighting:
    """Return one white directional light shining along +z, no ambient."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    _ = scene.add(lamp^)
    scene.update()
    scene.add_light(directional_light(Color(255, 255, 255), NodeId(0)))
    return Lighting(scene)


def bent_corner(x: Float32, y: Float32, normal: Vector3) -> RasterVertex:
    """Return a white corner at a point, carrying a normal of its own."""
    return RasterVertex(
        x, y, 0.5, 1, FloatColor(1, 1, 1), 0, 0, NO_TEXTURE, OPAQUE, normal
    )


def test_the_middle_of_a_triangle_is_lit_by_its_own_normal() raises:
    # The whole point of shading per fragment. Two corners lean 45 degrees
    # away from the light, so each catches cos(45) of it. Between them the
    # *normal* interpolates to straight at the light, so the middle is
    # brighter than either end.
    #
    # Shading at the corners and interpolating the color cannot do this: it
    # would mix two equal values and give a flat face. Neither can
    # interpolating the normal without normalizing it -- the average of those
    # two unit vectors is (0, 0, 0.707), which is 0.707 long, and its Lambert
    # term against the light is 0.707 again: exactly the corners' value. The
    # renormalization is what makes the difference, so this test fails if it
    # is dropped.
    var lean = Float32(0.70710678)
    var fb = RenderTarget(32, 16, Color(0, 0, 0))
    rasterize_shaded(
        bent_corner(0, 0, Vector3(-lean, 0, lean)),
        bent_corner(31, 0, Vector3(lean, 0, lean)),
        bent_corner(16, 15, Vector3(0, 0, 1)),
        fb,
        SHADE_LIT,
        TextureStore(),
        lit_along_z(),
    )
    var left_end = fb.shown(2, 1).r
    var middle = fb.shown(16, 1).r
    assert_true(left_end > 0, "the leaning corner caught no light at all")
    assert_true(
        middle > left_end + 20,
        (
            "the middle was no brighter than the corners: the normal was not"
            " interpolated and renormalized per fragment"
        ),
    )
    # The midpoint of the top edge is the one interior pixel whose answer
    # follows from symmetry alone: the two leaning normals cancel in x and
    # leave (0, 0, 0.707), which renormalizes to straight at the light. Fully
    # lit, so 255. Every other pixel's value depends on where it sits in the
    # triangle, so only this one is pinned exactly.
    assert_equal(middle, UInt8(255))
    assert_true(left_end < 240, "the left end was as bright as the middle")


def test_a_face_turned_away_from_every_light_is_black() raises:
    var fb = RenderTarget(16, 16, Color(0, 0, 0))
    var away = Vector3(0, 0, -1)
    rasterize_shaded(
        bent_corner(0, 0, away),
        bent_corner(15, 0, away),
        bent_corner(0, 15, away),
        fb,
        SHADE_LIT,
        TextureStore(),
        lit_along_z(),
    )
    assert_equal(fb.shown(2, 2).r, UInt8(0))


def test_lighting_modulates_a_texture_rather_than_replacing_it() raises:
    # The texel says what color the surface is; the light says how much of
    # it arrives. A half-lit red texel is a darker red, not gray.
    var textures = TextureStore()
    var pixels = List[UInt8]()
    for value in [UInt8(255), UInt8(0), UInt8(0), UInt8(255)]:
        pixels.append(value)
    var red = textures.add(Texture(1, 1, pixels^, REPEAT))
    var lean = Float32(0.70710678)
    var fb = RenderTarget(16, 16, Color(0, 0, 0))
    var slanted = Vector3(lean, 0, lean)
    rasterize_shaded(
        RasterVertex(
            0, 0, 0.5, 1, FloatColor(1, 1, 1), 0, 0, red, OPAQUE, slanted
        ),
        RasterVertex(
            15, 0, 0.5, 1, FloatColor(1, 1, 1), 0, 0, red, OPAQUE, slanted
        ),
        RasterVertex(
            0, 15, 0.5, 1, FloatColor(1, 1, 1), 0, 0, red, OPAQUE, slanted
        ),
        fb,
        SHADE_TEXTURE,
        textures,
        lit_along_z(),
    )
    # All three normals are the same, so every fragment gets the same answer
    # and it can be worked out by hand: a 45 degree lean catches cos(45) of
    # the light, which is 0.7071 of it, and 0.7071 in linear light displays
    # as 219. Not 188 -- that is *half* the light, which is a steeper lean.
    var shown = fb.shown(2, 2)
    assert_equal(shown.r, UInt8(219))
    assert_equal(shown.g, UInt8(0))
    assert_equal(shown.b, UInt8(0))


def test_a_zero_length_normal_is_left_alone_rather_than_dividing_by_it() raises:
    # A hand-built triangle can carry one, and normalizing it would be a
    # divide by zero and a pixel full of NaN. It catches only the ambient.
    var fb = RenderTarget(16, 16, Color(0, 0, 0))
    var nothing = Vector3(0, 0, 0)
    rasterize_shaded(
        bent_corner(0, 0, nothing),
        bent_corner(15, 0, nothing),
        bent_corner(0, 15, nothing),
        fb,
        SHADE_LIT,
        TextureStore(),
        lit_along_z(),
    )
    assert_equal(fb.shown(2, 2).r, UInt8(0))


def test_a_row_range_limits_where_a_triangle_is_drawn() raises:
    # The band-parallel renderer draws every triangle once per band, so a
    # call told to stay within rows must write nothing outside them.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var white = FloatColor(1, 1, 1)
    var a = RasterVertex(0, 0, 0.5, 1, white)
    var b = RasterVertex(8, 0, 0.5, 1, white)
    var c = RasterVertex(0, 8, 0.5, 1, white)
    rasterize_shaded(a, b, c, target, first_row=2, last_row=4)
    for y in range(8):
        var drawn = target.shown(0, y).r > 0
        assert_equal(drawn, y >= 2 and y <= 4)


def test_rasterize_all_on_several_workers_matches_one() raises:
    # Two overlapping triangles, one translucent, so a band boundary cuts
    # through blending as well as depth.
    var corners = List[RasterVertex]()
    corners.append(flat_vertex(Vector3(0, 0, 0.5), Color(0, 255, 0)))
    corners.append(flat_vertex(Vector3(12, 0, 0.5), Color(0, 255, 0)))
    corners.append(flat_vertex(Vector3(0, 12, 0.5), Color(0, 255, 0)))
    var red = Color(255, 0, 0, 128)
    corners.append(flat_vertex(Vector3(2, 2, 0.2), red, 1, BLEND))
    corners.append(flat_vertex(Vector3(12, 2, 0.2), red, 1, BLEND))
    corners.append(flat_vertex(Vector3(2, 12, 0.2), red, 1, BLEND))
    var alone = RenderTarget(12, 12, Color(0, 0, 0))
    rasterize_all(corners, alone)
    var crowd = RenderTarget(12, 12, Color(0, 0, 0))
    rasterize_all(corners, crowd, workers=4)
    var drawn = 0
    for y in range(12):
        for x in range(12):
            var one = alone.shown(x, y)
            var many = crowd.shown(x, y)
            assert_equal(one.r, many.r)
            assert_equal(one.g, many.g)
            assert_equal(one.b, many.b)
            assert_equal(alone.depth_at(x, y), crowd.depth_at(x, y))
            if one.g > 0:
                drawn += 1
    assert_true(drawn > 0, "nothing was drawn")


def test_rasterize_all_with_nothing_to_draw_leaves_the_target_alone() raises:
    var target = RenderTarget(4, 4, Color(9, 9, 9))
    rasterize_all(List[RasterVertex](), target, workers=3)
    assert_equal(target.shown(1, 1).r, UInt8(9))


def test_rasterize_all_carries_a_workers_error_back() raises:
    # A triangle naming a texture the store does not have is refused when a
    # fragment tries to sample it. On a worker that raise cannot propagate,
    # so it is carried back and raised once every band is done -- and must
    # not be dropped on the way. Malformed metadata no longer reaches a band
    # at all: `rasterize_all` refuses it before any band starts.
    var corners = List[RasterVertex]()
    corners.append(stated_corner(Vector3(-2, -2, 0), TextureId(0), OPAQUE))
    corners.append(stated_corner(Vector3(20, -2, 0), TextureId(0), OPAQUE))
    corners.append(stated_corner(Vector3(-2, 20, 0), TextureId(0), OPAQUE))
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var none = TextureStore()
    with assert_raises():
        rasterize_all(corners, target, SHADE_TEXTURE, none, workers=2)
    with assert_raises():
        rasterize_all(corners, target, SHADE_TEXTURE, none)


def test_rasterize_all_needs_whole_triangles_and_a_worker() raises:
    var target = RenderTarget(4, 4, Color(0, 0, 0))
    var corners = List[RasterVertex]()
    corners.append(flat_vertex(Vector3(0, 0, 0), Color(1, 1, 1)))
    with assert_raises():
        rasterize_all(corners, target)
    with assert_raises():
        rasterize_all(List[RasterVertex](), target, workers=0)


# --- fog ----------------------------------------------------------------------


def placed_corner(
    x: Float32,
    y: Float32,
    world: Vector3,
    kind: MaterialKind = BASIC,
    alpha: Float32 = 1.0,
    blend: Blending = OPAQUE,
    glow: FloatColor = FloatColor(0.0, 0.0, 0.0),
    depth: Float32 = 0,
) -> RasterVertex:
    """Return a white corner at a pixel, standing at `world`, facing +z,
    `depth` meters in front of the camera."""
    return RasterVertex(
        x,
        y,
        0.5,
        1,
        FloatColor(1, 1, 1, alpha),
        0,
        0,
        NO_TEXTURE,
        blend,
        Vector3(0, 0, 1),
        world,
        kind,
        glow,
        NO_TEXTURE,
        depth,
    )


def placed_quad(
    depth: Float32,
    kind: MaterialKind = BASIC,
    alpha: Float32 = 1.0,
    blend: Blending = OPAQUE,
    glow: FloatColor = FloatColor(0.0, 0.0, 0.0),
) -> List[RasterVertex]:
    """Return two white triangles covering an eight-pixel target, standing
    `depth` meters in front of a camera at the origin looking down -z."""
    var world = Vector3(0, 0, -depth)
    var corners = List[RasterVertex]()
    corners.append(placed_corner(0, 0, world, kind, alpha, blend, glow, depth))
    corners.append(placed_corner(8, 0, world, kind, alpha, blend, glow, depth))
    corners.append(placed_corner(8, 8, world, kind, alpha, blend, glow, depth))
    corners.append(placed_corner(0, 0, world, kind, alpha, blend, glow, depth))
    corners.append(placed_corner(8, 8, world, kind, alpha, blend, glow, depth))
    corners.append(placed_corner(0, 8, world, kind, alpha, blend, glow, depth))
    return corners^


def gray_fog() raises -> FogView:
    """Return a mid-gray linear fog from one to three meters."""
    return FogView(
        linear_fog(Color(128, 128, 128), Length(1.0, METER), Length(3.0, METER))
    )


def fogged_pixel(
    corners: List[RasterVertex],
    fog: FogView,
    mode: ShadeMode = SHADE_LIT,
    lighting: Lighting = Lighting.uniform(),
    workers: Int = 1,
) raises -> Color:
    """Draw `corners` under `fog` and return the center pixel."""
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(corners, target, mode, TextureStore(), lighting, workers, fog)
    return target.shown(4, 4)


def assert_same_color(shown: Color, expected: Color) raises:
    """Assert two colors agree in every channel."""
    assert_equal(shown.r, expected.r)
    assert_equal(shown.g, expected.g)
    assert_equal(shown.b, expected.b)
    assert_equal(shown.a, expected.a)


def test_fog_veils_a_fragment_by_its_depth() raises:
    # A white unlit surface through a gray fog from one to three meters:
    # untouched at half a meter, half way to the fog color at two, and the
    # fog color alone at four. The mix is in linear light, so half way is
    # half the light of each and not half the bytes.
    var fog = gray_fog()
    var near = fogged_pixel(placed_quad(0.5), fog)
    assert_same_color(near, Color(255, 255, 255))
    var gray = FloatColor(srgb=Color(128, 128, 128))
    var halfway = fogged_pixel(placed_quad(2), fog)
    assert_same_color(
        halfway,
        FloatColor(
            1 + (gray.r - 1) * 0.5,
            1 + (gray.g - 1) * 0.5,
            1 + (gray.b - 1) * 0.5,
            1.0,
        ).encode(),
    )
    assert_true(halfway.r > 128, "the mix was taken on bytes, not on light")
    var far = fogged_pixel(placed_quad(4), fog)
    assert_same_color(far, Color(128, 128, 128))
    # Without fog, or with the view of none, the same surface is white at
    # any depth.
    assert_same_color(
        fogged_pixel(placed_quad(4), FogView.none()), Color(255, 255, 255)
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(placed_quad(4), target)
    assert_same_color(target.shown(4, 4), Color(255, 255, 255))


def test_the_uv_view_is_never_fogged() raises:
    # Coordinates, not light: deep in the fog the debug view still writes
    # the raw coordinates it would write without any fog.
    var fog = gray_fog()
    var veiled = fogged_pixel(placed_quad(40), fog, SHADE_UV)
    var clear = fogged_pixel(placed_quad(40), FogView.none(), SHADE_UV)
    assert_same_color(veiled, clear)
    assert_equal(veiled.b, UInt8(0))


def test_fog_leaves_alpha_alone_and_mixes_before_blending() raises:
    # A half-transparent white surface deep in the fog, over black: the
    # color is fogged to gray first, then half of that light is blended over
    # the black, and the coverage is what the material said.
    var fog = gray_fog()
    var target = RenderTarget(8, 8, Color(0, 0, 0, 0))
    rasterize_all(
        placed_quad(10, BASIC, 0.5, BLEND),
        target,
        SHADE_LIT,
        TextureStore(),
        Lighting.uniform(),
        1,
        fog,
    )
    var gray = FloatColor(srgb=Color(128, 128, 128))
    var shown = target.shown(4, 4)
    assert_same_color(shown, Color(128, 128, 128, 128))
    assert_almost_equal(
        target.color_at(4, 4).r, gray.r * 0.5, atol=Float64(1e-6)
    )


def test_a_lit_surface_is_fogged_after_the_lights_and_the_glow() raises:
    # White, square on to a white lamp, glowing a quarter red, two meters
    # into the fog: the light and the glow make (1.25, 1, 1), and only then
    # is it mixed half way to gray. Fogging before the glow would leave the
    # glow unveiled.
    var fog = gray_fog()
    var quad = placed_quad(2, LAMBERT, 1.0, OPAQUE, FloatColor(0.25, 0.0, 0.0))
    var shown = fogged_pixel(quad, fog, SHADE_LIT, lit_along_z())
    var gray = FloatColor(srgb=Color(128, 128, 128))
    var expected = FloatColor(
        1.25 + (gray.r - 1.25) * 0.5,
        1 + (gray.g - 1) * 0.5,
        1 + (gray.b - 1) * 0.5,
        1.0,
    ).encode()
    assert_same_color(shown, expected)


def test_fog_is_the_same_on_one_worker_and_on_four() raises:
    var fog = FogView(
        exp2_fog(Color(200, 220, 255), InverseLength(0.3, PER_METER))
    )
    var quad = placed_quad(3, LAMBERT)
    var alone = fogged_pixel(quad, fog, SHADE_LIT, lit_along_z(), 1)
    var crowd = fogged_pixel(quad, fog, SHADE_LIT, lit_along_z(), 4)
    assert_same_color(alone, crowd)
    assert_true(alone.b > alone.r, "the exponential fog tinted nothing")


def test_a_blinding_surface_fully_fogged_is_the_fog_color() raises:
    # A surface a million times brighter than the fog, deep in it: exactly
    # the fog color, without a curve and through one. The lerp subtracted
    # the surface from the fog color and came out black; at sixty-five
    # thousand it lost a level or two.
    var fog = gray_fog()
    var blinding = placed_quad(
        10, BASIC, 1.0, OPAQUE, FloatColor(1.0e6, 1.0e6, 1.0e6)
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        blinding, target, SHADE_LIT, TextureStore(), Lighting.uniform(), 1, fog
    )
    assert_same_color(target.shown(4, 4), Color(128, 128, 128))
    var gray = FloatColor(srgb=Color(128, 128, 128))
    var curved = target.resolve(1, REINHARD_TONE_MAPPING)
    var expected = tone_map(gray, REINHARD_TONE_MAPPING, 1.0).encode()
    assert_same_color(curved.get_pixel(4, 4), expected)
    var bright = placed_quad(
        10, BASIC, 1.0, OPAQUE, FloatColor(65536.0, 65536.0, 65536.0)
    )
    var again = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        bright, again, SHADE_LIT, TextureStore(), Lighting.uniform(), 1, fog
    )
    assert_same_color(again.shown(4, 4), Color(128, 128, 128))


def test_a_view_built_by_hand_is_refused_before_a_fragment_is_drawn() raises:
    # The low-level entry points take a view directly, and one can hold
    # anything: refused on one worker and on four, per triangle, and for an
    # unknown kind as for a color that is not a number.
    var broken = FogView(
        LINEAR_FOG, FloatColor(nan[DType.float32](), 0.5, 0.5, 1.0), 1, 5, 0
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    with assert_raises():
        rasterize_all(
            placed_quad(2),
            target,
            SHADE_LIT,
            TextureStore(),
            Lighting.uniform(),
            1,
            broken,
        )
    with assert_raises():
        rasterize_all(
            placed_quad(2),
            target,
            SHADE_LIT,
            TextureStore(),
            Lighting.uniform(),
            4,
            broken,
        )
    var quad = placed_quad(2)
    with assert_raises():
        rasterize_shaded(
            quad[0],
            quad[1],
            quad[2],
            target,
            SHADE_LIT,
            TextureStore(),
            Lighting.uniform(),
            0,
            -1,
            broken,
        )
    var unknown = FogView(FogKind(9), FloatColor(0.5, 0.5, 0.5, 1.0), 1, 5, 0)
    with assert_raises():
        rasterize_all(
            placed_quad(2),
            target,
            SHADE_LIT,
            TextureStore(),
            Lighting.uniform(),
            1,
            unknown,
        )


# --- data materials: the normal and the depth -------------------------------


def data_corner(
    x: Float32,
    y: Float32,
    kind: MaterialKind,
    normal: Vector3 = Vector3(0, 0, 1),
    z: Float32 = 0.5,
    alpha: Float32 = 1.0,
    blend: Blending = OPAQUE,
    depth: Float32 = 0,
    texture: TextureId = NO_TEXTURE,
    alpha_map: TextureId = NO_TEXTURE,
    alpha_test: Float32 = 0,
) -> RasterVertex:
    """Return a white corner of a data material, facing `normal`.

    White and opaque, so that anything but white in the image is the data
    the material shows rather than the color it carries.
    """
    return RasterVertex(
        x,
        y,
        z,
        1,
        FloatColor(1, 1, 1, alpha),
        0,
        0,
        texture,
        blend,
        normal,
        Vector3(0, 0, 0),
        kind,
        FloatColor(0.0, 0.0, 0.0),
        NO_TEXTURE,
        depth,
        alpha_map,
        alpha_test,
    )


def data_quad(
    kind: MaterialKind,
    normal: Vector3 = Vector3(0, 0, 1),
    z: Float32 = 0.5,
    alpha: Float32 = 1.0,
    blend: Blending = OPAQUE,
    depth: Float32 = 0,
    texture: TextureId = NO_TEXTURE,
    alpha_map: TextureId = NO_TEXTURE,
    alpha_test: Float32 = 0,
) -> List[RasterVertex]:
    """Return two triangles of a data material covering an eight-pixel
    target."""
    var corners = List[RasterVertex]()
    var places: List[Tuple[Float32, Float32]] = [
        (Float32(0), Float32(0)),
        (Float32(8), Float32(0)),
        (Float32(8), Float32(8)),
        (Float32(0), Float32(0)),
        (Float32(8), Float32(8)),
        (Float32(0), Float32(8)),
    ]
    for place in places:
        corners.append(
            data_corner(
                place[0],
                place[1],
                kind,
                normal,
                z,
                alpha,
                blend,
                depth,
                texture,
                alpha_map,
                alpha_test,
            )
        )
    return corners^


def data_pixel(
    corners: List[RasterVertex],
    fog: FogView = FogView.none(),
    lighting: Lighting = Lighting.uniform(),
    mode: ShadeMode = SHADE_TEXTURE,
    textures: TextureStore = TextureStore(),
    workers: Int = 1,
) raises -> RenderTarget:
    """Draw `corners` into an eight-pixel target and return it."""
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(corners, target, mode, textures, lighting, workers, fog)
    return target^


def test_a_normal_is_packed_into_zero_to_one_per_axis() raises:
    # three.js's `packNormalToRGB`: halved and moved up by a half, so a
    # surface square on to the camera is (0.5, 0.5, 1).
    var square = packed_normal(Vector3(0, 0, 1))
    assert_equal(square.x, Float32(0.5))
    assert_equal(square.y, Float32(0.5))
    assert_equal(square.z, Float32(1.0))
    var right = packed_normal(Vector3(1, 0, 0))
    assert_equal(right.x, Float32(1.0))
    assert_equal(right.y, Float32(0.5))
    assert_equal(right.z, Float32(0.5))
    var down = packed_normal(Vector3(0, -1, 0))
    assert_equal(down.x, Float32(0.5))
    assert_equal(down.y, Float32(0.0))
    assert_equal(down.z, Float32(0.5))


def test_a_depth_is_one_at_the_near_plane_and_zero_at_the_far_one() raises:
    # NDC depth runs -1 to 1, and three.js writes one minus the window-space
    # depth, which is half of it plus a half.
    assert_equal(packed_depth(-1.0), Float32(1.0))
    assert_equal(packed_depth(0.0), Float32(0.5))
    assert_equal(packed_depth(1.0), Float32(0.0))
    assert_equal(packed_depth(0.5), Float32(0.25))


def test_data_resolves_to_the_bytes_it_names() raises:
    # Data is stored decoded, so `resolve`'s encode gives the bytes back
    # unchanged. A half is byte 128 whatever the sRGB curve does to light.
    var shown = data_color(0.5, 0.25, 0.0, 0.75)
    assert_equal(shown.r, FloatColor(srgb=Color(128, 128, 128)).r)
    assert_equal(shown.g, FloatColor(srgb=Color(64, 64, 64)).r)
    assert_equal(shown.b, Float32(0))
    assert_equal(shown.a, Float32(0.75))
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.write(0, 0, shown, True)
    assert_same_color(target.shown(0, 0), Color(128, 64, 0, 191))
    assert_same_color(target.resolve().get_pixel(0, 0), Color(128, 64, 0, 191))


def test_a_normal_material_writes_its_normal_and_not_its_color() raises:
    # A white surface square on to the camera is (128, 128, 255), whatever
    # the lights would have done to a white surface.
    var half = Lighting(ambient=FloatColor(0.5, 0.5, 0.5, 1.0))
    var facing = data_pixel(data_quad(NORMALS), lighting=half)
    assert_same_color(facing.shown(4, 4), Color(128, 128, 255))
    # Turned to the camera's right, and turned down.
    var right = data_pixel(data_quad(NORMALS, Vector3(1, 0, 0)))
    assert_same_color(right.shown(4, 4), Color(255, 128, 128))
    var down = data_pixel(data_quad(NORMALS, Vector3(0, -1, 0)))
    assert_same_color(down.shown(4, 4), Color(128, 0, 128))
    # The same surface as a basic material shows the color instead, so the
    # normal really is what changed.
    var plain = data_pixel(data_quad(BASIC), lighting=half)
    assert_same_color(plain.shown(4, 4), Color(255, 255, 255))


def test_a_normal_material_makes_the_normal_unit_length_per_fragment() raises:
    # A normal half a unit long: normalized it is (1, 0, 0) and shows 255,
    # and packed as it arrives it would show 191.
    var shown = data_pixel(data_quad(NORMALS, Vector3(0.5, 0, 0)))
    assert_same_color(shown.shown(4, 4), Color(255, 128, 128))
    # A normal of no length has no direction to normalize, and is packed as
    # it is: the middle of every channel.
    var none = data_pixel(data_quad(NORMALS, Vector3(0, 0, 0)))
    assert_same_color(none.shown(4, 4), Color(128, 128, 128))


def test_a_depth_material_writes_its_depth_as_a_gray() raises:
    # A quarter of the way from the far plane to the near one is byte 64.
    var near = data_pixel(data_quad(DEPTH, z=-1.0))
    assert_same_color(near.shown(4, 4), Color(255, 255, 255))
    var middle = data_pixel(data_quad(DEPTH, z=0.0))
    assert_same_color(middle.shown(4, 4), Color(128, 128, 128))
    var far = data_pixel(data_quad(DEPTH, z=0.5))
    assert_same_color(far.shown(4, 4), Color(64, 64, 64))
    var furthest = data_pixel(data_quad(DEPTH, z=1.0))
    assert_same_color(furthest.shown(4, 4), Color(0, 0, 0))
    # The normal is not read: a depth material with its surface turned away
    # shows the same gray.
    var turned = data_pixel(data_quad(DEPTH, Vector3(1, 0, 0), 0.5))
    assert_same_color(turned.shown(4, 4), Color(64, 64, 64))


def test_a_maps_alpha_cuts_a_depth_out_and_its_color_does_not() raises:
    # three.js's `MeshDepthMaterial` reads its map's alpha. A red texel at
    # half alpha halves the coverage and leaves the gray alone.
    var pixels = List[UInt8]()
    for value in [255, 0, 0, 128]:
        pixels.append(UInt8(value))
    var textures = TextureStore()
    var cut = textures.add(Texture(1, 1, pixels^))
    var shown = data_pixel(
        data_quad(DEPTH, z=0.5, texture=cut), textures=textures
    )
    assert_same_color(shown.shown(4, 4), Color(64, 64, 64, 128))
    # The alpha reaches the pixel as coverage and the gray comes back
    # exact, because the fragment is written rather than mixed. Mixing is
    # refused: see the next test.


def test_a_data_triangle_cannot_blend() raises:
    # One pixel cannot hold part of a normal and part of the scene's light.
    # Refused by both backends from the same function, on one worker and
    # on four, so `RenderTarget.blend` can say a mixture is always light.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    for kind in [NORMALS, DEPTH]:
        var corners = data_quad(kind, blend=BLEND)
        with assert_raises():
            rasterize_shaded(corners[0], corners[1], corners[2], target)
        for workers in [1, 4]:
            with assert_raises():
                rasterize_all(corners, target, workers=workers)
        # Opaque is what such a surface must be, and it draws.
        rasterize_all(data_quad(kind, blend=OPAQUE), target)
    # A lit triangle blends as it always did.
    rasterize_all(data_quad(LAMBERT, blend=BLEND), target)
    rasterize_all(data_quad(BASIC, blend=BLEND), target)


def test_a_data_material_is_never_fogged() raises:
    # The fog mixes light, and a normal is not light. A basic surface at the
    # same depth is veiled, which is what makes this a test.
    var fog = gray_fog()
    var veiled = fogged_pixel(placed_quad(2, BASIC), fog)
    assert_true(veiled.r < 255, "the fog reached nothing")
    for kind in [NORMALS, DEPTH]:
        # Half way into the fog, and far past it: the same pixel either way,
        # and the same as with no fog at all.
        var clear = data_pixel(data_quad(kind, Vector3(1, 2, 3), 0.25))
        var halfway = data_pixel(
            data_quad(kind, Vector3(1, 2, 3), 0.25, depth=2), fog
        )
        var swallowed = data_pixel(
            data_quad(kind, Vector3(1, 2, 3), 0.25, depth=40), fog
        )
        assert_same_color(halfway.shown(4, 4), clear.shown(4, 4))
        assert_same_color(swallowed.shown(4, 4), clear.shown(4, 4))


def test_a_data_material_is_never_tone_mapped() raises:
    # A curve that compresses light would make a normal lie about its own
    # numbers, so the target keeps it off a pixel that holds data.
    var facing = data_pixel(data_quad(NORMALS))
    var curved = facing.resolve(1, REINHARD_TONE_MAPPING)
    assert_same_color(curved.get_pixel(4, 4), Color(128, 128, 255))
    assert_true(facing.is_data(4, 4))
    assert_true(facing.is_data(0, 0))
    # The same white surface as light really is compressed by that curve.
    var plain = data_pixel(data_quad(BASIC))
    assert_false(plain.is_data(4, 4))
    var squeezed = plain.resolve(1, REINHARD_TONE_MAPPING)
    assert_true(
        squeezed.get_pixel(4, 4).b < 255, "the curve compressed nothing"
    )


def test_a_data_material_draws_the_same_on_one_worker_and_on_four() raises:
    var alone = data_pixel(data_quad(NORMALS, Vector3(1, 2, 3)), workers=1)
    var crowd = data_pixel(data_quad(NORMALS, Vector3(1, 2, 3)), workers=4)
    for y in range(8):
        for x in range(8):
            assert_same_color(alone.shown(x, y), crowd.shown(x, y))
            assert_equal(alone.is_data(x, y), crowd.is_data(x, y))


def test_an_unknown_material_kind_is_refused_even_when_agreed() raises:
    # `MaterialKind(9)` constructs, because a struct's fields are open, and
    # neither backend has a fragment path for it. Agreement is not enough.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var corners = data_quad(MaterialKind(9))
    with assert_raises():
        rasterize_shaded(corners[0], corners[1], corners[2], target)
    for workers in [1, 4]:
        with assert_raises():
            rasterize_all(corners, target, workers=workers)


def test_every_material_kind_shades_a_fragment() raises:
    # Each of the four has its own fragment path, and each has to reach a
    # pixel rather than fall through to another kind's.
    var lamp = Lighting(ambient=FloatColor(0.5, 0.5, 0.5, 1.0))
    assert_same_color(
        data_pixel(data_quad(LAMBERT), lighting=lamp).shown(4, 4),
        Color(188, 188, 188),
    )
    assert_same_color(
        data_pixel(data_quad(BASIC), lighting=lamp).shown(4, 4),
        Color(255, 255, 255),
    )
    assert_same_color(
        data_pixel(data_quad(NORMALS), lighting=lamp).shown(4, 4),
        Color(128, 128, 255),
    )
    assert_same_color(
        data_pixel(data_quad(DEPTH, z=0.0), lighting=lamp).shown(4, 4),
        Color(128, 128, 128),
    )


# --- alpha maps and the alpha test ------------------------------------------


def a_mask(
    green: UInt8,
    space: ColorSpace = LINEAR,
    alpha: Alpha = IGNORED,
) raises -> Texture:
    """Return a one-texel alpha map whose green channel is `green`.

    Red and blue are deliberately not `green`: three.js reads `.g` and
    nothing else, and a gray texel could not tell the two apart.
    """
    var pixels = List[UInt8]()
    pixels.append(0)
    pixels.append(green)
    pixels.append(255)
    pixels.append(255)
    return Texture(1, 1, pixels^, REPEAT, NEAREST, space, False, alpha)


def test_an_alpha_map_must_be_stored_as_data() raises:
    # Its green channel is a coverage. The sRGB curve would turn a byte of
    # 128 into 0.216, and a coverage-weighted filter would weight it by an
    # alpha that means nothing.
    check_alpha_map(a_mask(128))
    with assert_raises():
        check_alpha_map(a_mask(128, SRGB, IGNORED))
    with assert_raises():
        check_alpha_map(a_mask(128, LINEAR, COVERAGE))
    with assert_raises():
        check_alpha_map(a_mask(128, SRGB, COVERAGE))


def test_an_alpha_maps_green_channel_thins_the_surface() raises:
    # three.js's `alphamap_fragment` reads `.g` and multiplies the alpha by
    # it. The texture is linear, so the byte arrives as it was stored.
    var textures = TextureStore()
    var mask = textures.add(a_mask(128))
    var shown = data_pixel(data_quad(BASIC, alpha_map=mask), textures=textures)
    assert_same_color(shown.shown(4, 4), Color(255, 255, 255, 128))
    # A green of 255 leaves the surface alone, and one of zero empties it.
    var whole = textures.add(a_mask(255))
    var solid = data_pixel(data_quad(BASIC, alpha_map=whole), textures=textures)
    assert_same_color(solid.shown(4, 4), Color(255, 255, 255, 255))
    var empty = textures.add(a_mask(0))
    var gone = data_pixel(data_quad(BASIC, alpha_map=empty), textures=textures)
    assert_equal(gone.shown(4, 4).a, UInt8(0))


def test_an_alpha_map_multiplies_the_opacity_it_is_given() raises:
    # The map thins whatever alpha reached it, as three.js multiplies into
    # `diffuseColor.a`: half an opacity through a half map is a quarter.
    var textures = TextureStore()
    var mask = textures.add(a_mask(128))
    var shown = data_pixel(
        data_quad(BASIC, alpha=0.5, alpha_map=mask), textures=textures
    )
    assert_equal(shown.shown(4, 4).a, UInt8(64))


def test_an_alpha_map_leaves_the_color_alone() raises:
    # Only the alpha. The map's red and blue say nothing, and neither does
    # its green about the color.
    var textures = TextureStore()
    var mask = textures.add(a_mask(128))
    var shown = data_pixel(data_quad(BASIC, alpha_map=mask), textures=textures)
    var pixel = shown.shown(4, 4)
    assert_equal(pixel.r, UInt8(255))
    assert_equal(pixel.g, UInt8(255))
    assert_equal(pixel.b, UInt8(255))


def test_the_alpha_test_throws_a_fragment_away() raises:
    # three.js's `alphatest_fragment`: below the test the fragment is
    # discarded. At the test it survives, because the comparison is strict.
    var cut = data_pixel(data_quad(BASIC, alpha=0.4, alpha_test=0.5))
    assert_same_color(cut.shown(4, 4), Color(0, 0, 0))
    var kept = data_pixel(data_quad(BASIC, alpha=0.4, alpha_test=0.4))
    assert_equal(kept.shown(4, 4).a, UInt8(102))
    # A test of zero is no test at all, as in three.js.
    var every = data_pixel(data_quad(BASIC, alpha=0.0, alpha_test=0.0))
    assert_equal(every.shown(4, 4).a, UInt8(0))
    assert_false(every.is_data(4, 4))


def test_an_alpha_map_and_the_test_cut_a_shape_out() raises:
    # The pair together: the map thins the surface and the test throws away
    # what it thinned too far. This is the cut-out leaf.
    var textures = TextureStore()
    var thin = textures.add(a_mask(100))
    var thick = textures.add(a_mask(200))
    var gone = data_pixel(
        data_quad(BASIC, alpha_map=thin, alpha_test=0.5), textures=textures
    )
    assert_same_color(gone.shown(4, 4), Color(0, 0, 0))
    var there = data_pixel(
        data_quad(BASIC, alpha_map=thick, alpha_test=0.5), textures=textures
    )
    assert_equal(there.shown(4, 4).r, UInt8(255))


def two_quads(
    near: List[RasterVertex], far: List[RasterVertex]
) -> List[RasterVertex]:
    """Return `near` submitted before `far`, as one triangle list."""
    var corners = List[RasterVertex]()
    for corner in near:
        corners.append(corner)
    for corner in far:
        corners.append(corner)
    return corners^


def test_a_discarded_fragment_claims_no_depth() raises:
    # The whole point of a cut-out: the hole shows what is behind it. The
    # near surface is drawn first and thrown away, so the far one wins even
    # though it is further.
    var near = data_quad(BASIC, z=-0.5, alpha=0.0, alpha_test=0.5)
    var far = data_quad(LAMBERT, z=0.5)
    var shown = data_pixel(two_quads(near, far))
    assert_equal(shown.shown(4, 4).r, UInt8(255))
    assert_equal(shown.depth_at(4, 4), Float32(0.5))
    # A fragment that survives does claim it, so the far one is hidden.
    var solid = data_quad(BASIC, z=-0.5, alpha=1.0, alpha_test=0.5)
    var hidden = data_pixel(two_quads(solid, far))
    assert_equal(hidden.depth_at(4, 4), Float32(-0.5))
    # And nothing is claimed where the near surface never covered.
    var empty = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(near, empty)
    assert_true(empty.depth_at(4, 4) > 1.0e30, "the hole claimed a depth")


def test_the_alpha_test_reaches_a_translucent_surface_too() raises:
    # three.js tests every material, not only the opaque ones. A blended
    # fragment claims no depth either way, so only the color changes.
    var gone = data_pixel(
        data_quad(BASIC, alpha=0.2, blend=BLEND, alpha_test=0.5)
    )
    assert_same_color(gone.shown(4, 4), Color(0, 0, 0))
    var mixed = data_pixel(
        data_quad(BASIC, alpha=0.6, blend=BLEND, alpha_test=0.5)
    )
    assert_true(mixed.shown(4, 4).r > 0, "the blended fragment was thrown away")


def test_the_alpha_test_applies_to_a_data_material() raises:
    # A depth material's alpha is its opacity, and three.js's
    # `MeshDepthMaterial` has an alpha test like any other material.
    var gone = data_pixel(data_quad(DEPTH, z=0.0, alpha=0.2, alpha_test=0.5))
    assert_same_color(gone.shown(4, 4), Color(0, 0, 0))
    var there = data_pixel(data_quad(DEPTH, z=0.0, alpha=0.8, alpha_test=0.5))
    assert_equal(there.shown(4, 4).r, UInt8(128))


def test_lit_shading_ignores_the_alpha_map_but_keeps_the_test() raises:
    # `SHADE_LIT` ignores every texture, the alpha map included, so the
    # alpha reaching the test is the material's own.
    var textures = TextureStore()
    var mask = textures.add(a_mask(128))
    var corners = data_quad(BASIC, alpha_map=mask, alpha_test=0.6)
    var sampled = data_pixel(corners, textures=textures)
    assert_same_color(sampled.shown(4, 4), Color(0, 0, 0))
    var ignored = data_pixel(corners, textures=textures, mode=SHADE_LIT)
    assert_equal(ignored.shown(4, 4).r, UInt8(255))


def test_the_uv_view_cuts_nothing_out() raises:
    # It shows the nearest surface's coordinates and samples no texture, so
    # neither the map nor the test reaches it.
    var textures = TextureStore()
    var mask = textures.add(a_mask(0))
    var shown = data_pixel(
        data_quad(BASIC, alpha=0.0, alpha_map=mask, alpha_test=0.9),
        textures=textures,
        mode=SHADE_UV,
    )
    assert_true(shown.is_data(4, 4))
    assert_equal(shown.shown(4, 4).a, UInt8(255))


def test_corners_that_disagree_about_thinning_are_rejected() raises:
    # The alpha map and the alpha test are per triangle like the blend
    # policy, and read from the first corner.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var corners = data_quad(BASIC)
    var mapped = data_quad(BASIC, alpha_map=TextureId(0))
    with assert_raises():
        rasterize_shaded(corners[0], mapped[1], corners[2], target)
    with assert_raises():
        rasterize_shaded(corners[0], corners[1], mapped[2], target)
    var tested = data_quad(BASIC, alpha_test=0.5)
    with assert_raises():
        rasterize_shaded(corners[0], tested[1], corners[2], target)
    with assert_raises():
        rasterize_shaded(corners[0], corners[1], tested[2], target)


def test_an_alpha_test_outside_zero_to_one_is_refused() raises:
    # A corner's fields are open, and a threshold nothing can reach is a
    # mistake rather than a choice. Not a number is worse: every comparison
    # with it is false, so the test would silently stop testing.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    for bad in [Float32(-0.5), Float32(1.5), nan[DType.float32]()]:
        var corners = data_quad(BASIC, alpha_test=bad)
        with assert_raises():
            rasterize_shaded(corners[0], corners[1], corners[2], target)
        for workers in [1, 4]:
            with assert_raises():
                rasterize_all(corners, target, workers=workers)
    # The two ends are legal.
    var none = data_quad(BASIC, alpha_test=0.0)
    rasterize_all(none, target)
    var all_of_it = data_quad(BASIC, alpha_test=1.0)
    rasterize_all(all_of_it, target)


def test_an_alpha_map_id_that_nothing_can_hold_is_refused() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var corners = data_quad(BASIC, alpha_map=TextureId(-2))
    with assert_raises():
        rasterize_shaded(corners[0], corners[1], corners[2], target)
    # The absence value is fine.
    rasterize_all(data_quad(BASIC, alpha_map=NO_TEXTURE), target)


def test_an_alpha_map_that_is_not_data_is_refused_before_a_fragment() raises:
    # Asked once per call, before the first fragment, as the GPU asks it
    # before the launch -- and only when the map will be opened.
    var textures = TextureStore()
    var wrong = textures.add(a_mask(128, SRGB, IGNORED))
    var corners = data_quad(BASIC, alpha_map=wrong)
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    with assert_raises():
        rasterize_all(corners, target, SHADE_TEXTURE, textures)
    with assert_raises():
        rasterize_shaded(
            corners[0], corners[1], corners[2], target, SHADE_TEXTURE, textures
        )
    # `SHADE_LIT` never opens it, so it is not refused there.
    rasterize_all(corners, target, SHADE_LIT, textures)


# --- the phong highlight ----------------------------------------------------


def lit_along_z_from(z: Float32) raises -> Lighting:
    """Return one white directional light shining from up the z axis, with
    the camera `z` meters up it."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, 1.0))
    scene.update()
    return Lighting(scene, Layers.all(), Vector3(0, 0, z))


def test_a_phong_triangle_adds_a_highlight_a_lambert_one_has_not() raises:
    # The same black surface under the same light: a lambert one is black
    # and a phong one shows its highlight, which is four times a white
    # specular head on and so clamps to white.
    var lighting = lit_along_z_from(4)
    var dull = data_quad(LAMBERT, alpha=1.0)
    var flat = data_pixel(dull, lighting=lighting)
    var shiny = phong_quad(FloatColor(1, 1, 1), 30.0)
    var bright = data_pixel(shiny, lighting=lighting)
    # `data_quad` carries a white color, so the lambert one is already
    # white; a black one shows the difference the highlight makes.
    var black = black_phong_quad(FloatColor(1, 1, 1), 30.0)
    var only = data_pixel(black, lighting=lighting)
    assert_same_color(only.shown(4, 4), Color(255, 255, 255))
    # A black specular is not quite nothing: three.js's F_Schlick rises
    # toward one at a grazing angle, and head on it leaves a couple of
    # levels rather than zero.
    var none = black_phong_quad(FloatColor(0, 0, 0), 30.0)
    assert_true(
        data_pixel(none, lighting=lighting).shown(4, 4).r < 4,
        "a black specular reflected a visible highlight",
    )
    # And the lit white surface is brighter with the highlight than without.
    assert_true(
        bright.color_at(4, 4).r > flat.color_at(4, 4).r,
        "the highlight added nothing",
    )


def test_a_dimmer_specular_gives_a_measurable_highlight() raises:
    # A black surface with a mid-gray specular, head on: the lobe is
    # sixteen, the geometric term a quarter, and the Fresnel weight leaves
    # the gray almost as it is. Four times the decoded gray, near enough.
    var lighting = lit_along_z_from(4)
    var sheen = FloatColor(srgb=Color(128, 128, 128)).r
    var shown = data_pixel(
        black_phong_quad(FloatColor(sheen, sheen, sheen), 30.0),
        lighting=lighting,
    )
    var expected = FloatColor(sheen * 4, sheen * 4, sheen * 4, 1.0).encode()
    var pixel = shown.shown(4, 4)
    assert_true(
        _apart_by(pixel.r, expected.r) <= 1, "the highlight is the wrong size"
    )
    # Half as shiny is half as bright at the center.
    var wider = data_pixel(
        black_phong_quad(FloatColor(sheen, sheen, sheen), 14.0),
        lighting=lighting,
    )
    assert_true(wider.color_at(4, 4).r < shown.color_at(4, 4).r)


def _apart_by(a: UInt8, b: UInt8) -> Int:
    """Return how many levels apart two channel values are."""
    if a > b:
        return Int(a) - Int(b)
    return Int(b) - Int(a)


def phong_corner(
    x: Float32,
    y: Float32,
    specular: FloatColor,
    shininess: Float32,
    color: FloatColor = FloatColor(1, 1, 1),
    texture: TextureId = NO_TEXTURE,
    glow: FloatColor = FloatColor(0.0, 0.0, 0.0),
    depth: Float32 = 0,
) -> RasterVertex:
    """Return a phong corner facing the camera, at the world origin."""
    return RasterVertex(
        x,
        y,
        0.5,
        1,
        color,
        0,
        0,
        texture,
        OPAQUE,
        Vector3(0, 0, 1),
        Vector3(0, 0, 0),
        PHONG,
        glow,
        NO_TEXTURE,
        depth,
        NO_TEXTURE,
        0,
        specular,
        shininess,
    )


def phong_quad(
    specular: FloatColor,
    shininess: Float32,
    color: FloatColor = FloatColor(1, 1, 1),
    texture: TextureId = NO_TEXTURE,
    glow: FloatColor = FloatColor(0.0, 0.0, 0.0),
    depth: Float32 = 0,
) -> List[RasterVertex]:
    """Return two phong triangles covering an eight-pixel target."""
    var corners = List[RasterVertex]()
    var places: List[Tuple[Float32, Float32]] = [
        (Float32(0), Float32(0)),
        (Float32(8), Float32(0)),
        (Float32(8), Float32(8)),
        (Float32(0), Float32(0)),
        (Float32(8), Float32(8)),
        (Float32(0), Float32(8)),
    ]
    for place in places:
        corners.append(
            phong_corner(
                place[0],
                place[1],
                specular,
                shininess,
                color,
                texture,
                glow,
                depth,
            )
        )
    return corners^


def black_phong_quad(
    specular: FloatColor, shininess: Float32
) -> List[RasterVertex]:
    """Return `phong_quad` with a black base color, so only the highlight
    reaches the pixel."""
    return phong_quad(specular, shininess, FloatColor(0, 0, 0))


def test_the_highlight_is_not_tinted_by_the_color_or_the_texture() raises:
    # three.js adds `directSpecular` to the outgoing light rather than
    # multiplying it into `diffuseColor`, which is why a red plastic ball
    # has a white highlight. A black surface and a red one send the same.
    var lighting = lit_along_z_from(4)
    var sheen = FloatColor(srgb=Color(64, 64, 64)).r
    var specular = FloatColor(sheen, sheen, sheen)
    var black = data_pixel(
        phong_quad(specular, 30.0, FloatColor(0, 0, 0)), lighting=lighting
    )
    var red = data_pixel(
        phong_quad(specular, 30.0, FloatColor(1, 0, 0)), lighting=lighting
    )
    # Red keeps its own red and adds the same green as the black one.
    assert_equal(red.shown(4, 4).g, black.shown(4, 4).g)
    assert_true(red.shown(4, 4).r > black.shown(4, 4).r)
    # A texture that empties the color leaves the highlight alone too.
    var textures = TextureStore()
    var dark = textures.add(a_mask(0, SRGB, IGNORED))
    var mapped = data_pixel(
        phong_quad(specular, 30.0, FloatColor(1, 1, 1), dark),
        lighting=lighting,
        textures=textures,
    )
    assert_equal(mapped.shown(4, 4).g, black.shown(4, 4).g)


def test_the_highlight_is_added_before_the_fog() raises:
    # The fog veils the finished color, highlight included, as it veils the
    # glow: three.js mixes it last of all.
    var lighting = lit_along_z_from(4)
    var sheen = FloatColor(srgb=Color(128, 128, 128)).r
    var quad = phong_quad(
        FloatColor(sheen, sheen, sheen), 30.0, FloatColor(0, 0, 0), depth=2
    )
    var clear = data_pixel(quad, lighting=lighting)
    var veiled = data_pixel(
        phong_quad(
            FloatColor(sheen, sheen, sheen), 30.0, FloatColor(0, 0, 0), depth=2
        ),
        gray_fog(),
        lighting,
    )
    assert_true(
        veiled.shown(4, 4).r != clear.shown(4, 4).r,
        "the fog left the highlight alone",
    )


def test_corners_that_disagree_about_shininess_are_rejected() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var sharp = phong_quad(FloatColor(1, 1, 1), 30.0)
    var soft = phong_quad(FloatColor(1, 1, 1), 5.0)
    with assert_raises():
        rasterize_shaded(sharp[0], soft[1], sharp[2], target)
    with assert_raises():
        rasterize_shaded(sharp[0], sharp[1], soft[2], target)
    rasterize_shaded(sharp[0], sharp[1], sharp[2], target)


def test_a_shininess_that_is_not_a_number_is_refused() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    for bad in [Float32(-1.0), nan[DType.float32]()]:
        var corners = phong_quad(FloatColor(1, 1, 1), bad)
        with assert_raises():
            rasterize_shaded(corners[0], corners[1], corners[2], target)
        for workers in [1, 4]:
            with assert_raises():
                rasterize_all(corners, target, workers=workers)
    # Zero and a very tight lobe are both legal.
    rasterize_all(phong_quad(FloatColor(1, 1, 1), 0.0), target)
    rasterize_all(phong_quad(FloatColor(1, 1, 1), 1000.0), target)


# --- interpolation that keeps a constant constant ---------------------------


def test_a_constant_alpha_survives_interpolation() raises:
    # The weights are three rounded floats that sum to one only up to
    # rounding, so the obvious `a * sa + b * sb + c * sc` can reach
    # 0.99999994 for three alphas of one. That is invisible where alpha is
    # quantized and fatal where it is compared: an alpha test of one then
    # throws away a fully opaque surface.
    assert_equal(interpolate_alpha(1.0, 1.0, 1.0, 0.9499999, 0.041666664), 1.0)
    assert_equal(interpolate_alpha(0.5, 0.5, 0.5, 0.3, 0.45), 0.5)
    # The old spelling does not, at the weights one real pixel produced.
    var summed = (
        Float32(1) * Float32(0.008333333)
        + Float32(1) * Float32(0.9499999)
        + Float32(1) * Float32(0.041666664)
    )
    assert_true(summed < 1.0, "the weights no longer expose the rounding")
    # Where the alphas differ it interpolates as it always did: the ends
    # exactly, and the middle in between.
    assert_equal(interpolate_alpha(0.0, 1.0, 1.0, 0.0, 0.0), 0.0)
    assert_equal(interpolate_alpha(0.0, 1.0, 0.0, 1.0, 0.0), 1.0)
    assert_equal(interpolate_alpha(0.0, 0.0, 1.0, 0.0, 1.0), 1.0)
    assert_almost_equal(
        interpolate_alpha(0.0, 1.0, 1.0, 0.25, 0.25),
        Float32(0.5),
        atol=Float64(1e-7),
    )


def covered_pixels(target: RenderTarget) raises -> Int:
    """Return how many pixels of `target` a fragment claimed the depth of."""
    var claimed = 0
    for y in range(target.height):
        for x in range(target.width):
            if target.depth_at(x, y) < 1.0e30:
                claimed += 1
    return claimed


def opaque_triangle(alpha: Float32, alpha_test: Float32) -> List[RasterVertex]:
    """Return one large triangle of a uniform alpha, tested at
    `alpha_test`."""
    var corners = List[RasterVertex]()
    var places: List[Tuple[Float32, Float32]] = [
        (Float32(0), Float32(0)),
        (Float32(60), Float32(0)),
        (Float32(0), Float32(60)),
    ]
    for place in places:
        corners.append(
            data_corner(
                place[0],
                place[1],
                BASIC,
                Vector3(0, 0, 1),
                0.5,
                alpha,
                OPAQUE,
                0,
                NO_TEXTURE,
                NO_TEXTURE,
                alpha_test,
            )
        )
    return corners^


def test_a_uniform_surface_is_not_cut_by_its_own_alpha_test() raises:
    # A triangle that is opaque at every corner, tested against one: every
    # covered pixel must survive, and the image and depth must be what the
    # same triangle gives with no test at all. A last-bit error in the
    # interpolated alpha used to punch holes in it.
    var tested = RenderTarget(64, 64, Color(0, 0, 0))
    rasterize_all(opaque_triangle(1.0, 1.0), tested, SHADE_TEXTURE)
    var plain = RenderTarget(64, 64, Color(0, 0, 0))
    rasterize_all(opaque_triangle(1.0, 0.0), plain, SHADE_TEXTURE)
    var claimed = covered_pixels(plain)
    assert_true(claimed > 1500, "the triangle covered almost nothing")
    assert_equal(covered_pixels(tested), claimed)
    for y in range(64):
        for x in range(64):
            assert_equal(tested.depth_at(x, y), plain.depth_at(x, y))
            assert_equal(tested.shown(x, y).r, plain.shown(x, y).r)
            assert_equal(tested.shown(x, y).a, plain.shown(x, y).a)
    # And a uniformly half-covered surface tested against exactly a half.
    var half = RenderTarget(64, 64, Color(0, 0, 0))
    rasterize_all(opaque_triangle(0.5, 0.5), half, SHADE_TEXTURE)
    var loose = RenderTarget(64, 64, Color(0, 0, 0))
    rasterize_all(opaque_triangle(0.5, 0.0), loose, SHADE_TEXTURE)
    assert_equal(covered_pixels(half), covered_pixels(loose))


# --- a toon triangle steps through a ramp -----------------------------------


def a_ramp(
    tones: List[UInt8],
    space: ColorSpace = LINEAR,
    alpha: Alpha = IGNORED,
) raises -> Texture:
    """Return a one-row gradient map whose red channel holds `tones`.

    Green and blue are deliberately not the tone: three.js reads `.r` and
    nothing else, and a gray texel could not tell them apart. A second row
    is added below, filled with a value nothing may read, so a shader that
    sampled anywhere but the top row would show it.
    """
    var pixels = List[UInt8]()
    for tone in tones:
        pixels.append(tone)
        pixels.append(255)
        pixels.append(0)
        pixels.append(255)
    for _ in tones:
        pixels.append(17)
        pixels.append(17)
        pixels.append(17)
        pixels.append(255)
    return Texture(len(tones), 2, pixels^, REPEAT, NEAREST, space, False, alpha)


def toon_corner(
    x: Float32,
    y: Float32,
    normal: Vector3,
    gradient_map: TextureId = NO_TEXTURE,
) -> RasterVertex:
    """Return a white toon corner facing `normal`."""
    return RasterVertex(
        x,
        y,
        0.5,
        1,
        FloatColor(1, 1, 1),
        0,
        0,
        NO_TEXTURE,
        OPAQUE,
        normal,
        Vector3(0, 0, 0),
        TOON,
        FloatColor(0.0, 0.0, 0.0),
        NO_TEXTURE,
        0,
        NO_TEXTURE,
        0,
        FloatColor(0.0, 0.0, 0.0),
        0,
        gradient_map,
    )


def toon_quad(
    left: Vector3, right: Vector3, gradient_map: TextureId = NO_TEXTURE
) -> List[RasterVertex]:
    """Return two triangles whose normal turns from `left` to `right`
    across an eight-pixel target, so the ramp is really swept."""
    var corners = List[RasterVertex]()
    corners.append(toon_corner(0, 0, left, gradient_map))
    corners.append(toon_corner(8, 0, right, gradient_map))
    corners.append(toon_corner(8, 8, right, gradient_map))
    corners.append(toon_corner(0, 0, left, gradient_map))
    corners.append(toon_corner(8, 8, right, gradient_map))
    corners.append(toon_corner(0, 8, left, gradient_map))
    return corners^


def lamp_straight_on() raises -> Lighting:
    """Return one white directional light down the z axis, and nothing
    else: no ambient, so every level in the image is the ramp's."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, 1.0))
    scene.update()
    return Lighting(scene)


def test_a_gradient_map_must_be_stored_as_data() raises:
    # Its red channel is a tone, not a color. The sRGB curve would turn a
    # byte of 128 into 0.216, and a coverage-weighted filter would weight
    # it by an alpha that means nothing.
    var tones: List[UInt8] = [0, 128, 255]
    check_gradient_map(a_ramp(tones))
    with assert_raises():
        check_gradient_map(a_ramp(tones, SRGB, IGNORED))
    with assert_raises():
        check_gradient_map(a_ramp(tones, LINEAR, COVERAGE))
    with assert_raises():
        check_gradient_map(a_ramp(tones, SRGB, COVERAGE))
    # And a ramp of no tones steps nowhere. A material that wants the
    # fallback names no map at all, which is a different thing.
    with assert_raises():
        check_gradient_map(Texture())


def test_a_ramp_is_the_top_rows_red_channel_and_nothing_else() raises:
    # three.js reads its gradient map at `vec2(coord, 0.0)` and takes `.r`.
    var tones: List[UInt8] = [0, 51, 204, 255]
    var read = gradient_ramp(a_ramp(tones))
    assert_equal(len(read), 4)
    assert_equal(read[0], Float32(0))
    assert_almost_equal(read[1], Float32(0.2), atol=Float64(1e-6))
    assert_almost_equal(read[2], Float32(0.8), atol=Float64(1e-6))
    assert_equal(read[3], Float32(1))
    # The second row holds 17 in every channel, and none of it arrived.
    for tone in read:
        assert_true(tone != Float32(17) / 255, "the ramp read the wrong row")


def test_a_toon_triangle_shows_flat_tones_where_a_lambert_one_fades() raises:
    # The normal turns from square-on to nearly edge-on across the quad. A
    # lambert surface fades smoothly over that; a toon surface shows two
    # flat tones with one edge between them.
    var lighting = lamp_straight_on()
    var stepped = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        toon_quad(Vector3(0, 0, 1), Vector3(0.95, 0, 0.31)),
        stepped,
        SHADE_TEXTURE,
        TextureStore(),
        lighting,
    )
    var levels = List[UInt8]()
    for x in range(8):
        levels.append(stepped.shown(x, 4).r)
    # Two values and no more, and the left one is the brighter.
    var bright = levels[0]
    var dark = levels[7]
    assert_true(bright > dark, "the ramp did not step down")
    for level in levels:
        assert_true(level == bright or level == dark, "a toon surface faded")
    # The same quad as a lambert one takes more than two values.
    var faded = RenderTarget(8, 8, Color(0, 0, 0))
    var smooth = List[RasterVertex]()
    for here in toon_quad(Vector3(0, 0, 1), Vector3(0.95, 0, 0.31)):
        smooth.append(as_kind(here, LAMBERT))
    rasterize_all(smooth, faded, SHADE_TEXTURE, TextureStore(), lighting)
    var seen = 0
    for x in range(8):
        var here = faded.shown(x, 4).r
        if here != bright and here != dark:
            seen += 1
    assert_true(seen > 0, "a lambert surface stepped like a toon one")


def as_kind(base: RasterVertex, kind: MaterialKind) -> RasterVertex:
    """Return `base` as a surface of another kind, carrying everything
    else it holds -- the ramp included, so a ramp on a kind that must not
    have one can be built and refused."""
    return RasterVertex(
        base.x,
        base.y,
        base.z,
        base.inv_w,
        base.color,
        base.u,
        base.v,
        base.texture,
        base.blend,
        base.normal,
        base.world,
        kind,
        base.emissive,
        base.emissive_map,
        base.view_depth,
        base.alpha_map,
        base.alpha_test,
        base.specular,
        base.shininess,
        base.gradient_map,
    )


def test_a_named_ramp_replaces_the_fallback() raises:
    # A ramp of three flat tones gives three flat bands, and the darkest
    # is darker than the fallback's low tone -- which is what says the
    # texture was read rather than ignored.
    var textures = TextureStore()
    var tones: List[UInt8] = [0, 128, 255]
    var ramp = textures.add(a_ramp(tones))
    var lighting = lamp_straight_on()
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        toon_quad(Vector3(0.6, 0, 0.8), Vector3(0.6, 0, -0.8), ramp),
        target,
        SHADE_TEXTURE,
        textures,
        lighting,
    )
    # The left edge is turned toward the lamp and reads the top of the
    # ramp; the right edge is turned away and reads the bottom, which is
    # black. The middle passes through the tone in between, which a normal
    # swept straight from +z to -z would skip.
    assert_equal(target.shown(0, 4).r, UInt8(255))
    assert_equal(target.shown(7, 4).r, UInt8(0))
    # Three tones and no more across the row.
    var seen = List[UInt8]()
    for x in range(8):
        var here = target.shown(x, 4).r
        var known = False
        for tone in seen:
            if tone == here:
                known = True
        if not known:
            seen.append(here)
    assert_equal(len(seen), 3)


def test_a_toon_triangles_ramp_is_checked_and_belongs_to_the_kind() raises:
    # The same three refusals the material makes, made again of a
    # hand-built triangle, so neither backend can be handed one.
    var textures = TextureStore()
    var tones: List[UInt8] = [0, 255]
    var ramp = textures.add(a_ramp(tones))
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    # A ramp on any other kind is refused.
    var wrong = toon_quad(Vector3(0, 0, 1), Vector3(0, 0, 1), ramp)
    for index in range(len(wrong)):
        wrong[index] = as_kind(wrong[index], LAMBERT)
    with assert_raises():
        check_triangle_state(wrong[0], wrong[1], wrong[2])
    # Corners that disagree about the ramp are refused, whichever of the
    # two behind the first is the odd one out.
    var second = toon_quad(Vector3(0, 0, 1), Vector3(0, 0, 1), ramp)
    second[1] = toon_corner(8, 0, Vector3(0, 0, 1))
    with assert_raises():
        check_triangle_state(second[0], second[1], second[2])
    var third = toon_quad(Vector3(0, 0, 1), Vector3(0, 0, 1), ramp)
    third[2] = toon_corner(8, 8, Vector3(0, 0, 1))
    with assert_raises():
        check_triangle_state(third[0], third[1], third[2])
    # An id nothing can hold is refused.
    var bad = toon_quad(Vector3(0, 0, 1), Vector3(0, 0, 1), TextureId(-9))
    with assert_raises():
        check_triangle_state(bad[0], bad[1], bad[2])
    with assert_raises():
        rasterize_all(bad, target, SHADE_TEXTURE, textures)
    # A ramp that is not stored as data is refused before the first
    # fragment, on every worker count.
    var colored = TextureStore()
    var wrong_space = colored.add(a_ramp(tones, SRGB, IGNORED))
    var stepped = toon_quad(Vector3(0, 0, 1), Vector3(0, 0, 1), wrong_space)
    for workers in [1, 4]:
        with assert_raises():
            rasterize_all(
                stepped, target, SHADE_TEXTURE, colored, workers=workers
            )
    # The uv debug view shades nothing and reads no ramp, so it draws.
    rasterize_all(stepped, target, SHADE_UV, colored)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
