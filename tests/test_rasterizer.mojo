# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.rasterizer`."""

from core.layers import Layers
from materials.material import (
    BASIC,
    DEPTH,
    DISTANCE,
    LAMBERT,
    MATCAP,
    NORMALS,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
    TOON,
    Blending,
    MaterialKind,
    depth_material,
    normal_material,
)
from math.vector2 import Vector2
from std.math import inf, isfinite, pi

# The intensity that lights a white surface square on to full white: three.js
# divides every lit term by pi, and so does `Lighting`. See tests/test_light.
comptime FULL = Float32(pi)
from render.framebuffer import Color, FloatColor, Framebuffer
from materials.material import BLEND, NO_TEXTURE, OPAQUE
from render.texture import (
    CLAMP,
    COVERAGE,
    IGNORED,
    NEAREST,
    REPEAT,
    UV_CHANNEL_1,
    Alpha,
    Texture,
    UvChannel,
    UvPlacement,
    checkerboard,
    float_texture,
)
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from render.cube_texture import CubeTexture
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
    CubeTextureStore,
)
from materials.material import (
    ADD_OPERATION,
    MIX_OPERATION,
    MULTIPLY_OPERATION,
    Combine,
)
from lights.light import ambient_light, directional_light
from lights.lighting import (
    ROUGHNESS_FLOOR,
    Lighting,
    floored_roughness,
    specular_occlusion,
)
from lights.shadow import ShadowMap
from core.fog import LINEAR_FOG, FogKind, FogView, exp2_fog, linear_fog
from render.tonemap import REINHARD_TONE_MAPPING, tone_map
from std.math import atan2, nan, sqrt
from units.si import Angle, DEGREE, InverseLength, Length, METER, PER_METER
from core.object3d import NodeId, Object3D
from core.scene import Scene
from math.vector3 import Vector3
from render.target import RenderTarget
from render.packing import (
    BASIC_DEPTH_PACKING,
    RGBA_DEPTH_PACKING,
    RGB_DEPTH_PACKING,
    RG_DEPTH_PACKING,
    DepthPacking,
)
from render.srgb import LINEAR, SRGB, ColorSpace
from render.rasterizer import (
    DRAW_SEGMENTS,
    DRAW_TRIANGLES,
    Draw,
    DrawKind,
    LayerFactors,
    tangent_frame,
    check_draws,
    rasterize_frame,
    MATCAP_CEILING,
    MATCAP_FLOOR,
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    RasterVertex,
    ShadeMode,
    Triangle,
    bumped_normal,
    check_alpha_map,
    check_data_map,
    check_gradient_map,
    check_light_map,
    check_output_kinds,
    check_triangle_state,
    data_color,
    mapped_normal,
    gradient_ramp,
    interpolate_alpha,
    matcap_fallback,
    matcap_uv,
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


def test_a_transparent_surface_claims_the_depth() raises:
    # Two panes drawn furthest first both show, and each claims its depth,
    # as three.js's transparent material with `depthWrite` does.
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
    # And the depth buffer holds the near pane, so a surface behind both
    # would not draw.
    assert_almost_equal(fb.depth_at(3, 3), Float32(0.2), atol=Float64(1e-5))


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
        checkerboard(
            32,
            16,
            Color(255, 0, 0),
            Color(0, 0, 255),
            REPEAT,
            NEAREST,
            mipmapped=False,
        )
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


def test_a_bad_map_is_refused_on_every_worker_count() raises:
    # A band skips a triangle its rows never reach before `rasterize_shaded`
    # can open its maps, so an emissive map that reads alpha as coverage on
    # a triangle above the image was refused on one worker and drawn around
    # on four. `rasterize_all` asks about every triangle's maps before any
    # band starts, exactly as it asks about their state.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(8, 2, Color(255, 255, 255), Color(0, 0, 0))
    )
    var above = List[RasterVertex]()
    above.append(glowing_corner(0, -20, 0, 1, FloatColor(1, 1, 1), board))
    above.append(glowing_corner(8, -20, 1, 1, FloatColor(1, 1, 1), board))
    above.append(glowing_corner(8, -12, 1, 0, FloatColor(1, 1, 1), board))
    for workers in [1, 4]:
        var target = RenderTarget(8, 8, Color(0, 0, 0))
        with assert_raises():
            rasterize_all(
                above, target, SHADE_TEXTURE, textures, workers=workers
            )
        # Under a mode that never opens the map, the same triangle is fine.
        rasterize_all(above, target, SHADE_LIT, textures, workers=workers)


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
    scene.add_light(directional_light(Color(255, 255, 255), NodeId(0), FULL))
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


def test_a_frame_draws_its_runs_in_the_order_given() raises:
    # A blended triangle over an opaque segment, and the same two with the
    # segment drawn last: the order is the caller's, and it shows.
    var textures = TextureStore()
    var pane = List[RasterVertex]()
    for point in covering(0.2):
        pane.append(stated_corner(point, NO_TEXTURE, BLEND))
    for index in range(3):
        pane[index].color = FloatColor(1, 0, 0, 0.5)
    var stroke: List[RasterVertex] = [
        stated_corner(Vector3(0, 4.5, 0), NO_TEXTURE, OPAQUE),
        stated_corner(Vector3(8, 4.5, 0), NO_TEXTURE, OPAQUE),
    ]
    stroke[0].kind = BASIC
    stroke[1].kind = BASIC
    stroke[0].color = FloatColor(0, 0, 1)
    stroke[1].color = FloatColor(0, 0, 1)
    stroke[0].z = 0.6
    stroke[1].z = 0.6
    var behind = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_frame(
        pane,
        stroke,
        [Draw(DRAW_SEGMENTS, 0, 1), Draw(DRAW_TRIANGLES, 0, 1)],
        behind,
        SHADE_LIT,
        textures,
    )
    # The stroke first, then half red over it: half red and half blue.
    var seen = behind.shown(4, 4)
    assert_equal(seen.r, UInt8(188))
    assert_equal(seen.b, UInt8(188))
    var over = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_frame(
        pane,
        stroke,
        [Draw(DRAW_TRIANGLES, 0, 1), Draw(DRAW_SEGMENTS, 0, 1)],
        over,
        SHADE_LIT,
        textures,
    )
    # The pane claims its depth as it blends, so the stroke behind it,
    # drawn second, fails the test and never shows: the order decides.
    var replaced = over.shown(4, 4)
    assert_equal(replaced.r, UInt8(188))
    assert_equal(replaced.b, UInt8(0))
    # And an empty order draws nothing at all, nor does a run of nothing.
    var untouched = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_frame(pane, stroke, List[Draw](), untouched)
    rasterize_frame(
        pane,
        stroke,
        [Draw(DRAW_TRIANGLES, 1, 0), Draw(DRAW_SEGMENTS, 1, 0)],
        untouched,
    )
    assert_equal(untouched.shown(4, 4).r, UInt8(0))
    assert_equal(untouched.depth_at(4, 4), inf[DType.float32]())


def test_a_frame_draws_the_same_on_one_worker_and_on_four() raises:
    var textures = TextureStore()
    var pane = List[RasterVertex]()
    for point in covering(0.2):
        pane.append(stated_corner(point, NO_TEXTURE, BLEND))
    for index in range(3):
        pane[index].color = FloatColor(1, 0, 0, 0.5)
    var strokes = List[RasterVertex]()
    var rows: List[Float32] = [1.5, 4.5, 6.5]
    var ends: List[Float32] = [0, 8]
    for row in rows:
        for x in ends:
            var end = stated_corner(Vector3(x, row, 0), NO_TEXTURE, OPAQUE)
            end.kind = BASIC
            end.color = FloatColor(0, 0, 1)
            end.z = 0.6
            strokes.append(end)
    var order: List[Draw] = [
        Draw(DRAW_SEGMENTS, 0, 2),
        Draw(DRAW_TRIANGLES, 0, 1),
        Draw(DRAW_SEGMENTS, 2, 1),
        Draw(DRAW_SEGMENTS, 0, 0),
    ]
    var alone = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_frame(pane, strokes, order, alone, SHADE_LIT, textures)
    var crowd = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_frame(pane, strokes, order, crowd, SHADE_LIT, textures, workers=4)
    for y in range(8):
        for x in range(8):
            var one = alone.shown(x, y)
            var four = crowd.shown(x, y)
            assert_equal(one.r, four.r)
            assert_equal(one.g, four.g)
            assert_equal(one.b, four.b)
            assert_equal(alone.depth_at(x, y), crowd.depth_at(x, y))
    # The last stroke was drawn after the pane and behind it, so it is
    # hidden where the pane claimed the depth; the first two show under it.
    assert_equal(alone.shown(4, 6).b, UInt8(0))
    assert_equal(alone.shown(4, 1).b, UInt8(188))


def test_a_frame_refuses_a_draw_it_does_not_hold() raises:
    # Every operand of the range check has to decide the outcome alone, and
    # a kind that is none of the two is refused before the range is read.
    var textures = TextureStore()
    var pane = List[RasterVertex]()
    for point in covering(0.2):
        pane.append(stated_corner(point, NO_TEXTURE, OPAQUE))
    var stroke: List[RasterVertex] = [
        stated_corner(Vector3(0, 4.5, 0), NO_TEXTURE, OPAQUE),
        stated_corner(Vector3(8, 4.5, 0), NO_TEXTURE, OPAQUE),
    ]
    stroke[0].kind = BASIC
    stroke[1].kind = BASIC
    check_draws([Draw(DRAW_TRIANGLES, 0, 1), Draw(DRAW_SEGMENTS, 0, 1)], 1, 1)
    check_draws([Draw(DRAW_TRIANGLES, 1, 0), Draw(DRAW_SEGMENTS, 1, 0)], 1, 1)
    with assert_raises():
        check_draws([Draw(DrawKind(7), 0, 1)], 1, 1)
    with assert_raises():
        check_draws([Draw(DRAW_TRIANGLES, -1, 1)], 1, 1)
    with assert_raises():
        check_draws([Draw(DRAW_TRIANGLES, 0, -1)], 1, 1)
    with assert_raises():
        check_draws([Draw(DRAW_TRIANGLES, 0, 2)], 1, 1)
    with assert_raises():
        check_draws([Draw(DRAW_SEGMENTS, 1, 1)], 1, 1)
    for workers in [1, 4]:
        var target = RenderTarget(8, 8, Color(0, 0, 0))
        with assert_raises():
            rasterize_frame(
                pane,
                stroke,
                [Draw(DRAW_SEGMENTS, 0, 2)],
                target,
                SHADE_LIT,
                textures,
                workers=workers,
            )
        with assert_raises():
            rasterize_frame(
                pane, stroke, [Draw(DRAW_TRIANGLES, 0, 1)], target, workers=0
            )
        var odd = List[RasterVertex]()
        odd.append(stroke[0])
        with assert_raises():
            rasterize_frame(pane, odd, List[Draw](), target)


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


def packed_quad(
    kind: MaterialKind,
    packing: DepthPacking,
    z: Float32 = 0.0,
    reference: Vector3 = Vector3(0, 0, 0),
    near: Float32 = 1,
    far: Float32 = 1000,
) -> List[RasterVertex]:
    """Return `data_quad` with a depth packing and a distance range, every
    corner three meters up and four back from the origin."""
    var corners = data_quad(kind, z=z)
    for index in range(len(corners)):
        corners[index].depth_packing = packing
        corners[index].world = Vector3(0, 3, 4)
        corners[index].reference = reference
        corners[index].near_distance = near
        corners[index].far_distance = far
    return corners^


def test_a_depth_material_writes_its_depth_by_its_packing() raises:
    # NDC zero is window depth one half: red 128 and nothing below it.
    var rgba = data_pixel(packed_quad(DEPTH, RGBA_DEPTH_PACKING))
    # The alpha is data and is zero, and the color survives it: a data
    # pixel is stored straight.
    assert_same_color(rgba.shown(4, 4), Color(128, 0, 0, 0))
    assert_same_color(rgba.resolve().get_pixel(4, 4), Color(128, 0, 0, 0))
    var rgb = data_pixel(packed_quad(DEPTH, RGB_DEPTH_PACKING))
    assert_same_color(rgb.shown(4, 4), Color(128, 0, 0, 255))
    var rg = data_pixel(packed_quad(DEPTH, RG_DEPTH_PACKING))
    assert_same_color(rg.shown(4, 4), Color(128, 0, 0, 255))
    # NDC -0.4 is window depth 0.3: three.js's bytes 76, 204 and 205.
    var deeper = data_pixel(packed_quad(DEPTH, RGBA_DEPTH_PACKING, -0.4))
    assert_same_color(deeper.shown(4, 4), Color(76, 204, 205, 0))
    assert_true(deeper.is_data(4, 4))
    # Read back as premultiplied light, a data pixel is scaled like any.
    assert_equal(deeper.color_at(4, 4).a, Float32(0))
    assert_equal(deeper.color_at(4, 4).r, Float32(0))


def test_a_distance_material_writes_its_distance_packed() raises:
    # Five meters from the origin, half way from zero to ten: red 128.
    var half = data_pixel(
        packed_quad(DISTANCE, BASIC_DEPTH_PACKING, near=0, far=10)
    )
    assert_same_color(half.shown(4, 4), Color(128, 0, 0, 0))
    # From a reference of its own: three meters away, from one to five.
    var nearer = data_pixel(
        packed_quad(DISTANCE, BASIC_DEPTH_PACKING, 0.9, Vector3(0, 3, 1), 1, 5)
    )
    assert_same_color(nearer.shown(4, 4), Color(128, 0, 0, 0))
    # The depth is not read: the same surface at another depth.
    var moved = data_pixel(
        packed_quad(DISTANCE, BASIC_DEPTH_PACKING, -0.9, near=0, far=10)
    )
    assert_same_color(moved.shown(4, 4), Color(128, 0, 0, 0))
    # Nor in the uv debug view, which shows coordinates.
    var uv = data_pixel(
        packed_quad(DISTANCE, BASIC_DEPTH_PACKING, near=0, far=10),
        mode=SHADE_UV,
    )
    assert_true(uv.shown(4, 4).a == 255)


def test_a_triangle_refuses_a_packing_or_a_range_it_cannot_use() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    # A packing on a kind that shows no depth.
    var normal = packed_quad(NORMALS, RGB_DEPTH_PACKING)
    with assert_raises(contains="Only a depth triangle"):
        check_triangle_state(normal[0], normal[1], normal[2])
    # A packing that is none of the four.
    var odd = packed_quad(DEPTH, DepthPacking(9))
    with assert_raises(contains="none of the four"):
        check_triangle_state(odd[0], odd[1], odd[2])
    # Corners that disagree about the packing, second and third.
    var split = packed_quad(DEPTH, RGB_DEPTH_PACKING)
    split[1].depth_packing = RG_DEPTH_PACKING
    with assert_raises(contains="depth packing"):
        check_triangle_state(split[0], split[1], split[2])
    split = packed_quad(DEPTH, RGB_DEPTH_PACKING)
    split[2].depth_packing = RG_DEPTH_PACKING
    with assert_raises(contains="depth packing"):
        check_triangle_state(split[0], split[1], split[2])
    # A range the distance cannot be measured by.
    var flat = packed_quad(DISTANCE, BASIC_DEPTH_PACKING, near=5, far=5)
    with assert_raises(contains="far distance"):
        rasterize_all(flat, target)
    # Corners that disagree about the range, in each of its five numbers.
    for field in range(5):
        var parted = packed_quad(DISTANCE, BASIC_DEPTH_PACKING, near=0, far=9)
        var other = 1 + field % 2
        if field == 0:
            parted[other].reference.x = 1
        elif field == 1:
            parted[other].reference.y = 1
        elif field == 2:
            parted[other].reference.z = 1
        elif field == 3:
            parted[other].near_distance = 1
        else:
            parted[other].far_distance = 8
        with assert_raises(contains="distance range"):
            check_triangle_state(parted[0], parted[1], parted[2])
    # The range is not read on any other kind.
    var ignored = packed_quad(DEPTH, BASIC_DEPTH_PACKING, near=5, far=5)
    check_triangle_state(ignored[0], ignored[1], ignored[2])


def test_a_triangle_whose_material_turns_the_fog_off_is_not_fogged() raises:
    # three.js's `fog = false`: the same white surface two meters into a
    # gray fog, veiled with the switch on and clear with it off.
    var fog = gray_fog()
    var veiled = fogged_pixel(placed_quad(2, BASIC), fog)
    assert_true(veiled.r < 255, "the fog reached nothing")
    var corners = placed_quad(2, BASIC)
    for index in range(len(corners)):
        corners[index].fog = False
    assert_same_color(fogged_pixel(corners, fog), Color(255, 255, 255))
    # Corners that disagree about the switch, second and third.
    var split = placed_quad(2, BASIC)
    split[1].fog = False
    with assert_raises(contains="fog"):
        check_triangle_state(split[0], split[1], split[2])
    split = placed_quad(2, BASIC)
    split[2].fog = False
    with assert_raises(contains="fog"):
        check_triangle_state(split[0], split[1], split[2])


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
    # `MaterialKind(11)` constructs, because a struct's fields are open, and
    # neither backend has a fragment path for it. Agreement is not enough.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var corners = data_quad(MaterialKind(11))
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
    assert_same_color(shown.shown(4, 4), Color(255, 255, 255, 255))
    # A green of 255 leaves the surface alone, and one of zero empties it:
    # an opaque fragment is written with an alpha of one whatever the map
    # said, as three.js writes it, so the alpha test is what shows the
    # thinning.
    var whole = textures.add(a_mask(255))
    var solid = data_pixel(
        data_quad(BASIC, alpha_map=whole, alpha_test=0.5), textures=textures
    )
    assert_same_color(solid.shown(4, 4), Color(255, 255, 255, 255))
    var empty = textures.add(a_mask(0))
    var gone = data_pixel(
        data_quad(BASIC, alpha_map=empty, alpha_test=0.5), textures=textures
    )
    assert_same_color(gone.shown(4, 4), Color(0, 0, 0))
    # And a blended fragment carries the thinned alpha into the mix.
    var seen = data_pixel(
        data_quad(BASIC, alpha_map=textures.add(a_mask(128)), blend=BLEND),
        textures=textures,
    )
    assert_equal(seen.shown(4, 4).r, FloatColor(0.5, 0.5, 0.5).encode().r)


