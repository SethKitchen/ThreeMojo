# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.nodes`: building a node graph, compiling it, and
the interpreter both rasterizers run.

Each node's answer is worked out by hand from GLSL's definition of the
function it ports, and read back through the compiled program, so a test
checks the builder, the layout and the interpreter together.
"""

from materials.nodes import (
    AO_NODE,
    AT_FRAGMENT,
    AT_HERE,
    AT_RIGHT,
    AT_UP,
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    CORNER_C,
    DEPTH_NODE,
    EMISSIVE_NODE,
    INSTRUCTION_FLOATS,
    MASK_NODE,
    MAX_GRAPH_NODES,
    MAX_INSTRUCTIONS,
    MAX_LOOP_COUNT,
    MAX_REGISTERS,
    NODE_ADD,
    NODE_FLOAT,
    NODE_MAT3,
    NODE_MAT4,
    NODE_OUTPUT_COUNT,
    NODE_SAMPLER,
    NODE_SAMPLER_CUBE,
    NODE_SWIZZLE,
    NODE_VEC2,
    NODE_VEC3,
    NODE_VEC4,
    NORMAL_NODE,
    NO_NODES,
    OPACITY_NODE,
    OUTPUT_NODE,
    POSITION_NODE,
    PROGRAM_HEADER,
    PROGRAM_TIME,
    Fn,
    NodeContext,
    NodeGraph,
    NodeInputs,
    NodeKind,
    NodeOutput,
    NodeProgram,
    NodeProgramId,
    NodeProgramStore,
    NodeRef,
    NodeSource,
    NodeVar,
    ProgramSource,
    ValueType,
    cell_noise,
    cell_noise_vec3,
    has_output,
    here_inputs,
    moved_position,
    node_attributes,
    node_depth,
    offset_normal,
    perlin_noise,
    perlin_noise_vec3,
    perspective_shares,
    run_nodes,
    worley_noise,
)
from math.matrix3 import Matrix3
from math.vector4 import Vector4
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.srgb import srgb_to_linear
from render.cube_texture_store import CubeTextureId
from render.volume_texture_store import Data3DTextureId, DataArrayTextureId
from render.texture_store import NO_TEXTURE, TextureId
from std.math import cos, isnan, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND, Duration

comptime Lanes = SIMD[DType.float32, 4]


def inputs(textured: Bool = False) -> NodeInputs:
    """Return a fragment with every attribute a different number."""
    return NodeInputs(
        0.25,
        0.75,
        Vector3(1, 2, 3),
        Vector3(0, 0, 1),
        Vector3(0.1, 0.2, 0.3),
        Vector3(0.5, 0.6, 0.7),
        textured,
    )


def color_of(
    graph: NodeGraph, textured: Bool = False, time: Float32 = 0
) raises -> Lanes:
    """Return what the graph's color output computes for `inputs`."""
    var program = graph.compile()
    program.set_frame(Duration(time, SECOND), Matrix4())
    return run_nodes(
        ProgramSource(Pointer(to=program)), COLOR_NODE, inputs(textured)
    )


def vec3_of(mut graph: NodeGraph, node: NodeRef) raises -> Lanes:
    """Return a `vec3` node's value, through the color output."""
    graph.set_output(COLOR_NODE, node)
    return color_of(graph)


def float_of(mut graph: NodeGraph, node: NodeRef) raises -> Float32:
    """Return a `float` node's value, through the opacity output."""
    graph.set_output(OPACITY_NODE, node)
    var program = graph.compile()
    return run_nodes(
        ProgramSource(Pointer(to=program)), OPACITY_NODE, inputs()
    )[0]


def assert_lanes(got: Lanes, x: Float32, y: Float32, z: Float32) raises:
    """Assert the first three lanes."""
    assert_almost_equal(got[0], x, atol=1e-6)
    assert_almost_equal(got[1], y, atol=1e-6)
    assert_almost_equal(got[2], z, atol=1e-6)


# --- the types ----------------------------------------------------------------


def test_the_types_say_which_values_they_can_hold() raises:
    assert_true(NODE_FLOAT.is_valid())
    assert_true(NODE_VEC4.is_valid())
    assert_false(ValueType(0).is_valid())
    assert_false(ValueType(5).is_valid())
    assert_true(NODE_MAT3.is_valid())
    assert_true(NODE_MAT4.is_valid())
    assert_true(NODE_SAMPLER.is_valid())
    assert_true(NODE_SAMPLER_CUBE.is_valid())
    assert_equal(NODE_SAMPLER_CUBE.name(), "cubeTexture")
    assert_false(ValueType(36).is_valid())
    assert_false(NODE_MAT4.is_vector())
    assert_false(ValueType(0).is_vector())
    assert_equal(NODE_FLOAT.name(), "float")
    assert_equal(NODE_VEC3.name(), "vec3")
    assert_equal(NODE_MAT3.name(), "mat3")
    assert_equal(NODE_MAT4.name(), "mat4")
    assert_equal(NODE_SAMPLER.name(), "texture")
    assert_true(AT_FRAGMENT.is_valid())
    assert_true(CORNER_C.is_valid())
    assert_false(NodeContext(7).is_valid())
    assert_false(NodeContext(-1).is_valid())
    assert_true(CORNER_A.is_corner())
    assert_false(AT_UP.is_corner())
    assert_true(NodeVar(0).is_valid())
    assert_false(NodeVar(-1).is_valid())
    assert_true(NODE_ADD.is_valid())
    assert_true(NODE_SWIZZLE.is_valid())
    assert_false(NodeKind(-1).is_valid())
    assert_false(NodeKind(105).is_valid())
    assert_true(NodeKind(103).is_valid())
    assert_true(COLOR_NODE.is_valid())
    assert_true(OUTPUT_NODE.is_valid())
    assert_false(NodeOutput(-1).is_valid())
    assert_false(NodeOutput(NODE_OUTPUT_COUNT).is_valid())
    assert_true(OPACITY_NODE.value_type() == NODE_FLOAT)
    assert_true(MASK_NODE.value_type() == NODE_FLOAT)
    assert_true(AO_NODE.value_type() == NODE_FLOAT)
    assert_true(DEPTH_NODE.value_type() == NODE_FLOAT)
    assert_true(EMISSIVE_NODE.value_type() == NODE_VEC3)
    assert_true(NodeRef(0).is_valid())
    assert_false(NodeRef(-1).is_valid())
    assert_true(NodeProgramId(0).is_valid())
    assert_true(NO_NODES.is_valid())
    assert_false(NodeProgramId(-2).is_valid())


# --- values and attributes ----------------------------------------------------


def test_constants_hold_their_values() raises:
    var graph = NodeGraph()
    assert_lanes(vec3_of(graph, graph.vec3(0.1, 0.2, 0.3)), 0.1, 0.2, 0.3)
    assert_almost_equal(float_of(graph, graph.float(0.4)), 0.4)
    var four = graph.vec4(1, 2, 3, 4)
    assert_lanes(vec3_of(graph, graph.swizzle(four, "wzy")), 4, 3, 2)
    var two = graph.vec2(5, 6)
    assert_lanes(vec3_of(graph, graph.swizzle(two, "yxy")), 6, 5, 6)
    assert_equal(graph.type_of(two), NODE_VEC2)


def test_a_color_is_decoded_to_linear() raises:
    var graph = NodeGraph()
    var red = graph.color(Color(255, 128, 0))
    assert_lanes(vec3_of(graph, red), 1, srgb_to_linear(128.0 / 255), 0)


def test_the_attributes_read_the_fragment() raises:
    var graph = NodeGraph()
    assert_lanes(
        vec3_of(graph, graph.swizzle(graph.uv(), "xyx")), 0.25, 0.75, 0.25
    )
    assert_lanes(vec3_of(graph, graph.position_world()), 1, 2, 3)
    assert_lanes(vec3_of(graph, graph.normal_world()), 0, 0, 1)
    assert_lanes(vec3_of(graph, graph.vertex_color()), 0.1, 0.2, 0.3)


def test_time_is_the_frames_in_seconds() raises:
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.swizzle(graph.time(), "xxx"))
    assert_lanes(color_of(graph, time=2.5), 2.5, 2.5, 2.5)


def test_the_view_nodes_read_through_the_frames_view() raises:
    # A view that moves the world one meter down minus z and turns it a
    # quarter turn about y: x goes to minus z, z to x.
    var view = Matrix4()
    view.elements[0] = 0
    view.elements[2] = -1
    view.elements[8] = 1
    view.elements[10] = 0
    view.elements[14] = -1
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.position_view())
    graph.set_output(EMISSIVE_NODE, graph.normal_view())
    var program = graph.compile()
    program.set_frame(Duration(0.0, SECOND), view)
    var source = ProgramSource(Pointer(to=program))
    # (1, 2, 3): x' = z = 3, y' = 2, z' = -x - 1 = -2.
    assert_lanes(run_nodes(source, COLOR_NODE, inputs()), 3, 2, -2)
    # The normal (0, 0, 1) turns to (1, 0, 0) and stays a unit vector.
    assert_lanes(run_nodes(source, EMISSIVE_NODE, inputs()), 1, 0, 0)


def test_the_lit_color_reaches_an_output_node() raises:
    var graph = NodeGraph()
    var tint = graph.vec3(1, 0.5, 0)
    graph.set_output(OUTPUT_NODE, graph.mul(graph.lit(), tint))
    var program = graph.compile()
    assert_lanes(
        run_nodes(ProgramSource(Pointer(to=program)), OUTPUT_NODE, inputs()),
        0.5,
        0.3,
        0,
    )
    # A program on its own is at no pixel.
    var place = ProgramSource(Pointer(to=program)).frag_coord(AT_FRAGMENT)
    assert_equal(place[0], 0)
    assert_equal(place[3], 1)


