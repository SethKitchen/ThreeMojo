# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A knot written to a glTF file, read back, and turned under a lamp.

    mojo run -I . examples/reloaded.mojo [path.png]

The page is Exporters. `write_gltf` writes the mesh and its material.
`read_gltf` builds them again. The lamp is added after the read, because
a glTF file from this writer does not carry lights.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from exporters.gltf import GLB, write_gltf
from geometries.torus import torus_knot
from lights.light import ambient_light, directional_light
from loaders.gltf import read_gltf
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.os import remove
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/exporters.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var document = String(destination.removesuffix(".png")) + ".glb"

    var assets = Assets()
    var knot = assets.geometries.add(
        torus_knot(Length(0.62, METER), Length(0.18, METER), 72, 10)
    )
    var paint = assets.materials.add(Material(Color(70, 150, 220)))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(knot, paint, node))
    scene.update()
    write_gltf(document, scene, assets, GLB)

    var loaded = Scene()
    var loaded_assets = Assets()
    _ = read_gltf(document, loaded, loaded_assets)
    remove(document)
    var subject = loaded.meshes[0].node

    var lamp = Object3D()
    lamp.set_position(0.8, 1.3, 1.4)
    var lamp_node = loaded.add(lamp^)
    loaded.add_light(ambient_light(Color(255, 255, 255), 0.4))
    loaded.add_light(directional_light(Color(255, 250, 240), lamp_node, 2.5))

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(40.0, METER),
    )
    camera.place(Vector3(0.3, 0.7, 3.2), Vector3(0, 0, 0))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        loaded.node(subject).rotate_y(step)
        loaded.update()
        frames.append(renderer.render(loaded, loaded_assets, camera))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
