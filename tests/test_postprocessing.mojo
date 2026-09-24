# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `postprocessing.composer`: each pass against a worked-out
answer on a hand-built frame, and the composer against the renderer."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from materials.material import Material, distance_material, normal_material
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    AFTERIMAGE,
    AFTERIMAGE_FLOOR,
    BLOOM,
    BLUR,
    COPY,
    DOT_SCREEN,
    FILM,
    LUMINOSITY,
    OUTPUT,
    RENDER,
    SEPIA,
    VIGNETTE,
    EffectComposer,
    Pass,
    PassKind,
    afterimage_light,
    afterimage_pass,
    bloom_light,
    bloom_pass,
    blur_light,
    blur_pass,
    check_pass,
    clear_mask_pass,
    copy_light,
    copy_pass,
    dot_screen_light,
    dot_screen_pass,
    film_light,
    film_pass,
    luminance,
    luminosity_light,
    luminosity_pass,
    output_light,
    output_pass,
    reads_frame_as_light,
    render_pass,
    sepia_light,
    sepia_pass,
    vignette_light,
    vignette_pass,
)
from postprocessing.sampling import LightView
from postprocessing.screen_space import glsl_rand
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import RenderTarget
from render.tonemap import (
    ACES_FILMIC_TONE_MAPPING,
    NO_TONE_MAPPING,
    REINHARD_TONE_MAPPING,
)
from renderers.renderer import Renderer
from std.math import inf, min, nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, RADIAN

comptime WIDTH = 24
comptime HEIGHT = 18
comptime BLACK = Color(0, 0, 0)
comptime TOLERANCE = Float64(1e-5)


def flat(width: Int, height: Int, color: FloatColor) raises -> RenderTarget:
    """Return a frame every pixel of which holds `color`, straight."""
    var frame = RenderTarget(width, height, BLACK)
    for y in range(height):
        for x in range(width):
            frame.write(x, y, color)
    return frame^


def straight(frame: RenderTarget, x: Int, y: Int) raises -> FloatColor:
    """Return a pixel's straight color."""
    return frame.color_at(x, y).unpremultiplied()


def total_light(frame: RenderTarget) -> Float32:
    """Return the sum of every pixel's red."""
    var sum = Float32(0)
    for index in range(len(frame.colors)):
        sum += frame.colors[index].r
    return sum


def lit_sheet(mut assets: Assets) raises -> Scene:
    """Return a white sheet facing the camera under a lamp straight on."""
    var scene = Scene()
    var node = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(
        directional_light(Color(255, 255, 255), lamp_node, Float32(pi))
    )
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    scene.add_mesh(Mesh(sheet, paint, node))
    scene.update()
    return scene^


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking at the origin from four meters up z."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def count_differences(a: Framebuffer, b: Framebuffer) raises -> Int:
    """Return how many pixels differ between two images of one size."""
    var count = 0
    for y in range(a.height):
        for x in range(a.width):
            if not same(a.get_pixel(x, y), b.get_pixel(x, y)):
                count += 1
    return count


def same(a: Color, b: Color) -> Bool:
    """Return True if two colors match in every byte."""
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a


# --- the kinds and the builders ---------------------------------------------


def test_the_first_eleven_kinds_are_valid_and_a_twenty_seventh_is_not() raises:
    assert_true(RENDER.is_valid())
    assert_true(COPY.is_valid())
    assert_true(BLUR.is_valid())
    assert_true(BLOOM.is_valid())
    assert_true(FILM.is_valid())
    assert_true(DOT_SCREEN.is_valid())
    assert_true(SEPIA.is_valid())
    assert_true(VIGNETTE.is_valid())
    assert_true(LUMINOSITY.is_valid())
    assert_true(AFTERIMAGE.is_valid())
    assert_true(OUTPUT.is_valid())
    assert_false(PassKind(35).is_valid())


