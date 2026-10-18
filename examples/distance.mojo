# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sphere shows its distance from a point, packed into color.

    mojo run -I . examples/distance.mojo [path.png]

The page is Materials. `distance_material` writes how far each fragment
is from a reference point. The fraction is packed into four channels, so
the sphere is banded rather than a smooth gray. It turns in place.
"""

from examples.output import example_destination, spin_frame, write_example

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import distance_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/distance.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(12, 14, 20))
    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 40, 28))
    var measured = assets.materials.add(
        distance_material(
            Vector3(0.4, 1.1, 0.8),
            Length(0.2, METER),
            Length(2.4, METER),
        )
    )

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, measured, node))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.2, 0.3, 3.1), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(spin_frame(renderer, camera, assets, scene, node, step))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
