# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sphere wearing MeshNormalMaterial, circled by the camera.

    mojo run -I . examples/normals.mojo [path.png]

The colors are the view-space normal, written as bytes no curve touches.
Turning the camera turns the colors. That is why a normal is not a color
that lighting can mix.
"""

from tools._example_output import (
    example_destination,
    framed_camera,
    gallery_renderer,
    spin_clip,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import normal_material
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/normals.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 28, 18))
    var paint = assets.materials.add(normal_material())

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, paint, node))

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.2, 3.1)
    var eye_node = scene.attach(eye^, pivot)
    var camera = framed_camera(
        WIDTH,
        HEIGHT,
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )
    camera.attach(eye_node)

    spin_clip(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