def test_an_alpha_map_multiplies_the_opacity_it_is_given() raises:
    # The map thins whatever alpha reached it, as three.js multiplies into
    # `diffuseColor.a`: half an opacity through a half map is a quarter.
    var textures = TextureStore()
    var mask = textures.add(a_mask(128))
    var shown = data_pixel(
        data_quad(BASIC, alpha=0.5, alpha_map=mask, blend=BLEND),
        textures=textures,
    )
    # A quarter of white over black, in linear light.
    assert_equal(shown.shown(4, 4).r, FloatColor(0.25, 0.25, 0.25).encode().r)
    # The alpha test reads the same quarter: just above it discards, just
    # below it keeps.
    var cut = data_pixel(
        data_quad(BASIC, alpha=0.5, alpha_map=mask, alpha_test=0.26),
        textures=textures,
    )
    assert_same_color(cut.shown(4, 4), Color(0, 0, 0))
    var kept = data_pixel(
        data_quad(BASIC, alpha=0.5, alpha_map=mask, alpha_test=0.24),
        textures=textures,
    )
    assert_equal(kept.shown(4, 4).r, UInt8(255))


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
    # Written opaque, with an alpha of one, as three.js writes it.
    assert_same_color(kept.shown(4, 4), Color(255, 255, 255, 255))
    # A test of zero is no test at all, as in three.js.
    var every = data_pixel(data_quad(BASIC, alpha=0.0, alpha_test=0.0))
    assert_equal(every.shown(4, 4).r, UInt8(255))
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
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
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
    nothing else, and a gray texel could not tell them apart.
    """
    var pixels = List[UInt8]()
    for tone in tones:
        pixels.append(tone)
        pixels.append(255)
        pixels.append(0)
        pixels.append(255)
    return Texture(len(tones), 1, pixels^, REPEAT, NEAREST, space, False, alpha)


def a_tall_ramp(tones: List[UInt8]) raises -> Texture:
    """Return a two-row gradient map, which is refused. The rows differ, so
    a reader that picked one silently would show which."""
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
    return Texture(
        len(tones), 2, pixels^, REPEAT, NEAREST, LINEAR, False, IGNORED
    )


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
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
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
    # A float ramp is linear and can ignore its alpha, and is still refused:
    # both backends read a ramp one byte a tone.
    with assert_raises(contains="must hold bytes"):
        check_gradient_map(
            float_texture(
                2, 1, [0, 0, 0, 1, 1, 1, 1, 1], filter=NEAREST, alpha=IGNORED
            )
        )


def test_a_ramp_is_one_row_of_the_red_channel() raises:
    # three.js reads its gradient map at `vec2(coord, 0.0)` and takes `.r`.
    var tones: List[UInt8] = [0, 51, 204, 255]
    var read = gradient_ramp(a_ramp(tones))
    assert_equal(len(read), 4)
    assert_equal(read[0], Float32(0))
    assert_almost_equal(read[1], Float32(0.2), atol=Float64(1e-6))
    assert_almost_equal(read[2], Float32(0.8), atol=Float64(1e-6))
    assert_equal(read[3], Float32(1))


def test_a_ramp_taller_than_one_row_is_refused() raises:
    # Under this project's texture convention a `v` of zero is the *bottom*
    # row: every sampler flips with `1 - v`, so three.js's `vec2(coord, 0)`
    # and "the first stored row" are not the same row at all. A ramp is
    # read as a flat table rather than sampled, so a taller image would
    # leave two defensible answers. One row has only one.
    var tones: List[UInt8] = [0, 255]
    check_gradient_map(a_ramp(tones))
    with assert_raises():
        check_gradient_map(a_tall_ramp(tones))
    # And the refusal reaches a draw, on every worker count, before the
    # first fragment.
    var textures = TextureStore()
    var tall = textures.add(a_tall_ramp(tones))
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var corners = toon_quad(TOWARD_Z, TOWARD_Z, tall)
    for workers in [1, 4]:
        with assert_raises():
            rasterize_all(
                corners, target, SHADE_TEXTURE, textures, workers=workers
            )


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
        base.matcap,
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


# --- a matcap is looked up by which way a surface is turned -----------------


comptime UP_Y = Vector3(0, 1, 0)
comptime TOWARD_Z = Vector3(0, 0, 1)


def test_a_surface_square_on_reads_the_middle_of_a_matcap() raises:
    # The frame is the camera's own: across its right and up its own up.
    # A normal pointing straight back at the camera leans along neither.
    var middle = matcap_uv(TOWARD_Z, UP_Y, TOWARD_Z)
    assert_equal(middle.x, Float32(0.5))
    assert_equal(middle.y, Float32(0.5))


def test_a_leaning_surface_reads_off_the_middle_by_three_js_scale() raises:
    # three.js's 0.495, which keeps the edge of the image out of the
    # lookup and so out of any wrapping.
    var right = matcap_uv(TOWARD_Z, UP_Y, Vector3(1, 0, 0))
    assert_almost_equal(right.x, Float32(0.995), atol=Float64(1e-6))
    assert_almost_equal(right.y, Float32(0.5), atol=Float64(1e-6))
    var left = matcap_uv(TOWARD_Z, UP_Y, Vector3(-1, 0, 0))
    assert_almost_equal(left.x, Float32(0.005), atol=Float64(1e-6))
    var above = matcap_uv(TOWARD_Z, UP_Y, UP_Y)
    assert_almost_equal(above.x, Float32(0.5), atol=Float64(1e-6))
    assert_almost_equal(above.y, Float32(0.995), atol=Float64(1e-6))
    var below = matcap_uv(TOWARD_Z, UP_Y, Vector3(0, -1, 0))
    assert_almost_equal(below.y, Float32(0.005), atol=Float64(1e-6))


def test_a_matcap_turns_with_the_camera() raises:
    # Roll the camera a quarter turn about the direction it looks, and a
    # surface leaning to the right now reads as leaning up. That is what
    # says the frame is the camera's and not the world's.
    var rolled = matcap_uv(TOWARD_Z, Vector3(-1, 0, 0), Vector3(1, 0, 0))
    assert_almost_equal(rolled.x, Float32(0.5), atol=Float64(1e-6))
    assert_almost_equal(rolled.y, Float32(0.005), atol=Float64(1e-6))


def test_a_collapsed_frame_reads_the_middle() raises:
    # Up parallel to the way the camera is seen from leaves no frame to
    # measure in. A camera cannot see a surface from there -- it would be
    # looking straight along its own up axis -- but a hand-built call can
    # ask, and it must not divide by zero.
    var along = matcap_uv(UP_Y, UP_Y, Vector3(1, 0, 0))
    assert_equal(along.x, Float32(0.5))
    assert_equal(along.y, Float32(0.5))
    var none = matcap_uv(Vector3(0, 0, 0), UP_Y, Vector3(1, 0, 0))
    assert_equal(none.x, Float32(0.5))
    var no_up = matcap_uv(TOWARD_Z, Vector3(0, 0, 0), Vector3(1, 0, 0))
    assert_equal(no_up.x, Float32(0.5))


def test_the_fallback_matcap_is_a_gray_gradient() raises:
    # three.js's `mix(0.2, 0.8, uv.y)`: dark at the bottom, pale at the
    # top, which reads as a sphere lit from above.
    assert_equal(matcap_fallback(0.0), MATCAP_FLOOR)
    assert_equal(matcap_fallback(1.0), MATCAP_CEILING)
    assert_almost_equal(matcap_fallback(0.5), Float32(0.5), atol=Float64(1e-6))


def matcap_corner(
    x: Float32, y: Float32, normal: Vector3, matcap: TextureId = NO_TEXTURE
) -> RasterVertex:
    """Return a white matcap corner facing `normal`, at the origin."""
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
        MATCAP,
        FloatColor(0.0, 0.0, 0.0),
        NO_TEXTURE,
        0,
        NO_TEXTURE,
        0,
        FloatColor(0.0, 0.0, 0.0),
        0,
        NO_TEXTURE,
        matcap,
    )


def matcap_quad(
    left: Vector3, right: Vector3, matcap: TextureId = NO_TEXTURE
) -> List[RasterVertex]:
    """Return two triangles whose normal turns from `left` to `right`
    across an eight-pixel target."""
    var corners = List[RasterVertex]()
    corners.append(matcap_corner(0, 0, left, matcap))
    corners.append(matcap_corner(8, 0, right, matcap))
    corners.append(matcap_corner(8, 8, right, matcap))
    corners.append(matcap_corner(0, 0, left, matcap))
    corners.append(matcap_corner(8, 8, right, matcap))
    corners.append(matcap_corner(0, 8, left, matcap))
    return corners^


def watching_from(z: Float32) raises -> Lighting:
    """Return lighting with the camera up the z axis and no lights at all,
    so nothing but the matcap decides a pixel."""
    return Lighting(Scene(), Layers.all(), Vector3(0, 0, z))


def half_and_half(left: Color, right: Color) raises -> Texture:
    """Return a two-texel image: `left` on the left, `right` on the
    right."""
    var pixels = List[UInt8]()
    for tint in [left, right]:
        pixels.append(tint.r)
        pixels.append(tint.g)
        pixels.append(tint.b)
        pixels.append(255)
    return Texture(2, 1, pixels^, REPEAT, NEAREST, SRGB, False, IGNORED)


def test_a_matcap_triangle_shows_the_image_and_not_the_lights() raises:
    # A surface leaning left reads the image's left half and one leaning
    # right reads its right half, whatever the scene's lights say -- and
    # here the scene has none at all.
    var textures = TextureStore()
    var ball = textures.add(half_and_half(Color(255, 0, 0), Color(0, 0, 255)))
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        matcap_quad(Vector3(-1, 0, 0), Vector3(1, 0, 0), ball),
        target,
        SHADE_TEXTURE,
        textures,
        watching_from(4),
    )
    assert_equal(target.shown(0, 4).r, UInt8(255))
    assert_equal(target.shown(0, 4).b, UInt8(0))
    assert_equal(target.shown(7, 4).r, UInt8(0))
    assert_equal(target.shown(7, 4).b, UInt8(255))


def test_a_matcap_triangle_without_an_image_takes_the_gradient() raises:
    # Dark at the bottom of the lookup and pale at the top, which for a
    # quad whose normal sweeps down to up is dark on one side.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        matcap_quad(Vector3(0, -1, 0), Vector3(0, 1, 0)),
        target,
        SHADE_TEXTURE,
        TextureStore(),
        watching_from(4),
    )
    var low = target.shown(0, 4).r
    var high = target.shown(7, 4).r
    assert_true(high > low, "the gradient did not rise across the quad")
    # The ends are the gradient's own two values, encoded.
    assert_equal(low, FloatColor(MATCAP_FLOOR, 0, 0, 1).encode().r)
    assert_equal(high, FloatColor(MATCAP_CEILING, 0, 0, 1).encode().r)


def test_a_matcap_triangles_image_is_checked_and_belongs_to_the_kind() raises:
    var textures = TextureStore()
    var ball = textures.add(half_and_half(Color(255, 0, 0), Color(0, 0, 255)))
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    # An image on any other kind is refused.
    var wrong = matcap_quad(TOWARD_Z, TOWARD_Z, ball)
    for index in range(len(wrong)):
        wrong[index] = as_kind(wrong[index], LAMBERT)
    with assert_raises():
        check_triangle_state(wrong[0], wrong[1], wrong[2])
    # Corners that disagree about it are refused, either of the two.
    var second = matcap_quad(TOWARD_Z, TOWARD_Z, ball)
    second[1] = matcap_corner(8, 0, TOWARD_Z)
    with assert_raises():
        check_triangle_state(second[0], second[1], second[2])
    var third = matcap_quad(TOWARD_Z, TOWARD_Z, ball)
    third[2] = matcap_corner(8, 8, TOWARD_Z)
    with assert_raises():
        check_triangle_state(third[0], third[1], third[2])
    # An id nothing can hold is refused.
    var bad = matcap_quad(TOWARD_Z, TOWARD_Z, TextureId(-9))
    with assert_raises():
        check_triangle_state(bad[0], bad[1], bad[2])
    with assert_raises():
        rasterize_all(bad, target, SHADE_TEXTURE, textures)


def test_a_matcap_must_ignore_its_own_alpha() raises:
    # Filtering would weight its channels by an alpha that means nothing:
    # three.js reads `.rgb` and no more. The rule the emissive map follows.
    var textures = TextureStore()
    var pixels = List[UInt8]()
    for _ in range(2):
        pixels.append(255)
        pixels.append(255)
        pixels.append(255)
        pixels.append(128)
    var weighted = textures.add(
        Texture(2, 1, pixels^, REPEAT, NEAREST, SRGB, False, COVERAGE)
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var corners = matcap_quad(TOWARD_Z, TOWARD_Z, weighted)
    for workers in [1, 4]:
        with assert_raises():
            rasterize_all(
                corners, target, SHADE_TEXTURE, textures, workers=workers
            )
    # The uv debug view looks nothing up, so it draws.
    rasterize_all(corners, target, SHADE_UV, textures)


def test_a_faint_blend_cannot_decide_a_data_pixels_curve() raises:
    # The discontinuity this refusal exists for. A black surface at an
    # alpha of 1e-8 leaves the stored color bit for bit identical, because
    # `1 - alpha` rounds to one in Float32. It still turns the tone mapping
    # on for the normal underneath, which moves (128, 128, 255) to
    # (117, 117, 188). A fragment too faint to change one channel must not
    # decide the whole pixel's answer, and no per-pixel rule can make that
    # continuous, so the frame is refused instead.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.write(0, 0, data_color(0.5, 0.5, 1.0, 1.0), True)
    var before = target.shown(0, 0, REINHARD_TONE_MAPPING)
    assert_equal(before.r, UInt8(128))
    assert_equal(before.b, UInt8(255))
    target.blend(0, 0, FloatColor(0.0, 0.0, 0.0, 0.00000001))
    # The color really did not move, and the flag really did.
    assert_equal(target.color_at(0, 0).r, FloatColor(srgb=Color(128, 0, 0)).r)
    assert_false(target.is_data(0, 0))
    var after = target.shown(0, 0, REINHARD_TONE_MAPPING)
    assert_equal(after.r, UInt8(117))
    assert_equal(after.b, UInt8(188))
    # So a frame that could reach it is refused before anything is drawn.
    var mixed = data_quad(NORMALS)
    for here in toon_quad(TOWARD_Z, TOWARD_Z):
        mixed.append(as_kind(here, BASIC))
    mixed[6] = blended(mixed[6])
    mixed[7] = blended(mixed[7])
    mixed[8] = blended(mixed[8])
    with assert_raises():
        check_output_kinds(mixed, True)
    # With no curve there is nothing to decide, and the same frame draws.
    check_output_kinds(mixed, False)
    # Data alone, or blended light alone, is fine under a curve.
    check_output_kinds(data_quad(NORMALS), True)
    check_output_kinds(data_quad(BASIC, blend=BLEND), True)
    # An empty frame holds neither.
    check_output_kinds(List[RasterVertex](), True)
    # A blended segment mixes light into whatever it crosses, a data pixel
    # included, so it counts as a blended triangle does. An opaque one
    # replaces the pixel and decides nothing for the pixel behind it.
    var stroke: List[RasterVertex] = [
        stated_corner(Vector3(0, 0, 0), NO_TEXTURE, BLEND),
        stated_corner(Vector3(8, 8, 0), NO_TEXTURE, BLEND),
    ]
    with assert_raises():
        check_output_kinds(data_quad(NORMALS), True, stroke)
    check_output_kinds(data_quad(NORMALS), False, stroke)
    check_output_kinds(List[RasterVertex](), True, stroke)
    var solid_stroke: List[RasterVertex] = [
        stated_corner(Vector3(0, 0, 0), NO_TEXTURE, OPAQUE),
        stated_corner(Vector3(8, 8, 0), NO_TEXTURE, OPAQUE),
    ]
    check_output_kinds(data_quad(NORMALS), True, solid_stroke)


def blended(base: RasterVertex) -> RasterVertex:
    """Return `base` as a source-over fragment."""
    return RasterVertex(
        base.x,
        base.y,
        base.z,
        base.inv_w,
        base.color,
        base.u,
        base.v,
        base.texture,
        BLEND,
        base.normal,
        base.world,
        base.kind,
    )


def four_corners(
    top_left: Color, top_right: Color, low_left: Color, low_right: Color
) raises -> Texture:
    """Return a two-by-two matcap, a different color in every quadrant.

    A two-texel image only pins left against right. Four pin the other axis
    too, which is what catches a flipped `v` or a swapped frame vector.
    Stored top row first, as `Texture` stores every image.
    """
    var pixels = List[UInt8]()
    for tint in [top_left, top_right, low_left, low_right]:
        pixels.append(tint.r)
        pixels.append(tint.g)
        pixels.append(tint.b)
        pixels.append(255)
    return Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB, False, IGNORED)


def leaning(x: Float32, y: Float32) -> Vector3:
    """Return a unit normal leaning that way in the camera's frame."""
    var facing = Vector3(x, y, 0)
    facing.normalize()
    return facing^


def test_a_matcap_is_looked_up_the_right_way_up_and_round() raises:
    # The camera sits up the z axis with world up, so `across` is +x and
    # `upright` is +y. A normal leaning up and left must read the image's
    # top-left texel, and so on round the four. This pins the sign of both
    # frame vectors and the `v` flip at once; a two-texel image could not.
    var textures = TextureStore()
    var ball = textures.add(
        four_corners(
            Color(255, 0, 0),  # top left
            Color(0, 255, 0),  # top right
            Color(0, 0, 255),  # low left
            Color(255, 255, 0),  # low right
        )
    )
    var wanted: List[Tuple[Float32, Float32, UInt8, UInt8]] = [
        (Float32(-1), Float32(1), UInt8(255), UInt8(0)),
        (Float32(1), Float32(1), UInt8(0), UInt8(255)),
        (Float32(-1), Float32(-1), UInt8(0), UInt8(0)),
        (Float32(1), Float32(-1), UInt8(255), UInt8(255)),
    ]
    for want in wanted:
        var facing = leaning(want[0], want[1])
        var target = RenderTarget(8, 8, Color(0, 0, 0))
        rasterize_all(
            matcap_quad(facing, facing, ball),
            target,
            SHADE_TEXTURE,
            textures,
            watching_from(4),
        )
        var shown = target.shown(4, 4)
        assert_equal(shown.r, want[2])
        assert_equal(shown.g, want[3])


# --- a surface that reflects -------------------------------------------------


def a_flat_face(color: Color) raises -> Texture:
    """Return a 2x2 face of one color, clamped and nearest."""
    var pixels = List[UInt8]()
    for _ in range(4):
        pixels.append(color.r)
        pixels.append(color.g)
        pixels.append(color.b)
        pixels.append(255)
    return Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB, False)


def a_cube_store() raises -> CubeTextureStore:
    """Return a store holding one cube: red +x, green -x, blue +y, yellow
    -y, cyan +z, magenta -z."""
    var faces = List[Texture]()
    for color in [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 0),
        Color(0, 255, 255),
        Color(255, 0, 255),
    ]:
        faces.append(a_flat_face(color))
    var store = CubeTextureStore()
    _ = store.add(CubeTexture(faces^))
    return store^


def mirror_quad(
    env: CubeTextureId = CubeTextureId(0),
    reflectivity: Float32 = 1,
    combine: Combine = MULTIPLY_OPERATION,
    normal: Vector3 = Vector3(0, 0, 1),
    kind: MaterialKind = BASIC,
    color: FloatColor = FloatColor(1, 1, 1),
) -> List[RasterVertex]:
    """Return two triangles covering an eight-pixel target, at the origin
    with one normal, reflecting `env`."""
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
            RasterVertex(
                place[0],
                place[1],
                0.5,
                1,
                color,
                normal=normal,
                world=Vector3(0, 0, 0),
                kind=kind,
                env_map=env,
                reflectivity=reflectivity,
                combine=combine,
            )
        )
    return corners^


def mirror_pixel(
    corners: List[RasterVertex],
    mode: ShadeMode = SHADE_TEXTURE,
    workers: Int = 1,
    lit: Bool = False,
) raises -> Color:
    """Rasterize `corners` over a cube store and return one pixel, seen
    from up the z axis, under one lamp straight on when `lit`."""
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var scene = Scene()
    if lit:
        var lamp = Object3D()
        lamp.set_position(0, 0, 1)
        var node = scene.add(lamp^)
        scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
        scene.update()
    rasterize_all(
        corners,
        target,
        mode,
        TextureStore(),
        Lighting(scene, Layers.all(), Vector3(0, 0, 3)),
        workers,
        cubes=a_cube_store(),
    )
    return target.shown(3, 3)


def test_a_corner_reflects_nothing_unless_asked() raises:
    var corner = RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1))
    assert_equal(corner.env_map, NO_CUBE_TEXTURE)
    assert_equal(corner.reflectivity, Float32(1))
    assert_equal(corner.combine, MULTIPLY_OPERATION)


def test_a_mirror_square_on_reflects_the_face_behind_the_camera() raises:
    # The view down -z turned back through a +z normal is +z: cyan.
    var seen = mirror_pixel(mirror_quad())
    assert_equal(seen.r, UInt8(0))
    assert_equal(seen.g, UInt8(255))
    assert_equal(seen.b, UInt8(255))
    # Tilted halfway toward +x, the view bounces off along +x: red.
    var tilted = Vector3(1, 0, 1)
    tilted.normalize()
    var side = mirror_pixel(mirror_quad(normal=tilted))
    assert_equal(side.r, UInt8(255))
    assert_equal(side.g, UInt8(0))
    assert_equal(side.b, UInt8(0))


