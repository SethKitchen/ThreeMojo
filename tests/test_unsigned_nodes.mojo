# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact 32-bit node values through graph construction, layout and execution.

The oracles are integer identities and explicit bit patterns. No expected
unsigned value passes through a numeric Float32 conversion.
"""

from materials.nodes import (
    COLOR_NODE,
    INSTRUCTION_A,
    INSTRUCTION_B,
    INSTRUCTION_C,
    NODE_CONSTANT,
    NODE_FLOAT,
    NODE_INT,
    NODE_INT_FIRST,
    NODE_INT_LAST,
    NODE_IVEC2,
    NODE_IVEC3,
    NODE_IVEC4,
    NODE_UINT,
    NODE_UINT_FIRST,
    NODE_UINT_LAST,
    NODE_UVEC2,
    NODE_UVEC3,
    NODE_UVEC4,
    NODE_VEC2,
    NODE_VEC4,
    Fn,
    NodeGraph,
    NodeInputs,
    NodeKind,
    NodeRef,
    NodeVar,
    ProgramSource,
    ValueType,
    run_code,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime Lanes = SIMD[DType.float32, 4]
comptime Words = SIMD[DType.uint32, 4]


def inputs() -> NodeInputs:
    return NodeInputs(
        0,
        0,
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        False,
    )


def value_of(graph: NodeGraph, root: NodeRef) raises -> Lanes:
    var starts = List[Int]()
    var program = graph.compile_roots([root], starts)
    return run_code(
        ProgramSource(Pointer(to=program)), starts[0], starts[1], inputs()
    )


def bits_of(graph: NodeGraph, root: NodeRef) raises -> Words:
    return bitcast[DType.uint32, 4](value_of(graph, root))


def first(graph: NodeGraph, root: NodeRef) raises -> UInt32:
    return bits_of(graph, root)[0]


def test_exact_integer_types() raises:
    for width in range(1, 5):
        var unsigned = ValueType(40 + width)
        var signed = ValueType(44 + width)
        assert_true(unsigned.is_valid())
        assert_true(unsigned.is_vector())
        assert_true(unsigned.is_unsigned())
        assert_true(unsigned.is_integer())
        assert_false(unsigned.is_signed())
        assert_equal(unsigned.width(), width)
        assert_true(signed.is_valid())
        assert_true(signed.is_vector())
        assert_true(signed.is_signed())
        assert_true(signed.is_integer())
        assert_false(signed.is_unsigned())
        assert_equal(signed.width(), width)
    assert_equal(NODE_UINT.name(), "uint")
    assert_equal(NODE_UVEC2.name(), "uvec2")
    assert_equal(NODE_UVEC3.name(), "uvec3")
    assert_equal(NODE_UVEC4.name(), "uvec4")
    assert_equal(NODE_INT.name(), "int")
    assert_equal(NODE_IVEC2.name(), "ivec2")
    assert_equal(NODE_IVEC3.name(), "ivec3")
    assert_equal(NODE_IVEC4.name(), "ivec4")
    assert_false(ValueType(40).is_valid())
    assert_false(ValueType(49).is_valid())
    assert_equal(NODE_FLOAT.width(), 1)
    assert_equal(NODE_VEC4.width(), 4)
    assert_false(NODE_FLOAT.is_integer())
    for kind in range(NODE_UINT_FIRST.value, NODE_INT_LAST.value + 1):
        assert_true(NodeKind(kind).is_valid())
    assert_true(NODE_UINT_LAST.value < NODE_INT_FIRST.value)
    assert_false(NodeKind(NODE_INT_LAST.value + 1).is_valid())


def test_integer_constant_type_tags_are_metadata_not_registers() raises:
    var g = NodeGraph()
    var roots = List[NodeRef]()
    var expected = List[Words]()
    for type in range(41, 49):
        var value_type = ValueType(type)
        var words = Words(0)
        var samples = Words(0xFFFFFFFF, 0x80000000, 0x7F800001, 1)
        for lane in range(value_type.width()):
            words[lane] = samples[lane]
        roots.append(
            g._add(
                NODE_CONSTANT,
                value_type,
                value=bitcast[DType.float32, 4](words),
            )
        )
        expected.append(words)
    roots.append(g.float(1))
    var starts = List[Int]()
    var program = g.compile_roots(roots, starts)
    for root in range(8):
        var at = starts[2 * root]
        assert_equal(starts[2 * root + 1], 1)
        assert_equal(program.code[at + INSTRUCTION_A], Float32(0))
        assert_equal(program.code[at + INSTRUCTION_B], Float32(1 + root))
        assert_equal(program.code[at + INSTRUCTION_C], Float32(0))
        var result = run_code(
            ProgramSource(Pointer(to=program)), at, 1, inputs()
        )
        assert_equal(bitcast[DType.uint32, 4](result), expected[root])
    assert_equal(program.code[starts[16] + INSTRUCTION_B], Float32(0))


def test_every_payload_survives_constants_swizzles_joins_and_selects() raises:
    var graph = NodeGraph()
    # These words look like a float NaN, negative zero, infinity and subnormal.
    var words = graph.uvec4(0xFFFFFFFF, 0x80000000, 0x7F800000, 1)
    assert_equal(
        bits_of(graph, words), Words(0xFFFFFFFF, 0x80000000, 0x7F800000, 1)
    )
    var reverse = graph.swizzle(words, "wzyx")
    assert_equal(graph.type_of(reverse), NODE_UVEC4)
    assert_equal(
        bits_of(graph, reverse), Words(1, 0x7F800000, 0x80000000, 0xFFFFFFFF)
    )
    var parts = List[NodeRef]()
    parts.append(graph.swizzle(words, "z"))
    parts.append(graph.swizzle(words, "x"))
    parts.append(graph.swizzle(words, "y"))
    parts.append(graph.swizzle(words, "w"))
    assert_equal(
        bits_of(graph, graph.join(parts)),
        Words(0x7F800000, 0xFFFFFFFF, 0x80000000, 1),
    )
    var selected = graph.select(graph.vec4(1, 0, 1, 0), words, reverse)
    assert_equal(graph.type_of(selected), NODE_UVEC4)
    assert_equal(
        bits_of(graph, selected),
        Words(0xFFFFFFFF, 0x7F800000, 0x7F800000, 0xFFFFFFFF),
    )
    var scalar = graph.uint(16777217)
    assert_equal(first(graph, scalar), UInt32(16777217))
    assert_false(graph._is_zero(graph.uint(0x80000000).value))
    assert_false(graph._is_zero(graph.uint(0xFFFFFFFF).value))
    assert_true(graph._is_zero(graph.uint(0).value))
    assert_false(graph._is_zero(graph.add(scalar, scalar).value))
    var splat = graph.select(graph.vec2(0, 1), graph.uint(0x7F800001), scalar)
    assert_equal(graph.type_of(splat), NODE_UVEC2)
    assert_equal(bits_of(graph, splat)[0], UInt32(16777217))
    assert_equal(bits_of(graph, splat)[1], UInt32(0x7F800001))
    assert_equal(graph.type_of(graph.uvec3(1, 2, 3)), NODE_UVEC3)
    assert_equal(
        bits_of(graph, graph.uvec2(0x80000001, 0xFFFFFFFF))[1],
        UInt32(0xFFFFFFFF),
    )


def test_unsigned_arithmetic_and_order_do_not_round() raises:
    var g = NodeGraph()
    var high = g.uint(0xFFFFFFFF)
    var one = g.uint(1)
    var two = g.uint(2)
    var zero = g.uint(0)
    assert_equal(first(g, g.add(high, one)), UInt32(0))
    assert_equal(first(g, g.sub(zero, one)), UInt32(0xFFFFFFFF))
    assert_equal(first(g, g.mul(high, high)), UInt32(1))
    assert_equal(first(g, g.mul(g.uint(0x80000001), two)), UInt32(2))
    assert_equal(first(g, g.div(high, two)), UInt32(0x7FFFFFFF))
    assert_equal(first(g, g.mod(high, g.uint(3))), UInt32(0))
    assert_equal(first(g, g.mod(high, two)), UInt32(1))
    assert_equal(first(g, g.div(high, zero)), UInt32(0))
    assert_equal(first(g, g.mod(high, zero)), UInt32(0))
    assert_equal(first(g, g.negate(one)), UInt32(0xFFFFFFFF))
    assert_equal(first(g, g.min(high, g.uint(0x80000000))), UInt32(0x80000000))
    assert_equal(first(g, g.max(high, g.uint(0x80000000))), UInt32(0xFFFFFFFF))
    assert_equal(
        first(g, g.clamp(high, one, g.uint(16777217))), UInt32(16777217)
    )
    var larger = g.uint(16777217)
    var smaller = g.uint(16777216)
    assert_equal(value_of(g, g.less_than(smaller, larger))[0], Float32(1))
    assert_equal(value_of(g, g.less_than_equal(larger, smaller))[0], Float32(0))
    assert_equal(value_of(g, g.greater_than(larger, smaller))[0], Float32(1))
    assert_equal(
        value_of(g, g.greater_than_equal(larger, larger))[0], Float32(1)
    )
    assert_equal(value_of(g, g.equal(larger, smaller))[0], Float32(0))
    assert_equal(value_of(g, g.not_equal(larger, smaller))[0], Float32(1))
    assert_equal(g.type_of(g.less_than(larger, smaller)), NODE_FLOAT)
    var vector = g.uvec2(0xFFFFFFFF, 16777217)
    assert_equal(g.type_of(g.less_than(vector, larger)), NODE_VEC2)
    assert_equal(bits_of(g, g.add(vector, one))[0], UInt32(0))
    assert_equal(bits_of(g, g.add(vector, one))[1], UInt32(16777218))


def test_unsigned_bit_operations_and_bounded_shifts() raises:
    var g = NodeGraph()
    var high = g.uint(0xFFFFFFFF)
    var low = g.uint(0x01234567)
    assert_equal(first(g, g.bit_and(high, low)), UInt32(0x01234567))
    assert_equal(
        first(g, g.bit_or(g.uint(0x80000000), low)), UInt32(0x81234567)
    )
    assert_equal(first(g, g.bit_xor(high, low)), UInt32(0xFEDCBA98))
    assert_equal(first(g, g.bit_not(low)), UInt32(0xFEDCBA98))
    assert_equal(
        first(g, g.shift_left(g.uint(1), g.uint(31))), UInt32(0x80000000)
    )
    assert_equal(first(g, g.shift_right(high, g.uint(31))), UInt32(1))
    assert_equal(first(g, g.shift_right(high, g.uint(0))), UInt32(0xFFFFFFFF))
    assert_equal(first(g, g.shift_left(high, g.uint(32))), UInt32(0))
    assert_equal(first(g, g.shift_right(high, g.uint(33))), UInt32(0))
    assert_equal(first(g, g.shift_right(high, g.int32(-1))), UInt32(0))
    assert_equal(first(g, g.shift_right(high, g.int32(1))), UInt32(0x7FFFFFFF))
    var vector = g.uvec4(1, 2, 4, 8)
    assert_equal(
        bits_of(g, g.shift_left(vector, g.uint(1))), Words(2, 4, 8, 16)
    )
    assert_equal(
        bits_of(g, g.shift_right(vector, g.uvec4(0, 1, 2, 3))),
        Words(1, 1, 1, 1),
    )


def test_integer_conversions_are_explicit_and_reversible() raises:
    var g = NodeGraph()
    var words = g.uvec4(0xFFFFFFFF, 0x80000001, 0x7FFFFFFF, 16777217)
    var signed = g.uint_to_int(words)
    assert_equal(g.type_of(signed), NODE_IVEC4)
    assert_equal(
        bits_of(g, g.to_uint(signed)),
        Words(0xFFFFFFFF, 0x80000001, 0x7FFFFFFF, 16777217),
    )
    assert_equal(g.to_uint(words), words)
    assert_equal(g.to_int(signed), signed)
    assert_equal(
        value_of(g, g.int_to_float(signed)),
        Lanes(-1, -2147483648.0, 2147483648.0, 16777216),
    )
    assert_equal(
        value_of(g, g.uint_to_float(g.uint(0xFFFFFFFF)))[0],
        Float32(4294967296.0),
    )
    assert_equal(
        value_of(g, g.uint_to_bool(g.uvec4(0, 1, 0x80000000, 0xFFFFFFFF))),
        Lanes(0, 1, 1, 1),
    )
    assert_equal(
        value_of(
            g, g.int_to_bool(g.to_int(g.uvec4(0, 1, 0x80000000, 0xFFFFFFFF)))
        ),
        Lanes(0, 1, 1, 1),
    )
    assert_equal(first(g, g.to_uint(g.float(-1.75))), UInt32(0))
    assert_equal(first(g, g.to_uint(g.float(-1.0))), UInt32(0))
    assert_equal(first(g, g.to_uint(g.float(-0.5))), UInt32(0))
    assert_equal(first(g, g.to_uint(g.float(2147483648.0))), UInt32(0x80000000))
    assert_equal(first(g, g.to_uint(g.int32(-1))), UInt32(0xFFFFFFFF))
    assert_equal(first(g, g.to_int(g.float(2147483648.0))), UInt32(0))
    assert_equal(first(g, g.to_int(g.float(2147483520.0))), UInt32(0x7FFFFF80))
    assert_equal(first(g, g.to_int(g.float(-2147483904.0))), UInt32(0))
    assert_equal(first(g, g.to_int(g.float(-1.0))), UInt32(0xFFFFFFFF))
    assert_equal(first(g, g.to_int(g.float(-0.5))), UInt32(0))
    assert_equal(first(g, g.to_int(g.float(4294967296.0))), UInt32(0))
    assert_equal(first(g, g.to_uint(g.float(4294967040.0))), UInt32(0xFFFFFF00))
    assert_equal(first(g, g.to_uint(g.float(4294967296.0))), UInt32(0))
    assert_equal(first(g, g.to_uint(g.float(-4294967296.0))), UInt32(0))
    assert_equal(first(g, g.to_uint(g.float(0.75))), UInt32(0))
    assert_equal(
        first(
            g, g.to_uint(g.float(bitcast[DType.float32](UInt32(0x7FC00001))))
        ),
        UInt32(0),
    )
    assert_equal(
        first(g, g.to_int(g.float(bitcast[DType.float32](UInt32(0x7F800000))))),
        UInt32(0),
    )
    assert_equal(first(g, g.to_int(g.float(-2147483648.0))), UInt32(0x80000000))
    assert_equal(first(g, g.to_int(g.float(1.9))), UInt32(1))
    assert_equal(value_of(g, g.unsigned(g.float(-1)))[0], Float32(4294967296.0))


def test_signed_arithmetic_keeps_full_integer_results() raises:
    var g = NodeGraph()
    var minimum = g.int32(-2147483648)
    var negative = g.int32(-1)
    var one = g.int32(1)
    var two = g.int32(2)
    assert_equal(first(g, g.add(g.int32(2147483647), one)), UInt32(0x80000000))
    assert_equal(first(g, g.sub(minimum, one)), UInt32(0x7FFFFFFF))
    assert_equal(first(g, g.mul(minimum, two)), UInt32(0))
    assert_equal(first(g, g.div(minimum, negative)), UInt32(0x80000000))
    assert_equal(first(g, g.div(g.int32(-7), two)), UInt32(0xFFFFFFFD))
    assert_equal(first(g, g.mod(g.int32(-7), two)), UInt32(0xFFFFFFFF))
    assert_equal(first(g, g.mod(g.int32(7), g.int32(-2))), UInt32(1))
    assert_equal(first(g, g.div(minimum, g.int32(0))), UInt32(0))
    assert_equal(first(g, g.mod(minimum, g.int32(0))), UInt32(0))
    assert_equal(first(g, g.negate(minimum)), UInt32(0x80000000))
    assert_equal(first(g, g.abs(minimum)), UInt32(0x80000000))
    assert_equal(first(g, g.abs(g.int32(-16777217))), UInt32(16777217))
    assert_equal(first(g, g.sign(negative)), UInt32(0xFFFFFFFF))
    assert_equal(first(g, g.sign(one)), UInt32(1))
    assert_equal(first(g, g.sign(g.int32(0))), UInt32(0))
    assert_equal(first(g, g.min(negative, one)), UInt32(0xFFFFFFFF))
    assert_equal(first(g, g.max(negative, one)), UInt32(1))
    assert_equal(first(g, g.clamp(minimum, negative, one)), UInt32(0xFFFFFFFF))
    assert_equal(
        first(g, g.shift_right(minimum, g.uint(1))), UInt32(0xC0000000)
    )
    assert_equal(first(g, g.shift_right(minimum, g.uint(32))), UInt32(0))
    assert_equal(first(g, g.shift_right(minimum, g.int32(-1))), UInt32(0))
    assert_equal(first(g, g.bit_not(negative)), UInt32(0))
    assert_equal(
        first(g, g.bit_and(negative, g.int32(16777217))), UInt32(16777217)
    )
    assert_equal(first(g, g.bit_or(minimum, one)), UInt32(0x80000001))
    assert_equal(first(g, g.bit_xor(negative, one)), UInt32(0xFFFFFFFE))
    assert_equal(first(g, g.shift_left(one, g.int32(31))), UInt32(0x80000000))
    assert_equal(first(g, g.div(g.int32(7), g.int32(-2))), UInt32(0xFFFFFFFD))
    assert_equal(first(g, g.div(g.int32(-7), g.int32(-2))), UInt32(3))
    assert_equal(first(g, g.mod(g.int32(-7), g.int32(-2))), UInt32(0xFFFFFFFF))
    assert_equal(
        first(g, g.add(g.int32(16777217), g.float(1))), UInt32(16777218)
    )
    assert_equal(value_of(g, g.less_than(negative, one))[0], Float32(1))
    assert_equal(value_of(g, g.less_than_equal(one, negative))[0], Float32(0))
    assert_equal(value_of(g, g.greater_than(one, negative))[0], Float32(1))
    assert_equal(
        value_of(g, g.greater_than_equal(negative, negative))[0], Float32(1)
    )
    assert_equal(value_of(g, g.equal(negative, negative))[0], Float32(1))
    assert_equal(value_of(g, g.not_equal(negative, one))[0], Float32(1))


def test_unsigned_uniforms_keep_metadata_and_bits() raises:
    var g = NodeGraph()
    var scalar = g.uniform_uint("scalar", UInt32(0xFFFFFFFF))
    var vector = g.uniform_uint(
        "vector", Words(0x7F800001, 0xFFFFFFFF, 0x80000000, 16777217)
    )
    var pair = g.uniform_uint("pair", SIMD[DType.uint32, 2](1, 2))
    var triple = g.uniform_uint("triple", NODE_UVEC3)
    _ = g.uniform_uint("triple_value", UInt32(1), UInt32(2), UInt32(3))
    var floating = g.uniform("floating", Float32(3))
    var starts = List[Int]()
    var p = g.compile_roots([scalar, vector, pair, triple, floating], starts)
    assert_equal(p.uniform_types[0], NODE_UINT)
    assert_equal(p.uniform_types[1], NODE_UVEC4)
    assert_equal(p.read_unsigned("scalar"), Words(0xFFFFFFFF, 0, 0, 0))
    assert_equal(
        p.read_unsigned("vector"),
        Words(0x7F800001, 0xFFFFFFFF, 0x80000000, 16777217),
    )
    assert_equal(p.read_unsigned("pair"), Words(1, 2, 0, 0))
    assert_equal(p.read_unsigned("triple"), Words(0))
    assert_equal(p.read_unsigned("triple_value"), Words(1, 2, 3, 0))
    p.set_uniform_uint(
        "triple", UInt32(0xFFFFFFFF), UInt32(0x80000000), UInt32(16777217)
    )
    assert_equal(
        p.read_unsigned("triple"), Words(0xFFFFFFFF, 0x80000000, 16777217, 0)
    )
    p.set_uniform_uint("scalar", UInt32(0x80000001))
    p.set_uniform_uint("vector", Words(0xFFFFFFFF, 16777217, 1, 0))
    p.set_uniform_uint("pair", SIMD[DType.uint32, 2](0xFFFFFFFF, 0x80000000))
    assert_equal(p.read_unsigned("scalar")[0], UInt32(0x80000001))
    assert_equal(p.read_unsigned("pair"), Words(0xFFFFFFFF, 0x80000000, 0, 0))
    assert_equal(
        bitcast[DType.uint32, 4](
            run_code(
                ProgramSource(Pointer(to=p)), starts[2], starts[3], inputs()
            )
        ),
        Words(0xFFFFFFFF, 16777217, 1, 0),
    )
    with assert_raises(contains="not a float"):
        p.set_uniform("scalar", Float32(1))
    with assert_raises(contains="not a vec2"):
        p.set_uniform("pair", Vector2(1, 2))
    with assert_raises(contains="not a uint"):
        p.set_uniform_uint("floating", UInt32(1))
    with assert_raises(contains="unsigned uniform"):
        _ = p.read_unsigned("floating")
    with assert_raises(contains="no uniform"):
        _ = p.read_unsigned("missing")
    with assert_raises(contains="not a uvec2"):
        p.set_uniform_uint("scalar", SIMD[DType.uint32, 2](1, 2))
    with assert_raises(contains="unsigned type"):
        _ = g.uniform_uint("invalid", NODE_FLOAT)
    with assert_raises(contains="already"):
        _ = g.uniform_uint("scalar", UInt32(1))
    with assert_raises(contains="name"):
        _ = g.uniform_uint("", UInt32(1))
    with assert_raises(contains="one to four"):
        _ = g.uniform_uint[8]("too_wide", SIMD[DType.uint32, 8](0))
    with assert_raises(contains="one to four"):
        p.set_uniform_uint[8]("vector", SIMD[DType.uint32, 8](0))


def returned_unsigned(mut g: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
    g.If(g.greater_than(args[0], g.uint(16777216)))
    g.Return(g.add(args[0], g.uint(1)))
    g.End()
    return g.uint(9)


def returned_signed(mut g: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
    g.If(g.less_than(args[0], g.int32(0)))
    g.Return(g.sub(args[0], g.int32(1)))
    g.End()
    return g.int32(8)


def test_variables_functions_and_unrolled_loops_preserve_integer_types() raises:
    var g = NodeGraph()
    var current = g.Var(g.uint(0xFFFFFFFE))
    _ = g.Loop(4)
    g.assign(current, g.add(g.get(current), g.uint(1)))
    g.End()
    assert_equal(g.type_of(g.get(current)), NODE_UINT)
    assert_equal(first(g, g.get(current)), UInt32(2))
    g.If(g.equal(g.get(current), g.uint(2)))
    g.assign(current, g.uint(0x7F800001))
    g.Else()
    g.assign(current, g.uint(0xFFFFFFFF))
    g.End()
    assert_equal(first(g, g.get(current)), UInt32(0x7F800001))
    var u = Fn("unsigned", [NODE_UINT], NODE_UINT, returned_unsigned)
    assert_equal(first(g, g.call(u, [g.uint(16777217)])), UInt32(16777218))
    assert_equal(first(g, g.call(u, [g.uint(1)])), UInt32(9))
    var i = Fn("signed", [NODE_INT], NODE_INT, returned_signed)
    assert_equal(first(g, g.call(i, [g.int32(-16777217)])), UInt32(0xFEFFFFFE))
    assert_equal(first(g, g.call(i, [g.int32(1)])), UInt32(8))
    var vector = g.Var(g.uvec3(1, 2, 3))
    g.assign(vector, g.uint(0xFFFFFFFF))
    assert_equal(bits_of(g, g.get(vector))[2], UInt32(0xFFFFFFFF))
    var exact = g.Var(g.int32(-2147483648))
    _ = g.Loop(3)
    g.If(g.less_than(g.get(exact), g.int32(-2147483647)))
    g.assign(exact, g.add(g.get(exact), g.int32(1)))
    g.Else()
    g.Break()
    g.End()
    g.End()
    assert_equal(first(g, g.get(exact)), UInt32(0x80000001))


def test_integer_payloads_refuse_float_math_and_mixed_families() raises:
    var g = NodeGraph()
    var u = g.uint(0xFFFFFFFF)
    var i = g.int32(-1)
    var f = g.float(1)
    with assert_raises(contains="cannot add"):
        _ = g.add(u, f)
    with assert_raises(contains="cannot add"):
        _ = g.add(u, i)
    with assert_raises(contains="numeric family"):
        _ = g.join([u, f])
    with assert_raises(contains="float-only"):
        _ = g.sin(u)
    with assert_raises(contains="float-only"):
        _ = g.abs(u)
    with assert_raises(contains="float-only"):
        _ = g.floor(i)
    with assert_raises(contains="exact integer"):
        _ = g.pow(u, u)
    with assert_raises(contains="exact integer"):
        _ = g.mix(u, u, u)
    with assert_raises(contains="exact integer"):
        _ = g.smoothstep(u, u, u)
    with assert_raises(contains="exact integer"):
        _ = g.dot(u, u)
    with assert_raises(contains="exact integer"):
        _ = g.varying(u)
    with assert_raises(contains="exact integer"):
        _ = g.dfdx(u)
    with assert_raises(contains="exact integer"):
        _ = g.remap(u, u, u, u, u)
    with assert_raises(contains="exact integer"):
        _ = g.select(u, u, u)
    with assert_raises(contains="component"):
        _ = g.swizzle(u, "y")
    with assert_raises(contains="four components"):
        _ = g.join([g.uvec3(1, 2, 3), g.uvec2(4, 5)])
    with assert_raises(contains="wrong type"):
        _ = g.uint_to_float(i)
    with assert_raises(contains="wrong type"):
        _ = g.int_to_float(u)
    with assert_raises(contains="wrong type"):
        _ = g.uint_to_bool(i)
    with assert_raises(contains="wrong type"):
        _ = g.int_to_bool(u)
    with assert_raises(contains="unsigned value"):
        _ = g.uint_to_int(f)
    with assert_raises(contains="no node"):
        _ = g.to_uint(NodeRef(-1))
    with assert_raises(contains="no node"):
        _ = g.to_int(NodeRef(-1))
    with assert_raises():
        g.set_output(COLOR_NODE, g.uvec3(1, 2, 3))
    var doubled = g.add(u, u)
    with assert_raises(contains="not a float"):
        g.set_input(doubled, 0, f)
    with assert_raises():
        _ = g.shift_left(u, g.uvec2(1, 2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
