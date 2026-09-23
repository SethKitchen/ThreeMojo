# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `postprocessing.effects`: the bokeh, the glitch, the halftone,
the mask, the clear and the texture against worked-out answers, and all
seven in the composer."""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.layers import Layers
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from materials.material import Material
from math.utils import SeededRandom
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    BOKEH,
    CLEAR,
    CLEAR_MASK,
    GLITCH,
    HALFTONE,
    MASK,
    RENDER,
    TEXTURE,
    EffectComposer,
    Pass,
    PassKind,
    bokeh_pass,
    check_pass,
    clear_mask_pass,
    clear_pass,
    glitch_pass,
    halftone_pass,
    mask_pass,
    render_pass,
    texture_pass,
)
from postprocessing.effects import (
    BOKEH_TAPS,
    GLITCH_BAND,
    HALFTONE_ADD,
    HALFTONE_DARKER,
    HALFTONE_DOT,
    HALFTONE_ELLIPSE,
    HALFTONE_LIGHTER,
    HALFTONE_LINE,
    HALFTONE_LINEAR,
    HALFTONE_MULTIPLY,
    HALFTONE_SQUARE,
    SQRT2_HALF_MINUS_ONE,
    SQRT2_MINUS_ONE,
    BokehSettings,
    FrameCopy,
    GlitchSettings,
    GlitchUniforms,
    HalftoneBlending,
    HalftoneSettings,
    HalftoneShape,
    MaskSettings,
    bokeh_blur,
    bokeh_light,
    bokeh_taps,
    check_bokeh,
    check_glitch,
    check_halftone,
    clear_light,
    dot_radius_distance,
    glitch_heightmap,
    glitch_light,
    glitch_uniforms,
    halftone_blend,
    halftone_light,
    halftone_sample,
    inside_mask,
    keep_outside_mask,
    mask_stencil,
    reference_cell,
    sine_hash,
    texture_light,
)
from postprocessing.screen_space import DepthView
from render.framebuffer import Color, FloatColor
from render.target import RenderTarget
from render.texture import data_texture
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer
from std.math import cos, floor, inf, nan, pi, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, RADIAN

comptime WIDTH = 16
comptime HEIGHT = 12
comptime BLACK = Color(0, 0, 0)
comptime TOLERANCE = Float64(1e-4)


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def flat(width: Int, height: Int, color: FloatColor) raises -> RenderTarget:
    """Return a frame every pixel of which holds `color`, as stored."""
    var frame = RenderTarget(width, height, BLACK)
    for slot in range(width * height):
        frame.colors[slot] = color
    return frame^


def rows(width: Int, height: Int) raises -> RenderTarget:
    """Return a frame whose rows are grays from zero at the top, each row
    a twentieth brighter than the one above."""
    var frame = RenderTarget(width, height, BLACK)
    for y in range(height):
        for x in range(width):
            var value = Float32(y) / 20
            frame.colors[y * width + x] = FloatColor(value, value, value, 1)
    return frame^


def columns(width: Int, height: Int) raises -> RenderTarget:
    """Return a frame whose columns are grays from zero at the left, each
    column a twentieth brighter than the one before."""
    var frame = RenderTarget(width, height, BLACK)
    for y in range(height):
        for x in range(width):
            var value = Float32(x) / 20
            frame.colors[y * width + x] = FloatColor(value, value, value, 1)
    return frame^


def a_view(width: Int, height: Int, depth: List[Float32]) raises -> DepthView:
    """Return a hand-built depth through a camera from 0.1 to 10 meters."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(width) / Float32(height),
        meters(0.1),
        meters(10.0),
    )
    return DepthView(
        depth,
        width,
        height,
        camera.projection_matrix(),
        meters(0.1),
        meters(10.0),
    )


def window_depth_of(distance: Float32) -> Float32:
    """Return the window depth of a point `distance` in front of the
    0.1-to-10-meter camera: three.js's `viewZToPerspectiveDepth`."""
    var near = Float32(0.1)
    var far = Float32(10.0)
    var z = -distance
    return ((near + z) * far) / ((far - near) * z)


def ndc_of(distance: Float32) -> Float32:
    """Return the NDC depth of a point `distance` in front of the camera."""
    return window_depth_of(distance) * 2 - 1


def still_frame(a: RenderTarget, b: RenderTarget) -> Bool:
    """Return True if two frames hold the same light."""
    for slot in range(len(a.colors)):
        if a.colors[slot] != b.colors[slot]:
            return False
    return True


# --- the kinds and the builders ----------------------------------------------


