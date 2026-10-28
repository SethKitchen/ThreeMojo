# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Triangles gathered piece by piece, with a normal, a color and texture
coordinates at each vertex.

A `Sheet` holds the triangles of one material. The village's view of a
house fills one sheet for each of its materials: the facade, the
plaster, the wood, the stone, the roof and the glass. Then it turns each
sheet into a `BufferGeometry`.

Texture coordinates are in meters on the surface, divided by the sheet's
`tile`: the size of the ground that one copy of the sheet's texture
covers. So a texture keeps its true size on every face, and it runs on
across two quads that share an edge when they give the same coordinates
at that edge.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from math.vector3 import Vector3


def _normal(p0: Vector3, p1: Vector3, p3: Vector3) -> Vector3:
    """Return the unit normal of the plane through three points, wound
    counterclockwise, or +y for points on one line."""
    var a = p1 - p0
    var b = p3 - p0
    var n = Vector3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )
    var length = n.length()
    if length <= 0:
        return Vector3(0, 1, 0)
    return n / length


struct Sheet(Movable):
    """The triangles of one material, with a normal, a color and texture
    coordinates at each vertex."""

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]
    var uvs: List[Float32]
    var index: List[Int]
    # The meters of surface that one copy of the texture covers.
    var tile: Float32

    def __init__(out self, tile: Float32):
        """Hold no triangles.

        Args:
            tile: The meters of surface that one copy of the texture
                covers. It must be positive.
        """
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()
        self.uvs = List[Float32]()
        self.index = List[Int]()
        self.tile = tile

    def vertex(
        mut self, p: Vector3, n: Vector3, color: Vector3, u: Float32, v: Float32
    ) -> Int:
        """Add one vertex.

        Args:
            p: Where it is.
            n: Its normal, of length one.
            color: Its linear color.
            u: Its first texture coordinate, in meters.
            v: Its second texture coordinate, in meters.

        Returns:
            Its index.
        """
        var at = len(self.positions) // 3
        self.positions.append(p.x)
        self.positions.append(p.y)
        self.positions.append(p.z)
        self.normals.append(n.x)
        self.normals.append(n.y)
        self.normals.append(n.z)
        self.colors.append(color.x)
        self.colors.append(color.y)
        self.colors.append(color.z)
        self.uvs.append(u / self.tile)
        self.uvs.append(v / self.tile)
        return at

    def triangle(mut self, a: Int, b: Int, c: Int):
        """Add a triangle of three vertices already added.

        Args:
            a: The first vertex.
            b: The second, counterclockwise from the front.
            c: The third.
        """
        self.index.append(a)
        self.index.append(b)
        self.index.append(c)

    def painted_quad(
        mut self,
        p0: Vector3,
        p1: Vector3,
        p2: Vector3,
        p3: Vector3,
        c0: Vector3,
        c1: Vector3,
        c2: Vector3,
        c3: Vector3,
        u0: Float32,
        v0: Float32,
        u1: Float32,
        v1: Float32,
    ):
        """Add a flat quad with a color at each corner.

        The corners go counterclockwise seen from the front. The texture
        coordinates run from `(u0, v0)` at `p0` to `(u1, v0)` at `p1`, and
        to `(u0, v1)` at `p3`.

        Args:
            p0: The first corner.
            p1: The second.
            p2: The third.
            p3: The fourth.
            c0: The color at the first corner.
            c1: The color at the second.
            c2: The color at the third.
            c3: The color at the fourth.
            u0: The first texture coordinate at `p0`, in meters.
            v0: The second texture coordinate at `p0`, in meters.
            u1: The first texture coordinate at `p1`, in meters.
            v1: The second texture coordinate at `p3`, in meters.
        """
        var n = _normal(p0, p1, p3)
        var a = self.vertex(p0, n, c0, u0, v0)
        var b = self.vertex(p1, n, c1, u1, v0)
        var c = self.vertex(p2, n, c2, u1, v1)
        var d = self.vertex(p3, n, c3, u0, v1)
        self.triangle(a, b, c)
        self.triangle(a, c, d)

    def quad(
        mut self,
        p0: Vector3,
        p1: Vector3,
        p2: Vector3,
        p3: Vector3,
        color: Vector3,
    ):
        """Add a flat quad of one color, its texture laid in meters along
        its first and its last edges.

        Args:
            p0: The first corner, counterclockwise seen from the front.
            p1: The second.
            p2: The third.
            p3: The fourth.
            color: Its linear color.
        """
        var width = (p1 - p0).length()
        var height = (p3 - p0).length()
        self.painted_quad(
            p0, p1, p2, p3, color, color, color, color, 0, 0, width, height
        )

    def box(
        mut self,
        center: Vector3,
        x: Vector3,
        y: Vector3,
        z: Vector3,
        color: Vector3,
    ):
        """Add a box of one color, its six faces facing out.

        Args:
            center: Its middle.
            x: Half of its first edge, as a vector.
            y: Half of its second edge, as a vector, at right angles to
                the first.
            z: Half of its third edge, as a vector: `x` cross `y` points
                along it.
            color: Its linear color.
        """
        var c = center
        # The corners: - and + along x, y and z.
        var p000 = c - x - y - z
        var p100 = c + x - y - z
        var p010 = c - x + y - z
        var p110 = c + x + y - z
        var p001 = c - x - y + z
        var p101 = c + x - y + z
        var p011 = c - x + y + z
        var p111 = c + x + y + z
        self.quad(p001, p101, p111, p011, color)
        self.quad(p100, p000, p010, p110, color)
        self.quad(p101, p100, p110, p111, color)
        self.quad(p000, p001, p011, p010, color)
        self.quad(p011, p111, p110, p010, color)
        self.quad(p000, p100, p101, p001, color)

    def triangles(self) -> Int:
        """Return how many triangles the sheet holds.

        Returns:
            The count.
        """
        return len(self.index) // 3

    def geometry(self) raises -> BufferGeometry:
        """Return the sheet as a geometry.

        Returns:
            A geometry with `position`, `normal`, `color` and `uv`, and an
            index.

        Raises:
            Error: If an attribute cannot be set.
        """
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(self.positions.copy(), 3)
        )
        geometry.set_attribute(
            String(NORMAL), BufferAttribute(self.normals.copy(), 3)
        )
        geometry.set_attribute(
            String(COLOR), BufferAttribute(self.colors.copy(), 3)
        )
        geometry.set_attribute(String(UV), BufferAttribute(self.uvs.copy(), 2))
        geometry.set_index(self.index.copy())
        return geometry^
