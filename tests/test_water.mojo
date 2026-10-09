# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clearwater's spectrum, ripples, caustics, glare and graded frame."""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import BASIC, Material
from objects.mesh import Mesh
from renderers.renderer import Renderer
from extensions.water.caustics import (
    _splat,
    CausticField,
    caustic_covers,
    flat_shift,
    render_caustics,
)
from extensions.water.field import ComplexField, complex_mul, fft2
from extensions.water.filter import anisotropic_step
from extensions.water.frame import (
    CameraLook,
    WaterScene,
    camera_look,
    floor_f,
    grade_pixel,
    render_water,
    water_radiance,
)
from extensions.water.glare import aperture_open, apply_glare, glare_kernels
from extensions.water.pebbles import (
    PebbleBed,
    pebble_bed,
    sample_pebble,
    sample_pebble_grad,
)
from extensions.water.optics import (
    aces_channel,
    bed_color,
    beckmann,
    channel_ior,
    clamp01,
    fbm2,
    floor_depth,
    fresnel,
    hash12,
    max,
    refract,
    refracted_sun,
    sky_radiance,
    smith_visibility,
    sun_direction,
    value_noise,
    water_ior,
)
from extensions.water.random import Mulberry32, gaussian_pair
from extensions.water.resolution import (
    log2_resolution,
    require_resolution,
    SpectrumResolution,
)
from extensions.water.ripple import (
    RippleField,
    clearwater_ripple_size,
    sample_ripple,
    step_ripple,
)
from extensions.water.spectrum import (
    angular_frequency,
    build_spectrum,
    clearwater_depth,
    clearwater_patch,
    clearwater_slope,
    evolve_spectrum,
)
from extensions.water.surface import (
    SurfaceField,
    SurfaceSample,
    clearwater_surface,
    sample_surface,
    sample_surface_filtered,
    sample_surface_smooth,
    shader_time,
    slope_variance,
    water_surface,
)
from extensions.water.view import (
    CAUSTICS,
    FRAME,
    GLARE,
    LINEAR,
    WaterView,
    require_view,
)
from math.vector3 import Vector3
from std.math import cos, inf, isfinite, nan, sin, sqrt
from render.framebuffer import Color, Framebuffer
from render.png import SRGB, DecodedImage
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, RADIAN, SECOND, Angle, Duration, Length


def test_resolution_and_view() raises:
    assert_true(SpectrumResolution(4).is_valid())
    assert_true(SpectrumResolution(256).is_valid())
    assert_true(not SpectrumResolution(3).is_valid())
    assert_true(not SpectrumResolution(512).is_valid())
    assert_true(not SpectrumResolution(0).is_valid())
    assert_true(not SpectrumResolution(-4).is_valid())
    assert_true(not SpectrumResolution(6).is_valid())
    assert_equal(log2_resolution(SpectrumResolution(8)), 3)
    assert_equal(log2_resolution(SpectrumResolution(4)), 2)
    with assert_raises():
        require_resolution(SpectrumResolution(6))
    with assert_raises():
        _ = ComplexField(SpectrumResolution(3))
    assert_true(FRAME.is_valid())
    assert_true(CAUSTICS.is_valid())
    assert_true(LINEAR.is_valid())
    assert_true(GLARE.is_valid())
    assert_true(not WaterView(-1).is_valid())
    assert_true(not WaterView(4).is_valid())
    require_view(FRAME)
    with assert_raises():
        require_view(WaterView(9))


def test_mulberry_matches_the_page() raises:
    var rng = Mulberry32(7)
    assert_almost_equal(rng.next_unit(), 0.0117047532, atol=1e-9)
    assert_almost_equal(rng.next_unit(), 0.0619582576, atol=1e-9)
    var again = Mulberry32(7)
    assert_almost_equal(again.gauss(), 2.7593729870, atol=1e-6)
    var zero = Mulberry32(0)
    zero.state = 2463401483
    _ = zero.gauss()
    assert_almost_equal(gaussian_pair(0.0, 0.0), 7.433848, atol=1e-3)
    assert_almost_equal(gaussian_pair(0.5, 0.25), 0.0, atol=1e-6)


def test_fft_round_trip() raises:
    var field = ComplexField(SpectrumResolution(4))
    field.put(0, 0, 0, 1.0)
    var forward = fft2(field, 1.0)
    assert_almost_equal(forward.channel(0, 0, 0), 1.0)
    assert_almost_equal(forward.channel(3, 2, 0), 1.0)
    var back = fft2(forward, -1.0)
    assert_almost_equal(back.channel(0, 0, 0), 16.0, atol=1e-4)
    assert_almost_equal(back.channel(1, 2, 0), 0.0, atol=1e-3)
    with assert_raises():
        _ = fft2(field, 0.0)
    var prod = complex_mul(1.0, 2.0, 3.0, -4.0)
    assert_almost_equal(prod[0], 11.0)
    assert_almost_equal(prod[1], 2.0)
    _ = field.index(1, 2)


def test_spectrum_and_surface() raises:
    assert_almost_equal(clearwater_patch().value, 4.6)
    assert_almost_equal(clearwater_depth().value, 1.6)
    assert_almost_equal(clearwater_slope(), 0.078)
    assert_almost_equal(angular_frequency(1.0), 3.03687290, atol=1e-5)
    assert_almost_equal(angular_frequency(0.0), 0.0)
    assert_almost_equal(angular_frequency(-10.0), angular_frequency(10.0))
    assert_almost_equal(angular_frequency(10.0), 9.84365698, atol=1e-4)
    var resolution = SpectrumResolution(4)
    var patch = Length(4.6)
    var h0 = build_spectrum(resolution, patch, 0.078)
    var at_zero = evolve_spectrum(h0, patch, Duration(0.0, SECOND))
    var at_loop = evolve_spectrum(h0, patch, Duration(60.0, SECOND))
    assert_almost_equal(
        at_zero.channel(1, 2, 0), at_loop.channel(1, 2, 0), atol=1e-4
    )
    var surface = water_surface(resolution, patch, Duration(0.0, SECOND), 0.078)
    var a = sample_surface(surface, 0.2, -0.4)
    var b = sample_surface(surface, 0.2 + 4.6, -0.4)
    assert_almost_equal(a.height, b.height, atol=1e-5)
    var negative = slope_variance(SurfaceSample(0.0, 2.0, 0.0, 0.0))
    assert_almost_equal(negative, 0.0)
    var positive = slope_variance(SurfaceSample(0.0, 0.2, 0.1, 1.0))
    assert_true(positive > 0.0)
    var scaled = shader_time(Duration(10.0, SECOND))
    assert_almost_equal(scaled.value, 9.0)
    var page = clearwater_surface(Duration(0.0, SECOND))
    var center = sample_surface(page, 0.0, 0.0)
    var smooth = sample_surface_smooth(page, 0.2, -0.4)
    assert_true(smooth.height < 5.0)
    assert_true(smooth.height > -5.0)
    _ = center.height
    with assert_raises():
        _ = build_spectrum(resolution, Length(-1.0), 0.078)
    with assert_raises():
        _ = build_spectrum(resolution, patch, 0.0)
    with assert_raises():
        _ = evolve_spectrum(h0, Length(0.0), Duration(1.0, SECOND))


