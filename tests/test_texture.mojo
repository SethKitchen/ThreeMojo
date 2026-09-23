# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.texture`.

Two things are easy to get backwards here and neither shows up as an error:
which way `v` runs, and which texel a coordinate on a tile boundary belongs
to. Both are asserted against worked-out answers rather than against whatever
the implementation happens to do.
"""

from math.matrix3 import Matrix3
from math.vector2 import Vector2
from render.srgb import UNKNOWN_SPACE, ColorSpace
from render.texture import Filter, Wrap
from units.si import Angle, DEGREE
from render.framebuffer import Color, FloatColor, Framebuffer
from render.srgb import LINEAR, SRGB, srgb_to_linear
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    IGNORED,
    NEAREST,
    MIRROR,
    REPEAT,
    Alpha,
    Texture,
    blend,
    checkerboard,
    data_texture,
    depth_texture_of,
    depth_texture_of_buffer,
    mix_color,
    texture_of,
    wrap_index,
    Footprint,
    MAX_ANISOTROPY,
    UV_CHANNEL_0,
    UV_CHANNEL_1,
    UvChannel,
    anisotropic_footprint,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-6)


def quad(wrap: Wrap = REPEAT) raises -> Texture:
    """Return a 2x2 texture with four distinguishable texels.

    Laid out by row from the top, as the image is stored:

        red    green
        blue   white

    Args:
        wrap: The wrap mode to build it with.

    Returns:
        The texture.

    Raises:
        Error: If the texture is malformed, which it is not.
    """
    var pixels = List[UInt8]()
    var colors = [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 255),
    ]
    for index in range(4):
        pixels.append(colors[index].r)
        pixels.append(colors[index].g)
        pixels.append(colors[index].b)
        pixels.append(colors[index].a)
    return Texture(2, 2, pixels^, wrap, NEAREST, mipmapped=False)


# --- the blank texture ------------------------------------------------------


def test_the_blank_texture_samples_as_opaque_white() raises:
    # White is the identity for modulation, so a mesh with no texture shades
    # exactly as it did before textures existed.
    var nothing = Texture()
    assert_true(nothing.is_blank())
    var sampled = nothing.sample(0.3, 0.7)
    assert_equal(sampled.r, Float32(1))
    assert_equal(sampled.g, Float32(1))
    assert_equal(sampled.b, Float32(1))
    assert_equal(sampled.a, Float32(1))


def test_the_blank_texture_has_no_texels_to_read() raises:
    with assert_raises():
        _ = Texture().texel(0, 0)


def test_a_real_texture_is_not_blank() raises:
    assert_false(quad().is_blank())


# --- construction -----------------------------------------------------------


def test_dimensions_must_be_positive() raises:
    with assert_raises():
        _ = Texture(0, 2, List[UInt8](), REPEAT)
    with assert_raises():
        _ = Texture(2, -1, List[UInt8](), REPEAT)


def test_the_buffer_must_match_the_dimensions() raises:
    var short = List[UInt8](length=15, fill=0)
    with assert_raises():
        _ = Texture(2, 2, short^, REPEAT)


def test_every_known_wrap_mode_is_accepted() raises:
    # Each has to be able to decide the outcome on its own.
    _ = quad(REPEAT)
    _ = quad(CLAMP)
    _ = quad(MIRROR)


def test_a_texture_clamps_by_default_as_three_js_does() raises:
    """Every constructor defaults to three.js's `ClampToEdgeWrapping`."""
    assert_equal(Texture().wrap, CLAMP)
    var pixels = List[UInt8](length=4, fill=255)
    assert_equal(Texture(1, 1, pixels^).wrap, CLAMP)
    var board = checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))
    assert_equal(board.wrap, CLAMP)
    # The dark edge texel holds past the edge. A tiling read would come
    # back to the light square at the left.
    assert_equal(board.sample(1.3, 0.9).r, 0)


def test_copying_a_texture_leaves_the_original_alone() raises:
    var original = quad()
    var duplicate = Texture(copy=original)
    assert_equal(duplicate.width, 2)
    assert_equal(duplicate.texel(0, 0).r, UInt8(255))
    assert_equal(original.texel(0, 0).r, UInt8(255))


# --- texels -----------------------------------------------------------------


def test_texels_are_addressed_by_row_from_the_top() raises:
    var image = quad()
    assert_equal(image.texel(0, 0).r, UInt8(255))
    assert_equal(image.texel(1, 0).g, UInt8(255))
    assert_equal(image.texel(0, 1).b, UInt8(255))
    assert_equal(image.texel(1, 1).r, UInt8(255))
    assert_equal(image.texel(1, 1).b, UInt8(255))


def test_reading_a_texel_out_of_bounds_is_rejected() raises:
    var image = quad()
    with assert_raises():
        _ = image.texel(-1, 0)
    with assert_raises():
        _ = image.texel(0, -1)
    with assert_raises():
        _ = image.texel(2, 0)
    with assert_raises():
        _ = image.texel(0, 2)


# --- sampling ---------------------------------------------------------------


def test_v_runs_upwards_while_rows_run_down() raises:
    # The reconciliation this module exists to do once. v = 1 is the *top* of
    # the image, because texture space counts up from the bottom and rows
    # count down from the top. Getting it backwards flips every texture
    # vertically and nothing reports an error.
    var image = quad()
    # Top-left texel is red, and v near 1 must find it.
    assert_equal(image.sample(0.25, 0.9).r, Float32(1))
    assert_equal(image.sample(0.25, 0.9).b, Float32(0))
    # Bottom-left texel is blue, and v near 0 must find it.
    assert_equal(image.sample(0.25, 0.1).b, Float32(1))
    assert_equal(image.sample(0.25, 0.1).r, Float32(0))


def test_each_quarter_samples_its_own_texel() raises:
    var image = quad()
    # (u, v) with v measured up: the four quarters in reading order.
    assert_equal(image.sample(0.25, 0.75).r, Float32(1))
    assert_equal(image.sample(0.75, 0.75).g, Float32(1))
    assert_equal(image.sample(0.25, 0.25).b, Float32(1))
    assert_equal(image.sample(0.75, 0.25).g, Float32(1))
    assert_equal(image.sample(0.75, 0.25).r, Float32(1))


def test_sampling_is_nearest_neighbor_not_blended() raises:
    # Either side of the midline gives one texel or the other, never a mix.
    var image = quad()
    var left = image.sample(0.49, 0.75)
    var right = image.sample(0.51, 0.75)
    assert_equal(left.r, Float32(1))
    assert_equal(left.g, Float32(0))
    assert_equal(right.r, Float32(0))
    assert_equal(right.g, Float32(1))


def test_eight_bit_texels_come_back_as_fractions() raises:
    # A LINEAR texture is used as stored, so a byte is just a byte over 255.
    var pixels = List[UInt8]()
    for value in [UInt8(51), UInt8(102), UInt8(153), UInt8(204)]:
        pixels.append(value)
    var image = Texture(1, 1, pixels^, REPEAT, NEAREST, LINEAR)
    assert_almost_equal(
        image.sample(0.5, 0.5).r, Float32(51) / 255, atol=TOLERANCE
    )
    assert_almost_equal(
        image.sample(0.5, 0.5).a, Float32(204) / 255, atol=TOLERANCE
    )


def test_a_color_texture_is_decoded_from_srgb() raises:
    # The default, because that is what an image file holds. A byte of 128 is
    # not half the light -- it is about 21.6% of it.
    var pixels = List[UInt8]()
    for value in [UInt8(128), UInt8(128), UInt8(128), UInt8(128)]:
        pixels.append(value)
    var image = Texture(1, 1, pixels^, REPEAT, NEAREST, SRGB)
    assert_almost_equal(
        image.sample(0.5, 0.5).r,
        srgb_to_linear(Float32(128) / 255),
        atol=TOLERANCE,
    )
    assert_true(image.sample(0.5, 0.5).r < 0.25)


def test_alpha_is_never_decoded() raises:
    # Alpha is coverage, not color. Decoding it would make a half-transparent
    # surface a fifth-transparent one.
    var pixels = List[UInt8]()
    for value in [UInt8(128), UInt8(128), UInt8(128), UInt8(128)]:
        pixels.append(value)
    var image = Texture(1, 1, pixels^, REPEAT, NEAREST, SRGB)
    assert_almost_equal(
        image.sample(0.5, 0.5).a, Float32(128) / 255, atol=TOLERANCE
    )


def test_a_texture_keeps_the_color_space_it_was_given() raises:
    var pixels = List[UInt8](length=4, fill=0)
    var image = Texture(1, 1, pixels^, REPEAT, NEAREST, LINEAR)
    assert_equal(image.color_space, LINEAR)
    assert_equal(Texture().color_space, LINEAR)


# --- wrapping ---------------------------------------------------------------


