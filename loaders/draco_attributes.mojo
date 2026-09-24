# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The attributes of a Draco file and their prediction, from Draco 1.5.6.

Draco stores most attributes as integers: a float attribute is quantized
first, and a normal is folded onto an octahedron as two integers. Each
value is then predicted from values decoded before it, and only the
correction is stored. This module ports:

- `attributes/geometry_attribute.h` and `point_attribute.h`:
  `DracoAttribute`, the values of one attribute and the value each point
  uses.
- `compression/attributes/prediction_schemes`: the difference,
  parallelogram, multi-parallelogram, constrained multi-parallelogram,
  portable texture coordinate and geometric normal predictions, with the
  wrap and the two octahedron transforms of their corrections.
- `compression/attributes/normal_compression_utils.h`: the octahedron
  arithmetic.
- `attributes/attribute_quantization_transform.cc` and
  `attribute_octahedron_transform.cc`: `dequantize` and
  `octahedron_to_normals`.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**Arithmetic.** Draco predicts in 32-bit and 64-bit integers that wrap,
and divides toward zero. The port does the same with `to_int32` and
`truncated_divide`. The floats of dequantization and of the octahedron
are `Float32`, in the order Draco computes them, so each value is the
same float the WebAssembly decoder gives.

**What is refused.** The deprecated texture coordinate prediction, and a
geometric normal prediction with the wrap transform, which Draco decodes
with an octahedron that was never set up.
"""

from loaders.draco_buffer import (
    MASK32,
    DracoBuffer,
    RAnsBitDecoder,
    draco_require,
    most_significant_bit,
    to_int32,
    truncated_divide,
)
from loaders.draco_mesh import NONE, DracoCornerTable
from std.math import sqrt
from std.memory import bitcast


@no_inline
def product32(a: Float32, b: Float32) -> Float32:
    """Return `a * b`, rounded before any sum uses it.

    The WebAssembly decoder rounds each product on its own. A call that is
    not inlined keeps the compiler from fusing the product into a sum.

    Args:
        a: A number.
        b: A number.

    Returns:
        The product.
    """
    return a * b


@fieldwise_init
struct DracoDataType(Equatable, ImplicitlyCopyable, Writable):
    """The type of the values of a Draco attribute, as a type rather than a
    bare int.

    The attribute decoders refuse one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the eleven types there are.

        Returns:
            True from `DRACO_INT8` to `DRACO_BOOL`.
        """
        return self.value >= DRACO_INT8.value and (
            self.value <= DRACO_BOOL.value
        )

    def size(self) -> Int:
        """Return the bytes of one value of this type.

        Returns:
            One, two, four or eight bytes.
        """
        var sizes: List[Int] = [0, 1, 1, 2, 2, 4, 4, 8, 8, 4, 8, 1]
        return sizes[self.value]

    def is_integral(self) -> Bool:
        """Return True for the integer types and `DRACO_BOOL`.

        Returns:
            False for the two float types.
        """
        return self != DRACO_FLOAT32 and self != DRACO_FLOAT64

    def is_signed(self) -> Bool:
        """Return True for the four signed integer types.

        Returns:
            True for `DRACO_INT8`, `DRACO_INT16`, `DRACO_INT32` and
            `DRACO_INT64`.
        """
        return (self.value - DRACO_INT8.value) % 2 == 0 and (
            self.value <= DRACO_INT64.value
        )


comptime DRACO_INT8 = DracoDataType(1)
comptime DRACO_UINT8 = DracoDataType(2)
comptime DRACO_INT16 = DracoDataType(3)
comptime DRACO_UINT16 = DracoDataType(4)
comptime DRACO_INT32 = DracoDataType(5)
comptime DRACO_UINT32 = DracoDataType(6)
comptime DRACO_INT64 = DracoDataType(7)
comptime DRACO_UINT64 = DracoDataType(8)
comptime DRACO_FLOAT32 = DracoDataType(9)
comptime DRACO_FLOAT64 = DracoDataType(10)
comptime DRACO_BOOL = DracoDataType(11)


@fieldwise_init
struct DracoAttributeType(Equatable, ImplicitlyCopyable, Writable):
    """What a Draco attribute is for, as a type rather than a bare int.

    The attribute decoders refuse one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the five named types.

        Returns:
            True from `DRACO_POSITION` to `DRACO_GENERIC`.
        """
        return self.value >= DRACO_POSITION.value and (
            self.value <= DRACO_GENERIC.value
        )


comptime DRACO_POSITION = DracoAttributeType(0)
comptime DRACO_NORMAL = DracoAttributeType(1)
comptime DRACO_COLOR = DracoAttributeType(2)
comptime DRACO_TEX_COORD = DracoAttributeType(3)
comptime DRACO_GENERIC = DracoAttributeType(4)


@fieldwise_init
struct DracoPrediction(Equatable, ImplicitlyCopyable, Writable):
    """How the values of an attribute are predicted, as a type rather than
    a bare int.

    `decode_draco` reads one that is not valid as a difference, as Draco
    1.5.6 does.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True from `DRACO_PREDICTION_NONE` to the geometric
        normal prediction.

        Returns:
            True for the nine values Draco reads.
        """
        return self.value >= DRACO_PREDICTION_NONE.value and (
            self.value <= DRACO_GEOMETRIC_NORMAL.value
        )


comptime DRACO_PREDICTION_NONE = DracoPrediction(-2)
comptime DRACO_PREDICTION_UNDEFINED = DracoPrediction(-1)
comptime DRACO_DIFFERENCE = DracoPrediction(0)
comptime DRACO_PARALLELOGRAM = DracoPrediction(1)
comptime DRACO_MULTI_PARALLELOGRAM = DracoPrediction(2)
comptime DRACO_TEX_COORDS_DEPRECATED = DracoPrediction(3)
comptime DRACO_CONSTRAINED_MULTI_PARALLELOGRAM = DracoPrediction(4)
comptime DRACO_TEX_COORDS_PORTABLE = DracoPrediction(5)
comptime DRACO_GEOMETRIC_NORMAL = DracoPrediction(6)


@fieldwise_init
struct DracoTransform(Equatable, ImplicitlyCopyable, Writable):
    """How the corrections of a prediction are stored, as a type rather
    than a bare int.

    `decode_draco` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True from `DRACO_TRANSFORM_NONE` to the canonicalized
        octahedron.

        Returns:
            True for the five values Draco reads.
        """
        return self.value >= DRACO_TRANSFORM_NONE.value and (
            self.value <= DRACO_OCTAHEDRON_CANONICALIZED.value
        )


comptime DRACO_TRANSFORM_NONE = DracoTransform(-1)
comptime DRACO_DELTA = DracoTransform(0)
comptime DRACO_WRAP = DracoTransform(1)
comptime DRACO_OCTAHEDRON = DracoTransform(2)
comptime DRACO_OCTAHEDRON_CANONICALIZED = DracoTransform(3)


struct DracoAttribute(Copyable, Movable):
    """The values of one Draco attribute.

    Draco's `PointAttribute`: `count` values of `components` components
    each, stored as the bytes of `data_type`, and the value each point
    uses.
    """

    var attribute_type: DracoAttributeType
    """What the attribute is for."""
    var data_type: DracoDataType
    """The type of each component."""
    var components: Int
    """The components of each value."""
    var normalized: Bool
    """True if integers stand for fractions of their range."""
    var unique_id: Int
    """The id that glTF's `KHR_draco_mesh_compression` names."""
    var bytes: List[UInt8]
    """The values, packed."""
    var count: Int
    """The values."""
    var point_map: List[Int]
    """The value of each point; empty when point `i` uses value `i`."""

    def __init__(
        out self,
        attribute_type: DracoAttributeType,
        data_type: DracoDataType,
        components: Int,
        normalized: Bool,
        unique_id: Int,
    ):
        """Make an attribute with no values.

        Args:
            attribute_type: What it is for.
            data_type: The type of each component.
            components: The components of each value.
            normalized: True if integers stand for fractions.
            unique_id: Its unique id.
        """
        self.attribute_type = attribute_type
        self.data_type = data_type
        self.components = components
        self.normalized = normalized
        self.unique_id = unique_id
        self.bytes = List[UInt8]()
        self.count = 0
        self.point_map = List[Int]()

    def reset(mut self, count: Int):
        """Make room for `count` values, all zero.

        Args:
            count: The values.
        """
        self.count = count
        self.bytes = List[UInt8](
            length=count * self.components * self.data_type.size(), fill=0
        )

    def mapped(self, point: Int) -> Int:
        """Return the value a point uses.

        Args:
            point: The point.

        Returns:
            Its value.
        """
        if len(self.point_map) == 0:
            return point
        return self.point_map[point]

    def set_bits(mut self, index: Int, bits: Int):
        """Store the low bits of an integer as component `index`.

        Args:
            index: The component, counted over all values.
            bits: The value; the bytes past the type's size are dropped.
        """
        var size = self.data_type.size()
        for k in range(size):  # pragma: no branch
            self.bytes[index * size + k] = UInt8((bits >> (8 * k)) & 0xFF)

    def set_float32(mut self, index: Int, value: Float32):
        """Store a float as component `index` of a float attribute.

        Args:
            index: The component, counted over all values.
            value: The value.
        """
        self.set_bits(index, Int(bitcast[DType.uint32](value)))

    def bits_at(self, index: Int) -> Int:
        """Return the stored bits of component `index`, unsigned.

        Args:
            index: The component, counted over all values.

        Returns:
            The bytes of the component as an unsigned integer.
        """
        var size = self.data_type.size()
        var bits = 0
        for k in range(size):  # pragma: no branch
            bits |= Int(self.bytes[index * size + k]) << (8 * k)
        return bits

    def float32_at(self, value: Int, component: Int) -> Float32:
        """Return a component as a `Float32`.

        Draco's `ConvertValue<float>`: a float is cast; an integer is
        cast, then divided by the largest value of its type when the
        attribute is normalized.

        Args:
            value: The value.
            component: The component.

        Returns:
            The component.
        """
        var bits = self.bits_at(value * self.components + component)
        var t = self.data_type
        if t == DRACO_FLOAT32:
            return bitcast[DType.float32](UInt32(bits))
        if t == DRACO_FLOAT64:
            return Float32(bitcast[DType.float64](UInt64(bits)))
        var size = t.size()
        var number: Float32
        var largest: Float32
        if t.is_signed():
            var shift = 64 - 8 * size
            number = Float32((bits << shift) >> shift)
            largest = Float32((1 << (8 * size - 1)) - 1)
        elif size == 8:
            number = Float32(UInt64(bits))
            largest = Float32(UInt64(0xFFFFFFFFFFFFFFFF))
        else:
            number = Float32(bits)
            largest = Float32((1 << (8 * size)) - 1)
        if t == DRACO_BOOL:
            largest = 1
        if self.normalized:
            return number / largest
        return number

    def integer_at(
        self, value: Int, component: Int, out_type: DracoDataType
    ) raises -> Int:
        """Return a component as an integer of another type.

        Draco's `ConvertValue` to an integer type: a value of the type
        asked for is read as it is, and an integer of another type must
        fit it. Draco also rounds a float to an integer; that is refused
        here, since a glTF file that asks for it is not valid.

        Args:
            value: The value.
            component: The component.
            out_type: An integer type of 32 bits or fewer.

        Returns:
            The component.

        Raises:
            Error: If the attribute is a float, or the component does not
                fit `out_type`.
        """
        var t = self.data_type
        draco_require(t.is_integral(), "a float attribute is read as integers")
        var number = self.bits_at(value * self.components + component)
        if t.is_signed():
            var shift = 64 - 8 * t.size()
            number = (number << shift) >> shift
        if t == out_type or t == DRACO_BOOL:
            return number
        var bits = 8 * out_type.size()
        var low = 0
        var high = (1 << bits) - 1
        if out_type.is_signed():
            high = (1 << (bits - 1)) - 1
            if t.is_signed():
                low = -high - 1
        draco_require(
            number >= low and number <= high,
            "a Draco value does not fit its accessor's type",
        )
        return number


