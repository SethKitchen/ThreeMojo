# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One geometry drawn eight times from one InstancedMesh.

    mojo run -I . examples/instances.mojo [path.png]

The copies sit on a ring. The node they share turns, so the ring turns with
it. Nothing here is eight Mesh objects.
"""

from tools._example_output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    spin_clip,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import Material
from math.matrix4 import rotation_y, translation
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from render.framebuffer import Color
from std.math import cos, pi, sin
from units.si import Angle, DEGREE, Length, METER, RADIAN

comptime DEFAULT_OUTPUT = "out/instances.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime COUNT = 8
comptime RADIUS = Float32(1.35)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(0.42, METER)))
    var paint = assets.materials.add(Material(Color(255, 160, 60)))

    var scene = Scene()
    var node = scene.add(Object3D())
    var group = InstancedMesh(block, paint, node, COUNT)
    for index in range(COUNT):
        var angle = Float32(2) * Float32(pi) * Float32(index) / Float32(COUNT)
        var placed = translation(RADIUS * cos(angle), 0, RADIUS * sin(angle))
        placed.premultiply(rotation_y(Angle(angle, RADIAN)))
        group.set_matrix_at(index, placed)
    scene.add_instanced_mesh(group^)

    fill_and_key(
        scene,
        0.4,
        1.1,
        0.7,
        Color(255, 255, 255),
        0.69,
        Color(255, 255, 255),
        2.51,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 2.1, 3.6),
        Vector3(0, 0, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
