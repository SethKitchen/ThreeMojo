# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the anti-aliasing passes: FXAA and SMAA against worked-out
answers on hand-built frames, and the SSAA and TAA passes against the
renderer."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from materials.material import Material, normal_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.antialiasing import (
    FXAA_EDGE_STEP_COUNT,
    SMAA_MAX_DISTANCE_LEFT,
    SMAA_MAX_DISTANCE_RIGHT,
    BlendWeights,
    EdgeMap,
    JitteredCamera,
    fxaa_light,
    fxaa_luminance,
    jitter_offsets,
    smaa_area,
    smaa_blend,
    smaa_edges,
    smaa_light,
    smaa_weights,
)
from postprocessing.composer import (
    FXAA,
    SMAA,
    SSAA_RENDER,
    TAA_RENDER,
    TAA_SAMPLES,
    EffectComposer,
    Pass,
    PassKind,
    check_pass,
    fxaa_pass,
    output_pass,
    render_pass,
    smaa_pass,
    ssaa_render_pass,
    supersample,
    taa_render_pass,
)
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import RenderTarget
from render.tonemap import REINHARD_TONE_MAPPING
from renderers.renderer import Renderer
from std.math import inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 24
comptime HEIGHT = 18
comptime BLACK = Color(0, 0, 0)
comptime WHITE = FloatColor(1, 1, 1, 1)
comptime DARK = FloatColor(0, 0, 0, 1)


def painted(width: Int, height: Int, lit: List[Bool]) raises -> RenderTarget:
    """Return a frame white where `lit` says and black elsewhere."""
    var frame = RenderTarget(width, height, BLACK)
    for y in range(height):
        for x in range(width):
            if lit[y * width + x]:
                frame.write(x, y, WHITE)
            else:
                frame.write(x, y, DARK)
    return frame^


def step_frame() raises -> RenderTarget:
    """Return a 16 by 8 frame, black above and white below, the white
    starting a row higher right of the middle: one step of a staircase."""
    var lit = List[Bool](length=16 * 8, fill=False)
    for y in range(8):
        for x in range(16):
            lit[y * 16 + x] = y >= 5 or (y >= 4 and x >= 8)
    return painted(16, 8, lit)


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
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b or p.a != q.a:
                count += 1
    return count


def is_between(value: Float32, low: Float32, high: Float32) -> Bool:
    """Return True if `value` is strictly between `low` and `high`."""
    return value > low and value < high


# --- the kinds and the builders ---------------------------------------------


def test_the_four_new_kinds_and_their_builders() raises:
    assert_true(FXAA.is_valid())
    assert_true(SMAA.is_valid())
    assert_true(SSAA_RENDER.is_valid())
    assert_true(TAA_RENDER.is_valid())
    assert_false(PassKind(35).is_valid())
    assert_equal(fxaa_pass().kind, FXAA)
    assert_equal(smaa_pass().kind, SMAA)
    var ssaa = ssaa_render_pass()
    assert_equal(ssaa.kind, SSAA_RENDER)
    assert_equal(ssaa.sample_level, 4)
    assert_true(ssaa.unbiased)
    var plain = ssaa_render_pass(2, False)
    assert_equal(plain.sample_level, 2)
    assert_false(plain.unbiased)
    var taa = taa_render_pass()
    assert_equal(taa.kind, TAA_RENDER)
    assert_equal(taa.sample_level, 0)
    assert_false(taa.accumulate)
    assert_equal(taa.accumulate_index, -1)
    assert_true(taa_render_pass(3, True).accumulate)


def test_a_sample_level_or_index_out_of_range_is_refused() raises:
    with assert_raises():
        _ = ssaa_render_pass(6)
    with assert_raises():
        _ = ssaa_render_pass(-1)
    with assert_raises():
        _ = taa_render_pass(7, True)
    var ahead = taa_render_pass(0, True)
    ahead.accumulate_index = TAA_SAMPLES + 1
    with assert_raises():
        check_pass(ahead)
    ahead.accumulate_index = -2
    with assert_raises():
        check_pass(ahead)
    ahead.accumulate_index = TAA_SAMPLES
    check_pass(ahead)
    check_pass(ssaa_render_pass(5))
    check_pass(ssaa_render_pass(0))
    with assert_raises():
        _ = jitter_offsets(6)
    with assert_raises():
        _ = jitter_offsets(-1)


