# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Any curve in space, from three.js `src/extras/core/Curve.js`.

three.js's `Curve` is a base class. A subclass gives `getPoint`, and the
base class gives the rest: arc lengths, points spaced by distance, the
tangent by a small step either side, and Frenet frames. `math.curve3`
holds three.js's four built-in curves in one struct with a kind. The
addon curves -- the named curves of `CurveExtras` and the NURBS curve --
are open-ended, so here they are a trait, `SpaceCurve`, and the base
class is a set of functions generic over it.

## Doubles, as in three.js

A `SpaceCurve` gives its points as `Point3`, four doubles of which the
fourth is not used. Everything in this module works in doubles, as
three.js does, and a `Vector3` is made only at the end. So the arc
lengths, the parameter for a distance and the frames agree with
three.js's to a double's last bits and not a float's. `math.curve3`
works in floats.

## What differs from `math.curve3`

The tangent of a curve here is three.js's base `getTangent`: the chord
from a ten-thousandth before the point to a ten-thousandth after it,
unless the curve gives an exact one. A curve that stops at a point has a
zero tangent there, as in three.js, and not an error.

The frames are three.js's `computeFrenetFrames` step for step: a turn
between two tangents shorter than `Number.EPSILON` is no turn, and two
tangents that point opposite ways leave the normal where it was.
`math.curve3.transport_frames` refuses that case.

`SpaceCurve3` lets a `Curve3` be used where a `SpaceCurve` is wanted. It
reads the points of the `Curve3` and takes the tangent by the base rule,
as three.js does for its `CatmullRomCurve3` and the two Bezier curves.
"""

from math.curve3 import Curve3, FrenetFrames
from math.vector3 import Vector3
from std.math import acos, cos, sin, sqrt
from units.si import Length, METER

# Four doubles: a point or a direction in space, and a fourth number that
# is not used.
comptime Point3 = SIMD[DType.float64, 4]

# How many straight runs stand in for a curve when its length is measured,
# three.js's default `arcLengthDivisions`.
comptime ARC_LENGTH_DIVISIONS = 200

# How far either side of a point three.js's base `getTangent` looks.
comptime TANGENT_DELTA = 0.0001

# JavaScript's `Number.EPSILON`: below it, the turn between two tangents
# has no axis.
comptime NUMBER_EPSILON = 2.220446049250313e-16


def point3(x: Float64, y: Float64, z: Float64) -> Point3:
    """Return a point from its three coordinates.

    Args:
        x: The first coordinate.
        y: The second coordinate.
        z: The third coordinate.

    Returns:
        The point, with a fourth number of zero.
    """
    return Point3(x, y, z, 0)


def to_vector3(p: Point3) -> Vector3:
    """Return a point as a `Vector3`, each coordinate rounded to a float.

    Args:
        p: The point.

    Returns:
        The vector.
    """
    return Vector3(Float32(p[0]), Float32(p[1]), Float32(p[2]))


def dot3(a: Point3, b: Point3) -> Float64:
    """Return the dot product of two points, summed as three.js sums it.

    Args:
        a: The first.
        b: The second.

    Returns:
        `a.x * b.x + a.y * b.y + a.z * b.z`.
    """
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross3(a: Point3, b: Point3) -> Point3:
    """Return the cross product of two points, three.js's
    `crossVectors`.

    Args:
        a: The first.
        b: The second.

    Returns:
        `a` crossed with `b`.
    """
    return point3(
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def length3(a: Point3) -> Float64:
    """Return how long a point is from the origin.

    Args:
        a: The point.

    Returns:
        Its length.
    """
    return sqrt(dot3(a, a))


def normalized3(a: Point3) -> Point3:
    """Return a point scaled to unit length, three.js's `normalize`.

    Args:
        a: The point.

    Returns:
        `a` times one over its length, or `a` itself if it is zero long.
    """
    var length = length3(a)
    return a * (1.0 / (length if length != 0 else 1.0))


trait SpaceCurve(Copyable, Movable):
    """A curve in space: three.js's `Curve`, as far as a subclass has to
    give it."""

    def point3(self, t: Float64) raises -> Point3:
        """Return the point of the curve at `t`, three.js's `getPoint`.

        Args:
            t: Where on the curve, from zero at its start to one at its
                end.

        Returns:
            The point, in meters.

        Raises:
            Error: If the curve refuses `t`.
        """
        ...

    def tangent3(self, t: Float64) raises -> Point3:
        """Return the unit direction of the curve at `t`, three.js's
        `getTangent`.

        Args:
            t: Where on the curve, from zero through one.

        Returns:
            The direction, of unit length, or zero where the curve stops.

        Raises:
            Error: If the curve refuses `t`.
        """
        ...


def chord_tangent[C: SpaceCurve](curve: C, t: Float64) raises -> Point3:
    """Return three.js's base `getTangent`: the unit chord from a little
    before `t` to a little after it.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        t: Where on the curve, from zero through one.

    Returns:
        The direction, of unit length, or zero where the two points meet.

    Raises:
        Error: If the curve refuses a point.
    """
    var t1 = t - TANGENT_DELTA
    var t2 = t + TANGENT_DELTA
    if t1 < 0:
        t1 = 0
    if t2 > 1:
        t2 = 1
    return normalized3(curve.point3(t2) - curve.point3(t1))


def _check_divisions(divisions: Int) raises:
    """Raise unless a curve is cut into one run or more."""
    if divisions < 1:
        raise Error("A curve needs one division or more")


def _check_u(u: Float64) raises:
    """Raise unless `u` is a share of a curve's length."""
    if not (u >= 0 and u <= 1):
        raise Error("A curve's u must lie from zero through one")


