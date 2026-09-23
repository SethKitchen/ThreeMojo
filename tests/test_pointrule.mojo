# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.pointrule` and the point rasterizer beside it."""

from core.fog import FogView, linear_fog
from materials.material import (
    BASIC,
    BLEND,
    Blending,
    LAMBERT,
    MaterialKind,
    OPAQUE,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.pointrule import (
    attenuated_size,
    coord,
    covers,
    first_covered,
    last_covered,
    mip_level_of,
)
from render.rasterizer import (
    DRAW_POINTS,
    DRAW_SEGMENTS,
    DRAW_TRIANGLES,
    Draw,
    DrawKind,
    RasterVertex,
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    ShadeMode,
    check_draws,
    check_output_kinds,
    check_point_maps,
    check_point_state,
    rasterize_frame,
    rasterize_point,
    rasterize_points_all,
)
from render.srgb import LINEAR, SRGB
from render.target import RenderTarget
from render.texture import (
    Alpha,
    COVERAGE,
    IGNORED,
    NEAREST,
    REPEAT,
    Texture,
    checkerboard,
)
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from render.tonemap import NO_TONE_MAPPING, REINHARD_TONE_MAPPING
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime TOLERANCE = Float64(1e-5)


def dot(
    x: Float32,
    y: Float32,
    size: Float32 = 3,
    z: Float32 = 0.5,
    color: FloatColor = FloatColor(1, 1, 1),
    blend: Blending = OPAQUE,
    texture: TextureId = NO_TEXTURE,
    alpha_map: TextureId = NO_TEXTURE,
    alpha_test: Float32 = 0,
    depth: Float32 = 0,
) raises -> RasterVertex:
    """Return one point, unlit as a point must be."""
    return RasterVertex(
        x,
        y,
        z,
        1,
        color,
        0,
        0,
        texture,
        blend,
        kind=BASIC,
        view_depth=depth,
        alpha_map=alpha_map,
        alpha_test=alpha_test,
        point_size=size,
    )


def lit(target: RenderTarget) raises -> Int:
    """Return how many pixels are not still the clear color."""
    var count = 0
    var image = target.resolve(1, NO_TONE_MAPPING, 1.0)
    for y in range(image.height):
        for x in range(image.width):
            var pixel = image.get_pixel(x, y)
            if pixel.r != 0 or pixel.g != 0 or pixel.b != 0:
                count += 1
    return count


def a_mask(green: UInt8) raises -> Texture:
    """Return a one-texel alpha map whose green channel is `green`."""
    var pixels = List[UInt8]()
    pixels.append(0)
    pixels.append(green)
    pixels.append(255)
    pixels.append(255)
    return Texture(1, 1, pixels^, REPEAT, NEAREST, LINEAR, False, IGNORED)


def a_split() raises -> Texture:
    """Return a two-texel image, red on the left and blue on the right,
    with the right half transparent, nearest and unmipmapped."""
    var pixels: List[UInt8] = [255, 0, 0, 255, 0, 0, 255, 0]
    return Texture(2, 1, pixels^, REPEAT, NEAREST, SRGB, False, COVERAGE)


# --- the rule ---------------------------------------------------------------


def test_a_size_shrinks_with_distance_under_perspective_only() raises:
    # three.js: size * (scale / -z), scale being half the image height.
    assert_almost_equal(
        Float64(attenuated_size(4, -2, 8, True)), Float64(16), atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(attenuated_size(4, -8, 8, True)), Float64(4), atol=TOLERANCE
    )
    # A parallel projection shrinks nothing with distance, and nor does
    # this.
    assert_equal(attenuated_size(4, -8, 8, False), Float32(4))


def test_a_pixel_is_covered_when_its_center_is_in_the_square() raises:
    # A three-pixel point centered on a pixel center covers that pixel and
    # its eight neighbors, and none beyond.
    var center = Vector2(4.5, 4.5)
    for y in range(9):
        for x in range(9):
            var inside = x >= 3 and x <= 5 and y >= 3 and y <= 5
            assert_equal(covers(center, 3, x, y), inside)


def test_the_square_is_half_open() raises:
    # A two-pixel point centered on a pixel corner covers the four pixels
    # around the corner. Each edge condition is asked on its own.
    var center = Vector2(4.0, 4.0)
    assert_true(covers(center, 2, 3, 3))
    assert_true(covers(center, 2, 4, 4))
    # Left edge: the center at 2.5 is one below 3.
    assert_false(covers(center, 2, 2, 3))
    # Right edge: the center at 5.5 is on it, and out.
    assert_false(covers(center, 2, 5, 3))
    # Top edge.
    assert_false(covers(center, 2, 3, 2))
    # Bottom edge.
    assert_false(covers(center, 2, 3, 5))


def test_a_one_pixel_point_covers_one_pixel() raises:
    var center = Vector2(2.5, 2.5)
    var count = 0
    for y in range(6):
        for x in range(6):
            if covers(center, 1, x, y):
                count += 1
                assert_equal(x, 2)
                assert_equal(y, 2)
    assert_equal(count, 1)


def test_the_coordinate_runs_across_the_square_with_v_upward() raises:
    var center = Vector2(4.5, 4.5)
    # Bottom left pixel of the three: u a sixth in, v a sixth up.
    var corner = coord(center, 3, 3, 5)
    assert_almost_equal(Float64(corner.x), Float64(1) / 6, atol=TOLERANCE)
    assert_almost_equal(Float64(corner.y), Float64(1) / 6, atol=TOLERANCE)
    # Top right pixel: five sixths each way.
    var far = coord(center, 3, 5, 3)
    assert_almost_equal(Float64(far.x), Float64(5) / 6, atol=TOLERANCE)
    assert_almost_equal(Float64(far.y), Float64(5) / 6, atol=TOLERANCE)
    # The middle is the middle.
    var middle = coord(center, 3, 4, 4)
    assert_almost_equal(Float64(middle.x), 0.5, atol=TOLERANCE)
    assert_almost_equal(Float64(middle.y), 0.5, atol=TOLERANCE)


def test_the_bounds_hold_the_covered_pixels_and_little_else() raises:
    # For a spread of centers and sizes the bounds enclose the first and
    # last pixels `covers` lights, and reach at most one pixel past each.
    var centers: List[Float32] = [4.5, 4.0, 4.25, 4.75, 0.3, 7.9]
    var sizes: List[Float32] = [1, 2, 3, 0.5, 4.5, 0.2]
    for center in centers:
        for size in sizes:
            var first = -100
            var last = -100
            for x in range(-4, 16):
                if covers(Vector2(center, 0.5), size, x, 0):
                    if first == -100:
                        first = x
                    last = x
            var before = first_covered(center, size)
            var after = last_covered(center, size)
            if first == -100:
                # Nothing covered: the bounds enclose at most two pixels,
                # and `covers` refuses both.
                assert_true(after - before <= 1)
            else:
                assert_true(before <= first and before >= first - 1)
                assert_true(after >= last and after <= last + 1)


def test_the_mip_level_follows_the_size() raises:
    # An eight-texel image on a two-pixel point: four texels a pixel, two
    # levels down. The longer edge decides.
    assert_almost_equal(Float64(mip_level_of(2, 8, 8)), 2.0, atol=TOLERANCE)
    assert_almost_equal(Float64(mip_level_of(2, 4, 8)), 2.0, atol=TOLERANCE)
    assert_almost_equal(Float64(mip_level_of(2, 8, 4)), 2.0, atol=TOLERANCE)
    # A point larger than its image is magnified: a level below zero.
    assert_true(mip_level_of(16, 8, 8) < 0)
    # No size and no image both read the full-size level.
    assert_equal(mip_level_of(0, 8, 8), Float32(0))
    assert_equal(mip_level_of(2, 0, 0), Float32(0))


# --- the rasterizer ---------------------------------------------------------


def test_a_point_paints_its_square() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3), target)
    assert_equal(lit(target), 9)
    assert_equal(target.shown(4, 4).r, UInt8(255))
    assert_equal(target.shown(3, 3).r, UInt8(255))
    assert_equal(target.shown(6, 6).r, UInt8(0))
    assert_equal(target.depth_at(4, 4), Float32(0.5))
    # Opaque, so written with an alpha of one.
    assert_equal(target.shown(4, 4).a, UInt8(255))


