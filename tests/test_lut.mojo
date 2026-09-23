# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.lut_cube` and the LUT pass: three.js's
`LUTCubeLoader` and `LUTPass`, a `.cube` table read into a 3D texture and
the frame graded through it."""

from cameras.orthographic_camera import OrthographicCamera
from core.assets import Assets
from core.scene import Scene
from loaders.lut_cube import LUT_MAX_SIZE, parse_lut_cube, read_lut_cube
from math.vector3 import Vector3
from postprocessing.composer import (
    LUT,
    EffectComposer,
    Pass,
    PassKind,
    check_pass,
    clear_pass,
    lut_pass,
    output_pass,
)
from postprocessing.effects import lut_color, lut_light
from render.framebuffer import Color, FloatColor
from render.srgb import LINEAR, linear_to_srgb, srgb_to_linear
from render.target import RenderTarget
from render.texture import (
    BILINEAR,
    CLAMP,
    FLOAT_TYPE,
    UNSIGNED_BYTE_TYPE,
    Filter,
    TexelType,
)
from render.volume_texture import Data3DTexture
from render.volume_texture_store import NO_DATA_3D_TEXTURE, Data3DTextureId
from renderers.renderer import Renderer
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime TOLERANCE = Float64(1e-5)


def entries(size: Int, invert: Bool) -> String:
    """Return the data lines of a table of `size` a side: the identity, or
    each channel turned upside down. Red changes fastest."""
    var text = String()
    for b in range(size):
        for g in range(size):
            for r in range(size):
                var step = Float64(size - 1)
                var red = Float64(r) / step
                var green = Float64(g) / step
                var blue = Float64(b) / step
                if invert:
                    red = 1 - red
                    green = 1 - green
                    blue = 1 - blue
                text += (
                    String(red)
                    + " "
                    + String(green)
                    + " "
                    + String(blue)
                    + "\n"
                )
    return text


def table(size: Int, invert: Bool) -> String:
    """Return a whole `.cube` file with no title."""
    return "LUT_3D_SIZE " + String(size) + "\n" + entries(size, invert)


def assert_close(
    got: FloatColor, r: Float32, g: Float32, b: Float32, a: Float32
) raises:
    """Assert every channel of `got` is within the tolerance."""
    assert_almost_equal(got.r, r, atol=TOLERANCE)
    assert_almost_equal(got.g, g, atol=TOLERANCE)
    assert_almost_equal(got.b, b, atol=TOLERANCE)
    assert_almost_equal(got.a, a, atol=TOLERANCE)


# --- the loader -------------------------------------------------------------


def test_a_cube_file_reads_into_a_3d_table() raises:
    var text = (
        String('TITLE "Identity"\r\n')
        + "# a comment\n"
        + "\n"
        + "LUT_3D_INPUT_RANGE 0.0 1.0\n"
        + "lut_other 1\n"
        + "_private 2\n"
        + "LUT_3D_SIZE 2\r\n"
        + entries(2, False)
    )
    var lut = parse_lut_cube(text)
    assert_equal(lut.title.value(), "Identity")
    assert_equal(lut.size, 2)
    assert_equal(lut.domain_min.x, 0.0)
    assert_equal(lut.domain_max.z, 1.0)
    ref texture = lut.texture
    assert_true(texture.image.texel_type == UNSIGNED_BYTE_TYPE)
    assert_true(texture.wrap_s == CLAMP)
    assert_true(texture.wrap_t == CLAMP)
    assert_true(texture.wrap_r == CLAMP)
    assert_true(texture.filter == BILINEAR)
    assert_true(texture.color_space == LINEAR)
    assert_equal(texture.image.width, 2)
    assert_equal(texture.image.depth, 2)
    # Red across, green up, blue deep.
    assert_close(texture.texel_fetch(1, 0, 0), 1, 0, 0, 1)
    assert_close(texture.texel_fetch(0, 1, 1), 0, 1, 1, 1)


def test_bytes_are_cut_as_a_uint8_array_cuts_them() raises:
    var text = String("LUT_3D_SIZE 2\n")
    for _ in range(8):
        text += "0.5 1 0\n"
    var lut = parse_lut_cube(text)
    assert_false(Bool(lut.title))
    # 127.5 is cut to 127, not rounded to 128.
    assert_equal(lut.texture.image.pixels[0], 127)
    assert_equal(lut.texture.image.pixels[1], 255)
    assert_equal(lut.texture.image.pixels[3], 255)


def test_floats_keep_light_above_one_and_the_domain_is_kept() raises:
    var text = String(
        "DOMAIN_MIN 0.1 0.2 0.3\nDOMAIN_MAX 2 3 4\nLUT_3D_SIZE 2\n"
    )
    for _ in range(8):
        text += "1.5 -0.25 2e0\n"
    var lut = parse_lut_cube(text, FLOAT_TYPE)
    assert_true(lut.texture.image.texel_type == FLOAT_TYPE)
    assert_close(lut.texture.texel_fetch(1, 1, 1), 1.5, -0.25, 2, 1)
    assert_almost_equal(lut.domain_min.y, 0.2, atol=TOLERANCE)
    assert_equal(lut.domain_max.z, 4.0)


def test_a_malformed_cube_file_is_refused() raises:
    with assert_raises(contains="texel type"):
        _ = parse_lut_cube(table(2, False), TexelType(7))
    with assert_raises(contains="needs a LUT_3D_SIZE"):
        _ = parse_lut_cube("# nothing\n")
    with assert_raises(contains="1D table"):
        _ = parse_lut_cube("LUT_1D_SIZE 4\n")
    with assert_raises(contains="takes one number"):
        _ = parse_lut_cube("LUT_3D_SIZE 2 2\n")
    with assert_raises(contains="not a whole number"):
        _ = parse_lut_cube("LUT_3D_SIZE two\n")
    with assert_raises(contains="runs from 2 through 256"):
        _ = parse_lut_cube("LUT_3D_SIZE 1\n")
    with assert_raises(contains="runs from 2 through 256"):
        _ = parse_lut_cube("LUT_3D_SIZE " + String(LUT_MAX_SIZE + 1) + "\n")
    with assert_raises(contains="double quotes"):
        _ = parse_lut_cube("TITLE none\n")
    with assert_raises(contains="double quotes"):
        _ = parse_lut_cube('TITLE "half\n')
    with assert_raises(contains="three numbers"):
        _ = parse_lut_cube("DOMAIN_MIN 0 0\n")
    with assert_raises(contains="three numbers"):
        _ = parse_lut_cube("0 0 0 0\n")
    with assert_raises(contains="not a number"):
        _ = parse_lut_cube("0 zero 0\n")
    with assert_raises(contains="finite"):
        _ = parse_lut_cube("0 1e100 0\n")
    with assert_raises(contains="LUT line 2"):
        _ = parse_lut_cube("LUT_3D_SIZE 2\n0 0\n")
    with assert_raises(contains="holds 8 entries"):
        _ = parse_lut_cube("LUT_3D_SIZE 2\n0 0 0\n")
    var over = String("LUT_3D_SIZE 2\n")
    var under = String("LUT_3D_SIZE 2\n")
    for _ in range(8):
        over += "1.5 0 0\n"
        under += "0 0 -0.5\n"
    with assert_raises(contains="zero to one"):
        _ = parse_lut_cube(over)
    with assert_raises(contains="zero to one"):
        _ = parse_lut_cube(under)


def test_a_domain_whose_minimum_is_above_its_maximum_is_refused() raises:
    for axis in range(3):
        var low: List[String] = ["0", "0", "0"]
        low[axis] = "2"
        var text = (
            "DOMAIN_MIN "
            + low[0]
            + " "
            + low[1]
            + " "
            + low[2]
            + "\n"
            + table(2, False)
        )
        with assert_raises(contains="DOMAIN_MIN must not be above"):
            _ = parse_lut_cube(text)


def test_a_cube_file_is_read_from_disk() raises:
    Path("out/lut_identity.cube").write_text(table(2, True))
    var lut = read_lut_cube("out/lut_identity.cube", FLOAT_TYPE)
    assert_close(lut.texture.texel_fetch(0, 0, 0), 1, 1, 1, 1)
    with assert_raises():
        _ = read_lut_cube("out/no_such_table.cube")


# --- the shader -------------------------------------------------------------


def test_an_identity_table_changes_nothing() raises:
    var lut = parse_lut_cube(table(3, False), FLOAT_TYPE)
    var color = FloatColor(0.25, 0.6, 0.9, 0.5)
    assert_close(lut_color(color, lut.texture, 1), 0.25, 0.6, 0.9, 0.5)
    # The half-texel pull keeps zero and one on the edge texels' centers.
    assert_close(lut_color(FloatColor(0, 1, 1, 1), lut.texture, 1), 0, 1, 1, 1)


def test_intensity_mixes_toward_the_lookup() raises:
    var lut = parse_lut_cube(table(2, True), FLOAT_TYPE)
    var color = FloatColor(0.2, 0.3, 1.0, 1)
    assert_close(lut_color(color, lut.texture, 1), 0.8, 0.7, 0.0, 1)
    assert_close(lut_color(color, lut.texture, 0), 0.2, 0.3, 1.0, 1)
    assert_close(lut_color(color, lut.texture, 0.5), 0.5, 0.5, 0.5, 1)


def test_the_pass_grades_encoded_color_and_keeps_alpha() raises:
    var lut = parse_lut_cube(table(2, True), FLOAT_TYPE)
    var frame = RenderTarget(2, 1, Color(0, 0, 0, 0))
    frame.colors[0] = FloatColor(1, 0, 0, 1)
    frame.colors[1] = FloatColor(0.2, 0.2, 0.2, 0.5).premultiplied()
    lut_light(frame, lut.texture, 1)
    assert_close(frame.colors[0], 0, 1, 1, 1)
    var graded = srgb_to_linear(1 - linear_to_srgb(0.2))
    assert_close(frame.colors[1].unpremultiplied(), graded, graded, graded, 0.5)
    var broken = Data3DTexture(copy=lut.texture)
    broken.filter = Filter(6)
    with assert_raises(contains="filter"):
        lut_light(frame, broken, 1)


# --- the pass ---------------------------------------------------------------


def a_camera() raises -> OrthographicCamera:
    """Return a camera the clear and LUT passes never look through."""
    var camera = OrthographicCamera(
        Length(-1.0, METER),
        Length(1.0, METER),
        Length(1.0, METER),
        Length(-1.0, METER),
        Length(0.1, METER),
        Length(10.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def test_the_builder_names_a_table_and_refuses_none() raises:
    assert_true(LUT.is_valid())
    assert_false(PassKind(27).is_valid())
    var step = lut_pass(Data3DTextureId(0), 0.75)
    assert_equal(step.kind, LUT)
    assert_equal(step.lut, Data3DTextureId(0))
    assert_equal(step.strength, Float32(0.75))
    assert_equal(lut_pass(Data3DTextureId(1)).strength, Float32(1))
    assert_equal(Pass(LUT).lut, NO_DATA_3D_TEXTURE)
    with assert_raises(contains="must name a 3D texture"):
        _ = lut_pass(NO_DATA_3D_TEXTURE)
    with assert_raises(contains="must not be negative"):
        _ = lut_pass(Data3DTextureId(0), -1)
    with assert_raises(contains="must name a 3D texture"):
        check_pass(Pass(LUT))


def test_the_composer_grades_the_frame_through_the_table() raises:
    var assets = Assets()
    var lut = parse_lut_cube(table(2, True))
    var id = assets.data_3d_textures.add(Data3DTexture(copy=lut.texture))
    var renderer = Renderer(4, 3)
    var scene = Scene()
    var camera = a_camera()
    var composer = EffectComposer()
    composer.add_pass(clear_pass(Color(255, 0, 0, 255)))
    composer.add_pass(output_pass())
    composer.add_pass(lut_pass(id))
    var image = composer.render(renderer, scene, assets, camera)
    var pixel = image.get_pixel(1, 1)
    assert_equal(pixel.r, UInt8(0))
    assert_equal(pixel.g, UInt8(255))
    assert_equal(pixel.b, UInt8(255))
    assert_equal(pixel.a, UInt8(255))
    # Half way, every channel lands at half the encoded range: 127.5,
    # which rounds either way after the decode and the encode.
    composer.passes[2].strength = 0.5
    var half = composer.render(renderer, scene, assets, camera)
    assert_true(half.get_pixel(0, 0).r >= 127 and half.get_pixel(0, 0).r <= 128)
    assert_true(half.get_pixel(0, 0).g >= 127 and half.get_pixel(0, 0).g <= 128)
    # A table the assets do not hold is refused when the frame is drawn.
    composer.passes[2].lut = Data3DTextureId(1)
    with assert_raises(contains="No 3D texture"):
        _ = composer.render(renderer, scene, assets, camera)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