def test_ripples() raises:
    assert_almost_equal(clearwater_ripple_size().value, 7.0)
    with assert_raises():
        _ = RippleField(SpectrumResolution(4), Length(0.0))
    with assert_raises():
        _ = RippleField(SpectrumResolution(6), Length(7.0))
    var field = RippleField(SpectrumResolution(16), Length(7.0))
    step_ripple(field, 0.0, 0.0, 0.5, 0.5, 0.08, 0.07)
    var calm = RippleField(SpectrumResolution(16), Length(7.0))
    step_ripple(calm, 0.0, 0.0, 0.5, 0.5, 0.08, 0.0)
    var shifted = RippleField(SpectrumResolution(4), Length(7.0))
    step_ripple(shifted, -2.0, 0.0, 0.5, 0.5, 0.02, 0.0)
    step_ripple(shifted, 0.0, -2.0, 0.5, 0.5, 0.02, 0.0)
    step_ripple(shifted, 2.0, 0.0, 0.5, 0.5, 0.02, 0.0)
    step_ripple(shifted, 0.0, 2.0, 0.5, 0.5, 0.02, 0.0)
    var mid = sample_ripple(field, 0.0, 0.0)
    assert_true(mid.height != 0.0)
    _ = sample_ripple(field, -3.5, 0.0)
    _ = sample_ripple(field, 3.5, 0.0)
    _ = sample_ripple(field, 0.0, -3.5)
    _ = sample_ripple(field, 0.0, 3.5)
    var outside = sample_ripple(field, 40.0, 0.0)
    assert_almost_equal(outside.height, 0.0)
    var left = sample_ripple(field, -40.0, 0.0)
    assert_almost_equal(left.height, 0.0)
    var down = sample_ripple(field, 0.0, -40.0)
    assert_almost_equal(down.height, 0.0)
    var up = sample_ripple(field, 0.0, 40.0)
    assert_almost_equal(up.height, 0.0)


def test_optics() raises:
    assert_almost_equal(water_ior(), 1.3335)
    assert_almost_equal(channel_ior(0), 1.3315)
    assert_almost_equal(channel_ior(1), 1.3335)
    assert_almost_equal(channel_ior(2), 1.3365)
    assert_almost_equal(channel_ior(5), 1.3335)
    assert_almost_equal(clamp01(-1.0), 0.0)
    assert_almost_equal(clamp01(2.0), 1.0)
    assert_almost_equal(clamp01(0.25), 0.25)
    assert_almost_equal(fresnel(1.0, 1.3335), 0.02042566, atol=1e-5)
    assert_almost_equal(fresnel(0.0, 1.3335), 1.0, atol=1e-5)
    assert_almost_equal(fresnel(0.0, 0.5), 1.0)
    var air = refract(0.0, -1.0, 0.0, 0.0, 1.0, 0.0, 1.0 / 1.3335)
    assert_true(air.hit)
    var tir = refract(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 2.0)
    assert_true(not tir.hit)
    assert_almost_equal(beckmann(0.0, 0.2), 0.0)
    assert_almost_equal(beckmann(0.8, 0.0), 0.0)
    _ = beckmann(0.001, 0.2)
    assert_true(beckmann(0.5, 0.2) > 0.0)
    assert_true(smith_visibility(0.4, 0.5, 0.04) > 0.0)
    assert_almost_equal(aces_channel(0.0), 0.0)
    assert_almost_equal(aces_channel(1.0), 0.80379747, atol=1e-5)
    assert_almost_equal(aces_channel(-2.0), 0.0)
    assert_almost_equal(aces_channel(40.0), 1.0)
    assert_almost_equal(max(2.0, 1.0), 2.0)
    assert_almost_equal(max(1.0, 3.0), 3.0)
    assert_true(hash12(1.2, 3.4) >= 0.0)
    _ = value_noise(1.3, 2.4)
    _ = fbm2(0.2, 0.4)
    var sun = sun_direction()
    assert_true(sun.y > 0.0)
    _ = sky_radiance(0.0, 0.0, 0.0, sun)
    _ = sky_radiance(sun.x, sun.y, sun.z, sun)
    _ = sky_radiance(-sun.x, -sun.y, -sun.z, sun)
    _ = sky_radiance(0.0, 1.0, 0.0, sun)
    _ = sky_radiance(0.0, -1.0, 0.0, sun)
    _ = sky_radiance(1.0, 0.2, 0.0, sun)
    _ = sky_radiance(1.0, 0.2, 0.0, Vector3(0.0, 1.0, 0.0))
    _ = sky_radiance(0.0, -0.5, 1.0, sun)
    var shallow = floor_depth(0.0, 0.0)
    var near = floor_depth(0.0, 10.0)
    var far = floor_depth(0.0, -20.0)
    assert_true(shallow > 0.0)
    assert_true(near > 0.0)
    assert_true(far > shallow)
    var stones = _stones()
    var bed = bed_color(stones, 0.4, -1.2)
    assert_true(bed.r > 0.0)
    _ = bed_color(stones, -3.0, 2.5)
    var sample = sample_pebble(stones, -0.2, 1.4)
    assert_true(sample.r > 0.0)
    var bytes = List[UInt8](length=4, fill=128)
    bytes[3] = 255
    var photo = pebble_bed(DecodedImage(1, 1, bytes^, SRGB))
    assert_true(photo.pixels[0] > 0.1)
    assert_true(photo.pixels[0] < 0.3)
    with assert_raises():
        _ = PebbleBed(0, 1, List[Float32]())
    with assert_raises():
        _ = PebbleBed(1, 0, List[Float32]())
    with assert_raises():
        var short = List[Float32](length=1, fill=0.0)
        _ = PebbleBed(1, 1, short^)
    with assert_raises():
        var empty = List[UInt8]()
        _ = pebble_bed(DecodedImage(0, 1, empty^, SRGB))
    with assert_raises():
        var thin = List[UInt8](length=4, fill=0)
        _ = pebble_bed(DecodedImage(1, 0, thin^, SRGB))
    with assert_raises():
        var short_rgba = List[UInt8](length=4, fill=0)
        _ = pebble_bed(DecodedImage(2, 2, short_rgba^, SRGB))


def test_caustics() raises:
    var sun = sun_direction()
    var shift = flat_shift(sun, 1.6)
    _ = shift[0]
    _ = flat_shift(Vector3(0.2, 0.0, 0.8), 1.6)
    _ = flat_shift(Vector3(0.0, 2.0, 0.0), 1.6)
    _ = flat_shift(Vector3(0.0, 1.0, 0.0), 1.6)
    with assert_raises():
        _ = CausticField(0, Length(4.6))
    with assert_raises():
        _ = CausticField(4, Length(-1.0))
    var flat = _filled(0.0, 0.0, 0.0)
    var image = render_caustics(flat, sun, Length(1.6), 2, 8)
    assert_true(image.channel(4, 4, 1) >= 0.0)
    var low = Vector3(0.0, -0.70710677, -0.70710677)
    _ = render_caustics(_corner(0, 0), low, Length(1.6), 2, 4)
    _ = render_caustics(_corner(2, 0), low, Length(1.6), 2, 4)
    _ = render_caustics(_corner(0, 2), low, Length(1.6), 2, 4)
    var folded = _folded()
    var bright = render_caustics(folded, sun, Length(1.6), 2, 32)
    assert_true(bright.channel(0, 0, 0) >= 0.0)
    var focus = _focus()
    var hot = render_caustics(focus, sun, Length(1.6), 2, 8)
    assert_true(hot.channel(0, 0, 1) >= 0.0)
    with assert_raises():
        _ = render_caustics(flat, sun, Length(1.6), 0, 4)
    with assert_raises():
        _ = render_caustics(flat, sun, Length(0.0), 2, 4)
    var inside = 0
    var outside = 0
    for y in range(-1, 4):
        for x in range(-1, 4):
            var px = Float32(x) * 0.7
            var py = Float32(y) * 0.7
            if caustic_covers(px, py, 0.0, 0.0, 2.0, 0.0, 0.0, 2.0, 4.0):
                inside += 1
            else:
                outside += 1
            _ = caustic_covers(px, py, 0.0, 0.0, 0.0, 2.0, 2.0, 0.0, -4.0)
    assert_true(inside > 0)
    assert_true(outside > 0)


