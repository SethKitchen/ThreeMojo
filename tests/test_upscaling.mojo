# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `SharpenNode` and `FSR1Node`: RCAS and EASU
against three.js's arithmetic, their settings, and their passes."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from math.vector3 import Vector3
from postprocessing.composer import (
    FSR1,
    SHARPEN,
    EffectComposer,
    Pass,
    fsr1_pass,
    render_pass,
    sharpen_pass,
)
from postprocessing.sampling import LightView
from postprocessing.upscaling import (
    EasuEdge,
    UpscaleSettings,
    check_upscale,
    easu_pixel,
    easu_weight,
    fsr1_light,
    load_straight,
    max_num,
    min_num,
    rcas_pixel,
    sharpen_light,
)
from render.framebuffer import Color, FloatColor
from render.target import FLOAT_TARGET, RenderTarget
from renderers.renderer import Renderer
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def gray(value: Float32) -> FloatColor:
    """Return an opaque gray."""
    return FloatColor(value, value, value, 1)


def cross(
    center: Float32, up: Float32, left: Float32, right: Float32, down: Float32
) -> List[FloatColor]:
    """Return a 3 by 3 image of grays: a center, its cross, and corners at
    the center's value."""
    var image = List[FloatColor](length=9, fill=gray(center))
    image[1] = gray(up)
    image[3] = gray(left)
    image[5] = gray(right)
    image[7] = gray(down)
    return image^


def rcas_of(
    image: List[FloatColor], sharpness: Float32, denoise: Bool
) -> Float32:
    """Return the center of a 3 by 3 image after RCAS, its red."""
    var result = rcas_pixel(LightView(image, 3, 3), 1, 1, sharpness, denoise)
    return result.r


def test_the_nan_safe_min_and_max_take_the_number() raises:
    var missing = nan[DType.float32]()
    assert_equal(max_num(missing, 2), 2)
    assert_equal(max_num(2, missing), 2)
    assert_equal(max_num(1, 2), 2)
    assert_equal(max_num(3, 2), 3)
    assert_equal(min_num(missing, 2), 2)
    assert_equal(min_num(2, missing), 2)
    assert_equal(min_num(1, 2), 1)
    assert_equal(min_num(3, 2), 2)


def test_rcas_is_three_js_s_arithmetic() raises:
    # A bright center in a darker ring: the lobe pushes it brighter.
    var ring = cross(0.5, 0.25, 0.25, 0.25, 0.25)
    assert_almost_equal(rcas_of(ring, 0.2, False), 0.8457587, atol=1e-5)
    assert_almost_equal(rcas_of(ring, 0.2, True), 0.6022037, atol=1e-5)
    # A ring of four values, no sharpness scale.
    var uneven = cross(0.5, 0.2, 0.3, 0.4, 0.6)
    assert_almost_equal(rcas_of(uneven, 0, False), 0.5625, atol=1e-5)
    assert_almost_equal(rcas_of(uneven, 0, True), 0.5489130, atol=1e-5)
    # An even image stays as it is.
    var even = cross(0.3, 0.3, 0.3, 0.3, 0.3)
    assert_almost_equal(rcas_of(even, 0.2, False), 0.3, atol=1e-6)
    # A black ring divides zero by zero; the NaN is passed over.
    var black = cross(0, 0, 0, 0, 0)
    var result = rcas_of(black, 0.2, False)
    assert_true(result == 0)


def test_rcas_keeps_the_alpha_and_premultiplies() raises:
    var image = List[FloatColor](
        length=9, fill=FloatColor(0.25, 0.25, 0.25, 0.5)
    )
    var result = rcas_pixel(LightView(image, 3, 3), 1, 1, 0.2, False)
    assert_almost_equal(result.a, 0.5, atol=1e-6)
    assert_almost_equal(result.r, 0.25, atol=1e-5)
    # A texel past the edge is the edge texel.
    var edge = load_straight(LightView(image, 3, 3), -4, 9)
    assert_almost_equal(edge.r, 0.5, atol=1e-6)


