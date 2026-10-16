# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube circled by an OrthographicCamera riding a pivot.

    mojo run -I . examples/ortho.mojo [path.png]

Parallel projection keeps the cube the same size at every depth. The
camera is a scene node, the same way a mesh is.
"""

from examples.output import example_destination, spin_clip

from cameras.orthographic_camera import OrthographicCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/cameras.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(1.1, METER)))
    var paint = assets.materials.add(Material(Color(90, 190, 255)))

    var scene = Scene()
    var tilted = Object3D()
    tilted.set_euler(
        Angle(22.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var box = scene.add(tilted^)
    scene.add_mesh(Mesh(block, paint, box))

    var lamp = Object3D()
    lamp.set_position(0.45, 0.85, 0.55)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.69))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.35, 3.2)
    var eye_node = scene.attach(eye^, pivot)

    var camera = OrthographicCamera(
        Length(-1.7, METER),
        Length(1.7, METER),
        Length(1.25, METER),
        Length(-1.25, METER),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.attach(eye_node)

    spin_clip(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