def test_glare() raises:
    var radius = Float32(64) * 0.11
    assert_true(not aperture_open(radius + 3.0, 0.0, radius, 64))
    var open_count = 0
    var shut_count = 0
    for y in range(-32, 32):
        for x in range(-32, 32):
            if aperture_open(Float32(x) * 0.2, Float32(y) * 0.2, radius, 64):
                open_count += 1
            else:
                shut_count += 1
    assert_true(open_count > 0)
    assert_true(shut_count > 0)
    var small = glare_kernels(SpectrumResolution(4))
    var wide = glare_kernels(SpectrumResolution(64))
    var picture = List[Float32](length=2 * 2 * 3, fill=0.0)
    picture[0] = 4.0
    picture[1] = 3.0
    picture[2] = 2.0
    var glare = apply_glare(picture, 2, 2, small)
    assert_equal(len(glare), 12)
    _ = apply_glare(picture, 2, 2, wide)
    var tall = List[Float32](length=1 * 30 * 3, fill=1.0)
    _ = apply_glare(tall, 1, 30, small)
    var wide_image = List[Float32](length=30 * 1 * 3, fill=1.0)
    _ = apply_glare(wide_image, 30, 1, small)
    var negative = List[Float32](length=2 * 2 * 3, fill=0.0)
    negative[0] = -5.0
    negative[1] = -5.0
    negative[2] = -5.0
    _ = apply_glare(negative, 2, 2, wide)
    with assert_raises():
        _ = apply_glare(picture, 0, 2, small)
    with assert_raises():
        _ = apply_glare(picture, 3, 3, small)
    with assert_raises():
        _ = apply_glare(picture, 2, 0, small)


def test_grade_and_camera() raises:
    var page_pitch = Angle(-0.72, RADIAN)
    var still = camera_look(Duration(5.0, SECOND), False, page_pitch)
    var sway = camera_look(Duration(5.0, SECOND), True, page_pitch)
    assert_true(sway.px != still.px or sway.py != still.py)
    assert_almost_equal(floor_f(1.8), 1.0)
    assert_almost_equal(floor_f(-1.2), -2.0)
    var clock = Duration(5.0, SECOND)
    var linear = grade_pixel(
        1.0, 0.4, 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, 1, 4, 4, clock, LINEAR
    )
    var frame = grade_pixel(
        1.0, 0.4, 0.2, 0.01, 0.0, 0.0, 0.2, 0.0, 0.0, 0, 0, 4, 4, clock, FRAME
    )
    var glare = grade_pixel(
        0.0, 0.0, 0.0, 0.02, 0.01, 0.0, 0.0, 0.0, 0.0, 3, 2, 4, 4, clock, GLARE
    )
    var dark = grade_pixel(
        -1.0,
        -1.0,
        -1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0,
        0,
        2,
        2,
        clock,
        LINEAR,
    )
    assert_true(linear.x > 0.0)
    assert_true(frame.x != linear.x)
    assert_true(glare.x >= 0.0 or glare.x < 0.0)
    _ = dark.x


def test_frame_pictures() raises:
    var ocean = SpectrumResolution(4)
    var glare = SpectrumResolution(4)
    var clock = Duration(5.0, SECOND)
    var stones = _stones()
    var page_pitch = Angle(-0.72, RADIAN)
    with assert_raises():
        _ = render_water(
            0,
            2,
            clock,
            FRAME,
            False,
            ocean,
            2,
            4,
            glare,
            False,
            stones,
            page_pitch,
        )
    with assert_raises():
        _ = render_water(
            2,
            0,
            clock,
            FRAME,
            False,
            ocean,
            2,
            4,
            glare,
            False,
            stones,
            page_pitch,
        )
    with assert_raises():
        _ = render_water(
            2,
            2,
            clock,
            WaterView(8),
            False,
            ocean,
            2,
            4,
            glare,
            False,
            stones,
            page_pitch,
        )
    var caustics = render_water(
        2,
        2,
        clock,
        CAUSTICS,
        False,
        ocean,
        2,
        4,
        glare,
        False,
        stones,
        page_pitch,
    )
    var linear = render_water(
        2, 2, clock, LINEAR, False, ocean, 2, 4, glare, True, stones, page_pitch
    )
    var frame = render_water(
        3, 3, clock, FRAME, True, ocean, 2, 4, glare, True, stones, page_pitch
    )
    var spikes = render_water(
        2, 1, clock, GLARE, False, ocean, 2, 4, glare, False, stones, page_pitch
    )
    var glint = render_water(
        32,
        18,
        clock,
        LINEAR,
        False,
        SpectrumResolution(16),
        2,
        4,
        glare,
        False,
        stones,
        page_pitch,
    )
    assert_equal(caustics.width, 2)
    assert_equal(linear.height, 2)
    assert_equal(frame.width, 3)
    assert_equal(spikes.width, 2)
    assert_equal(glint.width, 32)
    var total = 0
    for y in range(frame.height):
        for x in range(frame.width):
            var pixel = frame.get_pixel(x, y)
            total += Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
    assert_true(total > 0)


def test_view_rays() raises:
    var flat = _filled(0.0, 0.0, 0.0)
    var deep = _filled(-10.0, 0.0, 0.0)
    var steep = _filled(0.0, 100.0, 0.0)
    var away = _filled(0.0, -20.0, 5.0)
    var calm = _ripples(0.0)
    var sharp = _ripples(80.0)
    var spread = _ripples(-5.5)
    var caustics = CausticField(4, Length(4.6))
    var down = CameraLook(
        0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.4, 0.0
    )
    var up = CameraLook(
        0.0, 0.8, -0.2, 1.0, 0.0, 0.0, 0.0, 0.2, 0.8, 0.0, 1.5, 0.0
    )
    var ahead = CameraLook(
        0.0, -0.4, 0.8, 1.0, 0.0, 0.0, 0.0, 0.8, 0.4, 0.0, 1.2, 0.0
    )
    var graze = CameraLook(
        0.0, -0.02, -1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.3, 0.0
    )
    var clock = Duration(1.0, SECOND)
    var stones = _stones()
    _ = water_radiance(down, 0.0, 0.0, 1.0, flat, calm, caustics, stones, clock)
    _ = water_radiance(down, 0.0, 0.0, 1.0, deep, calm, caustics, stones, clock)
    _ = water_radiance(
        down, 0.0, 0.0, 1.0, flat, sharp, caustics, stones, clock
    )
    _ = water_radiance(
        down, 0.0, 0.0, 1.0, flat, spread, caustics, stones, clock
    )
    _ = water_radiance(
        down, 0.0, 0.0, 1.0, steep, calm, caustics, stones, clock
    )
    _ = water_radiance(down, 0.0, 0.0, 1.0, away, calm, caustics, stones, clock)
    _ = water_radiance(up, 0.0, 0.0, 1.0, flat, calm, caustics, stones, clock)
    _ = water_radiance(
        ahead, 0.2, -0.4, 1.2, flat, calm, caustics, stones, clock
    )
    _ = water_radiance(
        graze, 0.0, 0.0, 1.6, steep, calm, caustics, stones, sun_clock(0.0)
    )
    _ = water_radiance(
        _down(0.84, 0.66), 0.0, 0.0, 1.0, flat, calm, caustics, stones, clock
    )
    _ = water_radiance(
        _down(0.72, 0.93), 0.0, 0.0, 1.0, flat, calm, caustics, stones, clock
    )
    _ = water_radiance(
        _down(0.0, 1.53), 0.0, 0.0, 1.0, flat, calm, caustics, stones, clock
    )
    _ = water_radiance(
        _down(0.2, 0.2), 0.0, 0.0, 1.0, flat, calm, caustics, stones, clock
    )
    var shallow = _filled(-0.9, 0.0, 0.0)
    _ = water_radiance(
        _down(0.72, 0.93), 0.0, 0.0, 1.0, shallow, calm, caustics, stones, clock
    )
    _ = water_radiance(
        _down(0.84, 0.66), 0.0, 0.0, 1.0, shallow, calm, caustics, stones, clock
    )


