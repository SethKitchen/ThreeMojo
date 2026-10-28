# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Find the heads of a street lamp mesh.

    carla_town_lamps FILE

`FILE` is JSON. It has `mesh` and `primitives`. Each primitive has
`positions` and `triangles`. The program prints the heads in the mesh
frame, or `null` when the mesh is not a lamp. With `heads`, `linear`
and `move`, it places those heads: `heads @ linear.T + move`. With
`heads` and `matrices`, it places the heads for every copy.
"""

from std.math import isinf, isnan
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._python_float import parse_float, python_repr
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)
from tools.carla_town_frame import frame_json


@fieldwise_init
struct _WeldKey(ImplicitlyCopyable):
    """One corner rounded to a millimeter, for welding."""

    var x: Int
    var y: Int
    var z: Int


def heads_text(text: String) raises -> String:
    """Return the lamp heads in a mesh as JSON.

    Args:
        text: A JSON object with `mesh` and `primitives`, or `heads`
            with `linear` and `move`, or `heads` with `matrices`. Each
            primitive has `positions` and `triangles`.

    Returns:
        A JSON array of heads, or `null` when the mesh is not a lamp.
        Glass uses one head for each connected piece. A lamp with no
        glass uses the top of its bounds.

    Raises:
        Error: If the JSON is not that object, a coordinate is not
            finite, a lamp mesh has no corners, or an index is out of
            range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("lamp request is not an object")
    if doc.get(root, "matrices") != MISSING:
        return _placed_copies(doc, root)
    if doc.get(root, "heads") != MISSING:
        return _placed(doc, root)
    var mesh_node = doc.at(root, "mesh")
    if doc.kind(mesh_node) != PY_STR:
        raise Error("mesh is not a string")
    var mesh = doc.text(mesh_node)
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var raw = List[Int]()
    _read_primitives(doc, root, xs, ys, zs, raw)
    if _ends(mesh, "_glass_ext"):
        return _glass(xs, ys, zs, raw)
    if _ends(mesh, "/SM_Lights/SM_StreetLightWall") or _ends(
        mesh, "/Chainbarrier/SM_LightPost"
    ):
        return _top(xs, ys, zs)
    return "null"


def _read_primitives(
    doc: PyJson,
    root: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
    mut raw: List[Int],
) raises:
    """Read positions and triangle indices from the request."""
    var prims = doc.at(root, "primitives")
    if doc.kind(prims) != PY_LIST:
        raise Error("primitives is not a list")
    var prim_count = doc.length(prims)
    for prim_index in range(prim_count):
        var prim = doc.item(prims, prim_index)
        if doc.kind(prim) != PY_DICT:
            raise Error("primitive is not an object")
        var positions = doc.at(prim, "positions")
        var triangles = doc.at(prim, "triangles")
        if doc.kind(positions) != PY_LIST or doc.kind(triangles) != PY_LIST:
            raise Error("primitive arrays are not lists")
        var offset = len(xs)
        var point_count = doc.length(positions)
        for point_index in range(point_count):
            var point = doc.item(positions, point_index)
            if doc.kind(point) != PY_LIST or doc.length(point) != 3:
                raise Error("position is not a 3-vector")
            xs.append(_number(doc, doc.item(point, 0)))
            ys.append(_number(doc, doc.item(point, 1)))
            zs.append(_number(doc, doc.item(point, 2)))
        var triangle_count = doc.length(triangles)
        for triangle_index in range(triangle_count):
            var triangle = doc.item(triangles, triangle_index)
            if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
                raise Error("triangle is not three indices")
            for corner in range(3):
                raw.append(_whole(doc, doc.item(triangle, corner)) + offset)