def lengths_of[
    C: SpaceCurve
](curve: C, divisions: Int = ARC_LENGTH_DIVISIONS) raises -> List[Float64]:
    """Return how far along the curve each of `divisions + 1` equal steps
    in `t` is, three.js's `getLengths`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        divisions: How many straight runs to measure, one or more.

    Returns:
        The distances in meters, the first zero and the last the whole
        length.

    Raises:
        Error: If `divisions` is less than one, or the curve refuses a
            point.
    """
    _check_divisions(divisions)
    var out = List[Float64](capacity=divisions + 1)
    var last = curve.point3(0)
    var total = 0.0
    out.append(0)
    for step in range(1, divisions + 1):  # pragma: no branch
        # One division at least, so this runs.
        var current = curve.point3(Float64(step) / Float64(divisions))
        total += length3(current - last)
        out.append(total)
        last = current
    return out^


def length_of[
    C: SpaceCurve
](curve: C, divisions: Int = ARC_LENGTH_DIVISIONS) raises -> Length:
    """Return how long the curve is, three.js's `getLength`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        divisions: How many straight runs to measure, one or more.

    Returns:
        The length across the runs, an approximation from below.

    Raises:
        Error: If `divisions` is less than one, or the curve refuses a
            point.
    """
    var table = lengths_of(curve, divisions)
    return Length(Float32(table[len(table) - 1]), METER)


def u_to_t(lengths: List[Float64], u: Float64) -> Float64:
    """Return the `t` at which a curve has run `u` of its length,
    three.js's `getUtoTmapping`, binary search and all.

    Args:
        lengths: The table `lengths_of` gives, two entries or more.
        u: How far along by length, from zero through one.

    Returns:
        The parameter at that distance.
    """
    var count = len(lengths)
    var target = u * lengths[count - 1]
    var low = 0
    var high = count - 1
    while low <= high:
        var i = low + (high - low) // 2
        var comparison = lengths[i] - target
        if comparison < 0:
            low = i + 1
        elif comparison > 0:
            high = i - 1
        else:
            high = i
            break
    var i = high
    if lengths[i] == target:
        return Float64(i) / Float64(count - 1)
    var before = lengths[i]
    var fraction = (target - before) / (lengths[i + 1] - before)
    return (Float64(i) + fraction) / Float64(count - 1)


def points_of[
    C: SpaceCurve
](curve: C, divisions: Int = 5) raises -> List[Vector3]:
    """Return `divisions + 1` points at equal steps in `t`, three.js's
    `getPoints`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        divisions: How many runs, one or more. Five by default, as in
            three.js.

    Returns:
        The points, first to last.

    Raises:
        Error: If `divisions` is less than one, or the curve refuses a
            point.
    """
    _check_divisions(divisions)
    var out = List[Vector3](capacity=divisions + 1)
    for step in range(divisions + 1):  # pragma: no branch
        # One division at least, so this runs.
        out.append(to_vector3(curve.point3(Float64(step) / Float64(divisions))))
    return out^


def point_at[
    C: SpaceCurve
](
    curve: C, u: Float64, arc_divisions: Int = ARC_LENGTH_DIVISIONS
) raises -> Vector3:
    """Return the point `u` of the way along the curve by distance,
    three.js's `getPointAt`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        u: How far along by length, from zero through one.
        arc_divisions: How many runs measure the length, three.js's
            `arcLengthDivisions`.

    Returns:
        The point.

    Raises:
        Error: If `u` falls outside zero through one, `arc_divisions` is
            less than one, or the curve refuses a point.
    """
    _check_u(u)
    var table = lengths_of(curve, arc_divisions)
    return to_vector3(curve.point3(u_to_t(table, u)))