def test_the_jitter_patterns_are_three_js_s() raises:
    var one = jitter_offsets(0)
    assert_equal(len(one), 1)
    assert_equal(one[0].x, Float32(0))
    var two = jitter_offsets(1)
    assert_equal(two[0].x, Float32(0.25))
    assert_equal(two[1].y, Float32(-0.25))
    var four = jitter_offsets(2)
    assert_equal(four[1].x, Float32(6.0 / 16.0))
    assert_equal(four[1].y, Float32(-2.0 / 16.0))
    assert_equal(len(jitter_offsets(3)), 8)
    var sixteen = jitter_offsets(4)
    assert_equal(sixteen[15].x, Float32(-7.0 / 16.0))
    assert_equal(sixteen[15].y, Float32(-8.0 / 16.0))
    var many = jitter_offsets(5)
    assert_equal(len(many), 32)
    assert_equal(many[0].x, Float32(-4.0 / 16.0))
    assert_equal(many[31].x, Float32(3.0 / 16.0))
    assert_equal(many[31].y, Float32(7.0 / 16.0))
    # Every offset lies inside the pixel, and each pattern is centered.
    for level in range(6):
        var offsets = jitter_offsets(level)
        for index in range(len(offsets)):
            assert_true(offsets[index].x >= -0.5 and offsets[index].x < 0.5)
            assert_true(offsets[index].y >= -0.5 and offsets[index].y < 0.5)


# --- FXAA -------------------------------------------------------------------


def test_fxaa_leaves_a_flat_frame_and_weights_luminance_as_three_js() raises:
    assert_almost_equal(
        fxaa_luminance(FloatColor(1, 0, 0, 1)), Float32(0.3), atol=1e-7
    )
    assert_almost_equal(
        fxaa_luminance(FloatColor(0, 1, 1, 1)), Float32(0.7), atol=1e-6
    )
    var lit = List[Bool](length=16, fill=True)
    var frame = painted(4, 4, lit)
    fxaa_light(frame)
    for index in range(16):
        assert_almost_equal(frame.colors[index].r, Float32(1), atol=1e-6)


def test_fxaa_blends_a_straight_edge_by_the_subpixel_factor() raises:
    # A vertical edge between black and white. Beside it, a pixel's
    # neighborhood averages a third away from it, so the subpixel factor is
    # smoothstep(1/3) squared; the edge never ends, so the edge factor is
    # zero; and the read moves that far across the edge.
    var lit = List[Bool](length=8 * 6, fill=False)
    for y in range(6):
        for x in range(4, 8):
            lit[y * 8 + x] = True
    var frame = painted(8, 6, lit)
    fxaa_light(frame)
    var f = Float32(1.0 / 3.0)
    var smooth = f * f * (3 - 2 * f)
    var blend = smooth * smooth
    assert_almost_equal(frame.color_at(3, 2).r, blend, atol=1e-5)
    assert_almost_equal(frame.color_at(4, 2).r, 1 - blend, atol=1e-5)
    assert_almost_equal(frame.color_at(0, 2).r, Float32(0), atol=1e-6)
    assert_almost_equal(frame.color_at(7, 2).r, Float32(1), atol=1e-6)
    # Turned on its side the answer is the same.
    var lying = List[Bool](length=6 * 8, fill=False)
    for y in range(4, 8):
        for x in range(6):
            lying[y * 6 + x] = True
    var turned = painted(6, 8, lying)
    fxaa_light(turned)
    assert_almost_equal(turned.color_at(2, 3).r, blend, atol=1e-5)
    assert_almost_equal(turned.color_at(2, 4).r, 1 - blend, atol=1e-5)