def test_repeat_tiles_the_image() raises:
    # 1.25 is a quarter of the way into the second tile, so it reads what 0.25
    # reads. Negative coordinates tile the same way.
    var image = quad(REPEAT)
    assert_equal(image.sample(1.25, 0.75).r, image.sample(0.25, 0.75).r)
    assert_equal(image.sample(-0.75, 0.75).r, image.sample(0.25, 0.75).r)
    assert_equal(image.sample(0.25, 1.75).r, image.sample(0.25, 0.75).r)


def test_clamp_holds_the_edge_texel() raises:
    var image = quad(CLAMP)
    # Far off to the right stays in the right-hand column.
    assert_equal(image.sample(9.0, 0.75).g, Float32(1))
    assert_equal(image.sample(9.0, 0.75).r, Float32(0))
    # Far off to the left stays in the left-hand one.
    assert_equal(image.sample(-9.0, 0.75).r, Float32(1))


def test_negative_coordinates_rely_on_floored_modulo() raises:
    # `wrap_index` has no correction for a negative remainder because Mojo's
    # `%` is floored like Python's and never produces one. If that ever
    # changed, every wrap mode would break for coordinates left of or below
    # the image, and this is the assertion that would say so.
    assert_equal(-1 % 4, 3)
    assert_equal(-5 % 4, 3)
    assert_equal(-4 % 4, 0)
    # And the wrapping built on it agrees.
    assert_equal(wrap_index(-1, 4, REPEAT), 3)
    assert_equal(wrap_index(-5, 4, REPEAT), 3)
    # -1 lands at 7 in the period of 8, which is in the reversed half, so it
    # folds back to 0. -5 lands at 3, which is in the forward half already.
    assert_equal(wrap_index(-1, 4, MIRROR), 0)
    assert_equal(wrap_index(-5, 4, MIRROR), 3)


def test_wrapping_covers_a_whole_period_in_each_mode() raises:
    # Walked directly, because sampling can only reach these through a
    # coordinate and it is easier to be sure of the answers here.
    for index in range(4):
        assert_equal(wrap_index(index, 4, REPEAT), index)
        assert_equal(wrap_index(index, 4, CLAMP), index)
        assert_equal(wrap_index(index, 4, MIRROR), index)
    # One tile further: repeat starts again, mirror comes back, clamp holds.
    assert_equal(wrap_index(4, 4, REPEAT), 0)
    assert_equal(wrap_index(7, 4, REPEAT), 3)
    assert_equal(wrap_index(4, 4, MIRROR), 3)
    assert_equal(wrap_index(7, 4, MIRROR), 0)
    assert_equal(wrap_index(4, 4, CLAMP), 3)
    assert_equal(wrap_index(99, 4, CLAMP), 3)


def test_mirror_alternates_direction_every_tile() raises:
    # The second tile runs backwards, so 1.25 reads what 0.75 reads rather
    # than what 0.25 does -- which is what makes tiles meet without a seam.
    var image = quad(MIRROR)
    assert_equal(image.sample(1.25, 0.75).g, image.sample(0.75, 0.75).g)
    assert_equal(image.sample(1.25, 0.75).r, Float32(0))
    # And the third tile is the right way round again.
    assert_equal(image.sample(2.25, 0.75).r, image.sample(0.25, 0.75).r)


def test_the_ends_of_the_range_meet_under_repeat() raises:
    # v = 0 and v = 1 name the same boundary of a tiled image, so they sample
    # the same texel. That is not an off-by-one; it is what seamless means.
    var image = quad(REPEAT)
    assert_equal(image.sample(0.25, 0.0).r, image.sample(0.25, 1.0).r)


def test_the_ends_of_the_range_are_opposite_edges_under_clamp() raises:
    # Clamping holds each edge instead, so the two ends are the two rows.
    var image = quad(CLAMP)
    assert_equal(image.sample(0.25, 1.0).r, Float32(1))
    assert_equal(image.sample(0.25, 0.0).b, Float32(1))


# --- the checkerboard -------------------------------------------------------


def test_a_checkerboard_alternates_from_the_top_left() raises:
    var board = checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))
    assert_equal(board.width, 4)
    assert_equal(board.texel(0, 0).r, UInt8(255))
    assert_equal(board.texel(2, 0).r, UInt8(0))
    assert_equal(board.texel(0, 2).r, UInt8(0))
    assert_equal(board.texel(2, 2).r, UInt8(255))


def test_a_checkerboards_squares_are_whole() raises:
    # Every texel inside one square is the same color; the edge is hard.
    var board = checkerboard(8, 2, Color(255, 255, 255), Color(0, 0, 0))
    for y in range(4):
        for x in range(4):
            assert_equal(board.texel(x, y).r, UInt8(255))
    assert_equal(board.texel(4, 0).r, UInt8(0))


def test_a_checkerboard_must_divide_evenly() raises:
    # A half square at one edge makes a tiled image visibly discontinuous.
    with assert_raises():
        _ = checkerboard(5, 2, Color(255, 255, 255), Color(0, 0, 0))
    with assert_raises():
        _ = checkerboard(0, 2, Color(255, 255, 255), Color(0, 0, 0))
    with assert_raises():
        _ = checkerboard(8, 0, Color(255, 255, 255), Color(0, 0, 0))


def test_a_checkerboard_carries_its_wrap_mode() raises:
    var board = checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0), CLAMP)
    assert_equal(board.wrap, CLAMP)


# --- bilinear filtering -----------------------------------------------------


def smooth_quad() raises -> Texture:
    """Return the 2x2 texture again, blended rather than stepped."""
    var pixels = List[UInt8]()
    var colors = [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 255),
    ]
    for index in range(4):
        pixels.append(colors[index].r)
        pixels.append(colors[index].g)
        pixels.append(colors[index].b)
        pixels.append(colors[index].a)
    return Texture(2, 2, pixels^, CLAMP, BILINEAR)


