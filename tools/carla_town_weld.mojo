# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Gather a far mesh's corners into cells.

    carla_town_weld FILE

`FILE` is JSON with positions, triangles, `divisions` and `minimum`.
Corners that fall in one cell become their mean. A triangle whose
corners meet, and a repeated triangle, are left out.
"""

from std.math import floor, sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import python_repr
from tools._python_json import PY_DICT, PyJson
from tools._town_json import json_number, json_triangles, json_vec3


def weld_text(text: String) raises -> String:
    """Return the welded points and the triangles that remain.

    Args:
        text: A JSON object with positions, triangles, `divisions` and
            `minimum`.

    Returns:
        `points` and `triangles`, or `{"empty": true}` when none remain.

    Raises:
        Error: If the JSON is not that mesh, or an index is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("weld request is not an object")
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    json_vec3(doc, doc.at(root, "positions"), px, py, pz)
    if len(px) == 0:
        raise Error("positions are empty")
    var faces = json_triangles(doc, doc.at(root, "triangles"), len(px))
    var divisions = json_number(doc, doc.at(root, "divisions"))
    var minimum = json_number(doc, doc.at(root, "minimum"))
    var low_x = px[0]
    var low_y = py[0]
    var low_z = pz[0]
    var high_x = px[0]
    var high_y = py[0]
    var high_z = pz[0]
    for index in range(len(px)):
        if px[index] < low_x:
            low_x = px[index]
        if py[index] < low_y:
            low_y = py[index]
        if pz[index] < low_z:
            low_z = pz[index]
        if px[index] > high_x:
            high_x = px[index]
        if py[index] > high_y:
            high_y = py[index]
        if pz[index] > high_z:
            high_z = pz[index]
    var size = sqrt(
        _fadd(
            _fadd(
                _fmul(_fsub(high_x, low_x), _fsub(high_x, low_x)),
                _fmul(_fsub(high_y, low_y), _fsub(high_y, low_y)),
            ),
            _fmul(_fsub(high_z, low_z), _fsub(high_z, low_z)),
        )
    )
    var cell = _fdiv(size, divisions)
    if cell < minimum:
        cell = minimum
    var cx = List[Int]()
    var cy = List[Int]()
    var cz = List[Int]()
    for index in range(len(px)):
        cx.append(_cell(_fdiv(px[index], cell)))
        cy.append(_cell(_fdiv(py[index], cell)))
        cz.append(_cell(_fdiv(pz[index], cell)))
    var order = List[Int]()
    for index in range(len(px)):
        order.append(index)
    _sort_vertices(order, cx, cy, cz)
    var inverse = List[Int](length=len(px), fill=0)
    var unique = 0
    var previous = order[0]
    for index in range(1, len(order)):
        var vertex = order[index]
        if (
            cx[vertex] != cx[previous]
            or cy[vertex] != cy[previous]
            or cz[vertex] != cz[previous]
        ):
            unique += 1
            previous = vertex
        inverse[vertex] = unique
    unique += 1
    var sx = List[Float64](length=unique, fill=0.0)
    var sy = List[Float64](length=unique, fill=0.0)
    var sz = List[Float64](length=unique, fill=0.0)
    var counts = List[Int](length=unique, fill=0)
    for index in range(len(px)):
        var id = inverse[index]
        sx[id] = _fadd(sx[id], px[index])
        sy[id] = _fadd(sy[id], py[index])
        sz[id] = _fadd(sz[id], pz[index])
        counts[id] += 1
    for index in range(unique):
        var count = Float64(counts[index])
        sx[index] = _fdiv(sx[index], count)
        sy[index] = _fdiv(sy[index], count)
        sz[index] = _fdiv(sz[index], count)
    var kept = List[Int]()
    var face_count = len(faces) // 3
    for face in range(face_count):
        var base = face * 3
        var a = inverse[faces[base]]
        var b = inverse[faces[base + 1]]
        var c = inverse[faces[base + 2]]
        if a != b and b != c and a != c:
            kept.append(a)
            kept.append(b)
            kept.append(c)
    var remain = len(kept) // 3
    if remain == 0:
        return '{"empty": true}'
    var kx = List[Int]()
    var ky = List[Int]()
    var kz = List[Int]()
    for face in range(remain):
        var base = face * 3
        var a = kept[base]
        var b = kept[base + 1]
        var c = kept[base + 2]
        if a > b:
            var swap = a
            a = b
            b = swap
        if b > c:
            var swap = b
            b = c
            c = swap
        if a > b:
            var swap = a
            a = b
            b = swap
        kx.append(a)
        ky.append(b)
        kz.append(c)
    var tri_order = List[Int]()
    for face in range(remain):
        tri_order.append(face)
    _sort_triangles(tri_order, kx, ky, kz)
    var chosen = List[Int]()
    var first = tri_order[0]
    chosen.append(first)
    for index in range(1, len(tri_order)):
        var face = tri_order[index]
        if (
            kx[face] != kx[first]
            or ky[face] != ky[first]
            or kz[face] != kz[first]
        ):
            chosen.append(face)
            first = face
    _sort_ints(chosen)
    var out = String('{"points":[')
    for index in range(unique):
        if index > 0:
            out += ","
        out += "["
        out += python_repr(sx[index])
        out += ","
        out += python_repr(sy[index])
        out += ","
        out += python_repr(sz[index])
        out += "]"
    out += '],"triangles":['
    for index in range(len(chosen)):
        if index > 0:
            out += ","
        var base = chosen[index] * 3
        out += "["
        out += String(kept[base])
        out += ","
        out += String(kept[base + 1])
        out += ","
        out += String(kept[base + 2])
        out += "]"
    out += "]}"
    return out^


