# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `WoodNodeMaterial`: the presets, and a plank of teak and one
of walnut drawn in their own colors."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from materials.material import PHYSICAL
from materials.wood import (
    GLOSS,
    MATTE,
    RAW,
    SEMIGLOSS,
    TEAK,
    WALNUT,
    WoodFinish,
    WoodGenus,
    wood_material,
    wood_preset,
    wood_program,
)
from materials.nodes import NodeProgramId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16


def test_the_presets_are_three_js_numbers() raises:
    var teak = wood_preset(TEAK, RAW)
    assert_almost_equal(teak.center_size, 1.11)
    assert_almost_equal(teak.ring_thickness, 1.0 / 34, atol=1e-6)
    assert_equal(teak.dark_grain_color.hex(), 0x0C0504)
    assert_equal(teak.light_grain_color.hex(), 0x926C50)
    assert_equal(teak.clearcoat, 0)
    assert_equal(teak.clearcoat_darken, 1)
    var gloss = wood_preset(WALNUT, GLOSS)
    assert_equal(gloss.clearcoat, 1)
    assert_almost_equal(gloss.clearcoat_roughness, 0.1)
    assert_almost_equal(gloss.clearcoat_darken, 0.2)
    assert_almost_equal(wood_preset(WALNUT, SEMIGLOSS).clearcoat_roughness, 0.4)
    assert_equal(wood_preset(WALNUT, MATTE).clearcoat_roughness, 1)
    assert_false(WoodGenus(10).is_valid())
    assert_false(WoodFinish(-1).is_valid())
    with assert_raises(contains="A wood genus is one of the ten"):
        _ = wood_preset(WoodGenus(10), RAW)
    with assert_raises(contains="raw, matte, semigloss or gloss"):
        _ = wood_preset(TEAK, WoodFinish(4))


def a_plank(genus: WoodGenus) raises -> Framebuffer:
    """Return a plank of a genus, lit from the front."""
    var assets = Assets()
    var params = wood_preset(genus, GLOSS)
    var id = assets.programs.add(wood_program(params))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(1.0, METER), Length(1.0, METER), 2, 2)
            ),
            assets.materials.add(wood_material(id, params)),
            node,
        )
    )
    var lamp = Object3D()
    lamp.set_position(0.3, 0.4, 2)
    var lamp_node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.5))
    scene.update()
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 1.5), Vector3(0, 0, 0))
    return Renderer(SIZE, SIZE).render(scene, assets, camera)


def test_a_plank_is_wood_colored_and_grained() raises:
    var teak = a_plank(TEAK)
    var reds = 0
    var lowest = 255
    var highest = 0
    for y in range(4, 12):
        for x in range(4, 12):
            var seen = teak.get_pixel(x, y)
            # Wood: more red than green, more green than blue.
            if seen.r > seen.g and seen.g >= seen.b:
                reds += 1
            lowest = min(lowest, Int(seen.r))
            highest = max(highest, Int(seen.r))
    assert_true(reds > 48, "teak is brown")
    assert_true(highest - lowest > 3, "the grain varies")
    # Walnut is darker than teak's light grain on average.
    var walnut = a_plank(WALNUT)
    var teak_sum = 0
    var walnut_sum = 0
    for y in range(4, 12):
        for x in range(4, 12):
            teak_sum += Int(teak.get_pixel(x, y).g)
            walnut_sum += Int(walnut.get_pixel(x, y).g)
    assert_true(teak_sum != walnut_sum, "the genuses differ")
    var material = wood_material(NodeProgramId(0), wood_preset(TEAK, RAW))
    assert_equal(material.kind, PHYSICAL)
    assert_equal(material.clearcoat, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
