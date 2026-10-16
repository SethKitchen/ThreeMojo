# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Three KTX2 images, decoded and shown on panels.

    mojo run -I . examples/basis.mojo [path.png]

The page is Textures. The left panel is UASTC stored with Zstandard.
The middle panel is ETC1S. The right panel is a UASTC gradient. Each
file is decoded to bytes and sampled as an ordinary texture. The panels
turn together.
"""

from examples.output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
    spin_frame,
    write_example,
)

from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.ktx2 import read
from std.pathlib import Path
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/ktx2.png"
comptime WIDTH = 320
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var assets = Assets()
    var card = assets.geometries.add(
        plane(Length(0.9, METER), Length(0.9, METER))
    )
    var paths = List[String]()
    paths.append("assets/ktx2/uastc_rgb_zstd_mips.ktx2")
    paths.append("assets/ktx2/etc1s_rgb.ktx2")
    paths.append("assets/ktx2/uastc_gradient.ktx2")
    var scene = Scene()
    var pivot = scene.add(Object3D())
    for index in range(3):
        var decoded = read(Path(paths[index]).read_bytes())
        var image = assets.textures.add(decoded.texture())
        var paint = assets.materials.add(
            Material(Color(255, 255, 255), image, kind=BASIC)
        )
        var stand = Object3D()
        stand.set_position((Float32(index) - 1) * 1.05, 0, 0)
        var node = scene.attach(stand^, pivot)
        scene.add_mesh(Mesh(card, paint, node))

    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0, 3.2),
        Vector3(0, 0, 0),
        field_of_view=Angle(36.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(20.0, METER),
    )

    var step = Angle(Float32(20) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(spin_frame(renderer, camera, assets, scene, pivot, step))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
