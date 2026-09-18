# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tube swept along one cubic Bezier curve.

    mojo run -I . examples/curves.mojo [path.png]

The curve is sampled, lifted into space, and given thickness. The page is
Curves. This file draws that one path, not a set of kinds.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.tube import tube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.curve import cubic_bezier
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/curves.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the tube by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        node: The tube's node.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var bend = cubic_bezier(
        Vector2(-1.3, -0.85),
        Vector2(-0.3, 1.25),
        Vector2(0.3, -1.25),
        Vector2(1.3, 0.85),
    )
    var samples = bend.sample(28)
    var path = List[Vector3]()
    for point in samples:
        path.append(Vector3(point.x, point.y, 0))

    var assets = Assets()
    var hose = assets.geometries.add(tube(path, Length(0.13, METER), 8, False))
    var paint = assets.materials.add(Material(Color(255, 170, 70)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(hose, paint, node))

    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.9)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.22))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.85))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.15, 3.5), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
