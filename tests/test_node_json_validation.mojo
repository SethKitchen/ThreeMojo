# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Serialized node metadata is checked before any interpreter reads it."""

from exporters.json_writer import JsonWriter
from loaders.json import parse_json
from materials.node_json import read_node_program, write_node_program
from materials import nodes
from materials.node_validation import _span, _whole, validate_surface_program
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises


def _program() raises -> nodes.NodeProgram:
    """Return a small valid program with one named value."""
    var graph = nodes.NodeGraph()
    graph.set_output(
        nodes.COLOR_NODE, graph.uniform("tint", Vector3(0.5, 0.25, 1))
    )
    return graph.compile()


def _read(program: nodes.NodeProgram) raises:
    """Serialize and read a program, without interpreting its instructions."""
    var writer = JsonWriter()
    var textures = List[String](length=len(program.texture_offsets), fill="")
    var cubes = List[String](length=len(program.cube_offsets), fill="")
    write_node_program(writer, program, textures, cubes)
    var document = parse_json(writer.finish())
    _ = read_node_program(document, document.root())


def test_valid_scalar_vector_matrix_and_texture_programs_are_accepted() raises:
    _read(_program())
    var graph = nodes.NodeGraph()
    var matrix = graph.uniform("matrix", Matrix4())
    var mapped = graph.mul(matrix, graph.vec4(1, 2, 3, 1))
    graph.set_output(nodes.FRAGMENT_NODE, mapped)
    _read(graph.compile())
    var textured = nodes.NodeGraph()
    textured.set_output(
        nodes.FRAGMENT_NODE,
        textured.texture(textured.texture_uniform("map"), textured.uv()),
    )
    _read(textured.compile())
    var custom = nodes.NodeGraph()
    custom.set_output(
        nodes.COLOR_NODE, custom.attribute("paint", nodes.NODE_VEC3)
    )
    _read(custom.compile())


def test_derivatives_varyings_and_multiple_outputs_keep_valid_layouts() raises:
    var graph = nodes.NodeGraph()
    var uv = graph.uv()
    var smooth = graph.varying(uv)
    var gradient = graph.dfdx(uv)
    graph.set_output(nodes.COLOR_NODE, graph.join([smooth, graph.float(0.5)]))
    graph.set_output(nodes.EMISSIVE_NODE, graph.swizzle(gradient, "xyx"))
    _read(graph.compile())


def test_uniform_spans_must_fit_the_entire_value() raises:
    for mode in range(4):
        var program = _program()
        if mode == 0:
            program.uniform_offsets[0] = len(program.code) - 1
        elif mode == 1:
            program.uniform_offsets[0] = -1
        elif mode == 2:
            program.uniform_offsets[0] = 0
        else:
            program.uniform_types[0] = nodes.NODE_MAT4
        with assert_raises():
            _read(program)


def test_custom_attribute_spans_must_fit_the_vertex_storage() raises:
    for mode in range(4):
        var program = _program()
        program.attribute_names.append("extra")
        program.attribute_offsets.append(
            8 if mode == 0 else (-1 if mode == 1 else 0)
        )
        program.attribute_widths.append(
            0 if mode == 2 else (5 if mode == 3 else 4)
        )
        with assert_raises():
            _read(program)


def test_output_runs_are_bounded_and_integral() raises:
    for mode in range(5):
        var program = _program()
        if mode == 0:
            program.code[0] = Float32(len(program.code) + 1)
        elif mode == 1:
            program.code[0] = -1
        elif mode == 2:
            program.code[0] += 0.5
        elif mode == 3:
            program.code[1] = nodes.MAX_INSTRUCTIONS + 1
        else:
            program.code[2] = program.code[0]
            program.code[3] = program.code[1]
        with assert_raises():
            _read(program)


