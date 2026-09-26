# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `postprocessing.shaders`: each of the eighteen screen shaders
and the god-rays chain against worked-out answers on hand-built frames,
their settings checks, and their passes in the composer."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import Material
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    GOD_RAYS,
    SHADER_EFFECT,
    EffectComposer,
    Pass,
    PassKind,
    bleach_bypass_pass,
    brightness_contrast_pass,
    check_pass,
    color_correction_pass,
    colorify_pass,
    effect_pass,
    exposure_pass,
    focus_pass,
    normal_map_pass,
    triangle_blur_pass,
    frei_chen_pass,
    gamma_correction_pass,
    god_rays_pass,
    hue_saturation_pass,
    kaleido_pass,
    mirror_pass,
    reads_frame_as_light,
    render_pass,
    rgb_shift_pass,
    sobel_pass,
    sun_on_screen,
    technicolor_pass,
    tilt_shift_pass,
)
from postprocessing.sampling import LightView, u_of, v_of
from postprocessing.screen_space import DepthView, glsl_rand
from postprocessing.shaders import (
    BLEACH_BYPASS,
    BRIGHTNESS_CONTRAST,
    COLOR_CORRECTION,
    COLORIFY,
    EFFECT_FLOATS,
    EXPOSURE,
    FOCUS,
    NORMAL_MAP,
    TRIANGLE_BLUR,
    focus_pixel,
    normal_map_pixel,
    triangle_blur_pixel,
    FREI_CHEN,
    GAMMA_CORRECTION,
    GOD_RAYS_PASSES,
    HORIZONTAL_TILT_SHIFT,
    HUE_SATURATION,
    KALEIDO,
    MIRROR,
    MIRROR_BOTTOM,
    MIRROR_LEFT,
    MIRROR_RIGHT,
    MIRROR_TOP,
    RGB_SHIFT,
    SOBEL,
    TECHNICOLOR,
    VERTICAL_TILT_SHIFT,
    EffectSettings,
    GodRaysSettings,
    MirrorSide,
    ShaderEffect,
    bleach_bypass_color,
    brightness_contrast_color,
    check_effect,
    check_god_rays,
    color_correction_color,
    colorify_color,
    effect_color,
    effect_floats,
    effect_from_floats,
    effect_light,
    effect_luminance,
    effect_pixel,
    exposure_color,
    fake_sun_color,
    frei_chen_mask,
    frei_chen_pixel,
    gamma_correction_color,
    god_rays,
    god_rays_combine_pixel,
    god_rays_generate_pixel,
    god_rays_light,
    god_rays_mask,
    god_rays_size,
    god_rays_step,
    god_rays_sun,
    hue_saturation_color,
    kaleido_pixel,
    mirror_pixel,
    reads_neighbors,
    rgb_shift_pixel,
    sobel_pixel,
    technicolor_color,
    tilt_shift_pixel,
)
from render.framebuffer import Color, FloatColor
from render.target import RenderTarget
from renderers.renderer import Renderer
from std.math import atan2, cos, floor, inf, nan, pi, pow, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, RADIAN

comptime BLACK = Color(0, 0, 0)


def near(a: Float32, b: Float32, tolerance: Float32 = 1e-5) raises:
    """Assert two floats agree."""
    assert_almost_equal(a, b, atol=Float64(tolerance))


def same_color(a: FloatColor, b: FloatColor, tolerance: Float32 = 1e-5) raises:
    """Assert two colors agree in every channel."""
    near(a.r, b.r, tolerance)
    near(a.g, b.g, tolerance)
    near(a.b, b.b, tolerance)
    near(a.a, b.a, tolerance)


def ramp(width: Int, height: Int) -> List[FloatColor]:
    """Return a frame whose red grows across, green grows down and blue is
    a quarter, opaque but for a half-covered last pixel."""
    var colors = List[FloatColor]()
    for y in range(height):
        for x in range(width):
            colors.append(
                FloatColor(
                    Float32(x) / Float32(width),
                    Float32(y) / Float32(height),
                    0.25,
                    1,
                )
            )
    colors[len(colors) - 1] = FloatColor(0.3, 0.2, 0.1, 0.5)
    return colors^


def frame_of(
    colors: List[FloatColor], width: Int, height: Int
) raises -> RenderTarget:
    """Return a target holding the given light."""
    var frame = RenderTarget(width, height, BLACK)
    for slot in range(len(colors)):
        frame.colors[slot] = colors[slot]
        frame.data[slot] = True
    return frame^


# --- the types and the checks ------------------------------------------------


def test_the_effects_and_the_sides_are_types_with_a_range() raises:
    for value in range(18):
        assert_true(ShaderEffect(value).is_valid())
    assert_false(ShaderEffect(18).is_valid())
    assert_false(ShaderEffect(-1).is_valid())
    for value in range(4):
        assert_true(MirrorSide(value).is_valid())
    assert_false(MirrorSide(4).is_valid())
    assert_false(MirrorSide(-1).is_valid())
    assert_true(PassKind(33) == SHADER_EFFECT)
    assert_true(PassKind(34) == GOD_RAYS)
    assert_false(PassKind(60).is_valid())