def test_a_point_is_clipped_to_the_image() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    # Hanging off the top left corner: only the quarter on the image.
    rasterize_point(dot(0.5, 0.5, 3), target)
    assert_equal(lit(target), 4)
    # And off the bottom right, and wholly off the image.
    rasterize_point(dot(7.5, 7.5, 3), target)
    assert_equal(lit(target), 8)
    rasterize_point(dot(30.5, 30.5, 3), target)
    assert_equal(lit(target), 8)
    # And off the left side alone, on rows that are on the image.
    rasterize_point(dot(-5.0, 4.5, 3), target)
    assert_equal(lit(target), 8)


def test_a_row_range_outside_the_image_is_held_inside_it() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3), target, first_row=-5, last_row=-1)
    assert_equal(lit(target), 9)
    var below = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3), below, first_row=0, last_row=90)
    assert_equal(lit(below), 9)
    # A band owns its rows and nothing else.
    var band = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3), band, first_row=4, last_row=4)
    assert_equal(lit(band), 3)


def test_a_point_behind_something_is_hidden() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3, 0.2, FloatColor(0, 1, 0)), target)
    rasterize_point(dot(4.5, 4.5, 3, 0.8, FloatColor(1, 0, 0)), target)
    assert_equal(target.shown(4, 4).g, UInt8(255))
    assert_equal(target.shown(4, 4).r, UInt8(0))