struct DracoPortable(Copyable, Movable):
    """The integer values of an attribute before they are transformed
    back, which other attributes predict from.

    Draco's portable attribute: the quantized positions, for instance.
    """

    var values: List[Int]
    """The values, `components` to each entry."""
    var components: Int
    """The components of each entry."""

    def __init__(out self, var values: List[Int], components: Int):
        """Keep values.

        Args:
            values: The values.
            components: The components of each entry.
        """
        self.values = values^
        self.components = components


struct DracoMeshData(Copyable, Movable):
    """What a mesh prediction needs from the connectivity.

    Draco's `MeshPredictionSchemeData`: a table and the order in which the
    attribute's values are stored.
    """

    var table: DracoCornerTable
    """The table of the attribute: the mesh's or the attribute's own."""
    var value_corners: List[Int]
    """The corner at which each value was reached."""
    var vertex_values: List[Int]
    """The value of each vertex of the table."""

    def __init__(
        out self,
        var table: DracoCornerTable,
        var value_corners: List[Int],
        var vertex_values: List[Int],
    ):
        """Keep the table and the order.

        Args:
            table: The table.
            value_corners: The corner of each value.
            vertex_values: The value of each vertex.
        """
        self.table = table^
        self.value_corners = value_corners^
        self.vertex_values = vertex_values^