def test_the_defaults_are_three_js_s() raises:
    var settings = EffectSettings()
    assert_true(settings.effect == RGB_SHIFT)
    near(settings.amount, 0.005)
    near(settings.angle.value, 0)
    near(settings.pow_rgb.x, 2)
    near(settings.mul_rgb.y, 1)
    near(settings.add_rgb.z, 0)
    assert_equal(Int(settings.color.g), 255)
    near(settings.opacity, 1)
    near(settings.sides, 6)
    assert_true(settings.side == MIRROR_RIGHT)
    near(settings.spread, 1.0 / 512.0)
    near(settings.focus, 0.35)
    near(settings.exposure, 1)
    near(settings.delta_u, 1)
    near(settings.delta_v, 1)
    near(settings.height, 0.05)
    near(settings.resolution_x, 512)
    near(settings.resolution_y, 512)
    near(settings.sample_distance, 0.94)
    near(settings.wave_factor, 0.00125)
    near(settings.screen_width, 1024)
    near(settings.screen_height, 1024)
    var rays = GodRaysSettings()
    near(rays.sun.y, 1000)
    near(rays.intensity, 0.69)
    near(rays.filter_length, 1)
    near(rays.resolution_scale, 0.25)
    assert_false(rays.fake_sun)
    assert_equal(Int(rays.sun_color.g), 238)
    check_effect(settings)
    check_god_rays(rays)


def test_effect_settings_no_shader_could_run_are_refused() raises:
    with assert_raises(contains="eighteen"):
        check_effect(EffectSettings(ShaderEffect(18)))
    var flat = EffectSettings(NORMAL_MAP)
    flat.resolution_x = 0
    with assert_raises(contains="positive"):
        check_effect(flat)
    var narrow = EffectSettings(FOCUS)
    narrow.screen_height = -1
    with assert_raises(contains="positive"):
        check_effect(narrow)
    var bad = EffectSettings()
    bad.side = MirrorSide(4)
    with assert_raises(contains="four"):
        check_effect(bad)
    # Every uniform alone is refused when it is not finite.
    for field in range(14):
        var settings = EffectSettings()
        var wrong = Float32(nan[DType.float32]())
        if field == 0:
            settings.amount = wrong
        elif field == 1:
            settings.angle = Angle(wrong, RADIAN)
        elif field == 2:
            settings.brightness = wrong
        elif field == 3:
            settings.contrast = wrong
        elif field == 4:
            settings.hue = wrong
        elif field == 5:
            settings.saturation = wrong
        elif field == 6:
            settings.opacity = wrong
        elif field == 7:
            settings.sides = wrong
        elif field == 8:
            settings.spread = wrong
        elif field == 9:
            settings.focus = wrong
        elif field == 10:
            settings.exposure = wrong
        elif field == 11:
            settings.pow_rgb = Vector3(2, wrong, 2)
        elif field == 12:
            settings.mul_rgb = Vector3(wrong, 1, 1)
        else:
            settings.add_rgb = Vector3(0, 0, wrong)
        with assert_raises(contains="finite"):
            check_effect(settings)
    var hard = EffectSettings(BRIGHTNESS_CONTRAST)
    hard.contrast = 1
    with assert_raises(contains="contrast"):
        check_effect(hard)
    var rich = EffectSettings(HUE_SATURATION)
    rich.saturation = 1.01
    with assert_raises(contains="saturation"):
        check_effect(rich)
    var none = EffectSettings(KALEIDO)
    none.sides = 0
    with assert_raises(contains="sides"):
        check_effect(none)
    # A vector's z alone, and its x alone, are refused.
    var z = EffectSettings()
    z.pow_rgb = Vector3(2, 2, inf[DType.float32]())
    with assert_raises(contains="finite"):
        check_effect(z)


def test_god_ray_settings_no_chain_could_run_are_refused() raises:
    for field in range(4):
        var settings = GodRaysSettings()
        var wrong = Float32(nan[DType.float32]())
        if field == 0:
            settings.sun = Vector3(0, wrong, 0)
        elif field == 1:
            settings.intensity = wrong
        elif field == 2:
            settings.filter_length = wrong
        else:
            settings.resolution_scale = wrong
        with assert_raises(contains="finite"):
            check_god_rays(settings)
    var dark = GodRaysSettings()
    dark.intensity = -0.1
    with assert_raises(contains="negative"):
        check_god_rays(dark)
    var short = GodRaysSettings()
    short.filter_length = 0
    with assert_raises(contains="positive"):
        check_god_rays(short)
    var small = GodRaysSettings()
    small.resolution_scale = 0
    with assert_raises(contains="resolution"):
        check_god_rays(small)
    var big = GodRaysSettings()
    big.resolution_scale = 1.5
    with assert_raises(contains="resolution"):
        check_god_rays(big)
    var sun = GodRaysSettings()
    sun.sun = Vector3(inf[DType.float32](), 0, 0)
    with assert_raises(contains="finite"):
        check_god_rays(sun)
    var far = GodRaysSettings()
    far.sun = Vector3(0, 0, nan[DType.float32]())
    with assert_raises(contains="finite"):
        check_god_rays(far)


def test_the_settings_survive_the_trip_through_floats() raises:
    var settings = EffectSettings(MIRROR)
    settings.amount = 0.01
    settings.angle = Angle(0.5, RADIAN)
    settings.brightness = 0.1
    settings.contrast = 0.2
    settings.hue = 0.3
    settings.saturation = 0.4
    settings.pow_rgb = Vector3(1, 2, 3)
    settings.mul_rgb = Vector3(4, 5, 6)
    settings.add_rgb = Vector3(7, 8, 9)
    settings.color = Color(10, 20, 30, 40)
    settings.opacity = 0.5
    settings.sides = 7
    settings.side = MIRROR_TOP
    settings.spread = 0.25
    settings.focus = 0.75
    settings.exposure = 2
    settings.delta_u = 0.1
    settings.delta_v = 0.2
    settings.height = 0.3
    settings.resolution_x = 40
    settings.resolution_y = 50
    settings.sample_distance = 0.6
    settings.wave_factor = 0.7
    settings.screen_width = 80
    settings.screen_height = 90
    var floats = effect_floats(settings)
    assert_equal(len(floats), EFFECT_FLOATS)
    var back = effect_from_floats(
        floats.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    )
    assert_true(back.effect == MIRROR)
    near(back.amount, 0.01)
    near(back.angle.value, 0.5)
    near(back.brightness, 0.1)
    near(back.contrast, 0.2)
    near(back.hue, 0.3)
    near(back.saturation, 0.4)
    near(back.pow_rgb.z, 3)
    near(back.mul_rgb.x, 4)
    near(back.add_rgb.y, 8)
    assert_equal(Int(back.color.r), 10)
    assert_equal(Int(back.color.g), 20)
    assert_equal(Int(back.color.b), 30)
    assert_equal(Int(back.color.a), 40)
    near(back.opacity, 0.5)
    near(back.sides, 7)
    assert_true(back.side == MIRROR_TOP)
    near(back.spread, 0.25)
    near(back.focus, 0.75)
    near(back.exposure, 2)
    near(back.delta_u, 0.1)
    near(back.delta_v, 0.2)
    near(back.height, 0.3)
    near(back.resolution_x, 40)
    near(back.resolution_y, 50)
    near(back.sample_distance, 0.6)
    near(back.wave_factor, 0.7)
    near(back.screen_width, 80)
    near(back.screen_height, 90)