def test_each_combine_reaches_the_pixel() raises:
    # Red times cyan is black; red mixed halfway to cyan is half of each;
    # red plus cyan is white.
    var red = FloatColor(1, 0, 0)
    var multiplied = mirror_pixel(mirror_quad(color=red))
    assert_equal(multiplied.r, UInt8(0))
    assert_equal(multiplied.g, UInt8(0))
    var mixed = mirror_pixel(
        mirror_quad(color=red, reflectivity=0.5, combine=MIX_OPERATION)
    )
    assert_equal(mixed.r, UInt8(188))
    assert_equal(mixed.g, UInt8(188))
    assert_equal(mixed.b, UInt8(188))
    var added = mirror_pixel(mirror_quad(color=red, combine=ADD_OPERATION))
    assert_equal(added.r, UInt8(255))
    assert_equal(added.g, UInt8(255))
    assert_equal(added.b, UInt8(255))


def test_the_bands_reflect_as_one_thread_does() raises:
    var one = mirror_pixel(
        mirror_quad(combine=ADD_OPERATION, color=FloatColor(1, 0, 0))
    )
    var four = mirror_pixel(
        mirror_quad(combine=ADD_OPERATION, color=FloatColor(1, 0, 0)),
        workers=4,
    )
    assert_equal(one.r, four.r)
    assert_equal(one.g, four.g)
    assert_equal(one.b, four.b)
    assert_equal(four.g, UInt8(255))


def test_a_reflection_is_a_texture_the_other_modes_ignore() raises:
    var corners = mirror_quad(combine=ADD_OPERATION, color=FloatColor(1, 0, 0))
    var lit = mirror_pixel(corners, SHADE_LIT)
    assert_equal(lit.r, UInt8(255))
    assert_equal(lit.g, UInt8(0))
    var uv = mirror_pixel(corners, SHADE_UV)
    assert_equal(uv.b, UInt8(0))


def test_a_lit_mirror_reflects_after_it_is_lit() raises:
    # A white lambert surface under no light is black, and black times
    # cyan is black; under a lamp straight on it is white, and white
    # times cyan is cyan.
    var dark = mirror_pixel(mirror_quad(kind=LAMBERT))
    assert_equal(dark.g, UInt8(0))
    var lit = mirror_pixel(mirror_quad(kind=LAMBERT), lit=True)
    assert_equal(lit.r, UInt8(0))
    assert_equal(lit.g, UInt8(255))
    assert_equal(lit.b, UInt8(255))


def test_an_env_map_the_store_lacks_is_refused_before_a_fragment() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var corners = mirror_quad(CubeTextureId(1))
    with assert_raises():
        rasterize_shaded(
            corners[0], corners[1], corners[2], target, SHADE_TEXTURE
        )
    for workers in [1, 4]:
        with assert_raises():
            rasterize_all(
                corners,
                target,
                SHADE_TEXTURE,
                workers=workers,
                cubes=a_cube_store(),
            )
    # A mode that never opens the cube never asks for it.
    rasterize_all(corners, target, SHADE_LIT)


def test_corners_that_disagree_about_their_environment_are_rejected() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var cubes = a_cube_store()
    var one = mirror_quad()
    for other in [
        mirror_quad(NO_CUBE_TEXTURE),
        mirror_quad(reflectivity=0.5),
        mirror_quad(combine=ADD_OPERATION),
    ]:
        with assert_raises():
            rasterize_shaded(one[0], other[1], one[2], target, cubes=cubes)
        with assert_raises():
            rasterize_shaded(one[0], one[1], other[2], target, cubes=cubes)
    rasterize_shaded(one[0], one[1], one[2], target, cubes=cubes)


def test_a_bad_environment_value_is_refused_on_both_paths() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var cubes = a_cube_store()
    var bad = List[List[RasterVertex]]()
    for value in [Float32(-0.5), Float32(1.5), nan[DType.float32]()]:
        bad.append(mirror_quad(reflectivity=value))
    bad.append(mirror_quad(combine=Combine(7)))
    # Only a reflecting kind carries an env map.
    for kind in [TOON, MATCAP]:
        bad.append(mirror_quad(kind=kind))
    # A data kind, whose color must be white and which cannot reflect.
    bad.append(mirror_quad(kind=NORMALS))
    # The scene's environment is resolved by the renderer, and an id
    # nothing can hold is refused with it.
    bad.append(mirror_quad(SCENE_ENVIRONMENT))
    bad.append(mirror_quad(CubeTextureId(-4)))
    for corners in bad:
        with assert_raises():
            rasterize_shaded(
                corners[0], corners[1], corners[2], target, cubes=cubes
            )
        for workers in [1, 4]:
            with assert_raises():
                rasterize_all(corners, target, workers=workers, cubes=cubes)
    # The three kinds that reflect, and the whole range of reflectivity.
    for kind in [BASIC, LAMBERT, PHONG]:
        rasterize_all(mirror_quad(kind=kind), target, cubes=cubes)
    rasterize_all(mirror_quad(reflectivity=0), target, cubes=cubes)


# --- anisotropy, through the rasterizer -----------------------------------------


def striped_store(
    anisotropy: Int, mipmapped: Bool = True
) raises -> TextureStore:
    """Return a store holding an 8x8 image of vertical stripes with the
    given anisotropy."""
    var pixels = List[UInt8]()
    for _ in range(8):
        for x in range(8):
            var tone = UInt8(255) if x % 2 == 0 else UInt8(0)
            pixels.append(tone)
            pixels.append(tone)
            pixels.append(tone)
            pixels.append(255)
    var image = Texture(8, 8, pixels^, CLAMP, NEAREST, LINEAR, mipmapped)
    image.anisotropy = anisotropy
    var store = TextureStore()
    _ = store.add(image^)
    return store^


def stretched_quad() -> List[RasterVertex]:
    """Return two basic triangles covering an eight-pixel target whose
    coordinates run once across and four times down: one texel a pixel
    across, four a pixel down."""
    var corners = List[RasterVertex]()
    var places: List[Tuple[Float32, Float32, Float32, Float32]] = [
        (Float32(0), Float32(0), Float32(0), Float32(4)),
        (Float32(8), Float32(0), Float32(1), Float32(4)),
        (Float32(8), Float32(8), Float32(1), Float32(0)),
        (Float32(0), Float32(0), Float32(0), Float32(4)),
        (Float32(8), Float32(8), Float32(1), Float32(0)),
        (Float32(0), Float32(8), Float32(0), Float32(0)),
    ]
    for place in places:
        corners.append(
            RasterVertex(
                place[0],
                place[1],
                0.5,
                1,
                FloatColor(1, 1, 1),
                place[2],
                place[3],
                TextureId(0),
                kind=BASIC,
            )
        )
    return corners^


def test_a_textures_anisotropy_reaches_the_pixels() raises:
    # One tap reads the stripes off a coarse level, gray; eight taps read
    # them off the full-size image, and the columns alternate.
    var gray = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(stretched_quad(), gray, SHADE_TEXTURE, striped_store(1))
    var soft = gray.shown(2, 4).r
    assert_true(soft > 60 and soft < 200, "one tap was not gray")
    var sharp = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(stretched_quad(), sharp, SHADE_TEXTURE, striped_store(8))
    assert_equal(sharp.shown(2, 4).r, UInt8(255))
    assert_equal(sharp.shown(3, 4).r, UInt8(0))
    # The bands agree with one thread.
    var banded = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        stretched_quad(), banded, SHADE_TEXTURE, striped_store(8), workers=4
    )
    assert_equal(banded.shown(2, 4).r, UInt8(255))
    assert_equal(banded.shown(3, 4).r, UInt8(0))
    # A texture with no chain still takes its taps, off its one level.
    var flat = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        stretched_quad(), flat, SHADE_TEXTURE, striped_store(8, False)
    )
    assert_equal(flat.shown(2, 4).r, UInt8(255))
    assert_equal(flat.shown(3, 4).r, UInt8(0))


# --- physical surfaces and normal maps --------------------------------------


def lit_from_x(z: Float32 = 4) raises -> Lighting:
    """Return one white directional light shining from far up the x axis,
    a little above the surface, with the camera `z` meters up the z axis."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(1, 0, 0.2)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
    scene.update()
    return Lighting(scene, Layers.all(), Vector3(0, 0, z))


def a_data_texel(r: UInt8, g: UInt8, b: UInt8) raises -> Texture:
    """Return a one-texel map stored as data: linear, alpha ignored."""
    var pixels = List[UInt8]()
    pixels.append(r)
    pixels.append(g)
    pixels.append(b)
    pixels.append(255)
    return Texture(1, 1, pixels^, REPEAT, NEAREST, LINEAR, False, IGNORED)


def a_step_map() raises -> Texture:
    """Return a two-texel height map: zero on the left, full on the right,
    stored as data."""
    var pixels = List[UInt8]()
    for value in [0, 255]:
        pixels.append(UInt8(value))
        pixels.append(UInt8(value))
        pixels.append(UInt8(value))
        pixels.append(255)
    return Texture(2, 1, pixels^, CLAMP, NEAREST, LINEAR, False, IGNORED)


def physical_quad(
    kind: MaterialKind = STANDARD,
    roughness: Float32 = 1,
    metalness: Float32 = 0,
    color: FloatColor = FloatColor(1, 1, 1),
    specular: FloatColor = FloatColor(0.04, 0.04, 0.04),
    env: CubeTextureId = NO_CUBE_TEXTURE,
    env_map_intensity: Float32 = 1,
    clearcoat: Float32 = 0,
    clearcoat_roughness: Float32 = 0,
    roughness_map: TextureId = NO_TEXTURE,
    metalness_map: TextureId = NO_TEXTURE,
    normal_map: TextureId = NO_TEXTURE,
    normal_scale: Vector2 = Vector2(1, 1),
    bump_map: TextureId = NO_TEXTURE,
    bump_scale: Float32 = 1,
    texture: TextureId = NO_TEXTURE,
    glow: FloatColor = FloatColor(0.0, 0.0, 0.0),
    mirrored_uv: Bool = False,
) -> List[RasterVertex]:
    """Return two triangles of one kind covering an eight-pixel target,
    facing the camera in the xy plane with the coordinates running across
    it, so a map's tangent frame is the world's own axes."""
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
        var u = place[0] / 8
        if mirrored_uv:
            u = 1 - u
        corners.append(
            RasterVertex(
                place[0],
                place[1],
                0.5,
                1,
                color,
                u,
                1 - place[1] / 8,
                texture,
                normal=Vector3(0, 0, 1),
                # The screen's rows count downward and the world's y counts
                # upward, so the world position mirrors the row.
                world=Vector3(place[0] / 8, 1 - place[1] / 8, 0),
                kind=kind,
                emissive=glow,
                specular=specular,
                env_map=env,
                roughness=roughness,
                metalness=metalness,
                env_map_intensity=env_map_intensity,
                roughness_map=roughness_map,
                metalness_map=metalness_map,
                clearcoat=clearcoat,
                clearcoat_roughness=clearcoat_roughness,
                normal_map=normal_map,
                normal_scale=normal_scale,
                bump_map=bump_map,
                bump_scale=bump_scale,
            )
        )
    return corners^


def viewed_from_z() -> Lighting:
    """Return no lights at all, with the camera far up the z axis, so a
    sheet at the origin is seen square on."""
    var lighting = Lighting(ambient=FloatColor(0.0, 0.0, 0.0))
    lighting.eye = Vector3(0, 0, 400)
    return lighting^


def physical_pixel(
    corners: List[RasterVertex],
    lighting: Lighting = viewed_from_z(),
    textures: TextureStore = TextureStore(),
    mode: ShadeMode = SHADE_TEXTURE,
    workers: Int = 1,
    x: Int = 3,
    y: Int = 3,
) raises -> FloatColor:
    """Draw `corners` over the cube store and return one pixel's light."""
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        corners,
        target,
        mode,
        textures,
        lighting,
        workers,
        cubes=a_cube_store(),
    )
    return target.color_at(x, y)


def test_a_corner_is_a_rough_dielectric_with_no_map_unless_asked() raises:
    var corner = RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1))
    assert_equal(corner.roughness, Float32(1))
    assert_equal(corner.metalness, Float32(0))
    assert_equal(corner.env_map_intensity, Float32(1))
    assert_equal(corner.specular_intensity, Float32(1))
    assert_equal(corner.clearcoat, Float32(0))
    assert_equal(corner.clearcoat_roughness, Float32(0))
    assert_equal(corner.roughness_map, NO_TEXTURE)
    assert_equal(corner.metalness_map, NO_TEXTURE)
    assert_equal(corner.normal_map, NO_TEXTURE)
    assert_equal(corner.bump_map, NO_TEXTURE)
    assert_equal(corner.normal_scale.x, Float32(1))
    assert_equal(corner.normal_scale.y, Float32(1))
    assert_equal(corner.bump_scale, Float32(1))


def test_a_standard_surface_scatters_like_lambert_plus_a_lobe() raises:
    # A white dielectric under one white light head on scatters one, and
    # its lobe adds a quarter of four percent on top.
    var lighting = lit_along_z_from(400)
    var chalk = physical_pixel(physical_quad(), lighting)
    assert_almost_equal(chalk.r, Float32(1.01), atol=1e-3)
    assert_equal(chalk.a, Float32(1))
    # A red metal scatters nothing and reflects a quarter of red.
    var metal = physical_pixel(
        physical_quad(metalness=1, color=FloatColor(1, 0, 0)), lighting
    )
    assert_almost_equal(metal.r, Float32(0.25), atol=1e-3)
    assert_almost_equal(metal.g, Float32(0), atol=1e-3)
    # A smoother metal is brighter at the center of its lobe.
    var polished = physical_pixel(
        physical_quad(roughness=0.4, metalness=1, color=FloatColor(1, 0, 0)),
        lighting,
    )
    assert_true(polished.r > metal.r, "a smoother metal made a dimmer lobe")
    # A physical surface is the same under every lit mode: it reads no
    # map here, and reads the same lights.
    var lit = physical_pixel(physical_quad(), lighting, mode=SHADE_LIT)
    assert_equal(lit.r, chalk.r)
    # And it is lit the same on four workers as on one.
    var banded = physical_pixel(physical_quad(), lighting, workers=4)
    assert_equal(banded.r, chalk.r)
    # The glow is added after the lights, as on every lit surface.
    var glowing = physical_pixel(
        physical_quad(glow=FloatColor(0.5, 0.0, 0.0)), lighting
    )
    assert_almost_equal(glowing.r, Float32(1.51), atol=1e-3)
    assert_almost_equal(glowing.g, Float32(1.01), atol=1e-3)
    # A physical material is lit; the two kinds are the same shader with
    # the physical one's extra terms at their defaults.
    var physical = physical_pixel(physical_quad(kind=PHYSICAL), lighting)
    assert_equal(physical.r, chalk.r)


def test_a_map_multiplies_the_base_color_before_the_lobe_is_tinted() raises:
    # A red metal under a green map reflects nothing: the map multiplies
    # the color the lobe is tinted by, not the finished light.
    var textures = TextureStore()
    var green = textures.add(a_data_texel(0, 255, 0))
    var lighting = lit_along_z_from(400)
    var tinted = physical_pixel(
        physical_quad(metalness=1, color=FloatColor(1, 0, 0), texture=green),
        lighting,
        textures,
    )
    assert_almost_equal(tinted.r, Float32(0), atol=1e-3)
    assert_almost_equal(tinted.g, Float32(0), atol=1e-3)
    # A roughness map's green multiplies the roughness, and a metalness
    # map's blue the metalness: a white metal under a map that is black
    # in blue scatters as a dielectric, and one that is black in green is
    # a mirror-smooth lobe.
    var no_blue = textures.add(a_data_texel(255, 255, 0))
    var dielectric = physical_pixel(
        physical_quad(metalness=1, metalness_map=no_blue), lighting, textures
    )
    assert_almost_equal(dielectric.r, Float32(1.01), atol=1e-3)
    var no_green = textures.add(a_data_texel(255, 0, 255))
    var smooth = physical_pixel(
        physical_quad(
            metalness=1, color=FloatColor(1, 0, 0), roughness_map=no_green
        ),
        lighting,
        textures,
    )
    var rough = physical_pixel(
        physical_quad(metalness=1, color=FloatColor(1, 0, 0)),
        lighting,
        textures,
    )
    assert_true(smooth.r > rough.r, "the roughness map did not smooth")
    # Neither map is read under lit shading.
    var ignored = physical_pixel(
        physical_quad(metalness=1, metalness_map=no_blue),
        lighting,
        textures,
        mode=SHADE_LIT,
    )
    assert_almost_equal(ignored.r, Float32(0.25), atol=1e-3)


def test_a_physical_surface_reflects_its_environment_by_its_roughness() raises:
    # A smooth white metal square on to the camera reflects the face
    # behind the camera, cyan, almost whole: the split sum keeps nearly
    # all of it head on.
    var mirror = physical_pixel(
        physical_quad(
            roughness=0,
            metalness=1,
            env=CubeTextureId(0),
        )
    )
    assert_true(mirror.g > 0.9, "a smooth metal lost its reflection")
    assert_true(mirror.b > 0.9, "a smooth metal lost its reflection")
    assert_true(mirror.r < 0.1, "a smooth metal reflected the wrong face")
    # The intensity scales it, and zero is no reflection.
    var dimmed = physical_pixel(
        physical_quad(
            roughness=0,
            metalness=1,
            env=CubeTextureId(0),
            env_map_intensity=0.5,
        )
    )
    assert_almost_equal(dimmed.g, mirror.g * 0.5, atol=1e-3)
    var none = physical_pixel(
        physical_quad(
            roughness=0,
            metalness=1,
            env=CubeTextureId(0),
            env_map_intensity=0,
        )
    )
    assert_equal(none.g, Float32(0))
    # A dielectric under the same sky scatters the irradiance around its
    # normal, cyan, through its color: white takes it, red keeps the red
    # of it, which is none.
    var chalk = physical_pixel(physical_quad(env=CubeTextureId(0)))
    assert_true(chalk.g > 0.5, "a white surface under a cyan sky went dark")
    var red = physical_pixel(
        physical_quad(env=CubeTextureId(0), color=FloatColor(1, 0, 0))
    )
    assert_true(red.g < chalk.g, "a red surface scattered as much green")
    # Only under textured shading: a reflection is a texture.
    var lit = physical_pixel(
        physical_quad(roughness=0, metalness=1, env=CubeTextureId(0)),
        mode=SHADE_LIT,
    )
    assert_equal(lit.g, Float32(0))
    # A coat reflects the sky too, on its own: a black coated dielectric
    # with no lights shows the coat's gloss and nothing else.
    var coated = physical_pixel(
        physical_quad(
            color=FloatColor(0, 0, 0),
            env=CubeTextureId(0),
            clearcoat=1,
        )
    )
    var bare = physical_pixel(
        physical_quad(color=FloatColor(0, 0, 0), env=CubeTextureId(0))
    )
    assert_true(coated.g > bare.g, "the coat reflected nothing")
    # A rough reflection reads the chain: a cube of one level reads the
    # same texel at every roughness, so the two agree here, which is what
    # the mipmapped cube in the renderer's tests distinguishes.
    var rough = physical_pixel(
        physical_quad(roughness=1, metalness=1, env=CubeTextureId(0))
    )
    assert_true(rough.g > 0, "a rough metal lost the sky")


def test_a_clear_coat_glosses_a_black_surface() raises:
    # A black dielectric under one light shows a quarter of four percent
    # from its lobe; a full smooth coat over it adds a bright gloss at
    # the center, dimmed only by the coat's own Fresnel.
    var lighting = lit_along_z_from(400)
    var bare = physical_pixel(
        physical_quad(color=FloatColor(0, 0, 0)), lighting
    )
    assert_almost_equal(bare.r, Float32(0.01), atol=1e-3)
    var coated = physical_pixel(
        physical_quad(color=FloatColor(0, 0, 0), clearcoat=1), lighting
    )
    assert_true(coated.r > 1, "a smooth coat made no gloss")
    # A rougher coat spreads the gloss and dims its center.
    var matte = physical_pixel(
        physical_quad(
            color=FloatColor(0, 0, 0), clearcoat=1, clearcoat_roughness=1
        ),
        lighting,
    )
    assert_true(matte.r < coated.r, "a rough coat was as bright")
    assert_true(matte.r > bare.r, "a rough coat added nothing")


