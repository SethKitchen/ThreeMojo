# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Append one glTF buffer view and its accessor.

    carla_gltf_append FILE

`FILE` describes the bytes already in the buffer and the values to add.
The program prints the padding and the packed bytes, plus the view and
the accessor that point at them.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_float import parse_float
from tools._python_json import (
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)


def append_text(path: String) raises -> String:
    """Return the bytes, view and accessor for one append.

    Args:
        path: A JSON object with `length`, `viewIndex`, `accessorIndex`,
            `values`, `form`, `component`, `kind` and `target`. `form` is
            `f`, `I`, `H` or `B`.

    Returns:
        An object with `bytes`, `view`, `accessor` and `index`. `bytes`
        starts with the zeros that align the view to four bytes.

    Raises:
        Error: If the file cannot be read, a field has the wrong shape, or
            a value does not fit in `form`.
    """
    var doc = PyJson.parse(Path(path).read_text())
    if doc.kind(doc.root) != PY_DICT:
        raise Error("append is not an object")
    var length = _int(doc, doc.at(doc.root, "length"), "length")
    var view_index = _int(doc, doc.at(doc.root, "viewIndex"), "viewIndex")
    var accessor_index = _int(
        doc, doc.at(doc.root, "accessorIndex"), "accessorIndex"
    )
    var form = _text(doc, doc.at(doc.root, "form"), "form")
    var kind = _text(doc, doc.at(doc.root, "kind"), "kind")
    var component = _int(doc, doc.at(doc.root, "component"), "component")
    var target = _int(doc, doc.at(doc.root, "target"), "target")
    var values = _values(doc, doc.at(doc.root, "values"))
    var width = _width(kind)
    var packed = _pack(values, form)
    var pad = _pad(length)
    var tree = JsonTree()
    var obj = tree.object()
    var blob = tree.array()
    for _ in range(pad):
        tree.append(blob, tree.integer(0))
    for index in range(len(packed)):
        tree.append(blob, tree.integer(Int(packed[index])))
    tree.set(obj, "bytes", blob)
    var view = tree.object()
    tree.set(view, "buffer", tree.integer(0))
    tree.set(view, "byteOffset", tree.integer(length + pad))
    tree.set(view, "byteLength", tree.integer(len(packed)))
    tree.set(view, "target", tree.integer(target))
    tree.set(obj, "view", view)
    var accessor = tree.object()
    tree.set(accessor, "bufferView", tree.integer(view_index))
    tree.set(accessor, "componentType", tree.integer(component))
    tree.set(accessor, "count", tree.integer(len(values) // width))
    tree.set(accessor, "type", tree.string(kind))
    if kind == "VEC3" and form == "f":
        tree.set(accessor, "min", _bounds(tree, values, False))
        tree.set(accessor, "max", _bounds(tree, values, True))
    tree.set(obj, "accessor", accessor)
    tree.set(obj, "index", tree.integer(accessor_index))
    return tree.dumps(obj, False)


def _pad(length: Int) -> Int:
    """Return the zero bytes that make `length` a multiple of four."""
    var rest = length % 4
    if rest == 0:
        return 0
    return 4 - rest


def _width(kind: String) raises -> Int:
    """Return how many numbers one element of `kind` holds."""
    if kind == "SCALAR":
        return 1
    if kind == "VEC2":
        return 2
    if kind == "VEC3":
        return 3
    if kind == "VEC4":
        return 4
    raise Error("unknown accessor type")


def _pack(values: List[Float64], form: String) raises -> List[UInt8]:
    """Return `values` packed little-endian in `form`."""
    var out = List[UInt8]()
    if form == "f":
        for index in range(len(values)):
            _pack_f32(out, values[index])
        return out^
    if form == "B":
        return _pack_int(values, 255, 1, form)
    if form == "H":
        return _pack_int(values, 65535, 2, form)
    if form == "I":
        return _pack_int(values, 4294967295, 4, form)
    raise Error("unknown component form")


def _pack_int(
    values: List[Float64], limit: Int, width: Int, form: String
) raises -> List[UInt8]:
    """Return unsigned integers packed little-endian."""
    var out = List[UInt8]()
    for index in range(len(values)):
        var value = values[index]
        if (
            value != Float64(Int(value))
            or value < 0.0
            or value > Float64(limit)
        ):
            raise Error("value does not fit in " + form)
        var bits = Int(value)
        for byte in range(width):
            out.append(UInt8((bits >> (8 * byte)) & 255))
    return out^


def _pack_f32(mut out: List[UInt8], value: Float64):
    """Append one little-endian float32."""
    var bits = UInt32(bitcast[DType.uint32](Float32(value)))
    out.append(UInt8(bits & 255))
    out.append(UInt8((bits >> 8) & 255))
    out.append(UInt8((bits >> 16) & 255))
    out.append(UInt8((bits >> 24) & 255))


def _bounds(
    mut tree: JsonTree, values: List[Float64], high: Bool
) raises -> Int:
    """Return the min or the max of each VEC3 component."""
    var row = tree.array()
    for axis in range(3):
        var found = False
        var bound = 0.0
        var index = axis
        while index < len(values):
            var value = values[index]
            if (
                not found
                or (high and value > bound)
                or (not high and value < bound)
            ):
                bound = value
                found = True
            index += 3
        if not found:
            raise Error("empty vector")
        tree.append(row, tree.number(bound))
    return row


def _values(doc: PyJson, node: Int) raises -> List[Float64]:
    """Return the number list."""
    if doc.kind(node) != PY_LIST:
        raise Error("values is not a list")
    var out = List[Float64]()
    for index in range(doc.length(node)):
        out.append(_number(doc, doc.item(node, index)))
    return out^


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as `float`."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("value is not a number")


def _int(doc: PyJson, node: Int, name: String) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error(name + " is not an int")
    return Int(doc.text(node))


def _text(doc: PyJson, node: Int, name: String) raises -> String:
    """Return a JSON string."""
    if doc.kind(node) != PY_STR:
        raise Error(name + " is not a string")
    return doc.text(node)


def main() raises:
    """Print one packed buffer view for the file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_gltf_append FILE", file=stderr)
        exit(2)
    try:
        print(append_text(arguments[1]))
    except error:
        print("carla_gltf_append:", error, file=stderr)
        exit(1)
