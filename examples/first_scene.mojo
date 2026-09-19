# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One lit cube, rendered to a PNG file.

    mojo run -I . examples/first_scene.mojo

The finished program of the wiki tutorial "Render your first scene", whose
source is docs/wiki/Tutorial-Render-your-first-scene.md. The tutorial
explains each step; this file is the whole of it, so that the build checks
what the tutorial shows.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.png import encode
from renderers.renderer import Renderer
from std.pathlib import Path
from units.si import Angle, DEGREE, Length, METER


def main() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var orange = assets.materials.add(Material(Color(255, 140, 40)))

    var scene = Scene()
    var block = Object3D()
    block.set_euler(
        Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE)
    )
    var node = scene.add(block^)
    scene.add_mesh(Mesh(box, orange, node))

    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.79))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.36))
    scene.update()

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 4.0 / 3.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))

    var renderer = Renderer(320, 240)
    renderer.set_background(Color(16, 18, 26))
    var image = renderer.render(scene, assets, camera)
    Path("out/first_scene.png").write_bytes(encode(image))
    print("Wrote out/first_scene.png")
