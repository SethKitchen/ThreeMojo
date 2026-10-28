# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Simplify each part of a CARLA vehicle glTF.

    carla_gltf_decimate BUDGET KEEP INPUT.gltf INPUT.bin OUTPUT.gltf OUTPUT.bin

`BUDGET` is the triangle count the free parts share. `KEEP` is the
minimum a part must have before it can be simplified. A part under
`KEEP`, and a part whose material is `MASK`, stays whole. Each free
part is collapsed on its own, with its open edges held. The output
matches the previous Python decimation, including the compacted buffer.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._process import _remove_tree

from tools._python_float import parse_float, python_repr
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)
from tools.carla_area_normals import normals_text
from tools.carla_collapse_map import collapse_text
from tools.carla_gltf_append import append_text
from tools.carla_gltf_compact import compact_gltf, gltf_text
from tools.carla_gltf_read import read_text
from tools.carla_simplify import simplify_text
from tools.carla_simplify_target import target_text
from tools._town_json import json_int


def decimate_files(
    budget: Int,
    keep: Int,
    in_gltf: String,
    in_bin: String,
    out_gltf: String,
    out_bin: String,
) raises:
    """Write one vehicle glTF simplified to about `budget` triangles.

    Args:
        budget: The triangle count the free parts share.
        keep: A part with fewer triangles stays whole.
        in_gltf: The source glTF.
        in_bin: The source buffer.
        out_gltf: The simplified glTF.
        out_bin: The simplified buffer.

    Raises:
        Error: If a file cannot be read, the glTF is not an object, or a
            primitive cannot be simplified.
    """
    var text = Path(in_gltf).read_text()
    var raw = Path(in_bin).read_bytes()
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("glTF is not an object")
    var data = List[UInt8]()
    for index in range(len(raw)):
        data.append(raw[index])
    var source = List[UInt8]()
    for index in range(len(raw)):
        source.append(raw[index])
    var changed = _decimate(doc, data, source, budget, keep)
    if not changed:
        Path(out_gltf).write_text(text)
        Path(out_bin).write_bytes(raw)
        return
    var output = compact_gltf(doc, "compact", data)
    Path(out_gltf).write_text(gltf_text(doc))
    Path(out_bin).write_bytes(Span(output))


def _decimate(
    mut doc: PyJson,
    mut data: List[UInt8],
    source: List[UInt8],
    budget: Int,
    keep: Int,
) raises -> Bool:
    """Simplify every free primitive. Return whether any work was done."""
    var meshes = doc.at(doc.root, "meshes")
    if doc.kind(meshes) != PY_LIST:
        raise Error("meshes are not a list")
    var counts = List[Int]()
    var fixed = List[Bool]()
    var places = List[Int]()
    for mesh_index in range(doc.length(meshes)):
        var primitives = doc.at(doc.item(meshes, mesh_index), "primitives")
        if doc.kind(primitives) != PY_LIST:
            raise Error("primitives are not a list")
        for primitive_index in range(doc.length(primitives)):
            var primitive = doc.item(primitives, primitive_index)
            var count = _triangles(doc, primitive)
            counts.append(count)
            fixed.append(_fixed(doc, primitive, count, keep))
            places.append(primitive)
    var chosen = PyJson.parse(_targets(counts, fixed, budget, keep))
    var skip = chosen.at(chosen.root, "skip")
    if chosen.kind(skip) != PY_BOOL:
        raise Error("skip is not a bool")
    if chosen.flag(skip):
        return False
    var targets = chosen.at(chosen.root, "targets")
    if chosen.kind(targets) != PY_LIST or chosen.length(targets) != len(counts):
        raise Error("targets do not match the primitives")
    var folder = mkdtemp(prefix="gltf decimate ")
    for slot in range(len(places)):
        if fixed[slot]:
            continue
        var target = json_int(
            chosen, chosen.item(targets, slot), "target is not an integer"
        )
        _simplify_one(doc, data, source, places[slot], target, folder)
    _remove_tree(folder)
    var buffers = doc.at(doc.root, "buffers")
    var buffer = doc.item(buffers, 0)
    doc.set(buffer, "byteLength", doc.new_int(len(data)))
    return True


