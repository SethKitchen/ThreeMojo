# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""SHA-256 of town-bake primitives, in the reviewed Python byte order.

    carla_geometry_digest REQUEST

REQUEST is either a little-endian CGD1 file or a JSON object.

A CGD1 file has:

- Four bytes `CGD1`, then a u32 primitive count.
- Each primitive has a u32 field count of 4.
- The fields are `positions`, `normals`, `uvs` and `triangles`, in that
  order. Each field is a u32 name length, the name, a u32 rank, that many
  u32 dimensions, a u64 payload length and the payload bytes.

JSON has `primitives`. Each primitive has those four fields. A field is
`shape` and flat `values` in C order, or a nested array of the same
values. Float fields are float64. Triangles are int64. An empty
dimension contributes no payload bytes.

The digest of one primitive is SHA-256 over each field in order. The field
prefix is the UTF-8 JSON `["name",[dimensions]]` with no spaces, then the
payload. That is `json.dumps([name, shape], separators=(",", ":"))` and the
little-endian contiguous array bytes.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson
from tools._sha256 import Sha256


def digest_bytes(data: Span[UInt8, _]) raises -> List[String]:
    """Return one SHA-256 hex digest for each primitive.

    Args:
        data: A CGD1 geometry request.

    Returns:
        The digests, in primitive order. Each one is 64 lowercase hex
        digits. An empty request returns an empty list.

    Raises:
        Error: If the request is truncated, has trailing bytes, or does
            not list the four fields in order.
    """
    if len(data) < 8:
        raise Error("truncated geometry digest")
    if (
        Int(data[0]) != 67
        or Int(data[1]) != 71
        or Int(data[2]) != 68
        or Int(data[3]) != 49
    ):
        raise Error("geometry digest has a bad header")
    var at = 4
    var count = _u32(data, at)
    var lines = List[String]()
    for _ in range(count):
        var fields = _u32(data, at)
        if fields != 4:
            raise Error("geometry digest needs four fields")
        var state = Sha256()
        for index in range(4):
            var name = _field_name(index)
            var length = _u32(data, at)
            if length != name.byte_length():
                raise Error("geometry field is out of order")
            var got = String()
            for byte in range(length):
                got += chr(Int(data[at + byte]))
            at += length
            if got != name:
                raise Error("geometry field is out of order")
            var rank = _u32(data, at)
            if rank > 16:
                raise Error("geometry rank is too large")
            var dims = List[Int]()
            for _ in range(rank):
                dims.append(_u32(data, at))
            var prefix = _prefix(name, dims)
            state.update(prefix.as_bytes())
            var nbytes = _u64(data, at)
            if nbytes > UInt64(len(data) - at):
                raise Error("truncated geometry digest")
            var size = Int(nbytes)
            state.update(data[at : at + size])
            at += size
        lines.append(state^.hexdigest())
    if at != len(data):
        raise Error("geometry digest has trailing bytes")
    return lines^


