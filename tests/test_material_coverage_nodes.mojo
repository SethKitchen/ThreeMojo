# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent integer-family and explicit-gradient boundary regressions."""

from materials import nodes
from materials.compute_ids import (
    ComputeStatementId,
    INSTANCE_INDEX,
    StorageBufferId,
)
from materials.compute_nodes import StorageBuffer
from math.matrix3 import Matrix3
from math.vector2 import Vector2
from render.texture_store import TextureId
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises
from tests.test_glsl import run
from tests.test_unsigned_nodes import first


def test_signed_promotion_is_symmetric_and_includes_the_third_operand() raises:
    var graph = nodes.NodeGraph()
    var one = graph.float(1)
    var exact = graph.int32(16777217)
    assert_equal(first(graph, graph.add(one, exact)), UInt32(16777218))
    assert_equal(first(graph, graph.add(exact, one)), UInt32(16777218))
    var upper = graph.int32(3)
    var promoted = graph.clamp(graph.float(5), one, upper)
    assert_equal(graph.type_of(promoted), nodes.NODE_INT)
    assert_equal(first(graph, promoted), UInt32(3))
    var already_signed = graph.clamp(graph.int32(5), graph.int32(1), upper)
    assert_equal(first(graph, already_signed), UInt32(3))


def test_assignment_checks_integer_family_and_matrix_sources() raises:
    var graph = nodes.NodeGraph()
    var signed = graph.Var(graph.int32(7))
    var floating = graph.Var(graph.float(9))
    with assert_raises(contains="cannot assign"):
        graph.assign(signed, graph.uint(1))
    with assert_raises(contains="cannot assign"):
        graph.assign(signed, graph.uniform("matrix", Matrix3()))
    with assert_raises(contains="cannot assign"):
        graph.assign(floating, graph.int32(1))
    assert_equal(first(graph, graph.get(signed)), UInt32(7))
    graph.assign(signed, graph.float(2.75))
    assert_equal(first(graph, graph.get(signed)), UInt32(2))


def test_float_values_are_refused_by_exact_integer_conversions() raises:
    var graph = nodes.NodeGraph()
    var floating = graph.float(1)
    with assert_raises(contains="wrong type"):
        _ = graph.uint_to_float(floating)
    with assert_raises(contains="wrong type"):
        _ = graph.int_to_float(floating)
    assert_equal(
        graph.type_of(graph.uint_to_float(graph.uint(1))), nodes.NODE_FLOAT
    )
    assert_equal(
        graph.type_of(graph.int_to_float(graph.int32(1))), nodes.NODE_FLOAT
    )


def test_join_refuses_a_signed_and_float_pair_in_both_orders() raises:
    var graph = nodes.NodeGraph()
    var signed = graph.int32(1)
    var floating = graph.float(2)
    with assert_raises(contains="one numeric family"):
        _ = graph.join([signed, floating])
    with assert_raises(contains="one numeric family"):
        _ = graph.join([floating, signed])
    assert_equal(graph.type_of(graph.join([signed, signed])), nodes.NODE_IVEC2)
    assert_equal(
        graph.type_of(graph.join([floating, floating])), nodes.NODE_VEC2
    )


def test_compute_storage_and_results_refuse_exact_integer_types() raises:
    var graph = nodes.NodeGraph()
    var index = graph.float(0)
    for type in [nodes.NODE_UINT, nodes.NODE_IVEC2]:
        with assert_raises(contains="float or a vector"):
            _ = StorageBuffer(1, type)
        with assert_raises(contains="float or a vector"):
            _ = graph.storage_element(StorageBufferId(0), index, type)
        with assert_raises(contains="float or a vector"):
            _ = graph.compute_result(ComputeStatementId(0), type)
    var valid = StorageBuffer(1, nodes.NODE_VEC2)
    assert_equal(valid.count, 1)
    assert_equal(len(valid.array), 2)
    assert_equal(
        graph.type_of(
            graph.storage_element(StorageBufferId(0), index, nodes.NODE_VEC2)
        ),
        nodes.NODE_VEC2,
    )
    assert_equal(
        graph.type_of(
            graph.compute_result(ComputeStatementId(0), nodes.NODE_VEC2)
        ),
        nodes.NODE_VEC2,
    )


