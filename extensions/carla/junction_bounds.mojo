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
from extensions.carla.curve_bounds import _lane_jet, _reference_work
from extensions.carla.lane_value_bounds import _lane_value_bound
from extensions.carla.curve_interval import _Interval, _Jet, _next_up
from extensions.carla.lane_refinement import _midpoint
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import (
    _preflight_road_records,
    _reserve_lane_boundaries,
    _reserve_lane_scalars,
)
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
    road: Road,
    section: Int,
    lane: Int,
    a: Float64,
    b: Float64,
    mut work: _MapBuildWork,
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
    # The valid selected lane belongs to this nonempty lane list.
    for other in road.sections[section].lanes:  # pragma: no branch
        work.step()
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
        out.expand_by_point(_budgeted_pose(road, section, lane, a, work))
        out.expand_by_point(_budgeted_pose(road, section, lane, b, work))
        comptime half_pi = 1.5707963267948966
        var theta_a = (
            geometry.heading + (a - geometry.s) * geometry.curvature_start
        )
        var theta_b = (
            geometry.heading + (b - geometry.s) * geometry.curvature_start
        )
        var first = ceil(min(theta_a, theta_b) / half_pi)
        # An arc checks exactly four consecutive cardinal headings.
        for i in range(4):  # pragma: no branch
            var theta = (first + Float64(i)) * half_pi
            if theta <= max(theta_a, theta_b):
                var s = (
                    geometry.s
                    + (theta - geometry.heading) / geometry.curvature_start
                )
                out.expand_by_point(
                    _budgeted_pose(road, section, lane, min(max(s, a), b), work)
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
        # Uncertified proposal for a singular tangent or excessive work.
        # The historical reference chord and offset disk only suggest a box;
        # _certify_junction_span must still prove the actual lane graph fits.
        # This proposal deliberately has no 1 cm tightness claim.
        _reserve_reference_point(road, a, work)
        var first = road.directed_point_no_lane_offset(a).to_carla().location
        _reserve_reference_point(road, b, work)
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
    # At least one piece gives at least two endpoint samples.
    for i in range(pieces + 1):  # pragma: no branch
        # Compute from the fixed start. Never accumulate signed steps or
        # follow a successor into another lane, section, or road.
        var s = b if i == pieces else a + (b - a) * (
            Float64(i) / Float64(pieces)
        )
        var point = _budgeted_pose(road, section, lane, s, work)
        var padding = Vector3(
            Float32(xy_pad + _ROUNDING * (1.0 + q[0] + abs(Float64(point.x)))),
            Float32(xy_pad + _ROUNDING * (1.0 + q[0] + abs(Float64(point.y)))),
            Float32(z_pad + _ROUNDING * (1.0 + z[0])),
        )
        out.expand_by_point(point - padding)
        out.expand_by_point(point + padding)
    return out


def _reserve_reference_point(
    road: Road, s: Float64, mut work: _MapBuildWork
) raises:
    work.step()
    var terms = _reference_work(road, s, s)
    if terms < 0:
        raise Error(
            "Junction construction cannot resolve scalar quadrature work"
        )
    work.term(terms)


def _budgeted_pose(
    road: Road, section: Int, lane: Int, s: Float64, mut work: _MapBuildWork
) raises -> Vector3:
    _reserve_lane_scalars(road, section, work, 2)
    _reserve_reference_point(road, s, work)
    var terms = _reference_work(road, s, s)
    work.term(terms)
    return road.lane_transform(section, lane, s).location


def _canonical_endpoint(
    road: Road, section: Int, lane: Int, s: Float64, mut work: _MapBuildWork
) raises -> Vector3:
    _reserve_lane_scalars(road, section, work)
    _reserve_reference_point(road, s, work)
    var point = road._lane_center(section, lane, s)
    var result = Vector3(
        Float32(point[0]), Float32(point[1]), Float32(point[2])
    )
    if not (isfinite(result.x) and isfinite(result.y) and isfinite(result.z)):
        raise Error(
            "Junction canonical endpoint is not finite in public storage"
        )
    return result


def _outward_float(value: Float64, lower: Bool) raises -> Float32:
    var result = Float32(value)
    if not isfinite(result):
        raise Error(
            "Junction canonical enclosure is not finite in public storage"
        )
    if (lower and Float64(result) > value) or (
        not lower and Float64(result) < value
    ):
        if result == 0.0:
            return bitcast[DType.float32](
                UInt32(0x80000001) if lower else UInt32(1)
            )
        var bits = bitcast[DType.uint32](result)
        if (result > 0.0) == lower:
            bits -= 1
        else:
            bits += 1
        result = bitcast[DType.float32](bits)
        if not isfinite(result):
            raise Error(
                "Junction canonical enclosure is not finite in public storage"
            )
    return result


def _centered_elevation_enclosure(
    road: Road,
    low: Float64,
    high: Float64,
    original: _Interval,
    scalar_error: Float64,
    mut work: _MapBuildWork,
) raises -> _Interval:
    # Re-expand the exact real cubic in stored coefficients using outward
    # interval arithmetic. Keep the original canonical Horner roundoff bound;
    # this never treats the reordered polynomial as the scalar evaluator.
    work.step()
    work.term(128)
    if not isfinite(scalar_error) or scalar_error < 0.0:
        return original
    var at = info_index(road.info.elevations, low)
    if at < 0 or info_index(road.info.elevations, high) != at:
        return original
    ref p = road.info.elevations[at].polynomial
    var m = _Interval.point(_midpoint(low, high))
    var a = _Interval.point(p.a)
    var b = _Interval.point(p.b)
    var c = _Interval.point(p.c)
    var d = _Interval.point(p.d)
    var value = a + m * (b + m * (c + m * d))
    var first = b + m * (
        _Interval.point(2.0) * c + m * _Interval.point(3.0) * d
    )
    var second = c + _Interval.point(3.0) * m * d
    var delta = _Interval(low, high) - m
    var ideal = value + delta * (first + delta * (second + delta * d))
    var stored = ideal + _Interval(-scalar_error, scalar_error)
    var lower = max(original.low, stored.low)
    var upper = min(original.high, stored.high)
    if not stored.is_finite() or lower > upper:
        return original
    return _Interval(lower, upper)


def _monotone_coordinate(value: _Jet) -> Bool:
    # These are derivatives of the complete ideal expression, not of the
    # rounded scalar staircase. A branch join has unknown derivatives.
    return (
        value.first.is_finite()
        and (value.first.low >= 0.0 or value.first.high <= 0.0)
        and isfinite(value.error)
        and value.error >= 0.0
    )


def _monotone_coordinate_enclosure(
    value: _Jet, first: _Interval, last: _Interval, original: _Interval
) -> _Interval:
    # For every fixed permitted expression, a sign-definite ideal derivative
    # puts its real values between its ideal endpoints. Scalar evaluations
    # need not be monotone. Add the ORIGINAL WHOLE-CELL scalar error, never
    # the endpoint errors, to cover their potentially nonmonotone roundoff.
    if not _monotone_coordinate(value):
        return original
    if not (first.is_finite() and last.is_finite()):
        return original
    var ideal = first.hull(last)
    var stored = ideal + _Interval(-value.error, value.error)
    var lower = max(original.low, stored.low)
    var upper = min(original.high, stored.high)
    if not stored.is_finite() or lower > upper:
        return original
    return _Interval(lower, upper)


def _needs_monotone_enclosure(
    value: _Jet, original: _Interval, lower: Float64, upper: Float64
) -> Bool:
    return _monotone_coordinate(value) and (
        original.low < lower or original.high > upper
    )


def _monotone_junction_enclosure(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    terms: Int,
    box: Box3,
    x: _Interval,
    y: _Interval,
    z: _Interval,
    mut work: _MapBuildWork,
) raises -> Tuple[_Interval, _Interval, _Interval]:
    # The ordinary value certificate was insufficient. Admit one full
    # coordinate derivative traversal before evaluating that graph.
    work.step()
    work.term(terms)
    _reserve_lane_scalars(road, section, work)
    var point = _lane_jet(road, section, lane, low, high)
    if not (
        _needs_monotone_enclosure(
            point[0], x, Float64(box.min.x), Float64(box.max.x)
        )
        or _needs_monotone_enclosure(
            -point[1], y, Float64(box.min.y), Float64(box.max.y)
        )
        or _needs_monotone_enclosure(
            point[2], z, Float64(box.min.z), Float64(box.max.z)
        )
    ):
        return (x, y, z)
    work.step(2)
    # A monotone coordinate needs a resolved lane graph on [low, high], so
    # each endpoint's quadrature count is resolved too.
    var first_terms = _reference_work(road, low, low)
    var last_terms = _reference_work(road, high, high)
    # Reserve BOTH endpoint traversals and lane scans before either begins.
    # A refused reservation still poisons the original global work ledger.
    work.term(first_terms)
    work.term(last_terms)
    _reserve_lane_scalars(road, section, work, 2)
    var first = _lane_value_bound(road, section, lane, low, low)
    var last = _lane_value_bound(road, section, lane, high, high)
    return (
        _monotone_coordinate_enclosure(
            point[0], first[0].value, last[0].value, x
        ),
        _monotone_coordinate_enclosure(
            -point[1], -first[1].value, -last[1].value, y
        ),
        _monotone_coordinate_enclosure(
            point[2], first[2].value, last[2].value, z
        ),
    )


def _certify_junction_span(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    mut box: Box3,
    mut work: _MapBuildWork,
) raises:
    if low == high:
        box.expand_by_point(_canonical_endpoint(road, section, lane, low, work))
        return
    work.step()
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    while len(pending) > 0:
        work.step()
        var cell = pending.pop()
        var terms = _reference_work(road, cell[0], cell[1])
        var finite = False
        var x = _Interval.whole()
        var y = _Interval.whole()
        var z = _Interval.whole()
        if terms >= 0:
            work.term(terms)
            _reserve_lane_scalars(road, section, work)
            var point = _lane_value_bound(road, section, lane, cell[0], cell[1])
            x = point[0].rounded_value()
            y = -point[1].rounded_value()
            z = point[2].rounded_value()
            if z.is_finite() and z.width() > 4.0 * max(
                1.0, Float64(box.max.z) - Float64(box.min.z)
            ):
                z = _centered_elevation_enclosure(
                    road, cell[0], cell[1], z, point[2].error, work
                )
            finite = x.is_finite() and y.is_finite() and z.is_finite()
            if (
                finite
                and x.low >= Float64(box.min.x)
                and x.high <= Float64(box.max.x)
                and y.low >= Float64(box.min.y)
                and y.high <= Float64(box.max.y)
                and z.low >= Float64(box.min.z)
                and z.high <= Float64(box.max.z)
            ):
                continue
            var monotone = _monotone_junction_enclosure(
                road, section, lane, cell[0], cell[1], terms, box, x, y, z, work
            )
            x = monotone[0]
            y = monotone[1]
            z = monotone[2]
            finite = x.is_finite() and y.is_finite() and z.is_finite()
            if (
                finite
                and x.low >= Float64(box.min.x)
                and x.high <= Float64(box.max.x)
                and y.low >= Float64(box.min.y)
                and y.high <= Float64(box.max.y)
                and z.low >= Float64(box.min.z)
                and z.high <= Float64(box.max.z)
            ):
                continue
        var middle = _midpoint(cell[0], cell[1])
        if middle <= cell[0] or middle >= cell[1]:
            # The domain is stored Float64 road stations; the enclosure
            # covers their public Float32 lane-center positions. These are
            # the only two representable stations in this adjacent cell.
            box.expand_by_point(
                _canonical_endpoint(road, section, lane, cell[0], work)
            )
            box.expand_by_point(
                _canonical_endpoint(road, section, lane, cell[1], work)
            )
            continue
        if cell[2] >= 24:
            if not finite:
                raise Error(
                    "Junction canonical enclosure exhausted its numerical"
                    " subdivision limit"
                )
            # Keep the entire certified boundary enclosure. No chord or
            # point sample is used as a substitute for unresolved coverage.
            box.expand_by_point(
                Vector3(
                    _outward_float(x.low, True),
                    _outward_float(y.low, True),
                    _outward_float(z.low, True),
                )
            )
            box.expand_by_point(
                Vector3(
                    _outward_float(x.high, False),
                    _outward_float(y.high, False),
                    _outward_float(z.high, False),
                )
            )
            continue
        # Both child allocations are admitted before appending either one.
        work.step(2)
        pending.append((middle, cell[1], cell[2] + 1))
        pending.append((cell[0], middle, cell[2] + 1))


def _lane_section_box(road: Road, section: Int, lane: Int) raises -> Box3:
    var work = _MapBuildWork(MapBuildBudget())
    work.record(1)
    _preflight_road_records(road, work)
    return _lane_section_box_with_work(road, section, lane, work)


def _lane_section_box_with_work(
    road: Road, section: Int, lane: Int, mut work: _MapBuildWork
) raises -> Box3:
    road._check_lane(section, lane)
    var a = road.sections[section].s
    # Use the stored endpoint. Re-adding a rounded section length can
    # overshoot it, including for a=10.2 and road.length=50.1.
    work.step(len(road.sections))
    var b = min(road.upper_bound(a), road.length)
    if not (isfinite(a) and isfinite(b) and a >= 0.0 and b >= a):
        raise Error("A junction lane has an invalid section interval")
    if a == b:
        var point = _canonical_endpoint(road, section, lane, a, work)
        return Box3(point, point)
    var before = work.steps
    _reserve_lane_boundaries(road, section, work)
    var boundary_count = work.steps - before
    work.step(2)
    boundary_count += 2
    work.sort_work(boundary_count)
    var breaks: List[Float64] = [a, b]
    _record_breaks(breaks, road.info.geometries)
    _record_breaks(breaks, road.info.elevations)
    _record_breaks(breaks, road.info.lane_offsets)
    # The valid selected lane belongs to this nonempty lane list.
    for other in road.sections[section].lanes:  # pragma: no branch
        _record_breaks(breaks, other.info.widths)
    for record in road.info.geometries:
        _insert_break(breaks, record.s + record.geometry.length)
        for sample in record.geometry.samples:
            _insert_break(breaks, record.s + sample.s)
    var out = Box3.empty()
    # Breaks starts with both endpoints and only gains entries.
    for i in range(len(breaks) - 1):  # pragma: no branch
        # Keep both sides of a discontinuous record boundary. The previous
        # representable s is the final API input that uses the old records.
        # Breaks increase strictly within [a, b], so end > breaks[i].
        var end = bitcast[DType.float64](
            bitcast[DType.uint64](min(breaks[i + 1], b)) - 1
        )
        work.step()
        out.union(_span_box(road, section, lane, breaks[i], end, work))
    # The z bounds are padded symmetrically, so they overflow together.
    for bound in [  # pragma: no branch
        out.min.x,
        out.min.y,
        out.min.z,
        out.max.x,
        out.max.y,
        out.max.z,
    ]:
        if not isfinite(bound):
            raise Error("Junction proposal is not finite in public storage")
    # The old analytic expression is only a proposal. Prove the actual
    # canonical lane graph is covered, including both sides of record jumps.
    for i in range(len(breaks) - 1):  # pragma: no branch
        work.step()
        var start = breaks[i]
        out.expand_by_point(
            _canonical_endpoint(road, section, lane, start, work)
        )
        # Breaks increase strictly, so the open span between two breaks
        # starts no later than it ends.
        var end = bitcast[DType.float64](
            bitcast[DType.uint64](min(breaks[i + 1], b)) - 1
        )
        start = _next_up(start)
        _certify_junction_span(road, section, lane, start, end, out, work)
    out.expand_by_point(_canonical_endpoint(road, section, lane, b, work))
    return out
