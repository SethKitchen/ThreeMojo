# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.tsl_utils`: triplanar mapping, sprite sheets, the
oscillators, `remapClamp`, `rotate`, the equirectangular and matcap
coordinates, and the normal packings.

Each expected value is worked out from three.js's formula, and read back
through the compiled program, so a test checks the builder and the
interpreter together.
"""

from materials.nodes import (
    FRAGMENT_NODE,
    NODE_FLOAT,
    NODE_VEC2,
    NODE_VEC3,
    NodeContext,
    NodeGraph,
    NodeInputs,
    NodeProgram,
    NodeRef,
    NodeSource,
    ProgramSource,
    run_nodes,
)
from materials.tsl_utils import (
    equirect_direction,
    equirect_uv,
    matcap_uv,
    osc_sawtooth,
    osc_sine,
    osc_square,
    osc_triangle,
    pack_normal_to_rgb,
    position_world_direction,
    remap_clamp,
    rotate,
    spritesheet_uv,
    triplanar_texture,
    triplanar_textures,
    unpack_normal,
    unpack_rgb_to_normal,
)
from math.euler import EulerOrder, XYZ, YZX, ZYX
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from render.texture_store import TextureId
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import SECOND, Duration

comptime Lanes = SIMD[DType.float32, 4]


def fragment(textured: Bool = False) -> NodeInputs:
    """Return a fragment at (1, 2, 3), facing `+z`, at the coordinate
    (0.25, 0.75)."""
    return NodeInputs(
        0.25,
        0.75,
        Vector3(1, 2, 3),
        Vector3(0, 0, 1),
        Vector3(0.1, 0.2, 0.3),
        Vector3(0, 0, 0),
        textured,
    )


def shown(mut g: NodeGraph, node: NodeRef) raises -> NodeProgram:
    """Return the program that shows a node, padded to a `vec4`, as the
    fragment output."""
    var type = g.type_of(node)
    var padded = node
    if type == NODE_FLOAT:
        padded = g.join([node, g.vec3(0, 0, 0)])
    elif type == NODE_VEC2:
        padded = g.join([node, g.vec2(0, 0)])
    elif type == NODE_VEC3:
        padded = g.join([node, g.float(0)])
    g.set_output(FRAGMENT_NODE, padded)
    return g.compile()


def value_of(
    mut g: NodeGraph, node: NodeRef, time: Float32 = 0
) raises -> Lanes:
    """Return a node's value at `fragment`, at a time, from the origin."""
    var program = shown(g, node)
    program.set_frame(Duration(time, SECOND), Matrix4())
    return run_nodes(
        ProgramSource(Pointer(to=program)), FRAGMENT_NODE, fragment()
    )


def assert_near(got: Lanes, x: Float32, y: Float32, z: Float32 = 0) raises:
    """Assert the first three lanes to 1e-5."""
    assert_almost_equal(got[0], x, atol=1e-5)
    assert_almost_equal(got[1], y, atol=1e-5)
    assert_almost_equal(got[2], z, atol=1e-5)


