# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.glsl`: GLSL source compiled to a node program.

Each test compiles a pair of shaders and runs the program on a made-up
triangle, `Corners`, whose attributes are worked out by hand. The GLSL
answers follow the GLSL ES 3.0 specification; each refusal is checked by
its message, which names the shader and the line.
"""

from materials.glsl import (
    _Type,
    _TokenKind,
    compile_raw_shader_material,
    compile_shader_material,
    shader_graph,
)
from materials.nodes import (
    AT_RIGHT,
    AT_UP,
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    DEPTH_NODE,
    MASK_NODE,
    OPACITY_NODE,
    POSITION_NODE,
    NodeContext,
    NodeInputs,
    NodeProgram,
    NodeSource,
    here_inputs,
    moved_position,
    run_nodes,
)
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.vector4 import Vector4
from render.framebuffer import FloatColor
from render.texture_store import NO_TEXTURE, TextureId
from std.math import cos, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime Lanes = SIMD[DType.float32, 4]

comptime VERTEX = """
void main() {
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
"""


struct Corners(NodeSource):
    """A made-up triangle. The fragment weighs its corners one half, one
    quarter and one quarter, the pixel to the right one quarter, one half,
    one quarter, and the pixel above one quarter, one quarter, one half.

    The corners' coordinates are (0, 0), (1, 0) and (0, 1), their world
    positions (0, 0, 0), (4, 0, 0) and (0, 4, 0), their normals +z, +y and
    +x, and their colors red, green and blue. So the fragment's
    coordinates are (0.25, 0.25) and its position (1, 1, 0).
    """

    var code: List[Float32]

    def __init__(out self, program: NodeProgram):
        """Copy a program's floats."""
        self.code = program.code.copy()

    def word(self, at: Int) -> Float32:
        """Return one float."""
        return self.code[at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return the coordinate and the slot as a color."""
        return FloatColor(u, v, Float32(slot), 0.5)

    def shares(self, context: NodeContext) -> Lanes:
        """Return the made-up weights."""
        if context == AT_RIGHT:
            return Lanes(0.25, 0.5, 0.25, 0)
        if context == AT_UP:
            return Lanes(0.25, 0.25, 0.5, 0)
        return Lanes(0.5, 0.25, 0.25, 0)

    def frag_coord(self, context: NodeContext) -> Lanes:
        """Return a made-up place: the pixel (10, 20) from the bottom
        left, at a depth of 0.75, and its neighbors a pixel over."""
        if context == AT_RIGHT:
            return Lanes(11.5, 20.5, 0.75, 1)
        if context == AT_UP:
            return Lanes(10.5, 21.5, 0.75, 1)
        return Lanes(10.5, 20.5, 0.75, 1)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return the made-up corners."""
        var none = Vector3(0, 0, 0)
        if context == CORNER_A:
            return NodeInputs(
                0, 0, none, Vector3(0, 0, 1), Vector3(1, 0, 0), none, False
            )
        if context == CORNER_B:
            return NodeInputs(
                1,
                0,
                Vector3(4, 0, 0),
                Vector3(0, 1, 0),
                Vector3(0, 1, 0),
                none,
                False,
            )
        return NodeInputs(
            0,
            1,
            Vector3(0, 4, 0),
            Vector3(1, 0, 0),
            Vector3(0, 0, 1),
            none,
            False,
        )


def run(
    program: NodeProgram, output: type_of(COLOR_NODE) = COLOR_NODE
) -> Lanes:
    """Return one output of a program on `Corners`, textures read."""
    var source = Corners(program)
    return run_nodes(source, output, here_inputs(source, True))


def paint(
    fragment: String, vertex: String = VERTEX, raw: Bool = False
) raises -> Lanes:
    """Return the color two shaders paint on `Corners`."""
    if raw:
        return run(compile_raw_shader_material(vertex, fragment))
    return run(compile_shader_material(vertex, fragment))


def value(expression: String, before: String = "") raises -> Lanes:
    """Return a `vec3` expression's value in a fragment shader's `main`."""
    return paint(
        before
        + "\nvoid main() {\n    gl_FragColor = vec4("
        + expression
        + ", 1.0);\n}\n"
    )


def number(expression: String, before: String = "") raises -> Float32:
    """Return a `float` expression's value in a fragment shader's `main`."""
    return value("vec3(" + expression + ")", before)[0]


def refused(
    fragment: String, why: String, vertex: String = VERTEX, raw: Bool = False
) raises:
    """Assert that two shaders are refused with a message."""
    with assert_raises(contains=why):
        _ = paint(fragment, vertex, raw)


def refused_statement(body: String, why: String) raises:
    """Assert that a statement in a fragment shader's `main` is refused."""
    refused(
        "void main() {\n" + body + "\n    gl_FragColor = vec4(1.0);\n}\n", why
    )


def assert_lanes(got: Lanes, x: Float32, y: Float32, z: Float32) raises:
    """Assert the first three lanes."""
    assert_almost_equal(got[0], x, atol=1e-5)
    assert_almost_equal(got[1], y, atol=1e-5)
    assert_almost_equal(got[2], z, atol=1e-5)


# --- the kinds ----------------------------------------------------------------


def test_the_private_kinds_say_which_values_they_hold() raises:
    assert_true(_TokenKind(0).is_valid())
    assert_true(_TokenKind(4).is_valid())
    assert_false(_TokenKind(5).is_valid())
    assert_false(_TokenKind(-1).is_valid())
    assert_true(_Type(0).is_valid())
    assert_true(_Type(6).is_valid())
    assert_true(_Type(9).is_valid())
    assert_true(_Type(16).is_valid())
    assert_true(_Type(32).is_valid())
    assert_false(_Type(7).is_valid())
    assert_false(_Type(-1).is_valid())


# --- a shader material --------------------------------------------------------


def test_a_shader_material_paints_its_color_and_alpha() raises:
    var program = compile_shader_material(
        VERTEX,
        "void main() { gl_FragColor = vec4(1.0, 0.5, 0.25, 0.75); }",
    )
    assert_lanes(run(program), 1, 0.5, 0.25)
    assert_almost_equal(run(program, OPACITY_NODE)[0], 0.75)
    # A vertex that stays where it is sets no position node.
    assert_false(program.has(POSITION_NODE))
    assert_false(program.has(DEPTH_NODE))
    # The graph can be had before it is compiled.
    var graph = shader_graph(
        VERTEX, "void main() { pc_fragColor = vec4(1.0); }"
    )
    assert_true(graph.output(COLOR_NODE).value >= 0)


def test_the_lexer_reads_comments_numbers_and_marks() raises:
    var fragment = String(
        "// a line comment\n"
        "/* a comment\n over two lines */\n"
        "\tvoid main() {\r\n"
        "    float a = 0x1F == 31 ? 1.0 : 0.0;\n"
        "    float b = 1.5e1 + .5 + 2. + 1e1 + 2E+1 + 1.0f + 3.0F;\n"
        "    float c = 25e-1;\n"
        "    gl_FragColor = vec4(a, b, c, 1.0);\n"
        "} // the end, no line after"
    )
    assert_lanes(paint(fragment), 1, 51.5, 2.5)


def test_the_lexer_refuses_what_is_outside_the_subset() raises:
    refused(
        "void main() { @ }", "line 1: the character @ is outside the subset"
    )
    refused(
        "void main() {}\n/* never closed", "line 2: a comment is never closed"
    )
    refused("void main() { 0x; }", "a hexadecimal number needs digits")
    refused("void main() { 1e+; }", "an exponent needs digits")
    refused("void main() { 1u; }", "unsigned integers are outside the subset")
    refused("void main() { 1U; }", "unsigned integers are outside the subset")
    refused("void main() { 1a; }", "a letter cannot follow a number")
    refused("void main() { 2f; }", "a letter cannot follow a number")
    refused("void main() { 2.0fx; }", "a letter cannot follow a number")
    refused("void main() { 2.0e1x; }", "a letter cannot follow a number")
    refused("void main() { 0x1g; }", "a letter cannot follow a number")
    refused("void main() { a # b }", "a # must begin its line")


def test_a_fragment_reads_where_it_is() raises:
    # `gl_FragCoord`: the made-up pixel's center, its depth and one.
    var here = value("gl_FragCoord.xyz")
    assert_equal(here[0], 10.5)
    assert_equal(here[1], 20.5)
    assert_equal(here[2], 0.75)
    assert_equal(value("vec3(gl_FragCoord.w)")[0], 1)
    # One pixel to the next, as the neighbors are.
    var step = value(
        "vec3(dFdx(gl_FragCoord.x), dFdy(gl_FragCoord.y), dFdx(gl_FragCoord.y))"
    )
    assert_equal(step[0], 1)
    assert_equal(step[1], 1)
    assert_equal(step[2], 0)
    # A vertex shader has no fragment.
    with assert_raises():
        _ = paint(
            "void main() { gl_FragColor = vec4(1.0); }",
            "void main() { gl_Position = gl_FragCoord; }",
        )


def test_a_define_stands_for_its_tokens() raises:
    var fragment = String(
        "#define HALF 0.5\n"
        "#define TWICE_HALF (HALF * 2.0) // a comment\n"
        "#define NOTHING\n"
        "#  define   SPACED 3.0\n"
        "#\n"
        "#define END 1e2\n"
        "#define HEX 0x10\n"
        "void main() {\n"
        "    float n = float(HEX) NOTHING;\n"
        "    gl_FragColor = vec4(HALF, TWICE_HALF, SPACED + END + n, 1.0);\n"
        "}\n"
    )
    assert_lanes(paint(fragment), 0.5, 1, 119)
    refused("#define\nvoid main() {}", "a #define needs a name")
    refused("#define", "a #define needs a name")
    refused("#define F(x) x\nvoid main() {}", "with arguments is outside")
    refused("#define A 1\n#define A 2\nvoid main() {}", "A is defined twice")
    refused("#define E 1e", "an exponent needs digits")
    refused("#define E 1e-", "an exponent needs digits")
    refused("#define D 3.", "the shader has no main")
    refused("#define N 3", "the shader has no main")
    refused("#define X 0xAb", "the shader has no main")


def test_every_other_directive_is_refused() raises:
    refused(
        "#include <common>\nvoid main() {}",
        (
            "#include reads three.js's shader chunks, and this port's materials"
            " are not made of chunks"
        ),
    )
    refused("#ifdef USE_MAP\n#endif\nvoid main() {}", "#ifdef is outside")
    refused(
        "#version 300 es\nvoid main() {}", "writes a ShaderMaterial's #version"
    )
    refused("void main() {}\n#pragma", "#pragma is outside")


# --- a raw shader material ----------------------------------------------------


comptime RAW_VERTEX = """#version 300 es
precision highp float;
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec3 color;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat3 normalMatrix;
uniform mat4 modelMatrix;
uniform mat4 viewMatrix;
uniform vec3 cameraPosition;
out vec2 vUv;
out vec3 vColor;
void main() {
    vUv = uv;
    vColor = color + cameraPosition * 0.0 + normalMatrix * normal * 0.0;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
"""


def test_a_raw_shader_declares_what_it_reads() raises:
    var fragment = String(
        "#version 300 es\n"
        "precision mediump float;\n"
        "uniform mat4 viewMatrix;\n"
        "uniform vec3 cameraPosition;\n"
        "in vec2 vUv;\n"
        "in vec3 vColor;\n"
        "layout(location = 0) out vec4 color;\n"
        "uniform sampler2D map;\n"
        "void main() {\n"
        "    vec4 t = texture(map, vUv);\n"
        "    color = vec4(vColor + vec3(vUv, t.z) * 0.0, 1.0);\n"
        "}\n"
    )
    # The color is the corners' red, green and blue mixed.
    assert_lanes(paint(fragment, RAW_VERTEX, True), 0.5, 0.25, 0.25)
    # A GLSL ES 1.0 raw shader writes attribute, varying and gl_FragColor.
    var old = compile_raw_shader_material(
        """#version 100
        attribute vec3 position;
        uniform mat4 projectionMatrix;
        uniform mat4 viewMatrix;
        uniform mat4 modelMatrix;
        varying vec2 vUv;
        void main() {
            vUv = vec2(0.5);
            gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
        }
        """,
        """
        precision mediump float;
        varying vec2 vUv;
        uniform sampler2D map;
        void main() {
            gl_FragColor = texture2D(map, vUv);
        }
        """,
    )
    old.set_texture("map", TextureId(3))
    assert_lanes(run(old), 0.5, 0.5, 3)


def test_a_raw_shader_keeps_to_its_version_and_its_built_ins() raises:
    var modern = String("#version 300 es\nprecision highp float;\n")
    var fragment = modern + "out vec4 c;\nvoid main() { c = vec4(1.0); }"
    refused(
        fragment,
        "attribute is GLSL ES 1.0: #version 300 es writes in and out",
        modern + "attribute vec3 position;\nvoid main() {}",
        True,
    )
    refused(
        "void main() {}",
        "in is GLSL ES 3.0: write #version 300 es first",
        "in vec3 position;\nvoid main() {}",
        True,
    )
    refused(
        "#version 100\n#version 300 es\nvoid main() {}",
        "#version must be the shader's first line",
        RAW_VERTEX,
        True,
    )
    refused(
        "void main() {}\n#version 300 es\n",
        "#version must be the shader's first line",
        RAW_VERTEX,
        True,
    )
    refused(
        "#version 200\nvoid main() {}",
        "the version is #version 300 es or #version 100",
        RAW_VERTEX,
        True,
    )
    refused(
        modern
        + "uniform sampler2D m;\nout vec4 c;\n"
        + "void main() { c = texture2D(m, vec2(0.0)); }",
        "texture2D() is not in this shader's GLSL version",
        RAW_VERTEX,
        True,
    )
    refused(
        (
            "uniform sampler2D m;\nvoid main() { gl_FragColor = texture(m,"
            " vec2(0.0)); }"
        ),
        "texture() is not in this shader's GLSL version",
        "attribute vec3 position;\nuniform mat4 projectionMatrix;\n"
        + "uniform mat4 modelViewMatrix;\n"
        + "void main() { gl_Position = projectionMatrix * modelViewMatrix *"
        " vec4(position, 1.0); }",
        True,
    )
    refused(
        modern + "void main() { gl_FragColor = vec4(1.0); }",
        "GLSL's gl_FragColor is outside the subset",
        RAW_VERTEX,
        True,
    )
    refused(
        "void main() { gl_FragDepth = 0.5; gl_FragColor = vec4(1.0); }",
        "GLSL's gl_FragDepth is outside the subset",
        "attribute vec3 position;\nuniform mat4 projectionMatrix;\n"
        + "uniform mat4 modelViewMatrix;\n"
        + "void main() { gl_Position = projectionMatrix * modelViewMatrix *"
        " vec4(position, 1.0); }",
        True,
    )
    # The built-ins take three.js's types and belong in their shaders.
    refused(
        fragment,
        "three.js's modelViewMatrix is a mat4",
        modern + "uniform mat3 modelViewMatrix;\nvoid main() {}",
        True,
    )
    refused(
        fragment,
        "three.js's cameraPosition is a vec3",
        modern + "uniform vec4 cameraPosition;\nvoid main() {}",
        True,
    )
    refused(
        fragment,
        "three.js's normalMatrix is a mat3",
        modern + "uniform mat4 normalMatrix;\nvoid main() {}",
        True,
    )
    refused(
        modern + "uniform mat4 modelMatrix;\nout vec4 c;\nvoid main() {}",
        "a fragment shader has no modelMatrix in this port",
        RAW_VERTEX,
        True,
    )
    refused(
        fragment,
        "the attribute tangent is not one this port has",
        modern + "in vec4 tangent;\nvoid main() {}",
        True,
    )
    refused(
        fragment,
        "the attribute uv is a vec2",
        modern + "in vec3 uv;\nvoid main() {}",
        True,
    )
    refused(
        fragment,
        "the attribute color is a vec3",
        modern + "in vec4 color;\nvoid main() {}",
        True,
    )
    refused(
        modern + "in vec3 position;\nout vec4 c;\nvoid main() {}",
        "the vertex shader declares no varying position",
        RAW_VERTEX,
        True,
    )
    refused(
        "attribute vec3 position;\nvoid main() {}",
        "a fragment shader has no attributes",
    )
    refused(
        modern + "out vec3 c;\nvoid main() {}",
        "a fragment output is a vec4",
        RAW_VERTEX,
        True,
    )
    refused(
        modern + "out vec4 c;\nout vec4 d;\nvoid main() {}",
        "a fragment shader has one out vec4 in this port",
        RAW_VERTEX,
        True,
    )


# --- the vertex shader --------------------------------------------------------


comptime WHITE = "void main() { gl_FragColor = vec4(1.0); }"


def placed(vertex: String) raises -> Vector3:
    """Return where a vertex shader moves the vertex at (1, 2, 3) with the
    normal +y."""
    var program = compile_shader_material(vertex, WHITE)
    if not program.has(POSITION_NODE):
        return Vector3(1, 2, 3)
    return moved_position(program, Vector3(1, 2, 3), Vector3(0, 1, 0))


def test_the_vertex_shader_places_the_vertex() raises:
    # Lifted along the normal by a uniform, as three.js's displacement.
    var lifted = compile_shader_material(
        """
        uniform float lift;
        vec3 raise(vec3 p) { return p + normal * lift; }
        void main() {
            vec3 moved = raise(position);
            vec4 mvPosition = modelViewMatrix * vec4(moved, 1.0);
            gl_Position = projectionMatrix * mvPosition;
        }
        """,
        WHITE,
    )
    lifted.set_uniform("lift", Float32(2))
    var moved = moved_position(lifted, Vector3(1, 2, 3), Vector3(0, 1, 0))
    assert_equal(moved.y, 4)
    # The same through the view and the model matrices, and through a
    # function that returns the clip-space point.
    var through = placed(
        """
        vec4 clip(vec3 p) {
            return projectionMatrix * viewMatrix * modelMatrix * vec4(p, 1.0);
        }
        void main() { gl_Position = clip(position * 2.0); }
        """
    )
    assert_equal(through.z, 6)
    var chained = placed(
        """
        void main() {
            vec4 world = modelMatrix * vec4(position + vec3(1.0), 1.0);
            vec4 view = viewMatrix * world;
            vec4 clip;
            clip = projectionMatrix * view;
            gl_Position = clip;
        }
        """
    )
    assert_equal(chained.x, 2)
    var composed = placed(
        """
        void main() {
            gl_Position = (projectionMatrix * modelViewMatrix) * vec4(position, 1.0);
        }
        """
    )
    assert_equal(composed.x, 1)


def test_the_vertex_shader_writes_gl_position_as_the_host_places_it() raises:
    refused(WHITE, "main never writes gl_Position", "void main() {}")
    var clip = String(
        "projectionMatrix * modelViewMatrix * vec4(position, 1.0)"
    )
    refused(
        WHITE,
        "gl_Position is written once",
        "void main() { gl_Position = "
        + clip
        + "; gl_Position = "
        + clip
        + "; }",
    )
    refused(
        WHITE,
        "gl_Position is written in main, outside every branch and loop",
        "void main() { if (true) { gl_Position = " + clip + "; } }",
    )
    refused(
        WHITE,
        "gl_Position is written in main, outside every branch and loop",
        "void place() { gl_Position = "
        + clip
        + "; }\nvoid main() { place(); }",
    )
    refused(
        WHITE,
        "gl_Position is written whole",
        "void main() { gl_Position.x = 1.0; }",
    )
    refused(
        WHITE,
        "this port draws gl_Position = projectionMatrix * modelViewMatrix",
        "void main() { gl_Position = vec4(position, 1.0); }",
    )
    refused(
        WHITE,
        "those two transforms do not follow one another",
        (
            "void main() { gl_Position = modelMatrix * projectionMatrix *"
            " vec4(position, 1.0); }"
        ),
    )
    refused(
        WHITE,
        "this port knows the transforms only as",
        "void main() { gl_Position = projectionMatrix * vec4(position, 1.0); }",
    )
    refused(
        WHITE,
        "this port knows the transforms only as",
        "void main() { vec3 n = modelMatrix * normal; }",
    )
    refused(
        WHITE,
        "this port knows the transforms only as",
        "void main() { vec4 n = modelMatrix * vec4(position, 0.0); }",
    )
    refused(
        WHITE,
        "this port knows the transforms only as",
        "void main() { vec3 n = normalMatrix * position; }",
    )
    refused(
        WHITE,
        "this port knows modelMatrix, modelViewMatrix, normalMatrix",
        "void main() { vec4 p = (" + clip + ") + vec4(1.0); }",
    )
    refused(
        WHITE,
        "this port knows modelMatrix, modelViewMatrix, normalMatrix",
        "void main() { true ? modelMatrix : modelMatrix; }",
    )
    refused(
        WHITE,
        "this port knows modelMatrix, modelViewMatrix, normalMatrix",
        "void main() { float x = (" + clip + ").x; }",
    )
    refused(
        WHITE,
        "the world and view position only of the point gl_Position draws",
        """
        varying vec3 vWorld;
        void main() {
            vWorld = (modelMatrix * vec4(position * 2.0, 1.0)).xyz;
            gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
        """,
    )
    # A point the host cannot place from the local position alone.
    refused(
        WHITE,
        "A position node runs once per vertex",
        "void main() { gl_Position = projectionMatrix * modelViewMatrix"
        + " * vec4(vec3(uv, 0.0), 1.0); }",
    )
    refused(
        WHITE,
        "a vertex shader reads no texture in this port",
        "uniform sampler2D m;\nvoid main() { vec4 t = texture(m, uv); }",
    )
    refused(
        WHITE,
        "dFdx() is a fragment shader's",
        "void main() { float d = dFdx(1.0); }",
    )
    refused(
        WHITE, "only a fragment shader can discard", "void main() { discard; }"
    )


def test_a_varying_carries_what_a_corner_keeps() raises:
    var vertex = String(
        """
        varying vec2 vUv;
        varying vec3 vWorld;
        varying vec3 vNormal;
        varying vec4 vWorldNormal;
        varying vec3 vView;
        out float vSeen;
        varying vec3 vColor;
        void main() {
            vUv = uv;
            vec4 world = modelMatrix * vec4(position, 1.0);
            vWorld = world.xyz;
            vNormal = normalize(normalMatrix * normal);
            vWorldNormal = modelMatrix * vec4(normal, 0.0);
            vView = (viewMatrix * world).xyz;
            vSeen = distance(cameraPosition, vWorld);
            vColor = color;
            gl_Position = projectionMatrix * viewMatrix * world;
        }
        """
    )
    # The corners' world positions weighed: (1, 1, 0).
    assert_lanes(
        paint(
            (
                "varying vec3 vWorld;\nvoid main() { gl_FragColor ="
                " vec4(vWorld, 1.0); }"
            ),
            vertex,
        ),
        1,
        1,
        0,
    )
    assert_lanes(
        paint(
            "in vec2 vUv;\nvoid main() { gl_FragColor = vec4(vUv, 0.0, 1.0); }",
            vertex,
        ),
        0.25,
        0.25,
        0,
    )
    # The corners' unit normals weighed, under an identity view.
    assert_lanes(
        paint(
            (
                "varying vec3 vNormal;\nvoid main() { gl_FragColor ="
                " vec4(vNormal, 1.0); }"
            ),
            vertex,
        ),
        0.25,
        0.25,
        0.5,
    )
    assert_lanes(
        paint(
            (
                "varying vec4 vWorldNormal;\nvoid main() { gl_FragColor ="
                " vWorldNormal; }"
            ),
            vertex,
        ),
        0.25,
        0.25,
        0.5,
    )
    assert_lanes(
        paint(
            (
                "varying vec3 vView;\nvoid main() { gl_FragColor = vec4(vView,"
                " 1.0); }"
            ),
            vertex,
        ),
        1,
        1,
        0,
    )
    # Each corner's distance from the camera at the origin: 0, 4 and 4.
    assert_almost_equal(
        paint(
            "varying float vSeen;\nvoid main() { gl_FragColor = vec4(vSeen); }",
            vertex,
        )[0],
        2,
    )
    assert_lanes(
        paint(
            (
                "varying vec3 vColor;\nvoid main() { gl_FragColor ="
                " vec4(vColor, 1.0); }"
            ),
            vertex,
        ),
        0.5,
        0.25,
        0.25,
    )
    # A varying the vertex shader never writes holds zero.
    assert_lanes(
        paint(
            (
                "varying vec3 vLate;\nvoid main() { gl_FragColor = vec4(vLate,"
                " 1.0); }"
            ),
            "varying vec3 vLate;\n" + VERTEX,
        ),
        0,
        0,
        0,
    )
    refused(
        "varying vec3 vUv;\nvoid main() { gl_FragColor = vec4(1.0); }",
        "the varying vUv is a vec2 in the vertex shader",
        vertex,
    )
    refused(
        "varying vec3 vMissing;\nvoid main() { gl_FragColor = vec4(1.0); }",
        "the vertex shader declares no varying vMissing",
    )
    refused(
        WHITE,
        "the varying vLocal reads position or normal",
        "varying vec3 vLocal;\nvoid main() { vLocal = position;\n"
        + "gl_Position = projectionMatrix * modelViewMatrix * vec4(position,"
        " 1.0); }",
    )
    refused(
        WHITE,
        "a varying of type bool is outside the subset",
        "varying bool vFlag;\n" + VERTEX,
    )
    refused(
        "void main() { vUv = vec2(1.0); gl_FragColor = vec4(1.0); }",
        "the name vUv is not declared",
    )
    refused(
        (
            "varying vec2 vUv;\nvoid main() { vUv = vec2(1.0); gl_FragColor ="
            " vec4(1.0); }"
        ),
        "cannot assign vUv: it is a varying the vertex shader wrote",
        "varying vec2 vUv;\n" + VERTEX,
    )


# --- uniforms -----------------------------------------------------------------


def test_uniforms_are_shared_and_set_by_name() raises:
    var program = compile_shader_material(
        "uniform float scale;\n" + VERTEX,
        """
        uniform float scale;
        uniform vec2 shift;
        uniform vec3 tint;
        uniform vec4 glow;
        uniform mat3 turn;
        uniform mat4 place;
        void main() {
            vec3 turned = turn * vec3(1.0, 0.0, 0.0);
            vec4 moved = place * vec4(0.0, 0.0, 0.0, 1.0);
            vec3 sum = tint * scale + vec3(shift, glow.w) + turned + moved.xyz;
            gl_FragColor = vec4(sum, 1.0);
        }
        """,
    )
    # Every uniform starts at zero.
    assert_lanes(run(program), 0, 0, 0)
    program.set_uniform("scale", Float32(2))
    program.set_uniform("shift", Vector2(1, 2))
    program.set_uniform("tint", Vector3(1, 1, 1))
    program.set_uniform("glow", Vector4(0, 0, 0, 3))
    program.set_uniform("turn", Matrix3())
    program.set_uniform("place", Matrix4())
    assert_lanes(run(program), 4, 4, 5)
    refused(
        "uniform vec3 scale;\n" + WHITE,
        "the uniform scale is a float in the other shader",
        "uniform float scale;\n" + VERTEX,
    )
    refused("uniform int count;\n" + WHITE, "a uniform of type int is outside")
    refused("uniform bool on;\n" + WHITE, "a uniform of type bool is outside")
    refused("uniform float many[4];\n" + WHITE, "arrays are outside the subset")
    refused(
        "uniform samplerCube sky;\n" + WHITE, "the type samplerCube is outside"
    )
    refused(
        "uniform mat4 modelMatrix;\n" + WHITE,
        "a fragment shader has no modelMatrix in this port",
    )
    refused(
        "uniform mat4 viewMatrix;\n" + WHITE,
        "the name viewMatrix is declared already",
    )
    refused(
        WHITE,
        "the name modelMatrix is declared already",
        "uniform mat4 modelMatrix;\n" + VERTEX,
    )


# --- expressions --------------------------------------------------------------


def test_the_operators_follow_glsl_es() raises:
    assert_lanes(
        value("vec3(1.0 + 2.0, 5.0 - 7.0, 2.0 * 3.0 / 4.0)"), 3, -2, 1.5
    )
    # An int division drops the fraction toward zero, and % is a
    # remainder of the same sign.
    assert_lanes(
        value("vec3(float(7 / 2), float(-7 / 2), float(-7 % 3))"), 3, -3, -1
    )
    assert_lanes(value("vec3(-1.0, +2.0, - -3.0)"), -1, 2, 3)
    assert_lanes(value("vec3(2.0) * 0.5 + 1.0"), 2, 2, 2)
    assert_lanes(value("1.0 - vec3(1.0, 2.0, 3.0)"), 0, -1, -2)
    assert_lanes(value("vec3(1.0, 2.0, 3.0) / vec3(2.0)"), 0.5, 1, 1.5)
    assert_lanes(
        value(
            "vec3(1.0 < 2.0 ? 1.0 : 0.0, 2 <= 1 ? 1.0 : 0.0,"
            + " 3.0 > 2.0 && 2 >= 2 ? 1.0 : 0.0)"
        ),
        1,
        0,
        1,
    )
    assert_lanes(
        value(
            "vec3(vec2(1.0) == vec2(1.0) ? 1.0 : 0.0,"
            + " vec3(1.0) != vec3(1.0, 1.0, 2.0) ? 1.0 : 0.0,"
            + " 1 == 2 || !(true ^^ false) ? 1.0 : 0.0)"
        ),
        1,
        1,
        0,
    )
    assert_almost_equal(number("true && false || true ? 2.0 : 3.0"), 2)
    assert_almost_equal(number("false ^^ false ? 2.0 : 3.0"), 3)
    # * binds tighter than +, and a parenthesis tighter than both.
    assert_almost_equal(number("1.0 + 2.0 * 3.0 - (1.0 + 1.0) * 2.0"), 3)


def test_the_types_must_meet_as_glsl_es_requires() raises:
    refused_statement("float x = 1.0 + 1;", "cannot use + on a float and a int")
    refused_statement("float x = 1;", "cannot give a float a int")
    refused_statement(
        "vec3 x = vec3(1.0) + vec2(1.0);", "cannot use + on a vec3 and a vec2"
    )
    refused_statement(
        "float x = 1.0 % 2.0;", "% takes two ints: write mod() for floats"
    )
    refused_statement("int x = 1 % 2.0;", "% takes two ints")
    refused_statement(
        "bool b = true + false;", "cannot use + on a bool and a bool"
    )
    refused_statement(
        "bool b = vec2(1.0) < vec2(2.0);", "cannot compare a vec2 and a vec2"
    )
    refused_statement("bool b = 1.0 < 2;", "cannot compare a float and a int")
    refused_statement("bool b = 1.0 == 1;", "cannot compare a float and a int")
    refused_statement("bool b = !1.0;", "! takes a bool, not a float")
    refused_statement("float x = -true;", "cannot use - on a bool")
    refused_statement("float x = +true;", "cannot use + on a bool")
    refused_statement("bool b = 1.0 && true;", "&& joins two bools")
    refused_statement("bool b = true || 1;", "|| joins two bools")
    refused_statement(
        "float x = 1.0 ? 1.0 : 0.0;", "a ?: needs a bool, not a float"
    )
    refused_statement(
        "float x = true ? 1.0 : 1;",
        "a ?: chooses between one type, not a float and a int",
    )
    refused_statement(
        "int x = 1 | 2;", "the bit operator | is outside the subset"
    )
    refused_statement(
        "int x = 1 & 2;", "the bit operator & is outside the subset"
    )
    refused_statement(
        "int x = 1 ^ 2;", "the bit operator ^ is outside the subset"
    )
    refused_statement(
        "int x = 1 << 2;", "the bit operator << is outside the subset"
    )
    refused_statement(
        "int x = 4 >> 1;", "the bit operator >> is outside the subset"
    )
    refused_statement("int x = ~1;", "the bit operator ~ is outside the subset")
    refused_statement(
        "int x = 1 < 2 | 3;", "the bit operator | is outside the subset"
    )
    refused_statement("float x = ;", "expected a value before ';'")
    refused_statement("float x = (1.0;", "expected ) before ';'")


def test_a_swizzle_or_an_index_picks_components() raises:
    assert_lanes(value("vec4(1.0, 2.0, 3.0, 4.0).wzy"), 4, 3, 2)
    assert_lanes(value("vec4(1.0, 2.0, 3.0, 4.0).abg"), 4, 3, 2)
    assert_lanes(value("vec3(vec4(1.0, 2.0, 3.0, 4.0).qpt)"), 4, 3, 2)
    assert_lanes(
        value("vec3(vec3(5.0, 6.0, 7.0)[2], vec2(8.0, 9.0)[1], 0.0)"), 7, 9, 0
    )
    var written = String(
        """
        void main() {
            vec4 v = vec4(0.0);
            v.xz = vec2(1.0, 2.0);
            v.y = 3.0;
            v.zx.y = 5.0;
            v.w += 4.0;
            gl_FragColor = v;
        }
        """
    )
    assert_lanes(paint(written), 5, 3, 2)
    refused_statement(
        "vec2 v = vec2(1.0); v.xx = vec2(1.0);", "that cannot be assigned"
    )
    refused_statement(
        "float f = 1.0; float g = f.x;", "only a vector has components to pick"
    )
    refused_statement(
        "vec2 v = vec2(1.0); float g = v.z;", "a vec2 has no component z"
    )
    refused_statement(
        "vec2 v = vec2(1.0); float g = v.q;", "a vec2 has no component q"
    )
    refused_statement(
        "vec2 v = vec2(1.0); float g = v.k;", "a vec2 has no component k"
    )
    refused_statement(
        "vec4 v = vec4(1.0); vec2 g = v.xg;",
        "a swizzle cannot mix xyzw, rgba and stpq",
    )
    refused_statement(
        "vec4 v = vec4(1.0); vec4 g = v.xyzwx;",
        "a swizzle picks one to four components",
    )
    refused_statement(
        "float f = 1.0; float g = f[0];",
        "only a vector can be indexed in this subset",
    )
    refused_statement(
        "vec2 v = vec2(1.0); int i = 0; float g = v[i];",
        "a vector is indexed by a constant int",
    )
    refused_statement(
        "vec2 v = vec2(1.0); float g = v[1.0];",
        "a vector is indexed by a constant int",
    )
    refused_statement(
        "vec2 v = vec2(1.0); float g = v[2];", "the index is outside the vec2"
    )
    refused_statement(
        "vec2 v = vec2(1.0); float g = v[-1];", "the index is outside the vec2"
    )
    refused_statement(
        "vec2 v = vec2(1.0); v[0 == 0 ? 0 : 1] = 1.0;",
        "a vector is indexed by a constant int",
    )


def test_a_constructor_converts_or_lays_components_end_to_end() raises:
    assert_lanes(
        value("vec3(float(3), float(true), float(vec2(4.0, 5.0)))"), 3, 1, 4
    )
    assert_lanes(
        value("vec3(float(int(-2.5)), float(int(false)), float(bool(2.0)))"),
        -2,
        0,
        1,
    )
    assert_lanes(
        value("vec3(float(bool(0)), float(bool(true)), float(int(7)))"), 0, 1, 7
    )
    assert_lanes(value("vec3(vec2(1.0, 2.0), 3)"), 1, 2, 3)
    assert_lanes(value("vec3(vec4(1.0, 2.0, 3.0, 4.0))"), 1, 2, 3)
    assert_lanes(value("vec3(1.0, vec4(2.0, 3.0, 4.0, 5.0))"), 1, 2, 3)
    assert_lanes(value("vec3(2)"), 2, 2, 2)
    # A constant int from a constructor is known, as a for loop needs.
    assert_almost_equal(number("float(int(3.9) + int(true))"), 4)
    refused_statement(
        "vec3 v = vec3(1.0, 2.0, 3.0, 4.0);",
        "a vec3 constructor has too many arguments",
    )
    refused_statement(
        "vec3 v = vec3(1.0, 2.0);", "a vec3 constructor needs 3 components"
    )
    refused_statement("vec3 v = vec3();", "a vec3 constructor needs arguments")
    refused_statement(
        "float f = float(1.0, 2.0);", "a float constructor takes one argument"
    )
    refused_statement(
        "mat3 m = mat3(1.0);", "a local variable of type mat3 is outside"
    )
    refused_statement(
        "vec3 v = mat3(1.0) * vec3(1.0);",
        "a mat3 constructor is outside the subset",
    )
    refused_statement(
        "ivec2 v = ivec2(1);", "the type ivec2 is outside the subset"
    )
    refused_statement(
        "vec2 v = ivec2(1);", "the type ivec2 is outside the subset"
    )
    refused_statement(
        "vec3 v = vec3(viewMatrix);", "cannot make a vec3 of a mat4"
    )


# --- built-in functions -------------------------------------------------------


def test_the_built_in_functions_follow_glsl() raises:
    assert_lanes(
        value("vec3(radians(180.0), degrees(1.0), sin(0.5))"),
        3.1415927,
        57.29578,
        sin(Float32(0.5)),
    )
    assert_lanes(
        value("vec3(cos(0.5), tan(0.0), asin(1.0))"),
        cos(Float32(0.5)),
        0,
        1.5707964,
    )
    assert_lanes(
        value("vec3(acos(1.0), atan(1.0), atan(1.0, -1.0))"),
        0,
        0.7853982,
        2.3561945,
    )
    assert_lanes(value("vec3(pow(2.0, 3.0), exp(0.0), log(1.0))"), 8, 1, 0)
    assert_lanes(value("vec3(exp2(3.0), log2(8.0), sqrt(9.0))"), 8, 3, 3)
    assert_lanes(
        value("vec3(inversesqrt(4.0), abs(-2.0), sign(-3.0))"), 0.5, 2, -1
    )
    assert_lanes(value("vec3(floor(1.5), ceil(1.5), trunc(-1.5))"), 1, 2, -1)
    assert_lanes(
        value("vec3(round(2.5), roundEven(3.5), fract(1.25))"), 2, 4, 0.25
    )
    assert_lanes(
        value("vec3(mod(5.0, 3.0), min(1.0, 2.0), max(1.0, 2.0))"), 2, 1, 2
    )
    assert_lanes(
        value(
            "vec3(clamp(3.0, 0.0, 1.0), mix(0.0, 10.0, 0.25), step(0.5, 0.4))"
        ),
        1,
        2.5,
        0,
    )
    assert_lanes(
        value(
            "vec3(smoothstep(0.0, 1.0, 0.5), length(vec2(3.0, 4.0)),"
            " distance(vec2(0.0), vec2(0.0, 2.0)))"
        ),
        0.5,
        5,
        2,
    )
    assert_lanes(
        value("vec3(dot(vec2(1.0, 2.0), vec2(3.0, 4.0)), 0.0, 0.0)"), 11, 0, 0
    )
    assert_lanes(
        value("cross(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0))"), 0, 0, 1
    )
    assert_lanes(value("normalize(vec3(0.0, 3.0, 4.0))"), 0, 0.6, 0.8)
    assert_lanes(
        value(
            "faceforward(vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0,"
            " 1.0, 0.0))"
        ),
        0,
        -1,
        0,
    )
    assert_lanes(
        value("reflect(vec3(1.0, -1.0, 0.0), vec3(0.0, 1.0, 0.0))"), 1, 1, 0
    )
    assert_lanes(
        value("refract(vec3(0.0, -1.0, 0.0), vec3(0.0, 1.0, 0.0), 1.0)"),
        0,
        -1,
        0,
    )
    # The generic signatures: a float beside a vector where GLSL has one.
    assert_lanes(value("mod(vec3(5.0, 6.0, 7.0), 4.0)"), 1, 2, 3)
    assert_lanes(value("clamp(vec3(-1.0, 0.5, 2.0), 0.0, 1.0)"), 0, 0.5, 1)
    assert_lanes(value("mix(vec3(0.0), vec3(4.0), 0.5)"), 2, 2, 2)
    assert_lanes(value("step(1.0, vec3(0.0, 1.0, 2.0))"), 0, 1, 1)
    assert_lanes(value("smoothstep(0.0, 2.0, vec3(0.0, 1.0, 2.0))"), 0, 0.5, 1)
    # abs, sign, min, max and clamp have int signatures.
    assert_lanes(
        value(
            "vec3(float(abs(-2)), float(min(3, 4) + max(3, 4)), float(clamp(9,"
            " 0, 5) + sign(-4)))"
        ),
        2,
        7,
        4,
    )
    # A texture read at an expression.
    var sampled = compile_shader_material(
        VERTEX,
        """
        uniform sampler2D map;
        void main() { gl_FragColor = texture2D(map, vec2(0.5, 0.75)) + texture(map, vec2(0.0)); }
        """,
    )
    sampled.set_texture("map", TextureId(2))
    assert_lanes(run(sampled), 0.5, 0.75, 4)
    assert_almost_equal(run(sampled, OPACITY_NODE)[0], 1)


def test_derivatives_are_a_fragment_shaders() raises:
    var vertex = String("varying vec2 vUv;\nvoid main() { vUv = uv * 4.0;\n")
    vertex += (
        "gl_Position = projectionMatrix * modelViewMatrix * vec4(position,"
        " 1.0); }"
    )
    var fragment = String(
        "varying vec2 vUv;\nvoid main() { gl_FragColor = vec4(dFdx(vUv),"
        " dFdy(vUv.y), fwidth(vUv.x)); }"
    )
    var program = compile_shader_material(vertex, fragment)
    # Four times the coordinates: a quarter across is one more.
    assert_lanes(run(program), 1, 0, 1)
    assert_almost_equal(run(program, OPACITY_NODE)[0], 1)


def test_a_built_in_takes_only_its_signatures() raises:
    refused_statement(
        "float x = pow(vec3(1.0), 2.0).x;",
        "no signature of pow() takes (vec3, float)",
    )
    refused_statement(
        "vec3 x = mix(vec3(1.0), vec2(1.0), 0.5);",
        "no signature of mix() takes (vec3, vec2, float)",
    )
    refused_statement("float x = sin(1);", "no signature of sin() takes (int)")
    refused_statement(
        "int x = min(1, 2.0);", "no signature of min() takes (int, float)"
    )
    refused_statement(
        "float x = min(1.0, 2);", "no signature of min() takes (float, int)"
    )
    refused_statement(
        "vec3 x = cross(vec2(1.0), vec2(1.0));",
        "no signature of cross() takes (vec2, vec2)",
    )
    refused_statement(
        "float x = step(vec2(1.0), 1.0);",
        "no signature of step() takes (vec2, float)",
    )
    refused_statement("float x = sin();", "no signature of sin() takes ()")
    refused_statement(
        "float x = sinh(1.0);", "GLSL's sinh() is outside the subset"
    )
    refused_statement(
        "float x = lessThan(1.0, 2.0);",
        "GLSL's lessThan() is outside the subset",
    )
    refused_statement(
        "float x = shade(1.0);", "the function shade is not declared"
    )
    refused(
        (
            "uniform sampler2D m;\nvoid main() { gl_FragColor = texture2D(m,"
            " vec3(0.0)); }"
        ),
        "texture2D() takes a sampler2D and a vec2",
    )
    refused(
        "void main() { gl_FragColor = texture2D(vec2(0.0), vec2(0.0)); }",
        "texture2D() takes a sampler2D and a vec2",
    )
    refused(
        "uniform sampler2D m;\nvoid main() { gl_FragColor = texture(m); }",
        "texture() takes a sampler2D and a vec2",
    )


# --- statements ---------------------------------------------------------------


def test_the_statements_build_the_graph() raises:
    var fragment = String(
        """
        const float HALF = 0.5;
        const int COUNT = 3 * 2 - 1;
        void main() {
            float a = 1.0, b, c = HALF;
            int n = COUNT;
            const vec2 pair = vec2(HALF, 2.0);
            highp float d = 0.0;
            ;
            {
                float a = 10.0;
                d = a;
            }
            a += 2.0;
            a -= 0.5;
            a *= 2.0;
            a /= 5.0;
            b++;
            ++b;
            b--;
            --b;
            b++;
            n++;
            if (n > 5) c = 9.0;
            if (a < 1.0) {
                c += 1.0;
            } else if (a > 1.0) {
                c += 2.0;
            } else {
                c += 3.0;
            }
            gl_FragColor = vec4(a + float(n) + pair.y, b, c + d, 1.0);
        }
        """
    )
    # a: (1 + 2 - 0.5) * 2 / 5 = 1; n: 6; c: 9 + 3; d: 10.
    assert_lanes(paint(fragment), 9, 1, 22)
    refused_statement(
        "float a = 1.0; a %= 2.0;", "the operator %= is outside the subset"
    )
    refused_statement(
        "int a = 1; a &= 2;", "the operator &= is outside the subset"
    )
    refused_statement(
        "float a; float b; a = b = 1.0;",
        "an assignment or ++ is a whole statement",
    )
    refused_statement(
        "float a = 1.0; float b = a++;",
        "expected ; before '++'",
    )
    refused_statement(
        "float a = 1.0; float b = ++a;",
        "an assignment or ++ is a whole statement",
    )
    refused_statement(
        "float a; a++ ++;", "an assignment or ++ is a whole statement"
    )
    refused_statement(
        "bool a = true; a++;", "++ and -- change an int or a float"
    )
    refused_statement("1.0 = 2.0;", "that cannot be assigned")
    refused_statement("float a = 1.0; a = 1;", "cannot assign a int to a float")
    refused(
        "uniform float u;\nvoid main() { u = 1.0; gl_FragColor = vec4(1.0); }",
        "cannot assign u: it is a uniform",
    )
    refused(
        WHITE,
        "cannot assign position: it is an attribute",
        "void main() { position = vec3(0.0); }",
    )
    refused(
        WHITE,
        "cannot assign viewMatrix: it is a built-in transform",
        "void main() { viewMatrix = viewMatrix; }",
    )
    refused_statement(
        "const float k = 1.0; k = 2.0;", "cannot assign k: it is a const"
    )
    refused_statement("const float k;", "a const needs a value")
    refused_statement(
        "float u = 1.0; const float k = u;",
        "a const's value must be a constant expression",
    )
    refused_statement("float a[2];", "arrays are outside the subset")
    refused_statement(
        "void v;", "a local variable of type void is outside the subset"
    )
    refused_statement(
        "sampler2D s;", "a local variable of type sampler2D is outside"
    )
    refused_statement(
        "float a = 1.0; float a = 2.0;", "the name a is declared already"
    )
    refused_statement("float if = 1.0;", "the name if is a keyword")
    refused_statement(
        "float gl_Thing = 1.0;", "a name that begins gl_ is GLSL's"
    )
    refused_statement(
        "float x = gl_PointCoord.x;",
        "GLSL's gl_PointCoord is outside the subset",
    )
    refused_statement("float x = y;", "the name y is not declared")
    refused_statement("if (1.0) {}", "an if needs a bool, not a float")
    refused_statement("while (true) {}", "while is outside the subset")
    refused_statement("break;", "break is outside the subset")
    refused_statement("{ float a = 1.0;", "a function's body is never closed")
    refused("void main() { float a = 1.0;", "a function's body is never closed")
    refused_statement("float x = 1.0 float y;", "expected ; before 'float'")
    refused_statement("float 1.0;", "expected a name before '1.0'")
    refused("void main() { gl_FragColor = vec4(1.0) }", "expected ; before '}'")


def test_a_for_loop_with_a_constant_count_is_unrolled() raises:
    var fragment = String(
        """
        void main() {
            float sum = 0.0;
            for (int i = 0; i < 4; i++) { sum += float(i); }
            for (int i = 10; i > 7; --i) sum += 1.0;
            for (int i = 0; i <= 4; i += 2) { sum += 100.0; }
            for (int i = 6; i >= 0; i -= 3) { sum += 1000.0; }
            for (float x = 0.0; x != 1.0; x += 0.25) { sum += x * 10000.0; }
            for (int i = 0; i < 2; ++i) {
                for (int j = 0; j < 2; j--) {
                    if (j < -1) { break_out(); }
                    sum += 100000.0;
                }
            }
            for (int i = 0; i < 0; i++) { sum = -1.0; }
            gl_FragColor = vec4(sum, 0.0, 0.0, 1.0);
        }
        """
    )
    refused(
        fragment.replace("j--", "j++"), "the function break_out is not declared"
    )
    var counted = fragment.replace(
        "if (j < -1) { break_out(); }", "if (j < -1) { j; }"
    )
    # 6 + 3 + 300 + 3000 + 15000 + 400000
    assert_almost_equal(paint(counted.replace("j--", "j++"))[0], 418309)
    refused(counted, "a for loop runs at most 1024 times")
    refused_statement(
        "for (i = 0; i < 2; i++) {}",
        "a for loop begins by declaring its int or float index",
    )
    refused_statement(
        "for (bool i = true; i; i++) {}", "a for loop begins by declaring"
    )
    refused_statement(
        "int n = 2; for (int i = n; i < 2; i++) {}",
        "a for loop's start is a constant int",
    )
    refused_statement(
        "int n = 2; for (int i = 0; i < n; i++) {}",
        "a for loop's bound is a constant int",
    )
    refused_statement(
        "for (int i = 0; 2 > i; i++) {}",
        "a for loop's condition compares its index",
    )
    refused_statement(
        "for (int i = 0; i == 2; i++) {}",
        "a for loop's condition is <, <=, >, >= or !=",
    )
    refused_statement(
        "int j = 0; for (int i = 0; i < 2; j++) {}",
        "a for loop steps its own index",
    )
    refused_statement(
        "int j = 0; for (int i = 0; i < 2; ++j) {}",
        "a for loop steps its own index",
    )
    refused_statement(
        "for (int i = 0; i < 2; i *= 2) {}",
        "a for loop steps its index by ++, --, += or -=",
    )
    refused_statement(
        "for (int i = 0; i < 2; i += 0) {}", "a for loop's step cannot be zero"
    )
    refused_statement(
        "int n = 1; for (int i = 0; i < 2; i += n) {}",
        "a for loop's step is a constant int",
    )
    refused_statement(
        "for (int i = 0; i < 2; i++) { i = 1; }",
        "cannot assign i: it is a for loop's index",
    )
    refused_statement(
        "for (int i = 0; i < 2000; i++) {}",
        "a for loop runs at most 1024 times",
    )


def test_a_discard_throws_the_fragment_away() raises:
    var program = compile_shader_material(
        VERTEX,
        """
        void main() {
            if (1.0 > 2.0) discard;
            gl_FragColor = vec4(1.0);
        }
        """,
    )
    assert_true(program.has(MASK_NODE))
    assert_equal(run(program, MASK_NODE)[0], 1)
    var always = compile_shader_material(
        VERTEX, "void main() { discard; gl_FragColor = vec4(1.0); }"
    )
    assert_equal(run(always, MASK_NODE)[0], 0)


# --- functions ----------------------------------------------------------------


def test_a_function_is_inlined_at_each_call() raises:
    var fragment = String(
        """
        float twice(in float x) { return x * 2.0; }
        float add(const in highp float a, float b) { float s = a + b; s += 0.0; return s; }
        void nothing(void) { }
        void cut(float x) { if (x > 100.0) discard; return; }
        vec3 shade(vec2 uv) {
            float t = twice(uv.x);
            return vec3(t, add(t, 1.0), 0.0);
        }
        void main() {
            nothing();
            cut(1.0);
            float x = 3.0;
            gl_FragColor = vec4(shade(vec2(x)), 1.0);
        }
        """
    )
    assert_lanes(paint(fragment), 6, 7, 0)
    refused(
        (
            "float f(float x) { return f(x); }\nvoid main() { gl_FragColor ="
            " vec4(f(1.0)); }"
        ),
        "a function cannot call itself",
    )
    refused(
        (
            "float f(float x) { if (x > 1.0) { return 1.0; } return 0.0;"
            " }\nvoid main() { f(1.0); }"
        ),
        "a return must be the last statement of its function",
    )
    refused(
        "float f() { return 1.0; float y = 1.0; }\nvoid main() { f(); }",
        "a return must be the last statement of its function",
    )
    refused(
        "float f() { }\nvoid main() { f(); }",
        "the function f ends with no return",
    )
    refused(
        "float f() { return; }\nvoid main() { f(); }",
        "the function f returns a float, not a void",
    )
    refused(
        "void f() { return 1.0; }\nvoid main() { f(); }",
        "the function f returns a void, not a float",
    )
    refused(
        "void f() {}\nvoid main() { float x = f(); }",
        "cannot give a float a void",
    )
    refused(
        "float f(float x);\nvoid main() {}", "prototypes are outside the subset"
    )
    refused(
        "float f(out float x) { return 1.0; }\nvoid main() {}",
        "out and inout parameters are outside",
    )
    refused(
        "float f(inout float x) { return 1.0; }\nvoid main() {}",
        "out and inout parameters are outside",
    )
    refused(
        "float f(sampler2D s) { return 1.0; }\nvoid main() {}",
        "a parameter of type sampler2D is outside",
    )
    refused(
        "float f(float a float b) { return 1.0; }\nvoid main() {}",
        "expected , before 'float'",
    )
    refused(
        "void f() {}\nvoid f() {}\nvoid main() {}",
        "the function f is defined twice",
    )
    refused(
        "float sin(float x) { return x; }\nvoid main() {}",
        "the function sin is GLSL's own",
    )
    refused(
        "float isnan(float x) { return x; }\nvoid main() {}",
        "the function isnan is GLSL's own",
    )
    refused(
        "float out(float x) { return x; }\nvoid main() {}",
        "the name out is a keyword",
    )
    refused(
        "uniform float f() { return 1.0; }\nvoid main() {}",
        "a function has no storage qualifier",
    )
    refused(
        "float f(float x) { return x; }\nvoid main() { f(1.0, 2.0); }",
        "the function f takes 1 arguments",
    )
    refused(
        "float f(float x) { return x; }\nvoid main() { f(1); }",
        "the function f takes a float as argument 1",
    )
    refused(
        "void main() { float x = 1.0; }\nvoid main() {}",
        "the function main is defined twice",
    )
    refused("float main() { return 1.0; }", "main is void main()")
    refused("void main(float x) {}", "main is void main()")
    refused("void helper() {}", "the shader has no main")
    refused(
        (
            "float f(float x) { return y; }\nvoid main() { float y = 1.0;"
            " gl_FragColor = vec4(f(y)); }"
        ),
        "the name y is not declared",
    )
    refused(
        "void f() {\nvoid main() {}",
        "a function's body is never closed",
    )


# --- declarations -------------------------------------------------------------


def test_the_declarations_at_the_top_of_a_shader() raises:
    var fragment = String(
        """
        precision highp float;
        precision mediump sampler2D;
        ;
        const float SCALE = 2.0;
        const vec3 TINT = vec3(1.0, 0.5, 0.25) * SCALE;
        uniform lowp float fade;
        void main() { gl_FragColor = vec4(TINT, fade); }
        """
    )
    assert_lanes(paint(fragment), 2, 1, 0.5)
    refused(
        "precision float;\nvoid main() {}",
        "a precision statement names highp, mediump or lowp",
    )
    refused(
        "flat varying vec3 v;\nvoid main() {}",
        "the qualifier flat is outside the subset",
    )
    refused(
        "invariant gl_Position;\nvoid main() {}",
        "the qualifier invariant is outside",
    )
    refused(
        "float g;\nvoid main() {}", "a global variable is outside the subset"
    )
    refused("const float g;\nvoid main() {}", "expected = before ';'")
    refused(
        "uniform float u;\nconst float g = u;\nvoid main() {}",
        "a const's value must be a constant expression",
    )
    refused(
        "const float g = 1;\nvoid main() {}", "cannot give a const float a int"
    )
    refused(
        "const float g[2];\nvoid main() {}", "arrays are outside the subset"
    )
    refused(
        "struct S { float x; };\nvoid main() {}",
        "the type struct is outside the subset",
    )
    refused("layout(location = 0 out vec4 c;", "a layout is never closed")
    refused("uniform float;\nvoid main() {}", "expected a name before ';'")
    refused("banana x;\nvoid main() {}", "expected a type before 'banana'")
    refused("uniform float in;\nvoid main() {}", "the name in is a keyword")
    refused(
        "const float x = 1.0;\nconst float x = 2.0;\nvoid main() {}",
        "the name x is declared already",
    )


# --- the fragment's outputs ---------------------------------------------------


def test_the_fragment_writes_its_color_and_its_depth() raises:
    var program = compile_shader_material(
        VERTEX,
        """
        void main() {
            pc_fragColor = vec4(0.25);
            gl_FragColor.g = 0.5;
            gl_FragDepth = 0.75;
        }
        """,
    )
    assert_lanes(run(program), 0.25, 0.5, 0.25)
    assert_true(program.has(DEPTH_NODE))
    assert_equal(run(program, DEPTH_NODE)[0], 0.75)
    refused("void main() {}", "main never writes its color")
    refused(
        "void main() { gl_FragDepth = 0.5; }", "main never writes its color"
    )
    refused(
        "out vec4 color;\nvoid main() { color = vec4(1.0); }",
        "three.js declares a ShaderMaterial's out vec4 pc_fragColor itself",
    )
    refused(
        "void main() { gl_FragColor = vec3(1.0); }",
        "cannot assign a vec3 to a vec4",
    )


def test_the_corners_of_the_grammar() raises:
    refused("void main() {}\nfoo", "expected a type before 'foo'")
    refused("uniform float", "expected a name before the end")
    refused("precision highp float", "expected ; before the end")
    refused(
        "const float f() { return 1.0; }\nvoid main() {}",
        "a function has no storage qualifier",
    )
    refused(
        "float f(void x) { return 1.0; }\nvoid main() {}",
        "a parameter of type void is outside",
    )
    refused(
        "float f() { if (true) return 1.0; }\nvoid main() { f(); }",
        "a return must be the last statement of its function",
    )
    refused(
        "const float x = foo(1.0);\nvoid main() {}",
        "the function foo is not declared",
    )
    refused_statement(
        "for (int i = 0.0; i < 2; i++) {}",
        "a for loop's start is a constant int",
    )
    refused_statement(
        "float a; a-- --;", "an assignment or ++ is a whole statement"
    )
    refused_statement(
        "float a; float b = --a;", "an assignment or ++ is a whole statement"
    )
    refused_statement(
        "bool b = viewMatrix == viewMatrix;", "cannot compare a mat4 and a mat4"
    )
    refused(
        WHITE,
        "three.js declares a ShaderMaterial's attributes itself",
        "in vec3 extra;\n" + VERTEX,
    )
    refused(
        WHITE,
        "this port knows modelMatrix, modelViewMatrix, normalMatrix",
        """
        void main() {
            vec4 c;
            if (true) { c = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }
            gl_Position = c;
        }
        """,
    )
    # A raw GLSL ES 1.0 fragment shader that says so.
    assert_lanes(
        paint(
            "#version 100\nvoid main() { gl_FragColor = vec4(0.5); }",
            RAW_VERTEX,
            True,
        ),
        0.5,
        0.5,
        0.5,
    )


def test_a_matrix_uniform_multiplies_a_vector() raises:
    var program = compile_shader_material(
        VERTEX,
        """
        uniform mat3 m;
        void main() {
            vec3 a = m * vec3(1.0, 0.0, 0.0);
            vec3 b = vec3(1.0, 0.0, 0.0) * m;
            vec3 c = (viewMatrix * vec4(1.0, 2.0, 3.0, 1.0)).xyz;
            vec3 d = (vec4(1.0, 2.0, 3.0, 1.0) * viewMatrix).xyz;
            gl_FragColor = vec4(a + b * 10.0 + c * 100.0 + d * 1000.0, 1.0);
        }
        """,
    )
    var turn = Matrix3()
    turn.elements[1] = 2
    turn.elements[3] = 5
    program.set_uniform("m", turn)
    # M e1 is the first column (1, 2, 0); e1 M the first row (1, 5, 0).
    assert_lanes(
        run(program), 1 + 10 + 100 + 1000, 2 + 50 + 200 + 2000, 300 + 3000
    )
    var uniform = String("uniform mat3 m;\n")
    refused(
        uniform + "void main() { vec3 v = m + vec3(1.0); }",
        "cannot use + on a mat3 and a vec3",
    )
    refused(
        uniform + "void main() { vec3 v = m * m; }",
        "cannot use * on a mat3 and a mat3",
    )
    refused(
        uniform + "void main() { vec4 v = m * vec4(1.0); }",
        "cannot multiply a mat3 and a vec4",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
