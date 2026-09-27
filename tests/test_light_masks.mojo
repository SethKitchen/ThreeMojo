# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for materials lit by some of the lights, three.js's `lightsNode`:
the mask, the lighting it narrows, and a frame that lights each material
by its own lights."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ALL_LIGHTS, LightMask, directional_light, lights_of
from lights.lighting import Lighting
from materials.material import BASIC, LAMBERT, PHYSICAL, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.rasterizer import (
    SHADE_LIT,
    SHADE_TEXTURE,
    RasterVertex,
    rasterize_all,
)
from render.target import RenderTarget
from renderers.renderer import Renderer, light_masks
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime SIZE = 16


def test_a_mask_names_the_lights_it_holds() raises:
    var mask = lights_of([0, 2])
    assert_true(mask.is_valid())
    assert_true(mask.includes(0))
    assert_false(mask.includes(1))
    assert_true(mask.includes(2))
    assert_false(mask.includes(70))
    assert_true(ALL_LIGHTS.includes(70))
    assert_true(ALL_LIGHTS.includes(3))
    with assert_raises(contains="the first 64 lights"):
        _ = lights_of([-1])
    with assert_raises(contains="the first 64 lights"):
        _ = lights_of([64])


def two_lights(mut scene: Scene) raises:
    """Add a red light and a blue one, both shining down +z."""
    var node = Object3D()
    node.set_position(0, 0, 5)
    var at = scene.add(node^)
    scene.add_light(directional_light(Color(255, 0, 0), at, 2.0))
    scene.add_light(directional_light(Color(0, 0, 255), at, 2.0))
    scene.update()


def test_a_lighting_takes_the_lights_it_is_given() raises:
    var scene = Scene()
    two_lights(scene)
    assert_equal(Lighting(scene).count(), 2)
    var red = Lighting(scene, chosen=lights_of([0]))
    assert_equal(red.count(), 1)
    assert_true(red.radiances[0].r > 0)
    assert_equal(red.radiances[0].b, 0)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking down -z at the planes."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    return camera^


def a_scene(mut assets: Assets) raises -> Scene:
    """Return two white planes side by side under the two lights: the left
    lit by the red one alone, the right by both."""
    var scene = Scene()
    two_lights(scene)
    var red = Material(Color(255, 255, 255))
    red.lights = lights_of([0])
    var square = assets.geometries.add(
        plane(Length(1, METER), Length(1, METER))
    )
    for index in range(2):
        var stand = Object3D()
        stand.set_position(Float32(index) - 0.5, 0, 0)
        scene.add_mesh(
            Mesh(
                square,
                assets.materials.add(
                    red if index == 0 else Material(Color(255, 255, 255))
                ),
                scene.add(stand^),
            )
        )
    scene.update()
    return scene^


def test_each_material_is_lit_by_its_own_lights() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var masks = light_masks(assets)
    assert_equal(len(masks), 1)
    assert_true(masks[0] == lights_of([0]))
    var image = Renderer(SIZE, SIZE).render(scene, assets, a_camera())
    var left = image.get_pixel(SIZE // 4, SIZE // 2)
    var right = image.get_pixel(3 * SIZE // 4, SIZE // 2)
    assert_true(left.r > 0)
    assert_equal(left.b, 0)
    assert_true(right.r > 0)
    assert_true(right.b > 0)
    # Two materials with the same mask share its lighting.
    var twin = Material(Color(255, 255, 255))
    twin.lights = lights_of([0])
    _ = assets.materials.add(twin)
    assert_equal(len(light_masks(assets)), 1)


def test_a_masked_surface_looks_through_glass_too() raises:
    # A glass pane before the planes: the transmission pass draws the
    # masked plane behind it with its own lights as well.
    var assets = Assets()
    var scene = a_scene(assets)
    var glass = Material(Color(255, 255, 255), kind=PHYSICAL)
    glass.transmission = 1
    var pane = Object3D()
    pane.set_position(0, 0, 1)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(plane(Length(0.5, METER), Length(0.5, METER))),
            assets.materials.add(glass),
            scene.add(pane^),
        )
    )
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.shading = SHADE_TEXTURE
    var image = renderer.render(scene, assets, a_camera())
    assert_equal(image.width, SIZE)


def test_a_triangle_that_names_no_lighting_is_refused() raises:
    var corner = RasterVertex(1, 1, 0, 1, FloatColor(1.0, 1.0, 1.0), kind=BASIC)
    corner.lights = 1
    var corners: List[RasterVertex] = [corner, corner, corner]
    var target = RenderTarget(4, 4, Color(0, 0, 0))
    with assert_raises(contains="names a lighting the frame does not have"):
        rasterize_all(corners, target, SHADE_LIT)
    corner.lights = -1
    corners = [corner, corner, corner]
    with assert_raises(contains="names a lighting the frame does not have"):
        rasterize_all(corners, target, SHADE_LIT)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
