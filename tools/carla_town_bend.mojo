# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Bend a town spline mesh along its curve.

    carla_town_bend REQUEST.json

The request holds the points, the normals and the spline. The program
prints the bent points and normals in the component frame, in Unreal's
axes and centimeters. The curve is the same Hermite curve the Python
bake uses.
"""

from std.math import cos, sin, sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_float import python_repr


def bend_text(text: String) raises -> String:
    """Bend the mesh in one JSON request.

    Args:
        text: JSON with `points`, `normals`, `forward_axis`, `start`,
            `end`, `start_tangent`, `end_tangent`, `start_roll`,
            `end_roll`, `start_scale` and `end_scale`.

    Returns:
        JSON with `points` and `normals`.

    Raises:
        Error: If the request has no points or an unknown forward axis.
    """
    var tree = JsonTree()
    var root = tree.parse(text)
    var points = _vec3(tree, tree.item(root, "points"))
    var normals = _vec3(tree, tree.item(root, "normals"))
    if len(points) == 0 or len(points) != len(normals):
        raise Error("a spline mesh needs one normal for each point")
    var axis = tree.int_value(tree.item(root, "forward_axis"))
    if axis < 0 or axis > 2:
        raise Error("a spline forward axis is 0, 1 or 2")
    var start = _one(tree, tree.item(root, "start"))
    var end = _one(tree, tree.item(root, "end"))
    var start_tangent = _one(tree, tree.item(root, "start_tangent"))
    var end_tangent = _one(tree, tree.item(root, "end_tangent"))
    var start_roll = tree.value(tree.item(root, "start_roll"))
    var end_roll = tree.value(tree.item(root, "end_roll"))
    var start_scale = _pair(tree, tree.item(root, "start_scale"))
    var end_scale = _pair(tree, tree.item(root, "end_scale"))
    var count = len(points) // 3
    var local = List[Float64]()
    var along = List[Float64]()
    var low = 0.0
    var high = 0.0
    for index in range(count):
        var x = points[index * 3] * 100.0
        var y = points[index * 3 + 2] * 100.0
        var z = points[index * 3 + 1] * 100.0
        local.append(x)
        local.append(y)
        local.append(z)
        var value = x
        if axis == 1:
            value = y
        elif axis == 2:
            value = z
        along.append(value)
        if index == 0 or value < low:
            low = value
        if index == 0 or value > high:
            high = value
    var span = high - low
    if span < 1e-6:
        span = 1e-6
    var bent = List[Float64]()
    var bent_normals = List[Float64]()
    for index in range(count):
        var alpha = (along[index] - low) / span
        var position = _hermite_point(
            start, start_tangent, end, end_tangent, alpha
        )
        var direction = _hermite_direction(
            start, start_tangent, end, end_tangent, alpha
        )
        direction = _unit(direction, 1e-9)
        var base_x = _cross(_up(), direction)
        base_x = _unit(base_x, 1e-9)
        var base_y = _cross(direction, base_x)
        var roll = start_roll + (end_roll - start_roll) * alpha
        var c = cos(roll)
        var s = sin(roll)
        var x_vec = _sub(_scale(base_x, c), _scale(base_y, s))
        var y_vec = _add(_scale(base_y, c), _scale(base_x, s))
        var scale0 = start_scale[0] + (end_scale[0] - start_scale[0]) * alpha
        var scale1 = start_scale[1] + (end_scale[1] - start_scale[1]) * alpha
        var across0 = 1
        var across1 = 2
        if axis == 1:
            across0 = 2
            across1 = 0
        elif axis == 2:
            across0 = 0
            across1 = 1
        var offset = _add(
            _scale(x_vec, local[index * 3 + across0] * scale0),
            _scale(y_vec, local[index * 3 + across1] * scale1),
        )
        var point = _add(position, offset)
        bent.append(point[0])
        bent.append(point[1])
        bent.append(point[2])
        var nx = normals[index * 3]
        var ny = normals[index * 3 + 2]
        var nz = normals[index * 3 + 1]
        var normal = _add(
            _add(_scale(direction, nx), _scale(x_vec, ny)), _scale(y_vec, nz)
        )
        if axis == 1:
            normal = _add(
                _add(_scale(y_vec, nx), _scale(direction, ny)),
                _scale(x_vec, nz),
            )
        elif axis == 2:
            normal = _add(
                _add(_scale(x_vec, nx), _scale(y_vec, ny)),
                _scale(direction, nz),
            )
        bent_normals.append(normal[0])
        bent_normals.append(normal[1])
        bent_normals.append(normal[2])
    var out = String('{"points":')
    out += _json(bent)
    out += ',"normals":'
    out += _json(bent_normals)
    out += "}"
    return out^


def _hermite_point(
    p0: List[Float64],
    t0: List[Float64],
    p1: List[Float64],
    t1: List[Float64],
    alpha: Float64,
) -> List[Float64]:
    """Return the point on the Hermite curve."""
    var a2 = alpha * alpha
    var a3 = a2 * alpha
    return _mix(
        p0,
        t0,
        p1,
        t1,
        2.0 * a3 - 3.0 * a2 + 1.0,
        a3 - 2.0 * a2 + alpha,
        -2.0 * a3 + 3.0 * a2,
        a3 - a2,
    )


def _hermite_direction(
    p0: List[Float64],
    t0: List[Float64],
    p1: List[Float64],
    t1: List[Float64],
    alpha: Float64,
) -> List[Float64]:
    """Return the unnormalized Hermite tangent."""
    var a2 = alpha * alpha
    return _mix(
        p0,
        t0,
        p1,
        t1,
        6.0 * a2 - 6.0 * alpha,
        3.0 * a2 - 4.0 * alpha + 1.0,
        -6.0 * a2 + 6.0 * alpha,
        3.0 * a2 - 2.0 * alpha,
    )


def _mix(
    p0: List[Float64],
    t0: List[Float64],
    p1: List[Float64],
    t1: List[Float64],
    w0: Float64,
    w1: Float64,
    w2: Float64,
    w3: Float64,
) -> List[Float64]:
    """Return a weighted sum of four 3-vectors."""
    var out = List[Float64]()
    for index in range(3):
        out.append(
            w0 * p0[index] + w1 * t0[index] + w2 * p1[index] + w3 * t1[index]
        )
    return out^


def _up() -> List[Float64]:
    """Return Unreal's up axis."""
    var out = List[Float64]()
    out.append(0.0)
    out.append(0.0)
    out.append(1.0)
    return out^