# --- the color transforms ----------------------------------------------------


def test_brightness_and_contrast_follow_the_shader() raises:
    var color = FloatColor(0.2, 0.5, 0.9, 0.7)
    same_color(
        brightness_contrast_color(color, 0.1, 0),
        FloatColor(0.3, 0.6, 1.0, 0.7),
    )
    # Above zero the contrast divides by one minus it.
    same_color(
        brightness_contrast_color(color, 0, 0.5),
        FloatColor(-0.1, 0.5, 1.3, 0.7),
    )
    # Below zero it multiplies by one plus it.
    same_color(
        brightness_contrast_color(color, 0, -0.5),
        FloatColor(0.35, 0.5, 0.7, 0.7),
    )


def test_hue_turns_about_gray_and_saturation_scales_from_the_average() raises:
    var color = FloatColor(0.8, 0.4, 0.2, 1)
    # No turn and no saturation keep the color.
    same_color(hue_saturation_color(color, 0, 0), color)
    # A third of a full turn, two thirds of pi, moves red to green.
    var turned = hue_saturation_color(color, Float32(2.0 / 3.0), 0)
    same_color(turned, FloatColor(0.2, 0.8, 0.4, 1), 1e-4)
    # Minus one grays.
    var gray = hue_saturation_color(color, 0, -1)
    var average = Float32((0.8 + 0.4 + 0.2) / 3)
    same_color(gray, FloatColor(average, average, average, 1))
    # Above zero: `1 - 1 / (1.001 - saturation)`.
    var k = 1 - 1 / (Float32(1.001) - 0.5)
    var rich = hue_saturation_color(color, 0, 0.5)
    near(rich.r, 0.8 + (average - 0.8) * k, 1e-4)
    near(rich.b, 0.2 + (average - 0.2) * k, 1e-4)


def test_color_correction_colorify_bleach_technicolor_and_exposure() raises:
    var color = FloatColor(0.5, 0.25, 0.8, 0.6)
    same_color(
        color_correction_color(
            color, Vector3(2, 1, 0.5), Vector3(1, 2, 3), Vector3(0, 0.25, 0.2)
        ),
        FloatColor(0.25, 1.0, 3.0, 0.6),
    )
    var lum = effect_luminance(0.5, 0.25, 0.8)
    near(lum, 0.2126729 * 0.5 + 0.7151522 * 0.25 + 0.072175 * 0.8)
    same_color(
        colorify_color(color, FloatColor(1, 0.5, 0, 1)),
        FloatColor(lum, lum * 0.5, 0, 0.6),
    )
    same_color(technicolor_color(color), FloatColor(0.5, 0.525, 0.525, 1))
    same_color(exposure_color(color, 2), FloatColor(1, 0.5, 1.6, 0.6))
    # A dark color is multiplied by its luminance: `2 * base * lum`, mixed
    # in by the opacity times the alpha.
    var dark = FloatColor(0.2, 0.2, 0.2, 1)
    var dark_lum = effect_luminance(0.2, 0.2, 0.2)
    var bleached = bleach_bypass_color(dark, 0.5)
    near(bleached.r, 0.5 * (2 * 0.2 * dark_lum) + 0.5 * 0.2)
    # A bright one is screened: `1 - 2 (1 - lum)(1 - base)`.
    var bright = FloatColor(0.9, 0.9, 0.9, 1)
    var bright_lum = effect_luminance(0.9, 0.9, 0.9)
    near(
        bleach_bypass_color(bright, 1).g,
        1 - 2 * (1 - bright_lum) * (1 - 0.9),
    )


def test_gamma_correction_is_three_js_s_srgb_curve() raises:
    var color = gamma_correction_color(FloatColor(0.002, 0.5, 1, 0.3))
    near(color.r, 0.002 * 12.92)
    near(color.g, pow(Float32(0.5), Float32(0.41666)) * 1.055 - 0.055)
    near(color.b, 1, 1e-4)
    near(color.a, 0.3)


def test_effect_color_runs_each_transform() raises:
    var color = FloatColor(0.5, 0.25, 0.8, 0.6)
    var settings = EffectSettings(BRIGHTNESS_CONTRAST)
    settings.brightness = 0.1
    same_color(
        effect_color(color, settings), brightness_contrast_color(color, 0.1, 0)
    )
    settings.effect = HUE_SATURATION
    settings.hue = 0.2
    same_color(
        effect_color(color, settings), hue_saturation_color(color, 0.2, 0)
    )
    settings.effect = COLOR_CORRECTION
    same_color(
        effect_color(color, settings),
        color_correction_color(
            color, Vector3(2, 2, 2), Vector3(1, 1, 1), Vector3(0, 0, 0)
        ),
    )
    settings.effect = COLORIFY
    settings.color = Color(255, 0, 0)
    same_color(
        effect_color(color, settings),
        colorify_color(color, FloatColor(1, 0, 0, 1)),
    )
    settings.effect = BLEACH_BYPASS
    same_color(effect_color(color, settings), bleach_bypass_color(color, 1))
    settings.effect = TECHNICOLOR
    same_color(effect_color(color, settings), technicolor_color(color))
    settings.effect = EXPOSURE
    settings.exposure = 3
    same_color(effect_color(color, settings), exposure_color(color, 3))
    settings.effect = GAMMA_CORRECTION
    same_color(effect_color(color, settings), gamma_correction_color(color))


