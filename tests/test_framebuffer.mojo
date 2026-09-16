# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.framebuffer`."""

from std.math import inf
from render.framebuffer import Color, FloatColor, Framebuffer, HSL
from render.srgb import LINEAR, SRGB, UNKNOWN_SPACE, srgb_to_linear
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

# Float32 through the sRGB curve and back is good to about six figures.
comptime TOLERANCE = Float64(1e-4)


def assert_linear(
    got: FloatColor, r: Float32, g: Float32, b: Float32, a: Float32 = 1.0
) raises:
    """Assert a float color matches on every channel, within tolerance.

    Args:
        got: The color to check.
        r: Expected red.
        g: Expected green.
        b: Expected blue.
        a: Expected alpha.

    Raises:
        Error: If any channel differs.
    """
    assert_almost_equal(got.r, r, atol=TOLERANCE)
    assert_almost_equal(got.g, g, atol=TOLERANCE)
    assert_almost_equal(got.b, b, atol=TOLERANCE)
    assert_almost_equal(got.a, a, atol=TOLERANCE)


def assert_hsl(
    got: HSL, hue: Float32, saturation: Float32, lightness: Float32
) raises:
    """Assert hue, saturation and lightness match, within tolerance.

    Args:
        got: The triple to check.
        hue: Expected hue.
        saturation: Expected saturation.
        lightness: Expected lightness.

    Raises:
        Error: If any of the three differs.
    """
    assert_almost_equal(got.hue, hue, atol=TOLERANCE)
    assert_almost_equal(got.saturation, saturation, atol=TOLERANCE)
    assert_almost_equal(got.lightness, lightness, atol=TOLERANCE)


def assert_color(got: Color, expected: Color) raises:
    """Assert that two colors match on every channel."""
    assert_equal(got.r, expected.r)
    assert_equal(got.g, expected.g)
    assert_equal(got.b, expected.b)
    assert_equal(got.a, expected.a)


def test_new_buffer_is_filled_with_clear_color() raises:
    var clear = Color(20, 24, 32)
    var fb = Framebuffer(4, 3, clear)
    for y in range(3):
        for x in range(4):
            assert_color(fb.get_pixel(x, y), clear)


def test_set_pixel_roundtrips() raises:
    var fb = Framebuffer(4, 3, Color(0, 0, 0))
    fb.set_pixel(2, 1, Color(255, 128, 32))
    assert_color(fb.get_pixel(2, 1), Color(255, 128, 32))


def test_set_pixel_does_not_disturb_neighbors() raises:
    var fb = Framebuffer(4, 3, Color(1, 2, 3))
    fb.set_pixel(2, 1, Color(255, 128, 32))
    assert_color(fb.get_pixel(1, 1), Color(1, 2, 3))
    assert_color(fb.get_pixel(3, 1), Color(1, 2, 3))
    assert_color(fb.get_pixel(2, 0), Color(1, 2, 3))
    assert_color(fb.get_pixel(2, 2), Color(1, 2, 3))


def test_rows_are_stored_top_down() raises:
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    fb.set_pixel(0, 0, Color(9, 9, 9))
    # The top-left pixel must be the first three bytes of the buffer.
    assert_equal(fb.pixels[0], UInt8(9))


def test_zero_width_is_rejected() raises:
    with assert_raises():
        _ = Framebuffer(0, 3, Color(0, 0, 0))


def test_negative_height_is_rejected() raises:
    with assert_raises():
        _ = Framebuffer(4, -1, Color(0, 0, 0))


def test_reads_past_each_edge_are_rejected() raises:
    var fb = Framebuffer(4, 3, Color(0, 0, 0))
    with assert_raises():
        _ = fb.get_pixel(-1, 0)
    with assert_raises():
        _ = fb.get_pixel(4, 0)
    with assert_raises():
        _ = fb.get_pixel(0, -1)
    with assert_raises():
        _ = fb.get_pixel(0, 3)


def test_writes_out_of_bounds_are_rejected() raises:
    var fb = Framebuffer(4, 3, Color(0, 0, 0))
    with assert_raises():
        fb.set_pixel(4, 3, Color(1, 1, 1))


def test_colors_are_opaque_unless_given_an_alpha() raises:
    assert_equal(Color(1, 2, 3).a, UInt8(255))
    assert_equal(Color(1, 2, 3, 128).a, UInt8(128))


