# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact node words survive JSON without admitting nonfinite control data."""

from exporters.json_writer import JsonWriter
from loaders.json import parse_json
from materials import nodes
from materials.node_json import read_node_program, write_node_program
from materials.node_validation import validate_surface_program
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime Words = SIMD[DType.uint32, 4]


def _write(program: nodes.NodeProgram) raises -> String:
    var writer = JsonWriter()
    write_node_program(
        writer,
        program,
        List[String](length=len(program.texture_offsets), fill=""),
        List[String](length=len(program.cube_offsets), fill=""),
    )
    return writer.finish()


def _read(text: String) raises -> nodes.NodeProgram:
    var document = parse_json(text)
    var loaded = read_node_program(document, document.root())
    return loaded.program.copy()


def _roundtrip(program: nodes.NodeProgram) raises -> nodes.NodeProgram:
    var loaded = _read(_write(program))
    assert_equal(len(loaded.code), len(program.code))
    for index in range(len(program.code)):
        assert_equal(
            bitcast[DType.uint32](loaded.code[index]),
            bitcast[DType.uint32](program.code[index]),
        )
    assert_equal(len(loaded.uniform_names), len(program.uniform_names))
    for index in range(len(program.uniform_names)):
        assert_equal(loaded.uniform_names[index], program.uniform_names[index])
        assert_equal(
            loaded.uniform_offsets[index], program.uniform_offsets[index]
        )
        assert_equal(loaded.uniform_types[index], program.uniform_types[index])
    return loaded^


def _root(
    graph: nodes.NodeGraph, root: nodes.NodeRef
) raises -> nodes.NodeProgram:
    """Use a math root as an inert surface run, retaining its exact lanes."""
    var starts = List[Int]()
    var program = graph.compile_roots([root], starts)
    program.code[nodes.OPACITY_NODE.value * 2] = Float32(starts[0])
    program.code[nodes.OPACITY_NODE.value * 2 + 1] = Float32(starts[1])
    return program^


def _value(mut program: nodes.NodeProgram) -> Words:
    var inputs = nodes.NodeInputs(
        0,
        0,
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        False,
    )
    var result = nodes.run_code(
        nodes.ProgramSource(Pointer(to=program)),
        Int(program.code[nodes.OPACITY_NODE.value * 2]),
        Int(program.code[nodes.OPACITY_NODE.value * 2 + 1]),
        inputs,
    )
    return bitcast[DType.uint32, 4](result)


def _constant(
    type: nodes.ValueType = nodes.NODE_UVEC4,
) raises -> nodes.NodeProgram:
    var graph = nodes.NodeGraph()
    var words = Words(0)
    var samples = Words(0xFFFFFFFF, 0x80000000, 0x7F800001, 1)
    for lane in range(type.width()):
        words[lane] = samples[lane]
    var root = graph._add(
        nodes.NODE_CONSTANT, type, value=bitcast[DType.float32, 4](words)
    )
    return _root(graph, root)


def _last(program: nodes.NodeProgram) -> Int:
    var start = Int(program.code[nodes.OPACITY_NODE.value * 2])
    var count = Int(program.code[nodes.OPACITY_NODE.value * 2 + 1])
    return start + (count - 1) * nodes.INSTRUCTION_FLOATS


def _width_opcode(op: Int) -> Bool:
    return op == 120 or op == 124 or op == 145 or op == 149 or op >= 162


def _arity(op: Int) -> Int:
    if op == 119 or op == 144:
        return 3
    if _width_opcode(op) or (op >= 133 and op <= 136) or op >= 158:
        return 1
    return 2


def _operation(op: Int) raises -> nodes.NodeProgram:
    var graph = nodes.NodeGraph()
    var type = nodes.NODE_UVEC4 if op < 137 else nodes.NODE_IVEC4
    var a = graph._add(
        nodes.NODE_CONSTANT,
        type,
        value=bitcast[DType.float32, 4](Words(0xFFFFFFFF, 0x80000000, 1, 17)),
    )
    var b = graph._add(
        nodes.NODE_CONSTANT,
        type,
        value=bitcast[DType.float32, 4](Words(1, 2, 3, 4)),
    )
    var c = graph._add(
        nodes.NODE_CONSTANT,
        type,
        value=bitcast[DType.float32, 4](Words(12, 15, 7, 31)),
    )
    if op == 133 or op == 158:
        a = graph.vec4(0, 1, 2, 3)
    var arity = _arity(op)
    var root = graph._add(
        nodes.NodeKind(op),
        type,
        a.value,
        b.value if arity >= 2 else -1,
        c.value if arity == 3 else -1,
        value=nodes.Lanes(4 if _width_opcode(op) else 0),
    )
    return _root(graph, root)