struct Octahedron(Copyable, Movable):
    """The octahedron that Draco folds unit vectors onto.

    Draco's `OctahedronToolBox`, for `bits` bits a coordinate.
    """

    var bits: Int
    """The bits of each coordinate."""
    var max_quantized: Int
    """`2^bits - 1`."""
    var max_value: Int
    """`2^bits - 2`."""
    var center: Int
    """Half of `max_value`."""
    var scale: Float32
    """`2 / max_value`."""

    def __init__(out self, bits: Int) raises:
        """Set up the octahedron for `bits` bits a coordinate.

        Args:
            bits: From 2 to 30.

        Raises:
            Error: If `bits` is out of range.
        """
        draco_require(
            bits >= 2 and bits <= 30, "normal bits are not from 2 to 30"
        )
        self.bits = bits
        self.max_quantized = (1 << bits) - 1
        self.max_value = self.max_quantized - 1
        self.center = self.max_value // 2
        self.scale = Float32(2) / Float32(self.max_value)

    def to_unit_vector(
        self, s: Int, t: Int
    ) -> Tuple[Float32, Float32, Float32]:
        """Unfold two coordinates into a unit vector.

        Draco's `QuantizedOctahedralCoordsToUnitVector`.

        Args:
            s: The first coordinate.
            t: The second coordinate.

        Returns:
            The vector, or zero when it is too short to normalize.
        """
        var y = product32(Float32(s), self.scale) - Float32(1)
        var z = product32(Float32(t), self.scale) - Float32(1)
        var x = Float32(1) - abs(y) - abs(z)
        var offset = -x
        if offset < 0:
            offset = 0
        y += offset if y < 0 else -offset
        z += offset if z < 0 else -offset
        var norm2 = product32(x, x) + product32(y, y) + product32(z, z)
        # Draco returns zero below a squared length of 1e-6. The unfolded
        # vector has components that sum to one in size, so its squared
        # length is at least a third, and that branch is left out.
        var d = Float32(1) / sqrt(norm2)
        return (x * d, y * d, z * d)

    def canonicalize_coords(self, s: Int, t: Int) -> Tuple[Int, Int]:
        """Draco's `CanonicalizeOctahedralCoords`: one pair for each point
        on the octahedron's border.

        Args:
            s: The first coordinate.
            t: The second coordinate.

        Returns:
            The canonical pair.
        """
        var m = self.max_value
        var c = self.center
        if (s == 0 and t == 0) or (s == 0 and t == m) or (s == m and t == 0):
            return (m, m)
        if s == 0 and t > c:
            return (s, c - (t - c))
        if s == m and t < c:
            return (s, c + (c - t))
        if t == m and s < c:
            return (c + (c - s), t)
        if t == 0 and s > c:
            return (c - (s - c), t)
        return (s, t)

    def vector_to_coords(self, x: Int, y: Int, z: Int) -> Tuple[Int, Int]:
        """Fold an integer vector whose components sum to `center` in
        magnitude.

        Draco's `IntegerVectorToQuantizedOctahedralCoords`.

        Args:
            x: The first component.
            y: The second component.
            z: The third component.

        Returns:
            The canonical coordinates.
        """
        var s: Int
        var t: Int
        if x >= 0:
            s = y + self.center
            t = z + self.center
        else:
            s = abs(z) if y < 0 else self.max_value - abs(z)
            t = abs(y) if z < 0 else self.max_value - abs(y)
        return self.canonicalize_coords(s, t)

    def canonicalize_vector(
        self, x: Int, y: Int, z: Int
    ) -> Tuple[Int, Int, Int]:
        """Scale an integer vector so its components sum to `center` in
        magnitude.

        Draco's `CanonicalizeIntegerVector`, which divides toward zero.

        Args:
            x: The first component.
            y: The second component.
            z: The third component.

        Returns:
            The scaled vector.
        """
        var sum = abs(x) + abs(y) + abs(z)
        if sum == 0:
            return (self.center, y, z)
        var a = to_int32(truncated_divide(x * self.center, sum))
        var b = to_int32(truncated_divide(y * self.center, sum))
        var c = self.center - abs(a) - abs(b)
        if z < 0:
            c = -c
        return (a, b, c)

    def in_diamond(self, s: Int, t: Int) -> Bool:
        """Return True if a centered pair is inside the diamond.

        Args:
            s: The first coordinate.
            t: The second coordinate.

        Returns:
            True when `|s| + |t|` is at most `center`.
        """
        return abs(s) + abs(t) <= self.center

    def invert_diamond(self, s: Int, t: Int) -> Tuple[Int, Int]:
        """Reflect a centered pair between the inside and the outside of
        the diamond.

        Draco's `InvertDiamond`, in its 32-bit unsigned arithmetic.

        Args:
            s: The first coordinate.
            t: The second coordinate.

        Returns:
            The reflected pair.
        """
        var sign_s: Int
        var sign_t: Int
        if s >= 0 and t >= 0:
            sign_s = 1
            sign_t = 1
        elif s <= 0 and t <= 0:
            sign_s = -1
            sign_t = -1
        else:
            sign_s = 1 if s > 0 else -1
            sign_t = 1 if t > 0 else -1
        var corner_s = (sign_s * self.center) & MASK32
        var corner_t = (sign_t * self.center) & MASK32
        var us = (s + s - corner_s) & MASK32
        var ut = (t + t - corner_t) & MASK32
        if sign_s * sign_t >= 0:
            var temp = us
            us = (-ut) & MASK32
            ut = (-temp) & MASK32
        else:
            var temp = us
            us = ut
            ut = temp
        us = (us + corner_s) & MASK32
        ut = (ut + corner_t) & MASK32
        return (
            truncated_divide(to_int32(us), 2),
            truncated_divide(to_int32(ut), 2),
        )

    def mod_max(self, x: Int) -> Int:
        """Wrap a correction into the range of the coordinates.

        Args:
            x: The value.

        Returns:
            The value within `center` of zero.
        """
        if x > self.center:
            return x - self.max_quantized
        if x < -self.center:
            return x + self.max_quantized
        return x