def digest_text(text: String) raises -> List[String]:
    """Return one SHA-256 hex digest for each JSON primitive.

    Args:
        text: A JSON object with a `primitives` list. Each primitive has
            `positions`, `normals`, `uvs` and `triangles`. A field has
            `shape` and flat `values`, or it is a nested array.

    Returns:
        The digests, in primitive order. Each one is 64 lowercase hex
        digits. An empty list returns an empty list.

    Raises:
        Error: If the JSON is not that object, a shape does not match its
            values, or a number does not fit in the field.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("digest request is not an object")
    var primitives = doc.at(root, "primitives")
    if doc.kind(primitives) != PY_LIST:
        raise Error("primitives are not a list")
    var lines = List[String]()
    for index in range(doc.length(primitives)):
        var item = doc.item(primitives, index)
        if doc.kind(item) != PY_DICT:
            raise Error("primitive is not an object")
        var state = Sha256()
        for field in range(4):
            var name = _field_name(field)
            var packed = _pack_field(doc, doc.at(item, name), field == 3)
            var prefix = _prefix(name, packed.shape)
            state.update(prefix.as_bytes())
            state.update(Span(packed.bytes))
        lines.append(state^.hexdigest())
    return lines^


def digest_file(path: String) raises -> List[String]:
    """Return the primitive digests stored in a request file.

    Args:
        path: A CGD1 file, or a JSON file whose first value is an object.

    Returns:
        The same digests `digest_bytes` or `digest_text` returns.

    Raises:
        Error: If the file cannot be read, or is not a CGD1 or JSON request.
    """
    var data = Path(path).read_bytes()
    if _is_json(data):
        return digest_text(String(from_utf8=Span(data)))
    return digest_bytes(data)


def _field_name(index: Int) -> String:
    """Return the field name at `index`."""
    if index == 0:
        return "positions"
    if index == 1:
        return "normals"
    if index == 2:
        return "uvs"
    return "triangles"


def _prefix(name: String, dims: List[Int]) -> String:
    """Return the JSON shape prefix for one field."""
    var text = '["' + name + '",['
    for index in range(len(dims)):
        if index > 0:
            text += ","
        text += String(dims[index])
    text += "]]"
    return text^


@fieldwise_init
struct _Packed(Movable):
    var shape: List[Int]
    var bytes: List[UInt8]


def _is_json(data: Span[UInt8, _]) -> Bool:
    """Return whether the request starts with a JSON object."""
    var index = 0
    while index < len(data):
        var byte = data[index]
        if byte == 32 or byte == 9 or byte == 10 or byte == 13:
            index += 1
            continue
        return byte == 123
    return False


def _pack_field(doc: PyJson, node: Int, integral: Bool) raises -> _Packed:
    """Return the little-endian payload of one field."""
    if doc.kind(node) == PY_LIST:
        return _pack_nested(doc, node, integral)
    if doc.kind(node) != PY_DICT:
        raise Error("geometry field is not an object")
    var shape_node = doc.at(node, "shape")
    var values_node = doc.at(node, "values")
    if doc.kind(shape_node) != PY_LIST or doc.kind(values_node) != PY_LIST:
        raise Error("geometry field is not a shape and values")
    var shape = List[Int]()
    var count = 1
    var empty = False
    for index in range(doc.length(shape_node)):
        var dim = _shape_dim(doc, doc.item(shape_node, index))
        shape.append(dim)
        if dim == 0:
            empty = True
        elif count > 268435456 // dim:
            raise Error("geometry field is too large")
        else:
            count *= dim
    if empty:
        count = 0
    if doc.length(values_node) != count:
        raise Error("geometry values do not match the shape")
    var raw = List[UInt8]()
    for index in range(count):
        var item = doc.item(values_node, index)
        if integral:
            _store_i64(raw, _triangle(doc, item))
        else:
            _store_f64(raw, _float(doc, item))
    return _Packed(shape^, raw^)


def _pack_nested(doc: PyJson, node: Int, integral: Bool) raises -> _Packed:
    """Return a nested array packed in C order."""
    var rows = doc.length(node)
    var shape = List[Int]()
    if rows == 0:
        shape.append(0)
        return _Packed(shape^, List[UInt8]())
    var first = doc.item(node, 0)
    if doc.kind(first) != PY_LIST:
        shape.append(rows)
        var raw = List[UInt8]()
        for index in range(rows):
            _store_value(doc, doc.item(node, index), integral, raw)
        return _Packed(shape^, raw^)
    var width = doc.length(first)
    shape.append(rows)
    shape.append(width)
    var raw = List[UInt8]()
    for row in range(rows):
        var line = doc.item(node, row)
        if doc.kind(line) != PY_LIST or doc.length(line) != width:
            raise Error("geometry rows differ")
        for column in range(width):
            _store_value(doc, doc.item(line, column), integral, raw)
    return _Packed(shape^, raw^)


def _store_value(
    doc: PyJson, node: Int, integral: Bool, mut raw: List[UInt8]
) raises:
    """Append one nested value."""
    if integral:
        _store_i64(raw, _triangle(doc, node))
    else:
        _store_f64(raw, _float(doc, node))


def _shape_dim(doc: PyJson, node: Int) raises -> Int:
    """Return one shape dimension."""
    if doc.kind(node) != PY_INT:
        raise Error("geometry dimension is not an integer")
    var value = _int64_text(doc.text(node))
    if value < 0:
        raise Error("geometry dimension is negative")
    if value > 4294967295:
        raise Error("geometry dimension does not fit")
    return value


def _float(doc: PyJson, node: Int) raises -> Float64:
    """Return one float64 payload value."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("geometry value is not a number")