def test_a_blended_point_mixes_and_claims_no_depth() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(
        dot(4.5, 4.5, 3, 0.5, FloatColor(1, 0, 0, 0.5), BLEND), target
    )
    assert_equal(target.shown(4, 4).r, UInt8(188))
    assert_equal(target.depth_at(4, 4), inf[DType.float32]())
    # Hidden by what is in front, tested without claiming.
    var covered = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3, 0.2, FloatColor(0, 0, 1)), covered)
    rasterize_point(
        dot(4.5, 4.5, 3, 0.8, FloatColor(1, 0, 0, 0.5), BLEND), covered
    )
    assert_equal(covered.shown(4, 4).r, UInt8(0))
    assert_equal(covered.shown(4, 4).b, UInt8(255))


def test_the_uv_view_shows_the_points_own_coordinate() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3), target, SHADE_UV)
    # Bottom left pixel: a sixth each way, as bytes without the curve.
    var corner = target.shown(3, 5)
    assert_equal(corner.r, UInt8(43))
    assert_equal(corner.g, UInt8(43))
    # Top right: five sixths.
    var far = target.shown(5, 3)
    assert_equal(far.r, UInt8(213))
    assert_equal(far.g, UInt8(213))
    # Opaque data, so the depth is claimed and the curve is kept off.
    assert_equal(target.depth_at(4, 4), Float32(0.5))
    assert_equal(target.shown(4, 4, REINHARD_TONE_MAPPING).r, UInt8(128))


def test_a_point_samples_its_map_across_its_square() raises:
    var textures = TextureStore()
    var split = textures.add(a_split())
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(
        dot(4.5, 4.5, 4, texture=split), target, SHADE_TEXTURE, textures
    )
    # Red on the left half, blue on the right. The right half's alpha is
    # zero, which an opaque point ignores.
    assert_equal(target.shown(3, 4).r, UInt8(255))
    assert_equal(target.shown(3, 4).b, UInt8(0))
    assert_equal(target.shown(5, 4).b, UInt8(255))
    assert_equal(target.shown(5, 4).r, UInt8(0))
    assert_equal(target.shown(5, 4).a, UInt8(255))
    # Under SHADE_LIT the map is not opened.
    var plain = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 4, texture=split), plain, SHADE_LIT, textures)
    assert_equal(plain.shown(3, 4).r, UInt8(255))
    assert_equal(plain.shown(3, 4).b, UInt8(255))


