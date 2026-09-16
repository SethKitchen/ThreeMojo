# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A mesh's vertex data, from three.js `src/core/BufferGeometry.js`.

A geometry is a bag of named attributes — `position` at minimum, later
`normal` and `uv` — plus an optional index buffer saying which vertices make
up each triangle. Indexing exists so a vertex shared by several triangles is
stored once; a cube's eight corners serve thirty-six triangle slots.

Without an index, vertices are taken three at a time in order. three.js allows
both and so does this.

Reading an attribute borrows it; copying one is a separate call with copy in
its name. That distinction is the whole reason `attribute_view` exists next to
`clone_attribute`: a single accessor that returned an owning copy made every
read allocate, and reads are what a renderer does constantly.

The attributes are held as two parallel lists rather than a `Dict`, which is
the concession that makes the borrowing accessor usable. Mojo gives every value
in a `Dict` the same symbolic origin, so taking a view of `normal` invalidates
an outstanding view of `position` — the compiler cannot tell the two apart, and
a renderer that wants both at once is refused. List elements share an origin
too, but one the compiler does not invalidate on a second borrow. Two lists
also keep insertion order, which a `Dict` does not promise and a GPU upload
will eventually want.

The examples grew these arrays by hand before this module existed, and two of
them had drifted into near-identical copies. That duplication is what a
geometry type is for.
"""

from core.buffer_attribute import BufferAttribute
from math.bounds import Box3, Sphere
from math.vector3 import Vector3

# The attributes this port knows about, named as three.js names them.
# `position` is the only one a geometry must have.
comptime POSITION = "position"
comptime NORMAL = "normal"
# Texture coordinates, two per vertex. three.js's convention and OpenGL's: the
# origin is the bottom-left of the image and v grows upwards, which is the
# opposite of how a framebuffer's rows are numbered. Sampling is where that
# gets reconciled, not here.
comptime UV = "uv"
# A color per vertex, three or four floats, in linear light as three.js's
# are since its color management: what a material's `vertex_colors`
# multiplies the material's color by. Decode an authored sRGB color with
# `FloatColor(srgb=...)` before storing it here.
comptime COLOR = "color"


struct BufferGeometry(Movable):
    """Named vertex attributes, with optional indexed triangles."""

    # Parallel arrays: `names[i]` is the name of `values[i]`. See the module
    # docstring for why this is not a Dict.
    var names: List[String]
    var values: List[BufferAttribute]
    var index: List[Int]

    def __init__(out self):
        """Create an empty geometry with no attributes and no index."""
        self.names = List[String]()
        self.values = List[BufferAttribute]()
        self.index = List[Int]()

    def _slot(self, name: String) -> Int:
        """Return where `name` is stored, or -1 if it is not present."""
        for position in range(len(self.names)):
            if self.names[position] == name:
                return position
        return -1

    def set_attribute(mut self, name: String, var attribute: BufferAttribute):
        """Store `attribute` under `name`, replacing any previous one."""
        var slot = self._slot(name)
        if slot < 0:
            self.names.append(name)
            self.values.append(attribute^)
        else:
            self.values[slot] = attribute^

    def has_attribute(self, name: String) -> Bool:
        """Return True if an attribute of that name is present."""
        return self._slot(name) >= 0

    def attribute_count(self) -> Int:
        """Return how many named attributes this geometry holds."""
        return len(self.names)

    def attribute_view(
        self, name: String
    ) raises -> ref[origin_of(self.values[0])] BufferAttribute:
        """Return a borrowed view of the named attribute.

        This is the ordinary way to read vertex data, and it copies nothing.
        The reference borrows from the geometry, so the geometry must outlive
        it; the compiler enforces that rather than trusting the caller.

        Binding the result with `var` is a compile error rather than a silent
        copy, because `BufferAttribute` is `Copyable` but not
        `ImplicitlyCopyable`. Bind it with `ref`, or say `clone_attribute` if
        a copy is genuinely what was meant.

        The borrow is immutable, which is what lets a caller hold views of
        `position` and `normal` at the same time.

        Args:
            name: Which attribute to read.

        Returns:
            A reference to it, valid as long as this geometry is.

        Raises:
            Error: If the geometry has no such attribute.
        """
        var slot = self._slot(name)
        if slot < 0:
            raise Error("This geometry has no attribute named " + name)
        return self.values[slot]

    def clone_attribute(self, name: String) raises -> BufferAttribute:
        """Return an owning copy of the named attribute.

        Allocates and copies the whole array, so this is for deliberately
        duplicating vertex data — not for reading it. Use `attribute_view`
        to read.

        Args:
            name: Which attribute to copy.

        Returns:
            A copy of it, owned by the caller.

        Raises:
            Error: If the geometry has no such attribute.
        """
        var slot = self._slot(name)
        if slot < 0:
            raise Error("This geometry has no attribute named " + name)
        return BufferAttribute(copy=self.values[slot])

    def vertex_count(self) raises -> Int:
        """Return how many vertices the position attribute holds.

        Reads the stored attribute through a view. This used to go through a
        copying accessor, which mattered more than it looks: `corner_index`
        calls it, the renderer calls `corner_index` three times per triangle,
        and so drawing a mesh copied its entire position array nine times per
        triangle.

        Returns:
            The vertex count.

        Raises:
            Error: If the geometry has no positions.
        """
        return self.attribute_view(POSITION).count()

    def set_index(mut self, var index: List[Int]) raises:
        """Set the triangle index buffer.

        Args:
            index: Vertex indices, three per triangle.

        Raises:
            Error: If the count is not a multiple of three, or any entry is
                negative. Entries are checked against the vertex count when
                read, since positions may be set after the index.
        """
        if len(index) % 3 != 0:
            raise Error("An index buffer must hold whole triangles")
        for position in range(len(index)):
            if index[position] < 0:
                raise Error("An index entry cannot be negative")
        self.index = index^

    def is_indexed(self) -> Bool:
        """Return True if triangles are looked up through an index buffer."""
        return len(self.index) > 0

    def triangle_count(self) raises -> Int:
        """Return how many triangles this geometry describes.

        Returns:
            The triangle count, from the index if there is one.

        Raises:
            Error: If the geometry has no positions.
        """
        if self.is_indexed():
            return len(self.index) // 3
        return self.vertex_count() // 3

    def corner_index(self, triangle: Int, corner: Int) raises -> Int:
        """Return which vertex a triangle corner refers to.

        For non-indexed geometry that is just the running position; with an
        index it is the entry stored there. Callers that want to transform
        each vertex once and reuse it need this rather than `corner`.

        Args:
            triangle: Which triangle, from zero.
            corner: Which of its three corners, from zero.

        Returns:
            The vertex index.

        Raises:
            Error: If either index is out of range, or an index entry points
                past the end of the position attribute.
        """
        if triangle < 0 or triangle >= self.triangle_count():
            raise Error("Triangle index out of range")
        if corner < 0 or corner > 2:
            raise Error("A triangle has three corners")

        var slot = triangle * 3 + corner
        if not self.is_indexed():
            return slot

        var vertex = self.index[slot]
        if vertex >= self.vertex_count():
            raise Error("An index entry points past the last vertex")
        return vertex

    def corner(self, triangle: Int, corner: Int) raises -> Vector3:
        """Return one corner of one triangle, in the geometry's own space.

        Args:
            triangle: Which triangle, from zero.
            corner: Which of its three corners, from zero.

        Returns:
            That corner's position.

        Raises:
            Error: If either index is out of range, or an index entry points
                past the end of the position attribute.
        """
        var vertex = self.corner_index(triangle, corner)
        return self.attribute_view(POSITION).vector3(vertex)

    def compute_vertex_normals(mut self) raises:
        """Set the `normal` attribute from the triangles, three.js's
        `computeVertexNormals`.

        Each triangle's normal -- the cross product of two of its edges,
        and so twice its area long -- is added to each of its three corners,
        and every corner's sum is made unit length at the end. A vertex
        shared by several triangles gets the average of their normals,
        weighted by their areas, which is what makes a sphere shade
        smoothly. A vertex used once, as every vertex of a box or a
        polyhedron is, gets its one face's normal and shades flat. A vertex
        no triangle uses keeps a zero normal, as in three.js.

        Faces are joined by index, not by position. The two vertices either
        side of a texture seam sit in the same place and keep separate
        sums, so recomputing a seamed sphere's normals shows the seam, as it
        does in three.js. A builder's own normals know better; replace them
        only on purpose.

        Raises:
            Error: If the geometry has no positions, or an index entry
                points past the last vertex.
        """
        var count = self.vertex_count()
        var sums = List[Float32](length=count * 3, fill=0.0)
        for triangle in range(self.triangle_count()):
            var a = self.corner_index(triangle, 0)
            var b = self.corner_index(triangle, 1)
            var c = self.corner_index(triangle, 2)
            var origin = self.corner(triangle, 0)
            var normal = self.corner(triangle, 1) - origin
            normal.cross(self.corner(triangle, 2) - origin)
            for vertex in [a, b, c]:  # pragma: no branch
                sums[vertex * 3] += normal.x
                sums[vertex * 3 + 1] += normal.y
                sums[vertex * 3 + 2] += normal.z
        for vertex in range(count):
            var unit = Vector3(
                sums[vertex * 3], sums[vertex * 3 + 1], sums[vertex * 3 + 2]
            )
            unit.normalize()
            sums[vertex * 3] = unit.x
            sums[vertex * 3 + 1] = unit.y
            sums[vertex * 3 + 2] = unit.z
        self.set_attribute(NORMAL, BufferAttribute(sums^, 3))

    def bounding_box(self) raises -> Box3:
        """Return the smallest box around every vertex, three.js's
        `computeBoundingBox`.

        Computed each time it is asked for rather than cached: a geometry's
        attributes are open, so a cached answer could not know when it had
        gone stale. Empty for a geometry with no vertices.

        Returns:
            The box.

        Raises:
            Error: If the geometry has no positions.
        """
        ref positions = self.attribute_view(POSITION)
        var box = Box3.empty()
        for vertex in range(positions.count()):
            box.expand_by_point(positions.vector3(vertex))
        return box

    def bounding_sphere(self) raises -> Sphere:
        """Return a sphere around every vertex, three.js's
        `computeBoundingSphere`: centered on the bounding box, reaching the
        farthest vertex.

        Not the smallest sphere possible, but a bound, as three.js's is; see
        `Sphere.from_points`. Computed each time, for the reason
        `bounding_box` is. Empty for a geometry with no vertices.

        Returns:
            The sphere.

        Raises:
            Error: If the geometry has no positions.
        """
        var box = self.bounding_box()
        if box.is_empty():
            return Sphere.empty()
        # Two passes over the borrowed positions rather than a copy of them:
        # the box's center, then the farthest vertex from it.
        ref positions = self.attribute_view(POSITION)
        var center = box.center()
        var farthest = Float32(0)
        for vertex in range(positions.count()):  # pragma: no branch
            var reach = (positions.vector3(vertex) - center).length()
            if reach > farthest:
                farthest = reach
        return Sphere(center, farthest)
