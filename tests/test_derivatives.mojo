# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.derivatives`, and for what reads a screen-space width:
the toon fallback's edge in `lights.lighting`, `surface_steps` and
`edge_ramp_at` in `render.fragment_flags`, and the toon edge, the matcap
footprint, the alpha test's ramp and a wide line's edge ramp in
`render.rasterizer`.

The expected numbers are worked out from the GLSL each one ports. A
triangle with corners at (0, 0), (W, 0) and (0, H) weighs its second
corner by `x / W` at a pixel center, so a value that changes from the
first corner to the second changes by a known amount per pixel.
"""

from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import directional_light, point_light, spot_light
from lights.lighting import (
    Lighting,
    TOON_EDGE,
    TOON_SHADE,
    toon_coord,
    toon_edge,
    toon_step,
    toon_tone,
    toon_width_along,
    toon_width_toward,
)
from materials.material import BASIC, BLEND, MATCAP, OPAQUE, TOON
from materials.nodes import (
    AT_RIGHT,
    AT_UP,
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    NodeContext,
    NodeGraph,
    NodeInputs,
    NodeProgramId,
    NodeProgramStore,
    NodeSource,
    OPACITY_NODE,
)
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.derivatives import (
    CAPSULE_EDGE_RAMP,
    DISC_EDGE_RAMP,
    NO_EDGE_RAMP,
    EdgeRamp,
    SurfaceSteps,
    alpha_test_ramp,
    edge_ramp_alpha,
    fwidth,
    require_edge_ramp,
)
from render.fragment_flags import alpha_covers, edge_ramp_at, surface_steps
from render.framebuffer import Color, FloatColor
from render.raster_state import RasterState
from render.rasterizer import (
    RasterVertex,
    SHADE_TEXTURE,
    SHADE_UV,
    matcap_steps,
    matcap_uv,
    rasterize_point,
    rasterize_shaded,
)
from render.srgb import LINEAR
from render.target import RenderTarget
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    IGNORED,
    NEAREST,
    REPEAT,
    Texture,
)
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from std.math import nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE

comptime Lanes = SIMD[DType.float32, 4]
comptime TOLERANCE = Float64(1e-5)
comptime WHITE = Color(255, 255, 255)
comptime ORIGIN = Vector3(0, 0, 0)
# The intensity that lights a white surface square on to full white.
comptime FULL = Float32(pi)
# The side of the triangles and the targets below, in pixels.
comptime SIDE = 32


def hermite(t: Float64) -> Float64:
    """Return GLSL's `smoothstep` over a fraction already from zero to
    one."""
    return t * t * (3 - 2 * t)


def step_between(edge0: Float64, edge1: Float64, x: Float64) -> Float64:
    """Return GLSL's `smoothstep`, written out again for the tests."""
    if x <= edge0:
        return 0
    if x >= edge1:
        return 1
    return hermite((x - edge0) / (edge1 - edge0))


# --- render.derivatives -------------------------------------------------------


def test_an_edge_ramp_is_one_of_three() raises:
    assert_true(NO_EDGE_RAMP.is_valid())
    assert_true(DISC_EDGE_RAMP.is_valid())
    assert_true(CAPSULE_EDGE_RAMP.is_valid())
    assert_false(EdgeRamp(3).is_valid())
    assert_false(EdgeRamp(-1).is_valid())
    require_edge_ramp(CAPSULE_EDGE_RAMP)
    with assert_raises(contains="none of the three"):
        require_edge_ramp(EdgeRamp(3))


def test_fwidth_is_the_sum_of_two_absolute_differences() raises:
    # GLSL's `abs(dFdx(v)) + abs(dFdy(v))`.
    assert_equal(fwidth(1, 1, 1), Float32(0))
    assert_equal(fwidth(1, 3, 1), Float32(2))
    assert_equal(fwidth(1, 0.5, 4), Float32(3.5))
    assert_equal(fwidth(-2, -3, -2.5), Float32(1.5))


def test_an_alpha_test_ramp_is_three_js_smoothstep() raises:
    # `smoothstep(alphaTest, alphaTest + fwidth(alpha), alpha)`.
    assert_equal(alpha_test_ramp(0.5, 0.5, 0.2), Float32(0))
    assert_almost_equal(
        alpha_test_ramp(0.55, 0.5, 0.2), 0.15625, atol=TOLERANCE
    )
    assert_almost_equal(alpha_test_ramp(0.6, 0.5, 0.2), 0.5, atol=TOLERANCE)
    assert_equal(alpha_test_ramp(0.9, 0.5, 0.2), Float32(1))
    # No width is the hard step: zero at and below the test, one above.
    assert_equal(alpha_test_ramp(0.2, 0.5, 0), Float32(0))
    assert_equal(alpha_test_ramp(0.5, 0.5, 0), Float32(0))
    assert_equal(alpha_test_ramp(0.51, 0.5, 0), Float32(1))
    # A width that is not a number, or below zero, is the hard step too.
    assert_equal(alpha_test_ramp(0.9, 0.5, nan[DType.float32]()), Float32(1))
    assert_equal(alpha_test_ramp(0.4, 0.5, nan[DType.float32]()), Float32(0))
    assert_equal(alpha_test_ramp(0.9, 0.5, -1), Float32(1))


def test_a_disc_ramp_reads_the_squared_length_about_one() raises:
    # `1 - smoothstep(1 - dlen, 1 + dlen, len2)`. Here len2 is 1, 1.13 and
    # 1.17, so dlen is 0.3 and the rim is half covered.
    var rim = edge_ramp_alpha(
        DISC_EDGE_RAMP, Vector2(0.6, 0.8), Vector2(0.7, 0.8), Vector2(0.6, 0.9)
    )
    assert_almost_equal(rim, 0.5, atol=TOLERANCE)
    # Well inside is one and well outside is zero.
    var inside = edge_ramp_alpha(
        DISC_EDGE_RAMP, Vector2(0, 0), Vector2(0.1, 0), Vector2(0, 0.1)
    )
    assert_equal(inside, Float32(1))
    var outside = edge_ramp_alpha(
        DISC_EDGE_RAMP, Vector2(2, 0), Vector2(2.1, 0), Vector2(2, 0.1)
    )
    assert_equal(outside, Float32(0))
    # Where the coordinates do not move the edge is hard: the rim itself
    # is inside.
    var on_it = Vector2(1, 0)
    assert_equal(
        edge_ramp_alpha(DISC_EDGE_RAMP, on_it, on_it, on_it), Float32(1)
    )
    var past = Vector2(1.01, 0)
    assert_equal(edge_ramp_alpha(DISC_EDGE_RAMP, past, past, past), Float32(0))