def test_the_seven_new_kinds_and_their_builders() raises:
    assert_true(BOKEH.is_valid())
    assert_true(GLITCH.is_valid())
    assert_true(HALFTONE.is_valid())
    assert_true(MASK.is_valid())
    assert_true(CLEAR_MASK.is_valid())
    assert_true(CLEAR.is_valid())
    assert_true(TEXTURE.is_valid())
    assert_false(PassKind(26).is_valid())
    var bokeh = bokeh_pass()
    assert_equal(bokeh.kind, BOKEH)
    assert_equal(bokeh.bokeh.focus.value, Float32(1))
    assert_almost_equal(bokeh.bokeh.aperture, Float32(0.025))
    assert_equal(bokeh.bokeh.max_blur, Float32(1))
    var custom = bokeh_pass(meters(3), 0.5, 0.02)
    assert_equal(custom.bokeh.focus.value, Float32(3))
    assert_equal(custom.bokeh.aperture, Float32(0.5))
    assert_almost_equal(custom.bokeh.max_blur, Float32(0.02))
    var glitch = glitch_pass()
    assert_equal(glitch.kind, GLITCH)
    assert_equal(glitch.glitch.size, 64)
    assert_equal(glitch.glitch.seed, 0)
    assert_false(glitch.glitch.go_wild)
    assert_equal(glitch.glitch.frame, 0)
    assert_equal(glitch_pass(8, 5).glitch.seed, 5)
    var halftone = halftone_pass()
    assert_equal(halftone.kind, HALFTONE)
    assert_equal(halftone.halftone.radius, Float32(4))
    assert_equal(halftone.halftone.shape, HALFTONE_DOT)
    assert_equal(halftone.halftone.blending_mode, HALFTONE_LINEAR)
    assert_almost_equal(halftone.halftone.rotate_g.value, Float32(pi / 6))
    assert_equal(halftone_pass(2).halftone.radius, Float32(2))
    var mask = mask_pass(Layers(UInt32(2)), True)
    assert_equal(mask.kind, MASK)
    assert_equal(mask.mask.selection, Layers(UInt32(2)))
    assert_true(mask.mask.inverse)
    assert_false(mask_pass(Layers()).mask.inverse)
    assert_equal(MaskSettings().selection.mask, UInt32(0))
    assert_equal(clear_mask_pass().kind, CLEAR_MASK)
    var clear = clear_pass()
    assert_equal(clear.kind, CLEAR)
    assert_equal(clear.clear_color.a, UInt8(0))
    assert_equal(clear_pass(Color(1, 2, 3, 4)).clear_color.b, UInt8(3))
    var texture = texture_pass(TextureId(0), 0.5)
    assert_equal(texture.kind, TEXTURE)
    assert_equal(texture.texture, TextureId(0))
    assert_equal(texture.strength, Float32(0.5))


def test_the_builders_refuse_what_no_pass_could_run() raises:
    with assert_raises(contains="bokeh setting must not be negative"):
        _ = bokeh_pass(meters(-1))
    with assert_raises(contains="glitch map"):
        _ = glitch_pass(0)
    with assert_raises(contains="halftone radius"):
        _ = halftone_pass(0)
    with assert_raises(contains="must name a texture"):
        _ = texture_pass(NO_TEXTURE)
    with assert_raises(contains="must not be negative"):
        _ = texture_pass(TextureId(0), -1)
    # A texture pass is checked for its texture; no other kind is.
    check_pass(Pass(RENDER))
    with assert_raises(contains="must name a texture"):
        check_pass(Pass(TEXTURE))


# --- bokeh -------------------------------------------------------------------


def test_bokeh_settings_no_pass_could_run_are_refused() raises:
    check_bokeh(BokehSettings())
    var bad = BokehSettings()
    bad.focus = meters(nan[DType.float32]())
    with assert_raises(contains="finite"):
        check_bokeh(bad)
    bad = BokehSettings()
    bad.aperture = inf[DType.float32]()
    with assert_raises(contains="finite"):
        check_bokeh(bad)
    bad = BokehSettings()
    bad.max_blur = nan[DType.float32]()
    with assert_raises(contains="finite"):
        check_bokeh(bad)
    bad = BokehSettings()
    bad.focus = meters(-1)
    with assert_raises(contains="negative"):
        check_bokeh(bad)
    bad = BokehSettings()
    bad.aperture = -1
    with assert_raises(contains="negative"):
        check_bokeh(bad)
    bad = BokehSettings()
    bad.max_blur = -1
    with assert_raises(contains="negative"):
        check_bokeh(bad)


def test_the_bokeh_taps_are_three_js_s_41() raises:
    var taps = bokeh_taps()
    assert_equal(len(taps), BOKEH_TAPS)
    assert_equal(taps[0].x, Float32(0))
    assert_equal(taps[0].y, Float32(0))
    # The first of the full ring, the first at nine tenths, at seven
    # tenths and at four tenths.
    assert_almost_equal(taps[1].y, Float32(0.4))
    assert_almost_equal(taps[17].x, Float32(0.135))
    assert_almost_equal(taps[17].y, Float32(0.333))
    assert_almost_equal(taps[25].x, Float32(0.203))
    assert_almost_equal(taps[33].x, Float32(0.116))
    assert_almost_equal(taps[40].y, Float32(0.16))