def test_all_register_operands_and_destinations_are_bounded() raises:
    for slot in [
        nodes.INSTRUCTION_A,
        nodes.INSTRUCTION_B,
        nodes.INSTRUCTION_C,
        nodes.INSTRUCTION_DEST,
    ]:
        for value in [Float32(-1), Float32(nodes.MAX_REGISTERS), Float32(0.5)]:
            var program = _program()
            program.code[nodes.PROGRAM_HEADER + slot] = value
            with assert_raises():
                _read(program)


def test_constants_matrices_and_packed_lane_counts_cannot_escape_storage() raises:
    for kind in [
        nodes.NODE_CONSTANT,
        nodes.NODE_MATRIX_VECTOR,
        nodes.NODE_JOIN,
        nodes.NODE_ATTRIBUTE,
        nodes.NODE_CELL_NOISE,
    ]:
        var program = _program()
        program.code[nodes.PROGRAM_HEADER] = Float32(kind.value)
        var immediate = Float32(len(program.code) - 1)
        if kind == nodes.NODE_MATRIX_VECTOR:
            immediate = Float32(len(program.code) * 8 + 4)
        elif kind == nodes.NODE_JOIN:
            immediate = 4 + 5 * 4
        elif kind == nodes.NODE_ATTRIBUTE:
            immediate = 7 + 8 * 4
        elif kind == nodes.NODE_CELL_NOISE:
            immediate = 5
        program.code[
            nodes.PROGRAM_HEADER + nodes.INSTRUCTION_IMMEDIATE
        ] = immediate
        with assert_raises():
            _read(program)


def test_surface_programs_reject_unknown_graph_only_and_compute_opcodes() raises:
    for op in [
        nodes.NODE_COMPUTE_RESULT.value + 1,
        nodes.NODE_VARYING.value,
        nodes.NODE_COMPUTE_RESULT.value,
        nodes.NODE_MATRIX_COLUMNS.value,
    ]:
        var program = _program()
        program.code[nodes.PROGRAM_HEADER] = Float32(op)
        with assert_raises():
            _read(program)


def test_texture_reads_need_corresponding_serialized_metadata() raises:
    var graph = nodes.NodeGraph()
    graph.set_output(
        nodes.FRAGMENT_NODE,
        graph.texture(graph.texture_uniform("map"), graph.uv()),
    )
    var program = graph.compile()
    program.texture_offsets.clear()
    with assert_raises(contains="lacks its offset"):
        _read(program)


def test_nonfinite_control_words_are_rejected_before_integer_conversion() raises:
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        var program = _program()
        program.code[0] = value
        with assert_raises(contains="finite code"):
            validate_surface_program(program)


def test_uniform_instructions_need_declared_uniform_offsets() raises:
    var program = _program()
    var undeclared = len(program.code)
    for value in [Float32(0.25), Float32(0.5), Float32(1), Float32(0)]:
        program.code.append(value)
    program.code[nodes.PROGRAM_HEADER + nodes.INSTRUCTION_IMMEDIATE] = Float32(
        undeclared
    )
    with assert_raises(contains="uniform instruction lacks its offset"):
        _read(program)


def test_attribute_names_are_unique() raises:
    var program = _program()
    for _ in range(2):
        program.attribute_names.append("extra")
        program.attribute_offsets.append(0)
        program.attribute_widths.append(1)
    with assert_raises(contains="attribute name is repeated"):
        _read(program)
    program.attribute_names[1] = "other"
    _read(program)


def test_viewport_programs_declare_their_scene_read() raises:
    var graph = nodes.NodeGraph()
    graph.set_output(nodes.FRAGMENT_NODE, graph.viewport_texture(graph.uv()))
    var program = graph.compile()
    _read(program)
    program.reads_scene = False
    with assert_raises(contains="declare readsScene"):
        _read(program)


