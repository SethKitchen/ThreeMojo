# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the original triangle a simplified face reads.

    carla_town_choose FILE

`FILE` is JSON. `mode` is `source` or `choose`. `source` reads the
original positions and triangles. It prints each triangle's center and
its area normal. `choose` reads those centers, a short list of neighbor
indexes for each new face, and the new face. The neighbor nearest the
new face's plane wins. An equal score keeps the earlier neighbor.
"""

from std.math import sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import python_repr
from tools._python_json import PY_DICT, PY_LIST, PyJson
from tools._town_json import json_index, json_triangles, json_vec3


def choose_text(text: String) raises -> String:
    """Return one choice step as JSON.

    Args:
        text: A JSON object. `mode` selects the step.

    Returns:
        The centers and normals, or the chosen triangle index of each face.

    Raises:
        Error: If the JSON is not that step, or an index is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("choose request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode == "source":
        return _source(doc, root)
    if mode == "choose":
        return _choose(doc, root)
    raise Error("mode is not source or choose")


def _source(doc: PyJson, root: Int) raises -> String:
    """Return each triangle's center and its unit area normal."""
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    json_vec3(doc, doc.at(root, "positions"), px, py, pz)
    var faces = json_triangles(doc, doc.at(root, "triangles"), len(px))
    var out = String('{"centers":[')
    var normals = String('"normals":[')
    var count = len(faces) // 3
    for face in range(count):
        var base = face * 3
        var x0 = px[faces[base]]
        var y0 = py[faces[base]]
        var z0 = pz[faces[base]]
        var x1 = px[faces[base + 1]]
        var y1 = py[faces[base + 1]]
        var z1 = pz[faces[base + 1]]
        var x2 = px[faces[base + 2]]
        var y2 = py[faces[base + 2]]
        var z2 = pz[faces[base + 2]]
        if face > 0:
            out += ","
            normals += ","
        out += "["
        out += _xyz(
            _fdiv(_fadd(_fadd(x0, x1), x2), 3.0),
            _fdiv(_fadd(_fadd(y0, y1), y2), 3.0),
            _fdiv(_fadd(_fadd(z0, z1), z2), 3.0),
        )
        out += "]"
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
        normals += "["
        normals += _xyz(_fdiv(cx, length), _fdiv(cy, length), _fdiv(cz, length))
        normals += "]"
    out += "],"
    out += normals
    out += "]}"
    return out^


def _choose(doc: PyJson, root: Int) raises -> String:
    """Return the neighbor nearest each new face's plane."""
    var cx = List[Float64]()
    var cy = List[Float64]()
    var cz = List[Float64]()
    var nx = List[Float64]()
    var ny = List[Float64]()
    var nz = List[Float64]()
    var qx = List[Float64]()
    var qy = List[Float64]()
    var qz = List[Float64]()
    var fx = List[Float64]()
    var fy = List[Float64]()
    var fz = List[Float64]()
    json_vec3(doc, doc.at(root, "centers"), cx, cy, cz)
    json_vec3(doc, doc.at(root, "normals"), nx, ny, nz)
    json_vec3(doc, doc.at(root, "queries"), qx, qy, qz)
    json_vec3(doc, doc.at(root, "faces"), fx, fy, fz)
    if len(cx) != len(nx) or len(qx) != len(fx):
        raise Error("choose arrays differ in length")
    var near = doc.at(root, "near")
    if doc.kind(near) != PY_LIST or doc.length(near) != len(qx):
        raise Error("near does not match the faces")
    var out = String('{"best":[')
    for face in range(len(qx)):
        var row = doc.item(near, face)
        if doc.kind(row) != PY_LIST or doc.length(row) == 0:
            raise Error("near row is empty")
        var best = _index(doc, doc.item(row, 0), len(cx))
        var best_score = _score(
            qx[face],
            qy[face],
            qz[face],
            fx[face],
            fy[face],
            fz[face],
            cx[best],
            cy[best],
            cz[best],
            nx[best],
            ny[best],
            nz[best],
        )
        for slot in range(1, doc.length(row)):
            var candidate = _index(doc, doc.item(row, slot), len(cx))
            var score = _score(
                qx[face],
                qy[face],
                qz[face],
                fx[face],
                fy[face],
                fz[face],
                cx[candidate],
                cy[candidate],
                cz[candidate],
                nx[candidate],
                ny[candidate],
                nz[candidate],
            )
            if score < best_score:
                best = candidate
                best_score = score
        if face > 0:
            out += ","
        out += String(best)
    out += "]}"
    return out^


def _score(
    qx: Float64,
    qy: Float64,
    qz: Float64,
    fx: Float64,
    fy: Float64,
    fz: Float64,
    cx: Float64,
    cy: Float64,
    cz: Float64,
    nx: Float64,
    ny: Float64,
    nz: Float64,
) -> Float64:
    """Return the plane offset minus the absolute facing."""
    var facing = _dot(nx, ny, nz, fx, fy, fz)
    var offset = _abs(
        _dot(nx, ny, nz, _fsub(qx, cx), _fsub(qy, cy), _fsub(qz, cz))
    )
    return _fsub(offset, _abs(facing))


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


def _index(doc: PyJson, node: Int, count: Int) raises -> Int:
    """Return a neighbor index inside `count`."""
    var value = json_index(doc, node)
    if value < 0 or value >= count:
        raise Error("index out of range")
    return value


def _xyz(x: Float64, y: Float64, z: Float64) raises -> String:
    """Return one 3-vector as JSON text, without brackets."""
    var out = python_repr(x)
    out += ","
    out += python_repr(y)
    out += ","
    out += python_repr(z)
    return out^


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
    """Print one choice step for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_choose FILE", file=stderr)
        exit(2)
    try:
        print(choose_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_choose:", error, file=stderr)
        exit(1)
