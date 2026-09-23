# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One named array of per-vertex data, from three.js
`src/core/BufferAttribute.js`, `src/core/InterleavedBufferAttribute.js` and
`src/core/InstancedBufferAttribute.js`.

An attribute is a flat array plus how many numbers belong to each vertex.
Positions come in threes, texture coordinates in twos, and the array does not
record which it is — `item_size` does. Keeping the data flat rather than as a
list of `Vector3` is the whole point: it is the layout a GPU wants, so it can
be uploaded without rearranging.

## Interleaved attributes

three.js has a second class, `InterleavedBufferAttribute`, that reads its
numbers out of an `InterleavedBuffer` shared with other attributes: item
`i` begins at `i * stride + offset` of the shared array. Here it is the same
`BufferAttribute`, built with `BufferAttribute(buffer, item_size, offset)`.
One type is what keeps every reader unchanged: `count`, `component` and
`vector3` take the stride into account, and the renderer, the raycaster,
the deformers and the exporters read through them.

`data` is the attribute's own array and is empty for an interleaved one.
Code that wants every number in item order, whatever the layout, asks for
`packed`.

Copying an interleaved attribute copies its handle on the buffer, so the
copy reads the same shared numbers, as a second reference to one three.js
object does. `BufferGeometry.clone_attribute` copies the numbers instead,
and `BufferGeometry.clone` copies each buffer once and keeps its
attributes sharing the copy, as three.js's `copy` does.

## Instanced attributes

