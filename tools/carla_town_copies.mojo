# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build each copy's Unreal world matrix.

    carla_town_copies FILE

`FILE` is one layout component: `scale`, `rotation` and `location`, and
an optional `instances` list. The program prints each copy's 4×4 matrix
in row-vector order. With no instances, that is the component matrix.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PyJson,
)
from tools._python_math import cos, product, radians, sin


def copies_text(path: String) raises -> String:
    """Return each copy's world matrix as JSON.

    Args:
        path: A JSON object with `scale`, `rotation` and `location`.
            `instances`, when present, is a list of 4×4 matrices.

    Returns:
        A JSON array of 4×4 matrices. Each matrix is four rows of four
        numbers. An empty `instances` list returns `[]`.

    Raises:
        Error: If the file cannot be read, or a field is not the shape
            the placement uses.
    """
    var doc = PyJson.parse(Path(path).read_text())
    if doc.kind(doc.root) != PY_DICT:
        raise Error("placement is not an object")
    var scale = _vector3(doc, doc.root, "scale")
    var rotation = _vector3(doc, doc.root, "rotation")
    var location = _vector3(doc, doc.root, "location")
    var component = _component(scale, rotation, location)
    var tree = JsonTree()
    var array = tree.array()
    var listed = doc.get(doc.root, "instances")
    if listed == MISSING:
        tree.append(array, _matrix(tree, component))
    else:
        if doc.kind(listed) != PY_LIST:
            raise Error("instances is not a list")
        for index in range(doc.length(listed)):
            var flat = _sixteen(doc, doc.item(listed, index))
            var world = _mul(flat, component)
            tree.append(array, _matrix(tree, world))
    return tree.dumps(array, False)


def _vector3(doc: PyJson, root: Int, key: String) raises -> List[Float64]:
    """Return three numbers stored at `key`."""
    var node = doc.at(root, key)
    if doc.kind(node) != PY_LIST or doc.length(node) != 3:
        raise Error(key + " is not 3 numbers")
    var out = List[Float64]()
    for index in range(3):
        out.append(_number(doc, doc.item(node, index)))
    return out^


def _sixteen(doc: PyJson, node: Int) raises -> List[Float64]:
    """Return one instance as 16 row-major numbers."""
    if doc.kind(node) != PY_LIST:
        raise Error("instance is not 16 numbers")
    var out = List[Float64]()
    var count = doc.length(node)
    if count == 16:
        for index in range(16):
            out.append(_number(doc, doc.item(node, index)))
        return out^
    if count == 4:
        for row in range(4):
            var line = doc.item(node, row)
            if doc.kind(line) != PY_LIST or doc.length(line) != 4:
                raise Error("instance is not 16 numbers")
            for col in range(4):
                out.append(_number(doc, doc.item(line, col)))
        return out^
    raise Error("instance is not 16 numbers")


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as `float`."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("placement value is not a number")


def _component(
    scale: List[Float64], rotation: List[Float64], location: List[Float64]
) -> List[Float64]:
    """Return scale, then rotation, then location, as a 4×4 matrix."""
    var turned = _rotation(rotation[0], rotation[1], rotation[2])
    var matrix = List[Float64]()
    for _ in range(16):
        matrix.append(0.0)
    for row in range(3):
        for col in range(3):
            # A diagonal product, so the two zero terms stay in the sum.
            # They clear a negated zero the way `diag(scale) @ rotation` does.
            var value = 0.0
            for k in range(3):
                var diagonal = scale[row] if k == row else 0.0
                value += product(diagonal, turned[k * 3 + col])
            matrix[row * 4 + col] = value
    matrix[12] = location[0]
    matrix[13] = location[1]
    matrix[14] = location[2]
    matrix[15] = 1.0
    return matrix^


def _rotation(pitch: Float64, yaw: Float64, roll: Float64) -> List[Float64]:
    """Return Unreal's row-vector rotation, in degrees."""
    var p = radians(pitch)
    var y = radians(yaw)
    var r = radians(roll)
    var sp = sin(p)
    var cp = cos(p)
    var sy = sin(y)
    var cy = cos(y)
    var sr = sin(r)
    var cr = cos(r)
    var out = List[Float64]()
    out.append(product(cp, cy))
    out.append(product(cp, sy))
    out.append(sp)
    var sr_sp = product(sr, sp)
    out.append(product(sr_sp, cy) - product(cr, sy))
    out.append(product(sr_sp, sy) + product(cr, cy))
    out.append(-product(sr, cp))
    var cr_sp = product(cr, sp)
    out.append(-(product(cr_sp, cy) + product(sr, sy)))
    out.append(product(cy, sr) - product(cr_sp, sy))
    out.append(product(cr, cp))
    return out^


def _mul(left: List[Float64], right: List[Float64]) -> List[Float64]:
    """Return `left @ right` for two row-major 4×4 matrices."""
    var out = List[Float64]()
    for row in range(4):
        for col in range(4):
            var sum = 0.0
            for k in range(4):
                sum += product(left[row * 4 + k], right[k * 4 + col])
            out.append(sum)
    return out^


def _matrix(mut tree: JsonTree, values: List[Float64]) raises -> Int:
    """Return a 4×4 JSON array."""
    var rows = tree.array()
    for row in range(4):
        var line = tree.array()
        for col in range(4):
            tree.append(line, tree.number(values[row * 4 + col]))
        tree.append(rows, line)
    return rows


def main() raises:
    """Print the world matrices for the component file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_copies FILE", file=stderr)
        exit(2)
    try:
        print(copies_text(arguments[1]))
    except error:
        print("carla_town_copies:", error, file=stderr)
        exit(1)