def test_a_bilinear_sample_on_a_texel_center_is_that_texel() raises:
    # Texel centers sit at 0.25 and 0.75 on a 2x2 image. Landing exactly on
    # one must give it back unblended, or every image is offset.
    var image = smooth_quad()
    var middle = image.sample(0.25, 0.75)
    assert_almost_equal(middle.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(middle.g, Float32(0), atol=TOLERANCE)
    assert_almost_equal(middle.b, Float32(0), atol=TOLERANCE)


def test_a_bilinear_sample_between_two_texels_is_their_mean() raises:
    # Halfway between the top-left red and top-right green, along the row of
    # texel centers: half of each and nothing of the bottom row.
    var image = smooth_quad()
    var between = image.sample(0.5, 0.75)
    assert_almost_equal(between.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.b, Float32(0), atol=TOLERANCE)


def test_a_bilinear_sample_in_the_middle_is_all_four() raises:
    # The center of the image is equidistant from all four texel centers.
    # red + green + blue + white, quartered: r = (1 + 0 + 0 + 1) / 4 = 0.5.
    var image = smooth_quad()
    var center = image.sample(0.5, 0.5)
    assert_almost_equal(center.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(center.g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(center.b, Float32(0.5), atol=TOLERANCE)


def test_nearest_and_bilinear_agree_on_texel_centers() raises:
    # The filters differ between centers, not at them.
    var stepped = quad(CLAMP)
    var smooth = smooth_quad()
    assert_equal(stepped.sample(0.25, 0.75).r, smooth.sample(0.25, 0.75).r)
    assert_equal(stepped.sample(0.75, 0.25).g, smooth.sample(0.75, 0.25).g)


def test_bilinear_blends_where_nearest_steps() raises:
    # Just off a boundary, nearest jumps and bilinear does not.
    var stepped = quad(CLAMP)
    var smooth = smooth_quad()
    assert_equal(stepped.sample(0.5, 0.75).r, Float32(0))
    assert_true(smooth.sample(0.5, 0.75).r > 0.4)
    assert_true(smooth.sample(0.5, 0.75).r < 0.6)


def test_bilinear_blends_through_the_wrap_mode() raises:
    # Beyond the edge, a clamped texture holds its edge texel rather than
    # fading out of it -- the neighbors are fetched through the wrap mode,
    # not clamped to the image after the fact.
    var image = smooth_quad()
    var beyond = image.sample(1.4, 0.75)
    assert_almost_equal(beyond.g, Float32(1), atol=TOLERANCE)
    assert_almost_equal(beyond.r, Float32(0), atol=TOLERANCE)


def test_a_repeating_bilinear_texture_blends_across_its_seam() raises:
    # The other side of the same rule: a tiled image's left edge blends with
    # its own right edge, which is what keeps a tiled surface seamless.
    var pixels = List[UInt8]()
    var colors = [Color(255, 0, 0), Color(0, 0, 255)]
    for index in range(2):
        pixels.append(colors[index].r)
        pixels.append(colors[index].g)
        pixels.append(colors[index].b)
        pixels.append(colors[index].a)
    var strip = Texture(2, 1, pixels^, REPEAT, BILINEAR)
    # At u = 0 the sample sits between the right-hand texel of the previous
    # tile and the left-hand texel of this one: half red, half blue.
    var seam = strip.sample(0.0, 0.5)
    assert_almost_equal(seam.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(seam.b, Float32(0.5), atol=TOLERANCE)


def test_a_texture_keeps_the_filter_it_was_given() raises:
    assert_equal(quad().filter, NEAREST)
    assert_equal(smooth_quad().filter, BILINEAR)
    # Left unsaid, the filter is bilinear and the chain is built, as
    # three.js's `LinearFilter`, `LinearMipmapLinearFilter` and
    # `generateMipmaps` have them.
    var told_nothing = checkerboard(8, 2, Color(255, 255, 255), Color(0, 0, 0))
    assert_equal(told_nothing.filter, BILINEAR)
    assert_equal(told_nothing.levels, 4)
    var board = checkerboard(
        4, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, BILINEAR
    )
    assert_equal(board.filter, BILINEAR)


def test_the_blank_texture_is_white_under_either_filter() raises:
    # Blank short-circuits before the filter is consulted at all.
    assert_equal(Texture().sample(0.3, 0.3).r, Float32(1))


def test_blending_four_equal_texels_changes_nothing() raises:
    var same = FloatColor(0.25, 0.5, 0.75, 1.0)
    var result = blend(same, same, same, same, 0.3, 0.8)
    assert_almost_equal(result.r, Float32(0.25), atol=TOLERANCE)
    assert_almost_equal(result.b, Float32(0.75), atol=TOLERANCE)


def test_the_blank_texture_wraps_to_white_rather_than_dividing_by_zero() raises:
    # `wrapped_texel` is public and `sample` is not its only caller: the blank
    # texture has a zero extent, and wrapping into one is a modulo by zero.
    # The guard is in both places for that reason.
    var nothing = Texture()
    assert_equal(nothing.wrapped_texel(0, 0).r, Float32(1))
    assert_equal(nothing.wrapped_texel(-3, 9).b, Float32(1))
    assert_equal(nothing.wrapped_texel(0, 0).a, Float32(1))


def test_filtering_does_not_drag_hidden_color_into_view() raises:
    # An opaque red beside a fully transparent green. Filtering the straight
    # colors averages them and puts a green fringe along a transparent edge,
    # which is the halo around every badly filtered cut-out sprite. Blended
    # where hidden color weighs nothing, the answer is half-covered red.
    var pixels = List[UInt8]()
    for value in [UInt8(255), UInt8(0), UInt8(0), UInt8(255)]:
        pixels.append(value)
    for value in [UInt8(0), UInt8(255), UInt8(0), UInt8(0)]:
        pixels.append(value)
    var strip = Texture(2, 1, pixels^, CLAMP, BILINEAR, LINEAR)

    # Halfway between the two texel centers.
    var between = strip.sample(0.5, 0.5)
    assert_almost_equal(between.a, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.g, Float32(0), atol=TOLERANCE)
    assert_almost_equal(between.r, Float32(1), atol=TOLERANCE)


def test_filtering_two_opaque_texels_is_unchanged_by_premultiplying() raises:
    # The other side: where both texels are opaque, premultiplying and
    # unpremultiplying cancel and the plain average is still the answer.
    var pixels = List[UInt8]()
    for value in [UInt8(255), UInt8(0), UInt8(0), UInt8(255)]:
        pixels.append(value)
    for value in [UInt8(0), UInt8(255), UInt8(0), UInt8(255)]:
        pixels.append(value)
    var strip = Texture(2, 1, pixels^, CLAMP, BILINEAR, LINEAR)
    var between = strip.sample(0.5, 0.5)
    assert_almost_equal(between.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.a, Float32(1.0), atol=TOLERANCE)


# --- Mipmaps ----------------------------------------------------------------


def test_a_texture_has_one_level_when_asked_for_none() raises:
    # Building the chain costs a third more memory and is pointless for an
    # image that is never minified, so it is opt-in.
    var plain = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=False
    )
    assert_equal(plain.levels, 1)


def test_the_chain_halves_down_to_a_single_texel() raises:
    # 8 -> 4 -> 2 -> 1 is four levels, and the last one has nowhere to go.
    var board = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=True
    )
    assert_equal(board.levels, 4)
    assert_equal(board.level_width(0), 8)
    assert_equal(board.level_width(3), 1)
    assert_equal(board.level_height(3), 1)


def test_a_level_starts_after_every_level_before_it() raises:
    # The chain is one buffer, largest first: 8x8 then 4x4 then 2x2 then 1x1,
    # four bytes each. The GPU works the same offsets out from the same two
    # numbers, so they are asserted rather than assumed.
    var board = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=True
    )
    assert_equal(board.level_offset(0), 0)
    assert_equal(board.level_offset(1), 8 * 8 * 4)
    assert_equal(board.level_offset(2), (8 * 8 + 4 * 4) * 4)
    assert_equal(board.level_offset(3), (8 * 8 + 4 * 4 + 2 * 2) * 4)
    assert_equal(len(board.pixels), (8 * 8 + 4 * 4 + 2 * 2 + 1) * 4)


def test_a_level_is_the_average_of_the_light_beneath_it() raises:
    # A two-square board of black and white averages, over any four texels,
    # to half the *light* -- which encodes as 188, not 128. The smallest
    # level is that average taken over the whole image.
    var board = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=True
    )
    var smallest = board.wrapped_texel(0, 0, 3)
    assert_almost_equal(smallest.r, Float32(0.5), atol=Float64(0.004))
    assert_equal(
        board.pixels[board.level_offset(3)],
        UInt8(188),
    )


def test_a_uniform_image_survives_the_whole_chain() raises:
    # Averaging equal values changes nothing, so every level of a flat image
    # is the color it started as. Catches an offset or extent that is wrong
    # in a way a gradient would hide.
    var board = checkerboard(
        4, 1, Color(30, 90, 210), Color(30, 90, 210), mipmapped=True
    )
    for level in range(board.levels):
        var texel = board.wrapped_texel(0, 0, level)
        assert_almost_equal(
            texel.r, srgb_to_linear(Float32(30) / 255), atol=Float64(0.004)
        )
        assert_almost_equal(
            texel.b, srgb_to_linear(Float32(210) / 255), atol=Float64(0.004)
        )


def test_a_hidden_color_weighs_nothing_when_a_level_is_built() raises:
    # The premultiplied reason, one level up: a transparent red next to an
    # opaque white must average to white at half alpha, not to pink. Two
    # texels wide, so level 1 is a single texel holding the average.
    var pixels = List[UInt8]()
    for value in [UInt8(255), UInt8(0), UInt8(0), UInt8(0)]:
        pixels.append(value)
    for value in [UInt8(255), UInt8(255), UInt8(255), UInt8(255)]:
        pixels.append(value)
    var strip = Texture(2, 1, pixels^, CLAMP, BILINEAR, LINEAR, mipmapped=True)
    assert_equal(strip.levels, 2)
    var mixed = strip.wrapped_texel(0, 0, 1)
    assert_almost_equal(mixed.a, Float32(0.5), atol=Float64(0.004))
    # Levels are stored straight, like every other texel, so the color that
    # comes back is the white one alone -- pink would mean the red had been
    # averaged in despite contributing no light.
    assert_almost_equal(mixed.r, Float32(1.0), atol=Float64(0.01))
    assert_almost_equal(mixed.g, Float32(1.0), atol=Float64(0.01))


def test_a_fractional_level_lands_between_the_two_either_side() raises:
    var board = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=True
    )
    var lower = board.sample_at(0.3, 0.7, 1)
    var upper = board.sample_at(0.3, 0.7, 2)
    var between = board.sample_level(0.3, 0.7, 1.25)
    assert_almost_equal(
        between.r, mix_color(lower, upper, 0.25).r, atol=TOLERANCE
    )


def test_a_level_below_zero_reads_the_full_size_image() raises:
    # Magnification: the surface is bigger on screen than the image is, and
    # no amount of blurring improves that.
    var board = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=True
    )
    assert_equal(
        board.sample_level(0.1, 0.9, -3.0).r, board.sample_at(0.1, 0.9, 0).r
    )


def test_a_level_past_the_end_reads_the_smallest_image() raises:
    var board = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=True
    )
    assert_equal(
        board.sample_level(0.1, 0.9, 99.0).r, board.sample_at(0.1, 0.9, 3).r
    )


def test_a_texture_without_a_chain_ignores_the_level() raises:
    var plain = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=False
    )
    assert_equal(plain.sample_level(0.1, 0.9, 2.0).r, plain.sample(0.1, 0.9).r)


def test_the_blank_texture_is_white_at_every_level() raises:
    var nothing = Texture()
    assert_equal(nothing.sample_level(0.5, 0.5, 2.0).r, Float32(1))
    assert_equal(nothing.sample_at(0.5, 0.5, 2).r, Float32(1))
    assert_equal(nothing.wrapped_texel(3, 4, 2).r, Float32(1))