def _simplify_one(
    mut doc: PyJson,
    mut data: List[UInt8],
    source: List[UInt8],
    primitive: Int,
    target: Int,
    folder: String,
) raises:
    """Replace one primitive with its collapsed vertices."""
    var indices = _read(
        doc,
        source,
        json_int(
            doc, doc.at(primitive, "indices"), "indices is not an integer"
        ),
        folder,
    )
    var attributes = doc.at(primitive, "attributes")
    if doc.kind(attributes) != PY_DICT:
        raise Error("attributes are not an object")
    var position = doc.find(attributes, "POSITION")
    if position == MISSING:
        raise Error("primitive has no position")
    var points = _read(
        doc,
        source,
        json_int(doc, position, "position is not an integer"),
        folder,
    )
    var request = String('{"points":')
    request += _grouped(points, points.at(points.root, "values"), 3, True)
    request += ',"triangles":'
    request += _grouped(indices, indices.at(indices.root, "values"), 3, False)
    request += ',"target":'
    request += String(target)
    request += ',"border":true}'
    var collapsed = PyJson.parse(simplify_text(request))
    var replay_request = String('{"mode":"replay","points":')
    replay_request += _grouped(
        points, points.at(points.root, "values"), 3, True
    )
    replay_request += ',"triangles":'
    replay_request += _grouped(
        indices, indices.at(indices.root, "values"), 3, False
    )
    replay_request += ',"collapses":'
    replay_request += _rows(
        collapsed, collapsed.at(collapsed.root, "collapses"), False
    )
    replay_request += "}"
    var replay = PyJson.parse(simplify_text(replay_request))
    var triangles = replay.at(replay.root, "triangles")
    if replay.kind(triangles) != PY_LIST or replay.length(triangles) == 0:
        return
    var point_rows = replay.at(replay.root, "points")
    var mapping = replay.at(replay.root, "mapping")
    var map_request = String('{"mapping":')
    map_request += _flat(replay, mapping, False)
    map_request += ',"count":'
    map_request += String(replay.length(point_rows))
    map_request += "}"
    var source_map = PyJson.parse(collapse_text(map_request))
    var fresh = doc.new_dict()
    var positions = _append(
        doc,
        data,
        _flatten(replay, point_rows, True),
        "f",
        5126,
        "VEC3",
        34962,
        folder,
    )
    doc.set(fresh, "POSITION", doc.new_int(positions))
    if doc.find(attributes, "NORMAL") != MISSING:
        var normal_request = String('{"points":')
        normal_request += _rows(replay, point_rows, True)
        normal_request += ',"faces":'
        normal_request += _rows(replay, triangles, False)
        normal_request += "}"
        var normals = PyJson.parse(_stored(folder, normal_request, 2))
        var normal_index = _append(
            doc,
            data,
            _flatten(normals, normals.root, True),
            "f",
            5126,
            "VEC3",
            34962,
            folder,
        )
        doc.set(fresh, "NORMAL", doc.new_int(normal_index))
    for index in range(doc.length(attributes)):
        var name = doc.key(attributes, index)
        if name == "POSITION" or name == "NORMAL":
            continue
        var accessor_index = json_int(
            doc, doc.value(attributes, index), "accessor is not an integer"
        )
        var accessor = doc.item(doc.at(doc.root, "accessors"), accessor_index)
        var component = json_int(
            doc,
            doc.at(accessor, "componentType"),
            "componentType is not an integer",
        )
        if component != 5126:
            continue
        var values = _read(doc, source, accessor_index, folder)
        var gather = String('{"source":')
        gather += _flat(
            source_map, source_map.at(source_map.root, "source"), False
        )
        gather += ',"values":'
        gather += _flat(values, values.at(values.root, "values"), True)
        gather += ',"width":'
        gather += String(
            json_int(
                values,
                values.at(values.root, "width"),
                "width is not an integer",
            )
        )
        gather += "}"
        var copied = PyJson.parse(collapse_text(gather))
        var copied_index = _append(
            doc,
            data,
            _flat(copied, copied.at(copied.root, "values"), True),
            "f",
            5126,
            doc.text(doc.at(accessor, "type")),
            34962,
            folder,
        )
        doc.set(fresh, name, doc.new_int(copied_index))
    doc.set(primitive, "attributes", fresh)
    var face_index = _append(
        doc,
        data,
        _flatten(replay, triangles, False),
        "I",
        5125,
        "SCALAR",
        34963,
        folder,
    )
    doc.set(primitive, "indices", doc.new_int(face_index))


