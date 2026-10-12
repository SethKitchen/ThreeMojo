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
from extensions.carla.quantity_boundary import (
    _RAW_SI,
    _RawSI,
    _finite_si,
    _nonnegative_si,
    _positive_si,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.vector3 import Vector3
from std.math import atan, atan2, ceil, cos, isfinite, sin, sqrt
from units.si import (
    DEGREE,
    PER_METER,
    RADIAN,
    Angle,
    Angle64,
    Length64,
    InverseLength,
    InverseLength64,
    InverseArea64,
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
        x: Length64,
        y: Length64,
        z: Length64,
        tangent: Angle64,
        pitch: Float64 = 0.0,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            x: Its typed source quantity.
            y: Its typed source quantity.
            z: Its typed source quantity.
            tangent: Its typed source quantity.
            pitch: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = DirectedPoint.from_si(
            x.value, y.value, z.value, tangent.value, pitch
        )

    @staticmethod
    def from_si(
        x: Float64,
        y: Float64,
        z: Float64,
        tangent: Float64,
        pitch: Float64 = 0.0,
    ) raises -> DirectedPoint:
        """Explicit source-unit compatibility adapter. Create a directed point.

        Args:
            x: East, in meters.
            y: North, in meters.
            z: Up, in meters.
            tangent: The heading, in radians.
            pitch: The elevation slope.
        """
        _ = _finite_si(x)
        _ = _finite_si(y)
        _ = _finite_si(z)
        _ = _finite_si(tangent)
        _ = _finite_si(pitch)
        return DirectedPoint(_RAW_SI, x, y, z, tangent, pitch)

    @staticmethod
    def _from_si(
        x: Float64,
        y: Float64,
        z: Float64,
        tangent: Float64,
        pitch: Float64 = 0.0,
    ) -> DirectedPoint:
        """Explicit source-unit compatibility adapter. Create a directed point.

        Args:
            x: East, in meters.
            y: North, in meters.
            z: Up, in meters.
            tangent: The heading, in radians.
            pitch: The elevation slope.
        """
        return DirectedPoint(_RAW_SI, x, y, z, tangent, pitch)

    def __init__(
        out self,
        raw: _RawSI,
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

    def apply_lateral_offset(mut self, offset: Length) raises:
        """Move the point sideways, `DirectedPoint::ApplyLateralOffset`.

        Args:
            offset: How far to move. Plus is to the right of the heading.
        """
        var t = _finite_si(Float64(offset.value))
        var x = _finite_si(self.x + t * sin(self.tangent))
        var y = _finite_si(self.y - t * cos(self.tangent))
        self.x = x
        self.y = y

    def heading(self) raises -> Angle64:
        """Return the heading as an angle.

        Returns:
            The tangent, counter-clockwise from plus x.
        """
        return Angle64(_finite_si(self.tangent), RADIAN)

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

    def x_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw x compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.x))

    def y_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw y compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.y))

    def z_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw z compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.z))

    def tangent_quantity(self) raises -> Angle64:
        """Read the checked typed view of the raw tangent compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Angle64(_finite_si(self.tangent))


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
    # A poly3 uses `_u_poly` as v(u). A paramPoly3 uses both.
    var _u_poly: CubicPolynomial
    var _v_poly: CubicPolynomial
    var samples: List[_Sample]

    def __init__(
        out self,
        kind: RoadGeometryKind,
        s: Length64,
        x: Length64,
        y: Length64,
        heading: Angle64,
        length: Length64,
    ) raises:
        """Create a record with typed Float64 station, coordinates and heading.

        Args:
            kind: The plan-view record kind.
            s: Its nonnegative start station.
            x: Its east coordinate.
            y: Its north coordinate.
            heading: Its heading in radians.
            length: Its positive length.

        Returns:
            A record that retains every input bit.

        Raises:
            Error: If a value is not finite or its domain is invalid.
        """
        self = RoadGeometry(
            _RAW_SI,
            kind,
            s.value,
            x.value,
            y.value,
            heading.value,
            length.value,
        )

    @staticmethod
    def from_meters(
        kind: RoadGeometryKind,
        s: Float64,
        x: Float64,
        y: Float64,
        heading: Float64,
        length: Float64,
    ) raises -> RoadGeometry:
        """Read an explicit meter/radian compatibility record without narrowing.

        Args:
            kind: The plan-view record kind.
            s: Its nonnegative start station in meters.
            x: Its east coordinate in meters.
            y: Its north coordinate in meters.
            heading: Its heading in radians.
            length: Its positive length in meters.

        Returns:
            The unchanged finite source values.

        Raises:
            Error: If a value is not finite or its domain is invalid.
        """
        return RoadGeometry(_RAW_SI, kind, s, x, y, heading, length)

    @staticmethod
    def from_float32(
        kind: RoadGeometryKind,
        s: Length,
        x: Length,
        y: Length,
        heading: Angle,
        length: Length,
    ) raises -> RoadGeometry:
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
        return RoadGeometry.from_meters(
            kind,
            Float64(s.value),
            Float64(x.value),
            Float64(y.value),
            Float64(heading.value),
            Float64(length.value),
        )

    def __init__(
        out self,
        raw: _RawSI,
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
        _ = _finite_si(s)
        _ = _finite_si(x)
        _ = _finite_si(y)
        _ = _finite_si(heading)
        _ = _finite_si(length)
        if not kind.is_valid():
            raise Error("Road geometry kind is not valid")
        if s < 0.0:
            raise Error("A road geometry cannot start before s = 0")
        if not (length > 0.0):
            raise Error("A road geometry needs a positive length")
        _ = _finite_si(s + length)
        self.kind = kind
        self.s = s
        self.x = x
        self.y = y
        self.heading = heading
        self.length = length
        self.curvature_start = 0.0
        self.curvature_end = 0.0
        self._u_poly = CubicPolynomial._constant_si(0.0)
        self._v_poly = CubicPolynomial._constant_si(0.0)
        self.samples = List[_Sample]()

    def u_coefficients(
        self,
    ) -> Tuple[Float64, Float64, Float64, Float64, Float64]:
        """Read raw local u coefficients and origin in the source parameter units.

        Returns:
            The original a, b, c, d and parameter origin. Normalized mode
            has four length coefficients; arc-length mode has station units.
            This raw tuple does not assert either dimensional contract.
        """
        return (
            self._u_poly.a,
            self._u_poly.b,
            self._u_poly.c,
            self._u_poly.d,
            self._u_poly.s,
        )

    def v_coefficients(
        self,
    ) -> Tuple[Float64, Float64, Float64, Float64, Float64]:
        """Read raw local v coefficients and origin in the source parameter units.

        Returns:
            The original a, b, c, d and parameter origin, without a typed
            interpretation of the common CARLA coefficient storage.
        """
        return (
            self._v_poly.a,
            self._v_poly.b,
            self._v_poly.c,
            self._v_poly.d,
            self._v_poly.s,
        )

    def end_s(self) raises -> Length64:
        """Return the finite Float64 end station.

        Args:
            None.

        Returns:
            The start station plus length in meters.

        Raises:
            Error: If the sum is not finite.
        """
        return Length64(_finite_si(self.end_s_meters()))

    def end_s_meters(self) raises -> Float64:
        """Return where the record ends along the road.

        Returns:
            `s` plus `length`, in meters.
        """
        _ = _nonnegative_si(self.s)
        _ = _positive_si(self.length)
        return _finite_si(self.s + self.length)

    def pos_from_dist(
        self, dist: Length, max_steps: Int = 4194304
    ) raises -> DirectedPoint:
        """Return the point `dist` into the record, `PosFromDist`.

        Args:
            max_steps: The maximum logical spiral pieces or stored table samples.
            dist: Distance from the record's start. It is clamped to the
                record.

        Returns:
            The point and heading, with z zero.
        """
        return self.pos_at_meters(Float64(dist.value), max_steps)

    def pos_at(
        self, dist: Length64, max_steps: Int = 4194304
    ) raises -> DirectedPoint:
        """Evaluate a typed Float64 distance into this record.

        Args:
            max_steps: The maximum logical spiral pieces or stored table samples.
            dist: A finite distance, clamped to the record.

        Returns:
            Its point and heading without a Float32 conversion.

        Raises:
            Error: If the distance or stored record is invalid.
        """
        return self.pos_at_meters(dist.value, max_steps)

    def pos_at_meters(
        self, dist: Float64, max_steps: Int = 4194304
    ) raises -> DirectedPoint:
        """Evaluate an explicit meter compatibility distance.

        Args:
            max_steps: The maximum logical spiral pieces or stored table samples.
            dist: A finite distance in meters, clamped to the record.

        Returns:
            Its point and heading.

        Raises:
            Error: If the distance or stored record is invalid.
        """
        _ = _finite_si(dist)
        if max_steps <= 0:
            raise Error("Geometry query work limit must be positive")
        if len(self.samples) > max_steps:
            raise Error("Geometry query exceeds its sample work limit")
        _check_geometry_record(self)
        if self.kind == SPIRAL:
            var d = min(max(dist, 0.0), self.length)
            var rate = _finite_si(
                (self.curvature_end - self.curvature_start) / self.length
            )
            var reach = max(
                abs(self.curvature_start),
                abs(_finite_si(self.curvature_start + rate * d)),
            )
            var work = ceil(_finite_si(d * (1.0 + reach)))
            if work >= 9223372036854775807.0 or work >= Float64(max_steps):
                raise Error("Geometry query exceeds its spiral work limit")
            _ = _finite_si(
                self.heading + d * (self.curvature_start + 0.5 * rate * d)
            )
        var point = self._pos_at_si(dist)
        _ = _finite_si(point.x)
        _ = _finite_si(point.y)
        _ = _finite_si(point.z)
        _ = _finite_si(point.tangent)
        _ = _finite_si(point.pitch)
        return point

    def _pos_at_si(self, dist: Float64) -> DirectedPoint:
        """Return the point `dist` meters into the record, in double.

        Args:
            dist: Distance from the record's start, in meters. It is
                clamped to the record.

        Returns:
            The point and heading, with z zero.
        """
        var d = min(max(dist, 0.0), self.length)
        if self.kind == LINE:
            return DirectedPoint._from_si(
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

    def distance_to(self, point: Vector3) raises -> Tuple[Length, Length]:
        """Return typed distances from the retained CARLA Float32 calculation.

        Args:
            point: A query point in CARLA's Float32 coordinate layout.

        Returns:
            The distance along the record and distance from it.

        Raises:
            Error: If a coordinate or result is not finite.
        """
        var result = self.distance_to_meters(point)
        return (Length(result[0]), Length(result[1]))

    def distance_to_meters(
        self, point: Vector3
    ) raises -> Tuple[Float32, Float32]:
        """Use the explicit meter adapter for CARLA's reference distance query.

        Args:
            point: A query point in CARLA's Float32 coordinate layout.

        Returns:
            The unchanged finite Float32 distances in meters.

        Raises:
            Error: If a coordinate or result is not finite.
        """
        _check_geometry_record(self)
        _ = _finite_si(Float64(point.x))
        _ = _finite_si(Float64(point.y))
        _ = _finite_si(Float64(point.z))
        var result = self._distance_to_si(point)
        _ = _finite_si(Float64(result[0]))
        _ = _finite_si(Float64(result[1]))
        return result

    def _distance_to_si(self, point: Vector3) -> Tuple[Float32, Float32]:
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
            var end = self._pos_at_si(self.length)
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
        return DirectedPoint._from_si(x, y, 0.0, tangent)

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
        return DirectedPoint._from_si(
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
        return DirectedPoint._from_si(
            self.x + u * c - v * s,
            self.y + v * c + u * s,
            0.0,
            self.heading + tangent,
        )

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))

    def x_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw x compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.x))

    def y_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw y compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.y))

    def length_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw length compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_positive_si(self.length))

    def heading_quantity(self) raises -> Angle64:
        """Read the checked typed view of the raw heading compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Angle64(_finite_si(self.heading))

    def curvature_start_quantity(self) raises -> InverseLength64:
        """Read the checked typed view of the raw curvature_start compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return InverseLength64(_finite_si(self.curvature_start))

    def curvature_end_quantity(self) raises -> InverseLength64:
        """Read the checked typed view of the raw curvature_end compatibility field.

        Args:
            None.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return InverseLength64(_finite_si(self.curvature_end))


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
    return RoadGeometry.from_float32(LINE, s, x, y, heading, length)


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
    return with_arc_si(
        RoadGeometry.from_float32(ARC, s, x, y, heading, length),
        Float64(curvature.value),
    )


