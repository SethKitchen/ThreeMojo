# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""PLY files, from three.js `examples/jsm/loaders/PLYLoader.js`.

The Stanford polygon format: a text header that lists elements and their
properties, then the elements' rows, as text or as binary in either byte
order. `parse_ply` turns a file into one indexed `BufferGeometry`, and
`read_ply` reads a file first.

The header is `ply`, `format ascii 1.0`, `format binary_little_endian 1.0`
or `format binary_big_endian 1.0`, then `element name count` lines, each
followed by its properties: `property type name` or `property list
count_type item_type name`. `comment` and `obj_info` lines are skipped,
and `end_header` ends it. Every PLY scalar type is read: `char`, `uchar`,
`short`, `ushort`, `int`, `uint`, `float` and `double`, and their other
names `int8` through `float64`.

What is read is what three.js's loader reads:

- The `vertex` element: `x`, `y` and `z` into `position`, which a file
  must have; `nx`, `ny` and `nz` into `normal`; `s` and `t` into `uv`,
  or `u` and `v`, `texture_u` and `texture_v`, or `tx` and `ty`; and
  `red`, `green` and `blue` into `color`, or their other names, `r` or
  `diffuse_red` and so on. A color is divided by 255 and decoded from
  sRGB to linear light, as three.js reads it, whatever its type. An
  `alpha` or `a` is divided by 255 and kept as the color's fourth
  channel, which three.js leaves out.
- The `face` element: its `vertex_indices` or `vertex_index` list, into
  the geometry's index. A face of more than three corners is cut into a
  fan from its first corner, and so it must be convex, as `loaders.obj`
  requires of an OBJ face. three.js cuts a quad on its other diagonal,
  and leaves out a face of five or more.
- Every other element and property is read past and dropped.

A file without a `face` element is a point cloud: its geometry has no
index, as three.js's has none.

A header that is not PLY, a type or a format that is not known, a row
too short or too long for its properties, a file that ends early, a
value that is not a number of its type, a coordinate that is not finite
as a `Float32`, a vertex with some channels of a color, a normal or a
texture coordinate and not all of them, and a face that names a vertex
the file does not have are refused, naming what is wrong.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from math.vector3 import Vector3
from render.srgb import srgb_to_linear
from std.math import isfinite
from std.memory import bitcast
from std.pathlib import Path


@fieldwise_init
struct PlyFormat(Equatable, ImplicitlyCopyable, Writable):
    """How a PLY file stores its rows, as a type rather than a bare int.

    Three small integers that mean three encodings must not be
    interchangeable with a count. The type stops a bare integer at compile
    time, and `decode_ply_scalar` stops `PlyFormat(7)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three formats there are."""
        return (
            self == PLY_ASCII
            or self == PLY_BINARY_LITTLE_ENDIAN
            or self == PLY_BINARY_BIG_ENDIAN
        )


# Rows as lines of text, values split by white space.
comptime PLY_ASCII = PlyFormat(0)
# Rows as packed values, least significant byte first.
comptime PLY_BINARY_LITTLE_ENDIAN = PlyFormat(1)
# Rows as packed values, most significant byte first.
comptime PLY_BINARY_BIG_ENDIAN = PlyFormat(2)


@fieldwise_init
struct PlyScalar(Equatable, ImplicitlyCopyable, Writable):
    """The type of one PLY value, as a type rather than a bare int.

    `size` refuses a value that is not one of the eight types, which is
    the check every read goes through.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eight types there are."""
        return self.value >= PLY_INT8.value and self.value <= PLY_FLOAT64.value

    def size(self) raises -> Int:
        """Return how many bytes a value of this type takes in a binary
        file.

        Returns:
            One, two, four or eight.

        Raises:
            Error: If this is not one of the eight types.
        """
        if not self.is_valid():
            raise Error("PLY: a scalar type that is not known: " + String(self))
        if self.value <= PLY_UINT8.value:
            return 1
        if self.value <= PLY_UINT16.value:
            return 2
        if self.value <= PLY_FLOAT32.value:
            return 4
        return 8

    def is_integer(self) -> Bool:
        """Return True for the six integer types, False for `float` and
        `double`, and for a type that is not valid."""
        return self.value >= PLY_INT8.value and self.value <= PLY_UINT32.value

    def is_signed(self) -> Bool:
        """Return True for `char`, `short` and `int`, the signed integer
        types."""
        return self.is_integer() and self.value % 2 == 0