def test_uniform_spans_cannot_alias_each_other() raises:
    var graph = nodes.NodeGraph()
    var a = graph.uniform("a", Vector3(1, 0, 0))
    var b = graph.uniform("b", Vector3(0, 1, 0))
    graph.set_output(nodes.COLOR_NODE, graph.add(a, b))
    var program = graph.compile()
    var old = program.uniform_offsets[1]
    var alias = program.uniform_offsets[0] + 1
    program.uniform_offsets[1] = alias
    var start = Int(program.code[nodes.COLOR_NODE.value * 2])
    var count = Int(program.code[nodes.COLOR_NODE.value * 2 + 1])
    for index in range(count):
        var at = start + index * nodes.INSTRUCTION_FLOATS
        if (
            Int(program.code[at]) == nodes.NODE_UNIFORM.value
            and Int(program.code[at + nodes.INSTRUCTION_IMMEDIATE]) == old
        ):
            program.code[at + nodes.INSTRUCTION_IMMEDIATE] = Float32(alias)
    with assert_raises(contains="uniform spans overlap"):
        _read(program)


def test_sampler_uniforms_cannot_be_retyped_as_numeric_values() raises:
    for cube in [False, True]:
        var graph = nodes.NodeGraph()
        var sample = graph.texture_cube(
            graph.cube_uniform("map"), graph.vec3(0, 0, 1)
        ) if cube else graph.texture(graph.texture_uniform("map"), graph.uv())
        graph.set_output(nodes.FRAGMENT_NODE, sample)
        var program = graph.compile()
        program.uniform_types[0] = nodes.NODE_FLOAT
        with assert_raises(contains="sampler"):
            _read(program)


def test_anonymous_sampler_slots_cannot_hide_inside_a_matrix_uniform() raises:
    var graph = nodes.NodeGraph()
    _ = graph.uniform("matrix", Matrix4())
    var sample = graph.texture(graph.texture_uniform("map"), graph.uv())
    graph.set_output(nodes.FRAGMENT_NODE, sample)
    var program = graph.compile()
    var alias = program.uniform_offsets[0] + 1
    program.texture_offsets[0] = alias
    var start = Int(program.code[nodes.FRAGMENT_NODE.value * 2])
    var count = Int(program.code[nodes.FRAGMENT_NODE.value * 2 + 1])
    for index in range(count):
        var at = start + index * nodes.INSTRUCTION_FLOATS
        if Int(program.code[at]) == nodes.NODE_TEXTURE.value:
            program.code[at + nodes.INSTRUCTION_IMMEDIATE] = Float32(alias)
    with assert_raises(contains="sampler"):
        _read(program)


def _instruction(kind: nodes.NodeKind, immediate: Int = 0) -> nodes.NodeProgram:
    """Build inert bytecode for validator tests, never for execution."""
    var program = nodes.NodeProgram()
    program.code = List[Float32](length=nodes.PROGRAM_HEADER + 38, fill=0)
    program.code[nodes.COLOR_NODE.value * 2] = nodes.PROGRAM_HEADER
    program.code[nodes.COLOR_NODE.value * 2 + 1] = 1
    program.code[nodes.PROGRAM_HEADER] = Float32(kind.value)
    program.code[nodes.PROGRAM_HEADER + nodes.INSTRUCTION_IMMEDIATE] = Float32(
        immediate
    )
    return program^


