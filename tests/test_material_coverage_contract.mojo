# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Helper refusals and conservative folding retain their exact contracts.

Unknown graph kinds are never accepted as valid programs: both optimizer
controls require final compiler refusal before any interpreter can run.
"""

from materials import glsl, nodes
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_unsigned_nodes import first, value_of
from tests.test_glsl import number, refused_statement


def test_scalar_matching_rejects_a_matrix_destination() raises:
    var graph = nodes.NodeGraph()
    var scalar = graph.float(2)
    with assert_raises(contains="cannot match"):
        _ = graph._match(scalar, nodes.NODE_MAT3, "match")
    var vector = graph._match(scalar, nodes.NODE_VEC2, "match")
    assert_equal(graph.type_of(vector), nodes.NODE_VEC2)
    var result = value_of(graph, vector)
    assert_equal(result[0], Float32(2))
    assert_equal(result[1], Float32(2))


def test_scalar_unary_result_refuses_exact_integer_input() raises:
    var graph = nodes.NodeGraph()
    var exact = graph.int32(-3)
    with assert_raises(contains="float-only node"):
        _ = graph._unary(nodes.NODE_NEGATE, exact, scalar=True)
    var retained = graph._unary(nodes.NODE_NEGATE, exact)
    assert_equal(graph.type_of(retained), nodes.NODE_INT)
    assert_equal(first(graph, retained), UInt32(3))
    var floating = graph._unary(nodes.NODE_NEGATE, graph.float(-3), scalar=True)
    assert_equal(graph.type_of(floating), nodes.NODE_FLOAT)
    assert_equal(value_of(graph, floating)[0], Float32(3))


def test_loop_proof_never_treats_an_unknown_opcode_as_an_integer() raises:
    var graph = nodes.NodeGraph()
    var unknown_kind = nodes.NodeKind(nodes.NODE_INT_LAST.value + 1)
    assert_false(unknown_kind.is_valid())
    var left = graph.float(2)
    var right = graph.float(3)
    var unknown = graph._add(
        unknown_kind, nodes.NODE_FLOAT, left.value, right.value
    )
    var proof = glsl._loop_constants(graph, unknown)
    assert_false(Bool(proof[unknown.value]))
    assert_equal(graph._kinds[unknown.value], unknown_kind)
    graph.set_output(nodes.OPACITY_NODE, unknown)
    with assert_raises(contains="kind or a type there is not"):
        _ = graph.compile()

    var valid = nodes.NodeGraph()
    var sum = valid.add(valid.int32(2), valid.int32(3))
    var known = glsl._loop_constants(valid, sum)
    assert_true(Bool(known[sum.value]))
    assert_equal(bitcast[DType.uint32](known[sum.value].value()), UInt32(5))


def test_integer_folding_cannot_hide_an_invalid_opcode_from_validation() raises:
    var graph = nodes.NodeGraph()
    var unknown_kind = nodes.NodeKind(nodes.NODE_INT_LAST.value + 1)
    var left = graph.float(2)
    var right = graph.float(3)
    var unknown = graph._add(
        unknown_kind, nodes.NODE_FLOAT, left.value, right.value
    )
    glsl._fold_integer_constants(graph)
    assert_equal(graph._kinds[unknown.value], unknown_kind)
    assert_equal(graph._inputs[unknown.value * 3], left.value)
    assert_equal(graph._inputs[unknown.value * 3 + 1], right.value)
    graph.set_output(nodes.OPACITY_NODE, unknown)
    with assert_raises(contains="kind or a type there is not"):
        _ = graph.compile()

    var valid = nodes.NodeGraph()
    var sum = valid.add(valid.int32(2), valid.int32(3))
    glsl._fold_integer_constants(valid)
    assert_equal(valid._kinds[sum.value], nodes.NODE_CONSTANT)
    assert_equal(first(valid, sum), UInt32(5))


def test_index_literal_preserves_each_supported_register_family() raises:
    var compiler = glsl._Compiler(False)
    var float_index = compiler.graph.float(0)
    var signed_index = compiler.graph.int32(0)
    var unsigned_index = compiler.graph.uint(0)
    var floating = compiler.index_literal(float_index, 3)
    var signed = compiler.index_literal(signed_index, 3)
    var unsigned = compiler.index_literal(unsigned_index, 3)
    assert_equal(compiler.graph.type_of(floating), nodes.NODE_FLOAT)
    assert_equal(compiler.graph.type_of(signed), nodes.NODE_INT)
    assert_equal(compiler.graph.type_of(unsigned), nodes.NODE_UINT)
    assert_equal(value_of(compiler.graph, floating)[0], Float32(3))
    assert_equal(first(compiler.graph, signed), UInt32(3))
    assert_equal(first(compiler.graph, unsigned), UInt32(3))


def test_remainder_keeps_integer_sign_and_original_type_refusals() raises:
    assert_equal(number("float(7u % 3u)"), Float32(1))
    assert_equal(number("float(-7 % 3)"), Float32(-1))
    assert_equal(number("float(7 % -3)"), Float32(1))
    refused_statement("float v = 7.0 % 3.0;", "% takes two ints")
    refused_statement("uint v = 7u % 3;", "% takes two ints")
    refused_statement("int v = 7 % 3u;", "% takes two ints")
    # A float zero first violates the remainder type requirement.
    refused_statement("float v = 7.0 % 0.0;", "% takes two ints")
    refused_statement("int v = 7 % 0;", "integer division or remainder by zero")
    refused_statement(
        "uint v = 7u % 0u;", "integer division or remainder by zero"
    )


def test_signed_opcode_classification_checks_both_closed_interval_bounds() raises:
    for raw in [
        Int.MIN,
        nodes.NODE_INT_ADD.value - 1,
        nodes.NODE_INT_LAST.value + 1,
        Int.MAX,
    ]:
        assert_false(nodes._is_signed_operation(raw))
    for raw in [nodes.NODE_INT_ADD.value, nodes.NODE_INT_LAST.value]:
        assert_true(nodes._is_signed_operation(raw))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
