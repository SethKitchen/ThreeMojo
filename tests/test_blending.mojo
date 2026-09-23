# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.blend` and the blending modes a material names."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light
from materials.material import (
    ADDITIVE,
    BASIC,
    BLEND,
    Blending,
    DEPTH,
    MULTIPLY,
    Material,
    OPAQUE,
    SUBTRACTIVE,
    custom_blending,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.blend import (
    ADD_EQUATION,
    BlendEquation,
    BlendFactor,
    CUSTOM_BASE,
    DST_ALPHA_FACTOR,
    DST_COLOR_FACTOR,
    MAX_EQUATION,
    MIN_EQUATION,
    ONE_FACTOR,
    ONE_MINUS_DST_ALPHA_FACTOR,
    ONE_MINUS_DST_COLOR_FACTOR,
    ONE_MINUS_SRC_ALPHA_FACTOR,
    ONE_MINUS_SRC_COLOR_FACTOR,
    REVERSE_SUBTRACT_EQUATION,
    Rgba,
    SRC_ALPHA_FACTOR,
    SRC_ALPHA_SATURATE_FACTOR,
    SRC_COLOR_FACTOR,
    SUBTRACT_EQUATION,
    ZERO_FACTOR,
    blend_pixel,
    is_valid_custom,
    pack_custom,
)
from render.framebuffer import Color, FloatColor
from render.target import RenderTarget
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

comptime TOLERANCE = Float64(1e-6)


def _near(got: Rgba, r: Float32, g: Float32, b: Float32, a: Float32) raises:
    """Assert a pixel's four channels.

    Args:
        got: The pixel.
        r: The expected red.
        g: The expected green.
        b: The expected blue.
        a: The expected alpha.

    Raises:
        Error: If a channel differs.
    """
    assert_almost_equal(got[0], r, atol=TOLERANCE)
    assert_almost_equal(got[1], g, atol=TOLERANCE)
    assert_almost_equal(got[2], b, atol=TOLERANCE)
    assert_almost_equal(got[3], a, atol=TOLERANCE)


def _one(src: BlendFactor, dst: BlendFactor, eq: BlendEquation) -> Int:
    """Return a custom mode with the same parts for color and alpha."""
    return pack_custom(src, dst, eq, src, dst, eq)


# The pixel behind and the fragment every factor test uses.
comptime BEHIND = Rgba(0.2, 0.4, 0.6, 0.5)
comptime FRONT = Rgba(0.5, 0.25, 1.0, 0.8)


def test_the_types_know_their_values() raises:
    assert_true(ZERO_FACTOR.is_valid())
    assert_true(SRC_ALPHA_SATURATE_FACTOR.is_valid())
    assert_false(BlendFactor(11).is_valid())
    assert_false(BlendFactor(-1).is_valid())
    assert_true(MAX_EQUATION.is_valid())
    assert_false(BlendEquation(5).is_valid())
    assert_false(BlendEquation(-1).is_valid())


def test_a_custom_mode_packs_six_fields() raises:
    var mode = _one(SRC_ALPHA_FACTOR, ONE_FACTOR, ADD_EQUATION)
    assert_true(mode >= CUSTOM_BASE)
    assert_true(is_valid_custom(mode))
    assert_false(is_valid_custom(5))
    assert_false(is_valid_custom(CUSTOM_BASE * 2))
    # A factor field of fifteen names no factor.
    assert_false(is_valid_custom(CUSTOM_BASE | 15))
    assert_false(is_valid_custom(CUSTOM_BASE | (7 << 8)))


def test_blending_names_its_modes() raises:
    assert_true(OPAQUE.is_valid())
    assert_true(MULTIPLY.is_valid())
    assert_false(Blending(5).is_valid())
    assert_false(Blending(-1).is_valid())
    assert_false(OPAQUE.mixes())
    assert_true(ADDITIVE.mixes())
    var custom = custom_blending(ONE_FACTOR, ONE_FACTOR)
    assert_true(custom.is_valid())
    assert_true(custom.mixes())
    var separate = custom_blending(
        ONE_FACTOR,
        ZERO_FACTOR,
        ADD_EQUATION,
        src_alpha=ZERO_FACTOR,
        dst_alpha=ONE_FACTOR,
        equation_alpha=MAX_EQUATION,
    )
    _near(blend_pixel(BEHIND, FRONT, separate.value), 0.5, 0.25, 1.0, 0.8)
    with assert_raises(contains="not one"):
        _ = custom_blending(BlendFactor(12), ONE_FACTOR)


def test_the_named_modes() raises:
    # Source-over.
    _near(
        blend_pixel(BEHIND, FRONT, BLEND.value),
        0.5 * 0.8 + 0.2 * 0.2,
        0.25 * 0.8 + 0.4 * 0.2,
        1.0 * 0.8 + 0.6 * 0.2,
        0.8 + 0.5 * 0.2,
    )
    # Additive: the color weighed by its alpha, and alpha squared.
    _near(
        blend_pixel(BEHIND, FRONT, ADDITIVE.value),
        0.5 * 0.8 + 0.2,
        0.25 * 0.8 + 0.4,
        1.0 * 0.8 + 0.6,
        1.0,
    )
    # Subtractive: behind times one less the color; alpha kept.
    _near(
        blend_pixel(BEHIND, FRONT, SUBTRACTIVE.value),
        0.2 * 0.5,
        0.4 * 0.75,
        0.0,
        0.5,
    )
    # Multiply: behind times the color, alpha times alpha.
    _near(
        blend_pixel(BEHIND, FRONT, MULTIPLY.value),
        0.2 * 0.5,
        0.4 * 0.25,
        0.6,
        0.5 * 0.8,
    )
    # An alpha past one counts as one.
    _near(blend_pixel(BEHIND, Rgba(1, 1, 1, 3), BLEND.value), 1, 1, 1, 1)


def test_every_factor() raises:
    # The factor on the source alone, so the result is the factor times the
    # fragment's color.
    var s = FRONT
    var d = BEHIND
    var expected = List[Rgba]()
    expected.append(Rgba(0))
    expected.append(Rgba(1))
    expected.append(s)
    expected.append(Rgba(1) - s)
    expected.append(Rgba(s[3]))
    expected.append(Rgba(1 - s[3]))
    expected.append(Rgba(d[3]))
    expected.append(Rgba(1 - d[3]))
    expected.append(d)
    expected.append(Rgba(1) - d)
    var saturate = min(s[3], 1 - d[3])
    expected.append(Rgba(saturate, saturate, saturate, 1))
    for code in range(11):
        var mode = _one(BlendFactor(code), ZERO_FACTOR, ADD_EQUATION)
        var got = blend_pixel(d, s, mode)
        var want = s * expected[code]
        _near(got, want[0], want[1], want[2], min(Float32(1), want[3]))


def test_every_equation() raises:
    var mode = _one(ONE_FACTOR, ONE_FACTOR, SUBTRACT_EQUATION)
    # The source less the destination, never below zero.
    _near(blend_pixel(BEHIND, FRONT, mode), 0.3, 0.0, 0.4, 0.3)
    mode = _one(ONE_FACTOR, ONE_FACTOR, REVERSE_SUBTRACT_EQUATION)
    _near(blend_pixel(BEHIND, FRONT, mode), 0.0, 0.15, 0.0, 0.0)
    mode = _one(ZERO_FACTOR, ZERO_FACTOR, MIN_EQUATION)
    _near(blend_pixel(BEHIND, FRONT, mode), 0.2, 0.25, 0.6, 0.5)
    mode = _one(ZERO_FACTOR, ZERO_FACTOR, MAX_EQUATION)
    _near(blend_pixel(BEHIND, FRONT, mode), 0.5, 0.4, 1.0, 0.8)
    # The two remaining factors, one on each side.
    mode = _one(ONE_MINUS_SRC_ALPHA_FACTOR, DST_ALPHA_FACTOR, ADD_EQUATION)
    _ = blend_pixel(BEHIND, FRONT, mode)
    mode = _one(ONE_MINUS_DST_ALPHA_FACTOR, DST_COLOR_FACTOR, ADD_EQUATION)
    _ = blend_pixel(BEHIND, FRONT, mode)
    mode = _one(SRC_COLOR_FACTOR, ONE_MINUS_DST_COLOR_FACTOR, ADD_EQUATION)
    _ = blend_pixel(BEHIND, FRONT, mode)
    mode = _one(ONE_MINUS_SRC_COLOR_FACTOR, ONE_FACTOR, ADD_EQUATION)
    _ = blend_pixel(BEHIND, FRONT, mode)


def test_a_target_blends_by_mode() raises:
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    target.write(0, 0, FloatColor(0.5, 0.5, 0.5, 1.0))
    # A clear fragment still darkens under the subtractive mode.
    target.blend(0, 0, FloatColor(1.0, 0.0, 0.0, 0.0), SUBTRACTIVE.value)
    var pixel = target.color_at(0, 0)
    assert_almost_equal(pixel.r, Float32(0), atol=TOLERANCE)
    assert_almost_equal(pixel.g, Float32(0.5), atol=TOLERANCE)
    # And adds nothing under the additive one.
    target.blend(0, 0, FloatColor(1.0, 1.0, 1.0, 0.0), ADDITIVE.value)
    assert_almost_equal(target.color_at(0, 0).g, Float32(0.5), atol=TOLERANCE)


def test_a_material_that_blends_by_any_mode_is_transparent() raises:
    var glow = Material(Color(255, 255, 255), kind=BASIC, blending=ADDITIVE)
    assert_true(glow.is_transparent())
    with assert_raises(contains="named modes"):
        _ = Material(Color(1, 1, 1), blending=Blending(9))
    with assert_raises(contains="cannot blend"):
        _ = Material(Color(255, 255, 255), kind=DEPTH, blending=MULTIPLY)


def test_an_additive_quad_brightens_what_is_behind() raises:
    var assets = Assets()
    var scene = Scene()
    var back = scene.add(Object3D())
    var front = scene.add(Object3D())
    scene.node(front).set_position(0, 0, 0.5)
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    var quad = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var gray = assets.materials.add(Material(Color(100, 100, 100), kind=BASIC))
    scene.add_mesh(Mesh(quad, gray, back))
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var renderer = Renderer(8, 8)
    scene.update()
    var before = renderer.render(scene, assets, camera).get_pixel(4, 4)
    var glow = assets.materials.add(
        Material(Color(80, 0, 0), kind=BASIC, blending=ADDITIVE)
    )
    scene.add_mesh(Mesh(quad, glow, front))
    scene.update()
    var after = renderer.render(scene, assets, camera).get_pixel(4, 4)
    assert_true(after.r > before.r)
    assert_equal(after.g, before.g)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