def test_integer_and_span_helpers_enforce_each_boundary() raises:
    for value in [
        Float32(-1),
        Float32(5),
        Float32(0.5),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises():
            _ = _whole(value, 4)
    assert_equal(_whole(0, 4), 0)
    assert_equal(_whole(4, 4), 4)
    _span(0, 0, 0, 0)
    _span(1, 3, 1, 4)
    for mode in range(4):
        with assert_raises():
            _span(
                0 if mode == 0 else (5 if mode == 1 else 1),
                -1 if mode == 2 else (4 if mode == 3 else 1),
                1,
                4,
            )


def test_empty_program_and_raw_metadata_lengths_are_checked() raises:
    var empty = nodes.NodeProgram()
    empty.code = List[Float32](length=nodes.PROGRAM_HEADER, fill=0)
    validate_surface_program(empty)
    empty.code.clear()
    with assert_raises(contains="too short"):
        validate_surface_program(empty)
    for mode in range(4):
        var program = _program()
        if mode == 0:
            program.uniform_offsets.clear()
        elif mode == 1:
            program.uniform_types.clear()
        elif mode == 2:
            program.uniform_types[0] = nodes.ValueType(-1)
        else:
            program.uniform_names[0] = ""
        with assert_raises(contains="uniform"):
            validate_surface_program(program)
    for mode in range(2):
        var program = _program()
        program.attribute_names.append("paint")
        if mode == 1:
            program.attribute_offsets.append(0)
        with assert_raises(contains="metadata lengths"):
            validate_surface_program(program)


def test_duplicate_uniform_and_sampler_metadata_is_refused() raises:
    var program = _program()
    program.uniform_names.append(program.uniform_names[0])
    program.uniform_offsets.append(len(program.code))
    program.uniform_types.append(nodes.NODE_FLOAT)
    for _ in range(4):
        program.code.append(0)
    with assert_raises(contains="name is repeated"):
        validate_surface_program(program)
    for cube in [False, True]:
        var sampled = _instruction(nodes.NODE_ADD)
        var slot = nodes.PROGRAM_HEADER + nodes.INSTRUCTION_FLOATS
        if cube:
            sampled.cube_offsets.append(slot)
            sampled.cube_offsets.append(slot)
        else:
            sampled.texture_offsets.append(slot)
            sampled.texture_offsets.append(slot)
        with assert_raises(contains="offset is repeated"):
            validate_surface_program(sampled)
        if cube:
            sampled.cube_offsets[1] += 4
        else:
            sampled.texture_offsets[1] += 4
        validate_surface_program(sampled)


def test_uniform_spans_are_disjoint_in_either_metadata_order() raises:
    var slot = nodes.PROGRAM_HEADER + nodes.INSTRUCTION_FLOATS
    for displacement in [-4, -1, 0, 1, 4]:
        var program = _instruction(nodes.NODE_ADD)
        for name in ["a", "b"]:
            program.uniform_names.append(name)
            program.uniform_types.append(nodes.NODE_VEC4)
        program.uniform_offsets.append(slot + 4)
        program.uniform_offsets.append(slot + 4 + displacement)
        if displacement == -4 or displacement == 4:
            validate_surface_program(program)
        else:
            with assert_raises(contains="uniform spans overlap"):
                validate_surface_program(program)


def test_sampler_kinds_and_separate_slots_cannot_overlap() raises:
    var slot = nodes.PROGRAM_HEADER + nodes.INSTRUCTION_FLOATS
    for displacement in [-4, -1, 0, 1, 4]:
        var program = _instruction(nodes.NODE_ADD)
        program.texture_offsets.append(slot + 4)
        program.cube_offsets.append(slot + 4 + displacement)
        if displacement == -4 or displacement == 4:
            validate_surface_program(program)
        else:
            with assert_raises(contains="sampler spans overlap"):
                validate_surface_program(program)
    for displacement in [-4, -1, 0, 1, 4]:
        var program = _instruction(nodes.NODE_ADD)
        program.uniform_names.append("map")
        program.uniform_types.append(nodes.NODE_SAMPLER)
        program.uniform_offsets.append(slot + 4)
        program.texture_offsets.append(slot + 4 + displacement)
        if displacement == -4 or displacement == 0 or displacement == 4:
            validate_surface_program(program)
        else:
            with assert_raises(contains="sampler overlaps"):
                validate_surface_program(program)


def test_every_graph_only_or_compute_opcode_is_refused() raises:
    for kind in [
        nodes.NODE_VARYING,
        nodes.NODE_DFDX,
        nodes.NODE_DFDY,
        nodes.NODE_COPY,
        nodes.NODE_VIEW_MATRIX,
        nodes.NODE_MATRIX_COLUMNS,
        nodes.NODE_MATRIX_TAIL,
        nodes.NODE_COMPUTE_BUILTIN,
        nodes.NODE_STORAGE_ELEMENT,
        nodes.NODE_COMPUTE_RESULT,
        nodes.NODE_TEXTURE_3D,
        nodes.NODE_TEXTURE_ARRAY,
    ]:
        with assert_raises(contains="surface instruction"):
            validate_surface_program(_instruction(kind))


def test_matrix_widths_and_header_pool_spans_are_checked() raises:
    for kind in [nodes.NODE_MATRIX_VECTOR, nodes.NODE_VECTOR_MATRIX]:
        for width in [3, 4]:
            for slot in [
                nodes.PROGRAM_VIEW,
                nodes.PROGRAM_HEADER + nodes.INSTRUCTION_FLOATS,
            ]:
                validate_surface_program(_instruction(kind, slot * 8 + width))
        for width in [0, 2, 5]:
            with assert_raises(contains="matrix must"):
                validate_surface_program(_instruction(kind, width))


def test_texture_instruction_families_require_matching_offsets() raises:
    var slot = nodes.PROGRAM_HEADER + nodes.INSTRUCTION_FLOATS
    for kind in [
        nodes.NODE_TEXTURE,
        nodes.NODE_TEXTURE_LEVEL,
        nodes.NODE_TEXEL_FETCH,
        nodes.NODE_TEXTURE_SIZE,
        nodes.NODE_TEXTURE_CUBE,
    ]:
        var program = _instruction(kind, slot)
        with assert_raises(contains="lacks its offset"):
            validate_surface_program(program)
        if kind == nodes.NODE_TEXTURE_CUBE:
            program.cube_offsets.append(slot)
        else:
            program.texture_offsets.append(slot)
        validate_surface_program(program)


def test_attribute_join_and_context_widths_are_checked() raises:
    for immediate in [0, 8 * 5]:
        with assert_raises(contains="attribute instruction width"):
            validate_surface_program(
                _instruction(nodes.NODE_ATTRIBUTE, immediate)
            )
    validate_surface_program(_instruction(nodes.NODE_ATTRIBUTE, 8 * 4))
    for immediate in [0, 4 + 5 * 4]:
        with assert_raises(contains="join exceeds"):
            validate_surface_program(_instruction(nodes.NODE_JOIN, immediate))
    for immediate in [1, 4, 1 + 5 + 25]:
        validate_surface_program(_instruction(nodes.NODE_JOIN, immediate))
    for context in [0, nodes.NODE_CONTEXT_COUNT - 1]:
        validate_surface_program(_instruction(nodes.NODE_INTERPOLATE, context))
    with assert_raises(contains="invalid integer"):
        validate_surface_program(
            _instruction(nodes.NODE_INTERPOLATE, nodes.NODE_CONTEXT_COUNT)
        )


def test_vector_and_noise_families_check_packed_widths() raises:
    for kind in [
        nodes.NODE_CELL_NOISE,
        nodes.NODE_CELL_NOISE_VEC3,
        nodes.NODE_DOT,
        nodes.NODE_LENGTH,
        nodes.NODE_NORMALIZE,
        nodes.NODE_DISTANCE,
        nodes.NODE_REFLECT,
        nodes.NODE_REFRACT,
        nodes.NODE_FACEFORWARD,
    ]:
        for width in [1, 4]:
            validate_surface_program(_instruction(kind, width))
        for width in [0, 5]:
            with assert_raises(contains="vector width"):
                validate_surface_program(_instruction(kind, width))
    for kind in [nodes.NODE_NOISE, nodes.NODE_NOISE_VEC3]:
        for width in [2, 3]:
            validate_surface_program(_instruction(kind, width))
        with assert_raises(contains="Perlin"):
            validate_surface_program(_instruction(kind, 1))
    for width in [2, 3]:
        for result in [1, 3]:
            validate_surface_program(
                _instruction(nodes.NODE_WORLEY, width + result * 4)
            )
    for immediate in [0, 1, 2, 3, 4 + 4 * 4, 2 + 4 * 4]:
        with assert_raises(contains="Worley"):
            validate_surface_program(_instruction(nodes.NODE_WORLEY, immediate))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
