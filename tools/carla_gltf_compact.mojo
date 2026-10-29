# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Compact a CARLA vehicle glTF the way the Python exporter does.

    carla_gltf_compact MODE INPUT.gltf INPUT.bin OUTPUT.gltf OUTPUT.bin

MODE is `dedupe`, `strip` or `compact`. `dedupe` keeps the first material
of each name and rewrites primitive indexes. `strip` drops skin, joint,
weight and color attributes, then compacts the buffer. `compact` keeps
only the bytes a primitive reads, aligned to 4 bytes. The JSON key order
matches the Python dict order.
"""

from std.collections import Dict
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)


def compact_gltf(
    mut doc: PyJson, mode: String, data: Span[UInt8, _]
) raises -> List[UInt8]:
    """Apply one exporter buffer step and return the buffer bytes.

    Args:
        doc: The glTF document. The function edits it.
        mode: `dedupe`, `strip` or `compact`.
        data: The current buffer. `dedupe` does not read it.

    Returns:
        The buffer after the step. `dedupe` returns `data` unchanged.

    Raises:
        Error: If `mode` is unknown or the glTF is missing a required
            table.
    """
    if mode == "dedupe":
        _dedupe(doc)
        return _copy(data)
    if mode == "strip":
        _strip(doc)
    elif mode != "compact":
        raise Error("unknown glTF compact mode: " + mode)
    return _compact(doc, data)


def _dedupe(mut doc: PyJson) raises:
    """Keep the first material of each name."""
    var root = doc.root
    var meshes = doc.at(root, "meshes")
    var materials = doc.find(root, "materials")
    var first = Dict[String, Int]()
    var kept = List[Int]()
    var new_index = List[Int]()
    if materials != MISSING:
        for index in range(doc.length(materials)):
            var material = doc.item(materials, index)
            var name = String("")
            var named = doc.find(material, "name")
            if named != MISSING:
                name = doc.text(named)
            if not (name in first):
                first[name] = len(kept)
                kept.append(material)
            new_index.append(first[name])
        if len(kept) > 0:
            var replacement = doc.new_list()
            for index in range(len(kept)):
                doc.append(replacement, kept[index])
            doc.set(root, "materials", replacement)
    for mesh_index in range(doc.length(meshes)):
        var primitives = doc.at(doc.item(meshes, mesh_index), "primitives")
        for primitive_index in range(doc.length(primitives)):
            var primitive = doc.item(primitives, primitive_index)
            var material = doc.find(primitive, "material")
            if material != MISSING:
                doc.set(
                    primitive,
                    "material",
                    doc.new_int(new_index[_int(doc, material)]),
                )


def _strip(mut doc: PyJson) raises:
    """Drop skin tables and attributes the plain mesh does not read."""
    var root = doc.root
    var nodes = doc.at(root, "nodes")
    for index in range(doc.length(nodes)):
        var node = doc.item(nodes, index)
        if doc.find(node, "skin") != MISSING:
            doc.remove(node, "skin")
    if doc.find(root, "skins") != MISSING:
        doc.remove(root, "skins")
    var meshes = doc.at(root, "meshes")
    for mesh_index in range(doc.length(meshes)):
        var primitives = doc.at(doc.item(meshes, mesh_index), "primitives")
        for primitive_index in range(doc.length(primitives)):
            var attributes = doc.at(
                doc.item(primitives, primitive_index), "attributes"
            )
            var drop = List[String]()
            for index in range(doc.length(attributes)):
                var key = doc.key(attributes, index)
                if (
                    key.startswith("JOINTS_")
                    or key.startswith("WEIGHTS_")
                    or key.startswith("COLOR_")
                ):
                    drop.append(key)
            for index in range(len(drop)):
                doc.remove(attributes, drop[index])


def _compact(mut doc: PyJson, data: Span[UInt8, _]) raises -> List[UInt8]:
    """Keep the bytes the primitives read and retarget the accessors."""
    var root = doc.root
    var meshes = doc.at(root, "meshes")
    var accessors = doc.at(root, "accessors")
    var views = doc.at(root, "bufferViews")
    var used = List[Int]()
    for mesh_index in range(doc.length(meshes)):
        var primitives = doc.at(doc.item(meshes, mesh_index), "primitives")
        for primitive_index in range(doc.length(primitives)):
            var primitive = doc.item(primitives, primitive_index)
            var attributes = doc.at(primitive, "attributes")
            for index in range(doc.length(attributes)):
                used.append(_int(doc, doc.value(attributes, index)))
            var indices = doc.find(primitive, "indices")
            if indices != MISSING:
                used.append(_int(doc, indices))
    var order = _unique_sorted(used)
    var accessor_of = Dict[Int, Int]()
    var kept = doc.new_list()
    for index in range(len(order)):
        accessor_of[order[index]] = index
        doc.append(kept, doc.item(accessors, order[index]))
    var view_of = Dict[Int, Int]()
    var new_views = doc.new_list()
    var out = List[UInt8]()
    for index in range(len(order)):
        var accessor = doc.item(accessors, order[index])
        var old = _int(doc, doc.at(accessor, "bufferView"))
        if not (old in view_of):
            var view = doc.copy_node(doc.item(views, old))
            var start = 0
            var offset = doc.find(view, "byteOffset")
            if offset != MISSING:
                start = _int(doc, offset)
            var size = _int(doc, doc.at(view, "byteLength"))
            _align(out)
            doc.set(view, "byteOffset", doc.new_int(len(out)))
            var end = start + size
            if end > len(data):
                end = len(data)
            if start < 0:
                start = 0
            for byte in range(start, end):
                out.append(data[byte])
            view_of[old] = doc.length(new_views)
            doc.append(new_views, view)
        doc.set(accessor, "bufferView", doc.new_int(view_of[old]))
    for mesh_index in range(doc.length(meshes)):
        var primitives = doc.at(doc.item(meshes, mesh_index), "primitives")
        for primitive_index in range(doc.length(primitives)):
            var primitive = doc.item(primitives, primitive_index)
            var attributes = doc.at(primitive, "attributes")
            var fresh = doc.new_dict()
            for index in range(doc.length(attributes)):
                var key = doc.key(attributes, index)
                var old_accessor = _int(doc, doc.value(attributes, index))
                doc.set(fresh, key, doc.new_int(accessor_of[old_accessor]))
            doc.set(primitive, "attributes", fresh)
            var indices = doc.find(primitive, "indices")
            if indices != MISSING:
                doc.set(
                    primitive,
                    "indices",
                    doc.new_int(accessor_of[_int(doc, indices)]),
                )
    doc.set(root, "accessors", kept)
    doc.set(root, "bufferViews", new_views)
    _align(out)
    var buffers = doc.at(root, "buffers")
    var uri = doc.text(doc.at(doc.item(buffers, 0), "uri"))
    var buffer = doc.new_dict()
    doc.set(buffer, "uri", doc.new_str(uri))
    doc.set(buffer, "byteLength", doc.new_int(len(out)))
    var buffer_list = doc.new_list()
    doc.append(buffer_list, buffer)
    doc.set(root, "buffers", buffer_list)
    return out^


def _unique_sorted(values: List[Int]) -> List[Int]:
    """Return the values once, in ascending order."""
    var unique = List[Int]()
    for value in values:
        if value not in unique:
            unique.append(value)
    sort(unique)
    return unique^


def _align(mut out: List[UInt8]):
    """Pad `out` to a multiple of 4, as Python's `(-len) % 4` does."""
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
    var negative = False
    var bytes = text.as_bytes()
    var start = 0
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


