# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the renderer's output color space, three.js's
`outputColorSpace`: the encoding of each space, and the images it gives.

`assets/output_color_space/three_output.mjs` makes the reference with
three.js 0.180: the shader's matrix for each space, whether it applies
sRGB's curve, and the bytes a few linear colors come out as.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from loaders.json import JsonDocument, parse_json
from materials.material import BASIC, Material, normal_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.color_spaces import (
    ColorSpaceId,
    DISPLAY_P3_COLOR_SPACE,
    EXTENDED_SRGB_COLOR_SPACE,
    LINEAR_DISPLAY_P3_COLOR_SPACE,
    LINEAR_REC2020_COLOR_SPACE,
    LINEAR_SRGB_COLOR_SPACE,
    NO_COLOR_SPACE,
    OutputEncoding,
    SRGB_COLOR_SPACE,
    output_encoding,
    output_from,
)
from render.framebuffer import Color, FloatColor
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
from units.si import Angle, DEGREE, Length, METER


def _spaces() -> List[ColorSpaceId]:
    """Return the spaces in the reference's order."""
    return [
        SRGB_COLOR_SPACE,
        LINEAR_SRGB_COLOR_SPACE,
        DISPLAY_P3_COLOR_SPACE,
        LINEAR_DISPLAY_P3_COLOR_SPACE,
        LINEAR_REC2020_COLOR_SPACE,
        EXTENDED_SRGB_COLOR_SPACE,
    ]


def test_each_space_encodes_as_three_js_shader_does() raises:
    var doc = parse_json(
        Path("assets/output_color_space/output.json").read_text()
    )
    var colors = doc.get(doc.root(), "colors")
    var entries = doc.get(doc.root(), "spaces")
    var spaces = _spaces()
    assert_equal(doc.length(entries), len(spaces))
    for at in range(len(spaces)):
        var entry = doc.at(entries, at)
        var encoding = output_encoding(spaces[at])
        var elements = doc.get(entry, "elements")
        for k in range(9):
            assert_almost_equal(
                Float64(encoding.elements[k]),
                doc.number(doc.at(elements, k)),
                atol=1e-6,
            )
        assert_equal(encoding.srgb, doc.boolean(doc.get(entry, "srgb")))
        var bytes = doc.get(entry, "bytes")
        for c in range(doc.length(colors)):
            var rgb = doc.at(colors, c)
            var light = FloatColor(
                Float32(doc.number(doc.at(rgb, 0))),
                Float32(doc.number(doc.at(rgb, 1))),
                Float32(doc.number(doc.at(rgb, 2))),
                1,
            )
            var shown = encoding.encode(light)
            var want = doc.at(bytes, c)
            # three.js's curve raises to 0.41666 rather than 1 / 2.4, so
            # a byte can round the other way.
            assert_true(abs(Int(shown.r) - doc.integer(doc.at(want, 0))) <= 1)
            assert_true(abs(Int(shown.g) - doc.integer(doc.at(want, 1))) <= 1)
            assert_true(abs(Int(shown.b) - doc.integer(doc.at(want, 2))) <= 1)
            assert_equal(Int(shown.a), 255)


def test_the_default_output_is_srgb_and_skips_the_matrix() raises:
    var default = OutputEncoding()
    var srgb = output_encoding(SRGB_COLOR_SPACE)
    assert_true(default.srgb and srgb.srgb)
    assert_true(default.identity and srgb.identity)
    assert_false(output_encoding(DISPLAY_P3_COLOR_SPACE).identity)
    var flat = output_encoding(DISPLAY_P3_COLOR_SPACE).flatten()
    assert_equal(len(flat), 11)
    assert_equal(flat[9], Float32(1))
    assert_equal(flat[10], Float32(0))
    # The device reads the floats back as the encoding they came from.
    var back = output_from(
        flat.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](), 0
    )
    var p3 = output_encoding(DISPLAY_P3_COLOR_SPACE)
    assert_true(back.srgb and not back.identity)
    for at in range(9):
        assert_equal(back.elements[at], p3.elements[at])


def test_what_is_not_an_output_space_is_refused() raises:
    with assert_raises(contains="NO_COLOR_SPACE"):
        _ = output_encoding(NO_COLOR_SPACE)
    with assert_raises(contains="Not a color space"):
        _ = output_encoding(ColorSpaceId(40))
    var renderer = Renderer(4, 4)
    with assert_raises():
        renderer.set_output_color_space(NO_COLOR_SPACE)
    assert_true(renderer.output_color_space == SRGB_COLOR_SPACE)


def _sheet(material: Material) raises -> Tuple[Scene, Assets]:
    """Return a scene of one sheet filling the view."""
    var scene = Scene()
    var assets = Assets()
    var sheet = assets.geometries.add(plane(Length(4, METER), Length(4, METER)))
    var paint = assets.materials.add(material)
    scene.add_mesh(Mesh(sheet, paint, scene.add(Object3D())))
    scene.update()
    return (scene^, assets^)


def _center(scene: Scene, assets: Assets, space: ColorSpaceId) raises -> Color:
    """Return the middle pixel of the scene, written out in `space`."""
    var camera = PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(0.1, METER), Length(10, METER)
    )
    camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
    var renderer = Renderer(8, 8)
    renderer.set_output_color_space(space)
    var image = renderer.render(scene, assets, camera)
    return image.get_pixel(4, 4)


def test_a_linear_output_writes_the_light_itself() raises:
    var made = _sheet(Material(Color(128, 64, 200), kind=BASIC))
    var srgb = _center(made[0], made[1], SRGB_COLOR_SPACE)
    var linear = _center(made[0], made[1], LINEAR_SRGB_COLOR_SPACE)
    # The sheet's color, as sRGB bytes, and as the light they stand for.
    assert_equal(Int(srgb.r), 128)
    var want = FloatColor(srgb=Color(128, 64, 200)).quantize()
    assert_equal(Int(linear.r), Int(want.r))
    assert_equal(Int(linear.g), Int(want.g))
    assert_equal(Int(linear.b), Int(want.b))
    # Display P3 carries the light through three.js's matrix first.
    var p3 = _center(made[0], made[1], DISPLAY_P3_COLOR_SPACE)
    var through = output_encoding(DISPLAY_P3_COLOR_SPACE).encode(
        FloatColor(srgb=Color(128, 64, 200))
    )
    assert_equal(Int(p3.r), Int(through.r))
    assert_equal(Int(p3.g), Int(through.g))
    assert_equal(Int(p3.b), Int(through.b))


def test_data_is_written_as_it_is_in_any_space() raises:
    # A normal material's pixels are data, which three.js writes without
    # `linearToOutputTexel`, so every space shows the same bytes.
    var made = _sheet(normal_material())
    var srgb = _center(made[0], made[1], SRGB_COLOR_SPACE)
    for space in [LINEAR_SRGB_COLOR_SPACE, DISPLAY_P3_COLOR_SPACE]:
        var other = _center(made[0], made[1], space)
        assert_equal(Int(other.r), Int(srgb.r))
        assert_equal(Int(other.g), Int(srgb.g))
        assert_equal(Int(other.b), Int(srgb.b))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
