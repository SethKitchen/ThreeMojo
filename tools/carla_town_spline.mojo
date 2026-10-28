# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Place one bent spline mesh in the renderer frame.

    carla_town_spline FILE

`FILE` is JSON. It has a 4×4 `matrix`, `positions`, `normals` and
`triangles`. The positions are already bent, in the component frame,
in centimeters. The program prints points in meters, unit normals,
and triangles. A negative determinant reverses each triangle.
"""

from std.math import sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._python_float import parse_float, python_repr
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson


def spline_text(text: String) raises -> String:
    """Return one bent mesh placed in the renderer frame, as JSON.

    Args:
        text: A JSON object with `matrix`, `positions`, `normals` and
            `triangles`.

    Returns:
        JSON with `points`, `normals` and `triangles`.

    Raises:
        Error: If the JSON is not that object, a value is not a number,
            or the linear matrix is singular.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("spline request is not an object")
    var matrix = _matrix(doc, doc.at(root, "matrix"))
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var nxs = List[Float64]()
    var nys = List[Float64]()
    var nzs = List[Float64]()
    _vectors(doc, doc.at(root, "positions"), xs, ys, zs)
    _vectors(doc, doc.at(root, "normals"), nxs, nys, nzs)
    if len(xs) != len(nxs):
        raise Error("positions and normals differ in length")
    var triangles = _triangles(doc, doc.at(root, "triangles"))
    var linear = List[Float64]()
    var translation = List[Float64]()
    for row in range(3):
        for col in range(3):
            linear.append(matrix[row * 4 + col])
        translation.append(matrix[3 * 4 + row])
    var inverse = _inverse(linear)
    var det = inverse[9]
    var flip = det < 0.0
    var zeros = List[Float64]()
    zeros.append(0.0)
    zeros.append(0.0)
    zeros.append(0.0)
    var points = _placed(xs, ys, zs, linear, translation, False)
    var normals = _placed(nxs, nys, nzs, inverse, zeros, True)
    _normalize(normals)
    if flip:
        var flipped = List[Int]()
        var count = len(triangles) // 3
        for index in range(count):
            var base = index * 3
            flipped.append(triangles[base + 2])
            flipped.append(triangles[base + 1])
            flipped.append(triangles[base])
        triangles = flipped^
    return _json(points, normals, triangles)


def _matrix(doc: PyJson, node: Int) raises -> List[Float64]:
    """Return 16 matrix entries, row by row."""
    if doc.kind(node) != PY_LIST or doc.length(node) != 4:
        raise Error("matrix is not 4 by 4")
    var out = List[Float64]()
    for row in range(4):
        var line = doc.item(node, row)
        if doc.kind(line) != PY_LIST or doc.length(line) != 4:
            raise Error("matrix is not 4 by 4")
        for col in range(4):
            out.append(_number(doc, doc.item(line, col)))
    return out^


