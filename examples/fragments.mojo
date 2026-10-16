# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A coarse sphere, close up, so per-fragment shading crosses each face.

    mojo run -I . examples/fragments.mojo [path.png]

The triangles are large on purpose. Lighting is evaluated at every pixel
from an interpolated unit normal. Shading only at the corners would crease
every edge.
"""

from examples.output import example_destination, spin_clip

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/fragments.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(10, 11, 16))

    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 10, 6))
    var paint = assets.materials.add(Material(Color(230, 230, 235)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, paint, node))

    var lamp = Object3D()
    lamp.set_position(0.8, 0.35, 0.9)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.38))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 3.3))

    var camera = PerspectiveCamera(
        Angle(32.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.1, 2.35), Vector3(0, 0, 0))

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
