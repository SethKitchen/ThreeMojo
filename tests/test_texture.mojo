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

from render.framebuffer import Color, FloatColor
from render.texture import (
    BILINEAR,
    CLAMP,
    NEAREST,
    MIRROR,
    REPEAT,
    Texture,
    blend,
    checkerboard,
    wrap_index,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-6)


def quad(wrap: Int = REPEAT) raises -> Texture:
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
    var colours = [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 255),
    ]
    for index in range(4):
        pixels.append(colours[index].r)
        pixels.append(colours[index].g)
        pixels.append(colours[index].b)
        pixels.append(colours[index].a)
    return Texture(2, 2, pixels^, wrap)


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


def test_an_unknown_wrap_mode_is_rejected() raises:
    var pixels = List[UInt8](length=16, fill=0)
    with assert_raises():
        _ = Texture(2, 2, pixels^, 42)


def test_every_known_wrap_mode_is_accepted() raises:
    # Each has to be able to decide the outcome on its own.
    _ = quad(REPEAT)
    _ = quad(CLAMP)
    _ = quad(MIRROR)


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


def test_sampling_is_nearest_neighbour_not_blended() raises:
    # Either side of the midline gives one texel or the other, never a mix.
    var image = quad()
    var left = image.sample(0.49, 0.75)
    var right = image.sample(0.51, 0.75)
    assert_equal(left.r, Float32(1))
    assert_equal(left.g, Float32(0))
    assert_equal(right.r, Float32(0))
    assert_equal(right.g, Float32(1))


def test_eight_bit_texels_come_back_as_fractions() raises:
    var pixels = List[UInt8]()
    for value in [UInt8(51), UInt8(102), UInt8(153), UInt8(204)]:
        pixels.append(value)
    var image = Texture(1, 1, pixels^, REPEAT)
    assert_almost_equal(
        image.sample(0.5, 0.5).r, Float32(51) / 255, atol=TOLERANCE
    )
    assert_almost_equal(
        image.sample(0.5, 0.5).a, Float32(204) / 255, atol=TOLERANCE
    )


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
    # Every texel inside one square is the same colour; the edge is hard.
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
    var colours = [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 255),
    ]
    for index in range(4):
        pixels.append(colours[index].r)
        pixels.append(colours[index].g)
        pixels.append(colours[index].b)
        pixels.append(colours[index].a)
    return Texture(2, 2, pixels^, CLAMP, BILINEAR)


def test_a_bilinear_sample_on_a_texel_centre_is_that_texel() raises:
    # Texel centres sit at 0.25 and 0.75 on a 2x2 image. Landing exactly on
    # one must give it back unblended, or every image is offset.
    var image = smooth_quad()
    var middle = image.sample(0.25, 0.75)
    assert_almost_equal(middle.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(middle.g, Float32(0), atol=TOLERANCE)
    assert_almost_equal(middle.b, Float32(0), atol=TOLERANCE)


def test_a_bilinear_sample_between_two_texels_is_their_mean() raises:
    # Halfway between the top-left red and top-right green, along the row of
    # texel centres: half of each and nothing of the bottom row.
    var image = smooth_quad()
    var between = image.sample(0.5, 0.75)
    assert_almost_equal(between.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(between.b, Float32(0), atol=TOLERANCE)


def test_a_bilinear_sample_in_the_middle_is_all_four() raises:
    # The centre of the image is equidistant from all four texel centres.
    # red + green + blue + white, quartered: r = (1 + 0 + 0 + 1) / 4 = 0.5.
    var image = smooth_quad()
    var centre = image.sample(0.5, 0.5)
    assert_almost_equal(centre.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(centre.g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(centre.b, Float32(0.5), atol=TOLERANCE)


def test_nearest_and_bilinear_agree_on_texel_centres() raises:
    # The filters differ between centres, not at them.
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
    # fading out of it -- the neighbours are fetched through the wrap mode,
    # not clamped to the image after the fact.
    var image = smooth_quad()
    var beyond = image.sample(1.4, 0.75)
    assert_almost_equal(beyond.g, Float32(1), atol=TOLERANCE)
    assert_almost_equal(beyond.r, Float32(0), atol=TOLERANCE)


def test_a_repeating_bilinear_texture_blends_across_its_seam() raises:
    # The other side of the same rule: a tiled image's left edge blends with
    # its own right edge, which is what keeps a tiled surface seamless.
    var pixels = List[UInt8]()
    var colours = [Color(255, 0, 0), Color(0, 0, 255)]
    for index in range(2):
        pixels.append(colours[index].r)
        pixels.append(colours[index].g)
        pixels.append(colours[index].b)
        pixels.append(colours[index].a)
    var strip = Texture(2, 1, pixels^, REPEAT, BILINEAR)
    # At u = 0 the sample sits between the right-hand texel of the previous
    # tile and the left-hand texel of this one: half red, half blue.
    var seam = strip.sample(0.0, 0.5)
    assert_almost_equal(seam.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(seam.b, Float32(0.5), atol=TOLERANCE)


def test_an_unknown_filter_mode_is_rejected() raises:
    var pixels = List[UInt8](length=16, fill=0)
    with assert_raises():
        _ = Texture(2, 2, pixels^, REPEAT, 9)


def test_a_texture_keeps_the_filter_it_was_given() raises:
    assert_equal(quad().filter, NEAREST)
    assert_equal(smooth_quad().filter, BILINEAR)
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
