# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Utah teapot turns under a lamp.

    mojo run -I . examples/utah.mojo [path.png]

The page is Geometry addons. `teapot` builds the thirty-two bicubic
patches of the classic model. The body, the lid, the handle and the
spout are one geometry.
"""

from examples.output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    spin_clip,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.teapot import teapot
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/teapot.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var assets = Assets()
    var model = assets.geometries.add(teapot(Length(0.85, METER), segments=6))
    var clay = assets.materials.add(Material(Color(196, 154, 118)))

    var scene = Scene()
    var stand = Object3D()
    stand.set_position(0, -0.15, 0)
    var node = scene.add(stand^)
    scene.add_mesh(Mesh(model, clay, node))
    fill_and_key(
        scene,
        1.4,
        2.2,
        1.6,
        Color(255, 255, 255),
        0.35,
        Color(255, 244, 230),
        2.6,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(1.5, 1.05, 2.3),
        Vector3(0, 0.2, 0),
        field_of_view=Angle(38.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(20.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
