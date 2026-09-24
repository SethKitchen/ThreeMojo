# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Three cubes in a fog. The middle one keeps its color.

    mojo run -I . examples/unfogged.mojo [path.png]

The page is Materials. The scene fog veils by distance. The middle cube
has `fog` off, so it stays orange while the other two fade. The camera
walks in and back.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.fog import linear_fog
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/unfogged.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var fog_color = Color(170, 178, 190)
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(fog_color)
    var assets = Assets()
    var block = assets.geometries.add(cube(Length(0.7, METER)))
    var faded = assets.materials.add(Material(Color(230, 140, 40)))
    var clear = Material(Color(230, 140, 40), fog=False)
    var kept = assets.materials.add(clear^)

    var scene = Scene()
    scene.fog = linear_fog(fog_color, Length(2.2, METER), Length(9.0, METER))
    var near = Object3D()
    near.set_position(-1.15, 0, 0.4)
    scene.add_mesh(Mesh(block, faded, scene.add(near^)))
    var mid = Object3D()
    mid.set_position(0, 0, -1.5)
    scene.add_mesh(Mesh(block, kept, scene.add(mid^)))
    var far = Object3D()
    far.set_position(1.05, 0, -2.2)
    scene.add_mesh(Mesh(block, faded, scene.add(far^)))

    var lamp = Object3D()
    lamp.set_position(0.6, 1.4, 2.0)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.55))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.2))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(40.0, METER),
    )

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        var depth = Float32(4.2) + Float32(1.6) * cos(turn)
        camera.place(Vector3(0, 0.45, depth), Vector3(0, 0, -1.2))
        scene.update()
        frames.append(renderer.render(scene, assets, camera))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
