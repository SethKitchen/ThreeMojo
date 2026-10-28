# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Give a simplified triangle the texture of one original triangle.

    carla_town_uv FILE

`FILE` is JSON. `source` is the original triangle, three corners each.
`uvs` is that triangle's texture coordinates. `corners` is the new
triangle. The program projects each new corner into the original
triangle and prints the texture coordinates it finds there.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson


def uv_text(text: String) raises -> String:
    """Return projected texture coordinates as JSON.

    Args:
        text: A JSON object with `source`, `uvs` and `corners`. Each is
            one list per triangle. A triangle has three corners.

    Returns:
        An object with `uvs`, three pairs per triangle.

    Raises:
        Error: If the JSON is not that mesh, or a triangle is short.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("uv request is not an object")
    var sx = List[Float64]()
    var sy = List[Float64]()
    var sz = List[Float64]()
    var cu = List[Float64]()
    var cv = List[Float64]()
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    _vec3(doc, doc.at(root, "source"), sx, sy, sz)
    _vec2(doc, doc.at(root, "uvs"), cu, cv)
    _vec3(doc, doc.at(root, "corners"), px, py, pz)
    if len(sx) != len(px) or len(sx) != len(cu):
        raise Error("triangles differ in length")
    if len(sx) % 3 != 0:
        raise Error("triangles are not whole")
    var out = String('{"uvs":[')
    var count = len(sx) // 3
    for face in range(count):
        var base = face * 3
        var e0x = _fsub(sx[base + 1], sx[base])
        var e0y = _fsub(sy[base + 1], sy[base])
        var e0z = _fsub(sz[base + 1], sz[base])
        var e1x = _fsub(sx[base + 2], sx[base])
        var e1y = _fsub(sy[base + 2], sy[base])
        var e1z = _fsub(sz[base + 2], sz[base])
        var d00 = _dot(e0x, e0y, e0z, e0x, e0y, e0z)
        var d01 = _dot(e0x, e0y, e0z, e1x, e1y, e1z)
        var d11 = _dot(e1x, e1y, e1z, e1x, e1y, e1z)
        var denom = _fsub(_fmul(d00, d11), _fmul(d01, d01))
        if _abs(denom) <= 1e-18:
            denom = 1e-18
        for corner in range(3):
            var at = base + corner
            var e2x = _fsub(px[at], sx[base])
            var e2y = _fsub(py[at], sy[base])
            var e2z = _fsub(pz[at], sz[base])
            var d20 = _dot(e2x, e2y, e2z, e0x, e0y, e0z)
            var d21 = _dot(e2x, e2y, e2z, e1x, e1y, e1z)
            var v = _fdiv(_fsub(_fmul(d11, d20), _fmul(d01, d21)), denom)
            var w = _fdiv(_fsub(_fmul(d00, d21), _fmul(d01, d20)), denom)
            var u = _fsub(_fsub(1.0, v), w)
            var tu = _fadd(
                _fadd(_fmul(u, cu[base]), _fmul(v, cu[base + 1])),
                _fmul(w, cu[base + 2]),
            )
            var tv = _fadd(
                _fadd(_fmul(u, cv[base]), _fmul(v, cv[base + 1])),
                _fmul(w, cv[base + 2]),
            )
            if face > 0 or corner > 0:
                out += ","
            out += "["
            out += python_repr(tu)
            out += ","
            out += python_repr(tv)
            out += "]"
    out += "]}"
    return out^


def _dot(
    ax: Float64,
    ay: Float64,
    az: Float64,
    bx: Float64,
    by: Float64,
    bz: Float64,
) -> Float64:
    """Return a dot product, each product rounded first."""
    return _fadd(_fadd(_fmul(ax, bx), _fmul(ay, by)), _fmul(az, bz))


def _abs(value: Float64) -> Float64:
    """Return the absolute value."""
    if value < 0.0:
        return -value
    return value


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


def _vec3(
    doc: PyJson,
    node: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
) raises:
    """Read triangles of 3-vectors. Each triangle is three corners."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var triangle = doc.item(node, index)
        if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
            raise Error("triangle is not three corners")
        for corner in range(3):
            var point = doc.item(triangle, corner)
            if doc.kind(point) != PY_LIST or doc.length(point) != 3:
                raise Error("vector is not 3 numbers")
            xs.append(_number(doc, doc.item(point, 0)))
            ys.append(_number(doc, doc.item(point, 1)))
            zs.append(_number(doc, doc.item(point, 2)))


def _vec2(
    doc: PyJson, node: Int, mut xs: List[Float64], mut ys: List[Float64]
) raises:
    """Read triangles of texture coordinates."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var triangle = doc.item(node, index)
        if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
            raise Error("triangle is not three corners")
        for corner in range(3):
            var point = doc.item(triangle, corner)
            if doc.kind(point) != PY_LIST or doc.length(point) != 2:
                raise Error("vector is not 2 numbers")
            xs.append(_number(doc, doc.item(point, 0)))
            ys.append(_number(doc, doc.item(point, 1)))


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as a float."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("coordinate is not a number")


def main() raises:
    """Print the texture coordinates for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_uv FILE", file=stderr)
        exit(2)
    try:
        print(uv_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_uv:", error, file=stderr)
        exit(1)