def test_texture_filter() raises:
    var zero = anisotropic_step(0.0, 0.0, 0.0, 0.0, 8.0, 8.0, 8.0, 0.0, 2.0)
    assert_equal(zero.taps, 1)
    assert_almost_equal(zero.lod, 0.0)
    var tall = anisotropic_step(0.0, 0.01, 0.0, 1.0, 16.0, 16.0, 8.0, 0.0, 4.0)
    assert_true(tall.taps > 1)
    var wide = anisotropic_step(
        1.0, 0.0, 0.0, 0.0001, 64.0, 64.0, 8.0, 1.0, 2.0
    )
    assert_equal(wide.taps, 8)
    assert_almost_equal(wide.lod, 2.0)
    var mid = anisotropic_step(
        4.0 / 64.0, 0.0, 4.0 / 64.0, 0.0, 64.0, 64.0, 8.0, 0.0, 6.0
    )
    assert_equal(mid.taps, 1)
    assert_almost_equal(mid.lod, 2.0, atol=1e-4)
    var stones = _stones()
    var sharp = sample_pebble_grad(stones, 0.25, 0.25, 0.0, 0.0, 0.0, 0.0)
    var plain = sample_pebble(stones, 0.25, 0.25)
    assert_almost_equal(sharp.r, plain.r, atol=1e-5)
    var blur = sample_pebble_grad(stones, 0.25, 0.25, 0.5, 0.0, 0.0, 0.5)
    assert_true(blur.r > 0.0)
    var row = List[Float32](length=6, fill=0.2)
    var thin = PebbleBed(1, 2, row^)
    assert_equal(thin.mip_w[0], 1)
    var col = List[Float32](length=6, fill=0.4)
    var flat_bed = PebbleBed(2, 1, col^)
    assert_equal(flat_bed.mip_h[0], 1)
    _ = bed_color(stones, 0.2, 0.4, 0.3, 0.0, 0.0, 0.3)
    var grid = ComplexField(SpectrumResolution(8))
    grid.put(1, 2, 0, 1.0)
    grid.put(1, 2, 1, 0.2)
    var ocean = SurfaceField(Length(4.6), grid^)
    assert_true(len(ocean.mips) > 0)
    var cubic = sample_surface_filtered(
        ocean, 0.4, 0.5, 0.0, 0.0, 0.0, 0.0, True
    )
    assert_true(cubic.height < 5.0)
    var soft = sample_surface_filtered(
        ocean, 0.4, 0.5, 0.2, 0.0, 0.2, 0.0, True
    )
    var fine = sample_surface_filtered(
        ocean, 0.4, 0.5, 0.02, 0.0, 0.0, 0.02, False
    )
    var broad = sample_surface_filtered(
        ocean, 0.4, 0.5, 0.4, 0.0, 0.01, 0.0, False
    )
    assert_true(soft.height < 5.0)
    assert_true(fine.height < 5.0)
    assert_true(broad.height < 5.0)
    var clock = Duration(5.0, SECOND)
    var calm = _ripples(0.0)
    var caustics = render_caustics(
        _filled(0.0, 0.0, 0.0), sun_direction(), Length(1.6), 2, 4
    )
    assert_true(len(caustics.mip_n) > 0)
    var near = CameraLook(
        0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.02, 0.0
    )
    _ = water_radiance(
        near,
        0.0,
        0.0,
        1.0,
        _filled(0.0, 0.0, 0.0),
        calm,
        caustics,
        stones,
        clock,
        0.25,
        0.25,
    )
    var up = CameraLook(
        0.0, 0.2, -1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.55, 0.0
    )
    _ = water_radiance(
        up,
        0.0,
        0.2,
        1.0,
        _filled(0.0, 0.0, 0.0),
        calm,
        caustics,
        stones,
        clock,
        0.1,
        0.1,
    )
    # A straight-down ray aimed at one dark speck. The tint needs hash > 0.992.
    var ix = Float32(0.0)
    var iz = Float32(0.0)
    var ox = Float32(0.0)
    var oz = Float32(0.0)
    var found = False
    for cell_z in range(-30, 30):
        for cell_x in range(-30, 30):
            var cx = Float32(cell_x)
            var cz = Float32(cell_z)
            if hash12(cx, cz) > 0.992:
                ix = cx
                iz = cz
                ox = hash12(cx + 3.1, cz) - 0.5
                oz = hash12(cx, cz + 7.7) - 0.5
                found = True
                break
        if found:
            break
    assert_true(found)
    var qx = ix + 0.5 + ox * 0.6
    var qz = iz + 0.5 + oz * 0.6
    var hit_x = (qx - clock.value * 0.05) / 48.0
    var hit_z = (qz - clock.value * 0.02) / 48.0
    var speck = CameraLook(
        0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, hit_x, 1.55, hit_z
    )
    var shaded = water_radiance(
        speck,
        0.0,
        0.0,
        1.0,
        _filled(0.0, 0.0, 0.0),
        calm,
        caustics,
        stones,
        clock,
    )
    assert_true(shaded.x == shaded.x)


def _stones() raises -> PebbleBed:
    var pixels = List[Float32](length=12, fill=0.35)
    pixels[0] = 0.15
    pixels[1] = 0.2
    pixels[2] = 0.1
    pixels[3] = 0.55
    pixels[4] = 0.5
    pixels[5] = 0.4
    pixels[9] = 0.7
    return PebbleBed(2, 2, pixels^)


def _filled(
    height: Float32, slope_x: Float32, slope_z: Float32
) raises -> SurfaceField:
    var field = ComplexField(SpectrumResolution(4))
    for y in range(4):
        for x in range(4):
            field.put(x, y, 0, height)
            field.put(x, y, 1, slope_x)
            field.put(x, y, 2, slope_z)
            var square = slope_x * slope_x + slope_z * slope_z
            field.put(x, y, 3, square)
    return SurfaceField(Length(4.6), field^)


def _down(x: Float32, z: Float32) -> CameraLook:
    return CameraLook(0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, x, 0.4, z)


