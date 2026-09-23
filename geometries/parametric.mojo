# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A surface from a function of two numbers, from three.js
`examples/jsm/geometries/ParametricGeometry.js` and
`ParametricFunctions.js`.

The function takes `u` and `v`, each from zero to one, and returns a point.
The builder samples it on a grid of `slices` by `stacks` cells and joins the
samples with two triangles a cell, exactly as three.js does.

three.js passes the function as a JavaScript closure. Mojo closures are hard
to store and pass around, so the surface is a type instead. Anything that
implements `ParametricSurface` is a surface, and a plain function becomes one
through `SurfaceFunction`. A surface that needs its own numbers, a radius or
a twist, is a struct that holds them.

The normals are three.js's finite differences. Each vertex asks the function
for a second point one `EPS` away along `u`, and another along `v`, and
crosses the two differences. At the first row and column the step goes
forward, because the function is not asked for a negative number. The
arithmetic is `Float32` here and `Float64` in JavaScript, so a normal can
be off by a few parts in a thousand where three.js is exact to twelve places.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from math.vector3 import Vector3
from std.math import cos, isfinite, pi, sin

# The step the finite differences take, in units of `u` and `v`: three.js's
# `EPS`.
comptime EPS = Float32(0.00001)


trait ParametricSurface:
    """A surface as a function from two numbers to a point.

    `u` and `v` each run from zero to one. The point is in meters, in the
    geometry's own space.
    """

    def point(self, u: Float32, v: Float32) -> Vector3:
        """Return the point of the surface at `(u, v)`.

        Args:
            u: How far along the first direction, zero to one.
            v: How far along the second direction, zero to one.

        Returns:
            The point, in meters.
        """
        ...


@fieldwise_init
struct SurfaceFunction[func: def(Float32, Float32) thin -> Vector3](
    ImplicitlyCopyable, ParametricSurface
):
    """A plain function of `u` and `v` used as a surface.

    `parametric(SurfaceFunction[klein]())` builds three.js's Klein bottle.
    The function is a compile-time parameter, so the call costs nothing.

    Parameters:
        func: The function, from `u` and `v` to a point in meters.
    """

    def point(self, u: Float32, v: Float32) -> Vector3:
        """Return what the function gives at `(u, v)`.

        Args:
            u: How far along the first direction, zero to one.
            v: How far along the second direction, zero to one.

        Returns:
            The point, in meters.
        """
        return Self.func(u, v)


def _check(point: Vector3) raises -> Vector3:
    """Return `point`, or raise if any of its numbers is not finite."""
    if not (isfinite(point.x) and isfinite(point.y) and isfinite(point.z)):
        raise Error("A parametric surface must give finite points")
    return point


def parametric[
    S: ParametricSurface
](surface: S, slices: Int = 8, stacks: Int = 8) raises -> BufferGeometry:
    """Return a grid sampled from a surface, three.js's `ParametricGeometry`.

    Vertices run in rows of `slices + 1`, one row for each step of `v`. The
    texture coordinate of a vertex is its `(u, v)`.

    Parameters:
        S: The type of the surface.

    Args:
        surface: The function to sample.
        slices: Cells along `u`, one or more. Eight by default, as in
            three.js.
        stacks: Cells along `v`, one or more. Eight by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an index
        buffer.

    Raises:
        Error: If either count is less than one, or the surface gives a point
            that is not finite.
    """
    if slices < 1 or stacks < 1:
        raise Error("A parametric surface needs one slice and one stack")

    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    # Both counts were checked above, so none of these loops runs zero times.
    for i in range(stacks + 1):  # pragma: no branch
        var v = Float32(i) / Float32(stacks)
        for j in range(slices + 1):  # pragma: no branch
            var u = Float32(j) / Float32(slices)
            var p0 = _check(surface.point(u, v))
            data.append(p0.x)
            data.append(p0.y)
            data.append(p0.z)
            var pu: Vector3
            if u - EPS >= 0:
                pu = p0 - _check(surface.point(u - EPS, v))
            else:
                pu = _check(surface.point(u + EPS, v)) - p0
            var pv: Vector3
            if v - EPS >= 0:
                pv = p0 - _check(surface.point(u, v - EPS))
            else:
                pv = _check(surface.point(u, v + EPS)) - p0
            pu.cross(pv)
            pu.normalize()
            normals.append(pu.x)
            normals.append(pu.y)
            normals.append(pu.z)
            uvs.append(u)
            uvs.append(v)

    var slice_count = slices + 1
    var index = List[Int]()
    for i in range(stacks):  # pragma: no branch
        for j in range(slices):  # pragma: no branch
            var a = i * slice_count + j
            var b = i * slice_count + j + 1
            var c = (i + 1) * slice_count + j + 1
            var d = (i + 1) * slice_count + j
            index.append(a)
            index.append(b)
            index.append(d)
            index.append(b)
            index.append(c)
            index.append(d)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    return geometry^


def parametric_plane(u: Float32, v: Float32) -> Vector3:
    """Return the flat square of three.js's `ParametricFunctions.plane`.

    Args:
        u: The x coordinate, in meters.
        v: The z coordinate, in meters.

    Returns:
        The point `(u, 0, v)`.
    """
    return Vector3(u, 0, v)


def klein(v: Float32, u: Float32) -> Vector3:
    """Return a point of three.js's Klein bottle,
    `ParametricFunctions.klein`.

    The two names are swapped, as they are in three.js: the first argument
    goes around the tube and the second along it.

    Args:
        v: How far around the tube, zero to one.
        u: How far along the bottle, zero to one.

    Returns:
        The point, about sixteen meters across.
    """
    var a = u * Float32(pi) * 2
    var b = v * (2 * Float32(pi))
    var ring = 2 * (1 - cos(a) / 2)
    var x: Float32
    var z: Float32
    if a < Float32(pi):
        x = 3 * cos(a) * (1 + sin(a)) + ring * cos(a) * cos(b)
        z = -8 * sin(a) - ring * sin(a) * cos(b)
    else:
        x = 3 * cos(a) * (1 + sin(a)) + ring * cos(b + Float32(pi))
        z = -8 * sin(a)
    return Vector3(x, -ring * sin(b), z)


def mobius(u: Float32, t: Float32) -> Vector3:
    """Return a point of three.js's flat Mobius strip,
    `ParametricFunctions.mobius`.

    Args:
        u: How far across the strip, zero to one.
        t: How far around it, zero to one.

    Returns:
        The point. The strip's center line is a circle of radius two meters.
    """
    var across = u - 0.5
    var v = 2 * Float32(pi) * t
    var a = Float32(2)
    return Vector3(
        cos(v) * (a + across * cos(v / 2)),
        sin(v) * (a + across * cos(v / 2)),
        across * sin(v / 2),
    )


def mobius3d(u: Float32, t: Float32) -> Vector3:
    """Return a point of three.js's thick Mobius band,
    `ParametricFunctions.mobius3d`.

    Args:
        u: How far around the band, zero to one.
        t: How far around its cross section, zero to one.

    Returns:
        The point. The band's center line is a circle of radius 2.25 meters.
    """
    var turn = u * Float32(pi) * 2
    var section = t * (2 * Float32(pi))
    var phi = turn / 2
    var major = Float32(2.25)
    var a = Float32(0.125)
    var b = Float32(0.65)
    var x = a * cos(section) * cos(phi) - b * sin(section) * sin(phi)
    var z = a * cos(section) * sin(phi) + b * sin(section) * cos(phi)
    return Vector3((major + x) * cos(turn), (major + x) * sin(turn), z)
