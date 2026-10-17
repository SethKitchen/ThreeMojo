# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube turning along a slerp, not by adding Euler angles.

    mojo run -I . examples/rotations.mojo [path.png]

`slerp` walks the short arc at a constant speed. Averaging four quaternion
numbers would speed up in the middle and stop being a rotation.
"""

from tools._example_output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    write_example,
)

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import Material
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.math import cos, pi
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/rotations.png"
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
    start: Quaternion,
    finish: Quaternion,
    t: Float32,
) raises -> Framebuffer:
    """Set the cube to a slerp of `start` toward `finish` and render.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        node: The cube's node.
        start: The rotation at t of zero.
        finish: The rotation at t of one.
        t: How far along the arc, zero to one.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).set_quaternion(start.slerp(finish, t))
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(1.1, METER)))
    var paint = assets.materials.add(Material(Color(255, 140, 40)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(block, paint, node))

    fill_and_key(
        scene,
        0.5,
        0.9,
        0.6,
        Color(255, 255, 255),
        0.69,
        Color(255, 255, 255),
        2.51,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(1.6, 1.1, 2.6),
        Vector3(0, 0, 0),
        field_of_view=Angle(45.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    var start = Quaternion.identity()
    var axis = Vector3(0.4, 1.0, 0.2)
    axis.normalize()
    var finish = Quaternion.from_axis_angle(axis, Angle(160.0, DEGREE))

    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        var t = Float32(0.5) - Float32(0.5) * cos(turn)
        frames.append(
            frame_at(renderer, camera, assets, scene, node, start, finish, t)
        )

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
