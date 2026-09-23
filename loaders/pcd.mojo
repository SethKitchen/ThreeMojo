# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""PCD point clouds, from three.js `examples/jsm/loaders/PCDLoader.js`.

The Point Cloud Library's format: a text header of keyword lines, then the
points as text, as packed little-endian rows, or as LZF-compressed
columns. `parse_pcd` turns a file into a `PcdModel`, and `read_pcd` reads
a file first.

**The header.** `VERSION`, `FIELDS`, `SIZE`, `TYPE`, `COUNT`, `WIDTH`,
`HEIGHT`, `VIEWPOINT` and `POINTS` lines, in any order and any case, then
`DATA ascii`, `DATA binary` or `DATA binary_compressed`. A `#` starts a
comment to the end of its line. `COUNT` is one for every field when it is
missing, and `POINTS` is `WIDTH` times `HEIGHT`. The data starts one byte
after the `DATA` line's format word, as three.js starts it.

**What is read.** What three.js's loader reads:

- `x`, `y` and `z` into `position`.
- `normal_x`, `normal_y` and `normal_z` into `normal`.
- `rgb`: the red, green and blue bytes of a packed 32-bit value, each
  divided by 255 and decoded from sRGB to linear light, into `color`. In
  text, an `F` value is the bits of a `Float32`, as PCL writes it.
- `intensity` into an `intensity` attribute of one value a point.
- `label` into the model's `labels`, which three.js keeps as an
  `Int32BufferAttribute`. A geometry here holds `Float32` values only,
  which would round a label past 2^24.
- Every other field is read past and dropped.

**Where this port differs.** three.js reads a text row by the field's
position and ignores `COUNT`, so a field after one with a count above one
reads the wrong column. This reads each field at the sum of the counts
before it. three.js reads a binary `label` as an `Int32` whatever its
type; this reads it as its type. three.js reads an 8-byte integer as its
low four bytes; this reads all eight.

**What is refused.** A file with no `DATA` line or a format that is not
known; a `SIZE`, `TYPE` or `COUNT` line whose length is not the number of
fields; a type other than `F`, `I` and `U`, or a size its type does not
have; a count below one; a `WIDTH`, `HEIGHT` or `POINTS` that is not a
whole number of zero or more; `x`, `y` and `z`, or the three normals,
not all given; an `rgb` of other than four bytes; a text row with fewer
values than its fields, or a value that is not a number; a coordinate
that is not finite as a `Float32`; a file that ends early; and LZF data
that is not valid or does not fill its declared size. three.js reads
past most of these and yields `NaN`, or throws a `RangeError`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from render.srgb import srgb_to_linear
from std.math import floor, isfinite
from std.memory import bitcast
from std.pathlib import Path

# The attribute `intensity` goes into.
comptime INTENSITY = "intensity"


@fieldwise_init
struct PcdDataFormat(Equatable, ImplicitlyCopyable, Writable):
    """How a PCD file stores its points, as a type rather than a bare int.

    `parse_pcd` reads one of the three through `pcd_data_format`, and
    `PcdHeader.check` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three formats there are."""
        return self.value >= PCD_ASCII.value and (
            self.value <= PCD_BINARY_COMPRESSED.value
        )


# Rows of text, values split by white space.
comptime PCD_ASCII = PcdDataFormat(0)
# Rows of packed little-endian values.
comptime PCD_BINARY = PcdDataFormat(1)
# Columns of packed little-endian values, compressed with LZF.
comptime PCD_BINARY_COMPRESSED = PcdDataFormat(2)


@fieldwise_init
struct PcdFieldType(Equatable, ImplicitlyCopyable, Writable):
    """The type of one PCD field, `F`, `I` or `U`, as a type rather than a
    bare int.

    `decode_pcd_value` refuses a type that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three types there are."""
        return self.value >= PCD_FLOAT.value and (
            self.value <= PCD_UNSIGNED.value
        )

    def has_size(self, size: Int) -> Bool:
        """Return True if a value of this type can take `size` bytes.

        Args:
            size: The bytes a `SIZE` line gives.

        Returns:
            For `F`: four or eight. For `I` and `U`: one, two, four or
            eight. False for a type that is not valid.
        """
        if self == PCD_FLOAT:
            return size == 4 or size == 8
        return self.is_valid() and (
            size == 1 or size == 2 or size == 4 or size == 8
        )


