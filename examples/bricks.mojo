# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An LDraw model of bricks turns under a lamp.

    mojo run -I . examples/bricks.mojo [path.png]

The page is More model files. `read_ldraw` builds `assets/ldraw/scene.mpd`
from the parts library beside it, and `load_ldraw` puts that model in the
scene. The root turns one whole turn.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from loaders.ldraw import load_ldraw, read_ldraw
from loaders.ldraw_parse import LDrawLoader
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import DEGREE, METER, Angle, Length, MILLISECOND

comptime DEFAULT_OUTPUT = "out/models.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime LIBRARY = "assets/ldraw/library/"


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    root: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the model by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the model.
        assets: The geometries and materials the loader built.
        scene: The persistent scene, edited in place.
        root: The model's root node.
        step: How much further the model turns.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(root).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var model = read_ldraw("assets/ldraw/scene.mpd", LDrawLoader(LIBRARY))
    var assets = Assets()
    var scene = Scene()
    load_ldraw(model, scene, assets)
    var root = model.scene_nodes[model.root]

    var lamp = Object3D()
    lamp.set_position(12, -16, 10)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.55))
    scene.add_light(
        directional_light(Color(255, 248, 236), scene.add(lamp^), 2.4)
    )

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(200.0, METER),
    )
    camera.place(Vector3(8, -7, 11), Vector3(0, 1.5, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, root, step))

    print(
        '{"frames_ms": ',
        frame_clock.elapsed().to(MILLISECOND),
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
