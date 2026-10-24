# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Split CARLA vehicle lamps into head lamps and tail lamps.

    carla_gltf_lamps INPUT.gltf INPUT.bin OUTPUT.gltf OUTPUT.bin

A lamp triangle whose center is in front of the model's middle becomes a
head lamp. One behind the middle becomes a tail lamp. The new index
lists are little-endian unsigned 32-bit values, aligned to 4 bytes. A
model with no lamp material is unchanged.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)


def split_lamps(mut doc: PyJson, data: Span[UInt8, _]) raises -> List[UInt8]:
    """Split lamp primitives and return the buffer, including new indices.

    Args:
        doc: The glTF document. A model with lamps is edited.
        data: The current buffer.

    Returns:
        The buffer. It is `data` when the model has no lamp material.

    Raises:
        Error: If a lamp primitive is missing positions, indices, or the
            bytes those accessors name.
    """
    var out = _copy(data)
    var root = doc.root
    var materials = doc.find(root, "materials")
    if materials == MISSING:
        return out^
    var lamps = List[Int]()
    for index in range(doc.length(materials)):
        var material = doc.item(materials, index)
        var extras = doc.find(material, "extras")
        if extras == MISSING:
            continue
        var tag = doc.find(extras, "carla")
        if (
            tag != MISSING
            and doc.kind(tag) == PY_STR
            and doc.text(tag) == "lamps"
        ):
            lamps.append(index)
    if len(lamps) == 0:
        return out^
    var meshes = doc.at(root, "meshes")
    var low = Float64(0)
    var high = Float64(0)
    var seen = False
    for mesh_index in range(doc.length(meshes)):
        var primitives = doc.at(doc.item(meshes, mesh_index), "primitives")
        for primitive_index in range(doc.length(primitives)):
            var primitive = doc.item(primitives, primitive_index)
            var attributes = doc.at(primitive, "attributes")
            var position = doc.at(attributes, "POSITION")
            var accessor = doc.item(
                doc.at(root, "accessors"), _int(doc, position)
            )
            var minimum = _float(doc, doc.item(doc.at(accessor, "min"), 0))
            var maximum = _float(doc, doc.item(doc.at(accessor, "max"), 0))
            if not seen or minimum < low:
                low = minimum
            if not seen or maximum > high:
                high = maximum
            seen = True
    if not seen:
        raise Error("lamp model has no positions")
    var middle = (low + high) / 2
    var heads = lamps[0]
    doc.set_item(materials, heads, _head_material(doc))
    doc.append(materials, _tail_material(doc))
    var tails = doc.length(materials) - 1
    for mesh_index in range(doc.length(meshes)):
        var mesh = doc.item(meshes, mesh_index)
        var primitives = doc.at(mesh, "primitives")
        var split = doc.new_list()
        for primitive_index in range(doc.length(primitives)):
            var primitive = doc.item(primitives, primitive_index)
            var material = doc.find(primitive, "material")
            var indices_node = doc.find(primitive, "indices")
            if (
                material == MISSING
                or indices_node == MISSING
                or not _is_lamp(_int(doc, material), lamps)
            ):
                doc.append(split, primitive)
                continue
            var indices = _read_ints(doc, data, _int(doc, indices_node))
            var positions = _read_floats(
                doc,
                data,
                _int(doc, doc.at(doc.at(primitive, "attributes"), "POSITION")),
            )
            var front = List[Int]()
            var back = List[Int]()
            var triangle = 0
            while triangle + 2 < len(indices):
                var first = indices[triangle]
                var second = indices[triangle + 1]
                var third = indices[triangle + 2]
                var x = (
                    _component(positions, first)
                    + _component(positions, second)
                    + _component(positions, third)
                ) / 3
                if x >= middle:
                    front.append(first)
                    front.append(second)
                    front.append(third)
                else:
                    back.append(first)
                    back.append(second)
                    back.append(third)
                triangle += 3
            _add_part(doc, out, split, primitive, heads, front)
            _add_part(doc, out, split, primitive, tails, back)
        doc.set(mesh, "primitives", split)
    var buffers = doc.at(root, "buffers")
    doc.set(doc.item(buffers, 0), "byteLength", doc.new_int(len(out)))
    return out^


def _is_lamp(material: Int, lamps: List[Int]) -> Bool:
    """Return whether `material` is one of the lamp materials."""
    for index in range(len(lamps)):
        if lamps[index] == material:
            return True
    return False


def _component(positions: List[Float64], index: Int) raises -> Float64:
    """Return the x coordinate of vertex `index`."""
    var at = 3 * index
    if at < 0 or at >= len(positions):
        raise Error("lamp index is outside the position accessor")
    return positions[at]


