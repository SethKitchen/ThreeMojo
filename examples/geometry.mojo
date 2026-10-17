# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A torus knot turning, one builder and nothing else.

    mojo run -I . examples/geometry.mojo [path.png]

The page is Geometry. This file draws one built solid, not a row of them.
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
from geometries.torus import torus_knot
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/geometry.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(14, 16, 22))

    var assets = Assets()
    var knot = assets.geometries.add(
        torus_knot(Length(0.85, METER), Length(0.22, METER), 48, 8, 2, 3)
    )
    var paint = assets.materials.add(Material(Color(90, 190, 255)))

    var scene = Scene()
    var tilted = Object3D()
    tilted.set_euler(
        Angle(18.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var node = scene.add(tilted^)
    scene.add_mesh(Mesh(knot, paint, node))

    fill_and_key(
        scene,
        0.6,
        0.9,
        0.8,
        Color(255, 255, 255),
        0.63,
        Color(255, 255, 255),
        2.67,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0.35, 3.4),
        Vector3(0, 0, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
