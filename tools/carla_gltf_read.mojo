# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read one glTF accessor from a buffer.

    carla_gltf_read FILE

`FILE` holds the buffer bytes and the accessor. The program prints the
values and the number of components, as `struct.unpack_from` does.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_json import MISSING, PY_DICT, PY_INT, PY_LIST, PY_STR, PyJson


def read_text(path: String) raises -> String:
    """Return one accessor's values as JSON.

    Args:
        path: A JSON object with `bytes`, `accessors`, `bufferViews` and
            `accessor`. A missing `byteOffset` is zero.

    Returns:
        An object with `values` and `width`. Floats are the float32 values
        widened to float64. Integers are unsigned.

    Raises:
        Error: If the file cannot be read, an index is out of range, the
            component type is unknown, or the buffer is short.
    """
    var doc = PyJson.parse(Path(path).read_text())
    if doc.kind(doc.root) != PY_DICT:
        raise Error("read is not an object")
    var data = _bytes(doc, doc.at(doc.root, "bytes"))
    var accessors = doc.at(doc.root, "accessors")
    var views = doc.at(doc.root, "bufferViews")
    if doc.kind(accessors) != PY_LIST or doc.kind(views) != PY_LIST:
        raise Error("accessors are not lists")
    var index = _int(doc, doc.at(doc.root, "accessor"))
    if index < 0:
        index += doc.length(accessors)
    if index < 0 or index >= doc.length(accessors):
        raise Error("accessor index out of range")
    var accessor = doc.item(accessors, index)
    var view_index = _int(doc, doc.at(accessor, "bufferView"))
    if view_index < 0:
        view_index += doc.length(views)
    if view_index < 0 or view_index >= doc.length(views):
        raise Error("buffer view index out of range")
    var view = doc.item(views, view_index)
    var kind = _text(doc, doc.at(accessor, "type"))
    var width = _width(kind)
    var form = _form(_int(doc, doc.at(accessor, "componentType")))
    var start = _optional(doc, view, "byteOffset") + _optional(
        doc, accessor, "byteOffset"
    )
    var count = _int(doc, doc.at(accessor, "count")) * width
    var values = _unpack(data, start, count, form)
    var tree = JsonTree()
    var obj = tree.object()
    var listed = tree.array()
    for index in range(len(values)):
        if form == "f":
            tree.append(listed, tree.number(values[index]))
        else:
            tree.append(listed, tree.integer(Int(values[index])))
    tree.set(obj, "values", listed)
    tree.set(obj, "width", tree.integer(width))
    return tree.dumps(obj, False)


def _unpack(
    data: List[UInt8], start: Int, count: Int, form: String
) raises -> List[Float64]:
    """Return `count` values beginning at `start`."""
    var size = 1
    if form == "f" or form == "I":
        size = 4
    elif form == "H":
        size = 2
    var need = start + count * size
    if start < 0 or need > len(data):
        raise Error("buffer is short")
    var out = List[Float64]()
    var at = start
    for _ in range(count):
        if form == "f":
            out.append(_f32(data, at))
        elif form == "B":
            out.append(Float64(Int(data[at])))
        else:
            var bits = Int(data[at])
            for byte in range(1, size):
                bits = bits | (Int(data[at + byte]) << (8 * byte))
            out.append(Float64(bits))
        at += size
    return out^


def _f32(data: List[UInt8], at: Int) -> Float64:
    """Return the little-endian float32 at `at`, widened to float64."""
    var bits = UInt32(data[at])
    bits = bits | (UInt32(data[at + 1]) << 8)
    bits = bits | (UInt32(data[at + 2]) << 16)
    bits = bits | (UInt32(data[at + 3]) << 24)
    return Float64(bitcast[DType.float32](bits))


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


def _form(component: Int) raises -> String:
    """Return the pack code for a glTF component type."""
    if component == 5121:
        return "B"
    if component == 5123:
        return "H"
    if component == 5125:
        return "I"
    if component == 5126:
        return "f"
    raise Error("unknown component type")


def _optional(doc: PyJson, node: Int, key: String) raises -> Int:
    """Return an integer member, or zero when it is absent."""
    var found = doc.get(node, key)
    if found == MISSING:
        return 0
    return _int(doc, found)


def _bytes(doc: PyJson, node: Int) raises -> List[UInt8]:
    """Return a list of byte values."""
    if doc.kind(node) != PY_LIST:
        raise Error("bytes is not a list")
    var out = List[UInt8]()
    for index in range(doc.length(node)):
        var value = _int(doc, doc.item(node, index))
        if value < 0 or value > 255:
            raise Error("byte out of range")
        out.append(UInt8(value))
    return out^


def _int(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("value is not an int")
    return Int(doc.text(node))


def _text(doc: PyJson, node: Int) raises -> String:
    """Return a JSON string."""
    if doc.kind(node) != PY_STR:
        raise Error("value is not a string")
    return doc.text(node)


def main() raises:
    """Print one accessor for the file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_gltf_read FILE", file=stderr)
        exit(2)
    try:
        print(read_text(arguments[1]))
    except error:
        print("carla_gltf_read:", error, file=stderr)
        exit(1)