def tangent_at[
    C: SpaceCurve
](
    curve: C, u: Float64, arc_divisions: Int = ARC_LENGTH_DIVISIONS
) raises -> Vector3:
    """Return the unit direction `u` of the way along the curve by
    distance, three.js's `getTangentAt`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        u: How far along by length, from zero through one.
        arc_divisions: How many runs measure the length.

    Returns:
        The direction.

    Raises:
        Error: If `u` falls outside zero through one, `arc_divisions` is
            less than one, or the curve refuses a point.
    """
    _check_u(u)
    var table = lengths_of(curve, arc_divisions)
    return to_vector3(curve.tangent3(u_to_t(table, u)))


def spaced_points3[
    C: SpaceCurve
](
    curve: C, divisions: Int = 5, arc_divisions: Int = ARC_LENGTH_DIVISIONS
) raises -> List[Point3]:
    """Return `divisions + 1` points at equal distances along the curve,
    in doubles.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        divisions: How many equal runs, one or more.
        arc_divisions: How many runs measure the length.

    Returns:
        The points, first to last.

    Raises:
        Error: If either count is less than one, or the curve refuses a
            point.
    """
    _check_divisions(divisions)
    var table = lengths_of(curve, arc_divisions)
    var out = List[Point3](capacity=divisions + 1)
    for step in range(divisions + 1):  # pragma: no branch
        # One division at least, so this runs.
        var u = Float64(step) / Float64(divisions)
        out.append(curve.point3(u_to_t(table, u)))
    return out^


def spaced_points_of[
    C: SpaceCurve
](
    curve: C, divisions: Int = 5, arc_divisions: Int = ARC_LENGTH_DIVISIONS
) raises -> List[Vector3]:
    """Return `divisions + 1` points at equal distances along the curve,
    three.js's `getSpacedPoints`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        divisions: How many equal runs, one or more. Five by default, as
            in three.js.
        arc_divisions: How many runs measure the length.

    Returns:
        The points, first to last.

    Raises:
        Error: If either count is less than one, or the curve refuses a
            point.
    """
    var spaced = spaced_points3(curve, divisions, arc_divisions)
    var out = List[Vector3](capacity=len(spaced))
    for index in range(len(spaced)):  # pragma: no branch
        # One division at least, so there are two points.
        out.append(to_vector3(spaced[index]))
    return out^


struct Frames3(Copyable, Movable):
    """A tangent, a normal and a binormal at each step along a curve, in
    doubles: three.js's `computeFrenetFrames` result."""

    var tangents: List[Point3]
    var normals: List[Point3]
    var binormals: List[Point3]

    def __init__(out self):
        """Create an empty set of frames."""
        self.tangents = List[Point3]()
        self.normals = List[Point3]()
        self.binormals = List[Point3]()

    def to_frenet_frames(self) -> FrenetFrames:
        """Return the frames rounded to floats, as `math.curve3` holds
        them.

        Returns:
            The same frames.
        """
        var out = FrenetFrames()
        for index in range(len(self.tangents)):  # pragma: no branch
            # A set of frames from `frames3_of` has two frames at least.
            out.tangents.append(to_vector3(self.tangents[index]))
            out.normals.append(to_vector3(self.normals[index]))
            out.binormals.append(to_vector3(self.binormals[index]))
        return out^


def _rotated(v: Point3, axis: Point3, angle: Float64) -> Point3:
    """Return `v` turned about the unit `axis` by `angle` radians, as
    three.js's `makeRotationAxis` and `applyMatrix4` do it.

    Args:
        v: The point to turn.
        axis: The axis, of unit length.
        angle: The angle, in radians.

    Returns:
        The turned point.
    """
    var c = cos(angle)
    var s = sin(angle)
    var t = 1 - c
    var x = axis[0]
    var y = axis[1]
    var z = axis[2]
    var tx = t * x
    var ty = t * y
    return point3(
        (tx * x + c) * v[0] + (tx * y - s * z) * v[1] + (tx * z + s * y) * v[2],
        (tx * y + s * z) * v[0] + (ty * y + c) * v[1] + (ty * z - s * x) * v[2],
        (tx * z - s * y) * v[0]
        + (ty * z + s * x) * v[1]
        + (t * z * z + c) * v[2],
    )


def _clamp_unit(value: Float64) -> Float64:
    """Return `value` held to minus one through one, for `acos`."""
    return max(-1.0, min(1.0, value))


