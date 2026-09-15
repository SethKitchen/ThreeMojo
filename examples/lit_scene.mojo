# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A checkerboard cube turning under a warm bulb, as an animated PNG.

    mojo run -I . examples/lit_scene.mojo

The finished program of the wiki tutorial "Light, texture and animate a
scene", whose source is docs/wiki/Tutorial-Light-texture-and-animate.md. The
tutorial explains each step; this file is the whole of it, so that the build
checks what the tutorial shows.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, point_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.texture import BILINEAR, REPEAT, checkerboard
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from units.si import Angle, DEGREE, Length, METER


def main() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var board = assets.textures.add(
        checkerboard(
            64,
            8,
            Color(245, 245, 250),
            Color(35, 70, 150),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var tiled = assets.materials.add(Material(Color(255, 255, 255), board))

    var scene = Scene()
    var block = Object3D()
    block.set_euler(Angle(25.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
    var node = scene.add(block^)
    scene.add_mesh(Mesh(box, tiled, node))

    var bulb = Object3D()
    bulb.set_position(0.8, 1.0, 1.5)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 220, 180), bulb_node, 1.5))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.15))

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 4.0 / 3.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0.6, 3), Vector3(0, 0, 0))

    var renderer = Renderer(320, 240, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var frames = List[Framebuffer]()
    var step = Angle(Float32(360) / Float32(36), DEGREE)
    for _ in range(36):
        scene.node(node).rotate_y(step)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))

    Path("out/lit_scene.png").write_bytes(encode(frames, delay_ms=60))
    print("Wrote out/lit_scene.png -", len(frames), "frames")