def test_a_chain_over_a_tall_strip_runs_out_of_width_first() raises:
    # 1x4: the width is already one at the top of the chain, so every level
    # after it halves only the height, and the four texels being averaged are
    # two rows of one rather than a square.
    var pixels = List[UInt8]()
    for step in range(4):
        var shade = UInt8(0)
        if step < 2:
            shade = 255
        for _ in range(3):  # pragma: no branch
            pixels.append(shade)
        pixels.append(255)
    var strip = Texture(1, 4, pixels^, CLAMP, NEAREST, LINEAR, mipmapped=True)
    assert_equal(strip.levels, 3)
    assert_equal(strip.level_width(1), 1)
    assert_equal(strip.level_height(1), 2)
    # The top pair averages to white, the bottom pair to black, and the whole
    # image to half.
    assert_almost_equal(
        strip.wrapped_texel(0, 0, 1).r, Float32(1.0), atol=Float64(0.004)
    )
    assert_almost_equal(
        strip.wrapped_texel(0, 1, 1).r, Float32(0.0), atol=Float64(0.004)
    )
    assert_almost_equal(
        strip.wrapped_texel(0, 0, 2).r, Float32(0.5), atol=Float64(0.004)
    )


def test_a_chain_over_a_wide_strip_runs_out_of_height_first() raises:
    # The other way round, because width and height are two separate shifts
    # and clamping only one of them at a floor of one is a mistake a square
    # image cannot show.
    var pixels = List[UInt8]()
    for step in range(4):
        var shade = UInt8(0)
        if step < 2:
            shade = 255
        for _ in range(3):  # pragma: no branch
            pixels.append(shade)
        pixels.append(255)
    var strip = Texture(4, 1, pixels^, CLAMP, NEAREST, LINEAR, mipmapped=True)
    assert_equal(strip.levels, 3)
    assert_equal(strip.level_width(1), 2)
    assert_equal(strip.level_height(1), 1)
    assert_almost_equal(
        strip.wrapped_texel(0, 0, 1).r, Float32(1.0), atol=Float64(0.004)
    )
    assert_almost_equal(
        strip.wrapped_texel(1, 0, 1).r, Float32(0.0), atol=Float64(0.004)
    )


def test_a_level_is_filtered_within_itself_as_well() raises:
    # Trilinear is bilinear twice: a bilinear texture's mip levels are read
    # bilinearly too, not snapped to a texel because they are small.
    var board = checkerboard(
        8,
        2,
        Color(255, 255, 255),
        Color(0, 0, 0),
        REPEAT,
        BILINEAR,
        mipmapped=True,
    )
    # A quarter of the way between two texel centers of level 1, which under
    # nearest would give one of them exactly.
    var between = board.sample_at(0.3125, 0.5, 1)
    var nearer = board.wrapped_texel(1, 1, 1)
    var further = board.wrapped_texel(2, 1, 1)
    assert_true(
        (between.r > nearer.r and between.r < further.r)
        or (between.r < nearer.r and between.r > further.r),
        "the level was not filtered within itself",
    )


# --- Odd extents in the chain -----------------------------------------------


def gray_strip(wide: Int, tall: Int, shades: List[UInt8]) raises -> Texture:
    """Return a mipmapped linear grayscale image from one byte per texel."""
    var pixels = List[UInt8]()
    for shade in shades:
        for _ in range(3):  # pragma: no branch
            pixels.append(shade)
        pixels.append(255)
    return Texture(wide, tall, pixels^, CLAMP, NEAREST, LINEAR, mipmapped=True)


def test_an_odd_width_keeps_its_last_column() raises:
    # A fixed 2x2 source block reads columns 0 and 1 of a three-wide image and
    # drops the third entirely: this reduced to black rather than to a third
    # of the light. Nothing reports it, because the block is in bounds.
    var strip = gray_strip(3, 1, [UInt8(0), UInt8(0), UInt8(255)])
    assert_equal(strip.levels, 2)
    assert_almost_equal(
        strip.wrapped_texel(0, 0, 1).r,
        Float32(1) / 3,
        atol=Float64(0.004),
    )


def test_an_odd_height_keeps_its_last_row() raises:
    # The same the other way up, because width and height reduce separately.
    var strip = gray_strip(1, 3, [UInt8(0), UInt8(0), UInt8(255)])
    assert_equal(strip.levels, 2)
    assert_almost_equal(
        strip.wrapped_texel(0, 0, 1).r,
        Float32(1) / 3,
        atol=Float64(0.004),
    )


def test_an_even_size_is_no_protection_against_an_odd_level() raises:
    # 6 -> 3 -> 1. The base is even and the first reduction is clean; the
    # second is the odd one, and it used to lose the last third of the image.
    # An even base size proves nothing about the rest of the chain.
    var strip = gray_strip(
        6, 1, [UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(255), UInt8(255)]
    )
    assert_equal(strip.levels, 3)
    # Level 1 is three texels: black, black, white.
    assert_almost_equal(
        strip.wrapped_texel(2, 0, 1).r, Float32(1), atol=Float64(0.004)
    )
    assert_almost_equal(
        strip.wrapped_texel(0, 0, 2).r,
        Float32(1) / 3,
        atol=Float64(0.004),
    )


def test_a_source_texel_can_be_shared_between_two_destinations() raises:
    # 5 -> 2. The middle column falls half in each half, and taking it wholly
    # into one would bias that side. Left half covers [0, 2.5) of five
    # columns: two black and half a white, so a fifth of the light.
    var strip = gray_strip(
        5, 1, [UInt8(0), UInt8(0), UInt8(255), UInt8(255), UInt8(255)]
    )
    assert_equal(strip.level_width(1), 2)
    assert_almost_equal(
        strip.wrapped_texel(0, 0, 1).r,
        Float32(0.5) / 2.5,
        atol=Float64(0.004),
    )
    assert_almost_equal(
        strip.wrapped_texel(1, 0, 1).r,
        Float32(2.5) / 2.5,
        atol=Float64(0.004),
    )


def test_an_odd_reduction_carries_alpha_by_area_too() raises:
    # The weights apply to coverage as well as color: three texels at alpha
    # 0, 0 and 1 average to a third covered, and the surviving color is the
    # one that was actually there.
    var pixels = List[UInt8]()
    for value in [UInt8(255), UInt8(0), UInt8(0), UInt8(0)]:
        pixels.append(value)
    for value in [UInt8(255), UInt8(0), UInt8(0), UInt8(0)]:
        pixels.append(value)
    for value in [UInt8(0), UInt8(255), UInt8(0), UInt8(255)]:
        pixels.append(value)
    var strip = Texture(3, 1, pixels^, CLAMP, NEAREST, LINEAR, mipmapped=True)
    var mixed = strip.wrapped_texel(0, 0, 1)
    assert_almost_equal(mixed.a, Float32(1) / 3, atol=Float64(0.004))
    # Green, not the red that contributes no light.
    assert_almost_equal(mixed.g, Float32(1), atol=Float64(0.01))
    assert_almost_equal(mixed.r, Float32(0), atol=Float64(0.01))


def test_a_non_square_odd_image_reduces_on_both_axes() raises:
    # 5x3: both extents are odd, and the two reductions have to agree about
    # which source rectangle a destination texel owns. A uniform image is the
    # check that no weight is lost or double counted -- any error in the area
    # arithmetic shows up as a level that is not the color it started as.
    var shades = List[UInt8]()
    for _ in range(15):  # pragma: no branch
        shades.append(UInt8(160))
    var image = gray_strip(5, 3, shades)
    for level in range(image.levels):  # pragma: no branch
        assert_almost_equal(
            image.wrapped_texel(0, 0, level).r,
            Float32(160) / 255,
            atol=Float64(0.004),
        )


# --- Direct level access ----------------------------------------------------


def test_reading_a_level_the_chain_does_not_have_is_rejected() raises:
    # An 8x8 chain is four levels and 340 bytes. Level 4's offset is exactly
    # 340 -- one past the end -- so this used to compute an out-of-range
    # index and read it.
    var board = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=True
    )
    assert_equal(board.levels, 4)
    with assert_raises():
        _ = board.wrapped_texel(0, 0, 4)
    with assert_raises():
        _ = board.sample_at(0.5, 0.5, 4)
    with assert_raises():
        _ = board.wrapped_texel(0, 0, -1)
    with assert_raises():
        _ = board.sample_at(0.5, 0.5, -1)


def test_a_texture_without_a_chain_has_only_level_zero() raises:
    var plain = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=False
    )
    _ = plain.sample_at(0.5, 0.5, 0)
    with assert_raises():
        _ = plain.sample_at(0.5, 0.5, 1)


def test_a_fractional_level_outside_the_chain_is_clamped_not_rejected() raises:
    # The other interface, and deliberately more forgiving: a footprint
    # routinely lands outside the chain and clamping is the answer there.
    var board = checkerboard(
        8, 2, Color(255, 255, 255), Color(0, 0, 0), mipmapped=True
    )
    assert_equal(
        board.sample_level(0.5, 0.5, 99.0).r, board.sample_at(0.5, 0.5, 3).r
    )


