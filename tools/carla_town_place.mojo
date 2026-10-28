# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Place one town mesh copy in the renderer's frame.

    carla_town_place matrix PITCH YAW ROLL SX SY SZ X Y Z
    carla_town_place apply REQUEST.json
    carla_town_place cell X Y TILE
    carla_town_place serve

`matrix` prints the Unreal row-vector matrix: scale, then rotate, then
move. `apply` reads that matrix plus positions, normals and triangles, and
prints the placed points, unit normals and triangles. `cell` prints the
tile of a copy whose origin is `X` and `Y` centimeters. `TILE` is the
tile width in meters. `serve` answers one request on each line.
"""

from std.ffi import external_call
from std.math import cos, floor, pi, sin
from std.memory import OpaquePointer
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._owned_process import EINTR, errno
from tools._python_float import python_repr


def matrix_rows(
    pitch: Float64,
    yaw: Float64,
    roll: Float64,
    sx: Float64,
    sy: Float64,
    sz: Float64,
    tx: Float64,
    ty: Float64,
    tz: Float64,
) -> List[Float64]:
    """Return the 4 by 4 row-vector matrix, row-major.

    Args:
        pitch: The pitch in degrees.
        yaw: The yaw in degrees.
        roll: The roll in degrees.
        sx: The x scale.
        sy: The y scale.
        sz: The z scale.
        tx: The x translation in centimeters.
        ty: The y translation in centimeters.
        tz: The z translation in centimeters.

    Returns:
        Sixteen numbers. The last column is `0, 0, 0, 1`.
    """
    var p = pitch * pi / 180.0
    var y = yaw * pi / 180.0
    var r = roll * pi / 180.0
    var sp = sin(p)
    var cp = cos(p)
    var syaw = sin(y)
    var cy = cos(y)
    var sr = sin(r)
    var cr = cos(r)
    var r00 = cp * cy
    var r01 = cp * syaw
    var r02 = sp
    var r10 = sr * sp * cy - cr * syaw
    var r11 = sr * sp * syaw + cr * cy
    var r12 = -sr * cp
    var r20 = -(cr * sp * cy + sr * syaw)
    var r21 = cy * sr - cr * sp * syaw
    var r22 = cr * cp
    var out = List[Float64]()
    out.append(sx * r00)
    out.append(sx * r01)
    out.append(sx * r02)
    out.append(0.0)
    out.append(sy * r10)
    out.append(sy * r11)
    out.append(sy * r12)
    out.append(0.0)
    out.append(sz * r20)
    out.append(sz * r21)
    out.append(sz * r22)
    out.append(0.0)
    out.append(tx)
    out.append(ty)
    out.append(tz)
    out.append(1.0)
    return out^


def place_rigid(
    matrix: List[Float64],
    positions: List[Float64],
    normals: List[Float64],
    triangles: List[Int],
) raises -> String:
    """Place vertices by one Unreal row-vector matrix.

    Args:
        matrix: Sixteen row-major numbers.
        positions: The mesh points, three numbers each, in the three.js frame.
        normals: The mesh normals, three numbers each.
        triangles: The triangle indexes, three each.

    Returns:
        JSON with `points`, `normals` and `triangles`.

    Raises:
        Error: If the linear map cannot be inverted.
    """
    if len(matrix) != 16:
        raise Error("a placement matrix has 16 numbers")
    var linear = _to_three(matrix)
    var move_x = matrix[12] / 100.0
    var move_y = matrix[14] / 100.0
    var move_z = matrix[13] / 100.0
    var inverse = _inverse(linear)
    var flip = _det(linear) < 0.0
    var transposed = _transpose(linear)
    var out = String('{"points":')
    out += _placed(positions, transposed, move_x, move_y, move_z)
    out += ',"normals":'
    out += _unit_normals(normals, inverse)
    out += ',"triangles":'
    out += _triangles(triangles, flip)
    out += "}"
    return out^


def _to_three(matrix: List[Float64]) -> List[Float64]:
    """Return `SWAP @ M.T @ SWAP` for the upper 3 by 3."""
    var mt = List[Float64]()
    for row in range(3):
        for column in range(3):
            mt.append(matrix[column * 4 + row])
    var swap = List[Float64]()
    swap.append(1.0)
    swap.append(0.0)
    swap.append(0.0)
    swap.append(0.0)
    swap.append(0.0)
    swap.append(1.0)
    swap.append(0.0)
    swap.append(1.0)
    swap.append(0.0)
    return _mul(_mul(swap, mt), swap)


def _mul(left: List[Float64], right: List[Float64]) -> List[Float64]:
    """Return the product of two 3 by 3 matrices."""
    var out = List[Float64]()
    for row in range(3):
        for column in range(3):
            var sum = 0.0
            for k in range(3):
                sum += left[row * 3 + k] * right[k * 3 + column]
            out.append(sum)
    return out^


def _transpose(matrix: List[Float64]) -> List[Float64]:
    """Return the transpose of a 3 by 3 matrix."""
    var out = List[Float64]()
    for row in range(3):
        for column in range(3):
            out.append(matrix[column * 3 + row])
    return out^


def _det(matrix: List[Float64]) -> Float64:
    """Return the determinant of a 3 by 3 matrix."""
    var a = matrix[0]
    var b = matrix[1]
    var c = matrix[2]
    var d = matrix[3]
    var e = matrix[4]
    var f = matrix[5]
    var g = matrix[6]
    var h = matrix[7]
    var i = matrix[8]
    return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)


def _inverse(matrix: List[Float64]) raises -> List[Float64]:
    """Return the inverse of a 3 by 3 matrix."""
    var a = matrix[0]
    var b = matrix[1]
    var c = matrix[2]
    var d = matrix[3]
    var e = matrix[4]
    var f = matrix[5]
    var g = matrix[6]
    var h = matrix[7]
    var i = matrix[8]
    var det = _det(matrix)
    if det == 0.0:
        raise Error("the placement matrix cannot be inverted")
    var inv = 1.0 / det
    var out = List[Float64]()
    out.append((e * i - f * h) * inv)
    out.append((c * h - b * i) * inv)
    out.append((b * f - c * e) * inv)
    out.append((f * g - d * i) * inv)
    out.append((a * i - c * g) * inv)
    out.append((c * d - a * f) * inv)
    out.append((d * h - e * g) * inv)
    out.append((b * g - a * h) * inv)
    out.append((a * e - b * d) * inv)
    return out^


def _placed(
    positions: List[Float64],
    linear_t: List[Float64],
    move_x: Float64,
    move_y: Float64,
    move_z: Float64,
) raises -> String:
    """Return placed points as JSON."""
    if len(positions) % 3 != 0:
        raise Error("positions need three numbers each")
    var out = String("[")
    var count = len(positions) // 3
    for index in range(count):
        if index > 0:
            out += ","
        var x = positions[index * 3]
        var y = positions[index * 3 + 1]
        var z = positions[index * 3 + 2]
        out += "["
        out += python_repr(
            x * linear_t[0] + y * linear_t[3] + z * linear_t[6] + move_x
        )
        out += ","
        out += python_repr(
            x * linear_t[1] + y * linear_t[4] + z * linear_t[7] + move_y
        )
        out += ","
        out += python_repr(
            x * linear_t[2] + y * linear_t[5] + z * linear_t[8] + move_z
        )
        out += "]"
    out += "]"
    return out^


def _unit_normals(
    normals: List[Float64], inverse: List[Float64]
) raises -> String:
    """Return unit normals after `normals @ inverse`."""
    if len(normals) % 3 != 0:
        raise Error("normals need three numbers each")
    var out = String("[")
    var count = len(normals) // 3
    for index in range(count):
        if index > 0:
            out += ","
        var x = normals[index * 3]
        var y = normals[index * 3 + 1]
        var z = normals[index * 3 + 2]
        var nx = x * inverse[0] + y * inverse[3] + z * inverse[6]
        var ny = x * inverse[1] + y * inverse[4] + z * inverse[7]
        var nz = x * inverse[2] + y * inverse[5] + z * inverse[8]
        var length = (nx * nx + ny * ny + nz * nz) ** 0.5
        if length < 1e-12:
            length = 1e-12
        out += "["
        out += python_repr(nx / length)
        out += ","
        out += python_repr(ny / length)
        out += ","
        out += python_repr(nz / length)
        out += "]"
    out += "]"
    return out^


def _triangles(triangles: List[Int], flip: Bool) -> String:
    """Return triangles, reversed when `flip` is true."""
    var out = String("[")
    var count = len(triangles) // 3
    for index in range(count):
        if index > 0:
            out += ","
        var a = triangles[index * 3]
        var b = triangles[index * 3 + 1]
        var c = triangles[index * 3 + 2]
        if flip:
            var swap = a
            a = c
            c = swap
        out += "["
        out += String(a)
        out += ","
        out += String(b)
        out += ","
        out += String(c)
        out += "]"
    out += "]"
    return out^


def _flat_matrix(tree: JsonTree, node: Int) raises -> List[Float64]:
    """Read a 4 by 4 matrix."""
    var rows = tree.items(node)
    if len(rows) != 4:
        raise Error("a placement matrix has 4 rows")
    var out = List[Float64]()
    for row in range(4):
        var columns = tree.items(rows[row])
        if len(columns) != 4:
            raise Error("a placement matrix has 4 columns")
        for column in range(4):
            out.append(tree.value(columns[column]))
    return out^


def _flat3(tree: JsonTree, node: Int) raises -> List[Float64]:
    """Read an array of 3-vectors."""
    var rows = tree.items(node)
    var out = List[Float64]()
    for index in range(len(rows)):
        var columns = tree.items(rows[index])
        if len(columns) != 3:
            raise Error("a vector needs three numbers")
        for column in range(3):
            out.append(tree.value(columns[column]))
    return out^


def _flat_indexes(tree: JsonTree, node: Int) raises -> List[Int]:
    """Read an array of triangles."""
    var rows = tree.items(node)
    var out = List[Int]()
    for index in range(len(rows)):
        var columns = tree.items(rows[index])
        if len(columns) != 3:
            raise Error("a triangle needs three indexes")
        for column in range(3):
            out.append(tree.int_value(columns[column]))
    return out^


def apply_text(text: String) raises -> String:
    """Place the mesh described by one JSON object.

    Args:
        text: JSON with `matrix`, `positions`, `normals` and `triangles`.

    Returns:
        The placed JSON.

    Raises:
        Error: If the JSON or the matrix is not usable.
    """
    var tree = JsonTree()
    var root = tree.parse(text)
    return place_rigid(
        _flat_matrix(tree, tree.item(root, "matrix")),
        _flat3(tree, tree.item(root, "positions")),
        _flat3(tree, tree.item(root, "normals")),
        _flat_indexes(tree, tree.item(root, "triangles")),
    )


def matrix_text(
    pitch: Float64,
    yaw: Float64,
    roll: Float64,
    sx: Float64,
    sy: Float64,
    sz: Float64,
    tx: Float64,
    ty: Float64,
    tz: Float64,
) raises -> String:
    """Return `matrix_rows` as a JSON array of four rows."""
    var values = matrix_rows(pitch, yaw, roll, sx, sy, sz, tx, ty, tz)
    var out = String("[")
    for row in range(4):
        if row > 0:
            out += ","
        out += "["
        for column in range(4):
            if column > 0:
                out += ","
            out += python_repr(values[row * 4 + column])
        out += "]"
    out += "]"
    return out^


def cell_text(x: Float64, y: Float64, tile: Float64) raises -> String:
    """Return the tile column and row for one copy.

    Args:
        x: The copy's x origin in centimeters.
        y: The copy's y origin in centimeters.
        tile: The tile width in meters.

    Returns:
        Two integers separated by a tab. Each is the floor of the origin
        in meters divided by `tile`.

    Raises:
        Error: If `tile` is not positive.
    """
    if not (tile > 0.0):
        raise Error("tile is not positive")
    var column = _floor_cell(x, tile)
    var row = _floor_cell(y, tile)
    return String(column) + "\t" + String(row)


def _floor_cell(centimeters: Float64, tile: Float64) -> Int:
    """Return the floor of one origin divided by the tile width."""
    var origin = _fdiv(centimeters, 100.0)
    var scaled = floor(_fdiv(origin, tile))
    if scaled < 0.0:
        return -Int(-scaled)
    return Int(scaled)


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


def answer(text: String) raises -> String:
    """Answer one JSON request.

    Args:
        text: An object whose `op` is `matrix` or `apply`.

    Returns:
        The matrix or the placed mesh.

    Raises:
        Error: If `op` is not known or the request is incomplete.
    """
    var tree = JsonTree()
    var root = tree.parse(text)
    var op = tree.text(tree.item(root, "op"))
    if op == "matrix":
        var scale = tree.items(tree.item(root, "scale"))
        var location = tree.items(tree.item(root, "location"))
        return matrix_text(
            tree.value(tree.item(root, "pitch")),
            tree.value(tree.item(root, "yaw")),
            tree.value(tree.item(root, "roll")),
            tree.value(scale[0]),
            tree.value(scale[1]),
            tree.value(scale[2]),
            tree.value(location[0]),
            tree.value(location[1]),
            tree.value(location[2]),
        )
    if op == "apply":
        return place_rigid(
            _flat_matrix(tree, tree.item(root, "matrix")),
            _flat3(tree, tree.item(root, "positions")),
            _flat3(tree, tree.item(root, "normals")),
            _flat_indexes(tree, tree.item(root, "triangles")),
        )
    raise Error("usage: carla_town_place matrix|apply|serve")


def _starts(text: String, prefix: String) -> Bool:
    """Return whether `text` begins with `prefix`."""
    var raw = text.as_bytes()
    var head = prefix.as_bytes()
    if len(raw) < len(head):
        return False
    for index in range(len(head)):
        if raw[index] != head[index]:
            return False
    return True


def _write_stdout(text: String) raises:
    """Write `text` to standard output."""
    var raw = text.as_bytes()
    var sent = 0
    while sent < len(raw):
        var count = external_call["write", Int](
            Int32(1),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(raw.unsafe_ptr()) + sent
            ),
            len(raw) - sent,
        )
        if count > 0:
            sent += count
            continue
        if count == 0 or errno() != Int(EINTR):
            raise Error("cannot write the placement")


def _read_line() raises -> String:
    """Return one line from standard input, or empty text at the end."""
    var out = List[UInt8]()
    var buf = List[UInt8](length=1, fill=0)
    while True:
        var count = external_call["read", Int](
            Int32(0),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(buf.unsafe_ptr())
            ),
            1,
        )
        if count == 0:
            if len(out) == 0:
                return String("")
            break
        if count < 0:
            if errno() == Int(EINTR):
                continue
            raise Error("cannot read the placement request")
        if buf[0] == 10:
            break
        out.append(buf[0])
    if len(out) > 0 and out[len(out) - 1] == 13:
        out.resize(len(out) - 1, 0)
    return String(unsafe_from_utf8=Span(out))


def serve() raises:
    """Answer JSON requests from standard input until it closes."""
    while True:
        var line = _read_line()
        if line.byte_length() == 0:
            return
        try:
            if _starts(line, "apply\t"):
                _write_stdout(
                    apply_text(Path(String(line[byte=6:])).read_text()) + "\n"
                )
            elif _starts(line, "cell\t"):
                _write_stdout(_cell_line(String(line[byte=5:])) + "\n")
            else:
                _write_stdout(answer(line) + "\n")
        except error:
            _write_stdout("ERR\t" + String(error) + "\n")


def _cell_line(text: String) raises -> String:
    """Return the tile for three tab-separated numbers."""
    var parts = List[String]()
    var start = 0
    var raw = text.as_bytes()
    for index in range(len(raw)):
        if raw[index] == 9:
            parts.append(String(text[byte=start:index]))
            start = index + 1
    parts.append(String(text[byte=start:]))
    if len(parts) != 3:
        raise Error("cell needs x, y and tile")
    return cell_text(_arg(parts[0]), _arg(parts[1]), _arg(parts[2]))


def _arg(text: String) raises -> Float64:
    """Read one decimal number."""
    var tree = JsonTree()
    return tree.value(tree.parse(text))


def main() raises:
    """Print one matrix or one placed mesh."""
    var arguments = argv()
    if len(arguments) < 2:
        print(
            "usage: carla_town_place matrix|apply|cell|serve ...", file=stderr
        )
        exit(2)
    try:
        var command = arguments[1]
        if command == "serve" and len(arguments) == 2:
            serve()
        elif command == "matrix" and len(arguments) == 11:
            print(
                matrix_text(
                    _arg(arguments[2]),
                    _arg(arguments[3]),
                    _arg(arguments[4]),
                    _arg(arguments[5]),
                    _arg(arguments[6]),
                    _arg(arguments[7]),
                    _arg(arguments[8]),
                    _arg(arguments[9]),
                    _arg(arguments[10]),
                )
            )
        elif command == "apply" and len(arguments) == 3:
            print(apply_text(Path(arguments[2]).read_text()))
        elif command == "cell" and len(arguments) == 5:
            print(
                cell_text(
                    _arg(arguments[2]), _arg(arguments[3]), _arg(arguments[4])
                )
            )
        else:
            raise Error("usage: carla_town_place matrix|apply|cell|serve ...")
    except error:
        print("carla_town_place:", error, file=stderr)
        exit(1)