def _folded() raises -> SurfaceField:
    var field = ComplexField(SpectrumResolution(4))
    field.put(2, 0, 1, 6.0)
    field.put(0, 2, 2, -4.0)
    field.put(2, 2, 1, 3.0)
    return SurfaceField(Length(4.6), field^)


def _focus() raises -> SurfaceField:
    var field = ComplexField(SpectrumResolution(4))
    field.put(2, 2, 1, 4.0)
    return SurfaceField(Length(4.6), field^)


def _corner(tx: Int, ty: Int) raises -> SurfaceField:
    var field = ComplexField(SpectrumResolution(4))
    field.put(tx, ty, 1, -20.0)
    field.put(tx, ty, 3, 400.0)
    return SurfaceField(Length(4.6), field^)


def _ripples(laplacian: Float32) raises -> RippleField:
    var field = RippleField(SpectrumResolution(4), Length(7.0))
    for i in range(16):
        field.normal[i * 4 + 3] = laplacian
    return field^


def sun_clock(seconds: Float32) -> Duration:
    return Duration(seconds, SECOND)


def test_flat_caustics_conserve_energy_on_shared_edges() raises:
    # Every center falls on a cell diagonal. It must belong to one triangle.
    var grid = ComplexField(SpectrumResolution(4))
    var surface = SurfaceField(Length(4.0), grid^)
    var image = render_caustics(surface, Vector3(0, 1, 0), Length(1), 4, 4)
    for y in range(4):
        for x in range(4):
            for channel in range(3):
                assert_almost_equal(image.channel(x, y, channel), Float32(1))
    # Either winding must select the same pixels; a collapsed face adds none.
    var first = caustic_covers(0.5, 0.5, 0, 0, 1, 0, 0, 1, 1)
    var reversed = caustic_covers(0.5, 0.5, 0, 0, 0, 1, 1, 0, -1)
    var second = caustic_covers(0.5, 0.5, 1, 0, 1, 1, 0, 1, 1)
    assert_equal(first, reversed)
    assert_true(first != second)
    assert_true(not caustic_covers(0.5, 0.5, 0, 0, 1, 1, 2, 2, 0))


def test_water_samples_use_texture_texel_centers() raises:
    var grid = ComplexField(SpectrumResolution(8))
    for y in range(8):
        for x in range(8):
            grid.put(x, y, 0, Float32(x))
    var surface = SurfaceField(Length(8), grid^)
    assert_almost_equal(sample_surface(surface, 2.5, 2.5).height, Float32(2))
    assert_almost_equal(
        sample_surface_smooth(surface, 2.5, 2.5).height, Float32(2)
    )
    assert_almost_equal(
        sample_surface_filtered(surface, 2.5, 2.5, 0, 0, 0, 0, False).height,
        Float32(2),
    )
    # Repeat sampling wraps the half-texel on the left, rather than shifting it.
    assert_almost_equal(sample_surface(surface, 0, 2.5).height, Float32(3.5))
    var pixels: List[Float32] = [1, 0, 0, 0, 1, 0]
    var bed = PebbleBed(2, 1, pixels^)
    assert_almost_equal(sample_pebble(bed, 0.25, 0.5).r, Float32(1))
    assert_almost_equal(sample_pebble(bed, 0.25, 0.5).g, Float32(0))
    assert_almost_equal(
        sample_pebble_grad(bed, 0.75, 0.5, 0, 0, 0, 0).g, Float32(1)
    )


def test_underwater_sun_keeps_its_incident_direction() raises:
    var sun = sun_direction()
    var ray = refracted_sun(sun)
    var eta = 1.0 / water_ior()
    assert_true(ray.hit)
    assert_almost_equal(ray.x, -sun.x * eta)
    assert_almost_equal(ray.z, -sun.z * eta)
    assert_almost_equal(ray.y, -sqrt(1.0 - eta * eta * (1.0 - sun.y * sun.y)))
    assert_true(ray.y > -0.9)
    var vertical = refracted_sun(Vector3(0, 1, 0))
    assert_almost_equal(vertical.y, Float32(-1))


def test_spectrum_and_glare_refuse_invalid_sizes_at_entry() raises:
    for side in [0, -4, 3, 512]:
        with assert_raises(contains="power of two"):
            _ = build_spectrum(SpectrumResolution(side), Length(4.6), 0.078)
        with assert_raises(contains="power of two"):
            _ = glare_kernels(SpectrumResolution(side))


def test_caustic_splat_rejects_collapsed_and_caps_tight_focus() raises:
    var image = CausticField(1, Length(1))
    var x = List[Float32](length=9, fill=0.5)
    var z = List[Float32](length=9, fill=0.5)
    var live = List[Int](length=9, fill=1)
    # A point has no area and deposits no light, even on a pixel center.
    _splat(image, x, z, live, 0, 1, 2, 1, 0, 0, 0, 0, 0.5, 1)
    assert_almost_equal(image.channel(0, 0, 1), Float32(0))
    # A small but nonzero triangle retains its energy cap. An epsilon-area
    # rejection would erase this valid focus instead of bounding it.
    x[1] = 0.49
    z[1] = 0.49
    x[4] = 0.51
    z[4] = 0.49
    x[7] = 0.5
    z[7] = 0.51
    _splat(image, x, z, live, 0, 1, 2, 1, 0, 0, 0, 0, 0.5, 1)
    assert_almost_equal(image.channel(0, 0, 1), Float32(40))


def _assert_same_picture(a: Framebuffer, b: Framebuffer) raises:
    assert_equal(a.width, b.width)
    assert_equal(a.height, b.height)
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            assert_equal(p.r, q.r)
            assert_equal(p.g, q.g)
            assert_equal(p.b, q.b)
            assert_equal(p.a, q.a)


def _scene(clock: Duration) raises -> WaterScene:
    return WaterScene(SpectrumResolution(4), 2, 4, SpectrumResolution(4), clock)


def test_water_scene_draws_what_render_water_draws() raises:
    # render_water is one scene step and one draw, for every view.
    var clock = Duration(5.0, SECOND)
    var stones = _stones()
    var pitch = Angle(-0.72, RADIAN)
    for view in [CAUSTICS, LINEAR, FRAME, GLARE]:
        var scene = _scene(clock)
        scene.advance(Duration(0.0, SECOND), True)
        _assert_same_picture(
            scene.draw(3, 2, view, True, stones, pitch),
            render_water(
                3,
                2,
                clock,
                view,
                True,
                SpectrumResolution(4),
                2,
                4,
                SpectrumResolution(4),
                True,
                stones,
                pitch,
            ),
        )


def test_water_scene_steps_deterministically_and_resets() raises:
    var stones = _stones()
    var pitch = Angle(-0.72, RADIAN)
    var a = _scene(Duration(1.0, SECOND))
    var b = _scene(Duration(1.0, SECOND))
    var tick = Duration(1.0 / 60.0, SECOND)
    for k in range(12):
        a.advance(tick, k % 5 == 0)
        b.advance(tick, k % 5 == 0)
    assert_equal(a.steps, 12)
    assert_equal(a.clock.value, b.clock.value)
    var first = a.draw(3, 2, FRAME, False, stones, pitch)
    _assert_same_picture(first, b.draw(3, 2, FRAME, False, stones, pitch))
    # Drawing does not change the simulation.
    assert_equal(a.steps, 12)
    _assert_same_picture(first, a.draw(3, 2, FRAME, False, stones, pitch))
    # A reset scene replays exactly as a new one does.
    a.reset()
    assert_equal(a.steps, 0)
    assert_equal(a.clock.value, 1.0)
    var fresh = _scene(Duration(1.0, SECOND))
    for k in range(3):
        a.advance(tick, k == 0)
        fresh.advance(tick, k == 0)
    _assert_same_picture(
        a.draw(3, 2, LINEAR, False, stones, pitch),
        fresh.draw(3, 2, LINEAR, False, stones, pitch),
    )


