# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Remove skin, joints, weights and vertex colors from a glTF document.

    carla_gltf_skin FILE

A CARLA vehicle is a skeletal mesh. At rest its bones are where the mesh
was bound, so the vertices already stand where the car stands. The skin
data goes. The bone nodes stay, as named markers of the wheels.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PY_DICT, PY_LIST, PyJson
from tools._town_json import json_dump


def strip_text(path: String) raises -> String:
    """Return a glTF document with its skin data removed.

    Args:
        path: A glTF JSON file.

    Returns:
        The document as `json.dumps` writes it. Each node's `skin` is
        gone, as is the document's `skins` list. Attributes named
        `JOINTS_`, `WEIGHTS_` or `COLOR_` are gone. The bone nodes stay.

    Raises:
        Error: If the file cannot be read, the JSON is not an object, or a
            node, mesh or primitive is missing.
    """
    var doc = PyJson.parse(Path(path).read_text())
    if doc.kind(doc.root) != PY_DICT:
        raise Error("glTF is not an object")
    _strip(doc)
    return json_dump(doc, doc.root)


def _strip(mut doc: PyJson) raises:
    """Remove skin members and skin attributes."""
    var nodes = doc.at(doc.root, "nodes")
    if doc.kind(nodes) != PY_LIST:
        raise Error("nodes is not a list")
    for index in range(doc.length(nodes)):
        var node = doc.item(nodes, index)
        if doc.kind(node) != PY_DICT:
            raise Error("node is not an object")
        if doc.get(node, "skin") != MISSING:
            doc.remove(node, "skin")
    if doc.get(doc.root, "skins") != MISSING:
        doc.remove(doc.root, "skins")
    var meshes = doc.at(doc.root, "meshes")
    if doc.kind(meshes) != PY_LIST:
        raise Error("meshes is not a list")
    for mesh_index in range(doc.length(meshes)):
        var primitives = doc.at(doc.item(meshes, mesh_index), "primitives")
        if doc.kind(primitives) != PY_LIST:
            raise Error("primitives is not a list")
        for primitive_index in range(doc.length(primitives)):
            var attributes = doc.at(
                doc.item(primitives, primitive_index), "attributes"
            )
            if doc.kind(attributes) != PY_DICT:
                raise Error("attributes is not an object")
            var drop = List[String]()
            for key_index in range(doc.length(attributes)):
                var key = doc.key(attributes, key_index)
                if _skin_key(key):
                    drop.append(key)
            for key_index in range(len(drop)):
                doc.remove(attributes, drop[key_index])


def _skin_key(key: String) -> Bool:
    """Return whether an attribute is joints, weights or vertex colors."""
    return (
        key.startswith("JOINTS_")
        or key.startswith("WEIGHTS_")
        or key.startswith("COLOR_")
    )


def main() raises:
    """Print one glTF file with its skin data removed."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_gltf_skin FILE", file=stderr)
        exit(2)
    try:
        print(strip_text(arguments[1]))
    except error:
        print("carla_gltf_skin:", error, file=stderr)
        exit(1)
