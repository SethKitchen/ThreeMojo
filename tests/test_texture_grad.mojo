# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Explicit sampler2D gradients: type boundaries, real texels, and Mesa oracles.

The Mesa cases use a 16 by 8 floating-point texture with five authored mip
levels. Each texel is ((level + 1) / 8, x / 16, y / 8, 1). Expected colors
come from independent GLES 3.0 execution and analytic checks, not this sampler.
"""

from materials.glsl import compile_raw_shader_material, compile_shader_material
from materials.nodes import (
    COLOR_NODE,
    FRAGMENT_NODE,
    OPACITY_NODE,
    POSITION_NODE,
    SIZE_NODE,
    NODE_TEXTURE_GRAD,
    NodeGraph,
    NodeRef,
    NodeContext,
    NodeInputs,
    NodeProgram,
    NodeSource,
    run_nodes,
    here_inputs,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.srgb import LINEAR, SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    MIRROR,
    REPEAT,
    NEAREST,
    NEAREST_MIPMAP_NEAREST,
    NEAREST_MIPMAP_LINEAR,
    LINEAR_MIPMAP_LINEAR,
    COVERAGE,
    MAX_ANISOTROPY,
    Filter,
    Wrap,
    Texture,
    float_texture,
    checkerboard,
    anisotropic_footprint,
    gradient_sample_coordinate,
)
from render.texture_store import TextureId
from std.math import inf, nan, isfinite
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests.test_glsl import VERTEX, RAW_VERTEX, Corners, run, refused, value

comptime Lanes = SIMD[DType.float32, 4]


struct TextureSource(NodeSource):
    """A real texture beside the artificial triangle used by the GLSL suite."""

    var code: List[Float32]
    var image: Texture

    def __init__(out self, program: NodeProgram, image: Texture):
        self.code = program.code.copy()
        self.image = Texture(copy=image)

    def word(self, at: Int) -> Float32:
        return self.code[at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        return self.image.sample(u, v)

    def sample_level(
        self, slot: Int, u: Float32, v: Float32, level: Float32
    ) -> FloatColor:
        return self.image.sample_level(u, v, level)

    def sample_grad(
        self, slot: Int, u: Float32, v: Float32, dx: Vector2, dy: Vector2
    ) -> FloatColor:
        return self.image._sample_grad(u, v, dx, dy)

    def fetch(self, slot: Int, x: Int, y: Int, level: Int) -> FloatColor:
        return self.image.fetch(x, y, level)

    def size(self, slot: Int, level: Int) -> Lanes:
        return self.image.fetch_size(level)

    def shares(self, context: NodeContext) -> Lanes:
        return Lanes(1, 0, 0, 0)

    def frag_coord(self, context: NodeContext) -> Lanes:
        return Lanes(0.5, 0.5, 0, 1)

    def corner(self, context: NodeContext) -> NodeInputs:
        var zero = Vector3(0, 0, 0)
        return NodeInputs(0, 0, zero, zero, zero, zero, True)


def assert_color(actual: FloatColor, expected: FloatColor) raises:
    assert_almost_equal(actual.r, expected.r, atol=0.000002)
    assert_almost_equal(actual.g, expected.g, atol=0.000002)
    assert_almost_equal(actual.b, expected.b, atol=0.000002)
    assert_almost_equal(actual.a, expected.a, atol=0.000002)


def authored_mips(filter: Filter, wrap: Wrap) raises -> Texture:
    var data = List[Float32]()
    for y in range(8):
        for x in range(16):
            data.extend(
                [Float32(0.125), Float32(x) / 16, Float32(y) / 8, Float32(1)]
            )
    var image = float_texture(16, 8, data^, wrap, NEAREST, True)
    image.flip_y = False
    image.mag_filter = BILINEAR if filter == LINEAR_MIPMAP_LINEAR else NEAREST
    image.min_filter = filter
    for level in range(5):
        for y in range(image.level_height(level)):
            for x in range(image.level_width(level)):
                var at = (
                    image.offsets[level]
                    + (y * image.level_width(level) + x) * 4
                )
                image.data[at] = Float32(level + 1) / 8
                image.data[at + 1] = Float32(x) / 16
                image.data[at + 2] = Float32(y) / 8
                image.data[at + 3] = 1
    image.validate()
    return image^


def check_mesa_case(
    expression: String,
    uv: Vector2,
    dx: Vector2,
    dy: Vector2,
    filter: Filter,
    wrap: Wrap,
    expected: FloatColor,
) raises:
    var program = compile_raw_shader_material(
        RAW_VERTEX,
        "#version 300 es\nprecision highp float; precision highp"
        " sampler2D;\nuniform sampler2D source; uniform vec2 uv; uniform vec2"
        " dx; uniform vec2 dy;\nout vec4 result; void main() { result = "
        + expression
        + "; }",
    )
    program.set_texture("source", TextureId(0))
    # The constant-argument case does not emit these uniforms.
    if (
        expression
        != "textureGrad(source, vec2(0.34375,0.6875), vec2(0.25,0.0),"
        " vec2(0.0,0.5))"
    ):
        program.set_uniform("uv", uv)
        program.set_uniform("dx", dx)
        program.set_uniform("dy", dy)
    var image = authored_mips(filter, wrap)
    var source = TextureSource(program, image)
    var rgb = run_nodes(source, COLOR_NODE, here_inputs(source, True))
    var alpha = run_nodes(source, OPACITY_NODE, here_inputs(source, True))
    assert_color(FloatColor(rgb[0], rgb[1], rgb[2], alpha[0]), expected)


def test_mesa_textureGrad_mip_0() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.0625, 0.0),
        Vector2(0.0, 0.125),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.125, 0.3125, 0.625, 1.0),
    )


def test_mesa_textureGrad_mip_1() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.125, 0.0),
        Vector2(0.0, 0.25),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.25, 0.125, 0.25, 1.0),
    )


def test_mesa_textureGrad_mip_2() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.25, 0.0),
        Vector2(0.0, 0.5),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.375, 0.0625, 0.125, 1.0),
    )


def test_mesa_textureGrad_mip_3() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.5, 0.0),
        Vector2(0.0, 1.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.5, 0.0, 0.0, 1.0),
    )


def test_mesa_textureGrad_mip_4() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(1.0, 0.0),
        Vector2(0.0, 2.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.625, 0.0, 0.0, 1.0),
    )


def test_mesa_textureGrad_zero() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.0, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.125, 0.3125, 0.625, 1.0),
    )


def test_mesa_textureGrad_magnification() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.015625, 0.0),
        Vector2(0.0, 0.03125),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.125, 0.3125, 0.625, 1.0),
    )


def test_mesa_textureGrad_minification_clamp() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(8.0, 0.0),
        Vector2(0.0, 8.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.625, 0.0, 0.0, 1.0),
    )


def test_mesa_textureGrad_dx_dominates() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.5, 0.0),
        Vector2(0.0, 0.125),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.5, 0.0, 0.0, 1.0),
    )


def test_mesa_textureGrad_dy_dominates() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.0625, 0.0),
        Vector2(0.0, 1.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.5, 0.0, 0.0, 1.0),
    )


def test_mesa_textureGrad_rectangular_x() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.125, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.25, 0.125, 0.25, 1.0),
    )


def test_mesa_textureGrad_rectangular_y() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.0, 0.125),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.125, 0.3125, 0.625, 1.0),
    )


def test_mesa_textureGrad_negative_gradients() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(-0.25, 0.0),
        Vector2(0.0, -0.5),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.375, 0.0625, 0.125, 1.0),
    )


def test_mesa_textureGrad_swapped_derivatives() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.0, 0.5),
        Vector2(0.25, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.375, 0.0625, 0.125, 1.0),
    )


def test_mesa_textureGrad_diagonal() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.15000000596046448, 0.4000000059604645),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.375, 0.0625, 0.125, 1.0),
    )


def test_mesa_textureGrad_nearest_below_mip_switch() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.1486508846282959, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.25, 0.125, 0.25, 1.0),
    )


def test_mesa_textureGrad_nearest_above_mip_switch() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.21022410690784454, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.375, 0.0625, 0.125, 1.0),
    )


def test_mesa_textureGrad_trilinear_half() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.34375, 0.6875),
        Vector2(0.1767766922712326, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_LINEAR,
        CLAMP,
        FloatColor(0.3125, 0.09375, 0.1875, 1.0),
    )


def test_mesa_textureGrad_bilinear() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.375, 0.625),
        Vector2(0.0625, 0.0),
        Vector2(0.0, 0.125),
        LINEAR_MIPMAP_LINEAR,
        CLAMP,
        FloatColor(0.125, 0.34375, 0.5625, 1.0),
    )


def test_mesa_textureGrad_trilinear_bilinear() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.375, 0.625),
        Vector2(0.1767766922712326, 0.0),
        Vector2(0.0, 0.0),
        LINEAR_MIPMAP_LINEAR,
        CLAMP,
        FloatColor(0.3125, 0.109375, 0.171875, 1.0),
    )


def test_mesa_textureGrad_uv_lower_left() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.03125, 0.0625),
        Vector2(0.0, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.125, 0.0, 0.0, 1.0),
    )


def test_mesa_textureGrad_uv_upper_right() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(0.96875, 0.9375),
        Vector2(0.0, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.125, 0.9375, 0.875, 1.0),
    )


def test_mesa_textureGrad_uv_clamp() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(-0.25, 1.25),
        Vector2(0.0, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.125, 0.0, 0.875, 1.0),
    )


def test_mesa_textureGrad_uv_repeat() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(1.34375, -0.3125),
        Vector2(0.0, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        REPEAT,
        FloatColor(0.125, 0.3125, 0.625, 1.0),
    )


def test_mesa_textureGrad_uv_mirror() raises:
    check_mesa_case(
        "textureGrad(source, uv, dx, dy)",
        Vector2(1.34375, -0.3125),
        Vector2(0.0, 0.0),
        Vector2(0.0, 0.0),
        NEAREST_MIPMAP_NEAREST,
        MIRROR,
        FloatColor(0.125, 0.625, 0.25, 1.0),
    )


def test_mesa_textureGrad_uv_transform_fixed_grad() raises:
    check_mesa_case(
        "textureGrad(source, uv * 2.0 + vec2(0.125,0.125), dx, dy)",
        Vector2(0.125, 0.25),
        Vector2(0.0625, 0.0),
        Vector2(0.0, 0.125),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.125, 0.375, 0.625, 1.0),
    )


def test_mesa_textureGrad_uv_transform_scaled_grad() raises:
    check_mesa_case(
        "textureGrad(source, uv * 2.0 + vec2(0.125,0.125), dx * 2.0, dy * 2.0)",
        Vector2(0.125, 0.25),
        Vector2(0.0625, 0.0),
        Vector2(0.0, 0.125),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.25, 0.1875, 0.25, 1.0),
    )


def test_mesa_textureGrad_constant_arguments() raises:
    check_mesa_case(
        (
            "textureGrad(source, vec2(0.34375,0.6875), vec2(0.25,0.0),"
            " vec2(0.0,0.5))"
        ),
        Vector2(0.34375, 0.6875),
        Vector2(0.25, 0.0),
        Vector2(0.0, 0.5),
        NEAREST_MIPMAP_NEAREST,
        CLAMP,
        FloatColor(0.375, 0.0625, 0.125, 1.0),
    )


def test_gradient_node_uses_explicit_inputs_and_keeps_sampler_binding() raises:
    assert_true(NODE_TEXTURE_GRAD.is_valid())
    var graph = NodeGraph()
    var uv = graph.vec2(0.25, 0.5)
    var dx = graph.vec2(0.125, 0)
    var dy = graph.vec2(0, 0.125)
    var fixed = graph.texture_grad(TextureId(3), uv, dx, dy)
    var named = graph.texture_grad(
        graph.texture_uniform("map", TextureId(4)), uv, dx, dy
    )
    graph.set_output(FRAGMENT_NODE, graph.add(fixed, named))
    var program = graph.compile()
    assert_equal(len(program.textures), 2)
    program.set_texture("map", TextureId(5))
    var source = Corners(program)
    var result = run_nodes(source, FRAGMENT_NODE, here_inputs(source, True))
    assert_equal(result[0], 0.5)
    assert_equal(result[1], 1)
    assert_equal(result[2], 6)
    assert_equal(result[3], 0.5)
    var white = run_nodes(source, FRAGMENT_NODE, here_inputs(source, False))
    assert_equal(white[0], 2)
    assert_equal(white[3], 2)


def test_gradient_signatures_versions_and_stages_are_checked() raises:
    for expression in [
        "textureGrad()",
        "textureGrad(map, vec2(0.0), vec2(0.0))",
        "textureGrad(map, vec2(0.0), vec2(0.0), vec2(0.0), 1.0)",
        "textureGrad(1.0, vec2(0.0), vec2(0.0), vec2(0.0))",
        "textureGrad(map, vec3(0.0), vec2(0.0), vec2(0.0))",
        "textureGrad(map, vec2(0.0), 0.0, vec2(0.0))",
        "textureGrad(map, vec2(0.0), vec2(0.0), ivec2(0))",
    ]:
        refused(
            "uniform sampler2D map; void main() { gl_FragColor = "
            + expression
            + "; }",
            "textureGrad() takes a sampler2D and three vec2 values",
        )
    for sampler in ["samplerCube", "sampler3D", "sampler2DArray"]:
        refused(
            "uniform "
            + sampler
            + " map; void main() { gl_FragColor = textureGrad(map, vec2(0.0),"
            " vec2(0.0), vec2(0.0)); }",
            "textureGrad() takes a sampler2D and three vec2 values",
        )
    with assert_raises(contains="not in this shader's GLSL version"):
        _ = compile_raw_shader_material(
            "attribute vec3 position; uniform mat4 modelViewMatrix; uniform"
            " mat4 projectionMatrix;"
            + VERTEX,
            (
                "precision highp float; uniform sampler2D map; void main() {"
                " gl_FragColor = textureGrad(map, vec2(0.0), vec2(0.0),"
                " vec2(0.0)); }"
            ),
        )
    var graph = NodeGraph()
    var read = graph.texture_grad(
        TextureId(0), graph.vec2(0, 0), graph.vec2(0, 0), graph.vec2(0, 0)
    )
    var position = graph.copy()
    position.set_output(POSITION_NODE, position.swizzle(read, "rgb"))
    with assert_raises(contains="position node"):
        _ = position.compile()
    var size = graph.copy()
    size.set_output(SIZE_NODE, size.swizzle(read, "r"))
    with assert_raises(contains="size node"):
        _ = size.compile()
    var starts = List[Int]()
    with assert_raises(contains="compute program runs on no surface"):
        _ = graph.compile_roots([read], starts)
    with assert_raises(contains="must be a vec2"):
        _ = graph.texture_grad(
            TextureId(0), graph.vec2(0, 0), graph.float(0), graph.vec2(0, 0)
        )
    with assert_raises(contains="must be a vec2"):
        _ = graph.texture_grad(
            TextureId(0),
            graph.vec2(0, 0),
            graph.vec2(0, 0),
            graph.vec3(0, 0, 0),
        )
    with assert_raises(contains="no node with that ref"):
        _ = graph.texture_grad(
            TextureId(0), graph.vec2(0, 0), NodeRef(-1), graph.vec2(0, 0)
        )


def test_nonfinite_constants_are_refused_and_runtime_gradients_fail_closed() raises:
    for expression in [
        "vec2(1.0 / 0.0)",
        "vec2(0.0 / 0.0)",
        "vec2(sqrt(-1.0))",
    ]:
        refused(
            "uniform sampler2D map; void main() { gl_FragColor ="
            " textureGrad(map, vec2(0.5), "
            + expression
            + ", vec2(0.0)); }",
            "texture gradient must be finite",
        )
    var image = authored_mips(NEAREST_MIPMAP_NEAREST, CLAMP)
    for bad in [
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
    ]:
        var graph = NodeGraph()
        with assert_raises(contains="must be finite"):
            _ = graph.texture_grad(
                TextureId(0),
                graph.vec2(0.5, 0.5),
                graph.vec2(bad, 0),
                graph.vec2(0, 0),
            )
        with assert_raises(contains="must be finite"):
            _ = image.sample_grad(0.5, 0.5, Vector2(0, 0), Vector2(0, bad))
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform sampler2D map; uniform vec2 dx; uniform vec2 dy; void"
            " main() { gl_FragColor = textureGrad(map, vec2(0.5), dx, dy); }"
        ),
    )
    program.set_texture("map", TextureId(0))
    for lane in range(4):
        var dx = Vector2(0, 0)
        var dy = Vector2(0, 0)
        if lane == 0:
            dx.x = inf[DType.float32]()
        elif lane == 1:
            dx.y = nan[DType.float32]()
        elif lane == 2:
            dy.x = -inf[DType.float32]()
        else:
            dy.y = nan[DType.float32]()
        program.set_uniform("dx", dx)
        program.set_uniform("dy", dy)
        var source = TextureSource(program, image)
        var rgb = run_nodes(source, COLOR_NODE, here_inputs(source, True))
        var alpha = run_nodes(source, OPACITY_NODE, here_inputs(source, True))
        assert_color(
            FloatColor(rgb[0], rgb[1], rgb[2], alpha[0]), FloatColor(0, 0, 0, 0)
        )


def test_gradients_keep_alpha_colorspace_wrap_and_existing_uv_placement() raises:
    var pixels: List[UInt8] = [255, 0, 0, 255, 0, 255, 0, 0]
    var image = Texture(2, 1, pixels^, CLAMP, BILINEAR, SRGB, True, COVERAGE)
    image.offset = Vector2(0.25, 0.75)
    image.repeat = Vector2(4, 2)
    assert_color(
        image.sample_grad(0.5, 0.5, Vector2(1, 0), Vector2(0, 0)),
        FloatColor(1, 0, 0, Float32(128) / 255),
    )
    # Texture nodes receive already placed coordinates, just as textureLod.
    assert_color(
        image.sample_grad(0.125, 0.5, Vector2(0, 0), Vector2(0, 0)),
        image.sample_level(0.125, 0.5, 0),
    )
    image.flip_y = False
    assert_color(
        image.sample_grad(0.75, 0.5, Vector2(0, 0), Vector2(0, 0)),
        image.sample_level(0.75, 0.5, 0),
    )


def test_anisotropic_gradients_average_bounded_taps() raises:
    var pixels = List[UInt8]()
    for _ in range(8):
        for x in range(8):
            var value = UInt8(255 if x % 2 == 0 else 0)
            pixels.extend([value, value, value, UInt8(255)])
    var image = Texture(8, 8, pixels^, REPEAT, NEAREST, LINEAR, False)
    image.anisotropy = 8
    assert_color(
        image.sample_grad(0.5, 0.5, Vector2(1, 0), Vector2(0, 0.125)),
        FloatColor(0.5, 0.5, 0.5, 1),
    )
    image.anisotropy = MAX_ANISOTROPY
    var huge = image.sample_grad(0.5, 0.5, Vector2(3e38, 0), Vector2(0, 3e-38))
    assert_true(isfinite(huge.r) and isfinite(huge.a))
    var footprint = anisotropic_footprint(
        Vector2(3e38, 0), Vector2(0, 3e-38), 8, 8, MAX_ANISOTROPY
    )
    assert_true(footprint.taps >= 1 and footprint.taps <= MAX_ANISOTROPY)
    for mode in [CLAMP, REPEAT, MIRROR]:
        assert_true(isfinite(gradient_sample_coordinate(Float32(3e38), mode)))
        assert_true(isfinite(gradient_sample_coordinate(Float32(-3e38), mode)))
    assert_color(
        Texture().sample_grad(0, 0, Vector2(0, 0), Vector2(0, 0)),
        FloatColor(1, 1, 1, 1),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