def _append(
    mut doc: PyJson,
    mut data: List[UInt8],
    values: String,
    form: String,
    component: Int,
    kind: String,
    target: Int,
    folder: String,
) raises -> Int:
    """Append one accessor and return its index."""
    var request = String('{"length":')
    request += String(len(data))
    request += ',"viewIndex":'
    request += String(doc.length(doc.at(doc.root, "bufferViews")))
    request += ',"accessorIndex":'
    request += String(doc.length(doc.at(doc.root, "accessors")))
    request += ',"values":'
    request += values
    request += ',"form":"'
    request += form
    request += '","component":'
    request += String(component)
    request += ',"kind":"'
    request += kind
    request += '","target":'
    request += String(target)
    request += "}"
    var parsed = PyJson.parse(_stored(folder, request, 1))
    var bytes = parsed.at(parsed.root, "bytes")
    if parsed.kind(bytes) != PY_LIST:
        raise Error("append bytes are not a list")
    for index in range(parsed.length(bytes)):
        var value = json_int(
            parsed, parsed.item(bytes, index), "byte is not an integer"
        )
        if value < 0 or value > 255:
            raise Error("byte is out of range")
        data.append(UInt8(value))
    doc.append(
        doc.at(doc.root, "bufferViews"),
        doc.adopt(parsed, parsed.at(parsed.root, "view")),
    )
    doc.append(
        doc.at(doc.root, "accessors"),
        doc.adopt(parsed, parsed.at(parsed.root, "accessor")),
    )
    return json_int(
        parsed, parsed.at(parsed.root, "index"), "index is not an integer"
    )


def _read(
    doc: PyJson, source: List[UInt8], accessor: Int, folder: String
) raises -> PyJson:
    """Return one accessor from the original buffer."""
    var request = String('{"bytes":[')
    for index in range(len(source)):
        if index > 0:
            request += ","
        request += String(Int(source[index]))
    request += '],"accessors":'
    request += doc.subtree(doc.at(doc.root, "accessors")).dumps()
    request += ',"bufferViews":'
    request += doc.subtree(doc.at(doc.root, "bufferViews")).dumps()
    request += ',"accessor":'
    request += String(accessor)
    request += "}"
    return PyJson.parse(_stored(folder, request, 0))


def _stored(folder: String, payload: String, kind: Int) raises -> String:
    """Run one file tool. `kind` 0 reads, 1 appends, and 2 weighs normals."""
    var path = folder + "/request.json"
    Path(path).write_text(payload)
    if kind == 0:
        return read_text(path)
    if kind == 1:
        return append_text(path)
    if kind == 2:
        return normals_text(path)
    raise Error("tool kind is not known")


def _targets(
    counts: List[Int], fixed: List[Bool], budget: Int, keep: Int
) raises -> String:
    """Return the vehicle target JSON."""
    var out = String('{"mode":"vehicle","counts":[')
    for index in range(len(counts)):
        if index > 0:
            out += ","
        out += String(counts[index])
    out += '],"fixed":['
    for index in range(len(fixed)):
        if index > 0:
            out += ","
        if fixed[index]:
            out += "true"
        else:
            out += "false"
    out += '],"budget":'
    out += String(budget)
    out += ',"keep":'
    out += String(keep)
    out += "}"
    return target_text(out)


def _triangles(doc: PyJson, primitive: Int) raises -> Int:
    """Return the triangle count of one primitive."""
    var index = json_int(
        doc, doc.at(primitive, "indices"), "indices is not an integer"
    )
    var accessor = doc.item(doc.at(doc.root, "accessors"), index)
    var count = json_int(
        doc, doc.at(accessor, "count"), "count is not an integer"
    )
    return count // 3


def _fixed(doc: PyJson, primitive: Int, count: Int, keep: Int) raises -> Bool:
    """Return whether a primitive stays whole."""
    if count < keep:
        return True
    var material_index = doc.find(primitive, "material")
    if material_index == MISSING:
        return False
    var material = doc.item(
        doc.at(doc.root, "materials"),
        json_int(doc, material_index, "material is not an integer"),
    )
    var alpha = doc.find(material, "alphaMode")
    if alpha == MISSING or doc.kind(alpha) != PY_STR:
        return False
    return doc.text(alpha) == "MASK"