comptime PLY_INT8 = PlyScalar(0)
comptime PLY_UINT8 = PlyScalar(1)
comptime PLY_INT16 = PlyScalar(2)
comptime PLY_UINT16 = PlyScalar(3)
comptime PLY_INT32 = PlyScalar(4)
comptime PLY_UINT32 = PlyScalar(5)
comptime PLY_FLOAT32 = PlyScalar(6)
comptime PLY_FLOAT64 = PlyScalar(7)


def ply_format(name: String) raises -> PlyFormat:
    """Return the format a header's `format` line names.

    Args:
        name: `ascii`, `binary_little_endian` or `binary_big_endian`.

    Returns:
        The format.

    Raises:
        Error: If the name is none of the three.
    """
    if name == "ascii":
        return PLY_ASCII
    if name == "binary_little_endian":
        return PLY_BINARY_LITTLE_ENDIAN
    if name == "binary_big_endian":
        return PLY_BINARY_BIG_ENDIAN
    raise Error("PLY: a format that is not known: " + name)


def ply_scalar(name: String) raises -> PlyScalar:
    """Return the type a `property` line names.

    Args:
        name: `char`, `uchar`, `short`, `ushort`, `int`, `uint`, `float`
            or `double`, or `int8`, `uint8`, `int16`, `uint16`, `int32`,
            `uint32`, `float32` or `float64`.

    Returns:
        The type.

    Raises:
        Error: If the name is none of these.
    """
    if name == "char" or name == "int8":
        return PLY_INT8
    if name == "uchar" or name == "uint8":
        return PLY_UINT8
    if name == "short" or name == "int16":
        return PLY_INT16
    if name == "ushort" or name == "uint16":
        return PLY_UINT16
    if name == "int" or name == "int32":
        return PLY_INT32
    if name == "uint" or name == "uint32":
        return PLY_UINT32
    if name == "float" or name == "float32":
        return PLY_FLOAT32
    if name == "double" or name == "float64":
        return PLY_FLOAT64
    raise Error("PLY: a scalar type that is not known: " + name)


def decode_ply_scalar(
    bytes: List[UInt8], at: Int, scalar: PlyScalar, format: PlyFormat
) raises -> Float64:
    """Read one value of a binary PLY file.

    Every type fits a `Float64` exactly, the 32-bit integers included.

    Args:
        bytes: The file.
        at: Where the value starts.
        scalar: Its type.
        format: The file's byte order: `PLY_BINARY_LITTLE_ENDIAN` or
            `PLY_BINARY_BIG_ENDIAN`.

    Returns:
        The value.

    Raises:
        Error: If the type is not valid, the format is not one of the two
            binary ones, or the value runs past the end of the file.
    """
    var size = scalar.size()
    if not format.is_valid() or format == PLY_ASCII:
        raise Error(
            "PLY: only a binary format has binary values, and this one is "
            + String(format)
        )
    if at < 0 or at + size > len(bytes):
        raise Error(
            "PLY: the file ends inside a value, at byte "
            + String(at)
            + " of "
            + String(len(bytes))
        )
    var big = format == PLY_BINARY_BIG_ENDIAN
    var raw = UInt64(0)
    # Every type takes a byte or more: the loop always runs.
    for index in range(size):  # pragma: no branch
        var byte = bytes[at + index] if big else bytes[at + size - 1 - index]
        raw = (raw << 8) | UInt64(byte)
    if scalar == PLY_FLOAT32:
        return Float64(bitcast[DType.float32](UInt32(raw)))
    if scalar == PLY_FLOAT64:
        return bitcast[DType.float64](raw)
    var value = Int(raw)
    var half = 1 << (size * 8 - 1)
    if scalar.is_signed() and value >= half:
        value -= half * 2
    return Float64(value)


@fieldwise_init
struct _Property(Copyable, Movable):
    """One `property` line: a value, or a list of them."""

    var name: String
    # The type of the value, or of each item of a list.
    var scalar: PlyScalar
    var is_list: Bool
    # The type of a list's length. Meaningless for a value.
    var count: PlyScalar


