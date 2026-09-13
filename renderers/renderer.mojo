# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draws a scene through a camera, the counterpart to three.js's renderers.

The loop here is the one both cube examples had grown by hand: take each
mesh's world transform, project its vertices, and rasterize its triangles with
depth. Having it in one place is what lets an example say `render(scene,
meshes, camera)` instead of spelling all that out.

Shading is flat: one colour per triangle, from the angle between its face and
a fixed light. The normal is computed from the triangle's own world-space
corners with a cross product rather than read from the geometry, because there
is no `normal` attribute yet. That makes it a *geometric* normal — faceted by
construction, which is right for a cube and would look wrong on a sphere, where
per-vertex normals smoothed across the surface are what is wanted.

There is no backface culling. Faces pointing away light to ambient and are
covered by nearer geometry anyway, so the depth buffer alone gives the correct
image. Culling would be an optimization, not a correctness fix, which is only
true because the depth buffer exists.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.buffer_geometry import POSITION
from core.scene import Scene
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.rasterizer import rasterize_depth
from std.math import max


def face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    """Return the unit normal of the triangle, or zero if it is degenerate.

    Wound counter-clockwise seen from the front, so the normal points at the
    viewer for a front-facing triangle.
    """
    var first = b
    first.sub(a)
    var second = c
    second.sub(a)
    first.cross(second)
    # normalize leaves a zero vector alone, so a degenerate triangle gives a
    # zero normal rather than a division by zero.
    first.normalize()
    return first^


def _scale(channel: UInt8, level: Float32) -> UInt8:
    """Return `channel` multiplied by `level`, rounded rather than truncated.

    Truncating costs a level everywhere: a face square-on to the light has a
    Lambert term of 0.99999 rather than 1, and converting that straight to an
    integer turns 200 into 199. Every shaded pixel would come out fractionally
    darker than asked for.
    """
    var scaled = Float32(channel) * level + 0.5
    if scaled > 255:
        return 255
    return UInt8(scaled)


struct Renderer(Movable):
    """Renders a scene to a framebuffer of a fixed size."""

    var width: Int
    var height: Int
    var background: Color
    var light: Vector3
    var ambient: Float32

    def __init__(out self, width: Int, height: Int) raises:
        """Create a renderer with a dark background and a default light.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.

        Raises:
            Error: If either dimension is not positive.
        """
        if width <= 0 or height <= 0:
            raise Error("Renderer dimensions must be positive")
        self.width = width
        self.height = height
        self.background = Color(16, 18, 26)
        # Pointing from the scene towards the light, up and to the right.
        var direction = Vector3(0.4, 0.8, 0.5)
        direction.normalize()
        self.light = direction
        # Enough fill that a face turned away is still legible, not black.
        self.ambient = 0.25

    def set_background(mut self, color: Color):
        """Set the colour the image is cleared to."""
        self.background = color

    def set_light(mut self, direction: Vector3, ambient: Float32) raises:
        """Point the light and set how much the unlit side keeps.

        Args:
            direction: From the scene towards the light; normalized here.
            ambient: Fraction of the base colour a face turned away keeps.

        Raises:
            Error: If the direction has no length, or ambient is outside
                zero to one.
        """
        if direction.length() == 0:
            raise Error("The light needs a direction")
        if ambient < 0 or ambient > 1:
            raise Error("Ambient light must be between zero and one")
        var pointing = direction
        pointing.normalize()
        self.light = pointing
        self.ambient = ambient

    def shade(self, base: Color, normal: Vector3) -> Color:
        """Return `base` dimmed by how far the face is turned from the light.

        A face turned away keeps the ambient fraction rather than going black,
        because a scene lit by one light and nothing else reads as broken.
        """
        var lambert = max(Float32(0), normal.dot(self.light))
        var level = self.ambient + (1 - self.ambient) * lambert
        return Color(
            _scale(base.r, level),
            _scale(base.g, level),
            _scale(base.b, level),
            base.a,
        )

    def render(
        self, scene: Scene, meshes: List[Mesh], camera: PerspectiveCamera
    ) raises -> Framebuffer:
        """Draw every mesh and return the finished image.

        `scene.update()` must have been called since the last transform
        change; this reads world matrices rather than recomputing them, so a
        stale scene renders stale positions.

        Args:
            scene: The transform hierarchy the meshes sit in.
            meshes: What to draw, each naming a node in `scene`.
            camera: The camera to project through.

        Returns:
            The rendered image.

        Raises:
            Error: If a mesh names a node the scene does not have, or its
                geometry has no positions.
        """
        var target = Framebuffer(self.width, self.height, self.background)

        for index in range(len(meshes)):
            var world = scene.world_matrix(meshes[index].node)

            # World positions are kept as well as screen ones: shading needs
            # the triangle's real shape, which the projection does not
            # preserve.
            var positions = meshes[index].geometry.attribute(String(POSITION))
            var world_points = List[Vector3]()
            var screen_points = List[Vector3]()
            for vertex in range(positions.count()):
                var point = world.transform_point(positions.vector3(vertex))
                screen_points.append(
                    camera.project(point, self.width, self.height)
                )
                world_points.append(point)

            var triangles = meshes[index].geometry.triangle_count()
            for triangle in range(triangles):
                var first = meshes[index].geometry.corner_index(triangle, 0)
                var second = meshes[index].geometry.corner_index(triangle, 1)
                var third = meshes[index].geometry.corner_index(triangle, 2)
                var normal = face_normal(
                    world_points[first],
                    world_points[second],
                    world_points[third],
                )
                rasterize_depth(
                    screen_points[first],
                    screen_points[second],
                    screen_points[third],
                    target,
                    self.shade(meshes[index].color, normal),
                )

        return target^