# --- the shaders that read their neighbors ------------------------------------


def test_which_effects_read_their_neighbors() raises:
    assert_true(reads_neighbors(RGB_SHIFT))
    assert_true(reads_neighbors(SOBEL))
    assert_true(reads_neighbors(FREI_CHEN))
    assert_true(reads_neighbors(KALEIDO))
    assert_true(reads_neighbors(MIRROR))
    assert_true(reads_neighbors(HORIZONTAL_TILT_SHIFT))
    assert_true(reads_neighbors(VERTICAL_TILT_SHIFT))
    assert_false(reads_neighbors(EXPOSURE))
    assert_false(reads_neighbors(TECHNICOLOR))


def test_rgb_shift_moves_red_and_blue_apart() raises:
    var colors = ramp(4, 4)
    var view = LightView(colors, 4, 4)
    var u = u_of(1, 4)
    var v = v_of(1, 4)
    # A quarter of the width to the right: red from the next column.
    var shifted = rgb_shift_pixel(view, u, v, 0.25, Angle(0.0, RADIAN))
    near(shifted.r, 0.5, 1e-4)
    near(shifted.g, 0.25, 1e-4)
    near(shifted.b, 0.25, 1e-4)
    near(shifted.a, 1)
    # A quarter turn moves red up a row, toward the top.
    var up = rgb_shift_pixel(view, u, v, 0.25, Angle(90.0, DEGREE))
    near(up.r, 0.25, 1e-4)
    # The views do not keep their lists alive; this does.
    _ = colors^


def test_sobel_measures_the_red_gradient() raises:
    var colors = ramp(4, 4)
    var view = LightView(colors, 4, 4)
    # Red grows by a quarter a column, so `Gx` is 4 * 0.5 = 2 and `Gy` 0.
    var edge = sobel_pixel(view, u_of(1, 4), v_of(1, 4))
    same_color(edge, FloatColor(2, 2, 2, 1), 1e-4)
    var flat = List[FloatColor](length=9, fill=FloatColor(0.5, 0.5, 0.5, 1))
    same_color(
        sobel_pixel(LightView(flat, 3, 3), u_of(1, 3), v_of(1, 3)),
        FloatColor(0, 0, 0, 1),
    )
    # The views do not keep their lists alive; this does.
    _ = colors^
    _ = flat^


def test_frei_chen_finds_an_edge_and_is_black_where_all_is_black() raises:
    near(frei_chen_mask(0, 0, 0), 0.3535533845424652)
    near(frei_chen_mask(8, 2, 2), 0.3333333432674408)
    near(frei_chen_mask(4, 1, 0), 0.5)
    var black = List[FloatColor](length=9, fill=FloatColor(0, 0, 0, 1))
    same_color(
        frei_chen_pixel(LightView(black, 3, 3), u_of(1, 3), v_of(1, 3)),
        FloatColor(0, 0, 0, 1),
    )
    # A flat gray has no edge: only the ninth mask, the mean, responds.
    var gray = List[FloatColor](length=9, fill=FloatColor(0.5, 0.5, 0.5, 1))
    same_color(
        frei_chen_pixel(LightView(gray, 3, 3), u_of(1, 3), v_of(1, 3)),
        FloatColor(0, 0, 0, 1),
        1e-4,
    )
    # A step between the left column and the others is an edge.
    var step = List[FloatColor](length=9, fill=FloatColor(1, 1, 1, 1))
    for row in range(3):
        step[row * 3] = FloatColor(0, 0, 0, 1)
    var edge = frei_chen_pixel(LightView(step, 3, 3), u_of(1, 3), v_of(1, 3))
    # The first four responses add to 4.5 of 18: the edge is a half.
    near(edge.r, 0.5, 1e-3)
    near(edge.a, 1)
    # The views do not keep their lists alive; this does.
    _ = black^
    _ = gray^
    _ = step^


def test_kaleido_folds_the_frame_about_its_center() raises:
    var colors = ramp(8, 8)
    var view = LightView(colors, 8, 8)
    # The center folds onto itself.
    var u = Float32(0.3)
    var v = Float32(0.6)
    var px = u - 0.5
    var py = v - 0.5
    var r = sqrt(px * px + py * py)
    var wedge = Float32(2.0 * 3.1416) / 4
    var a = atan2(py, px) + 0.25
    a = a - wedge * floor(a / wedge)
    a = abs(a - wedge / 2)
    same_color(
        kaleido_pixel(view, u, v, 4, Angle(0.25, RADIAN)),
        view.sample(r * cos(a) + 0.5, r * sin(a) + 0.5),
    )
    # The views do not keep their lists alive; this does.
    _ = colors^


