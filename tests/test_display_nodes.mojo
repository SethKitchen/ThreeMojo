# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `postprocessing.display_nodes`: three.js's TSL display nodes
as composer passes, against worked-out answers on hand-built frames."""

from postprocessing.composer import (
    ANAMORPHIC,
    BOX_BLUR,
    CHROMATIC_ABERRATION,
    GAUSSIAN_BLUR,
    HASH_BLUR,
    LENSFLARE,
    EffectComposer,
    Pass,
    anamorphic_pass,
    box_blur_pass,
    check_pass,
    chromatic_aberration_pass,
    gaussian_blur_pass,
    hash_blur_pass,
    lensflare_pass,
    render_pass,
)
from postprocessing.display_nodes import (
    DisplaySettings,
    anamorphic_light,
    bayer16,
    box_blur_light,
    check_display,
    chromatic_aberration_light,
    gaussian_blur_light,
    gaussian_coefficients,
    hash_blur_light,
    lensflare_light,
    scaled_size,
)
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer
from units.si import Angle, DEGREE, Length, METER
from render.target import RenderTarget
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime W = 12
comptime H = 8


def even(color: FloatColor) raises -> RenderTarget:
    """Return a frame of one color."""
    var frame = RenderTarget(W, H, Color(0, 0, 0, 255))
    for slot in range(len(frame.colors)):
        frame.colors[slot] = color
    return frame^


def one_bright() raises -> RenderTarget:
    """Return a black frame with one bright pixel near the middle."""
    var frame = even(FloatColor(0, 0, 0, 1))
    frame.colors[4 * W + 6] = FloatColor(4, 4, 4, 1)
    return frame^


def test_the_gaussian_weights_are_three_js_s() raises:
    # `_getCoefficients( 3 + 2 * 4 )`: eleven weights, not normalized.
    var weights = gaussian_coefficients(4)
    assert_equal(len(weights), 11)
    assert_almost_equal(weights[0], Float32(0.10880182), atol=1e-6)
    assert_almost_equal(weights[1], Float32(0.10482979), atol=1e-6)
    assert_almost_equal(weights[10], Float32(0.0026393160), atol=1e-6)
    # An even frame comes out scaled by the weights' sum, twice, its
    # alpha as well; the straight color stored premultiplied is scaled by
    # the alpha once more.
    var frame = even(FloatColor(0.5, 0.5, 0.5, 1))
    gaussian_blur_light(frame, DisplaySettings())
    var twice = Float32(0.99186108)
    assert_almost_equal(frame.colors[3 * W + 5].a, twice, atol=1e-4)
    assert_almost_equal(
        frame.colors[3 * W + 5].r, 0.5 * twice * twice, atol=1e-4
    )
    # At half the size, and premultiplied, it still blurs.
    var settings = DisplaySettings()
    settings.resolution_scale = 0.5
    settings.premultiplied_alpha = True
    var spread = one_bright()
    gaussian_blur_light(spread, settings)
    assert_true(spread.colors[4 * W + 8].r > 0)
    assert_equal(scaled_size(W, 0.5), 6)
    # A sigma of zero is one weight: the frame times it.
    var sharp = DisplaySettings()
    sharp.sigma = 0
    var still = even(FloatColor(0.5, 0.5, 0.5, 1))
    gaussian_blur_light(still, sharp)
    assert_true(still.colors[3 * W + 5].a > 0)
    assert_equal(scaled_size(1, 0.1), 1)


def test_the_box_and_hash_blurs_keep_an_even_frame() raises:
    var color = FloatColor(0.25, 0.5, 0.75, 1)
    var boxed = even(color)
    box_blur_light(boxed, DisplaySettings())
    assert_almost_equal(boxed.colors[20].g, Float32(0.5), atol=1e-5)
    var hashed = even(color)
    hash_blur_light(hashed, DisplaySettings())
    assert_almost_equal(hashed.colors[20].b, Float32(0.75), atol=1e-5)
    # One bright pixel spreads into its box.
    var settings = DisplaySettings()
    settings.size = 1
    settings.premultiplied_alpha = True
    var spread = one_bright()
    box_blur_light(spread, settings)
    assert_almost_equal(spread.colors[4 * W + 7].r, Float32(4.0 / 9), atol=1e-5)


def test_chromatic_aberration_parts_the_channels_away_from_the_center() raises:
    # A frame whose red rises to the right: away from the center, red is
    # read further out, so it rises.
    var frame = RenderTarget(W, H, Color(0, 0, 0, 255))
    for y in range(H):
        for x in range(W):
            var value = Float32(x) / Float32(W)
            frame.colors[y * W + x] = FloatColor(value, value, value, 1)
    var before = frame.colors[3 * W + 10]
    chromatic_aberration_light(frame, DisplaySettings())
    var after = frame.colors[3 * W + 10]
    assert_true(after.r > before.r)
    assert_true(after.b < before.b)
    assert_almost_equal(after.g, before.g, atol=1e-6)


def test_the_streak_and_the_flare_add_only_bright_light() raises:
    var dark = even(FloatColor(0.1, 0.1, 0.1, 1))
    anamorphic_light(dark, DisplaySettings())
    assert_almost_equal(dark.colors[10].r, Float32(0.1), atol=1e-6)
    lensflare_light(dark, DisplaySettings())
    assert_almost_equal(dark.colors[10].g, Float32(0.1), atol=1e-6)
    # A bright pixel streaks blue along its row: the taps are three
    # pixels apart, so the pixel three to its left reads it.
    var lit = one_bright()
    anamorphic_light(lit, DisplaySettings())
    assert_true(lit.colors[4 * W + 3].b > 0)
    assert_almost_equal(lit.colors[4 * W + 3].g, Float32(0), atol=1e-6)
    # And throws ghosts through the center.
    var flared = one_bright()
    var settings = DisplaySettings()
    settings.ghost_attenuation = 1
    settings.down_sample_ratio = 1
    lensflare_light(flared, settings)
    var added = 0
    for slot in range(len(flared.colors)):
        if slot != 4 * W + 6 and flared.colors[slot].r > 0:
            added += 1
    assert_true(added > 0)
    # No ghosts add nothing.
    var ghostless = one_bright()
    settings.ghost_samples = 0
    lensflare_light(ghostless, settings)
    assert_almost_equal(ghostless.colors[0].r, Float32(0), atol=1e-6)


def test_bayer16_is_three_js_s_matrix() raises:
    assert_equal(bayer16(0, 0), Float32(0))
    assert_almost_equal(bayer16(1, 0), Float32(128.0 / 255), atol=1e-7)
    assert_almost_equal(bayer16(15, 15), Float32(85.0 / 255), atol=1e-7)
    # It wraps every sixteen, both ways.
    assert_equal(bayer16(17, 0), bayer16(1, 0))
    assert_equal(bayer16(-1, 0), bayer16(15, 0))


def test_the_display_settings_and_builders_are_checked() raises:
    check_display(DisplaySettings())
    var bad = DisplaySettings()
    bad.sigma = -1
    with assert_raises(contains="sigma"):
        check_display(bad)
    bad = DisplaySettings()
    bad.resolution_scale = 0
    with assert_raises(contains="positive"):
        check_display(bad)
    bad = DisplaySettings()
    bad.separation = -1
    with assert_raises(contains="negative"):
        check_display(bad)
    bad = DisplaySettings()
    bad.size = -1
    with assert_raises(contains="negative"):
        check_display(bad)
    bad = DisplaySettings()
    bad.samples = 1
    with assert_raises(contains="two samples"):
        check_display(bad)
    bad = DisplaySettings()
    bad.ghost_samples = -1
    with assert_raises(contains="ghost"):
        check_display(bad)
    bad = DisplaySettings()
    bad.strength = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_display(bad)
    assert_true(gaussian_blur_pass().kind == GAUSSIAN_BLUR)
    assert_true(box_blur_pass(2, 2).kind == BOX_BLUR)
    assert_true(hash_blur_pass(0.2, 10).kind == HASH_BLUR)
    assert_true(chromatic_aberration_pass(2).kind == CHROMATIC_ABERRATION)
    assert_true(anamorphic_pass(0.5, 2, 8).kind == ANAMORPHIC)
    assert_true(lensflare_pass(0.2).kind == LENSFLARE)
    with assert_raises(contains="repeat"):
        _ = hash_blur_pass(repeats=0)


def test_each_display_pass_runs_in_the_composer() raises:
    var steps = List[Pass]()
    steps.append(gaussian_blur_pass(2))
    steps.append(box_blur_pass())
    steps.append(hash_blur_pass())
    steps.append(chromatic_aberration_pass())
    steps.append(anamorphic_pass(0.1))
    steps.append(lensflare_pass(0.1))
    var camera = PerspectiveCamera(
        Angle(60, DEGREE),
        Float32(W) / Float32(H),
        Length(0.1, METER),
        Length(10, METER),
    )
    var renderer = Renderer(W, H)
    renderer.set_background(Color(200, 200, 200, 255))
    var scene = Scene()
    var assets = Assets()
    for at in range(len(steps)):
        var composer = EffectComposer()
        composer.add_pass(render_pass())
        composer.add_pass(steps[at].copy())
        check_pass(composer.passes[1])
        var image = composer.render(renderer, scene, assets, camera)
        assert_equal(image.width, W)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