# `F`: an IEEE float.
comptime PCD_FLOAT = PcdFieldType(0)
# `I`: a signed integer.
comptime PCD_SIGNED = PcdFieldType(1)
# `U`: an unsigned integer.
comptime PCD_UNSIGNED = PcdFieldType(2)


def pcd_data_format(name: String) raises -> PcdDataFormat:
    """Return the format a `DATA` line names.

    Args:
        name: `ascii`, `binary` or `binary_compressed`.

    Returns:
        The format.

    Raises:
        Error: If the name is none of the three.
    """
    if name == "ascii":
        return PCD_ASCII
    if name == "binary":
        return PCD_BINARY
    if name == "binary_compressed":
        return PCD_BINARY_COMPRESSED
    raise Error("PCD: a data format that is not known: `" + name + "`")


def pcd_field_type(name: String) raises -> PcdFieldType:
    """Return the type a `TYPE` line names.

    Args:
        name: `F`, `I` or `U`.

    Returns:
        The type.

    Raises:
        Error: If the name is none of the three.
    """
    if name == "F":
        return PCD_FLOAT
    if name == "I":
        return PCD_SIGNED
    if name == "U":
        return PCD_UNSIGNED
    raise Error("PCD: a field type that is not known: `" + name + "`")


def decode_pcd_value(
    bytes: List[UInt8], at: Int, type: PcdFieldType, size: Int
) raises -> Float64:
    """Read one little-endian value, three.js's `_getDataView`.

    Args:
        bytes: The data.
        at: Where the value starts.
        type: Its type.
        size: Its size in bytes.

    Returns:
        The value. A 64-bit integer past 2^53 is rounded.

    Raises:
        Error: If the type is not valid, the size is not one it has, or
            the value runs past the end of the data.
    """
    if not type.has_size(size):
        raise Error(
            "PCD: a field of type "
            + String(type)
            + " cannot take "
            + String(size)
            + " bytes"
        )
    if at < 0 or at + size > len(bytes):
        raise Error(
            "PCD: the data ends inside a value, at byte "
            + String(at)
            + " of "
            + String(len(bytes))
        )
    var raw = UInt64(0)
    # A value takes a byte or more: the loop always runs.
    for index in range(size):  # pragma: no branch
        raw = (raw << 8) | UInt64(bytes[at + size - 1 - index])
    if type == PCD_FLOAT:
        if size == 4:
            return Float64(bitcast[DType.float32](UInt32(raw)))
        return bitcast[DType.float64](raw)
    if type == PCD_UNSIGNED:
        return Float64(raw)
    var bits = size * 8
    if bits == 64:
        return Float64(bitcast[DType.int64](raw))
    var value = Int(raw)
    var half = 1 << (bits - 1)
    if value >= half:
        value -= half * 2
    return Float64(value)


def decompress_lzf(data: List[UInt8], out_length: Int) raises -> List[UInt8]:
    """Expand LZF data, three.js's `decompressLZF`.

    A control byte below 32 starts a run of that many plus one literal
    bytes. Any other is a back reference: its top three bits are the
    length less two, seven meaning a further length byte follows, and its
    low five bits and the next byte are the distance back less one.

    Args:
        data: The compressed bytes.
        out_length: How many bytes they expand to.

    Returns:
        The `out_length` bytes.

    Raises:
        Error: If a run or a reference ends past the input or the output,
            a reference points before the start, or the output is not
            filled.
    """
    var out = List[UInt8](capacity=out_length)
    var at = 0
    while at < len(data):
        var control = Int(data[at])
        at += 1
        if control < 32:
            var run = control + 1
            if len(out) + run > out_length:
                raise Error("PCD: LZF output is larger than its declared size")
            if at + run > len(data):
                raise Error("PCD: LZF data ends inside a run of literals")
            for _ in range(run):  # pragma: no branch
                out.append(data[at])
                at += 1
            continue
        var length = control >> 5
        var back = len(out) - ((control & 0x1F) << 8) - 1
        if at >= len(data):
            raise Error("PCD: LZF data ends inside a back reference")
        if length == 7:
            length += Int(data[at])
            at += 1
            if at >= len(data):
                raise Error("PCD: LZF data ends inside a back reference")
        back -= Int(data[at])
        at += 1
        if len(out) + length + 2 > out_length:
            raise Error("PCD: LZF output is larger than its declared size")
        if back < 0:
            raise Error("PCD: an LZF back reference before the start")
        # A reference copies two bytes or more: the loop always runs.
        for _ in range(length + 2):  # pragma: no branch
            out.append(out[back])
            back += 1
    if len(out) != out_length:
        raise Error(
            "PCD: LZF data expands to "
            + String(len(out))
            + " bytes, and its header declares "
            + String(out_length)
        )
    return out^


