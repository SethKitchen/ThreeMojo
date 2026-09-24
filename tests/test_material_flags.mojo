# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the material flags a fragment reads: `dithering`,
`toneMapped`, `alphaHash`, `alphaToCoverage` and `premultipliedAlpha`, the
blend constant, and `render.fragment_flags`."""

from materials.material import (
    BACK_SIDE,
    BASIC,
    BLEND,
    DEPTH,
    DOUBLE_SIDE,
    FRONT_SIDE,
    Material,
    OPAQUE,
    Side,
    custom_blending,
)
from math.vector3 import Vector3
from render.blend import CONSTANT_COLOR_FACTOR, ZERO_FACTOR, Rgba
from render.fragment_flags import (
    MIN_HASH_THRESHOLD,
    alpha_covers,
    alpha_hash_threshold,
    coverage_threshold,
    dither,
    fragment_rand,
)
from render.framebuffer import Color, FloatColor
from render.raster_state import REPLACE_STENCIL_OP, RasterState
from render.rasterizer import (
    RasterVertex,
    SHADE_UV,
    check_output_kinds,
    rasterize_line,
    rasterize_point,
    rasterize_shaded,
)
from render.srgb import linear_to_srgb
from render.target import RenderTarget
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime SIZE = 8


def _corner(
    x: Float32,
    y: Float32,
    color: FloatColor,
    state: RasterState,
    blend: Bool = False,
    kind: Bool = True,
) -> RasterVertex:
    """Return a corner of a flat, unlit triangle whose world position runs
    across the screen, so a hashed alpha has a scale to read."""
    var blending = OPAQUE
    if blend:
        blending = BLEND
    var shown = BASIC
    if not kind:
        shown = DEPTH
    return RasterVertex(
        x,
        y,
        0.5,
        1,
        color,
        blend=blending,
        world=Vector3(x * 0.37, y * 0.29, 0.1),
        kind=shown,
        state=state,
    )


def _cover(
    mut target: RenderTarget,
    color: FloatColor,
    state: RasterState,
    blend: Bool = False,
    mode_uv: Bool = False,
) raises:
    """Draw one triangle over the whole target."""
    var a = _corner(-1, -1, color, state, blend)
    var b = _corner(Float32(SIZE * 3), -1, color, state, blend)
    var c = _corner(-1, Float32(SIZE * 3), color, state, blend)
    if mode_uv:
        rasterize_shaded(a, b, c, target, SHADE_UV)
    else:
        rasterize_shaded(a, b, c, target)


def _drawn(target: RenderTarget) raises -> Int:
    """Return how many pixels of the target are not black."""
    var count = 0
    for y in range(SIZE):
        for x in range(SIZE):
            if target.color_at(x, y).r > 0:
                count += 1
    return count


# --- the functions ----------------------------------------------------------


def test_rand_is_three_js_rand() raises:
    for step in range(40):
        var value = fragment_rand(Float32(step) * 3.5, Float32(step) * 1.25)
        assert_true(value >= 0 and value < 1)
    # fract(sin(0) * c) is zero.
    assert_equal(fragment_rand(0, 0), 0)


def test_dithering_moves_the_encoding_by_at_most_half_a_byte() raises:
    var gray = FloatColor(0.2, 0.2, 0.2, 0.75)
    var moved = 0
    for y in range(SIZE):
        for x in range(SIZE):
            var shown = dither(gray, x, y, SIZE)
            assert_equal(shown.a, gray.a)
            var red = linear_to_srgb(shown.r) - linear_to_srgb(gray.r)
            var green = linear_to_srgb(shown.g) - linear_to_srgb(gray.g)
            assert_true(abs(red) <= 0.5 / 255 + 1e-5)
            # Green moves the other way, as three.js shifts it.
            assert_almost_equal(red, -green, atol=1e-5)
            if abs(red) > 1e-4:
                moved += 1
    assert_true(moved > SIZE, "the dither moved almost nothing")


def test_the_hashed_threshold_is_uniform_and_kept_above_zero() raises:
    # Every case of three.js's distribution is reached, and every
    # threshold is inside its clamp.
    var total = Float32(0)
    var low = 0
    var high = 0
    var count = 0
    for step in range(400):
        var at = Vector3(
            Float32(step) * 0.173, Float32(step) * 0.071, Float32(step) * 0.013
        )
        # A scale that moves across the powers of two, so every mix of the
        # two noise levels is used.
        var reach = Float32(0.01) + Float32(step % 23) * 0.0137
        var found = alpha_hash_threshold(
            at, Vector3(reach, 0, 0), Vector3(0, reach * 0.5, 0)
        )
        assert_true(found >= MIN_HASH_THRESHOLD and found <= 1)
        total += found
        count += 1
        if found < 0.25:
            low += 1
        if found > 0.75:
            high += 1
    assert_true(low > 40 and high > 40, "the threshold was not uniform")
    assert_almost_equal(total / Float32(count), 0.5, atol=0.08)


def test_coverage_follows_the_alpha() raises:
    var half = 0
    for y in range(4):
        for x in range(4):
            assert_true(alpha_covers(1, x, y))
            assert_false(alpha_covers(0, x, y))
            if alpha_covers(0.5, x, y):
                half += 1
            var edge = coverage_threshold(x, y)
            assert_true(edge > 0 and edge < 1)
    assert_equal(half, 8)
    # The pattern repeats every four pixels.
    assert_equal(coverage_threshold(5, 6), coverage_threshold(1, 2))


# --- the state ------------------------------------------------------------


def test_the_flags_ride_the_ops_word() raises:
    var state = RasterState(
        dithering=True,
        tone_mapped=False,
        alpha_hash=True,
        alpha_to_coverage=True,
        premultiplied_alpha=True,
        blend_red=0.25,
        blend_green=0.5,
        blend_blue=0.75,
        blend_alpha=1,
    )
    state.check()
    var back = RasterState.unpacked(state.ops_word(), state.stencil_word())
    assert_true(back.dithering)
    assert_false(back.tone_mapped)
    assert_true(back.alpha_hash)
    assert_true(back.alpha_to_coverage)
    assert_true(back.premultiplied_alpha)
    # The blend constant rides float lanes of its own, not the words.
    assert_equal(back.blend_alpha, 0)
    var constant = state.blend_constant()
    assert_equal(constant[0], 0.25)
    assert_equal(constant[3], 1)
    # The defaults are three.js's.
    var plain = RasterState.unpacked(
        RasterState().ops_word(), RasterState().stencil_word()
    )
    assert_true(plain == RasterState())
    assert_true(plain.tone_mapped)
    assert_false(plain.dithering)


def test_a_blend_constant_outside_zero_to_one_is_refused() raises:
    for bad in [Float32(-0.1), Float32(1.5)]:
        with assert_raises(contains="blend color"):
            RasterState(blend_red=bad).check()
        with assert_raises(contains="blend color"):
            RasterState(blend_green=bad).check()
        with assert_raises(contains="blend color"):
            RasterState(blend_blue=bad).check()
        with assert_raises(contains="blend color"):
            RasterState(blend_alpha=bad).check()


def test_a_material_carries_its_flags_into_its_state() raises:
    var plain = Material(Color(255, 255, 255), kind=BASIC)
    assert_true(plain.visible)
    assert_true(plain.allow_override)
    assert_true(plain.tone_mapped)
    assert_false(plain.dithering)
    assert_equal(plain.blend_alpha, 0)
    assert_equal(plain.blend_color.hex(), 0)
    var flagged = Material(Color(255, 255, 255), kind=BASIC)
    flagged.dithering = True
    flagged.tone_mapped = False
    flagged.alpha_hash = True
    flagged.alpha_to_coverage = True
    flagged.premultiplied_alpha = True
    flagged.blend_color = Color(255, 0, 0)
    flagged.blend_alpha = 0.5
    var state = flagged.raster_state()
    assert_true(state.dithering)
    assert_false(state.tone_mapped)
    assert_true(state.alpha_hash)
    assert_true(state.alpha_to_coverage)
    assert_true(state.premultiplied_alpha)
    # The color is decoded to linear light.
    assert_equal(state.blend_red, 1)
    assert_equal(state.blend_green, 0)
    assert_equal(state.blend_alpha, 0.5)
    flagged.blend_alpha = 2
    with assert_raises(contains="blend color"):
        _ = flagged.raster_state()


def test_a_shadow_side_falls_back_to_the_side() raises:
    var sheet = Material(Color(255, 255, 255), side=BACK_SIDE)
    assert_true(sheet.shadow_face() == BACK_SIDE)
    sheet.shadow_side = DOUBLE_SIDE
    assert_true(sheet.shadow_face() == DOUBLE_SIDE)
    sheet.shadow_side = Side(5)
    with assert_raises(contains="shadow side"):
        _ = sheet.shadow_face()


# --- triangles ------------------------------------------------------------


def test_a_dithered_triangle_moves_its_light_a_little() raises:
    var gray = FloatColor(0.2, 0.2, 0.2, 1)
    var plain = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(plain, gray, RasterState())
    var dithered = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(dithered, gray, RasterState(dithering=True))
    var moved = 0
    for y in range(SIZE):
        for x in range(SIZE):
            var shift = linear_to_srgb(
                dithered.color_at(x, y).r
            ) - linear_to_srgb(plain.color_at(x, y).r)
            assert_true(abs(shift) <= 0.5 / 255 + 1e-5)
            if abs(shift) > 1e-4:
                moved += 1
    assert_true(moved > 0, "nothing was dithered")
    # A data triangle is never dithered.
    var depth = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    var state = RasterState(dithering=True)
    rasterize_shaded(
        _corner(-1, -1, gray, state, kind=False),
        _corner(24, -1, gray, state, kind=False),
        _corner(-1, 24, gray, state, kind=False),
        depth,
    )
    assert_true(depth.is_data(3, 3))


def test_a_triangle_that_is_not_tone_mapped_keeps_the_curve_off() raises:
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(target, FloatColor(0.5, 0.5, 0.5, 1), RasterState())
    assert_false(target.is_data(2, 2))
    _cover(target, FloatColor(0.5, 0.5, 0.5, 1), RasterState(tone_mapped=False))
    assert_true(target.is_data(2, 2))


def test_a_hashed_triangle_keeps_about_its_alpha() raises:
    var state = RasterState(alpha_hash=True)
    var clear = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(clear, FloatColor(1, 1, 1, 0), state)
    assert_equal(_drawn(clear), 0)
    var solid = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(solid, FloatColor(1, 1, 1, 1), state)
    assert_equal(_drawn(solid), SIZE * SIZE)
    var half = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(half, FloatColor(1, 1, 1, 0.5), state)
    var kept = _drawn(half)
    assert_true(kept > 8 and kept < SIZE * SIZE - 8, "no hash was applied")
    # The uv view hashes nothing.
    var uv = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(uv, FloatColor(1, 1, 1, 0), state, mode_uv=True)
    assert_true(uv.is_data(1, 1))


def test_a_triangle_covers_by_its_alpha() raises:
    var state = RasterState(alpha_to_coverage=True)
    var half = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(half, FloatColor(1, 1, 1, 0.5), state)
    assert_equal(_drawn(half), SIZE * SIZE // 2)
    # A covered sample is written opaque.
    for y in range(SIZE):
        for x in range(SIZE):
            if half.color_at(x, y).r > 0:
                assert_equal(half.color_at(x, y).a, 1)
    # A fragment that fails its depth test is still shaded when its
    # coverage could discard it and its failure changes the stencil.
    var stenciled = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    var marking = RasterState(
        alpha_to_coverage=True,
        depth_test=True,
        stencil_write=True,
        stencil_z_fail=REPLACE_STENCIL_OP,
        stencil_ref=9,
    )
    _cover(stenciled, FloatColor(1, 1, 1, 1), RasterState())
    var a = _corner(-1, -1, FloatColor(1, 0, 0, 0.5), marking)
    a.z = 0.9
    var b = _corner(24, -1, FloatColor(1, 0, 0, 0.5), marking)
    b.z = 0.9
    var c = _corner(-1, 24, FloatColor(1, 0, 0, 0.5), marking)
    c.z = 0.9
    rasterize_shaded(a, b, c, stenciled)
    # The sample the alpha covers takes the failing operation; the one it
    # does not cover is discarded first and keeps its stencil.
    assert_equal(stenciled.stencil_at(0, 0), 9)
    assert_equal(stenciled.stencil_at(1, 0), 0)


def test_a_premultiplied_triangle_blends_by_three_js_factors() raises:
    var constant = RasterState(
        premultiplied_alpha=True, blend_red=0.5, blend_green=0.5, blend_blue=0.5
    )
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _cover(target, FloatColor(0.5, 0.5, 0.5, 1), RasterState())
    var mode = custom_blending(CONSTANT_COLOR_FACTOR, ZERO_FACTOR)
    var a = _corner(-1, -1, FloatColor(1, 1, 1, 0.5), constant)
    var b = _corner(24, -1, FloatColor(1, 1, 1, 0.5), constant)
    var c = _corner(-1, 24, FloatColor(1, 1, 1, 0.5), constant)
    a.blend = mode
    b.blend = mode
    c.blend = mode
    rasterize_shaded(a, b, c, target)
    # One premultiplied by one half, times the constant's one half.
    assert_almost_equal(target.color_at(2, 2).r, 0.25, atol=1e-5)


# --- segments and points ---------------------------------------------------


def _line(
    mut target: RenderTarget,
    color: FloatColor,
    state: RasterState,
    blend: Bool = False,
) raises:
    """Draw a horizontal segment across row three."""
    var a = _corner(-1, 3.5, color, state, blend)
    var b = _corner(Float32(SIZE + 1), 3.5, color, state, blend)
    rasterize_line(a, b, target)


def test_a_segment_reads_the_flags() raises:
    # Covering by its alpha: half the row's samples.
    var covered = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _line(
        covered, FloatColor(1, 1, 1, 0.5), RasterState(alpha_to_coverage=True)
    )
    assert_equal(_drawn(covered), SIZE // 2)
    # Not tone mapped, and dithered.
    var kept = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _line(
        kept,
        FloatColor(0.2, 0.2, 0.2, 1),
        RasterState(tone_mapped=False, dithering=True),
    )
    assert_true(kept.is_data(2, 3))
    assert_false(kept.is_data(2, 2))
    # Blended with a premultiplied color.
    var blended = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    _line(
        blended,
        FloatColor(1, 1, 1, 0.5),
        RasterState(premultiplied_alpha=True),
        blend=True,
    )
    assert_almost_equal(blended.color_at(2, 3).r, 0.5, atol=1e-5)


def _point(
    color: FloatColor, state: RasterState, blend: Bool = False
) -> RasterVertex:
    """Return a point four pixels wide at the target's middle."""
    var dot = _corner(4, 4, color, state, blend)
    dot.point_size = 4
    return dot


