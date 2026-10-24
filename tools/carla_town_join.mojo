# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Join a building's primitives into one mesh.

    carla_town_join FILE

`FILE` is JSON. `parts` lists each primitive's positions, normals, uvs
and triangles. Triangle indices are local to that part. The program
prints one mesh, with each later part's triangles shifted by the
vertices already written.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson


def join_text(text: String) raises -> String:
    """Return the joined mesh as JSON.

    Args:
        text: A JSON object with a `parts` list.

    Returns:
        One object with `positions`, `normals`, `uvs` and `triangles`.

    Raises:
        Error: If the JSON is not that list, or an index is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("join request is not an object")
    var parts = doc.at(root, "parts")
    if doc.kind(parts) != PY_LIST or doc.length(parts) == 0:
        raise Error("parts are not a list")
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    var nx = List[Float64]()
    var ny = List[Float64]()
    var nz = List[Float64]()
    var us = List[Float64]()
    var vs = List[Float64]()
    var triangles = List[Int]()
    for index in range(doc.length(parts)):
        var part = doc.item(parts, index)
        var base = len(px)
        var before_n = len(nx)
        var before_u = len(us)
        _vec3(doc, doc.at(part, "positions"), px, py, pz)
        _vec3(doc, doc.at(part, "normals"), nx, ny, nz)
        _vec2(doc, doc.at(part, "uvs"), us, vs)
        if (
            len(px) - base != len(nx) - before_n
            or len(px) - base != len(us) - before_u
        ):
            raise Error("attributes differ in length")
        var faces = _triangles(doc, doc.at(part, "triangles"), len(px) - base)
        for corner in faces:
            triangles.append(corner + base)
    var out = String('{"positions":')
    out += _points(px, py, pz)
    out += ',"normals":'
    out += _points(nx, ny, nz)
    out += ',"uvs":'
    out += _pairs(us, vs)
    out += ',"triangles":'
    out += _indices(triangles)
    out += "}"
    return out^


def _points(
    xs: List[Float64], ys: List[Float64], zs: List[Float64]
) raises -> String:
    """Return points as a JSON array."""
    var out = String("[")
    for index in range(len(xs)):
        if index > 0:
            out += ","
        out += "["
        out += python_repr(xs[index])
        out += ","
        out += python_repr(ys[index])
        out += ","
        out += python_repr(zs[index])
        out += "]"
    out += "]"
    return out^


def _pairs(xs: List[Float64], ys: List[Float64]) raises -> String:
    """Return pairs as a JSON array."""
    var out = String("[")
    for index in range(len(xs)):
        if index > 0:
            out += ","
        out += "["
        out += python_repr(xs[index])
        out += ","
        out += python_repr(ys[index])
        out += "]"
    out += "]"
    return out^


def _indices(values: List[Int]) -> String:
    """Return triangle indices as a JSON array."""
    var out = String("[")
    var count = len(values) // 3
    for index in range(count):
        if index > 0:
            out += ","
        out += "["
        out += String(values[index * 3])
        out += ","
        out += String(values[index * 3 + 1])
        out += ","
        out += String(values[index * 3 + 2])
        out += "]"
    out += "]"
    return out^


def _vec3(
    doc: PyJson,
    node: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
) raises:
    """Read a list of 3-vectors."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST or doc.length(point) != 3:
            raise Error("vector is not 3 numbers")
        xs.append(_number(doc, doc.item(point, 0)))
        ys.append(_number(doc, doc.item(point, 1)))
        zs.append(_number(doc, doc.item(point, 2)))


def _vec2(
    doc: PyJson, node: Int, mut xs: List[Float64], mut ys: List[Float64]
) raises:
    """Read a list of 2-vectors."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST or doc.length(point) != 2:
            raise Error("vector is not 2 numbers")
        xs.append(_number(doc, doc.item(point, 0)))
        ys.append(_number(doc, doc.item(point, 1)))


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


def main() raises:
    """Print the joined mesh for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_join FILE", file=stderr)
        exit(2)
    try:
        print(join_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_join:", error, file=stderr)
        exit(1)
