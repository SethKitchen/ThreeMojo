# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tube swept along one cubic Bezier curve.

    mojo run -I . examples/curves.mojo [path.png]

The curve is sampled, lifted into space, and given thickness. The page is
Curves. This file draws that one path, not a set of kinds.
"""

from examples.output import example_destination, spin_clip

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.tube import tube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.curve import cubic_bezier
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/curves.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var bend = cubic_bezier(
        Vector2(-1.3, -0.85),
        Vector2(-0.3, 1.25),
        Vector2(0.3, -1.25),
        Vector2(1.3, 0.85),
    )
    var samples = bend.sample(28)
    var path = List[Vector3]()
    for point in samples:
        path.append(Vector3(point.x, point.y, 0))

    var assets = Assets()
    var hose = assets.geometries.add(tube(path, Length(0.13, METER), 8, False))
    var paint = assets.materials.add(Material(Color(255, 170, 70)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(hose, paint, node))

    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.9)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.69))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.67))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.15, 3.5), Vector3(0, 0, 0))

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