def test_a_point_reads_the_mip_level_its_size_chooses() raises:
    # A mipmapped checkerboard on a two-pixel point reads a level far down
    # the chain, where the squares have averaged to gray; on a big point
    # it reads the full-size image, where a pixel lands on one square.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(16, 8, Color(255, 255, 255), Color(0, 0, 0))
    )
    var small = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(
        dot(4.0, 4.0, 2, texture=board), small, SHADE_TEXTURE, textures
    )
    var gray = target_gray(small, 3, 3)
    assert_true(gray > 60 and gray < 200, "the small point read no mip")
    var big = RenderTarget(32, 32, Color(0, 0, 0))
    rasterize_point(
        dot(16.0, 16.0, 32, texture=board), big, SHADE_TEXTURE, textures
    )
    var sharp = target_gray(big, 1, 1)
    assert_true(sharp < 30 or sharp > 225, "the big point read a mip")


def target_gray(target: RenderTarget, x: Int, y: Int) raises -> Int:
    """Return one pixel's red channel as an Int."""
    return Int(target.shown(x, y).r)


def test_an_alpha_map_and_a_test_cut_a_point_out() raises:
    var textures = TextureStore()
    var thin = textures.add(a_mask(64))
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(
        dot(
            4.5,
            4.5,
            3,
            color=FloatColor(1, 1, 1, 1),
            blend=BLEND,
            alpha_map=thin,
        ),
        target,
        SHADE_TEXTURE,
        textures,
    )
    # Thinned to a quarter and blended over black.
    var seen = target.shown(4, 4).r
    assert_true(seen > 120 and seen < 150, "the alpha map did not thin")
    # A test above the thinned alpha throws every pixel away, claiming no
    # depth; one below it keeps them and claims it late.
    var cut = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(
        dot(4.5, 4.5, 3, alpha_map=thin, alpha_test=0.5),
        cut,
        SHADE_TEXTURE,
        textures,
    )
    assert_equal(lit(cut), 0)
    assert_equal(cut.depth_at(4, 4), inf[DType.float32]())
    var kept = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(
        dot(4.5, 4.5, 3, alpha_map=thin, alpha_test=0.2),
        kept,
        SHADE_TEXTURE,
        textures,
    )
    assert_equal(lit(kept), 9)
    assert_equal(kept.depth_at(4, 4), Float32(0.5))
    # A tested point tests the depth without claiming it first: behind an
    # opaque one it is hidden.
    var behind = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3, 0.1, FloatColor(0, 0, 1)), behind)
    rasterize_point(
        dot(4.5, 4.5, 3, 0.9, alpha_map=thin, alpha_test=0.2),
        behind,
        SHADE_TEXTURE,
        textures,
    )
    assert_equal(behind.shown(4, 4).b, UInt8(255))
    assert_equal(behind.shown(4, 4).r, UInt8(0))


def test_fog_veils_a_point_by_its_depth() raises:
    var fog = FogView(
        linear_fog(Color(0, 0, 255), Length(1.0, METER), Length(3.0, METER))
    )
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(
        dot(4.5, 4.5, 3, color=FloatColor(1, 0, 0), depth=2), target, fog=fog
    )
    var seen = target.shown(4, 4)
    assert_true(seen.r > 100 and seen.r < 255, "the fog did nothing")
    assert_true(seen.b > 100, "the fog color did not reach the point")
    # Not in the uv view, which shows coordinates.
    var view = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(dot(4.5, 4.5, 3, depth=2), view, SHADE_UV, fog=fog)
    assert_equal(view.shown(4, 4).b, UInt8(0))