def test_water_scene_keeps_bounded_resources() raises:
    var stones = _stones()
    var pitch = Angle(-0.72, RADIAN)
    var scene = _scene(Duration(0.0, SECOND))
    var cells = len(scene._ripples.height)
    var spectrum = len(scene._spectrum.samples)
    # The glare kernels are built on the first frame that needs them, and
    # a reset keeps them.
    assert_false(Bool(scene._glare))
    _ = scene.draw(2, 2, LINEAR, False, stones, pitch)
    assert_false(Bool(scene._glare))
    _ = scene.draw(2, 2, GLARE, False, stones, pitch)
    assert_true(Bool(scene._glare))
    for k in range(400):
        scene.advance(Duration(0.01, SECOND), k % 7 == 0)
    scene.reset()
    assert_true(Bool(scene._glare))
    assert_equal(len(scene._ripples.height), cells)
    assert_equal(len(scene._ripples.velocity), cells)
    assert_equal(len(scene._spectrum.samples), spectrum)


def test_water_scene_refuses_bad_steps_and_pictures() raises:
    var stones = _stones()
    var pitch = Angle(-0.72, RADIAN)
    var scene = _scene(Duration(0.0, SECOND))
    for bad in [inf[DType.float32](), nan[DType.float32](), -0.5]:
        with assert_raises(contains="time step"):
            scene.advance(Duration(bad, SECOND), False)
    assert_equal(scene.steps, 0)
    with assert_raises(contains="dimensions"):
        _ = scene.draw(0, 2, FRAME, False, stones, pitch)
    with assert_raises(contains="dimensions"):
        _ = scene.draw(2, 0, FRAME, False, stones, pitch)
    with assert_raises():
        _ = scene.draw(2, 2, WaterView(8), False, stones, pitch)


def _page_camera(width: Int, height: Int) raises -> PerspectiveCamera:
    # Clearwater's still camera: 1.55 m up, 64 degrees, pitched down 0.72.
    var camera = PerspectiveCamera(
        Angle(64.0, DEGREE),
        Float32(width) / Float32(height),
        Length(0.01, METER),
        Length(1000.0, METER),
    )
    var pitch = Float32(-0.72)
    camera.place(
        Vector3(0, 1.55, 0), Vector3(0, 1.55 + sin(pitch), -cos(pitch))
    )
    return camera^


def test_composed_water_matches_the_page_camera() raises:
    # With Clearwater's own camera and an empty depth buffer, composition
    # draws the LINEAR picture wherever a ray reaches the water.
    var stones = _stones()
    var scene = _scene(Duration(5.0, SECOND))
    var picture = scene.draw(6, 4, LINEAR, False, stones, Angle(-0.72, RADIAN))
    var image = Framebuffer(6, 4, Color(0, 0, 0))
    var drawn = scene.compose(
        image, _page_camera(6, 4), Length(0.0, METER), stones
    )
    assert_equal(drawn, 24)
    for y in range(4):
        for x in range(6):
            var a = image.get_pixel(x, y)
            var b = picture.get_pixel(x, y)
            assert_true(abs(Int(a.r) - Int(b.r)) <= 2)
            assert_true(abs(Int(a.g) - Int(b.g)) <= 2)
            assert_true(abs(Int(a.b) - Int(b.b)) <= 2)
            assert_true(image.depth_at(x, y) < 1.0)


def test_composed_water_respects_the_scene_depth() raises:
    # A white ball floats above the water in a rendered scene. Water fills
    # the rest of the view below the horizon; the ball and the sky stay.
    var width = 16
    var height = 12
    var assets = Assets()
    var world = Scene()
    var node = world.add(Object3D())
    world.node(node).set_position(0, 0.6, -2.5)
    var paint = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    world.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.35, METER), 12, 8)),
            paint,
            node,
        )
    )
    world.update()
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE),
        Float32(width) / Float32(height),
        Length(0.05, METER),
        Length(200.0, METER),
    )
    camera.place(Vector3(0, 1.2, 0), Vector3(0, 0.4, -3))
    var renderer = Renderer(width, height)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(world, assets, camera)
    var before = image.depth.copy()
    var ball = camera.screen_matrix(width, height).transform_point(
        Vector3(0, 0.6, -2.5)
    )
    var bx = Int(ball.x)
    var by = Int(ball.y)
    assert_equal(image.get_pixel(bx, by).r, 255)
    var water = _scene(Duration(5.0, SECOND))
    var drawn = water.compose(image, camera, Length(0.0, METER), _stones())
    assert_true(drawn > 0)
    # The ball is nearer than the water behind it, so it keeps its pixel.
    var kept = image.get_pixel(bx, by)
    assert_equal(kept.r, 255)
    assert_equal(kept.g, 255)
    assert_equal(image.depth_at(bx, by), before[by * width + bx])
    # The top row looks above the horizon and stays clear.
    for x in range(width):
        assert_equal(image.get_pixel(x, 0).r, 0)
    # The bottom row looks down at the water, which is drawn with depth.
    for x in range(width):
        assert_true(image.depth_at(x, height - 1) < 1.0)
    # Every water pixel holds a depth no farther than before.
    for i in range(width * height):
        assert_true(image.depth[i] <= before[i])


def test_composition_refuses_unsupported_cameras() raises:
    var stones = _stones()
    var water = _scene(Duration(1.0, SECOND))
    var image = Framebuffer(4, 4, Color(0, 0, 0))
    var below = _page_camera(4, 4)
    below.place(Vector3(0, -0.5, 0), Vector3(0, -1, -1))
    with assert_raises(contains="above the water"):
        _ = water.compose(image, below, Length(0.0, METER), stones)
    var level = _page_camera(4, 4)
    with assert_raises(contains="above the water"):
        _ = water.compose(image, level, Length(2.0, METER), stones)
    var flat = OrthographicCamera(
        Length(-1.0, METER),
        Length(1.0, METER),
        Length(1.0, METER),
        Length(-1.0, METER),
        Length(0.1, METER),
        Length(10.0, METER),
    )
    flat.place(Vector3(0, 2, 0), Vector3(0, 0, -1))
    with assert_raises(contains="centered perspective"):
        _ = water.compose(image, flat, Length(0.0, METER), stones)
    # A shifted projection is refused, horizontally or vertically.
    for slot in [8, 9]:
        var shifted = _page_camera(4, 4)
        var matrix = shifted.projection_matrix()
        matrix.elements[slot] = 0.1
        shifted.projection_override = matrix
        with assert_raises(contains="centered perspective"):
            _ = water.compose(image, shifted, Length(0.0, METER), stones)


