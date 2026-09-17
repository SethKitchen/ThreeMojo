# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.target`.

Two things were wrong here before this type existed, and both are asserted
against worked-out answers: compositing ignored the destination's alpha and
forced the result opaque, and every translucent layer round-tripped through
eight bits, so the losses compounded.
"""

from render.framebuffer import Color, FloatColor
from render.srgb import srgb_to_linear
from render.target import RenderTarget
from render.tonemap import (
    ACES_FILMIC_TONE_MAPPING,
    LINEAR_TONE_MAPPING,
    NO_TONE_MAPPING,
    REINHARD_TONE_MAPPING,
    ToneMapping,
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

comptime TOLERANCE = Float64(1e-5)


# --- the representation -----------------------------------------------------


def test_a_target_starts_at_its_clear_color() raises:
    var target = RenderTarget(2, 2, Color(40, 50, 60))
    assert_equal(target.shown(0, 0).r, UInt8(40))
    assert_equal(target.shown(1, 1).b, UInt8(60))
    assert_equal(target.depth_at(0, 0), inf[DType.float32]())


def test_dimensions_must_be_positive() raises:
    with assert_raises():
        _ = RenderTarget(0, 2, Color(0, 0, 0))
    with assert_raises():
        _ = RenderTarget(2, -1, Color(0, 0, 0))


def test_coordinates_outside_the_target_are_rejected() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0))
    with assert_raises():
        _ = target.shown(-1, 0)
    with assert_raises():
        _ = target.color_at(0, 2)
    with assert_raises():
        _ = target.depth_at(2, 0)
    with assert_raises():
        _ = target.depth_passes(0, -1, 0.5)
    with assert_raises():
        target.write(2, 2, FloatColor(1, 1, 1, 1))
    with assert_raises():
        target.blend(-1, -1, FloatColor(1, 1, 1, 1))
    with assert_raises():
        _ = target.test_depth(9, 9, 0.5)


def test_color_is_stored_premultiplied_and_linear() raises:
    # Both halves of the representation: scaled by coverage, and in light
    # rather than in display values.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(1.0, 0.0, 0.0, 0.5))
    var stored = target.color_at(0, 0)
    assert_almost_equal(stored.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(stored.a, Float32(0.5), atol=TOLERANCE)
    # And it comes back out as the straight color that went in.
    assert_equal(target.shown(0, 0).r, UInt8(255))
    assert_equal(target.shown(0, 0).a, UInt8(128))


def test_resolving_encodes_color_but_not_alpha() raises:
    # Half the light displays as 188; half the coverage is just 128.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(0.5, 0.5, 0.5, 0.5))
    var image = target.resolve()
    assert_equal(image.get_pixel(0, 0).r, UInt8(188))
    assert_equal(image.get_pixel(0, 0).a, UInt8(128))


def test_resolving_carries_the_depth_buffer() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0))
    _ = target.test_depth(1, 1, 0.25)
    var image = target.resolve()
    assert_equal(image.depth_at(1, 1), Float32(0.25))
    assert_equal(image.depth_at(0, 0), inf[DType.float32]())


# --- compositing ------------------------------------------------------------


def test_half_red_over_transparent_blue_keeps_no_blue() raises:
    # The failing case that prompted this type. The blue is invisible, so it
    # must contribute nothing; the old code gave opaque purple.
    var target = RenderTarget(1, 1, Color(0, 0, 255, 0))
    target.blend(0, 0, FloatColor(1, 0, 0, 0.5))
    var shown = target.shown(0, 0)
    assert_equal(shown.r, UInt8(255))
    assert_equal(shown.g, UInt8(0))
    assert_equal(shown.b, UInt8(0))
    assert_equal(shown.a, UInt8(128))


def test_nothing_over_a_transparent_pixel_leaves_it_transparent() raises:
    var target = RenderTarget(1, 1, Color(0, 0, 0, 0))
    target.blend(0, 0, FloatColor(1, 1, 1, 0.0))
    assert_equal(target.shown(0, 0).a, UInt8(0))


def test_half_white_over_opaque_black_is_half_the_light() raises:
    # 188, not 128: mixing the encoded bytes would give a fifth of the light
    # wearing the label of a half.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.blend(0, 0, FloatColor(1, 1, 1, 0.5))
    assert_equal(target.shown(0, 0).r, UInt8(188))
    assert_equal(target.shown(0, 0).a, UInt8(255))


def test_compositing_accumulates_alpha() raises:
    # Two half-covering layers leave three quarters covered.
    var target = RenderTarget(1, 1, Color(0, 0, 0, 0))
    target.blend(0, 0, FloatColor(1, 0, 0, 0.5))
    target.blend(0, 0, FloatColor(1, 0, 0, 0.5))
    assert_almost_equal(target.color_at(0, 0).a, Float32(0.75), atol=TOLERANCE)


def test_a_hundred_faint_layers_are_not_rounded_away() raises:
    # The precision contract. Each layer on its own rounds back to black in
    # eight bits, so accumulating in the framebuffer gave zero; the light
    # really adds up to 1 - 0.9999^100, about 0.00995, which displays as 25.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    for _ in range(100):
        target.blend(0, 0, FloatColor(1.0, 1.0, 1.0, 0.0001))
    assert_equal(target.shown(0, 0).r, UInt8(25))


def test_blending_clamps_an_alpha_outside_zero_to_one() raises:
    # Nothing in the renderer produces one, but this is public and an alpha
    # of two would otherwise subtract what is already there.
    var target = RenderTarget(1, 1, Color(10, 20, 30))
    target.blend(0, 0, FloatColor(1.0, 1.0, 1.0, 2.0))
    assert_equal(target.shown(0, 0).r, UInt8(255))
    var other = RenderTarget(1, 1, Color(10, 20, 30))
    other.blend(0, 0, FloatColor(1.0, 1.0, 1.0, -1.0))
    assert_equal(other.shown(0, 0).r, UInt8(10))


# --- depth ------------------------------------------------------------------


def test_claiming_a_depth_records_it_without_testing() raises:
    # The other half of a late depth write: a fragment an alpha test can
    # throw away tests without claiming, then claims once it survives.
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    assert_true(target.depth_passes(0, 0, 0.5))
    assert_equal(target.depth_at(0, 0), inf[DType.float32]())
    target.claim_depth(0, 0, 0.5)
    assert_equal(target.depth_at(0, 0), Float32(0.5))
    assert_false(target.depth_passes(0, 0, 0.7))
    # It tests nothing, so it can move the depth further away. Only a
    # fragment that has already passed calls it.
    target.claim_depth(0, 0, 0.9)
    assert_equal(target.depth_at(0, 0), Float32(0.9))
    with assert_raises():
        target.claim_depth(2, 0, 0.5)


def test_writing_depth_claims_it_and_passing_does_not() raises:
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    assert_true(target.depth_passes(0, 0, 0.5))
    assert_true(target.depth_passes(0, 0, 0.5))
    assert_equal(target.depth_at(0, 0), inf[DType.float32]())
    assert_true(target.test_depth(0, 0, 0.5))
    assert_equal(target.depth_at(0, 0), Float32(0.5))
    assert_false(target.test_depth(0, 0, 0.9))
    assert_false(target.depth_passes(0, 0, 0.9))
    assert_true(target.depth_passes(0, 0, 0.1))


def test_resolving_on_several_workers_matches_one() raises:
    var target = RenderTarget(7, 5, Color(20, 24, 32, 200))
    for y in range(5):
        for x in range(7):
            target.blend(
                x,
                y,
                FloatColor(
                    Float32(x) / 7, Float32(y) / 5, 0.5, Float32(x + y) / 12
                ),
            )
    var alone = target.resolve()
    var crowd = target.resolve(4)
    for y in range(5):
        for x in range(7):
            var one = alone.get_pixel(x, y)
            var many = crowd.get_pixel(x, y)
            assert_equal(one.r, many.r)
            assert_equal(one.g, many.g)
            assert_equal(one.b, many.b)
            assert_equal(one.a, many.a)


def test_more_workers_than_pixels_still_resolves() raises:
    var target = RenderTarget(2, 1, Color(200, 100, 50))
    var image = target.resolve(16)
    assert_equal(image.get_pixel(1, 0).r, UInt8(200))


def test_resolving_needs_at_least_one_worker() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0))
    with assert_raises():
        _ = target.resolve(0)


# --- tone mapping -------------------------------------------------------------


def test_resolving_can_tone_map_the_light() raises:
    # Twice white in the buffer clamps to white without a curve. Reinhard
    # shows two thirds of the light. The linear curve at a half exposure
    # shows one, white again, and at a quarter shows a half.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(2.0, 2.0, 2.0, 1.0))
    assert_equal(target.resolve().get_pixel(0, 0).r, UInt8(255))
    var squeezed = target.resolve(1, REINHARD_TONE_MAPPING)
    var expected = FloatColor(2.0 / 3, 2.0 / 3, 2.0 / 3, 1.0).encode()
    assert_equal(squeezed.get_pixel(0, 0).r, expected.r)
    assert_equal(target.shown(0, 0, REINHARD_TONE_MAPPING).g, expected.g)
    var exposed = target.resolve(1, LINEAR_TONE_MAPPING, 0.5)
    assert_equal(exposed.get_pixel(0, 0).r, UInt8(255))
    var dim = target.resolve(1, LINEAR_TONE_MAPPING, 0.25)
    assert_equal(
        dim.get_pixel(0, 0).r, FloatColor(0.5, 0.5, 0.5, 1.0).encode().r
    )
    # Without a curve the exposure is not applied, as in three.js.
    var plain = target.resolve(1, NO_TONE_MAPPING, 0.25)
    assert_equal(plain.get_pixel(0, 0).r, UInt8(255))


def test_tone_mapping_sees_the_straight_color_and_keeps_alpha() raises:
    # A half-covered pixel holding twice white: the curve is applied to the
    # straight color, two, and not to the premultiplied one, and the
    # coverage is left as it was.
    var target = RenderTarget(1, 1, Color(0, 0, 0, 0))
    target.write(0, 0, FloatColor(2.0, 2.0, 2.0, 0.5))
    var shown = target.shown(0, 0, REINHARD_TONE_MAPPING)
    assert_equal(shown.r, FloatColor(2.0 / 3, 0, 0, 1.0).encode().r)
    assert_equal(shown.a, UInt8(128))
    var image = target.resolve(1, REINHARD_TONE_MAPPING)
    assert_equal(image.get_pixel(0, 0).r, shown.r)
    assert_equal(image.get_pixel(0, 0).a, UInt8(128))


def test_tone_mapping_on_several_workers_matches_one() raises:
    var target = RenderTarget(7, 5, Color(20, 24, 32))
    for y in range(5):
        for x in range(7):
            target.write(
                x, y, FloatColor(Float32(x) * 0.5, Float32(y) * 0.7, 1.5, 1.0)
            )
    var alone = target.resolve(1, ACES_FILMIC_TONE_MAPPING, 1.3)
    var crowd = target.resolve(4, ACES_FILMIC_TONE_MAPPING, 1.3)
    var changed = 0
    var plain = target.resolve()
    for y in range(5):
        for x in range(7):
            var one = alone.get_pixel(x, y)
            var many = crowd.get_pixel(x, y)
            assert_equal(one.r, many.r)
            assert_equal(one.g, many.g)
            assert_equal(one.b, many.b)
            if plain.get_pixel(x, y).b != one.b:
                changed += 1
    # And the curve really changed the image.
    assert_true(changed > 20, "the curve changed almost nothing")


def test_resolving_refuses_an_unknown_curve_or_a_negative_exposure() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0))
    with assert_raises():
        _ = target.resolve(1, ToneMapping(9))
    with assert_raises():
        _ = target.resolve(1, LINEAR_TONE_MAPPING, -1.0)
    with assert_raises():
        _ = target.shown(0, 0, ToneMapping(9))
    with assert_raises():
        _ = target.shown(0, 0, LINEAR_TONE_MAPPING, -1.0)
    # A zero exposure is a legal black.
    var black = target.resolve(1, LINEAR_TONE_MAPPING, 0.0)
    assert_equal(black.get_pixel(0, 0).r, UInt8(0))


def test_tone_mapping_is_applied_after_compositing_not_per_fragment() raises:
    # Half-transparent light of two over opaque black, then Reinhard: the
    # composite is one, and the curve shows a half, byte 188. Tone mapping
    # each fragment first would give two thirds, then a third, byte 154.
    # The placement is the policy, and this pins it.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.blend(0, 0, FloatColor(2.0, 2.0, 2.0, 0.5))
    var late = target.shown(0, 0, REINHARD_TONE_MAPPING)
    assert_equal(late.r, FloatColor(0.5, 0.5, 0.5, 1.0).encode().r)
    assert_equal(late.r, UInt8(188))
    var early = FloatColor(1.0 / 3, 1.0 / 3, 1.0 / 3, 1.0).encode().r
    assert_true(late.r != early, "the curve was applied per fragment")
    assert_equal(
        target.resolve(1, REINHARD_TONE_MAPPING).get_pixel(0, 0).r, late.r
    )


def test_resolving_refuses_an_exposure_that_is_not_finite() raises:
    # Infinity over one plus infinity is not a number, and nothing
    # downstream could say so.
    var target = RenderTarget(2, 2, Color(0, 0, 0))
    with assert_raises():
        _ = target.resolve(1, REINHARD_TONE_MAPPING, inf[DType.float32]())
    with assert_raises():
        _ = target.resolve(1, REINHARD_TONE_MAPPING, nan[DType.float32]())
    with assert_raises():
        _ = target.shown(0, 0, LINEAR_TONE_MAPPING, inf[DType.float32]())
    with assert_raises():
        _ = target.shown(0, 0, LINEAR_TONE_MAPPING, nan[DType.float32]())


# --- pixels that hold data --------------------------------------------------


def test_a_cleared_pixel_holds_light_and_not_data() raises:
    var target = RenderTarget(2, 2, Color(40, 50, 60))
    assert_false(target.is_data(0, 0))
    assert_false(target.is_data(1, 1))
    with assert_raises():
        _ = target.is_data(2, 0)


def test_writing_or_blending_says_whether_a_pixel_holds_data() raises:
    # A normal material writes bytes a display must show as they are, and
    # the last fragment into a pixel decides. Either call can say so, and
    # either can take it back.
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(0.5, 0.5, 0.5, 1.0), True)
    assert_true(target.is_data(0, 0))
    target.write(0, 0, FloatColor(0.5, 0.5, 0.5, 1.0))
    assert_false(target.is_data(0, 0))
    target.blend(1, 0, FloatColor(0.5, 0.5, 0.5, 1.0), True)
    assert_true(target.is_data(1, 0))
    target.blend(1, 0, FloatColor(0.5, 0.5, 0.5, 1.0))
    assert_false(target.is_data(1, 0))


def test_a_data_pixel_is_encoded_but_never_tone_mapped() raises:
    # Twice white through Reinhard is two thirds as light; as data it is
    # clamped and encoded like any byte, because a curve would make a
    # normal lie about its own numbers.
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(2.0, 2.0, 2.0, 1.0), True)
    target.write(1, 0, FloatColor(2.0, 2.0, 2.0, 1.0))
    var squeezed = target.resolve(1, REINHARD_TONE_MAPPING)
    var compressed = FloatColor(2.0 / 3, 2.0 / 3, 2.0 / 3, 1.0).encode()
    assert_equal(squeezed.get_pixel(0, 0).r, UInt8(255))
    assert_equal(squeezed.get_pixel(1, 0).r, compressed.r)
    # `shown` is the same read for one pixel and must agree.
    assert_equal(target.shown(0, 0, REINHARD_TONE_MAPPING).r, UInt8(255))
    assert_equal(target.shown(1, 0, REINHARD_TONE_MAPPING).r, compressed.r)
    # The exposure does not reach a data pixel either.
    var exposed = target.resolve(1, LINEAR_TONE_MAPPING, 0.25)
    assert_equal(exposed.get_pixel(0, 0).r, UInt8(255))
    assert_equal(
        exposed.get_pixel(1, 0).r, FloatColor(0.5, 0, 0, 1.0).encode().r
    )


def test_data_pixels_resolve_the_same_on_several_workers() raises:
    # Each band reads the same flag per pixel, so a curve cannot reach a
    # data pixel on one thread and miss it on another.
    var target = RenderTarget(7, 5, Color(20, 24, 32))
    for y in range(5):
        for x in range(7):
            var holds_data = (x + y) % 2 == 0
            target.write(
                x,
                y,
                FloatColor(Float32(x) * 0.4, Float32(y) * 0.6, 1.5, 1.0),
                holds_data,
            )
    var alone = target.resolve(1, ACES_FILMIC_TONE_MAPPING, 1.3)
    var crowd = target.resolve(4, ACES_FILMIC_TONE_MAPPING, 1.3)
    var curved = 0
    for y in range(5):
        for x in range(7):
            var one = alone.get_pixel(x, y)
            var many = crowd.get_pixel(x, y)
            assert_equal(one.r, many.r)
            assert_equal(one.g, many.g)
            assert_equal(one.b, many.b)
            if not target.is_data(x, y):
                curved += 1
    assert_true(curved > 10, "no pixel was left to the curve")
    # And the curve really did reach the pixels that hold light: a data
    # pixel of 1.5 blue clamps to 255, a light one does not.
    assert_equal(alone.get_pixel(0, 0).b, UInt8(255))
    assert_true(alone.get_pixel(1, 0).b < 255, "the curve missed a pixel")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
