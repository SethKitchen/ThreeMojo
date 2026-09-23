# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One named array of per-vertex data, from three.js `src/core/BufferAttribute.js`.

An attribute is a flat array plus how many numbers belong to each vertex.
Positions come in threes, texture coordinates in twos, and the array does not
record which it is — `item_size` does. Keeping the data flat rather than as a
list of `Vector3` is the whole point: it is the layout a GPU wants, so it can
be uploaded without rearranging.
"""

from math.vector3 import Vector3


struct BufferAttribute(Copyable, Movable):
    """A flat array of floats, grouped into per-vertex items."""

    var data: List[Float32]
    var item_size: Int

    def __init__(out self, var data: List[Float32], item_size: Int) raises:
        """Create an attribute from flat data.

        Args:
            data: The numbers, vertex after vertex.
            item_size: How many numbers each vertex contributes.

        Raises:
            Error: If `item_size` is not positive, or the data does not divide
                evenly into items, which would leave a partial vertex.
        """
        if item_size <= 0:
            raise Error("An attribute's item size must be positive")
        if len(data) % item_size != 0:
            raise Error("Attribute data does not divide evenly into items")
        self.data = data^
        self.item_size = item_size

    def __init__(out self, *, copy: Self):
        """Copy another attribute."""
        self.data = copy.data.copy()
        self.item_size = copy.item_size

    def count(self) -> Int:
        """Return how many vertices this attribute describes."""
        return len(self.data) // self.item_size

    def component(self, index: Int, offset: Int) raises -> Float32:
        """Return one number belonging to one vertex.

        Args:
            index: Which vertex.
            offset: Which number within that vertex, from zero.

        Returns:
            The value stored there.

        Raises:
            Error: If either index falls outside the attribute.
        """
        if index < 0 or index >= self.count():
            raise Error("Attribute vertex index out of range")
        if offset < 0 or offset >= self.item_size:
            raise Error("Attribute component offset out of range")
        return self.data[index * self.item_size + offset]

    def vector3(self, index: Int) raises -> Vector3:
        """Return a vertex's first three numbers as a vector.

        Args:
            index: Which vertex.

        Returns:
            The vertex as a `Vector3`.

        Raises:
            Error: If the attribute stores fewer than three numbers per
                vertex, or the index is out of range.
        """
        if self.item_size < 3:
            raise Error("This attribute has fewer than three items per vertex")
        return Vector3(
            self.component(index, 0),
            self.component(index, 1),
            self.component(index, 2),
        )

    def gather(self, index: List[Int]) raises -> BufferAttribute:
        """Return the items an index names, one copy per entry.

        What three.js's `toNonIndexed` does to each attribute, and what
        `mergeVertices` does to keep the vertices it did not merge.

        Args:
            index: Which item each entry of the result copies.

        Returns:
            An attribute of the same item size with one item per entry.

        Raises:
            Error: If an entry points outside this attribute.
        """
        var data = List[Float32](capacity=len(index) * self.item_size)
        for entry in range(len(index)):
            # An item size is positive: the constructor refuses anything else.
            for offset in range(self.item_size):  # pragma: no branch
                data.append(self.component(index[entry], offset))
        return BufferAttribute(data^, self.item_size)
