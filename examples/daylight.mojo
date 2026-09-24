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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.sky import Sky
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/sky.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

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

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(80.0, METER),
    )
    camera.place(Vector3(0, 0.25, 1.5), Vector3(0, 0.45, -1.6))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(0.35) + Float32(0.9) * Float32(index) / Float32(FRAMES - 1)
        var sun = Vector3(cos(turn), sin(turn) + 0.15, -0.2)
        assets.programs.get(sky.program).set_uniform("sunPosition", sun)
        scene.node(lamp_node).set_position(
            sun.x * 5, sun.y * 5, -1.6 + sun.z * 5
        )
        scene.update()
        frames.append(renderer.render(scene, assets, camera))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