def _add_part(
    mut doc: PyJson,
    mut out: List[UInt8],
    split: Int,
    primitive: Int,
    material: Int,
    part: List[Int],
) raises:
    """Append one split primitive when `part` has indices."""
    if len(part) == 0:
        return
    _align(out)
    var view = doc.new_dict()
    doc.set(view, "buffer", doc.new_int(0))
    doc.set(view, "byteOffset", doc.new_int(len(out)))
    doc.set(view, "byteLength", doc.new_int(4 * len(part)))
    doc.set(view, "target", doc.new_int(34963))
    var views = doc.at(doc.root, "bufferViews")
    doc.append(views, view)
    for index in range(len(part)):
        _append_u32(out, part[index])
    var accessor = doc.new_dict()
    doc.set(accessor, "bufferView", doc.new_int(doc.length(views) - 1))
    doc.set(accessor, "componentType", doc.new_int(5125))
    doc.set(accessor, "count", doc.new_int(len(part)))
    doc.set(accessor, "type", doc.new_str("SCALAR"))
    var accessors = doc.at(doc.root, "accessors")
    doc.append(accessors, accessor)
    var piece = doc.copy_node(primitive)
    doc.set(piece, "indices", doc.new_int(doc.length(accessors) - 1))
    doc.set(piece, "material", doc.new_int(material))
    doc.append(split, piece)


def _head_material(mut doc: PyJson) raises -> Int:
    """Return the head-lamp material object."""
    return _lamp_material(
        doc, "CarlaHeadLamps", "0.85", "0.85", "0.8", "0.15", "heads"
    )


def _tail_material(mut doc: PyJson) raises -> Int:
    """Return the tail-lamp material object."""
    return _lamp_material(
        doc, "CarlaTailLamps", "0.3", "0.01", "0.01", "0.2", "tails"
    )


def _lamp_material(
    mut doc: PyJson,
    name: String,
    red: String,
    green: String,
    blue: String,
    roughness: String,
    tag: String,
) raises -> Int:
    """Return one replacement lamp material."""
    var color = doc.new_list()
    doc.append(color, doc.new_float(parse_float(red)))
    doc.append(color, doc.new_float(parse_float(green)))
    doc.append(color, doc.new_float(parse_float(blue)))
    doc.append(color, doc.new_int(1))
    var pbr = doc.new_dict()
    doc.set(pbr, "baseColorFactor", color)
    doc.set(pbr, "metallicFactor", doc.new_float(parse_float("0.0")))
    doc.set(pbr, "roughnessFactor", doc.new_float(parse_float(roughness)))
    var extras = doc.new_dict()
    doc.set(extras, "carla", doc.new_str(tag))
    var material = doc.new_dict()
    doc.set(material, "name", doc.new_str(name))
    doc.set(material, "pbrMetallicRoughness", pbr)
    doc.set(material, "extras", extras)
    return material


def _read_ints(
    doc: PyJson, data: Span[UInt8, _], accessor_index: Int
) raises -> List[Int]:
    """Return an accessor's integer values."""
    var values = List[Int]()
    var raw = _read_raw(doc, data, accessor_index)
    for index in range(len(raw)):
        values.append(raw[index])
    return values^


def _read_floats(
    doc: PyJson, data: Span[UInt8, _], accessor_index: Int
) raises -> List[Float64]:
    """Return an accessor's values as doubles."""
    var accessor = doc.item(doc.at(doc.root, "accessors"), accessor_index)
    var kind = _int(doc, doc.at(accessor, "componentType"))
    var view = doc.item(
        doc.at(doc.root, "bufferViews"),
        _int(doc, doc.at(accessor, "bufferView")),
    )
    var width = _width(doc.text(doc.at(accessor, "type")))
    var start = _offset(doc, view) + _offset(doc, accessor)
    var count = _int(doc, doc.at(accessor, "count")) * width
    var size = _component_size(kind)
    if start < 0 or count < 0 or start + count * size > len(data):
        raise Error("lamp accessor is outside the buffer")
    var values = List[Float64]()
    for index in range(count):
        var at = start + index * size
        if kind == 5126:
            values.append(_f32(data, at))
        else:
            values.append(Float64(_unsigned(data, at, size)))
    return values^


def _read_raw(
    doc: PyJson, data: Span[UInt8, _], accessor_index: Int
) raises -> List[Int]:
    """Return an accessor's unsigned components as integers."""
    var accessor = doc.item(doc.at(doc.root, "accessors"), accessor_index)
    var kind = _int(doc, doc.at(accessor, "componentType"))
    if kind == 5126:
        raise Error("lamp indices are floating point")
    var view = doc.item(
        doc.at(doc.root, "bufferViews"),
        _int(doc, doc.at(accessor, "bufferView")),
    )
    var width = _width(doc.text(doc.at(accessor, "type")))
    var start = _offset(doc, view) + _offset(doc, accessor)
    var count = _int(doc, doc.at(accessor, "count")) * width
    var size = _component_size(kind)
    if start < 0 or count < 0 or start + count * size > len(data):
        raise Error("lamp accessor is outside the buffer")
    var values = List[Int]()
    for index in range(count):
        values.append(_unsigned(data, start + index * size, size))
    return values^


def _offset(doc: PyJson, node: Int) raises -> Int:
    """Return `byteOffset`, or 0 when the key is absent."""
    var offset = doc.find(node, "byteOffset")
    if offset == MISSING:
        return 0
    return _int(doc, offset)


