# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent controls for each operand of the GLSL validation guards.

Keep the existing rejected language explicit beside the loop correction.
These controls complete the module's grouped-condition coverage without
changing any parser guard or coverage obligation.
"""

from materials.glsl import (
    _Compiler,
    _Token,
    _INT,
    _NAME,
    _END,
    compile_raw_shader_material,
)
from tests.test_glsl import RAW_VERTEX, refused, refused_statement, run
from std.testing import TestSuite, assert_equal


def test_raw_volume_uniforms_obey_the_shader_version() raises:
    var modern = compile_raw_shader_material(
        RAW_VERTEX,
        (
            "#version 300 es\nprecision highp float; uniform sampler3D cloud;"
            " uniform sampler2DArray layers; out vec4 color; void main() {"
            " color = vec4(1.0); }"
        ),
    )
    assert_equal(run(modern)[0], 1)
    refused(
        (
            "uniform sampler2DArray layers; void main() { gl_FragColor ="
            " vec4(1.0); }"
        ),
        "sampler2DArray is not in this shader's GLSL version",
        RAW_VERTEX,
        True,
    )


def test_relational_requires_an_operator_token_kind() raises:
    # A defensive parser guard: operator-looking text in a nonoperator
    # token must not consume the next expression. The lexer never emits
    # this token pair, so exercise the internal boundary directly.
    var compiler = _Compiler(False)
    compiler.tokens = [
        _Token(_INT, "1", 1, 1),
        _Token(_NAME, "<", 0, 1),
        _Token(_END, "", 0, 1),
    ]
    var value = compiler.relational()
    assert_equal(value.number, 1)
    assert_equal(compiler.at, 1)


def test_matrix_builtins_and_negative_indices_are_refused() raises:
    refused_statement(
        "vec3 x = mat3(1.0)[-1];", "the index is outside the mat3"
    )
    refused_statement(
        "mat3 x = inverse();", "inverse() takes one mat2, mat3 or mat4"
    )
    refused_statement(
        "float x = determinant(viewMatrix);",
        "determinant() takes one mat2, mat3 or mat4",
    )


def test_texture_signatures_check_each_argument() raises:
    refused_statement(
        "vec4 x = textureProj();",
        "textureProj() takes a sampler2D and a vec3 or a vec4",
    )
    refused_statement(
        "vec4 x = textureProj(1.0, vec3(0.0));",
        "textureProj() takes a sampler2D and a vec3 or a vec4",
    )
    refused_statement(
        "vec4 x = textureLod(1.0, vec2(0.0), 0.0);",
        "textureLod() takes a sampler2D, a vec2 and a float",
    )
    refused(
        (
            "uniform sampler2D map; void main() { gl_FragColor ="
            " textureLod(map, vec3(0.0), 0.0); }"
        ),
        "textureLod() takes a sampler2D, a vec2 and a float",
    )
    refused(
        (
            "uniform sampler2D map; void main() { gl_FragColor ="
            " textureLod(map, vec2(0.0), 0); }"
        ),
        "textureLod() takes a sampler2D, a vec2 and a float",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