def test_mirror_keeps_each_half() raises:
    var colors = ramp(4, 4)
    var view = LightView(colors, 4, 4)
    # Left: a point on the right reads its mirror on the left.
    same_color(
        mirror_pixel(view, 0.875, 0.625, MIRROR_LEFT), view.sample(0.125, 0.625)
    )
    same_color(
        mirror_pixel(view, 0.125, 0.625, MIRROR_LEFT), view.sample(0.125, 0.625)
    )
    same_color(
        mirror_pixel(view, 0.125, 0.625, MIRROR_RIGHT),
        view.sample(0.875, 0.625),
    )
    same_color(
        mirror_pixel(view, 0.875, 0.625, MIRROR_RIGHT),
        view.sample(0.875, 0.625),
    )
    same_color(
        mirror_pixel(view, 0.375, 0.125, MIRROR_TOP), view.sample(0.375, 0.875)
    )
    same_color(
        mirror_pixel(view, 0.375, 0.875, MIRROR_TOP), view.sample(0.375, 0.875)
    )
    same_color(
        mirror_pixel(view, 0.375, 0.875, MIRROR_BOTTOM),
        view.sample(0.375, 0.125),
    )
    same_color(
        mirror_pixel(view, 0.375, 0.125, MIRROR_BOTTOM),
        view.sample(0.375, 0.125),
    )
    # The views do not keep their lists alive; this does.
    _ = colors^


def test_tilt_shift_is_sharp_at_the_focus_and_blurs_away_from_it() raises:
    var colors = ramp(8, 8)
    var view = LightView(colors, 8, 8)
    var u = u_of(3, 8)
    var v = v_of(4, 8)
    # On the focus row the taps all land on the pixel.
    same_color(
        tilt_shift_pixel(view, u, v, 0.1, v, True), view.sample(u, v), 1e-4
    )
    # Away from it, nine taps along the row, weighted.
    var spread = Float32(0.5)
    var focus = Float32(0.0)
    var step = spread * abs(focus - v)
    var weights: List[Float32] = [
        0.051,
        0.0918,
        0.12245,
        0.1531,
        0.1633,
        0.1531,
        0.12245,
        0.0918,
        0.051,
    ]
    var across = FloatColor(0, 0, 0, 0)
    var down = FloatColor(0, 0, 0, 0)
    for tap in range(9):
        var offset = Float32(tap - 4) * step
        var a = view.sample(u + offset, v)
        var b = view.sample(u, v + offset)
        across = FloatColor(
            across.r + a.r * weights[tap],
            across.g + a.g * weights[tap],
            across.b + a.b * weights[tap],
            across.a + a.a * weights[tap],
        )
        down = FloatColor(
            down.r + b.r * weights[tap],
            down.g + b.g * weights[tap],
            down.b + b.b * weights[tap],
            down.a + b.a * weights[tap],
        )
    same_color(tilt_shift_pixel(view, u, v, spread, focus, True), across)
    same_color(tilt_shift_pixel(view, u, v, spread, focus, False), down)
    # The views do not keep their lists alive; this does.
    _ = colors^


def test_the_triangle_blur_weighs_its_taps_by_a_tent() raises:
    var colors = ramp(8, 8)
    var view = LightView(colors, 8, 8)
    var u = u_of(3, 8)
    var v = v_of(4, 8)
    # No reach: every tap is the pixel.
    same_color(triangle_blur_pixel(view, u, v, 0, 0), view.sample(u, v), 1e-5)
    # A reach: twenty-one taps, each weighted by one less its distance.
    var offset = glsl_rand(u, v)
    var sum = FloatColor(0, 0, 0, 0)
    var total = Float32(0)
    for step in range(-10, 11):
        var percent = (Float32(step) + offset - 0.5) / 10
        var weight = 1 - abs(percent)
        var tap = view.sample(u + 0.2 * percent, v + 0.1 * percent)
        sum = FloatColor(
            sum.r + tap.r * weight,
            sum.g + tap.g * weight,
            sum.b + tap.b * weight,
            sum.a + tap.a * weight,
        )
        total += weight
    same_color(
        triangle_blur_pixel(view, u, v, 0.2, 0.1),
        FloatColor(sum.r / total, sum.g / total, sum.b / total, sum.a / total),
    )
    _ = colors^


def test_the_normal_map_turns_a_slope_into_a_normal() raises:
    # Flat: the normal points straight out, blue at one.
    var even = List[FloatColor](length=16, fill=FloatColor(0.4, 0, 0, 1))
    var flat = LightView(even, 4, 4)
    same_color(
        normal_map_pixel(flat, 0.5, 0.5, 0.05, 4, 4),
        FloatColor(0.5, 0.5, 1, 1),
    )
    # No slope and no height: no direction, a half in each channel.
    same_color(
        normal_map_pixel(flat, 0.5, 0.5, 0, 4, 4),
        FloatColor(0.5, 0.5, 0.5, 1),
    )
    # Red rising to the right: the normal leans left.
    var colors = ramp(4, 4)
    var view = LightView(colors, 4, 4)
    var u = u_of(1, 4)
    var v = v_of(1, 4)
    var here = view.sample(u, v).r
    var across = view.sample(u + 0.25, v).r
    var up = view.sample(u, v + 0.25).r
    var n = Vector3(here - across, here - up, 0.05)
    n.normalize()
    same_color(
        normal_map_pixel(view, u, v, 0.05, 4, 4),
        FloatColor(0.5 * n.x + 0.5, 0.5 * n.y + 0.5, 0.5 * n.z + 0.5, 1),
    )
    _ = even^
    _ = colors^


