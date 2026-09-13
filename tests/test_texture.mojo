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

from render.framebuffer import Color
from render.texture import (
    CLAMP,
    MIRROR,
    REPEAT,
    Texture,
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
