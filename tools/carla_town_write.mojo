# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write one town glTF and pack it into a binary glTF.

    carla_town_write FILE

`FILE` is JSON. It holds the material tables, the mesh groups and the
lamp heads. The program writes the buffer, the loose glTF and
`NAME.glb`. It then removes the loose files.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)
from tools.carla_gltf_compact import gltf_text
from tools.carla_town_buffers import buffer_text
from tools.carla_town_clean import refusal
from tools.carla_town_glb import pack_glb
from tools._town_json import json_text

comptime CREDIT = (
    "CARLA Team, CARLA Simulator 0.9.16, CC-BY 4.0 (https://carla.org)"
)


def write_town(text: String) raises -> String:
    """Write one town package and return its triangle counts.

    Args:
        text: JSON with `out_dir`, `name`, `gltf`, `groups` and `lamps`.

    Returns:
        `triangles`, the near and far counts, and `nodes`, the node count.

    Raises:
        Error: If the JSON is not that package, the package names an
            engine, or the buffer cannot be packed.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("town write is not an object")
    var out_dir = json_text(doc, doc.at(root, "out_dir"), "out_dir is not text")
    var name = json_text(doc, doc.at(root, "name"), "name is not text")
    var tables = PyJson.parse(
        buffer_text(_buffer_request(doc, root, out_dir, name))
    )
    var gltf = doc.subtree(doc.at(root, "gltf"))
    if gltf.kind(gltf.root) != PY_DICT:
        raise Error("gltf is not an object")
    var asset = gltf.new_dict()
    gltf.set(asset, "version", gltf.new_str("2.0"))
    gltf.set(asset, "generator", gltf.new_str("ThreeMojo build_towns.py"))
    gltf.set(asset, "copyright", gltf.new_str(CREDIT))
    gltf.set(gltf.root, "asset", asset)
    gltf.set(gltf.root, "scene", gltf.new_int(0))
    _take(gltf, tables, "nodes")
    _take(gltf, tables, "meshes")
    _take(gltf, tables, "accessors")
    _take(gltf, tables, "bufferViews")
    _take(gltf, tables, "scenes")
    _take(gltf, tables, "buffers")
    var gltf_path = out_dir + "/" + name + ".gltf"
    Path(gltf_path).write_text(_compact(gltf, gltf.root))
    var unclean = refusal(out_dir)
    if unclean.byte_length() > 0:
        raise Error(unclean)
    pack_glb(out_dir, name)
    var triangles = tables.at(tables.root, "triangles")
    var nodes = tables.at(tables.root, "nodes")
    var out = String('{"triangles":[')
    out += tables.text(tables.item(triangles, 0))
    out += ","
    out += tables.text(tables.item(triangles, 1))
    out += '],"nodes":'
    out += String(tables.length(nodes))
    out += "}"
    return out^


def _buffer_request(
    doc: PyJson, root: Int, out_dir: String, name: String
) raises -> String:
    """Return the buffer-tool request."""
    var request = PyJson()
    var top = request.new_dict()
    request.root = top
    request.set(top, "bin", request.new_str(out_dir + "/" + name + ".bin"))
    request.set(top, "name", request.new_str(name))
    request.set(top, "groups", request.adopt(doc, doc.at(root, "groups")))
    request.set(top, "lamps", request.adopt(doc, doc.at(root, "lamps")))
    return gltf_text(request)


def _take(mut gltf: PyJson, tables: PyJson, key: String) raises:
    """Copy one buffer table onto the glTF."""
    gltf.set(gltf.root, key, gltf.adopt(tables, tables.at(tables.root, key)))


def _compact(doc: PyJson, node: Int) raises -> String:
    """Return JSON with no spaces, in insertion order."""
    var kind = doc.kind(node)
    if kind == PY_DICT:
        var out = String("{")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += _quote(doc.key(node, index))
            out += ":"
            out += _compact(doc, doc.value(node, index))
        out += "}"
        return out
    if kind == PY_LIST:
        var out = String("[")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += _compact(doc, doc.item(node, index))
        out += "]"
        return out
    if kind == PY_STR:
        return _quote(doc.text(node))
    if kind == PY_BOOL:
        if doc.flag(node):
            return "true"
        return "false"
    if kind == PY_NONE:
        return "null"
    return doc.text(node)


def _quote(text: String) -> String:
    """Return one JSON string."""
    var out = String('"')
    var raw = text.as_bytes()
    var hex = String("0123456789abcdef")
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 34 or byte == 92:
            out += "\\"
            out += chr(Int(byte))
        elif byte == 10:
            out += "\\n"
        elif byte == 13:
            out += "\\r"
        elif byte == 9:
            out += "\\t"
        elif byte < 32:
            out += "\\u00"
            out += chr(Int(hex.as_bytes()[Int(byte >> 4)]))
            out += chr(Int(hex.as_bytes()[Int(byte & 15)]))
        else:
            out += chr(Int(byte))
    out += '"'
    return out


def main() raises:
    """Write the town package described on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_write FILE", file=stderr)
        exit(2)
    try:
        print(write_town(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_write:", error, file=stderr)
        exit(1)