def _cross(left: List[Float64], right: List[Float64]) -> List[Float64]:
    """Return the cross product of two 3-vectors."""
    var out = List[Float64]()
    out.append(left[1] * right[2] - left[2] * right[1])
    out.append(left[2] * right[0] - left[0] * right[2])
    out.append(left[0] * right[1] - left[1] * right[0])
    return out^


def _add(left: List[Float64], right: List[Float64]) -> List[Float64]:
    """Return the sum of two 3-vectors."""
    var out = List[Float64]()
    for index in range(3):
        out.append(left[index] + right[index])
    return out^


def _sub(left: List[Float64], right: List[Float64]) -> List[Float64]:
    """Return the difference of two 3-vectors."""
    var out = List[Float64]()
    for index in range(3):
        out.append(left[index] - right[index])
    return out^


def _scale(value: List[Float64], factor: Float64) -> List[Float64]:
    """Return a 3-vector multiplied by `factor`."""
    var out = List[Float64]()
    for index in range(3):
        out.append(value[index] * factor)
    return out^


def _unit(value: List[Float64], floor: Float64) -> List[Float64]:
    """Return `value` divided by its length, and at least `floor`."""
    var length = sqrt(
        value[0] * value[0] + value[1] * value[1] + value[2] * value[2]
    )
    if length < floor:
        length = floor
    return _scale(value, 1.0 / length)


def _vec3(tree: JsonTree, node: Int) raises -> List[Float64]:
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


def _one(tree: JsonTree, node: Int) raises -> List[Float64]:
    """Read one 3-vector."""
    var columns = tree.items(node)
    if len(columns) != 3:
        raise Error("a vector needs three numbers")
    var out = List[Float64]()
    for column in range(3):
        out.append(tree.value(columns[column]))
    return out^


def _pair(tree: JsonTree, node: Int) raises -> List[Float64]:
    """Read one pair of scales."""
    var columns = tree.items(node)
    if len(columns) != 2:
        raise Error("a spline scale needs two numbers")
    var out = List[Float64]()
    out.append(tree.value(columns[0]))
    out.append(tree.value(columns[1]))
    return out^


def _json(values: List[Float64]) raises -> String:
    """Return 3-vectors as a JSON array."""
    var out = String("[")
    var count = len(values) // 3
    for index in range(count):
        if index > 0:
            out += ","
        out += "["
        out += python_repr(values[index * 3])
        out += ","
        out += python_repr(values[index * 3 + 1])
        out += ","
        out += python_repr(values[index * 3 + 2])
        out += "]"
    out += "]"
    return out^


def main() raises:
    """Print the bent points for the request file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_bend REQUEST.json", file=stderr)
        exit(2)
    try:
        print(bend_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_bend:", error, file=stderr)
        exit(1)
