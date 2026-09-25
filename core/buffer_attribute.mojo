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

## Integer attributes

three.js stores an attribute in any typed array: a `Uint8Array` of colors,
an `Int16Array` of quantized positions. With `normalized` set, a read
divides the stored integer by the type's largest value, three.js's
`denormalize`, and a write multiplies and rounds, three.js's `normalize`.

Here `data` stays a `Float32` array for every attribute, and holds what a
read returns. An integer attribute also keeps the integers it stores, in
`stored_values`, and the component type they are stored as. Every write
goes through the integers first, so `data` holds exactly what three.js's
`getX` gives back. The renderer, the raycaster and the deformers read
`data` through `component` and `vector3`, and pay nothing for the integer
types. Only an exporter asks for the integers.

An interleaved attribute is always `Float32`, and so is an instanced one
built from floats.
"""

from core.interleaved_buffer import InterleavedBuffer
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.utils import (
    ComponentType,
    FLOAT32_COMPONENT,
    INT16_COMPONENT,
    INT32_COMPONENT,
    INT8_COMPONENT,
    UINT16_COMPONENT,
    UINT8_COMPONENT,
    denormalize,
    normalize,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import floor, isfinite, trunc


def array_type_name(component: ComponentType) raises -> String:
    """Return the name of the typed array a component type is stored in,
    as three.js's `toJSON` writes it in `type`.

    Args:
        component: The component type.

    Returns:
        `Float32Array`, `Uint8Array` and so on.

    Raises:
        Error: If the component type is not valid.
    """
    if not component.is_valid():
        raise Error("A typed array needs a valid component type")
    var names: List[String] = [
        "Float32Array",
        "Uint32Array",
        "Uint16Array",
        "Uint8Array",
        "Int32Array",
        "Int16Array",
        "Int8Array",
    ]
    return names[component.value]


def component_of_array(name: String) raises -> ComponentType:
    """Return the component type a typed array's name stands for, as
    three.js's `getTypedArray` reads `type`.

    Args:
        name: `Float32Array`, `Uint8Array` and so on.

    Returns:
        The component type.

    Raises:
        Error: If the name is not one of the seven arrays read.
    """
    # Seven is a constant, so the loop always runs.
    for value in range(7):  # pragma: no branch
        if array_type_name(ComponentType(value)) == name:
            return ComponentType(value)
    raise Error("A typed array that is not read: " + name)


def typed_value(value: Float64, component: ComponentType) raises -> Int:
    """Return the integer a typed array of one integer type stores for a
    number, as JavaScript converts one on assignment.

    The number is cut toward zero and wrapped into the type's range, so a
    `Uint8Array` stores 256 as 0 and -1 as 255. Not a number, and either
    infinity, store 0.

    Args:
        value: The number assigned.
        component: The integer type of the array.

    Returns:
        The stored integer.

    Raises:
        Error: If the component type is not valid, or is `Float32`, which
            stores the number itself.
    """
    if not component.is_valid() or component == FLOAT32_COMPONENT:
        raise Error("A typed value needs an integer component type")
    if not isfinite(value):
        return 0
    var bits = 32
    if component == UINT16_COMPONENT or component == INT16_COMPONENT:
        bits = 16
    elif component == UINT8_COMPONENT or component == INT8_COMPONENT:
        bits = 8
    var modulus = Float64(1 << bits)
    var whole = trunc(value)
    var wrapped = Int(whole - floor(whole / modulus) * modulus)
    var signed = component.value >= INT32_COMPONENT.value
    if signed and wrapped >= (1 << (bits - 1)):
        wrapped -= 1 << bits
    return wrapped


struct BufferAttribute(Copyable, Movable):
    """A flat array of floats, grouped into per-vertex items, or a view of
    a shared interleaved array."""

    # What a read returns: the numbers themselves, or for an integer
    # attribute the stored integers, denormalized when `normalized` is set.
    var data: List[Float32]
    var item_size: Int
    # The type the numbers are stored as, and the integers themselves for
    # an integer type. Empty for `Float32`. See the module docstring.
    var _component: ComponentType
    var _stored: List[Int]
    # three.js's `normalized`: whether a stored integer stands for a number
    # from zero or minus one to one.
    var _normalized: Bool
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
        self._component = FLOAT32_COMPONENT
        self._stored = List[Int]()
        self._normalized = False
        self._buffer = None
        self._offset = 0
        self._mesh_per_attribute = 0

    def __init__(
        out self,
        stored: List[Int],
        item_size: Int,
        component: ComponentType,
        normalized: Bool = False,
    ) raises:
        """Create an attribute from a typed array, three.js's
        `new BufferAttribute( new Uint8Array( stored ), itemSize,
        normalized )` and its kin.

        Each number is stored as the array type stores it: see
        `typed_value`. A `Float32` component stores each as a float.

        Args:
            stored: The numbers, as the typed array holds them.
            item_size: How many numbers each vertex contributes.
            component: The typed array's type.
            normalized: Whether a stored integer stands for a number from
                zero, or minus one for a signed type, to one.

        Raises:
            Error: If the component type is not valid, `item_size` is not
                positive, or the numbers do not divide evenly into items.
        """
        if not component.is_valid():
            raise Error("An attribute needs a valid component type")
        var floats = List[Float32](capacity=len(stored))
        for value in stored:
            floats.append(Float32(value))
        self = BufferAttribute(floats^, item_size)
        self._normalized = normalized
        if component == FLOAT32_COMPONENT:
            return
        self._component = component
        self._stored = List[Int](capacity=len(stored))
        for at in range(len(stored)):
            var kept = typed_value(Float64(stored[at]), component)
            self._stored.append(kept)
            self.data[at] = self._read_of(kept)

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
        self._component = FLOAT32_COMPONENT
        self._stored = List[Int]()
        self._normalized = False
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
        self._component = copy._component
        self._stored = copy._stored.copy()
        self._normalized = copy._normalized
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

    def component_type(self) -> ComponentType:
        """Return the type the numbers are stored as: the typed array
        three.js holds them in."""
        return self._component

    def is_integer(self) -> Bool:
        """Return True if the numbers are stored as integers."""
        return self._component != FLOAT32_COMPONENT

    def is_normalized(self) -> Bool:
        """Return True if a stored integer stands for a number from zero
        or minus one to one, three.js's `normalized`."""
        return self._normalized

    def set_normalized(mut self, normalized: Bool) raises:
        """Set three.js's `normalized`, and read every stored integer
        again with it.

        The stored integers do not change, as in three.js: only what a
        read returns does. A `Float32` attribute reads the same either
        way, and only carries the flag to an exporter.

        Args:
            normalized: Whether a stored integer stands for a number from
                zero or minus one to one.

        Raises:
            Error: If the component type is not valid.
        """
        self._normalized = normalized
        for at in range(len(self._stored)):
            self.data[at] = self._read_of(self._stored[at])

    def stored_values(self) raises -> List[Int]:
        """Return the integers an integer attribute stores, item after
        item: what an exporter writes.

        Returns:
            `count() * item_size` integers.

        Raises:
            Error: If the attribute stores floats.
        """
        if not self.is_integer():
            raise Error("A Float32 attribute stores no integers")
        return self._stored.copy()

    def _read_of(self, stored: Int) raises -> Float32:
        """Return what a read of one stored integer gives.

        Args:
            stored: The integer.

        Returns:
            The integer, denormalized if the attribute is normalized.

        Raises:
            Error: If the component type is not valid.
        """
        if self._normalized:
            return Float32(denormalize(Float64(stored), self._component))
        return Float32(stored)

    def _write(mut self, at: Int, value: Float64) raises:
        """Store one number of a plain attribute, as a typed array stores
        an assignment: the number itself, or the integer it becomes.

        Args:
            at: The position in `data`.
            value: The number, already normalized if it is to be.

        Raises:
            Error: If the component type is not valid.
        """
        if not self.is_integer():
            self.data[at] = Float32(value)
            return
        var kept = typed_value(value, self._component)
        self._stored[at] = kept
        self.data[at] = self._read_of(kept)

    def _raw(self, at: Int) -> Float64:
        """Return the number a plain attribute's array holds at one
        position, three.js's `array[at]`.

        Args:
            at: The position in `data`.

        Returns:
            The stored integer, or the float.
        """
        if self.is_integer():
            return Float64(self._stored[at])
        return Float64(self.data[at])

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
        attribute on it sees the change. An integer attribute stores the
        integer the number becomes, normalized first if it is normalized,
        and a read returns what that integer stands for.

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
        elif self.is_integer():
            var number = Float64(value)
            if self._normalized:
                number = normalize(number, self._component)
            self._write(at, number)
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
        var copied: BufferAttribute
        if self.is_integer():
            copied = BufferAttribute(
                self._stored, self.item_size, self._component, self._normalized
            )
        else:
            copied = BufferAttribute(self.packed(), self.item_size)
            copied._normalized = self._normalized
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
        if self.is_integer():
            var kept = List[Int](capacity=len(index) * self.item_size)
            for entry in range(len(index)):
                var at = self._at(index[entry], 0)
                # An item size is positive: the constructor refuses
                # anything else.
                for offset in range(self.item_size):  # pragma: no branch
                    kept.append(self._stored[at + offset])
            return BufferAttribute(
                kept, self.item_size, self._component, self._normalized
            )
        var data = List[Float32](capacity=len(index) * self.item_size)
        for entry in range(len(index)):
            # An item size is positive: the constructor refuses anything else.
            for offset in range(self.item_size):  # pragma: no branch
                data.append(self.component(index[entry], offset))
        var gathered = BufferAttribute(data^, self.item_size)
        gathered._normalized = self._normalized
        return gathered^

    def _put3(mut self, index: Int, value: Vector3) raises:
        """Replace an item's first three numbers, three.js's `setXYZ`.

        Args:
            index: Which item.
            value: The new numbers.

        Raises:
            Error: If the index is out of range, or the item holds fewer
                than three numbers.
        """
        self.set_component(index, 0, value.x)
        self.set_component(index, 1, value.y)
        self.set_component(index, 2, value.z)

    def apply_matrix3(mut self, matrix: Matrix3) raises:
        """Transform every item by a 3x3 matrix, three.js's
        `applyMatrix3`.

        An item of two numbers is a 2D point, and the matrix's last column
        moves it. An item of three is a vector, multiplied by the matrix.
        An item of any other size is left as it is, as in three.js.

        Args:
            matrix: The transform.

        Raises:
            Error: If an interleaved item reaches past its run.
        """
        if self.item_size == 2:
            for index in range(self.count()):
                var moved = matrix.transform_point(
                    Vector2(self.component(index, 0), self.component(index, 1))
                )
                self.set_component(index, 0, moved.x)
                self.set_component(index, 1, moved.y)
        elif self.item_size == 3:
            for index in range(self.count()):
                self._put3(index, matrix.transform(self.vector3(index)))

    def apply_matrix4(mut self, matrix: Matrix4) raises:
        """Transform every item as a point by a 4x4 matrix, three.js's
        `applyMatrix4`: with its translation, and divided by its w.

        Args:
            matrix: The transform.

        Raises:
            Error: If the attribute holds fewer than three numbers an
                item. three.js reads the next item's numbers then.
        """
        if self.item_size < 3:
            raise Error("A 4x4 matrix moves items of three numbers or more")
        for index in range(self.count()):
            self._put3(index, matrix.transform_point(self.vector3(index)))

    def apply_normal_matrix(mut self, matrix: Matrix3) raises:
        """Transform every item as a normal, three.js's
        `applyNormalMatrix`: multiplied by the matrix and made unit
        length.

        Args:
            matrix: The normal matrix, from `Matrix3.normal_matrix`.

        Raises:
            Error: If the attribute holds fewer than three numbers an item.
        """
        if self.item_size < 3:
            raise Error("A normal matrix turns items of three numbers")
        for index in range(self.count()):
            var turned = matrix.transform(self.vector3(index))
            turned.normalize()
            self._put3(index, turned)

    def transform_direction(mut self, matrix: Matrix4) raises:
        """Transform every item as a direction, three.js's
        `transformDirection`: by the matrix without its translation, and
        made unit length.

        Args:
            matrix: The transform.

        Raises:
            Error: If the attribute holds fewer than three numbers an item.
        """
        if self.item_size < 3:
            raise Error("A direction is an item of three numbers or more")
        for index in range(self.count()):
            var turned = matrix.transform_direction(self.vector3(index))
            turned.normalize()
            self._put3(index, turned)

    def _check_span(self, offset: Int, length: Int) raises:
        """Raise unless a run of the array fits inside it.

        Args:
            offset: The first position.
            length: How many positions.

        Raises:
            Error: If the attribute is interleaved, whose array is shared,
                or the run starts before the array or ends past it, which
                JavaScript's `TypedArray.set` refuses too.
        """
        if Bool(self._buffer):
            raise Error("An interleaved attribute has no array of its own")
        if offset < 0 or offset + length > len(self.data):
            raise Error("The numbers do not fit in the attribute's array")

    def set(mut self, values: List[Float32], offset: Int = 0) raises:
        """Write numbers into the array from a position on, three.js's
        `set`.

        The numbers go in as the array stores them, and are not
        normalized, as in three.js: a `Uint8Array` takes 255 as 255.

        Args:
            values: The numbers.
            offset: The position in the array of the first, from zero.

        Raises:
            Error: If the attribute is interleaved, or the numbers do not
                fit from `offset` on.
        """
        self._check_span(offset, len(values))
        for at in range(len(values)):
            self._write(offset + at, Float64(values[at]))

    def set_stored(mut self, values: List[Int], offset: Int = 0) raises:
        """Write integers into the array from a position on, three.js's
        `set`, with every integer kept whole for a 32-bit type, which a
        `Float32` cannot hold.

        Args:
            values: The numbers, as the typed array stores them.
            offset: The position in the array of the first, from zero.

        Raises:
            Error: If the attribute is interleaved, or the numbers do not
                fit from `offset` on.
        """
        self._check_span(offset, len(values))
        for at in range(len(values)):
            self._write(offset + at, Float64(values[at]))

    def copy_at(
        mut self, index: Int, source: BufferAttribute, source_index: Int
    ) raises:
        """Copy one item of another attribute over one item of this one,
        three.js's `copyAt`.

        The numbers are copied as the arrays store them, and are not
        normalized, as in three.js. This item's size says how many are
        copied, from the start of the source's item.

        Args:
            index: Which item of this attribute to write.
            source: The attribute to read.
            source_index: Which item of `source` to read.

        Raises:
            Error: If either attribute is interleaved, either index is out
                of range, or the source's item holds fewer numbers than
                this one's.
        """
        if source.is_interleaved():
            raise Error("An interleaved attribute has no array of its own")
        if source.item_size < self.item_size:
            raise Error("The source item holds fewer numbers than this one")
        if source_index < 0 or source_index >= source.count():
            raise Error("Attribute vertex index out of range")
        self._check_span(index * self.item_size, self.item_size)
        var read = source_index * source.item_size
        # An item size is positive: the constructor refuses anything else.
        for lane in range(self.item_size):  # pragma: no branch
            self._write(index * self.item_size + lane, source._raw(read + lane))
