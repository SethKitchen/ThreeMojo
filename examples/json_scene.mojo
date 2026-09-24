# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube written as three.js JSON, read back, and turned.

    mojo run -I . examples/json_scene.mojo [path.png]

The page is Scene JSON. The scene, its lamp and its camera are written
with `write_object_json` and read with `load_object_json`. The picture
is the scene that came back, not the one that was written.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from exporters.object_json import write_object_json
from geometries.box import cube
from lights.light import ambient_light, directional_light
from loaders.object_loader import ObjectCameras, load_object_json
from materials.material import Material
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.os import remove
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/scenejson.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var document = String(destination.removesuffix(".png")) + ".json"

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(0.9, METER)))
    var paint = assets.materials.add(Material(Color(230, 140, 50)))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(block, paint, node))
    var lamp = Object3D()
    lamp.set_position(0.9, 1.4, 1.2)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.45))
    scene.add_light(directional_light(Color(255, 248, 236), lamp_node, 2.6))

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0.5, 0.15, 3.4)
    var eye_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(40.0, METER),
    )
    camera.attach(eye_node)
    scene.update()

    var cameras = ObjectCameras()
    cameras.perspective.append(camera)
    write_object_json(document, scene, assets, cameras)

    var loaded = Scene()
    var loaded_assets = Assets()
    var model = load_object_json(document, loaded, loaded_assets)
    var camera_again = model.cameras.perspective[0]
    var subject = loaded.meshes[0].node
    remove(document)

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        loaded.node(subject).rotate_y(step)
        loaded.update()
        frames.append(renderer.render(loaded, loaded_assets, camera_again))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