struct Checker(NodeSource):
    """A `NodeSource` over a program that samples a texture as its own
    coordinate and its slot, to see what the interpreter asks for."""

    var code: List[Float32]

    def __init__(out self, program: NodeProgram):
        """Copy the program's floats."""
        self.code = program.code.copy()

    def word(self, at: Int) -> Float32:
        """Return one float."""
        return self.code[at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return the coordinate and the slot as a color."""
        return FloatColor(u, v, Float32(slot), 0.5)

    def sample_level(
        self, slot: Int, u: Float32, v: Float32, level: Float32
    ) -> FloatColor:
        """Return the coordinate and the level as a color."""
        return FloatColor(u, v, level, 0.25)

    def fetch(self, slot: Int, x: Int, y: Int, level: Int) -> FloatColor:
        """Return the column, the row and the level as a color."""
        return FloatColor(Float32(x), Float32(y), Float32(level), 0.75)

    def size(self, slot: Int, level: Int) -> Lanes:
        """Return a made-up size that halves by level."""
        return Lanes(Float32(64 >> level), Float32(32 >> level), 0, 0)

    def shares(self, context: NodeContext) -> Lanes:
        """Return the weights `Corners` gives."""
        return Corners().shares(context)

    def frag_coord(self, context: NodeContext) -> Lanes:
        """Return no place."""
        return Lanes(0, 0, 0, 1)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return the corners `Corners` gives."""
        return Corners().corner(context)


def test_a_texture_reads_at_the_level_the_graph_gives() raises:
    var graph = NodeGraph()
    var level = graph.add(graph.float(1), graph.float(0.5))
    var read = graph.texture_level(TextureId(3), graph.uv(), level)
    var named = graph.texture_level(
        graph.texture_uniform("map", TextureId(4)), graph.uv(), level
    )
    graph.set_output(
        COLOR_NODE,
        graph.add(graph.swizzle(read, "rgb"), graph.swizzle(named, "rgb")),
    )
    graph.set_output(OPACITY_NODE, graph.swizzle(read, "a"))
    var program = graph.compile()
    assert_equal(len(program.textures), 2)
    var source = Checker(program)
    # The checker gives the coordinate and the level as the color.
    assert_equal(run_nodes(source, COLOR_NODE, inputs(True))[2], 3)
    assert_equal(run_nodes(source, OPACITY_NODE, inputs(True))[0], 0.25)
    # A mode that opens no textures reads white.
    assert_equal(run_nodes(source, OPACITY_NODE, inputs(False))[0], 1)
    # The host's source for a program alone reads white.
    var alone = ProgramSource(Pointer(to=program))
    assert_equal(alone.sample_level(3, 0.5, 0.5, 1).g, 1)
    var bad = NodeGraph()
    with assert_raises(contains="A texture's level is a float, not a vec2"):
        _ = bad.texture_level(TextureId(0), bad.uv(), bad.uv())
    # Only a fragment reads a texture, at a level or not.
    var moved = NodeGraph()
    moved.set_output(
        POSITION_NODE,
        moved.swizzle(
            moved.texture_level(TextureId(0), moved.uv(), moved.float(0)), "xyz"
        ),
    )
    with assert_raises(contains="A position node runs once per vertex"):
        _ = moved.compile()
    var varied = NodeGraph()
    varied.set_output(
        COLOR_NODE,
        varied.varying(
            varied.swizzle(
                varied.texture_level(
                    TextureId(0), varied.uv(), varied.float(0)
                ),
                "xyz",
            )
        ),
    )
    with assert_raises(contains="A varying runs once per corner"):
        _ = varied.compile()


def test_a_texel_and_a_size_are_read_by_whole_numbers() raises:
    var graph = NodeGraph()
    var map = graph.texture_uniform("map", TextureId(2))
    var texel = graph.texture_load(map, graph.vec2(3, 5), graph.float(1))
    var size = graph.texture_size(map, graph.float(1))
    graph.set_output(
        COLOR_NODE,
        graph.join([graph.swizzle(texel, "xy"), graph.swizzle(size, "x")]),
    )
    graph.set_output(OPACITY_NODE, graph.swizzle(texel, "a"))
    var program = graph.compile()
    var source = Checker(program)
    # The checker gives the column, the row and the level as the color.
    assert_lanes(run_nodes(source, COLOR_NODE, inputs(True)), 3, 5, 32)
    assert_equal(run_nodes(source, OPACITY_NODE, inputs(True))[0], 0.75)
    assert_equal(run_nodes(source, OPACITY_NODE, inputs(False))[0], 1)
    var alone = ProgramSource(Pointer(to=program))
    assert_equal(alone.fetch(0, 1, 2, 0).r, 1)
    assert_equal(alone.size(0, 0)[0], 0)
    var bad = NodeGraph()
    with assert_raises(contains="A texture's size is a texture's, not a vec2"):
        _ = bad.texture_size(bad.uv(), bad.float(0))
    var named = bad.texture_uniform("map", TextureId(0))
    with assert_raises(contains="A texture's level is a float, not a vec2"):
        _ = bad.texture_size(named, bad.uv())


def test_a_custom_attribute_is_read_at_each_corner() raises:
    var graph = NodeGraph()
    var size = graph.attribute("size", NODE_FLOAT)
    var offset = graph.attribute("offset", NODE_VEC3)
    var again = graph.attribute("size", NODE_FLOAT)
    graph.set_output(
        COLOR_NODE,
        graph.join([graph.add(size, again), graph.swizzle(offset, "xy")]),
    )
    graph.set_output(
        EMISSIVE_NODE,
        graph.varying(graph.join([size, graph.swizzle(offset, "yz")])),
    )
    var program = graph.compile()
    assert_equal(len(program.attribute_names), 2)
    assert_equal(program.attribute_names[1], "offset")
    assert_equal(program.attribute_offsets[1], 1)
    assert_equal(program.attribute_widths[1], 3)
    # Corners gives each float k + 1 at the first corner, ten times that at
    # the second and a hundred times at the third.
    var s = Corners().shares(AT_HERE)
    var mean = s[0] + 10 * s[1] + 100 * s[2]
    var here = run_nodes(Corners(program), COLOR_NODE, inputs())
    assert_almost_equal(here[0], 2 * mean, atol=1e-4)
    assert_almost_equal(here[1], 2 * mean, atol=1e-4)
    assert_almost_equal(here[2], 3 * mean, atol=1e-4)
    var carried = run_nodes(Corners(program), EMISSIVE_NODE, inputs())
    assert_almost_equal(carried[2], 4 * mean, atol=1e-4)
    var bad = NodeGraph()
    with assert_raises(contains="uv is a built-in attribute"):
        _ = bad.attribute("uv", NODE_VEC2)
    with assert_raises(
        contains="An attribute is a float or a vector, not a mat3"
    ):
        _ = bad.attribute("frame", NODE_MAT3)
    _ = bad.attribute("size", NODE_FLOAT)
    with assert_raises(contains="The attribute size is a float, not a vec2"):
        _ = bad.attribute("size", NODE_VEC2)
    _ = bad.attribute("a", NODE_VEC4)
    with assert_raises(contains="A graph's attributes hold at most 8 floats"):
        _ = bad.attribute("b", NODE_VEC4)
    # A position node runs on the host, where no corner carries them.
    var moved = NodeGraph()
    moved.set_output(
        POSITION_NODE,
        moved.add(moved.position_local(), moved.attribute("lift", NODE_VEC3)),
    )
    with assert_raises(contains="A position node runs once per vertex"):
        _ = moved.compile()


def test_a_3d_and_an_array_texture_are_read_at_a_vec3() raises:
    var graph = NodeGraph()
    var cloud = graph.volume_uniform("cloud", Data3DTextureId(3))
    var stack = graph.array_uniform("stack")
    var middle = graph.vec3(0.5, 0.5, 0.5)
    var a = graph.texture_3d(cloud, middle)
    var b = graph.texture_3d(cloud, graph.vec3(0, 0, 0))
    var c = graph.texture_array(stack, middle)
    graph.set_output(
        COLOR_NODE, graph.swizzle(graph.add(a, graph.add(b, c)), "rgb")
    )
    var program = graph.compile()
    # Each texture is listed once however often it is read.
    assert_equal(len(program.volumes), 1)
    assert_equal(program.volumes[0].value, 3)
    assert_equal(len(program.arrays), 1)
    assert_equal(program.arrays[0].value, -1)
    program.set_array("stack", DataArrayTextureId(4))
    assert_equal(program.arrays[0].value, 4)
    var named = NodeGraph()
    _ = named.array_uniform("given", DataArrayTextureId(2))
    program.set_volume("cloud", Data3DTextureId(1))
    assert_equal(program.volumes[0].value, 1)
    # A source with neither reads white.
    assert_lanes(run_nodes(Checker(program), COLOR_NODE, inputs(True)), 3, 3, 3)
    # Untextured, each read is opaque white without asking the source.
    assert_lanes(
        run_nodes(Checker(program), COLOR_NODE, inputs(False)), 3, 3, 3
    )
    with assert_raises(contains="A 3D texture uniform needs a texture"):
        program.set_volume("cloud", Data3DTextureId(-1))
    with assert_raises(contains="An array texture uniform needs a texture"):
        program.set_array("stack", DataArrayTextureId(-1))
    with assert_raises(contains="The uniform stack is a textureArray"):
        program.set_volume("stack", Data3DTextureId(0))
    var bad = NodeGraph()
    with assert_raises(contains="A 3D texture uniform names no texture"):
        _ = bad.volume_uniform("x", Data3DTextureId(-3))
    with assert_raises(contains="An array texture uniform names no texture"):
        _ = bad.array_uniform("y", DataArrayTextureId(-3))
    var layers = bad.array_uniform("layers")
    with assert_raises(contains="This read reads a texture3D, not a vec2"):
        _ = bad.texture_3d(bad.uv(), bad.vec3(0, 0, 0))
    with assert_raises(contains="A textureArray is read at a vec3, not a vec2"):
        _ = bad.texture_array(layers, bad.uv())
    # Only a fragment reads one.
    var varied = NodeGraph()
    varied.set_output(
        COLOR_NODE,
        varied.varying(
            varied.swizzle(
                varied.texture_3d(
                    varied.volume_uniform("c"), varied.normal_world()
                ),
                "xyz",
            )
        ),
    )
    with assert_raises(contains="A varying runs once per corner"):
        _ = varied.compile()


def test_a_call_needs_a_type_and_an_open_call() raises:
    var graph = NodeGraph()
    with assert_raises(contains="A call returns a float or a vector"):
        graph.open_call(NODE_MAT3)
    with assert_raises(contains="A close_call needs an open_call"):
        _ = graph.close_call(graph.float(0))
    with assert_raises(contains="An attribute is a float or a vector"):
        _ = graph.attribute("heat", ValueType(0))


def test_a_cube_is_read_in_a_direction() raises:
    var graph = NodeGraph()
    var sky = graph.cube_uniform("sky", CubeTextureId(2))
    var ground = graph.cube_uniform("ground")
    var up = graph.texture_cube(sky, graph.vec3(0, 1, 0))
    var again = graph.texture_cube(sky, graph.vec3(1, 0, 0))
    var down = graph.texture_cube(ground, graph.vec3(0, -1, 0))
    graph.set_output(
        COLOR_NODE,
        graph.swizzle(graph.add(up, graph.add(again, down)), "rgb"),
    )
    var program = graph.compile()
    # One cube, listed once however often it is read, and one unset.
    assert_equal(len(program.cubes), 2)
    assert_equal(program.cubes[0].value, 2)
    assert_equal(program.cubes[1].value, -1)
    program.set_cube("ground", CubeTextureId(5))
    assert_equal(program.cubes[1].value, 5)
    # A source with no cubes reads white.
    assert_lanes(run_nodes(Checker(program), COLOR_NODE, inputs(True)), 3, 3, 3)
    assert_lanes(
        run_nodes(Checker(program), COLOR_NODE, inputs(False)), 3, 3, 3
    )
    with assert_raises(contains="A cube uniform needs a cube"):
        program.set_cube("sky", CubeTextureId(-1))
    var bad = NodeGraph()
    with assert_raises(contains="A cube uniform names no cube there can be"):
        _ = bad.cube_uniform("x", CubeTextureId(-3))
    var sky2 = bad.cube_uniform("sky")
    with assert_raises(contains="A cube read reads a cube texture, not a vec2"):
        _ = bad.texture_cube(bad.uv(), bad.vec3(1, 0, 0))
    with assert_raises(
        contains="A cube is read in a vec3 direction, not a vec2"
    ):
        _ = bad.texture_cube(sky2, bad.uv())
    # Only a fragment reads a cube.
    var moved = NodeGraph()
    moved.set_output(
        POSITION_NODE,
        moved.swizzle(
            moved.texture_cube(moved.cube_uniform("c"), moved.vec3(1, 0, 0)),
            "xyz",
        ),
    )
    with assert_raises(contains="A position node runs once per vertex"):
        _ = moved.compile()
    var varied = NodeGraph()
    varied.set_output(
        COLOR_NODE,
        varied.varying(
            varied.swizzle(
                varied.texture_cube(
                    varied.cube_uniform("c"), varied.normal_world()
                ),
                "xyz",
            )
        ),
    )
    with assert_raises(contains="A varying runs once per corner"):
        _ = varied.compile()


def test_a_texture_reads_where_its_coordinate_says() raises:
    var graph = NodeGraph()
    var at = graph.mul(graph.uv(), graph.float(2))
    var read = graph.texture(TextureId(3), at)
    graph.set_output(COLOR_NODE, graph.swizzle(read, "rgb"))
    graph.set_output(OPACITY_NODE, graph.swizzle(read, "a"))
    var program = graph.compile()
    assert_equal(len(program.textures), 1)
    assert_equal(program.textures[0].value, 3)
    var source = Checker(program)
    assert_lanes(run_nodes(source, COLOR_NODE, inputs(True)), 0.5, 1.5, 3)
    assert_almost_equal(run_nodes(source, OPACITY_NODE, inputs(True))[0], 0.5)
    # A mode that opens no textures reads white.
    assert_lanes(run_nodes(source, COLOR_NODE, inputs(False)), 1, 1, 1)
    # The host's source for a program alone reads white too.
    var alone = ProgramSource(Pointer(to=program))
    var white = alone.sample(3, 0.5, 0.5)
    assert_equal(white.r, 1)
    assert_equal(white.a, 1)
    # Two textures are both listed, each once.
    var both = NodeGraph()
    var first = both.texture(TextureId(3), both.uv())
    var second = both.texture(TextureId(4), both.uv())
    both.set_output(COLOR_NODE, both.swizzle(both.add(first, second), "rgb"))
    both.set_output(OPACITY_NODE, both.swizzle(first, "a"))
    var listed = both.compile().textures.copy()
    assert_equal(len(listed), 2)
    assert_equal(listed[1].value, 4)


# --- math ---------------------------------------------------------------------


def test_the_four_operators_work_component_by_component() raises:
    var graph = NodeGraph()
    var a = graph.vec3(1, 2, 3)
    var b = graph.vec3(4, 5, 6)
    assert_lanes(vec3_of(graph, graph.add(a, b)), 5, 7, 9)
    assert_lanes(vec3_of(graph, graph.sub(a, b)), -3, -3, -3)
    assert_lanes(vec3_of(graph, graph.mul(a, b)), 4, 10, 18)
    assert_lanes(vec3_of(graph, graph.div(a, b)), 0.25, 0.4, 0.5)


def test_a_float_is_repeated_beside_a_vector_on_either_side() raises:
    var graph = NodeGraph()
    var a = graph.vec3(1, 2, 3)
    var two = graph.float(2)
    assert_lanes(vec3_of(graph, graph.mul(two, a)), 2, 4, 6)
    assert_lanes(vec3_of(graph, graph.sub(a, two)), -1, 0, 1)
    # Two floats stay a float.
    assert_almost_equal(float_of(graph, graph.add(two, two)), 4)


def test_mix_clamp_and_smoothstep_follow_glsl() raises:
    var graph = NodeGraph()
    var a = graph.vec3(0, 10, 20)
    var b = graph.vec3(10, 20, 40)
    assert_lanes(
        vec3_of(graph, graph.mix(a, b, graph.float(0.25))), 2.5, 12.5, 25
    )
    var x = graph.vec3(-1, 0.5, 3)
    assert_lanes(
        vec3_of(graph, graph.clamp(x, graph.float(0), graph.float(1))),
        0,
        0.5,
        1,
    )
    # A vector edge beside a float value widens the value.
    var edges = graph.vec3(0, 0, 1)
    assert_lanes(
        vec3_of(
            graph,
            graph.smoothstep(edges, graph.vec3(1, 2, 2), graph.float(0.5)),
        ),
        0.5,
        0.15625,
        0,
    )
    # The third operand alone can be the widest.
    var t = graph.vec3(0, 0.5, 1)
    assert_lanes(
        vec3_of(graph, graph.mix(graph.float(2), graph.float(4), t)), 2, 3, 4
    )


def test_dot_length_and_normalize_read_only_their_type() raises:
    var graph = NodeGraph()
    var a = graph.vec3(1, 2, 2)
    assert_almost_equal(float_of(graph, graph.dot(a, a)), 9)
    assert_almost_equal(float_of(graph, graph.length(a)), 3)
    var two = graph.vec2(3, 4)
    assert_almost_equal(float_of(graph, graph.dot(two, two)), 25)
    var four = graph.vec4(1, 1, 1, 1)
    assert_almost_equal(float_of(graph, graph.length(four)), 2)
    var one = graph.float(-3)
    assert_almost_equal(float_of(graph, graph.dot(one, one)), 9)
    assert_lanes(vec3_of(graph, graph.normalize(a)), 1.0 / 3, 2.0 / 3, 2.0 / 3)
    # A zero vector stays zero rather than dividing by nothing.
    assert_lanes(vec3_of(graph, graph.normalize(graph.vec3(0, 0, 0))), 0, 0, 0)


def test_the_functions_of_one_value() raises:
    var graph = NodeGraph()
    var x = graph.vec3(0.5, 1.25, -0.75)
    var sines = vec3_of(graph, graph.sin(x))
    assert_lanes(
        sines, sin(Float32(0.5)), sin(Float32(1.25)), sin(Float32(-0.75))
    )
    var cosines = vec3_of(graph, graph.cos(x))
    assert_lanes(
        cosines, cos(Float32(0.5)), cos(Float32(1.25)), cos(Float32(-0.75))
    )
    assert_lanes(vec3_of(graph, graph.fract(x)), 0.5, 0.25, 0.25)
    var squares = graph.pow(graph.vec3(2, 3, 4), graph.float(2))
    assert_lanes(vec3_of(graph, squares), 4, 9, 16)
    var steps = graph.step(graph.float(1), graph.vec3(0.5, 1, 2))
    assert_lanes(vec3_of(graph, steps), 0, 1, 1)


def test_a_division_by_zero_is_ieee() raises:
    var graph = NodeGraph()
    var zero = graph.float(0)
    assert_true(isnan(float_of(graph, graph.div(zero, zero))))


def test_a_swizzle_takes_either_alphabet() raises:
    var graph = NodeGraph()
    var four = graph.vec4(1, 2, 3, 4)
    assert_lanes(vec3_of(graph, graph.swizzle(four, "abg")), 4, 3, 2)
    assert_almost_equal(float_of(graph, graph.swizzle(four, "z")), 3)
    var all = graph.swizzle(four, "wzyx")
    assert_equal(graph.type_of(all), NODE_VEC4)
    assert_lanes(vec3_of(graph, graph.swizzle(all, "xyz")), 4, 3, 2)


# --- refusals as a graph is built ---------------------------------------------


def test_a_type_error_is_refused_as_the_graph_is_built() raises:
    var graph = NodeGraph()
    var three = graph.vec3(1, 2, 3)
    var two = graph.vec2(1, 2)
    with assert_raises(contains="cannot add a vec3 and a vec2"):
        _ = graph.add(three, two)
    with assert_raises(contains="cannot multiply a vec3 and a vec2"):
        _ = graph.mul(two, three)
    with assert_raises(contains="cannot subtract"):
        _ = graph.sub(three, two)
    with assert_raises(contains="cannot divide"):
        _ = graph.div(three, two)
    with assert_raises(contains="cannot raise"):
        _ = graph.pow(three, two)
    with assert_raises(contains="cannot step"):
        _ = graph.step(three, two)
    with assert_raises(contains="cannot mix"):
        _ = graph.mix(three, three, two)
    with assert_raises(contains="cannot clamp"):
        _ = graph.clamp(two, three, three)
    with assert_raises(contains="cannot smoothstep"):
        _ = graph.smoothstep(three, two, three)
    with assert_raises(contains="cannot dot a vec3 and a vec2"):
        _ = graph.dot(three, two)
    with assert_raises(contains="reads at a vec2, not a vec3"):
        _ = graph.texture(TextureId(0), three)
    with assert_raises(contains="needs a texture"):
        _ = graph.texture(NO_TEXTURE, two)


def test_a_ref_from_nowhere_is_refused() raises:
    var graph = NodeGraph()
    var one = graph.float(1)
    with assert_raises(contains="no node with that ref"):
        _ = graph.add(one, NodeRef(7))
    with assert_raises(contains="no node with that ref"):
        _ = graph.add(NodeRef(-1), one)
    with assert_raises(contains="no node with that ref"):
        _ = graph.mix(one, one, NodeRef(9))
    with assert_raises(contains="no node with that ref"):
        _ = graph.sin(NodeRef(9))
    with assert_raises(contains="no node with that ref"):
        _ = graph.swizzle(NodeRef(9), "x")
    with assert_raises(contains="no node with that ref"):
        _ = graph.dot(NodeRef(9), one)
    with assert_raises(contains="no node with that ref"):
        _ = graph.type_of(NodeRef(9))


def test_a_swizzle_must_name_components_the_value_has() raises:
    var graph = NodeGraph()
    var two = graph.vec2(1, 2)
    with assert_raises(contains="one to four components"):
        _ = graph.swizzle(two, "")
    with assert_raises(contains="one to four components"):
        _ = graph.swizzle(two, "xyxyx")
    with assert_raises(contains="a vec2 does not have: xz"):
        _ = graph.swizzle(two, "xz")
    with assert_raises(contains="does not have: q"):
        _ = graph.swizzle(two, "q")


def test_a_uniform_needs_a_name_of_its_own() raises:
    var graph = NodeGraph()
    _ = graph.uniform("tint", Color(255, 0, 0))
    with assert_raises(contains="already has a uniform named tint"):
        _ = graph.uniform("tint", Float32(1))
    with assert_raises(contains="needs a name"):
        _ = graph.uniform("", Vector2(1, 2))
    # A constant does not hold a name, so it never clashes.
    _ = graph.float(1)
    _ = graph.uniform("offset", Vector3(1, 2, 3))


def test_an_output_takes_its_own_type_only() raises:
    var graph = NodeGraph()
    var three = graph.vec3(1, 2, 3)
    with assert_raises(contains="takes a float, not a vec3"):
        graph.set_output(OPACITY_NODE, three)
    with assert_raises(contains="takes a vec3, not a float"):
        graph.set_output(NORMAL_NODE, graph.float(1))
    with assert_raises(contains="none of the ten"):
        graph.set_output(NodeOutput(10), three)
    with assert_raises(contains="no node with that ref"):
        graph.set_output(COLOR_NODE, NodeRef(99))


def test_a_rewire_keeps_the_types_and_refuses_a_cycle() raises:
    var graph = NodeGraph()
    var a = graph.vec3(1, 2, 3)
    var b = graph.vec3(10, 20, 30)
    var sum = graph.add(a, a)
    var twice = graph.add(sum, sum)
    graph.set_input(sum, 1, b)
    assert_lanes(vec3_of(graph, twice), 22, 44, 66)
    # A source that reads one node twice is walked once past it.
    var other = graph.sub(b, b)
    graph.set_input(other, 0, twice)
    assert_lanes(vec3_of(graph, other), 12, 24, 36)
    with assert_raises(contains="would make a cycle"):
        graph.set_input(sum, 0, twice)
    with assert_raises(contains="would make a cycle"):
        graph.set_input(sum, 0, sum)
    with assert_raises(contains="reads a vec3, not a float"):
        graph.set_input(sum, 0, graph.float(1))
    with assert_raises(contains="no input in that slot"):
        graph.set_input(sum, 2, b)
    with assert_raises(contains="no input in that slot"):
        graph.set_input(sum, 3, b)
    with assert_raises(contains="no input in that slot"):
        graph.set_input(sum, -1, b)
    with assert_raises(contains="no input in that slot"):
        graph.set_input(a, 0, b)
    with assert_raises(contains="no node with that ref"):
        graph.set_input(sum, 0, NodeRef(99))
    with assert_raises(contains="no node with that ref"):
        graph.set_input(NodeRef(99), 0, b)


# --- compiling ----------------------------------------------------------------


def test_a_program_is_laid_out_header_instructions_then_values() raises:
    var graph = NodeGraph()
    var tint = graph.uniform("tint", Vector3(1, 0.5, 0.25))
    var doubled = graph.add(tint, tint)
    graph.set_output(COLOR_NODE, doubled)
    graph.set_output(EMISSIVE_NODE, tint)
    var program = graph.compile()
    # The color is two instructions and the emissive one, and the uniform
    # is stored once after all three.
    assert_equal(Int(program.code[0]), PROGRAM_HEADER)
    assert_equal(Int(program.code[1]), 2)
    assert_equal(Int(program.code[5]), 1)
    assert_equal(len(program.code), PROGRAM_HEADER + 3 * INSTRUCTION_FLOATS + 4)
    assert_equal(program.uniform_offsets[0], len(program.code) - 4)
    assert_true(program.has(COLOR_NODE))
    assert_false(program.has(OPACITY_NODE))
    with assert_raises(contains="none of the ten"):
        _ = program.has(NodeOutput(10))
    var source = ProgramSource(Pointer(to=program))
    assert_true(has_output(source, EMISSIVE_NODE))
    assert_false(has_output(source, NORMAL_NODE))
    # Changing the uniform changes both outputs, between frames.
    program.set_uniform("tint", Vector3(0.1, 0.2, 0.3))
    var changed = ProgramSource(Pointer(to=program))
    assert_lanes(run_nodes(changed, COLOR_NODE, inputs()), 0.2, 0.4, 0.6)
    assert_lanes(run_nodes(changed, EMISSIVE_NODE, inputs()), 0.1, 0.2, 0.3)


def test_a_uniform_is_set_by_name_and_type() raises:
    var graph = NodeGraph()
    var level = graph.uniform("level", Float32(0.5))
    var shift = graph.uniform("shift", Vector2(1, 2))
    var tint = graph.uniform("tint", Color(0, 0, 0))
    var sum = graph.add(
        graph.add(tint, graph.swizzle(shift, "xyx")),
        graph.swizzle(level, "xxx"),
    )
    graph.set_output(COLOR_NODE, sum)
    var program = graph.compile()
    assert_almost_equal(program.uniform("level")[0], 0.5)
    program.set_uniform("level", Float32(1))
    program.set_uniform("shift", Vector2(3, 4))
    program.set_uniform("tint", Color(255, 255, 255))
    assert_lanes(
        run_nodes(ProgramSource(Pointer(to=program)), COLOR_NODE, inputs()),
        5,
        6,
        5,
    )
    assert_equal(program.uniform("shift")[1], 4)
    with assert_raises(contains="no uniform named speed"):
        program.set_uniform("speed", Float32(1))
    with assert_raises(contains="no uniform named speed"):
        _ = program.uniform("speed")
    with assert_raises(contains="The uniform level is a float, not a vec3"):
        program.set_uniform("level", Vector3(1, 2, 3))
    # A program with no uniforms knows no name.
    var plain = NodeGraph()
    plain.set_output(COLOR_NODE, plain.vec3(1, 1, 1))
    var fixed = plain.compile()
    with assert_raises(contains="no uniform named level"):
        fixed.set_uniform("level", Float32(1))
    with assert_raises(contains="no uniform named level"):
        _ = fixed.uniform("level")


def test_a_node_two_outputs_share_is_computed_by_each() raises:
    var graph = NodeGraph()
    var shared = graph.add(graph.vec3(1, 1, 1), graph.vertex_color())
    graph.set_output(COLOR_NODE, shared)
    graph.set_output(EMISSIVE_NODE, graph.mul(shared, shared))
    var program = graph.compile()
    var source = ProgramSource(Pointer(to=program))
    assert_lanes(run_nodes(source, COLOR_NODE, inputs()), 1.1, 1.2, 1.3)
    assert_lanes(run_nodes(source, EMISSIVE_NODE, inputs()), 1.21, 1.44, 1.69)


def test_compiling_refuses_a_graph_it_cannot_run() raises:
    var empty = NodeGraph()
    with assert_raises(contains="at least one output"):
        _ = empty.compile()
    # A chain of a hundred nodes needs two registers: each value dies as
    # the next is made.
    var long = NodeGraph()
    var chain = long.vec3(0, 0, 0)
    for _ in range(100):
        chain = long.add(chain, long.vec3(1, 1, 1))
    long.set_output(COLOR_NODE, chain)
    assert_lanes(color_of(long), 100, 100, 100)
    # Thirty-three values summed twice, in two orders: whichever sum is
    # laid out first, every value waits for the other, in any order the
    # compiler tries.
    var wide = NodeGraph()
    var terms = List[NodeRef]()
    for index in range(MAX_REGISTERS + 1):
        terms.append(wide.mul(wide.uv(), wide.float(Float32(index))))
    var forward = terms[0]
    for index in range(1, len(terms)):
        forward = wide.add(forward, terms[index])
    var backward = terms[len(terms) - 1]
    for index in range(len(terms) - 2, -1, -1):
        backward = wide.add(backward, terms[index])
    wide.set_output(
        COLOR_NODE, wide.swizzle(wide.mul(forward, backward), "xyx")
    )
    with assert_raises(contains="more than 32 values alive at once"):
        _ = wide.compile()
    # An output of more instructions than a fragment may run is refused.
    var huge = NodeGraph()
    var total = huge.uv()
    for index in range(MAX_INSTRUCTIONS // 2 + 1):
        total = huge.add(total, huge.float(Float32(index)))
    huge.set_output(COLOR_NODE, huge.swizzle(total, "xyx"))
    with assert_raises(contains="at most 4096 instructions"):
        _ = huge.compile()
    # A block left open is refused.
    var open = NodeGraph()
    open.set_output(COLOR_NODE, open.vec3(1, 1, 1))
    open.If(open.float(1))
    with assert_raises(contains="End never closed"):
        _ = open.compile()


def test_compiling_refuses_an_edited_graph() raises:
    # The fields are open, so a graph can be edited past what the builder
    # allows: a cycle, a dangling input, a dangling output, a kind or a
    # type there is not.
    var graph = NodeGraph()
    var a = graph.vec3(1, 2, 3)
    var b = graph.add(a, a)
    graph.set_output(COLOR_NODE, b)
    var cycle = graph.copy()
    cycle._inputs[b.value * 3] = b.value
    with assert_raises(contains="cannot hold a cycle"):
        _ = cycle.compile()
    var dangling = graph.copy()
    dangling._inputs[b.value * 3] = 42
    with assert_raises(contains="reads a node the graph does not hold"):
        _ = dangling.compile()
    var nowhere = graph.copy()
    nowhere._outputs[COLOR_NODE.value] = 42
    with assert_raises(contains="names a node the graph does not hold"):
        _ = nowhere.compile()
    var strange = graph.copy()
    strange._kinds[a.value] = NodeKind(105)
    with assert_raises(contains="a kind or a type there is not"):
        _ = strange.compile()
    var shapeless = graph.copy()
    shapeless._types[a.value] = ValueType(7)
    with assert_raises(contains="a kind or a type there is not"):
        _ = shapeless.compile()
    shapeless._types[a.value] = ValueType(99)
    with assert_raises(contains="a kind or a type there is not"):
        _ = shapeless.compile()


def test_each_output_reads_only_what_its_stage_has() raises:
    var lit_color = NodeGraph()
    lit_color.set_output(COLOR_NODE, lit_color.lit())
    with assert_raises(contains="Only an output node reads the lit color"):
        _ = lit_color.compile()
    var local = NodeGraph()
    local.set_output(COLOR_NODE, local.position_local())
    with assert_raises(contains="Only a position node reads the local"):
        _ = local.compile()
    var normal = NodeGraph()
    normal.set_output(EMISSIVE_NODE, normal.normal_local())
    with assert_raises(contains="Only a position node reads the local"):
        _ = normal.compile()
    var moved = NodeGraph()
    moved.set_output(POSITION_NODE, moved.position_world())
    with assert_raises(contains="A position node runs once per vertex"):
        _ = moved.compile()
    # Nor a texture, a varying or a derivative.
    for which in range(4):
        var vertex = NodeGraph()
        var local = vertex.position_local()
        var read: NodeRef
        if which == 0:
            read = vertex.swizzle(
                vertex.texture(TextureId(0), vertex.swizzle(local, "xy")), "xyz"
            )
        elif which == 1:
            read = vertex.varying(local)
        elif which == 2:
            read = vertex.dfdx(local)
        else:
            read = vertex.dfdy(local)
        vertex.set_output(POSITION_NODE, read)
        with assert_raises(contains="A position node runs once per vertex"):
            _ = vertex.compile()
    # A position node reads the camera, and multiplies by the view.
    var seen = NodeGraph()
    var far = seen.mul(
        seen.camera_view_matrix(),
        seen.join([seen.position_local(), seen.float(1)]),
    )
    seen.set_output(
        POSITION_NODE,
        seen.add(seen.camera_position(), seen.swizzle(far, "xyz")),
    )
    _ = seen.compile()
    # What a vertex has: constants, uniforms, time, math and the local
    # position and normal.
    var fine = NodeGraph()
    var lift = fine.mul(
        fine.normal_local(),
        fine.mul(fine.uniform("height", Float32(1)), fine.sin(fine.time())),
    )
    fine.set_output(
        POSITION_NODE,
        fine.add(fine.add(lift, fine.position_local()), fine.vec3(0, 0, 0)),
    )
    _ = fine.compile()


# --- the vertex stage ---------------------------------------------------------


def test_a_position_node_moves_each_vertex() raises:
    var graph = NodeGraph()
    var lift = graph.mul(
        graph.normal_local(), graph.uniform("height", Float32(2))
    )
    graph.set_output(
        POSITION_NODE,
        graph.add(lift, graph.swizzle(graph.position_local(), "zzz")),
    )
    var program = graph.compile()
    var moved = moved_position(program, Vector3(1, 1, 1), Vector3(0, 1, 0))
    assert_equal(moved.x, 2)
    assert_equal(moved.y, 4)
    assert_equal(moved.z, 2)
    var colored = NodeGraph()
    colored.set_output(COLOR_NODE, colored.vec3(1, 1, 1))
    with assert_raises(contains="has no position node"):
        _ = moved_position(
            colored.compile(), Vector3(0, 0, 0), Vector3(0, 0, 1)
        )


def test_an_offset_normal_is_a_unit_vector_again() raises:
    var bent = offset_normal(Vector3(0, 0, 1), Lanes(1, 0, 0, 0))
    assert_almost_equal(bent.x, sqrt(Float32(0.5)))
    assert_almost_equal(bent.z, sqrt(Float32(0.5)))
    # An offset that cancels the normal leaves zero, not a division by it.
    var gone = offset_normal(Vector3(0, 0, 1), Lanes(0, 0, -1, 0))
    assert_equal(gone.z, 0)


# --- the store ----------------------------------------------------------------


def test_the_store_owns_programs_and_writes_every_frame() raises:
    var store = NodeProgramStore()
    assert_equal(store.count(), 0)
    var graph = NodeGraph()
    graph.set_output(OPACITY_NODE, graph.uniform("fade", Float32(0.5)))
    var id = store.add(graph.compile())
    assert_equal(id.value, 0)
    assert_equal(store.count(), 1)
    store.get(id).set_uniform("fade", Float32(0.25))
    assert_almost_equal(store.get(id).uniform("fade")[0], 0.25)
    store.set_frame(Duration(3.0, SECOND), Matrix4())
    assert_equal(store.get(id).code[PROGRAM_TIME], 3)
    with assert_raises(contains="No node program has that id"):
        _ = store.get(NodeProgramId(1))
    with assert_raises(contains="No node program has that id"):
        _ = store.get(NO_NODES)
    # An empty store writes nothing.
    var none = NodeProgramStore()
    none.set_frame(Duration(1.0, SECOND), Matrix4())
    assert_equal(none.count(), 0)


# --- the node library ---------------------------------------------------------


struct Corners(NodeSource):
    """A `NodeSource` over a triangle of made-up corners and weights, to
    check varyings and derivatives by hand.

    The fragment weighs the corners one half, one quarter, one quarter; the
    pixel to the right one quarter, one half, one quarter; the pixel above
    one quarter, one quarter, one half. So the coordinates are (0.25, 0.25)
    here, (0.5, 0.25) to the right and (0.25, 0.5) above.
    """

    var code: List[Float32]

    def __init__(out self):
        """Read no program."""
        self.code = List[Float32]()

    def __init__(out self, program: NodeProgram):
        """Copy a program's floats."""
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
        """Return the coordinate and the level as a color."""
        return FloatColor(u, v, level, 0.25)

    def fetch(self, slot: Int, x: Int, y: Int, level: Int) -> FloatColor:
        """Return the column, the row and the level as a color."""
        return FloatColor(Float32(x), Float32(y), Float32(level), 0.75)

    def size(self, slot: Int, level: Int) -> Lanes:
        """Return a made-up size that halves by level."""
        return Lanes(Float32(64 >> level), Float32(32 >> level), 0, 0)

    def shares(self, context: NodeContext) -> Lanes:
        """Return the made-up weights."""
        if context == AT_RIGHT:
            return Lanes(0.25, 0.5, 0.25, 0)
        if context == AT_UP:
            return Lanes(0.25, 0.25, 0.5, 0)
        return Lanes(0.5, 0.25, 0.25, 0)

    def frag_coord(self, context: NodeContext) -> Lanes:
        """Return a made-up place: the pixel (10, 20) from the bottom
        left, at a depth of 0.75, and its neighbors a pixel over."""
        if context == AT_RIGHT:
            return Lanes(11.5, 20.5, 0.75, 1)
        if context == AT_UP:
            return Lanes(10.5, 21.5, 0.75, 1)
        return Lanes(10.5, 20.5, 0.75, 1)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return the made-up corners, each with custom floats of its own:
        one to eight at the first, ten times those at the second, and a
        hundred times at the third."""
        var at = self._plain_corner(context)
        var scale = Float32(1) if context == CORNER_A else (
            Float32(10) if context == CORNER_B else Float32(100)
        )
        at.custom = SIMD[DType.float32, 8](1, 2, 3, 4, 5, 6, 7, 8) * scale
        return at

    def _plain_corner(self, context: NodeContext) -> NodeInputs:
        """Return the made-up corners: normals two long, to see them made
        unit."""
        if context == CORNER_A:
            return NodeInputs(
                0,
                0,
                Vector3(0, 0, 0),
                Vector3(0, 0, 2),
                Vector3(1, 0, 0),
                Vector3(0, 0, 0),
                False,
            )
        if context == CORNER_B:
            return NodeInputs(
                1,
                0,
                Vector3(4, 0, 0),
                Vector3(0, 2, 0),
                Vector3(0, 1, 0),
                Vector3(0, 0, 0),
                False,
            )
        return NodeInputs(
            0,
            1,
            Vector3(0, 4, 0),
            Vector3(2, 0, 0),
            Vector3(0, 0, 1),
            Vector3(0, 0, 0),
            False,
        )


def on_corners(
    mut graph: NodeGraph, node: NodeRef, textured: Bool = False
) raises -> Lanes:
    """Return a node's value on `Corners`, through the color output, the
    fragment's own attributes those `Corners` interpolates."""
    var type = graph.type_of(node)
    var shown = node
    if type == NODE_FLOAT:
        shown = graph.swizzle(node, "xxx")
    elif type == NODE_VEC2:
        shown = graph.swizzle(node, "xyx")
    elif type == NODE_VEC4:
        shown = graph.swizzle(node, "xyz")
    graph.set_output(COLOR_NODE, shown)
    var source = Corners(graph.compile())
    return run_nodes(source, COLOR_NODE, here_inputs(source, textured))


def one(mut graph: NodeGraph, node: NodeRef) raises -> Float32:
    """Return the first lane of a node's value on `Corners`."""
    return on_corners(graph, node)[0]


def test_the_math_of_one_value_follows_glsl() raises:
    var graph = NodeGraph()
    var x = graph.vec4(-1.5, 0.5, 2.5, -0.25)
    assert_lanes(on_corners(graph, graph.abs(x)), 1.5, 0.5, 2.5)
    assert_lanes(on_corners(graph, graph.sign(graph.vec3(-2, 0, 3))), -1, 0, 1)
    assert_lanes(on_corners(graph, graph.floor(x)), -2, 0, 2)
    assert_lanes(on_corners(graph, graph.ceil(x)), -1, 1, 3)
    assert_lanes(on_corners(graph, graph.trunc(x)), -1, 0, 2)
    # A half goes to the even whole number, either way.
    assert_lanes(on_corners(graph, graph.round(x)), -2, 0, 2)
    assert_lanes(
        on_corners(graph, graph.round(graph.vec3(0.4, 0.6, 3.5))), 0, 1, 4
    )
    var two = graph.vec3(0, 1, 2)
    assert_lanes(on_corners(graph, graph.exp(two)), 1, 2.7182817, 7.389056)
    assert_lanes(on_corners(graph, graph.exp2(two)), 1, 2, 4)
    var many = graph.vec3(1, 4, 16)
    assert_lanes(on_corners(graph, graph.log(many)), 0, 1.3862944, 2.7725887)
    assert_lanes(on_corners(graph, graph.log2(many)), 0, 2, 4)
    assert_lanes(on_corners(graph, graph.sqrt(many)), 1, 2, 4)
    assert_lanes(on_corners(graph, graph.inverse_sqrt(many)), 1, 0.5, 0.25)
    assert_lanes(on_corners(graph, graph.reciprocal(many)), 1, 0.25, 0.0625)
    assert_lanes(on_corners(graph, graph.negate(two)), 0, -1, -2)
    assert_lanes(on_corners(graph, graph.one_minus(two)), 1, 0, -1)
    assert_lanes(on_corners(graph, graph.saturate(x)), 0, 0.5, 1)
    var angles = graph.vec3(0, 0.5, -1)
    assert_lanes(
        on_corners(graph, graph.tan(angles)),
        0,
        sin(Float32(0.5)) / cos(Float32(0.5)),
        sin(Float32(-1)) / cos(Float32(-1)),
    )
    assert_lanes(
        on_corners(graph, graph.radians(graph.vec3(180, 90, -45))),
        3.1415927,
        1.5707964,
        -0.7853982,
    )
    assert_lanes(
        on_corners(graph, graph.degrees(graph.vec3(3.1415927, 1, 0))),
        180,
        57.29578,
        0,
    )


def test_the_arc_functions_follow_glsl() raises:
    var graph = NodeGraph()
    # The three ranges `_atan` folds its argument through, both signs.
    assert_lanes(
        on_corners(graph, graph.atan(graph.vec3(0.25, -1, 10))),
        0.24497867,
        -0.7853982,
        1.4711276,
    )
    assert_lanes(
        on_corners(graph, graph.asin(graph.vec3(0.5, -1, 0))),
        0.5235988,
        -1.5707964,
        0,
    )
    assert_lanes(
        on_corners(graph, graph.acos(graph.vec3(0.5, -1, 1))),
        1.0471976,
        3.1415927,
        0,
    )
    # Every quadrant of `atan(y, x)`, and the axes.
    var y = graph.vec4(1, 1, -1, 0)
    var x = graph.vec4(1, -1, -1, -1)
    assert_lanes(
        on_corners(graph, graph.atan2(y, x)), 0.7853982, 2.3561945, -2.3561945
    )
    assert_almost_equal(
        one(graph, graph.swizzle(graph.atan2(y, x), "w")), 3.1415927
    )
    var up = graph.atan2(graph.vec3(1, -1, 0), graph.vec3(0, 0, 0))
    assert_lanes(on_corners(graph, up), 1.5707964, -1.5707964, 0)
    # Past one, an arc sine has no angle; a NaN reaches `atan(y, x)`.
    assert_true(isnan(one(graph, graph.asin(graph.float(2)))))
    var nan = graph.div(graph.float(0), graph.float(0))
    assert_true(isnan(one(graph, graph.atan2(graph.float(1), nan))))
    assert_true(isnan(one(graph, graph.atan2(nan, graph.float(1)))))


def test_the_math_of_two_and_three_values_follows_glsl() raises:
    var graph = NodeGraph()
    var a = graph.vec3(1, -2, 3)
    var b = graph.vec3(2, -3, 1)
    assert_lanes(on_corners(graph, graph.min(a, b)), 1, -3, 1)
    assert_lanes(on_corners(graph, graph.max(a, graph.float(0))), 1, 0, 3)
    # GLSL's mod follows the divisor's sign.
    assert_lanes(
        on_corners(graph, graph.mod(graph.vec3(5, -5, 5.5), graph.float(3))),
        2,
        1,
        2.5,
    )
    assert_almost_equal(one(graph, graph.distance(a, b)), sqrt(Float32(6)))
    assert_lanes(
        on_corners(
            graph, graph.cross(graph.vec3(1, 0, 0), graph.vec3(0, 1, 0))
        ),
        0,
        0,
        1,
    )
    var down = graph.vec3(1, -1, 0)
    var floor = graph.vec3(0, 1, 0)
    assert_lanes(on_corners(graph, graph.reflect(down, floor)), 1, 1, 0)
    # Straight through at a ratio of one, and nothing past the critical
    # angle.
    var slant = graph.normalize(down)
    assert_lanes(
        on_corners(graph, graph.refract(slant, floor, graph.float(1))),
        0.70710677,
        -0.70710677,
        0,
    )
    assert_lanes(
        on_corners(graph, graph.refract(slant, floor, graph.float(2))), 0, 0, 0
    )
    assert_lanes(
        on_corners(graph, graph.faceforward(floor, down, floor)), 0, 1, 0
    )
    var flat = graph.vec2(1, 0)
    with assert_raises(contains="crosses two vec3s, not a vec2 and a vec3"):
        _ = graph.cross(flat, a)
    with assert_raises(contains="crosses two vec3s, not a vec3 and a vec2"):
        _ = graph.cross(a, flat)
    with assert_raises(contains="ratio is a float, not a vec3"):
        _ = graph.refract(a, b, a)
    with assert_raises(contains="cannot orient a vec3 by a vec2"):
        _ = graph.faceforward(a, b, flat)
    with assert_raises(contains="cannot reflect a vec3 and a vec2"):
        _ = graph.reflect(a, flat)
    assert_lanes(
        on_corners(graph, graph.faceforward(floor, floor, floor)), 0, -1, 0
    )
    var ranged = graph.remap(
        graph.float(5),
        graph.float(0),
        graph.float(10),
        graph.float(100),
        graph.float(200),
    )
    assert_almost_equal(one(graph, ranged), 150)


def test_comparisons_logic_and_select_are_per_component() raises:
    var graph = NodeGraph()
    var a = graph.vec3(1, 2, 3)
    var b = graph.float(2)
    assert_lanes(on_corners(graph, graph.less_than(a, b)), 1, 0, 0)
    assert_lanes(on_corners(graph, graph.less_than_equal(a, b)), 1, 1, 0)
    assert_lanes(on_corners(graph, graph.greater_than(a, b)), 0, 0, 1)
    assert_lanes(on_corners(graph, graph.greater_than_equal(a, b)), 0, 1, 1)
    assert_lanes(on_corners(graph, graph.equal(a, b)), 0, 1, 0)
    assert_lanes(on_corners(graph, graph.not_equal(a, b)), 1, 0, 1)
    var p = graph.vec3(1, 1, 0)
    var q = graph.vec3(1, 0, 0)
    assert_lanes(on_corners(graph, graph.logical_and(p, q)), 1, 0, 0)
    assert_lanes(on_corners(graph, graph.logical_or(p, q)), 1, 1, 0)
    assert_lanes(on_corners(graph, graph.logical_xor(p, q)), 0, 1, 0)
    assert_lanes(on_corners(graph, graph.logical_not(p)), 0, 0, 1)
    var chosen = graph.select(p, graph.vec3(7, 8, 9), graph.float(-1))
    assert_lanes(on_corners(graph, chosen), 7, 8, -1)
    with assert_raises(contains="cannot compare a vec3 and a vec2"):
        _ = graph.less_than(a, graph.vec2(1, 1))
    with assert_raises(contains="cannot select"):
        _ = graph.select(graph.vec2(1, 1), a, a)


def test_a_join_lays_components_end_to_end() raises:
    var graph = NodeGraph()
    var one_part = graph.float(1)
    assert_equal(graph.join([one_part]), one_part)
    var pair = graph.join([graph.float(1), graph.float(2)])
    assert_equal(graph.type_of(pair), NODE_VEC2)
    assert_lanes(on_corners(graph, pair), 1, 2, 1)
    var three = graph.join([pair, graph.float(3)])
    assert_lanes(on_corners(graph, three), 1, 2, 3)
    var four = graph.join(
        [graph.float(4), graph.float(3), graph.float(2), graph.float(1)]
    )
    assert_equal(graph.type_of(four), NODE_VEC4)
    assert_lanes(on_corners(graph, graph.swizzle(four, "yzw")), 3, 2, 1)
    var split = graph.join([graph.float(9), pair, graph.float(8)])
    assert_lanes(on_corners(graph, graph.swizzle(split, "yzw")), 1, 2, 8)
    with assert_raises(contains="needs at least one part"):
        _ = graph.join(List[NodeRef]())
    with assert_raises(contains="at most four components, not 5"):
        _ = graph.join([three, pair])
    with assert_raises(contains="cannot join a mat4"):
        _ = graph.join([graph.camera_view_matrix(), pair])


def test_a_matrix_multiplies_a_vector_either_side() raises:
    var graph = NodeGraph()
    # Column-major: the first column is (1, 2, 3).
    var turn = Matrix3()
    for index in range(9):
        turn.elements[index] = Float32(index + 1)
    var m3 = graph.uniform("turn", turn)
    assert_equal(graph.type_of(m3), NODE_MAT3)
    var v = graph.vec3(1, 0, 1)
    # M v is the first column plus the third: (1+7, 2+8, 3+9).
    assert_lanes(on_corners(graph, graph.mul(m3, v)), 8, 10, 12)
    # v M is v dotted with each column: (1+3, 4+6, 7+9).
    assert_lanes(on_corners(graph, graph.mul(v, m3)), 4, 10, 16)
    var place = Matrix4()
    place.elements[12] = 5
    var m4 = graph.uniform("place", place)
    var point = graph.vec4(1, 2, 3, 1)
    assert_lanes(on_corners(graph, graph.mul(m4, point)), 6, 2, 3)
    var product = graph.mul(m4, point)
    graph.set_output(COLOR_NODE, graph.swizzle(product, "xyz"))
    var program = graph.compile()
    var moved = Matrix4()
    moved.elements[13] = -2
    program.set_uniform("place", moved)
    var quarter = Matrix3()
    program.set_uniform("turn", quarter)
    assert_lanes(run_nodes(Corners(program), COLOR_NODE, inputs()), 1, 0, 3)
    assert_equal(program.uniform("turn")[0], 1)
    with assert_raises(contains="is a mat3, not a mat4"):
        program.set_uniform("turn", Matrix4())
    with assert_raises(contains="is a mat4, not a mat3"):
        program.set_uniform("place", Matrix3())
    with assert_raises(contains="cannot multiply a mat3 and a vec4"):
        _ = graph.mul(m3, point)
    with assert_raises(contains="cannot multiply a mat3 and a mat4"):
        _ = graph.mul(m3, m4)
    with assert_raises(contains="cannot add a mat3"):
        _ = graph.add(m3, v)
    with assert_raises(contains="cannot compute with a mat4"):
        _ = graph.sin(m4)


def test_whole_numbers_and_their_bits() raises:
    var graph = NodeGraph()
    assert_lanes(
        on_corners(graph, graph.integer(graph.vec3(2.7, -2.7, 0.5))), 2, -2, 0
    )
    var wrapped = on_corners(graph, graph.unsigned(graph.vec3(3.9, -1, -2.5)))
    assert_equal(wrapped[0], 3)
    assert_equal(wrapped[1], Float32(4294967295.0))
    assert_equal(wrapped[2], Float32(4294967294.0))
    var a = graph.vec3(12, 10, -1)
    var b = graph.vec3(10, 6, 255)
    assert_lanes(on_corners(graph, graph.bit_and(a, b)), 8, 2, 255)
    assert_lanes(on_corners(graph, graph.bit_or(a, b)), 14, 14, -1)
    assert_lanes(on_corners(graph, graph.bit_xor(a, b)), 6, 12, -256)
    assert_lanes(on_corners(graph, graph.bit_not(a)), -13, -11, 0)
    assert_lanes(
        on_corners(
            graph, graph.shift_left(graph.vec3(3, 1, 1), graph.vec3(4, 33, 0))
        ),
        48,
        2,
        1,
    )
    assert_lanes(
        on_corners(
            graph, graph.shift_right(graph.vec3(-16, 64, 7), graph.float(2))
        ),
        -4,
        16,
        1,
    )
    # NaN is zero, and a number past 32 bits is held at the end.
    var nan = graph.div(graph.float(0), graph.float(0))
    assert_equal(one(graph, graph.bit_or(nan, graph.float(0))), 0)
    assert_equal(
        one(graph, graph.bit_or(graph.float(1e10), graph.float(0))),
        Float32(2147483520),
    )
    with assert_raises(contains="cannot take the bits of a vec3 and a vec2"):
        _ = graph.bit_and(a, graph.vec2(1, 2))


def test_a_matrix_is_built_turned_and_inverted() raises:
    var graph = NodeGraph()
    var m = graph.mat3(
        graph.vec3(2, 0, 0), graph.vec3(1, 3, 0), graph.vec3(0, 0, 4)
    )
    var ones = graph.vec3(1, 1, 1)
    # Its columns weighted, and its columns dotted.
    assert_lanes(on_corners(graph, graph.mul(m, ones)), 3, 3, 4)
    assert_lanes(on_corners(graph, graph.mul(ones, m)), 2, 4, 4)
    assert_lanes(on_corners(graph, graph.column(m, 1)), 1, 3, 0)
    assert_almost_equal(one(graph, graph.determinant(m)), 24)
    assert_lanes(
        on_corners(graph, graph.mul(graph.transpose(m), ones)), 2, 4, 4
    )
    var v = graph.vec3(1, 2, 3)
    var back = graph.mul(m, graph.mul(graph.inverse(m), v))
    var lanes = on_corners(graph, back)
    for lane in range(3):
        assert_almost_equal(lanes[lane], Float32(lane + 1), atol=1e-5)
    # A mat4, triangular: its determinant is its diagonal's product.
    var four = graph.mat4(
        graph.vec4(1, 0, 0, 0),
        graph.vec4(1, 2, 0, 0),
        graph.vec4(0, 0, 3, 0),
        graph.vec4(0, 0, 1, 4),
    )
    assert_almost_equal(one(graph, graph.determinant(four)), 24, atol=1e-4)
    var w = graph.vec4(4, 3, 2, 1)
    # `on_corners` shows a vec4's first three lanes, so the fourth is
    # read on its own.
    var undone = graph.mul(four, graph.mul(graph.inverse(four), w))
    var front = on_corners(graph, undone)
    for lane in range(3):
        assert_almost_equal(front[lane], Float32(4 - lane), atol=1e-5)
    assert_almost_equal(one(graph, graph.swizzle(undone, "w")), 1, atol=1e-5)
    assert_lanes(
        on_corners(graph, graph.swizzle(graph.column(four, 3), "zwx")), 1, 4, 0
    )
    # A uniform's columns, and a product of a built matrix and a uniform.
    var identity = graph.uniform("identity", Matrix4())
    assert_almost_equal(one(graph, graph.determinant(identity)), 1)
    var product = graph.mul(four, identity)
    var same = on_corners(graph, graph.swizzle(graph.mul(product, w), "yzw"))
    var direct = on_corners(graph, graph.swizzle(graph.mul(four, w), "yzw"))
    for lane in range(3):
        assert_almost_equal(same[lane], direct[lane])
    var turned = graph.uniform("turned", Matrix3())
    assert_lanes(
        on_corners(graph, graph.mul(graph.inverse(turned), v)), 1, 2, 3
    )


def test_a_matrix_function_refuses_what_it_cannot_do() raises:
    var graph = NodeGraph()
    var m3 = graph.mat3(
        graph.vec3(1, 0, 0), graph.vec3(0, 1, 0), graph.vec3(0, 0, 1)
    )
    var m4 = graph.uniform("m4", Matrix4())
    with assert_raises(contains="cannot multiply a mat3 and a mat4"):
        _ = graph.mul(m3, m4)
    with assert_raises(contains="made of vec3 columns, not a vec4"):
        _ = graph.mat3(
            graph.vec3(1, 0, 0), graph.vec3(0, 1, 0), graph.vec4(0, 0, 0, 1)
        )
    with assert_raises(contains="A mat3 has no column 3"):
        _ = graph.column(m3, 3)
    with assert_raises(contains="A mat3 has no column -1"):
        _ = graph.column(m3, -1)
    with assert_raises(contains="can transpose a mat3 or a mat4, not a vec3"):
        _ = graph.transpose(graph.vec3(1, 2, 3))
    # An edit that makes an instruction read a built matrix is refused.
    var edited = NodeGraph()
    var uniform = edited.uniform("m", Matrix3())
    var moved = edited.mul(uniform, edited.vec3(1, 2, 3))
    edited.set_output(COLOR_NODE, moved)
    var built = edited.mat3(
        edited.vec3(1, 0, 0), edited.vec3(0, 1, 0), edited.vec3(0, 0, 1)
    )
    edited.set_input(moved, 1, built)
    with assert_raises(contains="only multiplied"):
        _ = edited.compile()


def test_the_view_matrix_and_the_camera_come_from_the_frame() raises:
    # The camera stands at (0, 0, 5) looking down minus z.
    var view = Matrix4()
    view.elements[14] = -5
    var graph = NodeGraph()
    var eye = graph.camera_position()
    var into = graph.mul(graph.camera_view_matrix(), graph.vec4(1, 2, 3, 1))
    graph.set_output(COLOR_NODE, eye)
    graph.set_output(EMISSIVE_NODE, graph.swizzle(into, "xyz"))
    var program = graph.compile()
    program.set_frame(Duration(0.0, SECOND), view)
    var source = ProgramSource(Pointer(to=program))
    assert_lanes(run_nodes(source, COLOR_NODE, inputs()), 0, 0, 5)
    assert_lanes(run_nodes(source, EMISSIVE_NODE, inputs()), 1, 2, -2)


def test_a_vec4_uniform_is_set_and_read() raises:
    var graph = NodeGraph()
    var tint = graph.uniform("tint", Vector4(1, 2, 3, 4))
    graph.set_output(COLOR_NODE, graph.swizzle(tint, "wzy"))
    var program = graph.compile()
    assert_lanes(run_nodes(Corners(program), COLOR_NODE, inputs()), 4, 3, 2)
    program.set_uniform("tint", Vector4(5, 6, 7, 8))
    assert_lanes(run_nodes(Corners(program), COLOR_NODE, inputs()), 8, 7, 6)
    with assert_raises(contains="is a vec4, not a vec3"):
        program.set_uniform("tint", Vector3(1, 1, 1))


def test_a_texture_uniform_is_read_and_changed() raises:
    var graph = NodeGraph()
    var map = graph.texture_uniform("map", TextureId(2))
    assert_equal(graph.type_of(map), NODE_SAMPLER)
    var read = graph.texture(map, graph.uv())
    var again = graph.texture(map, graph.mul(graph.uv(), graph.float(2)))
    var fixed = graph.texture(TextureId(5), graph.uv())
    var twice = graph.texture(TextureId(5), graph.uv())
    graph.set_output(COLOR_NODE, graph.swizzle(graph.add(read, again), "xyz"))
    graph.set_output(
        EMISSIVE_NODE, graph.swizzle(graph.add(fixed, twice), "xyz")
    )
    var program = graph.compile()
    # The uniform is one texture however many nodes read it.
    assert_equal(len(program.textures), 2)
    assert_equal(program.textures[0].value, 2)
    assert_equal(program.textures[1].value, 5)
    assert_lanes(
        run_nodes(Checker(program), COLOR_NODE, inputs(True)), 0.75, 2.25, 4
    )
    program.set_texture("map", TextureId(7))
    assert_equal(program.textures[0].value, 7)
    assert_lanes(
        run_nodes(Checker(program), COLOR_NODE, inputs(True)), 0.75, 2.25, 14
    )
    with assert_raises(contains="needs a texture"):
        program.set_texture("map", NO_TEXTURE)
    with assert_raises(contains="is a texture, not a float"):
        program.set_uniform("map", Float32(1))
    # A texture set later lists as none until it is.
    var later = NodeGraph()
    var unset = later.texture_uniform("later")
    later.set_output(
        COLOR_NODE, later.swizzle(later.texture(unset, later.uv()), "xyz")
    )
    var waiting = later.compile()
    assert_equal(waiting.textures[0], NO_TEXTURE)
    with assert_raises(contains="names no texture there can be"):
        _ = later.texture_uniform("bad", TextureId(-2))
    with assert_raises(contains="reads a texture, not a vec2"):
        _ = later.texture(later.uv(), later.uv())
    with assert_raises(contains="reads at a vec2, not a vec3"):
        _ = later.texture(unset, later.vec3(0, 0, 0))


def test_a_variable_holds_what_was_last_assigned() raises:
    var graph = NodeGraph()
    var v = graph.Var(graph.vec3(1, 2, 3))
    var first = graph.get(v)
    graph.assign(v, graph.float(5))
    assert_lanes(on_corners(graph, first), 1, 2, 3)
    assert_lanes(on_corners(graph, graph.get(v)), 5, 5, 5)
    with assert_raises(contains="no variable with that ref"):
        _ = graph.get(NodeVar(3))
    with assert_raises(contains="no variable with that ref"):
        graph.assign(NodeVar(-1), first)
    with assert_raises(contains="cannot assign a vec3 and a vec2"):
        graph.assign(v, graph.vec2(1, 1))
    with assert_raises(contains="cannot hold a texture"):
        _ = graph.Var(graph.texture_uniform("map", TextureId(0)))


def test_an_if_makes_each_changed_variable_a_select() raises:
    var graph = NodeGraph()
    var x = graph.Var(graph.float(0))
    var y = graph.Var(graph.float(10))
    var inside = graph.Var(graph.float(0))
    var u = graph.swizzle(graph.uv(), "x")
    # Here u is a quarter: the second branch runs.
    graph.If(graph.greater_than(u, graph.float(0.5)))
    graph.assign(x, graph.float(1))
    var late = graph.Var(graph.float(3))
    graph.assign(late, graph.float(4))
    graph.Else()
    graph.assign(x, graph.float(2))
    graph.assign(inside, graph.float(6))
    graph.End()
    assert_almost_equal(one(graph, graph.get(x)), 2)
    assert_almost_equal(one(graph, graph.get(y)), 10)
    assert_almost_equal(one(graph, graph.get(inside)), 6)
    # An If without an Else keeps what came before where it does not run.
    graph.If(graph.greater_than(u, graph.float(0.5)))
    graph.assign(y, graph.float(20))
    graph.End()
    assert_almost_equal(one(graph, graph.get(y)), 10)
    # An ElseIf chain, closed by one End.
    var z = graph.Var(graph.float(0))
    graph.If(graph.less_than(u, graph.float(0)))
    graph.assign(z, graph.float(1))
    graph.ElseIf(graph.less_than(u, graph.float(0.3)))
    graph.assign(z, graph.float(2))
    graph.Else()
    graph.assign(z, graph.float(3))
    graph.End()
    assert_almost_equal(one(graph, graph.get(z)), 2)
    assert_equal(len(graph._blocks), 0)
    with assert_raises(contains="A condition is a float, not a vec2"):
        graph.If(graph.uv())
    with assert_raises(contains="An Else needs an If"):
        graph.Else()
    with assert_raises(contains="An End needs an If or a Loop"):
        graph.End()
    graph.If(graph.float(1))
    graph.Else()
    with assert_raises(contains="An Else needs an If"):
        graph.Else()
    with assert_raises(contains="An Else needs an If"):
        graph.ElseIf(graph.float(1))
    graph.End()
    _ = graph.Loop(2)
    with assert_raises(contains="An Else needs an If"):
        graph.Else()


def test_a_loop_runs_its_body_its_count_of_times() raises:
    var graph = NodeGraph()
    var sum = graph.Var(graph.float(0))
    var steps = graph.Var(graph.float(0))
    var index = graph.Loop(4, 1, 2)
    # 1 + 3 + 5 + 7 and four steps.
    graph.assign(sum, graph.add(graph.get(sum), index))
    graph.assign(steps, graph.add(graph.get(steps), graph.float(1)))
    # A uniform made in the body is one uniform, not four.
    _ = graph.uniform("once", Float32(1))
    graph.End()
    assert_almost_equal(one(graph, graph.get(sum)), 16)
    assert_almost_equal(one(graph, graph.get(steps)), 4)
    # A loop inside a loop, and a branch inside a loop.
    var grid = graph.Var(graph.float(0))
    var i = graph.Loop(3)
    var j = graph.Loop(2)
    graph.If(graph.greater_than(j, i))
    graph.assign(grid, graph.add(graph.get(grid), graph.float(10)))
    graph.Else()
    graph.assign(grid, graph.add(graph.get(grid), graph.float(1)))
    graph.End()
    graph.End()
    graph.End()
    # Pairs (i, j) with j > i: only (0, 1); five others.
    assert_almost_equal(one(graph, graph.get(grid)), 15)
    # A loop of none leaves its variables alone, and one of one runs once.
    var kept = graph.Var(graph.float(7))
    _ = graph.Loop(0)
    graph.assign(kept, graph.float(8))
    graph.End()
    assert_almost_equal(one(graph, graph.get(kept)), 7)
    _ = graph.Loop(1)
    graph.assign(kept, graph.add(graph.get(kept), graph.float(1)))
    graph.End()
    assert_almost_equal(one(graph, graph.get(kept)), 8)
    # A loop of an empty body, in a graph of no variables.
    var empty = NodeGraph()
    _ = empty.Loop(3)
    empty.End()
    # The index and its value each time after the first, and the two
    # flags a Break and a Continue set, each with a copy the body reads
    # and a Continue's reset.
    assert_equal(empty.count(), 8)
    with assert_raises(contains="A Loop runs from zero to 1024 times, not -1"):
        _ = graph.Loop(-1)
    with assert_raises(contains="not 1025"):
        _ = graph.Loop(MAX_LOOP_COUNT + 1)
    # Nested loops that would grow the graph too far are refused.
    var grown = NodeGraph()
    var total = grown.Var(grown.float(0))
    var outer = grown.Loop(1000)
    _ = grown.Loop(1000)
    grown.assign(total, grown.add(grown.get(total), outer))
    grown.End()
    with assert_raises(contains="past 65536 nodes"):
        grown.End()


def test_a_break_leaves_the_loop() raises:
    var graph = NodeGraph()
    var sum = graph.Var(graph.float(0))
    var index = graph.Loop(10)
    graph.If(graph.greater_than(index, graph.float(3.5)))
    graph.Break()
    graph.End()
    graph.assign(sum, graph.add(graph.get(sum), index))
    graph.End()
    # 0 + 1 + 2 + 3, and nothing after.
    assert_almost_equal(one(graph, graph.get(sum)), 6)
    # A break at the end of the body: what came before it in the same
    # time through counts, and no later time does.
    var last = graph.Var(graph.float(0))
    var i = graph.Loop(5)
    graph.assign(last, i)
    graph.If(graph.greater_than(i, graph.float(1.5)))
    graph.Break()
    graph.End()
    graph.End()
    assert_almost_equal(one(graph, graph.get(last)), 2)


def test_a_continue_skips_the_rest_of_one_time_through() raises:
    var graph = NodeGraph()
    var odd = graph.Var(graph.float(0))
    var index = graph.Loop(6)
    graph.If(
        graph.less_than(graph.mod(index, graph.float(2)), graph.float(0.5))
    )
    graph.Continue()
    graph.End()
    graph.assign(odd, graph.add(graph.get(odd), index))
    graph.End()
    assert_almost_equal(one(graph, graph.get(odd)), 9)


def test_a_break_and_a_continue_meet_in_either_order() raises:
    # Even numbers below seven: 0 + 2 + 4 + 6, whichever comes first.
    for breaks_first in [False, True]:
        var graph = NodeGraph()
        var sum = graph.Var(graph.float(0))
        var index = graph.Loop(10)
        for step in range(2):
            if (step == 0) == breaks_first:
                graph.If(graph.greater_than(index, graph.float(6.5)))
                graph.Break()
                graph.End()
            else:
                graph.If(
                    graph.greater_than(
                        graph.mod(index, graph.float(2)), graph.float(0.5)
                    )
                )
                graph.Continue()
                graph.End()
        graph.assign(sum, graph.add(graph.get(sum), index))
        graph.End()
        assert_almost_equal(one(graph, graph.get(sum)), 12)
    # A break in a loop of none changes nothing.
    var none = NodeGraph()
    var kept = none.Var(none.float(5))
    _ = none.Loop(0)
    none.Break()
    none.assign(kept, none.float(6))
    none.End()
    assert_almost_equal(one(none, none.get(kept)), 5)


def test_a_break_leaves_only_its_own_loop() raises:
    var graph = NodeGraph()
    var count = graph.Var(graph.float(0))
    var outer = graph.Loop(4)
    var inner = graph.Loop(4)
    graph.If(graph.greater_than(inner, outer))
    graph.Break()
    graph.End()
    graph.assign(count, graph.add(graph.get(count), graph.float(1)))
    graph.End()
    graph.If(graph.greater_than(outer, graph.float(1.5)))
    graph.Break()
    graph.End()
    graph.End()
    # Outer 0 counts one, 1 two and 2 three, and then the outer loop stops.
    assert_almost_equal(one(graph, graph.get(count)), 6)


def test_a_discard_after_a_break_throws_nothing_away() raises:
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.vec3(1, 1, 1))
    var index = graph.Loop(3)
    graph.If(graph.greater_than(index, graph.float(0.5)))
    graph.Discard()
    graph.End()
    graph.Break()
    graph.Discard()
    graph.End()
    assert_equal(run_nodes(Corners(graph.compile()), MASK_NODE, inputs())[0], 1)
    # A discard before the loop is not the loop's to stop.
    var before = NodeGraph()
    before.set_output(COLOR_NODE, before.vec3(1, 1, 1))
    before.Discard()
    _ = before.Loop(2)
    before.Break()
    before.End()
    assert_equal(
        run_nodes(Corners(before.compile()), MASK_NODE, inputs())[0], 0
    )


def capped(mut graph: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
    graph.If(graph.greater_than(args[0], graph.float(1)))
    graph.Return(graph.float(1))
    graph.End()
    return args[0]


def first_square_over(
    mut graph: NodeGraph, args: List[NodeRef]
) raises -> NodeRef:
    var i = graph.Loop(8)
    graph.If(graph.greater_than(graph.mul(i, i), args[0]))
    graph.Return(i)
    graph.End()
    graph.End()
    return graph.float(-1)


def returns_early(mut graph: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
    var v = graph.Var(args[0])
    graph.Return(graph.get(v))
    graph.assign(v, graph.float(99))
    graph.Return(graph.float(98))
    return graph.get(v)


def returns_twice_in_a_loop(
    mut graph: NodeGraph, args: List[NodeRef]
) raises -> NodeRef:
    """Return the first index past `args[0]` if the first time through
    finds one, and minus two otherwise: a second `Return` in a loop, where
    the first one's flag gates it."""
    var i = graph.Loop(4)
    graph.If(graph.greater_than(i, args[0]))
    graph.Return(i)
    graph.End()
    graph.Return(graph.float(-2))
    graph.End()
    return graph.float(-1)


def returns_the_wrong_type(
    mut graph: NodeGraph, args: List[NodeRef]
) raises -> NodeRef:
    graph.Return(args[0])
    return graph.vec3(1, 2, 3)


def test_a_return_gives_the_functions_answer_where_it_runs() raises:
    var graph = NodeGraph()
    var cap = Fn("capped", [NODE_FLOAT], NODE_FLOAT, capped)
    assert_almost_equal(one(graph, graph.call(cap, [graph.float(3)])), 1)
    assert_almost_equal(one(graph, graph.call(cap, [graph.float(0.5)])), 0.5)
    var search = Fn("first", [NODE_FLOAT], NODE_FLOAT, first_square_over)
    assert_almost_equal(one(graph, graph.call(search, [graph.float(10)])), 4)
    assert_almost_equal(one(graph, graph.call(search, [graph.float(100)])), -1)
    # A bound only the fragment knows: the Return is gated where it runs.
    var bound = graph.mul(graph.swizzle(graph.uv(), "x"), graph.float(40))
    var wanted = Float32(-1)
    for i in range(8):
        if Float32(i * i) > one(graph, bound):
            wanted = Float32(i)
            break
    assert_true(wanted > 0)
    assert_almost_equal(one(graph, graph.call(search, [bound])), wanted)
    var twice = Fn("twice", [NODE_FLOAT], NODE_FLOAT, returns_twice_in_a_loop)
    assert_almost_equal(one(graph, graph.call(twice, [graph.float(-1)])), 0)
    assert_almost_equal(one(graph, graph.call(twice, [graph.float(1.5)])), -2)
    var early = Fn("early", [NODE_VEC3], NODE_VEC3, returns_early)
    assert_lanes(
        on_corners(graph, graph.call(early, [graph.vec3(1, 2, 3)])), 1, 2, 3
    )
    var wrong = Fn("wrong", [NODE_FLOAT], NODE_FLOAT, returns_the_wrong_type)
    with assert_raises(contains="returns a float, not a vec3"):
        _ = graph.call(wrong, [graph.float(1)])
    with assert_raises(contains="A Return needs a Fn to be in"):
        graph.Return(graph.float(1))
    with assert_raises(contains="A Break needs a Loop to be in"):
        graph.Break()
    graph.If(graph.float(1))
    with assert_raises(contains="A Continue needs a Loop to be in"):
        graph.Continue()
    graph.End()


def test_a_discard_joins_the_mask() raises:
    # A graph with nothing but a discard compiles: its mask is the output.
    var graph = NodeGraph()
    var u = graph.swizzle(graph.uv(), "x")
    graph.If(graph.greater_than(u, graph.float(0.5)))
    graph.Discard()
    graph.Else()
    graph.If(graph.less_than(u, graph.float(0)))
    graph.Discard()
    graph.End()
    graph.End()
    var program = graph.compile()
    assert_true(program.has(MASK_NODE))
    # u is a quarter: neither branch discards.
    assert_equal(
        run_nodes(Corners(program), MASK_NODE, inputs()), Lanes(1, 0, 0, 0)
    )
    var near = NodeInputs(
        0.75,
        0.5,
        Vector3(0, 0, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        False,
    )
    assert_equal(run_nodes(Corners(program), MASK_NODE, near)[0], 0)
    # A discard outside every branch throws everything away, and joins a
    # mask the graph sets.
    var always = NodeGraph()
    always.set_output(MASK_NODE, always.float(1))
    always.Discard()
    assert_equal(
        run_nodes(Corners(always.compile()), MASK_NODE, inputs())[0], 0
    )
    # A discard in a loop's body counts each time, and in a loop of none,
    # never.
    var looped = NodeGraph()
    var index = looped.Loop(3)
    looped.If(looped.greater_than(index, looped.float(1.5)))
    looped.Discard()
    looped.End()
    looped.End()
    assert_equal(len(looped._discards), 3)
    assert_equal(
        run_nodes(Corners(looped.compile()), MASK_NODE, inputs())[0], 0
    )
    var never = NodeGraph()
    never.set_output(COLOR_NODE, never.vec3(1, 1, 1))
    _ = never.Loop(0)
    never.Discard()
    never.End()
    assert_equal(len(never._discards), 0)
    assert_false(never.compile().has(MASK_NODE))
    # A discard made before the loop stays.
    var before = NodeGraph()
    before.Discard()
    _ = before.Loop(0)
    before.Discard()
    before.End()
    assert_equal(len(before._discards), 1)


def double(mut graph: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
    """A function body: twice its first argument plus its second."""
    return graph.add(graph.mul(args[0], graph.float(2)), args[1])


def seven(mut graph: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
    """A function body of no arguments."""
    return graph.float(7)


def leaves_open(mut graph: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
    """A function body that opens an If and never closes it."""
    graph.If(args[0])
    return args[0]


def test_a_fn_checks_its_layout_and_inlines_its_body() raises:
    var graph = NodeGraph()
    var twice = Fn("twice", [NODE_VEC3, NODE_FLOAT], NODE_VEC3, double)
    var out = graph.call(twice, [graph.vec3(1, 2, 3), graph.float(1)])
    assert_lanes(on_corners(graph, out), 3, 5, 7)
    with assert_raises(contains="The Fn twice takes 2 arguments, not 1"):
        _ = twice.call(graph, [graph.float(1)])
    with assert_raises(contains="takes a vec3 as argument 1, not a float"):
        _ = twice.call(graph, [graph.float(1), graph.float(1)])
    var wrong = Fn("wrong", [NODE_FLOAT, NODE_FLOAT], NODE_VEC3, double)
    with assert_raises(contains="The Fn wrong returns a vec3, not a float"):
        _ = wrong.call(graph, [graph.float(1), graph.float(1)])
    var open = Fn("open", [NODE_FLOAT], NODE_FLOAT, leaves_open)
    with assert_raises(contains="The Fn open leaves an If or a Loop open"):
        _ = open.call(graph, [graph.float(1)])
    with assert_raises(contains="takes floats and vectors"):
        _ = Fn("sampled", [NODE_SAMPLER], NODE_FLOAT, double)
    # A function of nothing.
    var nothing = Fn("seven", List[ValueType](), NODE_FLOAT, seven)
    var fresh = NodeGraph()
    assert_almost_equal(one(fresh, nothing.call(fresh, List[NodeRef]())), 7)
    with assert_raises(contains="returns a float or a vector"):
        _ = Fn("matrix", [NODE_FLOAT], NODE_MAT3, double)


def test_a_varying_is_computed_per_corner_and_interpolated() raises:
    var graph = NodeGraph()
    # The world position is linear already; its square is not, so the
    # corners' squares mixed differ from the fragment's own square.
    var p = graph.position_world()
    var squared = graph.mul(p, p)
    # Corners: (0,0,0), (16,0,0), (0,16,0), weighed 1/2, 1/4, 1/4.
    assert_lanes(on_corners(graph, graph.varying(squared)), 4, 4, 0)
    assert_lanes(on_corners(graph, squared), 1, 1, 0)
    # A corner's normal is made unit length before the math reads it.
    assert_lanes(
        on_corners(graph, graph.varying(graph.normal_world())), 0.25, 0.25, 0.5
    )
    assert_lanes(
        on_corners(graph, graph.varying(graph.vertex_color())), 0.5, 0.25, 0.25
    )
    assert_lanes(
        on_corners(graph, graph.varying(graph.swizzle(graph.uv(), "yxy"))),
        0.25,
        0.25,
        0.25,
    )
    # A varying of what does not vary is itself, and a varying of a
    # varying is the varying.
    assert_lanes(on_corners(graph, graph.varying(graph.vec3(1, 2, 3))), 1, 2, 3)
    assert_lanes(
        on_corners(graph, graph.varying(graph.varying(squared))), 4, 4, 0
    )
    var view = graph.varying(
        graph.add(graph.position_view(), graph.normal_view())
    )
    assert_lanes(on_corners(graph, view), 1.25, 1.25, 0.5)
    with assert_raises(contains="cannot interpolate a texture"):
        _ = graph.varying(graph.texture_uniform("map", TextureId(0)))
    var textured = NodeGraph()
    textured.set_output(
        COLOR_NODE,
        textured.varying(
            textured.swizzle(
                textured.texture(TextureId(0), textured.uv()), "xyz"
            )
        ),
    )
    with assert_raises(contains="it reads no texture and no derivative"):
        _ = textured.compile()
    var sloped = NodeGraph()
    sloped.set_output(
        COLOR_NODE, sloped.varying(sloped.dfdx(sloped.position_world()))
    )
    with assert_raises(contains="it reads no texture and no derivative"):
        _ = sloped.compile()
    var lit = NodeGraph()
    lit.set_output(OUTPUT_NODE, lit.varying(lit.lit()))
    with assert_raises(contains="cannot read the lit color"):
        _ = lit.compile()


def test_a_derivative_is_the_difference_to_the_pixel_beside() raises:
    var graph = NodeGraph()
    # The coordinates: (0.25, 0.25) here, (0.5, 0.25) right, (0.25, 0.5) up.
    assert_lanes(
        on_corners(graph, graph.swizzle(graph.dfdx(graph.uv()), "xyx")),
        0.25,
        0,
        0.25,
    )
    assert_lanes(on_corners(graph, graph.dfdy(graph.position_world())), 0, 1, 0)
    assert_lanes(
        on_corners(graph, graph.fwidth(graph.position_world())), 1, 1, 0
    )
    # A derivative of what does not vary is zero.
    assert_lanes(on_corners(graph, graph.dfdx(graph.vec3(1, 2, 3))), 0, 0, 0)
    assert_lanes(on_corners(graph, graph.dfdy(graph.time())), 0, 0, 0)
    # The normal a derivative reads is the interpolated one, in both
    # places; here it is (0.5, 0.5, 1) made unit, to the right (0.5, 1,
    # 0.5) made unit.
    var slope = graph.dfdx(graph.normal_world())
    var r = 1 / sqrt(Float32(1.5))
    assert_lanes(
        on_corners(graph, slope), 0.5 * r - 0.5 * r, r - 0.5 * r, 0.5 * r - r
    )
    # A derivative of a varying moves the weights, not the corners.
    var p = graph.position_world()
    var squared = graph.varying(graph.mul(p, p))
    # Right: 16 * 0.5 = 8 in x, less 4 here.
    assert_lanes(on_corners(graph, graph.dfdx(squared)), 4, 0, 0)
    # A texture beside is read at the coordinate beside.
    var beside = graph.dfdx(graph.texture(TextureId(3), graph.uv()))
    assert_lanes(on_corners(graph, beside, True), 0.25, 0, 0)
    # The derivatives of the view position read the frame's view.
    assert_lanes(on_corners(graph, graph.dfdy(graph.position_view())), 0, 1, 0)
    var nested = NodeGraph()
    nested.set_output(
        COLOR_NODE, nested.dfdx(nested.dfdy(nested.position_world()))
    )
    with assert_raises(contains="A derivative cannot read another derivative"):
        _ = nested.compile()
    var lit = NodeGraph()
    lit.set_output(OUTPUT_NODE, lit.dfdx(lit.lit()))
    with assert_raises(contains="cannot read the lit color"):
        _ = lit.compile()
    with assert_raises(contains="cannot differentiate a mat4"):
        _ = graph.dfdx(graph.camera_view_matrix())


def near3(got: Lanes, x: Float64, y: Float64, z: Float64) raises:
    assert_almost_equal(Float64(got[0]), x, atol=1e-6)
    assert_almost_equal(Float64(got[1]), y, atol=1e-6)
    assert_almost_equal(Float64(got[2]), z, atol=1e-6)


def test_the_other_materialx_noises_are_three_js_s() raises:
    # Values from three.js's `mx_noise.js`, transcribed in 32-bit floats
    # by `assets/noise/mx_noise.py`.
    near3(
        perlin_noise_vec3(Lanes(0.3, 0.7, 0, 0), 2),
        0.04074367880821228,
        0.6510121822357178,
        -0.30239030718803406,
    )
    near3(
        perlin_noise_vec3(Lanes(3.1, -2.3, 5.9, 0), 3),
        0.07585524767637253,
        -0.061793237924575806,
        0.1329670399427414,
    )
    assert_almost_equal(
        Float64(cell_noise(Lanes(0.3, 0, 0, 0), 1)), 0.5824258327484131
    )
    assert_almost_equal(
        Float64(cell_noise(Lanes(-1.25, 2.5, 0, 0), 2)), 0.5628882646560669
    )
    assert_almost_equal(
        Float64(cell_noise(Lanes(0.3, 0.7, 0.2, 0), 3)), 0.6110676527023315
    )
    assert_almost_equal(
        Float64(cell_noise(Lanes(3.1, -2.3, 5.9, -0.4), 4)), 0.4390026032924652
    )
    near3(
        cell_noise_vec3(Lanes(0.3, 0, 0, 0), 1),
        0.8603127598762512,
        0.842521071434021,
        0.9748212099075317,
    )
    near3(
        cell_noise_vec3(Lanes(3.1, -2.3, 5.9, -0.4), 4),
        0.11370349675416946,
        0.10571760684251785,
        0.41482704877853394,
    )
    near3(
        worley_noise(Lanes(0.3, 0.7, 0, 0), 2, 1, 3),
        0.3611402213573456,
        0.4000799059867859,
        1.0939582586288452,
    )
    # Two distances: a vec2, whose third lane is not its own.
    var pair = worley_noise(Lanes(0.3, 0.7, 0, 0), 2, 0.5, 2)
    assert_almost_equal(Float64(pair[0]), 0.19280943274497986, atol=1e-6)
    assert_almost_equal(Float64(pair[1]), 0.459095299243927, atol=1e-6)
    near3(
        worley_noise(Lanes(-1.25, 2.5, 0.6, 0), 3, 0.5, 3),
        0.09683658182621002,
        0.5652338266372681,
        0.6648467183113098,
    )
    assert_almost_equal(
        Float64(worley_noise(Lanes(-1.25, 2.5, 0.6, 0), 3, 1, 1)[0]),
        0.2914171814918518,
        atol=1e-6,
    )
    # Through the graph.
    var graph = NodeGraph()
    var point = graph.vec3(0.3, 0.7, 0.2)
    near3(
        on_corners(graph, graph.mx_noise_vec3(point, 2, 1)),
        2 * 0.2737118899822235 + 1,
        2 * -0.18833453953266144 + 1,
        2 * 0.40486136078834534 + 1,
    )
    var four = graph.mx_noise_vec4(graph.vec2(0.3, 0.7))
    near3(
        on_corners(graph, four),
        0.04074367880821228,
        0.6510121822357178,
        -0.30239030718803406,
    )
    var moved = graph.perlin_noise(graph.vec2(19.3, 73.7))
    assert_almost_equal(one(graph, graph.swizzle(four, "w")), one(graph, moved))
    var deep = graph.mx_noise_vec4(point)
    var shifted = graph.perlin_noise(graph.vec3(19.3, 73.7, 0.2))
    assert_almost_equal(
        one(graph, graph.swizzle(deep, "w")), one(graph, shifted)
    )
    assert_almost_equal(
        one(graph, graph.cell_noise_float(point)), 0.6110676527023315
    )
    near3(
        on_corners(graph, graph.cell_noise_vec3(graph.float(0.3))),
        0.8603127598762512,
        0.842521071434021,
        0.9748212099075317,
    )
    var jitter = graph.float(0.5)
    var two = on_corners(
        graph, graph.worley_noise(graph.vec2(0.3, 0.7), jitter, 2)
    )
    assert_almost_equal(Float64(two[0]), 0.19280943274497986, atol=1e-6)
    assert_almost_equal(Float64(two[1]), 0.459095299243927, atol=1e-6)
    with assert_raises(
        contains="Perlin noise reads a vec2 to a vec3, not a float"
    ):
        _ = graph.perlin_noise_vec3(graph.float(1))
    with assert_raises(
        contains="Cell noise reads a float to a vec4, not a mat4"
    ):
        _ = graph.cell_noise_float(graph.camera_view_matrix())
    with assert_raises(
        contains="Worley noise reads a vec2 to a vec3, not a vec4"
    ):
        _ = graph.worley_noise(graph.vec4(1, 2, 3, 4), jitter, 1)
    with assert_raises(contains="jitter is a float, not a vec2"):
        _ = graph.worley_noise(graph.vec2(1, 2), graph.vec2(1, 2), 1)
    with assert_raises(contains="one to three distances, not 4"):
        _ = graph.worley_noise(graph.vec2(1, 2), jitter, 4)
    with assert_raises(contains="one to three distances, not 0"):
        _ = graph.worley_noise(graph.vec2(1, 2), jitter, 0)


def test_perlin_noise_is_materialxs() raises:
    # Values from three.js's `mx_noise.js`, transcribed and run in 32-bit
    # floats.
    assert_almost_equal(perlin_noise(Lanes(0.3, 0.7, 0, 0), 2), 0.04074368)
    assert_almost_equal(perlin_noise(Lanes(-1.25, 2.5, 0, 0), 2), -0.49910742)
    assert_almost_equal(perlin_noise(Lanes(10.1, -3.3, 0, 0), 2), 0.31854936)
    assert_equal(perlin_noise(Lanes(0.5, 0.5, 0, 0), 2), 0)
    assert_almost_equal(perlin_noise(Lanes(0.3, 0.7, 0.2, 0), 3), 0.27371189)
    assert_almost_equal(
        perlin_noise(Lanes(-1.25, 2.5, -0.75, 0), 3), -0.15042429
    )
    assert_almost_equal(perlin_noise(Lanes(3.1, -2.3, 5.9, 0), 3), 0.07585525)
    var graph = NodeGraph()
    var flat = graph.mx_noise_float(graph.vec2(0.3, 0.7), 2, 1)
    assert_almost_equal(one(graph, flat), 1.08148736)
    var deep = graph.mx_noise_float(graph.vec3(0.3, 0.7, 0.2))
    assert_almost_equal(one(graph, deep), 0.27371189)
    var fractal = graph.mx_fractal_noise_float(graph.vec2(0.3, 0.7))
    assert_almost_equal(one(graph, fractal), 0.03460022)
    var solid = graph.mx_fractal_noise_float(
        graph.vec3(0.3, 0.7, 0.2), 1, 2, 0.5, 2
    )
    assert_almost_equal(one(graph, solid), 0.54742378)
    with assert_raises(
        contains="Perlin noise reads a vec2 or a vec3, not a vec4"
    ):
        _ = graph.perlin_noise(graph.vec4(0, 0, 0, 0))
    with assert_raises(
        contains="Fractal noise reads a vec2 or a vec3, not a float"
    ):
        _ = graph.mx_fractal_noise_float(graph.float(0))
    with assert_raises(contains="A Loop runs from zero to 1024 times"):
        _ = graph.mx_fractal_noise_float(graph.vec3(0, 0, 0), -1)


def test_the_new_outputs_take_floats() raises:
    var graph = NodeGraph()
    graph.set_output(MASK_NODE, graph.float(1))
    graph.set_output(AO_NODE, graph.float(0.5))
    graph.set_output(DEPTH_NODE, graph.float(0.25))
    assert_equal(graph.output(AO_NODE).value, 1)
    assert_equal(graph.output(COLOR_NODE).value, -1)
    with assert_raises(contains="none of the ten"):
        _ = graph.output(NodeOutput(-1))
    var program = graph.compile()
    var source = Corners(program)
    assert_equal(run_nodes(source, AO_NODE, inputs())[0], 0.5)
    assert_equal(run_nodes(source, DEPTH_NODE, inputs())[0], 0.25)
    with assert_raises(contains="takes a float, not a vec3"):
        graph.set_output(DEPTH_NODE, graph.vec3(0, 0, 0))
    # The depth buffer keeps the minus one to one scale, or the reversed
    # window depth.
    assert_equal(node_depth(0.25, False), -0.5)
    assert_equal(node_depth(0.25, True), 0.25)


def test_the_helpers_the_rasterizers_share() raises:
    assert_equal(
        perspective_shares(0.5, 0.25, 0.25, 1, 1, 2),
        Lanes(0.4, 0.2, 0.4, 0),
    )
    # A zero 1 / w keeps the screen weights.
    assert_equal(
        perspective_shares(0.5, 0.25, 0.25, 0, 0, 0), Lanes(0.5, 0.25, 0.25, 0)
    )
    var here = here_inputs(Corners(), True)
    assert_almost_equal(here.u, 0.25)
    assert_almost_equal(here.position.x, 1)
    assert_true(here.textured)
    var corner = node_attributes(Corners(), CORNER_B, False)
    assert_equal(corner.u, 1)
    assert_equal(corner.normal.y, 1)
    # The vertex stage's source has no triangle.
    var program = NodeProgram()
    var alone = ProgramSource(Pointer(to=program))
    assert_equal(alone.shares(AT_RIGHT), Lanes(1, 0, 0, 0))
    assert_equal(alone.corner(CORNER_A).u, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