def _grouped(doc: PyJson, node: Int, width: Int, floats: Bool) raises -> String:
    """Return a flat accessor as rows of `width`."""
    if doc.kind(node) != PY_LIST:
        raise Error("values are not a list")
    var count = doc.length(node)
    if width < 1 or count % width != 0:
        raise Error("values do not match the accessor")
    var out = String("[")
    var rows = count // width
    for row in range(rows):
        if row > 0:
            out += ","
        out += "["
        for column in range(width):
            if column > 0:
                out += ","
            out += _token(doc, doc.item(node, row * width + column), floats)
        out += "]"
    out += "]"
    return out^


def _rows(doc: PyJson, node: Int, floats: Bool) raises -> String:
    """Return a list of rows, rewritten with Python's number text."""
    if doc.kind(node) != PY_LIST:
        raise Error("rows are not a list")
    var out = String("[")
    for row in range(doc.length(node)):
        if row > 0:
            out += ","
        var item = doc.item(node, row)
        if doc.kind(item) != PY_LIST:
            raise Error("row is not a list")
        out += "["
        for column in range(doc.length(item)):
            if column > 0:
                out += ","
            out += _token(doc, doc.item(item, column), floats)
        out += "]"
    out += "]"
    return out^


def _flat(doc: PyJson, node: Int, floats: Bool) raises -> String:
    """Return a flat list of numbers."""
    if doc.kind(node) != PY_LIST:
        raise Error("values are not a list")
    var out = String("[")
    for index in range(doc.length(node)):
        if index > 0:
            out += ","
        out += _token(doc, doc.item(node, index), floats)
    out += "]"
    return out^


def _flatten(doc: PyJson, node: Int, floats: Bool) raises -> String:
    """Return the numbers in a list of rows."""
    if doc.kind(node) != PY_LIST:
        raise Error("rows are not a list")
    var out = String("[")
    var first = True
    for row in range(doc.length(node)):
        var item = doc.item(node, row)
        if doc.kind(item) != PY_LIST:
            raise Error("row is not a list")
        for column in range(doc.length(item)):
            if not first:
                out += ","
            first = False
            out += _token(doc, doc.item(item, column), floats)
    out += "]"
    return out^


def _token(doc: PyJson, node: Int, floats: Bool) raises -> String:
    """Return one JSON number."""
    if floats:
        return _float_text(doc, node)
    return _int_text(doc, node)


def _float_text(doc: PyJson, node: Int) raises -> String:
    """Return one float as Python writes it."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return python_repr(doc.number(node))
    if kind == PY_INT:
        return python_repr(parse_float(doc.text(node)))
    raise Error("value is not a number")


def _int_text(doc: PyJson, node: Int) raises -> String:
    """Return one integer's digits."""
    if doc.kind(node) != PY_INT:
        raise Error("value is not an integer")
    return doc.text(node)


def _argument(text: String, name: String) raises -> Int:
    """Return a command-line integer."""
    var raw = text.as_bytes()
    if len(raw) == 0:
        raise Error(name + " is not an integer")
    var index = 0
    var negative = False
    if raw[0] == 45:
        negative = True
        index = 1
    if index == len(raw):
        raise Error(name + " is not an integer")
    var value = 0
    for offset in range(index, len(raw)):
        var byte = raw[offset]
        if byte < 48 or byte > 57:
            raise Error(name + " is not an integer")
        value = value * 10 + Int(byte - 48)
    if negative:
        return -value
    return value


def main() raises:
    """Write the simplified glTF named on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 7:
        print(
            (
                "usage: carla_gltf_decimate BUDGET KEEP INPUT.gltf INPUT.bin"
                " OUTPUT.gltf OUTPUT.bin"
            ),
            file=stderr,
        )
        exit(2)
    try:
        decimate_files(
            _argument(arguments[1], "budget"),
            _argument(arguments[2], "keep"),
            arguments[3],
            arguments[4],
            arguments[5],
            arguments[6],
        )
    except error:
        print("carla_gltf_decimate:", error, file=stderr)
        exit(1)
