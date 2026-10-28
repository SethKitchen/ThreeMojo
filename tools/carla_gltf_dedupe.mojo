# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Keep one glTF material of each name.

    carla_gltf_dedupe FILE

The merge gives each primitive its own copy of a material, so one name
can appear many times. The program keeps the first material of each name
and points every primitive at that copy.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PY_DICT, PY_INT, PY_LIST, PY_STR, PyJson
from tools._town_json import json_dump


def dedupe_text(path: String) raises -> String:
    """Return a glTF document with one material of each name.

    Args:
        path: A glTF JSON file.

    Returns:
        The document as `json.dumps` writes it. The first material of each
        name stays, in the order the names first appear. A missing
        `materials` list stays missing. An empty list stays empty.

    Raises:
        Error: If the file cannot be read, the JSON is not an object, or a
            primitive's material index is not in range.
    """
    var doc = PyJson.parse(Path(path).read_text())
    if doc.kind(doc.root) != PY_DICT:
        raise Error("glTF is not an object")
    _dedupe(doc)
    return json_dump(doc, doc.root)


def _dedupe(mut doc: PyJson) raises:
    """Keep the first material of each name and renumber the primitives."""
    var materials = doc.get(doc.root, "materials")
    if materials == MISSING:
        return
    if doc.kind(materials) != PY_LIST:
        raise Error("materials is not a list")
    var names = List[String]()
    var remap = List[Int]()
    var kept = doc.new_list()
    var count = doc.length(materials)
    for index in range(count):
        var material = doc.item(materials, index)
        var name = _name(doc, material)
        var found = _find(names, name)
        if found < 0:
            names.append(name)
            found = doc.length(kept)
            doc.append(kept, material)
        remap.append(found)
    if count == 0:
        return
    doc.set(doc.root, "materials", kept)
    var meshes = doc.at(doc.root, "meshes")
    if doc.kind(meshes) != PY_LIST:
        raise Error("meshes is not a list")
    for mesh_index in range(doc.length(meshes)):
        var mesh = doc.item(meshes, mesh_index)
        var primitives = doc.at(mesh, "primitives")
        if doc.kind(primitives) != PY_LIST:
            raise Error("primitives is not a list")
        for primitive_index in range(doc.length(primitives)):
            var primitive = doc.item(primitives, primitive_index)
            var slot = doc.get(primitive, "material")
            if slot == MISSING:
                continue
            var index = _index(doc, slot, len(remap))
            doc.set(primitive, "material", doc.new_int(remap[index]))


def _name(doc: PyJson, material: Int) raises -> String:
    """Return a material's name, or empty text when it has none."""
    if doc.kind(material) != PY_DICT:
        raise Error("material is not an object")
    var named = doc.get(material, "name")
    if named == MISSING:
        return String("")
    if doc.kind(named) != PY_STR:
        raise Error("material name is not a string")
    return doc.text(named)


def _find(names: List[String], name: String) -> Int:
    """Return the kept index of `name`, or -1."""
    for index in range(len(names)):
        if names[index] == name:
            return index
    return -1


def _index(doc: PyJson, node: Int, limit: Int) raises -> Int:
    """Return a material index, with Python's negative positions."""
    if doc.kind(node) != PY_INT:
        raise Error("material index is not an int")
    var value = Int(doc.text(node))
    if value < 0:
        value += limit
    if value < 0 or value >= limit:
        raise Error("material index out of range")
    return value


def main() raises:
    """Print one glTF file with duplicate materials removed."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_gltf_dedupe FILE", file=stderr)
        exit(2)
    try:
        print(dedupe_text(arguments[1]))
    except error:
        print("carla_gltf_dedupe:", error, file=stderr)
        exit(1)
