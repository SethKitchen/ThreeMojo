# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One array that several attributes share, from three.js
`src/core/InterleavedBuffer.js` and `src/core/InstancedInterleavedBuffer.js`.

An interleaved buffer lays a vertex's numbers side by side: a position,
then a normal, then a texture coordinate, then the next vertex. `stride`
says how many numbers one vertex takes in all, and each attribute that
reads the buffer says where in that run its own numbers begin. See
`BufferAttribute(buffer, item_size, offset)`.

three.js shares the buffer by reference: two attributes built on it read
and write one array. This does the same with a reference-counted handle.
Copying an `InterleavedBuffer` copies the handle and not the numbers, as
assigning a JavaScript object does, so a write through one copy shows
through every other. `clone` is the call that copies the numbers.

A buffer built with `mesh_per_attribute` is three.js's
`InstancedInterleavedBuffer`: the attributes on it advance once per
instance, or once per so many instances, and not once per vertex. See
`BufferGeometry(instanced=True)`.
"""

from std.memory import ArcPointer


struct _InterleavedArray(Movable):
    """The numbers an interleaved buffer's handles share."""

    var array: List[Float32]
    var stride: Int
    # How many instances each run of `stride` numbers serves, or zero when
    # the buffer advances per vertex.
    var mesh_per_attribute: Int

    def __init__(
        out self, var array: List[Float32], stride: Int, mesh_per_attribute: Int
    ):
        """Hold the numbers, already checked.

        Args:
            array: The numbers, vertex after vertex.
            stride: How many numbers one vertex takes.
            mesh_per_attribute: Zero, or how many instances one run serves.
        """
        self.array = array^
        self.stride = stride
        self.mesh_per_attribute = mesh_per_attribute


def _checked(
    var array: List[Float32], stride: Int, mesh_per_attribute: Int
) raises -> ArcPointer[_InterleavedArray]:
    """Return a new shared array, if its shape is one a buffer can have.

    Args:
        array: The numbers.
        stride: How many numbers one vertex takes.
        mesh_per_attribute: Zero, or how many instances one run serves.

    Returns:
        The handle to the new array.

    Raises:
        Error: If the stride is not positive, or the numbers do not divide
            into whole runs of it.
    """
    if stride <= 0:
        raise Error("An interleaved buffer's stride must be positive")
    if len(array) % stride != 0:
        raise Error("Interleaved data does not divide evenly into strides")
    return ArcPointer(_InterleavedArray(array^, stride, mesh_per_attribute))


struct InterleavedBuffer(Copyable, Movable):
    """A shared array of floats that several attributes read with a
    stride, three.js's `InterleavedBuffer`.

    A copy is a second handle on the same numbers. See the module
    docstring.
    """

    var _shared: ArcPointer[_InterleavedArray]

    def __init__(out self, var array: List[Float32], stride: Int) raises:
        """Create a buffer that advances once per vertex.

        Args:
            array: The numbers, vertex after vertex.
            stride: How many numbers one vertex takes, across every
                attribute that reads the buffer.

        Raises:
            Error: If `stride` is not positive, or the numbers do not divide
                evenly into runs of it.
        """
        self._shared = _checked(array^, stride, 0)

    def __init__(
        out self,
        var array: List[Float32],
        stride: Int,
        *,
        mesh_per_attribute: Int,
    ) raises:
        """Create a buffer that advances once per instance, three.js's
        `InstancedInterleavedBuffer`.

        Args:
            array: The numbers, instance after instance.
            stride: How many numbers one instance takes.
            mesh_per_attribute: How many instances in a row read one run
                of `stride` numbers, three.js's `meshPerAttribute`.

        Raises:
            Error: If `stride` or `mesh_per_attribute` is not positive, or
                the numbers do not divide evenly into runs of the stride.
        """
        if mesh_per_attribute <= 0:
            raise Error("An instanced buffer serves one instance a run or more")
        self._shared = _checked(array^, stride, mesh_per_attribute)

    def count(self) -> Int:
        """Return how many runs of `stride` numbers the buffer holds:
        vertices, or instances when it is instanced."""
        return len(self._shared[].array) // self._shared[].stride

    def stride(self) -> Int:
        """Return how many numbers one vertex takes."""
        return self._shared[].stride

    def length(self) -> Int:
        """Return how many numbers the buffer holds in all."""
        return len(self._shared[].array)

    def mesh_per_attribute(self) -> Int:
        """Return how many instances one run serves, or zero for a buffer
        that advances per vertex."""
        return self._shared[].mesh_per_attribute

    def is_instanced(self) -> Bool:
        """Return True if the buffer advances per instance."""
        return self._shared[].mesh_per_attribute > 0

    def value(self, at: Int) raises -> Float32:
        """Return one number of the array.

        Args:
            at: Where it is, counted from the first number.

        Returns:
            The number.

        Raises:
            Error: If `at` is outside the array.
        """
        if at < 0 or at >= self.length():
            raise Error("Interleaved buffer index out of range")
        return self._shared[].array[at]

    def set_value(self, at: Int, value: Float32) raises:
        """Replace one number of the array. Every attribute and every copy
        of this handle sees the change.

        Args:
            at: Where it is, counted from the first number.
            value: The new number.

        Raises:
            Error: If `at` is outside the array.
        """
        if at < 0 or at >= self.length():
            raise Error("Interleaved buffer index out of range")
        self._shared[].array[at] = value

    def shares_with(self, other: InterleavedBuffer) -> Bool:
        """Return True if both handles name one array.

        Args:
            other: The other handle.

        Returns:
            Whether a write through one shows through the other.
        """
        return self._shared.ptr() == other._shared.ptr()

    def clone(self) -> InterleavedBuffer:
        """Return a buffer with a copy of the numbers, three.js's `clone`.

        Returns:
            A new buffer of the same stride and instancing that shares
            nothing with this one.
        """
        var copied = self.copy()
        copied._shared = ArcPointer(
            _InterleavedArray(
                self._shared[].array.copy(),
                self._shared[].stride,
                self._shared[].mesh_per_attribute,
            )
        )
        return copied^
