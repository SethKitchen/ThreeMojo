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
from render.srgb import LINEAR, SRGB, srgb_to_linear
from render.target import RenderTarget
from render.texture import IGNORED, NEAREST, REPEAT
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


def test_a_data_pixel_is_stored_straight() raises:
    # A packed depth's alpha is data, and is often zero. Premultiplied, the
    # color would be lost; straight, it comes back.
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    var packed = FloatColor(0.5, 0.25, 0.75, 0.0)
    target.write(0, 0, packed, True)
    assert_equal(target.colors[0].r, Float32(0.5))
    assert_equal(target.shown(0, 0).a, UInt8(0))
    assert_equal(
        target.resolve().get_pixel(0, 0).r, FloatColor(0.5, 0, 0, 1).encode().r
    )
    # Read as light it is premultiplied, as every other pixel is.
    assert_equal(target.color_at(0, 0).r, Float32(0))
    assert_equal(target.light_at(0).b, Float32(0))
    # A light pixel is stored premultiplied, and read as it is stored.
    target.write(1, 0, FloatColor(1, 1, 1, 0.5))
    assert_equal(target.light_at(1).r, Float32(0.5))


def test_light_blended_over_a_data_pixel_mixes_with_its_light() raises:
    # Half a data pixel of alpha one half, under half of white: the data is
    # premultiplied before it mixes, and the result is light.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(1, 0, 0, 0.5), True)
    target.blend(0, 0, FloatColor(1, 1, 1, 0.5))
    assert_false(target.is_data(0, 0))
    assert_almost_equal(target.colors[0].r, Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(target.colors[0].g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(target.colors[0].a, Float32(0.75), atol=TOLERANCE)


def test_a_block_that_is_data_throughout_stays_straight() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0))
    for y in range(2):
        target.write(0, y, FloatColor(1, 0, 0, 0.5), True)
        target.write(1, y, FloatColor(0, 0, 1, 0.5), True)
    var small = target.downsampled(2)
    assert_true(small.is_data(0, 0))
    assert_almost_equal(small.colors[0].r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(small.colors[0].b, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(small.colors[0].a, Float32(0.5), atol=TOLERANCE)
    # A block of light stays premultiplied.
    var lit = RenderTarget(2, 2, Color(0, 0, 0))
    for y in range(2):
        lit.write(0, y, FloatColor(1, 0, 0, 0.5))
        lit.write(1, y, FloatColor(0, 0, 1, 0.5))
    var shrunk = lit.downsampled(2)
    assert_false(shrunk.is_data(0, 0))
    assert_almost_equal(shrunk.colors[0].r, Float32(0.25), atol=TOLERANCE)


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


def test_a_write_replaces_a_pixels_answer_and_a_blend_makes_it_light() raises:
    # A write replaces the pixel outright, so the pixel's answer becomes
    # the fragment's, either way round. A blend mixes into what is there,
    # and a mixture with light in it is light -- only light blends, because
    # a fragment showing data is refused the policy.
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(0.5, 0.5, 0.5, 1.0), True)
    assert_true(target.is_data(0, 0))
    target.write(0, 0, FloatColor(0.5, 0.5, 0.5, 1.0))
    assert_false(target.is_data(0, 0))
    # A translucent lit surface over a data pixel is the one mixture that
    # can happen, and it resolves as light.
    target.write(1, 0, FloatColor(0.5, 0.5, 0.5, 1.0), True)
    assert_true(target.is_data(1, 0))
    target.blend(1, 0, FloatColor(0.25, 0.25, 0.25, 0.5))
    assert_false(target.is_data(1, 0))


def test_a_blend_that_covers_nothing_changes_nothing_at_all() raises:
    # Source-over at alpha zero hides nothing and contributes nothing, so
    # it must not contribute an answer about what the pixel holds either.
    # It used to: the flag was assigned before the alpha was looked at, and
    # a fully transparent normal material could switch the tone mapping off
    # a lit pixel behind it. Twice white through Reinhard is two thirds;
    # unmapped it clamps to white, which is the bug this pins.
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(2.0, 2.0, 2.0, 1.0))
    var before = target.shown(0, 0, REINHARD_TONE_MAPPING)
    assert_equal(before.r, FloatColor(2.0 / 3, 0, 0, 1.0).encode().r)
    target.blend(0, 0, FloatColor(0.0, 0.0, 0.0, 0.0))
    var after = target.shown(0, 0, REINHARD_TONE_MAPPING)
    assert_equal(after.r, before.r)
    assert_false(target.is_data(0, 0))
    assert_equal(target.color_at(0, 0).r, Float32(2))
    assert_equal(target.color_at(0, 0).a, Float32(1))
    # And the other way round: an invisible fragment over a data pixel
    # leaves it data, so its bytes still come back unmapped.
    var shown = RenderTarget(1, 1, Color(0, 0, 0))
    shown.write(0, 0, FloatColor(2.0, 2.0, 2.0, 1.0), True)
    shown.blend(0, 0, FloatColor(9.0, 9.0, 9.0, 0.0))
    assert_true(shown.is_data(0, 0))
    assert_equal(shown.shown(0, 0, REINHARD_TONE_MAPPING).r, UInt8(255))
    assert_equal(shown.color_at(0, 0).r, Float32(2))
    # A negative alpha clamps to zero and is the same no-op.
    shown.blend(0, 0, FloatColor(9.0, 9.0, 9.0, -1.0))
    assert_true(shown.is_data(0, 0))
    assert_equal(shown.color_at(0, 0).r, Float32(2))


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


def test_a_target_becomes_a_texture_through_its_resolve() raises:
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(1, 0, 0, 1))
    _ = target.test_depth(0, 0, 0.0)
    var picture = target.texture()
    assert_true(picture.color_space == SRGB)
    assert_equal(picture.texel(0, 0).r, UInt8(255))
    assert_equal(picture.texel(1, 0).r, UInt8(0))
    # Through a curve, with the settings passed on.
    var dimmed = target.texture(
        REPEAT, NEAREST, False, IGNORED, 1, REINHARD_TONE_MAPPING, 1.0
    )
    assert_true(dimmed.wrap == REPEAT)
    assert_true(dimmed.alpha == IGNORED)
    assert_equal(dimmed.levels, 1)
    assert_equal(dimmed.texel(0, 0).r, UInt8(188))
    with assert_raises():
        _ = target.texture(workers=0)


def test_a_targets_depth_becomes_a_texture() raises:
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    _ = target.test_depth(0, 0, 0.0)
    var seen = target.depth_texture()
    assert_true(seen.color_space == LINEAR)
    assert_equal(seen.texel(0, 0).r, UInt8(128))
    assert_equal(seen.texel(1, 0).r, UInt8(255))
    assert_true(target.depth_texture(REPEAT).wrap == REPEAT)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