def test_a_normal_map_tilts_the_normal_in_the_surfaces_frame() raises:
    # A flat sheet lit from far along x catches little; a map whose one
    # texel points along +x, which is the sheet's own +u, turns the normal
    # toward the light and catches most of it.
    var textures = TextureStore()
    var toward_x = textures.add(a_data_texel(255, 128, 128))
    var lighting = lit_from_x()
    var flat = physical_pixel(physical_quad(kind=LAMBERT), lighting, textures)
    var tilted = physical_pixel(
        physical_quad(kind=LAMBERT, normal_map=toward_x), lighting, textures
    )
    assert_true(tilted.r > flat.r + 0.3, "the normal map did not tilt")
    # The scale turns it back: a negative scale, which is what the
    # renderer hands a corner it turns around, tilts toward -x and away
    # from the light.
    var turned = physical_pixel(
        physical_quad(
            kind=LAMBERT, normal_map=toward_x, normal_scale=Vector2(-1, -1)
        ),
        lighting,
        textures,
    )
    assert_true(turned.r < flat.r, "a negated scale did not tilt away")
    # Mirrored coordinates mirror the frame: +u is now -x, so the same
    # texel tilts away from the light.
    var mirrored = physical_pixel(
        physical_quad(kind=LAMBERT, normal_map=toward_x, mirrored_uv=True),
        lighting,
        textures,
    )
    assert_true(mirrored.r < flat.r, "a mirrored frame did not mirror")
    # A texel straight up leaves the normal alone.
    var straight = textures.add(a_data_texel(128, 128, 255))
    var same = physical_pixel(
        physical_quad(kind=LAMBERT, normal_map=straight), lighting, textures
    )
    assert_almost_equal(same.r, flat.r, atol=1e-2)
    # Every kind that reads a normal reads the map: phong, toon, matcap
    # and the physical two all change.
    for kind in [PHONG, TOON, STANDARD, PHYSICAL]:
        var plain = physical_pixel(physical_quad(kind=kind), lighting, textures)
        var mapped = physical_pixel(
            physical_quad(kind=kind, normal_map=toward_x), lighting, textures
        )
        assert_true(mapped.r != plain.r, "a lit kind ignored the normal map")
    var ball = physical_pixel(physical_quad(kind=MATCAP), lighting, textures)
    var looked = physical_pixel(
        physical_quad(kind=MATCAP, normal_map=toward_x), lighting, textures
    )
    assert_true(looked.r != ball.r, "a matcap ignored the normal map")
    # Not under lit shading, where no texture is opened.
    var unread = physical_pixel(
        physical_quad(kind=LAMBERT, normal_map=toward_x),
        lighting,
        textures,
        mode=SHADE_LIT,
    )
    assert_equal(unread.r, flat.r)
    # And the same on four workers.
    var banded = physical_pixel(
        physical_quad(kind=LAMBERT, normal_map=toward_x),
        lighting,
        textures,
        workers=4,
    )
    assert_equal(banded.r, tilted.r)


def test_a_hand_built_corner_with_no_divisor_is_still_perturbed() raises:
    # Nothing the renderer builds carries a reciprocal depth of zero, but
    # a hand-built corner can, and the frame's derivatives then fall back
    # to the screen-space weights as every other varying does.
    var textures = TextureStore()
    var toward_x = textures.add(a_data_texel(255, 128, 128))
    var lighting = lit_from_x()
    var flat = physical_quad(kind=LAMBERT)
    var tilted = physical_quad(kind=LAMBERT, normal_map=toward_x)
    for corner in range(6):
        flat[corner].inv_w = 0
        tilted[corner].inv_w = 0
    var plain = physical_pixel(flat, lighting, textures)
    var mapped = physical_pixel(tilted, lighting, textures)
    assert_true(mapped.r > plain.r, "the map did not tilt without a divisor")


def test_a_bump_map_tilts_the_normal_against_the_slope() raises:
    # Heights that rise toward +x tilt the normal toward -x, away from a
    # light along x; a negative scale, which is what a turned corner
    # carries, tilts it the other way. The pixel is the one whose next
    # pixel over crosses from the low texel to the high one.
    var textures = TextureStore()
    var step = textures.add(a_step_map())
    var lighting = lit_from_x()
    var flat = physical_pixel(
        physical_quad(kind=LAMBERT), lighting, textures, x=3
    )
    var against = physical_pixel(
        physical_quad(kind=LAMBERT, bump_map=step, bump_scale=0.5),
        lighting,
        textures,
        x=3,
    )
    assert_true(against.r < flat.r, "the bump did not tilt against the rise")
    var toward = physical_pixel(
        physical_quad(kind=LAMBERT, bump_map=step, bump_scale=-0.5),
        lighting,
        textures,
        x=3,
    )
    assert_true(toward.r > flat.r, "a negated bump did not tilt toward")
    # Where the height does not change, nothing tilts.
    var level = physical_pixel(
        physical_quad(kind=LAMBERT, bump_map=step, bump_scale=0.5),
        lighting,
        textures,
        x=1,
    )
    assert_almost_equal(level.r, flat.r, atol=1e-6)


def test_mapped_normal_builds_the_frame_from_the_derivatives() raises:
    # A sheet in the xy plane with u along x and v along y: a texel along
    # +x is the world's +x, and one along +y its +y.
    var up = Vector3(0, 0, 1)
    var along_x = Vector3(1, 0, 0)
    var along_y = Vector3(0, 1, 0)
    var right = mapped_normal(
        up,
        along_x,
        along_y,
        Vector2(1, 0),
        Vector2(0, 1),
        FloatColor(1, 0.5, 0.5),
        Vector2(1, 1),
    )
    assert_almost_equal(right.x, Float32(1), atol=1e-2)
    assert_almost_equal(right.z, Float32(0), atol=1e-2)
    var forward = mapped_normal(
        up,
        along_x,
        along_y,
        Vector2(1, 0),
        Vector2(0, 1),
        FloatColor(0.5, 1, 0.5),
        Vector2(1, 1),
    )
    assert_almost_equal(forward.y, Float32(1), atol=1e-2)
    # Mirrored coordinates mirror the tangent.
    var mirrored = mapped_normal(
        up,
        along_x,
        along_y,
        Vector2(-1, 0),
        Vector2(0, 1),
        FloatColor(1, 0.5, 0.5),
        Vector2(1, 1),
    )
    assert_almost_equal(mirrored.x, Float32(-1), atol=1e-2)
    # The scale multiplies x and y, and a texel straight up is the normal.
    var scaled = mapped_normal(
        up,
        along_x,
        along_y,
        Vector2(1, 0),
        Vector2(0, 1),
        FloatColor(0.75, 0.5, 1),
        Vector2(2, 1),
    )
    assert_almost_equal(scaled.x, scaled.z, atol=1e-6)
    var same = mapped_normal(
        up,
        along_x,
        along_y,
        Vector2(1, 0),
        Vector2(0, 1),
        FloatColor(0.5, 0.5, 1),
        Vector2(1, 1),
    )
    assert_almost_equal(same.z, Float32(1), atol=1e-6)
    # A degenerate frame leaves the normal alone, and so does a texel
    # that unpacks to nothing at all.
    var none = Vector3(0, 0, 0)
    var flat = mapped_normal(
        up,
        none,
        none,
        Vector2(0, 0),
        Vector2(0, 0),
        FloatColor(1, 0.5, 0.5),
        Vector2(1, 1),
    )
    assert_equal(flat.z, Float32(1))
    var zero = mapped_normal(
        up,
        along_x,
        along_y,
        Vector2(1, 0),
        Vector2(0, 1),
        FloatColor(0.5, 0.5, 0.5),
        Vector2(1, 1),
    )
    assert_equal(zero.z, Float32(1))


def test_bumped_normal_tilts_against_the_rise_in_either_frame() raises:
    var up = Vector3(0, 0, 1)
    # A right-handed frame: a rise toward +x tilts the normal toward -x.
    var against = bumped_normal(up, Vector3(1, 0, 0), Vector3(0, 1, 0), 0.5, 0)
    assert_true(against.x < 0, "the normal tilted with the rise")
    assert_almost_equal(against.x, -0.5 / sqrt(Float32(1.25)), atol=1e-6)
    # A mirrored frame, x running the other way: the same rise on the
    # screen is a rise toward -x in the world, so the tilt is toward +x.
    var mirrored = bumped_normal(
        up, Vector3(-1, 0, 0), Vector3(0, 1, 0), 0.5, 0
    )
    assert_true(mirrored.x > 0, "the mirrored frame did not mirror")
    # The changes are normalized first, so a longer step is the same tilt.
    var far = bumped_normal(up, Vector3(4, 0, 0), Vector3(0, 4, 0), 0.5, 0)
    assert_almost_equal(far.x, against.x, atol=1e-6)
    # A rise along y tilts along -y.
    var back = bumped_normal(up, Vector3(1, 0, 0), Vector3(0, 1, 0), 0, 0.5)
    assert_true(back.y < 0, "the y rise did not tilt")
    # A degenerate frame leaves the normal alone.
    var none = Vector3(0, 0, 0)
    assert_equal(bumped_normal(up, none, none, 0.5, 0.5).z, Float32(1))


def test_a_physical_triangle_state_is_checked_like_the_rest() raises:
    var good = physical_quad()
    check_triangle_state(good[0], good[1], good[2])
    # Every number in its range, and finite.
    for wrong in [Float32(-0.5), Float32(1.5), nan[DType.float32]()]:
        var rough = physical_quad(roughness=wrong)
        with assert_raises():
            check_triangle_state(rough[0], rough[1], rough[2])
        var metal = physical_quad(metalness=wrong)
        with assert_raises():
            check_triangle_state(metal[0], metal[1], metal[2])
        var coat = physical_quad(clearcoat=wrong)
        with assert_raises():
            check_triangle_state(coat[0], coat[1], coat[2])
        var coat_rough = physical_quad(clearcoat_roughness=wrong)
        with assert_raises():
            check_triangle_state(coat_rough[0], coat_rough[1], coat_rough[2])
        var intensity = physical_quad()
        intensity[0].specular_intensity = wrong
        with assert_raises():
            check_triangle_state(intensity[0], intensity[1], intensity[2])
    for wrong in [Float32(-1), nan[DType.float32]()]:
        var strength = physical_quad(env_map_intensity=wrong)
        with assert_raises():
            check_triangle_state(strength[0], strength[1], strength[2])
    var wide = physical_quad(normal_scale=Vector2(nan[DType.float32](), 1))
    with assert_raises():
        check_triangle_state(wide[0], wide[1], wide[2])
    var tall = physical_quad(normal_scale=Vector2(1, nan[DType.float32]()))
    with assert_raises():
        check_triangle_state(tall[0], tall[1], tall[2])
    var high = physical_quad(bump_scale=nan[DType.float32]())
    with assert_raises():
        check_triangle_state(high[0], high[1], high[2])
    # The corners must agree, on every number, map and scale, and a
    # disagreement on the second corner or the third is caught alike.
    for corner in [1, 2]:
        var rough = physical_quad()
        rough[corner].roughness = 0.5
        with assert_raises():
            check_triangle_state(rough[0], rough[1], rough[2])
        var metal = physical_quad()
        metal[corner].metalness = 0.5
        with assert_raises():
            check_triangle_state(metal[0], metal[1], metal[2])
        var strength = physical_quad()
        strength[corner].env_map_intensity = 0.5
        with assert_raises():
            check_triangle_state(strength[0], strength[1], strength[2])
        var intensity = physical_quad()
        intensity[corner].specular_intensity = 0.5
        with assert_raises():
            check_triangle_state(intensity[0], intensity[1], intensity[2])
        var coat = physical_quad()
        coat[corner].clearcoat = 0.5
        with assert_raises():
            check_triangle_state(coat[0], coat[1], coat[2])
        var coat_rough = physical_quad()
        coat_rough[corner].clearcoat_roughness = 0.5
        with assert_raises():
            check_triangle_state(coat_rough[0], coat_rough[1], coat_rough[2])
        var rough_map = physical_quad()
        rough_map[corner].roughness_map = TextureId(0)
        with assert_raises():
            check_triangle_state(rough_map[0], rough_map[1], rough_map[2])
        var metal_map = physical_quad()
        metal_map[corner].metalness_map = TextureId(0)
        with assert_raises():
            check_triangle_state(metal_map[0], metal_map[1], metal_map[2])
        var normal_map = physical_quad()
        normal_map[corner].normal_map = TextureId(0)
        with assert_raises():
            check_triangle_state(normal_map[0], normal_map[1], normal_map[2])
        var bump_map = physical_quad()
        bump_map[corner].bump_map = TextureId(0)
        with assert_raises():
            check_triangle_state(bump_map[0], bump_map[1], bump_map[2])
        var wide = physical_quad()
        wide[corner].normal_scale = Vector2(2, 1)
        with assert_raises():
            check_triangle_state(wide[0], wide[1], wide[2])
        var tall = physical_quad()
        tall[corner].normal_scale = Vector2(1, 2)
        with assert_raises():
            check_triangle_state(tall[0], tall[1], tall[2])
        var high = physical_quad()
        high[corner].bump_scale = 2
        with assert_raises():
            check_triangle_state(high[0], high[1], high[2])
    # An id nothing can hold, in any of the four.
    for slot in range(4):
        var held = physical_quad()
        for corner in range(6):
            if slot == 0:
                held[corner].roughness_map = TextureId(-2)
            elif slot == 1:
                held[corner].metalness_map = TextureId(-2)
            elif slot == 2:
                held[corner].normal_map = TextureId(-2)
            else:
                held[corner].bump_map = TextureId(-2)
        with assert_raises():
            check_triangle_state(held[0], held[1], held[2])
    # A roughness or metalness map on a kind that is not physical.
    var lambert_rough = physical_quad(kind=LAMBERT, roughness_map=TextureId(0))
    with assert_raises():
        check_triangle_state(
            lambert_rough[0], lambert_rough[1], lambert_rough[2]
        )
    var lambert_metal = physical_quad(kind=LAMBERT, metalness_map=TextureId(0))
    with assert_raises():
        check_triangle_state(
            lambert_metal[0], lambert_metal[1], lambert_metal[2]
        )
    # Both maps at once, and a map on a kind with no normal to perturb.
    var both = physical_quad(normal_map=TextureId(0), bump_map=TextureId(1))
    with assert_raises():
        check_triangle_state(both[0], both[1], both[2])
    for kind in [BASIC, DEPTH, NORMALS]:
        var flat = physical_quad(kind=kind, normal_map=TextureId(0))
        with assert_raises():
            check_triangle_state(flat[0], flat[1], flat[2])
        var bumpy = physical_quad(kind=kind, bump_map=TextureId(0))
        with assert_raises():
            check_triangle_state(bumpy[0], bumpy[1], bumpy[2])
    # A lit kind takes either, and the ends of every range pass.
    var mapped = physical_quad(
        kind=PHONG, normal_map=TextureId(0), normal_scale=Vector2(-2, 3)
    )
    check_triangle_state(mapped[0], mapped[1], mapped[2])
    var edges = physical_quad(
        roughness=0,
        metalness=1,
        env_map_intensity=0,
        clearcoat=1,
        clearcoat_roughness=1,
        bump_map=TextureId(0),
        bump_scale=-1,
    )
    edges[0].specular_intensity = 0
    edges[1].specular_intensity = 0
    edges[2].specular_intensity = 0
    check_triangle_state(edges[0], edges[1], edges[2])


def test_a_data_map_that_is_not_stored_as_data_is_refused() raises:
    # Each of the four maps, under the mode that opens it, on one worker
    # and on four; not under lit shading, which opens none.
    var textures = TextureStore()
    var encoded = textures.add(
        Texture(
            1,
            1,
            [UInt8(255), 255, 255, 255],
            REPEAT,
            NEAREST,
            SRGB,
            False,
            IGNORED,
        )
    )
    var covered = textures.add(
        Texture(
            1,
            1,
            [UInt8(255), 255, 255, 255],
            REPEAT,
            NEAREST,
            LINEAR,
            False,
            COVERAGE,
        )
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    for wrong in [encoded, covered]:
        var quads = List[List[RasterVertex]]()
        quads.append(physical_quad(roughness_map=wrong))
        quads.append(physical_quad(metalness_map=wrong))
        quads.append(physical_quad(normal_map=wrong))
        quads.append(physical_quad(bump_map=wrong))
        for index in range(len(quads)):
            ref quad = quads[index]
            with assert_raises():
                rasterize_shaded(
                    quad[0], quad[1], quad[2], target, SHADE_TEXTURE, textures
                )
            for workers in [1, 4]:
                with assert_raises():
                    rasterize_all(
                        quad, target, SHADE_TEXTURE, textures, workers=workers
                    )
            rasterize_shaded(
                quad[0], quad[1], quad[2], target, SHADE_LIT, textures
            )
    # A map that is not in the store is refused before a fragment too.
    var missing = physical_quad(normal_map=TextureId(7))
    with assert_raises():
        rasterize_all(missing, target, SHADE_TEXTURE, textures)
    # `check_data_map` names the map it refuses.
    with assert_raises(contains="A bump map holds data"):
        check_data_map(textures.get(encoded), "A bump map")
    with assert_raises(contains="A normal map must ignore"):
        check_data_map(textures.get(covered), "A normal map")
    # A map stored as data passes.
    var proper = textures.add(a_data_texel(128, 128, 255))
    check_data_map(textures.get(proper), "A normal map")


def test_every_channel_of_a_normal_map_is_read_and_neutral_is_neutral() raises:
    var up = Vector3(0, 0, 1)
    var along_x = Vector3(1, 0, 0)
    var along_y = Vector3(0, 1, 0)
    var frame_x = Vector2(1, 0)
    var frame_y = Vector2(0, 1)
    # Green alone is the bitangent, blue alone is the normal exactly, and
    # a blue of zero is the normal turned over, as three.js unpacks them.
    var forward = mapped_normal(
        up,
        along_x,
        along_y,
        frame_x,
        frame_y,
        FloatColor(0.5, 1, 0.5),
        Vector2(1, 1),
    )
    assert_almost_equal(forward.y, Float32(1), atol=1e-2)
    assert_almost_equal(forward.x, Float32(0), atol=1e-2)
    var neutral = mapped_normal(
        up,
        along_x,
        along_y,
        frame_x,
        frame_y,
        FloatColor(Float32(128) / 255, Float32(128) / 255, 1),
        Vector2(1, 1),
    )
    assert_almost_equal(neutral.x, Float32(0), atol=1e-2)
    assert_almost_equal(neutral.y, Float32(0), atol=1e-2)
    assert_almost_equal(neutral.z, Float32(1), atol=1e-4)
    var over = mapped_normal(
        up,
        along_x,
        along_y,
        frame_x,
        frame_y,
        FloatColor(0.5, 0.5, 0),
        Vector2(1, 1),
    )
    assert_almost_equal(over.z, Float32(-1), atol=1e-4)
    # Coordinates that do not change leave the normal alone, even for a
    # texel below the horizon that would otherwise turn it over.
    var still = Vector2(0, 0)
    var kept = mapped_normal(
        up, along_x, along_y, still, still, FloatColor(1, 0.5, 0), Vector2(1, 1)
    )
    assert_equal(kept.x, Float32(0))
    assert_equal(kept.z, Float32(1))
    # Coordinates that change along one direction only make a frame
    # whose two axes are parallel: the result is still a unit normal,
    # tilted along that one axis by both of the map's components.
    var lined = mapped_normal(
        up,
        along_x,
        along_y,
        Vector2(1, 0),
        Vector2(2, 0),
        FloatColor(1, 0.5, 0.75),
        Vector2(1, 1),
    )
    assert_almost_equal(lined.length(), Float32(1), atol=1e-5)
    assert_true(lined.z < 1, "a collinear frame tilted nothing")


def test_a_constant_height_leaves_the_normal_and_a_ramp_tilts_by_its_slope() raises:
    var up = Vector3(0, 0, 1)
    var along_x = Vector3(1, 0, 0)
    var along_y = Vector3(0, 1, 0)
    # Whatever the height and the scale, no rise is no tilt.
    for scale in [Float32(0.5), Float32(-2), Float32(10)]:
        var flat = bumped_normal(up, along_x, along_y, 0 * scale, 0 * scale)
        assert_equal(flat.x, Float32(0))
        assert_equal(flat.y, Float32(0))
        assert_equal(flat.z, Float32(1))
    # A rise of s over one pixel along x tilts the normal by atan(s)
    # toward -x: the normal is (-s, 0, 1) made unit.
    for rise in [Float32(0.25), Float32(1), Float32(3)]:
        var tilted = bumped_normal(up, along_x, along_y, rise, 0)
        var expected = Vector3(-rise, 0, 1)
        expected.normalize()
        assert_almost_equal(tilted.x, expected.x, atol=1e-6)
        assert_almost_equal(tilted.z, expected.z, atol=1e-6)
        assert_almost_equal(
            atan2(-tilted.x, tilted.z), atan2(rise, Float32(1)), atol=1e-6
        )
    # And a rise along both is the two tilts together.
    var both = bumped_normal(up, along_x, along_y, 1, 1)
    var corner = Vector3(-1, -1, 1)
    corner.normalize()
    assert_almost_equal(both.x, corner.x, atol=1e-6)
    assert_almost_equal(both.y, corner.y, atol=1e-6)


def test_an_asymmetric_normal_map_tilts_each_axis_by_its_own_sign() raises:
    # A texel tilted along both +u and +v under a lamp from each side in
    # turn: negating one axis of the scale turns that tilt away from its
    # lamp and leaves the other, which a symmetric texel could not show.
    var textures = TextureStore()
    var slanted = textures.add(a_data_texel(255, 200, 128))
    var from_x = lit_from_x()
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 1, 0.2)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
    scene.update()
    var from_y = Lighting(scene, Layers.all(), Vector3(0, 0, 4))
    var flat_x = physical_pixel(physical_quad(kind=LAMBERT), from_x, textures)
    var flat_y = physical_pixel(physical_quad(kind=LAMBERT), from_y, textures)
    var both_x = physical_pixel(
        physical_quad(kind=LAMBERT, normal_map=slanted), from_x, textures
    )
    var both_y = physical_pixel(
        physical_quad(kind=LAMBERT, normal_map=slanted), from_y, textures
    )
    assert_true(both_x.r > flat_x.r, "the +u tilt did not face the x lamp")
    assert_true(both_y.r > flat_y.r, "the +v tilt did not face the y lamp")
    var x_turned = physical_quad(
        kind=LAMBERT, normal_map=slanted, normal_scale=Vector2(-1, 1)
    )
    assert_true(
        physical_pixel(x_turned, from_x, textures).r < flat_x.r,
        "negating x did not turn the tilt from the x lamp",
    )
    assert_true(
        physical_pixel(x_turned, from_y, textures).r > flat_y.r,
        "negating x turned the tilt from the y lamp",
    )
    var y_turned = physical_quad(
        kind=LAMBERT, normal_map=slanted, normal_scale=Vector2(1, -1)
    )
    assert_true(
        physical_pixel(y_turned, from_y, textures).r < flat_y.r,
        "negating y did not turn the tilt from the y lamp",
    )
    assert_true(
        physical_pixel(y_turned, from_x, textures).r > flat_x.r,
        "negating y turned the tilt from the x lamp",
    )


