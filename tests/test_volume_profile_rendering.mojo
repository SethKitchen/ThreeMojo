# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Image regressions shared with the volume-profile GPU parity test."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.ies_spot_light import ies_spot_light
from lights.light import CONE_SPOT
from lights.projector_light import projector_light
from materials.volume_node_material import volume_node_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.texture import float_texture
from render.texture_store import NO_TEXTURE
from renderers.renderer import Renderer
from std.testing import TestSuite, assert_true
from units.si import Angle, DEGREE, Length, METER


def profiled_volume_scene(mut assets: Assets, projector: Bool) raises -> Scene:
    """Return a volume under one IES or projector beam.

    Args:
        assets: The stores receiving the geometry, material and IES map.
        projector: True for a narrow projector, False for a measured profile.

    Returns:
        The updated scene.

    Raises:
        Error: If a fixture asset cannot be built.
    """
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(2.0, METER))),
            assets.materials.add(volume_node_material(steps=12)),
            node,
        )
    )
    var lamp = scene.add(Object3D())
    scene.node(lamp).set_position(0, 2.5, 0)
    if projector:
        scene.add_light(
            projector_light(
                Color(100, 180, 255),
                lamp,
                40,
                angle=Angle(35, DEGREE),
                aspect=0.3,
            )
        )
    else:
        var values: List[Float32] = [0.1, 0, 0, 1, 0.8, 0, 0, 1]
        var profile = assets.textures.add(float_texture(2, 1, values^))
        scene.add_light(
            ies_spot_light(
                Color(255, 180, 100),
                lamp,
                profile,
                40,
                angle=Angle(35, DEGREE),
            )
        )
    scene.update()
    return scene^


def test_profiles_change_the_rendered_volume_from_a_plain_cone() raises:
    for style in range(2):
        var assets = Assets()
        var scene = profiled_volume_scene(assets, style == 1)
        var renderer = Renderer(48, 36)
        var camera = PerspectiveCamera(
            Angle(50, DEGREE),
            Float32(48) / Float32(36),
            Length(0.1, METER),
            Length(100, METER),
        )
        camera.place(Vector3(0.4, 0.3, 4), Vector3(0, 0, 0))
        var shaped = renderer.render(scene, assets, camera)
        scene.lights[0].spot_shape = CONE_SPOT
        scene.lights[0].ies_map = NO_TEXTURE
        var plain = renderer.render(scene, assets, camera)
        var changed = 0
        for y in range(36):
            for x in range(48):
                var a = shaped.get_pixel(x, y)
                var b = plain.get_pixel(x, y)
                if (
                    abs(Int(a.r) - Int(b.r)) > 1
                    or abs(Int(a.g) - Int(b.g)) > 1
                    or abs(Int(a.b) - Int(b.b)) > 1
                ):
                    changed += 1
        assert_true(changed > 20, "the volume ignored its spot beam profile")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
