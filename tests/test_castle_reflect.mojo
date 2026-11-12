# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the castle in the water: Fresnel's law, and the mirror image that
is added to the pixels where the water was drawn.

A red box floats over a plane of water at height zero. There is no water mesh:
the test marks the pixels that the water would have changed, a channel at a
time, and the mirror image must reach the pixels where the box is reflected.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.castle.reflect import fresnel, reflect_in_water
from geometries.box import box
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 32


def test_water_reflects_two_percent_looking_down_and_all_looking_along() raises:
    assert_almost_equal(fresnel(1.0), 0.02, atol=1.0e-12)
    assert_almost_equal(fresnel(0.0), 1.0, atol=1.0e-12)
    assert_true(fresnel(0.8) < fresnel(0.4))
    assert_true(fresnel(0.4) < fresnel(0.1))
    # A cosine outside 0 to 1 is held to the ends.
    assert_almost_equal(fresnel(2.0), 0.02, atol=1.0e-12)
    assert_almost_equal(fresnel(-1.0), 1.0, atol=1.0e-12)


struct _World(Movable):
    """A scene with a sky node and a red box floating over the water."""

    var scene: Scene
    var assets: Assets
    var sky: NodeId

    def __init__(out self) raises:
        self.scene = Scene()
        self.assets = Assets()
        self.sky = self.scene.add(Object3D())
        var raised = Object3D()
        raised.set_position(0, 2, 0)
        var node = self.scene.add(raised^)
        self.scene.add_mesh(
            Mesh(
                self.assets.geometries.add(
                    box(
                        Length(3.0, METER),
                        Length(3.0, METER),
                        Length(3.0, METER),
                    )
                ),
                self.assets.materials.add(
                    Material(Color(255, 0, 0), kind=BASIC)
                ),
                node,
            )
        )
        self.scene.update()


def _camera(height: Float32) raises -> PerspectiveCamera:
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, height, 8), Vector3(0, 0, 0))
    return camera^


def _mark_the_water(mut image: Framebuffer):
    """Change the lower half of the picture, a channel at a time: the red of
    the left quarter, the green of the next, the blue of the next, and all
    three of the last."""
    for row in range(SIZE // 2, SIZE):
        for column in range(SIZE):
            var at = (row * SIZE + column) * 4
            var quarter = column // (SIZE // 4)
            if quarter == 0 or quarter == 3:
                image.pixels[at] = image.pixels[at] ^ 0x20
            if quarter == 1 or quarter == 3:
                image.pixels[at + 1] = image.pixels[at + 1] ^ 0x20
            if quarter == 2 or quarter == 3:
                image.pixels[at + 2] = image.pixels[at + 2] ^ 0x20


def test_the_box_is_reflected_where_the_water_was_drawn() raises:
    var world = _World()
    var renderer = Renderer(SIZE, SIZE)
    var camera = _camera(4.0)
    var image = renderer.render(world.scene, world.assets, camera)
    var before = image.pixels.copy()
    _mark_the_water(image)
    var marked = image.pixels.copy()
    var shared = reflect_in_water(
        renderer,
        world.scene,
        world.assets,
        camera,
        world.sky,
        image,
        before,
        0.0,
    )
    # Some of the marked pixels see the box in the water and some do not.
    assert_true(shared > 0)
    assert_true(shared < SIZE * SIZE // 2)
    # A pixel that was not marked is left alone, and the sky is shown again.
    for column in range(SIZE):
        assert_equal(image.pixels[column * 4], before[column * 4])
    assert_true(world.scene.get(world.sky).visible)
    var changed = 0
    for at in range(len(marked)):
        if image.pixels[at] != marked[at]:
            changed += 1
    assert_true(changed > 0)


def test_a_stronger_gain_reflects_more_of_the_box() raises:
    var world = _World()
    var renderer = Renderer(SIZE, SIZE)
    var camera = _camera(4.0)
    var image = renderer.render(world.scene, world.assets, camera)
    var before = image.pixels.copy()
    _mark_the_water(image)
    var dim = Framebuffer(SIZE, SIZE, Color(0, 0, 0))
    dim.pixels = image.pixels.copy()
    _ = reflect_in_water(
        renderer,
        world.scene,
        world.assets,
        camera,
        world.sky,
        image,
        before,
        0.0,
        gain=0.0,
    )
    _ = reflect_in_water(
        renderer,
        world.scene,
        world.assets,
        camera,
        world.sky,
        dim,
        before,
        0.0,
        gain=1.0,
        murk=1.0,
    )
    var different = 0
    for at in range(len(dim.pixels)):
        if dim.pixels[at] != image.pixels[at]:
            different += 1
    assert_true(different > 0)


def test_the_water_seen_from_below_gets_no_mirror_image() raises:
    var world = _World()
    var renderer = Renderer(SIZE, SIZE)
    var camera = _camera(-3.0)
    var image = renderer.render(world.scene, world.assets, camera)
    var before = image.pixels.copy()
    _mark_the_water(image)
    var marked = image.pixels.copy()
    assert_equal(
        reflect_in_water(
            renderer,
            world.scene,
            world.assets,
            camera,
            world.sky,
            image,
            before,
            0.0,
        ),
        0,
    )
    for at in range(len(marked)):
        assert_equal(image.pixels[at], marked[at])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