def _glass(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    raw: List[Int],
) raises -> String:
    """Return one head for each connected piece of glass."""
    var count = len(xs)
    if count == 0:
        raise Error("need at least one array to concatenate")
    var faces = _resolve(raw, count)
    var weld = _weld(xs, ys, zs)
    var corners = 0
    if len(weld) > 0:
        for index in range(len(weld)):
            if weld[index] + 1 > corners:
                corners = weld[index] + 1
    var head = List[Int](length=corners, fill=-1)
    var dest = List[Int]()
    var nxt = List[Int]()
    var face_count = len(faces) // 3
    for index in range(face_count):
        var base = index * 3
        var a = weld[faces[base]]
        var b = weld[faces[base + 1]]
        var c = weld[faces[base + 2]]
        _link(head, dest, nxt, a, b)
        _link(head, dest, nxt, b, c)
    var seen = List[Bool](length=corners, fill=False)
    var label = List[Int](length=corners, fill=0)
    var pieces = 0
    var queue = List[Int]()
    for start in range(corners):
        if seen[start]:
            continue
        var piece = pieces
        pieces += 1
        var read = len(queue)
        queue.append(start)
        seen[start] = True
        label[start] = piece
        while read < len(queue):
            var node = queue[read]
            read += 1
            var edge = head[node]
            while edge >= 0:
                var other = dest[edge]
                if not seen[other]:
                    seen[other] = True
                    label[other] = piece
                    queue.append(other)
                edge = nxt[edge]
    return _centers(xs, ys, zs, label, weld, pieces)


def _top(
    xs: List[Float64], ys: List[Float64], zs: List[Float64]
) raises -> String:
    """Return the head at the top of a lamp that has no glass."""
    var count = len(xs)
    if count == 0:
        raise Error("need at least one array to concatenate")
    var low_x = xs[0]
    var high_x = xs[0]
    var high_y = ys[0]
    var low_z = zs[0]
    var high_z = zs[0]
    for index in range(1, count):
        if xs[index] < low_x:
            low_x = xs[index]
        if xs[index] > high_x:
            high_x = xs[index]
        if ys[index] > high_y:
            high_y = ys[index]
        if zs[index] < low_z:
            low_z = zs[index]
        if zs[index] > high_z:
            high_z = zs[index]
    var values = List[Float64]()
    values.append((low_x + high_x) / 2.0)
    values.append(high_y - parse_float("0.15"))
    values.append((low_z + high_z) / 2.0)
    return _json_heads(values)


def _centers(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    label: List[Int],
    weld: List[Int],
    pieces: Int,
) raises -> String:
    """Return the center of each piece's bounds."""
    var low_x = List[Float64]()
    var low_y = List[Float64]()
    var low_z = List[Float64]()
    var high_x = List[Float64]()
    var high_y = List[Float64]()
    var high_z = List[Float64]()
    var ready = List[Bool]()
    for _ in range(pieces):
        low_x.append(0.0)
        low_y.append(0.0)
        low_z.append(0.0)
        high_x.append(0.0)
        high_y.append(0.0)
        high_z.append(0.0)
        ready.append(False)
    for index in range(len(xs)):
        var piece = label[weld[index]]
        var x = xs[index]
        var y = ys[index]
        var z = zs[index]
        if not ready[piece]:
            ready[piece] = True
            low_x[piece] = x
            high_x[piece] = x
            low_y[piece] = y
            high_y[piece] = y
            low_z[piece] = z
            high_z[piece] = z
        else:
            if x < low_x[piece]:
                low_x[piece] = x
            if x > high_x[piece]:
                high_x[piece] = x
            if y < low_y[piece]:
                low_y[piece] = y
            if y > high_y[piece]:
                high_y[piece] = y
            if z < low_z[piece]:
                low_z[piece] = z
            if z > high_z[piece]:
                high_z[piece] = z
    var values = List[Float64]()
    for piece in range(pieces):
        values.append((low_x[piece] + high_x[piece]) / 2.0)
        values.append((low_y[piece] + high_y[piece]) / 2.0)
        values.append((low_z[piece] + high_z[piece]) / 2.0)
    return _json_heads(values)


def _weld(
    xs: List[Float64], ys: List[Float64], zs: List[Float64]
) raises -> List[Int]:
    """Return each corner's welded id, in sorted millimeter order."""
    var count = len(xs)
    var keys = List[_WeldKey]()
    var order = List[Int]()
    for index in range(count):
        keys.append(
            _WeldKey(
                _key_part(xs[index]), _key_part(ys[index]), _key_part(zs[index])
            )
        )
        order.append(index)
    _sort_order(keys, order)
    var weld = List[Int](length=count, fill=0)
    var unique = 0
    weld[order[0]] = 0
    for index in range(1, count):
        var current = order[index]
        if not _same(keys[order[index - 1]], keys[current]):
            unique += 1
        weld[current] = unique
    return weld^