def _width(text: String) raises -> Int:
    """Return the component count of a glTF type."""
    if text == "SCALAR":
        return 1
    if text == "VEC2":
        return 2
    if text == "VEC3":
        return 3
    if text == "VEC4":
        return 4
    raise Error("unknown glTF accessor type: " + text)


def _component_size(kind: Int) raises -> Int:
    """Return the byte width of a component type."""
    if kind == 5121:
        return 1
    if kind == 5123:
        return 2
    if kind == 5125 or kind == 5126:
        return 4
    raise Error("unknown glTF component type: " + String(kind))


def _unsigned(data: Span[UInt8, _], at: Int, size: Int) -> Int:
    """Return a little-endian unsigned integer."""
    var value = 0
    for index in range(size):
        value |= Int(data[at + index]) << (8 * index)
    return value


def _f32(data: Span[UInt8, _], at: Int) -> Float64:
    """Return a little-endian float32 promoted to a double."""
    var bits = UInt32(_unsigned(data, at, 4))
    return Float64(bitcast[DType.float32](bits))


def _append_u32(mut out: List[UInt8], value: Int):
    """Append a little-endian unsigned 32-bit integer."""
    var rest = value
    for _ in range(4):
        out.append(UInt8(rest & 255))
        rest >>= 8


def _align(mut out: List[UInt8]):
    """Pad `out` to a multiple of 4."""
    var extra = len(out) % 4
    if extra < 0:
        extra += 4
    if extra != 0:
        extra = 4 - extra
    for _ in range(extra):
        out.append(0)


def _int(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    var text = doc.text(node)
    var bytes = text.as_bytes()
    var start = 0
    var negative = False
    if len(bytes) > 0 and bytes[0] == 45:
        negative = True
        start = 1
    var value = 0
    for index in range(start, len(bytes)):
        var digit = Int(bytes[index]) - 48
        if digit < 0 or digit > 9:
            raise Error("glTF integer is not decimal: " + text)
        value = value * 10 + digit
    if negative:
        return -value
    return value


def _float(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as a double."""
    if doc.kind(node) == PY_FLOAT:
        return doc.number(node)
    return Float64(_int(doc, node))


def _copy(data: Span[UInt8, _]) -> List[UInt8]:
    """Return a copy of `data`."""
    var out = List[UInt8]()
    for index in range(len(data)):
        out.append(data[index])
    return out^


def _dumps(doc: PyJson) raises -> String:
    """Return JSON with Python's default separators and key order."""
    var out = List[UInt8]()
    _emit(doc, doc.root, out)
    return String(unsafe_from_utf8=Span(out))


def _emit(doc: PyJson, node: Int, mut out: List[UInt8]) raises:
    """Append one JSON value."""
    var kind = doc.kind(node)
    if kind == PY_DICT:
        out.append(0x7B)
        for index in range(doc.length(node)):
            if index > 0:
                _text(out, ", ")
            _quote(out, doc.key(node, index))
            _text(out, ": ")
            _emit(doc, doc.value(node, index), out)
        out.append(0x7D)
    elif kind == PY_LIST:
        out.append(0x5B)
        for index in range(doc.length(node)):
            if index > 0:
                _text(out, ", ")
            _emit(doc, doc.item(node, index), out)
        out.append(0x5D)
    elif kind == PY_STR:
        _quote(out, doc.text(node))
    elif kind == PY_BOOL:
        _text(out, "true" if doc.flag(node) else "false")
    elif kind == PY_NONE:
        _text(out, "null")
    else:
        _text(out, doc.text(node))


def _quote(mut out: List[UInt8], text: String):
    """Append a JSON string."""
    out.append(0x22)
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 0x22 or byte == 0x5C:
            out.append(0x5C)
            out.append(byte)
        elif byte == 0x0A:
            _text(out, "\\n")
        elif byte < 0x20:
            _text(out, "\\u00")
            var hex = "0123456789abcdef"
            out.append(hex.as_bytes()[Int(byte >> 4)])
            out.append(hex.as_bytes()[Int(byte & 15)])
        else:
            out.append(byte)
    out.append(0x22)


def _text(mut out: List[UInt8], text: String):
    """Append raw ASCII."""
    var raw = text.as_bytes()
    for index in range(len(raw)):
        out.append(raw[index])


def main() raises:
    """Rewrite one glTF, splitting its lamp primitives."""
    var arguments = argv()
    if len(arguments) != 5:
        print(
            (
                "usage: carla_gltf_lamps INPUT.gltf INPUT.bin OUTPUT.gltf"
                " OUTPUT.bin"
            ),
            file=stderr,
        )
        exit(2)
    try:
        var doc = PyJson.parse(Path(arguments[1]).read_text())
        var data = Path(arguments[2]).read_bytes()
        var output = split_lamps(doc, data)
        Path(arguments[3]).write_text(_dumps(doc))
        Path(arguments[4]).write_bytes(Span(output))
    except error:
        print("carla_gltf_lamps:", error, file=stderr)
        exit(1)