def test_unsigned_read_from_a_program_without_uniforms_is_rejected() raises:
    var graph = nodes.NodeGraph()
    graph.set_output(nodes.OPACITY_NODE, graph.float(1))
    var program = graph.compile()
    assert_equal(len(program.uniform_names), 0)
    with assert_raises(contains="no uniform named absent"):
        _ = program.read_unsigned("absent")


def test_each_runtime_gradient_source_defers_constant_evaluation() raises:
    for variant in range(7):
        var graph = nodes.NodeGraph()
        var gradient: nodes.NodeRef
        if variant == 0:
            gradient = graph.uniform("gradient", Vector2(0.25, 0.5))
        elif variant == 1:
            gradient = graph.swizzle(graph.time(), "xx")
        elif variant == 2:
            gradient = graph.swizzle(graph.camera_position(), "xy")
        elif variant == 3:
            gradient = graph.swizzle(
                graph.column(graph.camera_view_matrix(), 0), "xy"
            )
        elif variant == 4:
            gradient = graph.uv()
        elif variant == 5:
            gradient = graph.swizzle(
                graph.compute_builtin(INSTANCE_INDEX), "xx"
            )
        else:
            gradient = graph.swizzle(
                graph.viewport_texture(graph.vec2(0, 0)), "xy"
            )
        var texel = graph.texture_grad(
            TextureId(0), graph.vec2(0.25, 0.5), gradient, graph.vec2(0, 0)
        )
        assert_equal(graph.type_of(texel), nodes.NODE_VEC4)
        assert_equal(graph._kinds[texel.value], nodes.NODE_TEXTURE_GRAD)


def test_each_constant_gradient_component_must_be_finite() raises:
    for bad in [nan[DType.float32](), inf[DType.float32]()]:
        for component in range(2):
            var graph = nodes.NodeGraph()
            var gradient = graph.vec2(bad, 0) if component == 0 else graph.vec2(
                0, bad
            )
            with assert_raises(contains="texture gradient must be finite"):
                _ = graph.texture_grad(
                    TextureId(0), graph.vec2(0, 0), gradient, graph.vec2(0, 0)
                )
    var graph = nodes.NodeGraph()
    var texel = graph.texture_grad(
        TextureId(0), graph.vec2(0, 0), graph.vec2(0.25, 0.5), graph.vec2(0, 0)
    )
    assert_equal(graph.type_of(texel), nodes.NODE_VEC4)


def test_varying_cannot_read_an_explicit_gradient_texture() raises:
    var graph = nodes.NodeGraph()
    # A surface-dependent coordinate keeps this read in the corner context.
    var texel = graph.texture_grad(
        TextureId(0), graph.uv(), graph.vec2(0, 0), graph.vec2(0, 0)
    )
    graph.set_output(nodes.FRAGMENT_NODE, graph.varying(texel))
    with assert_raises(contains="A varying runs once per corner"):
        _ = graph.compile()


def test_nonfinite_texture_coordinates_return_transparent_black() raises:
    var graph = nodes.NodeGraph()
    var uv = graph.uniform("coordinate", Vector2(0.25, 0.5))
    var texel = graph.texture_grad(
        TextureId(0), uv, graph.vec2(0, 0), graph.vec2(0, 0)
    )
    graph.set_output(nodes.FRAGMENT_NODE, texel)
    var program = graph.compile()
    var valid = run(program, nodes.FRAGMENT_NODE)
    assert_equal(valid[0], Float32(0.25))
    assert_equal(valid[1], Float32(0.5))
    assert_equal(valid[3], Float32(0.25))
    for bad in [nan[DType.float32](), inf[DType.float32]()]:
        for component in range(2):
            var coordinate = Vector2(bad, 0.5) if component == 0 else Vector2(
                0.25, bad
            )
            program.set_uniform("coordinate", coordinate)
            var result = run(program, nodes.FRAGMENT_NODE)
            assert_equal(result, nodes.Lanes(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
