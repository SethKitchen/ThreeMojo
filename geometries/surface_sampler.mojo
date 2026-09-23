# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Random points on a surface, from three.js
`examples/jsm/math/MeshSurfaceSampler.js`.

A sampler picks random points on the triangles of a geometry. A larger
triangle gets more points, so the points spread evenly over the surface.
Grass on a field, fur on a model and stars in a galaxy are placed this way.
A weight attribute can make some triangles more likely and others never
chosen.

`build` adds up the weight of each triangle into a running total, once.
Each `sample` then draws one number, finds its triangle by a binary search,
and draws two more for a point in that triangle. The point comes with the
normal, the color and the texture coordinates at that point.

**Random numbers.** The sampler draws from a `SeededRandom`, three.js's
`MathUtils.seededRandom`. The same seed gives the same points, which is what
a test needs. three.js draws from `Math.random` unless it is given another
function, and `Math.random` cannot be seeded. Each sample draws three
numbers in three.js's order, so a seeded three.js sampler picks the same
triangles.

The sums are three.js's: an area in `Float64`, a weight stored in `Float32`,
a running total in `Float64` stored in `Float32`. A point is interpolated in
`Float64` and stored in `Float32`.

**Refusals.** three.js reads past its arrays or finds no triangle for these,
and here they are refused: a weight attribute that is not there, a weight
that is negative or not a number, positions that do not make whole
triangles, and a sample from a surface with no weight at all.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION, UV
from math.utils import SeededRandom
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from std.math import ceil, isfinite, sqrt


@fieldwise_init
struct SurfaceSample(ImplicitlyCopyable):
    """One random point on a surface, and what the surface is there."""

    # Which triangle, counting from zero.
    var face: Int
    var position: Vector3
    # Unit length: interpolated from the normals, or the triangle's own.
    var normal: Vector3
    # The interpolated vertex color, if the geometry has colors.
    var color: Optional[FloatColor]
    # The interpolated texture coordinates, if the geometry has them.
    var uv: Optional[Vector2]


def _mix(a: Vector3, b: Vector3, c: Vector3, u: Float64, v: Float64) -> Vector3:
    """Return three values mixed by barycentric weights, in `Float64`.
    three.js: `addScaledVector` three times from zero.

    Args:
        a: The value at the first corner.
        b: The value at the second corner.
        c: The value at the third corner.
        u: The weight of `a`.
        v: The weight of `b`. `c` gets what is left.

    Returns:
        The mixed value.
    """
    var w = 1 - (u + v)
    return Vector3(
        Float32(Float64(a.x) * u + Float64(b.x) * v + Float64(c.x) * w),
        Float32(Float64(a.y) * u + Float64(b.y) * v + Float64(c.y) * w),
        Float32(Float64(a.z) * u + Float64(b.z) * v + Float64(c.z) * w),
    )


def _area(a: Vector3, b: Vector3, c: Vector3) -> Float64:
    """Return a triangle's area in `Float64`. three.js: `Triangle.getArea`.

    Args:
        a: The first corner.
        b: The second corner.
        c: The third corner.

    Returns:
        Half the length of `(c - b) x (a - b)`.
    """
    var ex = Float64(c.x) - Float64(b.x)
    var ey = Float64(c.y) - Float64(b.y)
    var ez = Float64(c.z) - Float64(b.z)
    var fx = Float64(a.x) - Float64(b.x)
    var fy = Float64(a.y) - Float64(b.y)
    var fz = Float64(a.z) - Float64(b.z)
    var nx = ey * fz - ez * fy
    var ny = ez * fx - ex * fz
    var nz = ex * fy - ey * fx
    return sqrt(nx * nx + ny * ny + nz * nz) * 0.5