def octahedron_from_max(max_quantized: Int) raises -> Octahedron:
    """Set up an octahedron from its largest quantized value.

    Draco's `set_max_quantized_value`.

    Args:
        max_quantized: `2^bits - 1`, as the file gives it.

    Returns:
        The octahedron.

    Raises:
        Error: If the value is even, or its bits are not from 2 to 30.
    """
    draco_require(max_quantized % 2 != 0, "a normal range is even")
    return Octahedron(most_significant_bit(max_quantized & MASK32) + 1)


struct PredictionTransform(Copyable, Movable):
    """How the corrections of a prediction turn into values.

    Draco's wrap and normal octahedron decoding transforms.
    """

    var kind: DracoTransform
    """The transform."""
    var components: Int
    """The components of each value."""
    var min_value: Int
    """The smallest value, for the wrap transform."""
    var max_value: Int
    """The largest value, for the wrap transform."""
    var max_dif: Int
    """`max_value - min_value + 1`, for the wrap transform."""
    var octahedron: Octahedron
    """The octahedron, for the octahedron transforms."""

    def __init__(out self, kind: DracoTransform, components: Int) raises:
        """Make a transform whose data is not read yet.

        Args:
            kind: The transform.
            components: The components of each value.

        Raises:
            Error: Never; the placeholder octahedron is valid.
        """
        self.kind = kind
        self.components = components
        self.min_value = 0
        self.max_value = 0
        self.max_dif = 0
        self.octahedron = Octahedron(2)

    def read(mut self, mut buffer: DracoBuffer) raises:
        """Read the data of the transform.

        Args:
            buffer: The cursor.

        Raises:
            Error: If the data is not valid.
        """
        if self.kind == DRACO_WRAP:
            self.min_value = buffer.i32()
            self.max_value = buffer.i32()
            draco_require(
                self.min_value <= self.max_value, "a wrap range is empty"
            )
            var dif = self.max_value - self.min_value
            draco_require(dif < 0x7FFFFFFF, "a wrap range is too wide")
            self.max_dif = dif + 1
            return
        self.octahedron = octahedron_from_max(buffer.i32())
        if self.kind == DRACO_OCTAHEDRON_CANONICALIZED:
            _ = buffer.i32()

    def positive(self) -> Bool:
        """Return True if the corrections are stored as unsigned values.

        Returns:
            True for the octahedron transforms.
        """
        return self.kind != DRACO_WRAP

    def apply(self, predicted: List[Int], mut values: List[Int], offset: Int):
        """Add the corrections at `offset` to a prediction, in place.

        Args:
            predicted: The predicted value.
            values: The corrections, which become the values.
            offset: The first component of the value.
        """
        if self.kind == DRACO_WRAP:
            for c in range(self.components):  # pragma: no branch
                var p = min(max(predicted[c], self.min_value), self.max_value)
                var v = to_int32(p + values[offset + c])
                if v > self.max_value:
                    v -= self.max_dif
                elif v < self.min_value:
                    v += self.max_dif
                values[offset + c] = v
            return
        var o = self.octahedron.copy()
        var s = predicted[0] - o.center
        var t = predicted[1] - o.center
        var inside = o.in_diamond(s, t)
        if not inside:
            (s, t) = o.invert_diamond(s, t)
        var rotation = 0
        if self.kind == DRACO_OCTAHEDRON_CANONICALIZED:
            var bottom_left = (s == 0 and t == 0) or (s < 0 and t <= 0)
            if not bottom_left:
                rotation = _rotation_count(s, t)
                (s, t) = _rotate(s, t, rotation)
        var a = o.mod_max(to_int32(s + values[offset]))
        var b = o.mod_max(to_int32(t + values[offset + 1]))
        if rotation != 0:
            (a, b) = _rotate(a, b, 4 - rotation)
        if not inside:
            (a, b) = o.invert_diamond(a, b)
        values[offset] = to_int32(a + o.center)
        values[offset + 1] = to_int32(b + o.center)


