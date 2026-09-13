# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two cubes orbiting on a scene graph, drawn with a depth buffer.

    mojo run -I . examples/cubes.mojo [path.png]

`examples/cube.mojo` drew one convex cube and relied on backface culling to
hide what was behind. That trick only works for a single convex solid. Here a
small cube orbits a large one and passes behind it, so the correct image
depends on comparing depth per pixel — and there is deliberately no culling at
all, to show the depth buffer carrying the whole result on its own.

The orbit comes from the scene graph rather than from arithmetic here: the
small cube is a child of a spinning pivot, so rotating the pivot carries it
around. That is the entire point of a transform hierarchy.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.object3d import Object3D
from core.scene import Scene
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.rasterizer import rasterize_depth
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METRE

comptime DEFAULT_OUTPUT = "out/cubes.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 48
comptime DELAY_MS = 50


def corners(half: Float32) -> List[Vector3]:
    """Return the eight corners of a cube of the given half-extent."""
    var points = List[Vector3]()
    points.append(Vector3(-half, -half, -half))
    points.append(Vector3(half, -half, -half))
    points.append(Vector3(half, half, -half))
    points.append(Vector3(-half, half, -half))
    points.append(Vector3(-half, -half, half))
    points.append(Vector3(half, -half, half))
    points.append(Vector3(half, half, half))
    points.append(Vector3(-half, half, half))
    return points^


def add_face(mut indices: List[Int], a: Int, b: Int, c: Int, d: Int):
    """Append the two triangles of a quad face."""
    indices.append(a)
    indices.append(b)
    indices.append(c)
    indices.append(a)
    indices.append(c)
    indices.append(d)


def faces() -> List[Int]:
    """Return the cube's twelve triangles as corner indices."""
    var indices = List[Int]()
    add_face(indices, 4, 5, 6, 7)  # front  (+z)
    add_face(indices, 1, 0, 3, 2)  # back   (-z)
    add_face(indices, 0, 4, 7, 3)  # left   (-x)
    add_face(indices, 5, 1, 2, 6)  # right  (+x)
    add_face(indices, 3, 7, 6, 2)  # top    (+y)
    add_face(indices, 0, 1, 5, 4)  # bottom (-y)
    return indices^


def shade(face: Int, base: Color) -> Color:
    """Return `base` dimmed per face, so the cube's sides are told apart."""
    var levels = List[Float32]()
    levels.append(1.0)
    levels.append(0.45)
    levels.append(0.6)
    levels.append(0.85)
    levels.append(0.75)
    levels.append(0.35)
    var level = levels[(face // 2) % 6]
    return Color(
        UInt8(Float32(base.r) * level),
        UInt8(Float32(base.g) * level),
        UInt8(Float32(base.b) * level),
    )


def draw_cube(
    mut target: Framebuffer,
    camera: PerspectiveCamera,
    world: Matrix4,
    half: Float32,
    base: Color,
) raises:
    """Draw one cube under `world`, letting the depth buffer sort it out.

    Args:
        target: The framebuffer to draw into.
        camera: The camera to project through.
        world: The cube's world transform.
        half: Half the cube's edge length.
        base: The cube's colour before per-face shading.

    Raises:
        Error: If projection or rasterization fails.
    """
    var points = corners(half)
    var indices = faces()

    var screen = List[Vector3]()
    for index in range(len(points)):
        screen.append(
            camera.project(world.transform_point(points[index]), WIDTH, HEIGHT)
        )

    # No backface culling: every triangle is submitted, and depth decides.
    for face in range(len(indices) // 3):
        rasterize_depth(
            screen[indices[face * 3]],
            screen[indices[face * 3 + 1]],
            screen[indices[face * 3 + 2]],
            target,
            shade(face, base),
        )


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 1.2, 4.5), Vector3(0, 0, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(360) * Float32(index) / Float32(FRAMES)

        # A pivot at the origin, with the small cube parented 1.6 m out. The
        # orbit is the pivot's rotation; nothing here computes a position.
        var scene = Scene()
        var pivot = Object3D()
        pivot.set_euler(
            Angle(0.0, DEGREE), Angle(turn, DEGREE), Angle(0.0, DEGREE)
        )
        var pivot_index = scene.add(pivot^)

        var centre = Object3D()
        centre.set_euler(
            Angle(20.0, DEGREE), Angle(turn / 2, DEGREE), Angle(0.0, DEGREE)
        )
        var centre_index = scene.add(centre^)

        var moon = Object3D()
        moon.set_position(1.6, 0, 0)
        moon.set_euler(
            Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(turn * 2, DEGREE)
        )
        var moon_index = scene.attach(moon^, pivot_index)

        scene.update()

        var target = Framebuffer(WIDTH, HEIGHT, Color(16, 18, 26))
        draw_cube(
            target,
            camera,
            scene.world_matrix(centre_index),
            0.55,
            Color(255, 140, 40),
        )
        draw_cube(
            target,
            camera,
            scene.world_matrix(moon_index),
            0.22,
            Color(90, 190, 255),
        )
        frames.append(target^)

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
