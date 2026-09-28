# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `CRT.js`, `radialBlur`, `BilateralBlurNode`,
`depthAwareBlur` and `depthAwareBlend`: their arithmetic against
three.js's, their settings, and their passes."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from math.vector3 import Vector3
from postprocessing.composer import (
    BILATERAL_BLUR,
    CRT,
    DEPTH_AWARE_BLEND,
    DEPTH_AWARE_BLUR,
    RADIAL_BLUR,
    EffectComposer,
    Pass,
    bilateral_blur_pass,
    crt_pass,
    depth_aware_blend_pass,
    depth_aware_blur_pass,
    radial_blur_pass,
    render_pass,
)
from postprocessing.filter_nodes import (
    FilterSettings,
    barrel_mask,
    barrel_uv,
    bilateral_blur_light,
    check_filters,
    circle,
    color_bleeding,
    crt_light,
    crt_pixel,
    crt_vignette,
    depth_aware_blend_light,
    depth_aware_blend_pixel,
    depth_aware_blur_light,
    interleaved_gradient_noise,
    perspective_depth_to_view_z,
    radial_blur_light,
    radial_blur_pixel,
    sample_down,
    scanlines,
    view_z_to_orthographic_depth,
)
from postprocessing.sampling import LightView
from postprocessing.screen_space import DepthView
from render.framebuffer import Color, FloatColor
from render.target import FLOAT_TARGET, RenderTarget
from render.texture import data_texture
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime SIZE = 8


def gray(value: Float32) -> FloatColor:
    """Return an opaque gray."""
    return FloatColor(value, value, value, 1)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera at the origin looking down -z."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(50.0, METER)
    )
    camera.place(Vector3(0, 0, 0), Vector3(0, 0, -1))
    return camera^


def a_view(distances: List[Float32]) raises -> DepthView:
    """Return a depth view of an 8 by 8 frame whose pixels lie at the given
    distances, row by row."""
    var camera = a_camera()
    var projection = camera.projection_matrix()
    var depth = List[Float32]()
    for slot in range(len(distances)):
        depth.append(
            projection.transform_point(Vector3(0, 0, -distances[slot])).z
        )
    return DepthView(
        depth, SIZE, SIZE, projection, Length(0.1, METER), Length(50.0, METER)
    )


def test_the_settings_are_checked() raises:
    check_filters(FilterSettings())
    var bad = FilterSettings()
    bad.exposure = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_filters(bad)
    bad = FilterSettings()
    bad.curvature = 0.5
    with assert_raises(contains="curvature"):
        check_filters(bad)
    bad = FilterSettings()
    bad.count = 0
    with assert_raises(contains="tap"):
        check_filters(bad)
    bad = FilterSettings()
    bad.sigma = 0
    with assert_raises(contains="sigmas"):
        check_filters(bad)
    bad = FilterSettings()
    bad.sigma_color = -1
    with assert_raises(contains="sigmas"):
        check_filters(bad)
    bad = FilterSettings()
    bad.radius = Length(0, METER)
    with assert_raises(contains="radius"):
        check_filters(bad)
    bad = FilterSettings()
    bad.edge_radius = -1
    with assert_raises(contains="edge radius"):
        check_filters(bad)
    with assert_raises(contains="blend texture"):
        _ = depth_aware_blend_pass(NO_TEXTURE)
    with assert_raises(contains="curvature"):
        _ = crt_pass(curvature=0.7)
    assert_true(crt_pass().kind == CRT)
    assert_true(radial_blur_pass().kind == RADIAL_BLUR)
    assert_true(bilateral_blur_pass().kind == BILATERAL_BLUR)
    assert_true(depth_aware_blur_pass().kind == DEPTH_AWARE_BLUR)
    var blend = depth_aware_blend_pass(TextureId(0), Color(255, 0, 0))
    assert_true(blend.kind == DEPTH_AWARE_BLEND)
    assert_almost_equal(blend.filters.blend_r, 1, atol=1e-6)
    assert_almost_equal(blend.filters.blend_g, 0, atol=1e-6)


def test_the_noise_is_three_js_s() raises:
    assert_almost_equal(
        interleaved_gradient_noise(0.5, 0.5), 0.9324913, atol=1e-5
    )
    assert_almost_equal(
        interleaved_gradient_noise(3.5, 7.5), 0.7645149, atol=1e-5
    )


