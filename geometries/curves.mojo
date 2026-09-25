# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Space-filling curves as lists of points, from three.js
`examples/jsm/utils/GeometryUtils.js`.

`hilbert2d` and `hilbert3d` return the corners of a Hilbert curve that
fills a square in the xz plane or a cube, in the order the curve visits
them. `gosper` returns the points of a Gosper curve, the flowsnake, in the
xy plane. Each is three.js's function of the same name: the same points in
the same order, for a line strip.

`hilbert2d` and `hilbert3d` take the order in which the corners of each
cell are visited, as three.js's `v0` to `v7` do. The defaults are
three.js's.
"""

from math.vector3 import Vector3
from std.math import cos, pi, sin
from units.si import Length, METER


def _check_order(order: List[Int], count: Int) raises:
    """Refuse a visiting order that is not every corner once."""
    if len(order) != count:
        raise Error("A Hilbert curve needs the order of every corner")
    for corner in range(count):  # pragma: no branch
        var seen = 0
        for at in range(count):  # pragma: no branch
            if order[at] == corner:
                seen += 1
        if seen != 1:
            raise Error("A Hilbert curve visits each corner once")


def hilbert2d(
    center: Vector3 = Vector3(0, 0, 0),
    size: Length = Length(10.0, METER),
    iterations: Int = 1,
    order: List[Int] = [0, 1, 2, 3],
) raises -> List[Vector3]:
    """Return the corners of a Hilbert curve across a square in the xz
    plane, three.js's `hilbert2D`.

    Args:
        center: The middle of the square.
        size: How wide the square is.
        iterations: How many times each cell is split in four. One, the
            default, gives four cells and sixteen points.
        order: Which corner of a cell the curve visits first, second,
            third and fourth: three.js's `v0` to `v3`.

    Returns:
        Four points for each cell, in the order the curve visits them.

    Raises:
        Error: If `iterations` is negative, or `order` is not the four
            corners once each.
    """
    if iterations < 0:
        raise Error("A Hilbert curve cannot have a negative iteration count")
    _check_order(order, 4)
    var out = List[Vector3]()
    _hilbert2d(out, center, size.to(METER), iterations, order)
    return out^


def _hilbert2d(
    mut out: List[Vector3],
    center: Vector3,
    size: Float32,
    iterations: Int,
    order: List[Int],
):
    """Append a cell's points, or its four smaller cells'."""
    var half = size / 2
    var corners: List[Vector3] = [
        Vector3(center.x - half, center.y, center.z - half),
        Vector3(center.x - half, center.y, center.z + half),
        Vector3(center.x + half, center.y, center.z + half),
        Vector3(center.x + half, center.y, center.z - half),
    ]
    if iterations == 0:
        for at in range(4):  # pragma: no branch
            out.append(corners[order[at]])
        return
    var v0 = order[0]
    var v1 = order[1]
    var v2 = order[2]
    var v3 = order[3]
    var next = iterations - 1
    _hilbert2d(out, corners[v0], half, next, [v0, v3, v2, v1])
    _hilbert2d(out, corners[v1], half, next, [v0, v1, v2, v3])
    _hilbert2d(out, corners[v2], half, next, [v0, v1, v2, v3])
    _hilbert2d(out, corners[v3], half, next, [v2, v1, v0, v3])


def hilbert3d(
    center: Vector3 = Vector3(0, 0, 0),
    size: Length = Length(10.0, METER),
    iterations: Int = 1,
    order: List[Int] = [0, 1, 2, 3, 4, 5, 6, 7],
) raises -> List[Vector3]:
    """Return the corners of a Hilbert curve through a cube, three.js's
    `hilbert3D`.

    Args:
        center: The middle of the cube.
        size: How wide the cube is.
        iterations: How many times each cell is split in eight. One, the
            default, gives eight cells and sixty-four points.
        order: Which corner of a cell the curve visits in each turn:
            three.js's `v0` to `v7`.

    Returns:
        Eight points for each cell, in the order the curve visits them.

    Raises:
        Error: If `iterations` is negative, or `order` is not the eight
            corners once each.
    """
    if iterations < 0:
        raise Error("A Hilbert curve cannot have a negative iteration count")
    _check_order(order, 8)
    var out = List[Vector3]()
    _hilbert3d(out, center, size.to(METER), iterations, order)
    return out^


def _hilbert3d(
    mut out: List[Vector3],
    center: Vector3,
    size: Float32,
    iterations: Int,
    order: List[Int],
):
    """Append a cell's points, or its eight smaller cells'."""
    var half = size / 2
    var corners: List[Vector3] = [
        Vector3(center.x - half, center.y + half, center.z - half),
        Vector3(center.x - half, center.y + half, center.z + half),
        Vector3(center.x - half, center.y - half, center.z + half),
        Vector3(center.x - half, center.y - half, center.z - half),
        Vector3(center.x + half, center.y - half, center.z - half),
        Vector3(center.x + half, center.y - half, center.z + half),
        Vector3(center.x + half, center.y + half, center.z + half),
        Vector3(center.x + half, center.y + half, center.z - half),
    ]
    if iterations == 0:
        for at in range(8):  # pragma: no branch
            out.append(corners[order[at]])
        return
    var v0 = order[0]
    var v1 = order[1]
    var v2 = order[2]
    var v3 = order[3]
    var v4 = order[4]
    var v5 = order[5]
    var v6 = order[6]
    var v7 = order[7]
    var next = iterations - 1
    _hilbert3d(out, corners[v0], half, next, [v0, v3, v4, v7, v6, v5, v2, v1])
    _hilbert3d(out, corners[v1], half, next, [v0, v7, v6, v1, v2, v5, v4, v3])
    _hilbert3d(out, corners[v2], half, next, [v0, v7, v6, v1, v2, v5, v4, v3])
    _hilbert3d(out, corners[v3], half, next, [v2, v3, v0, v1, v6, v7, v4, v5])
    _hilbert3d(out, corners[v4], half, next, [v2, v3, v0, v1, v6, v7, v4, v5])
    _hilbert3d(out, corners[v5], half, next, [v4, v3, v2, v5, v6, v1, v0, v7])
    _hilbert3d(out, corners[v6], half, next, [v4, v3, v2, v5, v6, v1, v0, v7])
    _hilbert3d(out, corners[v7], half, next, [v6, v5, v2, v1, v0, v3, v4, v7])


# three.js's Gosper rules: four rewrites of `A`, turning a sixth of a turn.
comptime GOSPER_STEPS = 4
comptime GOSPER_A = "A+BF++BF-FA--FAFA-BF+"
comptime GOSPER_B = "-FA+BFBF++BF+FA--FA-B"


def gosper(size: Length = Length(1.0, METER)) -> List[Float32]:
    """Return the points of a Gosper curve in the xy plane, three.js's
    `gosper`.

    The word `A` is rewritten four times, and read as a turtle: `F` steps
    `size` forward, and `+` and `-` turn a sixth of a turn either way. The
    curve starts at the origin, heading along +x, and y points down, as
    three.js's `-sin` makes it.

    Args:
        size: How long each step is.

    Returns:
        Three numbers a point, the origin first, as three.js returns them.
    """
    var word = String("A")
    for _ in range(GOSPER_STEPS):  # pragma: no branch
        var next = String()
        for byte in word.as_bytes():  # pragma: no branch
            if byte == 65:
                next += GOSPER_A
            elif byte == 66:
                next += GOSPER_B
            else:
                next += chr(Int(byte))
        word = next^
    var step = Float64(size.to(METER))
    var x = Float64(0)
    var y = Float64(0)
    var angle = Float64(0)
    var sixth = pi / 3
    var path: List[Float32] = [0, 0, 0]
    for byte in word.as_bytes():  # pragma: no branch
        if byte == 43:
            angle += sixth
        elif byte == 45:
            angle -= sixth
        elif byte == 70:
            x += step * cos(angle)
            y += -step * sin(angle)
            path.append(Float32(x))
            path.append(Float32(y))
            path.append(0)
    return path^
