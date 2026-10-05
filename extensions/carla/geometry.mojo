# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""OpenDRIVE plan-view geometry, from CARLA's `road/element/Geometry.cpp`.

A road's reference line is a chain of records. Each record starts at a
point with a heading and runs for a length. A line keeps its heading. An
arc turns at a fixed curvature. A spiral (a clothoid) changes its
curvature at a fixed rate. A poly3 is a cubic v(u) in the record's own
frame. A paramPoly3 is a pair of cubics u(p) and v(p).

The frame is OpenDRIVE's: right-handed, x east, y north, heading counter-
clockwise from x. `DirectedPoint.to_carla` applies CARLA's flip of y.

`RoadGeometry.distance_to` is each record's `DistanceTo`, which
`Road::GetNearestPoint` reads. CARLA measures a line and an arc for real.
Its spiral returns the offset from the start, and its poly3 and paramPoly3
return the start itself. This port keeps those answers, since they are
what CARLA's nearest-point search sees.

CARLA evaluates a spiral with the odrSpiral Fresnel code. This port
integrates the same clothoid with Gauss-Legendre quadrature instead, which
also holds when the start and end curvatures are equal. The poly3 and
paramPoly3 records keep CARLA's sampled tables and its linear
interpolation between samples. Lane orientation differentiates that
position interpolation and its offset-frame heading separately. A sampled
heading need not be the direction of the position chord.
"""

from extensions.carla.math import (
    distance_arc_to_point,
    distance_segment_to_point,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.vector3 import Vector3
from std.math import atan, atan2, ceil, cos, isfinite, sin, sqrt
from units.si import (
    DEGREE,
    PER_METER,
    RADIAN,
    Angle,
    InverseLength,
    Length,
    METER,
)


@fieldwise_init
struct RoadGeometryKind(Equatable, ImplicitlyCopyable, Writable):
    """Which OpenDRIVE record a `RoadGeometry` is, `GeometryType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the five records."""
        return self.value >= 0 and self.value <= 4


# A straight segment.
comptime LINE = RoadGeometryKind(0)
# A segment of constant curvature.
comptime ARC = RoadGeometryKind(1)
# A clothoid: the curvature changes linearly with length.
comptime SPIRAL = RoadGeometryKind(2)
# A cubic v(u) in the record's frame.
comptime POLY3 = RoadGeometryKind(3)
# Two cubics, u(p) and v(p).
comptime PARAM_POLY3 = RoadGeometryKind(4)


@fieldwise_init
struct ParamPoly3Range(Equatable, ImplicitlyCopyable, Writable):
    """What p runs over in a paramPoly3, OpenDRIVE's `pRange`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `ARC_LENGTH` or `NORMALIZED`."""
        return self == ARC_LENGTH or self == NORMALIZED


# p runs from 0 to the record's length, in meters.
comptime ARC_LENGTH = ParamPoly3Range(0)
# p runs from 0 to 1.
comptime NORMALIZED = ParamPoly3Range(1)


struct DirectedPoint(ImplicitlyCopyable):
    """A point on a reference line and the heading there."""

    # East, north and up, in meters.
    var x: Float64
    var y: Float64
    var z: Float64
    # Counter-clockwise from plus x, in radians.
    var tangent: Float64
    # The slope of the elevation there, as CARLA keeps it: the tangent of
    # the elevation cubic, which CARLA then reads as radians.
    var pitch: Float64

    def __init__(
        out self,
        x: Float64,
        y: Float64,
        z: Float64,
        tangent: Float64,
        pitch: Float64 = 0.0,
    ):
        """Create a directed point.

        Args:
            x: East, in meters.
            y: North, in meters.
            z: Up, in meters.
            tangent: The heading, in radians.
            pitch: The elevation slope.
        """
        self.x = x
        self.y = y
        self.z = z
        self.tangent = tangent
        self.pitch = pitch

    def apply_lateral_offset(mut self, offset: Length):
        """Move the point sideways, `DirectedPoint::ApplyLateralOffset`.

        Args:
            offset: How far to move. Plus is to the right of the heading.
        """
        var t = Float64(offset.value)
        self.x += t * sin(self.tangent)
        self.y -= t * cos(self.tangent)

    def heading(self) -> Angle:
        """Return the heading as an angle.

        Returns:
            The tangent, counter-clockwise from plus x.
        """
        return Angle(Float32(self.tangent), RADIAN)

    def to_carla(self) -> CarlaTransform:
        """Return the point in CARLA's frame, as `Lane::ComputeTransform`.

        CARLA negates y and the heading, to turn OpenDRIVE's
        right-handed frame into its own left-handed one.

        Returns:
            A transform with yaw set and pitch and roll zero.
        """
        var yaw = Angle(Float32(-self.tangent), RADIAN)
        return CarlaTransform(
            Length(Float32(self.x), METER),
            Length(Float32(-self.y), METER),
            Length(Float32(self.z), METER),
            CarlaRotation(Angle(0.0, DEGREE), yaw, Angle(0.0, DEGREE)),
        )


@fieldwise_init
struct _Sample(Copyable, ImplicitlyCopyable):
    var u: Float64
    var v: Float64
    var s: Float64
    var tu: Float64
    var tv: Float64


struct RoadGeometry(Copyable, Movable):
    """One plan-view record of a reference line."""

    var kind: RoadGeometryKind
    # Where the record starts along the road, in meters.
    var s: Float64
    # The start point, in meters, and the start heading, in radians.
    var x: Float64
    var y: Float64
    var heading: Float64
    # The record's length along the line, in meters.
    var length: Float64
    # An arc's curvature, or a spiral's start and end curvature, per meter.
    var curvature_start: Float64
    var curvature_end: Float64
    # A poly3 uses `u_poly` as v(u). A paramPoly3 uses both.
    var u_poly: CubicPolynomial
    var v_poly: CubicPolynomial
    var samples: List[_Sample]

    def __init__(
        out self,
        kind: RoadGeometryKind,
        s: Length,
        x: Length,
        y: Length,
        heading: Angle,
        length: Length,
    ) raises:
        """Create the common part of a record. Use the helpers below.

        Args:
            kind: Which record this is.
            s: Where it starts along the road.
            x: Start east.
            y: Start north.
            heading: Start heading, counter-clockwise from plus x.
            length: Length along the line. It must be positive.

        Raises:
            Error: If `kind` is not valid, `s` is negative, or `length`
                is not positive.
        """
        self = RoadGeometry(
            kind,
            Float64(s.value),
            Float64(x.value),
            Float64(y.value),
            Float64(heading.value),
            Float64(length.value),
        )

    def __init__(
        out self,
        kind: RoadGeometryKind,
        s: Float64,
        x: Float64,
        y: Float64,
        heading: Float64,
        length: Float64,
    ) raises:
        """Create the common part of a record from CARLA's doubles.

        `MapBuilder` keeps s, the heading and the length in double
        precision. This form keeps them too.

        Args:
            kind: Which record this is.
            s: Where it starts along the road, in meters.
            x: Start east, in meters.
            y: Start north, in meters.
            heading: Start heading, in radians.
            length: Length along the line, in meters. It must be positive.

        Raises:
            Error: If `kind` is not valid, `s` is negative, or `length`
                is not positive.
        """
        if not kind.is_valid():
            raise Error("Road geometry kind is not valid")
        if s < 0.0:
            raise Error("A road geometry cannot start before s = 0")
        if not (length > 0.0):
            raise Error("A road geometry needs a positive length")
        self.kind = kind
        self.s = s
        self.x = x
        self.y = y
        self.heading = heading
        self.length = length
        self.curvature_start = 0.0
        self.curvature_end = 0.0
        self.u_poly = CubicPolynomial.constant(0.0)
        self.v_poly = CubicPolynomial.constant(0.0)
        self.samples = List[_Sample]()

    def end_s(self) -> Float64:
        """Return where the record ends along the road.

        Returns:
            `s` plus `length`, in meters.
        """
        return self.s + self.length

    def pos_from_dist(self, dist: Length) -> DirectedPoint:
        """Return the point `dist` into the record, `PosFromDist`.

        Args:
            dist: Distance from the record's start. It is clamped to the
                record.

        Returns:
            The point and heading, with z zero.
        """
        return self.pos_at(Float64(dist.value))

    def pos_at(self, dist: Float64) -> DirectedPoint:
        """Return the point `dist` meters into the record, in double.

        Args:
            dist: Distance from the record's start, in meters. It is
                clamped to the record.

        Returns:
            The point and heading, with z zero.
        """
        var d = min(max(dist, 0.0), self.length)
        if self.kind == LINE:
            return DirectedPoint(
                self.x + d * cos(self.heading),
                self.y + d * sin(self.heading),
                0.0,
                self.heading,
            )
        if self.kind == ARC:
            return self._arc(d)
        if self.kind == SPIRAL:
            return self._spiral(d)
        return self._sampled(d)

    def distance_to(self, point: Vector3) -> Tuple[Float32, Float32]:
        """Return CARLA's `Geometry::DistanceTo` for a point.

        A line gives the distance along it to the foot of the point and
        the distance in plan from the point to that foot. An arc gives
        the same with CARLA's arc search. A spiral, a poly3 and a
        paramPoly3 give what CARLA gives; see the module docstring.

        Args:
            point: The point, in the frame CARLA passes: x, y and z in
                meters.

        Returns:
            The pair CARLA returns, in meters.
        """
        var start = Vector3(Float32(self.x), Float32(self.y), 0)
        if self.kind == LINE:
            var end = self.pos_at(self.length)
            var d = distance_segment_to_point(
                point, start, Vector3(Float32(end.x), Float32(end.y), 0)
            )
            return (d[0].value, d[1].value)
        if self.kind == ARC:
            var d = distance_arc_to_point(
                point,
                start,
                Length(Float32(self.length), METER),
                Angle(Float32(self.heading), RADIAN),
                InverseLength(Float32(self.curvature_start), PER_METER),
            )
            return (d[0].value, d[1].value)
        if self.kind == SPIRAL:
            return (point.x - start.x, point.y - start.y)
        return (start.x, start.y)

    def _arc(self, d: Float64) -> DirectedPoint:
        var radius = 1.0 / self.curvature_start
        comptime half_pi = 1.5707963267948966
        var x = self.x + radius * cos(self.heading + half_pi)
        var y = self.y + radius * sin(self.heading + half_pi)
        var tangent = self.heading + d * self.curvature_start
        x -= radius * cos(tangent + half_pi)
        y -= radius * sin(tangent + half_pi)
        return DirectedPoint(x, y, 0.0, tangent)

    def _spiral(self, d: Float64) -> DirectedPoint:
        var k0 = self.curvature_start
        var rate = (self.curvature_end - self.curvature_start) / self.length
        var reach = max(abs(k0), abs(k0 + rate * d))
        var pieces = 1 + Int(ceil(d * (1.0 + reach)))
        var step = d / Float64(pieces)
        var nodes = materialize[_GL_NODES]()
        var weights = materialize[_GL_WEIGHTS]()
        var x = self.x
        var y = self.y
        for piece in range(pieces):  # pragma: no branch
            var start = step * Float64(piece)
            for i in range(5):  # pragma: no branch
                var t = start + step * 0.5 * (1.0 + nodes[i])
                var theta = self.heading + t * (k0 + 0.5 * rate * t)
                x += step * 0.5 * weights[i] * cos(theta)
                y += step * 0.5 * weights[i] * sin(theta)
        return DirectedPoint(
            x, y, 0.0, self.heading + d * (k0 + 0.5 * rate * d)
        )

    def _derivative_at(
        self, distance: Float64
    ) raises -> Tuple[Float64, Float64, Float64]:
        # Differentiate the evaluated position AND the offset frame. In a
        # sampled record its interpolated heading is not its chord heading.
        if not self.kind.is_valid():
            raise Error("Road geometry kind is not valid")
        if not isfinite(distance) or not isfinite(self.heading):
            raise Error("Lane geometry needs finite distance and heading")
        if not isfinite(self.length) or self.length <= 0.0:
            raise Error("Lane geometry needs a finite positive length")
        if distance < 0.0 or distance > self.length:
            return (0.0, 0.0, 0.0)
        var d = distance
        if self.kind == LINE:
            return (cos(self.heading), sin(self.heading), 0.0)
        if not isfinite(self.curvature_start) or not isfinite(
            self.curvature_end
        ):
            raise Error("Lane geometry needs finite curvature")
        if self.kind == ARC:
            if self.curvature_start == 0.0:
                raise Error("An arc needs nonzero curvature")
            var theta = self.heading + d * self.curvature_start
            return (cos(theta), sin(theta), self.curvature_start)
        if self.kind == SPIRAL:
            var k0 = self.curvature_start
            var rate = (self.curvature_end - k0) / self.length
            var reach = max(abs(k0), abs(k0 + rate * d))
            var work = ceil(d * (1.0 + reach))
            if not isfinite(work) or work >= 9223372036854775807.0:
                raise Error("Spiral derivative work is not representable")
            var pieces = 1 + Int(work)
            var step = d / Float64(pieces)
            var dstep = 1.0 / Float64(pieces)
            var nodes = materialize[_GL_NODES]()
            var weights = materialize[_GL_WEIGHTS]()
            var dx = 0.0
            var dy = 0.0
            # Hold the selected quadrature partition fixed. At a partition
            # transition this is the derivative of the selected side.
            for piece in range(pieces):  # pragma: no branch
                var start = step * Float64(piece)
                var dstart = dstep * Float64(piece)
                for i in range(5):  # pragma: no branch
                    var t = start + step * 0.5 * (1.0 + nodes[i])
                    var dt = dstart + dstep * 0.5 * (1.0 + nodes[i])
                    var theta = self.heading + t * (k0 + 0.5 * rate * t)
                    var dtheta = dt * (k0 + rate * t)
                    var factor = step * 0.5 * weights[i]
                    var dfactor = dstep * 0.5 * weights[i]
                    dx += dfactor * cos(theta) - factor * sin(theta) * dtheta
                    dy += dfactor * sin(theta) + factor * cos(theta) * dtheta
            return (dx, dy, k0 + rate * d)
        if len(self.samples) < 2:
            raise Error("A sampled lane geometry needs two samples")
        var lo = 0
        var hi = len(self.samples) - 1
        while hi - lo > 1:
            var mid = (lo + hi) // 2
            if self.samples[mid].s < d:
                lo = mid
            else:
                hi = mid
        var one = self.samples[lo]
        var two = self.samples[hi]
        var span = two.s - one.s
        if not isfinite(span) or span <= 0.0:
            raise Error("A sampled lane interval needs finite positive length")
        var fraction = (two.s - d) / span
        var tu = fraction * one.tu + (1.0 - fraction) * two.tu
        var tv = fraction * one.tv + (1.0 - fraction) * two.tv
        var du = (two.u - one.u) / span
        var dv = (two.v - one.v) / span
        var dtu = (two.tu - one.tu) / span
        var dtv = (two.tv - one.tv) / span
        var scale = max(1.0, abs(tv))
        var u = 1.0 / scale
        var v = tv / scale
        var turn = (dtv / scale) * u / (u * u + v * v)
        if self.kind == PARAM_POLY3:
            scale = max(abs(tu), abs(tv))
            if not isfinite(scale) or scale == 0.0:
                raise Error("A sampled lane offset frame has no heading")
            u = tu / scale
            v = tv / scale
            turn = (u * (dtv / scale) - v * (dtu / scale)) / (u * u + v * v)
        var c = cos(self.heading)
        var sn = sin(self.heading)
        return (du * c - dv * sn, du * sn + dv * c, turn)

    def _sampled(self, d: Float64) -> DirectedPoint:
        # The first segment whose end reaches d. CARLA finds the same one
        # as the nearest segment in an R-tree.
        var lo = 0
        var hi = len(self.samples) - 1
        while hi - lo > 1:
            var mid = (lo + hi) // 2
            if self.samples[mid].s < d:
                lo = mid
            else:
                hi = mid
        var one = self.samples[lo]
        var two = self.samples[hi]
        var rate = (two.s - d) / (two.s - one.s)
        var u = rate * one.u + (1.0 - rate) * two.u
        var v = rate * one.v + (1.0 - rate) * two.v
        var tu = rate * one.tu + (1.0 - rate) * two.tu
        var tv = rate * one.tv + (1.0 - rate) * two.tv
        var tangent = atan(tv)
        if self.kind == PARAM_POLY3:
            tangent = atan2(tv, tu)
        var c = cos(self.heading)
        var s = sin(self.heading)
        return DirectedPoint(
            self.x + u * c - v * s,
            self.y + v * c + u * s,
            0.0,
            self.heading + tangent,
        )


# Five-point Gauss-Legendre nodes and weights on [-1, 1].
comptime _GL_NODES: Array[Float64, 5] = [
    -0.9061798459386640,
    -0.5384693101056831,
    0.0,
    0.5384693101056831,
    0.9061798459386640,
]
comptime _GL_WEIGHTS: Array[Float64, 5] = [
    0.2369268850561891,
    0.4786286704993665,
    0.5688888888888889,
    0.4786286704993665,
    0.2369268850561891,
]


def line(
    s: Length, x: Length, y: Length, heading: Angle, length: Length
) raises -> RoadGeometry:
    """Return a straight record, `GeometryLine`.

    Args:
        s: Where it starts along the road.
        x: Start east.
        y: Start north.
        heading: The heading, counter-clockwise from plus x.
        length: Its length. It must be positive.

    Returns:
        The record.

    Raises:
        Error: If `s` is negative or `length` is not positive.
    """
    return RoadGeometry(LINE, s, x, y, heading, length)


def arc(
    s: Length,
    x: Length,
    y: Length,
    heading: Angle,
    length: Length,
    curvature: InverseLength,
) raises -> RoadGeometry:
    """Return a record of constant curvature, `GeometryArc`.

    Args:
        s: Where it starts along the road.
        x: Start east.
        y: Start north.
        heading: Start heading, counter-clockwise from plus x.
        length: Its length. It must be positive.
        curvature: One over the radius. Plus turns left.

    Returns:
        The record.

    Raises:
        Error: If `s` is negative, `length` is not positive, or the
            curvature is zero.
    """
    return with_arc(
        RoadGeometry(ARC, s, x, y, heading, length), Float64(curvature.value)
    )


def with_arc(var base: RoadGeometry, curvature: Float64) raises -> RoadGeometry:
    """Make a record an arc, `GeometryArc`, from CARLA's double.

    Args:
        base: The common part: start, heading and length.
        curvature: One over the radius, per meter. Plus turns left.

    Returns:
        The record, now an arc.

    Raises:
        Error: If the curvature is zero.
    """
    if curvature == 0.0:
        raise Error("An arc needs a curvature other than zero; use a line")
    base.kind = ARC
    base.curvature_start = curvature
    base.curvature_end = curvature
    return base^


def spiral(
    s: Length,
    x: Length,
    y: Length,
    heading: Angle,
    length: Length,
    curvature_start: InverseLength,
    curvature_end: InverseLength,
) raises -> RoadGeometry:
    """Return a clothoid record, `GeometrySpiral`.

    Args:
        s: Where it starts along the road.
        x: Start east.
        y: Start north.
        heading: Start heading, counter-clockwise from plus x.
        length: Its length. It must be positive.
        curvature_start: The curvature at the start. Plus turns left.
        curvature_end: The curvature at the end.

    Returns:
        The record.

    Raises:
        Error: If `s` is negative or `length` is not positive.
    """
    return with_spiral(
        RoadGeometry(SPIRAL, s, x, y, heading, length),
        Float64(curvature_start.value),
        Float64(curvature_end.value),
    )


def with_spiral(
    var base: RoadGeometry, curvature_start: Float64, curvature_end: Float64
) -> RoadGeometry:
    """Make a record a clothoid, `GeometrySpiral`, from CARLA's doubles.

    Args:
        base: The common part: start, heading and length.
        curvature_start: The curvature at the start, per meter.
        curvature_end: The curvature at the end, per meter.

    Returns:
        The record, now a spiral.
    """
    base.kind = SPIRAL
    base.curvature_start = curvature_start
    base.curvature_end = curvature_end
    return base^


def poly3(
    s: Length,
    x: Length,
    y: Length,
    heading: Angle,
    length: Length,
    a: Float64,
    b: Float64,
    c: Float64,
    d: Float64,
) raises -> RoadGeometry:
    """Return a cubic record v(u), `GeometryPoly3`.

    The table samples u every 0.3 meters, as CARLA's `PreComputeSpline`.

    Args:
        s: Where it starts along the road.
        x: Start east.
        y: Start north.
        heading: The direction of plus u.
        length: Its length along the curve. It must be positive.
        a: The constant term of v, in meters.
        b: The linear term.
        c: The quadratic term, per meter.
        d: The cubic term, per square meter.

    Returns:
        The record.

    Raises:
        Error: If `s` is negative or `length` is not positive.
    """
    return with_poly3(RoadGeometry(POLY3, s, x, y, heading, length), a, b, c, d)


def with_poly3(
    var base: RoadGeometry, a: Float64, b: Float64, c: Float64, d: Float64
) -> RoadGeometry:
    """Make a record a cubic v(u), `GeometryPoly3`, and sample it.

    Args:
        base: The common part: start, heading and length.
        a: The constant term of v, in meters.
        b: The linear term.
        c: The quadratic term, per meter.
        d: The cubic term, per square meter.

    Returns:
        The record, now a poly3 with its table.
    """
    base.kind = POLY3
    base.u_poly = CubicPolynomial(a, b, c, d, 0.0)
    base.samples.clear()
    comptime delta_u = 0.3
    var u = 0.0
    var total = 0.0
    var last = _Sample(
        0.0, base.u_poly.evaluate(0.0), 0.0, 1.0, base.u_poly.tangent(0.0)
    )
    base.samples.append(last)
    while total < base.length + delta_u:
        u += delta_u
        var v = base.u_poly.evaluate(u)
        var du = u - last.u
        var dv = v - last.v
        total += sqrt(du * du + dv * dv)
        last = _Sample(u, v, total, 1.0, base.u_poly.tangent(u))
        base.samples.append(last)
    return base^


def param_poly3(
    s: Length,
    x: Length,
    y: Length,
    heading: Angle,
    length: Length,
    u: CubicPolynomial,
    v: CubicPolynomial,
    p_range: ParamPoly3Range,
) raises -> RoadGeometry:
    """Return a parametric cubic record, `GeometryParamPoly3`.

    The table has one interval per 0.5 meters and at least five, as
    CARLA's `PreComputeSpline`.

    Args:
        s: Where it starts along the road.
        x: Start east.
        y: Start north.
        heading: The direction of plus u.
        length: Its length along the curve. It must be positive.
        u: The cubic u(p), in meters.
        v: The cubic v(p), in meters.
        p_range: What p runs over.

    Returns:
        The record.

    Raises:
        Error: If `s` is negative, `length` is not positive, `p_range` is
            not valid, or the curve does not move.
    """
    return with_param_poly3(
        RoadGeometry(PARAM_POLY3, s, x, y, heading, length), u, v, p_range
    )


def with_param_poly3(
    var base: RoadGeometry,
    u: CubicPolynomial,
    v: CubicPolynomial,
    p_range: ParamPoly3Range,
) raises -> RoadGeometry:
    """Make a record a parametric cubic, `GeometryParamPoly3`, and sample it.

    Args:
        base: The common part: start, heading and length.
        u: The cubic u(p), in meters.
        v: The cubic v(p), in meters.
        p_range: What p runs over.

    Returns:
        The record, now a paramPoly3 with its table.

    Raises:
        Error: If `p_range` is not valid, or the curve does not move.
    """
    if not p_range.is_valid():
        raise Error("paramPoly3 range is not valid")
    base.kind = PARAM_POLY3
    base.u_poly = u
    base.v_poly = v
    base.samples.clear()
    var intervals = max(Int(base.length / 0.5), 5)
    var delta_p = 1.0 / Float64(intervals)
    if p_range == ARC_LENGTH:
        delta_p *= base.length
    var p = 0.0
    var last = _Sample(
        u.evaluate(0.0), v.evaluate(0.0), 0.0, u.tangent(0.0), v.tangent(0.0)
    )
    base.samples.append(last)
    for _ in range(intervals):  # pragma: no branch
        p += delta_p
        var pu = u.evaluate(p)
        var pv = v.evaluate(p)
        var du = pu - last.u
        var dv = pv - last.v
        var total = last.s + sqrt(du * du + dv * dv)
        last = _Sample(pu, pv, total, u.tangent(p), v.tangent(p))
        base.samples.append(last)
        if total > base.length:
            break
    if not (last.s > 0.0):
        raise Error("A paramPoly3 must move")
    return base^