def _rotation_count(s: Int, t: Int) -> Int:
    """Draco's `GetRotationCount`, for a pair not in the bottom left."""
    if s == 0:
        return 3 if t > 0 else 1
    if s > 0:
        return 2 if t >= 0 else 1
    return 3


def _rotate(s: Int, t: Int, count: Int) -> Tuple[Int, Int]:
    """Draco's `RotatePoint`, by a quarter turn `count` times."""
    if count == 1:
        return (t, -s)
    if count == 2:
        return (-s, -t)
    return (-t, s)


struct PredictionScheme(Copyable, Movable):
    """A prediction of the values of one attribute.

    Draco's `PredictionSchemeDecoder` and its mesh schemes. Which fields
    are used depends on `method`.
    """

    var method: DracoPrediction
    """The prediction."""
    var transform: PredictionTransform
    """The transform of the corrections."""
    var creases: List[List[Bool]]
    """For the constrained multi-parallelogram prediction: for each count
    of parallelograms, which of them are creases."""
    var orientations: List[Bool]
    """For the texture coordinate prediction: which side of an edge each
    prediction is on."""
    var flips: RAnsBitDecoder
    """For the geometric normal prediction: which predictions flip."""

    def __init__(
        out self, method: DracoPrediction, var transform: PredictionTransform
    ):
        """Make a prediction whose data is not read yet.

        Args:
            method: The prediction.
            transform: The transform of the corrections.
        """
        self.method = method
        self.transform = transform^
        self.creases = List[List[Bool]]()
        self.orientations = List[Bool]()
        self.flips = RAnsBitDecoder()

    def needs_positions(self) -> Bool:
        """Return True if the prediction reads the positions.

        Returns:
            True for the texture coordinate and geometric normal
            predictions.
        """
        return self.method == DRACO_TEX_COORDS_PORTABLE or (
            self.method == DRACO_GEOMETRIC_NORMAL
        )

    def read(mut self, mut buffer: DracoBuffer, corners: Int) raises:
        """Read the data of the prediction and of its transform.

        Args:
            buffer: The cursor, after the corrections.
            corners: The corners of the mesh, which bound the crease
                flags.

        Raises:
            Error: If the data is not valid.
        """
        if self.method == DRACO_CONSTRAINED_MULTI_PARALLELOGRAM:
            for _ in range(4):  # pragma: no branch
                var count = buffer.varint32()
                draco_require(count <= corners, "there are too many creases")
                var flags = List[Bool](capacity=count)
                if count > 0:
                    var bits = RAnsBitDecoder()
                    bits.start(buffer)
                    for _ in range(count):  # pragma: no branch
                        flags.append(bits.bit())
                self.creases.append(flags^)
        elif self.method == DRACO_TEX_COORDS_PORTABLE:
            var count = buffer.i32()
            draco_require(count >= 0, "an orientation count is negative")
            var bits = RAnsBitDecoder()
            bits.start(buffer)
            var last = True
            for _ in range(count):
                if not bits.bit():
                    last = not last
                self.orientations.append(last)
        if self.method == DRACO_GEOMETRIC_NORMAL:
            self.transform.read(buffer)
            self.flips.start(buffer)
            return
        self.transform.read(buffer)

    def compute(
        mut self,
        mut values: List[Int],
        components: Int,
        points: List[Int],
        mesh: Optional[DracoMeshData],
        positions: Optional[DracoPortable],
        position_map: List[Int],
    ) raises:
        """Turn the corrections into values, in place.

        Args:
            values: The corrections, which become the values.
            components: The components of each value.
            points: The point of each value.
            mesh: The connectivity, for a mesh prediction.
            positions: The quantized positions, for a prediction that
                reads them.
            position_map: The position value of each point; empty when
                point `i` uses value `i`.

        Raises:
            Error: If the prediction runs out of data or its numbers
                overflow, as Draco refuses them.
        """
        if mesh is None:
            self._difference(values, components)
            return
        var data = mesh.value().copy()
        if self.method == DRACO_TEX_COORDS_PORTABLE:
            var reader = _Positions(
                positions.value().copy(), position_map.copy(), points.copy()
            )
            self._tex_coords(values, data, reader)
            return
        if self.method == DRACO_GEOMETRIC_NORMAL:
            var reader = _Positions(
                positions.value().copy(), position_map.copy(), points.copy()
            )
            self._normals(values, data, reader)
            return
        self._parallelograms(values, components, data)

    def _difference(self, mut values: List[Int], components: Int):
        """Draco's `PredictionSchemeDeltaDecoder`."""
        var predicted = List[Int](length=components, fill=0)
        var i = 0
        while i < len(values):
            if i > 0:
                for c in range(components):  # pragma: no branch
                    predicted[c] = values[i - components + c]
            self.transform.apply(predicted, values, i)
            i += components

    def _parallelograms(
        mut self,
        mut values: List[Int],
        components: Int,
        data: DracoMeshData,
    ) raises:
        """The parallelogram predictions: one, the mean of all, or the
        mean of those that are not creases."""
        var zero = List[Int](length=components, fill=0)
        self.transform.apply(zero, values, 0)
        var crease_at: List[Int] = [0, 0, 0, 0]
        var table = data.table.copy()
        # A mesh attribute has three values or more. The loop always runs.
        for p in range(1, len(data.value_corners)):  # pragma: no branch
            var start = data.value_corners[p]
            var found = List[List[Int]]()
            if self.method == DRACO_PARALLELOGRAM:
                var one = _parallelogram(p, start, data, values, components)
                if one is not None:
                    found.append(one.value().copy())
            elif self.method == DRACO_MULTI_PARALLELOGRAM:
                var corner = start
                while corner != NONE:
                    var one = _parallelogram(
                        p, corner, data, values, components
                    )
                    if one is not None:
                        found.append(one.value().copy())
                    corner = table.swing_right(corner)
                    if corner == start:
                        corner = NONE
            else:
                found = self._constrained(p, start, data, values, components)
                var used = List[List[Int]]()
                for i in range(len(found)):
                    var context = len(found) - 1
                    var at = crease_at[context]
                    crease_at[context] += 1
                    draco_require(
                        at < len(self.creases[context]),
                        "the crease flags run out",
                    )
                    if not self.creases[context][at]:
                        used.append(found[i].copy())
                found = used^
            var offset = p * components
            if len(found) == 0:
                var previous = List[Int](capacity=components)
                for c in range(components):  # pragma: no branch
                    previous.append(values[offset - components + c])
                self.transform.apply(previous, values, offset)
                continue
            var mean = List[Int](length=components, fill=0)
            for one in found:  # pragma: no branch
                for c in range(components):  # pragma: no branch
                    mean[c] = to_int32(mean[c] + one[c])
            for c in range(components):  # pragma: no branch
                mean[c] = truncated_divide(mean[c], len(found))
            self.transform.apply(mean, values, offset)

    def _constrained(
        self,
        p: Int,
        start: Int,
        data: DracoMeshData,
        values: List[Int],
        components: Int,
    ) -> List[List[Int]]:
        """The parallelograms of the constrained multi-parallelogram
        prediction: left around the vertex, then right, four at most."""
        var found = List[List[Int]]()
        var corner = start
        var first_pass = True
        while corner != NONE:
            var one = _parallelogram(p, corner, data, values, components)
            if one is not None:
                found.append(one.value().copy())
                if len(found) == 4:
                    break
            if first_pass:
                corner = data.table.swing_left(corner)
            else:
                corner = data.table.swing_right(corner)
            if corner == start:
                break
            if corner == NONE and first_pass:
                first_pass = False
                corner = data.table.swing_right(start)
        return found^

    def _tex_coords(
        mut self,
        mut values: List[Int],
        data: DracoMeshData,
        reader: _Positions,
    ) raises:
        """Draco's `MeshPredictionSchemeTexCoordsPortableDecoder`."""
        draco_require(
            self.transform.components == 2,
            "texture coordinates need two components",
        )
        for p in range(len(data.value_corners)):  # pragma: no branch
            var predicted = self._tex_coord(p, values, data, reader)
            self.transform.apply(predicted, values, p * 2)

    def _tex_coord(
        mut self,
        p: Int,
        values: List[Int],
        data: DracoMeshData,
        reader: _Positions,
    ) raises -> List[Int]:
        """Draco's `MeshPredictionSchemeTexCoordsPortablePredictor`."""
        var corner = data.value_corners[p]
        var table = data.table.copy()
        var next = data.vertex_values[table.vertex(table.next(corner))]
        var prev = data.vertex_values[table.vertex(table.previous(corner))]
        if prev < p and next < p:
            var n_u = values[next * 2]
            var n_v = values[next * 2 + 1]
            var p_u = values[prev * 2]
            var p_v = values[prev * 2 + 1]
            if p_u == n_u and p_v == n_v:
                return [p_u, p_v]
            var tip = reader.position(p)
            var next_pos = reader.position(next)
            var prev_pos = reader.position(prev)
            var pn = _sub(prev_pos, next_pos)
            var pn_norm2 = _dot(pn, pn)
            if pn_norm2 != 0:
                var cn = _sub(tip, next_pos)
                var cn_dot_pn = _dot(pn, cn)
                var pn_u = p_u - n_u
                var pn_v = p_v - n_v
                var limit = 0x7FFFFFFFFFFFFFFF
                draco_require(
                    max(abs(n_u), abs(n_v)) <= limit // pn_norm2,
                    "a texture coordinate prediction overflows",
                )
                # Draco 1.5.6 compares the dot product itself, not its size,
                # here and below.
                draco_require(
                    cn_dot_pn <= limit // max(abs(pn_u), abs(pn_v)),
                    "a texture coordinate prediction overflows",
                )
                var x_u = n_u * pn_norm2 + cn_dot_pn * pn_u
                var x_v = n_v * pn_norm2 + cn_dot_pn * pn_v
                var pn_max = max(max(abs(pn[0]), abs(pn[1])), abs(pn[2]))
                draco_require(
                    cn_dot_pn <= limit // pn_max,
                    "a texture coordinate prediction overflows",
                )
                var x_pos = List[Int](capacity=3)
                for k in range(3):  # pragma: no branch
                    x_pos.append(
                        next_pos[k]
                        + truncated_divide(cn_dot_pn * pn[k], pn_norm2)
                    )
                var cx = _sub(tip, x_pos)
                var cx_norm2 = _dot(cx, cx)
                var norm = _int_sqrt(UInt64(cx_norm2) * UInt64(pn_norm2))
                var cx_u = pn_v * norm
                var cx_v = -pn_u * norm
                draco_require(
                    len(self.orientations) > 0, "the orientations run out"
                )
                var orientation = self.orientations.pop()
                var u: Int
                var v: Int
                if orientation:
                    u = x_u + cx_u
                    v = x_v + cx_v
                else:
                    u = x_u - cx_u
                    v = x_v - cx_v
                return [
                    to_int32(truncated_divide(u, pn_norm2)),
                    to_int32(truncated_divide(v, pn_norm2)),
                ]
        # Draco first takes the previous vertex's value here, then always
        # replaces it; that dead store is left out.
        var offset: Int
        if next < p:
            offset = next * 2
        elif p > 0:
            offset = (p - 1) * 2
        else:
            return [0, 0]
        return [values[offset], values[offset + 1]]

    def _normals(
        mut self,
        mut values: List[Int],
        data: DracoMeshData,
        reader: _Positions,
    ) raises:
        """Draco's `MeshPredictionSchemeGeometricNormalDecoder` with the
        area-weighted predictor."""
        var o = self.transform.octahedron.copy()
        var table = data.table.copy()
        for p in range(len(data.value_corners)):  # pragma: no branch
            var corner = data.value_corners[p]
            var center = reader.position(
                data.vertex_values[table.vertex(corner)]
            )
            var normal: List[Int] = [0, 0, 0]
            for c in table.corners_of(corner):  # pragma: no branch
                var next = reader.position(
                    data.vertex_values[table.vertex(table.next(c))]
                )
                var prev = reader.position(
                    data.vertex_values[table.vertex(table.previous(c))]
                )
                var cross = _cross(_sub(next, center), _sub(prev, center))
                for k in range(3):  # pragma: no branch
                    normal[k] += cross[k]
            var sum = _abs_sum(normal)
            var upper = 1 << 29
            if sum > upper:
                var quotient = sum // upper
                for k in range(3):  # pragma: no branch
                    normal[k] = truncated_divide(normal[k], quotient)
            var canonical = o.canonicalize_vector(
                to_int32(normal[0]), to_int32(normal[1]), to_int32(normal[2])
            )
            var x = canonical[0]
            var y = canonical[1]
            var z = canonical[2]
            if self.flips.bit():
                x = -x
                y = -y
                z = -z
            var coords = o.vector_to_coords(x, y, z)
            self.transform.apply([coords[0], coords[1]], values, p * 2)


