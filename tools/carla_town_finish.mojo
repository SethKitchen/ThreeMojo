# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Finish a simplified far mesh.

    carla_town_finish FILE

`FILE` is JSON. `mode` is `prepare` or `wind`. `prepare` reads the
simplified points and triangles. When `box` is present, each point stays
inside that box. A triangle that is not finite is left out. The program
prints the corners and one area normal per triangle. `wind` reads those
corners, their texture coordinates and the original normals they face.
A face that points the other way is turned back.
"""

from std.math import isinf, isnan, sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson


def finish_text(text: String) raises -> String:
    """Return one finish step as JSON.

    Args:
        text: A JSON object. `mode` selects the step.

    Returns:
        The corners and normals, the wound mesh, or `{"empty": true}`.

    Raises:
        Error: If the JSON is not that step, or an index is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("finish request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode == "prepare":
        return _prepare(doc, root)
    if mode == "wind":
        return _wind(doc, root)
    raise Error("mode is not prepare or wind")


def _prepare(doc: PyJson, root: Int) raises -> String:
    """Clip points, drop non-finite triangles, and return area normals."""
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    _vec3(doc, doc.at(root, "points"), px, py, pz)
    var faces = _triangles(doc, doc.at(root, "triangles"), len(px))
    var box = doc.get(root, "box")
    if box != -1 and not doc.is_none(box):
        var bx = List[Float64]()
        var by = List[Float64]()
        var bz = List[Float64]()
        _vec3(doc, box, bx, by, bz)
        if len(bx) == 0:
            raise Error("box is empty")
        var low_x = bx[0]
        var low_y = by[0]
        var low_z = bz[0]
        var high_x = bx[0]
        var high_y = by[0]
        var high_z = bz[0]
        for index in range(len(bx)):
            if bx[index] < low_x:
                low_x = bx[index]
            if by[index] < low_y:
                low_y = by[index]
            if bz[index] < low_z:
                low_z = bz[index]
            if bx[index] > high_x:
                high_x = bx[index]
            if by[index] > high_y:
                high_y = by[index]
            if bz[index] > high_z:
                high_z = bz[index]
        for index in range(len(px)):
            px[index] = _clip(px[index], low_x, high_x)
            py[index] = _clip(py[index], low_y, high_y)
            pz[index] = _clip(pz[index], low_z, high_z)
    var out = String('{"corners":[')
    var normals = String('"normals":[')
    var written = 0
    var face_count = len(faces) // 3
    for face in range(face_count):
        var base = face * 3
        var finite = True
        for corner in range(3):
            var vertex = faces[base + corner]
            if (
                not _finite(px[vertex])
                or not _finite(py[vertex])
                or not _finite(pz[vertex])
            ):
                finite = False
        if not finite:
            continue
        var x0 = px[faces[base]]
        var y0 = py[faces[base]]
        var z0 = pz[faces[base]]
        var x1 = px[faces[base + 1]]
        var y1 = py[faces[base + 1]]
        var z1 = pz[faces[base + 1]]
        var x2 = px[faces[base + 2]]
        var y2 = py[faces[base + 2]]
        var z2 = pz[faces[base + 2]]
        var ex1 = _fsub(x1, x0)
        var ey1 = _fsub(y1, y0)
        var ez1 = _fsub(z1, z0)
        var ex2 = _fsub(x2, x0)
        var ey2 = _fsub(y2, y0)
        var ez2 = _fsub(z2, z0)
        var cx = _fsub(_fmul(ey1, ez2), _fmul(ez1, ey2))
        var cy = _fsub(_fmul(ez1, ex2), _fmul(ex1, ez2))
        var cz = _fsub(_fmul(ex1, ey2), _fmul(ey1, ex2))
        var length = sqrt(
            _fadd(_fadd(_fmul(cx, cx), _fmul(cy, cy)), _fmul(cz, cz))
        )
        if length < 1e-12:
            length = 1e-12
        cx = _fdiv(cx, length)
        cy = _fdiv(cy, length)
        cz = _fdiv(cz, length)
        if written > 0:
            out += ","
            normals += ","
        written += 1
        out += "[["
        out += _xyz(x0, y0, z0)
        out += "],["
        out += _xyz(x1, y1, z1)
        out += "],["
        out += _xyz(x2, y2, z2)
        out += "]]"
        normals += "["
        normals += _xyz(cx, cy, cz)
        normals += "]"
    if written == 0:
        return '{"empty": true}'
    out += "],"
    out += normals
    out += "]}"
    return out^


def _wind(doc: PyJson, root: Int) raises -> String:
    """Turn back a face that points away from its original."""
    var cx = List[Float64]()
    var cy = List[Float64]()
    var cz = List[Float64]()
    var nx = List[Float64]()
    var ny = List[Float64]()
    var nz = List[Float64]()
    var us = List[Float64]()
    var vs = List[Float64]()
    var fx = List[Float64]()
    var fy = List[Float64]()
    var fz = List[Float64]()
    _vec3(doc, doc.at(root, "corners"), cx, cy, cz)
    _vec3(doc, doc.at(root, "normals"), nx, ny, nz)
    _vec2(doc, doc.at(root, "uvs"), us, vs)
    _vec3(doc, doc.at(root, "facing"), fx, fy, fz)
    var count = len(nx)
    if len(cx) != count * 3 or len(us) != count * 3 or len(fx) != count:
        raise Error("wind arrays differ in length")
    for face in range(count):
        var dot = _fadd(
            _fadd(_fmul(nx[face], fx[face]), _fmul(ny[face], fy[face])),
            _fmul(nz[face], fz[face]),
        )
        if dot < 0.0:
            var base = face * 3
            _swap3(cx, cy, cz, base, base + 2)
            _swap2(us, vs, base, base + 2)
            nx[face] = -nx[face]
            ny[face] = -ny[face]
            nz[face] = -nz[face]
    var out = String('{"positions":[')
    for index in range(len(cx)):
        if index > 0:
            out += ","
        out += "["
        out += _xyz(cx[index], cy[index], cz[index])
        out += "]"
    out += '],"normals":['
    for face in range(count):
        for _corner in range(3):
            if face > 0 or _corner > 0:
                out += ","
            out += "["
            out += _xyz(nx[face], ny[face], nz[face])
            out += "]"
    out += '],"uvs":['
    for index in range(len(us)):
        if index > 0:
            out += ","
        out += "["
        out += python_repr(us[index])
        out += ","
        out += python_repr(vs[index])
        out += "]"
    out += '],"triangles":['
    for face in range(count):
        if face > 0:
            out += ","
        var base = face * 3
        out += "["
        out += String(base)
        out += ","
        out += String(base + 1)
        out += ","
        out += String(base + 2)
        out += "]"
    out += "]}"
    return out^


def _clip(value: Float64, low: Float64, high: Float64) -> Float64:
    """Return `value` clamped to `low` and `high`."""
    if value < low:
        return low
    if value > high:
        return high
    return value


def _finite(value: Float64) -> Bool:
    """Return whether `value` is finite."""
    return not isnan(value) and not isinf(value)


def _swap3(
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
    left: Int,
    right: Int,
):
    """Exchange two 3-vectors."""
    var x = xs[left]
    var y = ys[left]
    var z = zs[left]
    xs[left] = xs[right]
    ys[left] = ys[right]
    zs[left] = zs[right]
    xs[right] = x
    ys[right] = y
    zs[right] = z


def _swap2(mut xs: List[Float64], mut ys: List[Float64], left: Int, right: Int):
    """Exchange two pairs."""
    var x = xs[left]
    var y = ys[left]
    xs[left] = xs[right]
    ys[left] = ys[right]
    xs[right] = x
    ys[right] = y


def _xyz(x: Float64, y: Float64, z: Float64) raises -> String:
    """Return one 3-vector as JSON text, without brackets."""
    var out = python_repr(x)
    out += ","
    out += python_repr(y)
    out += ","
    out += python_repr(z)
    return out^


def _vec3(
    doc: PyJson,
    node: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
) raises:
    """Read 3-vectors. A nested triangle is flattened in corner order."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST:
            raise Error("vector is not 3 numbers")
        if doc.length(point) == 3 and doc.kind(doc.item(point, 0)) != PY_LIST:
            xs.append(_number(doc, doc.item(point, 0)))
            ys.append(_number(doc, doc.item(point, 1)))
            zs.append(_number(doc, doc.item(point, 2)))
        elif doc.length(point) == 3:
            for corner in range(3):
                var inner = doc.item(point, corner)
                if doc.kind(inner) != PY_LIST or doc.length(inner) != 3:
                    raise Error("vector is not 3 numbers")
                xs.append(_number(doc, doc.item(inner, 0)))
                ys.append(_number(doc, doc.item(inner, 1)))
                zs.append(_number(doc, doc.item(inner, 2)))
        else:
            raise Error("vector is not 3 numbers")


def _vec2(
    doc: PyJson, node: Int, mut xs: List[Float64], mut ys: List[Float64]
) raises:
    """Read texture coordinates, including three pairs per triangle."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST:
            raise Error("vector is not 2 numbers")
        if doc.length(point) == 2 and doc.kind(doc.item(point, 0)) != PY_LIST:
            xs.append(_number(doc, doc.item(point, 0)))
            ys.append(_number(doc, doc.item(point, 1)))
        elif doc.length(point) == 3:
            for corner in range(3):
                var inner = doc.item(point, corner)
                if doc.kind(inner) != PY_LIST or doc.length(inner) != 2:
                    raise Error("vector is not 2 numbers")
                xs.append(_number(doc, doc.item(inner, 0)))
                ys.append(_number(doc, doc.item(inner, 1)))
        else:
            raise Error("vector is not 2 numbers")


def _triangles(doc: PyJson, node: Int, count: Int) raises -> List[Int]:
    """Return triangle indices."""
    if doc.kind(node) != PY_LIST:
        raise Error("triangles are not a list")
    var out = List[Int]()
    for index in range(doc.length(node)):
        var triangle = doc.item(node, index)
        if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
            raise Error("triangle is not three indices")
        for corner in range(3):
            var face = _whole(doc, doc.item(triangle, corner))
            if face < 0 or face >= count:
                raise Error("index out of range")
            out.append(face)
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
    return Int(parse_float(doc.text(node)))


@no_inline
def _fmul(left: Float64, right: Float64) -> Float64:
    """Return one product, rounded before the next operation."""
    return left * right


@no_inline
def _fadd(left: Float64, right: Float64) -> Float64:
    """Return one sum, rounded before the next operation."""
    return left + right


@no_inline
def _fsub(left: Float64, right: Float64) -> Float64:
    """Return one difference, rounded before the next operation."""
    return left - right


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


def main() raises:
    """Print one finish step for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_finish FILE", file=stderr)
        exit(2)
    try:
        print(finish_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_finish:", error, file=stderr)
        exit(1)