def test_a_roughness_or_metalness_map_multiplies_before_the_floor() raises:
    # A map of zero makes the authored number zero, which the floor then
    # lifts: the same pixel as an authored roughness at the floor and no
    # map, and a metalness of zero. A map of one changes nothing.
    var textures = TextureStore()
    var zeros = textures.add(a_data_texel(0, 0, 0))
    var ones = textures.add(a_data_texel(255, 255, 255))
    var lighting = lit_along_z_from(400)
    var floored = physical_pixel(
        physical_quad(roughness=0.2, metalness=1, roughness_map=zeros),
        lighting,
        textures,
    )
    var at_floor = physical_pixel(
        physical_quad(roughness=ROUGHNESS_FLOOR, metalness=1),
        lighting,
        textures,
    )
    assert_equal(floored.r, at_floor.r)
    var unmapped = physical_pixel(
        physical_quad(roughness=0.2, metalness=1, roughness_map=ones),
        lighting,
        textures,
    )
    var plain = physical_pixel(
        physical_quad(roughness=0.2, metalness=1), lighting, textures
    )
    assert_equal(unmapped.r, plain.r)
    var dielectric = physical_pixel(
        physical_quad(metalness=0.7, metalness_map=zeros), lighting, textures
    )
    var chalk = physical_pixel(physical_quad(metalness=0), lighting, textures)
    assert_equal(dielectric.r, chalk.r)
    var metal = physical_pixel(
        physical_quad(metalness=0.7, metalness_map=ones), lighting, textures
    )
    var seven_tenths = physical_pixel(
        physical_quad(metalness=0.7), lighting, textures
    )
    assert_equal(metal.r, seven_tenths.r)


def test_a_clear_coat_lies_on_the_normal_before_the_map_perturbs_it() raises:
    # A rough black metal, whose own lobe is next to nothing whichever way
    # it faces -- Schlick's grazing rise is all a black reflectance keeps
    # -- with
    # a normal map that turns its normal well away from a lamp straight
    # on: the coat's gloss stays at the center, bright, because the coat
    # reads the geometric normal, and it is the very gloss the unmapped
    # surface shows.
    var textures = TextureStore()
    var toward_x = textures.add(a_data_texel(255, 128, 128))
    var lighting = lit_along_z_from(400)
    var bare = physical_pixel(
        physical_quad(
            kind=PHYSICAL,
            color=FloatColor(0, 0, 0),
            metalness=1,
            roughness=1,
            normal_map=toward_x,
        ),
        lighting,
        textures,
    )
    var coated = physical_pixel(
        physical_quad(
            kind=PHYSICAL,
            color=FloatColor(0, 0, 0),
            metalness=1,
            roughness=1,
            normal_map=toward_x,
            clearcoat=1,
        ),
        lighting,
        textures,
    )
    assert_true(bare.r < 1e-3, "the turned metal still caught the lamp")
    assert_true(coated.r > 1, "the coat followed the map off the lamp")
    var upright = physical_pixel(
        physical_quad(
            kind=PHYSICAL,
            color=FloatColor(0, 0, 0),
            metalness=1,
            roughness=1,
            clearcoat=1,
        ),
        lighting,
        textures,
    )
    assert_almost_equal(coated.r, upright.r, atol=1e-3)


# --- shadows ----------------------------------------------------------------


def a_shadowed_lighting(receives_map: Bool = True) raises -> Lighting:
    """Return one white sun up the z axis, with the camera far up it, and
    a shadow map over the unit square whose left half holds a caster at
    z = 0.5: the eight-pixel quads of `physical_quad` lie in that square,
    their left half in shadow."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    var sun = directional_light(Color(255, 255, 255), node, FULL)
    sun.cast_shadow = receives_map
    scene.add_light(sun)
    scene.update()
    var frame = SIMD[DType.float32, 16](0)
    frame[0] = 1
    frame[5] = 1
    frame[10] = -1
    frame[15] = 1
    var depths = List[Float32]()
    for _ in range(4):
        for column in range(4):
            if column < 2:
                depths.append(-0.5)
            else:
                depths.append(inf[DType.float32]())
    var maps = List[ShadowMap]()
    if receives_map:
        maps.append(ShadowMap(0, 4, frame, depths^, 0, 0, 0))
    return Lighting(scene, Layers.all(), Vector3(0, 0, 400), shadows=maps^)


def shadow_quad(
    kind: MaterialKind, receives: Bool = True
) -> List[RasterVertex]:
    """Return `physical_quad` of `kind` spanning x from -1 to 1 in the
    world, so its left half lies under the caster of `a_shadowed_lighting`,
    blending when the kind is `SHADOW`."""
    var corners = physical_quad(kind=kind)
    for index in range(len(corners)):
        corners[index].world = Vector3(
            corners[index].world.x * 2 - 1, corners[index].world.y * 2 - 1, 0
        )
        corners[index].receives_shadow = receives
        if kind == SHADOW:
            corners[index].blend = BLEND
            corners[index].color = FloatColor(0, 0, 0, 1)
    return corners^


def test_a_shadow_falls_on_the_half_of_a_quad_under_the_caster() raises:
    # Pixel x = 1 lies under the caster and x = 6 does not: the lit kinds
    # go dark on the left and stay lit on the right, unless the surface
    # does not receive.
    var lighting = a_shadowed_lighting()
    for kind in [LAMBERT, PHONG, TOON, STANDARD]:
        var dark = physical_pixel(shadow_quad(kind), lighting, x=1)
        var lit = physical_pixel(shadow_quad(kind), lighting, x=6)
        assert_true(lit.r > dark.r + 0.3, "the shadow did not fall")
        var ignored = physical_pixel(shadow_quad(kind, False), lighting, x=1)
        assert_equal(ignored.r, lit.r)
    # A toon surface in full shadow is black, as three.js's is: the
    # shadow scales the light before the ramp is read, not the tone after.
    var toon = physical_pixel(shadow_quad(TOON), lighting, x=1)
    assert_equal(toon.r, Float32(0))
    # Without a map the two halves are one.
    var plain = a_shadowed_lighting(False)
    assert_equal(
        physical_pixel(shadow_quad(LAMBERT), plain, x=1).r,
        physical_pixel(shadow_quad(LAMBERT), plain, x=6).r,
    )


def test_a_shadow_material_shows_the_shadow_as_its_alpha() raises:
    # Black where the caster blocks the sun, transparent where it does
    # not, over a black target: the pixel's own color tells nothing, so
    # the target's alpha is read through a blend over white instead.
    var lighting = a_shadowed_lighting()
    var target = RenderTarget(8, 8, Color(255, 255, 255))
    rasterize_all(
        shadow_quad(SHADOW), target, SHADE_TEXTURE, TextureStore(), lighting
    )
    assert_equal(target.shown(1, 3).r, UInt8(0))
    assert_equal(target.shown(6, 3).r, UInt8(255))
    # Under lit shading too: a shadow is not a texture.
    var lit = RenderTarget(8, 8, Color(255, 255, 255))
    rasterize_all(shadow_quad(SHADOW), lit, SHADE_LIT, TextureStore(), lighting)
    assert_equal(lit.shown(1, 3).r, UInt8(0))
    assert_equal(lit.shown(6, 3).r, UInt8(255))
    # An opacity below one is a fainter shadow.
    var faint = shadow_quad(SHADOW)
    for index in range(len(faint)):
        faint[index].color = FloatColor(0, 0, 0, 0.5)
    var half = RenderTarget(8, 8, Color(255, 255, 255))
    rasterize_all(faint, half, SHADE_LIT, TextureStore(), lighting)
    assert_true(half.shown(1, 3).r > 100, "the faint shadow was full")
    assert_true(half.shown(1, 3).r < 255, "the faint shadow was none")
    # The uv view shows coordinates, as it does for every kind.
    var view = RenderTarget(8, 8, Color(255, 255, 255))
    rasterize_all(shadow_quad(SHADOW), view, SHADE_UV, TextureStore(), lighting)
    assert_true(view.shown(1, 3).b == 0, "the uv view shaded a shadow")
    # Without a map, nothing is caught anywhere: fully transparent.
    var none = RenderTarget(8, 8, Color(255, 255, 255))
    rasterize_all(
        shadow_quad(SHADOW),
        none,
        SHADE_LIT,
        TextureStore(),
        a_shadowed_lighting(False),
    )
    assert_equal(none.shown(1, 3).r, UInt8(255))


def test_a_shadow_triangle_is_checked_like_the_rest() raises:
    var good = shadow_quad(SHADOW)
    check_triangle_state(good[0], good[1], good[2])
    # Opaque is refused, a map is refused, and the corners must agree
    # about receiving.
    var opaque = shadow_quad(SHADOW)
    for index in range(3):
        opaque[index].blend = OPAQUE
    with assert_raises():
        check_triangle_state(opaque[0], opaque[1], opaque[2])
    var mapped = shadow_quad(SHADOW)
    for index in range(3):
        mapped[index].texture = TextureId(0)
    with assert_raises():
        check_triangle_state(mapped[0], mapped[1], mapped[2])
    var masked = shadow_quad(SHADOW)
    for index in range(3):
        masked[index].alpha_map = TextureId(0)
    with assert_raises():
        check_triangle_state(masked[0], masked[1], masked[2])
    for corner in [1, 2]:
        var split = shadow_quad(LAMBERT)
        split[corner].receives_shadow = False
        with assert_raises():
            check_triangle_state(split[0], split[1], split[2])
    # A corner receives unless told otherwise.
    assert_true(RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1)).receives_shadow)


# --- ambient occlusion and light maps ---------------------------------------


def baked_quad(
    kind: MaterialKind = LAMBERT,
    ao_map: TextureId = NO_TEXTURE,
    light_map: TextureId = NO_TEXTURE,
    ao_map_intensity: Float32 = 1,
    light_map_intensity: Float32 = 1,
    second_u: Float32 = -1,
    roughness: Float32 = 1,
    metalness: Float32 = 0,
    env: CubeTextureId = NO_CUBE_TEXTURE,
) -> List[RasterVertex]:
    """Return `physical_quad` with the two baked maps, sampled at second
    coordinates that copy the first, or that hold `second_u` across the
    whole quad when it is not negative."""
    var corners = physical_quad(
        kind=kind,
        roughness=roughness,
        metalness=metalness,
        env=env,
    )
    for index in range(len(corners)):
        corners[index].u1 = corners[index].u
        corners[index].v1 = corners[index].v
        if second_u >= 0:
            corners[index].u1 = second_u
        corners[index].ao_map = ao_map
        corners[index].light_map = light_map
        corners[index].ao_map_intensity = ao_map_intensity
        corners[index].light_map_intensity = light_map_intensity
    return corners^


def lit_and_filled() raises -> Lighting:
    """Return a white sun head on along z that reflects one from a white
    surface, and an ambient light that reflects a half, seen from far up
    the z axis."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
    scene.add_light(ambient_light(Color(255, 255, 255), FULL * 0.5))
    scene.update()
    return Lighting(scene, Layers.all(), Vector3(0, 0, 400))


def filled() raises -> Lighting:
    """Return the ambient half of `lit_and_filled` alone."""
    var scene = Scene()
    scene.add_light(ambient_light(Color(255, 255, 255), FULL * 0.5))
    scene.update()
    return Lighting(scene, Layers.all(), Vector3(0, 0, 400))


def a_mipmapped_gray() raises -> Texture:
    """Return a two-by-two map of one gray, stored as data, with a chain:
    every level and every footprint reads the same number."""
    var pixels = List[UInt8]()
    for _ in range(4):
        for _ in range(3):
            pixels.append(128)
        pixels.append(255)
    return Texture(2, 2, pixels^, REPEAT, NEAREST, LINEAR, True, IGNORED)


comptime HALF_GRAY = Float32(128) / Float32(255)


def test_an_ao_map_dims_the_indirect_light_and_not_the_direct() raises:
    var textures = TextureStore()
    var gray = textures.add(a_data_texel(128, 128, 128))
    var lighting = lit_and_filled()
    # One from the sun and a half from the ambient light, unoccluded.
    var bare = physical_pixel(baked_quad(), lighting, textures)
    assert_almost_equal(bare.r, Float32(1.5), atol=1e-4)
    # The ambient half is dimmed by the gray; the sun is not.
    var dimmed = physical_pixel(baked_quad(ao_map=gray), lighting, textures)
    assert_almost_equal(dimmed.r, 1 + 0.5 * HALF_GRAY, atol=1e-4)
    # An intensity of zero switches the map off.
    var off = physical_pixel(
        baked_quad(ao_map=gray, ao_map_intensity=0), lighting, textures
    )
    assert_almost_equal(off.r, Float32(1.5), atol=1e-4)
    # Lit shading opens no map.
    var lit = physical_pixel(
        baked_quad(ao_map=gray), lighting, textures, mode=SHADE_LIT
    )
    assert_almost_equal(lit.r, Float32(1.5), atol=1e-4)
    # A toon and a phong surface are dimmed the same way.
    for kind in [TOON, PHONG]:
        var plain = physical_pixel(baked_quad(kind=kind), lighting, textures)
        var shaded = physical_pixel(
            baked_quad(kind=kind, ao_map=gray), lighting, textures
        )
        assert_almost_equal(
            plain.r - shaded.r, 0.5 * (1 - HALF_GRAY), atol=1e-4
        )


def test_a_light_map_adds_to_the_indirect_light() raises:
    var textures = TextureStore()
    var red = textures.add(a_data_texel(255, 0, 0))
    var black = textures.add(a_data_texel(0, 0, 0))
    var lighting = lit_and_filled()
    # Divided by pi like every lit term, so an intensity of pi adds one.
    var baked = physical_pixel(
        baked_quad(light_map=red, light_map_intensity=FULL),
        lighting,
        textures,
    )
    assert_almost_equal(baked.r, Float32(2.5), atol=1e-4)
    assert_almost_equal(baked.g, Float32(1.5), atol=1e-4)
    # A black ao map occludes it with the ambient light, and leaves the sun.
    var hidden = physical_pixel(
        baked_quad(ao_map=black, light_map=red, light_map_intensity=FULL),
        lighting,
        textures,
    )
    assert_almost_equal(hidden.r, Float32(1), atol=1e-4)
    assert_almost_equal(hidden.g, Float32(1), atol=1e-4)


def test_a_basic_surface_shows_its_light_map_and_is_occluded() raises:
    var textures = TextureStore()
    var orange = textures.add(a_data_texel(255, 128, 0))
    var gray = textures.add(a_data_texel(128, 128, 128))
    var black = textures.add(a_data_texel(0, 0, 0))
    # three.js's `meshbasic_frag`: the light map replaces the white
    # indirect light, divided by pi, whatever the scene's lights are.
    var baked = physical_pixel(
        baked_quad(kind=BASIC, light_map=orange), lit_and_filled(), textures
    )
    assert_almost_equal(baked.r, Float32(1 / pi), atol=1e-4)
    assert_almost_equal(baked.g, HALF_GRAY / Float32(pi), atol=1e-4)
    assert_almost_equal(baked.b, Float32(0), atol=1e-4)
    # An ao map dims the whole color, which is all indirect.
    var dimmed = physical_pixel(
        baked_quad(kind=BASIC, ao_map=gray), lit_and_filled(), textures
    )
    assert_almost_equal(dimmed.r, HALF_GRAY, atol=1e-4)
    var dark = physical_pixel(
        baked_quad(kind=BASIC, ao_map=black, light_map=orange),
        lit_and_filled(),
        textures,
    )
    assert_almost_equal(dark.r, Float32(0), atol=1e-4)


def test_the_baked_maps_read_the_second_coordinates() raises:
    # A map black on its left half and white on its right. The pixel sits
    # on the left of the first coordinates, and the second say right. A
    # map on `UV_CHANNEL_1` reads the second.
    var textures = TextureStore()
    var stepped = a_step_map()
    var first = textures.add(Texture(copy=stepped))
    stepped.channel = UV_CHANNEL_1
    var step = textures.add(stepped^)
    var right = physical_pixel(
        baked_quad(ao_map=step, second_u=0.9), filled(), textures
    )
    assert_almost_equal(right.r, Float32(0.5), atol=1e-4)
    var left = physical_pixel(
        baked_quad(ao_map=step, second_u=0.1), filled(), textures
    )
    assert_almost_equal(left.r, Float32(0), atol=1e-4)
    # On the first set, the same map reads the first pair: left.
    var on_first = physical_pixel(
        baked_quad(ao_map=first, second_u=0.9), filled(), textures
    )
    assert_almost_equal(on_first.r, Float32(0), atol=1e-4)
    # A map with a chain measures its footprint on the second pair too.
    var gray_chain = a_mipmapped_gray()
    gray_chain.channel = UV_CHANNEL_1
    var chained = textures.add(gray_chain^)
    var gray = physical_pixel(baked_quad(ao_map=chained), filled(), textures)
    assert_almost_equal(gray.r, 0.5 * HALF_GRAY, atol=1e-4)
    var banded = physical_pixel(
        baked_quad(ao_map=chained), filled(), textures, workers=4
    )
    assert_equal(banded.r, gray.r)