def _cell(value: Float64) -> Int:
    """Return the floor of one coordinate as an integer."""
    return Int(floor(value))


def _sort_vertices(
    mut order: List[Int], cx: List[Int], cy: List[Int], cz: List[Int]
):
    """Sort vertex indices by cell, keeping equals in their old order."""
    var aux = List[Int](length=len(order), fill=0)
    _merge_vertices(order, aux, 0, len(order), cx, cy, cz)


def _merge_vertices(
    mut order: List[Int],
    mut aux: List[Int],
    start: Int,
    end: Int,
    cx: List[Int],
    cy: List[Int],
    cz: List[Int],
):
    """Sort `order[start:end]` by cell."""
    if end - start <= 1:
        return
    var mid = (start + end) // 2
    _merge_vertices(order, aux, start, mid, cx, cy, cz)
    _merge_vertices(order, aux, mid, end, cx, cy, cz)
    var left = start
    var right = mid
    var write = start
    while left < mid and right < end:
        if _vertex_before(order[right], order[left], cx, cy, cz):
            aux[write] = order[right]
            right += 1
        else:
            aux[write] = order[left]
            left += 1
        write += 1
    while left < mid:
        aux[write] = order[left]
        left += 1
        write += 1
    while right < end:
        aux[write] = order[right]
        right += 1
        write += 1
    for index in range(start, end):
        order[index] = aux[index]


def _vertex_before(
    right: Int, left: Int, cx: List[Int], cy: List[Int], cz: List[Int]
) -> Bool:
    """Return whether `right`'s cell sorts before `left`'s cell."""
    if cx[right] != cx[left]:
        return cx[right] < cx[left]
    if cy[right] != cy[left]:
        return cy[right] < cy[left]
    return cz[right] < cz[left]


def _sort_triangles(
    mut order: List[Int], kx: List[Int], ky: List[Int], kz: List[Int]
):
    """Sort triangle indices by their sorted corners."""
    var aux = List[Int](length=len(order), fill=0)
    _merge_triangles(order, aux, 0, len(order), kx, ky, kz)


def _merge_triangles(
    mut order: List[Int],
    mut aux: List[Int],
    start: Int,
    end: Int,
    kx: List[Int],
    ky: List[Int],
    kz: List[Int],
):
    """Sort `order[start:end]` by sorted corners."""
    if end - start <= 1:
        return
    var mid = (start + end) // 2
    _merge_triangles(order, aux, start, mid, kx, ky, kz)
    _merge_triangles(order, aux, mid, end, kx, ky, kz)
    var left = start
    var right = mid
    var write = start
    while left < mid and right < end:
        if _triangle_before(order[right], order[left], kx, ky, kz):
            aux[write] = order[right]
            right += 1
        else:
            aux[write] = order[left]
            left += 1
        write += 1
    while left < mid:
        aux[write] = order[left]
        left += 1
        write += 1
    while right < end:
        aux[write] = order[right]
        right += 1
        write += 1
    for index in range(start, end):
        order[index] = aux[index]


def _triangle_before(
    right: Int, left: Int, kx: List[Int], ky: List[Int], kz: List[Int]
) -> Bool:
    """Return whether `right` sorts before `left`."""
    if kx[right] != kx[left]:
        return kx[right] < kx[left]
    if ky[right] != ky[left]:
        return ky[right] < ky[left]
    return kz[right] < kz[left]


def _sort_ints(mut values: List[Int]):
    """Sort integers into ascending order."""
    for index in range(1, len(values)):
        var key = values[index]
        var slot = index
        while slot > 0 and key < values[slot - 1]:
            values[slot] = values[slot - 1]
            slot -= 1
        values[slot] = key


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
    """Print the welded mesh for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_weld FILE", file=stderr)
        exit(2)
    try:
        print(weld_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_weld:", error, file=stderr)
        exit(1)
