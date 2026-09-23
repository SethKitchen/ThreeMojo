# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clearwater's spectrum, ripples, caustics, glare and graded frame."""

from extensions.water.caustics import (
    CausticField,
    caustic_covers,
    flat_shift,
    render_caustics,
)
from extensions.water.field import ComplexField, complex_mul, fft2
from extensions.water.filter import anisotropic_step
from extensions.water.frame import (
    CameraLook,
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
from render.png import SRGB, DecodedImage
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import RADIAN, SECOND, Angle, Duration, Length


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
