# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Direction-independent bounds for the lane centers of a junction.

On each smooth record span, a coordinate with |f''| <= M stays within
M*h*h/8 of its endpoint chord. Subdivision keeps that padding at most
one centimeter. This bounds the supported lane-center model, not the
lane surface or the exact OpenDRIVE polynomial behind a sampled table.
Separate numerical allowances cover Float32 rounding, Float64 cubic
evaluation, and spiral quadrature. They are not part of the 1 cm chord
target. The returned bounds must fit in finite Float32 coordinates.
"""

from extensions.carla.geometry import ARC, LINE, POLY3, SPIRAL, RoadGeometry
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import RoadInfo, info_index
from math.bounds import Box3
from math.vector3 import Vector3
from std.math import ceil, isfinite, sqrt
from std.memory import bitcast

comptime _CHORD_ERROR = 0.01
comptime _ROUNDING = 4.0 * 1.1920928955078125e-7
comptime _MAX_PIECES = 65536


def _polynomial_bounds(
    p: CubicPolynomial, a: Float64, b: Float64
) -> Tuple[Float64, Float64, Float64, Float64]:
    # Bernstein control values bound a cubic and its first two derivatives.
    var h = b - a
    var fa = p.evaluate(a)
    var fb = p.evaluate(b)
    var da = p.tangent(a)
    var db = p.tangent(b)
    var dda = 2.0 * p.c + 6.0 * p.d * a
    var ddb = 2.0 * p.c + 6.0 * p.d * b
    # Records are re-expanded about road s. Large s can cause cancellation
    # even for a small local polynomial. Bound Horner error by absolute
    # coefficient magnitudes, not by the small computed endpoint values.
    comptime epsilon = 8.0 * 2.220446049250313e-16
    var s = max(abs(a), abs(b))
    var value_error = epsilon * (
        abs(p.a) + s * (abs(p.b) + s * (abs(p.c) + s * abs(p.d)))
    )
    var tangent_error = epsilon * (
        abs(p.b) + s * (2.0 * abs(p.c) + s * 3.0 * abs(p.d))
    )
    var second_error = epsilon * (2.0 * abs(p.c) + s * 6.0 * abs(p.d))
    return (
        max(
            max(abs(fa), abs(fb)),
            max(abs(fa + h * da / 3.0), abs(fb - h * db / 3.0)),
        )
        * (1.0 + epsilon)
        + value_error
        + h * tangent_error / 3.0,
        max(max(abs(da), abs(db)), abs(da + h * dda / 2.0)) * (1.0 + epsilon)
        + tangent_error
        + h * second_error / 2.0,
        max(abs(dda), abs(ddb)) + second_error,
        value_error,
    )


def _insert_break(mut values: List[Float64], s: Float64):
    if s <= values[0] or s >= values[len(values) - 1]:
        return
    var lo = 0
    var hi = len(values)
    while lo < hi:
        var mid = (lo + hi) // 2
        if values[mid] < s:
            lo = mid + 1
        else:
            hi = mid
    if values[lo] != s:
        values.insert(lo, s)


def _record_breaks[T: RoadInfo](mut values: List[Float64], records: List[T]):
    for record in records:
        _insert_break(values, record.distance())


def _geometry_rates(
    geometry: RoadGeometry, a: Float64, b: Float64
) raises -> Tuple[Float64, Float64, Float64, Bool]:
    # Bounds on |heading'|, |heading''|, and |reference_position''|.
    # All geometry clamps at its end. Sampled geometry is piecewise linear
    # in position, but its interpolated tangent can still turn.
    if geometry.kind == LINE or a >= geometry.length:
        return (0.0, 0.0, 0.0, True)
    if geometry.kind == ARC:
        var k = abs(geometry.curvature_start)
        return (k, 0.0, k, True)
    if geometry.kind == SPIRAL:
        var rate = (
            geometry.curvature_end - geometry.curvature_start
        ) / geometry.length
        var k = max(
            abs(geometry.curvature_start + rate * a),
            abs(geometry.curvature_start + rate * b),
        )
        return (k, abs(rate), k, True)
    var lo = 0
    var hi = len(geometry.samples) - 1
    var middle = a + (b - a) * 0.5
    while hi - lo > 1:
        var mid = (lo + hi) // 2
        if geometry.samples[mid].s < middle:
            lo = mid
        else:
            hi = mid
    var one = geometry.samples[lo]
    var two = geometry.samples[hi]
    var h = two.s - one.s
    if h <= 0.0:
        raise Error("A junction geometry has a zero-length sample interval")
    var du = (two.tu - one.tu) / h
    var dv = (two.tv - one.tv) / h
    if geometry.kind == POLY3:
        return (abs(dv), 2.0 * dv * dv, 0.0, True)
    # A paramPoly3's tangent is atan2(tv, tu). Bound the distance of
    # the interpolated derivative vector from zero, including extrapolation.
    var u = one.tu + (a - one.s) * du
    var v = one.tv + (a - one.s) * dv
    var speed2 = du * du + dv * dv
    var t = 0.0
    if speed2 > 0.0:
        t = min(max(-(u * du + v * dv) / speed2, 0.0), b - a)
    var min_u = u + t * du
    var min_v = v + t * dv
    var norm2 = min_u * min_u + min_v * min_v
    if norm2 <= 1e-24 * max(1.0, u * u + v * v):
        # A cusp can change its normal discontinuously. Use an enclosing
        # offset disk instead of claiming a smooth-curve error there.
        return (0.0, 0.0, 0.0, False)
    var k = abs(u * dv - v * du) / norm2
    return (k, 2.0 * k * sqrt(speed2 / norm2), 0.0, True)


def _span_box(
    road: Road, section: Int, lane: Int, a: Float64, b: Float64
) raises -> Box3:
    var geometry_index = info_index(road.info.geometries, a)
    var offset_index = info_index(road.info.lane_offsets, a)
    var elevation_index = info_index(road.info.elevations, a)
    if geometry_index < 0 or offset_index < 0 or elevation_index < 0:
        raise Error(
            "A junction lane is missing a geometry, offset, or elevation record"
        )
    ref geometry = road.info.geometries[geometry_index].geometry
    var q = _polynomial_bounds(
        road.info.lane_offsets[offset_index].polynomial, a, b
    )
    var lane_id = road.sections[section].lanes[lane].id.value
    for other in road.sections[section].lanes:
        if other.id.value * lane_id <= 0 or abs(other.id.value) > abs(lane_id):
            continue
        var at = info_index(other.info.widths, a)
        if at < 0:
            raise Error("A junction lane has no width record")
        var width = _polynomial_bounds(other.info.widths[at].polynomial, a, b)
        var factor = 0.5 if other.id.value == lane_id else 1.0
        q = (
            q[0] + factor * width[0],
            q[1] + factor * width[1],
            q[2] + factor * width[2],
            q[3] + factor * width[3],
        )
    var z = _polynomial_bounds(
        road.info.elevations[elevation_index].polynomial, a, b
    )
    var arc_error = 0.0
    if geometry.kind == ARC:
        # Phase formation and conversion of cardinal angles back to road s
        # can lose precision. Large radii also amplify center cancellation.
        # Bound sine/cosine displacement by min(phase error, 2); this becomes
        # a full-circle allowance when consecutive angles are unresolved.
        comptime epsilon = 16.0 * 2.220446049250313e-16
        var radius = abs(1.0 / geometry.curvature_start)
        var phase = epsilon * (
            abs(geometry.heading)
            + (abs(geometry.s) + geometry.length)
            * abs(geometry.curvature_start)
        )
        arc_error = epsilon * (
            abs(geometry.x) + abs(geometry.y) + 2.0 * radius
        ) + 2.0 * (radius + q[0]) * min(phase, 2.0)
    var rates = _geometry_rates(geometry, a - geometry.s, b - geometry.s)
    var xy_acceleration = (
        rates[2]
        + q[2]
        + 2.0 * q[1] * rates[0]
        + q[0] * (rates[0] * rates[0] + rates[1])
    )
    var acceleration = max(xy_acceleration, z[2])
    var wanted = ceil((b - a) * sqrt(acceleration / (8.0 * _CHORD_ERROR)))
    if not (isfinite(wanted) and isfinite(q[0]) and isfinite(z[0])):
        raise Error("A junction lane has non-finite bounds")
    var out = Box3.empty()
    if geometry.kind == ARC and q[1] == 0.0 and z[2] == 0.0:
        # A constant-offset arc has its plan extrema at cardinal headings.
        # Evaluate those directly; ordinary arcs do not need chord padding.
        out.expand_by_point(road.lane_transform(section, lane, a).location)
        out.expand_by_point(road.lane_transform(section, lane, b).location)
        comptime half_pi = 1.5707963267948966
        var theta_a = (
            geometry.heading + (a - geometry.s) * geometry.curvature_start
        )
        var theta_b = (
            geometry.heading + (b - geometry.s) * geometry.curvature_start
        )
        var first = ceil(min(theta_a, theta_b) / half_pi)
        for i in range(4):
            var theta = (first + Float64(i)) * half_pi
            if theta <= max(theta_a, theta_b):
                var s = (
                    geometry.s
                    + (theta - geometry.heading) / geometry.curvature_start
                )
                out.expand_by_point(
                    road.lane_transform(
                        section, lane, min(max(s, a), b)
                    ).location
                )
        out.expand_by_vector(
            Vector3(
                Float32(
                    2.0 * q[3]
                    + arc_error
                    + _ROUNDING
                    * (
                        1.0
                        + q[0]
                        + max(abs(Float64(out.min.x)), abs(Float64(out.max.x)))
                    )
                ),
                Float32(
                    2.0 * q[3]
                    + arc_error
                    + _ROUNDING
                    * (
                        1.0
                        + q[0]
                        + max(abs(Float64(out.min.y)), abs(Float64(out.max.y)))
                    )
                ),
                Float32(2.0 * z[3] + _ROUNDING * (1.0 + z[0])),
            )
        )
        return out
    # For five-point Gauss-Legendre integration, the phase derivatives
    # satisfy |theta'|*step <= 1 and |theta''|*step^2 <= 2 in _spiral.
    # The standard tenth-derivative remainder is < 5.28e-8*length per
    # coordinate. Allow twice that for a sampled chord and another query.
    var quadrature = (
        1.1e-7 * geometry.length if geometry.kind == SPIRAL else 0.0
    )
    if not rates[3] or wanted > Float64(_MAX_PIECES):
        # Conservative fallback for a singular tangent or excessive work.
        # The reference chord gets its own curvature padding, then the
        # complete offset disk. This deliberately has no 1 cm tightness claim.
        var first = road.directed_point_no_lane_offset(a).to_carla().location
        var last = road.directed_point_no_lane_offset(b).to_carla().location
        var pad = (
            rates[2] * (b - a) * (b - a) / 8.0
            + q[0]
            + q[3]
            + quadrature
            + arc_error
        )
        out = Box3(first, first)
        out.expand_by_point(last)
        out.min.z = Float32(-z[0] - z[3])
        out.max.z = Float32(z[0] + z[3])
        var xy = Float32(
            pad
            + _ROUNDING
            * (
                1.0
                + pad
                + max(
                    max(abs(Float64(first.x)), abs(Float64(first.y))),
                    max(abs(Float64(last.x)), abs(Float64(last.y))),
                )
            )
        )
        out.expand_by_vector(Vector3(xy, xy, Float32(_ROUNDING * (1.0 + z[0]))))
        return out
    var pieces = max(1, Int(wanted))
    var step = (b - a) / Float64(pieces)
    var xy_pad = (
        xy_acceleration * step * step / 8.0
        + quadrature
        + 2.0 * q[3]
        + arc_error
    )
    var z_pad = z[2] * step * step / 8.0 + 2.0 * z[3]
    for i in range(pieces + 1):
        # Compute from the fixed start. Never accumulate signed steps or
        # follow a successor into another lane, section, or road.
        var s = b if i == pieces else a + (b - a) * (
            Float64(i) / Float64(pieces)
        )
        var point = road.lane_transform(section, lane, s).location
        var padding = Vector3(
            Float32(xy_pad + _ROUNDING * (1.0 + q[0] + abs(Float64(point.x)))),
            Float32(xy_pad + _ROUNDING * (1.0 + q[0] + abs(Float64(point.y)))),
            Float32(z_pad + _ROUNDING * (1.0 + z[0])),
        )
        out.expand_by_point(point - padding)
        out.expand_by_point(point + padding)
    return out


def _lane_section_box(road: Road, section: Int, lane: Int) raises -> Box3:
    var a = road.sections[section].s
    var b = a + road.section_length(section)
    if not (isfinite(a) and isfinite(b) and a >= 0.0 and b >= a):
        raise Error("A junction lane has an invalid section interval")
    var breaks: List[Float64] = [a, b]
    _record_breaks(breaks, road.info.geometries)
    _record_breaks(breaks, road.info.elevations)
    _record_breaks(breaks, road.info.lane_offsets)
    for other in road.sections[section].lanes:
        _record_breaks(breaks, other.info.widths)
    for record in road.info.geometries:
        _insert_break(breaks, record.s + record.geometry.length)
        for sample in record.geometry.samples:
            _insert_break(breaks, record.s + sample.s)
    var out = Box3.empty()
    for i in range(len(breaks) - 1):
        # Keep both sides of a discontinuous record boundary. The previous
        # representable s is the final API input that uses the old records.
        var end = breaks[i + 1]
        if end > breaks[i]:
            end = bitcast[DType.float64](bitcast[DType.uint64](end) - 1)
        out.union(_span_box(road, section, lane, breaks[i], end))
    out.expand_by_point(road.lane_transform(section, lane, b).location)
    return out
