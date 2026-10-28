# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Weight vertex normals by the area of the faces that meet there.

    carla_area_normals FILE

`FILE` is JSON with `points` and `faces`. The program prints one unit
normal per point. A point whose faces cancel, or that has none, points
up.
"""

from std.math import sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_float import parse_float
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson
from tools._python_math import product


def normals_text(path: String) raises -> String:
    """Return area-weighted unit normals as JSON.

    Args:
        path: A JSON object with `points`, a list of XYZ coordinates, and
            `faces`, a list of three indexes per triangle.

    Returns:
        A JSON array of unit XYZ normals, one per point. A normal whose
        length is at most `1e-12` is `[0.0, 1.0, 0.0]`.

    Raises:
        Error: If the file cannot be read, a list has the wrong shape, or
            a face index is out of range.
    """
    var doc = PyJson.parse(Path(path).read_text())
    if doc.kind(doc.root) != PY_DICT:
        raise Error("mesh is not an object")
    var points = _vectors(doc, doc.at(doc.root, "points"))
    var faces = _faces(doc, doc.at(doc.root, "faces"))
    var count = len(points) // 3
    _check_faces(faces, count)
    var normals = _normals(points, faces, count)
    return _emit(normals, count)


def _normals(
    points: List[Float64], faces: List[Int], count: Int
) -> List[Float64]:
    """Return one unit normal per point, in point order."""
    var face_count = len(faces) // 3
    var areas = List[Float64]()
    for face in range(face_count):
        var i0 = faces[face * 3]
        var i1 = faces[face * 3 + 1]
        var i2 = faces[face * 3 + 2]
        var e1x = points[i1 * 3] - points[i0 * 3]
        var e1y = points[i1 * 3 + 1] - points[i0 * 3 + 1]
        var e1z = points[i1 * 3 + 2] - points[i0 * 3 + 2]
        var e2x = points[i2 * 3] - points[i0 * 3]
        var e2y = points[i2 * 3 + 1] - points[i0 * 3 + 1]
        var e2z = points[i2 * 3 + 2] - points[i0 * 3 + 2]
        areas.append(product(e1y, e2z) - product(e1z, e2y))
        areas.append(product(e1z, e2x) - product(e1x, e2z))
        areas.append(product(e1x, e2y) - product(e1y, e2x))
    var sums = List[Float64]()
    for _ in range(count * 3):
        sums.append(0.0)
    for corner in range(3):
        for face in range(face_count):
            var vertex = faces[face * 3 + corner]
            sums[vertex * 3] = sums[vertex * 3] + areas[face * 3]
            sums[vertex * 3 + 1] = sums[vertex * 3 + 1] + areas[face * 3 + 1]
            sums[vertex * 3 + 2] = sums[vertex * 3 + 2] + areas[face * 3 + 2]
    var out = List[Float64]()
    for index in range(count):
        var x = sums[index * 3]
        var y = sums[index * 3 + 1]
        var z = sums[index * 3 + 2]
        var length = sqrt(product(x, x) + product(y, y) + product(z, z))
        if length > 1e-12:
            out.append(x / length)
            out.append(y / length)
            out.append(z / length)
        else:
            out.append(0.0)
            out.append(1.0)
            out.append(0.0)
    return out^


def _vectors(doc: PyJson, node: Int) raises -> List[Float64]:
    """Return XYZ points as a flat list."""
    if doc.kind(node) != PY_LIST:
        raise Error("points is not a list")
    var out = List[Float64]()
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST or doc.length(point) != 3:
            raise Error("point is not 3 numbers")
        for axis in range(3):
            out.append(_number(doc, doc.item(point, axis)))
    return out^


def _faces(doc: PyJson, node: Int) raises -> List[Int]:
    """Return triangle indexes as a flat list."""
    if doc.kind(node) != PY_LIST:
        raise Error("faces is not a list")
    var out = List[Int]()
    for index in range(doc.length(node)):
        var face = doc.item(node, index)
        if doc.kind(face) != PY_LIST or doc.length(face) != 3:
            raise Error("face is not 3 indexes")
        for corner in range(3):
            var item = doc.item(face, corner)
            if doc.kind(item) != PY_INT:
                raise Error("face index is not an int")
            out.append(Int(doc.text(item)))
    return out^


def _check_faces(mut faces: List[Int], count: Int) raises:
    """Reject an index outside the point list, and rewrite a negative one."""
    for index in range(len(faces)):
        var vertex = faces[index]
        if vertex < 0:
            vertex += count
        if vertex < 0 or vertex >= count:
            raise Error("face index out of range")
        faces[index] = vertex


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as `float`."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("coordinate is not a number")


def _emit(normals: List[Float64], count: Int) raises -> String:
    """Return the normals as a JSON array of XYZ rows."""
    var tree = JsonTree()
    var rows = tree.array()
    for index in range(count):
        var row = tree.array()
        tree.append(row, tree.number(normals[index * 3]))
        tree.append(row, tree.number(normals[index * 3 + 1]))
        tree.append(row, tree.number(normals[index * 3 + 2]))
        tree.append(rows, row)
    return tree.dumps(rows, False)


def main() raises:
    """Print area-weighted normals for the mesh file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_area_normals FILE", file=stderr)
        exit(2)
    try:
        print(normals_text(arguments[1]))
    except error:
        print("carla_area_normals:", error, file=stderr)
        exit(1)