def test_alpha_roundtrips_through_the_buffer() raises:
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    fb.set_pixel(1, 1, Color(10, 20, 30, 64))
    assert_equal(fb.get_pixel(1, 1).a, UInt8(64))


def test_buffer_allocates_four_bytes_per_pixel() raises:
    var fb = Framebuffer(4, 3, Color(0, 0, 0))
    assert_equal(len(fb.pixels), 4 * 3 * 4)


def test_existing_pixels_can_be_adopted() raises:
    var pixels = List[UInt8](length=2 * 2 * 4, fill=7)
    var fb = Framebuffer(2, 2, pixels^)
    assert_color(fb.get_pixel(1, 1), Color(7, 7, 7, 7))
    assert_equal(fb.width, 2)
    assert_equal(fb.height, 2)


def test_adopting_rejects_zero_width() raises:
    with assert_raises():
        _ = Framebuffer(0, 2, List[UInt8](length=0, fill=0))


def test_adopting_rejects_zero_height() raises:
    # The second half of the size guard needs its own case.
    with assert_raises():
        _ = Framebuffer(2, 0, List[UInt8](length=0, fill=0))


def test_adopting_rejects_a_buffer_that_is_too_short() raises:
    with assert_raises():
        _ = Framebuffer(2, 2, List[UInt8](length=4, fill=0))


def test_adopting_rejects_a_buffer_that_is_too_long() raises:
    with assert_raises():
        _ = Framebuffer(2, 2, List[UInt8](length=64, fill=0))


def test_depth_starts_at_infinity() raises:
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    # Anything at all must be nearer than an empty buffer.
    assert_true(fb.test_depth(0, 0, 1.0e30))


def test_a_nearer_fragment_wins_and_is_recorded() raises:
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    assert_true(fb.test_depth(0, 0, 0.5))
    assert_equal(fb.depth_at(0, 0), Float32(0.5))
    assert_true(fb.test_depth(0, 0, 0.2))
    assert_equal(fb.depth_at(0, 0), Float32(0.2))


def test_a_further_fragment_loses_and_changes_nothing() raises:
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    _ = fb.test_depth(0, 0, 0.2)
    assert_false(fb.test_depth(0, 0, 0.7))
    assert_equal(fb.depth_at(0, 0), Float32(0.2))


def test_an_equal_depth_loses() raises:
    # Ties go to whoever got there first, so coplanar surfaces do not fight.
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    _ = fb.test_depth(0, 0, 0.4)
    assert_false(fb.test_depth(0, 0, 0.4))


def test_depth_is_tracked_per_pixel() raises:
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    _ = fb.test_depth(0, 0, 0.1)
    assert_true(fb.test_depth(1, 1, 0.9))


def test_adopted_buffers_start_with_a_cleared_depth() raises:
    var fb = Framebuffer(2, 2, List[UInt8](length=2 * 2 * 4, fill=7))
    assert_true(fb.test_depth(0, 0, 1.0e30))


def test_depth_reads_out_of_bounds_are_rejected() raises:
    # All four edges: each operand of the guard needs its own case.
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    with assert_raises():
        _ = fb.depth_at(-1, 0)
    with assert_raises():
        _ = fb.depth_at(2, 0)
    with assert_raises():
        _ = fb.depth_at(0, -1)
    with assert_raises():
        _ = fb.depth_at(0, 2)


def test_depth_tests_out_of_bounds_are_rejected() raises:
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    with assert_raises():
        _ = fb.test_depth(-1, 0, 0.5)
    with assert_raises():
        _ = fb.test_depth(2, 0, 0.5)
    with assert_raises():
        _ = fb.test_depth(0, -1, 0.5)
    with assert_raises():
        _ = fb.test_depth(0, 2, 0.5)


# --- FloatColor -------------------------------------------------------------


def test_an_eight_bit_color_round_trips_through_floats() raises:
    # Every byte must survive the trip out to 0-1 and back, or shading would
    # shift colors simply by being computed.
    for value in range(256):
        var byte = UInt8(value)
        var back = FloatColor(of=Color(byte, byte, byte, byte)).quantize()
        assert_equal(back.r, byte)
        assert_equal(back.a, byte)


