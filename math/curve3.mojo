# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A curve in space, from three.js `src/extras/curves/LineCurve3.js`,
`QuadraticBezierCurve3.js`, `CubicBezierCurve3.js`, `CatmullRomCurve3.js`,
the frames of `src/extras/core/Curve.js` and `CurvePath.js`.

`Curve3` is `math.curve.Curve` one dimension up, and for the same reason
one struct with a kind: a `CurvePath3` holds a list of one type. The four
kinds are three.js's four curves in space:

    LINE3          two points, and the straight run between them
    QUADRATIC3     a start, one control point and an end
    CUBIC3         a start, two control points and an end
    CATMULL_ROM3   any number of points, and a curve through every one

The parameters, the arc-length table and the exact tangents are the plane
curve's, and so are the reasons for them; see that module.

## Three kinds of Catmull-Rom

three.js's `CatmullRomCurve3` has a `curveType`, and here it is a
`CatmullRomType`. `CATMULLROM` is the uniform spline: the direction at a
point is `tension` times the run from the point before to the point after.
`CENTRIPETAL`, three.js's default, spaces the points by the square root
of the distance between them, and `CHORDAL` by the distance itself. That
stops the curve looping over itself where two points are close and the
next is far away, which the uniform spline does.

A spline that does not close has no point before its first or after its
last. three.js makes one up by reflecting the neighbor through the end. It
keeps both made-up points in the same scratch vector, so on a curve of two
points the second overwrites the first and the curve leaves its start
going backwards. Here each end has its own, and a curve of two points is
the straight run between them.

## Frames

`frenet_frames` is three.js's `computeFrenetFrames`: a tangent, a normal
and a binormal at equal steps along the curve by distance, carried from
one step to the next by parallel transport so they do not twist where the
curve merely bends. `transport_frames` does the carrying, and
`geometries.tube` builds its rings in the frames it returns.

## What is refused

A kind that does not exist, or a Catmull-Rom type that does not. Points
that do not match the kind, or that are all one point. A closed curve of
any kind but `CATMULL_ROM3`, since only three.js's `CatmullRomCurve3`
closes. A `t` or `u` outside zero through one. A tangent where the curve
turns back. Frames where two steps point straight opposite ways, which
leave no axis to turn about.
"""

from math.curve import ARC_DIVISIONS, SEGMENT_SAMPLES, u_to_t
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import acos, floor
from units.si import Angle, Length, METER, RADIAN

# Below this two tangents are parallel and there is no axis to turn the
# frame about. three.js compares the cross product against
# `Number.EPSILON`, a double's last bit; a `Float32` axis this short has no
# direction worth turning about.
comptime STRAIGHT = Float32(1e-4)

# three.js's guard against repeated points in a centripetal or chordal
# spline: a spacing under this between two points counts as none.
comptime REPEATED = Float32(1e-4)


@fieldwise_init
struct Curve3Kind(Equatable, ImplicitlyCopyable, Writable):
    """Which function a curve in space is, as a type rather than a bare
    int, for the reason `math.curve.CurveKind` is one."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four kinds there are.

        Returns:
            True for `LINE3`, `QUADRATIC3`, `CUBIC3` and `CATMULL_ROM3`.
        """
        return (
            self == LINE3
            or self == QUADRATIC3
            or self == CUBIC3
            or self == CATMULL_ROM3
        )

    def control_count(self) -> Int:
        """Return how many points a curve of this kind takes, or zero for
        `CATMULL_ROM3`, which takes any number from two up.

        Returns:
            Two for `LINE3`, three for `QUADRATIC3`, four for `CUBIC3` and
            zero for `CATMULL_ROM3`. Zero for a kind that is not valid,
            which `Curve3.__init__` has already refused.
        """
        if self == LINE3:
            return 2
        if self == QUADRATIC3:
            return 3
        if self == CUBIC3:
            return 4
        return 0


# A straight run from the first point to the second: three.js's
# `LineCurve3`.
comptime LINE3 = Curve3Kind(0)
# A Bezier with one control point: three.js's `QuadraticBezierCurve3`.
comptime QUADRATIC3 = Curve3Kind(1)
# A Bezier with two control points: three.js's `CubicBezierCurve3`.
comptime CUBIC3 = Curve3Kind(2)
# A Catmull-Rom spline through every point: three.js's `CatmullRomCurve3`.
comptime CATMULL_ROM3 = Curve3Kind(3)


@fieldwise_init
struct CatmullRomType(Equatable, ImplicitlyCopyable, Writable):
    """How a Catmull-Rom spline spaces its points, three.js's `curveType`,
    as a type rather than a string."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three types there are.

        Returns:
            True for `CENTRIPETAL`, `CHORDAL` and `CATMULLROM`.
        """
        return self == CENTRIPETAL or self == CHORDAL or self == CATMULLROM


# Points spaced by the square root of the distance between them: three.js's
# `'centripetal'`, and its default.
comptime CENTRIPETAL = CatmullRomType(0)
# Points spaced by the distance between them: three.js's `'chordal'`.
comptime CHORDAL = CatmullRomType(1)
# Points spaced evenly, with a tension: three.js's `'catmullrom'`.
comptime CATMULLROM = CatmullRomType(2)


@fieldwise_init
struct _Cubic(ImplicitlyCopyable):
    """One segment of a Catmull-Rom spline as a cubic in its own parameter,
    three.js's `CubicPoly` for all three components at once."""

    var c0: Vector3
    var c1: Vector3
    var c2: Vector3
    var c3: Vector3
    var weight: Float32

    def point(self) -> Vector3:
        """Return the cubic at `weight`, three.js's `calc`."""
        var t2 = self.weight * self.weight
        var t3 = t2 * self.weight
        return self.c0 + self.c1 * self.weight + self.c2 * t2 + self.c3 * t3

    def slope(self) -> Vector3:
        """Return the cubic's derivative at `weight`."""
        var t = self.weight
        return self.c1 + self.c2 * (2 * t) + self.c3 * (3 * t * t)