def _empty_json(
    key: String, word: String = "0", length: Int = nodes.PROGRAM_HEADER
) -> String:
    var text = '{"' + key + '":['
    for index in range(length):
        if index > 0:
            text += ","
        text += word
    return (
        text
        + '],"uniforms":[],"textures":[],"cubes":[],"attributes":[],"readsScene":false}'
    )


def test_float_programs_keep_legacy_json_and_accept_bit_encoding() raises:
    var graph = nodes.NodeGraph()
    graph.set_output(nodes.COLOR_NODE, graph.vec3(0.25, 0.5, 1))
    var program = graph.compile()
    var document = parse_json(_write(program))
    assert_true(document.has(document.root(), "code"))
    assert_false(document.has(document.root(), "codeBits"))
    _ = _roundtrip(program)
    _ = _read(_empty_json("code"))
    _ = _read(_empty_json("codeBits"))


def test_every_constant_type_and_adversarial_bit_pattern_round_trips() raises:
    for type in range(41, 49):
        var program = _constant(nodes.ValueType(type))
        var text = _write(program)
        var document = parse_json(text)
        assert_true(document.has(document.root(), "codeBits"))
        assert_false(document.has(document.root(), "code"))
        var loaded = _roundtrip(program)
        assert_equal(_value(loaded), _value(program))
    var program = _constant()
    var pool = Int(program.code[_last(program) + nodes.INSTRUCTION_IMMEDIATE])
    for word in [
        UInt32(0),
        UInt32(1),
        UInt32(0x007FFFFF),
        UInt32(0x7F800000),
        UInt32(0xFF800000),
        UInt32(0x7FC00001),
        UInt32(0x80000000),
        UInt32(0xFFFFFFFF),
    ]:
        program.code[pool] = bitcast[DType.float32](word)
        var loaded = _roundtrip(program)
        assert_equal(_value(loaded)[0], word)


def test_all_integer_uniform_types_and_updates_round_trip() raises:
    for type in range(41, 49):
        var graph = nodes.NodeGraph()
        var value_type = nodes.ValueType(type)
        var words = Words(0)
        for lane in range(value_type.width()):
            words[lane] = Words(0xFFFFFFFF, 0x7F800000, 0x80000000, 1)[lane]
        var uniform = graph._uniform(
            "exact", value_type, bitcast[DType.float32, 4](words)
        )
        var program = _root(graph, uniform)
        var loaded = _roundtrip(program)
        assert_equal(_value(loaded), words)
    var graph = nodes.NodeGraph()
    var uniform = graph.uniform_uint("value", UInt32(0xFFFFFFFF))
    var program = _root(graph, uniform)
    program.set_uniform_uint("value", UInt32(0x80000000))
    var loaded = _roundtrip(program)
    assert_equal(_value(loaded)[0], UInt32(0x80000000))


def test_every_exact_opcode_preserves_words_and_execution() raises:
    for op in range(112, 164):
        var program = _operation(op)
        var loaded = _roundtrip(program)
        assert_equal(_value(loaded), _value(program))


def test_ambiguous_missing_wrong_kind_and_short_encodings_are_rejected() raises:
    for text in [
        _empty_json("codeBits").replace('"codeBits":', '"code":[],"codeBits":'),
        _empty_json("code").replace('"code":', '"missing":'),
        _empty_json("codeBits").replace(
            '"codeBits":[', '"codeBits":{},"ignored":['
        ),
        _empty_json("codeBits", length=nodes.PROGRAM_HEADER - 1),
        _empty_json("code", length=0),
    ]:
        with assert_raises():
            _ = _read(text)


def test_code_bits_requires_unsigned_whole_32_bit_numbers() raises:
    for word in [
        "-1",
        "4294967296",
        "0.5",
        "1e100",
        '"0"',
        "true",
        "null",
        "{}",
        "[]",
    ]:
        with assert_raises():
            _ = _read(_empty_json("codeBits", word))


