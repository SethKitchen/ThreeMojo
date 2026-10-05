# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Defensive no-rewrite checks for incomplete or unproved graph state.

These check existing conservative guards. They never compile or execute malformed
IR and never assert that a missing gate/source or invalid swizzle is valid.
The asserted property is that unavailable proof cannot rewrite a select.
"""

from materials import glsl, nodes
from std.testing import TestSuite, assert_equal


def test_simplifier_preserves_a_select_without_a_proved_gate_ref() raises:
    var graph = nodes.NodeGraph()
    var yes = graph.float(7)
    var no = graph.float(9)
    var pending = graph._add(
        nodes.NODE_SELECT, nodes.NODE_FLOAT, b=yes.value, c=no.value
    )
    var proof = List[Optional[Float32]](length=graph.count(), fill=None)
    var count = graph.count()
    glsl._simplify_proved_control(graph, proof)
    assert_equal(graph.count(), count)
    assert_equal(graph._kinds[pending.value], nodes.NODE_SELECT)
    assert_equal(graph._inputs[pending.value * 3], -1)
    assert_equal(graph._inputs[pending.value * 3 + 1], yes.value)
    assert_equal(graph._inputs[pending.value * 3 + 2], no.value)


def test_simplifier_preserves_a_swizzle_with_no_source_proof() raises:
    var graph = nodes.NodeGraph()
    var gate = graph._add(nodes.NODE_SWIZZLE, nodes.NODE_FLOAT)
    var yes = graph.float(7)
    var no = graph.float(9)
    var pending = graph.select(gate, yes, no)
    var proof = List[Optional[Float32]](length=graph.count(), fill=None)
    glsl._simplify_proved_control(graph, proof)
    assert_equal(graph._kinds[gate.value], nodes.NODE_SWIZZLE)
    assert_equal(graph._inputs[gate.value * 3], -1)
    assert_equal(graph._kinds[pending.value], nodes.NODE_SELECT)
    assert_equal(graph._inputs[pending.value * 3], gate.value)
    assert_equal(graph._inputs[pending.value * 3 + 1], yes.value)
    assert_equal(graph._inputs[pending.value * 3 + 2], no.value)


def test_simplifier_requires_a_valid_scalar_broadcast_before_using_proof() raises:
    for packed in [0, 1]:
        var graph = nodes.NodeGraph()
        var scalar = graph.float(1)
        var gate = graph._add(
            nodes.NODE_SWIZZLE,
            nodes.NODE_FLOAT,
            scalar.value,
            value=nodes.Lanes(Float32(packed), 0, 0, 0),
        )
        var yes = graph.float(7)
        var no = graph.float(9)
        var pending = graph.select(gate, yes, no)
        var proof = List[Optional[Float32]](length=graph.count(), fill=None)
        proof[scalar.value] = Float32(1)
        glsl._simplify_proved_control(graph, proof)
        if packed == 0:
            assert_equal(graph._kinds[pending.value], nodes.NODE_COPY)
            assert_equal(graph._inputs[pending.value * 3], yes.value)
            assert_equal(graph._inputs[pending.value * 3 + 1], -1)
            assert_equal(graph._inputs[pending.value * 3 + 2], -1)
        else:
            # Lane one of a scalar is not a valid scalar broadcast.
            # Keep it unproved; this malformed state is never interpreted.
            assert_equal(graph._kinds[pending.value], nodes.NODE_SELECT)
            assert_equal(graph._inputs[pending.value * 3], gate.value)
            assert_equal(graph._inputs[pending.value * 3 + 1], yes.value)
            assert_equal(graph._inputs[pending.value * 3 + 2], no.value)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
