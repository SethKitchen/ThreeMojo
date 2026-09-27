# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's toon shaders, drawn on a plane that faces the camera:
its normal in view space is (0, 0, 1), so each shader's arithmetic is worked
out by hand below."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import shader_material
from materials.nodes import NodeProgram
from materials.toon_shaders import (
    toon_shader_1,
    toon_shader_2,
    toon_shader_dotted,
    toon_shader_hatching,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import TestSuite, assert_equal, assert_true
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16


def drawn(var program: NodeProgram) raises -> Framebuffer:
    """Return a two-meter plane drawn with a program, four meters in front
    of the camera."""
    var assets = Assets()
    var id = assets.programs.add(program^)
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(2.0, METER), Length(2.0, METER), 2, 2)
            ),
            assets.materials.add(shader_material(id)),
            node,
        )
    )
    scene.update()
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return Renderer(SIZE, SIZE).render(scene, assets, camera)


def gray(image: Framebuffer, x: Int, y: Int) raises -> Int:
    """Return a pixel's red, which is its green and blue too."""
    var seen = image.get_pixel(x, y)
    assert_equal(seen.r, seen.g)
    assert_equal(seen.g, seen.b)
    return Int(seen.r)


def test_toon_shader_1_rims_in_two_tones() raises:
    # Lit head-on, the light's weight is 1.48 long: the intensity is
    # 0.3 + 0.2 * (1 + 0.2 * 1.48) = 0.559, over a half, and the camera
    # looks straight through, so no rim. The tone is
    # 1 - 2 * (1 - 0.559) * (1 - base): white for a white base.
    var white = toon_shader_1()
    white.set_uniform("uDirLightPos", Vector3(0, 0, 1))
    assert_equal(gray(drawn(white^), 8, 8), 255)
    # A gray base, 0x80, is 0.216 linear: the tone is 0.309, sRGB 151.
    var shaded = toon_shader_1()
    shaded.set_uniform("uDirLightPos", Vector3(0, 0, 1))
    shaded.set_uniform("uBaseColor", Color(0x80, 0x80, 0x80))
    assert_equal(gray(drawn(shaded^), 8, 8), 151)


def test_toon_shader_2_darkens_by_bands() raises:
    # Lit head-on the light is 1.48 long, not under one: the base shows,
    # 0xEE.
    var lit = toon_shader_2()
    lit.set_uniform("uDirLightPos", Vector3(0, 0, 1))
    assert_equal(gray(drawn(lit^), 8, 8), 0xEE)
    # Lit from behind, only the ambient is left, under one: the base times
    # the first line color, 0.855 * 0.216 linear, is sRGB 119.
    var dark = toon_shader_2()
    dark.set_uniform("uDirLightPos", Vector3(0, 0, -1))
    assert_equal(gray(drawn(dark^), 8, 8), 119)


def test_toon_shader_hatching_draws_lines_where_it_is_dark() raises:
    # Lit from behind, every band is on. The pixel (5, 11) has its center
    # at (5.5, 4.5) from the bottom left: x + y is 10, on the first line.
    var dark = toon_shader_hatching()
    dark.set_uniform("uDirLightPos", Vector3(0, 0, -1))
    var image = drawn(dark^)
    assert_equal(gray(image, 5, 11), 0)
    # The middle pixel, (8.5, 7.5), is on no line: x + y is 16 and x - y
    # is 1.
    assert_equal(gray(image, 8, 8), 255)
    # Lit head-on, no band is on.
    var lit = toon_shader_hatching()
    lit.set_uniform("uDirLightPos", Vector3(0, 0, 1))
    assert_equal(gray(drawn(lit^), 5, 11), 255)


def test_toon_shader_dotted_draws_dots_where_it_is_dark() raises:
    # The pixel (7, 9) has its center at (7.5, 6.5): mod(7.5, 4.001) and
    # mod(6.5, 4.0) add to 6.0, not over six, so no dot of the first; the
    # second, two over, adds mod(9.5, 4.001) and mod(8.5, 4.0), 2.0, so
    # none either. The pixel (6, 8), at (6.5, 7.5), adds 2.499 and 3.5,
    # 5.999: no dot; (7, 8), at (7.5, 7.5), adds 3.499 and 3.5, a dot.
    var dark = toon_shader_dotted()
    dark.set_uniform("uDirLightPos", Vector3(0, 0, -1))
    var image = drawn(dark^)
    assert_equal(gray(image, 7, 8), 0)
    assert_equal(gray(image, 6, 8), 255)
    var lit = toon_shader_dotted()
    lit.set_uniform("uDirLightPos", Vector3(0, 0, 1))
    assert_equal(gray(drawn(lit^), 7, 8), 255)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