def test_the_focus_is_sharp_where_the_frame_is_even() raises:
    # Every tap the same: the darkest is the color, the mean is the
    # color, and the shader writes the color plus its square, dimmed.
    var even = List[FloatColor](length=64, fill=FloatColor(0.2, 0.4, 0.6, 1))
    var view = LightView(even, 8, 8)
    for u in [Float32(0.5), Float32(0.1)]:
        same_color(
            focus_pixel(view, u, 0.5, EffectSettings(FOCUS)),
            FloatColor(
                0.2 * 0.2 * 0.95 + 0.2,
                0.4 * 0.4 * 0.95 + 0.4,
                0.6 * 0.6 * 0.95 + 0.6,
                1,
            ),
            1e-4,
        )
    # On a ramp, away from the center, the darkest blue pulls the pixel.
    var colors = ramp(8, 8)
    var slope = LightView(colors, 8, 8)
    var settings = EffectSettings(FOCUS)
    settings.screen_width = 8
    settings.screen_height = 8
    var edge = focus_pixel(slope, u_of(1, 8), v_of(1, 8), settings)
    assert_true(edge.a == 1)
    # Blue that grows across: a tap to the left is darker than the
    # pixel, so it is taken, and the pixel comes out darker than an even
    # frame of its own color.
    var across = List[FloatColor]()
    for _ in range(8):
        for x in range(8):
            across.append(FloatColor(0.5, 0.5, Float32(x) / 8, 1))
    var pulled = focus_pixel(
        LightView(across, 8, 8), u_of(4, 8), v_of(4, 8), settings
    )
    assert_true(pulled.b < 0.5 * 0.5 * 0.95 + 0.5)
    _ = even^
    _ = colors^
    _ = across^


def test_the_new_builders_set_their_uniforms() raises:
    var blur = triangle_blur_pass(0.3, 0.4)
    assert_true(blur.effect.effect == TRIANGLE_BLUR)
    near(blur.effect.delta_v, 0.4)
    var normals = normal_map_pass(0.2, 64, 32)
    assert_true(normals.effect.effect == NORMAL_MAP)
    near(normals.effect.resolution_y, 32)
    var focus = focus_pass(0.5, 0.01, 640, 480)
    assert_true(focus.effect.effect == FOCUS)
    near(focus.effect.screen_height, 480)
    with assert_raises(contains="positive"):
        _ = normal_map_pass(resolution_x=0)


def test_effect_pixel_runs_each_shader() raises:
    var colors = ramp(4, 4)
    var view = LightView(colors, 4, 4)
    var u = u_of(2, 4)
    var v = v_of(1, 4)
    var settings = EffectSettings(RGB_SHIFT)
    same_color(
        effect_pixel(view, 2, 1, settings),
        rgb_shift_pixel(view, u, v, settings.amount, settings.angle),
    )
    settings.effect = SOBEL
    same_color(effect_pixel(view, 2, 1, settings), sobel_pixel(view, u, v))
    settings.effect = FREI_CHEN
    same_color(effect_pixel(view, 2, 1, settings), frei_chen_pixel(view, u, v))
    settings.effect = KALEIDO
    same_color(
        effect_pixel(view, 2, 1, settings),
        kaleido_pixel(view, u, v, 6, Angle(0.0, RADIAN)),
    )
    settings.effect = MIRROR
    same_color(
        effect_pixel(view, 2, 1, settings),
        mirror_pixel(view, u, v, MIRROR_RIGHT),
    )
    settings.effect = HORIZONTAL_TILT_SHIFT
    same_color(
        effect_pixel(view, 2, 1, settings),
        tilt_shift_pixel(view, u, v, settings.spread, 0.35, True),
    )
    settings.effect = VERTICAL_TILT_SHIFT
    same_color(
        effect_pixel(view, 2, 1, settings),
        tilt_shift_pixel(view, u, v, settings.spread, 0.35, False),
    )
    settings.effect = TRIANGLE_BLUR
    same_color(
        effect_pixel(view, 2, 1, settings),
        triangle_blur_pixel(view, u, v, settings.delta_u, settings.delta_v),
    )
    settings.effect = NORMAL_MAP
    same_color(
        effect_pixel(view, 2, 1, settings),
        normal_map_pixel(
            view,
            u,
            v,
            settings.height,
            settings.resolution_x,
            settings.resolution_y,
        ),
    )
    settings.effect = FOCUS
    same_color(
        effect_pixel(view, 2, 1, settings), focus_pixel(view, u, v, settings)
    )
    # A color transform reads the straight texel and writes premultiplied.
    settings.effect = EXPOSURE
    settings.exposure = 2
    var last = effect_pixel(view, 3, 3, settings)
    same_color(last, FloatColor(0.6, 0.4, 0.2, 0.5))
    # The views do not keep their lists alive; this does.
    _ = colors^


def test_effect_light_runs_over_the_frame_as_it_was() raises:
    var colors = ramp(4, 3)
    var frame = frame_of(colors, 4, 3)
    var settings = EffectSettings(MIRROR)
    settings.side = MIRROR_LEFT
    effect_light(frame, settings)
    var view = LightView(colors, 4, 3)
    for y in range(3):
        for x in range(4):
            same_color(
                frame.colors[y * 4 + x], effect_pixel(view, x, y, settings)
            )
            assert_false(frame.data[y * 4 + x])

    # --- god rays ------------------------------------------------------------------
    # The views do not keep their lists alive; this does.
    _ = colors^


def test_the_god_ray_sizes_steps_and_sun() raises:
    assert_equal(god_rays_size(100, 0.25), 25)
    assert_equal(god_rays_size(3, 0.25), 1)
    near(god_rays_step(1, 1), 1.0 / 6.0)
    near(god_rays_step(2, 3), 2.0 / 216.0)
    # Straight ahead of an identity camera, at the center.
    var sun = god_rays_sun(Matrix4(), Vector3(0.5, -0.5, 3))
    near(sun.x, 0.75)
    near(sun.y, 0.25)
    near(sun.z, 3)