three.js's `InstancedBufferAttribute` is an attribute that advances once
per instance rather than once per vertex. Here it is a `BufferAttribute`
built with `mesh_per_attribute`, or one on an instanced interleaved buffer.
It is read by an instanced geometry; see `BufferGeometry(instanced=True)`.
"""

from core.interleaved_buffer import InterleavedBuffer
from math.vector3 import Vector3


struct BufferAttribute(Copyable, Movable):
    """A flat array of floats, grouped into per-vertex items, or a view of
    a shared interleaved array."""

    var data: List[Float32]
    var item_size: Int
    # The shared array an interleaved attribute reads, and where in each
    # run of it the attribute's items begin. Empty and zero otherwise.
    var _buffer: Optional[InterleavedBuffer]
    var _offset: Int
    # How many instances one item serves, three.js's `meshPerAttribute`,
    # or zero for an attribute that advances per vertex. An interleaved
    # attribute asks its buffer instead.
    var _mesh_per_attribute: Int

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
        self._buffer = None
        self._offset = 0
        self._mesh_per_attribute = 0

    def __init__(
        out self,
        var data: List[Float32],
        item_size: Int,
        *,
        mesh_per_attribute: Int,
    ) raises:
        """Create an attribute that advances per instance, three.js's
        `InstancedBufferAttribute`.

        Args:
            data: The numbers, instance after instance.
            item_size: How many numbers each instance reads.
            mesh_per_attribute: How many instances in a row read one item,
                three.js's `meshPerAttribute`.

        Raises:
            Error: If `item_size` or `mesh_per_attribute` is not positive,
                or the data does not divide evenly into items.
        """
        if mesh_per_attribute <= 0:
            raise Error("An instanced attribute serves one instance or more")
        self = BufferAttribute(data^, item_size)
        self._mesh_per_attribute = mesh_per_attribute

    def __init__(
        out self, buffer: InterleavedBuffer, item_size: Int, offset: Int
    ) raises:
        """Create an attribute that reads a shared interleaved array,
        three.js's `InterleavedBufferAttribute`.

        The attribute holds a handle on the buffer, so a write to the
        buffer shows through it. It advances per instance if the buffer
        does.

        Args:
            buffer: The shared array.
            item_size: How many numbers each item reads.
            offset: Where in each run of `buffer.stride()` numbers the
                item begins.

        Raises:
            Error: If `item_size` is not positive, `offset` is negative, or
                the item reaches past the end of its run.
        """
        if item_size <= 0:
            raise Error("An attribute's item size must be positive")
        if offset < 0 or offset + item_size > buffer.stride():
            raise Error("An interleaved item must lie inside the stride")
        self.data = List[Float32]()
        self.item_size = item_size
        self._buffer = buffer.copy()
        self._offset = offset
        self._mesh_per_attribute = 0

    def __init__(out self, *, copy: Self):
        """Copy another attribute.

        A plain attribute's numbers are copied. An interleaved attribute's
        handle is copied, so the copy reads the same shared buffer; see the
        module docstring.

        Args:
            copy: The attribute to copy.
        """
        self.data = copy.data.copy()
        self.item_size = copy.item_size
        self._buffer = copy._buffer.copy()
        self._offset = copy._offset
        self._mesh_per_attribute = copy._mesh_per_attribute

    def on_buffer(self, buffer: InterleavedBuffer) -> BufferAttribute:
        """Return this attribute reading another buffer at the same
        offset, as three.js's `InterleavedBufferAttribute.clone(data)`
        does with the buffer it has already cloned.

        Args:
            buffer: The buffer the result reads. It must have this
                attribute's buffer's stride, which is what `clone` of it
                gives.

        Returns:
            An interleaved attribute on `buffer`, or a copy of this one if
            it is not interleaved.
        """
        var moved = self.copy()
        if Bool(self._buffer):
            moved._buffer = buffer.copy()
        return moved^

    def is_interleaved(self) -> Bool:
        """Return True if the attribute reads a shared interleaved array."""
        return Bool(self._buffer)

    def interleaved_buffer(self) raises -> InterleavedBuffer:
        """Return a handle on the shared array this attribute reads,
        three.js's `data`.

        Returns:
            A handle that shares the numbers.

        Raises:
            Error: If the attribute is not interleaved.
        """
        if not Bool(self._buffer):
            raise Error("This attribute is not interleaved")
        return self._buffer.value().copy()

    def offset(self) -> Int:
        """Return where in each run of the shared array an item begins, or
        zero for an attribute that is not interleaved."""
        return self._offset

    def stride(self) -> Int:
        """Return how far apart two items are, in numbers: the buffer's
        stride, or the item size for an attribute that is not interleaved.
        """
        if Bool(self._buffer):
            return self._buffer.value().stride()
        return self.item_size

    def mesh_per_attribute(self) -> Int:
        """Return how many instances one item serves, or zero for an
        attribute that advances per vertex."""
        if Bool(self._buffer):
            return self._buffer.value().mesh_per_attribute()
        return self._mesh_per_attribute

    def is_instanced(self) -> Bool:
        """Return True if the attribute advances per instance."""
        return self.mesh_per_attribute() > 0

    def count(self) -> Int:
        """Return how many vertices this attribute describes: instances,
        for one that is instanced."""
        if Bool(self._buffer):
            return self._buffer.value().count()
        return len(self.data) // self.item_size

    def _at(self, index: Int, offset: Int) raises -> Int:
        """Return where one number of one item sits in its array.

        Args:
            index: Which item.
            offset: Which number within it.

        Returns:
            The position in `data`, or in the shared array.

        Raises:
            Error: If either index falls outside the attribute, or an
                interleaved item has been made to reach past its run.
        """
        if index < 0 or index >= self.count():
            raise Error("Attribute vertex index out of range")
        if offset < 0 or offset >= self.item_size:
            raise Error("Attribute component offset out of range")
        var lane = self._offset + offset
        var stride = self.stride()
        if lane >= stride:
            raise Error("An interleaved item must lie inside the stride")
        return index * stride + lane

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
        var at = self._at(index, offset)
        if Bool(self._buffer):
            return self._buffer.value().value(at)
        return self.data[at]

    def set_component(mut self, index: Int, offset: Int, value: Float32) raises:
        """Replace one number belonging to one vertex, three.js's `setX`
        and its kin.

        An interleaved attribute writes the shared array, so every other
        attribute on it sees the change.

        Args:
            index: Which vertex.
            offset: Which number within that vertex, from zero.
            value: The new number.

        Raises:
            Error: If either index falls outside the attribute.
        """
        var at = self._at(index, offset)
        if Bool(self._buffer):
            self._buffer.value().set_value(at, value)
        else:
            self.data[at] = value

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

    def packed(self) raises -> List[Float32]:
        """Return every number, item after item, with no stride between.

        A copy of `data` for an attribute that is not interleaved, and the
        attribute's own numbers picked out of the shared array for one that
        is: what an exporter writes.

        Returns:
            `count() * item_size` numbers.

        Raises:
            Error: If an interleaved item has been made to reach past its
                run.
        """
        if not Bool(self._buffer):
            return self.data.copy()
        var out = List[Float32](capacity=self.count() * self.item_size)
        for index in range(self.count()):
            # An item size is positive: the constructor refuses anything
            # else.
            for offset in range(self.item_size):  # pragma: no branch
                out.append(self.component(index, offset))
        return out^

    def clone(self) raises -> BufferAttribute:
        """Return a copy with an array of its own, three.js's `clone`.

        An interleaved attribute's numbers are picked out of the shared
        array, as three.js's `InterleavedBufferAttribute.clone()` does when
        it is given no buffers to share. Unlike three.js, the copy keeps
        its instancing.

        Returns:
            An attribute that is not interleaved and shares nothing.

        Raises:
            Error: If an interleaved item has been made to reach past its
                run.
        """
        var copied = BufferAttribute(self.packed(), self.item_size)
        copied._mesh_per_attribute = self.mesh_per_attribute()
        return copied^

    def gather(self, index: List[Int]) raises -> BufferAttribute:
        """Return the items an index names, one copy per entry.

        What three.js's `toNonIndexed` does to each attribute, and what
        `mergeVertices` does to keep the vertices it did not merge. The
        result is never interleaved.

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
