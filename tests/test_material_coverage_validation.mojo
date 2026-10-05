# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact immediate boundaries and empty payload bookkeeping are checked."""

from materials import nodes
from materials.node_validation import (
    _integer_instruction,
    _payload_span,
    _whole,
    validate_surface_program,
)
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises


def test_empty_payload_span_leaves_classifications_unchanged() raises:
    var types: List[Int] = [-1, 41]
    var starts: List[Int] = [0, 1]
    _payload_span(types, starts, 1, 0, 45)
    assert_equal(types[0], -1)
    assert_equal(types[1], 41)
    assert_equal(starts[0], 0)
    assert_equal(starts[1], 1)


def test_integer_immediate_and_opcode_independently_change_validity() raises:
    var written = List[Bool](length=nodes.MAX_REGISTERS, fill=True)
    # All six width-bearing opcodes accept exactly 1..4; a binary opcode
    # accepts only zero. Include both machine-int boundaries in refusals.
    for kind in [
        nodes.NODE_UINT_NEGATE,
        nodes.NODE_UINT_BIT_NOT,
        nodes.NODE_INT_NEGATE,
        nodes.NODE_INT_BIT_NOT,
        nodes.NODE_INT_ABS,
        nodes.NODE_INT_SIGN,
    ]:
        for immediate in range(1, 5):
            _integer_instruction(kind, 0, 0, 0, immediate, written)
        for immediate in [Int.MIN, -1, 0, 5, Int.MAX]:
            with assert_raises(contains="invalid immediate"):
                _integer_instruction(kind, 0, 0, 0, immediate, written)
    _integer_instruction(nodes.NODE_UINT_ADD, 0, 1, 0, 0, written)
    for immediate in [Int.MIN, -1, 1, 2, 3, 4, 5, Int.MAX]:
        with assert_raises(contains="invalid immediate"):
            _integer_instruction(
                nodes.NODE_UINT_ADD, 0, 1, 0, immediate, written
            )


def test_opcode_range_is_checked_before_surface_instruction_validation() raises:
    assert_equal(_whole(0, nodes.NODE_INT_LAST.value), 0)
    assert_equal(
        _whole(Float32(nodes.NODE_INT_LAST.value), nodes.NODE_INT_LAST.value),
        nodes.NODE_INT_LAST.value,
    )
    for invalid in [
        Float32(-1),
        Float32(nodes.NODE_INT_LAST.value + 1),
        Float32(0.5),
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
    ]:
        var graph = nodes.NodeGraph()
        graph.set_output(nodes.OPACITY_NODE, graph.float(1))
        var program = graph.compile()
        var start = Int(program.code[nodes.OPACITY_NODE.value * 2])
        program.code[start] = invalid
        var message = String()
        try:
            validate_surface_program(program)
        except error:
            message = String(error)
        # Nonfinite opcodes retain the preceding finite-code diagnostic;
        # finite invalid values retain _whole's integer diagnostic.
        if (
            invalid == inf[DType.float32]()
            or invalid == -inf[DType.float32]()
            or invalid != invalid
        ):
            assert_equal(
                message, "Object JSON: a node program needs finite code"
            )
        else:
            assert_equal(
                message, "Object JSON: a node program has an invalid integer"
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
