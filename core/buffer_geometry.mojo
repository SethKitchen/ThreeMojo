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

The examples grew these arrays by hand before this module existed, and two of
them had drifted into near-identical copies. That duplication is what a
geometry type is for.
"""

from core.buffer_attribute import BufferAttribute
from math.vector3 import Vector3

# The attributes this port knows about, named as three.js names them.
# `position` is the only one a geometry must have.
comptime POSITION = "position"
comptime NORMAL = "normal"


struct BufferGeometry(Movable):
    """Named vertex attributes, with optional indexed triangles."""

    var attributes: Dict[String, BufferAttribute]
    var index: List[Int]

    def __init__(out self):
        """Create an empty geometry with no attributes and no index."""
        self.attributes = Dict[String, BufferAttribute]()
        self.index = List[Int]()

    def set_attribute(mut self, name: String, var attribute: BufferAttribute):
        """Store `attribute` under `name`, replacing any previous one."""
        self.attributes[name] = attribute^

    def has_attribute(self, name: String) -> Bool:
        """Return True if an attribute of that name is present."""
        return name in self.attributes

    def attribute(self, name: String) raises -> BufferAttribute:
        """Return a copy of the named attribute.

        Args:
            name: Which attribute to fetch.

        Returns:
            A copy of it.

        Raises:
            Error: If the geometry has no such attribute.
        """
        if name not in self.attributes:
            raise Error("This geometry has no attribute named " + name)
        return BufferAttribute(copy=self.attributes[name])

    def vertex_count(self) raises -> Int:
        """Return how many vertices the position attribute holds.

        Returns:
            The vertex count.

        Raises:
            Error: If the geometry has no positions.
        """
        return self.attribute(POSITION).count()

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
        return self.attribute(POSITION).vector3(
            self.corner_index(triangle, corner)
        )
