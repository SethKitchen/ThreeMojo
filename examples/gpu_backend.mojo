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

from examples.output import example_destination, spin_frame, write_example

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from geometries.polyhedron import icosahedron
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/gpu_backend.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(10, 12, 16))

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

    var lamp = Object3D()
    lamp.set_position(0.55, 0.85, 0.7)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.63))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.67))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.2, 3.3), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(spin_frame(renderer, camera, assets, scene, node, step))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