struct _Positions(Movable):
    """The quantized position of each value of another attribute."""

    var portable: DracoPortable
    var position_map: List[Int]
    var points: List[Int]

    def __init__(
        out self,
        var portable: DracoPortable,
        var position_map: List[Int],
        var points: List[Int],
    ):
        self.portable = portable^
        self.position_map = position_map^
        self.points = points^

    def position(self, entry: Int) -> List[Int]:
        """Draco's `GetPositionForEntryId`."""
        var point = self.points[entry]
        # A mesh prediction runs on an Edgebreaker mesh only, whose
        # attributes always map their points.
        var at = self.position_map[point] * 3
        return [
            self.portable.values[at],
            self.portable.values[at + 1],
            self.portable.values[at + 2],
        ]


def _parallelogram(
    p: Int,
    corner: Int,
    data: DracoMeshData,
    values: List[Int],
    components: Int,
) -> Optional[List[Int]]:
    """Draco's `ComputeParallelogramPrediction`: the vertex across the
    opposite face, mirrored, when all three of its vertices come before
    value `p`."""
    var opposite = data.table.opposite(corner)
    if opposite == NONE:
        return None
    var o = data.vertex_values[data.table.vertex(opposite)]
    var n = data.vertex_values[data.table.vertex(data.table.next(opposite))]
    var r = data.vertex_values[data.table.vertex(data.table.previous(opposite))]
    if o >= p or n >= p or r >= p:
        return None
    var out = List[Int](capacity=components)
    for c in range(components):  # pragma: no branch
        out.append(
            to_int32(
                values[n * components + c]
                + values[r * components + c]
                - values[o * components + c]
            )
        )
    return out^


