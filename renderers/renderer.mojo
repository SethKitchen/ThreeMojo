# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draws a scene through a camera, the counterpart to three.js's renderers.

The loop here is the one both cube examples had grown by hand: take each
mesh's world transform, project its vertices, and rasterize its triangles with
depth. Having it in one place is what lets an example say `render(scene,
meshes, camera)` instead of spelling all that out.

Lighting is evaluated per vertex and interpolated across the triangle, which
is Gouraud shading. A geometry's `normal` attribute decides how it looks: a
box gives each of a face's four corners that face's own normal, so the four
agree and the face comes out flat with a crisp edge; a sphere gives each
vertex the direction it points from the centre, so neighbouring triangles
agree along their shared edge and the facets disappear.

A geometry with no normals falls back to the triangle's *geometric* normal,
computed from its own world-space corners with a cross product. That is always
faceted, which is the honest result for geometry that never said which way it
faces.

Normals are rotated by the world matrix but not translated, since a direction
has no position. Non-uniform scale would need the inverse transpose to stay
perpendicular; that is not handled, and is noted rather than hidden.

Vertices are taken into camera space and cut against the near plane *before*
being projected. Projecting first would divide by a depth of zero or a
negative one for anything level with or behind the camera, which does not
produce a slightly wrong triangle but a wildly wrong one. See `renderers.clip`.

There is no backface culling. Faces pointing away light to ambient and are
covered by nearer geometry anyway, so the depth buffer alone gives the correct
image. Culling would be an optimization, not a correctness fix, which is only
true because the depth buffer exists.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.buffer_geometry import NORMAL, POSITION
from core.scene import Scene
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.rasterizer import rasterize_shaded
from renderers.clip import ClipVertex, clip_near
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
        var view = camera.view_matrix()
        var to_screen = camera.view_to_screen_matrix(self.width, self.height)
        var near = camera.near.value

        for index in range(len(meshes)):
            var world = scene.world_matrix(meshes[index].node)
            var positions = meshes[index].geometry.attribute(String(POSITION))
            var smooth = meshes[index].geometry.has_attribute(String(NORMAL))

            # World positions are kept as well as camera-space ones: a
            # geometric normal needs the triangle's real shape, and the view
            # transform is where clipping has to happen.
            var world_points = List[Vector3]()
            var view_points = List[Vector3]()
            var vertex_colors = List[Color]()
            for vertex in range(positions.count()):
                var point = world.transform_point(positions.vector3(vertex))
                world_points.append(point)
                view_points.append(view.transform_point(point))
                if smooth:
                    # transform_direction ignores translation, which is what a
                    # normal wants: it points somewhere, it is not somewhere.
                    var direction = world.transform_direction(
                        meshes[index]
                        .geometry.attribute(String(NORMAL))
                        .vector3(vertex)
                    )
                    direction.normalize()
                    vertex_colors.append(
                        self.shade(meshes[index].color, direction)
                    )

            var triangles = meshes[index].geometry.triangle_count()
            for triangle in range(triangles):
                var first = meshes[index].geometry.corner_index(triangle, 0)
                var second = meshes[index].geometry.corner_index(triangle, 1)
                var third = meshes[index].geometry.corner_index(triangle, 2)

                var color_a: Color
                var color_b: Color
                var color_c: Color
                if smooth:
                    color_a = vertex_colors[first]
                    color_b = vertex_colors[second]
                    color_c = vertex_colors[third]
                else:
                    # No normals given, so the face supplies its own and the
                    # whole triangle takes one colour.
                    color_a = self.shade(
                        meshes[index].color,
                        face_normal(
                            world_points[first],
                            world_points[second],
                            world_points[third],
                        ),
                    )
                    color_b = color_a
                    color_c = color_a

                var pieces = clip_near(
                    ClipVertex(view_points[first], color_a),
                    ClipVertex(view_points[second], color_b),
                    ClipVertex(view_points[third], color_c),
                    near,
                )
                for piece in range(len(pieces) // 3):
                    var one = pieces[piece * 3]
                    var two = pieces[piece * 3 + 1]
                    var three = pieces[piece * 3 + 2]
                    rasterize_shaded(
                        to_screen.transform_point(one.position),
                        to_screen.transform_point(two.position),
                        to_screen.transform_point(three.position),
                        one.color,
                        two.color,
                        three.color,
                        target,
                    )

        return target^