def test_a_capsule_ramp_reads_half_the_length_about_one_half() raises:
    # `1 - smoothstep(0.5 - dnorm, 0.5 + dnorm, norm)`, `norm` half the
    # length. Here norm is 0.5 and 0.6, so dnorm is 0.1.
    var rim = edge_ramp_alpha(
        CAPSULE_EDGE_RAMP, Vector2(1, 0), Vector2(1.2, 0), Vector2(1, 0)
    )
    assert_almost_equal(rim, 0.5, atol=TOLERANCE)
    # A quarter of the way up the ramp: 1 - 0.15625.
    var near = edge_ramp_alpha(
        CAPSULE_EDGE_RAMP, Vector2(0.9, 0), Vector2(1.1, 0), Vector2(0.9, 0)
    )
    assert_almost_equal(near, 0.84375, atol=TOLERANCE)
    # No ramp leaves the alpha alone, whatever the coordinates say.
    assert_equal(
        edge_ramp_alpha(
            NO_EDGE_RAMP, Vector2(9, 9), Vector2(0, 0), Vector2(3, 3)
        ),
        Float32(1),
    )


def test_surface_steps_hold_three_pixels_or_nothing() raises:
    var none = SurfaceSteps()
    assert_false(none.measured)
    assert_equal(none.normal_right.x, Float32(0))
    var held = SurfaceSteps(
        Vector3(0, 0, 1),
        Vector3(1, 2, 3),
        Vector3(0, 1, 0),
        Vector3(4, 5, 6),
        Vector3(1, 0, 0),
        Vector3(7, 8, 9),
    )
    assert_true(held.measured)
    assert_equal(held.normal.z, Float32(1))
    assert_equal(held.position.y, Float32(2))
    assert_equal(held.normal_right.y, Float32(1))
    assert_equal(held.position_right.z, Float32(6))
    assert_equal(held.normal_up.x, Float32(1))
    assert_equal(held.position_up.x, Float32(7))


# --- the toon fallback's edge -----------------------------------------------


def unit(x: Float32, y: Float32, z: Float32) -> Vector3:
    """Return a unit vector pointing that way."""
    var facing = Vector3(x, y, z)
    facing.normalize()
    return facing^


def leaning(cosine: Float32) -> Vector3:
    """Return a unit normal whose cosine with +y is `cosine`."""
    return Vector3(sqrt(1 - cosine * cosine), cosine, 0)


