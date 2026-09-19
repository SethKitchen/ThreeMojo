# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One geometry drawn eight times from one InstancedMesh.

    mojo run -I . examples/instances.mojo [path.png]

The copies sit on a ring. The node they share turns, so the ring turns with
it. Nothing here is eight Mesh objects.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.matrix4 import rotation_y, translation
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER, RADIAN

comptime DEFAULT_OUTPUT = "out/instances.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime COUNT = 8
comptime RADIUS = Float32(1.35)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the shared node by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        node: The node every instance is relative to.
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

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(0.42, METER)))
    var paint = assets.materials.add(Material(Color(255, 160, 60)))

    var scene = Scene()
    var node = scene.add(Object3D())
    var group = InstancedMesh(block, paint, node, COUNT)
    for index in range(COUNT):
        var angle = Float32(2) * Float32(pi) * Float32(index) / Float32(COUNT)
        var placed = translation(RADIUS * cos(angle), 0, RADIUS * sin(angle))
        placed.premultiply(rotation_y(Angle(angle, RADIAN)))
        group.set_matrix_at(index, placed)
    scene.add_instanced_mesh(group^)

    var lamp = Object3D()
    lamp.set_position(0.4, 1.1, 0.7)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.69))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 2.1, 3.6), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