def _copy(data: Span[UInt8, _]) -> List[UInt8]:
    """Return a copy of `data`."""
    var out = List[UInt8]()
    for index in range(len(data)):
        out.append(data[index])
    return out^


def gltf_text(doc: PyJson) raises -> String:
    """Return the glTF as Python's `json.dumps` writes it.

    Args:
        doc: The document, in its current key order.

    Returns:
        JSON text with Python's default separators.

    Raises:
        Error: If a value cannot be written.
    """
    return _dumps(doc)


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
        elif byte == 0x0D:
            _text(out, "\\r")
        elif byte == 0x09:
            _text(out, "\\t")
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
    """Rewrite one glTF and its buffer for the requested mode."""
    var arguments = argv()
    if len(arguments) != 6:
        print(
            (
                "usage: carla_gltf_compact MODE INPUT.gltf INPUT.bin"
                " OUTPUT.gltf OUTPUT.bin"
            ),
            file=stderr,
        )
        exit(2)
    try:
        var doc = PyJson.parse(Path(arguments[2]).read_text())
        var data = Path(arguments[3]).read_bytes()
        var output = compact_gltf(doc, arguments[1], data)
        Path(arguments[4]).write_text(gltf_text(doc))
        Path(arguments[5]).write_bytes(Span(output))
    except error:
        print("carla_gltf_compact:", error, file=stderr)
        exit(1)