def test_a_point_reads_the_flags() raises:
    var covered = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    rasterize_point(
        _point(FloatColor(1, 1, 1, 0.5), RasterState(alpha_to_coverage=True)),
        covered,
    )
    assert_equal(_drawn(covered), 8)
    var kept = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    rasterize_point(
        _point(FloatColor(1, 1, 1, 1), RasterState(tone_mapped=False)), kept
    )
    assert_true(kept.is_data(4, 4))
    var blended = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    rasterize_point(
        _point(
            FloatColor(1, 1, 1, 0.5),
            RasterState(premultiplied_alpha=True),
            blend=True,
        ),
        blended,
    )
    assert_almost_equal(blended.color_at(4, 4).r, 0.5, atol=1e-5)
    # The uv view ignores the coverage.
    var uv = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    rasterize_point(
        _point(FloatColor(1, 1, 1, 0), RasterState(alpha_to_coverage=True)),
        uv,
        SHADE_UV,
    )
    assert_true(uv.is_data(4, 4))


# --- the curve ------------------------------------------------------------


def test_an_untoned_primitive_is_refused_beside_a_blend_under_a_curve() raises:
    var untoned = RasterState(tone_mapped=False)
    var white = FloatColor(1, 1, 1, 1)
    var flat = List[RasterVertex]()
    flat.append(_corner(0, 0, white, untoned))
    flat.append(_corner(4, 0, white, untoned))
    flat.append(_corner(0, 4, white, untoned))
    var glass = List[RasterVertex]()
    glass.append(_corner(0, 0, white, RasterState(), blend=True))
    glass.append(_corner(4, 0, white, RasterState(), blend=True))
    glass.append(_corner(0, 4, white, RasterState(), blend=True))
    var lines = List[RasterVertex]()
    lines.append(_corner(0, 0, white, untoned))
    lines.append(_corner(4, 0, white, untoned))
    var dots = List[RasterVertex]()
    dots.append(_point(white, untoned))
    var both = flat.copy()
    both.extend(glass.copy())
    # Alone, each is drawn.
    check_output_kinds(flat, True)
    check_output_kinds(glass, True)
    check_output_kinds(List[RasterVertex](), True, lines, dots)
    # Together under a curve, refused; without one, drawn.
    with assert_raises(contains="tone_mapped off"):
        check_output_kinds(both, True)
    check_output_kinds(both, False)
    with assert_raises(contains="tone_mapped off"):
        check_output_kinds(glass, True, lines)
    var shown = List[RasterVertex]()
    shown.append(_corner(0, 0, white, RasterState(), kind=False))
    shown.append(_corner(4, 0, white, RasterState(), kind=False))
    shown.append(_corner(0, 4, white, RasterState(), kind=False))
    shown.extend(glass.copy())
    with assert_raises(contains="data material"):
        check_output_kinds(shown, True)
    var strokes = List[RasterVertex]()
    strokes.append(_corner(0, 0, white, RasterState(), blend=True))
    strokes.append(_corner(4, 0, white, RasterState(), blend=True))
    with assert_raises(contains="tone_mapped off"):
        check_output_kinds(flat, True, strokes)
    with assert_raises(contains="tone_mapped off"):
        check_output_kinds(glass, True, List[RasterVertex](), dots)
    # An untoned blend is refused on its own.
    var untoned_glass = List[RasterVertex]()
    for corner in range(3):
        var blended = glass[corner]
        blended.state = untoned
        untoned_glass.append(blended)
    with assert_raises(contains="tone_mapped off"):
        check_output_kinds(untoned_glass, True)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