@fieldwise_init
struct _Element(Copyable, Movable):
    """One `element` line and the properties under it."""

    var name: String
    var rows: Int
    var properties: List[_Property]

    def find(self, names: List[String]) raises -> Int:
        """Return which property has one of `names`, trying them in
        order, or -1 when none does.

        Args:
            names: The names to look for.

        Returns:
            The property's position in a row, or -1.

        Raises:
            Error: If the property found is a list.
        """
        # Every call names at least one: the loop always runs.
        for name in names:  # pragma: no branch
            for index in range(len(self.properties)):
                if self.properties[index].name == name:
                    if self.properties[index].is_list:
                        raise Error(
                            "PLY: the property `"
                            + name
                            + "` of `"
                            + self.name
                            + "` must be a single value, not a list"
                        )
                    return index
        return -1


def _find_bytes(bytes: List[UInt8], word: String) -> Int:
    """Return where `word` first starts in the file, or -1.

    Args:
        bytes: The file.
        word: The ASCII text to look for, not empty.

    Returns:
        Its first byte, or -1 when the file does not hold it.
    """
    var text = word.as_bytes()
    for at in range(len(bytes) - len(text) + 1):
        var found = True
        # The word is not empty: the loop always runs.
        for index in range(len(text)):  # pragma: no branch
            if bytes[at + index] != text[index]:
                found = False
                break
        if found:
            return at
    return -1


def _text(bytes: List[UInt8], start: Int, end: Int) raises -> String:
    """Return part of the file as text.

    Args:
        bytes: The file.
        start: The first byte.
        end: One past the last byte.

    Returns:
        The text.

    Raises:
        Error: If the bytes are not UTF-8.
    """
    var part = List[UInt8](bytes[start:end])
    try:
        return String(from_utf8=Span(part))
    except:
        raise Error("PLY: text in the file that is not UTF-8")


def _where(line: Int) -> String:
    """Return the prefix a header error names its line with."""
    return "PLY header line " + String(line) + ": "


def _fields(line: String) -> List[String]:
    """Return a line split on white space."""
    var fields = List[String]()
    for piece in line.split():
        fields.append(String(piece))
    return fields^


def _parse_header(
    text: String, mut elements: List[_Element]
) raises -> PlyFormat:
    """Read the header, up to and not including `end_header`.

    Args:
        text: The header's text.
        elements: Where the elements go, in file order.

    Returns:
        The format.

    Raises:
        Error: If the first line is not `ply`, the format is missing or
            not known, an `element` or `property` line is malformed or
            names a type that is not known, a property comes before any
            element, an element is named twice, a list has a length that
            is not an integer type, or a line is not a header line.
    """
    var lines = List[String]()
    # A split yields at least one piece: the loop always runs.
    for raw in text.split("\n"):  # pragma: no branch
        lines.append(String(String(raw).strip()))
    if lines[0] != "ply":
        raise Error("PLY: the file does not start with `ply`")
    var format = PlyFormat(-1)
    for index in range(1, len(lines)):
        var fields = _fields(lines[index])
        if len(fields) == 0:
            continue
        var line = index + 1
        var keyword = fields[0]
        if keyword == "comment" or keyword == "obj_info":
            continue
        if keyword == "format":
            if len(fields) != 3:
                raise Error(_where(line) + "`format` takes a name and 1.0")
            format = ply_format(fields[1])
        elif keyword == "element":
            if len(fields) != 3:
                raise Error(_where(line) + "`element` takes a name and a count")
            var rows: Int
            try:
                rows = Int(fields[2])
            except:
                raise Error(_where(line) + "not a count: " + fields[2])
            if rows < 0:
                raise Error(_where(line) + "a negative count: " + fields[2])
            for element in elements:
                if element.name == fields[1]:
                    raise Error(
                        _where(line) + "an element named twice: " + fields[1]
                    )
            elements.append(_Element(fields[1], rows, List[_Property]()))
        elif keyword == "property":
            if len(elements) == 0:
                raise Error(_where(line) + "a property before any element")
            if len(fields) == 5 and fields[1] == "list":
                var count = ply_scalar(fields[2])
                if not count.is_integer():
                    raise Error(
                        _where(line)
                        + "a list's length must be an integer type, not "
                        + fields[2]
                    )
                elements[len(elements) - 1].properties.append(
                    _Property(fields[4], ply_scalar(fields[3]), True, count)
                )
            elif len(fields) == 3 and fields[1] != "list":
                elements[len(elements) - 1].properties.append(
                    _Property(
                        fields[2], ply_scalar(fields[1]), False, PLY_UINT8
                    )
                )
            else:
                raise Error(
                    _where(line)
                    + "`property` takes a type and a name, or `list`, two"
                    " types and a name"
                )
        else:
            raise Error(_where(line) + "not a header line: " + keyword)
    if not format.is_valid():
        raise Error("PLY: the header has no `format` line")
    return format


