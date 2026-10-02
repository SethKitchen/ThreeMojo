# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent material and node-stage boundary cases for compound coverage."""

from materials import nodes, glsl
from materials.node_validation import validate_surface_program
from tests.test_glsl import refused_statement, refused, VERTEX
from materials.material import Material, subsurface_scattering
from math.vector2 import Vector2
from render.framebuffer import Color
from render.texture_store import TextureId
from std.math import nan, inf
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_each_scattering_quantity_must_be_finite() raises:
    for field in range(5):
        for bad in [nan[DType.float32](), inf[DType.float32]()]:
            var value = subsurface_scattering(TextureId(0))
            if field == 0:
                value.distortion = bad
            elif field == 1:
                value.ambient = bad
            elif field == 2:
                value.attenuation = bad
            elif field == 3:
                value.power = bad
            else:
                value.scale = bad
            with assert_raises(contains="numbers must be finite"):
                value.check()
    var ordinary = subsurface_scattering(TextureId(0))
    ordinary.check()
    assert_equal(ordinary.power, Float32(2))


def test_each_nonnegative_scattering_quantity_rejects_negative() raises:
    for field in range(4):
        var value = subsurface_scattering(TextureId(0))
        if field == 0:
            value.power = -1
        elif field == 1:
            value.scale = -1
        elif field == 2:
            value.ambient = -1
        else:
            value.attenuation = -1
        with assert_raises(contains="cannot be negative"):
            value.check()
    var zero = subsurface_scattering(
        TextureId(0), distortion=-1, ambient=0, attenuation=0, power=0, scale=0
    )
    zero.check()
    assert_equal(zero.distortion, Float32(-1))


def test_normal_scale_y_requires_a_normal_map() raises:
    with assert_raises(contains="A normal scale needs a normal map"):
        _ = Material(Color(255, 255, 255), normal_scale=Vector2(1, 2))
    var mapped = Material(
        Color(255, 255, 255),
        normal_map=TextureId(0),
        normal_scale=Vector2(1, 2),
    )
    assert_equal(mapped.normal_scale.y, Float32(2))
    _ = Material(Color(255, 255, 255), normal_scale=Vector2(1, 1))


def test_every_builtin_attribute_name_uses_its_own_node() raises:
    var graph = nodes.NodeGraph()
    for name in ["position", "normal", "uv", "uv1", "color"]:
        with assert_raises(contains="is a built-in attribute"):
            _ = graph.attribute(name, nodes.NODE_VEC3)
    var custom = graph.attribute("paint", nodes.NODE_VEC3)
    assert_true(custom.value >= 0)


def test_size_stage_refuses_every_fragment_only_node_kind() raises:
    var graph = nodes.NodeGraph()
    var forbidden: List[nodes.NodeKind] = [
        nodes.NODE_TEXTURE,
        nodes.NODE_TEXTURE_LEVEL,
        nodes.NODE_TEXEL_FETCH,
        nodes.NODE_TEXTURE_SIZE,
        nodes.NODE_TEXTURE_CUBE,
        nodes.NODE_TEXTURE_3D,
        nodes.NODE_TEXTURE_ARRAY,
        nodes.NODE_VIEWPORT_TEXTURE,
        nodes.NODE_DFDX,
        nodes.NODE_DFDY,
        nodes.NODE_FRAG_COORD,
        nodes.NODE_POINT_COORD,
        nodes.NODE_SCREEN_UV,
        nodes.NODE_FRONT_FACING,
    ]
    for kind in forbidden:
        with assert_raises(contains="A size node runs once per point"):
            graph._check_stage(nodes.SIZE_NODE, kind)
        # These operations are legal in the fragment stage.
        graph._check_stage(nodes.COLOR_NODE, kind)
    var constant = graph.float(1)
    graph._check_stage(nodes.SIZE_NODE, graph._kinds[constant.value])


def test_matrix_tail_cannot_be_read_as_an_instruction() raises:
    var graph = nodes.NodeGraph()
    var root = graph.float(1)
    graph.set_output(nodes.MASK_NODE, root)
    graph._kinds[root.value] = nodes.NODE_MATRIX_TAIL
    with assert_raises(contains="only multiplied"):
        _ = graph.compile()


def test_varyings_refuse_each_texture_and_derivative_operation() raises:
    for variant in range(10):
        var graph = nodes.NodeGraph()
        var uv = graph.uv()
        var xyz = graph.position_world()
        var level = graph.swizzle(uv, "x")
        var sampler = graph.texture_uniform("map")
        var value = graph.texture(sampler, uv)
        if variant == 1:
            value = graph.texture_level(sampler, uv, level)
        elif variant == 2:
            value = graph.texture_load(sampler, uv, level)
        elif variant == 3:
            value = graph.texture_size(sampler, level)
        elif variant == 4:
            var cube = graph.cube_uniform("sky")
            value = graph.texture_cube(cube, xyz)
        elif variant == 5:
            var volume = graph.volume_uniform("cloud")
            value = graph.texture_3d(volume, xyz)
        elif variant == 6:
            var array = graph.array_uniform("layers")
            value = graph.texture_array(array, xyz)
        elif variant == 7:
            value = graph.viewport_texture(uv)
        elif variant == 8:
            value = graph.dfdx(uv)
        elif variant == 9:
            value = graph.dfdy(uv)
        var scalar = graph.swizzle(value, "x")
        var varying = graph.varying(scalar)
        graph.set_output(nodes.MASK_NODE, varying)
        with assert_raises(contains="A varying runs once per corner"):
            _ = graph.compile()