def test_nonfinite_bits_never_authorize_control_unused_or_float_words() raises:
    for word in [UInt32(0x7F800000), UInt32(0x7FC00001), UInt32(0xFF800000)]:
        for at in [
            0,
            nodes.PROGRAM_TIME,
            nodes.PROGRAM_VIEW,
            nodes.PROGRAM_HEADER,
            nodes.PROGRAM_HEADER + nodes.INSTRUCTION_A,
            nodes.PROGRAM_HEADER + nodes.INSTRUCTION_B,
            nodes.PROGRAM_HEADER + nodes.INSTRUCTION_C,
            nodes.PROGRAM_HEADER + nodes.INSTRUCTION_IMMEDIATE,
            nodes.PROGRAM_HEADER + nodes.INSTRUCTION_DEST,
        ]:
            var program = _constant()
            program.code[at] = bitcast[DType.float32](word)
            with assert_raises(contains="finite code"):
                validate_surface_program(program)
        var program = _constant()
        program.code.append(bitcast[DType.float32](word))
        with assert_raises(contains="finite code"):
            validate_surface_program(program)
    var program = _constant()
    program.code[nodes.PROGRAM_HEADER + nodes.INSTRUCTION_B] = 0
    with assert_raises(contains="finite code"):
        validate_surface_program(program)


def test_constant_type_tags_and_unused_inputs_are_validated() raises:
    for tag in [
        Float32(-1),
        Float32(0.5),
        Float32(9),
        Float32(31),
        Float32(32),
    ]:
        var program = _constant()
        program.code[nodes.PROGRAM_HEADER + nodes.INSTRUCTION_B] = tag
        with assert_raises():
            validate_surface_program(program)
    for slot in [nodes.INSTRUCTION_A, nodes.INSTRUCTION_C]:
        var program = _constant()
        program.code[nodes.PROGRAM_HEADER + slot] = 1
        with assert_raises(contains="has inputs"):
            validate_surface_program(program)
    var graph = nodes.NodeGraph()
    var uniform = graph.uniform_uint("exact", UInt32(1))
    var program = _root(graph, uniform)
    program.code[nodes.PROGRAM_HEADER + nodes.INSTRUCTION_B] = 1
    with assert_raises(contains="constant type tag"):
        validate_surface_program(program)


def test_integer_payload_cannot_alias_float_matrix_or_sampler_data() raises:
    for type in [
        nodes.NODE_FLOAT,
        nodes.NODE_MAT4,
        nodes.NODE_SAMPLER,
        nodes.NODE_UINT,
    ]:
        var program = _constant()
        var pool = Int(
            program.code[_last(program) + nodes.INSTRUCTION_IMMEDIATE]
        )
        program.uniform_names.append("alias")
        program.uniform_types.append(type)
        program.uniform_offsets.append(pool)
        for _ in range(12):
            program.code.append(0)
        with assert_raises(contains="payload spans overlap"):
            validate_surface_program(program)
    var program = _constant()
    program.texture_offsets.append(
        Int(program.code[_last(program) + nodes.INSTRUCTION_IMMEDIATE])
    )
    with assert_raises(contains="payload spans overlap"):
        validate_surface_program(program)


def test_integer_payload_aliases_require_the_same_complete_type() raises:
    for displacement in [0, 1]:
        var program = _constant()
        var pool = Int(
            program.code[_last(program) + nodes.INSTRUCTION_IMMEDIATE]
        )
        program.uniform_names.append("alias")
        program.uniform_types.append(nodes.NODE_UVEC4)
        program.uniform_offsets.append(pool + displacement)
        program.code.append(0)
        if displacement == 0:
            validate_surface_program(program)
        else:
            with assert_raises(contains="payload spans overlap"):
                validate_surface_program(program)
    var program = _constant()
    program.code[
        _last(program) + nodes.INSTRUCTION_IMMEDIATE
    ] = nodes.PROGRAM_HEADER
    with assert_raises(contains="span is outside"):
        validate_surface_program(program)


def test_integer_operations_check_arity_immediates_and_input_producers() raises:
    for op in range(112, 164):
        for slot in [
            nodes.INSTRUCTION_A,
            nodes.INSTRUCTION_B,
            nodes.INSTRUCTION_C,
            nodes.INSTRUCTION_DEST,
        ]:
            for bad in [Float32(-1), Float32(0.5), Float32(32)]:
                var program = _operation(op)
                program.code[_last(program) + slot] = bad
                with assert_raises():
                    validate_surface_program(program)
        var program = _operation(op)
        program.code[_last(program) + nodes.INSTRUCTION_IMMEDIATE] = 5
        with assert_raises(contains="invalid immediate"):
            validate_surface_program(program)
        program = _operation(op)
        program.code[_last(program) + nodes.INSTRUCTION_A] = 31
        with assert_raises(contains="no producer"):
            validate_surface_program(program)
        if _arity(op) < 3:
            program = _operation(op)
            program.code[_last(program) + nodes.INSTRUCTION_C] = 1
            with assert_raises(contains="extra input"):
                validate_surface_program(program)
        if _arity(op) == 1:
            program = _operation(op)
            program.code[_last(program) + nodes.INSTRUCTION_B] = 1
            with assert_raises(contains="second input"):
                validate_surface_program(program)