struct _Rows:
    """Reads the values of rows, one after the other, from text or binary."""

    var format: PlyFormat
    # Binary: where the next value starts.
    var at: Int
    # Text: the body's lines, the next to read, and the fields of the row
    # being read and the next of those.
    var lines: List[String]
    var line: Int
    var fields: List[String]
    var field: Int

    def __init__(out self, format: PlyFormat, var lines: List[String], at: Int):
        """Start at the first row.

        Args:
            format: The file's format.
            lines: A text body's lines, or none for a binary one.
            at: Where a binary body starts.
        """
        self.format = format
        self.at = at
        self.lines = lines^
        self.line = 0
        self.fields = List[String]()
        self.field = 0

    def begin(mut self) raises:
        """Start a row: for text, the next line with anything on it.

        Raises:
            Error: If a text body has no line left.
        """
        if self.format != PLY_ASCII:
            return
        while self.line < len(self.lines):
            self.fields = _fields(self.lines[self.line])
            self.line += 1
            self.field = 0
            if len(self.fields) > 0:
                return
        raise Error("the file ends before the row")

    def end(self) raises:
        """Finish a row.

        Raises:
            Error: If a text row has values left over.
        """
        if self.field < len(self.fields):
            raise Error(
                "the row has more values than its properties: "
                + self.fields[self.field]
            )

    def value(
        mut self, bytes: List[UInt8], scalar: PlyScalar
    ) raises -> Float64:
        """Read the next value of the row.

        Args:
            bytes: The file.
            scalar: The value's type.

        Returns:
            The value.

        Raises:
            Error: If the row or the file ends first, or a text value is
                not a number of its type.
        """
        if self.format != PLY_ASCII:
            var value = decode_ply_scalar(bytes, self.at, scalar, self.format)
            self.at += scalar.size()
            return value
        if self.field >= len(self.fields):
            raise Error("the row has fewer values than its properties")
        var field = self.fields[self.field]
        self.field += 1
        if not scalar.is_integer():
            try:
                return Float64(field)
            except:
                raise Error("not a number: " + field)
        var whole: Int
        try:
            whole = Int(field)
        except:
            raise Error("not a whole number: " + field)
        var size = scalar.size()
        var low = 0
        var high = (1 << (size * 8)) - 1
        if scalar.is_signed():
            low = -(1 << (size * 8 - 1))
            high = (1 << (size * 8 - 1)) - 1
        if whole < low or whole > high:
            raise Error(
                "out of range for its type: "
                + field
                + ", which must be from "
                + String(low)
                + " to "
                + String(high)
            )
        return Float64(whole)


def _coordinate(value: Float64, what: String) raises -> Float32:
    """Return a vertex value narrowed to the `Float32` a geometry holds.

    Args:
        value: The value as read.
        what: Its property's name, for the error.

    Returns:
        The value.

    Raises:
        Error: If it is not finite as a `Float32`.
    """
    var narrow = Float32(value)
    if not isfinite(narrow):
        raise Error(
            "`" + what + "` must be a finite number, and it is " + String(value)
        )
    return narrow


def _all_or_none(found: List[Int], what: String) raises -> Bool:
    """Return whether a vertex has every channel of something, refusing
    some of them without the rest.

    Args:
        found: Each channel's position in a row, or -1.
        what: What the channels are, for the error.

    Returns:
        True when every channel is there, False when none is.

    Raises:
        Error: If some are there and some are not.
    """
    var count = 0
    # Every call names two channels or more: the loop always runs.
    for position in found:  # pragma: no branch
        if position >= 0:
            count += 1
    if count > 0 and count < len(found):
        raise Error("PLY: a vertex has some channels of its " + what + " only")
    return count > 0


def _names(*names: String) -> List[String]:
    """Return the names given, as a list."""
    var out = List[String]()
    # Every call names one or more: the loop always runs.
    for name in names:  # pragma: no branch
        out.append(name)
    return out^