def with_arc_si(
    var base: RoadGeometry, curvature: Float64
) raises -> RoadGeometry:
    """Make a record an arc, `GeometryArc`, from CARLA's double.

    Args:
        base: The common part: start, heading and length.
        curvature: One over the radius, per meter. Plus turns left.

    Returns:
        The record, now an arc.

    Raises:
        Error: If the curvature is zero.
    """
    _check_geometry_base(base)
    _ = _finite_si(curvature)

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
    return with_spiral_si(
        RoadGeometry.from_float32(SPIRAL, s, x, y, heading, length),
        Float64(curvature_start.value),
        Float64(curvature_end.value),
    )


def with_spiral_si(
    var base: RoadGeometry, curvature_start: Float64, curvature_end: Float64
) raises -> RoadGeometry:
    """Make a record a clothoid, `GeometrySpiral`, from CARLA's doubles.

    Args:
        base: The common part: start, heading and length.
        curvature_start: The curvature at the start, per meter.
        curvature_end: The curvature at the end, per meter.

    Returns:
        The record, now a spiral.
    """
    _check_geometry_base(base)
    _ = _finite_si(curvature_start)
    _ = _finite_si(curvature_end)

    base.kind = SPIRAL
    base.curvature_start = curvature_start
    base.curvature_end = curvature_end
    return base^