def test_derivatives_cannot_nest_in_either_direction() raises:
    for outer in range(2):
        for inner in range(2):
            var graph = nodes.NodeGraph()
            var uv = graph.uv()
            var first = graph.dfdx(uv) if inner == 0 else graph.dfdy(uv)
            var second = graph.dfdx(first) if outer == 0 else graph.dfdy(first)
            graph.set_output(nodes.MASK_NODE, graph.swizzle(second, "x"))
            with assert_raises(contains="A derivative cannot read another"):
                _ = graph.compile()


def test_disjoint_serialized_output_spans_can_run_in_reverse_order() raises:
    var graph = nodes.NodeGraph()
    graph.set_output(nodes.COLOR_NODE, graph.vec3(1, 0, 0))
    graph.set_output(nodes.EMISSIVE_NODE, graph.vec3(0, 1, 0))
    var program = graph.compile()
    var first = nodes.COLOR_NODE.value * 2
    var second = nodes.EMISSIVE_NODE.value * 2
    var old_first = program.code[first]
    var old_count = program.code[first + 1]
    program.code[first] = program.code[second]
    program.code[first + 1] = program.code[second + 1]
    program.code[second] = old_first
    program.code[second + 1] = old_count
    assert_true(program.code[first] > program.code[second])
    validate_surface_program(program)


def test_matrix_function_arguments_and_negative_indices_are_checked() raises:
    refused_statement(
        "mat3 m = mat3(1.0); vec3 v = m[-1];", "the index is outside the mat3"
    )
    refused_statement(
        "mat3 m = transpose();", "transpose() takes one mat2, mat3 or mat4"
    )
    refused_statement(
        "mat4 m = transpose(viewMatrix);",
        "transpose() takes one mat2, mat3 or mat4",
    )


def test_texture_projection_and_lod_validate_each_argument() raises:
    for expression in ["textureProj()", "textureProj(1.0,vec3(1.0))"]:
        refused_statement(
            "vec4 v = " + expression + ";",
            "takes a sampler2D and a vec3 or a vec4",
        )
    for expression in [
        "textureLod(1.0,vec2(0.0),0.0)",
        "textureLod(map,vec3(0.0),0.0)",
        "textureLod(map,vec2(0.0),vec2(0.0))",
    ]:
        refused(
            "uniform sampler2D map; void main(){gl_FragColor = "
            + expression
            + ";}",
            "takes a sampler2D, a vec2 and a float",
        )


def test_raw_volume_sampler_version_is_checked_for_both_kinds() raises:
    for kind in ["sampler3D", "sampler2DArray"]:
        var vertex100 = (
            "#version 100\nattribute vec3 position; uniform mat4"
            " projectionMatrix; uniform mat4 modelViewMatrix; void"
            " main(){gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}"
        )
        refused(
            "#version 100\nprecision highp float; uniform "
            + kind
            + " tex; void main(){gl_FragColor=vec4(1.0);}",
            "not in this shader's GLSL version",
            vertex100,
            True,
        )
        var vertex300 = (
            "#version 300 es\nin vec3 position; uniform mat4 projectionMatrix;"
            " uniform mat4 modelViewMatrix; void"
            " main(){gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}"
        )
        var program = glsl.compile_raw_shader_material(
            vertex300,
            "#version 300 es\nprecision highp float; uniform "
            + kind
            + " tex; out vec4 color; void"
            " main(){color=texture(tex,vec3(0.0));}",
        )
        assert_true(len(program.code) > nodes.PROGRAM_HEADER)


def test_relational_parser_does_not_treat_a_name_as_an_operator() raises:
    var compiler = glsl._Compiler(False)
    compiler.tokens = [
        glsl._Token(glsl._INT, "1", 1, 1),
        glsl._Token(glsl._NAME, "<", 0, 1),
        glsl._Token(glsl._INT, "2", 2, 1),
        glsl._Token(glsl._END, "", 0, 1),
    ]
    var value = compiler.relational()
    assert_equal(value.number, Float64(1))
    assert_equal(compiler.at, 1)


def test_children_rejects_a_derivative_in_the_here_context() raises:
    # Test the private context boundary directly as well as graph compilation:
    # the ordinary canonicalizer folds this context for derivative nodes.
    var graph = nodes.NodeGraph()
    var uv = graph.uv()
    var derivative = graph.dfdy(uv)
    var zero = graph.float(0)
    var varies = List[Bool](length=graph.count(), fill=True)
    var bent = List[Bool](length=graph.count(), fill=False)
    with assert_raises(contains="A derivative cannot read another"):
        _ = nodes._children(
            graph,
            derivative.value,
            nodes.AT_HERE.value,
            varies,
            bent,
            zero.value,
        )


def test_shadow_wireframes_are_rejected_before_shadow_features() raises:
    from materials.material import SHADOW

    with assert_raises(contains="Only a basic material can be a wireframe"):
        _ = Material(Color(0, 0, 0), kind=SHADOW, wireframe=True)


def test_opacity_rejects_both_outside_bounds() raises:
    for bad in [Float32(-0.25), Float32(1.25)]:
        with assert_raises(contains="Opacity must be between zero and one"):
            _ = Material(Color(0, 0, 0), opacity=bad)
    for boundary in [Float32(0), Float32(1)]:
        var material = Material(Color(0, 0, 0), opacity=boundary)
        assert_equal(material.opacity, boundary)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