def test_water_scene_takes_the_scene_sun() raises:
    var stones = _stones()
    var pitch = Angle(-0.72, RADIAN)
    var scene = _scene(Duration(5.0, SECOND))
    var page = scene.draw(4, 3, LINEAR, False, stones, pitch)
    # A directional light's position minus its target, any length.
    scene.set_sun(Vector3(0.0, 2.0, 0.0))
    assert_equal(scene.sun.x, 0.0)
    assert_equal(scene.sun.y, 1.0)
    var overhead = scene.draw(4, 3, LINEAR, False, stones, pitch)
    var changed = 0
    for y in range(3):
        for x in range(4):
            if page.get_pixel(x, y).r != overhead.get_pixel(x, y).r:
                changed += 1
    assert_true(changed > 0)
    # Composition shades with the same sun as the scene's own picture.
    var image = Framebuffer(4, 3, Color(0, 0, 0))
    _ = scene.compose(image, _page_camera(4, 3), Length(0.0, METER), stones)
    for y in range(3):
        for x in range(4):
            assert_true(
                abs(
                    Int(image.get_pixel(x, y).g)
                    - Int(overhead.get_pixel(x, y).g)
                )
                <= 2
            )
    for bad in [
        Vector3(0, 0, 0),
        Vector3(0, -1, 0),
        Vector3(1, 0, 0),
        Vector3(0, nan[DType.float32](), 0),
        Vector3(inf[DType.float32](), 1, 0),
    ]:
        with assert_raises():
            scene.set_sun(bad)
    assert_equal(scene.sun.y, 1.0)


def test_composition_skips_water_outside_the_depth_range() raises:
    # Water nearer than the near plane, or past the far plane, is not drawn.
    var stones = _stones()
    var water = _scene(Duration(1.0, SECOND))
    for near_far in [
        (Float32(50.0), Float32(100.0)),
        (Float32(0.01), Float32(0.5)),
    ]:
        var camera = PerspectiveCamera(
            Angle(64.0, DEGREE),
            1.0,
            Length(near_far[0], METER),
            Length(near_far[1], METER),
        )
        camera.place(Vector3(0, 1.55, 0), Vector3(0, 0.5, -1))
        var image = Framebuffer(4, 4, Color(0, 0, 0))
        assert_equal(
            water.compose(image, camera, Length(0.0, METER), stones), 0
        )


def _active_scene(clock: Duration) raises -> WaterScene:
    # The center tap reaches texel centers at this resolution.
    return WaterScene(
        SpectrumResolution(64), 2, 4, SpectrumResolution(4), clock
    )


def _assert_same_ripple_state(a: RippleField, b: RippleField) raises:
    assert_equal(a.n, b.n)
    assert_equal(a.size, b.size)
    assert_equal(a.center_x, b.center_x)
    assert_equal(a.center_z, b.center_z)
    assert_equal(len(a.height), len(b.height))
    assert_equal(len(a.velocity), len(b.velocity))
    assert_equal(len(a.normal), len(b.normal))
    for i in range(len(a.height)):
        assert_equal(a.height[i], b.height[i])
        assert_equal(a.velocity[i], b.velocity[i])
    for i in range(len(a.normal)):
        assert_equal(a.normal[i], b.normal[i])


def _assert_same_scene_state(a: WaterScene, b: WaterScene) raises:
    assert_equal(a.start.value, b.start.value)
    assert_equal(a.clock.value, b.clock.value)
    assert_equal(a.steps, b.steps)
    assert_equal(a.sun.x, b.sun.x)
    assert_equal(a.sun.y, b.sun.y)
    assert_equal(a.sun.z, b.sun.z)
    _assert_same_ripple_state(a._ripples, b._ripples)


def _assert_active_ripples(scene: WaterScene) raises:
    var height_changed = False
    var velocity_changed = False
    var normal_changed = False
    for value in scene._ripples.height:
        height_changed = height_changed or value != 0.0
    for value in scene._ripples.velocity:
        velocity_changed = velocity_changed or value != 0.0
    for value in scene._ripples.normal:
        normal_changed = normal_changed or value != 0.0
    assert_true(height_changed)
    assert_true(velocity_changed)
    assert_true(normal_changed)


def test_water_scene_active_ripples_step_and_replay_exactly() raises:
    var a = _active_scene(Duration(1.0, SECOND))
    var b = _active_scene(Duration(1.0, SECOND))
    var expected = RippleField(SpectrumResolution(64), clearwater_ripple_size())
    var tick = Duration(1.0 / 60.0, SECOND)
    var clock = Float32(1.0)
    for k in range(6):
        var drop = k % 3 == 0
        a.advance(tick, drop)
        b.advance(tick, drop)
        step_ripple(
            expected,
            0.0,
            0.0,
            0.5,
            0.5,
            0.022,
            Float32(0.07) if drop else Float32(0.0),
        )
        clock += tick.value
        assert_equal(a.clock.value, clock)
        assert_equal(a.steps, k + 1)
        _assert_same_scene_state(a, b)
        _assert_same_ripple_state(a._ripples, expected)
        if k == 0:
            # The first tap changes height before the next step adds velocity.
            assert_true(a._ripples.height[31 * 64 + 31] < 0.0)
    _assert_active_ripples(a)
    a.reset()
    var fresh = _active_scene(Duration(1.0, SECOND))
    _assert_same_scene_state(a, fresh)
    for k in range(6):
        a.advance(tick, k % 3 == 0)
        fresh.advance(tick, k % 3 == 0)
        _assert_same_scene_state(a, fresh)
    _assert_same_scene_state(a, b)


def test_water_scene_draw_preserves_active_ripples() raises:
    var a = _active_scene(Duration(1.0, SECOND))
    var b = _active_scene(Duration(1.0, SECOND))
    var tick = Duration(1.0 / 60.0, SECOND)
    a.advance(tick, True)
    b.advance(tick, True)
    a.advance(tick, False)
    b.advance(tick, False)
    _assert_active_ripples(a)
    var stones = _stones()
    var pitch = Angle(-0.72, RADIAN)
    for view in [CAUSTICS, LINEAR, FRAME, GLARE]:
        var picture = a.draw(3, 2, view, False, stones, pitch)
        _assert_same_scene_state(a, b)
        _assert_same_picture(picture, a.draw(3, 2, view, False, stones, pitch))
        _assert_same_scene_state(a, b)
    for bad in [0, -1]:
        with assert_raises(contains="dimensions"):
            _ = a.draw(bad, 2, FRAME, False, stones, pitch)
        _assert_same_scene_state(a, b)
        with assert_raises(contains="dimensions"):
            _ = a.draw(2, bad, FRAME, False, stones, pitch)
        _assert_same_scene_state(a, b)
    with assert_raises():
        _ = a.draw(2, 2, WaterView(8), False, stones, pitch)
    _assert_same_scene_state(a, b)


def test_water_scene_bad_steps_preserve_active_ripples() raises:
    var a = _active_scene(Duration(3e38, SECOND))
    var b = _active_scene(Duration(3e38, SECOND))
    a.advance(Duration(0.0, SECOND), True)
    b.advance(Duration(0.0, SECOND), True)
    a.advance(Duration(0.0, SECOND), False)
    b.advance(Duration(0.0, SECOND), False)
    _assert_active_ripples(a)
    for bad in [
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
        -0.5,
    ]:
        with assert_raises(contains="time step"):
            a.advance(Duration(bad, SECOND), True)
        _assert_same_scene_state(a, b)
    # Both operands are finite, but their Float32 sum is not.
    with assert_raises(contains="clock"):
        a.advance(Duration(3e38, SECOND), True)
    _assert_same_scene_state(a, b)