def _check_convex(points: List[Vector3], face: Int) raises:
    """Refuse a face of four or more corners that a fan from its first
    corner would not cover: one that is not convex, or has no area.

    The same test as `loaders.obj`'s: the face's normal is Newell's sum
    over its edges, and each corner of a convex face turns the same way
    about it, within a millionth of straight.

    Args:
        points: The corners, in order.
        face: Which face, for the error.

    Raises:
        Error: If the face has no area, or a corner turns the wrong way.
    """
    var count = len(points)
    var normal = Vector3(0, 0, 0)
    # A face checked here has four corners or more: both loops always run.
    for index in range(count):  # pragma: no branch
        var a = points[index]
        var b = points[(index + 1) % count]
        normal.x += (a.y - b.y) * (a.z + b.z)
        normal.y += (a.z - b.z) * (a.x + b.x)
        normal.z += (a.x - b.x) * (a.y + b.y)
    var area = normal.length()
    if area == 0:
        raise Error("PLY face " + String(face) + ": a face has no area")
    for index in range(count):  # pragma: no branch
        var a = points[index]
        var b = points[(index + 1) % count]
        var c = points[(index + 2) % count]
        var turn = b - a
        turn.cross(c - b)
        if turn.dot(normal) < -1e-6 * area * area:
            raise Error(
                "PLY face "
                + String(face)
                + ": a face is not convex, and only a convex face cuts into"
                " a fan of triangles"
            )