def poly3_from_coefficients(
    s: Length,
    x: Length,
    y: Length,
    heading: Angle,
    length: Length,
    a: Float64,
    b: Float64,
    c: Float64,
    d: Float64,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Return a cubic record v(u), `GeometryPoly3`.

    The table samples u every 0.3 meters, as CARLA's `PreComputeSpline`.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
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
    return with_poly3_si(
        RoadGeometry.from_float32(POLY3, s, x, y, heading, length),
        a,
        b,
        c,
        d,
        max_samples=max_samples,
    )


def with_poly3_si(
    var base: RoadGeometry,
    a: Float64,
    b: Float64,
    c: Float64,
    d: Float64,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Make a record a cubic v(u), `GeometryPoly3`, and sample it.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
        base: The common part: start, heading and length.
        a: The constant term of v, in meters.
        b: The linear term.
        c: The quadratic term, per meter.
        d: The cubic term, per square meter.

    Returns:
        The record, now a poly3 with its table.
    """
    _check_geometry_base(base)
    if max_samples < 2:
        raise Error("Geometry sampling needs a budget of at least two samples")
    _ = _finite_si(a)
    _ = _finite_si(b)
    _ = _finite_si(c)
    _ = _finite_si(d)

    base.kind = POLY3
    base._u_poly = CubicPolynomial.from_coefficients(a, b, c, d, 0.0)
    base.samples.clear()
    comptime delta_u = 0.3
    var u = 0.0
    var total = 0.0
    var last = _Sample(
        0.0,
        base._u_poly._evaluate_si(0.0),
        0.0,
        1.0,
        base._u_poly._tangent_si(0.0),
    )
    base.samples.append(last)
    var target = _finite_si(base.length + delta_u)
    while total < target:
        if len(base.samples) >= max_samples:
            raise Error("Geometry sampling exhausted its sample budget")
        var next_u = _finite_si(u + delta_u)
        if not (next_u > u):
            raise Error("Geometry sampling cannot advance its parameter")
        u = next_u
        var v = _finite_si(base._u_poly._evaluate_si(u))
        var du = u - last.u
        var dv = v - last.v
        var next_total = _finite_si(total + sqrt(du * du + dv * dv))
        if not (next_total > total):
            raise Error("Geometry sampling cannot advance its length")
        total = next_total
        last = _Sample(
            u, v, total, 1.0, _finite_si(base._u_poly._tangent_si(u))
        )
        base.samples.append(last)
    _check_geometry_record(base)
    return base^


def param_poly3_from_coefficients(
    s: Length,
    x: Length,
    y: Length,
    heading: Angle,
    length: Length,
    u: CubicPolynomial,
    v: CubicPolynomial,
    p_range: ParamPoly3Range,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Return a parametric cubic record, `GeometryParamPoly3`.

    The table has one interval per 0.5 meters and at least five, as
    CARLA's `PreComputeSpline`.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
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
    return with_param_poly3_from_coefficients(
        RoadGeometry.from_float32(PARAM_POLY3, s, x, y, heading, length),
        u,
        v,
        p_range,
        max_samples=max_samples,
    )


def with_param_poly3_from_coefficients(
    var base: RoadGeometry,
    u: CubicPolynomial,
    v: CubicPolynomial,
    p_range: ParamPoly3Range,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Make a record a parametric cubic, `GeometryParamPoly3`, and sample it.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
        base: The common part: start, heading and length.
        u: The cubic u(p), in meters.
        v: The cubic v(p), in meters.
        p_range: What p runs over.

    Returns:
        The record, now a paramPoly3 with its table.

    Raises:
        Error: If `p_range` is not valid, or the curve does not move.
    """
    _check_geometry_base(base)
    if max_samples < 2:
        raise Error("Geometry sampling needs a budget of at least two samples")
    if not p_range.is_valid():
        raise Error("paramPoly3 range is not valid")
    _ = _nonnegative_si(base.s)
    _ = _positive_si(base.length)
    _ = _finite_si(base.x)
    _ = _finite_si(base.y)
    _ = _finite_si(base.heading)
    for polynomial in [u, v]:
        _ = _finite_si(polynomial.a)
        _ = _finite_si(polynomial.b)
        _ = _finite_si(polynomial.c)
        _ = _finite_si(polynomial.d)
        _ = _finite_si(polynomial.s)
    base.kind = PARAM_POLY3
    base._u_poly = u
    base._v_poly = v
    base.samples.clear()
    var work = _finite_si(base.length / 0.5)
    if work >= 9223372036854775807.0 or work >= Float64(max_samples):
        raise Error("Geometry sampling exceeds its sample budget")
    var intervals = max(Int(work), 5)
    if intervals >= max_samples:
        raise Error("Geometry sampling exceeds its sample budget")
    var delta_p = 1.0 / Float64(intervals)
    if p_range == ARC_LENGTH:
        delta_p *= base.length
    var p = 0.0
    var last = _Sample(
        _finite_si(u._evaluate_si(0.0)),
        _finite_si(v._evaluate_si(0.0)),
        0.0,
        _finite_si(u._tangent_si(0.0)),
        _finite_si(v._tangent_si(0.0)),
    )
    base.samples.append(last)
    for _ in range(intervals):  # pragma: no branch
        var next_p = _finite_si(p + delta_p)
        if not (next_p > p):
            raise Error("Geometry sampling cannot advance its parameter")
        p = next_p
        var pu = _finite_si(u._evaluate_si(p))
        var pv = _finite_si(v._evaluate_si(p))
        var du = pu - last.u
        var dv = pv - last.v
        var total = _finite_si(last.s + sqrt(du * du + dv * dv))
        last = _Sample(
            pu,
            pv,
            total,
            _finite_si(u._tangent_si(p)),
            _finite_si(v._tangent_si(p)),
        )
        base.samples.append(last)
        if total > base.length:
            break
    if not (last.s > 0.0):
        raise Error("A paramPoly3 must move")
    _check_geometry_record(base)
    return base^


def line(
    s: Length64, x: Length64, y: Length64, heading: Angle64, length: Length64
) raises -> RoadGeometry:
    """Create a checked Float64 line record.

    Args:
        s: Its start station.
        x: Its east coordinate.
        y: Its north coordinate.
        heading: Its heading.
        length: Its positive length.

    Returns:
        A line with unchanged Float64 inputs.

    Raises:
        Error: If any value is not finite or its domain is invalid.
    """
    return RoadGeometry(LINE, s, x, y, heading, length)


def with_arc(
    var base: RoadGeometry, curvature: InverseLength64
) raises -> RoadGeometry:
    """Set the typed Float64 curvature of an arc.

    Args:
        base: The source record.
        curvature: Its finite nonzero curvature.

    Returns:
        The arc record.

    Raises:
        Error: If curvature is not finite or is zero.
    """
    return with_arc_si(base^, curvature.value)


def with_spiral(
    var base: RoadGeometry,
    curvature_start: InverseLength64,
    curvature_end: InverseLength64,
) raises -> RoadGeometry:
    """Set the typed Float64 endpoint curvatures of a spiral.

    Args:
        base: The source record.
        curvature_start: Its finite start curvature.
        curvature_end: Its finite end curvature.

    Returns:
        The spiral record.

    Raises:
        Error: If a curvature is not finite.
    """
    return with_spiral_si(base^, curvature_start.value, curvature_end.value)


def with_poly3(
    var base: RoadGeometry,
    a: Length64,
    b: Float64,
    c: InverseLength64,
    d: InverseArea64,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Set a typed Float64 distance polynomial on a record.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
        base: The source record.
        a: Its constant length.
        b: Its dimensionless slope.
        c: Its quadratic coefficient per meter.
        d: Its cubic coefficient per square meter.

    Returns:
        The sampled cubic record.

    Raises:
        Error: If a coefficient is not finite.
    """
    return with_poly3_si(
        base^, a.value, b, c.value, d.value, max_samples=max_samples
    )


def arc(
    s: Length64,
    x: Length64,
    y: Length64,
    heading: Angle64,
    length: Length64,
    curvature: InverseLength64,
) raises -> RoadGeometry:
    """Create a checked Float64 arc record.

    Args:
        s: Its start station.
        x: Its east coordinate.
        y: Its north coordinate.
        heading: Its heading.
        length: Its positive length.
        curvature: Its finite nonzero curvature.

    Returns:
        The arc record.

    Raises:
        Error: If an input is not finite or its domain is invalid.
    """
    return with_arc(RoadGeometry(ARC, s, x, y, heading, length), curvature)


def spiral(
    s: Length64,
    x: Length64,
    y: Length64,
    heading: Angle64,
    length: Length64,
    curvature_start: InverseLength64,
    curvature_end: InverseLength64,
) raises -> RoadGeometry:
    """Create a checked Float64 spiral record.

    Args:
        s: Its start station.
        x: Its east coordinate.
        y: Its north coordinate.
        heading: Its heading.
        length: Its positive length.
        curvature_start: Its start curvature.
        curvature_end: Its end curvature.

    Returns:
        The spiral record.

    Raises:
        Error: If an input is not finite or its domain is invalid.
    """
    return with_spiral(
        RoadGeometry(SPIRAL, s, x, y, heading, length),
        curvature_start,
        curvature_end,
    )


def poly3(
    s: Length64,
    x: Length64,
    y: Length64,
    heading: Angle64,
    length: Length64,
    a: Length64,
    b: Float64,
    c: InverseLength64,
    d: InverseArea64,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Create a checked Float64 local cubic record.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
        s: Its start station.
        x: Its east coordinate.
        y: Its north coordinate.
        heading: Its heading.
        length: Its positive length.
        a: Its constant length.
        b: Its dimensionless slope.
        c: Its quadratic coefficient per meter.
        d: Its cubic coefficient per square meter.

    Returns:
        The sampled cubic record.

    Raises:
        Error: If an input is not finite or its domain is invalid.
    """
    return with_poly3(
        RoadGeometry(POLY3, s, x, y, heading, length),
        a,
        b,
        c,
        d,
        max_samples=max_samples,
    )


struct NormalizedCubic(ImplicitlyCopyable):
    """A length-valued cubic of a dimensionless normalized parameter.

    Every coefficient is a length. This is deliberately a different type
    from a road-station CubicPolynomial; raw CARLA storage is shared only
    after the parameter mode has been selected explicitly.
    """

    var a: Length64
    var b: Length64
    var c: Length64
    var d: Length64

    def __init__(
        out self, a: Length64, b: Length64, c: Length64, d: Length64
    ) raises:
        """Create finite coefficients for a normalized parameter.

        Args:
            a: The constant length coefficient.
            b: The linear length coefficient.
            c: The quadratic length coefficient.
            d: The cubic length coefficient.

        Raises:
            Error: If any coefficient is not finite.
        """
        self.a = Length64(_finite_si(a.value))
        self.b = Length64(_finite_si(b.value))
        self.c = Length64(_finite_si(c.value))
        self.d = Length64(_finite_si(d.value))

    @staticmethod
    def from_meters(
        a: Float64, b: Float64, c: Float64, d: Float64
    ) raises -> NormalizedCubic:
        """Read four explicit meter-valued normalized source coefficients.

        Args:
            a: The constant coefficient in meters.
            b: The linear coefficient in meters.
            c: The quadratic coefficient in meters.
            d: The cubic coefficient in meters.

        Returns:
            The checked normalized polynomial without narrowing.

        Raises:
            Error: If any coefficient is not finite.
        """
        return NormalizedCubic(
            Length64(a), Length64(b), Length64(c), Length64(d)
        )

    def _coefficients(self) raises -> CubicPolynomial:
        return CubicPolynomial.from_coefficients(
            self.a.value, self.b.value, self.c.value, self.d.value, 0
        )

    def evaluate(self, p: Float64) raises -> Length64:
        """Evaluate at a finite dimensionless normalized coordinate.

        Args:
            p: The parameter, between zero and one inclusive.

        Returns:
            The physical value in Float64 precision.

        Raises:
            Error: If a coefficient, parameter or result is invalid.
        """
        _ = _finite_si(p)
        if p < 0 or p > 1:
            raise Error(
                "A normalized polynomial parameter must be from zero"
                " through one"
            )
        var polynomial = self._coefficients()
        return Length64(_finite_si(polynomial._evaluate_si(p)))

    def tangent(self, p: Float64) raises -> Length64:
        """Differentiate with respect to the dimensionless parameter.

        Args:
            p: The parameter, between zero and one inclusive.

        Returns:
            The length-valued derivative, not a dimensionless station slope.

        Raises:
            Error: If a coefficient, parameter or result is invalid.
        """
        _ = _finite_si(p)
        if p < 0 or p > 1:
            raise Error(
                "A normalized polynomial parameter must be from zero"
                " through one"
            )
        var polynomial = self._coefficients()
        return Length64(_finite_si(polynomial._tangent_si(p)))


def with_param_poly3(
    var base: RoadGeometry,
    u: CubicPolynomial,
    v: CubicPolynomial,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Set an arc-length-parametrized cubic using station-unit coefficients.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
        base: The common geometry record.
        u: The u coordinate as a polynomial of meter station.
        v: The v coordinate as a polynomial of meter station.

    Returns:
        The sampled geometry in arc-length parameter mode.

    Raises:
        Error: If a value is invalid or the curve does not move.
    """
    return with_param_poly3_from_coefficients(
        base^, u, v, ARC_LENGTH, max_samples=max_samples
    )


def with_param_poly3_normalized(
    var base: RoadGeometry,
    u: NormalizedCubic,
    v: NormalizedCubic,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Set a normalized-parametric cubic with all-length coefficients.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
        base: The common geometry record.
        u: The u coordinate as a polynomial of dimensionless p.
        v: The v coordinate as a polynomial of dimensionless p.

    Returns:
        The sampled geometry in normalized parameter mode.

    Raises:
        Error: If a value is invalid or the curve does not move.
    """
    return with_param_poly3_from_coefficients(
        base^,
        u._coefficients(),
        v._coefficients(),
        NORMALIZED,
        max_samples=max_samples,
    )


def param_poly3(
    s: Length64,
    x: Length64,
    y: Length64,
    heading: Angle64,
    length: Length64,
    u: CubicPolynomial,
    v: CubicPolynomial,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Create a Float64 arc-length-parametric cubic.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
        s: The start station.
        x: The start east coordinate.
        y: The start north coordinate.
        heading: The heading.
        length: The positive curve length.
        u: The u polynomial with station-unit coefficients.
        v: The v polynomial with station-unit coefficients.

    Returns:
        The checked geometry.

    Raises:
        Error: If a value is invalid or the curve does not move.
    """
    return with_param_poly3(
        RoadGeometry(PARAM_POLY3, s, x, y, heading, length),
        u,
        v,
        max_samples=max_samples,
    )


def param_poly3_normalized(
    s: Length64,
    x: Length64,
    y: Length64,
    heading: Angle64,
    length: Length64,
    u: NormalizedCubic,
    v: NormalizedCubic,
    max_samples: Int = 4194304,
) raises -> RoadGeometry:
    """Create a Float64 cubic of normalized dimensionless p.

    Args:
        max_samples: The maximum emitted table samples; exhaustion refuses the geometry.
        s: The start station.
        x: The start east coordinate.
        y: The start north coordinate.
        heading: The heading.
        length: The positive curve length.
        u: The u polynomial with all-length coefficients.
        v: The v polynomial with all-length coefficients.

    Returns:
        The checked geometry.

    Raises:
        Error: If a value is invalid or the curve does not move.
    """
    return with_param_poly3_normalized(
        RoadGeometry(PARAM_POLY3, s, x, y, heading, length),
        u,
        v,
        max_samples=max_samples,
    )


def _check_geometry_base(base: RoadGeometry) raises:
    """Validate a mutable common record before shape conversion or sampling."""
    if not base.kind.is_valid():
        raise Error("Road geometry kind is not valid")
    _ = _nonnegative_si(base.s)
    _ = _positive_si(base.length)
    _ = _finite_si(base.x)
    _ = _finite_si(base.y)
    _ = _finite_si(base.heading)
    _ = _finite_si(base.s + base.length)


def _check_geometry_record(base: RoadGeometry) raises:
    """Check a complete geometry before a public record/query consumes it."""
    _check_geometry_base(base)
    if base.kind == ARC or base.kind == SPIRAL:
        _ = _finite_si(base.curvature_start)
        _ = _finite_si(base.curvature_end)
    if base.kind == ARC and base.curvature_start == 0:
        raise Error("An arc needs nonzero curvature")
    if base.kind == POLY3 or base.kind == PARAM_POLY3:
        if len(base.samples) < 2:
            raise Error("A sampled geometry needs at least two samples")
        var previous = Float64(-1)
        for sample in base.samples:
            _ = _finite_si(sample.u)
            _ = _finite_si(sample.v)
            _ = _finite_si(sample.tu)
            _ = _finite_si(sample.tv)
            _ = _nonnegative_si(sample.s)
            if not (sample.s > previous):
                raise Error("Geometry sample lengths must strictly increase")
            previous = sample.s
        if base.samples[0].s != 0:
            raise Error("Geometry samples must begin at zero length")