def test_quantizing_rounds_rather_than_truncating() raises:
    # 0.5/255 is exactly half a level: it must land on 1, not 0. Truncating
    # here is what used to turn a fully lit 200 into a 199.
    assert_equal(FloatColor(0.5 / 255, 0, 0).quantize().r, UInt8(1))
    assert_equal(FloatColor(1.4 / 255, 0, 0).quantize().r, UInt8(1))
    assert_equal(FloatColor(1.6 / 255, 0, 0).quantize().r, UInt8(2))


def test_quantizing_clamps_at_both_ends() raises:
    # Lighting can overshoot one, and an interpolated value can undershoot
    # zero by a rounding error. Neither may wrap around the byte.
    var bright = FloatColor(4.0, 2.0, 1.5, 1.0).quantize()
    assert_equal(bright.r, UInt8(255))
    assert_equal(bright.g, UInt8(255))
    var dark = FloatColor(-1.0, -0.001, 0.0, 1.0).quantize()
    assert_equal(dark.r, UInt8(0))
    assert_equal(dark.g, UInt8(0))
    assert_equal(dark.b, UInt8(0))


def test_scaling_dims_the_channels_and_keeps_alpha() raises:
    var half = FloatColor(1.0, 0.5, 0.25, 0.8).scaled(0.5)
    assert_equal(half.r, Float32(0.5))
    assert_equal(half.g, Float32(0.25))
    assert_equal(half.b, Float32(0.125))
    # Dimming a surface must not make it transparent.
    assert_equal(half.a, Float32(0.8))


def test_a_float_color_is_opaque_unless_told_otherwise() raises:
    assert_equal(FloatColor(0.0, 0.0, 0.0).a, Float32(1.0))


# --- adopting pixels together with their depth ------------------------------


# --- three.js's Color -------------------------------------------------------


def test_a_byte_color_from_hex_and_back() raises:
    assert_color(Color(hex=0xFF8000), Color(255, 128, 0))
    assert_color(Color(hex=0), Color(0, 0, 0))
    assert_color(Color(hex=0xFFFFFF), Color(255, 255, 255))
    assert_equal(Color(255, 128, 0).hex(), 0xFF8000)
    assert_equal(Color(hex=0x123456).hex(), 0x123456)
    # Alpha is not part of the number.
    assert_equal(Color(255, 128, 0, 7).hex(), 0xFF8000)
    with assert_raises():
        _ = Color(hex=-1)
    with assert_raises():
        _ = Color(hex=0x1000000)


def test_a_float_color_from_hex_is_decoded_and_encodes_back() raises:
    var orange = FloatColor(hex=0xFF8000)
    assert_linear(orange, 1, srgb_to_linear(Float32(128) / 255), 0, 1)
    assert_equal(orange.hex(), 0xFF8000)
    assert_equal(FloatColor(hex=0x808080).hex(), 0x808080)
    assert_equal(FloatColor(0, 0, 0).hex(), 0)
    with assert_raises():
        _ = FloatColor(hex=0x1000000)


def test_hsl_gives_the_primaries_and_wraps_the_hue() raises:
    assert_linear(FloatColor(hue=0, saturation=1, lightness=0.5), 1, 0, 0)
    assert_linear(FloatColor(hue=1.0 / 3, saturation=1, lightness=0.5), 0, 1, 0)
    assert_linear(FloatColor(hue=2.0 / 3, saturation=1, lightness=0.5), 0, 0, 1)
    assert_linear(FloatColor(hue=0.5, saturation=1, lightness=0.5), 0, 1, 1)
    # Once round the wheel and a quarter is a quarter, either way.
    var quarter = FloatColor(hue=0.25, saturation=1, lightness=0.5)
    assert_linear(
        FloatColor(hue=1.25, saturation=1, lightness=0.5),
        quarter.r,
        quarter.g,
        quarter.b,
    )
    assert_linear(
        FloatColor(hue=-0.75, saturation=1, lightness=0.5),
        quarter.r,
        quarter.g,
        quarter.b,
    )
    assert_linear(FloatColor(hue=1, saturation=1, lightness=0.5), 1, 0, 0)