def parse_ply(bytes: List[UInt8]) raises -> BufferGeometry:
    """Read a PLY file's bytes into a geometry.

    Args:
        bytes: The whole file.

    Returns:
        A geometry with `position`, and `normal`, `uv` and `color` when
        the vertices have them, indexed by the faces when the file has a
        `face` element.

    Raises:
        Error: If the header is refused (see the module docstring), the
            file has no `vertex` element or its vertices no `x`, `y` and
            `z`, a row is short, long or not numbers of its types, the
            file ends early, a coordinate is not finite, a vertex has only
            some channels of a normal, a texture coordinate or a color, or
            a face has fewer than three corners, names a vertex the file
            does not have, or is not convex.
    """
    var end = _find_bytes(bytes, "end_header")
    if end < 0:
        raise Error("PLY: the file has no `end_header`")
    var elements = List[_Element]()
    var format = _parse_header(_text(bytes, 0, end), elements)
    var body = end + 10  # the length of `end_header`
    if body < len(bytes) and bytes[body] == 13:
        body += 1
    if body < len(bytes) and bytes[body] == 10:
        body += 1
    var lines = List[String]()
    if format == PLY_ASCII:
        var text = _text(bytes, body, len(bytes))
        # A split yields at least one piece: the loop always runs.
        for raw in text.split("\n"):  # pragma: no branch
            lines.append(String(raw))
    var rows = _Rows(format, lines^, body)

    var vertices = -1
    for index in range(len(elements)):
        if elements[index].name == "vertex":
            vertices = index
    if vertices < 0:
        raise Error("PLY: the file has no `vertex` element")
    ref vertex = elements[vertices]
    var x = vertex.find(_names("x"))
    var y = vertex.find(_names("y"))
    var z = vertex.find(_names("z"))
    if x < 0 or y < 0 or z < 0:
        raise Error("PLY: a vertex must have `x`, `y` and `z`")
    var nx = vertex.find(_names("nx"))
    var ny = vertex.find(_names("ny"))
    var nz = vertex.find(_names("nz"))
    var with_normal = _all_or_none([nx, ny, nz], "normal")
    var s = vertex.find(_names("s", "u", "texture_u", "tx"))
    var t = vertex.find(_names("t", "v", "texture_v", "ty"))
    var with_uv = _all_or_none([s, t], "texture coordinate")
    var r = vertex.find(_names("red", "diffuse_red", "r", "diffuse_r"))
    var g = vertex.find(_names("green", "diffuse_green", "g", "diffuse_g"))
    var b = vertex.find(_names("blue", "diffuse_blue", "b", "diffuse_b"))
    var with_color = _all_or_none([r, g, b], "color")
    var a = vertex.find(_names("alpha", "a"))
    if a >= 0 and not with_color:
        raise Error("PLY: a vertex has an alpha and no red, green and blue")
    var channels = 4 if a >= 0 else 3
    var vertex_count = vertex.rows

    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var colors = List[Float32]()
    # Every face's corners, one after the other, and how many each has.
    var corners = List[Int]()
    var sizes = List[Int]()
    # The `vertex` element is there: the loop always runs.
    for element in elements:  # pragma: no branch
        var is_vertex = element.name == "vertex"
        var is_face = element.name == "face"
        var list = -1
        if is_face:
            for index in range(len(element.properties)):
                ref property = element.properties[index]
                if (
                    property.name == "vertex_indices"
                    or property.name == "vertex_index"
                ):
                    list = index
            if list < 0:
                raise Error(
                    "PLY: a face must have `vertex_indices` or `vertex_index`"
                )
            if not element.properties[list].is_list:
                raise Error("PLY: a face's vertex indices must be a list")
            if not element.properties[list].scalar.is_integer():
                raise Error(
                    "PLY: a face's vertex indices must be an integer type"
                )
        for row in range(element.rows):
            try:
                rows.begin()
                var values = List[Float64]()
                for index in range(len(element.properties)):
                    ref property = element.properties[index]
                    if not property.is_list:
                        values.append(rows.value(bytes, property.scalar))
                        continue
                    var length = Int(rows.value(bytes, property.count))
                    if length < 0:
                        raise Error("a list with a negative length")
                    values.append(Float64(length))
                    for _ in range(length):
                        var item = rows.value(bytes, property.scalar)
                        if index == list:
                            corners.append(Int(item))
                    if index == list:
                        sizes.append(length)
                rows.end()
                if is_vertex:
                    positions.append(_coordinate(values[x], "x"))
                    positions.append(_coordinate(values[y], "y"))
                    positions.append(_coordinate(values[z], "z"))
                    if with_normal:
                        normals.append(_coordinate(values[nx], "nx"))
                        normals.append(_coordinate(values[ny], "ny"))
                        normals.append(_coordinate(values[nz], "nz"))
                    if with_uv:
                        uvs.append(_coordinate(values[s], "s"))
                        uvs.append(_coordinate(values[t], "t"))
                    if with_color:
                        # Three channels: the loop always runs.
                        for channel in [r, g, b]:  # pragma: no branch
                            var value = _coordinate(
                                values[channel], "red, green or blue"
                            )
                            colors.append(srgb_to_linear(value / 255))
                        if a >= 0:
                            colors.append(_coordinate(values[a], "alpha") / 255)
            except reason:
                raise Error(
                    "PLY element `"
                    + element.name
                    + "` row "
                    + String(row)
                    + ": "
                    + String(reason)
                )

    var index = List[Int]()
    var first = 0
    for face in range(len(sizes)):
        var count = sizes[face]
        if count < 3:
            raise Error(
                "PLY face " + String(face) + ": a face needs three corners"
            )
        # A face has three corners or more here, and makes a triangle or
        # more: this loop and the three below always run.
        for corner in range(first, first + count):  # pragma: no branch
            if corners[corner] < 0 or corners[corner] >= vertex_count:
                raise Error(
                    "PLY face "
                    + String(face)
                    + ": it names vertex "
                    + String(corners[corner])
                    + ", and the file has "
                    + String(vertex_count)
                )
        if count > 3:
            var points = List[Vector3]()
            for corner in range(first, first + count):  # pragma: no branch
                var at = corners[corner] * 3
                points.append(
                    Vector3(positions[at], positions[at + 1], positions[at + 2])
                )
            _check_convex(points, face)
        for triangle in range(count - 2):  # pragma: no branch
            index.append(corners[first])
            index.append(corners[first + triangle + 1])
            index.append(corners[first + triangle + 2])
        first += count

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    if with_normal:
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    if with_uv:
        geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    if with_color:
        geometry.set_attribute(
            String(COLOR), BufferAttribute(colors^, channels)
        )
    geometry.set_index(index^)
    return geometry^


def read_ply(path: String) raises -> BufferGeometry:
    """Read a PLY file into a geometry.

    Args:
        path: The file to read.

    Returns:
        Its geometry; see `parse_ply`.

    Raises:
        Error: If the file cannot be read, or for anything `parse_ply`
            refuses.
    """
    return parse_ply(Path(path).read_bytes())