def test_the_settings_are_checked() raises:
    check_upscale(UpscaleSettings())
    var bad = UpscaleSettings()
    bad.sharpness = -1
    with assert_raises(contains="sharpness"):
        check_upscale(bad)
    bad = UpscaleSettings()
    bad.sharpness = Float32.MAX * 2
    with assert_raises(contains="sharpness"):
        check_upscale(bad)
    bad = UpscaleSettings()
    bad.resolution_scale = 0
    with assert_raises(contains="resolution scale"):
        check_upscale(bad)
    bad = UpscaleSettings()
    bad.resolution_scale = 1.5
    with assert_raises(contains="resolution scale"):
        check_upscale(bad)
    bad = UpscaleSettings()
    bad.resolution_scale = Float32.MAX * 2
    with assert_raises(contains="resolution scale"):
        check_upscale(bad)
    with assert_raises(contains="sharpness"):
        _ = sharpen_pass(-0.5)
    with assert_raises(contains="resolution scale"):
        _ = fsr1_pass(resolution_scale=2)
    assert_true(sharpen_pass().kind == SHARPEN)
    assert_true(fsr1_pass(0.1, True, 0.5).kind == FSR1)
    assert_true(fsr1_pass().upscale.resolution_scale == 1)


def test_the_easu_weight_is_one_at_the_center() raises:
    assert_almost_equal(easu_weight(0, 0, 1, 0, 1, 1, 0.5, 2), 1, atol=1e-6)
    # Past the clip, the kernel is flat at zero.
    assert_almost_equal(easu_weight(3, 0, 1, 0, 1, 1, 0.5, 2), 0, atol=1e-6)


def test_the_edge_sums_its_quadrants() raises:
    var edge = EasuEdge()
    edge.add(1, 0, 0, 0, 1, 0)
    assert_equal(edge.dir_x, 1)
    assert_equal(edge.dir_y, 0)
    assert_equal(edge.length, 1)


def image4() -> List[FloatColor]:
    """Return a 4 by 4 image of grays with an edge down its middle."""
    var values: List[Float32] = [
        0.1,
        0.2,
        0.8,
        0.9,
        0.1,
        0.3,
        0.7,
        0.9,
        0.2,
        0.3,
        0.8,
        0.8,
        0.1,
        0.2,
        0.9,
        0.9,
    ]
    var out = List[FloatColor]()
    for i in range(16):
        out.append(gray(values[i]))
    return out^


def test_easu_is_three_js_s_arithmetic() raises:
    var image = image4()
    var view = LightView(image, 4, 4)
    # Pixels whose results a reference of three.js's shader gives.
    assert_almost_equal(easu_pixel(view, 3, 3, 8, 8).r, 0.3507661, atol=1e-5)
    assert_almost_equal(easu_pixel(view, 4, 2, 8, 8).r, 0.6558798, atol=1e-5)
    assert_almost_equal(easu_pixel(view, 2, 5, 8, 8).r, 0.1659391, atol=1e-5)
    # At the corners the ringing is clamped to the four nearest texels.
    assert_almost_equal(easu_pixel(view, 0, 0, 8, 8).r, 0.1, atol=1e-6)
    assert_almost_equal(easu_pixel(view, 7, 7, 8, 8).g, 0.9, atol=1e-6)
    # An even image has no edge, and stays even.
    var flat = List[FloatColor](length=16, fill=gray(0.4))
    var even = easu_pixel(LightView(flat, 4, 4), 3, 4, 8, 8)
    assert_almost_equal(even.r, 0.4, atol=1e-6)
    assert_almost_equal(even.a, 1, atol=1e-6)
    # The view points into the image, so the image must outlive it.
    _ = image^


def test_the_light_functions_run_over_a_frame() raises:
    var frame = RenderTarget(8, 8, Color(0, 0, 0), FLOAT_TARGET)
    for y in range(8):
        for x in range(8):
            frame.colors[y * 8 + x] = gray(0.8 if x >= 4 else Float32(0.2))
    var sharp = frame.colors.copy()
    var before = frame.colors.copy()
    sharpen_light(frame, UpscaleSettings())
    # The bright side of the edge is brighter, the dark side darker.
    assert_true(frame.colors[3 * 8 + 4].r > before[3 * 8 + 4].r)
    assert_true(frame.colors[3 * 8 + 3].r < before[3 * 8 + 3].r)
    assert_almost_equal(frame.colors[0].r, 0.2, atol=1e-5)
    frame.colors = sharp^
    var settings = UpscaleSettings()
    settings.resolution_scale = 0.5
    fsr1_light(frame, settings)
    assert_almost_equal(frame.colors[0].r, 0.2, atol=1e-4)
    assert_almost_equal(frame.colors[63].r, 0.8, atol=1e-4)
    assert_false(frame.data[10])


def test_the_composer_runs_both_passes() raises:
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(sharpen_pass(0.5, True))
    composer.add_pass(fsr1_pass(resolution_scale=0.5))
    var image = composer.render(Renderer(8, 6), Scene(), Assets(), camera)
    assert_equal(image.width, 8)
    assert_equal(image.height, 6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
