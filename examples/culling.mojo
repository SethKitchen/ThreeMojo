# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube sliding through a tight frustum, gone when its bound is outside.

    mojo run -I . examples/culling.mojo [path.png]

The renderer skips a mesh whose bounding sphere misses the view, before a
vertex of it is transformed. The cube vanishes at the edge and comes back.
That is frustum culling, not clipping.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
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

comptime DEFAULT_OUTPUT = "out/culling.png"
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
    x: Float32,
) raises -> Framebuffer:
    """Place the cube at `x` meters and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: A tight frustum aimed at the origin.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        node: The cube's node.
        x: How far left or right the cube sits, in meters.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).set_position(x, 0, 0)
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
    var block = assets.geometries.add(cube(Length(0.7, METER)))
    var paint = assets.materials.add(Material(Color(255, 140, 40)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(block, paint, node))

    var lamp = Object3D()
    lamp.set_position(0.3, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.69))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))

    var camera = PerspectiveCamera(
        Angle(22.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.2, 4.2), Vector3(0, 0, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        var x = Float32(2.6) * cos(turn)
        frames.append(frame_at(renderer, camera, assets, scene, node, x))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
