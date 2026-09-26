# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 3D grid of values, three.js `examples/jsm/misc/Volume.js`.

A `Volume` holds one value for each voxel of an `x_length` by `y_length`
by `z_length` grid, x fastest, as three.js's `data` does. The values are
held as `Float64`, which holds every value of each typed array three.js
reads exactly. `loaders.nrrd` makes one from a file.

**What is kept.** The grid's lengths, its spacing and axis order, the
matrix from voxel indices to RAS space and its inverse, the value range,
and the window and the thresholds a slice is drawn with.

**What is not ported.** `extractSlice` and `repaintAllSlices` draw a
`VolumeSlice` on a canvas. This port has no canvas. `get_data`,
`access` and `reverse_access` read the voxels a slice would draw.
"""

from math.matrix4 import Matrix4
from std.math import floor, inf, isnan, nan
from std.memory import bitcast


def volume_element_size(type: String) raises -> Int:
    """Return the bytes of one value of a type, as the `Volume`
    constructor's typed array holds it.

    Args:
        type: A type name the constructor knows. Any other is `Uint8`.

    Returns:
        1, 2, 4 or 8.

    Raises:
        Error: For a 64-bit integer type, which three.js refuses.
    """
    var t = type
    var wide: List[String] = [
        "longlong",
        "long long",
        "long long int",
        "signed long long",
        "signed long long int",
        "int64",
        "int64_t",
        "ulonglong",
        "unsigned long long",
        "unsigned long long int",
        "uint64",
        "uint64_t",
    ]
    if t in wide:
        raise Error(
            "Error in Volume constructor : this type is not supported in"
            " JavaScript"
        )
    var names: List[String] = [
        "Int16",
        "int16",
        "short",
        "short int",
        "signed short",
        "signed short int",
        "int16_t",
        "Uint16",
        "uint16",
        "ushort",
        "unsigned short",
        "unsigned short int",
        "uint16_t",
    ]
    if t in names:
        return 2
    names = [
        "Int32",
        "int32",
        "int",
        "signed int",
        "int32_t",
        "Uint32",
        "uint32",
        "uint",
        "unsigned int",
        "uint32_t",
        "Float32",
        "float32",
        "float",
    ]
    if t in names:
        return 4
    names = ["Float64", "float64", "double"]
    if t in names:
        return 8
    return 1


def volume_values(bytes: Span[UInt8, _], type: String) raises -> List[Float64]:
    """Return bytes read as the `Volume` constructor's typed array of a
    type reads them: little-endian.

    Args:
        bytes: The buffer.
        type: A type name the constructor knows. Any other is `Uint8`.

    Returns:
        One value each.

    Raises:
        Error: For a 64-bit integer type, or a buffer that is not whole
            values, which a typed array refuses with a `RangeError`.
    """
    var size = volume_element_size(type)
    if len(bytes) % size != 0:
        raise Error(
            "Volume: "
            + String(len(bytes))
            + " bytes are not whole values of "
            + String(size)
        )
    var signed: List[String] = [
        "Int8",
        "int8",
        "signed char",
        "int8_t",
        "Int16",
        "int16",
        "short",
        "short int",
        "signed short",
        "signed short int",
        "int16_t",
        "Int32",
        "int32",
        "int",
        "signed int",
        "int32_t",
    ]
    var is_signed = type in signed
    var floating: List[String] = [
        "Float32",
        "float32",
        "float",
        "Float64",
        "float64",
        "double",
    ]
    var is_float = type in floating
    var out = List[Float64](capacity=len(bytes) // size)
    for at in range(0, len(bytes), size):
        var bits: UInt64 = 0
        for k in range(size):  # pragma: no branch
            bits |= UInt64(bytes[at + k]) << UInt64(8 * k)
        if is_float and size == 4:
            out.append(Float64(bitcast[DType.float32](UInt32(bits))))
        elif is_float:
            out.append(bitcast[DType.float64](bits))
        elif is_signed and bits >= (UInt64(1) << UInt64(8 * size - 1)):
            out.append(Float64(Int(bits) - (1 << (8 * size))))
        else:
            out.append(Float64(bits))
    return out^


struct Volume(Copyable, Movable):
    """A grid of values, three.js's `Volume`."""

    # The values, x fastest, then y, then z.
    var data: List[Float64]
    # The grid's lengths along each axis. NaN where the header gave none,
    # as three.js reads `undefined`.
    var x_length: Float64
    var y_length: Float64
    var z_length: Float64
    # three.js's `dimensions`: the three lengths.
    var dimensions: List[Float64]
    # Which axis each index runs along, three.js's `axisOrder`. An empty
    # string where three.js's array has a hole.
    var axis_order: List[String]
    # The distance between voxels along each axis.
    var spacing: List[Float64]
    var offset: List[Float64]
    # From voxel indices to RAS space, and back.
    var matrix: Matrix4
    var inverse_matrix: Matrix4
    # The lengths times the spacings, floored, three.js's `RASDimensions`.
    var ras_dimensions: List[Float64]
    # The range of the values that are not NaN, from `compute_min_max`:
    # infinity and minus infinity when there is none.
    var min: Float64
    var max: Float64
    # The values a slice maps to black and white, three.js's `windowLow`
    # and `windowHigh`.
    var window_low: Float64
    var window_high: Float64
    # The values a slice draws between.
    var lower_threshold: Float64
    var upper_threshold: Float64
    # Whether a slice draws labels rather than intensities.
    var segmentation: Bool

    def __init__(out self):
        """Make an empty volume, as three.js's `new Volume()` does."""
        self.data = List[Float64]()
        self.x_length = nan[DType.float64]()
        self.y_length = nan[DType.float64]()
        self.z_length = nan[DType.float64]()
        self.dimensions = List[Float64]()
        self.axis_order = ["x", "y", "z"]
        self.spacing = [1, 1, 1]
        self.offset = [0, 0, 0]
        self.matrix = Matrix4()
        self.inverse_matrix = Matrix4()
        self.ras_dimensions = List[Float64]()
        self.min = inf[DType.float64]()
        self.max = -inf[DType.float64]()
        self.window_low = 0
        self.window_high = 0
        self.lower_threshold = -inf[DType.float64]()
        self.upper_threshold = inf[DType.float64]()
        self.segmentation = False

    def __init__(
        out self,
        x_length: Float64,
        y_length: Float64,
        z_length: Float64,
        type: String,
        bytes: Span[UInt8, _],
    ) raises:
        """Make a volume from a buffer, three.js's `new Volume( xLength,
        yLength, zLength, type, arrayBuffer )`.

        Args:
            x_length: The length along x. Zero or NaN is one.
            y_length: The length along y. Zero or NaN is one.
            z_length: The length along z. Zero or NaN is one.
            type: The type of each value, by one of three.js's names.
                Any other name is `Uint8`, as in three.js.
            bytes: The values, little-endian.

        Raises:
            Error: For a 64-bit integer type, a buffer that is not whole
                values, or a count of values that is not the lengths'
                product, as three.js throws.
        """
        self = Self()
        self.x_length = (
            x_length if x_length == x_length and x_length != 0 else 1
        )
        self.y_length = (
            y_length if y_length == y_length and y_length != 0 else 1
        )
        self.z_length = (
            z_length if z_length == z_length and z_length != 0 else 1
        )
        self.data = volume_values(bytes, type)
        if Float64(len(self.data)) != (
            self.x_length * self.y_length * self.z_length
        ):
            raise Error(
                "Error in Volume constructor, lengths are not matching"
                " arrayBuffer size"
            )

    def get_data(self, i: Float64, j: Float64, k: Float64) -> Float64:
        """Return one voxel's value, three.js's `getData`.

        Args:
            i: The index along x.
            j: The index along y.
            k: The index along z.

        Returns:
            The value, or NaN where three.js reads `undefined`.
        """
        var at = self.access(i, j, k)
        var whole = at == floor(at) and at >= 0
        if whole and at < Float64(len(self.data)):
            return self.data[Int(at)]
        return nan[DType.float64]()

    def access(self, i: Float64, j: Float64, k: Float64) -> Float64:
        """Return where a voxel is in `data`, three.js's `access`.

        Args:
            i: The index along x.
            j: The index along y.
            k: The index along z.

        Returns:
            The index.
        """
        return k * self.x_length * self.y_length + j * self.x_length + i

    def reverse_access(self, index: Float64) -> List[Float64]:
        """Return a voxel's indices from its place in `data`, three.js's
        `reverseAccess`.

        Args:
            index: The place.

        Returns:
            The indices along x, y and z.
        """
        var plane = self.y_length * self.x_length
        var z = floor(index / plane)
        var y = floor((index - z * plane) / self.x_length)
        var x = index - z * plane - y * self.x_length
        return [x, y, z]

    def compute_min_max(mut self) -> Tuple[Float64, Float64]:
        """Set and return the smallest and largest value that is not NaN,
        three.js's `computeMinMax`.

        Returns:
            The smallest and the largest: infinity and minus infinity
            when every value is NaN.
        """
        var low = inf[DType.float64]()
        var high = -inf[DType.float64]()
        for value in self.data:
            if not isnan(value):
                low = min(low, value)
                high = max(high, value)
        self.min = low
        self.max = high
        return (low, high)