def _hermite(
    x0: Vector3, x1: Vector3, t0: Vector3, t1: Vector3, weight: Float32
) -> _Cubic:
    """Return the cubic from `x0` to `x1` leaving along `t0` and arriving
    along `t1`, three.js's `CubicPoly.init`."""
    return _Cubic(
        x0,
        t0,
        x0 * -3 + x1 * 3 - t0 * 2 - t1,
        x0 * 2 - x1 * 2 + t0 + t1,
        weight,
    )


def _over(v: Vector3, divisor: Float32) -> Vector3:
    """Return `v` divided by `divisor`, component by component, as three.js
    divides each coordinate."""
    return Vector3(v.x / divisor, v.y / divisor, v.z / divisor)


def _spacing(a: Vector3, b: Vector3, power: Float32) -> Float32:
    """Return the squared distance from `a` to `b` raised to `power`."""
    var gap = b - a
    return gap.dot(gap) ** power


struct Curve3(Copyable, Movable):
    """One curve in space: a kind, the points that kind reads, and for a
    Catmull-Rom spline whether it closes, its type and its tension."""

    var kind: Curve3Kind
    var points: List[Vector3]
    var closed: Bool
    var curve_type: CatmullRomType
    var tension: Float32

    def __init__(
        out self,
        kind: Curve3Kind,
        var points: List[Vector3],
        closed: Bool = False,
        curve_type: CatmullRomType = CENTRIPETAL,
        tension: Float32 = 0.5,
    ) raises:
        """Create a curve of `kind` through or around `points`.

        Args:
            kind: Which function the curve is.
            points: Its control points, in meters, in order.
            closed: True to join a Catmull-Rom spline's last point back to
                its first.
            curve_type: How a Catmull-Rom spline spaces its points.
            tension: How hard a `CATMULLROM` spline pulls toward its
                neighbors; three.js's default is one half.

        Raises:
            Error: If the kind or the type is not one there is, if the
                number of points does not match the kind, if every point
                is the same point, or if a curve that is not a Catmull-Rom
                spline is closed.
        """
        if not kind.is_valid():
            raise Error("A curve needs a kind that exists")
        if not curve_type.is_valid():
            raise Error("A Catmull-Rom curve needs a type that exists")
        var wanted = kind.control_count()
        if wanted == 0:
            if len(points) < 2:
                raise Error("A spline needs at least two points")
        elif len(points) != wanted:
            raise Error("A curve's points must match its kind")
        if closed and kind != CATMULL_ROM3:
            raise Error("Only a Catmull-Rom curve can close")
        var moved = False
        for index in range(1, len(points)):  # pragma: no branch
            # At least two points by the checks above, so this runs.
            var step = points[index] - points[0]
            if step.length() != 0:
                moved = True
        if not moved:
            raise Error("A curve needs two points that differ")
        self.kind = kind
        self.points = points^
        self.closed = closed
        self.curve_type = curve_type
        self.tension = tension

    def __init__(out self, *, copy: Self):
        """Copy another curve."""
        self.kind = copy.kind
        self.points = copy.points.copy()
        self.closed = copy.closed
        self.curve_type = copy.curve_type
        self.tension = copy.tension

    def segments(self) -> Int:
        """Return how many segments a Catmull-Rom spline has: one fewer
        than its points, or as many for a closed one.

        Returns:
            The segment count. For the other kinds it is the same count,
            which nothing reads.
        """
        if self.closed:
            return len(self.points)
        return len(self.points) - 1

    def _cubic(self, t: Float32) -> _Cubic:
        """Return the Catmull-Rom segment `t` falls in, as a cubic, three.js's
        `CatmullRomCurve3.getPoint` up to its last line."""
        var count = len(self.points)
        var p = Float32(self.segments()) * t
        var index = Int(floor(p))
        var weight = p - Float32(index)
        var p0: Vector3
        var p1: Vector3
        var p2: Vector3
        var p3: Vector3
        if self.closed:
            p0 = self.points[(index + count - 1) % count]
            p1 = self.points[index % count]
            p2 = self.points[(index + 1) % count]
            p3 = self.points[(index + 2) % count]
        else:
            if weight == 0 and index == count - 1:
                # The last point belongs to the segment before it.
                index = count - 2
                weight = 1
            p1 = self.points[index]
            p2 = self.points[index + 1]
            if index > 0:
                p0 = self.points[index - 1]
            else:
                p0 = (self.points[0] - self.points[1]) + self.points[0]
            if index + 2 < count:
                p3 = self.points[index + 2]
            else:
                p3 = (self.points[count - 1] - self.points[count - 2]) + (
                    self.points[count - 1]
                )
        if self.curve_type == CATMULLROM:
            return _hermite(
                p1,
                p2,
                (p2 - p0) * self.tension,
                (p3 - p1) * self.tension,
                weight,
            )
        var power = Float32(0.25)
        if self.curve_type == CHORDAL:
            power = 0.5
        var dt0 = _spacing(p0, p1, power)
        var dt1 = _spacing(p1, p2, power)
        var dt2 = _spacing(p2, p3, power)
        if dt1 < REPEATED:
            dt1 = 1
        if dt0 < REPEATED:
            dt0 = dt1
        if dt2 < REPEATED:
            dt2 = dt1
        # three.js's `initNonuniformCatmullRom`: the directions for a
        # parameter that runs over the spacing, then rescaled to run from
        # zero to one.
        var t1 = (
            _over(p1 - p0, dt0)
            - _over(p2 - p0, dt0 + dt1)
            + _over(p2 - p1, dt1)
        )
        var t2 = (
            _over(p2 - p1, dt1)
            - _over(p3 - p1, dt1 + dt2)
            + _over(p3 - p2, dt2)
        )
        return _hermite(p1, p2, t1 * dt1, t2 * dt1, weight)

    def point(self, t: Float32) raises -> Vector3:
        """Return the point at `t` along this curve's own parameter.

        Args:
            t: Where on the curve, from zero at the start to one at the
                end. It is not a distance; see `point_at`.

        Returns:
            The point, in meters.

        Raises:
            Error: If `t` falls outside zero through one.
        """
        if t < 0 or t > 1:
            raise Error("A curve's t must lie from zero through one")
        if self.kind == LINE3:
            # three.js's `LineCurve3.getPoint` returns the end itself at
            # one, rather than the start plus the whole run.
            if t == 1:
                return self.points[1]
            return (self.points[1] - self.points[0]) * t + self.points[0]
        var rest = 1 - t
        if self.kind == QUADRATIC3:
            return (
                self.points[0] * (rest * rest)
                + self.points[1] * (2 * rest * t)
                + self.points[2] * (t * t)
            )
        if self.kind == CUBIC3:
            return (
                self.points[0] * (rest * rest * rest)
                + self.points[1] * (3 * rest * rest * t)
                + self.points[2] * (3 * rest * t * t)
                + self.points[3] * (t * t * t)
            )
        return self._cubic(t).point()

    def _slope(self, t: Float32) -> Vector3:
        """Return how fast and which way the curve moves at `t`, before it
        is made unit length. The caller has checked `t` is on the curve."""
        if self.kind == LINE3:
            return self.points[1] - self.points[0]
        var rest = 1 - t
        if self.kind == QUADRATIC3:
            return (self.points[1] - self.points[0]) * (2 * rest) + (
                self.points[2] - self.points[1]
            ) * (2 * t)
        if self.kind == CUBIC3:
            return (
                (self.points[1] - self.points[0]) * (3 * rest * rest)
                + (self.points[2] - self.points[1]) * (6 * rest * t)
                + (self.points[3] - self.points[2]) * (3 * t * t)
            )
        return self._cubic(t).slope()

    def tangent(self, t: Float32) raises -> Vector3:
        """Return the unit direction the curve runs in at `t`, from the
        exact derivative, as `math.curve.Curve.tangent` gives it.

        Args:
            t: Where on the curve, from zero through one.

        Returns:
            The direction, of unit length.

        Raises:
            Error: If `t` falls outside zero through one, or if the curve
                stops at `t` and has no direction there.
        """
        if t < 0 or t > 1:
            raise Error("A curve's t must lie from zero through one")
        var slope = self._slope(t)
        if slope.length() == 0:
            raise Error("A curve has no direction where it turns back")
        slope.normalize()
        return slope

    def sample(self, divisions: Int) raises -> List[Vector3]:
        """Return `divisions + 1` points at equal steps in `t`, three.js's
        `getPoints`.

        Args:
            divisions: How many runs to cut the curve into; at least one.

        Returns:
            The points, first to last, in meters.

        Raises:
            Error: If `divisions` is less than one.
        """
        if divisions < 1:
            raise Error("A curve needs at least one division")
        var out = List[Vector3]()
        for index in range(divisions + 1):  # pragma: no branch
            # At least one division, so this runs.
            out.append(self.point(Float32(index) / Float32(divisions)))
        return out^

    def lengths(self, divisions: Int) raises -> List[Float32]:
        """Return how far along the curve each sample is, from zero,
        three.js's `getLengths`.

        Args:
            divisions: How many runs to cut the curve into; at least one.

        Returns:
            `divisions + 1` distances in meters, the first zero and the
            last the curve's whole length.

        Raises:
            Error: If `divisions` is less than one.
        """
        var samples = self.sample(divisions)
        var out = List[Float32]()
        out.append(0)
        for index in range(1, len(samples)):  # pragma: no branch
            # At least two samples, so this runs.
            var step = (samples[index] - samples[index - 1]).length()
            out.append(out[index - 1] + step)
        return out^

    def arc_divisions(self) -> Int:
        """Return how many straight runs stand in for this curve when its
        length is measured: `ARC_DIVISIONS`, or `SEGMENT_SAMPLES` for each
        segment of a Catmull-Rom spline if that is more.

        Returns:
            The number of runs, never fewer than `ARC_DIVISIONS`.
        """
        if self.kind == CATMULL_ROM3:
            var wanted = self.segments() * SEGMENT_SAMPLES
            if wanted > ARC_DIVISIONS:
                return wanted
        return ARC_DIVISIONS

    def arc_table(self) raises -> List[Float32]:
        """Return the table `point_at` reads: `lengths` at
        `arc_divisions`.

        Returns:
            The distances, in meters, from zero to the whole length.

        Raises:
            Error: If a sample falls outside the curve, which cannot
                happen for a curve that was constructed.
        """
        return self.lengths(self.arc_divisions())

    def length(self) raises -> Length:
        """Return how long the curve is, three.js's `getLength`.

        Returns:
            The length across the straight runs `arc_divisions` asks for,
            an approximation from below.

        Raises:
            Error: If a sample falls outside the curve, which cannot
                happen for a curve that was constructed.
        """
        var table = self.arc_table()
        return Length(table[len(table) - 1], METER)

    def point_at(self, u: Float32) raises -> Vector3:
        """Return the point `u` of the way along the curve by distance,
        three.js's `getPointAt`.

        Args:
            u: How far along by length, from zero through one.

        Returns:
            The point, in meters.

        Raises:
            Error: If `u` falls outside zero through one.
        """
        if u < 0 or u > 1:
            raise Error("A curve's u must lie from zero through one")
        return self.point(u_to_t(self.arc_table(), u))

    def tangent_at(self, u: Float32) raises -> Vector3:
        """Return the unit direction `u` of the way along the curve by
        distance, three.js's `getTangentAt`.

        Args:
            u: How far along by length, from zero through one.

        Returns:
            The direction, of unit length.

        Raises:
            Error: If `u` falls outside zero through one, or the curve
                stops there.
        """
        if u < 0 or u > 1:
            raise Error("A curve's u must lie from zero through one")
        return self.tangent(u_to_t(self.arc_table(), u))

    def spaced_points(self, divisions: Int) raises -> List[Vector3]:
        """Return `divisions + 1` points at equal distances along the
        curve, three.js's `getSpacedPoints`.

        Args:
            divisions: How many equal runs to cut the curve into; at least
                one.

        Returns:
            The points, first to last, in meters.

        Raises:
            Error: If `divisions` is less than one.
        """
        if divisions < 1:
            raise Error("A curve needs at least one division")
        var table = self.arc_table()
        var out = List[Vector3]()
        for index in range(divisions + 1):  # pragma: no branch
            # At least one division, so this runs.
            var u = Float32(index) / Float32(divisions)
            out.append(self.point(u_to_t(table, u)))
        return out^

    def frenet_frames(self, segments: Int, closed: Bool) raises -> FrenetFrames:
        """Return a frame at each of `segments + 1` equal steps along the
        curve by distance, three.js's `computeFrenetFrames`.

        Args:
            segments: How many equal runs to cut the curve into; at least
                one.
            closed: True to spread the twist the frames build up evenly
                back along the curve, so the last frame meets the first.

        Returns:
            The tangents, normals and binormals, `segments + 1` of each.

        Raises:
            Error: If `segments` is less than one, the curve stops at one
                of the steps, or two steps point straight opposite ways.
        """
        if segments < 1:
            raise Error("A curve needs at least one segment for frames")
        var table = self.arc_table()
        var tangents = List[Vector3]()
        for index in range(segments + 1):  # pragma: no branch
            # At least one segment, so this runs.
            var u = Float32(index) / Float32(segments)
            tangents.append(self.tangent(u_to_t(table, u)))
        return transport_frames(tangents, closed)