def test_the_crt_functions_are_three_js_s() raises:
    var middle = barrel_uv(0.1, 0.5, 0.5)
    assert_almost_equal(middle[0], 0.5, atol=1e-6)
    var corner = barrel_uv(0.1, 1, 1)
    assert_almost_equal(corner[0], 1, atol=1e-6)
    assert_almost_equal(corner[1], 1, atol=1e-6)
    var side = barrel_uv(0.1, 0.75, 0.5)
    assert_almost_equal(side[0], 0.7051282, atol=1e-6)
    assert_equal(barrel_mask(0.5, 0.5), 1)
    assert_equal(barrel_mask(-0.1, 0.5), 0)
    assert_equal(barrel_mask(0.5, 1.1), 0)
    assert_equal(barrel_mask(1.1, 0.5), 0)
    assert_equal(barrel_mask(0.5, -0.1), 0)
    assert_almost_equal(scanlines(0.3, 240, 0, 0, 0.5), 0.7629083, atol=1e-4)
    # A rolling line moves with the clock.
    assert_almost_equal(
        scanlines(0.3, 240, 1, 0.25, 0.75), scanlines(0.3, 240, 0, 0, 0.5)
    )
    assert_almost_equal(circle(1.42, 0.5, 0.5, 0.5), 1, atol=1e-6)
    assert_almost_equal(crt_vignette(0.4, 0.5, 0.5, 0.5), 1, atol=1e-6)
    assert_almost_equal(crt_vignette(0.4, 0.5, 0, 0), 0.6000793, atol=1e-5)


