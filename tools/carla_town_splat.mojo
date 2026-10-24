# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Draw one orthographic view of a town mesh.

    carla_town_splat FILE

`FILE` is JSON. `mode` is `axis` for a tree impostor or `ortho` for a
baked building. The program prints RGBA texels. A covered texel has
alpha 1. The nearest sample along the view wins. `span_u` and `span_v`
set the scale as `columns / max(span_u, 1e-6)` and
`rows / max(span_v, 1e-6)` when `scale_u` is absent.
"""

from std.math import ceil, floor, sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson
from tools.carla_town_cards import numpy_random


def splat_text(text: String) raises -> String:
    """Return one view as JSON rows of RGBA texels.

    Args:
        text: A JSON object with the view and its mesh parts.

    Returns:
        A JSON array of rows. Each texel is red, green, blue and alpha.

    Raises:
        Error: If the JSON is not that view, or an index is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("splat request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode != "axis" and mode != "ortho":
        raise Error("mode is not axis or ortho")
    var columns = _whole(doc, doc.at(root, "columns"))
    var image_rows = _whole(doc, doc.at(root, "rows"))
    var samples = _whole(doc, doc.at(root, "samples"))
    var cap = _whole(doc, doc.at(root, "cap"))
    var seed = _whole(doc, doc.at(root, "seed"))
    var fill = False
    var named_fill = doc.get(root, "fill")
    if named_fill != -1:
        fill = doc.flag(named_fill)
    var lit = doc.get(root, "light") != -1
    var light = List[Float64]()
    if lit:
        _vec3_one(doc, doc.at(root, "light"), light)
    var ortho = mode == "ortho"
    var across = 0
    var left = 0.0
    var top = 0.0
    var scale_u: Float64
    var scale_v: Float64
    var right = List[Float64]()
    var up = List[Float64]()
    var forward = List[Float64]()
    var low_r = 0.0
    var low_u = 0.0
    var height = 0.0
    if ortho:
        _vec3_one(doc, doc.at(root, "right"), right)
        _vec3_one(doc, doc.at(root, "up"), up)
        _vec3_one(doc, doc.at(root, "forward"), forward)
        low_r = _number(doc, doc.at(root, "low_r"))
        low_u = _number(doc, doc.at(root, "low_u"))
        height = _number(doc, doc.at(root, "height"))
    else:
        across = _whole(doc, doc.at(root, "across"))
        left = _number(doc, doc.at(root, "left"))
        top = _number(doc, doc.at(root, "top"))
    var named_scale = doc.get(root, "scale_u")
    if named_scale == -1:
        scale_u = _view_scale(columns, _number(doc, doc.at(root, "span_u")))
        scale_v = _view_scale(image_rows, _number(doc, doc.at(root, "span_v")))
    else:
        scale_u = _number(doc, named_scale)
        scale_v = _number(doc, doc.at(root, "scale_v"))
    var depth_axis = 0
    if across == 0:
        depth_axis = 2
    var sx = List[Float64]()
    var sy = List[Float64]()
    var sz = List[Float64]()
    var sr = List[Float64]()
    var sg = List[Float64]()
    var sb = List[Float64]()
    var parts = doc.at(root, "parts")
    if doc.kind(parts) != PY_LIST:
        raise Error("parts is not a list")
    var part_count = doc.length(parts)
    var totals = List[Int]()
    var draws = 0
    for part_index in range(part_count):
        var samples_here = _sample_count(
            doc,
            doc.item(parts, part_index),
            samples,
            cap,
            ortho,
            across,
            depth_axis,
            left,
            top,
            scale_u,
            scale_v,
            right,
            up,
            forward,
            low_r,
            low_u,
            height,
        )
        totals.append(samples_here)
        draws += samples_here * 2
    var draw = numpy_random(seed, draws)
    var cursor = 0
    for part_index in range(part_count):
        _part(
            doc,
            doc.item(parts, part_index),
            draw,
            cursor,
            totals[part_index],
            samples,
            cap,
            lit,
            light,
            ortho,
            across,
            depth_axis,
            left,
            top,
            scale_u,
            scale_v,
            right,
            up,
            forward,
            low_r,
            low_u,
            height,
            sx,
            sy,
            sz,
            sr,
            sg,
            sb,
        )
        cursor += totals[part_index] * 2
    return _paint(sx, sy, sz, sr, sg, sb, columns, image_rows, fill)


def _sample_count(
    doc: PyJson,
    node: Int,
    samples: Int,
    cap: Int,
    ortho: Bool,
    across: Int,
    depth_axis: Int,
    left: Float64,
    top: Float64,
    scale_u: Float64,
    scale_v: Float64,
    right: List[Float64],
    up: List[Float64],
    forward: List[Float64],
    low_r: Float64,
    low_u: Float64,
    height: Float64,
) raises -> Int:
    """Return how many samples one part draws, before the mask."""
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    _vec3(doc, doc.at(node, "positions"), px, py, pz)
    var faces = _triangles(doc, doc.at(node, "triangles"), len(px))
    var total = 0
    var face_count = len(faces) // 3
    for face in range(face_count):
        var base = face * 3
        var first = _corner(
            px,
            py,
            pz,
            faces[base],
            ortho,
            across,
            depth_axis,
            left,
            top,
            scale_u,
            scale_v,
            right,
            up,
            forward,
            low_r,
            low_u,
            height,
        )
        var second = _corner(
            px,
            py,
            pz,
            faces[base + 1],
            ortho,
            across,
            depth_axis,
            left,
            top,
            scale_u,
            scale_v,
            right,
            up,
            forward,
            low_r,
            low_u,
            height,
        )
        var third = _corner(
            px,
            py,
            pz,
            faces[base + 2],
            ortho,
            across,
            depth_axis,
            left,
            top,
            scale_u,
            scale_v,
            right,
            up,
            forward,
            low_r,
            low_u,
            height,
        )
        total += _quota(
            first[0],
            first[1],
            second[0],
            second[1],
            third[0],
            third[1],
            samples,
            cap,
        )
    return total


def _part(
    doc: PyJson,
    node: Int,
    draw: List[Float64],
    draw_at: Int,
    part_total: Int,
    samples: Int,
    cap: Int,
    lit: Bool,
    light: List[Float64],
    ortho: Bool,
    across: Int,
    depth_axis: Int,
    left: Float64,
    top: Float64,
    scale_u: Float64,
    scale_v: Float64,
    right: List[Float64],
    up: List[Float64],
    forward: List[Float64],
    low_r: Float64,
    low_u: Float64,
    height: Float64,
    mut sx: List[Float64],
    mut sy: List[Float64],
    mut sz: List[Float64],
    mut sr: List[Float64],
    mut sg: List[Float64],
    mut sb: List[Float64],
) raises:
    """Sample one mesh part into the view."""
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    var nx = List[Float64]()
    var ny = List[Float64]()
    var nz = List[Float64]()
    var us = List[Float64]()
    var vs = List[Float64]()
    _vec3(doc, doc.at(node, "positions"), px, py, pz)
    _vec3(doc, doc.at(node, "normals"), nx, ny, nz)
    _vec2(doc, doc.at(node, "uvs"), us, vs)
    var faces = _triangles(doc, doc.at(node, "triangles"), len(px))
    var factor = List[Float64]()
    _vec4(doc, doc.at(node, "factor"), factor)
    var cut = _number(doc, doc.at(node, "cut"))
    var masked = doc.flag(doc.at(node, "masked"))
    var image = doc.get(node, "image")
    var has_image = image != -1 and not doc.is_none(image)
    var width = 1
    var image_rows = 1
    var rgba = List[Float64]()
    if has_image:
        width = _whole(doc, doc.at(image, "width"))
        image_rows = _whole(doc, doc.at(image, "height"))
        _flat(doc, doc.at(image, "rgba"), rgba)
    var face_count = len(faces) // 3
    var corner_u = List[Float64]()
    var corner_v = List[Float64]()
    var corner_d = List[Float64]()
    var corner_s = List[Float64]()
    var corner_t = List[Float64]()
    var corner_nx = List[Float64]()
    var corner_ny = List[Float64]()
    var corner_nz = List[Float64]()
    var counts = List[Int]()
    var total = 0
    for face in range(face_count):
        var base = face * 3
        for corner in range(3):
            var vertex = faces[base + corner]
            var placed = _corner(
                px,
                py,
                pz,
                vertex,
                ortho,
                across,
                depth_axis,
                left,
                top,
                scale_u,
                scale_v,
                right,
                up,
                forward,
                low_r,
                low_u,
                height,
            )
            corner_u.append(placed[0])
            corner_v.append(placed[1])
            corner_d.append(placed[2])
            corner_s.append(us[vertex])
            corner_t.append(vs[vertex])
            corner_nx.append(nx[vertex])
            corner_ny.append(ny[vertex])
            corner_nz.append(nz[vertex])
        var count = _quota(
            corner_u[len(corner_u) - 3],
            corner_v[len(corner_v) - 3],
            corner_u[len(corner_u) - 2],
            corner_v[len(corner_v) - 2],
            corner_u[len(corner_u) - 1],
            corner_v[len(corner_v) - 1],
            samples,
            cap,
        )
        counts.append(count)
        total += count
    if total == 0:
        return
    var cursor = 0
    # NumPy fills every `a` for this part, then every `b`.
    for face in range(face_count):
        var count = counts[face]
        var base = face * 3
        for _sample in range(count):
            var a = draw[draw_at + cursor]
            var b = draw[draw_at + part_total + cursor]
            cursor += 1
            if _fadd(a, b) > 1.0:
                a = _fsub(1.0, a)
                b = _fsub(1.0, b)
            var w0 = _fsub(_fsub(1.0, a), b)
            var depth = _mix(
                w0,
                a,
                b,
                corner_d[base],
                corner_d[base + 1],
                corner_d[base + 2],
            )
            var s = _mix(
                w0, a, b, corner_s[base], corner_s[base + 1], corner_s[base + 2]
            )
            var t = _mix(
                w0, a, b, corner_t[base], corner_t[base + 1], corner_t[base + 2]
            )
            var red = factor[0]
            var green = factor[1]
            var blue = factor[2]
            var alpha = factor[3]
            if has_image:
                var ix = _trunc(_fmul(_mod1(s), Float64(width - 1)))
                var iy = _trunc(_fmul(_mod1(t), Float64(image_rows - 1)))
                if ix < 0:
                    ix = 0
                if iy < 0:
                    iy = 0
                if ix >= width:
                    ix = width - 1
                if iy >= image_rows:
                    iy = image_rows - 1
                var texel = (iy * width + ix) * 4
                red = _fmul(rgba[texel], factor[0])
                green = _fmul(rgba[texel + 1], factor[1])
                blue = _fmul(rgba[texel + 2], factor[2])
                alpha = _fmul(rgba[texel + 3], factor[3])
            if masked and alpha < cut:
                continue
            if lit:
                var nnx = _mix(
                    w0,
                    a,
                    b,
                    corner_nx[base],
                    corner_nx[base + 1],
                    corner_nx[base + 2],
                )
                var nny = _mix(
                    w0,
                    a,
                    b,
                    corner_ny[base],
                    corner_ny[base + 1],
                    corner_ny[base + 2],
                )
                var nnz = _mix(
                    w0,
                    a,
                    b,
                    corner_nz[base],
                    corner_nz[base + 1],
                    corner_nz[base + 2],
                )
                var length = sqrt(
                    _fadd(
                        _fadd(_fmul(nnx, nnx), _fmul(nny, nny)), _fmul(nnz, nnz)
                    )
                )
                if length < 1e-9:
                    length = 1e-9
                nnx = _fdiv(nnx, length)
                nny = _fdiv(nny, length)
                nnz = _fdiv(nnz, length)
                var gain = _fadd(
                    0.45, _fmul(0.55, _abs(_dot3(nnx, nny, nnz, light)))
                )
                red = _fmul(red, gain)
                green = _fmul(green, gain)
                blue = _fmul(blue, gain)
            var x = _trunc(
                _mix(
                    w0,
                    a,
                    b,
                    corner_u[base],
                    corner_u[base + 1],
                    corner_u[base + 2],
                )
            )
            var y = _trunc(
                _mix(
                    w0,
                    a,
                    b,
                    corner_v[base],
                    corner_v[base + 1],
                    corner_v[base + 2],
                )
            )
            sx.append(Float64(x))
            sy.append(Float64(y))
            sz.append(depth)
            sr.append(red)
            sg.append(green)
            sb.append(blue)


def _paint(
    sx: List[Float64],
    sy: List[Float64],
    sz: List[Float64],
    sr: List[Float64],
    sg: List[Float64],
    sb: List[Float64],
    columns: Int,
    image_rows: Int,
    fill: Bool,
) raises -> String:
    """Keep the nearest sample in each texel and print the picture."""
    var xs = List[Int]()
    var ys = List[Int]()
    var zs = List[Float64]()
    var rs = List[Float64]()
    var gs = List[Float64]()
    var bs = List[Float64]()
    var texel = List[Int]()
    for index in range(len(sx)):
        var x = Int(sx[index])
        var y = Int(sy[index])
        if x >= 0 and x < columns and y >= 0 and y < image_rows:
            xs.append(x)
            ys.append(y)
            zs.append(sz[index])
            rs.append(sr[index])
            gs.append(sg[index])
            bs.append(sb[index])
            texel.append(y * columns + x)
    var order = List[Int]()
    for index in range(len(xs)):
        order.append(index)
    _mergesort(order, zs, texel, False)
    _mergesort(order, zs, texel, True)
    var red = List[Float64](length=image_rows * columns, fill=0.0)
    var green = List[Float64](length=image_rows * columns, fill=0.0)
    var blue = List[Float64](length=image_rows * columns, fill=0.0)
    var alpha = List[Float64](length=image_rows * columns, fill=0.0)
    var previous = -1
    for index in range(len(order)):
        var sample = order[index]
        var cell = texel[sample]
        if cell != previous:
            previous = cell
            red[cell] = rs[sample]
            green[cell] = gs[sample]
            blue[cell] = bs[sample]
            alpha[cell] = 1.0
    if fill:
        _mean_fill(red, green, blue, alpha)
    var out = String("[")
    for row in range(image_rows):
        if row > 0:
            out += ", "
        out += "["
        for col in range(columns):
            if col > 0:
                out += ", "
            var cell = row * columns + col
            out += "["
            out += python_repr(red[cell])
            out += ", "
            out += python_repr(green[cell])
            out += ", "
            out += python_repr(blue[cell])
            out += ", "
            out += python_repr(alpha[cell])
            out += "]"
        out += "]"
    out += "]"
    return out^


def _mean_fill(
    mut red: List[Float64],
    mut green: List[Float64],
    mut blue: List[Float64],
    alpha: List[Float64],
):
    """Give empty texels the mean color of the covered texels."""
    var count = 0.0
    var sum_r = 0.0
    var sum_g = 0.0
    var sum_b = 0.0
    for index in range(len(alpha)):
        if alpha[index] > 0.0:
            sum_r = _fadd(sum_r, red[index])
            sum_g = _fadd(sum_g, green[index])
            sum_b = _fadd(sum_b, blue[index])
            count += 1.0
    if count == 0.0:
        return
    sum_r = _fdiv(sum_r, count)
    sum_g = _fdiv(sum_g, count)
    sum_b = _fdiv(sum_b, count)
    for index in range(len(alpha)):
        if alpha[index] <= 0.0:
            red[index] = sum_r
            green[index] = sum_g
            blue[index] = sum_b


def _mergesort(
    mut order: List[Int], z: List[Float64], texel: List[Int], by_texel: Bool
):
    """Sort stably. Texel is the primary key. Larger depth wins inside it."""
    var aux = List[Int](length=len(order), fill=0)
    _merge_range(order, aux, 0, len(order), z, texel, by_texel)


def _merge_range(
    mut order: List[Int],
    mut aux: List[Int],
    start: Int,
    end: Int,
    z: List[Float64],
    texel: List[Int],
    by_texel: Bool,
):
    """Sort `order[start:end]`."""
    if end - start <= 1:
        return
    var mid = (start + end) // 2
    _merge_range(order, aux, start, mid, z, texel, by_texel)
    _merge_range(order, aux, mid, end, z, texel, by_texel)
    var left = start
    var right = mid
    var write = start
    while left < mid and right < end:
        if _before(order[right], order[left], z, texel, by_texel):
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


def _before(
    right: Int,
    left: Int,
    z: List[Float64],
    texel: List[Int],
    by_texel: Bool,
) -> Bool:
    """Return whether `right` sorts before `left`."""
    if by_texel:
        return texel[right] < texel[left]
    return z[right] > z[left]


def _corner(
    px: List[Float64],
    py: List[Float64],
    pz: List[Float64],
    vertex: Int,
    ortho: Bool,
    across: Int,
    depth_axis: Int,
    left: Float64,
    top: Float64,
    scale_u: Float64,
    scale_v: Float64,
    right: List[Float64],
    up: List[Float64],
    forward: List[Float64],
    low_r: Float64,
    low_u: Float64,
    height: Float64,
) -> Tuple[Float64, Float64, Float64]:
    """Return one corner's screen position and its depth."""
    if ortho:
        var along = _dot3(px[vertex], py[vertex], pz[vertex], right)
        var above = _dot3(px[vertex], py[vertex], pz[vertex], up)
        var u = _fmul(_fsub(along, low_r), scale_u)
        var v = _fmul(_fsub(_fadd(low_u, height), above), scale_v)
        var depth = _dot3(px[vertex], py[vertex], pz[vertex], forward)
        return (u, v, depth)
    var u = _fmul(_fsub(_at(px, py, pz, vertex, across), left), scale_u)
    var v = _fmul(_fsub(top, py[vertex]), scale_v)
    var depth = _at(px, py, pz, vertex, depth_axis)
    return (u, v, depth)


def _quota(
    u0: Float64,
    v0: Float64,
    u1: Float64,
    v1: Float64,
    u2: Float64,
    v2: Float64,
    samples: Int,
    cap: Int,
) -> Int:
    """Return how many samples one triangle draws."""
    var area = _fmul(
        0.5,
        _abs(
            _fsub(
                _fmul(_fsub(u1, u0), _fsub(v2, v0)),
                _fmul(_fsub(u2, u0), _fsub(v1, v0)),
            )
        ),
    )
    var scaled = _fmul(area, Float64(samples))
    var count = cap
    if scaled < Float64(cap):
        count = _ceil_nonneg(scaled)
    if count < 1:
        count = 1
    if count > cap:
        count = cap
    return count


def _mix(
    w0: Float64, a: Float64, b: Float64, x0: Float64, x1: Float64, x2: Float64
) -> Float64:
    """Return one barycentric mix, each product rounded first."""
    return _fadd(_fadd(_fmul(w0, x0), _fmul(a, x1)), _fmul(b, x2))


def _dot3(x: Float64, y: Float64, z: Float64, vector: List[Float64]) -> Float64:
    """Return a dot product, each product rounded first."""
    return _fadd(
        _fadd(_fmul(x, vector[0]), _fmul(y, vector[1])), _fmul(z, vector[2])
    )


def _at(
    px: List[Float64],
    py: List[Float64],
    pz: List[Float64],
    vertex: Int,
    axis: Int,
) -> Float64:
    """Return one position component. Axis 0 is x and axis 2 is z."""
    if axis == 0:
        return px[vertex]
    if axis == 1:
        return py[vertex]
    return pz[vertex]


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


def _view_scale(count: Int, span: Float64) -> Float64:
    """Return `count / max(span, 1e-6)`."""
    var denom = span
    if not (denom > 1e-6):
        denom = 1e-6
    return _fdiv(Float64(count), denom)


def _ceil_nonneg(value: Float64) -> Int:
    """Return the ceiling of a non-negative float."""
    if value <= 0.0:
        return 0
    return Int(ceil(value))


def _trunc(value: Float64) -> Int:
    """Return `value` truncated toward zero."""
    return Int(value)


def _mod1(value: Float64) -> Float64:
    """Return `value` modulo 1, in `[0, 1)`."""
    return _fsub(value, floor(value))


def _abs(value: Float64) -> Float64:
    """Return the absolute value."""
    if value < 0.0:
        return -value
    return value


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


def _vec4(doc: PyJson, node: Int, mut out: List[Float64]) raises:
    """Read one 4-vector."""
    if doc.kind(node) != PY_LIST or doc.length(node) != 4:
        raise Error("factor is not 4 numbers")
    for index in range(4):
        out.append(_number(doc, doc.item(node, index)))


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


def _flat(doc: PyJson, node: Int, mut out: List[Float64]) raises:
    """Read a flat list of numbers."""
    if doc.kind(node) != PY_LIST:
        raise Error("image is not a list")
    for index in range(doc.length(node)):
        out.append(_number(doc, doc.item(node, index)))


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
    """Print the view for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_splat FILE", file=stderr)
        exit(2)
    try:
        print(splat_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_splat:", error, file=stderr)
        exit(1)