def test_a_point_whose_material_turns_the_fog_off_is_not_fogged() raises:
    # three.js's `fog = false` on a `PointsMaterial`.
    var fog = FogView(
        linear_fog(Color(0, 0, 255), Length(1.0, METER), Length(3.0, METER))
    )
    var point = dot(4.5, 4.5, 3, color=FloatColor(1, 0, 0), depth=2)
    point.fog = False
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_point(point, target, fog=fog)
    assert_equal(target.shown(4, 4).r, UInt8(255))
    assert_equal(target.shown(4, 4).b, UInt8(0))


def test_a_point_must_be_well_formed() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var bad_blend = dot(4.5, 4.5)
    bad_blend.blend = Blending(7)
    with assert_raises(contains="blend policy"):
        check_point_state(bad_blend)
    var bad_kind = dot(4.5, 4.5)
    bad_kind.kind = MaterialKind(11)
    with assert_raises(contains="material kind that exists"):
        check_point_state(bad_kind)
    var lit_point = dot(4.5, 4.5)
    lit_point.kind = LAMBERT
    with assert_raises(contains="must be unlit"):
        rasterize_point(lit_point, target)
    with assert_raises(contains="size above zero"):
        check_point_state(dot(4.5, 4.5, 0))
    with assert_raises(contains="size above zero"):
        check_point_state(dot(4.5, 4.5, -1))
    with assert_raises(contains="size above zero"):
        check_point_state(dot(4.5, 4.5, nan[DType.float32]()))
    with assert_raises(contains="alpha test"):
        check_point_state(dot(4.5, 4.5, alpha_test=1.5))
    with assert_raises(contains="alpha test"):
        check_point_state(dot(4.5, 4.5, alpha_test=-0.5))
    with assert_raises(contains="alpha test"):
        check_point_state(dot(4.5, 4.5, alpha_test=nan[DType.float32]()))
    with assert_raises(contains="texture id"):
        check_point_state(dot(4.5, 4.5, texture=TextureId(-7)))
    with assert_raises(contains="alpha map id"):
        check_point_state(dot(4.5, 4.5, alpha_map=TextureId(-7)))
    with assert_raises(contains="shading mode"):
        rasterize_point(dot(4.5, 4.5), target, ShadeMode(5))
    # A well-formed point passes every check.
    check_point_state(dot(4.5, 4.5))


def test_a_points_alpha_map_must_be_stored_as_data() raises:
    var textures = TextureStore()
    var pixels: List[UInt8] = [0, 128, 255, 255]
    var wrong = textures.add(
        Texture(1, 1, pixels^, REPEAT, NEAREST, SRGB, False, COVERAGE)
    )
    with assert_raises():
        check_point_maps(
            dot(4.5, 4.5, alpha_map=wrong), SHADE_TEXTURE, textures
        )
    # Not opened under any other mode, so not refused.
    check_point_maps(dot(4.5, 4.5, alpha_map=wrong), SHADE_LIT, textures)
    check_point_maps(dot(4.5, 4.5), SHADE_TEXTURE, textures)


def test_a_batch_draws_every_point_on_any_number_of_workers() raises:
    var points: List[RasterVertex] = [
        dot(2.5, 2.5, 3, 0.5, FloatColor(1, 0, 0)),
        dot(6.0, 6.0, 2, 0.4, FloatColor(0, 1, 0)),
        dot(6.5, 1.5, 1, 0.3, FloatColor(0, 0, 1)),
        dot(3.5, 5.5, 3, 0.6, FloatColor(1, 1, 0, 0.5), BLEND),
    ]
    var alone = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_points_all(points, alone)
    assert_equal(lit(alone), 9 + 4 + 1 + 9)
    var crowd = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_points_all(points, crowd, workers=4)
    for y in range(8):
        for x in range(8):
            var one = alone.shown(x, y)
            var four = crowd.shown(x, y)
            assert_equal(one.r, four.r)
            assert_equal(one.g, four.g)
            assert_equal(one.b, four.b)
            assert_equal(alone.depth_at(x, y), crowd.depth_at(x, y))
    # An empty batch draws nothing.
    var empty = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_points_all(List[RasterVertex](), empty)
    assert_equal(lit(empty), 0)


