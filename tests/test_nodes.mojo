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
    COLOR_NODE,
    EMISSIVE_NODE,
    INSTRUCTION_FLOATS,
    MAX_REGISTERS,
    NODE_ADD,
    NODE_FLOAT,
    NODE_OUTPUT_COUNT,
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
    NodeGraph,
    NodeInputs,
    NodeKind,
    NodeOutput,
    NodeProgram,
    NodeProgramId,
    NodeProgramStore,
    NodeRef,
    NodeSource,
    ProgramSource,
    ValueType,
    has_output,
    offset_normal,
    moved_position,
    run_nodes,
)
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.srgb import srgb_to_linear
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
    assert_equal(NODE_FLOAT.name(), "float")
    assert_equal(NODE_VEC3.name(), "vec3")
    assert_true(NODE_ADD.is_valid())
    assert_true(NODE_SWIZZLE.is_valid())
    assert_false(NodeKind(-1).is_valid())
    assert_false(NodeKind(29).is_valid())
    assert_true(COLOR_NODE.is_valid())
    assert_true(OUTPUT_NODE.is_valid())
    assert_false(NodeOutput(-1).is_valid())
    assert_false(NodeOutput(NODE_OUTPUT_COUNT).is_valid())
    assert_true(OPACITY_NODE.value_type() == NODE_FLOAT)
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
    with assert_raises(contains="none of the six"):
        graph.set_output(NodeOutput(6), three)
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
    with assert_raises(contains="none of the six"):
        _ = program.has(NodeOutput(9))
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
    # Thirty-three nodes in a chain need thirty-three registers.
    var long = NodeGraph()
    var chain = long.vec3(0, 0, 0)
    for _ in range(MAX_REGISTERS):
        chain = long.add(chain, chain)
    long.set_output(COLOR_NODE, chain)
    with assert_raises(contains="at most 32 nodes"):
        _ = long.compile()


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
    strange._kinds[a.value] = NodeKind(99)
    with assert_raises(contains="a kind or a type there is not"):
        _ = strange.compile()
    var shapeless = graph.copy()
    shapeless._types[a.value] = ValueType(7)
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