def test_generate_walks_toward_the_sun_and_fades_in() raises:
    var mask = List[FloatColor](length=16, fill=FloatColor(1, 1, 1, 1))
    var view = LightView(mask, 4, 4)
    # A sun far enough in front: all six taps within reach add one each.
    var sun = Vector3(0.9, 0.5, 2000)
    var rays = god_rays_generate_pixel(view, 0.1, 0.5, sun, 0.1)
    same_color(rays, FloatColor(1, 1, 1, 1))
    # A step too long for the distance: only the taps up to the sun count.
    var few = god_rays_generate_pixel(view, 0.1, 0.5, sun, 0.3)
    near(few.r, 3.0 / 6.0)
    # Halfway to the fade depth, half as bright.
    var faint = god_rays_generate_pixel(
        view, 0.1, 0.5, Vector3(0.9, 0.5, 500), 0.1
    )
    near(faint.r, 0.5)
    # A sun behind the camera adds nothing.
    near(
        god_rays_generate_pixel(view, 0.1, 0.5, Vector3(0.9, 0.5, -1), 0.1).r, 0
    )
    # A walk that leaves the top of the texture stops adding.
    var up = god_rays_generate_pixel(
        view, 0.5, 0.75, Vector3(0.5, 3, 2000), 0.1
    )
    near(up.r, 3.0 / 6.0)
    # At the sun itself no tap is past the first: the pixel counts once.
    near(god_rays_generate_pixel(view, 0.9, 0.5, sun, 0.1).r, 1.0 / 6.0)
    # The views do not keep their lists alive; this does.
    _ = mask^


def test_the_fake_sun_glows_and_fades_to_the_background() raises:
    var sun = Vector3(0.5, 0.5, 10)
    var glow = FloatColor(1, 1, 0, 1)
    var back = FloatColor(0, 0, 0.5, 1)
    # At the sun: `mix(sun, bg, 1 - 0.35)`.
    same_color(
        fake_sun_color(0.5, 0.5, 1, sun, glow, back),
        FloatColor(0.35, 0.35, 0.5 * 0.65, 1),
    )
    # Half a frame height away and more, the background.
    same_color(fake_sun_color(0.5, 1.0, 1, sun, glow, back), back)
    # The aspect stretches across.
    same_color(fake_sun_color(0.75, 0.5, 2, sun, glow, back), back)
    # A sun behind the camera is the background everywhere.
    same_color(
        fake_sun_color(0.5, 0.5, 1, Vector3(0.5, 0.5, -1), glow, back), back
    )


def test_combine_adds_the_rays_and_the_fake_sun_fills_the_sky() raises:
    var settings = GodRaysSettings()
    settings.intensity = 0.5
    var sun = Vector3(0.5, 0.5, 10)
    var color = FloatColor(0.1, 0.2, 0.3, 0.5)
    # `intensity * (1 - rays)` is added to the straight color.
    same_color(
        god_rays_combine_pixel(color, 0.6, 0.5, 0.5, 0.5, 1, sun, settings),
        FloatColor(0.4, 0.6, 0.8, 1),
    )
    # The fake sun replaces only where nothing was drawn.
    settings.fake_sun = True
    same_color(
        god_rays_combine_pixel(color, 1, 0.5, 0.5, 0.5, 1, sun, settings),
        FloatColor(0.2, 0.4, 0.6, 1),
    )
    var sky = god_rays_combine_pixel(color, 1, 1, 0.5, 0.5, 1, sun, settings)
    same_color(
        sky,
        fake_sun_color(
            0.5,
            0.5,
            1,
            sun,
            FloatColor(srgb=settings.sun_color),
            FloatColor(srgb=settings.bg_color),
        ),
    )