struct Probe(NodeSource):
    """A `NodeSource` that reads a texture as its coordinate, its slot and
    one, to see where a graph reads each texture."""

    var code: List[Float32]

    def __init__(out self, program: NodeProgram):
        """Copy the program's floats."""
        self.code = program.code.copy()

    def word(self, at: Int) -> Float32:
        """Return one float."""
        return self.code[at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return the coordinate and the slot as a color."""
        return FloatColor(u, v, Float32(slot), 1.0)

    def sample_level(
        self, slot: Int, u: Float32, v: Float32, level: Float32
    ) -> FloatColor:
        """Return the coordinate and the slot as a color."""
        return FloatColor(u, v, Float32(slot), 1.0)

    def fetch(self, slot: Int, x: Int, y: Int, level: Int) -> FloatColor:
        """Return opaque white."""
        return FloatColor(1.0, 1.0, 1.0, 1.0)

    def size(self, slot: Int, level: Int) -> Lanes:
        """Return a size of one."""
        return Lanes(1, 1, 0, 0)

    def shares(self, context: NodeContext) -> Lanes:
        """Return all the weight on the first corner."""
        return Lanes(1, 0, 0, 0)

    def frag_coord(self, context: NodeContext) -> Lanes:
        """Return no place."""
        return Lanes(0, 0, 0, 1)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return the fragment as every corner."""
        return fragment(True)


def sampled(mut g: NodeGraph, node: NodeRef) raises -> Lanes:
    """Return a node's value at `fragment`, with its textures read by
    `Probe`."""
    var program = shown(g, node)
    program.set_frame(Duration(0.0, SECOND), Matrix4())
    return run_nodes(Probe(program), FRAGMENT_NODE, fragment(True))


def test_triplanar_blends_three_projections_by_the_normal() raises:
    var g = NodeGraph()
    var one = g.texture_uniform("x", TextureId(1))
    var two = g.texture_uniform("y", TextureId(2))
    var three = g.texture_uniform("z", TextureId(3))
    # The normal (1, 2, 2) blends by (0.2, 0.4, 0.4). The textures read
    # (y, z), (z, x) and (x, y) of the position, times two.
    var blended = triplanar_textures(
        g,
        one,
        two,
        three,
        g.float(2),
        g.vec3(1, 2, 3),
        g.vec3(1, 2, 2),
    )
    var got = sampled(g, blended)
    assert_near(got, 4.0, 3.6, 2.2)
    assert_almost_equal(got[3], 1, atol=1e-6)
    # One texture read along all three axes.
    var alone = triplanar_texture(
        g,
        one,
        scale=g.float(2),
        position=g.vec3(1, 2, 3),
        normal=g.vec3(1, 2, 2),
    )
    assert_near(sampled(g, alone), 4.0, 3.6, 1.0)
    # By default: the world position and normal, at a scale of one. The
    # fragment faces `+z`, so only the texture along `z` is read, at x, y.
    assert_near(sampled(g, triplanar_textures(g, one, two, three)), 1, 2, 3)


def test_triplanar_refuses_what_is_not_its_type() raises:
    var g = NodeGraph()
    var map = g.texture_uniform("map", TextureId(0))
    with assert_raises(
        contains="triplanarTextures reads a texture, not a float"
    ):
        _ = triplanar_textures(g, g.float(1))
    with assert_raises(
        contains="triplanarTextures reads a texture, not a vec2"
    ):
        _ = triplanar_textures(g, map, g.vec2(1, 2))
    with assert_raises(
        contains="triplanarTextures reads a texture, not a vec3"
    ):
        _ = triplanar_textures(g, map, map, g.vec3(1, 2, 3))
    with assert_raises(contains="scale reads a float, not a vec2"):
        _ = triplanar_textures(g, map, scale=g.vec2(1, 2))
    with assert_raises(contains="position reads a vec3, not a vec2"):
        _ = triplanar_textures(g, map, position=g.vec2(1, 2))
    with assert_raises(contains="normal reads a vec3, not a float"):
        _ = triplanar_textures(g, map, normal=g.float(1))


def test_a_sprite_sheet_counts_frames_from_the_top_left() raises:
    var g = NodeGraph()
    var count = g.vec2(4, 2)
    var at = g.vec2(0.25, 0.75)
    # Frame 5 of a four by two sheet: column one, row zero from the bottom.
    assert_near(
        value_of(g, spritesheet_uv(g, count, at, g.float(5))), 0.3125, 0.375
    )
    assert_near(
        value_of(g, spritesheet_uv(g, count, at, g.float(1))), 0.3125, 0.875
    )
    # Frame 9 wraps round to frame 1.
    assert_near(
        value_of(g, spritesheet_uv(g, count, at, g.float(9.5))), 0.3125, 0.875
    )
    # By default: `uv()` and frame zero, the top left.
    assert_near(value_of(g, spritesheet_uv(g, count)), 0.0625, 0.875)
    with assert_raises(contains="count reads a vec2, not a float"):
        _ = spritesheet_uv(g, g.float(4))
    with assert_raises(contains="uv reads a vec2, not a vec3"):
        _ = spritesheet_uv(g, count, g.vec3(1, 2, 3))
    with assert_raises(contains="frame reads a float, not a vec2"):
        _ = spritesheet_uv(g, count, at, g.vec2(1, 2))


def test_the_oscillators_have_a_period_of_one() raises:
    var g = NodeGraph()
    assert_almost_equal(value_of(g, osc_sine(g, g.float(0)))[0], 0, atol=1e-6)
    assert_almost_equal(
        value_of(g, osc_sine(g, g.float(0.25)))[0], 0.5, atol=1e-6
    )
    assert_almost_equal(value_of(g, osc_sine(g, g.float(0.5)))[0], 1, atol=1e-6)
    # With no input they read the time.
    assert_almost_equal(
        value_of(g, osc_sine(g), time=0.1)[0], 0.0954915, atol=1e-6
    )
    assert_equal(value_of(g, osc_square(g, g.float(0.3)))[0], 0)
    assert_equal(value_of(g, osc_square(g, g.float(2.7)))[0], 1)
    assert_equal(value_of(g, osc_square(g), time=0.6)[0], 1)
    assert_equal(value_of(g, osc_triangle(g, g.float(0)))[0], 0)
    assert_equal(value_of(g, osc_triangle(g, g.float(0.5)))[0], 1)
    assert_almost_equal(
        value_of(g, osc_triangle(g), time=0.25)[0], 0.5, atol=1e-6
    )
    assert_almost_equal(
        value_of(g, osc_sawtooth(g, g.float(1.25)))[0], 0.25, atol=1e-6
    )
    assert_almost_equal(
        value_of(g, osc_sawtooth(g), time=3.75)[0], 0.75, atol=1e-6
    )
    with assert_raises(contains="An oscillator reads a float, not a vec2"):
        _ = osc_sine(g, g.vec2(1, 2))


def test_remap_clamp_holds_the_answer_inside_the_second_range() raises:
    var g = NodeGraph()
    var low = g.float(0)
    var high = g.float(10)
    assert_equal(value_of(g, remap_clamp(g, g.float(5), low, high))[0], 0.5)
    assert_equal(value_of(g, remap_clamp(g, g.float(-5), low, high))[0], 0)
    var out_low = g.float(2)
    var out_high = g.float(4)
    assert_near(
        value_of(
            g, remap_clamp(g, g.vec3(15, -5, 2.5), low, high, out_low, out_high)
        ),
        4,
        2,
        2.5,
    )


def test_rotate_turns_a_vec2_and_a_vec3() raises:
    var g = NodeGraph()
    assert_near(
        value_of(g, rotate(g, g.vec2(1, 2), g.float(0.5))),
        -0.0812685,
        2.2345907,
    )
    assert_near(
        value_of(g, rotate(g, g.vec2(1, 0), g.float(Float32(pi / 2)))), 0, 1
    )
    var p = g.vec3(1, 2, 3)
    var angles = g.vec3(0.3, 0.5, 0.7)
    # `XYZ` is the product Rx * Ry * Rz, as three.js multiplies them.
    assert_near(
        value_of(g, rotate(g, p, angles)), 0.9787804, 1.2245952, 3.3974043
    )
    assert_near(
        value_of(g, rotate(g, p, angles, ZYX)), 1.2791088, 2.4163637, 2.5544212
    )
    assert_near(
        value_of(g, rotate(g, p, angles, YZX)), 1.7496239, 1.4275020, 2.9834634
    )


def test_rotate_refuses_a_wrong_order_or_type() raises:
    var g = NodeGraph()
    with assert_raises(contains="order must name three different axes"):
        _ = rotate(g, g.vec3(1, 2, 3), g.vec3(0, 0, 0), EulerOrder(0, 0, 1))
    with assert_raises(contains="rotate of a vec2 reads a float, not a vec3"):
        _ = rotate(g, g.vec2(1, 2), g.vec3(0, 0, 0))
    with assert_raises(contains="rotate reads a vec3, not a vec4"):
        _ = rotate(g, g.vec4(1, 2, 3, 4), g.vec3(0, 0, 0))
    with assert_raises(contains="rotate of a vec3 reads a vec3, not a float"):
        _ = rotate(g, g.vec3(1, 2, 3), g.float(0))
    _ = rotate(g, g.vec3(1, 2, 3), g.vec3(0, 0, 0), XYZ)


def test_the_equirectangular_coordinate_and_its_inverse() raises:
    var g = NodeGraph()
    assert_near(value_of(g, equirect_uv(g, g.vec3(0, 0, 1))), 0.75, 0.5)
    assert_near(value_of(g, equirect_uv(g, g.vec3(1, 0, 0))), 0.5, 0.5)
    assert_near(
        value_of(g, equirect_uv(g, g.vec3(0.70710677, 0.70710677, 0))),
        0.5,
        0.75,
    )
    # By default: from the camera, at the origin, to the fragment.
    assert_near(value_of(g, equirect_uv(g)), 0.6987918, 0.6795085)
    var toward = value_of(g, position_world_direction(g))
    assert_near(toward, 0.26726124, 0.5345225, 0.8017837)
    # The direction of a coordinate, and back.
    var d = g.vec3(0.26726124, 0.5345225, 0.8017837)
    assert_near(
        value_of(g, equirect_direction(g, equirect_uv(g, d))),
        0.26726124,
        0.5345225,
        0.8017837,
    )
    # By default: `uv()`, here (0.25, 0.75).
    assert_near(value_of(g, equirect_direction(g)), 0, 0.70710677, -0.70710677)
    with assert_raises(contains="equirectUV reads a vec3, not a vec2"):
        _ = equirect_uv(g, g.vec2(1, 2))
    with assert_raises(contains="equirectDirection reads a vec2, not a vec3"):
        _ = equirect_direction(g, g.vec3(1, 2, 3))


def test_a_matcap_is_read_by_the_view_normal() raises:
    var g = NodeGraph()
    assert_near(value_of(g, matcap_uv(g)), 0.65653274, 0.24898919)


def test_a_normal_packs_to_a_color_and_back() raises:
    var g = NodeGraph()
    assert_near(value_of(g, pack_normal_to_rgb(g, g.vec3(0, -1, 1))), 0.5, 0, 1)
    assert_near(
        value_of(g, unpack_rgb_to_normal(g, g.vec3(0.5, 0, 1))), 0, -1, 1
    )
    assert_near(value_of(g, unpack_normal(g, g.vec2(0.6, 0))), 0.6, 0, 0.8)
    assert_near(value_of(g, unpack_normal(g, g.vec2(1, 1))), 1, 1, 0)
    with assert_raises(contains="unpackNormal reads a vec2, not a vec3"):
        _ = unpack_normal(g, g.vec3(1, 2, 3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