struct PcdHeader(Copyable, Movable):
    """A PCD file's header, three.js's `PCDheader`."""

    # The `VERSION` text, or empty.
    var version: String
    # The fields' names, sizes in bytes, types and counts, in file order.
    var fields: List[String]
    var sizes: List[Int]
    var types: List[PcdFieldType]
    var counts: List[Int]
    # The cloud's shape, zero when not given.
    var width: Int
    var height: Int
    # The `VIEWPOINT` text, or empty; kept and not applied, as in three.js.
    var viewpoint: String
    # How many points the file holds.
    var points: Int
    # How the points are stored.
    var data: PcdDataFormat
    # Where the points start in the file.
    var header_length: Int
    # Each field's offset: in values for text, in bytes for binary.
    var offsets: List[Int]
    # The bytes of one binary row: every field's size times its count.
    var row_size: Int

    def __init__(out self):
        """Start an empty text header."""
        self.version = String()
        self.fields = List[String]()
        self.sizes = List[Int]()
        self.types = List[PcdFieldType]()
        self.counts = List[Int]()
        self.width = 0
        self.height = 0
        self.viewpoint = String()
        self.points = 0
        self.data = PCD_ASCII
        self.header_length = 0
        self.offsets = List[Int]()
        self.row_size = 0

    def field(self, name: String) -> Int:
        """Return which field has a name, or -1.

        Args:
            name: The name.

        Returns:
            Its position in `fields`, or -1.
        """
        for index in range(len(self.fields)):
            if self.fields[index] == name:
                return index
        return -1

    def check(self) raises:
        """Refuse a header this loader cannot read.

        Raises:
            Error: If the format is not valid, a list's length is not the
                number of fields, a type has not the size given, a count
                is below one, or the points are negative.
        """
        if not self.data.is_valid():
            raise Error("PCD: a data format that is not valid")
        var count = len(self.fields)
        if len(self.sizes) != count:
            raise Error("PCD: `SIZE` must give one size a field")
        if len(self.types) != count:
            raise Error("PCD: `TYPE` must give one type a field")
        if len(self.counts) != count:
            raise Error("PCD: `COUNT` must give one count a field")
        for index in range(count):
            if not self.types[index].has_size(self.sizes[index]):
                raise Error(
                    "PCD: field `"
                    + self.fields[index]
                    + "` has a size its type does not have: "
                    + String(self.sizes[index])
                )
            if self.counts[index] < 1:
                raise Error(
                    "PCD: field `"
                    + self.fields[index]
                    + "` has a count below one"
                )
        if self.points < 0:
            raise Error("PCD: a negative number of points")


struct PcdModel(Movable):
    """What a PCD file holds: the geometry three.js's `PCDLoader` puts in
    its `Points`, and the labels it keeps as an integer attribute."""

    # The header as read.
    var header: PcdHeader
    # `position`, `normal`, `color` and `intensity`, each when the file
    # has it. A cloud of no points has no attributes.
    var geometry: BufferGeometry
    # One label a point, or none when the file has no `label` field.
    var labels: List[Int]

    def __init__(
        out self,
        var header: PcdHeader,
        var geometry: BufferGeometry,
        var labels: List[Int],
    ):
        """Hold what a file gave.

        Args:
            header: The header.
            geometry: The points.
            labels: The labels.
        """
        self.header = header^
        self.geometry = geometry^
        self.labels = labels^