struct FrenetFrames(Copyable, Movable):
    """A tangent, a normal and a binormal at each step along a curve, each
    at right angles to the other two and of unit length."""

    var tangents: List[Vector3]
    var normals: List[Vector3]
    var binormals: List[Vector3]

    def __init__(out self):
        """Create an empty set of frames."""
        self.tangents = List[Vector3]()
        self.normals = List[Vector3]()
        self.binormals = List[Vector3]()

    def __init__(out self, *, copy: Self):
        """Copy another set of frames."""
        self.tangents = copy.tangents.copy()
        self.normals = copy.normals.copy()
        self.binormals = copy.binormals.copy()

    def count(self) -> Int:
        """Return how many frames there are.

        Returns:
            The number of steps, one more than the segments.
        """
        return len(self.tangents)


def _clamp_unit(value: Float32) -> Float32:
    """Return `value` held to minus one through one, for `acos`."""
    return max(Float32(-1), min(Float32(1), value))


def _turned(v: Vector3, axis: Vector3, angle: Float32) -> Vector3:
    """Return `v` turned about the unit `axis` by `angle` radians."""
    return Quaternion.from_axis_angle(axis, Angle(angle, RADIAN)).rotate(v)


def first_normal(tangent: Vector3) -> Vector3:
    """Return a direction at right angles to the first tangent, three.js's
    choice in `computeFrenetFrames`: the axis the tangent leans least
    along, crossed with the tangent twice.

    Args:
        tangent: The first tangent, of unit length.

    Returns:
        The first normal, of unit length.
    """
    var smallest = abs(tangent.x)
    var axis = Vector3(1, 0, 0)
    if abs(tangent.y) <= smallest:
        smallest = abs(tangent.y)
        axis = Vector3(0, 1, 0)
    if abs(tangent.z) <= smallest:
        axis = Vector3(0, 0, 1)
    var across = tangent
    across.cross(axis)
    across.normalize()
    var normal = tangent
    normal.cross(across)
    return normal