def lamp_at(
    x: Float32, y: Float32, z: Float32, kind: Int = 0
) raises -> Lighting:
    """Return lighting with one white light on a node at a position: a
    directional light for kind 0, a point light that does not fall off for
    kind 1, and a spot light that does not fall off for kind 2."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(x, y, z)
    var node = scene.add(lamp^)
    if kind == 0:
        scene.add_light(directional_light(WHITE, node, FULL))
    elif kind == 1:
        scene.add_light(point_light(WHITE, node, FULL, 0.0))
    else:
        scene.add_light(
            spot_light(WHITE, node, FULL, 0.0, Angle(60.0, DEGREE), 0.0, 0.0)
        )
    scene.update()
    return Lighting(scene)


def test_the_fallback_edge_is_three_js_mix_of_a_smoothstep() raises:
    # `mix(0.7, 1.0, smoothstep(0.7 - fw, 0.7 + fw, coord))`.
    assert_almost_equal(toon_edge(0.7, 0.1), 0.85, atol=TOLERANCE)
    assert_almost_equal(toon_edge(0.65, 0.1), 0.746875, atol=TOLERANCE)
    assert_equal(toon_edge(0.5, 0.1), TOON_SHADE)
    assert_equal(toon_edge(0.9, 0.1), Float32(1))
    # No width, a width below zero and a width that is not a number give
    # the hard step.
    for coord in [Float32(0.2), TOON_EDGE - 0.001, TOON_EDGE, Float32(0.9)]:
        assert_equal(toon_edge(coord, 0), toon_step(coord))
        assert_equal(toon_edge(coord, -0.5), toon_step(coord))
        assert_equal(toon_edge(coord, nan[DType.float32]()), toon_step(coord))


def test_a_width_along_a_direction_reads_the_three_normals() raises:
    var toward = Vector3(0, 0, 1)
    # The coordinates are 1, 0.9 and 0.9: `fwidth` is 0.2, and half is 0.1.
    var steps = SurfaceSteps(
        Vector3(0, 0, 1),
        ORIGIN,
        Vector3(0.6, 0, 0.8),
        ORIGIN,
        Vector3(0, 0.6, 0.8),
        ORIGIN,
    )
    assert_almost_equal(toon_width_along(steps, toward), 0.1, atol=TOLERANCE)
    # Steps that hold nothing have no width.
    assert_equal(toon_width_along(SurfaceSteps(), toward), Float32(0))


def test_a_width_toward_a_position_reads_normals_and_positions() raises:
    var light = Vector3(0, 0, 1)
    var up = Vector3(0, 0, 1)
    # One normal everywhere, and the way to the light changes: straight
    # up here, and at 45 degrees one meter to the right. The coordinates
    # are 1 and 0.5 + 0.5 / sqrt(2).
    var plane = SurfaceSteps(up, ORIGIN, up, Vector3(1, 0, 0), up, ORIGIN)
    var expected = (1 - (0.5 + 0.5 / sqrt(Float64(2)))) * 0.5
    assert_almost_equal(
        toon_width_toward(plane, light, 1), Float32(expected), atol=TOLERANCE
    )
    # A neighbor on the light has no direction and takes the fragment's
    # coordinate. Here the pixel above is on the light, and the pixel to
    # the right faces away from it: coordinates 1, 0 and 1.
    var on_right = SurfaceSteps(
        up, ORIGIN, Vector3(0, 0, -1), Vector3(0, 0, 0.5), up, light
    )
    assert_almost_equal(
        toon_width_toward(on_right, light, 1), 0.5, atol=TOLERANCE
    )
    # A fragment on the light takes the coordinate the caller gives.
    var on_it = SurfaceSteps(
        up, light, Vector3(0, 0, -1), Vector3(0, 0, 0.5), up, light
    )
    assert_almost_equal(
        toon_width_toward(on_it, light, 0.3), 0.15, atol=TOLERANCE
    )
    assert_equal(toon_width_toward(SurfaceSteps(), light, 1), Float32(0))


def test_a_tone_softens_the_fallback_and_not_a_ramp() raises:
    var none = List[Float32]()
    # A cosine of 0.4 is a coordinate of 0.7, the edge itself.
    assert_almost_equal(toon_tone(0.4, none, 0.1), 0.85, atol=TOLERANCE)
    assert_equal(toon_tone(0.4, none), toon_step(toon_coord(0.4)))
    var tones: List[Float32] = [0.2, 0.6, 1.0]
    assert_equal(toon_tone(0.4, tones, 0.1), toon_tone(0.4, tones))


def test_each_kind_of_light_softens_its_own_edge() raises:
    # A surface whose coordinate is on the edge, 0.7, and 0.8 one pixel to
    # the right: half of `fwidth` is 0.05, so the tone is halfway up.
    var edge = leaning(0.4)
    var beside = leaning(0.6)
    var steps = SurfaceSteps(edge, ORIGIN, beside, ORIGIN, edge, ORIGIN)
    var none = List[Float32]()
    for kind in range(3):
        var lighting = lamp_at(0, 2, 0, kind)
        var soft = lighting.toon_at(edge, ORIGIN, none, True, steps=steps)
        assert_almost_equal(soft.r, 0.85, atol=TOLERANCE)
        # Without the steps the edge is hard, as it always was.
        var hard = lighting.toon_at(edge, ORIGIN, none)
        assert_equal(hard.r, toon_step(toon_coord(edge.y)))
        # A ramp of the material's own does not read the steps.
        var tones: List[Float32] = [0.2, 0.6, 1.0]
        assert_equal(
            lighting.toon_at(edge, ORIGIN, tones, True, steps=steps).r,
            lighting.toon_at(edge, ORIGIN, tones).r,
        )


# --- render.fragment_flags over a triangle's plane ---------------------------


struct Plane(NodeSource):
    """A `NodeSource` over a triangle of made-up corners and weights.

    The fragment weighs the corners one half, one quarter, one quarter; the
    pixel to the right one quarter, one half, one quarter; the pixel above
    one quarter, one quarter, one half. The coordinates are `scale` times
    (0.25, 0.25) here, (0.5, 0.25) to the right and (0.25, 0.5) above.
    """

    var scale: Float32

    def __init__(out self, scale: Float32 = 1):
        """Read no program, and scale the coordinates."""
        self.scale = scale

    def word(self, at: Int) -> Float32:
        """Return no float: there is no program."""
        return 0

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return opaque white."""
        return FloatColor(1, 1, 1, 1)

    def sample_level(
        self, slot: Int, u: Float32, v: Float32, level: Float32
    ) -> FloatColor:
        """Return opaque white."""
        return FloatColor(1, 1, 1, 1)

    def fetch(self, slot: Int, x: Int, y: Int, level: Int) -> FloatColor:
        """Return opaque white."""
        return FloatColor(1, 1, 1, 1)

    def size(self, slot: Int, level: Int) -> Lanes:
        """Return no size."""
        return Lanes(0)

    def shares(self, context: NodeContext) -> Lanes:
        """Return the made-up weights."""
        if context == AT_RIGHT:
            return Lanes(0.25, 0.5, 0.25, 0)
        if context == AT_UP:
            return Lanes(0.25, 0.25, 0.5, 0)
        return Lanes(0.5, 0.25, 0.25, 0)

    def frag_coord(self, context: NodeContext) -> Lanes:
        """Return no place."""
        return Lanes(0, 0, 0, 1)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return the made-up corners: normals two long, to see them made
        unit."""
        var none = Vector3(0, 0, 0)
        if context == CORNER_A:
            return NodeInputs(
                0, 0, Vector3(0, 0, 0), Vector3(0, 0, 2), none, none, False
            )
        if context == CORNER_B:
            return NodeInputs(
                self.scale,
                0,
                Vector3(4, 0, 0),
                Vector3(0, 2, 0),
                none,
                none,
                False,
            )
        return NodeInputs(
            0, self.scale, Vector3(0, 4, 0), Vector3(2, 0, 0), none, none, False
        )


def test_surface_steps_interpolate_the_plane_at_three_pixels() raises:
    var steps = surface_steps(Plane())
    assert_true(steps.measured)
    # Here: a quarter of (4, 0, 0) and a quarter of (0, 4, 0).
    assert_almost_equal(steps.position.x, 1, atol=TOLERANCE)
    assert_almost_equal(steps.position.y, 1, atol=TOLERANCE)
    assert_almost_equal(steps.position_right.x, 2, atol=TOLERANCE)
    assert_almost_equal(steps.position_right.y, 1, atol=TOLERANCE)
    assert_almost_equal(steps.position_up.x, 1, atol=TOLERANCE)
    assert_almost_equal(steps.position_up.y, 2, atol=TOLERANCE)
    # The normals are (0.5, 0.5, 1), (0.5, 1, 0.5) and (1, 0.5, 0.5), each
    # made unit: one over the square root of one and a half.
    var long = Float32(1 / sqrt(Float64(1.5)))
    assert_almost_equal(steps.normal.z, long, atol=TOLERANCE)
    assert_almost_equal(steps.normal.x, long * 0.5, atol=TOLERANCE)
    assert_almost_equal(steps.normal_right.y, long, atol=TOLERANCE)
    assert_almost_equal(steps.normal_right.z, long * 0.5, atol=TOLERANCE)
    assert_almost_equal(steps.normal_up.x, long, atol=TOLERANCE)
    assert_almost_equal(steps.normal_up.y, long * 0.5, atol=TOLERANCE)


def test_an_edge_ramp_reads_the_planes_coordinates() raises:
    # Scaled by four the coordinates are (1, 1), (2, 1) and (1, 2): the
    # squared lengths are 2, 5 and 5, so `fwidth` is 6.
    var disc = step_between(1 - 6, 1 + 6, 2)
    assert_almost_equal(
        edge_ramp_at(Plane(4), DISC_EDGE_RAMP),
        Float32(1 - disc),
        atol=TOLERANCE,
    )
    # Half the lengths are sqrt(2) / 2 and sqrt(5) / 2.
    var here = sqrt(Float64(2)) / 2
    var beside = sqrt(Float64(5)) / 2
    var width = 2 * (beside - here)
    var capsule = step_between(0.5 - width, 0.5 + width, here)
    assert_almost_equal(
        edge_ramp_at(Plane(4), CAPSULE_EDGE_RAMP),
        Float32(1 - capsule),
        atol=TOLERANCE,
    )
    assert_equal(edge_ramp_at(Plane(4), NO_EDGE_RAMP), Float32(1))


# --- a toon triangle's edge ---------------------------------------------------


def toon_corner(
    x: Float32, y: Float32, normal: Vector3, world: Vector3
) -> RasterVertex:
    """Return a white toon corner with no ramp of its own."""
    return RasterVertex(
        x, y, 0.5, 1, FloatColor(1, 1, 1), normal=normal, world=world, kind=TOON
    )


def test_a_toon_triangle_softens_the_edge_by_its_width() raises:
    # The normal turns from +z at the left to +x at the right, and the
    # light is along +z. At a pixel center the normal is (t, 0, 1 - t)
    # made unit, with t = (x + 0.5) / 32, so the cosine is known.
    var lighting = lamp_at(0, 0, 1)
    var target = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    var left = Vector3(0, 0, 1)
    var right = Vector3(1, 0, 0)
    rasterize_shaded(
        toon_corner(0, 0, left, ORIGIN),
        toon_corner(Float32(SIDE), 0, right, ORIGIN),
        toon_corner(0, Float32(SIDE), left, ORIGIN),
        target,
        lighting=lighting,
    )
    var soft = 0
    for x in range(18, 26):
        var here = coord_across(x)
        var beside = coord_across(x + 1)
        # The row above has the same normal, so `dFdy` is zero.
        var half = abs(beside - here) * 0.5
        var tone = 0.7 + 0.3 * step_between(0.7 - half, 0.7 + half, here)
        assert_almost_equal(
            target.color_at(x, 2).r, Float32(tone), atol=Float64(1e-4)
        )
        if tone > 0.7001 and tone < 0.9999:
            soft += 1
    # Exactly one pixel of the row is on the edge.
    assert_equal(soft, 1)


def coord_across(x: Int) -> Float64:
    """Return the toon coordinate at a pixel of the triangle above."""
    var t = (Float64(x) + 0.5) / Float64(SIDE)
    var cosine = (1 - t) / sqrt(t * t + (1 - t) * (1 - t))
    return cosine * 0.5 + 0.5


def test_a_toon_triangle_softens_the_edge_of_a_bulb() raises:
    # One normal everywhere, +z, on a floor an eighth of a meter a pixel,
    # under a bulb one meter up that does not fall off. The cosine at a
    # pixel is one over the distance to the bulb.
    var lighting = lamp_at(0, 0, 1, 1)
    var target = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    var up = Vector3(0, 0, 1)
    rasterize_shaded(
        toon_corner(0, 0, up, ORIGIN),
        toon_corner(Float32(SIDE), 0, up, Vector3(4, 0, 0)),
        toon_corner(0, Float32(SIDE), up, Vector3(0, 4, 0)),
        target,
        lighting=lighting,
    )
    var soft = 0
    for x in range(14, 22):
        var here = coord_under(x, 2)
        var half = (
            abs(coord_under(x + 1, 2) - here) + abs(coord_under(x, 1) - here)
        ) * 0.5
        var tone = 0.7 + 0.3 * step_between(0.7 - half, 0.7 + half, here)
        assert_almost_equal(
            target.color_at(x, 2).r, Float32(tone), atol=Float64(1e-4)
        )
        if tone > 0.7001 and tone < 0.9999:
            soft += 1
    assert_equal(soft, 1)


def test_a_toon_triangle_with_a_ramp_keeps_its_hard_steps() raises:
    # A gradient map of two tones is a lookup table: black below a
    # coordinate of one half and white from it. No fragment reads a width,
    # so no fragment shows a tone between the two.
    var textures = TextureStore()
    var tones: List[UInt8] = [0, 255, 0, 255, 255, 255, 0, 255]
    var ramp = textures.add(
        Texture(2, 1, tones^, REPEAT, NEAREST, LINEAR, False, IGNORED)
    )
    var left = Vector3(0, 0, 1)
    var right = Vector3(1, 0, -1)
    var target = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    var a = toon_corner(0, 0, left, ORIGIN)
    var b = toon_corner(Float32(SIDE), 0, right, ORIGIN)
    var c = toon_corner(0, Float32(SIDE), left, ORIGIN)
    a.gradient_map = ramp
    b.gradient_map = ramp
    c.gradient_map = ramp
    rasterize_shaded(a, b, c, target, SHADE_TEXTURE, textures, lamp_at(0, 0, 1))
    var dark = 0
    var bright = 0
    for x in range(SIDE - 4):
        var tone = target.color_at(x, 2).r
        if tone == 0:
            dark += 1
        elif tone > 0.999:
            bright += 1
    assert_equal(dark + bright, SIDE - 4)
    assert_true(dark > 0 and bright > 0, "the ramp did not step")


def coord_under(x: Int, y: Int) -> Float64:
    """Return the toon coordinate at a pixel of the floor above."""
    var px = (Float64(x) + 0.5) / 8
    var py = (Float64(y) + 0.5) / 8
    return 0.5 / sqrt(1 + px * px + py * py) + 0.5


# --- a matcap's own footprint -------------------------------------------------


def test_matcap_steps_are_the_lookups_two_differences() raises:
    var eye = Vector3(0, 0, 4)
    var up = Vector3(0, 1, 0)
    # The normal turns to +x one pixel right and to +y one pixel up, at
    # one place: the lookup moves from the middle to each edge, 0.495.
    var turning = SurfaceSteps(
        Vector3(0, 0, 1),
        ORIGIN,
        Vector3(1, 0, 0),
        ORIGIN,
        Vector3(0, 1, 0),
        ORIGIN,
    )
    var moved = matcap_steps(turning, eye, up)
    assert_almost_equal(moved[0].x, 0.495, atol=TOLERANCE)
    assert_almost_equal(moved[0].y, 0, atol=TOLERANCE)
    assert_almost_equal(moved[1].x, 0, atol=TOLERANCE)
    assert_almost_equal(moved[1].y, 0.495, atol=TOLERANCE)
    # One normal, and the place moves four meters right: the camera sees
    # it at 45 degrees, so the lookup moves by 0.495 / sqrt(2) across.
    var sliding = SurfaceSteps(
        Vector3(0, 0, 1),
        ORIGIN,
        Vector3(0, 0, 1),
        Vector3(4, 0, 0),
        Vector3(0, 0, 1),
        ORIGIN,
    )
    var slid = matcap_steps(sliding, eye, up)
    var here = matcap_uv(Vector3(0, 0, 1), up, Vector3(0, 0, 1))
    assert_almost_equal(here.x, 0.5, atol=TOLERANCE)
    assert_almost_equal(
        slid[0].x, Float32(0.495 / sqrt(Float64(2))), atol=TOLERANCE
    )
    assert_almost_equal(slid[0].y, 0, atol=TOLERANCE)
    assert_almost_equal(slid[1].x, 0, atol=TOLERANCE)
    assert_almost_equal(slid[1].y, 0, atol=TOLERANCE)


def a_checker(mipmapped: Bool) raises -> Texture:
    """Return a 64 by 64 image of one-texel black and white squares, as
    data. Every level of its chain below the first is one gray."""
    var pixels = List[UInt8]()
    for y in range(64):
        for x in range(64):
            var shade = UInt8(255) if (x + y) % 2 == 0 else UInt8(0)
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(255)
    return Texture(64, 64, pixels^, REPEAT, NEAREST, LINEAR, mipmapped, IGNORED)


def matcap_corner(
    x: Float32, y: Float32, normal: Vector3, matcap: TextureId
) -> RasterVertex:
    """Return a white matcap corner facing `normal`, at the origin."""
    return RasterVertex(
        x,
        y,
        0.5,
        1,
        FloatColor(1, 1, 1),
        normal=normal,
        kind=MATCAP,
        matcap=matcap,
    )


def test_a_matcap_with_a_chain_is_read_down_it_by_its_own_footprint() raises:
    # The normal sweeps from left to right over eight pixels, so the
    # lookup crosses the 64 texels about eight to a pixel. A chain reads
    # its gray level there; the same image with one level reads a texel.
    var lighting = Lighting(Scene(), Layers.all(), Vector3(0, 0, 4))
    var left = Vector3(-1, 0, 0.2)
    var right = Vector3(1, 0, 0.2)
    for mipmapped in [True, False]:
        var textures = TextureStore()
        var ball = textures.add(a_checker(mipmapped))
        var target = RenderTarget(8, 8, Color(0, 0, 0))
        rasterize_shaded(
            matcap_corner(0, 0, left, ball),
            matcap_corner(8, 0, right, ball),
            matcap_corner(0, 8, left, ball),
            target,
            SHADE_TEXTURE,
            textures,
            lighting,
        )
        for x in range(1, 6):
            var seen = target.color_at(x, 1).r
            if mipmapped:
                assert_almost_equal(seen, 0.5, atol=Float64(0.01))
            else:
                assert_true(seen == 0 or seen == 1, "a texel was filtered")


def a_stripe_matcap(anisotropy: Int) raises -> Texture:
    """Return a 64 by 64 image of upright stripes, two texels white and
    one black, as data, with one level and an anisotropy."""
    var pixels = List[UInt8]()
    for _ in range(64):
        for x in range(64):
            var shade = UInt8(255) if x % 3 != 2 else UInt8(0)
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(255)
    var image = Texture(
        64, 64, pixels^, REPEAT, NEAREST, LINEAR, False, IGNORED
    )
    image.anisotropy = anisotropy
    return image^


def test_a_matcap_with_one_level_takes_its_taps_along_its_footprint() raises:
    # One level and an anisotropy of four: the lookup's footprint is long
    # across the stripes, and the taps along it average white and black.
    # With an anisotropy of one, each fragment reads one texel.
    var lighting = Lighting(Scene(), Layers.all(), Vector3(0, 0, 4))
    var left = Vector3(-1, 0, 0.2)
    var right = Vector3(1, 0, 0.2)
    for anisotropy in [4, 1]:
        var textures = TextureStore()
        var ball = textures.add(a_stripe_matcap(anisotropy))
        var target = RenderTarget(8, 8, Color(0, 0, 0))
        rasterize_shaded(
            matcap_corner(0, 0, left, ball),
            matcap_corner(8, 0, right, ball),
            matcap_corner(0, 8, left, ball),
            target,
            SHADE_TEXTURE,
            textures,
            lighting,
        )
        var mixed = 0
        for x in range(6):
            var seen = target.color_at(x, 1).r
            if seen > 0.01 and seen < 0.99:
                mixed += 1
        if anisotropy == 4:
            assert_true(mixed > 0, "no fragment took more than one tap")
        else:
            assert_equal(mixed, 0)


# --- the alpha test's ramp under alpha to coverage ----------------------------


def flat_corner(
    x: Float32,
    y: Float32,
    alpha: Float32,
    state: RasterState,
    test: Float32 = 0.5,
) -> RasterVertex:
    """Return a white unlit corner that blends, with an alpha test. Over
    a black target, the red a fragment leaves is the alpha it kept."""
    return RasterVertex(
        x,
        y,
        0.5,
        1,
        FloatColor(1, 1, 1, alpha),
        blend=BLEND,
        kind=BASIC,
        alpha_test=test,
        state=state,
    )


def faded_triangle(
    mut target: RenderTarget, state: RasterState, uv_view: Bool = False
) raises:
    """Draw a triangle whose alpha rises from zero at the left to one at
    the right: `(x + 0.5) / 32` at a pixel center."""
    var a = flat_corner(0, 0, 0, state)
    var b = flat_corner(Float32(SIDE), 0, 1, state)
    var c = flat_corner(0, Float32(SIDE), 0, state)
    if uv_view:
        rasterize_shaded(a, b, c, target, SHADE_UV)
    else:
        rasterize_shaded(a, b, c, target)


def test_an_alpha_test_is_a_ramp_under_alpha_to_coverage() raises:
    # `fwidth` of the alpha is 1 / 32. With a test of one half the ramp is
    # `smoothstep(0.5, 0.53125, alpha)`: zero at column 15, one half at
    # column 16, where the alpha is 0.515625, and one from column 17 on.
    var target = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    faded_triangle(target, RasterState(alpha_to_coverage=True))
    for y in range(8):
        # Below the test: discarded.
        assert_equal(target.color_at(15, y).r, Float32(0))
        # On the ramp: the coverage reads one half, and a covered sample
        # blends by one half.
        if alpha_covers(0.5, 16, y):
            assert_almost_equal(target.color_at(16, y).r, 0.5, atol=TOLERANCE)
        else:
            assert_equal(target.color_at(16, y).r, Float32(0))
        # Past the ramp: every sample is covered, and the alpha is one.
        assert_almost_equal(target.color_at(17, y).r, 1, atol=TOLERANCE)
        assert_almost_equal(target.color_at(20, y).r, 1, atol=TOLERANCE)
    # Half the samples of column 16 are covered.
    var kept = 0
    for y in range(8):
        if target.color_at(16, y).r > 0:
            kept += 1
    assert_equal(kept, 4)


def test_an_alpha_test_alone_keeps_its_hard_edge() raises:
    # Without alpha to coverage the test discards below one half and
    # leaves the alpha above it alone.
    var target = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    faded_triangle(target, RasterState())
    assert_equal(target.color_at(15, 2).r, Float32(0))
    assert_almost_equal(target.color_at(16, 2).r, 0.515625, atol=TOLERANCE)
    assert_almost_equal(target.color_at(20, 2).r, 0.640625, atol=TOLERANCE)
    # The uv view tests nothing and ramps nothing.
    var uv = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    faded_triangle(uv, RasterState(alpha_to_coverage=True), uv_view=True)
    assert_true(uv.is_data(2, 2))


def test_an_alpha_with_no_width_takes_the_hard_step() raises:
    # One alpha everywhere: the ramp is the hard step, which keeps an
    # alpha above the test whole and discards one at the test.
    var state = RasterState(alpha_to_coverage=True)
    for pair in [(Float32(0.6), Float32(1)), (Float32(0.5), Float32(0))]:
        var target = RenderTarget(8, 8, Color(0, 0, 0))
        rasterize_shaded(
            flat_corner(-1, -1, pair[0], state),
            flat_corner(24, -1, pair[0], state),
            flat_corner(-1, 24, pair[0], state),
            target,
        )
        for y in range(4):
            for x in range(4):
                assert_almost_equal(
                    target.color_at(x, y).r, pair[1], atol=TOLERANCE
                )


def a_fade(alpha: Bool) raises -> Texture:
    """Return a two-texel image whose alpha is zero on the left and one on
    the right, filtered, or whose green is when `alpha` is False: an
    alpha map."""
    var pixels: List[UInt8] = [255, 0, 255, 0, 255, 255, 255, 255]
    if not alpha:
        pixels = [0, 0, 0, 255, 0, 255, 0, 255]
    return Texture(
        2,
        1,
        pixels^,
        CLAMP,
        BILINEAR,
        LINEAR,
        False,
        COVERAGE if alpha else IGNORED,
    )


def test_the_ramp_reads_the_maps_at_the_pixels_beside() raises:
    # The corners' alpha is one and the map's rises across the triangle:
    # bilinear between two texels, it is `2 u - 0.5` from a quarter to
    # three quarters. With `u` from zero to one over 32 pixels the alpha
    # rises by 1 / 16 a pixel, and the ramp is
    # `smoothstep(0.5, 0.5625, alpha)`.
    for by_alpha_map in [False, True]:
        var textures = TextureStore()
        var fade = textures.add(a_fade(not by_alpha_map))
        var state = RasterState(alpha_to_coverage=True)
        var a = flat_corner(0, 0, 1, state)
        var b = flat_corner(Float32(SIDE), 0, 1, state)
        var c = flat_corner(0, Float32(SIDE), 1, state)
        b.u = 1
        if by_alpha_map:
            a.alpha_map = fade
            b.alpha_map = fade
            c.alpha_map = fade
        else:
            a.texture = fade
            b.texture = fade
            c.texture = fade
        var target = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
        rasterize_shaded(a, b, c, target, SHADE_TEXTURE, textures)
        # Column 16: alpha 0.53125, halfway up the ramp. Column 15:
        # alpha 0.46875, discarded. Column 17: alpha 0.59375, whole.
        for y in range(8):
            assert_equal(target.color_at(15, y).r, Float32(0))
            if alpha_covers(0.5, 16, y):
                assert_almost_equal(
                    target.color_at(16, y).r, 0.5, atol=Float64(1e-4)
                )
            else:
                assert_equal(target.color_at(16, y).r, Float32(0))
            assert_almost_equal(target.color_at(17, y).r, 1, atol=TOLERANCE)


def test_a_point_ramps_its_alpha_test_by_its_map() raises:
    # A point eight pixels across at (8, 8) covers columns 4 to 11. Its
    # map's alpha is `2 u - 0.5` held from zero to one, with
    # `u = (i + 0.5) / 8` at its column i: 0.375 at the fourth, 0.625 at
    # the fifth, 0.875 at the sixth and one after. `fwidth` is 0.25 on
    # the rise, so the fifth column is halfway up the ramp.
    var textures = TextureStore()
    var fade = textures.add(a_fade(True))
    var state = RasterState(alpha_to_coverage=True)
    var dot = flat_corner(8, 8, 1, state)
    dot.point_size = 8
    dot.texture = fade
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_point(dot, target, SHADE_TEXTURE, textures)
    for y in range(4, 12):
        assert_equal(target.color_at(7, y).r, Float32(0))
        if alpha_covers(0.5, 8, y):
            assert_almost_equal(
                target.color_at(8, y).r, 0.5, atol=Float64(1e-4)
            )
        else:
            assert_equal(target.color_at(8, y).r, Float32(0))
        assert_almost_equal(target.color_at(9, y).r, 1, atol=TOLERANCE)
        assert_almost_equal(target.color_at(11, y).r, 1, atol=TOLERANCE)
    # Without alpha to coverage the test is hard and the alpha is kept.
    var hard = RenderTarget(16, 16, Color(0, 0, 0))
    var plain = flat_corner(8, 8, 1, RasterState())
    plain.point_size = 8
    plain.texture = fade
    rasterize_point(plain, hard, SHADE_TEXTURE, textures)
    assert_equal(hard.color_at(7, 6).r, Float32(0))
    assert_almost_equal(hard.color_at(8, 6).r, 0.625, atol=Float64(1e-4))
    # A point with no map has one alpha: the hard step, as a triangle.
    var bare = RenderTarget(16, 16, Color(0, 0, 0))
    var whole = flat_corner(8, 8, 0.6, state)
    whole.point_size = 8
    rasterize_point(whole, bare, SHADE_TEXTURE, textures)
    assert_almost_equal(bare.color_at(8, 6).r, 1, atol=TOLERANCE)
    var lit = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_point(whole, lit)
    assert_almost_equal(lit.color_at(8, 6).r, 1, atol=TOLERANCE)
    # A point with no alpha test takes no ramp. Under the coverage its
    # own alpha of one half keeps half of its 64 samples, and without the
    # coverage it blends by one half.
    var untested = RenderTarget(16, 16, Color(0, 0, 0))
    var half = flat_corner(8, 8, 0.5, state, 0)
    half.point_size = 8
    rasterize_point(half, untested)
    var kept = 0
    for y in range(4, 12):
        for x in range(4, 12):
            if untested.color_at(x, y).r > 0:
                kept += 1
    assert_equal(kept, 32)
    var blended = RenderTarget(16, 16, Color(0, 0, 0))
    var faint = flat_corner(8, 8, 0.5, RasterState(), 0)
    faint.point_size = 8
    rasterize_point(faint, blended)
    assert_almost_equal(blended.color_at(8, 6).r, 0.5, atol=TOLERANCE)


def a_program(sets_opacity: Bool) raises -> NodeProgramStore:
    """Return a store whose one program sets the color to white, and the
    opacity to 0.6 when asked. Without that it leaves the alpha alone."""
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.vec3(1, 1, 1))
    if sets_opacity:
        graph.set_output(OPACITY_NODE, graph.float(0.6))
    var store = NodeProgramStore()
    _ = store.add(graph.compile())
    return store^


def test_an_opacity_node_has_no_width_on_a_triangle() raises:
    var state = RasterState(alpha_to_coverage=True)
    var a = flat_corner(0, 0, 0, state)
    var b = flat_corner(Float32(SIDE), 0, 1, state)
    var c = flat_corner(0, Float32(SIDE), 0, state)
    a.nodes = NodeProgramId(0)
    b.nodes = NodeProgramId(0)
    c.nodes = NodeProgramId(0)
    # The node's 0.6 replaces the corners' alpha everywhere. It has no
    # width, so the hard step keeps it whole, where the corners' own
    # alpha is below the test.
    var set = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    rasterize_shaded(a, b, c, set, programs=a_program(True))
    assert_almost_equal(set.color_at(2, 2).r, 1, atol=TOLERANCE)
    assert_almost_equal(set.color_at(16, 2).r, 1, atol=TOLERANCE)
    # A program that sets no opacity leaves the ramp of the corners'
    # alpha: nothing at column 15, and all of it at column 17.
    var kept = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    rasterize_shaded(a, b, c, kept, programs=a_program(False))
    assert_equal(kept.color_at(2, 2).r, Float32(0))
    assert_equal(kept.color_at(15, 2).r, Float32(0))
    assert_almost_equal(kept.color_at(17, 2).r, 1, atol=TOLERANCE)


def test_an_opacity_node_has_no_width_on_a_point() raises:
    var textures = TextureStore()
    var fade = textures.add(a_fade(True))
    var dot = flat_corner(8, 8, 1, RasterState(alpha_to_coverage=True))
    dot.point_size = 8
    dot.texture = fade
    dot.nodes = NodeProgramId(0)
    # The node's 0.6 replaces the map's alpha: the whole square is kept.
    var set = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_point(dot, set, SHADE_TEXTURE, textures, programs=a_program(True))
    assert_almost_equal(set.color_at(4, 6).r, 1, atol=TOLERANCE)
    assert_almost_equal(set.color_at(11, 6).r, 1, atol=TOLERANCE)
    # With no opacity node the map's ramp is back: its fourth column is
    # below the test and its sixth is above the ramp.
    var kept = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_point(
        dot, kept, SHADE_TEXTURE, textures, programs=a_program(False)
    )
    assert_equal(kept.color_at(7, 6).r, Float32(0))
    assert_almost_equal(kept.color_at(9, 6).r, 1, atol=TOLERANCE)


def test_a_point_ramps_its_alpha_test_by_its_alpha_map() raises:
    # The alpha map's green rises across the point as the map's alpha
    # does in the test above, and the ramp reads it the same way.
    var textures = TextureStore()
    var fade = textures.add(a_fade(False))
    var dot = flat_corner(8, 8, 1, RasterState(alpha_to_coverage=True))
    dot.point_size = 8
    dot.alpha_map = fade
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_point(dot, target, SHADE_TEXTURE, textures)
    for y in range(4, 12):
        assert_equal(target.color_at(7, y).r, Float32(0))
        if alpha_covers(0.5, 8, y):
            assert_almost_equal(
                target.color_at(8, y).r, 0.5, atol=Float64(1e-4)
            )
        else:
            assert_equal(target.color_at(8, y).r, Float32(0))
        assert_almost_equal(target.color_at(9, y).r, 1, atol=TOLERANCE)


# --- a wide line's edge ramp ---------------------------------------------------


def ramp_corner(
    x: Float32, y: Float32, u: Float32, ramp: EdgeRamp
) -> RasterVertex:
    """Return a white unlit corner that blends, with a coordinate across
    and an edge ramp."""
    return RasterVertex(
        x,
        y,
        0.5,
        1,
        FloatColor(1, 1, 1, 1),
        u,
        0,
        blend=BLEND,
        kind=BASIC,
        state=RasterState(edge_ramp=ramp),
    )


def ramped(ramp: EdgeRamp, uv_view: Bool = False) raises -> RenderTarget:
    """Draw a triangle whose first coordinate rises from zero to two
    across 32 pixels, `(x + 0.5) / 16` at a pixel center, under a ramp."""
    var target = RenderTarget(SIDE, SIDE, Color(0, 0, 0))
    var a = ramp_corner(0, 0, 0, ramp)
    var b = ramp_corner(Float32(SIDE), 0, 2, ramp)
    var c = ramp_corner(0, Float32(SIDE), 0, ramp)
    if uv_view:
        rasterize_shaded(a, b, c, target, SHADE_UV)
    else:
        rasterize_shaded(a, b, c, target)
    return target^


def test_a_disc_ramp_fades_a_triangle_across_its_rim() raises:
    var target = ramped(DISC_EDGE_RAMP)
    for x in range(12, 20):
        var u = (Float64(x) + 0.5) / 16
        var beside = (Float64(x) + 1.5) / 16
        var width = beside * beside - u * u
        var alpha = 1 - step_between(1 - width, 1 + width, u * u)
        assert_almost_equal(
            target.color_at(x, 2).r, Float32(alpha), atol=Float64(1e-4)
        )
    # Whole inside, gone outside, and partly there on each side of the rim.
    assert_almost_equal(target.color_at(12, 2).r, 1, atol=TOLERANCE)
    assert_equal(target.color_at(19, 2).r, Float32(0))
    assert_true(target.color_at(15, 2).r > target.color_at(16, 2).r)
    assert_true(target.color_at(16, 2).r > 0)


def test_a_capsule_ramp_fades_a_triangle_across_its_outline() raises:
    var target = ramped(CAPSULE_EDGE_RAMP)
    # Half the coordinate is `(x + 0.5) / 32`, one part in 32 a pixel.
    assert_almost_equal(target.color_at(14, 2).r, 1, atol=TOLERANCE)
    assert_almost_equal(target.color_at(15, 2).r, 0.84375, atol=Float64(1e-4))
    assert_almost_equal(target.color_at(16, 2).r, 0.15625, atol=Float64(1e-4))
    assert_equal(target.color_at(17, 2).r, Float32(0))


def test_no_ramp_and_the_uv_view_leave_the_alpha_alone() raises:
    var plain = ramped(NO_EDGE_RAMP)
    assert_almost_equal(plain.color_at(20, 2).r, 1, atol=TOLERANCE)
    var uv = ramped(DISC_EDGE_RAMP, uv_view=True)
    assert_true(uv.is_data(20, 2))


def test_a_state_carries_its_edge_ramp_and_refuses_a_wrong_one() raises:
    var state = RasterState(edge_ramp=CAPSULE_EDGE_RAMP)
    assert_true(state.is_valid())
    # Bits 27 and 28 of the packed word, and nothing else.
    assert_equal(state.ops_word() ^ RasterState().ops_word(), 2 << 27)
    assert_equal(
        RasterState(edge_ramp=DISC_EDGE_RAMP).ops_word()
        ^ RasterState().ops_word(),
        1 << 27,
    )
    assert_true(state.ops_word() < (1 << 31))
    var back = RasterState.unpacked(state.ops_word(), state.stencil_word())
    assert_true(back.edge_ramp == CAPSULE_EDGE_RAMP)
    assert_true(back == state)
    assert_true(
        RasterState.unpacked(
            RasterState().ops_word(), RasterState().stencil_word()
        ).edge_ramp
        == NO_EDGE_RAMP
    )
    # A ramp that is none of the three is refused where a state is checked.
    var wrong = RasterState(edge_ramp=EdgeRamp(3))
    assert_false(wrong.is_valid())
    with assert_raises(contains="an edge ramp"):
        wrong.check()
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    with assert_raises():
        rasterize_shaded(
            ramp_corner(0, 0, 0, EdgeRamp(3)),
            ramp_corner(8, 0, 0, EdgeRamp(3)),
            ramp_corner(0, 8, 0, EdgeRamp(3)),
            target,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