def _fields(line: String) -> List[String]:
    """Return a line split on white space."""
    var fields = List[String]()
    for piece in line.split():
        fields.append(String(piece))
    return fields^


def _whole(text: String, what: String) raises -> Int:
    """Return a whole number of a header line.

    Args:
        text: The text.
        what: The keyword, for the error.

    Returns:
        The number.

    Raises:
        Error: If the text is not a whole number, or is negative.
    """
    var value: Int
    try:
        value = Int(text)
    except:
        raise Error("PCD: `" + what + "` is not a whole number: " + text)
    if value < 0:
        raise Error("PCD: `" + what + "` is negative: " + text)
    return value


def _is_space(byte: UInt8) -> Bool:
    """Return True for the white space a regular expression's `\\s` takes."""
    return byte == 32 or (byte >= 9 and byte <= 13)


def parse_pcd_header(bytes: List[UInt8]) raises -> PcdHeader:
    """Read a PCD file's header, three.js's `parseHeader`.

    Args:
        bytes: The whole file.

    Returns:
        The header, checked.

    Raises:
        Error: If there is no `DATA` line, its format is not known, a
            header value is not a number, or `PcdHeader.check` refuses it.
    """
    var header = PcdHeader()
    var line_start = 0
    var at = 0
    var data_line = -1
    var points_given = False
    while at <= len(bytes):
        var end = at == len(bytes)
        if not end:
            end = bytes[at] == 10 or bytes[at] == 13
        if not end:
            at += 1
            continue
        var text = String(
            from_utf8_lossy=Span(List[UInt8](bytes[line_start:at]))
        )
        var hash = text.find("#")
        if hash >= 0:
            var head = String(text[byte=:hash])
            text = head^
        var fields = _fields(text)
        if len(fields) > 0:
            var keyword = fields[0].upper()
            if keyword.startswith("DATA"):
                data_line = line_start + text.find(fields[0])
                break
            var value = String(" ").join(List[String](fields[1:]))
            if keyword == "VERSION":
                header.version = value
            elif keyword == "FIELDS":
                header.fields = List[String](fields[1:])
            elif keyword == "SIZE":
                for field in fields[1:]:
                    header.sizes.append(_whole(String(field), "SIZE"))
            elif keyword == "TYPE":
                for field in fields[1:]:
                    header.types.append(pcd_field_type(String(field)))
            elif keyword == "COUNT":
                for field in fields[1:]:
                    header.counts.append(_whole(String(field), "COUNT"))
            elif keyword == "WIDTH":
                header.width = _whole(value, "WIDTH")
            elif keyword == "HEIGHT":
                header.height = _whole(value, "HEIGHT")
            elif keyword == "VIEWPOINT":
                header.viewpoint = value
            elif keyword == "POINTS":
                header.points = _whole(value, "POINTS")
                points_given = True
        at += 1
        line_start = at
    if data_line < 0:
        raise Error("PCD: the file has no `DATA` line")
    # `DATA`, one white space, the format word, one white space.
    var word = data_line + 4
    if word >= len(bytes) or not _is_space(bytes[word]):
        raise Error("PCD: `DATA` must be followed by a space and a format")
    word += 1
    var word_end = word
    while word_end < len(bytes) and not _is_space(bytes[word_end]):
        word_end += 1
    if word_end >= len(bytes):
        raise Error("PCD: the file ends on its `DATA` line")
    header.data = pcd_data_format(
        String(from_utf8_lossy=Span(List[UInt8](bytes[word:word_end])))
    )
    header.header_length = word_end + 1
    if not points_given:
        header.points = header.width * header.height
    if len(header.counts) == 0:
        for _ in range(len(header.fields)):
            header.counts.append(1)
    header.check()
    var sum = 0
    for index in range(len(header.fields)):
        header.offsets.append(sum)
        if header.data == PCD_ASCII:
            sum += header.counts[index]
        else:
            sum += header.sizes[index] * header.counts[index]
    header.row_size = sum
    return header^