def transport_frames(
    tangents: List[Vector3], closed: Bool
) raises -> FrenetFrames:
    """Return the frames along a run of unit tangents, three.js's
    `computeFrenetFrames` after its tangents.

    Each normal is the last one turned about the axis between the last
    tangent and this one, by the angle between them, and each binormal is
    the tangent crossed with the normal. For a closed run, the twist that
    has built up between the first normal and the last is then spread
    evenly back along the run, each frame turned about its own tangent.

    Args:
        tangents: The unit tangents, at least two.
        closed: True to spread the twist so the last frame meets the first.

    Returns:
        A frame per tangent.

    Raises:
        Error: If there are fewer than two tangents, or two consecutive
            tangents point straight opposite ways, which leaves no axis to
            turn about and a half turn no rule decides.
    """
    var count = len(tangents)
    if count < 2:
        raise Error("Frames need at least two tangents")
    var last = count - 1
    var frames = FrenetFrames()
    frames.tangents = tangents.copy()
    frames.normals.append(first_normal(tangents[0]))
    var first_binormal = tangents[0]
    first_binormal.cross(frames.normals[0])
    frames.binormals.append(first_binormal)
    for ring in range(1, count):  # pragma: no branch
        # At least two tangents, so this runs.
        var normal = frames.normals[ring - 1]
        var axis = tangents[ring - 1]
        axis.cross(tangents[ring])
        if axis.length() > STRAIGHT:
            axis.normalize()
            var angle = acos(
                _clamp_unit(tangents[ring - 1].dot(tangents[ring]))
            )
            normal = _turned(normal, axis, angle)
        elif tangents[ring - 1].dot(tangents[ring]) < 0:
            raise Error("A curve's frames cannot fold straight back")
        var binormal = tangents[ring]
        binormal.cross(normal)
        frames.normals.append(normal)
        frames.binormals.append(binormal)

    if closed:
        var twist = acos(
            _clamp_unit(frames.normals[0].dot(frames.normals[last]))
        )
        twist /= Float32(last)
        var handed = frames.normals[0]
        handed.cross(frames.normals[last])
        if tangents[0].dot(handed) > 0:
            twist = -twist
        for ring in range(1, count):  # pragma: no branch
            # At least two tangents, so this runs.
            frames.normals[ring] = _turned(
                frames.normals[ring], tangents[ring], twist * Float32(ring)
            )
            var binormal = tangents[ring]
            binormal.cross(frames.normals[ring])
            frames.binormals[ring] = binormal
    return frames^