def _vectors(
    doc: PyJson,
    node: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
) raises:
    """Append x, y and z from a list of 3-vectors."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    var count = doc.length(node)
    for index in range(count):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST or doc.length(point) != 3:
            raise Error("vector is not 3 numbers")
        xs.append(_number(doc, doc.item(point, 0)))
        ys.append(_number(doc, doc.item(point, 1)))
        zs.append(_number(doc, doc.item(point, 2)))


def _triangles(doc: PyJson, node: Int) raises -> List[Int]:
    """Return triangle indices, three per triangle."""
    if doc.kind(node) != PY_LIST:
        raise Error("triangles are not a list")
    var out = List[Int]()
    var count = doc.length(node)
    for index in range(count):
        var triangle = doc.item(node, index)
        if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
            raise Error("triangle is not three indices")
        for corner in range(3):
            out.append(_whole(doc, doc.item(triangle, corner)))
    return out^


def _inverse(linear: List[Float64]) raises -> List[Float64]:
    """Return the transpose of the inverse, then the determinant.

    The first nine entries are `inv(M).T`, row by row. Entry 9 is `det(M)`.
    """
    var a = linear[0]
    var b = linear[1]
    var c = linear[2]
    var d = linear[3]
    var e = linear[4]
    var f = linear[5]
    var g = linear[6]
    var h = linear[7]
    var i = linear[8]
    var c00 = (e * i) - (f * h)
    var c01 = (f * g) - (d * i)
    var c02 = (d * h) - (e * g)
    var c10 = (c * h) - (b * i)
    var c11 = (a * i) - (c * g)
    var c12 = (b * g) - (a * h)
    var c20 = (b * f) - (c * e)
    var c21 = (c * d) - (a * f)
    var c22 = (a * e) - (b * d)
    var det = ((a * c00) + (b * c01)) + (c * c02)
    if det == 0.0:
        raise Error("singular matrix")
    # inv is the transpose of the cofactor matrix, divided by det.
    # Store inv.T, which is the cofactor matrix divided by det.
    var out = List[Float64]()
    out.append(c00 / det)
    out.append(c01 / det)
    out.append(c02 / det)
    out.append(c10 / det)
    out.append(c11 / det)
    out.append(c12 / det)
    out.append(c20 / det)
    out.append(c21 / det)
    out.append(c22 / det)
    out.append(det)
    return out^


def _placed(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    linear: List[Float64],
    translation: List[Float64],
    normals: Bool,
) -> List[Float64]:
    """Return transformed vectors with y and z swapped.

    Points are divided by 100. Normals are not.
    """
    var out = List[Float64]()
    var count = len(xs)
    for index in range(count):
        var x = xs[index]
        var y = ys[index]
        var z = zs[index]
        var world = List[Float64]()
        for col in range(3):
            var value = ((x * linear[col]) + (y * linear[3 + col])) + (
                z * linear[6 + col]
            )
            value += translation[col]
            world.append(value)
        var scale = 1.0
        if not normals:
            scale = 0.01
        out.append(world[0] * scale)
        out.append(world[2] * scale)
        out.append(world[1] * scale)
    return out^


def _normalize(mut values: List[Float64]):
    """Scale each normal to unit length, with a floor of `1e-12`."""
    var count = len(values) // 3
    for index in range(count):
        var base = index * 3
        var x = values[base]
        var y = values[base + 1]
        var z = values[base + 2]
        var length = sqrt(((x * x) + (y * y)) + (z * z))
        if length < 1e-12:
            length = 1e-12
        values[base] = x / length
        values[base + 1] = y / length
        values[base + 2] = z / length


def _json(
    points: List[Float64], normals: List[Float64], triangles: List[Int]
) raises -> String:
    """Return the placed mesh as JSON."""
    var out = String('{"points": ')
    out += _vectors_json(points)
    out += ', "normals": '
    out += _vectors_json(normals)
    out += ', "triangles": '
    out += _triangles_json(triangles)
    out += "}"
    return out^


def _vectors_json(values: List[Float64]) raises -> String:
    """Return vectors as a JSON list."""
    var out = String("[")
    var count = len(values) // 3
    for index in range(count):
        if index > 0:
            out += ", "
        var base = index * 3
        out += "["
        out += python_repr(values[base])
        out += ", "
        out += python_repr(values[base + 1])
        out += ", "
        out += python_repr(values[base + 2])
        out += "]"
    out += "]"
    return out^


def _triangles_json(values: List[Int]) -> String:
    """Return triangles as a JSON list."""
    var out = String("[")
    var count = len(values) // 3
    for index in range(count):
        if index > 0:
            out += ", "
        var base = index * 3
        out += "["
        out += String(values[base])
        out += ", "
        out += String(values[base + 1])
        out += ", "
        out += String(values[base + 2])
        out += "]"
    out += "]"
    return out^


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as a float."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("coordinate is not a number")


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("index is not an integer")
    return BigInt.parse(doc.text(node)).to_int()


def main() raises:
    """Print the placed spline mesh for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_spline FILE", file=stderr)
        exit(2)
    try:
        print(spline_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_spline:", error, file=stderr)
        exit(1)
