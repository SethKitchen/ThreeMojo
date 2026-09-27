# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `MeshPostProcessingMaterial`: a physical plane under ambient
light, dimmed where a pass's target is dark."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light
from materials.material import Material, PHYSICAL
from materials.post_processing_material import mesh_post_processing_program
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.srgb import LINEAR
from render.texture import CLAMP, NEAREST, Texture
from render.texture_store import NO_TEXTURE
from renderers.renderer import Renderer
from std.testing import TestSuite, assert_raises, assert_true
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16


def a_pass_target() raises -> Texture:
    """Return a target of one texel per pixel: black on the left half,
    white on the right."""
    var pixels = List[UInt8]()
    for _ in range(SIZE):
        for x in range(SIZE):
            var shade = UInt8(0 if x < SIZE // 2 else 255)
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(255)
    return Texture(SIZE, SIZE, pixels^, CLAMP, NEAREST, LINEAR, False)


def a_uniform_map(shade: UInt8) raises -> Texture:
    """Return a two-texel map of one shade."""
    var pixels = List[UInt8]()
    for _ in range(4):
        pixels.append(shade)
        pixels.append(shade)
        pixels.append(shade)
        pixels.append(255)
    return Texture(2, 2, pixels^, CLAMP, NEAREST, LINEAR, False)


def drawn(ao_map_shade: Int = -1) raises -> Framebuffer:
    """Return the plane drawn with the pass's occlusion, and an ambient
    occlusion map of one shade, or none."""
    var assets = Assets()
    var target = assets.textures.add(a_pass_target())
    var ao_map = NO_TEXTURE
    if ao_map_shade >= 0:
        ao_map = assets.textures.add(a_uniform_map(UInt8(ao_map_shade)))
    var id = assets.programs.add(
        mesh_post_processing_program(target, 1, ao_map, 1)
    )
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(4.0, METER), Length(4.0, METER), 2, 2)
            ),
            assets.materials.add(
                Material(Color(255, 255, 255), kind=PHYSICAL, nodes=id)
            ),
            node,
        )
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 2.0))
    scene.update()
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    return Renderer(SIZE, SIZE).render(scene, assets, camera)


def test_the_pass_dims_the_ambient_light_where_it_is_dark() raises:
    var image = drawn()
    var left = image.get_pixel(3, SIZE // 2)
    var right = image.get_pixel(12, SIZE // 2)
    assert_true(Int(right.r) > Int(left.r) + 50, "the dark half is dimmed")
    # A black map dims the light half too; a white one leaves it.
    var mapped = drawn(0)
    assert_true(
        Int(mapped.get_pixel(12, SIZE // 2).r) + 50 < Int(right.r),
        "the map's lower value wins",
    )
    var clear = drawn(255)
    assert_true(
        Int(clear.get_pixel(12, SIZE // 2).r) == Int(right.r),
        "a white map changes nothing",
    )
    with assert_raises(contains="needs the pass's target"):
        _ = mesh_post_processing_program(NO_TEXTURE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
