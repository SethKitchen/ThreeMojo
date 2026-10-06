# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Unsigned GLSL parser, conversion, assignment and resource boundaries."""

from materials.glsl import (
    _Type,
    compile_raw_shader_material,
    compile_shader_material,
)
from materials.nodes import NodeProgram
from tests.test_glsl import (
    RAW_VERTEX,
    VERTEX,
    number,
    refused,
    refused_statement,
    run,
)
from std.testing import TestSuite, assert_equal, assert_true


def test_unsigned_type_names_and_shapes() raises:
    for width in range(1, 5):
        var type = _Type(40 + width)
        assert_true(type.is_valid())
        assert_true(type.is_uint())
        assert_true(type.holds())
        assert_equal(type.width(), width)
        assert_equal(type.resized(1), _Type(41))
        assert_equal(type.graph_type().value, 40 + width)
    assert_equal(_Type(41).name(), "uint")
    assert_equal(_Type(44).name(), "uvec4")


def test_unsigned_literals_are_checked_and_exact() raises:
    assert_equal(number("float(077u)"), 63)
    assert_equal(number("float(0XffU)"), 255)
    assert_equal(number("float(0xffffffffu == 4294967295u)"), 1)
    refused_statement("uint x = 4294967296u;", "exceeds 32 bits")
    refused_statement("uint x = 0x100000000u;", "exceeds 32 bits")
    refused_statement(
        "uint x = 9999999999999999999999999999999u;", "exceeds 32 bits"
    )
    refused_statement("uint x = 08u;", "octal integer")
    refused_statement("uint x = 1.0u;", "a letter cannot follow a number")
    refused_statement("uint x = 1uu;", "a letter cannot follow a number")
    refused_statement("int x = 4294967295;", "use a u suffix")
    refused(
        "void main() { uint x; gl_FragColor = vec4(1.0); }",
        "unsigned types require GLSL ES 3.0",
        RAW_VERTEX,
        True,
    )
    refused(
        "void main() { gl_FragColor = vec4(float(1u)); }",
        "unsigned literals require GLSL ES 3.0",
        RAW_VERTEX,
        True,
    )


def test_unsigned_conversion_ranges_and_type_errors() raises:
    assert_equal(number("float(uint(-1) == 0xffffffffu)"), 1)
    assert_equal(number("float(uint(int(0x80000001u)) == 0x80000001u)"), 1)
    assert_equal(number("float(uint(4294967040.0) == 4294967040u)"), 1)
    assert_equal(number("float(bool(0x80000000u))"), 1)
    refused_statement(
        "uint x = uint(-1.0);", "uint conversion requires a finite value"
    )
    refused_statement(
        "uint x = uint(4294967296.0);",
        "uint conversion requires a finite value",
    )
    refused_statement(
        "uint x = uint(1e40);", "uint conversion requires a finite value"
    )
    refused_statement("uint x = 1;", "cannot give a uint a int")
    refused_statement("uint x = 1u + 1;", "cannot use + on a uint and a int")
    refused_statement("uvec2 x = uvec2(1u) + uvec3(2u);", "cannot use +")
    refused_statement("uint x = abs(1u);", "no signature of abs()")
    refused_statement(
        "uint x = 1u / 0u;", "integer division or remainder by zero"
    )
    refused_statement(
        "uint x = 1u % 0u;", "integer division or remainder by zero"
    )
    refused_statement("uint x = 1u << 32;", "shift count must be from 0 to 31")
    refused_statement("uint x = 1u >> -1;", "shift count must be from 0 to 31")
    refused_statement("uvec2 x = 1u << uvec2(1u);", "shift count is scalar")
    refused_statement(
        "uvec2 x = uvec2(1u) << uvec3(1u);", "shift count is scalar"
    )


def test_unsigned_index_and_for_boundaries() raises:
    assert_equal(
        number(
            "float(v[1u] == 0xffffffffu)",
            "",
            "uvec2 v = uvec2(1u, 0xffffffffu);",
        ),
        1,
    )
    assert_equal(
        number(
            "float(a[1u] == 0x80000001u)",
            "",
            "uint a[2u] = uint[2](0u, 1u); a[1u] = 0x80000001u;",
        ),
        1,
    )
    refused_statement("uint x = uvec2(1u)[2u];", "index is outside")
    refused_statement("uint a[257u];", "array holds at most")
    assert_equal(
        number(
            "float(s == 0x80000006u)",
            "",
            (
                "uint s = 0u; for (uint i = 0x80000001u; i < 0x80000004u; i++)"
                " { s += i; }"
            ),
        ),
        1,
    )
    assert_equal(
        number(
            "float(n)",
            "",
            "uint n = 0u; for (uint i = 0xfffffffeu; i != 1u; i++) { n++; }",
        ),
        3,
    )
    assert_equal(
        number(
            "float(v.x == 0u && v.y == 2u)",
            "",
            "uvec2 v = uvec2(0xffffffffu, 1u); v++;",
        ),
        1,
    )


def test_unsigned_uniform_updates_preserve_bits_and_types() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform uint value; void main() { gl_FragColor = vec4(float(value"
            " == 0xffffffffu)); }"
        ),
    )
    program.set_uniform_uint("value", UInt32(0xFFFFFFFF))
    assert_equal(run(program)[0], 1)
    program.set_uniform_uint("value", UInt32(0x80000000))
    assert_equal(run(program)[0], 0)
    program.set_uniform_uint("value", UInt32(0xFFFFFFFF))
    assert_equal(run(program)[0], 1)


def test_integer_matrix_constructors_convert_to_float() raises:
    assert_equal(number("mat2(1)[0][0]"), 1)
    assert_equal(number("mat3(2u)[1][1]"), 2)
    assert_equal(number("mat4(3)[2][2]"), 3)
    assert_equal(
        number(
            "mat3(ivec3(1, 2, 3), uvec3(4u, 5u, 6u), vec3(7.0, 8.0, 9.0))[1][2]"
        ),
        6,
    )


def test_unsigned_function_indexes_use_the_selected_return() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag; uint choose(bool b) { if (b) return 0u; return"
            " 1u; } void main() { vec2 v = vec2(10.0, 20.0); gl_FragColor ="
            " vec4(v[choose(flag)]); }"
        ),
    )
    program.set_uniform("flag", Float32(1))
    assert_equal(run(program)[0], 10)
    program.set_uniform("flag", Float32(0))
    assert_equal(run(program)[0], 20)
    refused(
        (
            "uint value() { return 1u; } const uint n = value(); void main() {"
            " gl_FragColor = vec4(float(n)); }"
        ),
        "constant expression",
    )


def test_known_float_rounding_matches_unsigned_runtime_conversion() raises:
    assert_equal(
        number("vec2(10.0, 20.0)[uint((16777216.0 + 1.0) - 16777216.0)]"), 10
    )
    assert_equal(
        number(
            "float(count)",
            "",
            (
                "uint count = 0u; for (uint i = uint(16777216.0 + 1.0); i <"
                " 16777218u; i++) { count++; }"
            ),
        ),
        2,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