def test_the_bokeh_blur_grows_away_from_the_focus_and_is_clamped() raises:
    var view = a_view(2, 2, List[Float32](length=4, fill=0))
    var settings = BokehSettings()
    settings.focus = meters(2)
    settings.aperture = 0.1
    settings.max_blur = 0.05
    # At the focus there is no blur.
    assert_almost_equal(
        bokeh_blur(view, window_depth_of(2), settings),
        Float32(0),
        atol=TOLERANCE,
    )
    # Two and a tenth meters is a tenth past it: minus a hundredth.
    assert_almost_equal(
        bokeh_blur(view, window_depth_of(2.1), settings),
        Float32(-0.01),
        atol=TOLERANCE,
    )
    # Far behind and far in front, the blur is held at the largest.
    assert_almost_equal(bokeh_blur(view, 1, settings), Float32(-0.05))
    assert_almost_equal(
        bokeh_blur(view, window_depth_of(0.2), settings), Float32(0.05)
    )


def test_bokeh_leaves_what_is_in_focus_and_blurs_what_is_not() raises:
    var width = 8
    var height = 4
    # The left half at two meters, in focus; the right half at nothing.
    var depth = List[Float32]()
    for _y in range(height):
        for x in range(width):
            depth.append(ndc_of(2) if x < 4 else Float32(1))
    var view = a_view(width, height, depth)
    var frame = columns(width, height)
    frame.colors[3] = FloatColor(0.5, 0.5, 0.5, 0.5)
    # A bright pixel beside an out-of-focus one, which a gradient's even
    # taps would otherwise average back to itself.
    frame.colors[7] = FloatColor(1, 1, 1, 1)
    frame.data[0] = True
    var before = frame.colors.copy()
    var settings = BokehSettings()
    settings.focus = meters(2)
    settings.aperture = 0.1
    settings.max_blur = 0.2
    bokeh_light(frame, view, settings)
    # A pixel in focus reads itself 41 times, and the result is opaque
    # light.
    assert_almost_equal(frame.colors[1].r, before[1].r, atol=TOLERANCE)
    assert_equal(frame.colors[1].a, Float32(1))
    assert_almost_equal(frame.colors[3].r, Float32(0.5), atol=TOLERANCE)
    assert_equal(frame.colors[3].a, Float32(1))
    assert_false(frame.data[0])
    # A pixel out of focus is blurred toward its neighbors.
    assert_true(abs(frame.colors[6].r - before[6].r) > 0.001)


# --- glitch ------------------------------------------------------------------


def test_glitch_settings_no_pass_could_run_are_refused() raises:
    check_glitch(GlitchSettings())
    var bad = GlitchSettings(0, 0)
    with assert_raises(contains="glitch map"):
        check_glitch(bad)
    bad = GlitchSettings(1, 0)
    bad.size = 4097
    with assert_raises(contains="glitch map"):
        check_glitch(bad)
    bad = GlitchSettings(1, 0)
    bad.state = -1
    with assert_raises(contains="32 bits"):
        check_glitch(bad)
    bad.state = 0x100000000
    with assert_raises(contains="32 bits"):
        check_glitch(bad)
    bad = GlitchSettings(1, 0)
    bad.frame = -1
    with assert_raises(contains="frame count"):
        check_glitch(bad)
    bad = GlitchSettings(1, 0)
    bad.trigger = 0
    with assert_raises(contains="trigger"):
        check_glitch(bad)


def test_the_glitch_starts_as_three_js_s_constructor_draws() raises:
    # The map first, then the trigger, from one generator.
    var settings = GlitchSettings(2, 7)
    var random = SeededRandom(7)
    var map = glitch_heightmap(2, 7)
    assert_equal(len(map), 4)
    for index in range(4):
        assert_equal(map[index], Float32(random.next()))
    assert_equal(settings.trigger, random.int_in(120, 240))
    assert_equal(settings.state, Int(random.state))
    assert_true(settings.trigger >= 120 and settings.trigger <= 240)
    assert_equal(len(glitch_heightmap(0, 7)), 0)


