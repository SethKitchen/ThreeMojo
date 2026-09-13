# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Render a spinning 3D cube to an animated PNG.

    mojo run -I . examples/cube.mojo [path.png]

This is the first example that draws a *scene* rather than screen-space
shapes: world-space corners in metres, turned by a model matrix, projected by
the camera, and rasterized where they land in pixels.

There is no depth buffer yet, so hidden faces are dealt with by backface
culling instead: a face whose screen-space winding has reversed is pointing
away and is skipped. For a convex solid like a cube that is exactly right, and
it costs one sign test that `Triangle.area2` already computes. A concave model,
or two objects overlapping, would need real depth.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.buffer_geometry import POSITION, BufferGeometry
from geometries.box import cube as cube_geometry
from math.matrix4 import Matrix4, rotation_x, rotation_y
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.rasterizer import Triangle, rasterize
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METRE

comptime DEFAULT_OUTPUT = "out/cube.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def face_color(face: Int) -> Color:
    """Return a distinct colour per cube face, two triangles at a time."""
    var palette = List[Color]()
    palette.append(Color(255, 128, 32))
    palette.append(Color(64, 160, 255))
    palette.append(Color(120, 220, 120))
    palette.append(Color(240, 200, 60))
    palette.append(Color(200, 100, 220))
    palette.append(Color(240, 90, 90))
    return palette[(face // 2) % 6]


def frame_at(
    camera: PerspectiveCamera, geometry: BufferGeometry, model: Matrix4
) raises -> Framebuffer:
    """Render one frame of the cube under the given model transform.

    Args:
        camera: The camera to project through.
        geometry: The cube's vertex data.
        model: The cube's world transform for this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If projection or rasterization fails.
    """
    var target = Framebuffer(WIDTH, HEIGHT, Color(18, 20, 28))

    # Project every vertex once, then reuse it for each face that shares it.
    ref positions = geometry.attribute_view(POSITION)
    var screen = List[Vector3]()
    for vertex in range(positions.count()):
        screen.append(
            camera.project(
                model.transform_point(positions.vector3(vertex)),
                WIDTH,
                HEIGHT,
            )
        )

    for face in range(geometry.triangle_count()):
        var a = screen[geometry.corner_index(face, 0)]
        var b = screen[geometry.corner_index(face, 1)]
        var c = screen[geometry.corner_index(face, 2)]
        var triangle = Triangle(
            Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y)
        )
        # Screen y runs downwards, which flips the sign of the winding, so a
        # face pointing at us reads as negative area here.
        if triangle.area2() < 0:
            rasterize(triangle, target, face_color(face))

    return target^


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 0, 2.5), Vector3(0, 0, 0))

    var geometry = cube_geometry(Length(1.0, METRE))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(360) * Float32(index) / Float32(FRAMES)
        var model = rotation_y(Angle(turn, DEGREE))
        model.premultiply(rotation_x(Angle(20.0, DEGREE)))
        frames.append(frame_at(camera, geometry, model))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