def test_hsl_is_in_the_linear_working_space_unless_told_srgb() raises:
    # three.js's setHSL takes its three numbers in the working space, so a
    # half-lightness gray is linear 0.5 and encodes to 188. Asked in sRGB
    # it is the gray 0x808080 decodes to, 0.21404, and encodes to 128.
    var gray = FloatColor(hue=0.3, saturation=0, lightness=0.5)
    assert_linear(gray, 0.5, 0.5, 0.5)
    assert_equal(gray.encode().r, UInt8(188))
    var encoded = FloatColor(hue=0.3, saturation=0, lightness=0.5, space=SRGB)
    assert_linear(encoded, 0.21404, 0.21404, 0.21404)
    assert_equal(encoded.encode().r, UInt8(128))
    # A pastel, by hand: hue 0.1 at saturation 0.5 and lightness 0.7 has a
    # ceiling of 0.85 and a floor of 0.55, and the hue puts red at the
    # ceiling, green on the ramp at 0.73 and blue at the floor.
    var pastel = FloatColor(hue=0.1, saturation=0.5, lightness=0.7)
    assert_linear(pastel, 0.85, 0.73, 0.55)
    var decoded = FloatColor(hue=0.1, saturation=0.5, lightness=0.7, space=SRGB)
    assert_almost_equal(decoded.r, Float32(0.6920), atol=1e-3)
    assert_almost_equal(decoded.g, Float32(0.4919), atol=1e-3)
    assert_almost_equal(decoded.b, Float32(0.2633), atol=1e-3)
    # The getter has the same default and the same option.
    assert_hsl(FloatColor(0.5, 0.5, 0.5).hsl(), 0, 0, 0.5)
    assert_hsl(FloatColor(0.5, 0.5, 0.5).hsl(space=LINEAR), 0, 0, 0.5)
    assert_hsl(FloatColor(0.5, 0.5, 0.5).hsl(space=SRGB), 0, 0, 0.73536)
    assert_hsl(pastel.hsl(space=LINEAR), 0.1, 0.5, 0.7)
    assert_hsl(decoded.hsl(space=SRGB), 0.1, 0.5, 0.7)
    # Neither space is refused, in both directions.
    with assert_raises():
        _ = FloatColor(hue=0, saturation=1, lightness=0.5, space=UNKNOWN_SPACE)
    with assert_raises():
        _ = FloatColor(1, 0, 0).hsl(space=UNKNOWN_SPACE)


def test_hsl_lightness_and_saturation_are_clamped() raises:
    assert_linear(FloatColor(hue=0, saturation=1, lightness=1), 1, 1, 1)
    assert_linear(FloatColor(hue=0, saturation=1, lightness=0), 0, 0, 0)
    # A lightness above a half takes the other formula for the ceiling.
    var pale = FloatColor(hue=0, saturation=1, lightness=0.75)
    assert_linear(pale, 1, 0.5, 0.5)
    # Out of range is clamped, not wrapped.
    var over = FloatColor(hue=0, saturation=2, lightness=0.5)
    assert_linear(over, 1, 0, 0)
    assert_linear(
        FloatColor(hue=0, saturation=-1, lightness=0.5), 0.5, 0.5, 0.5
    )
    assert_linear(FloatColor(hue=0, saturation=1, lightness=-1), 0, 0, 0)
    assert_linear(FloatColor(hue=0, saturation=1, lightness=2), 1, 1, 1)


def test_hsl_round_trips_through_every_branch() raises:
    # One case per way the largest channel can fall: red with green
    # above blue and below it, green, blue; and either half of lightness.
    # In both spaces, since each is its own pair of conversions.
    var cases = List[HSL]()
    cases.append(HSL(0.05, 0.8, 0.3))
    cases.append(HSL(0.95, 0.6, 0.6))
    cases.append(HSL(0.4, 0.5, 0.7))
    cases.append(HSL(0.7, 0.9, 0.4))
    for index in range(len(cases)):
        var wanted = cases[index]
        var color = FloatColor(
            hue=wanted.hue,
            saturation=wanted.saturation,
            lightness=wanted.lightness,
        )
        assert_hsl(color.hsl(), wanted.hue, wanted.saturation, wanted.lightness)
        var encoded = FloatColor(
            hue=wanted.hue,
            saturation=wanted.saturation,
            lightness=wanted.lightness,
            space=SRGB,
        )
        assert_hsl(
            encoded.hsl(space=SRGB),
            wanted.hue,
            wanted.saturation,
            wanted.lightness,
        )
    # A gray has no hue and no saturation, whatever it was built with.
    assert_hsl(
        FloatColor(hue=0.3, saturation=0, lightness=0.25).hsl(), 0, 0, 0.25
    )
    assert_hsl(FloatColor(1, 1, 1).hsl(), 0, 0, 1)
    # A pure primary, from the linear side.
    assert_hsl(FloatColor(0, 0, 1).hsl(), 2.0 / 3, 1, 0.5)