def _coordinate(value: Float64, what: String) raises -> Float32:
    """Return a value narrowed to the `Float32` a geometry holds.

    Args:
        value: The value as read.
        what: Its field's name, for the error.

    Returns:
        The value.

    Raises:
        Error: If it is not finite as a `Float32`.
    """
    var narrow = Float32(value)
    if not isfinite(narrow):
        raise Error(
            "PCD: `"
            + what
            + "` must be a finite number, and it is "
            + String(value)
        )
    return narrow


def _triple(header: PcdHeader, a: String, b: String, c: String) raises -> Bool:
    """Return whether the file has three fields, refusing some of them
    without the rest.

    Args:
        header: The header.
        a: The first field's name.
        b: The second's.
        c: The third's.

    Returns:
        True when all three are there, False when none is.

    Raises:
        Error: If one or two are there.
    """
    var count = 0
    # Three names: the loop always runs.
    for name in [a, b, c]:  # pragma: no branch
        if header.field(name) >= 0:
            count += 1
    if count == 1 or count == 2:
        raise Error(
            "PCD: a file must have all of `"
            + a
            + "`, `"
            + b
            + "` and `"
            + c
            + "`, or none"
        )
    return count == 3


def _rgb(packed: Int) -> List[Float32]:
    """Return a packed `rgb` value as linear red, green and blue.

    Args:
        packed: The value; red is bits 16 to 23, green 8 to 15, blue 0
            to 7.

    Returns:
        The three channels, divided by 255 and decoded from sRGB.
    """
    var out = List[Float32]()
    for shift in [16, 8, 0]:  # pragma: no branch
        out.append(srgb_to_linear(Float32((packed >> shift) & 0xFF) / 255))
    return out^


struct _Reader:
    """Reads a field of one point, from text or from binary data."""

    var header: PcdHeader
    # Binary: the data, rows or columns.
    var bytes: List[UInt8]
    # Text: the values of the row being read.
    var values: List[String]

    def __init__(out self, header: PcdHeader, var bytes: List[UInt8]):
        """Start reading.

        Args:
            header: The header.
            bytes: The binary data, or none for text.
        """
        self.header = header.copy()
        self.bytes = bytes^
        self.values = List[String]()

    def at(self, field: Int, point: Int, item: Int) -> Int:
        """Return where a binary value starts.

        Args:
            field: Which field.
            point: Which point.
            item: Which of the field's `COUNT` values.

        Returns:
            The byte offset into the data.
        """
        var size = self.header.sizes[field]
        if self.header.data == PCD_BINARY:
            return (
                point * self.header.row_size
                + self.header.offsets[field]
                + item * size
            )
        return (
            self.header.points * self.header.offsets[field]
            + (point * self.header.counts[field] + item) * size
        )

    def number(mut self, field: Int, point: Int) raises -> Float64:
        """Return a field's first value for a point.

        Args:
            field: Which field.
            point: Which point.

        Returns:
            The value.

        Raises:
            Error: If the data ends first, or a text value is not a
                number.
        """
        if self.header.data != PCD_ASCII:
            return decode_pcd_value(
                self.bytes,
                self.at(field, point, 0),
                self.header.types[field],
                self.header.sizes[field],
            )
        var text = self.values[self.header.offsets[field]]
        try:
            return Float64(text)
        except:
            raise Error(
                "PCD point "
                + String(point)
                + ": `"
                + self.header.fields[field]
                + "` is not a number: "
                + text
            )

    def packed_rgb(mut self, field: Int, point: Int) raises -> Int:
        """Return a point's `rgb` as a packed integer.

        Args:
            field: Which field is `rgb`.
            point: Which point.

        Returns:
            The value, with red in bits 16 to 23.

        Raises:
            Error: If the data ends first, or a text value is not a
                number.
        """
        if self.header.data != PCD_ASCII:
            var at = self.at(field, point, 0)
            return (
                Int(decode_pcd_value(self.bytes, at, PCD_UNSIGNED, 4))
                & 0xFFFFFF
            )
        var value = self.number(field, point)
        if self.header.types[field] == PCD_FLOAT:
            return Int(bitcast[DType.int32](Float32(value)))
        return Int(value)