def _sub(a: List[Int], b: List[Int]) -> List[Int]:
    """Subtract two three-component vectors."""
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def _dot(a: List[Int], b: List[Int]) -> Int:
    """The dot product of two three-component vectors."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(u: List[Int], v: List[Int]) -> List[Int]:
    """The cross product of two three-component vectors."""
    return [
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    ]


def _abs_sum(v: List[Int]) -> Int:
    """Draco's `VectorD::AbsSum`, which stops at the largest integer."""
    var limit = 0x7FFFFFFFFFFFFFFF
    var sum = 0
    for k in range(3):  # pragma: no branch
        var next = abs(v[k])
        if next < 0 or sum > limit - next:
            return limit
        sum += next
    return sum


def _int_sqrt(number: UInt64) -> Int:
    """Draco's `IntSqrt`: the integer square root by Newton's method."""
    if number == 0:
        return 0
    var act = number
    var root = UInt64(1)
    while act >= 2:
        root *= 2
        act //= 4
    while True:
        root = (root + number // root) // 2
        if root * root <= number:
            break
    return Int(root)


def dequantize(
    mut attribute: DracoAttribute,
    portable: List[Int],
    minimums: List[Float32],
    spread: Float32,
    bits: Int,
) raises:
    """Turn quantized integers back into floats.

    Draco's `AttributeQuantizationTransform::InverseTransformAttribute`:
    each value is `q * (range / (2^bits - 1)) + min`, in `Float32`.

    Args:
        attribute: The float attribute, whose values are set.
        portable: The quantized values.
        minimums: The smallest value of each component.
        spread: The largest spread of any component.
        bits: The bits of each quantized value.

    Raises:
        Error: If the attribute is not `Float32`.
    """
    draco_require(
        attribute.data_type == DRACO_FLOAT32,
        "a quantized attribute is not float",
    )
    var delta = spread / Float32((1 << bits) - 1)
    var components = attribute.components
    for i in range(attribute.count * components):
        var value = product32(Float32(portable[i]), delta)
        attribute.set_float32(i, value + minimums[i % components])


def octahedron_to_normals(
    mut attribute: DracoAttribute, portable: List[Int], bits: Int
) raises:
    """Turn octahedron coordinates back into unit normals.

    Draco's `AttributeOctahedronTransform::InverseTransformAttribute`.

    Args:
        attribute: The normal attribute, whose values are set.
        portable: Two coordinates for each normal.
        bits: The bits of each coordinate.

    Raises:
        Error: If the attribute is not three `Float32` components, or the
            bits are not from 2 to 30.
    """
    draco_require(
        attribute.data_type == DRACO_FLOAT32 and attribute.components == 3,
        "a normal attribute is not three floats",
    )
    var o = Octahedron(bits)
    # Normals are integers, which are never empty. The loop always runs.
    for i in range(attribute.count):  # pragma: no branch
        var v = o.to_unit_vector(portable[2 * i], portable[2 * i + 1])
        attribute.set_float32(3 * i, v[0])
        attribute.set_float32(3 * i + 1, v[1])
        attribute.set_float32(3 * i + 2, v[2])
