# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a render sampled by a later render: `texture_of`,
`depth_texture_of` and `data_texture` through the whole renderer."""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from materials.material import BASIC, Material, toon_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.rasterizer import SHADE_TEXTURE
from render.target import RenderTarget
from render.framebuffer import Framebuffer
from render.texture import (
    IGNORED,
    NEAREST,
    data_texture,
    depth_texture_of,
    texture_of,
)
from renderers.renderer import Renderer
from std.math import pi
from std.testing import TestSuite, assert_equal, assert_true
from units.si import Length, METER

comptime WIDTH = 16
comptime HEIGHT = 16


def a_camera() raises -> OrthographicCamera:
    """Return a camera looking down -z at a two-meter square of world."""
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def test_a_render_is_drawn_onto_a_surface_in_the_next_render() raises:
    # A red square on black, rendered, then shown on a plane half the
    # size: the second image holds the first, shrunk.
    var assets = Assets()
    var square = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    var red = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(square, red, node))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var first = renderer.render(scene, assets, a_camera())
    assert_true(first.get_pixel(8, 8).r > 128)
    assert_true(first.get_pixel(1, 1).r == 0)

    var screen = assets.textures.add(texture_of(first, mipmapped=False))
    var shown = assets.materials.add(
        Material(Color(255, 255, 255), screen, kind=BASIC)
    )
    var again = Scene()
    var stand = Object3D()
    stand.set_scale(0.5, 0.5, 1)
    var stand_node = again.add(stand^)
    again.update()
    again.add_mesh(Mesh(square, shown, stand_node))
    renderer.set_background(Color(0, 0, 40))
    var second = renderer.render(again, assets, a_camera())
    # The plane covers the middle four by four; its own middle shows the
    # first render's red square, and its corner the first render's black.
    assert_true(second.get_pixel(8, 8).r > 128)
    assert_equal(second.get_pixel(6, 6).r, UInt8(0))
    assert_equal(second.get_pixel(6, 6).b, UInt8(0))
    assert_equal(second.get_pixel(1, 1).b, UInt8(40))


def test_a_render_keeps_its_tones_orientation_and_alpha_on_a_surface() raises:
    # A picture that is not symmetric and not primary: a mid gray on the
    # top row, an orange on the bottom, half covered, shown unlit on a
    # plane and read back through the second render's bytes.
    var picture = Framebuffer(2, 2, Color(0, 0, 0))
    picture.set_pixel(0, 0, Color(128, 128, 128))
    picture.set_pixel(1, 0, Color(128, 128, 128))
    picture.set_pixel(0, 1, Color(255, 128, 0))
    picture.set_pixel(1, 1, Color(255, 128, 0, 128))
    var assets = Assets()
    var square = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var screen = assets.textures.add(
        texture_of(picture, filter=NEAREST, mipmapped=False)
    )
    var shown = assets.materials.add(
        Material(Color(255, 255, 255), screen, kind=BASIC, transparent=True)
    )
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(square, shown, node))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, a_camera())
    # The top row of the picture is at the top of the plane, and its
    # bytes come back as they went in: the sRGB curve was applied once
    # on the way in and once on the way out.
    var top = image.get_pixel(4, 4)
    assert_equal(top.r, UInt8(128))
    assert_equal(top.g, UInt8(128))
    assert_equal(top.b, UInt8(128))
    var bottom = image.get_pixel(4, 11)
    assert_equal(bottom.r, UInt8(255))
    assert_equal(bottom.g, UInt8(128))
    assert_equal(bottom.b, UInt8(0))
    # The half-covered texel blends over black to about half the light.
    var faint = image.get_pixel(11, 11)
    assert_true(faint.r > 170 and faint.r < 200, "the alpha was lost")
    assert_true(faint.b == 0)


def test_a_depth_texture_shows_a_surface_nearer_than_nothing() raises:
    var assets = Assets()
    var square = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    var red = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(square, red, node))
    var renderer = Renderer(WIDTH, HEIGHT)
    var seen = depth_texture_of(renderer.render(scene, assets, a_camera()))
    # The plane is four meters from a camera whose range is a tenth of a
    # meter to ten: well under half the window depth. Nothing else is at
    # the far plane.
    assert_true(seen.texel(8, 8).r < 128)
    assert_equal(seen.texel(1, 1).r, UInt8(255))


def test_a_data_texture_serves_as_a_toon_ramp() raises:
    # A two-tone ramp from numbers rather than from an image file,
    # stepped through by a lit surface.
    var assets = Assets()
    var square = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    var ramp = assets.textures.add(
        data_texture(2, 1, [0.2, 1.0], channels=1, alpha=IGNORED)
    )
    var cel = assets.materials.add(
        toon_material(Color(255, 255, 255), gradient_map=ramp)
    )
    var scene = Scene()
    var node = scene.add(Object3D())
    # A lamp behind the plane, at the intensity that lights a facing
    # white surface to full white: the cosine is minus one, so the
    # surface reads the ramp's left end, a fifth of white.
    var behind = Object3D()
    behind.set_position(0, 0, -1)
    var lamp = scene.add(behind^)
    scene.add_light(directional_light(Color(255, 255, 255), lamp, Float32(pi)))
    scene.update()
    scene.add_mesh(Mesh(square, cel, node))
    var renderer = Renderer(WIDTH, HEIGHT)
    var image = renderer.render(scene, assets, a_camera())
    var dim = image.get_pixel(8, 8).r
    assert_true(dim > 100 and dim < 140, "the ramp was not read")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
