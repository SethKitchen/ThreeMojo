# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Red light and green light adding to yellow on one white sphere.

    mojo run -I . examples/additive.mojo [path.png]

The lamps are fixed. The sphere turns, so the overlap slides. Mixing the
encoded bytes would make that overlap too dark. Mixing in linear light
makes it yellow.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
    spin_clip,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/additive.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(10, 11, 16))

    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 28, 18))
    var white = assets.materials.add(Material(Color(255, 255, 255)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, white, node))

    var left = Object3D()
    left.set_position(-1.1, 0.2, 0.6)
    var left_id = scene.add(left^)
    scene.add_light(directional_light(Color(255, 20, 20), left_id, 3.3))

    var right = Object3D()
    right.set_position(1.1, 0.2, 0.6)
    var right_id = scene.add(right^)
    scene.add_light(directional_light(Color(20, 255, 40), right_id, 3.3))

    scene.add_light(ambient_light(Color(24, 26, 32), 3.14))

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0.2, 3.2),
        Vector3(0, 0, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