def parse_pcd(bytes: List[UInt8]) raises -> PcdModel:
    """Read a PCD file's bytes into a point cloud, three.js's
    `PCDLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The header, a geometry, and the labels.

    Raises:
        Error: If the header is refused, the fields are not complete, the
            data ends early, a value is not a number, a coordinate is not
            finite, or LZF data is not valid; see the module docstring.
    """
    var header = parse_pcd_header(bytes)
    var with_position = _triple(header, "x", "y", "z")
    var with_normal = _triple(header, "normal_x", "normal_y", "normal_z")
    var rgb = header.field("rgb")
    var intensity = header.field("intensity")
    var label = header.field("label")
    if rgb >= 0 and header.sizes[rgb] != 4:
        raise Error("PCD: `rgb` must take four bytes")

    var data = List[UInt8]()
    var lines = List[String]()
    var points = header.points
    var start = header.header_length
    if header.data == PCD_ASCII:
        var text = String(
            from_utf8_lossy=Span(List[UInt8](bytes[start : len(bytes)]))
        )
        # A split yields at least one piece: the loop always runs.
        for raw in text.split("\n"):  # pragma: no branch
            var line = String(String(raw).strip())
            if line.byte_length() > 0:
                lines.append(line^)
        points = len(lines)
    elif header.data == PCD_BINARY:
        var end = start + header.points * header.row_size
        if end > len(bytes):
            raise Error(
                "PCD: the file ends before its "
                + String(header.points)
                + " points"
            )
        data = List[UInt8](bytes[start:end])
    else:
        if start + 8 > len(bytes):
            raise Error("PCD: the file ends before its compressed sizes")
        var packed = Int(decode_pcd_value(bytes, start, PCD_UNSIGNED, 4))
        var size = Int(decode_pcd_value(bytes, start + 4, PCD_UNSIGNED, 4))
        if start + 8 + packed > len(bytes):
            raise Error("PCD: the file ends inside its compressed data")
        data = decompress_lzf(
            List[UInt8](bytes[start + 8 : start + 8 + packed]), size
        )
        if len(data) < header.points * header.row_size:
            raise Error(
                "PCD: the compressed data is too small for its "
                + String(header.points)
                + " points"
            )

    var reader = _Reader(header, data^)
    var positions = List[Float32]()
    var normals = List[Float32]()
    var colors = List[Float32]()
    var intensities = List[Float32]()
    var labels = List[Int]()
    var names: List[String] = ["x", "y", "z"]
    var normal_names: List[String] = ["normal_x", "normal_y", "normal_z"]
    for point in range(points):
        if header.data == PCD_ASCII:
            reader.values = _fields(lines[point])
            if len(reader.values) < header.row_size:
                raise Error(
                    "PCD point "
                    + String(point)
                    + ": a row has fewer values than its fields"
                )
        if with_position:
            for name in names:  # pragma: no branch
                positions.append(
                    _coordinate(reader.number(header.field(name), point), name)
                )
        if rgb >= 0:
            colors.extend(_rgb(reader.packed_rgb(rgb, point)))
        if with_normal:
            for name in normal_names:  # pragma: no branch
                normals.append(
                    _coordinate(reader.number(header.field(name), point), name)
                )
        if intensity >= 0:
            intensities.append(
                _coordinate(reader.number(intensity, point), "intensity")
            )
        if label >= 0:
            var value = reader.number(label, point)
            if value != floor(value):
                raise Error(
                    "PCD point "
                    + String(point)
                    + ": `label` is not a whole number: "
                    + String(value)
                )
            labels.append(Int(value))

    var geometry = BufferGeometry()
    if len(positions) > 0:
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    if len(normals) > 0:
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    if len(colors) > 0:
        geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    if len(intensities) > 0:
        geometry.set_attribute(
            String(INTENSITY), BufferAttribute(intensities^, 1)
        )
    return PcdModel(header^, geometry^, labels^)


def read_pcd(path: String) raises -> PcdModel:
    """Read a PCD file into a point cloud.

    Args:
        path: The file to read.

    Returns:
        Its header, geometry and labels; see `parse_pcd`.

    Raises:
        Error: If the file cannot be read, or for anything `parse_pcd`
            refuses.
    """
    return parse_pcd(Path(path).read_bytes())