def line3(start: Vector3, end: Vector3) raises -> Curve3:
    """Return the straight run from `start` to `end`, three.js's
    `LineCurve3`.

    Args:
        start: Where the run begins, in meters.
        end: Where it ends, in meters.

    Returns:
        A `LINE3` curve.

    Raises:
        Error: If the two points are the same point.
    """
    return Curve3(LINE3, [start, end])


def quadratic_bezier3(
    start: Vector3, control: Vector3, end: Vector3
) raises -> Curve3:
    """Return a Bezier curve in space with one control point, three.js's
    `QuadraticBezierCurve3`.

    Args:
        start: Where the curve begins, in meters.
        control: The point the curve is pulled toward, in meters.
        end: Where the curve ends, in meters.

    Returns:
        A `QUADRATIC3` curve.

    Raises:
        Error: If all three points are the same point.
    """
    return Curve3(QUADRATIC3, [start, control, end])


def cubic_bezier3(
    start: Vector3, first: Vector3, second: Vector3, end: Vector3
) raises -> Curve3:
    """Return a Bezier curve in space with two control points, three.js's
    `CubicBezierCurve3`.

    Args:
        start: Where the curve begins, in meters.
        first: The point the start is pulled toward, in meters.
        second: The point the end is pulled toward, in meters.
        end: Where the curve ends, in meters.

    Returns:
        A `CUBIC3` curve.

    Raises:
        Error: If all four points are the same point.
    """
    return Curve3(CUBIC3, [start, first, second, end])


