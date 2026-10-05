# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""GLSL integer, Boolean, version and conservative-folding boundaries."""

from materials import glsl, nodes
from std.testing import TestSuite, assert_equal
from tests.test_glsl import (
    RAW_VERTEX,
    VERTEX,
    number,
    paint,
    refused,
    refused_statement,
    run,
)


def test_known_unsigned_bits_and_complement_keep_exact_metadata() raises:
    assert_equal(number("float(6u & 3u)"), Float32(2))
    assert_equal(number("float(6u | 3u)"), Float32(7))
    assert_equal(number("float(6u ^ 3u)"), Float32(5))
    assert_equal(number("float((~0u) == 4294967295u)"), Float32(1))


def test_unsigned_bit_operand_families_and_widths_are_independent() raises:
    refused_statement("uint v = 1u & 1;", "requires unsigned operands")
    refused_statement("uint v = 1u << 1.0;", "requires unsigned operands")
    refused_statement("uint v = 1u << true;", "requires unsigned operands")
    refused_statement("uvec2 v = uvec2(1u) & uvec3(1u);", "one vector width")
    assert_equal(number("float(1u << 2)"), Float32(4))
    assert_equal(number("float(1u << 2u)"), Float32(4))
    assert_equal(
        number("float(all(equal(1u | uvec2(2u), uvec2(3u))))"), Float32(1)
    )
    assert_equal(
        number("float(all(equal(uvec2(2u) | 1u, uvec2(3u))))"), Float32(1)
    )
    var program = glsl.compile_shader_material(
        VERTEX,
        "uniform uint mask; void main(){gl_FragColor=vec4(float(7u & mask));}",
    )
    program.set_uniform_uint("mask", UInt32(3))
    assert_equal(run(program)[0], Float32(3))
    program.set_uniform_uint("mask", UInt32(4))
    assert_equal(run(program)[0], Float32(4))


def test_logical_left_operands_and_remainder_types_are_checked() raises:
    refused_statement("bool v = 1.0 ^^ true;", "^^ joins two bools")
    refused_statement("bool v = 1.0 || true;", "|| joins two bools")
    refused_statement("uint v = 1u % 1.0;", "% takes two ints")
    refused_statement("int v = 1 / 0;", "integer division or remainder by zero")
    refused_statement("int v = 1 % 0;", "integer division or remainder by zero")
    assert_equal(number("float(true ^^ false)"), Float32(1))
    assert_equal(number("float(false || true)"), Float32(1))
    assert_equal(number("float(7 % 3)"), Float32(1))


def test_uninitialized_integer_declarations_can_then_be_assigned() raises:
    # The declaration constructs zeros; every value is assigned before use.
    assert_equal(
        number(
            "float(a.x + b.z) + float(c)",
            "",
            "uvec2 a; uvec3 b; int c; a=uvec2(2u); b=uvec3(3u); c=7;",
        ),
        Float32(12),
    )


def test_unsigned_switch_and_matrix_columns_are_accepted() raises:
    assert_equal(
        number(
            "value",
            "",
            (
                "float value=0.0; uint choice=2u; switch(choice){"
                "case 2u: value=7.0; break; default: value=9.0;}"
            ),
        ),
        Float32(7),
    )
    assert_equal(number("mat3(2.0)[1u][1]"), Float32(2))
    var result = paint(
        "varying vec3 delta; void main(){gl_FragColor=vec4(delta,1.0);}",
        (
            "varying vec3 delta; void main(){"
            "mat3 turn=mat3(modelMatrix[0u].xyz,modelMatrix[1u].xyz,"
            "modelMatrix[2u].xyz);"
            "delta=turn*normal-(modelMatrix*vec4(normal,0.0)).xyz;"
            "gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}"
        ),
    )
    assert_equal(result[0], Float32(0))
    assert_equal(result[1], Float32(0))
    assert_equal(result[2], Float32(0))


def test_raw_unsigned_forms_require_version_300() raises:
    var modern = glsl.compile_raw_shader_material(
        RAW_VERTEX,
        (
            "#version 300 es\nprecision highp float; out vec4 result;"
            "void main(){uint value=3u; result=vec4(float(uint(value)));}"
        ),
    )
    assert_equal(run(modern)[0], Float32(3))
    var vertex100 = (
        "attribute vec3 position; uniform mat4 projectionMatrix;"
        "uniform mat4 modelViewMatrix;"
        + VERTEX
    )
    refused(
        "precision highp float;void main(){gl_FragColor=vec4(float(uint(1)));}",
        "unsigned types require GLSL ES 3.0",
        vertex100,
        True,
    )


def test_refused_type_names_are_checked_in_constructor_expressions() raises:
    refused_statement("mat2x2(1.0);", "the type mat2x2 is outside the subset")


def test_known_signed_conversion_checks_each_range_boundary() raises:
    for expression in ["int(1e40)", "int(-2147483904.0)", "int(2147483648.0)"]:
        refused_statement(
            "int value=" + expression + ";",
            "int conversion requires a finite 32-bit signed value",
        )
    assert_equal(number("float(int(-2147483648.0))"), Float32(-2147483648.0))
    assert_equal(number("float(int(2147483520.0))"), Float32(2147483520.0))
    assert_equal(number("float(int(-3.75))"), Float32(-3))


def test_empty_folding_passes_preserve_an_empty_graph() raises:
    var graph = nodes.NodeGraph()
    glsl._fold_integer_constants(graph)
    glsl._simplify_proved_control(graph, List[Optional[Float32]]())
    assert_equal(graph.count(), 0)


def test_vector_swizzle_condition_is_not_replaced_with_its_source() raises:
    var graph = nodes.NodeGraph()
    var vector = graph.vec2(0, 1)
    var condition = graph.swizzle(vector, "y")
    var chosen = graph.select(condition, graph.float(7), graph.float(9))
    var proof = List[Optional[Float32]](length=graph.count(), fill=None)
    glsl._simplify_proved_control(graph, proof)
    assert_equal(graph._kinds[chosen.value], nodes.NODE_SELECT)
    assert_equal(graph._inputs[chosen.value * 3], condition.value)
    graph.set_output(nodes.OPACITY_NODE, chosen)
    assert_equal(run(graph.compile(), nodes.OPACITY_NODE)[0], Float32(7))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