def test_each_builder_sets_its_kind_and_three_js_defaults() raises:
    assert_equal(render_pass().kind, RENDER)
    assert_true(render_pass().enabled)
    var copied = copy_pass()
    assert_equal(copied.kind, COPY)
    assert_equal(copied.strength, Float32(1))
    var blurred = blur_pass()
    assert_equal(blurred.kind, BLUR)
    assert_equal(blurred.radius, Float32(1))
    var bloomed = bloom_pass()
    assert_equal(bloomed.kind, BLOOM)
    assert_equal(bloomed.strength, Float32(1))
    assert_equal(bloomed.radius, Float32(0))
    assert_equal(bloomed.threshold, Float32(0))
    var grained = film_pass()
    assert_equal(grained.kind, FILM)
    assert_equal(grained.strength, Float32(0.5))
    assert_false(grained.grayscale)
    assert_equal(grained.time, Float32(0))
    var dotted = dot_screen_pass()
    assert_equal(dotted.kind, DOT_SCREEN)
    assert_almost_equal(dotted.center.x, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(dotted.angle.to(RADIAN), Float32(1.57), atol=TOLERANCE)
    assert_equal(dotted.scale, Float32(1))
    var tinted = sepia_pass()
    assert_equal(tinted.kind, SEPIA)
    assert_equal(tinted.strength, Float32(1))
    var darkened = vignette_pass()
    assert_equal(darkened.kind, VIGNETTE)
    assert_equal(darkened.offset, Float32(1))
    assert_equal(darkened.strength, Float32(1))
    assert_equal(luminosity_pass().kind, LUMINOSITY)
    var trailed = afterimage_pass()
    assert_equal(trailed.kind, AFTERIMAGE)
    assert_almost_equal(trailed.strength, Float32(0.96), atol=TOLERANCE)
    assert_equal(output_pass().kind, OUTPUT)
    # Each builder takes its settings.
    assert_equal(copy_pass(0.25).strength, Float32(0.25))
    assert_equal(blur_pass(2.5).radius, Float32(2.5))
    var custom = bloom_pass(1.5, 0.4, 0.85)
    assert_equal(custom.strength, Float32(1.5))
    assert_almost_equal(custom.radius, Float32(0.4), atol=TOLERANCE)
    assert_almost_equal(custom.threshold, Float32(0.85), atol=TOLERANCE)
    assert_true(film_pass(0.3, True).grayscale)
    var turned = dot_screen_pass(Vector2(1, 2), Angle(0.5, RADIAN), 3.0)
    assert_equal(turned.center.y, Float32(2))
    assert_almost_equal(turned.angle.to(RADIAN), Float32(0.5), atol=TOLERANCE)
    assert_equal(turned.scale, Float32(3))
    assert_equal(sepia_pass(0.5).strength, Float32(0.5))
    var soft = vignette_pass(0.8, 0.6)
    assert_almost_equal(soft.offset, Float32(0.8), atol=TOLERANCE)
    assert_almost_equal(soft.strength, Float32(0.6), atol=TOLERANCE)
    assert_almost_equal(
        afterimage_pass(0.5).strength, Float32(0.5), atol=TOLERANCE
    )


def test_a_pass_no_kind_could_run_is_refused() raises:
    with assert_raises():
        check_pass(Pass(PassKind(35)))
    with assert_raises():
        _ = copy_pass(-1)
    with assert_raises():
        _ = copy_pass(nan[DType.float32]())
    with assert_raises():
        _ = blur_pass(inf[DType.float32]())
    with assert_raises():
        _ = bloom_pass(1, 1.5, 0)
    with assert_raises():
        _ = bloom_pass(1, 0, -0.5)
    with assert_raises():
        _ = film_pass(-0.1)
    with assert_raises():
        _ = dot_screen_pass(scale=-1)
    with assert_raises():
        _ = dot_screen_pass(angle=Angle(nan[DType.float32](), RADIAN))
    with assert_raises():
        _ = dot_screen_pass(center=Vector2(inf[DType.float32](), 0))
    with assert_raises():
        _ = dot_screen_pass(center=Vector2(0, nan[DType.float32]()))
    with assert_raises():
        _ = sepia_pass(-0.5)
    with assert_raises():
        _ = vignette_pass(-1, 0)
    with assert_raises():
        _ = vignette_pass(1, nan[DType.float32]())
    with assert_raises():
        _ = afterimage_pass(1.5)
    with assert_raises():
        _ = afterimage_pass(-0.5)
    var stale = film_pass()
    stale.time = inf[DType.float32]()
    with assert_raises():
        check_pass(stale)
    var wide = bloom_pass()
    wide.threshold = nan[DType.float32]()
    with assert_raises():
        check_pass(wide)
    var off = vignette_pass()
    off.offset = nan[DType.float32]()
    with assert_raises():
        check_pass(off)
    var fine = dot_screen_pass()
    fine.scale = nan[DType.float32]()
    with assert_raises():
        check_pass(fine)
    # A bloom's radius of one and a damp of one are the edge, and pass.
    check_pass(bloom_pass(0, 1, 0))
    check_pass(afterimage_pass(1))


# --- the composer's list ----------------------------------------------------


def test_passes_are_added_inserted_and_removed_in_order() raises:
    var composer = EffectComposer()
    assert_equal(composer.pass_count(), 0)
    composer.add_pass(render_pass())
    composer.add_pass(output_pass())
    composer.insert_pass(sepia_pass(), 1)
    assert_equal(composer.pass_count(), 3)
    assert_equal(composer.passes[0].kind, RENDER)
    assert_equal(composer.passes[1].kind, SEPIA)
    assert_equal(composer.passes[2].kind, OUTPUT)
    composer.insert_pass(copy_pass(), 3)
    assert_equal(composer.passes[3].kind, COPY)
    composer.insert_pass(blur_pass(), 0)
    assert_equal(composer.passes[0].kind, BLUR)
    composer.remove_pass(0)
    assert_equal(composer.passes[0].kind, RENDER)
    composer.remove_pass(3)
    assert_equal(composer.pass_count(), 3)
    assert_equal(len(composer.memories), 3)
    with assert_raises():
        composer.remove_pass(3)
    with assert_raises():
        composer.remove_pass(-1)
    with assert_raises():
        composer.insert_pass(copy_pass(), 4)
    with assert_raises():
        composer.insert_pass(copy_pass(), -1)
    with assert_raises():
        composer.add_pass(Pass(PassKind(35)))
    with assert_raises():
        composer.insert_pass(Pass(PassKind(35)), 0)
    assert_equal(composer.pass_count(), 3)


# --- the passes on a frame --------------------------------------------------


def test_a_copy_scales_every_channel() raises:
    var frame = flat(2, 2, FloatColor(1, 0.5, 0.25, 0.8))
    copy_light(frame, 0.5)
    var pixel = frame.color_at(1, 1)
    assert_almost_equal(pixel.r, Float32(0.4), atol=TOLERANCE)
    assert_almost_equal(pixel.g, Float32(0.2), atol=TOLERANCE)
    assert_almost_equal(pixel.b, Float32(0.1), atol=TOLERANCE)
    assert_almost_equal(pixel.a, Float32(0.4), atol=TOLERANCE)


def test_a_blur_spreads_one_bright_pixel_by_three_js_weights() raises:
    # Nine taps across and nine down: the center keeps the middle weight
    # squared, the next pixel across the middle times the next, and the
    # light is conserved since every tap lands inside.
    var frame = RenderTarget(11, 11, BLACK)
    frame.write(5, 5, FloatColor(1, 1, 1, 1))
    blur_light(frame, 1.0)
    assert_almost_equal(
        frame.color_at(5, 5).r, Float32(0.1633 * 0.1633), atol=1e-6
    )
    assert_almost_equal(
        frame.color_at(6, 5).r, Float32(0.1633 * 0.1531), atol=1e-6
    )
    assert_almost_equal(
        frame.color_at(5, 7).r, Float32(0.1633 * 0.12245), atol=1e-6
    )
    assert_almost_equal(
        frame.color_at(1, 1).r, Float32(0.051 * 0.051), atol=1e-6
    )
    assert_equal(frame.color_at(0, 5).r, Float32(0))
    assert_almost_equal(total_light(frame), Float32(1), atol=1e-4)
    # The clear is opaque, so the alpha is one everywhere and stays so;
    # over a transparent clear the alpha blurs as the color does.
    assert_almost_equal(frame.color_at(5, 5).a, Float32(1), atol=1e-6)
    var clear = RenderTarget(11, 11, Color(0, 0, 0, 0))
    clear.write(5, 5, FloatColor(1, 1, 1, 1))
    blur_light(clear, 1.0)
    assert_almost_equal(
        clear.color_at(5, 5).a, Float32(0.1633 * 0.1633), atol=1e-6
    )
    # A spread of two reaches twice as far, and a spread of zero leaves
    # every pixel as it was.
    var wide = RenderTarget(11, 11, BLACK)
    wide.write(5, 5, FloatColor(1, 1, 1, 1))
    blur_light(wide, 2.0)
    assert_almost_equal(
        wide.color_at(7, 5).r, Float32(0.1633 * 0.1531), atol=1e-6
    )
    assert_equal(wide.color_at(6, 5).r, Float32(0))
    var still = RenderTarget(3, 3, BLACK)
    still.write(1, 1, FloatColor(1, 1, 1, 1))
    blur_light(still, 0.0)
    assert_almost_equal(still.color_at(1, 1).r, Float32(1), atol=1e-6)
    assert_equal(still.color_at(0, 1).r, Float32(0))
    # At an edge the taps are held on the last pixel, as a clamped texture
    # reads: the corner pixel keeps the five taps that land on it, each
    # way, and the light past the edge is duplicated rather than lost.
    var corner = RenderTarget(3, 3, BLACK)
    corner.write(0, 0, FloatColor(1, 1, 1, 1))
    blur_light(corner, 1.0)
    var held = Float32(0.051 + 0.0918 + 0.12245 + 0.1531 + 0.1633)
    assert_almost_equal(corner.color_at(0, 0).r, held * held, atol=1e-5)
    assert_true(total_light(corner) > 1, "the edge lost light")


def test_a_bloom_bleeds_light_past_the_threshold_and_none_below() raises:
    # A bright pixel in the dark blooms onto its neighbors; the same
    # pixel below the threshold does not; and no strength adds nothing.
    var frame = RenderTarget(16, 12, BLACK)
    frame.write(8, 6, FloatColor(4, 4, 4, 1))
    var before = frame.color_at(8, 6).r
    bloom_light(frame, 1.0, 0.0, 0.5)
    assert_true(frame.color_at(8, 6).r > before, "the pixel did not glow")
    assert_true(frame.color_at(10, 6).r > 0, "the glow did not spread")
    assert_true(frame.color_at(0, 0).r > 0, "the widest blur did not reach")
    assert_equal(frame.color_at(8, 6).a, Float32(1))
    assert_equal(frame.color_at(10, 6).a, Float32(1))
    var dim = RenderTarget(16, 12, BLACK)
    dim.write(8, 6, FloatColor(0.3, 0.3, 0.3, 1))
    bloom_light(dim, 1.0, 0.0, 0.5)
    assert_almost_equal(dim.color_at(8, 6).r, Float32(0.3), atol=1e-6)
    assert_equal(dim.color_at(10, 6).r, Float32(0))
    var still = RenderTarget(16, 12, BLACK)
    still.write(8, 6, FloatColor(4, 4, 4, 1))
    bloom_light(still, 0.0, 0.0, 0.0)
    assert_equal(still.color_at(8, 6).r, Float32(4))
    assert_equal(still.color_at(10, 6).r, Float32(0))
    # A larger radius weighs the wide blurs more: the far corner brightens
    # and the center dims relative to a radius of zero.
    var wide = RenderTarget(16, 12, BLACK)
    wide.write(8, 6, FloatColor(4, 4, 4, 1))
    bloom_light(wide, 1.0, 1.0, 0.5)
    assert_true(wide.color_at(0, 0).r > frame.color_at(0, 0).r, "no wider")
    assert_true(wide.color_at(8, 6).r < frame.color_at(8, 6).r, "no dimmer")
    # Twice the strength is four times the glow: twice the light, added
    # at twice the alpha, as three.js's additive blend adds it.
    var strong = RenderTarget(16, 12, BLACK)
    strong.write(8, 6, FloatColor(4, 4, 4, 1))
    bloom_light(strong, 2.0, 0.0, 0.5)
    assert_almost_equal(
        strong.color_at(10, 6).r, frame.color_at(10, 6).r * 4, atol=1e-5
    )
    # A frame one pixel wide has one-pixel levels and still blooms.
    var thin = RenderTarget(1, 3, BLACK)
    thin.write(0, 1, FloatColor(4, 4, 4, 1))
    bloom_light(thin, 1.0, 0.5, 0.0)
    assert_true(thin.color_at(0, 0).r > 0, "a thin frame did not bloom")


def test_film_grain_brightens_by_at_most_the_light_and_holds_at_zero() raises:
    var frame = flat(4, 4, FloatColor(0.5, 0.25, 0.125, 1))
    film_light(frame, 0.0, False, 0.0)
    assert_almost_equal(straight(frame, 1, 1).r, Float32(0.5), atol=TOLERANCE)
    film_light(frame, 1.0, False, 0.0)
    var varied = False
    for y in range(4):
        for x in range(4):
            var pixel = straight(frame, x, y)
            assert_true(pixel.r >= 0.5 * 1.1 - 1e-6, "grain took light away")
            assert_true(pixel.r <= 1.0 + 1e-6, "grain more than doubled")
            assert_almost_equal(pixel.g / pixel.r, Float32(0.5), atol=1e-5)
            assert_equal(pixel.a, Float32(1))
            if pixel.r != straight(frame, 0, 0).r:
                varied = True
    assert_true(varied, "the grain was the same everywhere")
    # Half the intensity is halfway; gray is the luminance; another time
    # is another grain.
    var half = flat(1, 1, FloatColor(0.5, 0.5, 0.5, 1))
    var full = flat(1, 1, FloatColor(0.5, 0.5, 0.5, 1))
    film_light(half, 0.5, False, 0.0)
    film_light(full, 1.0, False, 0.0)
    assert_almost_equal(
        straight(half, 0, 0).r - 0.5,
        (straight(full, 0, 0).r - 0.5) * 0.5,
        atol=1e-6,
    )
    var gray = flat(1, 1, FloatColor(1, 0, 0, 0.5))
    film_light(gray, 0.0, True, 0.0)
    assert_almost_equal(straight(gray, 0, 0).g, Float32(0.2126729), atol=1e-6)
    assert_almost_equal(straight(gray, 0, 0).a, Float32(0.5), atol=1e-6)
    var later = flat(1, 1, FloatColor(0.5, 0.5, 0.5, 1))
    film_light(later, 1.0, False, 0.37)
    assert_true(
        straight(later, 0, 0).r != straight(full, 0, 0).r,
        "time changed nothing",
    )


def test_a_bloom_adds_its_glow_weighted_by_its_own_alpha() raises:
    # three.js composites the five levels into a target whose alpha is
    # the strength times the level weights, since each blurred level is
    # opaque, and blends that over the frame with `AdditiveBlending`:
    # `SRC_ALPHA, ONE`. So the glow is added times its own alpha. On a
    # flat frame every level blurs to the frame itself, and with a radius
    # of zero the weights are one, 0.8, 0.6, 0.4 and 0.2, which sum to 3.
    var frame = flat(8, 8, FloatColor(0.5, 0.25, 0.125, 1))
    bloom_light(frame, 1.0, 0.0, 0.0)
    var glow = Float32(3.0 * 3.0)
    assert_almost_equal(frame.color_at(3, 3).r, 0.5 + 0.5 * glow, atol=1e-4)
    assert_almost_equal(frame.color_at(3, 3).b, 0.125 * (1 + glow), atol=1e-4)
    assert_equal(frame.color_at(3, 3).a, Float32(1))
    # Half the strength halves both the glow and its alpha.
    var half = flat(8, 8, FloatColor(0.5, 0.25, 0.125, 1))
    bloom_light(half, 0.5, 0.0, 0.0)
    assert_almost_equal(half.color_at(3, 3).r, 0.5 + 0.5 * 1.5 * 1.5, atol=1e-4)


def test_film_grain_is_three_js_rand_of_the_wrapped_coordinate() raises:
    # three.js reads `rand( fract( vUv + time ) )`, and its `rand` takes
    # the dot modulo pi before the sine. So a whole second later is the
    # same grain, and one pixel's grain is `glsl_rand` of its coordinate.
    var now = flat(1, 1, FloatColor(0.5, 0.5, 0.5, 1))
    var later = flat(1, 1, FloatColor(0.5, 0.5, 0.5, 1))
    film_light(now, 1.0, False, 0.25)
    film_light(later, 1.0, False, 3.25)
    assert_almost_equal(
        straight(later, 0, 0).r, straight(now, 0, 0).r, atol=1e-4
    )
    # The coordinate is read at run time, as the pass reads it, since a
    # sine this steep turns a constant folded at compile time into
    # another number.
    var at = straight(now, 0, 0).a * 0.75
    var grain = min(Float32(1), glsl_rand(at, at) + 0.1)
    assert_almost_equal(straight(now, 0, 0).r, 0.5 + 0.5 * grain, atol=1e-5)


def test_the_dot_screen_stretches_the_average_about_a_half() raises:
    # With no scale the grid is flat and a gray of 0.6 comes out as one,
    # exactly ten times its average less five; with the grid on, white
    # stays at or above white and black at or below black, and the dots
    # vary across the frame.
    var gray = flat(2, 2, FloatColor(0.6, 0.6, 0.6, 1))
    dot_screen_light(gray, Vector2(0.5, 0.5), Angle(1.57, RADIAN), 0.0)
    assert_almost_equal(straight(gray, 0, 0).r, Float32(1), atol=1e-5)
    assert_almost_equal(straight(gray, 1, 1).b, Float32(1), atol=1e-5)
    var mixed = flat(1, 1, FloatColor(0.9, 0.3, 0.6, 0.5))
    dot_screen_light(mixed, Vector2(0.5, 0.5), Angle(1.57, RADIAN), 0.0)
    assert_almost_equal(straight(mixed, 0, 0).g, Float32(1), atol=1e-5)
    assert_almost_equal(straight(mixed, 0, 0).a, Float32(0.5), atol=1e-6)
    var white = flat(8, 8, FloatColor(1, 1, 1, 1))
    dot_screen_light(white, Vector2(0.5, 0.5), Angle(1.57, RADIAN), 1.0)
    var black = flat(8, 8, FloatColor(0, 0, 0, 1))
    dot_screen_light(black, Vector2(0.5, 0.5), Angle(1.57, RADIAN), 1.0)
    var varied = False
    for y in range(8):
        for x in range(8):
            assert_true(straight(white, x, y).r >= 1 - 1e-5, "white fell")
            assert_true(straight(black, x, y).r <= -1 + 1e-5, "black rose")
            if straight(white, x, y).r != straight(white, 0, 0).r:
                varied = True
    assert_true(varied, "the dots were the same everywhere")
    # Turned, the pattern differs.
    var turned = flat(8, 8, FloatColor(1, 1, 1, 1))
    dot_screen_light(turned, Vector2(0.5, 0.5), Angle(0.3, RADIAN), 1.0)
    assert_true(
        straight(turned, 3, 2).r != straight(white, 3, 2).r,
        "the angle changed nothing",
    )


def test_sepia_tints_by_three_js_matrix_and_clamps_at_white() raises:
    var white = flat(1, 1, FloatColor(1, 1, 1, 1))
    sepia_light(white, 1.0)
    var tinted = straight(white, 0, 0)
    assert_almost_equal(tinted.r, Float32(1), atol=1e-6)
    assert_almost_equal(tinted.g, Float32(1), atol=1e-6)
    assert_almost_equal(tinted.b, Float32(0.937), atol=1e-5)
    var red = flat(1, 1, FloatColor(1, 0, 0, 0.5))
    sepia_light(red, 1.0)
    var warm = straight(red, 0, 0)
    assert_almost_equal(warm.r, Float32(0.393), atol=1e-5)
    assert_almost_equal(warm.g, Float32(0.349), atol=1e-5)
    assert_almost_equal(warm.b, Float32(0.272), atol=1e-5)
    assert_almost_equal(warm.a, Float32(0.5), atol=1e-6)
    var none = flat(1, 1, FloatColor(0.2, 0.4, 0.6, 1))
    sepia_light(none, 0.0)
    assert_almost_equal(straight(none, 0, 0).g, Float32(0.4), atol=1e-6)
    # Each channel clamps on its own.
    var green = flat(1, 1, FloatColor(0, 2, 0, 1))
    sepia_light(green, 1.0)
    var bright = straight(green, 0, 0)
    assert_almost_equal(bright.r, Float32(1), atol=1e-6)
    assert_almost_equal(bright.g, Float32(1), atol=1e-6)
    assert_almost_equal(bright.b, Float32(1), atol=1e-6)


def test_a_vignette_leaves_the_center_and_darkens_the_corners() raises:
    # On a three by three frame the middle pixel sits at the center, and a
    # corner is a third out each way: mixed two ninths toward black.
    var frame = flat(3, 3, FloatColor(1, 1, 1, 1))
    vignette_light(frame, 1.0, 1.0)
    assert_almost_equal(straight(frame, 1, 1).r, Float32(1), atol=1e-6)
    assert_almost_equal(straight(frame, 0, 0).r, Float32(7.0 / 9.0), atol=1e-6)
    assert_almost_equal(straight(frame, 2, 2).b, Float32(7.0 / 9.0), atol=1e-6)
    assert_equal(straight(frame, 0, 0).a, Float32(1))
    # Half the darkness goes toward a half gray; twice the offset reaches
    # four times as far in.
    var soft = flat(3, 3, FloatColor(1, 1, 1, 0.5))
    vignette_light(soft, 1.0, 0.5)
    assert_almost_equal(
        straight(soft, 0, 0).r, Float32(1 - 0.5 * 2.0 / 9.0), atol=1e-6
    )
    assert_almost_equal(straight(soft, 0, 0).a, Float32(0.5), atol=1e-6)
    var far = flat(3, 3, FloatColor(1, 1, 1, 1))
    vignette_light(far, 2.0, 1.0)
    assert_almost_equal(straight(far, 0, 0).r, Float32(1.0 / 9.0), atol=1e-6)


def test_luminosity_grays_by_rec_709() raises:
    var frame = flat(1, 1, FloatColor(1, 0, 0, 0.5))
    luminosity_light(frame)
    var gray = straight(frame, 0, 0)
    assert_almost_equal(gray.r, Float32(0.2126729), atol=1e-6)
    assert_almost_equal(gray.g, gray.r, atol=1e-7)
    assert_almost_equal(gray.b, gray.r, atol=1e-7)
    assert_almost_equal(gray.a, Float32(0.5), atol=1e-6)
    assert_almost_equal(
        luminance(FloatColor(0, 1, 0, 1)), Float32(0.7151522), atol=1e-7
    )
    assert_almost_equal(
        luminance(FloatColor(0, 0, 1, 1)), Float32(0.0721750), atol=1e-7
    )


def test_an_afterimage_keeps_the_last_frame_damped_above_a_tenth() raises:
    var memory = List[FloatColor]()
    var first = flat(2, 1, FloatColor(1, 0.05, 0.5, 1))
    afterimage_light(first, memory, 0.5)
    # The first frame starts the trail and is left as it was.
    assert_almost_equal(straight(first, 0, 0).r, Float32(1), atol=1e-6)
    assert_equal(len(memory), 2)
    var second = flat(2, 1, FloatColor(0.2, 0.2, 0.3, 1))
    afterimage_light(second, memory, 0.5)
    var trail = second.color_at(0, 0)
    # Red: the old one damped to a half beats the new fifth. Green: the old
    # one was under the floor and is dropped, so the new fifth stays.
    # Blue: the old half damped to a quarter loses to the new three tenths.
    assert_almost_equal(trail.r, Float32(0.5), atol=1e-6)
    assert_almost_equal(trail.g, Float32(0.2), atol=1e-6)
    assert_almost_equal(trail.b, Float32(0.3), atol=1e-6)
    assert_almost_equal(trail.a, Float32(1), atol=1e-6)
    assert_equal(AFTERIMAGE_FLOOR, Float32(0.1))
    # The result is what the next frame sees.
    assert_almost_equal(memory[0].r, Float32(0.5), atol=1e-6)
    # A frame of another size starts over.
    var other = flat(3, 1, FloatColor(0.1, 0.1, 0.1, 1))
    afterimage_light(other, memory, 0.5)
    assert_almost_equal(straight(other, 0, 0).r, Float32(0.1), atol=1e-6)
    assert_equal(len(memory), 3)


def test_the_output_pass_applies_the_curve_to_light_and_not_to_data() raises:
    var frame = RenderTarget(2, 1, BLACK)
    frame.write(0, 0, FloatColor(1, 1, 1, 1))
    frame.write(1, 0, FloatColor(1, 1, 1, 1), data=True)
    output_light(frame, REINHARD_TONE_MAPPING, 1.0)
    assert_almost_equal(frame.color_at(0, 0).r, Float32(0.5), atol=1e-6)
    assert_equal(frame.color_at(1, 0).r, Float32(1))
    # The curve sees the straight color, and the alpha comes back.
    var translucent = RenderTarget(1, 1, BLACK)
    translucent.write(0, 0, FloatColor(1, 1, 1, 0.5))
    output_light(translucent, REINHARD_TONE_MAPPING, 1.0)
    assert_almost_equal(translucent.color_at(0, 0).r, Float32(0.25), atol=1e-6)
    assert_almost_equal(translucent.color_at(0, 0).a, Float32(0.5), atol=1e-6)
    # No curve changes nothing.
    var plain = RenderTarget(1, 1, BLACK)
    plain.write(0, 0, FloatColor(3, 3, 3, 1))
    output_light(plain, NO_TONE_MAPPING, 1.0)
    assert_equal(plain.color_at(0, 0).r, Float32(3))


def test_a_packed_distance_keeps_its_bytes_through_the_output_pass() raises:
    # A packed distance's alpha is data and can be zero. The render and
    # output passes do not read the frame as light, so the composer leaves
    # the data pixels straight and shows the bytes the renderer shows.
    assert_false(reads_frame_as_light(RENDER))
    assert_false(reads_frame_as_light(OUTPUT))
    assert_true(reads_frame_as_light(SEPIA))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_tone_mapping(REINHARD_TONE_MAPPING)
    var assets = Assets()
    var scene = lit_sheet(assets)
    scene.meshes[0].material = assets.materials.add(
        distance_material(
            Vector3(0, 0, 4), Length(3.0, METER), Length(5.0, METER)
        )
    )
    var camera = a_camera()
    var direct = renderer.render(scene, assets, camera)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(output_pass())
    var composed = composer.render(renderer, scene, assets, camera)
    assert_equal(count_differences(direct, composed), 0)


def test_a_data_frame_survives_a_pass_that_reads_it_as_light() raises:
    # A copy at full opacity reads the frame as premultiplied light. The
    # composer premultiplies the data first and stores it straight after,
    # so the normal comes back as it was drawn.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = lit_sheet(assets)
    scene.meshes[0].material = assets.materials.add(normal_material())
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(copy_pass(1.0))
    var shown = composer.render(renderer, scene, assets, a_camera())
    assert_true(
        same(shown.get_pixel(WIDTH // 2, HEIGHT // 2), Color(128, 128, 255))
    )


# --- the composer on a scene ------------------------------------------------


def test_a_render_pass_and_an_output_pass_match_the_renderer() raises:
    # With its tone mapping set, the renderer applies the curve once to
    # each pixel's composited light; a render pass followed by an output
    # pass reaches the same bytes. Without the output pass the light is
    # shown as it is and differs; with no passes the frame is the
    # background.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(30, 40, 50))
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, 1.5)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var camera = a_camera()
    var direct = renderer.render(scene, assets, camera)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(output_pass())
    var composed = composer.render(renderer, scene, assets, camera)
    assert_equal(count_differences(direct, composed), 0)
    composer.remove_pass(1)
    var raw = composer.render(renderer, scene, assets, camera)
    assert_true(count_differences(direct, raw) > 0, "the curve did nothing")
    renderer.set_tone_mapping(NO_TONE_MAPPING)
    var plain = renderer.render(scene, assets, camera)
    assert_equal(count_differences(plain, raw), 0)
    var empty = EffectComposer()
    var cleared = empty.render(renderer, scene, assets, camera)
    assert_true(same(cleared.get_pixel(0, 0), Color(30, 40, 50)))
    assert_true(
        same(cleared.get_pixel(WIDTH // 2, HEIGHT // 2), Color(30, 40, 50))
    )


def test_a_render_pass_antialiases_when_the_renderer_does() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    renderer.set_antialias(True)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var camera = a_camera()
    var direct = renderer.render(scene, assets, camera)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    var composed = composer.render(renderer, scene, assets, camera)
    assert_equal(count_differences(direct, composed), 0)
    renderer.set_antialias(False)
    var aliased = renderer.render(scene, assets, camera)
    assert_true(count_differences(aliased, composed) > 0, "no antialias")


def test_a_disabled_pass_is_skipped_and_a_changed_one_is_checked() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var camera = a_camera()
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(copy_pass(0.5))
    var halved = composer.render(renderer, scene, assets, camera)
    # The copy scales the whole texel, alpha included, as three.js's
    # `CopyShader` does: the resolved pixel is white at half coverage,
    # which shows as half gray over black.
    assert_equal(halved.get_pixel(WIDTH // 2, HEIGHT // 2).r, UInt8(255))
    assert_equal(halved.get_pixel(WIDTH // 2, HEIGHT // 2).a, UInt8(128))
    composer.passes[1].enabled = False
    var whole = composer.render(renderer, scene, assets, camera)
    assert_equal(whole.get_pixel(WIDTH // 2, HEIGHT // 2).a, UInt8(255))
    composer.passes[1].enabled = True
    composer.passes[1].strength = -1
    with assert_raises():
        _ = composer.render(renderer, scene, assets, camera)
    composer.passes[1].strength = 0.5
    composer.passes[1].kind = PassKind(35)
    with assert_raises():
        _ = composer.render(renderer, scene, assets, camera)
    with assert_raises():
        _ = composer.render(renderer, scene, assets, camera, delta_time=-1)
    with assert_raises():
        _ = composer.render(
            renderer, scene, assets, camera, delta_time=nan[DType.float32]()
        )


def test_every_kind_runs_in_the_composer_and_the_film_keeps_time() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    renderer.set_tone_mapping(REINHARD_TONE_MAPPING)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var camera = a_camera()
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(bloom_pass(0.5, 0.3, 0.2))
    composer.add_pass(blur_pass(1.0))
    composer.add_pass(film_pass(0.2))
    composer.add_pass(dot_screen_pass())
    composer.add_pass(sepia_pass(0.5))
    composer.add_pass(vignette_pass())
    composer.add_pass(luminosity_pass())
    composer.add_pass(afterimage_pass(0.9))
    composer.add_pass(output_pass())
    var first = composer.render(renderer, scene, assets, camera, 0.5)
    assert_almost_equal(composer.passes[3].time, Float32(0.5), atol=TOLERANCE)
    var second = composer.render(renderer, scene, assets, camera, 0.25)
    assert_almost_equal(composer.passes[3].time, Float32(0.75), atol=TOLERANCE)
    assert_true(count_differences(first, second) > 0, "the grain held still")
    # The gray passes leave every pixel gray.
    var pixel = second.get_pixel(WIDTH // 2, HEIGHT // 2)
    assert_equal(pixel.r, pixel.g)
    assert_equal(pixel.g, pixel.b)
    # The afterimage has a memory, which `reset` clears.
    assert_equal(len(composer.memories[8]), WIDTH * HEIGHT)
    composer.reset()
    assert_equal(len(composer.memories[8]), 0)
    var none = EffectComposer()
    none.reset()
    assert_equal(none.pass_count(), 0)
    # `passes` is an open list, so a pass can arrive without `add_pass`.
    # Its memory is made when the frame runs, rather than read past the
    # end of the memories.
    var open = EffectComposer()
    open.passes.append(render_pass())
    open.passes.append(afterimage_pass(0.9))
    _ = open.render(renderer, scene, assets, camera)
    assert_equal(len(open.memories), 2)
    assert_equal(len(open.accumulations), 2)
    assert_equal(len(open.memories[1]), WIDTH * HEIGHT)
    # A pass popped from the list takes its memory with it.
    _ = open.passes.pop()
    _ = open.render(renderer, scene, assets, camera)
    assert_equal(len(open.memories), 1)
    assert_equal(len(open.accumulations), 1)
    # A frame of data is not tone mapped by the output pass but is
    # grained like anything else.
    var shown = assets.materials.add(normal_material())
    scene.meshes[0].material = shown
    var plain = EffectComposer()
    plain.add_pass(render_pass())
    plain.add_pass(output_pass())
    var normals = plain.render(renderer, scene, assets, camera)
    assert_true(
        same(normals.get_pixel(WIDTH // 2, HEIGHT // 2), Color(128, 128, 255))
    )


def test_a_view_of_floats_reads_as_a_view_of_colors() raises:
    # Four floats a pixel is how a device buffer holds a frame.
    var colors: List[FloatColor] = [
        FloatColor(0.1, 0.2, 0.3, 0.4),
        FloatColor(0.5, 0.6, 0.7, 0.8),
        FloatColor(0.9, 1.0, 1.1, 1.2),
        FloatColor(1.3, 1.4, 1.5, 1.6),
    ]
    var floats = List[Float32]()
    for index in range(len(colors)):
        floats.append(colors[index].r)
        floats.append(colors[index].g)
        floats.append(colors[index].b)
        floats.append(colors[index].a)
    var listed = LightView(colors, 2, 2)
    var device_like = LightView(
        floats=floats.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
        width=2,
        height=2,
    )
    assert_true(device_like.at(1, 1) == colors[3])
    var a = listed.sample(0.3, 0.6)
    var b = device_like.sample(0.3, 0.6)
    assert_true(a == b)
    assert_true(listed.tap(-3, 9) == colors[2])
    _ = floats^
    _ = colors^


def test_a_clear_mask_step_run_alone_changes_nothing() raises:
    # `render` turns the mask off itself; the step has nothing to draw.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var composer = EffectComposer()
    composer.add_pass(clear_mask_pass())
    var frame = flat(WIDTH, HEIGHT, FloatColor(0.2, 0.4, 0.6, 1))
    composer.run_step(0, frame, renderer, scene, assets, a_camera(), 0.0)
    assert_almost_equal(straight(frame, 3, 3).g, Float32(0.4), atol=TOLERANCE)


def test_a_step_run_alone_fits_the_memories_and_checks_its_index() raises:
    # An afterimage appended to the open list has no memory until the
    # step fits them, as `render` does. An index past the passes, or
    # before them, is refused.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var composer = EffectComposer()
    composer.passes.append(afterimage_pass(0.5))
    var frame = flat(WIDTH, HEIGHT, FloatColor(0.2, 0.4, 0.6, 1))
    composer.run_step(0, frame, renderer, scene, assets, a_camera(), 0.0)
    assert_equal(len(composer.memories), 1)
    assert_equal(len(composer.memories[0]), WIDTH * HEIGHT)
    with assert_raises(contains="one of its passes"):
        composer.run_step(1, frame, renderer, scene, assets, a_camera(), 0.0)
    with assert_raises(contains="one of its passes"):
        composer.run_step(-1, frame, renderer, scene, assets, a_camera(), 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