def test_a_fractional_level_lands_on_an_independently_worked_out_value() raises:
    # The other fractional-level test computes its expectation with the same
    # `mix_color` the implementation uses, so it checks the wiring and not
    # the arithmetic. This one is worked out by hand.
    #
    # A 4x1 linear strip of 0, 0, 255, 255 reduces to two texels of 0 and
    # 255, then to one of (0 + 1) / 2 = 0.5, which stores as byte
    # 0.5 * 255 + 0.5 = 128 and reads back as 128 / 255.
    #
    # At u = 0.25, nearest takes texel 0 of each level: 0 at level 1 and
    # 128 / 255 at level 2. A quarter of the way between them is
    # 128 / 255 * 0.25, every texel being opaque so alpha does not enter.
    var strip = gray_strip(4, 1, [UInt8(0), UInt8(0), UInt8(255), UInt8(255)])
    assert_equal(strip.levels, 3)
    assert_equal(strip.pixels[strip.level_offset(2)], UInt8(128))
    assert_almost_equal(
        strip.sample_level(0.25, 0.5, 1.25).r,
        Float32(128) / 255 * 0.25,
        atol=Float64(1e-6),
    )


def test_a_texture_refuses_a_color_space_it_cannot_decode() raises:
    # `UNKNOWN_SPACE` is a decoder's admission, not a way to read texels: it
    # has no ramp. `texture_from` refuses it with a message; the constructor
    # has to as well, since it is reachable directly.
    var pixels = List[UInt8](length=4, fill=255)
    with assert_raises():
        _ = Texture(1, 1, pixels^, REPEAT, NEAREST, UNKNOWN_SPACE)


def test_a_wrong_value_in_the_right_type_is_refused() raises:
    # `Wrap(9)` constructs, because a struct's fields are open; the texture
    # is where it is caught, and each named value has to pass on its own.
    assert_true(REPEAT.is_valid())
    assert_true(CLAMP.is_valid())
    assert_true(MIRROR.is_valid())
    assert_true(not Wrap(9).is_valid())
    assert_true(NEAREST.is_valid())
    assert_true(BILINEAR.is_valid())
    assert_true(not Filter(5).is_valid())
    assert_true(SRGB.is_decodable())
    assert_true(LINEAR.is_decodable())
    assert_true(not UNKNOWN_SPACE.is_decodable())
    assert_true(not ColorSpace(99).is_decodable())
    assert_true(COVERAGE.is_valid())
    assert_true(IGNORED.is_valid())
    assert_true(not Alpha(9).is_valid())
    var pixels = List[UInt8](length=4, fill=255)
    with assert_raises():
        _ = Texture(1, 1, pixels.copy(), Wrap(9))
    with assert_raises():
        _ = Texture(1, 1, pixels.copy(), REPEAT, Filter(5))
    with assert_raises():
        _ = Texture(1, 1, pixels.copy(), REPEAT, NEAREST, ColorSpace(99))
    with assert_raises():
        _ = Texture(1, 1, pixels.copy(), REPEAT, NEAREST, SRGB, False, Alpha(9))


def test_a_texture_edited_after_construction_can_be_checked_again() raises:
    # What the GPU upload does before it trusts the fields.
    var image = quad(REPEAT)
    image.validate()
    image.filter = Filter(5)
    with assert_raises():
        image.validate()
    image.filter = NEAREST
    image.wrap = Wrap(9)
    with assert_raises():
        image.validate()
    image.wrap = REPEAT
    image.color_space = ColorSpace(99)
    with assert_raises():
        image.validate()
    image.color_space = SRGB
    image.alpha = Alpha(9)
    with assert_raises():
        image.validate()


# --- alpha as coverage, or not at all ---------------------------------------


def one_texel(color: Color, alpha: Alpha, filter: Filter) raises -> Texture:
    """Return a one-texel texture of `color`, reading alpha as `alpha`."""
    var pixels = List[UInt8]()
    pixels.append(color.r)
    pixels.append(color.g)
    pixels.append(color.b)
    pixels.append(color.a)
    return Texture(1, 1, pixels^, REPEAT, filter, LINEAR, False, alpha)


def red_beside_hidden_green(mipmapped: Bool, alpha: Alpha) raises -> Texture:
    """Return an opaque red texel beside a fully transparent green one."""
    var pixels = List[UInt8]()
    for value in [UInt8(255), UInt8(0), UInt8(0), UInt8(255)]:
        pixels.append(value)
    for value in [UInt8(0), UInt8(255), UInt8(0), UInt8(0)]:
        pixels.append(value)
    return Texture(2, 1, pixels^, CLAMP, BILINEAR, LINEAR, mipmapped, alpha)


def test_a_texture_reads_alpha_as_coverage_by_default() raises:
    assert_equal(quad().alpha, COVERAGE)
    assert_equal(Texture().alpha, COVERAGE)
    assert_equal(
        checkerboard(
            2, 2, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED
        ).alpha,
        IGNORED,
    )


def test_ignoring_alpha_reads_every_alpha_byte_as_one() raises:
    # A white texel with no alpha. As coverage it is hidden: nearest reads
    # it straight, but bilinear premultiplies its four samples to nothing
    # and gives transparent black. Ignored, it is white under either filter,
    # and opaque.
    var white = Color(255, 255, 255, 0)
    var stepped = one_texel(white, COVERAGE, NEAREST).sample(0.5, 0.5)
    assert_equal(stepped.r, Float32(1))
    assert_equal(stepped.a, Float32(0))
    var blended = one_texel(white, COVERAGE, BILINEAR).sample(0.5, 0.5)
    assert_equal(blended.r, Float32(0))
    assert_equal(blended.a, Float32(0))
    for filter in [NEAREST, BILINEAR]:
        var shown = one_texel(white, IGNORED, filter).sample(0.5, 0.5)
        assert_equal(shown.r, Float32(1))
        assert_equal(shown.g, Float32(1))
        assert_equal(shown.b, Float32(1))
        assert_equal(shown.a, Float32(1))
    # The byte is still stored, for anyone reading texels directly.
    assert_equal(one_texel(white, IGNORED, NEAREST).texel(0, 0).a, UInt8(0))