def test_a_physical_surface_occludes_its_indirect_light() raises:
    var textures = TextureStore()
    var gray = textures.add(a_data_texel(128, 128, 128))
    var white = textures.add(a_data_texel(255, 255, 255))
    # A white dielectric under the ambient light alone scatters a half.
    var bare = physical_pixel(baked_quad(kind=STANDARD), filled(), textures)
    assert_almost_equal(bare.r, Float32(0.5), atol=1e-4)
    var dimmed = physical_pixel(
        baked_quad(kind=STANDARD, ao_map=gray), filled(), textures
    )
    assert_almost_equal(dimmed.r, 0.5 * HALF_GRAY, atol=1e-4)
    # A light map joins the ambient light before the ao map dims both.
    var baked = physical_pixel(
        baked_quad(
            kind=PHYSICAL,
            ao_map=gray,
            light_map=white,
            light_map_intensity=FULL,
        ),
        filled(),
        textures,
    )
    assert_almost_equal(baked.r, 1.5 * HALF_GRAY, atol=1e-4)
    # A mirror's reflection is dimmed by the specular occlusion, which
    # keeps more of it than the gray alone would.
    var mirror = physical_pixel(
        baked_quad(
            kind=STANDARD, roughness=0, metalness=1, env=CubeTextureId(0)
        ),
        textures=textures,
    )
    var occluded = physical_pixel(
        baked_quad(
            kind=STANDARD,
            roughness=0,
            metalness=1,
            env=CubeTextureId(0),
            ao_map=gray,
        ),
        textures=textures,
    )
    var kept = specular_occlusion(1, HALF_GRAY, floored_roughness(0))
    assert_true(kept > HALF_GRAY)
    assert_almost_equal(occluded.g, mirror.g * kept, atol=1e-2)


def test_corners_that_disagree_about_their_baked_maps_are_rejected() raises:
    for corner in range(1, 3):
        for field in range(4):
            var quad = baked_quad(ao_map=TextureId(0), light_map=TextureId(1))
            if field == 0:
                quad[corner].ao_map = TextureId(2)
            elif field == 1:
                quad[corner].light_map = TextureId(2)
            elif field == 2:
                quad[corner].ao_map_intensity = 0.5
            else:
                quad[corner].light_map_intensity = 0.5
            with assert_raises(contains="baked maps"):
                check_triangle_state(quad[0], quad[1], quad[2])
    # An id nothing can hold.
    var ao = baked_quad(ao_map=TextureId(-2))
    with assert_raises(contains="ao map id"):
        check_triangle_state(ao[0], ao[1], ao[2])
    var light = baked_quad(light_map=TextureId(-2))
    with assert_raises(contains="light map id"):
        check_triangle_state(light[0], light[1], light[2])
    # An intensity that is negative or not a number.
    for wrong in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        var dim = baked_quad(ao_map=TextureId(0), ao_map_intensity=wrong)
        with assert_raises(contains="ao map intensity"):
            check_triangle_state(dim[0], dim[1], dim[2])
        var bright = baked_quad(
            light_map=TextureId(0), light_map_intensity=wrong
        )
        with assert_raises(contains="light map intensity"):
            check_triangle_state(bright[0], bright[1], bright[2])
    # Either map on a kind with no indirect term.
    for kind in [MATCAP, NORMALS, DEPTH, SHADOW]:
        var occluded = baked_quad(kind=kind, ao_map=TextureId(0))
        var lightened = baked_quad(kind=kind, light_map=TextureId(0))
        if kind == SHADOW:
            # A shadow surface blends wherever it is lit.
            for index in range(6):
                occluded[index].blend = BLEND
                lightened[index].blend = BLEND
        with assert_raises(contains="indirect term"):
            check_triangle_state(occluded[0], occluded[1], occluded[2])
        with assert_raises(contains="indirect term"):
            check_triangle_state(lightened[0], lightened[1], lightened[2])
    # A corner that says nothing names neither, and a basic one takes both.
    var corner = RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1))
    assert_equal(corner.ao_map, NO_TEXTURE)
    assert_equal(corner.light_map, NO_TEXTURE)
    assert_equal(corner.ao_map_intensity, Float32(1))
    assert_equal(corner.light_map_intensity, Float32(1))
    assert_equal(corner.u1, Float32(0))
    assert_equal(corner.v1, Float32(0))
    var basic = baked_quad(
        kind=BASIC,
        ao_map=TextureId(0),
        light_map=TextureId(1),
        ao_map_intensity=0,
        light_map_intensity=0,
    )
    check_triangle_state(basic[0], basic[1], basic[2])


def test_a_baked_map_stored_the_wrong_way_is_refused() raises:
    var textures = TextureStore()
    var encoded = textures.add(
        Texture(
            1,
            1,
            [UInt8(255), 255, 255, 255],
            REPEAT,
            NEAREST,
            SRGB,
            False,
            IGNORED,
        )
    )
    var covered = textures.add(
        Texture(
            1,
            1,
            [UInt8(255), 255, 255, 255],
            REPEAT,
            NEAREST,
            LINEAR,
            False,
            COVERAGE,
        )
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    # An ao map holds data, and says so twice.
    for wrong in [encoded, covered]:
        var quad = baked_quad(ao_map=wrong)
        with assert_raises(contains="An ao map"):
            rasterize_all(quad, target, SHADE_TEXTURE, textures)
        rasterize_all(quad, target, SHADE_LIT, textures)
    # A light map holds light, in either space, but ignores its alpha.
    var lit = baked_quad(light_map=covered)
    with assert_raises(contains="A light map must ignore"):
        rasterize_all(lit, target, SHADE_TEXTURE, textures)
    rasterize_all(lit, target, SHADE_LIT, textures)
    rasterize_all(
        baked_quad(light_map=encoded), target, SHADE_TEXTURE, textures
    )
    with assert_raises(contains="A light map must ignore"):
        check_light_map(textures.get(covered))
    check_light_map(textures.get(encoded))


# --- specular maps ----------------------------------------------------------


def with_specular_map(
    corners: List[RasterVertex], map: TextureId
) -> List[RasterVertex]:
    """Return `corners` with every corner naming `map` as its specular map."""
    var mapped = corners.copy()
    for index in range(len(mapped)):
        mapped[index].specular_map = map
    return mapped^


def strength_pixel(
    corners: List[RasterVertex],
    textures: TextureStore,
    lighting: Lighting,
    mode: ShadeMode = SHADE_TEXTURE,
) raises -> FloatColor:
    """Draw `corners` over the cube store and return the linear light at
    the center of the eight-pixel target."""
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_all(
        corners, target, mode, textures, lighting, cubes=a_cube_store()
    )
    return target.color_at(4, 4)


def test_a_corner_names_no_specular_map_unless_asked() raises:
    var corner = RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1))
    assert_equal(corner.specular_map, NO_TEXTURE)


def test_a_specular_map_scales_the_highlight_by_its_red() raises:
    # three.js's `specularmap_fragment`: the red channel is the
    # `specularStrength` the phong highlight is multiplied by. A black
    # base color and no ambient leave the highlight alone in the pixel.
    var lighting = lit_along_z_from(4)
    var textures = TextureStore()
    var none = textures.add(a_data_texel(0, 255, 255))
    var half = textures.add(a_data_texel(128, 0, 0))
    var full = textures.add(a_data_texel(255, 0, 0))
    var sheen = FloatColor(0.1, 0.1, 0.1)
    var plain = strength_pixel(
        black_phong_quad(sheen, 30.0), textures, lighting
    )
    assert_true(plain.r > 0.1, "the highlight is too dim to measure")
    var dark = strength_pixel(
        with_specular_map(black_phong_quad(sheen, 30.0), none),
        textures,
        lighting,
    )
    assert_equal(dark.r, Float32(0))
    var halved = strength_pixel(
        with_specular_map(black_phong_quad(sheen, 30.0), half),
        textures,
        lighting,
    )
    assert_almost_equal(halved.r, plain.r * 128 / 255, atol=1e-5)
    var whole = strength_pixel(
        with_specular_map(black_phong_quad(sheen, 30.0), full),
        textures,
        lighting,
    )
    assert_equal(whole.r, plain.r)
    # Lit shading opens no texture, so the map changes nothing there.
    var unopened = strength_pixel(
        with_specular_map(black_phong_quad(sheen, 30.0), none),
        textures,
        lighting,
        SHADE_LIT,
    )
    var lit = strength_pixel(
        black_phong_quad(sheen, 30.0), textures, lighting, SHADE_LIT
    )
    assert_equal(unopened.r, lit.r)


def test_a_specular_map_scales_the_reflectivity_by_its_red() raises:
    # three.js's `envmap_fragment` joins the reflection by
    # `specularStrength * reflectivity`, on a basic, lambert or phong
    # surface alike. Red plus cyan added is white; a map of zero red
    # leaves red, and a half map is a reflectivity of a half.
    var lighting = lit_along_z_from(3)
    var textures = TextureStore()
    var none = textures.add(a_data_texel(0, 255, 255))
    var half = textures.add(a_data_texel(128, 0, 0))
    var red = FloatColor(1, 0, 0)
    for kind in [BASIC, LAMBERT, PHONG]:
        var added = mirror_quad(color=red, combine=ADD_OPERATION, kind=kind)
        var bright = strength_pixel(added, textures, lighting)
        assert_true(bright.g > 0.5, "the reflection was not added")
        var kept = strength_pixel(
            with_specular_map(added, none), textures, lighting
        )
        assert_equal(kept.g, Float32(0))
        var mixed = strength_pixel(
            with_specular_map(
                mirror_quad(color=red, combine=MIX_OPERATION, kind=kind), half
            ),
            textures,
            lighting,
        )
        var expected = strength_pixel(
            mirror_quad(
                color=red,
                combine=MIX_OPERATION,
                kind=kind,
                reflectivity=Float32(128) / 255,
            ),
            textures,
            lighting,
        )
        # Equal but for rounding: the texel and the product round apart.
        assert_almost_equal(mixed.r, expected.r, atol=1e-4)
        assert_almost_equal(mixed.g, expected.g, atol=1e-4)
        assert_almost_equal(mixed.b, expected.b, atol=1e-4)


def test_a_specular_map_is_refused_where_nothing_reads_it() raises:
    # Corners that disagree, an id nothing can hold, and a kind three.js
    # gives no specular map.
    for corner in [1, 2]:
        var split = black_phong_quad(FloatColor(0.1, 0.1, 0.1), 30.0)
        split[corner].specular_map = TextureId(0)
        with assert_raises(contains="disagree about their maps"):
            check_triangle_state(split[0], split[1], split[2])
    var held = with_specular_map(
        black_phong_quad(FloatColor(0.1, 0.1, 0.1), 30.0), TextureId(-2)
    )
    with assert_raises(contains="specular map id"):
        check_triangle_state(held[0], held[1], held[2])
    for kind in [TOON, MATCAP, STANDARD, PHYSICAL, NORMALS, DEPTH]:
        var corners = List[RasterVertex]()
        for _ in range(3):
            corners.append(
                RasterVertex(
                    0,
                    0,
                    0.5,
                    1,
                    FloatColor(1, 1, 1),
                    kind=kind,
                    specular_map=TextureId(0),
                )
            )
        with assert_raises(contains="reads a specular map"):
            check_triangle_state(corners[0], corners[1], corners[2])
    for kind in [BASIC, LAMBERT, PHONG]:
        assert_true(kind.has_specular_map())
        var corners = List[RasterVertex]()
        for _ in range(3):
            corners.append(
                RasterVertex(
                    0,
                    0,
                    0.5,
                    1,
                    FloatColor(1, 1, 1),
                    kind=kind,
                    specular_map=TextureId(0),
                )
            )
        check_triangle_state(corners[0], corners[1], corners[2])


def test_a_specular_map_must_be_stored_as_data() raises:
    # Asked under the mode that opens it, on one worker and on four, and
    # not under lit shading, which opens none.
    var textures = TextureStore()
    var encoded = textures.add(
        Texture(
            1,
            1,
            [UInt8(255), 255, 255, 255],
            REPEAT,
            NEAREST,
            SRGB,
            False,
            IGNORED,
        )
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var quad = with_specular_map(
        black_phong_quad(FloatColor(0.1, 0.1, 0.1), 30.0), encoded
    )
    with assert_raises(contains="A specular map holds data"):
        rasterize_shaded(
            quad[0], quad[1], quad[2], target, SHADE_TEXTURE, textures
        )
    for workers in [1, 4]:
        with assert_raises(contains="A specular map holds data"):
            rasterize_all(
                quad, target, SHADE_TEXTURE, textures, workers=workers
            )
    rasterize_shaded(quad[0], quad[1], quad[2], target, SHADE_LIT, textures)
    var missing = with_specular_map(
        black_phong_quad(FloatColor(0.1, 0.1, 0.1), 30.0), TextureId(7)
    )
    with assert_raises():
        rasterize_all(missing, target, SHADE_TEXTURE, textures)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


# --- transmission -----------------------------------------------------------

from lights.lighting import environment_brdf
from math.matrix4 import Matrix4
from render.rasterizer import check_transmission, check_triangle_maps
from render.transmission import TransmissionTarget


def glass_quad(
    transmission: Float32 = 1,
    transmission_map: TextureId = NO_TEXTURE,
    thickness: Vector3 = Vector3(0, 0, 0),
    thickness_map: TextureId = NO_TEXTURE,
    attenuation_color: FloatColor = FloatColor(1.0, 1.0, 1.0),
    attenuation_distance: Float32 = inf[DType.float32](),
    dispersion: Float32 = 0,
    alpha: Float32 = 1,
    blend: Blending = OPAQUE,
) -> List[RasterVertex]:
    """Return `physical_quad` of a white, rough `PHYSICAL` surface with a
    volume, at an alpha."""
    var corners = physical_quad(
        PHYSICAL, color=FloatColor(1, 1, 1, alpha), roughness=0.5
    )
    for index in range(len(corners)):
        corners[index].transmission = transmission
        corners[index].transmission_map = transmission_map
        corners[index].thickness = thickness
        corners[index].thickness_map = thickness_map
        corners[index].attenuation_color = attenuation_color
        corners[index].attenuation_distance = attenuation_distance
        corners[index].dispersion = dispersion
        corners[index].blend = blend
    return corners^


def a_red_scene(alpha: UInt8 = 255) raises -> TransmissionTarget:
    """Return a flat red opaque scene to look through, 8x8."""
    return TransmissionTarget(
        RenderTarget(8, 8, Color(255, 0, 0, alpha)), Matrix4()
    )


def glass_pixel(
    corners: List[RasterVertex],
    scene: TransmissionTarget,
    textures: TextureStore = TextureStore(),
    mode: ShadeMode = SHADE_TEXTURE,
    workers: Int = 1,
    clear: Color = Color(0, 0, 0),
) raises -> FloatColor:
    """Draw `corners` looking through `scene` and return one pixel's light,
    premultiplied."""
    var target = RenderTarget(8, 8, clear)
    rasterize_all(
        corners,
        target,
        mode,
        textures,
        viewed_from_z(),
        workers,
        transmission=scene,
    )
    return target.color_at(3, 3)


def glass_reflectance() -> Vector3:
    """Return what a white dielectric at roughness 0.5 reflects head on
    from an environment, three.js's `EnvironmentBRDF`."""
    return environment_brdf(
        1, Vector3(0.04, 0.04, 0.04), 1, floored_roughness(0.5)
    )


def test_a_corner_holds_no_volume_unless_asked() raises:
    var corner = RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1))
    assert_equal(corner.transmission, Float32(0))
    assert_equal(corner.transmission_map, NO_TEXTURE)
    assert_equal(corner.thickness.x, Float32(0))
    assert_equal(corner.thickness_map, NO_TEXTURE)
    assert_equal(corner.attenuation_color.g, Float32(1))
    assert_equal(corner.attenuation_distance, inf[DType.float32]())
    assert_equal(corner.dispersion, Float32(0))
    assert_equal(corner.ior, Float32(1.5))


def test_a_transmissive_surface_shows_the_scene_behind_it() raises:
    # No light reaches the glass, so all it shows is the red scene through
    # it, less what it reflects: three.js's `(1 - F) * transmittance *
    # transmitted`, the diffuse light mixed all the way toward it.
    var scene = a_red_scene()
    var seen = glass_pixel(glass_quad(), scene)
    var reflected = glass_reflectance()
    assert_almost_equal(seen.r, 1 - reflected.x, atol=1e-3)
    assert_almost_equal(seen.g, 0, atol=1e-5)
    assert_almost_equal(seen.a, 1, atol=1e-5)
    # Half the transmission shows half of it, and none shows the dark
    # diffuse surface.
    var half = glass_pixel(glass_quad(0.5), scene)
    assert_almost_equal(half.r, (1 - reflected.x) / 2, atol=1e-3)
    var none = glass_pixel(glass_quad(0), scene)
    assert_almost_equal(none.r, 0, atol=1e-5)
    # The same on four workers, band by band.
    var banded = glass_pixel(glass_quad(), scene, workers=4)
    assert_equal(banded.r, seen.r)
    # With dispersion each channel reads its own index; on a flat scene
    # the red is where it was.
    var spread = glass_pixel(glass_quad(dispersion=3), scene)
    assert_almost_equal(spread.r, seen.r, atol=1e-3)


def test_a_volume_dims_the_light_it_carries() raises:
    # One meter of glass, looked through head on, that turns white light
    # half red after one meter: the red is halved.
    var scene = a_red_scene()
    var clear = glass_pixel(glass_quad(), scene)
    var tinted = glass_pixel(
        glass_quad(
            thickness=Vector3(1, 1, 1),
            attenuation_color=FloatColor(0.5, 1.0, 1.0),
            attenuation_distance=1,
        ),
        scene,
    )
    assert_almost_equal(tinted.r, clear.r * 0.5, atol=1e-3)


def test_the_volume_maps_multiply_the_transmission_and_the_thickness() raises:
    # The transmission map's red and the thickness map's green, sampled
    # under the mode that opens textures.
    var textures = TextureStore()
    var half = textures.add(a_data_texel(128, 0, 0))
    var thin = textures.add(a_data_texel(0, 0, 0))
    var scene = a_red_scene()
    var reflected = glass_reflectance()
    var mapped = glass_pixel(glass_quad(transmission_map=half), scene, textures)
    assert_almost_equal(mapped.r, (1 - reflected.x) * 128.0 / 255.0, atol=1e-3)
    var flat = glass_pixel(
        glass_quad(
            thickness=Vector3(1, 1, 1),
            thickness_map=thin,
            attenuation_color=FloatColor(0.5, 1.0, 1.0),
            attenuation_distance=1,
        ),
        scene,
        textures,
    )
    assert_almost_equal(flat.r, 1 - reflected.x, atol=1e-3)


def test_a_transmissive_surface_is_as_opaque_as_the_scene_behind() raises:
    # A blended glass over a half-transparent scene: three.js's
    # `1 - (1 - a) * transmittance`, the alpha mixed toward it.
    var scene = a_red_scene(128)
    var seen = glass_pixel(
        glass_quad(blend=BLEND), scene, clear=Color(0, 0, 0, 0)
    )
    assert_almost_equal(seen.a, 128.0 / 255.0, atol=1e-3)