def test_the_glitch_draws_wild_then_small_then_bypasses() raises:
    var settings = GlitchSettings(1, 3)
    settings.trigger = 10
    var random = SeededRandom(0)
    random.state = UInt32(settings.state)
    # Frame zero is wild, in three.js's order of draws.
    var wild = glitch_uniforms(settings)
    assert_false(wild.bypass)
    assert_almost_equal(wild.seed, Float32(random.next()))
    assert_almost_equal(wild.amount, Float32(random.next()) / 30)
    assert_almost_equal(
        wild.angle.value, random.float_in(-Float32(pi), Float32(pi))
    )
    assert_almost_equal(wild.seed_x, random.float_in(-1, 1))
    assert_almost_equal(wild.seed_y, random.float_in(-1, 1))
    assert_almost_equal(wild.distortion_x, random.float_in(0, 1))
    assert_almost_equal(wild.distortion_y, random.float_in(0, 1))
    var trigger = random.int_in(120, 240)
    assert_equal(settings.trigger, trigger)
    assert_equal(settings.frame, 1)
    assert_equal(settings.state, Int(random.state))
    # Frame one is in the first fifth: a small glitch.
    var small = glitch_uniforms(settings)
    assert_false(small.bypass)
    _ = random.next()
    assert_almost_equal(small.amount, Float32(random.next()) / 90)
    _ = random.float_in(-Float32(pi), Float32(pi))
    assert_almost_equal(small.distortion_x, random.float_in(0, 1))
    assert_almost_equal(small.distortion_y, random.float_in(0, 1))
    assert_almost_equal(small.seed_x, random.float_in(-0.3, 0.3))
    assert_almost_equal(small.seed_y, random.float_in(-0.3, 0.3))
    assert_equal(settings.trigger, trigger)
    assert_equal(settings.frame, 2)
    # Past the first fifth the frame is bypassed.
    settings.frame = trigger - 1
    assert_true(glitch_uniforms(settings).bypass)
    assert_equal(settings.frame, trigger)
    # Gone wild, every frame is wild.
    settings.frame = 5
    settings.go_wild = True
    assert_false(glitch_uniforms(settings).bypass)
    assert_equal(settings.frame, 1)


def test_the_sine_hash_is_the_shaders_own() raises:
    assert_equal(sine_hash(0, 0), Float32(0))
    var s = sin(Float32(1) * 12.9898 + Float32(2) * 78.233) * 43758.5453
    assert_equal(sine_hash(1, 2), s - floor(s))


def still_uniforms() -> GlitchUniforms:
    """Return uniforms that shift nothing, add no snow and tear nothing."""
    var uniforms = GlitchUniforms()
    uniforms.amount = 0
    uniforms.seed = 1
    uniforms.seed_x = 0
    uniforms.seed_y = 0
    # Both bands are far above every coordinate.
    uniforms.distortion_x = 5
    uniforms.distortion_y = 5
    return uniforms


def test_a_bypassed_or_still_glitch_leaves_the_frame() raises:
    var frame = rows(4, 20)
    var before = frame.colors.copy()
    var bypassed = GlitchUniforms()
    bypassed.bypass = True
    var zeros = List[Float32](length=1, fill=0)
    glitch_light(frame, zeros, 1, bypassed)
    assert_true(frame.colors == before)
    glitch_light(frame, zeros, 1, still_uniforms())
    for slot in range(len(before)):
        assert_almost_equal(frame.colors[slot].r, before[slot].r, atol=1e-6)


def test_the_glitch_tears_a_row() raises:
    var zeros = List[Float32](length=1, fill=0)
    # The band is 0.45 to 0.55, rows 9 and 10 of 20. A seed_x of zero
    # moves them to distortion_y: 0.025, the bottom row.
    var frame = rows(4, 20)
    var uniforms = still_uniforms()
    uniforms.distortion_x = 0.5
    uniforms.distortion_y = 0.025
    glitch_light(frame, zeros, 1, uniforms)
    assert_almost_equal(frame.colors[9 * 4].r, Float32(19) / 20, atol=1e-5)
    assert_almost_equal(frame.colors[10 * 4].r, Float32(19) / 20, atol=1e-5)
    assert_almost_equal(frame.colors[8 * 4].r, Float32(8) / 20, atol=1e-5)
    assert_almost_equal(frame.colors[11 * 4].r, Float32(11) / 20, atol=1e-5)
    # A positive seed_x flips them: row 9 reads 1 - (0.525 + 0.3), row 16.
    frame = rows(4, 20)
    uniforms.seed_x = 0.5
    uniforms.distortion_y = 0.3
    glitch_light(frame, zeros, 1, uniforms)
    assert_almost_equal(frame.colors[9 * 4].r, Float32(16) / 20, atol=1e-5)
    assert_almost_equal(frame.colors[10 * 4].r, Float32(15) / 20, atol=1e-5)


def test_the_glitch_tears_a_column() raises:
    var zeros = List[Float32](length=1, fill=0)
    # The band is 0.45 to 0.55, columns 9 and 10 of 20. A positive seed_y
    # moves them to distortion_x.
    var frame = columns(20, 4)
    var uniforms = still_uniforms()
    uniforms.distortion_y = 0.5
    uniforms.distortion_x = 0.025
    uniforms.seed_y = 0.5
    glitch_light(frame, zeros, 1, uniforms)
    # distortion_x of 0.025 is the center of column zero.
    assert_almost_equal(frame.colors[9].r, Float32(0), atol=1e-5)
    assert_almost_equal(frame.colors[10].r, Float32(0), atol=1e-5)
    assert_almost_equal(frame.colors[8].r, Float32(8) / 20, atol=1e-5)
    # A seed_y of zero flips them: column 9 reads 1 - (0.475 + 0.3).
    frame = columns(20, 4)
    uniforms.seed_y = 0
    uniforms.distortion_x = 0.3
    glitch_light(frame, zeros, 1, uniforms)
    assert_almost_equal(frame.colors[9].r, Float32(4) / 20, atol=1e-5)
    assert_almost_equal(frame.colors[10].r, Float32(3) / 20, atol=1e-5)


