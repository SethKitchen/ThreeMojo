# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box with a loop drawn around it and a path drawn through it.

    mojo run -I . examples/lines.mojo [path.png]

The page is Lines. The loop closes and the path does not, which is the
whole of the difference between `LOOP` and `STRIP`. Both turn with the
box, so the segments pass in front of the surface and then behind it.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.line import LOOP, STRIP, Line
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/lines.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
# How far the loop stands outside the box, so it reads as a ring around
# the shape rather than as an edge lying on it.
comptime RING = Float32(0.95)


def a_ring(sides: Int) raises -> BufferGeometry:
    """Return the points of a regular polygon in the xz plane.

    Args:
        sides: How many points to put around the circle.

    Returns:
        A geometry holding them in order, for a `LOOP` to close.

    Raises:
        Error: If the points do not divide into vertices.
    """
    var numbers = List[Float32]()
    for point in range(sides):
        var turn = 2 * pi * Float32(point) / Float32(sides)
        numbers.append(RING * cos(turn))
        numbers.append(0)
        numbers.append(RING * sin(turn))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


def a_rising_path(steps: Int) raises -> BufferGeometry:
    """Return a path climbing through the box, for a `STRIP` to join.

    Args:
        steps: How many points the path holds.

    Returns:
        A geometry holding them in order.

    Raises:
        Error: If the points do not divide into vertices.
    """
    var numbers = List[Float32]()
    for point in range(steps):
        var share = Float32(point) / Float32(steps - 1)
        var turn = 3 * pi * share
        numbers.append(0.7 * cos(turn))
        numbers.append(1.6 * share - 0.8)
        numbers.append(0.7 * sin(turn))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the group by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometries and materials.
        scene: The persistent scene, edited in place.
        node: The node the box and both lines hang from.
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
    var box = assets.geometries.add(cube(Length(1.1, METER)))
    var ring = assets.geometries.add(a_ring(24))
    var path = assets.geometries.add(a_rising_path(40))
    var paint = assets.materials.add(Material(Color(70, 110, 200)))
    # A line is unlit and untextured, so its material is `BASIC`. See
    # `objects.line`.
    var gold = assets.materials.add(Material(Color(255, 205, 70), kind=BASIC))
    var white = assets.materials.add(Material(Color(240, 240, 255), kind=BASIC))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(box, paint, node))
    scene.add_line(Line(ring, gold, node, mode=LOOP))
    scene.add_line(Line(path, white, node, mode=STRIP))

    var lamp = Object3D()
    lamp.set_position(0.5, 0.9, 0.8)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.8))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.7, 3.6), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