def catmull_rom3(
    var points: List[Vector3],
    closed: Bool = False,
    curve_type: CatmullRomType = CENTRIPETAL,
    tension: Float32 = 0.5,
) raises -> Curve3:
    """Return a Catmull-Rom spline in space through every point, three.js's
    `CatmullRomCurve3`.

    Args:
        points: The points the curve passes through, in meters, at least
            two of them.
        closed: True to join the last point back to the first.
        curve_type: How the spline spaces its points.
        tension: How hard a `CATMULLROM` spline pulls toward its neighbors.

    Returns:
        A `CATMULL_ROM3` curve.

    Raises:
        Error: If there are fewer than two points, every point is the same
            point, or the type is not one there is.
    """
    return Curve3(CATMULL_ROM3, points^, closed, curve_type, tension)


@fieldwise_init
struct _Place(ImplicitlyCopyable):
    """Which curve of a path, and how far along it by its own distance."""

    var curve: Int
    var u: Float32


struct CurvePath3(Copyable, Movable):
    """A run of curves in space, three.js's `CurvePath` of 3D curves.

    As in three.js, nothing makes one curve start where the last ended. The
    point at `t` is found by distance across the whole run, so a gap
    between two curves is jumped rather than measured.
    """

    var curves: List[Curve3]

    def __init__(out self):
        """Create a path with no curves on it."""
        self.curves = List[Curve3]()

    def __init__(out self, *, copy: Self):
        """Copy another path."""
        self.curves = copy.curves.copy()

    def add(mut self, var curve: Curve3):
        """Add `curve` to the end of the path.

        Args:
            curve: The next curve.
        """
        self.curves.append(curve^)

    def curve_count(self) -> Int:
        """Return how many curves the path is made of.

        Returns:
            The number of curves.
        """
        return len(self.curves)

    def _need_curves(self) raises:
        """Raise unless the path has a curve on it.

        Raises:
            Error: If the path has no curves.
        """
        if len(self.curves) == 0:
            raise Error("A curve path with no curves has no points")

    def close_path(mut self) raises:
        """Add the straight run from the end of the last curve back to the
        start of the first, three.js's `closePath`.

        Raises:
            Error: If the path has no curves, or already ends where it
                starts.
        """
        self._need_curves()
        var start = self.curves[0].point(0)
        var end = self.curves[len(self.curves) - 1].point(1)
        if (end - start).length() == 0:
            raise Error("A curve path that is closed cannot close again")
        self.curves.append(line3(end, start))

    def curve_lengths(self) raises -> List[Float32]:
        """Return how far along the path each curve ends, three.js's
        `getCurveLengths`.

        Returns:
            One running total per curve, in meters.

        Raises:
            Error: If the path has no curves.
        """
        self._need_curves()
        var out = List[Float32]()
        var total = Float32(0)
        for index in range(len(self.curves)):  # pragma: no branch
            # At least one curve, so this runs.
            total += self.curves[index].length().to(METER)
            out.append(total)
        return out^

    def length(self) raises -> Length:
        """Return how long the whole path is.

        Returns:
            The sum of its curves' lengths.

        Raises:
            Error: If the path has no curves.
        """
        var lengths = self.curve_lengths()
        return Length(lengths[len(lengths) - 1], METER)

    def _locate(self, t: Float32) raises -> _Place:
        """Find which curve holds the point `t` of the way along the path
        by distance, and how far along that curve by its own distance,
        three.js's `CurvePath.getPoint` before its last line.

        Raises:
            Error: If the path has no curves, or `t` falls outside zero
                through one.
        """
        if t < 0 or t > 1:
            raise Error("A curve path's t must lie from zero through one")
        var lengths = self.curve_lengths()
        var last = len(lengths) - 1
        var target = t * lengths[last]
        var curve = last
        for index in range(len(lengths)):  # pragma: no branch
            # At least one curve, and the last total is at least the
            # target, so this runs and breaks.
            if lengths[index] >= target:
                curve = index
                break
        var span = self.curves[curve].length().to(METER)
        var u = 1 - (lengths[curve] - target) / span
        return _Place(curve, max(Float32(0), min(Float32(1), u)))

    def point(self, t: Float32) raises -> Vector3:
        """Return the point `t` of the way along the path by distance,
        three.js's `CurvePath.getPoint`.

        Args:
            t: How far along the whole path, from zero through one.

        Returns:
            The point, in meters.

        Raises:
            Error: If the path has no curves, or `t` falls outside zero
                through one.
        """
        var place = self._locate(t)
        return self.curves[place.curve].point_at(place.u)

    def tangent(self, t: Float32) raises -> Vector3:
        """Return the unit direction `t` of the way along the path by
        distance, from the curve that holds that point.

        Args:
            t: How far along the whole path, from zero through one.

        Returns:
            The direction, of unit length.

        Raises:
            Error: If the path has no curves, `t` falls outside zero
                through one, or the curve stops there.
        """
        var place = self._locate(t)
        return self.curves[place.curve].tangent_at(place.u)

    def sample(self, divisions: Int) raises -> List[Vector3]:
        """Return the path as points, three.js's `CurvePath.getPoints`.

        A straight run is one run whatever `divisions` says, and every
        other curve is `divisions` runs. A point the same as the one before
        it, as where one curve meets the next, is left out.

        Args:
            divisions: How many runs to cut each curve that is not a
                straight run into; at least one.

        Returns:
            The points, in meters.

        Raises:
            Error: If the path has no curves, or `divisions` is less than
                one.
        """
        self._need_curves()
        if divisions < 1:
            raise Error("A curve path needs at least one division")
        var out = List[Vector3]()
        for index in range(len(self.curves)):  # pragma: no branch
            # At least one curve, so this runs.
            var runs = divisions
            if self.curves[index].kind == LINE3:
                runs = 1
            var piece = self.curves[index].sample(runs)
            for step in range(len(piece)):  # pragma: no branch
                # At least two points in a piece, so this runs.
                var here = piece[step]
                if len(out) > 0 and (here - out[len(out) - 1]).length() == 0:
                    continue
                out.append(here)
        return out^

    def spaced_points(self, divisions: Int) raises -> List[Vector3]:
        """Return `divisions + 1` points at equal distances along the path,
        three.js's `CurvePath.getSpacedPoints`.

        Args:
            divisions: How many equal runs to cut the path into; at least
                one.

        Returns:
            The points, first to last, in meters.

        Raises:
            Error: If the path has no curves, or `divisions` is less than
                one.
        """
        self._need_curves()
        if divisions < 1:
            raise Error("A curve path needs at least one division")
        var out = List[Vector3]()
        for index in range(divisions + 1):  # pragma: no branch
            # At least one division, so this runs.
            out.append(self.point(Float32(index) / Float32(divisions)))
        return out^

    def frenet_frames(self, segments: Int, closed: Bool) raises -> FrenetFrames:
        """Return a frame at each of `segments + 1` equal steps along the
        path by distance, three.js's `computeFrenetFrames`.

        Args:
            segments: How many equal runs to cut the path into; at least
                one.
            closed: True to spread the twist so the last frame meets the
                first.

        Returns:
            The tangents, normals and binormals, `segments + 1` of each.

        Raises:
            Error: If the path has no curves, `segments` is less than one,
                a curve stops at one of the steps, or two steps point
                straight opposite ways.
        """
        if segments < 1:
            raise Error("A curve path needs at least one segment for frames")
        var tangents = List[Vector3]()
        for index in range(segments + 1):  # pragma: no branch
            # At least one segment, so this runs.
            tangents.append(self.tangent(Float32(index) / Float32(segments)))
        return transport_frames(tangents, closed)
