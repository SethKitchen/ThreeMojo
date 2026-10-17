# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An icosahedron drawn by the shared rasterizer the GPU backend also runs.

    mojo run -I . examples/gpu_backend.mojo [path.png]

The GPU kernel is the same per-pixel loop. This file uses the CPU
`Renderer` so it runs without MAX, and still shows the picture both
backends agree on.
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
from geometries.polyhedron import icosahedron
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/gpu_backend.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(10, 12, 16))

    var assets = Assets()
    var solid = assets.geometries.add(icosahedron(Length(1.05, METER), 1))
    var paint = assets.materials.add(Material(Color(80, 210, 150)))

    var scene = Scene()
    var tilted = Object3D()
    tilted.set_euler(
        Angle(16.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var node = scene.add(tilted^)
    scene.add_mesh(Mesh(solid, paint, node))

    fill_and_key(
        scene,
        0.55,
        0.85,
        0.7,
        Color(255, 255, 255),
        0.63,
        Color(255, 255, 255),
        2.67,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0.2, 3.3),
        Vector3(0, 0, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