def test_fxaa_blends_a_short_step_more_near_its_end() raises:
    # One step of a staircase: the row just above the white is black on the
    # left and white on the right. Along the step's edge the pixel nearest
    # the corner blends most; far from it, the subpixel factor alone is
    # left.
    var frame = step_frame()
    fxaa_light(frame)
    var near = frame.color_at(7, 4).r
    var far = frame.color_at(1, 4).r
    assert_true(near > far, "the corner did not blend more")
    assert_true(is_between(near, 0, 1), "the corner did not blend")
    # Every value stays between black and white.
    for index in range(len(frame.colors)):
        assert_true(frame.colors[index].r >= -1e-6)
        assert_true(frame.colors[index].r <= 1 + 1e-6)


def test_fxaa_on_a_diagonal_and_on_noise_stays_in_range() raises:
    # A diagonal staircase of steps two pixels wide, and a hashed noise:
    # both reach every branch of the walk along an edge.
    var width = 20
    var height = 20
    var lit = List[Bool](length=width * height, fill=False)
    for y in range(height):
        for x in range(width):
            lit[y * width + x] = x >= 2 * (y // 2) + y % 2
    var diagonal = painted(width, height, lit)
    fxaa_light(diagonal)
    var changed = 0
    for index in range(len(diagonal.colors)):
        var value = diagonal.colors[index].r
        assert_true(value >= -1e-6 and value <= 1 + 1e-6)
        if is_between(value, 1e-3, 1 - 1e-3):
            changed += 1
    assert_true(changed > 20, "the diagonal was not smoothed")
    var noise = RenderTarget(width, height, BLACK)
    var seed = 7
    for y in range(height):
        for x in range(width):
            seed = (seed * 1103515245 + 12345) % 2147483648
            var level = Float32(seed % 1000) / 1000
            noise.write(x, y, FloatColor(level, level * 0.5, 1 - level, 1))
    fxaa_light(noise)
    for index in range(len(noise.colors)):
        assert_true(noise.colors[index].r >= -1e-6)
        assert_true(noise.colors[index].r <= 1 + 1e-6)
    assert_equal(FXAA_EDGE_STEP_COUNT, 6)


# --- SMAA -------------------------------------------------------------------


def test_the_area_of_each_pattern_is_the_area_texture_s() raises:
    # A straight edge, and every cross or T, is left alone.
    for left in range(3):
        for right in range(3):
            var none = smaa_area(False, False, False, False, left, right)
            assert_equal(none[0] + none[1], Float32(0))
            var cross = smaa_area(True, True, False, False, left, right)
            assert_equal(cross[0] + cross[1], Float32(0))
            var tee = smaa_area(False, False, True, True, left, right)
            assert_equal(tee[0] + tee[1], Float32(0))
            var full = smaa_area(True, True, True, True, left, right)
            assert_equal(full[0] + full[1], Float32(0))
    # An L below at the left: the line runs from half a pixel below the
    # left end to the edge at the middle. The first pixel of four is a
    # trapezoid of heights a half and a quarter.
    var ell = smaa_area(True, False, False, False, 0, 3)
    assert_almost_equal(ell[0], Float32(0.375), atol=1e-6)
    assert_equal(ell[1], Float32(0))
    # Past the middle the other end is nearer, and the L gives nothing.
    var past = smaa_area(True, False, False, False, 3, 0)
    assert_equal(past[0] + past[1], Float32(0))
    # The same L at the right, and both above.
    var right = smaa_area(False, False, True, False, 3, 0)
    assert_almost_equal(right[0], Float32(0.375), atol=1e-6)
    assert_equal(smaa_area(False, False, True, False, 0, 3)[0], Float32(0))
    var over = smaa_area(False, True, False, False, 0, 3)
    assert_almost_equal(over[1], Float32(0.375), atol=1e-6)
    assert_equal(over[0], Float32(0))
    assert_equal(smaa_area(False, True, False, False, 3, 0)[1], Float32(0))
    var over_right = smaa_area(False, False, False, True, 3, 0)
    assert_almost_equal(over_right[1], Float32(0.375), atol=1e-6)
    assert_equal(smaa_area(False, False, False, True, 0, 3)[1], Float32(0))
    # A Z from above at the left to below at the right: the line crosses
    # the edge in the middle pixel, two triangles of a twenty-fourth.
    var zed = smaa_area(False, True, True, False, 1, 1)
    assert_almost_equal(zed[0], Float32(1.0 / 24.0), atol=1e-6)
    assert_almost_equal(zed[1], Float32(1.0 / 24.0), atol=1e-6)
    var zed_start = smaa_area(False, True, True, False, 0, 1)
    assert_almost_equal(zed_start[1], Float32(0.25), atol=1e-6)
    var zed_end = smaa_area(False, True, True, False, 1, 0)
    assert_almost_equal(zed_end[0], Float32(0.25), atol=1e-6)
    # A crossing on both sides at one end acts as the opposite of the
    # crossing at the other.
    var seven = smaa_area(True, True, True, False, 0, 1)
    assert_almost_equal(seven[1], zed_start[1], atol=1e-6)
    var fourteen = smaa_area(False, True, True, True, 0, 1)
    assert_almost_equal(fourteen[1], zed_start[1], atol=1e-6)
    # The other Z, and its two relatives.
    var other = smaa_area(True, False, False, True, 0, 1)
    assert_almost_equal(other[0], Float32(0.25), atol=1e-6)
    assert_equal(other[1], Float32(0))
    var eleven = smaa_area(True, False, True, True, 0, 1)
    assert_almost_equal(eleven[0], Float32(0.25), atol=1e-6)
    var thirteen = smaa_area(True, True, False, True, 0, 1)
    assert_almost_equal(thirteen[0], Float32(0.25), atol=1e-6)
    # A one-pixel U above: two triangles of an eighth, each moved a
    # thirty-second of the way from a quarter toward itself.
    var bump = smaa_area(False, True, False, True, 0, 0)
    assert_equal(bump[0], Float32(0))
    var smoothed = Float32(0.25 + (0.125 - 0.25) / 32)
    assert_almost_equal(bump[1], 2 * smoothed, atol=1e-6)
    var dip = smaa_area(True, False, True, False, 0, 0)
    assert_almost_equal(dip[0], 2 * smoothed, atol=1e-6)
    assert_equal(dip[1], Float32(0))
    # A long U is not smoothed: at 32 pixels and more it keeps its area.
    var long = smaa_area(True, False, True, False, 0, 40)
    assert_almost_equal(long[0], smaa_area(True, False, False, False, 0, 40)[0])


def test_smaa_edges_mark_steps_and_drop_the_small_beside_the_large() raises:
    var frame = step_frame()
    var edges = smaa_edges(frame.colors, 16, 8)
    # The step's top edges, and its one left edge.
    assert_true(edges.top_at(8, 4))
    assert_true(edges.top_at(15, 4))
    assert_false(edges.top_at(7, 4))
    assert_true(edges.top_at(0, 5))
    assert_true(edges.top_at(7, 5))
    assert_false(edges.top_at(8, 5))
    assert_true(edges.left_at(8, 4))
    assert_false(edges.left_at(8, 5))
    assert_false(edges.left_at(8, 3))
    # Nothing at the frame's own edges, which read themselves.
    assert_false(edges.top_at(3, 0))
    assert_false(edges.left_at(0, 3))
    # A read past the map holds at its edge.
    assert_true(edges.top_at(40, 4))
    assert_true(edges.top_at(-3, 5))
    assert_false(edges.top_at(4, -1))
    # A step of 0.15 beside one of 0.85 is not an edge; alone, it is.
    var ramp = RenderTarget(4, 1, BLACK)
    ramp.write(0, 0, FloatColor(0, 0, 0, 1))
    ramp.write(1, 0, FloatColor(0, 0, 0, 1))
    ramp.write(2, 0, FloatColor(0.15, 0.15, 0.15, 1))
    ramp.write(3, 0, FloatColor(1, 1, 1, 1))
    var some = smaa_edges(ramp.colors, 4, 1)
    assert_false(some.left_at(2, 0))
    assert_true(some.left_at(3, 0))
    var gentle = RenderTarget(3, 1, BLACK)
    gentle.write(2, 0, FloatColor(0.15, 0.15, 0.15, 1))
    assert_true(smaa_edges(gentle.colors, 3, 1).left_at(2, 0))
    # One channel is enough, and a step under a tenth is not an edge.
    var green = RenderTarget(2, 1, BLACK)
    green.write(1, 0, FloatColor(0, 0.5, 0, 1))
    assert_true(smaa_edges(green.colors, 2, 1).left_at(1, 0))
    var faint = RenderTarget(2, 1, BLACK)
    faint.write(1, 0, FloatColor(0.05, 0.05, 0.05, 1))
    assert_false(smaa_edges(faint.colors, 2, 1).left_at(1, 0))
    # Transposed, left edges become top edges.
    var turned = edges.transposed()
    assert_equal(turned.width, 8)
    assert_equal(turned.height, 16)
    assert_true(turned.top_at(4, 8))
    assert_true(turned.left_at(4, 8))
    assert_true(turned.left_at(5, 0))


def test_smaa_weights_follow_the_step_s_lines() raises:
    var frame = step_frame()
    var edges = smaa_edges(frame.colors, 16, 8)
    var weights = smaa_weights(edges)
    # The upper run starts at column 8 with a crossing below and runs past
    # the right of the frame, which reads as going on: an L of 16 to the
    # right.
    var start = weights.at(8, 4)
    assert_almost_equal(
        start[0],
        smaa_area(True, False, False, False, 0, SMAA_MAX_DISTANCE_RIGHT)[0],
        atol=1e-6,
    )
    assert_true(start[0] > 0.45, "the corner pixel took too little")
    # The lower run ends at column 7 with a crossing above, and reads as
    # going on past the left of the frame: an L of 15 to the left.
    var end = weights.at(7, 5)
    assert_almost_equal(
        end[1],
        smaa_area(False, False, False, True, SMAA_MAX_DISTANCE_LEFT, 0)[1],
        atol=1e-6,
    )
    assert_almost_equal(end[1], Float32(0.46875), atol=1e-6)
    # The one left edge is a Z from below at its top to above at its foot.
    assert_almost_equal(start[2], Float32(0.125), atol=1e-6)
    assert_almost_equal(start[3], Float32(0.125), atol=1e-6)
    # Farther from the corner, less.
    assert_true(is_between(weights.at(15, 4)[0], 0, start[0]))
    assert_equal(weights.at(3, 2)[0] + weights.at(3, 2)[2], Float32(0))
    # A weight read past the frame holds at its edge.
    assert_equal(weights.at(-4, 5)[1], weights.at(0, 5)[1])


def test_smaa_walks_stop_at_crossings_and_at_the_reach() raises:
    # A 40-pixel line, black above and white below, with a notch: at
    # column 20 the white starts a row lower, a crossing below. Walks to the
    # left reach 15 and to the right 16.
    var width = 40
    var lit = List[Bool](length=width * 6, fill=False)
    for y in range(6):
        for x in range(width):
            lit[y * width + x] = y >= 3 and not (y == 3 and x == 20)
    var frame = painted(width, 6, lit)
    var edges = smaa_edges(frame.colors, width, 6)
    var weights = smaa_weights(edges)
    # Column 21 starts a run: a crossing below at its left end, and the
    # right walk stops at its reach.
    assert_almost_equal(
        weights.at(21, 3)[0],
        smaa_area(True, False, False, False, 0, SMAA_MAX_DISTANCE_RIGHT)[0],
        atol=1e-6,
    )
    # Column 19 ends a run: a crossing below at its right end, and the
    # left walk stops at its reach.
    assert_almost_equal(
        weights.at(19, 3)[0],
        smaa_area(False, False, True, False, SMAA_MAX_DISTANCE_LEFT, 0)[0],
        atol=1e-6,
    )
    # The notch itself has an edge above its foot, a one-pixel U.
    var notch = weights.at(20, 4)
    assert_almost_equal(
        notch[0], smaa_area(False, True, False, True, 0, 0)[0], atol=1e-6
    )
    assert_almost_equal(
        notch[1], smaa_area(False, True, False, True, 0, 0)[1], atol=1e-6
    )
    # A short run with no crossing at either end: an isolated dash two
    # pixels long in the middle of the frame.
    var dash = List[Bool](length=8 * 5, fill=False)
    dash[2 * 8 + 3] = True
    dash[2 * 8 + 4] = True
    var dashed = painted(8, 5, dash)
    var dash_edges = smaa_edges(dashed.colors, 8, 5)
    var dash_weights = smaa_weights(dash_edges)
    assert_almost_equal(
        dash_weights.at(3, 2)[0],
        smaa_area(True, False, True, False, 0, 1)[0],
        atol=1e-6,
    )


def test_smaa_blends_toward_the_heaviest_neighbor_in_gamma() raises:
    var frame = step_frame()
    var edges = smaa_edges(frame.colors, 16, 8)
    var weights = smaa_weights(edges)
    var blended = smaa_blend(frame.colors, 16, 8, weights)
    # The corner's white takes most from the black above, mixed in 2.2.
    var took = weights.at(8, 4)[0]
    assert_almost_equal(
        blended[4 * 16 + 8].r, (1 - took) ** (1 / 2.2), atol=1e-5
    )
    assert_almost_equal(blended[4 * 16 + 8].a, Float32(1), atol=1e-6)
    # The black beside it takes most from the white below.
    var gave = weights.at(7, 5)[1]
    assert_almost_equal(blended[4 * 16 + 7].r, gave ** (1 / 2.2), atol=1e-5)
    # A pixel with no weight is kept.
    assert_equal(blended[0].r, Float32(0))
    # Hand-set weights: the right and the left, the larger wins; across
    # beats up and down when larger.
    var colors = List[FloatColor](length=9, fill=FloatColor(0, 0, 0, 1))
    colors[3] = FloatColor(1, 1, 1, 1)
    colors[5] = FloatColor(1, 0, 0, 0.5)
    var hand = BlendWeights(3, 3)
    hand.rgba[4] = SIMD[DType.float32, 4](0, 0, 0.5, 0)
    hand.rgba[5] = SIMD[DType.float32, 4](0, 0, 0, 0.25)
    var mixed = smaa_blend(colors, 3, 3, hand)
    assert_almost_equal(mixed[4].g, Float32(0.5) ** (1 / 2.2), atol=1e-5)
    hand.rgba[5] = SIMD[DType.float32, 4](0, 0, 0, 0.75)
    mixed = smaa_blend(colors, 3, 3, hand)
    assert_almost_equal(mixed[4].r, Float32(0.75) ** (1 / 2.2), atol=1e-5)
    assert_equal(mixed[4].g, Float32(0))
    assert_almost_equal(mixed[4].a, Float32(1 - 0.75 * 0.5), atol=1e-6)
    # Up and down: the pixel below's green against the pixel's own red.
    var column = List[FloatColor](length=9, fill=FloatColor(0, 0, 0, 1))
    column[1] = FloatColor(1, 1, 1, 1)
    column[7] = FloatColor(0, 0, 1, 1)
    var vertical = BlendWeights(3, 3)
    vertical.rgba[4] = SIMD[DType.float32, 4](0.5, 0, 0, 0)
    vertical.rgba[7] = SIMD[DType.float32, 4](0, 0.25, 0, 0)
    var upward = smaa_blend(column, 3, 3, vertical)
    assert_almost_equal(upward[4].r, Float32(0.5) ** (1 / 2.2), atol=1e-5)
    vertical.rgba[7] = SIMD[DType.float32, 4](0, 0.75, 0, 0)
    var downward = smaa_blend(column, 3, 3, vertical)
    assert_equal(downward[4].r, Float32(0))
    assert_almost_equal(downward[4].b, Float32(0.75) ** (1 / 2.2), atol=1e-5)
    # Light below zero reads as zero in the gamma.
    var negative = List[FloatColor](length=2, fill=FloatColor(-1, 0, 0, 1))
    negative[1] = FloatColor(1, 0, 0, 1)
    var sideways = BlendWeights(2, 1)
    sideways.rgba[1] = SIMD[DType.float32, 4](0, 0, 0, 0.5)
    var clipped = smaa_blend(negative, 2, 1, sideways)
    assert_almost_equal(clipped[0].r, Float32(0.5) ** (1 / 2.2), atol=1e-5)


def test_smaa_leaves_a_flat_frame_and_smooths_a_step() raises:
    var lit = List[Bool](length=16, fill=True)
    var flat = painted(4, 4, lit)
    smaa_light(flat)
    for index in range(16):
        assert_equal(flat.colors[index].r, Float32(1))
    var frame = step_frame()
    smaa_light(frame)
    assert_true(is_between(frame.color_at(8, 4).r, 0, 1))
    assert_true(is_between(frame.color_at(7, 4).r, 0, 1))
    assert_equal(frame.color_at(0, 0).r, Float32(0))
    assert_equal(frame.color_at(0, 7).r, Float32(1))


# --- the jittered camera ----------------------------------------------------


def test_a_jittered_camera_moves_the_picture_the_other_way() raises:
    # A view offset of one whole pixel right and one down moves the picture
    # one pixel left and one up, exactly.
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var camera = a_camera()
    var plain = renderer.render(scene, assets, camera)
    var moved = JitteredCamera(camera, scene, 1, 1, WIDTH, HEIGHT)
    var shifted = renderer.render(scene, assets, moved)
    var differ = 0
    for y in range(HEIGHT - 1):
        for x in range(WIDTH - 1):
            var p = plain.get_pixel(x + 1, y + 1)
            var q = shifted.get_pixel(x, y)
            if p.r != q.r:
                differ += 1
    assert_equal(differ, 0)
    assert_true(count_differences(plain, shifted) > 0, "nothing moved")
    # Only the projection moves.
    var view = moved.view_matrix()
    var same = camera.view_matrix()
    assert_equal(view.get(0, 3), same.get(0, 3))
    assert_equal(moved.view_matrix_in(scene).get(2, 3), same.get(2, 3))
    assert_equal(moved.near_distance(), camera.near_distance())
    assert_equal(moved.far_distance(), camera.far_distance())
    assert_true(moved.visible_layers() == camera.visible_layers())
    with assert_raises():
        _ = moved.view_to_screen_matrix(0, 4)
    with assert_raises():
        _ = JitteredCamera(camera, scene, nan[DType.float32](), 0, 4, 4)
    with assert_raises():
        _ = JitteredCamera(camera, scene, 0, inf[DType.float32](), 4, 4)
    with assert_raises():
        _ = JitteredCamera(camera, scene, 0, 0, 0, 4)
    with assert_raises():
        _ = JitteredCamera(camera, scene, 0, 0, 4, -1)


# --- SSAA and TAA -----------------------------------------------------------


def test_one_sample_is_a_render_pass_and_more_smooth_the_edges() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var camera = a_camera()
    var direct = renderer.render(scene, assets, camera)
    var one = EffectComposer()
    one.add_pass(ssaa_render_pass(0))
    assert_equal(
        count_differences(direct, one.render(renderer, scene, assets, camera)),
        0,
    )
    # With sixteen samples, a pixel inside the sheet keeps its light and
    # one on its border is part lit.
    var many = supersample(renderer, scene, assets, camera, 4, True)
    var inside = renderer.width // 2 + (renderer.height // 2) * renderer.width
    var plain = RenderTarget(WIDTH, HEIGHT, BLACK)
    renderer.render_into(plain, scene, assets, camera)
    assert_almost_equal(
        many.colors[inside].r, plain.colors[inside].r, atol=1e-5
    )
    var partial = 0
    for index in range(len(many.colors)):
        if is_between(many.colors[index].a, 0.01, 0.99):
            partial += 1
        if is_between(
            many.colors[index].r, 0.01, plain.colors[inside].r - 0.01
        ):
            partial += 1
    assert_true(partial > 0, "no edge was smoothed")
    # Biased or not, the weights sum to one.
    var even = supersample(renderer, scene, assets, camera, 2, False)
    assert_almost_equal(
        even.colors[inside].r, plain.colors[inside].r, atol=1e-5
    )
    # The background is light, not data; a sheet of normals is data in
    # every sample, and stays data.
    assert_false(many.data[0])
    var shown = assets.materials.add(normal_material())
    scene.meshes[0].material = shown
    var normals = supersample(renderer, scene, assets, camera, 1, True)
    assert_true(normals.data[inside])
    assert_false(normals.data[0])
    assert_true(normals.depth[inside] < normals.depth[0])


def test_taa_accumulates_32_samples_over_frames_and_then_holds() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var camera = a_camera()
    var composer = EffectComposer()
    composer.add_pass(taa_render_pass(3, True))
    var images = List[Framebuffer]()
    for _ in range(5):
        images.append(composer.render(renderer, scene, assets, camera))
    # Eight samples a frame: 8, 16, 24, 32, and then no more.
    assert_equal(composer.passes[0].accumulate_index, TAA_SAMPLES)
    assert_equal(count_differences(images[3], images[4]), 0)
    # All 32 in, the frame is their average: a whole pixel inside the sheet
    # keeps its light.
    var full = composer.render(renderer, scene, assets, camera)
    var direct = renderer.render(scene, assets, camera)
    var cx = WIDTH // 2
    var cy = HEIGHT // 2
    assert_equal(full.get_pixel(cx, cy).r, direct.get_pixel(cx, cy).r)
    # `reset` forgets the samples: the next frame starts over, holding a
    # fresh frame, and has eight in again.
    composer.reset()
    _ = composer.render(renderer, scene, assets, camera)
    assert_equal(composer.passes[0].accumulate_index, 8)
    # So does an index of minus one.
    composer.passes[0].accumulate_index = -1
    _ = composer.render(renderer, scene, assets, camera)
    assert_equal(composer.passes[0].accumulate_index, 8)
    # Turned off, it is a supersampled render of its level, and its index
    # goes back to minus one.
    composer.passes[0].accumulate = False
    var off = composer.render(renderer, scene, assets, camera)
    assert_equal(composer.passes[0].accumulate_index, -1)
    var ssaa = EffectComposer()
    ssaa.add_pass(ssaa_render_pass(3))
    assert_equal(
        count_differences(off, ssaa.render(renderer, scene, assets, camera)),
        0,
    )
    # One sample a frame takes 32 frames; after the first, the frame is
    # one sample and 31 thirty-seconds of the held frame.
    var slow = EffectComposer()
    slow.add_pass(taa_render_pass(0, True))
    var first = slow.render(renderer, scene, assets, camera)
    assert_equal(slow.passes[0].accumulate_index, 1)
    assert_equal(len(slow.accumulations[0].hold), WIDTH * HEIGHT)
    assert_equal(first.get_pixel(cx, cy).r, direct.get_pixel(cx, cy).r)


def test_fxaa_and_smaa_run_in_the_composer_after_the_output() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BLACK)
    renderer.set_tone_mapping(REINHARD_TONE_MAPPING)
    var assets = Assets()
    var scene = lit_sheet(assets)
    var camera = a_camera()
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(output_pass())
    var sharp = composer.render(renderer, scene, assets, camera)
    composer.add_pass(fxaa_pass())
    var smooth = composer.render(renderer, scene, assets, camera)
    assert_true(count_differences(sharp, smooth) > 0, "FXAA did nothing")
    composer.passes[2].kind = SMAA
    var shaped = composer.render(renderer, scene, assets, camera)
    assert_true(count_differences(sharp, shaped) > 0, "SMAA did nothing")
    # A TAA pass in the list keeps a memory that insert and remove keep in
    # step with the passes.
    composer.insert_pass(taa_render_pass(), 0)
    assert_equal(len(composer.accumulations), 4)
    composer.remove_pass(0)
    assert_equal(len(composer.accumulations), 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
