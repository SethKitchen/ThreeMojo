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

from examples.output import (
    example_destination,
    fill_and_key,
    framed_camera,
    gallery_renderer,
    write_example,
)

from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from exporters.object_json import write_object_json
from geometries.box import cube
from loaders.object_loader import ObjectCameras, load_object_json
from materials.material import Material
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from std.os import remove
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/scenejson.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var document = String(destination.removesuffix(".png")) + ".json"

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(0.9, METER)))
    var paint = assets.materials.add(Material(Color(230, 140, 50)))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(block, paint, node))
    fill_and_key(
        scene,
        0.9,
        1.4,
        1.2,
        Color(255, 255, 255),
        0.45,
        Color(255, 248, 236),
        2.6,
    )

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0.5, 0.15, 3.4)
    var eye_node = scene.attach(eye^, pivot)
    var camera = framed_camera(
        WIDTH,
        HEIGHT,
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(40.0, METER),
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

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        loaded.node(subject).rotate_y(step)
        loaded.update()
        frames.append(renderer.render(loaded, loaded_assets, camera_again))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