def test_a_transmissive_triangle_needs_a_scene_under_the_texture_mode() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var quad = glass_quad()
    with assert_raises(contains="needs the opaque scene"):
        rasterize_shaded(quad[0], quad[1], quad[2], target, SHADE_TEXTURE)
    for workers in [1, 4]:
        with assert_raises(contains="needs the opaque scene"):
            rasterize_all(quad, target, SHADE_TEXTURE, workers=workers)
    # Lit shading opens no texture, so the glass is drawn as it is.
    rasterize_all(quad, target, SHADE_LIT)
    check_transmission(quad[0], SHADE_TEXTURE, True)
    check_transmission(glass_quad(0)[0], SHADE_TEXTURE, False)
    # A triangle no draw names is not asked, and a run of no triangles
    # or of segments asks nothing.
    var draws: List[Draw] = [
        Draw(DRAW_TRIANGLES, 0, 0),
        Draw(DRAW_SEGMENTS, 0, 0),
    ]
    rasterize_frame(quad, List[RasterVertex](), draws, target, SHADE_TEXTURE)


def test_a_volume_is_checked_like_the_rest_of_a_triangle() raises:
    var quad = glass_quad()
    check_triangle_state(quad[0], quad[1], quad[2])
    for wrong in [nan[DType.float32](), Float32(-0.5), Float32(2)]:
        var bad = glass_quad(wrong)
        with assert_raises(contains="transmission must be between"):
            check_triangle_state(bad[0], bad[1], bad[2])
    var deep = glass_quad(thickness=Vector3(0, -1, 0))
    with assert_raises(contains="thickness cannot be negative"):
        check_triangle_state(deep[0], deep[1], deep[2])
    var tinted = glass_quad(attenuation_color=FloatColor(1, -1, 1))
    with assert_raises(contains="attenuation color cannot be negative"):
        check_triangle_state(tinted[0], tinted[1], tinted[2])
    for wrong in [nan[DType.float32](), Float32(0)]:
        var far = glass_quad(attenuation_distance=wrong)
        with assert_raises(contains="attenuation distance must be above"):
            check_triangle_state(far[0], far[1], far[2])
    for wrong in [nan[DType.float32](), Float32(-1)]:
        var spread = glass_quad(dispersion=wrong)
        with assert_raises(contains="dispersion cannot be negative"):
            check_triangle_state(spread[0], spread[1], spread[2])
    for wrong in [nan[DType.float32](), Float32(0.5), Float32(3)]:
        var bent = glass_quad()
        bent[0].ior = wrong
        with assert_raises(contains="index of refraction must be between"):
            check_triangle_state(bent[0], bent[1], bent[2])
    var second = glass_quad()
    second[1].dispersion = 1
    with assert_raises(contains="disagree about their volume"):
        check_triangle_state(second[0], second[1], second[2])
    var third = glass_quad()
    third[2].ior = 1.4
    with assert_raises(contains="disagree about their volume"):
        check_triangle_state(third[0], third[1], third[2])
    var through = glass_quad(transmission_map=TextureId(-5))
    with assert_raises(contains="transmission map id"):
        check_triangle_state(through[0], through[1], through[2])
    var thick = glass_quad(thickness_map=TextureId(-5))
    with assert_raises(contains="thickness map id"):
        check_triangle_state(thick[0], thick[1], thick[2])
    var mapped = glass_quad(
        transmission_map=TextureId(1), thickness_map=TextureId(2)
    )
    check_triangle_state(mapped[0], mapped[1], mapped[2])
    var standard = glass_quad()
    for index in range(len(standard)):
        standard[index].kind = STANDARD
    with assert_raises(contains="Only a physical triangle transmits"):
        check_triangle_state(standard[0], standard[1], standard[2])


def test_a_volume_map_must_be_stored_as_data() raises:
    var textures = TextureStore()
    var encoded = textures.add(
        Texture(1, 1, [UInt8(255), 255, 255, 255], REPEAT, NEAREST, SRGB, False)
    )
    with assert_raises(contains="A transmission map holds data"):
        check_triangle_maps(
            glass_quad(transmission_map=encoded)[0], SHADE_TEXTURE, textures
        )
    with assert_raises(contains="A thickness map holds data"):
        check_triangle_maps(
            glass_quad(thickness_map=encoded)[0], SHADE_TEXTURE, textures
        )
    check_triangle_maps(
        glass_quad(transmission_map=encoded)[0], SHADE_LIT, textures
    )


# --- sheen, iridescence and anisotropy ---------------------------------------


def with_layers(
    corners: List[RasterVertex], layers: LayerFactors
) -> List[RasterVertex]:
    """Return `corners` with every corner carrying `layers`."""
    var layered = corners.copy()
    for index in range(len(layered)):
        layered[index].layers = layers
    return layered^


