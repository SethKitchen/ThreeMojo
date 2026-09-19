# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A femur mesh from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = femur(person)

The solid lives in `dimensions`. This file wraps a capsule around that
solid and walks each vertex from an interior landmark out to the zero
set, so a long thin bone is sampled along its surface rather than on a
grid that can miss the shaft. Normals come from the field's gradient.
Texture coordinates are the capsule's: `u` around, `v` up.

`detail` is how many segments the capsule uses around and along. Eight is
the least. Twenty-four is the default. Sixty-four is the most.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurDimensions,
    FemurField,
    femur_dimensions,
)
from geometries.capsule import capsule
from math.vector3 import Vector3
from std.math import max, min
from units.si import Length

comptime MIN_DETAIL = 8
comptime MAX_DETAIL = 64
comptime BISECT_STEPS = 16


def femur(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 24
) raises -> BufferGeometry:
    """Return a femur sized for `spec`, standing on y, origin at mid-shaft.

    Args:
        spec: Standing height and osteological sex. The femur reads both.
        side: `RIGHT` or `LEFT`. A right femur is the default.
        detail: Segments around and along the capsule. Eight through
            sixty-four, twenty-four by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes, indexed
        like a capsule. Each normal points out of the bone.

    Raises:
        Error: If `spec.sex` or `side` is not valid, if stature is not
            finite or is outside 1.2 m through 2.5 m, or if `detail` is
            out of range.
    """
    return femur_from_dimensions(
        femur_dimensions(spec.stature, spec.sex, side), detail
    )


def femur_from_dimensions(
    dimensions: FemurDimensions, detail: Int = 24
) raises -> BufferGeometry:
    """Return a femur mesh for already-computed dimensions.

    Args:
        dimensions: Size and landmarks from `femur_dimensions`.
        detail: Segments around and along the capsule.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `detail` is less than eight or more than sixty-four.
    """
    if detail < MIN_DETAIL:
        raise Error("A femur needs a detail of at least eight")
    if detail > MAX_DETAIL:
        raise Error("A femur's detail cannot exceed sixty-four")

    var field = FemurField(dimensions)
    var rad_fit = max(
        max(_abs(field.low.x), _abs(field.high.x)),
        max(_abs(field.low.z), _abs(field.high.z)),
    ) * Float32(1.08)
    var half_h = max(_abs(field.low.y), _abs(field.high.y))
    var rad = min(rad_fit, half_h * Float32(0.45))
    var straight = 2 * half_h - 2 * rad
    var cap_segments = detail // 4
    if cap_segments < 3:
        cap_segments = 3
    var geometry = capsule(
        Length(rad), Length(straight), cap_segments, detail, detail
    )
    var placed = geometry.clone_attribute(String(POSITION))
    var count = placed.count()
    var data = List[Float32]()
    var normals = List[Float32]()
    var reach = (half_h + rad) * 3
    for index in range(count):  # pragma: no branch
        var p = placed.vector3(index)
        var seed = _seed(field, p)
        var outer = seed + _direction(seed, p) * reach
        var surface = _bisect(field, seed, outer)
        data.append(surface.x)
        data.append(surface.y)
        data.append(surface.z)
        var n = field.gradient(surface)
        normals.append(n.x)
        normals.append(n.y)
        normals.append(n.z)
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    return geometry^


def _abs(value: Float32) -> Float32:
    """Return `value` without its sign."""
    if value < 0:
        return -value
    return value


def _direction(origin: Vector3, toward: Vector3) -> Vector3:
    """Return the unit vector from `origin` to `toward`.

    A zero vector, when the two coincide, is replaced by plus y so a
    later scale still has a direction.
    """
    var away = toward - origin
    if away.length() == 0:
        return Vector3(0, 1, 0)
    away.normalize()
    return away


def _closer(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
    """Return whichever of `a` or `b` is nearer to `point`."""
    var da = point - a
    var db = point - b
    if da.dot(da) <= db.dot(db):
        return a
    return b


def _seed(field: FemurField, point: Vector3) -> Vector3:
    """Return an interior landmark near `point`, to march out from."""
    var seed = field.head_center
    seed = _closer(point, seed, field.neck_base)
    seed = _closer(point, seed, field.s0)
    seed = _closer(point, seed, field.s1)
    seed = _closer(point, seed, field.s2)
    seed = _closer(point, seed, field.s3)
    seed = _closer(point, seed, field.s4)
    seed = _closer(point, seed, field.gt)
    seed = _closer(point, seed, field.lt)
    seed = _closer(point, seed, field.medial)
    seed = _closer(point, seed, field.lateral)
    return _closer(point, seed, field.patella)


def _bisect(field: FemurField, inside: Vector3, outside: Vector3) -> Vector3:
    """Return the zero set between an interior point and an exterior one."""
    var lo = inside
    var hi = outside
    for _ in range(BISECT_STEPS):  # pragma: no branch
        var mid = Vector3(
            (lo.x + hi.x) * 0.5,
            (lo.y + hi.y) * 0.5,
            (lo.z + hi.z) * 0.5,
        )
        if field.distance(mid) < 0:
            lo = mid
        else:
            hi = mid
    return hi