def a_flat_view(width: Int, height: Int, depth: Float32) raises -> DepthView:
    """Return a depth view of one depth everywhere."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1, Length(0.1, METER), Length(10.0, METER)
    )
    return DepthView(
        List[Float32](length=width * height, fill=depth),
        width,
        height,
        camera.projection_matrix(),
        Length(0.1, METER),
        Length(10.0, METER),
    )


def test_the_mask_is_the_depth_and_the_chain_runs_three_passes() raises:
    var view = a_flat_view(8, 8, 0.75)
    var mask = god_rays_mask(view)
    assert_equal(len(mask), 64)
    var z = view.depth[5]
    same_color(mask[5], FloatColor(z, z, z, 1))
    var settings = GodRaysSettings()
    settings.resolution_scale = 0.5
    var sun = Vector3(0.5, 0.5, 2000)
    var rays = god_rays(view, sun, settings)
    assert_equal(len(rays), 16)
    # Every tap of a flat mask reads 0.75, and a pass that walks the whole
    # way sums six of them: the result is flat too, once the first pass
    # has reached everywhere.
    for slot in range(16):
        assert_true(rays[slot].r > 0)
        assert_true(rays[slot].r <= z + 1e-5)
    assert_equal(GOD_RAYS_PASSES, 3)


def test_god_rays_light_lays_the_combine_over_the_frame() raises:
    var view = a_flat_view(4, 4, 1)
    var colors = ramp(4, 4)
    var frame = frame_of(colors, 4, 4)
    var settings = GodRaysSettings()
    settings.resolution_scale = 0.5
    settings.fake_sun = True
    var sun = Vector3(0.5, 0.5, 2000)
    god_rays_light(frame, view, sun, settings)
    var rays = god_rays(view, sun, settings)
    var rays_view = LightView(rays, 2, 2)
    for y in range(4):
        for x in range(4):
            var u = u_of(x, 4)
            var v = v_of(y, 4)
            same_color(
                frame.colors[y * 4 + x],
                god_rays_combine_pixel(
                    colors[y * 4 + x],
                    rays_view.sample(u, v).r,
                    view.depth[y * 4 + x],
                    u,
                    v,
                    1,
                    sun,
                    settings,
                ),
            )
            assert_false(frame.data[y * 4 + x])
    # The view does not keep the rays alive; this does.
    _ = rays^


# --- the passes -------------------------------------------------------------
# The views do not keep their lists alive; this does.


def test_each_builder_sets_its_shader_and_uniforms() raises:
    var shift = rgb_shift_pass(0.01, Angle(1.0, RADIAN))
    assert_true(shift.kind == SHADER_EFFECT)
    assert_true(shift.effect.effect == RGB_SHIFT)
    near(shift.effect.amount, 0.01)
    near(shift.effect.angle.value, 1)
    var bc = brightness_contrast_pass(0.1, 0.2)
    assert_true(bc.effect.effect == BRIGHTNESS_CONTRAST)
    near(bc.effect.contrast, 0.2)
    var hs = hue_saturation_pass(0.3, 0.4)
    assert_true(hs.effect.effect == HUE_SATURATION)
    near(hs.effect.saturation, 0.4)
    var cc = color_correction_pass(
        Vector3(1, 1, 1), Vector3(2, 2, 2), Vector3(0.1, 0.1, 0.1)
    )
    assert_true(cc.effect.effect == COLOR_CORRECTION)
    near(cc.effect.mul_rgb.x, 2)
    var tint = colorify_pass(Color(255, 0, 0))
    assert_true(tint.effect.effect == COLORIFY)
    assert_equal(Int(tint.effect.color.g), 0)
    var bleach = bleach_bypass_pass(0.5)
    assert_true(bleach.effect.effect == BLEACH_BYPASS)
    near(bleach.effect.opacity, 0.5)
    assert_true(technicolor_pass().effect.effect == TECHNICOLOR)
    assert_true(sobel_pass().effect.effect == SOBEL)
    assert_true(frei_chen_pass().effect.effect == FREI_CHEN)
    var kaleido = kaleido_pass(4, Angle(0.5, RADIAN))
    assert_true(kaleido.effect.effect == KALEIDO)
    near(kaleido.effect.sides, 4)
    assert_true(mirror_pass(MIRROR_TOP).effect.side == MIRROR_TOP)
    var across = tilt_shift_pass(True, 0.01, 0.5)
    assert_true(across.effect.effect == HORIZONTAL_TILT_SHIFT)
    near(across.effect.focus, 0.5)
    assert_true(tilt_shift_pass(False).effect.effect == VERTICAL_TILT_SHIFT)
    near(exposure_pass(2).effect.exposure, 2)
    assert_true(gamma_correction_pass().effect.effect == GAMMA_CORRECTION)
    var rays = god_rays_pass(Vector3(1, 2, 3), 0.5, True)
    assert_true(rays.kind == GOD_RAYS)
    near(rays.god_rays.sun.z, 3)
    near(rays.god_rays.intensity, 0.5)
    assert_true(rays.god_rays.fake_sun)
    assert_true(reads_frame_as_light(SHADER_EFFECT))
    assert_true(reads_frame_as_light(GOD_RAYS))


def test_a_builder_refuses_what_its_check_refuses() raises:
    with assert_raises(contains="eighteen"):
        _ = effect_pass(ShaderEffect(20))
    with assert_raises(contains="contrast"):
        _ = brightness_contrast_pass(0, 1)
    with assert_raises(contains="saturation"):
        _ = hue_saturation_pass(0, 2)
    with assert_raises(contains="sides"):
        _ = kaleido_pass(-1)
    with assert_raises(contains="four"):
        _ = mirror_pass(MirrorSide(9))
    with assert_raises(contains="finite"):
        _ = rgb_shift_pass(nan[DType.float32]())
    with assert_raises(contains="finite"):
        _ = color_correction_pass(Vector3(nan[DType.float32](), 1, 1))
    with assert_raises(contains="finite"):
        _ = bleach_bypass_pass(inf[DType.float32]())
    with assert_raises(contains="finite"):
        _ = tilt_shift_pass(True, nan[DType.float32]())
    with assert_raises(contains="finite"):
        _ = exposure_pass(nan[DType.float32]())
    with assert_raises(contains="negative"):
        _ = god_rays_pass(Vector3(0, 0, 0), -1)
    var step = Pass(SHADER_EFFECT)
    step.effect.sides = 0
    with assert_raises(contains="sides"):
        check_pass(step)


def a_scene(mut assets: Assets) raises -> Scene:
    """Return a gray square in front of the camera, with sky around it."""
    var scene = Scene()
    var paint = assets.materials.add(Material(Color(180, 120, 60)))
    var sheet = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    scene.add_mesh(Mesh(sheet, paint, scene.add(Object3D())))
    scene.update()
    return scene^


def a_camera() raises -> PerspectiveCamera:
    """Return a camera two meters back."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
    return camera^


def test_the_composer_runs_a_shader_effect_as_effect_light_does() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var camera = a_camera()
    var renderer = Renderer(8, 8)
    renderer.set_background(Color(20, 40, 80))
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(sobel_pass())
    var image = composer.render(renderer, scene, assets, camera)
    var frame = RenderTarget(8, 8, Color(20, 40, 80))
    renderer.render_into(frame, scene, assets, camera)
    effect_light(frame, EffectSettings(SOBEL))
    var expected = frame.resolve(1, renderer.tone_curve(), 1)
    for y in range(8):
        for x in range(8):
            var a = image.get_pixel(x, y)
            var b = expected.get_pixel(x, y)
            assert_equal(Int(a.r), Int(b.r))
            assert_equal(Int(a.a), Int(b.a))


def test_the_composer_lays_god_rays_from_the_sun_it_projects() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var camera = a_camera()
    var renderer = Renderer(8, 8)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    var sun = Vector3(0, 0.5, -5)
    composer.add_pass(god_rays_pass(sun, 0.5, True))
    var image = composer.render(renderer, scene, assets, camera)
    var on_screen = sun_on_screen(camera, scene, sun)
    near(on_screen.x, 0.5, 1e-4)
    assert_true(on_screen.y > 0.5)
    assert_true(on_screen.z > 0)
    # The sky is the fake sun and the rays: brighter than the black
    # background, and opaque.
    var corner = image.get_pixel(0, 0)
    assert_true(Int(corner.r) > 0)
    assert_equal(Int(corner.a), 255)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
