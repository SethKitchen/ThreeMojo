# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Lay out one far building's picture and its texture coordinates.

    carla_town_atlas FILE

`FILE` is JSON. `mode` is `flat`, `spans` or `pack`. `flat` gives each
triangle its own corners and one area normal. `spans` sizes the five
views. `pack` joins those views and assigns each far triangle the view
that faces it.
"""

from std.math import ceil, sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import (
    append_ascii,
    ascii_text,
    cached_repr,
    parse_float,
    python_repr,
)
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson


def atlas_text(text: String) raises -> String:
    """Return one far-building atlas step as JSON.

    Args:
        text: A JSON object. `mode` selects the step.

    Returns:
        The flat mesh, the view sizes, or the joined picture and its
        texture coordinates.

    Raises:
        Error: If the JSON is not that step, or an index is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("atlas request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode == "flat":
        return _flat(doc, root)
    if mode == "spans":
        return _spans(doc, root)
    if mode == "pack":
        return _pack(doc, root)
    raise Error("mode is not flat, spans or pack")


def _flat(doc: PyJson, root: Int) raises -> String:
    """Return unindexed corners and repeated area normals."""
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    _vec3(doc, doc.at(root, "positions"), px, py, pz)
    var faces = _triangles(doc, doc.at(root, "triangles"), len(px))
    var ox = List[Float64]()
    var oy = List[Float64]()
    var oz = List[Float64]()
    var nx = List[Float64]()
    var ny = List[Float64]()
    var nz = List[Float64]()
    var triangles = List[Int]()
    var face_count = len(faces) // 3
    for face in range(face_count):
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
        var ex1 = _fsub(x1, x0)
        var ey1 = _fsub(y1, y0)
        var ez1 = _fsub(z1, z0)
        var ex2 = _fsub(x2, x0)
        var ey2 = _fsub(y2, y0)
        var ez2 = _fsub(z2, z0)
        var cx = _fsub(_fmul(ey1, ez2), _fmul(ez1, ey2))
        var cy = _fsub(_fmul(ez1, ex2), _fmul(ex1, ez2))
        var cz = _fsub(_fmul(ex1, ey2), _fmul(ey1, ex2))
        var length = _length(cx, cy, cz)
        if length < 1e-12:
            length = 1e-12
        cx = _fdiv(cx, length)
        cy = _fdiv(cy, length)
        cz = _fdiv(cz, length)
        var origin = len(ox)
        ox.append(x0)
        oy.append(y0)
        oz.append(z0)
        ox.append(x1)
        oy.append(y1)
        oz.append(z1)
        ox.append(x2)
        oy.append(y2)
        oz.append(z2)
        for _corner in range(3):
            nx.append(cx)
            ny.append(cy)
            nz.append(cz)
        triangles.append(origin)
        triangles.append(origin + 1)
        triangles.append(origin + 2)
    var out = String('{"positions":')
    out += _points(ox, oy, oz)
    out += ',"normals":'
    out += _points(nx, ny, nz)
    out += ',"triangles":'
    out += _indices(triangles)
    out += "}"
    return out^


def _spans(doc: PyJson, root: Int) raises -> String:
    """Return each view's extent and its texel counts."""
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    _vec3(doc, doc.at(root, "positions"), px, py, pz)
    if len(px) == 0:
        raise Error("positions are empty")
    var density = _number(doc, doc.at(root, "density"))
    var most = _number(doc, doc.at(root, "most"))
    var views = doc.at(root, "views")
    if doc.kind(views) != PY_LIST:
        raise Error("views are not a list")
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
    var out = String("[")
    for view_index in range(doc.length(views)):
        var view = doc.item(views, view_index)
        var right = List[Float64]()
        var up = List[Float64]()
        _vec3_one(doc, doc.at(view, "right"), right)
        _vec3_one(doc, doc.at(view, "up"), up)
        var low_r = 0.0
        var high_r = 0.0
        var low_u = 0.0
        var high_u = 0.0
        _extent(
            low_x,
            low_y,
            low_z,
            high_x,
            high_y,
            high_z,
            right,
            low_r,
            high_r,
        )
        _extent(low_x, low_y, low_z, high_x, high_y, high_z, up, low_u, high_u)
        var width = _fsub(high_r, low_r)
        var height = _fsub(high_u, low_u)
        var reach = width
        if height > reach:
            reach = height
        if reach < 1e-6:
            reach = 1e-6
        var limit = _fdiv(most, reach)
        var used = density
        if limit < used:
            used = limit
        if view_index > 0:
            out += ", "
        out += '{"columns":'
        out += String(_pixels(_fmul(width, used)))
        out += ',"rows":'
        out += String(_pixels(_fmul(height, used)))
        out += ',"low_r":'
        out += python_repr(low_r)
        out += ',"high_r":'
        out += python_repr(high_r)
        out += ',"low_u":'
        out += python_repr(low_u)
        out += ',"high_u":'
        out += python_repr(high_u)
        out += ',"width":'
        out += python_repr(width)
        out += ',"height":'
        out += python_repr(height)
        out += "}"
    out += "]"
    return out^


def _pack(doc: PyJson, root: Int) raises -> String:
    """Join the views and return texture coordinates for the far mesh."""
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    var nx = List[Float64]()
    var ny = List[Float64]()
    var nz = List[Float64]()
    _vec3(doc, doc.at(root, "positions"), px, py, pz)
    _vec3(doc, doc.at(root, "normals"), nx, ny, nz)
    if len(px) != len(nx):
        raise Error("normals do not match positions")
    if len(px) % 3 != 0:
        raise Error("positions are not whole triangles")
    var views = doc.at(root, "views")
    if doc.kind(views) != PY_LIST or doc.length(views) == 0:
        raise Error("views are not a list")
    var fx = List[Float64]()
    var fy = List[Float64]()
    var fz = List[Float64]()
    var rx = List[Float64]()
    var ry = List[Float64]()
    var rz = List[Float64]()
    var ux = List[Float64]()
    var uy = List[Float64]()
    var uz = List[Float64]()
    var low_r = List[Float64]()
    var high_r = List[Float64]()
    var low_u = List[Float64]()
    var high_u = List[Float64]()
    var image_w = List[Int]()
    var image_h = List[Int]()
    var image_at = List[Int]()
    var rgb = List[Float64]()
    for view_index in range(doc.length(views)):
        var view = doc.item(views, view_index)
        var forward = List[Float64]()
        var right = List[Float64]()
        var up = List[Float64]()
        _vec3_one(doc, doc.at(view, "forward"), forward)
        _vec3_one(doc, doc.at(view, "right"), right)
        _vec3_one(doc, doc.at(view, "up"), up)
        fx.append(forward[0])
        fy.append(forward[1])
        fz.append(forward[2])
        rx.append(right[0])
        ry.append(right[1])
        rz.append(right[2])
        ux.append(up[0])
        uy.append(up[1])
        uz.append(up[2])
        var span_r = _pair(doc, doc.at(view, "span_r"))
        var span_u = _pair(doc, doc.at(view, "span_u"))
        low_r.append(span_r[0])
        high_r.append(span_r[1])
        low_u.append(span_u[0])
        high_u.append(span_u[1])
        var width = 0
        var height = 0
        image_at.append(len(rgb) // 3)
        _rgb(doc, doc.at(view, "image"), width, height, rgb)
        image_w.append(width)
        image_h.append(height)
    var view_count = len(image_w)
    var atlas_w = 0
    var atlas_h = 0
    for view_index in range(view_count):
        atlas_w += image_w[view_index]
        if image_h[view_index] > atlas_h:
            atlas_h = image_h[view_index]
    var red = List[Float64](length=atlas_h * atlas_w, fill=0.0)
    var green = List[Float64](length=atlas_h * atlas_w, fill=0.0)
    var blue = List[Float64](length=atlas_h * atlas_w, fill=0.0)
    var offsets = List[Int]()
    var column = 0
    for view_index in range(view_count):
        offsets.append(column)
        var width = image_w[view_index]
        var height = image_h[view_index]
        var source = image_at[view_index]
        for row in range(height):
            for col in range(width):
                var texel = source + row * width + col
                var dest = row * atlas_w + column + col
                red[dest] = rgb[texel * 3]
                green[dest] = rgb[texel * 3 + 1]
                blue[dest] = rgb[texel * 3 + 2]
        column += width
    var us = List[Float64]()
    var vs = List[Float64]()
    var face_count = len(px) // 3
    for face in range(face_count):
        var normal_at = face * 3
        var best = 0
        var best_dot = _dot_axis(
            nx[normal_at],
            ny[normal_at],
            nz[normal_at],
            fx[0],
            fy[0],
            fz[0],
        )
        for view_index in range(1, view_count):
            var dotted = _dot_axis(
                nx[normal_at],
                ny[normal_at],
                nz[normal_at],
                fx[view_index],
                fy[view_index],
                fz[view_index],
            )
            if dotted > best_dot:
                best = view_index
                best_dot = dotted
        var span = _fsub(high_r[best], low_r[best])
        if span < 1e-6:
            span = 1e-6
        var rise = _fsub(high_u[best], low_u[best])
        if rise < 1e-6:
            rise = 1e-6
        for corner in range(3):
            var vertex = normal_at + corner
            var across = _fdiv(
                _fsub(
                    _dot_axis(
                        px[vertex],
                        py[vertex],
                        pz[vertex],
                        rx[best],
                        ry[best],
                        rz[best],
                    ),
                    low_r[best],
                ),
                span,
            )
            var above = _fdiv(
                _fsub(
                    high_u[best],
                    _dot_axis(
                        px[vertex],
                        py[vertex],
                        pz[vertex],
                        ux[best],
                        uy[best],
                        uz[best],
                    ),
                ),
                rise,
            )
            us.append(
                _fdiv(
                    _fadd(
                        Float64(offsets[best]),
                        _fmul(_clip01(across), Float64(image_w[best])),
                    ),
                    Float64(atlas_w),
                )
            )
            vs.append(
                _fdiv(
                    _fmul(_clip01(above), Float64(image_h[best])),
                    Float64(atlas_h),
                )
            )
    var out = String('{"atlas":')
    out += _atlas(red, green, blue, atlas_w, atlas_h)
    out += ',"uvs":'
    out += _pairs(us, vs)
    out += "}"
    return out^


def _extent(
    low_x: Float64,
    low_y: Float64,
    low_z: Float64,
    high_x: Float64,
    high_y: Float64,
    high_z: Float64,
    axis: List[Float64],
    mut low: Float64,
    mut high: Float64,
):
    """Set `low` and `high` to the box's extent along `axis`."""
    var first = True
    for x_index in range(2):
        var x = low_x
        if x_index == 1:
            x = high_x
        for y_index in range(2):
            var y = low_y
            if y_index == 1:
                y = high_y
            for z_index in range(2):
                var z = low_z
                if z_index == 1:
                    z = high_z
                var dotted = _dot_axis(x, y, z, axis[0], axis[1], axis[2])
                if first or dotted < low:
                    low = dotted
                if first or dotted > high:
                    high = dotted
                first = False


def _pixels(value: Float64) -> Int:
    """Return at least four texels, the ceiling of `value`."""
    var count = 4
    if value > 0.0:
        var up = ceil(value)
        if up > 4.0:
            count = Int(up)
    return count


def _clip01(value: Float64) -> Float64:
    """Return `value` clamped to 0 and 1."""
    if value < 0.0:
        return 0.0
    if value > 1.0:
        return 1.0
    return value


def _length(x: Float64, y: Float64, z: Float64) -> Float64:
    """Return the length of one vector."""
    return sqrt(_fadd(_fadd(_fmul(x, x), _fmul(y, y)), _fmul(z, z)))


def _dot_axis(
    x: Float64,
    y: Float64,
    z: Float64,
    ax: Float64,
    ay: Float64,
    az: Float64,
) -> Float64:
    """Return a dot product, each product rounded first."""
    return _fadd(_fadd(_fmul(x, ax), _fmul(y, ay)), _fmul(z, az))


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


def _points(
    xs: List[Float64], ys: List[Float64], zs: List[Float64]
) raises -> String:
    """Return points as a JSON array."""
    var out = String("[")
    for index in range(len(xs)):
        if index > 0:
            out += ", "
        out += "["
        out += python_repr(xs[index])
        out += ", "
        out += python_repr(ys[index])
        out += ", "
        out += python_repr(zs[index])
        out += "]"
    out += "]"
    return out^


def _pairs(xs: List[Float64], ys: List[Float64]) raises -> String:
    """Return pairs as a JSON array."""
    var out = String("[")
    for index in range(len(xs)):
        if index > 0:
            out += ", "
        out += "["
        out += python_repr(xs[index])
        out += ", "
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
            out += ", "
        out += "["
        out += String(values[index * 3])
        out += ", "
        out += String(values[index * 3 + 1])
        out += ", "
        out += String(values[index * 3 + 2])
        out += "]"
    out += "]"
    return out^


def _atlas(
    red: List[Float64],
    green: List[Float64],
    blue: List[Float64],
    width: Int,
    height: Int,
) raises -> String:
    """Return an RGB picture as JSON rows."""
    var out = List[UInt8]()
    var cache = Dict[UInt64, String]()
    append_ascii(out, "[")
    for row in range(height):
        if row > 0:
            append_ascii(out, ", ")
        append_ascii(out, "[")
        for col in range(width):
            if col > 0:
                append_ascii(out, ", ")
            var cell = row * width + col
            append_ascii(out, "[")
            append_ascii(out, cached_repr(red[cell], cache))
            append_ascii(out, ", ")
            append_ascii(out, cached_repr(green[cell], cache))
            append_ascii(out, ", ")
            append_ascii(out, cached_repr(blue[cell], cache))
            append_ascii(out, "]")
        append_ascii(out, "]")
    append_ascii(out, "]")
    return ascii_text(out)


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


def _vec3_one(doc: PyJson, node: Int, mut out: List[Float64]) raises:
    """Read one 3-vector."""
    if doc.kind(node) != PY_LIST or doc.length(node) != 3:
        raise Error("vector is not 3 numbers")
    out.append(_number(doc, doc.item(node, 0)))
    out.append(_number(doc, doc.item(node, 1)))
    out.append(_number(doc, doc.item(node, 2)))


def _pair(doc: PyJson, node: Int) raises -> List[Float64]:
    """Read two numbers."""
    if doc.kind(node) != PY_LIST or doc.length(node) != 2:
        raise Error("span is not 2 numbers")
    var out = List[Float64]()
    out.append(_number(doc, doc.item(node, 0)))
    out.append(_number(doc, doc.item(node, 1)))
    return out^


def _rgb(
    doc: PyJson,
    node: Int,
    mut width: Int,
    mut height: Int,
    mut rgb: List[Float64],
) raises:
    """Read an RGB picture into `rgb` and set its size."""
    if doc.kind(node) != PY_LIST:
        raise Error("image is not a list")
    height = doc.length(node)
    width = 0
    for row in range(height):
        var line = doc.item(node, row)
        if doc.kind(line) != PY_LIST:
            raise Error("image row is not a list")
        if row == 0:
            width = doc.length(line)
        elif doc.length(line) != width:
            raise Error("image rows differ")
        for column in range(width):
            var pixel = doc.item(line, column)
            if doc.kind(pixel) != PY_LIST or doc.length(pixel) != 3:
                raise Error("pixel is not 3 numbers")
            for channel in range(3):
                rgb.append(_number(doc, doc.item(pixel, channel)))


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
    """Print one atlas step for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_atlas FILE", file=stderr)
        exit(2)
    try:
        print(atlas_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_atlas:", error, file=stderr)
        exit(1)