def test_water_scene_refuses_nonfinite_start_clocks() raises:
    var stones = _stones()
    var pitch = Angle(-0.72, RADIAN)
    for bad in [
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises(contains="start clock"):
            _ = _scene(Duration(bad, SECOND))
        # Time validation comes before spectrum allocation and validation.
        with assert_raises(contains="start clock"):
            _ = WaterScene(
                SpectrumResolution(3),
                2,
                4,
                SpectrumResolution(4),
                Duration(bad, SECOND),
            )
        for view in [CAUSTICS, LINEAR, FRAME, GLARE]:
            with assert_raises(contains="start clock"):
                _ = render_water(
                    2,
                    2,
                    Duration(bad, SECOND),
                    view,
                    False,
                    SpectrumResolution(4),
                    2,
                    4,
                    SpectrumResolution(4),
                    False,
                    stones,
                    pitch,
                )


def test_water_scene_keeps_negative_time_and_lazy_glare() raises:
    var stones = _stones()
    var pitch = Angle(-0.72, RADIAN)
    var scene = WaterScene(
        SpectrumResolution(4),
        2,
        4,
        SpectrumResolution(3),
        Duration(-1.0, SECOND),
    )
    assert_equal(scene.clock.value, Float32(-1.0))
    scene.advance(Duration(0.25, SECOND), True)
    assert_equal(scene.clock.value, Float32(-0.75))
    assert_equal(scene.steps, 1)
    for view in [CAUSTICS, LINEAR]:
        _assert_same_picture(
            scene.draw(2, 2, view, False, stones, pitch),
            render_water(
                2,
                2,
                Duration(-0.75, SECOND),
                view,
                False,
                SpectrumResolution(4),
                2,
                4,
                SpectrumResolution(3),
                True,
                stones,
                pitch,
            ),
        )
    assert_false(Bool(scene._glare))
    for view in [FRAME, GLARE]:
        with assert_raises(contains="power of two"):
            _ = scene.draw(2, 2, view, False, stones, pitch)
    scene.reset()
    assert_equal(scene.clock.value, Float32(-1.0))
    assert_equal(scene.steps, 0)


def test_composition_uses_the_attached_camera_parent_transform() raises:
    var width = 16
    var height = 12
    var world = Scene()
    var pivot = Object3D()
    pivot.set_position(1.0, 0.25, -0.5)
    pivot.set_euler(Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    var parent = world.add(pivot^)
    var eye = Object3D()
    eye.set_position(0.0, 1.55, 0.0)
    eye.set_euler(Angle(-0.72, RADIAN), Angle(0.0, RADIAN), Angle(0.0, RADIAN))
    var node = world.attach(eye^, parent)
    var assets = Assets()
    var ball_position = Vector3(-1.5, 0.6, -0.5)
    var ball_node = world.add(Object3D())
    world.node(ball_node).set_position(
        ball_position.x, ball_position.y, ball_position.z
    )
    var paint = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    world.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.35, METER), 12, 8)),
            paint,
            ball_node,
        )
    )
    world.update()
    var attached = _page_camera(width, height)
    attached.attach(node)
    # The parent's translation and quarter turn carry the pitched eye.
    var detached = _page_camera(width, height)
    detached.place(
        Vector3(1.0, 1.8, -0.5),
        Vector3(1.0 - cos(Float32(-0.72)), 1.8 + sin(Float32(-0.72)), -0.5),
    )
    var attached_view = attached.view_matrix_in(world)
    var detached_view = detached.view_matrix()
    for i in range(16):
        assert_almost_equal(
            attached_view.elements[i], detached_view.elements[i], atol=1e-6
        )
    var renderer = Renderer(width, height)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(world, assets, attached)
    var expected = renderer.render(world, assets, detached)
    var ball = detached.screen_matrix(width, height).transform_point(
        ball_position
    )
    var bx = Int(ball.x)
    var by = Int(ball.y)
    assert_equal(image.get_pixel(bx, by).r, 255)
    var before_depth = image.depth.copy()
    var water = _scene(Duration(5.0, SECOND))
    var control = _scene(Duration(5.0, SECOND))
    var stones = _stones()
    water.set_sun(Vector3(0.0, 2.0, 0.0))
    control.set_sun(Vector3(0.0, 2.0, 0.0))
    var count = water.compose(
        image, world, attached, Length(0.0, METER), stones
    )
    var expected_count = control.compose(
        expected, detached, Length(0.0, METER), stones
    )
    assert_true(count > 0)
    assert_equal(count, expected_count)
    _assert_same_scene_state(water, control)
    for i in range(len(image.pixels)):
        assert_true(abs(Int(image.pixels[i]) - Int(expected.pixels[i])) <= 2)
    for i in range(len(image.depth)):
        if isfinite(image.depth[i]):
            assert_almost_equal(image.depth[i], expected.depth[i], atol=1e-6)
        else:
            assert_equal(image.depth[i], expected.depth[i])
        assert_true(image.depth[i] <= before_depth[i])
    assert_equal(image.get_pixel(bx, by).r, 255)
    assert_equal(image.get_pixel(bx, by).g, 255)
    assert_equal(image.depth_at(bx, by), before_depth[by * width + bx])
    # The scene-aware overload also preserves detached-camera behavior.
    var plain = Framebuffer(4, 3, Color(0, 0, 0))
    var through_scene = Framebuffer(4, 3, Color(0, 0, 0))
    var camera = _page_camera(4, 3)
    assert_equal(
        water.compose(plain, camera, Length(0.0, METER), stones),
        water.compose(through_scene, world, camera, Length(0.0, METER), stones),
    )
    _assert_same_picture(plain, through_scene)
    for i in range(len(plain.depth)):
        assert_equal(plain.depth[i], through_scene.depth[i])


def test_composition_refuses_stale_or_missing_attached_camera_atomically() raises:
    var world = Scene()
    var eye = Object3D()
    eye.set_position(0.0, 1.55, 0.0)
    eye.set_euler(Angle(-0.72, RADIAN), Angle(0.0, RADIAN), Angle(0.0, RADIAN))
    var node = world.add(eye^)
    var camera = _page_camera(4, 3)
    camera.attach(node)
    var water = _active_scene(Duration(5.0, SECOND))
    var control = _active_scene(Duration(5.0, SECOND))
    water.advance(Duration(0.0, SECOND), True)
    control.advance(Duration(0.0, SECOND), True)
    water.advance(Duration(0.0, SECOND), False)
    control.advance(Duration(0.0, SECOND), False)
    _assert_active_ripples(water)
    var stones = _stones()
    var image = Framebuffer(4, 3, Color(31, 63, 127))
    image.depth[0] = -0.5
    var pixels = image.pixels.copy()
    var depth = image.depth.copy()
    for refusal in range(4):
        if refusal == 1:
            world.update()
            world.node(node).set_position(0.0, 2.0, 0.0)
        elif refusal == 2:
            world.update()
            camera.attach(NodeId(999))
        elif refusal == 3:
            camera.attach(node)
        with assert_raises():
            if refusal == 3:
                _ = water.compose(image, camera, Length(0.0, METER), stones)
            else:
                _ = water.compose(
                    image, world, camera, Length(0.0, METER), stones
                )
        for i in range(len(pixels)):
            assert_equal(image.pixels[i], pixels[i])
        for i in range(len(depth)):
            assert_equal(image.depth[i], depth[i])
        _assert_same_scene_state(water, control)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