struct MeshSurfaceSampler(Movable):
    """Weighted random points on the triangles of a geometry. three.js:
    `MeshSurfaceSampler`."""

    var geometry: BufferGeometry
    var random: SeededRandom
    # The attribute whose first number weighs each vertex, or None to weigh
    # by area alone.
    var weight_attribute: Optional[String]
    # The running total of the weights, one per triangle. Empty until built.
    var distribution: List[Float32]

    def __init__(
        out self, geometry: BufferGeometry, var random: SeededRandom
    ) raises:
        """Create a sampler for a geometry. three.js: the constructor and
        `setRandomGenerator`.

        The sampler keeps its own copy of the geometry. three.js takes a
        mesh and reads only its geometry.

        Args:
            geometry: The surface.
            random: Where the random numbers come from.

        Raises:
            Error: If the geometry has no positions.
        """
        if not geometry.has_attribute(POSITION):
            raise Error("A surface sampler needs a geometry with positions")
        self.geometry = geometry.clone()
        self.random = random^
        self.weight_attribute = None
        self.distribution = List[Float32]()

    def set_weight_attribute(mut self, name: Optional[String]) raises:
        """Weigh each triangle by an attribute as well as by its area.
        three.js: `setWeightAttribute`.

        A triangle's weight is the sum of the attribute's first number at
        its three corners, times its area. A triangle of weight zero is
        never chosen. Call `build` after this.

        Args:
            name: The attribute, or None to weigh by area alone.

        Raises:
            Error: If the geometry has no attribute of that name. three.js
                then weighs by area alone.
        """
        if Bool(name) and not self.geometry.has_attribute(name.value()):
            raise Error("The geometry has no attribute named " + name.value())
        self.weight_attribute = name

    def set_random_generator(mut self, var random: SeededRandom):
        """Use another generator. three.js: `setRandomGenerator`.

        Args:
            random: The generator.
        """
        self.random = random^

    def face_count(self) raises -> Int:
        """Return how many triangles the geometry has.

        Returns:
            A third of the index, or of the positions if there is no index.

        Raises:
            Error: If the positions do not make whole triangles.
        """
        if self.geometry.is_indexed():
            return len(self.geometry.index) // 3
        var count = self.geometry.vertex_count()
        if count % 3 != 0:
            raise Error("The positions do not make whole triangles")
        return count // 3

    def _corners(self, face: Int) -> Tuple[Int, Int, Int]:
        """Return the vertices of a triangle.

        Args:
            face: The triangle.

        Returns:
            The three vertex indices.
        """
        var i0 = face * 3
        if self.geometry.is_indexed():
            ref index = self.geometry.index
            return (index[i0], index[i0 + 1], index[i0 + 2])
        return (i0, i0 + 1, i0 + 2)

    def build(mut self) raises:
        """Add up the weight of every triangle. three.js: `build`.

        Raises:
            Error: If the positions do not make whole triangles, an index
                points past the positions, or a weight is negative or not a
                number.
        """
        var faces = self.face_count()
        ref positions = self.geometry.attribute_view(POSITION)
        var weights = List[Float32]()
        for face in range(faces):
            var corners = self._corners(face)
            var weight = Float64(1)
            if Bool(self.weight_attribute):
                ref weigh = self.geometry.attribute_view(
                    self.weight_attribute.value()
                )
                weight = (
                    Float64(weigh.component(corners[0], 0))
                    + Float64(weigh.component(corners[1], 0))
                    + Float64(weigh.component(corners[2], 0))
                )
            weight *= _area(
                positions.vector3(corners[0]),
                positions.vector3(corners[1]),
                positions.vector3(corners[2]),
            )
            if not isfinite(weight) or weight < 0:
                raise Error(
                    "A triangle's weight must be a number, not negative"
                )
            weights.append(Float32(weight))
        var distribution = List[Float32]()
        var total = Float64(0)
        for face in range(faces):
            total += Float64(weights[face])
            distribution.append(Float32(total))
        self.distribution = distribution^

    def _binary_search(self, x: Float64) -> Int:
        """Return the triangle whose share of the total holds a number.
        three.js: `_binarySearch`.

        Args:
            x: A number from zero up to the total.

        Returns:
            The triangle, or -1 if none holds it.
        """
        ref dist = self.distribution
        var start = 0
        var end = len(dist) - 1
        while start <= end:
            var mid = Int(ceil(Float64(start + end) / 2))
            var here = mid == 0 or (
                Float64(dist[mid - 1]) <= x and Float64(dist[mid]) > x
            )
            if here:
                return mid
            if x < Float64(dist[mid]):
                end = mid - 1
            else:
                start = mid + 1
        return -1

    def sample(mut self) raises -> SurfaceSample:
        """Return a random point of the surface. three.js: `sample`.

        Returns:
            The point, its triangle, and the normal, color and texture
            coordinates there.

        Raises:
            Error: If the sampler is not built, or the surface has no
                weight to choose by.
        """
        if len(self.distribution) == 0:
            raise Error("Build the sampler, over some triangles, first")
        var total = Float64(self.distribution[len(self.distribution) - 1])
        if total == 0:
            raise Error("No triangle has any weight to be chosen by")
        var face = self._binary_search(self.random.next() * total)
        return self.sample_face(face)

    def sample_face(mut self, face: Int) raises -> SurfaceSample:
        """Return a random point of one triangle. three.js: `_sampleFace`.

        Args:
            face: The triangle.

        Returns:
            The point, and the normal, color and texture coordinates there.

        Raises:
            Error: If there is no such triangle, or an attribute is too
                short for it.
        """
        if face < 0 or face >= self.face_count():
            raise Error("No triangle has that index")
        var u = self.random.next()
        var v = self.random.next()
        if u + v > 1:
            u = 1 - u
            v = 1 - v
        var corners = self._corners(face)
        ref positions = self.geometry.attribute_view(POSITION)
        var a = positions.vector3(corners[0])
        var b = positions.vector3(corners[1])
        var c = positions.vector3(corners[2])
        var position = _mix(a, b, c, u, v)
        var normal: Vector3
        if self.geometry.has_attribute(NORMAL):
            ref normals = self.geometry.attribute_view(NORMAL)
            normal = _mix(
                normals.vector3(corners[0]),
                normals.vector3(corners[1]),
                normals.vector3(corners[2]),
                u,
                v,
            )
        else:
            normal = c - b
            normal.cross(a - b)
        normal.normalize()
        var color: Optional[FloatColor] = None
        if self.geometry.has_attribute(COLOR):
            ref colors = self.geometry.attribute_view(COLOR)
            var mixed = _mix(
                colors.vector3(corners[0]),
                colors.vector3(corners[1]),
                colors.vector3(corners[2]),
                u,
                v,
            )
            color = FloatColor(mixed.x, mixed.y, mixed.z)
        var uv: Optional[Vector2] = None
        if self.geometry.has_attribute(UV):
            ref uvs = self.geometry.attribute_view(UV)
            var w = 1 - (u + v)
            uv = Vector2(
                Float32(
                    Float64(uvs.component(corners[0], 0)) * u
                    + Float64(uvs.component(corners[1], 0)) * v
                    + Float64(uvs.component(corners[2], 0)) * w
                ),
                Float32(
                    Float64(uvs.component(corners[0], 1)) * u
                    + Float64(uvs.component(corners[1], 1)) * v
                    + Float64(uvs.component(corners[2], 1)) * w
                ),
            )
        return SurfaceSample(face, position, normal, color, uv)