def test_lerp_moves_every_channel_and_lerp_hsl_goes_round_the_wheel() raises:
    var color = FloatColor(1, 0, 0, 1)
    color.lerp(FloatColor(0, 0, 1, 0), 0.25)
    assert_linear(color, 0.75, 0, 0.25, 0.75)
    # Halfway from red to blue by hue is green, the long way round, as in
    # three.js; the alpha is this color's own.
    var red = FloatColor(1, 0, 0, 0.5)
    red.lerp_hsl(FloatColor(0, 0, 1), 0.5)
    assert_linear(red, 0, 1, 0, 0.5)


def test_offset_hsl_turns_the_hue_and_shifts_the_rest() raises:
    var color = FloatColor(1, 0, 0, 0.5)
    color.offset_hsl(1.0 / 3, 0, 0)
    assert_linear(color, 0, 1, 0, 0.5)
    # Drained of saturation it is the linear half gray, not the sRGB one.
    color.offset_hsl(0, -1, 0)
    assert_linear(color, 0.5, 0.5, 0.5, 0.5)
    color.offset_hsl(0, 0, 1)
    assert_linear(color, 1, 1, 1, 0.5)


def test_multiply_add_and_equality() raises:
    var color = FloatColor(0.5, 1, 0.25, 0.5)
    color.multiply(FloatColor(2, 0.5, 0, 0.1))
    assert_linear(color, 1, 0.5, 0, 0.5)
    color.add(FloatColor(0.5, 0.5, 1, 0.1))
    assert_linear(color, 1.5, 1, 1, 0.5)
    assert_true(FloatColor(1, 0.5, 0, 1) == FloatColor(1, 0.5, 0, 1))
    assert_true(FloatColor(1, 0.5, 0, 1) != FloatColor(1, 0.5, 0, 0.5))
    assert_false(FloatColor(1, 0.5, 0, 1) == FloatColor(0, 0.5, 0, 1))
    assert_false(FloatColor(1, 0.5, 0, 1) == FloatColor(1, 0, 0, 1))
    assert_false(FloatColor(1, 0.5, 0, 1) == FloatColor(1, 0.5, 1, 1))


def test_adopting_pixels_and_depth_keeps_both() raises:
    # What a GPU readback needs. The three-argument version fills depth with
    # infinity, which would report an empty scene over a rendered one.
    var pixels = List[UInt8](length=2 * 2 * 4, fill=7)
    var depth = List[Float32](length=2 * 2, fill=0.25)
    var image = Framebuffer(2, 2, pixels^, depth^)
    assert_equal(image.get_pixel(1, 1).r, UInt8(7))
    assert_equal(image.depth_at(0, 0), Float32(0.25))
    # And the depth is live: something further away must not overwrite it.
    assert_false(image.test_depth(0, 0, 0.9))
    assert_true(image.test_depth(0, 0, 0.1))


def test_adopting_a_depth_buffer_of_the_wrong_length_is_rejected() raises:
    var pixels = List[UInt8](length=2 * 2 * 4, fill=0)
    var depth = List[Float32](length=3, fill=0.0)
    with assert_raises():
        _ = Framebuffer(2, 2, pixels^, depth^)


def test_adopting_pixels_of_the_wrong_length_is_rejected() raises:
    var pixels = List[UInt8](length=5, fill=0)
    var depth = List[Float32](length=2 * 2, fill=0.0)
    with assert_raises():
        _ = Framebuffer(2, 2, pixels^, depth^)


def test_adopting_with_bad_dimensions_is_rejected() raises:
    # Both halves of the dimension check, so each can be shown to decide the
    # outcome on its own.
    var pixels = List[UInt8](length=4, fill=0)
    var depth = List[Float32](length=1, fill=0.0)
    with assert_raises():
        _ = Framebuffer(0, 1, pixels^, depth^)
    var more_pixels = List[UInt8](length=4, fill=0)
    var more_depth = List[Float32](length=1, fill=0.0)
    with assert_raises():
        _ = Framebuffer(1, -3, more_pixels^, more_depth^)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