def test_the_glitch_pushes_by_the_map_shifts_and_snows() raises:
    # A map of one: every pixel is pushed by seed_y * seed / 5 up.
    var ones = List[Float32](length=4, fill=1)
    var frame = rows(4, 20)
    var uniforms = still_uniforms()
    uniforms.seed_y = 0.5
    # 0.5 * 1 / 5 = 0.1 up: two rows.
    glitch_light(frame, ones, 2, uniforms)
    assert_almost_equal(frame.colors[10 * 4].r, Float32(8) / 20, atol=1e-5)
    # A shift to the right reads red from the right and blue from the
    # left, and the snow adds to every channel.
    frame = columns(20, 4)
    var shift = still_uniforms()
    shift.amount = 0.1
    shift.seed = 0.5
    var zeros = List[Float32](length=1, fill=0)
    glitch_light(frame, zeros, 1, shift)
    var x = 10
    var y = 1
    var xs = floor((Float32(x) + 0.5) / 0.5)
    var ys = floor((Float32(4 - 1 - y) + 0.5) / 0.5)
    var snow = 200 * Float32(0.1) * sine_hash(xs * 0.5, ys * 0.5 * 50) * 0.2
    var here = frame.colors[y * 20 + x]
    assert_almost_equal(here.r, Float32(12) / 20 + snow, atol=1e-4)
    assert_almost_equal(here.g, Float32(10) / 20 + snow, atol=1e-4)
    assert_almost_equal(here.b, Float32(8) / 20 + snow, atol=1e-4)
    assert_almost_equal(here.a, 1 + snow, atol=1e-4)


# --- halftone ----------------------------------------------------------------


def test_the_halftone_shapes_and_modes_are_types() raises:
    assert_true(HALFTONE_DOT.is_valid())
    assert_true(HALFTONE_ELLIPSE.is_valid())
    assert_true(HALFTONE_LINE.is_valid())
    assert_true(HALFTONE_SQUARE.is_valid())
    assert_false(HalftoneShape(0).is_valid())
    assert_false(HalftoneShape(5).is_valid())
    assert_true(HALFTONE_LINEAR.is_valid())
    assert_true(HALFTONE_MULTIPLY.is_valid())
    assert_true(HALFTONE_ADD.is_valid())
    assert_true(HALFTONE_LIGHTER.is_valid())
    assert_true(HALFTONE_DARKER.is_valid())
    assert_false(HalftoneBlending(0).is_valid())
    assert_false(HalftoneBlending(6).is_valid())


