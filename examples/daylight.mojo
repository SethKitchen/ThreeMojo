# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A daylight sky around a sphere, with the sun crossing overhead.

    mojo run -I . examples/daylight.mojo [path.png]

The page is Scene objects. `Sky` is Preetham's model on a box seen from
inside. The sun position is a uniform. The sphere sits in the light so
the sky has something to shine on.
"""

from examples.output import example_destination, gallery_camera, write_example

from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.sky import Sky
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, sin
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/sky.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(8, 12, 20))
    var assets = Assets()
    var scene = Scene()

    var dome = Object3D()
    dome.set_scale(40, 40, 40)
    var sky_node = scene.add(dome^)
    var sky = Sky(assets, sky_node)
    scene.add_mesh(sky.mesh)

    var ball = assets.geometries.add(sphere(Length(0.55, METER), 32, 20))
    var paint = assets.materials.add(Material(Color(210, 200, 185)))
    var stand = Object3D()
    stand.set_position(0, 0.15, -1.6)
    scene.add_mesh(Mesh(ball, paint, scene.add(stand^)))

    var lamp = Object3D()
    lamp.set_position(4, 2, -1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(180, 200, 230), 0.45))
    scene.add_light(directional_light(Color(255, 244, 220), lamp_node, 2.4))

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0.25, 1.5),
        Vector3(0, 0.45, -1.6),
        field_of_view=Angle(50.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(80.0, METER),
    )

    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(0.35) + Float32(0.9) * Float32(index) / Float32(
            FRAMES - 1
        )
        var sun = Vector3(cos(turn), sin(turn) + 0.15, -0.2)
        assets.programs.get(sky.program).set_uniform("sunPosition", sun)
        scene.node(lamp_node).set_position(
            sun.x * 5, sun.y * 5, -1.6 + sun.z * 5
        )
        scene.update()
        frames.append(renderer.render(scene, assets, camera))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