def test_ignored_alpha_filters_color_straight() raises:
    # Opaque red beside transparent green. As coverage the answer is
    # half-covered red; ignored, it is the plain mean of the two colors,
    # which encodes to the (188, 188, 0) an emissive map should show.
    var covered = red_beside_hidden_green(False, COVERAGE).sample(0.5, 0.5)
    assert_almost_equal(covered.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(covered.g, Float32(0), atol=TOLERANCE)
    var between = red_beside_hidden_green(False, IGNORED).sample(0.5, 0.5)
    assert_almost_equal(between.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.b, Float32(0), atol=TOLERANCE)
    assert_equal(between.a, Float32(1))
    var shown = between.encode()
    assert_equal(shown.r, shown.g)
    assert_true(shown.r >= 186 and shown.r <= 190)
    assert_equal(shown.b, UInt8(0))


def test_alpha_bytes_do_not_reach_an_ignored_chain() raises:
    # Two images with the same color and different alpha bytes, both
    # ignoring alpha: the same at every level, and opaque everywhere.
    var solid = List[UInt8]()
    var holed = List[UInt8]()
    for y in range(4):
        for x in range(4):
            for image in [0, 1]:
                var alpha = UInt8(255)
                if image == 1:
                    alpha = UInt8((x * y * 37) % 256)
                var target = List[UInt8]()
                target.append(UInt8(x * 60))
                target.append(UInt8(y * 60))
                target.append(UInt8(100))
                target.append(alpha)
                if image == 0:
                    solid.extend(target^)
                else:
                    holed.extend(target^)
    var plain = Texture(4, 4, solid^, CLAMP, BILINEAR, LINEAR, True, IGNORED)
    var pierced = Texture(4, 4, holed^, CLAMP, BILINEAR, LINEAR, True, IGNORED)
    assert_equal(plain.levels, 3)
    assert_equal(pierced.levels, plain.levels)
    for level in range(3):
        for step in range(5):
            var u = Float32(step) / 4 + 0.1
            var v = 1 - u
            var one = plain.sample_at(u, v, level)
            var two = pierced.sample_at(u, v, level)
            assert_almost_equal(one.r, two.r, atol=TOLERANCE)
            assert_almost_equal(one.g, two.g, atol=TOLERANCE)
            assert_almost_equal(one.b, two.b, atol=TOLERANCE)
            assert_equal(two.a, Float32(1))
    var one = plain.sample_level(0.3, 0.7, 1.5)
    var two = pierced.sample_level(0.3, 0.7, 1.5)
    assert_almost_equal(one.r, two.r, atol=TOLERANCE)
    assert_almost_equal(one.g, two.g, atol=TOLERANCE)
    # And the chain stores an opaque alpha from level one on.
    assert_equal(pierced.wrapped_texel(0, 0, 1).a, Float32(1))
    assert_equal(pierced.texel(3, 3).a, UInt8((3 * 3 * 37) % 256))


def test_ignoring_alpha_copies_a_texture_into_the_other_mode() raises:
    # One image for both roles: the original keeps reading its alpha as
    # coverage, the copy ignores it, and the copy's chain is rebuilt from
    # the full-size image rather than inherited already averaged.
    var original = red_beside_hidden_green(True, COVERAGE)
    var copy = original.ignoring_alpha()
    assert_equal(original.alpha, COVERAGE)
    assert_equal(copy.alpha, IGNORED)
    assert_equal(copy.levels, original.levels)
    assert_equal(copy.levels, 2)
    assert_equal(copy.wrap, CLAMP)
    assert_equal(copy.filter, BILINEAR)
    assert_equal(copy.color_space, LINEAR)
    var kept = original.wrapped_texel(0, 0, 1)
    assert_almost_equal(kept.r, Float32(1), atol=Float64(0.01))
    assert_almost_equal(kept.a, Float32(0.5), atol=Float64(0.004))
    var rebuilt = copy.wrapped_texel(0, 0, 1)
    assert_almost_equal(rebuilt.r, Float32(0.5), atol=Float64(0.004))
    assert_almost_equal(rebuilt.g, Float32(0.5), atol=Float64(0.004))
    assert_equal(rebuilt.a, Float32(1))
    # A copy without a chain has none either. The blank texture's copy is
    # blank, and marked to ignore its alpha as any other copy is, so it is
    # accepted wherever the mode is checked.
    assert_equal(
        red_beside_hidden_green(False, COVERAGE).ignoring_alpha().levels, 1
    )
    var blank = Texture().ignoring_alpha()
    assert_true(blank.is_blank())
    assert_equal(blank.alpha, IGNORED)
    assert_equal(blank.sample(0.3, 0.7).r, Float32(1))


def test_a_texture_samples_where_the_geometry_says_until_moved() raises:
    # The transform is the identity by default, on a built texture and on
    # the blank one, so a texture that says nothing is sampled as before.
    assert_true(quad().uv_transform() == Matrix3())
    assert_true(Texture().uv_transform() == Matrix3())
    var placed = quad().uv_transform().transform_point(Vector2(0.25, 0.75))
    assert_almost_equal(placed.x, Float32(0.25), atol=TOLERANCE)
    assert_almost_equal(placed.y, Float32(0.75), atol=TOLERANCE)


def test_a_textures_transform_is_three_js_uv_transform() raises:
    var image = quad()
    image.offset = Vector2(0.5, 0.25)
    image.repeat = Vector2(2, 3)
    image.rotation = Angle(30.0, DEGREE)
    image.center = Vector2(0.5, 0.5)
    assert_true(
        image.uv_transform()
        == Matrix3.uv_transform(
            Vector2(0.5, 0.25),
            Vector2(2, 3),
            Angle(30.0, DEGREE),
            Vector2(0.5, 0.5),
        )
    )
    # Repeat alone scales the coordinates, so the image tiles.
    var tiled = quad()
    tiled.repeat = Vector2(2, 3)
    var placed = tiled.uv_transform().transform_point(Vector2(0.5, 0.5))
    assert_almost_equal(placed.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(placed.y, Float32(1.5), atol=TOLERANCE)


def test_a_copy_keeps_the_transform() raises:
    var image = quad()
    image.repeat = Vector2(2, 3)
    image.rotation = Angle(30.0, DEGREE)
    var copied = Texture(copy=image)
    assert_true(copied.uv_transform() == image.uv_transform())
    # The emissive copy too, so a base map and an emissive map from one
    # image are sampled at one place.
    var ignoring = image.ignoring_alpha()
    assert_true(ignoring.uv_transform() == image.uv_transform())
    assert_true(ignoring.uv_transform() != Matrix3())
    # The blank texture's copy is blank, and carries the transform too:
    # a transformed blank base map and its emissive copy must still agree.
    assert_true(Texture().ignoring_alpha().uv_transform() == Matrix3())
    var blank = Texture()
    blank.repeat = Vector2(2, 2)
    blank.offset = Vector2(0.5, 0)
    var glow = blank.ignoring_alpha()
    assert_true(glow.is_blank())
    assert_equal(glow.alpha, IGNORED)
    assert_true(glow.uv_transform() == blank.uv_transform())
    assert_true(glow.uv_transform() != Matrix3())


# --- textures from data and from renders -----------------------------------


def test_a_data_texture_quantizes_fractions_without_a_curve() raises:
    var ramp = data_texture(4, 1, [0.0, 0.25, 0.5, 1.0], channels=1)
    assert_equal(ramp.width, 4)
    assert_equal(ramp.height, 1)
    assert_true(ramp.color_space == LINEAR)
    assert_true(ramp.wrap == CLAMP)
    assert_true(ramp.filter == NEAREST)
    assert_equal(ramp.levels, 1)
    # One channel is red: green and blue are zero, as a `RedFormat`
    # texture samples, and alpha is one.
    assert_equal(ramp.texel(1, 0).r, UInt8(64))
    assert_equal(ramp.texel(1, 0).g, UInt8(0))
    assert_equal(ramp.texel(1, 0).b, UInt8(0))
    assert_equal(ramp.texel(1, 0).a, UInt8(255))
    assert_equal(ramp.texel(2, 0).r, UInt8(128))
    assert_equal(ramp.texel(3, 0).r, UInt8(255))
    # Linear, so the byte samples back as the fraction it was.
    assert_almost_equal(
        Float64(ramp.sample(0.625, 0.5).r), 128.0 / 255, atol=TOLERANCE
    )


def test_a_data_texture_reads_each_channel_count_its_own_way() raises:
    # Two channels are red and green, an `RGFormat` texture: the second
    # number lands in green, blue is zero and alpha is one.
    var two = data_texture(1, 1, [0.2, 0.8], channels=2)
    assert_equal(two.texel(0, 0).r, UInt8(51))
    assert_equal(two.texel(0, 0).g, UInt8(204))
    assert_equal(two.texel(0, 0).b, UInt8(0))
    assert_equal(two.texel(0, 0).a, UInt8(255))
    var sampled = two.sample(0.5, 0.5)
    assert_almost_equal(Float64(sampled.g), 204.0 / 255, atol=TOLERANCE)
    assert_almost_equal(Float64(sampled.b), 0.0, atol=TOLERANCE)
    assert_almost_equal(Float64(sampled.a), 1.0, atol=TOLERANCE)
    var three = data_texture(1, 1, [1.0, 0.5, 0.0], channels=3)
    assert_equal(three.texel(0, 0).r, UInt8(255))
    assert_equal(three.texel(0, 0).g, UInt8(128))
    assert_equal(three.texel(0, 0).b, UInt8(0))
    assert_equal(three.texel(0, 0).a, UInt8(255))
    var four = data_texture(1, 1, [1.0, 0.5, 0.0, 0.25])
    assert_equal(four.texel(0, 0).a, UInt8(64))
    # The other settings pass through, chain included.
    var tiled = data_texture(
        2,
        2,
        [0.0, 1.0, 1.0, 0.0],
        channels=1,
        wrap=REPEAT,
        filter=BILINEAR,
        mipmapped=True,
        alpha=IGNORED,
    )
    assert_true(tiled.wrap == REPEAT)
    assert_true(tiled.filter == BILINEAR)
    assert_true(tiled.alpha == IGNORED)
    assert_equal(tiled.levels, 2)


def test_a_data_texture_clamps_what_a_byte_cannot_hold() raises:
    var wide = data_texture(2, 1, [-3.0, 7.5], channels=1)
    assert_equal(wide.texel(0, 0).r, UInt8(0))
    assert_equal(wide.texel(1, 0).r, UInt8(255))


def test_a_data_texture_refuses_what_is_not_data() raises:
    with assert_raises(contains="dimensions must be positive"):
        _ = data_texture(0, 1, List[Float32](), channels=1)
    with assert_raises(contains="dimensions must be positive"):
        _ = data_texture(1, 0, List[Float32](), channels=1)
    with assert_raises(contains="one through four"):
        _ = data_texture(1, 1, [0.5], channels=0)
    with assert_raises(contains="one through four"):
        _ = data_texture(1, 1, [0.5], channels=5)
    with assert_raises(contains="does not match"):
        _ = data_texture(2, 1, [0.5], channels=1)
    with assert_raises(contains="finite"):
        _ = data_texture(1, 1, [nan[DType.float32]()], channels=1)
    with assert_raises(contains="finite"):
        _ = data_texture(1, 1, [inf[DType.float32]()], channels=1)


def test_a_rendered_image_becomes_a_texture_as_it_is() raises:
    var image = Framebuffer(2, 1, Color(0, 0, 0))
    image.set_pixel(0, 0, Color(255, 0, 0, 255))
    image.set_pixel(1, 0, Color(0, 0, 255, 128))
    var picture = texture_of(image)
    # A snapshot: the image edited afterward leaves the texture alone.
    image.set_pixel(0, 0, Color(0, 255, 0, 255))
    assert_equal(picture.texel(0, 0).r, UInt8(255))
    assert_equal(picture.texel(0, 0).g, UInt8(0))
    assert_equal(picture.width, 2)
    assert_equal(picture.height, 1)
    assert_true(picture.color_space == SRGB)
    assert_true(picture.wrap == CLAMP)
    assert_true(picture.filter == BILINEAR)
    assert_true(picture.alpha == COVERAGE)
    assert_equal(picture.levels, 2)
    assert_equal(picture.texel(0, 0).r, UInt8(255))
    assert_equal(picture.texel(1, 0).b, UInt8(255))
    assert_equal(picture.texel(1, 0).a, UInt8(128))
    # The bytes are sRGB and decode as such.
    assert_almost_equal(
        Float64(picture.sample(0.25, 0.5).r), 1.0, atol=TOLERANCE
    )
    var plain = texture_of(image, REPEAT, NEAREST, False, IGNORED)
    assert_true(plain.wrap == REPEAT)
    assert_true(plain.filter == NEAREST)
    assert_true(plain.alpha == IGNORED)
    assert_equal(plain.levels, 1)


def test_a_depth_texture_is_an_eight_bit_preview_of_perspective_depth() raises:
    # Planes at a tenth of a meter and a hundred: the NDC depth of a
    # camera-space distance d is (f + n) / (f - n) - 2 f n / ((f - n) d),
    # and a byte of window depth cannot tell forty meters from the far
    # plane. The numbers are worked out by hand, not read off the code.
    var near = Float64(0.1)
    var far = Float64(100)
    var depth = List[Float32]()
    for d in [1.0, 10.0, 40.0, 80.0, 100.0]:
        depth.append(
            Float32(
                (far + near) / (far - near)
                - 2 * far * near / ((far - near) * d)
            )
        )
    depth.append(inf[DType.float32]())
    var pixels = List[UInt8](length=6 * 4, fill=0)
    var seen = depth_texture_of(Framebuffer(6, 1, pixels^, depth^))
    assert_equal(seen.texel(0, 0).r, UInt8(230))
    assert_equal(seen.texel(1, 0).r, UInt8(253))
    assert_equal(seen.texel(2, 0).r, UInt8(255))
    assert_equal(seen.texel(3, 0).r, UInt8(255))
    assert_equal(seen.texel(4, 0).r, UInt8(255))
    assert_equal(seen.texel(5, 0).r, UInt8(255))
    # The buffer form refuses what a framebuffer could not hold.
    with assert_raises(contains="dimensions must be positive"):
        _ = depth_texture_of_buffer(0, 1, List[Float32]())
    with assert_raises(contains="dimensions must be positive"):
        _ = depth_texture_of_buffer(1, 0, List[Float32]())
    with assert_raises(contains="does not match"):
        _ = depth_texture_of_buffer(2, 1, [0.0])


def test_a_depth_texture_holds_window_space_depth_as_gray() raises:
    var pixels = List[UInt8](length=3 * 4, fill=0)
    var depth: List[Float32] = [-1.0, 0.0, inf[DType.float32]()]
    var image = Framebuffer(3, 1, pixels^, depth^)
    var seen = depth_texture_of(image)
    assert_true(seen.color_space == LINEAR)
    assert_true(seen.alpha == IGNORED)
    assert_true(seen.filter == NEAREST)
    assert_true(seen.wrap == CLAMP)
    assert_equal(seen.levels, 1)
    # The near plane is zero, the middle a half, and nothing drawn is the
    # far plane, one.
    assert_equal(seen.texel(0, 0).r, UInt8(0))
    assert_equal(seen.texel(1, 0).r, UInt8(128))
    assert_equal(seen.texel(1, 0).g, UInt8(128))
    assert_equal(seen.texel(1, 0).b, UInt8(128))
    assert_equal(seen.texel(1, 0).a, UInt8(255))
    assert_equal(seen.texel(2, 0).r, UInt8(255))
    var tiled = depth_texture_of(image, REPEAT)
    assert_true(tiled.wrap == REPEAT)


# --- anisotropy --------------------------------------------------------------------


def stripes() raises -> Texture:
    """Return an 8x8 image of vertical stripes, white and black columns,
    linear, nearest and chained."""
    var pixels = List[UInt8]()
    for _ in range(8):
        for x in range(8):
            var tone = UInt8(255) if x % 2 == 0 else UInt8(0)
            pixels.append(tone)
            pixels.append(tone)
            pixels.append(tone)
            pixels.append(255)
    return Texture(8, 8, pixels^, CLAMP, NEAREST, LINEAR, True)


def test_a_texture_allows_one_tap_unless_told_otherwise() raises:
    var image = quad()
    assert_equal(image.anisotropy, 1)
    assert_equal(Texture().anisotropy, 1)
    image.anisotropy = 8
    image.validate()
    var twin = Texture(copy=image)
    assert_equal(twin.anisotropy, 8)
    assert_equal(image.ignoring_alpha().anisotropy, 8)
    image.anisotropy = 0
    with assert_raises():
        image.validate()
    image.anisotropy = -3
    with assert_raises():
        image.validate()


def test_a_texture_reads_the_first_channel_unless_told_otherwise() raises:
    # three.js's `channel`: zero by default, set after construction, and
    # carried by every copy.
    var image = quad()
    assert_equal(image.channel, UV_CHANNEL_0)
    assert_equal(Texture().channel, UV_CHANNEL_0)
    image.channel = UV_CHANNEL_1
    image.validate()
    assert_equal(Texture(copy=image).channel, UV_CHANNEL_1)
    assert_equal(image.ignoring_alpha().channel, UV_CHANNEL_1)
    assert_true(UV_CHANNEL_0.is_valid())
    assert_true(UV_CHANNEL_1.is_valid())
    # A struct's fields are open, so a third channel constructs; the
    # texture refuses it.
    assert_false(UvChannel(2).is_valid())
    image.channel = UvChannel(2)
    with assert_raises(contains="channel"):
        image.validate()


def test_one_tap_reads_the_level_of_the_longer_axis() raises:
    # Four texels down and one across: level two, as `mip_level` says.
    var one = anisotropic_footprint(Vector2(0.125, 0), Vector2(0, 0.5), 8, 8, 1)
    assert_equal(one.taps, 1)
    assert_almost_equal(Float64(one.level), 2.0, atol=TOLERANCE)
    assert_equal(one.step.x, Float32(0))
    # A footprint of nothing is magnification, one tap at level zero.
    var none = anisotropic_footprint(Vector2(0, 0), Vector2(0, 0), 8, 8, 16)
    assert_equal(none.taps, 1)
    assert_equal(none.level, Float32(0))


def test_a_rounding_residue_does_not_tilt_the_long_axis() raises:
    # The two derivatives come from two interpolations that differ in
    # their last bit, so a derivative that is zero along one axis arrives
    # as a residue. The long axis stays exactly on the texel axis, so a
    # tap on a texel's edge reads the same texel however the compiler
    # rounded; a residue that is really a tilt still turns it.
    var residue = anisotropic_footprint(
        Vector2(0.125, 1e-9), Vector2(-1e-9, 0.5), 8, 8, 16
    )
    assert_equal(residue.taps, 4)
    assert_equal(residue.step.x, Float32(0))
    assert_almost_equal(Float64(residue.step.y), 0.125, atol=TOLERANCE)
    var across = anisotropic_footprint(
        Vector2(0.5, 1e-9), Vector2(1e-9, 0.125), 8, 8, 16
    )
    assert_equal(across.step.y, Float32(0))
    var tilted = anisotropic_footprint(
        Vector2(0.125, 0.01), Vector2(0, 0.5), 8, 8, 16
    )
    assert_true(tilted.step.x != 0, "a real tilt was snapped to the axis")
    # A residue of either sign is noise.
    var negative = anisotropic_footprint(
        Vector2(0.125, -1e-9), Vector2(0, 0.5), 8, 8, 16
    )
    assert_equal(negative.step.x, Float32(0))


def test_taps_cover_the_long_axis_at_the_short_axis_level() raises:
    # Four to one: four taps along y, each a texel apart, at level zero.
    var four = anisotropic_footprint(
        Vector2(0.125, 0), Vector2(0, 0.5), 8, 8, 16
    )
    assert_equal(four.taps, 4)
    assert_equal(four.level, Float32(0))
    assert_almost_equal(Float64(four.step.y), 0.125, atol=TOLERANCE)
    assert_equal(four.step.x, Float32(0))
    # Capped at the anisotropy, and the level then rises to cover the rest:
    # eight texels in two taps is four each, level two.
    var capped = anisotropic_footprint(
        Vector2(0.125, 0), Vector2(0, 1.0), 8, 8, 2
    )
    assert_equal(capped.taps, 2)
    assert_almost_equal(Float64(capped.level), 2.0, atol=TOLERANCE)
    assert_almost_equal(Float64(capped.step.y), 0.5, atol=TOLERANCE)
    # The long axis can be x, and a short axis of nothing takes every tap.
    var across = anisotropic_footprint(Vector2(0.5, 0), Vector2(0, 0), 8, 8, 16)
    assert_equal(across.taps, 4)
    assert_almost_equal(Float64(across.step.x), 0.125, atol=TOLERANCE)
    assert_equal(across.step.y, Float32(0))
    # A ratio that rounds up: three texels to one is three taps.
    var three = anisotropic_footprint(
        Vector2(0.125, 0), Vector2(0, 0.3), 8, 8, 16
    )
    assert_equal(three.taps, 3)
    # A short axis of two texels under a long one of four: two taps, each
    # reading two texels, so level one.
    var two = anisotropic_footprint(Vector2(0.25, 0), Vector2(0, 0.5), 8, 8, 16)
    assert_equal(two.taps, 2)
    assert_almost_equal(Float64(two.level), 1.0, atol=TOLERANCE)


def test_taps_along_a_stripe_keep_it_sharp() raises:
    # Reading a column of stripes four texels tall and one wide: one tap
    # reads level two, where the stripes have averaged to gray; four taps
    # read level zero down the column and find the stripe's own tone.
    var image = stripes()
    var tall = Vector2(0, 0.5)
    var thin = Vector2(0.125, 0)
    var gray = image.sample_footprint(
        0.0625, 0.5, anisotropic_footprint(thin, tall, 8, 8, 1)
    )
    assert_true(gray.r > 0.3 and gray.r < 0.7, "one tap was not gray")
    var white = image.sample_footprint(
        0.0625, 0.5, anisotropic_footprint(thin, tall, 8, 8, 4)
    )
    assert_almost_equal(Float64(white.r), 1.0, atol=TOLERANCE)
    var black = image.sample_footprint(
        0.1875, 0.5, anisotropic_footprint(thin, tall, 8, 8, 4)
    )
    assert_almost_equal(Float64(black.r), 0.0, atol=TOLERANCE)
    # A footprint built by hand with one tap is `sample_level`.
    var plain = image.sample_footprint(
        0.0625, 0.5, Footprint(0, 1, Vector2(0, 0))
    )
    assert_almost_equal(Float64(plain.r), 1.0, atol=TOLERANCE)
    # A blank texture is white however it is read.
    var blank = Texture().sample_footprint(
        0.5, 0.5, anisotropic_footprint(thin, tall, 8, 8, 4)
    )
    assert_equal(blank.r, Float32(1))


# --- the footprint is an ellipse, not two derivatives -----------------------


def test_a_rotated_screen_basis_keeps_an_anisotropic_footprint() raises:
    # A footprint sixteen texels long and one across, on a 64 by 64
    # texture. Axis aligned, it takes sixteen taps at level zero.
    var aligned = anisotropic_footprint(
        Vector2(16.0 / 64, 0), Vector2(0, 1.0 / 64), 64, 64, 16
    )
    assert_equal(aligned.taps, 16)
    assert_almost_equal(Float64(aligned.level), 0.0, atol=TOLERANCE)
    # Now turn the screen's basis forty-five degrees under the same
    # surface. The ellipse is the one above -- principal lengths sixteen
    # and one -- but the two derivatives now have equal length. Measuring
    # them calls the footprint round: one tap at level 3.5, which is a
    # surface blurring because of how it lies against the screen axes.
    var diagonal = Float32(1.0) / Float32(64.0 * 1.4142135623730951)
    var turned = anisotropic_footprint(
        Vector2(16.0 * diagonal, diagonal),
        Vector2(-16.0 * diagonal, diagonal),
        64,
        64,
        16,
    )
    assert_equal(turned.taps, 16)
    assert_almost_equal(Float64(turned.level), 0.0, atol=TOLERANCE)
    # And the taps run along the ellipse's own long axis, which is the
    # texture's x here whatever the screen is doing.
    assert_almost_equal(Float64(turned.step.x), 0.015625, atol=TOLERANCE)
    assert_almost_equal(Float64(turned.step.y), 0.0, atol=TOLERANCE)
    # The same ellipse stood on its end: sixteen texels down and one
    # across, again under a basis turned forty-five degrees. The long axis
    # is the texture's y now, and the step has to follow it there.
    var upright = anisotropic_footprint(
        Vector2(diagonal, 16.0 * diagonal),
        Vector2(diagonal, -16.0 * diagonal),
        64,
        64,
        16,
    )
    assert_equal(upright.taps, 16)
    assert_almost_equal(Float64(upright.level), 0.0, atol=TOLERANCE)
    assert_almost_equal(Float64(upright.step.x), 0.0, atol=TOLERANCE)
    assert_almost_equal(Float64(upright.step.y), 0.015625, atol=TOLERANCE)


def test_equal_derivatives_are_round_only_when_perpendicular() raises:
    # Two derivatives of the same length: a circle when they are square to
    # each other, and an ellipse when they are not. One tap against four.
    var square = anisotropic_footprint(
        Vector2(4.0 / 64, 0), Vector2(0, 4.0 / 64), 64, 64, 16
    )
    assert_equal(square.taps, 1)
    var sheared = anisotropic_footprint(
        Vector2(4.0 / 64, 0), Vector2(3.88 / 64, 1.0 / 64), 64, 64, 16
    )
    assert_true(
        sheared.taps > 1,
        "a sheared footprint of equal derivatives was called round",
    )


# --- the level follows the short axis ---------------------------------------


def test_rounding_the_tap_count_up_does_not_sharpen_the_level() raises:
    # Sixteen by sixteen is round: one tap at level four.
    var round_one = anisotropic_footprint(
        Vector2(16.0 / 64, 0), Vector2(0, 16.0 / 64), 64, 64, 16
    )
    assert_equal(round_one.taps, 1)
    assert_almost_equal(Float64(round_one.level), 4.0, atol=TOLERANCE)
    # A thousandth of a texel longer takes a second tap along the long
    # axis. The short axis still spans sixteen texels, so the level must
    # not move: dividing the major axis by the tap count gave 3.0 here,
    # nearly a whole level finer for a change of a thousandth.
    var barely = anisotropic_footprint(
        Vector2(16.001 / 64, 0), Vector2(0, 16.0 / 64), 64, 64, 16
    )
    assert_equal(barely.taps, 2)
    assert_almost_equal(Float64(barely.level), 4.0, atol=TOLERANCE)
    # And a quarter of a texel longer, the review's own case.
    var quarter = anisotropic_footprint(
        Vector2(16.25 / 64, 0), Vector2(0, 16.0 / 64), 64, 64, 16
    )
    assert_equal(quarter.taps, 2)
    assert_almost_equal(Float64(quarter.level), 4.0, atol=TOLERANCE)


def test_the_level_rises_when_the_taps_run_out() raises:
    # Sixty-four texels long and one across, with only sixteen taps
    # allowed: each tap has to cover four texels, so the level is two.
    var capped = anisotropic_footprint(
        Vector2(64.0 / 64, 0), Vector2(0, 1.0 / 64), 64, 64, 16
    )
    assert_equal(capped.taps, 16)
    assert_almost_equal(Float64(capped.level), 2.0, atol=TOLERANCE)


def test_an_anisotropy_above_the_cap_is_clamped_by_the_estimator() raises:
    # The estimator takes no more taps than `MAX_ANISOTROPY`, whatever it
    # is handed: a tap is per-fragment work on both backends.
    var asked = anisotropic_footprint(
        Vector2(64.0 / 64, 0), Vector2(0, 1.0 / 64), 64, 64, 1024
    )
    assert_equal(asked.taps, MAX_ANISOTROPY)


# --- a footprint built by hand is checked -----------------------------------


def test_a_hand_built_footprint_is_refused_before_it_is_sampled() raises:
    var image = stripes()
    # No taps at all, which the average would divide by.
    with assert_raises(contains="at least one tap"):
        _ = image.sample_footprint(0.5, 0.5, Footprint(0, 0, Vector2(0, 0)))
    with assert_raises(contains="at least one tap"):
        _ = image.sample_footprint(0.5, 0.5, Footprint(0, -4, Vector2(0, 0)))
    # More taps than any texture may ask for.
    with assert_raises(contains="MAX_ANISOTROPY"):
        _ = image.sample_footprint(
            0.5, 0.5, Footprint(0, MAX_ANISOTROPY + 1, Vector2(0, 0))
        )
    # A level or a step that is not a number.
    with assert_raises(contains="level must be finite"):
        _ = image.sample_footprint(
            0.5, 0.5, Footprint(inf[DType.float32](), 2, Vector2(0.1, 0))
        )
    with assert_raises(contains="step must be finite"):
        _ = image.sample_footprint(
            0.5,
            0.5,
            Footprint(0, 2, Vector2(inf[DType.float32](), 0)),
        )
    with assert_raises(contains="step must be finite"):
        _ = image.sample_footprint(
            0.5,
            0.5,
            Footprint(0, 2, Vector2(0, inf[DType.float32]())),
        )
    # A footprint that passes is sampled as it always was.
    var plain = image.sample_footprint(
        0.0625, 0.5, Footprint(0, 1, Vector2(0, 0))
    )
    assert_almost_equal(Float64(plain.r), 1.0, atol=TOLERANCE)


def test_a_texture_refuses_an_anisotropy_above_the_cap() raises:
    var image = stripes()
    image.anisotropy = MAX_ANISOTROPY
    image.validate()
    image.anisotropy = MAX_ANISOTROPY + 1
    with assert_raises(contains="MAX_ANISOTROPY"):
        image.validate()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