def frames3_of[
    C: SpaceCurve
](
    curve: C,
    segments: Int,
    closed: Bool = False,
    arc_divisions: Int = ARC_LENGTH_DIVISIONS,
) raises -> Frames3:
    """Return a frame at each of `segments + 1` equal steps along the
    curve by distance, three.js's `computeFrenetFrames`, in doubles.

    The first normal is the axis the first tangent leans least along,
    crossed with the tangent twice. Each later normal is the last one
    turned by the turn between the two tangents. A closed curve then has
    its built-up twist spread evenly back along the frames.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        segments: How many equal runs, one or more.
        closed: Whether to spread the twist so the last frame meets the
            first.
        arc_divisions: How many runs measure the length.

    Returns:
        The frames.

    Raises:
        Error: If `segments` or `arc_divisions` is less than one, or the
            curve refuses a point.
    """
    _check_divisions(segments)
    var table = lengths_of(curve, arc_divisions)
    var frames = Frames3()
    for step in range(segments + 1):  # pragma: no branch
        # One segment at least, so this runs.
        var u = Float64(step) / Float64(segments)
        frames.tangents.append(curve.tangent3(u_to_t(table, u)))
    var first = frames.tangents[0]
    # three.js starts from `Number.MAX_VALUE`, which any finite `tx` is
    # at most, so x is the axis until y or z leans less.
    var tx = abs(first[0])
    var ty = abs(first[1])
    var tz = abs(first[2])
    var smallest = tx
    var normal = point3(1, 0, 0)
    if ty <= smallest:
        smallest = ty
        normal = point3(0, 1, 0)
    if tz <= smallest:
        normal = point3(0, 0, 1)
    var across = normalized3(cross3(first, normal))
    frames.normals.append(cross3(first, across))
    frames.binormals.append(cross3(first, frames.normals[0]))
    for step in range(1, segments + 1):  # pragma: no branch
        # One segment at least, so this runs.
        var next_normal = frames.normals[step - 1]
        var turn = cross3(frames.tangents[step - 1], frames.tangents[step])
        if length3(turn) > NUMBER_EPSILON:
            turn = normalized3(turn)
            var theta = acos(
                _clamp_unit(
                    dot3(frames.tangents[step - 1], frames.tangents[step])
                )
            )
            next_normal = _rotated(next_normal, turn, theta)
        frames.normals.append(next_normal)
        frames.binormals.append(cross3(frames.tangents[step], next_normal))
    if closed:
        var theta = acos(
            _clamp_unit(dot3(frames.normals[0], frames.normals[segments]))
        )
        theta /= Float64(segments)
        var twist = cross3(frames.normals[0], frames.normals[segments])
        if dot3(frames.tangents[0], twist) > 0:
            theta = -theta
        for step in range(1, segments + 1):  # pragma: no branch
            # One segment at least, so this runs.
            frames.normals[step] = _rotated(
                frames.normals[step],
                frames.tangents[step],
                theta * Float64(step),
            )
            frames.binormals[step] = cross3(
                frames.tangents[step], frames.normals[step]
            )
    return frames^


def frames_of[
    C: SpaceCurve
](
    curve: C,
    segments: Int,
    closed: Bool = False,
    arc_divisions: Int = ARC_LENGTH_DIVISIONS,
) raises -> FrenetFrames:
    """Return a frame at each of `segments + 1` equal steps along the
    curve by distance, three.js's `computeFrenetFrames`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The curve.
        segments: How many equal runs, one or more.
        closed: Whether to spread the twist so the last frame meets the
            first.
        arc_divisions: How many runs measure the length.

    Returns:
        The frames, rounded to floats.

    Raises:
        Error: If `segments` or `arc_divisions` is less than one, or the
            curve refuses a point.
    """
    return frames3_of(curve, segments, closed, arc_divisions).to_frenet_frames()


struct SpaceCurve3(SpaceCurve):
    """A `Curve3` used as a `SpaceCurve`: its points, and the tangent by
    three.js's base rule."""

    var curve: Curve3

    def __init__(out self, curve: Curve3):
        """Wrap a copy of a curve.

        Args:
            curve: The curve.
        """
        self.curve = curve.copy()

    def point3(self, t: Float64) raises -> Point3:
        """Return the point of the curve at `t`.

        Args:
            t: Where on the curve, from zero through one.

        Returns:
            The point, from the curve's floats.

        Raises:
            Error: If `t` falls outside zero through one.
        """
        var p = self.curve.point(Float32(t))
        return point3(Float64(p.x), Float64(p.y), Float64(p.z))

    def tangent3(self, t: Float64) raises -> Point3:
        """Return the unit chord about `t`, three.js's base `getTangent`.

        Args:
            t: Where on the curve, from zero through one.

        Returns:
            The direction.

        Raises:
            Error: If `t` falls far outside zero through one.
        """
        return chord_tangent(self, t)