def test_halftone_settings_no_pass_could_run_are_refused() raises:
    check_halftone(HalftoneSettings())
    var bad = HalftoneSettings()
    bad.shape = HalftoneShape(5)
    with assert_raises(contains="shape"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.blending_mode = HalftoneBlending(6)
    with assert_raises(contains="blending mode"):
        check_halftone(bad)
    var nan32 = nan[DType.float32]()
    bad = HalftoneSettings()
    bad.radius = nan32
    with assert_raises(contains="finite"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.rotate_r = Angle(nan32, RADIAN)
    with assert_raises(contains="finite"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.rotate_g = Angle(nan32, RADIAN)
    with assert_raises(contains="finite"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.rotate_b = Angle(nan32, RADIAN)
    with assert_raises(contains="finite"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.scatter = nan32
    with assert_raises(contains="finite"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.blending = nan32
    with assert_raises(contains="finite"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.radius = 0
    with assert_raises(contains="radius"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.scatter = -1
    with assert_raises(contains="scatter"):
        check_halftone(bad)
    bad = HalftoneSettings()
    bad.blending = -0.1
    with assert_raises(contains="zero to one"):
        check_halftone(bad)
    bad.blending = 1.1
    with assert_raises(contains="zero to one"):
        check_halftone(bad)


def test_the_distance_to_each_dot_shape() raises:
    var origin = Vector2(0, 0)
    var across = Vector2(1, 0)
    # A dot of a full channel is the largest radius: four, less one.
    assert_almost_equal(
        dot_radius_distance(HALFTONE_DOT, 1, origin, across, across, 0, 4),
        Float32(3),
    )
    assert_almost_equal(
        dot_radius_distance(HALFTONE_DOT, 0.5, origin, across, across, 0, 4),
        Float32(0.5**1.125 * 4 - 1),
        atol=TOLERANCE,
    )
    # An ellipse stretches the distance along the grid.
    var stretched = (1 - SQRT2_HALF_MINUS_ONE) + SQRT2_MINUS_ONE
    assert_almost_equal(
        dot_radius_distance(HALFTONE_ELLIPSE, 1, origin, across, across, 0, 4),
        4 - stretched,
        atol=TOLERANCE,
    )
    assert_almost_equal(
        dot_radius_distance(HALFTONE_ELLIPSE, 1, origin, across, origin, 0, 4),
        Float32(4),
    )
    # A line measures along the normal alone.
    assert_almost_equal(
        dot_radius_distance(
            HALFTONE_LINE, 1, origin, across, Vector2(1, 2), 0, 4
        ),
        Float32(3),
        atol=TOLERANCE,
    )
    # A square's reach grows toward its corners.
    assert_almost_equal(
        dot_radius_distance(HALFTONE_SQUARE, 1, origin, across, across, 0, 4),
        Float32(3),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        dot_radius_distance(
            HALFTONE_SQUARE, 1, origin, across, Vector2(0, 1), 0, 4
        ),
        Float32(3),
        atol=TOLERANCE,
    )
    var diagonal = Float32(sqrt(0.5))
    assert_almost_equal(
        dot_radius_distance(
            HALFTONE_SQUARE,
            1,
            origin,
            across,
            Vector2(diagonal, diagonal),
            0,
            4,
        ),
        4 * (2 - diagonal) - 1,
        atol=TOLERANCE,
    )


def test_the_reference_cell_is_the_grid_square_around_a_point() raises:
    # On a grid point the nearest point is the point itself.
    var cell = reference_cell(Vector2(4, 8), 0, 4, 0)
    assert_almost_equal(cell.p1.x, Float32(4), atol=TOLERANCE)
    assert_almost_equal(cell.p1.y, Float32(8), atol=TOLERANCE)
    assert_almost_equal(cell.p2.x, Float32(8), atol=TOLERANCE)
    assert_almost_equal(cell.p2.y, Float32(8), atol=TOLERANCE)
    assert_almost_equal(cell.p3.x, Float32(4), atol=TOLERANCE)
    assert_almost_equal(cell.p3.y, Float32(12), atol=TOLERANCE)
    assert_almost_equal(cell.p4.x, Float32(8), atol=TOLERANCE)
    assert_almost_equal(cell.p4.y, Float32(12), atol=TOLERANCE)
    # Just past a half step, the nearest point is the next one.
    var past = reference_cell(Vector2(6.5, 8), 0, 4, 0)
    assert_almost_equal(past.p1.x, Float32(8), atol=TOLERANCE)
    assert_almost_equal(past.p2.x, Float32(4), atol=TOLERANCE)
    # Below and left of the origin the grid runs the other way.
    var behind = reference_cell(Vector2(-4.5, -8.5), 0, 4, 0)
    assert_almost_equal(behind.p1.x, Float32(-4), atol=TOLERANCE)
    assert_almost_equal(behind.p1.y, Float32(-8), atol=TOLERANCE)
    # A scatter of one moves the nearest point a quarter step.
    var scattered = reference_cell(Vector2(4, 8), 0, 4, 1)
    var dx = scattered.p1.x - 4
    var dy = scattered.p1.y - 8
    assert_almost_equal(sqrt(dx * dx + dy * dy), Float32(1), atol=TOLERANCE)


def test_a_halftone_sample_of_one_color_is_that_color() raises:
    var colors = List[FloatColor](length=16, fill=FloatColor(0.2, 0.4, 0.6, 1))
    var here = halftone_sample(colors, 4, 4, Vector2(2, 2), 4)
    assert_almost_equal(here.r, Float32(0.2), atol=TOLERANCE)
    assert_almost_equal(here.b, Float32(0.6), atol=TOLERANCE)
    assert_almost_equal(here.a, Float32(1), atol=TOLERANCE)


def test_each_halftone_blending_mode() raises:
    assert_almost_equal(halftone_blend(1, 0.5, 1, HALFTONE_LINEAR), Float32(1))
    assert_almost_equal(
        halftone_blend(1, 0.5, 0, HALFTONE_LINEAR), Float32(0.5)
    )
    assert_almost_equal(halftone_blend(0.8, 0.5, 1, HALFTONE_ADD), Float32(1))
    assert_almost_equal(
        halftone_blend(0.8, 0.5, 1, HALFTONE_MULTIPLY), Float32(0.4)
    )
    assert_almost_equal(
        halftone_blend(0.2, 0.5, 1, HALFTONE_LIGHTER), Float32(0.5)
    )
    assert_almost_equal(
        halftone_blend(0.2, 0.5, 1, HALFTONE_DARKER), Float32(0.2)
    )
    # At zero every mode but the linear one shows the halftone alone.
    assert_almost_equal(
        halftone_blend(0.2, 0.5, 0, HALFTONE_DARKER), Float32(0.2)
    )


def test_a_halftone_keeps_white_and_black_and_grays_if_asked() raises:
    var settings = HalftoneSettings()
    var white = flat(8, 8, FloatColor(1, 1, 1, 1))
    white.data[0] = True
    halftone_light(white, settings)
    for slot in range(64):
        assert_almost_equal(white.colors[slot].r, Float32(1), atol=TOLERANCE)
        assert_equal(white.colors[slot].a, Float32(1))
    assert_false(white.data[0])
    var black = flat(8, 8, FloatColor(0, 0, 0, 0))
    halftone_light(black, settings)
    assert_equal(black.colors[9].g, Float32(0))
    assert_equal(black.colors[9].a, Float32(1))
    # Red alone, grayed, is a third of the way to white.
    var red = flat(8, 8, FloatColor(1, 0, 0, 1))
    settings.grayscale = True
    halftone_light(red, settings)
    assert_almost_equal(red.colors[20].g, Float32(1) / 3, atol=TOLERANCE)
    assert_almost_equal(red.colors[20].b, red.colors[20].r)


def test_a_small_scattered_halftone_varies_and_a_disabled_one_is_still() raises:
    var settings = HalftoneSettings()
    settings.radius = 2
    settings.scatter = 0.5
    settings.shape = HALFTONE_SQUARE
    var frame = columns(8, 8)
    halftone_light(frame, settings)
    var low = Float32(1)
    var high = Float32(0)
    for slot in range(64):
        low = min(low, frame.colors[slot].r)
        high = max(high, frame.colors[slot].r)
    assert_true(low >= 0 and high <= 1)
    assert_true(high > low)
    settings.disable = True
    var still = columns(8, 8)
    halftone_light(still, settings)
    assert_true(still_frame(still, columns(8, 8)))


# --- mask, clear and texture -------------------------------------------------


def test_the_mask_writes_one_where_covered_or_the_inverse() raises:
    var frame = flat(2, 1, FloatColor(0.5, 0.5, 0.5, 1))
    var depth: List[Float32] = [0.5, inf[DType.float32]()]
    mask_stencil(frame, depth, False)
    assert_equal(frame.stencil_at(0, 0), 1)
    assert_equal(frame.stencil_at(1, 0), 0)
    mask_stencil(frame, depth, True)
    assert_equal(frame.stencil_at(0, 0), 0)
    assert_equal(frame.stencil_at(1, 0), 1)
    # The light is left alone.
    assert_equal(frame.colors[0].r, Float32(0.5))
    assert_true(inside_mask(1))
    assert_false(inside_mask(0))
    assert_false(inside_mask(2))


def test_a_pass_inside_a_mask_changes_only_the_masked_pixels() raises:
    var frame = flat(2, 1, FloatColor(0.5, 0.5, 0.5, 1))
    frame.stencil[0] = 1
    assert_equal(len(FrameCopy().colors), 0)
    var saved = FrameCopy(frame)
    assert_equal(len(saved.stencil), 2)
    # A pass that changes everything, the stencil included.
    clear_light(frame, Color(255, 255, 255))
    frame.data[1] = True
    keep_outside_mask(frame, saved)
    assert_almost_equal(frame.colors[0].r, Float32(1), atol=TOLERANCE)
    assert_equal(frame.colors[1].r, Float32(0.5))
    assert_false(frame.data[1])
    assert_equal(frame.stencil_at(0, 0), 1)
    assert_equal(frame.stencil_at(1, 0), 0)


def test_the_clear_resets_light_depth_data_and_stencil() raises:
    var frame = flat(2, 2, FloatColor(0.5, 0.5, 0.5, 1))
    frame.depth[0] = 0.25
    frame.data[1] = True
    frame.stencil[2] = 7
    clear_light(frame, Color(255, 0, 0, 51))
    var expected = FloatColor(srgb=Color(255, 0, 0, 51)).premultiplied()
    for slot in range(4):
        assert_true(frame.colors[slot] == expected)
        assert_equal(frame.depth[slot], inf[DType.float32]())
        assert_false(frame.data[slot])
        assert_equal(Int(frame.stencil[slot]), 0)
    assert_almost_equal(frame.colors[0].a, Float32(0.2), atol=TOLERANCE)


def test_the_texture_is_added_by_its_opacity() raises:
    var texture = data_texture(1, 1, [0.5, 0.25, 0.0, 1.0])
    var frame = flat(2, 2, FloatColor(0.1, 0.1, 0.1, 0))
    frame.data[3] = True
    texture_light(frame, texture, 0.5)
    for slot in range(4):
        assert_almost_equal(frame.colors[slot].r, Float32(0.35), atol=0.01)
        assert_almost_equal(frame.colors[slot].g, Float32(0.225), atol=0.01)
        assert_almost_equal(frame.colors[slot].b, Float32(0.1), atol=0.01)
        assert_almost_equal(frame.colors[slot].a, Float32(0.5), atol=0.01)
    assert_false(frame.data[3])


# --- in the composer ---------------------------------------------------------


def two_sheets(mut assets: Assets) raises -> Scene:
    """Return a white sheet on layer one at the left and one on layer two
    at the right, a meter from the origin, both also on layer zero."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(
        directional_light(Color(255, 255, 255), lamp_node, Float32(pi))
    )
    var sheet = assets.geometries.add(plane(meters(0.8), meters(1.0)))
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    var left = Object3D()
    left.set_position(-0.5, 0, 0)
    left.layers.enable(1)
    scene.add_mesh(Mesh(sheet, paint, scene.add(left^)))
    var right = Object3D()
    right.set_position(0.5, 0, 0)
    right.layers.enable(2)
    scene.add_mesh(Mesh(sheet, paint, scene.add(right^)))
    scene.update()
    return scene^


def a_flat_camera() raises -> OrthographicCamera:
    """Return an orthographic camera two meters wide and one and a half
    tall, looking down minus z from four meters."""
    var camera = OrthographicCamera(
        meters(-1),
        meters(1),
        meters(0.75),
        meters(-0.75),
        meters(0.1),
        meters(10),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_renderer() raises -> Renderer:
    """Return a renderer of the test size on a black background."""
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    return renderer^


def test_masks_let_two_textures_fill_two_sheets() raises:
    # three.js's masking example: clear, then each texture inside its own
    # mask.
    var assets = Assets()
    var scene = two_sheets(assets)
    var red = assets.textures.add(data_texture(1, 1, [1.0, 0.0, 0.0, 1.0]))
    var blue = assets.textures.add(data_texture(1, 1, [0.0, 0.0, 1.0, 1.0]))
    var renderer = a_renderer()
    var camera = a_flat_camera()
    var composer = EffectComposer()
    composer.add_pass(clear_pass())
    composer.add_pass(mask_pass(Layers(UInt32(2))))
    composer.add_pass(texture_pass(red))
    composer.add_pass(clear_mask_pass())
    composer.add_pass(mask_pass(Layers(UInt32(4))))
    composer.add_pass(texture_pass(blue))
    composer.add_pass(clear_mask_pass())
    var image = composer.render(renderer, scene, assets, camera)
    var y = HEIGHT // 2
    # The left sheet is red, the right blue, and between them is clear.
    var left = image.get_pixel(4, y)
    assert_equal(left.r, UInt8(255))
    assert_equal(left.b, UInt8(0))
    var right = image.get_pixel(WIDTH - 5, y)
    assert_equal(right.b, UInt8(255))
    assert_equal(right.r, UInt8(0))
    assert_equal(image.get_pixel(WIDTH // 2, y).a, UInt8(0))
    assert_equal(image.get_pixel(4, 0).a, UInt8(0))
    # Turned inside out, the red fills everything but the left sheet.
    composer.passes[1].mask.inverse = True
    var inverse = composer.render(renderer, scene, assets, camera)
    assert_equal(inverse.get_pixel(4, y).r, UInt8(0))
    assert_equal(inverse.get_pixel(WIDTH // 2, y).r, UInt8(255))
    # A disabled mask pass masks nothing.
    composer.passes[1].enabled = False
    var unmasked = composer.render(renderer, scene, assets, camera)
    assert_equal(unmasked.get_pixel(4, y).r, UInt8(255))
    assert_equal(unmasked.get_pixel(WIDTH // 2, y).r, UInt8(255))


def test_the_effects_run_in_the_composer() raises:
    var assets = Assets()
    var scene = two_sheets(assets)
    var renderer = a_renderer()
    var camera = a_flat_camera()
    var plain = EffectComposer()
    plain.add_pass(render_pass())
    var base = plain.render(renderer, scene, assets, camera)

    # The sheets are four meters away; a focus of one blurs their edges.
    var bokeh = EffectComposer()
    bokeh.add_pass(render_pass())
    bokeh.add_pass(bokeh_pass(meters(1), 0.01, 0.05))
    var blurred = bokeh.render(renderer, scene, assets, camera)
    var changed = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if blurred.get_pixel(x, y).r != base.get_pixel(x, y).r:
                changed += 1
    assert_true(changed > 0, "The bokeh changed nothing")

    # Two composers with one seed glitch alike, and each frame advances.
    var one = EffectComposer()
    one.add_pass(render_pass())
    one.add_pass(glitch_pass(8, 11))
    var two = EffectComposer()
    two.add_pass(render_pass())
    two.add_pass(glitch_pass(8, 11))
    var first = one.render(renderer, scene, assets, camera)
    var again = two.render(renderer, scene, assets, camera)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(first.get_pixel(x, y).g, again.get_pixel(x, y).g)
    assert_equal(one.passes[1].glitch.frame, 1)
    _ = one.render(renderer, scene, assets, camera)
    assert_equal(one.passes[1].glitch.frame, 2)

    var halftone = EffectComposer()
    halftone.add_pass(render_pass())
    halftone.add_pass(halftone_pass(2))
    var dotted = halftone.render(renderer, scene, assets, camera)
    changed = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if dotted.get_pixel(x, y).r != base.get_pixel(x, y).r:
                changed += 1
    assert_true(changed > 0, "The halftone changed nothing")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