def test_a_point_no_band_draws_is_still_refused() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var off = dot(0.5, 90.5)
    off.kind = LAMBERT
    with assert_raises():
        rasterize_points_all([off], target, workers=4)
    with assert_raises():
        rasterize_points_all([off], target, workers=1)


def test_a_frame_draws_points_among_its_triangles() raises:
    # A point behind an opaque triangle is hidden by it whichever is drawn
    # first, and one in front is drawn over it.
    var corners: List[RasterVertex] = [
        RasterVertex(-10, -10, 0.5, 1, FloatColor(0, 0, 1), kind=BASIC),
        RasterVertex(40, -10, 0.5, 1, FloatColor(0, 0, 1), kind=BASIC),
        RasterVertex(-10, 40, 0.5, 1, FloatColor(0, 0, 1), kind=BASIC),
    ]
    var points: List[RasterVertex] = [
        dot(2.5, 2.5, 1, 0.2, FloatColor(1, 0, 0)),
        dot(5.5, 5.5, 1, 0.8, FloatColor(0, 1, 0)),
    ]
    for workers in [1, 4]:
        var target = RenderTarget(8, 8, Color(0, 0, 0))
        rasterize_frame(
            corners,
            List[RasterVertex](),
            [
                Draw(DRAW_POINTS, 0, 2),
                Draw(DRAW_TRIANGLES, 0, 1),
                Draw(DRAW_POINTS, 2, 0),
            ],
            target,
            workers=workers,
            points=points,
        )
        assert_equal(target.shown(2, 2).r, UInt8(255))
        assert_equal(target.shown(5, 5).g, UInt8(0))
        assert_equal(target.shown(5, 5).b, UInt8(255))
        var other = RenderTarget(8, 8, Color(0, 0, 0))
        rasterize_frame(
            corners,
            List[RasterVertex](),
            [Draw(DRAW_TRIANGLES, 0, 1), Draw(DRAW_POINTS, 1, 1)],
            other,
            workers=workers,
            points=points,
        )
        assert_equal(other.shown(2, 2).b, UInt8(255))
        assert_equal(other.shown(5, 5).b, UInt8(255))


def test_a_draw_kind_knows_its_stride() raises:
    assert_equal(DRAW_TRIANGLES.stride(), 3)
    assert_equal(DRAW_SEGMENTS.stride(), 2)
    assert_equal(DRAW_POINTS.stride(), 1)
    assert_true(DRAW_POINTS.is_valid())
    assert_false(DrawKind(3).is_valid())
    assert_equal(DrawKind(3).stride(), 3)


def test_a_draw_of_points_is_held_to_the_points_there_are() raises:
    check_draws([Draw(DRAW_POINTS, 0, 2)], 0, 0, 2)
    check_draws([Draw(DRAW_POINTS, 2, 0)], 0, 0, 2)
    with assert_raises():
        check_draws([Draw(DRAW_POINTS, 0, 3)], 0, 0, 2)
    with assert_raises():
        check_draws([Draw(DRAW_POINTS, 0, 1)], 5, 5)
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    with assert_raises():
        rasterize_frame(
            List[RasterVertex](),
            List[RasterVertex](),
            [Draw(DRAW_POINTS, 0, 1)],
            target,
        )


def test_a_blended_point_beside_data_is_refused_under_a_curve() raises:
    var normal = RasterVertex(
        0, 0, 0.5, 1, FloatColor(1, 1, 1), kind=MaterialKind(2)
    )
    var corners: List[RasterVertex] = [normal, normal, normal]
    var faint = dot(1.5, 1.5, 1, color=FloatColor(1, 1, 1, 0.5), blend=BLEND)
    with assert_raises():
        check_output_kinds(corners, True, List[RasterVertex](), [faint])
    # An opaque point is no blend, and no curve refuses nothing.
    check_output_kinds(corners, True, List[RasterVertex](), [dot(1.5, 1.5)])
    check_output_kinds(corners, False, List[RasterVertex](), [faint])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