def _sort_order(keys: List[_WeldKey], mut order: List[Int]):
    """Sort `order` so the weld keys increase."""
    var count = len(order)
    var start = count // 2
    while start > 0:
        start -= 1
        _sift(keys, order, start, count)
    var end = count
    while end > 1:
        end -= 1
        var tmp = order[0]
        order[0] = order[end]
        order[end] = tmp
        _sift(keys, order, 0, end)


def _sift(keys: List[_WeldKey], mut order: List[Int], start: Int, end: Int):
    """Restore one heap whose root is `start`."""
    var root = start
    while True:
        var child = root * 2 + 1
        if child >= end:
            return
        if child + 1 < end and _before(
            keys[order[child]], keys[order[child + 1]]
        ):
            child += 1
        if _before(keys[order[root]], keys[order[child]]):
            var tmp = order[root]
            order[root] = order[child]
            order[child] = tmp
            root = child
        else:
            return


def _link(
    mut head: List[Int],
    mut dest: List[Int],
    mut nxt: List[Int],
    left: Int,
    right: Int,
):
    """Add an undirected edge once in each direction."""
    if left == right:
        return
    dest.append(right)
    nxt.append(head[left])
    head[left] = len(dest) - 1
    dest.append(left)
    nxt.append(head[right])
    head[right] = len(dest) - 1


def _resolve(raw: List[Int], count: Int) raises -> List[Int]:
    """Return triangle indices, with a negative index counted from the end."""
    var out = List[Int]()
    for index in range(len(raw)):
        var face = raw[index]
        if face < 0:
            face += count
        if face < 0 or face >= count:
            raise Error("index out of range")
        out.append(face)
    return out^


def _json_heads(values: List[Float64]) raises -> String:
    """Return heads as JSON, in the order of `values`."""
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


def _key_part(value: Float64) raises -> Int:
    """Return `round(value * 1000)` as an integer."""
    var scaled = value * 1000.0
    if isnan(scaled) or isinf(scaled):
        raise Error("coordinate is not finite")
    if scaled <= -9223372036854775808.0 or scaled >= 9223372036854775808.0:
        raise Error("coordinate is out of range")
    var negative = scaled < 0.0
    var mag = -scaled if negative else scaled
    var whole = Int(mag)
    var frac = mag - Float64(whole)
    var rounded = whole
    if frac > 0.5 or (frac == 0.5 and whole % 2 != 0):
        rounded += 1
    if negative:
        return -rounded
    return rounded


def _before(left: _WeldKey, right: _WeldKey) -> Bool:
    """Return whether `left` sorts before `right`."""
    if left.x != right.x:
        return left.x < right.x
    if left.y != right.y:
        return left.y < right.y
    return left.z < right.z


def _same(left: _WeldKey, right: _WeldKey) -> Bool:
    """Return whether two welded keys are equal."""
    return left.x == right.x and left.y == right.y and left.z == right.z


def _placed_copies(doc: PyJson, root: Int) raises -> String:
    """Return every copy's heads in the world frame."""
    var heads = doc.at(root, "heads")
    if doc.kind(heads) != PY_LIST:
        raise Error("heads are not a list")
    var matrices = doc.at(root, "matrices")
    if doc.kind(matrices) != PY_LIST:
        raise Error("matrices are not a list")
    var heads_json = _compact(doc, heads)
    var out = String("[")
    var first = True
    for index in range(doc.length(matrices)):
        var frame = PyJson.parse(
            frame_json(_compact(doc, doc.item(matrices, index)))
        )
        var request = String('{"heads":')
        request += heads_json
        request += ',"linear":'
        request += _compact(frame, frame.at(frame.root, "linear"))
        request += ',"move":'
        request += _compact(frame, frame.at(frame.root, "move"))
        request += "}"
        var placed_doc = PyJson.parse(request)
        var one = _placed(placed_doc, placed_doc.root)
        if one == "[]":
            continue
        if not first:
            out += ","
        first = False
        var end = one.byte_length() - 1
        out += String(one[byte=1:end])
    out += "]"
    return out