def _gradient(exact: Bool = False) raises -> nodes.NodeProgram:
    var graph = nodes.NodeGraph()
    if exact:
        _ = graph.uniform_uint("bits", UInt32(0xFFFFFFFF))
    var texel = graph.texture_grad(
        graph.texture_uniform("map"),
        graph.uv(),
        graph.vec2(0.125, 0.25),
        graph.vec2(0.5, 0.75),
    )
    graph.set_output(nodes.FRAGMENT_NODE, texel)
    return graph.compile()


def _gradient_at(program: nodes.NodeProgram) -> Int:
    var start = Int(program.code[nodes.FRAGMENT_NODE.value * 2])
    var count = Int(program.code[nodes.FRAGMENT_NODE.value * 2 + 1])
    return start + (count - 1) * nodes.INSTRUCTION_FLOATS


def test_gradient_sampler_binding_and_packed_registers_round_trip() raises:
    var program = _gradient()
    var loaded = _roundtrip(program)
    var at = _gradient_at(loaded)
    assert_equal(loaded.code[at], Float32(nodes.NODE_TEXTURE_GRAD.value))
    assert_equal(loaded.code[at + nodes.INSTRUCTION_B], Float32(0))
    assert_equal(len(loaded.texture_offsets), 1)
    assert_equal(loaded.texture_offsets[0], program.texture_offsets[0])
    var writer = JsonWriter()
    write_node_program(
        writer, program, [String("gradient-map")], List[String]()
    )
    var document = parse_json(writer.finish())
    var restored = read_node_program(document, document.root())
    assert_equal(restored.texture_uuids[0], "gradient-map")
    assert_equal(restored.texture_offsets[0], program.texture_offsets[0])
    assert_equal(
        restored.program.code[restored.texture_offsets[0]], Float32(-1)
    )


def test_gradient_rejects_missing_bindings_and_invalid_registers() raises:
    var program = _gradient()
    program.texture_offsets.clear()
    with assert_raises(contains="lacks its offset"):
        validate_surface_program(program)
    for slot in [nodes.INSTRUCTION_A, nodes.INSTRUCTION_C]:
        program = _gradient()
        program.code[_gradient_at(program) + slot] = 31
        with assert_raises(contains="no producer"):
            validate_surface_program(program)
    program = _gradient()
    program.code[_gradient_at(program) + nodes.INSTRUCTION_B] = 1
    with assert_raises(contains="extra input"):
        validate_surface_program(program)
    program = _gradient()
    program.uniform_types[0] = nodes.NODE_UVEC4
    with assert_raises(contains="sampler"):
        validate_surface_program(program)


def test_code_bits_keeps_gradient_bindings_and_unreferenced_integer_uniforms() raises:
    var program = _gradient(True)
    var document = parse_json(_write(program))
    assert_true(document.has(document.root(), "codeBits"))
    var loaded = _roundtrip(program)
    assert_equal(loaded.texture_offsets[0], program.texture_offsets[0])
    assert_equal(loaded.uniform_types[0], nodes.NODE_UINT)
    assert_equal(
        bitcast[DType.uint32](loaded.code[loaded.uniform_offsets[0]]),
        UInt32(0xFFFFFFFF),
    )


def test_integer_uniform_payload_requires_valid_declared_metadata() raises:
    var graph = nodes.NodeGraph()
    var uniform = graph.uniform_uint("bits", UInt32(0xFFFFFFFF))
    var original = _root(graph, uniform)
    for type in [nodes.NODE_FLOAT, nodes.ValueType(40), nodes.ValueType(49)]:
        var program = original.copy()
        program.uniform_types[0] = type
        with assert_raises():
            validate_surface_program(program)
    var program = original.copy()
    program.uniform_offsets[0] = 0
    with assert_raises(contains="span is outside"):
        validate_surface_program(program)
    program = original.copy()
    program.uniform_names.clear()
    program.uniform_offsets.clear()
    program.uniform_types.clear()
    with assert_raises(contains="lacks its offset"):
        validate_surface_program(program)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
