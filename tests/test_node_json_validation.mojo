# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Serialized node metadata is checked before any interpreter reads it."""

from exporters.json_writer import JsonWriter
from loaders.json import parse_json
from materials.node_json import read_node_program, write_node_program
from materials import nodes
from materials.node_validation import validate_surface_program
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