def _compact(doc: PyJson, node: Int) raises -> String:
    """Return JSON with no spaces, in insertion order."""
    var kind = doc.kind(node)
    if kind == PY_DICT:
        var out = String("{")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += _quote(doc.key(node, index))
            out += ":"
            out += _compact(doc, doc.value(node, index))
        out += "}"
        return out
    if kind == PY_LIST:
        var out = String("[")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += _compact(doc, doc.item(node, index))
        out += "]"
        return out
    if kind == PY_STR:
        return _quote(doc.text(node))
    if kind == PY_BOOL:
        if doc.flag(node):
            return "true"
        return "false"
    if kind == PY_NONE:
        return "null"
    return doc.text(node)


def _quote(text: String) -> String:
    """Return one JSON string."""
    var out = String('"')
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 34 or byte == 92:
            out += "\\"
            out += chr(Int(byte))
        else:
            out += chr(Int(byte))
    out += '"'
    return out


def _placed(doc: PyJson, root: Int) raises -> String:
    """Return lamp heads in the world frame."""
    var heads = _rows(doc, doc.at(root, "heads"), 3, "head")
    var linear = _rows(doc, doc.at(root, "linear"), 3, "matrix row")
    if len(linear) != 3:
        raise Error("matrix is not 3 by 3")
    var move = _row(doc, doc.at(root, "move"), 3, "move")
    var out = String("[")
    for index in range(len(heads)):
        if index > 0:
            out += ","
        out += "["
        for axis in range(3):
            if axis > 0:
                out += ","
            var sum = _fadd(
                _fadd(
                    _fmul(heads[index][0], linear[axis][0]),
                    _fmul(heads[index][1], linear[axis][1]),
                ),
                _fmul(heads[index][2], linear[axis][2]),
            )
            out += python_repr(_fadd(sum, move[axis]))
        out += "]"
    out += "]"
    return out^


def _rows(
    doc: PyJson, node: Int, width: Int, name: String
) raises -> List[List[Float64]]:
    """Return a list of number rows."""
    if doc.kind(node) != PY_LIST:
        raise Error(name + " is not a list")
    var out = List[List[Float64]]()
    for index in range(doc.length(node)):
        out.append(_row(doc, doc.item(node, index), width, name))
    return out^


def _row(
    doc: PyJson, node: Int, width: Int, name: String
) raises -> List[Float64]:
    """Return one row of `width` numbers."""
    if doc.kind(node) != PY_LIST or doc.length(node) != width:
        raise Error(name + " is not " + String(width) + " numbers")
    var out = List[Float64]()
    for index in range(width):
        out.append(_coord(doc, doc.item(node, index)))
    return out^


def _coord(doc: PyJson, node: Int) raises -> Float64:
    """Return one finite coordinate."""
    var kind = doc.kind(node)
    var value: Float64
    if kind == PY_FLOAT:
        value = doc.number(node)
    elif kind == PY_INT:
        value = parse_float(doc.text(node))
    else:
        raise Error("coordinate is not a number")
    if isnan(value) or isinf(value):
        raise Error("coordinate is not finite")
    return value


@no_inline
def _fmul(left: Float64, right: Float64) -> Float64:
    """Return one product, rounded before the next operation."""
    return left * right


@no_inline
def _fadd(left: Float64, right: Float64) -> Float64:
    """Return one sum, rounded before the next operation."""
    return left + right


def _ends(text: String, suffix: String) -> Bool:
    """Return whether `text` ends with `suffix`."""
    var raw = text.as_bytes()
    var tail = suffix.as_bytes()
    if len(raw) < len(tail):
        return False
    var start = len(raw) - len(tail)
    for index in range(len(tail)):
        if raw[start + index] != tail[index]:
            return False
    return True


def main() raises:
    """Print the lamp heads for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_lamps FILE", file=stderr)
        exit(2)
    try:
        print(heads_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_lamps:", error, file=stderr)
        exit(1)
