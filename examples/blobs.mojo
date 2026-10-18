# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two metaballs join into one surface.

    mojo run -I . examples/blobs.mojo [path.png]

The page is Scene objects. `MarchingCubes` fills a cube of cells from
two balls, then builds the surface where the field crosses isolation.
Each ball paints its own color onto the vertices. The surface turns.
"""

from examples.output import example_destination, gallery_camera, spin_clip

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.marching_cubes import MarchingCubes
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer, available_workers
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/blobs.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var field = MarchingCubes(16, enable_colors=True)
    field.reset()
    field.add_ball(0.42, 0.52, 0.5, 0.85, 10, FloatColor(1, 0.35, 0.12, 1))
    field.add_ball(0.58, 0.5, 0.48, 0.75, 10, FloatColor(0.2, 0.45, 1, 1))
    field.update()

    var assets = Assets()
    var surface = assets.geometries.add(field.geometry())
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), vertex_colors=True)
    )

    var scene = Scene()
    var stand = Object3D()
    stand.set_scale(1.45, 1.45, 1.45)
    var node = scene.add(stand^)
    scene.add_mesh(Mesh(surface, paint, node))
    var lamp = Object3D()
    lamp.set_position(1.2, 1.6, 1.4)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.4))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.4))

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.9, 0.55, 2.4),
        Vector3(0, 0, 0),
        field_of_view=Angle(38.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(20.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
