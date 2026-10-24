# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Draw the engine cube from scratch.

    carla_town_cube

The program prints one glTF-style primitive: a one-meter box centered on
its origin. Each face has four corners and two triangles. The material
name is `BasicShapeMaterial`.
"""

from std.sys import argv, exit, stderr

from tools._python_float import python_repr


def cube_text() raises -> String:
    """Return the engine cube as JSON.

    Returns:
        One object with `material`, `positions`, `normals`, `uvs` and
        `triangles`, as `json.dumps` writes the numbers.

    Raises:
        Error: If a coordinate cannot be written.
    """
    var positions = List[Float64]()
    var normals = List[Float64]()
    var uvs = List[Float64]()
    var triangles = List[Int]()
    for axis in range(3):
        for sign_index in range(2):
            var sign = -1.0
            if sign_index == 1:
                sign = 1.0
            var nx = 0.0
            var ny = 0.0
            var nz = 0.0
            if axis == 0:
                nx = sign
            elif axis == 1:
                ny = sign
            else:
                nz = sign
            var ux = 0.0
            var uy = 0.0
            var uz = 0.0
            var vx = 0.0
            var vy = 0.0
            var vz = 0.0
            var u_axis = (axis + 1) % 3
            var v_axis = (axis + 2) % 3
            if u_axis == 0:
                ux = 1.0
            elif u_axis == 1:
                uy = 1.0
            else:
                uz = 1.0
            if v_axis == 0:
                vx = 1.0
            elif v_axis == 1:
                vy = 1.0
            else:
                vz = 1.0
            if sign < 0.0:
                var swap_x = ux
                var swap_y = uy
                var swap_z = uz
                ux = vx
                uy = vy
                uz = vz
                vx = swap_x
                vy = swap_y
                vz = swap_z
            var base = len(positions) // 3
            for corner in range(4):
                var du = 0.0
                var dv = 0.0
                if corner == 1 or corner == 2:
                    du = 1.0
                if corner == 2 or corner == 3:
                    dv = 1.0
                positions.append(0.5 * nx + (du - 0.5) * ux + (dv - 0.5) * vx)
                positions.append(0.5 * ny + (du - 0.5) * uy + (dv - 0.5) * vy)
                positions.append(0.5 * nz + (du - 0.5) * uz + (dv - 0.5) * vz)
                normals.append(nx)
                normals.append(ny)
                normals.append(nz)
                uvs.append(du)
                uvs.append(dv)
            triangles.append(base)
            triangles.append(base + 1)
            triangles.append(base + 2)
            triangles.append(base)
            triangles.append(base + 2)
            triangles.append(base + 3)
    var out = String('{"material":"BasicShapeMaterial","positions":')
    out += _vectors(positions, 3)
    out += ',"normals":'
    out += _vectors(normals, 3)
    out += ',"uvs":'
    out += _vectors(uvs, 2)
    out += ',"triangles":'
    out += _triangles(triangles)
    out += "}"
    return out^


def _vectors(values: List[Float64], width: Int) raises -> String:
    """Return `values` as a JSON array of arrays of `width`."""
    var out = String("[")
    var count = len(values) // width
    for index in range(count):
        if index > 0:
            out += ","
        out += "["
        for axis in range(width):
            if axis > 0:
                out += ","
            out += python_repr(values[index * width + axis])
        out += "]"
    out += "]"
    return out^


def _triangles(values: List[Int]) -> String:
    """Return triangle indexes as a JSON array of triples."""
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


def main() raises:
    """Print the engine cube."""
    var arguments = argv()
    if len(arguments) != 1:
        print("usage: carla_town_cube", file=stderr)
        exit(2)
    print(cube_text())