def _triangle(doc: PyJson, node: Int) raises -> Int:
    """Return one int64 triangle index."""
    var kind = doc.kind(node)
    if kind == PY_INT:
        return _int64_text(doc.text(node))
    if kind != PY_FLOAT:
        raise Error("triangle is not a number")
    var value = doc.number(node)
    if value != value:
        raise Error("triangle is not finite")
    if value >= 9223372036854775808.0 or value < -9223372036854775808.0:
        raise Error("triangle does not fit in int64")
    if value >= 0.0:
        return Int(value)
    return -Int(-value)


def _int64_text(text: String) raises -> Int:
    """Return the signed 64-bit integer in `text`."""
    var raw = text.as_bytes()
    if len(raw) == 0:
        raise Error("triangle is not an integer")
    var index = 0
    var negative = False
    if raw[0] == 45:
        negative = True
        index = 1
    if index >= len(raw):
        raise Error("triangle is not an integer")
    var magnitude = UInt64(0)
    var max_mag = UInt64(9223372036854775807)
    if negative:
        max_mag = UInt64(1) << 63
    for offset in range(index, len(raw)):
        var byte = raw[offset]
        if byte < 48 or byte > 57:
            raise Error("triangle is not an integer")
        var digit = UInt64(Int(byte - 48))
        if magnitude > (max_mag - digit) // 10:
            raise Error("triangle does not fit in int64")
        magnitude = magnitude * 10 + digit
    if not negative:
        return Int(magnitude)
    if magnitude == (UInt64(1) << 63):
        return -9223372036854775807 - 1
    return -Int(magnitude)


def _store_f64(mut out: List[UInt8], value: Float64):
    """Append one little-endian float64."""
    var bits = bitcast[DType.uint64](value)
    for index in range(8):
        out.append(UInt8((bits >> (UInt64(8) * UInt64(index))) & 255))


def _store_i64(mut out: List[UInt8], value: Int):
    """Append one little-endian int64."""
    var rest = value
    for _ in range(8):
        out.append(UInt8(rest & 255))
        rest >>= 8


def _u32(data: Span[UInt8, _], mut at: Int) raises -> Int:
    """Read one little-endian u32 and advance `at`."""
    if at < 0 or at > len(data) or 4 > len(data) - at:
        raise Error("truncated geometry digest")
    var value = Int(data[at])
    value |= Int(data[at + 1]) << 8
    value |= Int(data[at + 2]) << 16
    value |= Int(data[at + 3]) << 24
    at += 4
    return value


def _u64(data: Span[UInt8, _], mut at: Int) raises -> UInt64:
    """Read one little-endian u64 and advance `at`."""
    if at < 0 or at > len(data) or 8 > len(data) - at:
        raise Error("truncated geometry digest")
    var value = UInt64(0)
    for index in range(8):
        value |= UInt64(data[at + index]) << UInt64(8 * index)
    at += 8
    return value


def main() raises:
    """Print one digest line for each primitive in the request file."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_geometry_digest REQUEST", file=stderr)
        exit(2)
    try:
        var lines = digest_file(arguments[1])
        for index in range(len(lines)):
            print(lines[index])
    except error:
        print("carla_geometry_digest:", error, file=stderr)
        exit(1)