def test_the_bleeding_smears_from_the_left() raises:
    # White stays white; a white pixel bleeds red into black to its right.
    var white = List[FloatColor](length=SIZE * SIZE, fill=gray(1))
    var kept = color_bleeding(LightView(white, SIZE, SIZE), 0.5, 0.5, 0.002)
    assert_almost_equal(kept.r, 1, atol=1e-6)
    assert_almost_equal(kept.b, 1, atol=1e-6)
    var half = List[FloatColor](length=SIZE * SIZE, fill=gray(0))
    for y in range(SIZE):
        for x in range(SIZE // 2):
            half[y * SIZE + x] = gray(1)
    var edge = color_bleeding(
        LightView(half, SIZE, SIZE), 4.5 / 8, 0.5, 1.0 / 8
    )
    assert_almost_equal(edge.r, (0.4 + 0.2 + 0.1) / 1.7, atol=1e-5)
    assert_almost_equal(edge.g, 0.35 / 1.35, atol=1e-5)
    assert_almost_equal(edge.b, 0.15 / 1.15, atol=1e-5)


def test_the_crt_darkens_the_corners() raises:
    var frame = RenderTarget(SIZE, SIZE, Color(255, 255, 255), FLOAT_TARGET)
    var settings = FilterSettings()
    settings.scanline_intensity = 0
    crt_light(frame, settings)
    assert_true(frame.colors[0].r < frame.colors[3 * SIZE + 3].r)
    assert_false(frame.data[0])
    # A negative curvature bends the edge pixels off the screen: black.
    var view_list = List[FloatColor](length=SIZE * SIZE, fill=gray(1))
    settings.curvature = -0.5
    var cut = crt_pixel(LightView(view_list, SIZE, SIZE), 0, 4, settings)
    assert_equal(cut.r, 0)


def test_the_radial_blur_is_three_js_s() raises:
    # An even frame: each tap is the pixel, weighed 0.9 times 0.95 to its
    # number, over 32, times 5, mixed with twice the pixel.
    var even = List[FloatColor](length=SIZE * SIZE, fill=gray(0.2))
    var settings = FilterSettings()
    var out = radial_blur_pixel(LightView(even, SIZE, SIZE), 2, 5, settings)
    assert_almost_equal(out.r, 0.2 * 2.1338432, atol=1e-4)
    assert_almost_equal(out.a, 1, atol=1e-6)
    # Premultiplied, three.js divides the sum's alpha back out.
    settings.premultiplied_alpha = True
    out = radial_blur_pixel(LightView(even, SIZE, SIZE), 2, 5, settings)
    assert_almost_equal(out.r, 0.2, atol=1e-4)
    # Over a frame, a bright center smears outward.
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    frame.colors[4 * SIZE + 4] = gray(1)
    radial_blur_light(frame, FilterSettings())
    assert_true(frame.colors[6 * SIZE + 6].r > 0)


def test_the_bilateral_blur_keeps_edges() raises:
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    for y in range(SIZE):
        for x in range(SIZE):
            frame.colors[y * SIZE + x] = gray(0.9 if x >= 4 else Float32(0.1))
    var settings = FilterSettings()
    bilateral_blur_light(frame, settings)
    assert_almost_equal(frame.colors[3 * SIZE + 3].r, 0.1, atol=1e-3)
    assert_almost_equal(frame.colors[3 * SIZE + 4].r, 0.9, atol=1e-3)
    # A wide color sigma blurs across the edge.
    settings.sigma_color = 10
    bilateral_blur_light(frame, settings)
    assert_true(frame.colors[3 * SIZE + 3].r > 0.2)


def test_the_depth_conversions_are_three_js_s() raises:
    # The near plane is at z = -near, the far at z = -far.
    assert_almost_equal(
        perspective_depth_to_view_z(0, 0.1, 50), -0.1, atol=1e-6
    )
    assert_almost_equal(perspective_depth_to_view_z(1, 0.1, 50), -50, atol=1e-3)
    assert_almost_equal(view_z_to_orthographic_depth(-0.1, 0.1, 50), 0)
    assert_almost_equal(view_z_to_orthographic_depth(-50, 0.1, 50), 1)


def test_the_depth_aware_blur_stops_at_a_depth_step() raises:
    var distances = List[Float32]()
    for _ in range(SIZE):
        for x in range(SIZE):
            distances.append(2 if x < 4 else Float32(20))
    var view = a_view(distances)
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    for y in range(SIZE):
        for x in range(SIZE):
            frame.colors[y * SIZE + x] = gray(0 if x < 4 else Float32(1))
    depth_aware_blur_light(frame, view, FilterSettings())
    assert_almost_equal(frame.colors[3 * SIZE + 3].r, 0, atol=1e-3)
    assert_almost_equal(frame.colors[3 * SIZE + 4].r, 1, atol=1e-3)
    assert_almost_equal(frame.colors[3 * SIZE + 4].a, 1, atol=1e-6)


def test_the_depth_aware_blend_mixes_by_the_mask() raises:
    var distances = List[Float32](length=SIZE * SIZE, fill=3)
    var view = a_view(distances)
    var black = List[FloatColor](length=SIZE * SIZE, fill=gray(0))
    var mask = List[FloatColor](length=SIZE * SIZE, fill=gray(0.5))
    var settings = FilterSettings()
    settings.blend_g = 0
    settings.blend_b = 0
    var out = depth_aware_blend_pixel(
        LightView(black, SIZE, SIZE),
        LightView(mask, SIZE, SIZE),
        view,
        3,
        3,
        settings,
    )
    assert_almost_equal(out.r, 0.5, atol=1e-5)
    assert_almost_equal(out.g, 0, atol=1e-5)
    # The push follows the taps that share the depth: a mask that is red
    # only a pixel to the right is read there.
    var right = List[FloatColor](length=SIZE * SIZE, fill=gray(0))
    for y in range(SIZE):
        right[y * SIZE + 4] = gray(1)
    settings.edge_strength = 8
    var pushed = depth_aware_blend_pixel(
        LightView(black, SIZE, SIZE),
        LightView(right, SIZE, SIZE),
        view,
        3,
        3,
        settings,
    )
    assert_true(pushed.r > 0)
    # With no reach every tap is the pixel: no push.
    settings.edge_radius = 0
    var still = depth_aware_blend_pixel(
        LightView(black, SIZE, SIZE),
        LightView(right, SIZE, SIZE),
        view,
        3,
        3,
        settings,
    )
    assert_almost_equal(still.r, 0, atol=1e-6)
    # A near pixel among far ones shares no tap's depth: no push either.
    var lone = List[Float32](length=SIZE * SIZE, fill=30)
    lone[3 * SIZE + 3] = 2
    settings.edge_radius = 3
    var apart = depth_aware_blend_pixel(
        LightView(black, SIZE, SIZE),
        LightView(right, SIZE, SIZE),
        a_view(lone),
        3,
        3,
        settings,
    )
    assert_almost_equal(apart.r, 0, atol=1e-6)
    # Over a frame, and refused with a mask of another size.
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    depth_aware_blend_light(frame, view, mask, FilterSettings())
    assert_almost_equal(frame.colors[0].r, 0.5, atol=1e-5)
    with assert_raises(contains="one blend texel"):
        depth_aware_blend_light(
            frame,
            view,
            List[FloatColor](length=3, fill=gray(0)),
            FilterSettings(),
        )


def test_sample_down_reads_from_the_top() raises:
    var image = List[FloatColor](length=4, fill=gray(0))
    image[0] = gray(1)
    assert_almost_equal(
        sample_down(LightView(image, 2, 2), 0.25, 0.25).r, 1, atol=1e-6
    )
    # The view points into the image, so the image must outlive it.
    _ = image^


def test_the_composer_runs_every_filter() raises:
    var assets = Assets()
    var mask = assets.textures.add(data_texture(1, 1, [1.0, 0.0, 0.0, 1.0]))
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(crt_pass(scanline_speed=1))
    composer.add_pass(radial_blur_pass(premultiplied_alpha=True))
    composer.add_pass(bilateral_blur_pass())
    composer.add_pass(depth_aware_blur_pass())
    composer.add_pass(depth_aware_blend_pass(mask))
    var image = composer.render(
        Renderer(SIZE, SIZE), Scene(), assets, a_camera(), 0.5
    )
    assert_equal(image.width, SIZE)
    assert_almost_equal(composer.passes[1].filters.time, 0.5)
    # The blend texture is white-red: every pixel takes the blend color.
    assert_equal(image.get_pixel(4, 4).r, 255)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