def lit_obliquely() raises -> Lighting:
    """Return one white directional light from forty-five degrees off the
    z axis, with the camera far up it."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(1, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, FULL))
    scene.update()
    return Lighting(scene, Layers.all(), Vector3(0, 0, 400))


def a_layer_texel(r: UInt8, g: UInt8, b: UInt8, a: UInt8) raises -> Texture:
    """Return a one-texel linear map whose alpha is read."""
    return Texture(1, 1, [r, g, b, a], REPEAT, NEAREST, LINEAR, False, COVERAGE)


def test_a_corner_has_no_sheen_film_or_stretch_unless_asked() raises:
    var corner = RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1))
    assert_false(corner.layers.is_layered())
    assert_false(corner.layers.is_anisotropic())
    assert_equal(corner.layers.iridescence_ior, Float32(1.3))
    assert_equal(corner.layers.thickness_maximum, Float32(400))
    assert_equal(corner.layers.sheen_color_map, NO_TEXTURE)


def test_layer_factors_agree_only_when_every_field_does() raises:
    var plain = LayerFactors()
    assert_true(plain.agrees(LayerFactors()))
    var other = LayerFactors()
    other.anisotropy_map = TextureId(3)
    assert_false(plain.agrees(other))
    assert_true(other.is_layered())
    var turned = LayerFactors()
    turned.anisotropy = Vector2(0, 0.5)
    assert_true(turned.is_anisotropic())
    turned.anisotropy = Vector2(0.5, 0)
    assert_true(turned.is_anisotropic())


def test_layer_factors_no_material_can_hold_are_refused() raises:
    var nan32 = nan[DType.float32]()
    var cases = List[LayerFactors]()
    for bad in [Float32(-0.1), nan32]:
        var sheen = LayerFactors()
        sheen.sheen_color = Vector3(0, bad, 0)
        cases.append(sheen)
    for bad in [Float32(-0.1), Float32(1.1), nan32]:
        var cloth = LayerFactors()
        cloth.sheen_roughness = bad
        cases.append(cloth)
        var film = LayerFactors()
        film.iridescence = bad
        cases.append(film)
    for bad in [Float32(0.9), Float32(2.5), nan32]:
        var index = LayerFactors()
        index.iridescence_ior = bad
        cases.append(index)
    for bad in [Float32(-1), nan32]:
        var thin = LayerFactors()
        thin.thickness_minimum = bad
        cases.append(thin)
        var thick = LayerFactors()
        thick.thickness_maximum = bad
        cases.append(thick)
    for bad in [Float32(1.5), nan32]:
        var stretch = LayerFactors()
        stretch.anisotropy = Vector2(bad, 0)
        cases.append(stretch)
    for field in range(5):
        var mapped = LayerFactors()
        if field == 0:
            mapped.sheen_color_map = TextureId(-2)
        elif field == 1:
            mapped.sheen_roughness_map = TextureId(-2)
        elif field == 2:
            mapped.iridescence_map = TextureId(-2)
        elif field == 3:
            mapped.thickness_map = TextureId(-2)
        else:
            mapped.anisotropy_map = TextureId(-2)
        cases.append(mapped)
    for index in range(len(cases)):
        with assert_raises():
            cases[index].check()
        var quad = with_layers(physical_quad(kind=PHYSICAL), cases[index])
        with assert_raises():
            check_triangle_state(quad[0], quad[1], quad[2])
    LayerFactors().check()


def test_a_layered_triangle_must_agree_and_be_physical() raises:
    var layers = LayerFactors()
    layers.iridescence = 0.5
    var good = with_layers(physical_quad(kind=PHYSICAL), layers)
    check_triangle_state(good[0], good[1], good[2])
    var split = good.copy()
    split[1].layers = LayerFactors()
    with assert_raises(contains="disagree about their sheen"):
        check_triangle_state(split[0], split[1], split[2])
    split = good.copy()
    split[2].layers = LayerFactors()
    with assert_raises(contains="disagree about their sheen"):
        check_triangle_state(split[0], split[1], split[2])
    var standard = with_layers(physical_quad(kind=STANDARD), layers)
    with assert_raises(contains="Only a physical triangle has a sheen"):
        check_triangle_state(standard[0], standard[1], standard[2])


def test_the_tangent_frame_follows_the_coordinates() raises:
    # u grows along x and v along y: the frame is the world's own axes.
    var frame = tangent_frame(
        Vector3(0, 0, 1),
        Vector3(0.5, 0, 0),
        Vector3(0, 0.5, 0),
        Vector2(0.25, 0),
        Vector2(0, 0.25),
    )
    assert_almost_equal(frame.tangent.x, Float32(1), atol=1e-6)
    assert_almost_equal(frame.bitangent.y, Float32(1), atol=1e-6)
    # Coordinates that do not change make no frame at all.
    var none = tangent_frame(
        Vector3(0, 0, 1),
        Vector3(0.5, 0, 0),
        Vector3(0, 0.5, 0),
        Vector2(0, 0),
        Vector2(0, 0),
    )
    assert_equal(none.tangent.x, Float32(0))
    assert_equal(none.bitangent.y, Float32(0))


def test_a_sheen_dims_what_is_under_it_and_adds_its_own_lobe() raises:
    var lighting = lit_obliquely()
    var chalk = physical_pixel(physical_quad(kind=PHYSICAL), lighting)
    var layers = LayerFactors()
    layers.sheen_color = Vector3(1, 0, 0)
    layers.sheen_roughness = 0.5
    var cloth = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL), layers), lighting
    )
    # Green has no sheen: only the albedo scaling reaches it.
    assert_almost_equal(cloth.g, chalk.g * 0.843, atol=1e-4)
    # Red has both, so it is brighter than green.
    assert_true(cloth.r > cloth.g, "the sheen added no light")
    # The same under lit shading and on four workers.
    var lit = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL), layers),
        lighting,
        mode=SHADE_LIT,
    )
    assert_equal(lit.r, cloth.r)
    var banded = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL), layers), lighting, workers=4
    )
    assert_equal(banded.r, cloth.r)


def test_the_sheen_maps_tint_it_and_roughen_it() raises:
    var lighting = lit_obliquely()
    var textures = TextureStore()
    var black = textures.add(a_data_texel(0, 0, 0))
    var smooth = textures.add(a_layer_texel(255, 255, 255, 40))
    var chalk = physical_pixel(physical_quad(kind=PHYSICAL), lighting, textures)
    var layers = LayerFactors()
    layers.sheen_color = Vector3(1, 1, 1)
    layers.sheen_roughness = 1
    var cloth = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL), layers), lighting, textures
    )
    # A black sheen color map turns the sheen off altogether.
    var tinted = layers
    tinted.sheen_color_map = black
    var dark = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL), tinted), lighting, textures
    )
    assert_equal(dark.r, chalk.r)
    # A low alpha makes the sheen smoother, which changes its lobe.
    var roughened = layers
    roughened.sheen_roughness_map = smooth
    var glossy = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL), roughened), lighting, textures
    )
    assert_true(abs(glossy.r - cloth.r) > 1e-4, "the alpha changed nothing")
    # Neither is read under lit shading.
    var ignored = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL), tinted),
        lighting,
        textures,
        mode=SHADE_LIT,
    )
    assert_equal(ignored.r, cloth.r)


def test_a_film_colors_the_lobe_and_its_maps_thin_it() raises:
    var lighting = lit_along_z_from(400)
    var textures = TextureStore()
    var black = textures.add(a_data_texel(0, 0, 0))
    var plain = physical_pixel(
        physical_quad(kind=PHYSICAL, roughness=0.3), lighting, textures
    )
    var layers = LayerFactors()
    layers.iridescence = 1
    var film = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL, roughness=0.3), layers),
        lighting,
        textures,
    )
    assert_true(abs(film.b - plain.b) > 1e-3, "the film changed nothing")
    # A black iridescence map takes the film away.
    var faded = layers
    faded.iridescence_map = black
    var bare = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL, roughness=0.3), faded),
        lighting,
        textures,
    )
    assert_equal(bare.b, plain.b)
    # So does a thickness map's green of zero over a range from zero.
    var thinned = layers
    thinned.thickness_map = black
    thinned.thickness_minimum = 0
    var thin = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL, roughness=0.3), thinned),
        lighting,
        textures,
    )
    assert_equal(thin.b, plain.b)


def test_a_stretch_changes_the_lobe_and_its_map_can_undo_it() raises:
    var lighting = lit_obliquely()
    var textures = TextureStore()
    var none = textures.add(a_data_texel(255, 128, 0))
    var plain = physical_pixel(
        physical_quad(kind=PHYSICAL, roughness=0.3), lighting, textures
    )
    var layers = LayerFactors()
    layers.anisotropy = Vector2(1, 0)
    var stretched = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL, roughness=0.3), layers),
        lighting,
        textures,
    )
    assert_true(
        abs(stretched.r - plain.r) > 1e-3, "the stretch changed nothing"
    )
    # Read under lit shading too: the stretch is a number.
    var lit = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL, roughness=0.3), layers),
        lighting,
        textures,
        mode=SHADE_LIT,
    )
    assert_equal(lit.r, stretched.r)
    # A map of no strength leaves the lobe as an even one along the
    # frame, which here is the world's own axes.
    var undone = layers
    undone.anisotropy_map = none
    var even = physical_pixel(
        with_layers(physical_quad(kind=PHYSICAL, roughness=0.3), undone),
        lighting,
        textures,
    )
    assert_almost_equal(even.r, plain.r, atol=1e-4)


def test_a_stretched_surface_reads_its_environment_along_a_bent_normal() raises:
    # Seen from well off to the side, along the stretch: the bent normal
    # leans toward the eye, and a smooth metal reads another part of the
    # cube than the plain one does.
    var lighting = viewed_from_z()
    lighting.eye = Vector3(400, 0, 300)
    var plain = physical_pixel(
        physical_quad(
            kind=PHYSICAL, roughness=0.2, metalness=1, env=CubeTextureId(0)
        ),
        lighting,
    )
    var layers = LayerFactors()
    layers.anisotropy = Vector2(1, 0)
    var bent = physical_pixel(
        with_layers(
            physical_quad(
                kind=PHYSICAL, roughness=0.2, metalness=1, env=CubeTextureId(0)
            ),
            layers,
        ),
        lighting,
    )
    assert_true(
        abs(bent.r - plain.r) + abs(bent.g - plain.g) + abs(bent.b - plain.b)
        > 1e-3,
        "the bent normal read the same environment",
    )


def test_a_layer_map_must_be_stored_as_it_is_read() raises:
    var textures = TextureStore()
    var coverage_color = textures.add(
        Texture(1, 1, [UInt8(255), 255, 255, 255], REPEAT, NEAREST, SRGB, False)
    )
    var ignored_linear = textures.add(a_data_texel(255, 255, 255))
    var covered_srgb = textures.add(
        Texture(
            1,
            1,
            [UInt8(255), 255, 255, 255],
            REPEAT,
            NEAREST,
            SRGB,
            False,
            COVERAGE,
        )
    )
    var covered_linear = textures.add(a_layer_texel(255, 255, 255, 255))
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var sheen = LayerFactors()
    sheen.sheen_color = Vector3(1, 1, 1)
    sheen.sheen_color_map = coverage_color
    var quad = with_layers(physical_quad(kind=PHYSICAL), sheen)
    with assert_raises(contains="A sheen color map must ignore its alpha"):
        rasterize_all(quad, target, SHADE_TEXTURE, textures)
    rasterize_all(quad, target, SHADE_LIT, textures)
    sheen.sheen_color_map = ignored_linear
    rasterize_all(
        with_layers(physical_quad(kind=PHYSICAL), sheen),
        target,
        SHADE_TEXTURE,
        textures,
    )
    var cloth = LayerFactors()
    cloth.sheen_color = Vector3(1, 1, 1)
    cloth.sheen_roughness_map = covered_srgb
    with assert_raises(contains="A sheen roughness map holds data"):
        rasterize_all(
            with_layers(physical_quad(kind=PHYSICAL), cloth),
            target,
            SHADE_TEXTURE,
            textures,
        )
    cloth.sheen_roughness_map = ignored_linear
    with assert_raises(contains="is read from its alpha"):
        rasterize_all(
            with_layers(physical_quad(kind=PHYSICAL), cloth),
            target,
            SHADE_TEXTURE,
            textures,
        )
    cloth.sheen_roughness_map = covered_linear
    rasterize_all(
        with_layers(physical_quad(kind=PHYSICAL), cloth),
        target,
        SHADE_TEXTURE,
        textures,
    )
    var film = LayerFactors()
    film.iridescence = 1
    film.iridescence_map = covered_linear
    with assert_raises(contains="An iridescence map must ignore"):
        rasterize_all(
            with_layers(physical_quad(kind=PHYSICAL), film),
            target,
            SHADE_TEXTURE,
            textures,
        )
    film.iridescence_map = NO_TEXTURE
    film.thickness_map = covered_linear
    with assert_raises(contains="An iridescence thickness map must ignore"):
        rasterize_all(
            with_layers(physical_quad(kind=PHYSICAL), film),
            target,
            SHADE_TEXTURE,
            textures,
        )
    var stretch = LayerFactors()
    stretch.anisotropy = Vector2(1, 0)
    stretch.anisotropy_map = covered_linear
    with assert_raises(contains="An anisotropy map must ignore"):
        rasterize_all(
            with_layers(physical_quad(kind=PHYSICAL), stretch),
            target,
            SHADE_TEXTURE,
            textures,
        )


# --- specular and clearcoat maps --------------------------------------------


def with_reflectance(
    corners: List[RasterVertex], specular: FloatColor, intensity: Float32
) -> List[RasterVertex]:
    """Return `corners` with every corner reflecting `specular` head on,
    scaled at a grazing angle by `intensity`."""
    var changed = corners.copy()
    for index in range(len(changed)):
        changed[index].specular = specular
        changed[index].specular_intensity = intensity
    return changed^


def test_layer_factors_carry_the_specular_and_coat_maps() raises:
    var plain = LayerFactors()
    assert_equal(plain.specular_color.x, Float32(1))
    assert_equal(plain.clearcoat_normal_scale.y, Float32(1))
    assert_false(plain.is_specular_mapped())
    for field in range(7):
        var other = LayerFactors()
        if field == 0:
            other.specular_color = Vector3(1, 0.5, 1)
        elif field == 1:
            other.clearcoat_normal_scale = Vector2(1, -1)
        elif field == 2:
            other.specular_intensity_map = TextureId(0)
        elif field == 3:
            other.specular_color_map = TextureId(0)
        elif field == 4:
            other.clearcoat_map = TextureId(0)
        elif field == 5:
            other.clearcoat_roughness_map = TextureId(0)
        else:
            other.clearcoat_normal_map = TextureId(0)
        assert_false(plain.agrees(other))
        assert_true(other.is_layered())
    var intensity = LayerFactors()
    intensity.specular_intensity_map = TextureId(0)
    assert_true(intensity.is_specular_mapped())
    var tint = LayerFactors()
    tint.specular_color_map = TextureId(0)
    assert_true(tint.is_specular_mapped())


def test_specular_and_coat_factors_no_material_can_hold_are_refused() raises:
    var nan32 = nan[DType.float32]()
    var cases = List[LayerFactors]()
    for bad in [Float32(-0.1), nan32]:
        var tint = LayerFactors()
        tint.specular_color = Vector3(1, bad, 1)
        cases.append(tint)
    var wide = LayerFactors()
    wide.clearcoat_normal_scale = Vector2(inf[DType.float32](), 1)
    cases.append(wide)
    var tall = LayerFactors()
    tall.clearcoat_normal_scale = Vector2(1, nan32)
    cases.append(tall)
    for field in range(5):
        var mapped = LayerFactors()
        if field == 0:
            mapped.specular_intensity_map = TextureId(-2)
        elif field == 1:
            mapped.specular_color_map = TextureId(-2)
        elif field == 2:
            mapped.clearcoat_map = TextureId(-2)
        elif field == 3:
            mapped.clearcoat_roughness_map = TextureId(-2)
        else:
            mapped.clearcoat_normal_map = TextureId(-2)
        cases.append(mapped)
    for index in range(len(cases)):
        with assert_raises():
            cases[index].check()
    with assert_raises(contains="specular or clearcoat map id"):
        cases[len(cases) - 1].check()
    # A standard triangle names none of them.
    var coat = LayerFactors()
    coat.clearcoat_map = TextureId(0)
    var standard = with_layers(physical_quad(kind=STANDARD), coat)
    with assert_raises(contains="or a specular or clearcoat map"):
        check_triangle_state(standard[0], standard[1], standard[2])


def test_the_specular_maps_set_the_reflectance_head_on() raises:
    var lighting = lit_along_z_from(400)
    var textures = TextureStore()
    var black = textures.add(
        Texture(
            1, 1, [UInt8(0), 0, 0, 255], REPEAT, NEAREST, SRGB, False, IGNORED
        )
    )
    var white = textures.add(a_data_texel(255, 255, 255))
    var clear = textures.add(a_layer_texel(255, 255, 255, 0))
    var opaque = textures.add(a_layer_texel(255, 255, 255, 255))
    var quad = physical_quad(kind=PHYSICAL, roughness=0.4, env=CubeTextureId(0))
    var plain = physical_pixel(quad, lighting, textures)
    # A black specular color map: nothing is reflected head on, though
    # the grazing reflectance stays the intensity, one.
    var tinted = LayerFactors()
    tinted.specular_color_map = black
    var dark = physical_pixel(with_layers(quad, tinted), lighting, textures)
    var none = physical_pixel(
        with_reflectance(quad, FloatColor(0, 0, 0), 1), lighting, textures
    )
    assert_equal(dark.r, none.r)
    assert_true(dark.r < plain.r, "the black specular color map did nothing")
    # An intensity map's alpha of zero: nothing is reflected at all.
    var faded = LayerFactors()
    faded.specular_intensity_map = clear
    var dull = physical_pixel(with_layers(quad, faded), lighting, textures)
    var nothing = physical_pixel(
        with_reflectance(quad, FloatColor(0, 0, 0), 0), lighting, textures
    )
    assert_equal(dull.r, nothing.r)
    # White maps change nothing: the reflectance is worked out again, to
    # what the corner already carried.
    var both = LayerFactors()
    both.specular_color_map = white
    both.specular_intensity_map = opaque
    var same = physical_pixel(with_layers(quad, both), lighting, textures)
    assert_almost_equal(same.r, plain.r, atol=1e-5)
    # Under lit shading no map is read, and the tint is the corner's.
    var lit = physical_pixel(
        with_layers(quad, tinted), lighting, textures, mode=SHADE_LIT
    )
    var lit_plain = physical_pixel(quad, lighting, textures, mode=SHADE_LIT)
    assert_almost_equal(lit.r, lit_plain.r, atol=1e-5)


def test_the_clearcoat_maps_scale_the_coat_and_its_roughness() raises:
    var lighting = lit_along_z_from(400)
    var textures = TextureStore()
    var none = textures.add(a_data_texel(0, 0, 0))
    var smooth = textures.add(a_data_texel(255, 0, 0))
    var bare = physical_pixel(
        physical_quad(color=FloatColor(0, 0, 0), kind=PHYSICAL),
        lighting,
        textures,
    )
    var coated = physical_quad(
        color=FloatColor(0, 0, 0),
        kind=PHYSICAL,
        clearcoat=1,
        clearcoat_roughness=0.8,
        env=CubeTextureId(0),
    )
    var matte = physical_pixel(coated, lighting, textures)
    # A clearcoat map's red of zero takes the coat away.
    var gone = LayerFactors()
    gone.clearcoat_map = none
    var uncoated = physical_pixel(
        with_layers(
            physical_quad(
                color=FloatColor(0, 0, 0), kind=PHYSICAL, clearcoat=1
            ),
            gone,
        ),
        lighting,
        textures,
    )
    assert_equal(uncoated.r, bare.r)
    # A roughness map's green of zero makes the coat as smooth as a
    # roughness of zero, and its red of one keeps the coat whole.
    var polished = LayerFactors()
    polished.clearcoat_map = smooth
    polished.clearcoat_roughness_map = smooth
    var glossy = physical_pixel(
        with_layers(coated, polished), lighting, textures
    )
    var smooth_coat = physical_pixel(
        physical_quad(
            color=FloatColor(0, 0, 0),
            kind=PHYSICAL,
            clearcoat=1,
            env=CubeTextureId(0),
        ),
        lighting,
        textures,
    )
    assert_equal(glossy.r, smooth_coat.r)
    assert_true(glossy.r > matte.r, "the roughness map did nothing")


def test_a_clearcoat_normal_map_turns_the_coat_alone() raises:
    # The rough black metal of the test above: a coat normal map turned
    # well away from the lamp takes the coat's gloss off the center, and
    # a flat one leaves it.
    var textures = TextureStore()
    var toward_x = textures.add(a_data_texel(255, 128, 128))
    var flat = textures.add(a_data_texel(128, 128, 255))
    var lighting = lit_along_z_from(400)
    var quad = physical_quad(
        kind=PHYSICAL,
        color=FloatColor(0, 0, 0),
        metalness=1,
        roughness=1,
        clearcoat=1,
        clearcoat_roughness=0.5,
    )
    var upright = physical_pixel(quad, lighting, textures)
    var turned = LayerFactors()
    turned.clearcoat_normal_map = toward_x
    var away = physical_pixel(with_layers(quad, turned), lighting, textures)
    assert_true(away.r < upright.r * 0.5, "the coat's normal did not turn")
    var level = LayerFactors()
    level.clearcoat_normal_map = flat
    var still = physical_pixel(with_layers(quad, level), lighting, textures)
    assert_almost_equal(still.r, upright.r, rtol=0.01)
    # The scale is applied before the frame: a scale of zero flattens it.
    var flattened = turned
    flattened.clearcoat_normal_scale = Vector2(0, 0)
    var level_again = physical_pixel(
        with_layers(quad, flattened), lighting, textures
    )
    assert_almost_equal(level_again.r, upright.r, atol=1e-4)
    # Under lit shading the map is not read.
    var lit = physical_pixel(
        with_layers(quad, turned), lighting, textures, mode=SHADE_LIT
    )
    var lit_upright = physical_pixel(quad, lighting, textures, mode=SHADE_LIT)
    assert_equal(lit.r, lit_upright.r)
    # And without a coat, the map is read and changes nothing.
    var uncoated = physical_quad(
        kind=PHYSICAL, color=FloatColor(0, 0, 0), metalness=1, roughness=1
    )
    assert_equal(
        physical_pixel(with_layers(uncoated, turned), lighting, textures).r,
        physical_pixel(uncoated, lighting, textures).r,
    )


def test_a_specular_or_coat_map_must_be_stored_as_it_is_read() raises:
    var textures = TextureStore()
    var coverage_color = textures.add(
        Texture(1, 1, [UInt8(255), 255, 255, 255], REPEAT, NEAREST, SRGB, False)
    )
    var ignored_linear = textures.add(a_data_texel(255, 255, 255))
    var covered_srgb = textures.add(
        Texture(
            1,
            1,
            [UInt8(255), 255, 255, 255],
            REPEAT,
            NEAREST,
            SRGB,
            False,
            COVERAGE,
        )
    )
    var covered_linear = textures.add(a_layer_texel(255, 255, 255, 255))
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var quad = physical_quad(kind=PHYSICAL, clearcoat=1)
    var tint = LayerFactors()
    tint.specular_color_map = coverage_color
    with assert_raises(contains="A specular color map must ignore its alpha"):
        rasterize_all(with_layers(quad, tint), target, SHADE_TEXTURE, textures)
    rasterize_all(with_layers(quad, tint), target, SHADE_LIT, textures)
    var intensity = LayerFactors()
    intensity.specular_intensity_map = covered_srgb
    with assert_raises(contains="A specular intensity map holds data"):
        rasterize_all(
            with_layers(quad, intensity), target, SHADE_TEXTURE, textures
        )
    intensity.specular_intensity_map = ignored_linear
    with assert_raises(contains="is read from its alpha"):
        rasterize_all(
            with_layers(quad, intensity), target, SHADE_TEXTURE, textures
        )
    for field in range(3):
        var coat = LayerFactors()
        if field == 0:
            coat.clearcoat_map = covered_linear
        elif field == 1:
            coat.clearcoat_roughness_map = covered_linear
        else:
            coat.clearcoat_normal_map = covered_linear
        with assert_raises(contains="must ignore"):
            rasterize_all(
                with_layers(quad, coat), target, SHADE_TEXTURE, textures
            )


# --- each map at its own placement ------------------------------------------


def uv_quad(
    placement: UvPlacement,
    texture: TextureId,
    second: Bool = False,
    emissive_map: TextureId = NO_TEXTURE,
) -> List[RasterVertex]:
    """Return two unlit triangles over a sixteen-pixel target whose raw
    coordinates run over the unit square, each corner's pair moved by
    `placement` first. The raw pair rides the second set when `second`,
    with a decoy in the first."""
    var corners = List[RasterVertex]()
    var places: List[Tuple[Float32, Float32]] = [
        (Float32(0), Float32(0)),
        (Float32(16), Float32(0)),
        (Float32(16), Float32(16)),
        (Float32(0), Float32(0)),
        (Float32(16), Float32(16)),
        (Float32(0), Float32(16)),
    ]
    for place in places:
        var at = placement.moved(Vector2(place[0] / 16, 1 - place[1] / 16))
        var first = at
        var other = Vector2(0.3, 0.6)
        if second:
            first = Vector2(0.3, 0.6)
            other = at
        corners.append(
            RasterVertex(
                place[0],
                place[1],
                0.5,
                1,
                FloatColor(1, 1, 1),
                first.x,
                first.y,
                texture,
                kind=BASIC,
                u1=other.x,
                v1=other.y,
                emissive_map=emissive_map,
            )
        )
    return corners^


def drawn_quad(
    corners: List[RasterVertex], textures: TextureStore
) raises -> Framebuffer:
    """Draw `corners` textured into a sixteen-pixel target."""
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_all(corners, target, SHADE_TEXTURE, textures)
    return target.resolve()


def largest_difference(one: Framebuffer, two: Framebuffer) raises -> Int:
    """Return the largest difference of any channel of any pixel."""
    var most = 0
    for y in range(one.height):
        for x in range(one.width):
            var p = one.get_pixel(x, y)
            var q = two.get_pixel(x, y)
            most = max(most, abs(Int(p.r) - Int(q.r)))
            most = max(most, abs(Int(p.g) - Int(q.g)))
            most = max(most, abs(Int(p.b) - Int(q.b)))
    return most


def test_a_map_is_placed_at_the_fragment_as_three_js_places_it() raises:
    # Moving the raw pair at the fragment by the map's matrix draws what
    # moving each corner's pair draws, as three.js moves it in the vertex
    # shader: the matrix is linear. Mipmapped and filtered, so the
    # footprint is measured on the placed pair too.
    var textures = TextureStore()
    var board = checkerboard(
        8, 4, Color(240, 60, 20), Color(20, 40, 200), REPEAT
    )
    var still = textures.add(Texture(copy=board))
    board.repeat = Vector2(2, 1.5)
    board.rotation = Angle(30.0, DEGREE)
    board.center = Vector2(0.5, 0.5)
    board.offset = Vector2(0.1, -0.2)
    var placement = board.placement()
    board.channel = UV_CHANNEL_1
    var on_second = textures.add(Texture(copy=board))
    board.channel = UvChannel(0)
    var moved = textures.add(board^)
    var by_corner = drawn_quad(uv_quad(placement, still), textures)
    var by_fragment = drawn_quad(uv_quad(UvPlacement(), moved), textures)
    var by_second = drawn_quad(
        uv_quad(UvPlacement(), on_second, second=True), textures
    )
    assert_true(largest_difference(by_corner, by_fragment) <= 1)
    assert_true(largest_difference(by_corner, by_second) <= 1)
    # And the pattern really moved.
    var raw = drawn_quad(uv_quad(UvPlacement(), still), textures)
    assert_true(largest_difference(raw, by_fragment) > 100)


def test_two_maps_of_one_triangle_are_placed_apart() raises:
    # A map on the first set as it is and an emissive map on the second,
    # tiled: each reads its own pair through its own matrix, so the glow
    # matches the glow a corner-moved pair gives.
    var textures = TextureStore()
    var white = textures.add(a_data_texel(255, 255, 255))
    var glow = checkerboard(
        4, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
    ).ignoring_alpha()
    var still = textures.add(Texture(copy=glow))
    glow.repeat = Vector2(3, 2)
    var placement = glow.placement()
    glow.channel = UV_CHANNEL_1
    var tiled = textures.add(glow^)
    var apart = uv_quad(UvPlacement(), white, True, tiled)
    var together = uv_quad(placement, white, True, still)
    for index in range(len(apart)):
        apart[index].kind = LAMBERT
        apart[index].emissive = FloatColor(1, 1, 1)
        together[index].kind = LAMBERT
        together[index].emissive = FloatColor(1, 1, 1)
        together[index].u = together[index].u1
        together[index].v = together[index].v1
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_all(apart, target, SHADE_TEXTURE, textures, Lighting.uniform())
    var expected = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_all(
        together, expected, SHADE_TEXTURE, textures, Lighting.uniform()
    )
    assert_true(largest_difference(target.resolve(), expected.resolve()) <= 1)


def test_a_map_with_a_channel_that_is_neither_is_refused() raises:
    var textures = TextureStore()
    var odd = a_data_texel(255, 255, 255)
    odd.channel = UvChannel(4)
    var id = textures.add(odd^)
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    with assert_raises(contains="channel must be"):
        rasterize_all(
            uv_quad(UvPlacement(), id), target, SHADE_TEXTURE, textures
        )
    # The uv view opens no map, so it asks nothing.
    rasterize_all(uv_quad(UvPlacement(), id), target, SHADE_UV, textures)


def bent_quad(
    roughness: Float32, curved: Bool, clearcoat: Float32 = 0
) -> List[RasterVertex]:
    """Return `physical_quad` at a roughness, its normals fanned out across
    the eight pixels when `curved`, so the normal turns about a tenth a
    pixel, and all facing +z otherwise."""
    var corners = physical_quad(
        kind=PHYSICAL,
        roughness=roughness,
        clearcoat=clearcoat,
        clearcoat_roughness=roughness,
    )
    if not curved:
        return corners^
    for index in range(len(corners)):
        var across = corners[index].x / 8 - 0.5
        var down = corners[index].y / 8 - 0.5
        corners[index].normal = Vector3(1.2 * across, -1.2 * down, 0.8)
    return corners^


def test_a_curved_surface_is_rougher_by_its_curve() raises:
    # three.js adds the geometric roughness after the floor and caps the
    # sum at one. On a surface whose normal turns about a tenth a pixel,
    # an authored 0.95 and an authored one both reach one, so they draw
    # alike; a flat surface keeps them apart, and a curved 0.5 stays
    # below one.
    var lighting = lit_obliquely()
    for pixel in range(3):
        var rough = physical_pixel(bent_quad(1, True), lighting, x=pixel + 2)
        var nearly = physical_pixel(
            bent_quad(0.95, True), lighting, x=pixel + 2
        )
        assert_equal(nearly.r, rough.r)
        assert_equal(nearly.g, rough.g)
        var half = physical_pixel(bent_quad(0.5, True), lighting, x=pixel + 2)
        assert_true(abs(half.r - rough.r) > 1e-4, "a curve reached one")
    var flat_rough = physical_pixel(bent_quad(1, False), lighting)
    var flat_nearly = physical_pixel(bent_quad(0.95, False), lighting)
    assert_true(
        abs(flat_nearly.r - flat_rough.r) > 1e-5,
        "a flat surface grew rougher",
    )
    # The clear coat takes the same curve.
    var coat_rough = physical_pixel(bent_quad(1, True, 1), lighting)
    var coat_nearly = physical_pixel(bent_quad(0.95, True, 1), lighting)
    assert_equal(coat_nearly.r, coat_rough.r)


def test_the_curve_is_measured_in_view_space() raises:
    # max(abs(dFdx(n)), abs(dFdy(n))) takes the largest part, which a turn
    # changes: the same surface seen through a camera turned about its
    # line of sight measures another roughness, as three.js's view space
    # normal does.
    var lighting = lit_obliquely()
    var turned = lit_obliquely()
    turned.up = Vector3(0.6, 0.8, 0)
    var square = physical_pixel(bent_quad(0.3, True), lighting)
    var aslant = physical_pixel(bent_quad(0.3, True), turned)
    assert_true(abs(square.r - aslant.r) > 1e-5, "the turn changed nothing")


def anisotropic_quad(
    normal_map: TextureId, coat_map: TextureId
) -> List[RasterVertex]:
    """Return a stretched physical quad with a normal map or a coat normal
    map, whose frame the stretch follows."""
    var layers = LayerFactors()
    layers.anisotropy = Vector2(1, 0)
    layers.clearcoat_normal_map = coat_map
    var coat = Float32(0)
    if coat_map != NO_TEXTURE:
        coat = 1
    return with_layers(
        physical_quad(
            kind=PHYSICAL,
            roughness=0.3,
            normal_map=normal_map,
            clearcoat=coat,
        ),
        layers,
    )


def test_a_stretch_follows_the_normal_maps_own_coordinates() raises:
    # three.js's `tbn` is measured on `vNormalMapUv`, else on
    # `vClearcoatNormalMapUv`, else on `vUv`. A flat normal map turns no
    # normal, but its placement turns the frame the lobe is stretched
    # along; so does the coat normal map's, when there is no normal map.
    var lighting = lit_obliquely()
    var textures = TextureStore()
    var flat = a_data_texel(128, 128, 255)
    var still = textures.add(Texture(copy=flat))
    flat.rotation = Angle(90.0, DEGREE)
    var turned = textures.add(flat^)
    var by_still = physical_pixel(
        anisotropic_quad(still, NO_TEXTURE), lighting, textures
    )
    var by_turned = physical_pixel(
        anisotropic_quad(turned, NO_TEXTURE), lighting, textures
    )
    assert_true(abs(by_turned.r - by_still.r) > 1e-3, "the frame did not turn")
    var coat_still = physical_pixel(
        anisotropic_quad(NO_TEXTURE, still), lighting, textures
    )
    var coat_turned = physical_pixel(
        anisotropic_quad(NO_TEXTURE, turned), lighting, textures
    )
    assert_true(
        abs(coat_turned.r - coat_still.r) > 1e-3,
        "the coat's frame did not turn",
    )
    # A mode that opens no map measures the raw pair.
    var unopened = physical_pixel(
        anisotropic_quad(turned, NO_TEXTURE), lighting, textures, SHADE_LIT
    )
    var bare = physical_pixel(
        anisotropic_quad(NO_TEXTURE, NO_TEXTURE), lighting, textures, SHADE_LIT
    )
    assert_equal(unopened.r, bare.r)


def test_a_hand_built_physical_corner_measures_no_curve_where_it_cannot() raises:
    # With no divisor the weights are used as they are, and a zero normal
    # stays zero: neither turns, so the lobe is the authored one's.
    var lighting = lit_obliquely()
    var plain = physical_pixel(bent_quad(0.4, False), lighting)
    var undivided = bent_quad(0.4, False)
    for index in range(len(undivided)):
        undivided[index].inv_w = 0
    var drawn = physical_pixel(undivided, lighting)
    assert_almost_equal(drawn.r, plain.r, atol=1e-4)
    var unturned = bent_quad(0.4, False)
    for index in range(len(unturned)):
        unturned[index].normal = Vector3(0, 0, 0)
    var dark = physical_pixel(unturned, lighting)
    assert_true(isfinite(dark.r), "a zero normal drew no number")
