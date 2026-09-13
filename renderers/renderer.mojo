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

Normals are carried by the world matrix's *normal matrix* — the inverse
transpose of its rotation and scale part — rather than by the world matrix
itself. Under a uniform scale the two agree up to a length that normalizing
removes, which is why the simpler version worked for as long as it did. Under
a non-uniform scale they do not: `Object3D.set_scale` takes three separate
factors, so the transform API could always reach a state the naive version
shaded wrongly. It is computed once per mesh, not once per vertex.

Vertices are taken into camera space and cut against the near and far planes
*before* being projected. Projecting first would divide by a depth of zero or a
negative one for anything level with or behind the camera, which does not
produce a slightly wrong triangle but a wildly wrong one. The far plane is cut
too, because the depth buffer cannot enforce it on its own: it clears to
infinity and accepts anything smaller, so geometry past `camera.far` would
otherwise still be drawn. See `renderers.clip`.

There is no backface culling. Faces pointing away light to ambient and are
covered by nearer geometry anyway, so the depth buffer alone gives the correct
image. Culling would be an optimization, not a correctness fix, which is only
true because the depth buffer exists.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.buffer_geometry import NORMAL, POSITION
from core.geometry_store import GeometryStore
from core.scene import Scene
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rasterizer import RasterVertex, rasterize_shaded
from renderers.clip import ClipVertex, clip_depth
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


def _to_raster(vertex: ClipVertex, to_screen: Matrix4) -> RasterVertex:
    """Project a clipped camera-space vertex into the rasterizer's input.

    `transform_point` does the perspective divide and throws the divisor away,
    which is all a position needs. Anything interpolated *alongside* the
    position needs the divisor too, so it is asked for separately and kept as
    its reciprocal — see `RasterVertex`.
    """
    var w = to_screen.transform_w(vertex.position)
    var inv_w = Float32(0)
    # Clipping has already removed everything at or behind the near plane, so
    # w is positive here. The guard costs nothing and keeps a degenerate
    # camera from producing infinities rather than a visible error.
    if w != 0:  # pragma: no branch
        inv_w = Float32(1) / w
    var screen = to_screen.transform_point(vertex.position)
    return RasterVertex(screen.x, screen.y, screen.z, inv_w, vertex.color)


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

    def shade(self, base: Color, normal: Vector3) -> FloatColor:
        """Return `base` dimmed by how far the face is turned from the light.

        A face turned away keeps the ambient fraction rather than going black,
        because a scene lit by one light and nothing else reads as broken.

        The result stays in floating point. It is about to be interpolated
        across a triangle and possibly cut by a clipping plane first, and
        rounding to eight bits before either of those throws away precision
        that those steps would have used.
        """
        var lambert = max(Float32(0), normal.dot(self.light))
        var level = self.ambient + (1 - self.ambient) * lambert
        return FloatColor(of=base).scaled(level)

    def prepare(
        self,
        scene: Scene,
        geometries: GeometryStore,
        meshes: List[Mesh],
        camera: PerspectiveCamera,
    ) raises -> List[RasterVertex]:
        """Turn a scene into the triangles a rasterizer can fill.

        Everything that is not filling pixels happens here: world transforms,
        lighting, clipping and projection. What comes out is the boundary
        between the two halves of the renderer — screen-space triangles with
        their varyings already worked out — and it is the *same* boundary
        whichever rasterizer consumes it. The CPU one is `render` below; the
        GPU one is `render.gpu`, which takes exactly this list.

        Keeping it a separate step is what makes the two backends comparable
        rather than merely similar: a parity test can hand both the identical
        input and demand identical output.

        `scene.update()` must have been called since the last transform
        change; this reads world matrices rather than recomputing them, so a
        stale scene renders stale positions.

        Args:
            scene: The transform hierarchy the meshes sit in.
            geometries: The vertex data the meshes name. Two meshes naming
                the same id share one copy of it.
            meshes: What to draw, each naming a node and a geometry.
            camera: The camera to project through.

        Returns:
            Raster vertices, three per triangle, in submission order.

        Raises:
            Error: If a mesh names a node or a geometry that is not there, or
                its geometry has no positions.
        """
        var corners = List[RasterVertex]()
        var view = camera.view_matrix()
        var to_screen = camera.view_to_screen_matrix(self.width, self.height)
        var near = camera.near.value
        var far = camera.far.value

        for index in range(len(meshes)):
            var world = scene.world_matrix(meshes[index].node)
            # Borrowed, not copied: two meshes naming the same id read the
            # same arrays rather than each holding their own.
            ref geometry = geometries.get(meshes[index].geometry)
            var smooth = geometry.has_attribute(String(NORMAL))

            # World positions are kept as well as camera-space ones: a
            # geometric normal needs the triangle's real shape, and the view
            # transform is where clipping has to happen.
            var world_points = List[Vector3]()
            var view_points = List[Vector3]()
            # `ref` and not `var`: this borrows the geometry's array rather
            # than copying it. Writing `var` here is a compile error, which is
            # the point of the two accessors.
            ref positions = geometry.attribute_view(String(POSITION))
            var vertex_count = positions.count()
            for vertex in range(vertex_count):
                var point = world.transform_point(positions.vector3(vertex))
                world_points.append(point)
                view_points.append(view.transform_point(point))

            # Shading is its own pass so the normal array can be borrowed only
            # when there is one, and the normal matrix built once per mesh
            # rather than once per vertex.
            var vertex_colors = List[FloatColor]()
            if smooth:
                ref normals = geometry.attribute_view(String(NORMAL))
                var to_normal = world.normal_matrix()
                for vertex in range(vertex_count):
                    # transform_direction ignores translation, which is what a
                    # normal wants: it points somewhere, it is not somewhere.
                    var direction = to_normal.transform_direction(
                        normals.vector3(vertex)
                    )
                    direction.normalize()
                    vertex_colors.append(
                        self.shade(meshes[index].color, direction)
                    )

            var triangles = geometry.triangle_count()
            for triangle in range(triangles):
                var first = geometry.corner_index(triangle, 0)
                var second = geometry.corner_index(triangle, 1)
                var third = geometry.corner_index(triangle, 2)

                var color_a: FloatColor
                var color_b: FloatColor
                var color_c: FloatColor
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

                var pieces = clip_depth(
                    ClipVertex(view_points[first], color_a),
                    ClipVertex(view_points[second], color_b),
                    ClipVertex(view_points[third], color_c),
                    near,
                    far,
                )
                for piece in range(len(pieces)):
                    corners.append(_to_raster(pieces[piece], to_screen))

        return corners^

    def render(
        self,
        scene: Scene,
        geometries: GeometryStore,
        meshes: List[Mesh],
        camera: PerspectiveCamera,
    ) raises -> Framebuffer:
        """Draw every mesh on the CPU and return the finished image.

        `prepare` does the work; this fills the triangles it produces.

        Args:
            scene: The transform hierarchy the meshes sit in.
            geometries: The vertex data the meshes name.
            meshes: What to draw, each naming a node and a geometry.
            camera: The camera to project through.

        Returns:
            The rendered image.

        Raises:
            Error: If a mesh names a node or a geometry that is not there, or
                its geometry has no positions.
        """
        var corners = self.prepare(scene, geometries, meshes, camera)
        var target = Framebuffer(self.width, self.height, self.background)
        for triangle in range(len(corners) // 3):
            rasterize_shaded(
                corners[triangle * 3],
                corners[triangle * 3 + 1],
                corners[triangle * 3 + 2],
                target,
            )
        return target^
