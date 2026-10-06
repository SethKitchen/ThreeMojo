# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent loop references for the GLSL ES 3.00 statement rules.

The integer recurrence i = i + 1 gives n body executions and the sum
n * (n - 1) / 2. A while condition is called n + 1 times; a do condition
is called once per body. These expectations do not use the node evaluator
or the frontend's loop budget. See docs/wiki/Node-materials.md.
"""

from materials.glsl import (
    _fold_integer_constants,
    shader_graph,
    _loop_binary,
    _loop_constant,
    compile_raw_shader_material,
    compile_shader_material,
)
from tests.test_glsl import (
    RAW_VERTEX,
    VERTEX,
    number,
    refused,
    refused_statement,
    run,
)
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from std.math import inf, nan
from std.memory import bitcast
from materials.nodes import (
    NodeGraph,
    NodeRef,
    NODE_CONSTANT,
    NODE_UINT_ADD,
    NODE_UINT_FIRST,
    NODE_INT_LAST,
    NODE_FLOAT,
    NODE_COPY,
    NODE_ADD,
    NODE_SUB,
    NODE_MUL,
    NODE_DIV,
    NODE_LESS_THAN,
    NODE_LESS_THAN_EQUAL,
    NODE_GREATER_THAN,
    NODE_GREATER_THAN_EQUAL,
    NODE_EQUAL,
    NODE_NOT_EQUAL,
    NODE_XOR,
    NODE_MIN,
)


def test_glsl3_while_reference_boundaries() raises:
    var counts: List[Int] = [0, 1, 63, 64, 65, 128, 256]
    var sums: List[Int] = [0, 0, 1953, 2016, 2080, 8128, 32640]
    var expressions: List[String] = ["float(i)", "sum", "float(calls)"]
    for at in range(len(counts)):
        var expected: List[Int] = [counts[at], sums[at], counts[at] + 1]
        for output in range(len(expressions)):
            # Separate result roots keep the existing 32-register limit.
            # Each shader executes the same body and condition calls.
            var fragment = (
                "#version 300 es\nprecision highp float;\nout vec4 color;\n"
                "bool ask(inout int calls, int i) { calls++; return i < "
                + String(counts[at])
                + "; }\nvoid main() { int i = 0; int calls = 0; float sum ="
                " 0.0;"
                " while (ask(calls, i)) { sum += float(i); i++; }"
                " color = vec4("
                + expressions[output]
                + "); }"
            )
            var got = run(compile_raw_shader_material(RAW_VERTEX, fragment))
            assert_equal(got[0], Float32(expected[output]))


def test_glsl3_do_reference_boundaries() raises:
    var bounds: List[Int] = [0, 1, 63, 64, 65, 128, 256]
    var counts: List[Int] = [1, 1, 63, 64, 65, 128, 256]
    var sums: List[Int] = [0, 0, 1953, 2016, 2080, 8128, 32640]
    var expressions: List[String] = ["float(i)", "sum", "float(calls)"]
    for at in range(len(bounds)):
        var expected: List[Int] = [counts[at], sums[at], counts[at]]
        for output in range(len(expressions)):
            var fragment = (
                "#version 300 es\nprecision highp float;\nout vec4 color;\n"
                "bool ask(inout int calls, int i) { calls++; return i < "
                + String(bounds[at])
                + "; }\nvoid main() { int i = 0; int calls = 0; float sum ="
                " 0.0;"
                " do { sum += float(i); i++; } while (ask(calls, i));"
                " color = vec4("
                + expressions[output]
                + "); }"
            )
            var got = run(compile_raw_shader_material(RAW_VERTEX, fragment))
            assert_equal(got[0], Float32(expected[output]))


def test_loop_jumps_at_the_budget() raises:
    assert_equal(
        number(
            "float(i)",
            "",
            "int i = 0; while (true) { i++; if (i == 64) break; }",
        ),
        64,
    )
    assert_equal(
        number(
            "float(i)",
            "",
            "int i = 0; do { i++; if (i == 64) break; } while (true);",
        ),
        64,
    )
    assert_equal(
        number(
            "s",
            "",
            (
                "int i = 0; float s = 0.0; while (i < 64) { i++; if (i < 64)"
                " continue; s += 1.0; }"
            ),
        ),
        1,
    )
    assert_equal(
        number(
            "s",
            "",
            (
                "int i = 0; float s = 0.0; do { i++; if (i < 64) continue; s"
                " += 1.0; } while (i < 64);"
            ),
        ),
        1,
    )
    assert_equal(
        number(
            "1.0",
            (
                "void first() { int i = 0; while (true) { i++; if (i == 64)"
                " return; } }"
            ),
            "first();",
        ),
        1,
    )
    refused(
        (
            "void first() { int i = 0; while (true) { i++; if (i == 257)"
            " return; } } void main() { first(); gl_FragColor = vec4(1.0); }"
        ),
        "must provably stop within",
    )
    # A break must skip the do condition, including its inout write.
    assert_equal(
        number(
            "float(calls)",
            "bool ask(inout int calls) { calls++; return true; }",
            "int calls = 0; do { break; } while (ask(calls));",
        ),
        0,
    )


def test_exhaustion_is_refused_even_when_its_output_is_dead() raises:
    var loops: List[String] = [
        "int i = 0; while (i < 257) i++;",
        "int i = 0; do { i++; } while (i < 257);",
        "while (true) {}",
        "do { continue; } while (true);",
        "while (true) { continue; }",
    ]
    for loop in loops:
        refused_statement(loop, "must provably stop within 256 body executions")
    # A later terminating iteration must not hide earlier exhaustion.
    refused_statement(
        (
            "for (int j = 0; j < 2; j++) { int i = 0; int n = j == 0 ? 257 : 1;"
            " while (i < n) i++; }"
        ),
        "must provably stop within",
    )
    # The first outer iteration must not serve as proof for later ones.
    refused_statement(
        (
            "for (int j = 0; j < 2; j++) { int i = 0; int n = j == 0 ? 1 : 257;"
            " while (i < n) i++; }"
        ),
        "must provably stop within",
    )
    refused_statement(
        "int i = 0; while (i < 1) { int j = 0; while (j < 1) j++; i++; }",
        "would grow the graph past",
    )


def test_bounded_loops_keep_runtime_data() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform float step; void main() { int i = 0; float s = 0.0; while"
            " (i < 64) { s += step; i++; } gl_FragColor = vec4(s); }"
        ),
    )
    program.set_uniform("step", 3.0)
    assert_equal(run(program)[0], 192)
    program.set_uniform("step", -2.0)
    assert_equal(run(program)[0], -128)
    assert_equal(
        number(
            "float(s)",
            "",
            (
                "int s = 0; for (int j = 0; j < 2; j++) { int i = 0; int n = j"
                " == 0 ? 31 : 33; while (i < n) { i++; s++; } }"
            ),
        ),
        64,
    )


def test_unproved_runtime_exits_are_explicitly_unsupported() raises:
    refused(
        (
            "uniform int count; void main() { int i = 0; while (i < count) i++;"
            " gl_FragColor = vec4(float(i)); }"
        ),
        "exit proof is unsupported",
    )
    refused_statement(
        "int i = 0; do { i++; } while (float(i) < gl_FragCoord.x);",
        "exit proof is unsupported",
    )
    refused(
        (
            "uniform sampler2D map; void main() { while (texture(map,"
            " vec2(0.0)).x > 0.0) {} gl_FragColor = vec4(1.0); }"
        ),
        "exit proof is unsupported",
    )


def test_scalar_loop_proof_uses_only_supported_operations() raises:
    var kinds = [
        NODE_ADD,
        NODE_SUB,
        NODE_MUL,
        NODE_DIV,
        NODE_LESS_THAN,
        NODE_LESS_THAN_EQUAL,
        NODE_GREATER_THAN,
        NODE_GREATER_THAN_EQUAL,
        NODE_EQUAL,
        NODE_NOT_EQUAL,
        NODE_XOR,
    ]
    var expected: List[Float32] = [6, 2, 8, 2, 0, 0, 1, 1, 0, 1, 0]
    for i in range(len(kinds)):
        assert_equal(_loop_binary(kinds[i], 4, 2).value(), expected[i])
    assert_false(_loop_binary(NODE_MIN, 1, 2))
    var graph = NodeGraph()
    var zero = graph.float(0)
    var one = graph.float(1)
    var unknown = graph.uniform("runtime", 0.0)
    assert_equal(
        _loop_constant(
            graph, graph._add(NODE_COPY, NODE_FLOAT, one.value)
        ).value(),
        1,
    )
    assert_false(_loop_constant(graph, graph.vec2(0, 1)))
    assert_false(_loop_constant(graph, graph.float(inf[DType.float32]())))
    assert_false(_loop_constant(graph, graph.float(nan[DType.float32]())))
    assert_false(_loop_constant(graph, graph.div(one, zero)))
    assert_false(_loop_constant(graph, graph.float(1e-40)))
    assert_false(
        _loop_constant(graph, graph.mul(graph.float(1e-20), graph.float(1e-20)))
    )
    assert_equal(
        _loop_constant(graph, graph.float(1.1754943508222875e-38)).value(),
        Float32(1.1754943508222875e-38),
    )
    assert_false(_loop_constant(graph, graph.swizzle(graph.vec2(0, 1), "x")))
    assert_equal(_loop_constant(graph, graph.swizzle(one, "x")).value(), 1)
    assert_false(_loop_constant(graph, graph.sin(one)))
    assert_false(_loop_constant(graph, graph.min(one, zero)))
    assert_false(_loop_constant(graph, graph.add(one, unknown)))
    assert_false(_loop_constant(graph, graph.add(unknown, one)))
    assert_equal(_loop_constant(graph, graph.negate(one)).value(), -1)
    assert_equal(
        _loop_constant(graph, graph.trunc(graph.float(-2.9))).value(), -2
    )
    assert_equal(_loop_constant(graph, graph.logical_not(zero)).value(), 1)
    assert_equal(_loop_constant(graph, graph.logical_not(one)).value(), 0)
    assert_equal(_loop_constant(graph, graph.add(one, one)).value(), 2)


def test_scalar_loop_proof_selects_and_unknowns() raises:
    var graph = NodeGraph()
    var zero = graph.float(0)
    var one = graph.float(1)
    var unknown = graph.uniform("runtime", 0.0)
    assert_equal(
        _loop_constant(graph, graph.select(one, one, unknown)).value(), 1
    )
    assert_equal(
        _loop_constant(graph, graph.select(zero, unknown, one)).value(), 1
    )
    assert_equal(
        _loop_constant(graph, graph.select(unknown, one, one)).value(), 1
    )
    assert_false(_loop_constant(graph, graph.select(unknown, one, zero)))
    assert_false(_loop_constant(graph, graph.select(unknown, unknown, one)))
    assert_false(_loop_constant(graph, graph.select(unknown, one, unknown)))
    assert_false(
        _loop_constant(graph, graph.select(unknown, zero, graph.negate(zero)))
    )
    var operands: List[NodeRef] = [zero, one, unknown]
    var and_expected: List[Int] = [0, 0, 0, 0, 1, -1, 0, -1, -1]
    var or_expected: List[Int] = [0, 1, -1, 1, 1, 1, -1, 1, -1]
    for a in range(3):
        for b in range(3):
            var both = _loop_constant(
                graph, graph.logical_and(operands[a], operands[b])
            )
            var either = _loop_constant(
                graph, graph.logical_or(operands[a], operands[b])
            )
            if and_expected[a * 3 + b] < 0:
                assert_false(both)
            else:
                assert_true(both)
                assert_equal(both.value(), Float32(and_expected[a * 3 + b]))
            if or_expected[a * 3 + b] < 0:
                assert_false(either)
            else:
                assert_true(either)
                assert_equal(either.value(), Float32(or_expected[a * 3 + b]))


def test_signed_zero_cannot_supply_a_false_exit_proof() raises:
    refused(
        (
            "uniform bool on; void main() { float x = on ? 0.0 : -0.0; while"
            " (1.0 / x < 0.0) {} gl_FragColor = vec4(1.0); }"
        ),
        "exit proof is unsupported",
    )


def test_larger_finite_loops_fail_explicitly_or_use_constant_for() raises:
    # Independent GLSL3 recurrence fixtures above the while/do budget.
    var bounds: List[Int] = [257, 320, 512]
    var sums: List[Int] = [32896, 51040, 130816]
    for at in range(len(bounds)):
        var bound = String(bounds[at])
        refused_statement(
            "int i = 0; while (i < " + bound + ") i++;",
            "must provably stop within 256",
        )
        refused_statement(
            "int i = 0; do { i++; } while (i < " + bound + ");",
            "must provably stop within 256",
        )
        var fragment = (
            "#version 300 es\nprecision highp float; out vec4 color; void"
            " main() { float sum = 0.0; for (int i = 0; i < "
            + bound
            + "; i++) sum += float(i); color = vec4(sum); }"
        )
        assert_equal(
            run(compile_raw_shader_material(RAW_VERTEX, fragment))[0],
            Float32(sums[at]),
        )


def test_loop_proof_respects_dead_paths_and_ignored_calls() raises:
    assert_equal(number("1.0", "", "if (false) { while (true) {} }"), 1)
    assert_equal(
        number(
            "first()",
            "float first() { return 2.0; while (true) {} return -1.0; }",
        ),
        2,
    )
    refused_statement(
        "for (int j = 0; j < 1; j++) { while (true) {} }",
        "must provably stop within",
    )
    refused(
        (
            "float ignored() { while (true) {} return 1.0; } void main() {"
            " ignored(); gl_FragColor = vec4(1.0); }"
        ),
        "must provably stop within",
    )
    # This proof is deliberately incomplete: the correlated exit is safe,
    # but scalar constant propagation alone cannot establish that fact.
    refused(
        (
            "uniform bool flag; void main() { while (flag) { break; }"
            " gl_FragColor = vec4(1.0); }"
        ),
        "exit proof is unsupported",
    )
    # An unknown condition is safe when the body leaves before asking it.
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag; void main() { do { break; } while (flag);"
            " gl_FragColor = vec4(1.0); }"
        ),
    )
    assert_equal(run(program)[0], 1)
    program.set_uniform("flag", 1.0)
    assert_equal(run(program)[0], 1)


def test_vertex_and_fragment_loop_budgets_are_independent() raises:
    var vertex = (
        "void main() { int i = 0; while (i < 64) i++; gl_Position ="
        " projectionMatrix * modelViewMatrix * vec4(position, 1.0); }"
    )
    var fragment = (
        "void main() { int i = 0; while (i < 63) i++; gl_FragColor ="
        " vec4(float(i)); }"
    )
    assert_equal(run(compile_shader_material(vertex, fragment))[0], 63)
    refused(
        fragment,
        "GLSL vertex shader",
        (
            "void main() { while (true) {} gl_Position = projectionMatrix *"
            " modelViewMatrix * vec4(position, 1.0); }"
        ),
    )


def test_scalar_return_uses_proved_control_without_more_registers() raises:
    # The successful scalar proof removes inactive selections. The same
    # workload now fits the unchanged 32-register budget.
    assert_equal(
        number(
            "first()",
            (
                "float first() { int i = 0; while (true) { i++; if (i == 63)"
                " return float(i); } return -1.0; }"
            ),
        ),
        63,
    )


def test_scalar_integer_constants_keep_exact_bits() raises:
    var graph = NodeGraph()
    var high = graph.uint(UInt32(4294967295))
    var two = graph.uint(UInt32(2))
    var wrapped = graph.add(high, two)
    var signed = graph.to_int(wrapped)
    var numeric = graph.int_to_float(signed)
    var runtime = graph.uniform_uint("runtime", UInt32(3))
    var dynamic = graph.add(runtime, wrapped)
    var float_sum = graph.add(graph.float(0.25), graph.float(0.5))
    _fold_integer_constants(graph)
    assert_equal(graph._kinds[wrapped.value], NODE_CONSTANT)
    assert_equal(
        bitcast[DType.uint32](graph._values[wrapped.value * 4]), UInt32(1)
    )
    assert_equal(graph._values[numeric.value * 4], Float32(1))
    assert_equal(graph._kinds[dynamic.value], NODE_UINT_ADD)
    assert_equal(graph._kinds[float_sum.value], NODE_ADD)


def test_folded_integer_constants_share_only_exact_types_and_bits() raises:
    var graph = NodeGraph()
    var positive_zero = graph.float(0)
    var negative_zero = graph.float(-Float32(0))
    var existing = graph.float(7)
    var integer = graph.to_int(existing)
    var converted = graph.int_to_float(integer)
    var zero = graph.uint_to_float(graph.uint(UInt32(0)))
    var unsigned = graph.to_uint(integer)
    var payload = graph.uint(UInt32(0x7FC00001))
    var round_trip = graph.to_uint(graph.to_int(payload))
    _fold_integer_constants(graph)
    assert_equal(graph._kinds[converted.value], NODE_COPY)
    assert_equal(graph._inputs[converted.value * 3], existing.value)
    assert_equal(graph._kinds[integer.value], NODE_CONSTANT)
    assert_equal(
        bitcast[DType.uint32](graph._values[integer.value * 4]), UInt32(7)
    )
    assert_equal(graph._inputs[zero.value * 3], positive_zero.value)
    assert_equal(graph._kinds[unsigned.value], NODE_CONSTANT)
    assert_true(graph._types[unsigned.value] != graph._types[integer.value])
    assert_equal(graph._kinds[round_trip.value], NODE_COPY)
    assert_equal(graph._inputs[round_trip.value * 3], payload.value)
    assert_equal(
        bitcast[DType.uint32](graph._values[payload.value * 4]),
        UInt32(0x7FC00001),
    )
    assert_equal(
        bitcast[DType.uint32](graph._values[negative_zero.value * 4]),
        UInt32(0x80000000),
    )


def test_unrolled_integer_indices_do_not_keep_runtime_arithmetic() raises:
    var graph = shader_graph(
        VERTEX,
        """
        uniform float scale;
        void main() {
            float sum = 0.0;
            for (int i = 0; i < 256; i++) sum += float(i) * scale;
            gl_FragColor = vec4(sum);
        }
    """,
    )
    for node in range(graph.count()):
        var kind = graph._kinds[node]
        assert_false(
            kind.value >= NODE_UINT_FIRST.value
            and kind.value <= NODE_INT_LAST.value
        )
    var program = graph.compile()
    program.set_uniform("scale", Float32(2))
    # Arithmetic progression: 2 * 256 * 255 / 2, exactly representable.
    assert_equal(run(program)[0], Float32(65280))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
