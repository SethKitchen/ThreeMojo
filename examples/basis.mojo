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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.ktx2 import read
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/ktx2.png"
comptime WIDTH = 320
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    pivot: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the panels by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the panels.
        assets: The planes and the decoded textures.
        scene: The persistent scene, edited in place.
        pivot: The node the panels ride.
        step: How much further they turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(pivot).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
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
    var camera = PerspectiveCamera(
        Angle(36.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0, 0, 3.2), Vector3(0, 0, 0))

    var step = Angle(Float32(20) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
