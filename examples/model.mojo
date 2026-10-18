# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube loaded from a Wavefront OBJ file, then turned.

    mojo run -I . examples/model.mojo [path.png]

`assets/cube.obj` is eight corners and six quads. `read_obj` turns that
into a BufferGeometry. After that it is an ordinary mesh.
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
from loaders.obj import read_obj
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/model.png"
comptime DEFAULT_MODEL = "assets/cube.obj"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var model = read_obj(DEFAULT_MODEL)
    if model.count() < 1:
        raise Error("The OBJ file has no objects")
    var geometry = model.objects[0].take_geometry()

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var block = assets.geometries.add(geometry^)
    var paint = assets.materials.add(Material(Color(210, 90, 70)))

    var scene = Scene()
    var tilted = Object3D()
    tilted.set_euler(
        Angle(22.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var node = scene.add(tilted^)
    scene.add_mesh(Mesh(block, paint, node))

    fill_and_key(
        scene,
        0.45,
        0.8,
        0.55,
        Color(255, 255, 255),
        0.69,
        Color(255, 255, 255),
        2.51,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0.25, 2.6),
        Vector3(0, 0, 0),
        field_of_view=Angle(45.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
