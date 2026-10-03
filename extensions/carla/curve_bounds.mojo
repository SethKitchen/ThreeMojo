# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Expression bounds for the actual CARLA lane-center evaluator.

Record selection, geometry clamping, sampled interpolation, quadrature piece
counts, and local scalar trig branches are part of the bound. A non-smooth
branch has no finite derivative certificate. Search policy and work limits
live in lane_refinement, not here.
"""

from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_trig import (
    _atan2_jet,
    _atan_jet,
    _curve_cos,
    _curve_atan2,
    _curve_sin,
    _sincos_jet,
    _sinc_jet,
    _uncertain,
)
from extensions.carla.geometry import (
    ARC, LINE, PARAM_POLY3, SPIRAL, RoadGeometry, _GL_NODES, _GL_WEIGHTS,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from math.vector3 import Vector3
from std.math import ceil, isfinite


def _polynomial_jet(polynomial: CubicPolynomial, s: _Jet) -> _Jet:
    return _Jet.constant(polynomial.a) + s * (
        _Jet.constant(polynomial.b) + s * (
            _Jet.constant(polynomial.c) + s * _Jet.constant(polynomial.d)
        )
    )


def _square_jet(value: _Jet) -> _Jet:
    var result = value * value
    result.value = value.value.square()
    return result


def _unknown_point() -> Tuple[_Jet, _Jet, _Jet]:
    var unknown = _uncertain(_Interval.whole())
    return (unknown, unknown, unknown)


def _geometry_distance(geometry: RoadGeometry, distance: _Jet) -> _Jet:
    var domain = distance.rounded_value()
    if domain.high <= 0.0:
        return _Jet.constant(0.0)
    if domain.low >= geometry.length:
        return _Jet.constant(geometry.length)
    if domain.low >= 0.0 and domain.high <= geometry.length:
        return distance
    return _uncertain(
        _Interval(max(domain.low, 0.0), min(domain.high, geometry.length))
    )


def _spiral_counts(geometry: RoadGeometry, d: _Jet) -> Tuple[Int, Int]:
    var k0 = geometry.curvature_start
    var rate = (geometry.curvature_end - k0) / geometry.length
    var reach = (
        _Jet.constant(k0) + _Jet.constant(rate) * d
    ).rounded_value().absolute().maximum(_Interval.point(abs(k0)))
    var counts = d.rounded_value() * (_Interval.point(1.0) + reach)
    if not counts.is_finite() or counts.low < 0.0 or counts.high > 1e9:
        # No Int conversion of an unbounded value. The caller must split
        # or report exhaustion, rather than claim a missing branch is empty.
        return (-1, -1)
    return (1 + Int(ceil(counts.low)), 1 + Int(ceil(counts.high)))


def _spiral_jet(
    geometry: RoadGeometry, d: _Jet, pieces: Int
) -> Tuple[_Jet, _Jet, _Jet]:
    var k0 = _Jet.constant(geometry.curvature_start)
    var rate = _Jet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var step = d / _Jet.constant(Float64(pieces))
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    var x = _Jet.constant(geometry.x)
    var y = _Jet.constant(geometry.y)
    var piece = 0
    while piece < pieces:
        var start = step * _Jet.constant(Float64(piece))
        var i = 0
        while i < 5:
            var t = start + step * _Jet.constant(0.5) * _Jet.constant(1.0 + nodes[i])
            var theta = _Jet.constant(geometry.heading) + t * (
                k0 + _Jet.constant(0.5) * rate * t
            )
            var trig = _sincos_jet(theta)
            x = x + step * _Jet.constant(0.5) * _Jet.constant(weights[i]) * trig[1]
            y = y + step * _Jet.constant(0.5) * _Jet.constant(weights[i]) * trig[0]
            i += 1
        piece += 1
    var heading = _Jet.constant(geometry.heading) + d * (
        k0 + _Jet.constant(0.5) * rate * d
    )
    return (x, y, heading)


def _sample_index(geometry: RoadGeometry, d: Float64) -> Int:
    var low = 0
    var high = len(geometry.samples) - 1
    while high - low > 1:
        var middle = (low + high) // 2
        if geometry.samples[middle].s < d:
            low = middle
        else:
            high = middle
    return low


def _sample_jet(
    geometry: RoadGeometry, d: _Jet, index: Int
) -> Tuple[_Jet, _Jet, _Jet]:
    var one = geometry.samples[index]
    var two = geometry.samples[index + 1]
    # The same expression and endpoint convention as RoadGeometry._sampled.
    var rate = (_Jet.constant(two.s) - d) / _Jet.constant(two.s - one.s)
    var complement = _Jet.constant(1.0) - rate
    var u = rate * _Jet.constant(one.u) + complement * _Jet.constant(two.u)
    var v = rate * _Jet.constant(one.v) + complement * _Jet.constant(two.v)
    var tu = rate * _Jet.constant(one.tu) + complement * _Jet.constant(two.tu)
    var tv = rate * _Jet.constant(one.tv) + complement * _Jet.constant(two.tv)
    var heading = _atan_jet(tv)
    if geometry.kind == PARAM_POLY3:
        heading = _atan2_jet(tv, tu)
        var domain = d.rounded_value()
        if domain.low >= one.s and domain.high <= two.s:
            if one.tv == 0.0 and two.tv == 0.0:
                if one.tu > 0.0 and two.tu > 0.0:
                    heading = _Jet.constant(_curve_atan2(one.tv + two.tv, 1.0))
                elif one.tu < 0.0 and two.tu < 0.0:
                    heading = _Jet.constant(_curve_atan2(one.tv + two.tv, -1.0))
                elif one.tu == 0.0 and two.tu == 0.0:
                    heading = _Jet.constant(_curve_atan2(one.tv + two.tv, one.tu + two.tu))
    var c = _Jet.constant(_curve_cos(geometry.heading))
    var s = _Jet.constant(_curve_sin(geometry.heading))
    return (
        _Jet.constant(geometry.x) + u * c - v * s,
        _Jet.constant(geometry.y) + v * c + u * s,
        _Jet.constant(geometry.heading) + heading,
    )


def _union_points(
    one: Tuple[_Jet, _Jet, _Jet], two: Tuple[_Jet, _Jet, _Jet]
) -> Tuple[_Jet, _Jet, _Jet]:
    return (
        _uncertain(one[0].rounded_value().hull(two[0].rounded_value())),
        _uncertain(one[1].rounded_value().hull(two[1].rounded_value())),
        _uncertain(one[2].rounded_value().hull(two[2].rounded_value())),
    )


def _arc_offset_jet(
    geometry: RoadGeometry, d: _Jet, offset: _Jet
) -> Tuple[_Jet, _Jet, _Jet]:
    var radius = 1.0 / geometry.curvature_start
    var k = _Jet.constant(geometry.curvature_start)
    var turn = d * k
    var half = turn * _Jet.constant(0.5)
    var phase = _Jet.constant(geometry.heading) + half
    var factor = (_Jet.constant(radius) + offset) * k * d
    if not isfinite(radius):
        factor = (_Jet.constant(1.0) + offset * k) * d
    var chord = factor * _sinc_jet(half)
    var trig = _sincos_jet(phase)
    return (
        _Jet.constant(geometry.x) + offset * _Jet.constant(_curve_sin(geometry.heading)) + chord * trig[1],
        _Jet.constant(geometry.y) - offset * _Jet.constant(_curve_cos(geometry.heading)) + chord * trig[0],
        _Jet.constant(geometry.heading) + turn,
    )


def _reference_jet(
    geometry: RoadGeometry, distance: _Jet
) -> Tuple[_Jet, _Jet, _Jet]:
    var d = _geometry_distance(geometry, distance)
    if geometry.kind == LINE:
        return (
            _Jet.constant(geometry.x) + d * _Jet.constant(_curve_cos(geometry.heading)),
            _Jet.constant(geometry.y) + d * _Jet.constant(_curve_sin(geometry.heading)),
            _Jet.constant(geometry.heading),
        )
    if geometry.kind == ARC:
        return _arc_offset_jet(geometry, d, _Jet.constant(0.0))
    if geometry.kind == SPIRAL:
        var counts = _spiral_counts(geometry, d)
        if counts[0] < 1 or counts[1] - counts[0] > 1:
            return _unknown_point()
        var first = _spiral_jet(geometry, d, counts[0])
        if counts[0] == counts[1]:
            return first
        # A piece-count transition is an actual evaluator discontinuity.
        return _union_points(first, _spiral_jet(geometry, d, counts[1]))
    if len(geometry.samples) < 2:
        return _unknown_point()
    var domain = d.rounded_value()
    var low = _sample_index(geometry, domain.low)
    var high = _sample_index(geometry, domain.high)
    if high - low > 1:
        return _unknown_point()
    var first = _sample_jet(geometry, d, low)
    if low == high:
        return first
    return _union_points(first, _sample_jet(geometry, d, high))


def _reference_work(road: Road, low: Float64, high: Float64) -> Int:
    # Bound the number of Gauss nodes before evaluating the interval.
    # -1 denotes an unresolved integer domain; no work is attempted there.
    var at = info_index(road.info.geometries, low)
    if at < 0 or info_index(road.info.geometries, high) != at:
        return -1
    ref record = road.info.geometries[at]
    if record.geometry.kind != SPIRAL:
        return 1
    var d = _geometry_distance(
        record.geometry, _Jet.variable(low, high) - _Jet.constant(record.s)
    )
    var counts = _spiral_counts(record.geometry, d)
    if counts[0] < 1 or counts[1] - counts[0] > 1:
        return -1
    if counts[0] == counts[1]:
        return 5 * counts[0]
    return 5 * (counts[0] + counts[1])


def _lane_jet(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64
) raises -> Tuple[_Jet, _Jet, _Jet]:
    var geometry_at = info_index(road.info.geometries, low)
    var elevation_at = info_index(road.info.elevations, low)
    var offset_at = info_index(road.info.lane_offsets, low)
    if geometry_at < 0 or elevation_at < 0 or offset_at < 0:
        raise Error("A lane bound needs geometry, elevation and offset records")
    if (
        info_index(road.info.geometries, high) != geometry_at
        or info_index(road.info.elevations, high) != elevation_at
        or info_index(road.info.lane_offsets, high) != offset_at
    ):
        return _unknown_point()
    var s = _Jet.variable(low, high)
    var offset = _Jet.constant(0.0)
    ref lanes = road.sections[section].lanes
    var lane_id = lanes[lane].id
    var negative = lane_id.value < 0
    var sign = _Jet.constant(1.0 if negative else -1.0)
    if lane_id.value != 0:
        var position = 0
        var done = False
        while position < len(lanes) and not done:
            var i = len(lanes) - 1 - position if negative else position
            position += 1
            if negative:
                if lanes[i].id.value >= 0:
                    continue
            elif lanes[i].id.value < 1:
                continue
            var width_at = info_index(lanes[i].info.widths, low)
            if width_at < 0:
                raise Error("A lane bound needs a width record")
            if info_index(lanes[i].info.widths, high) != width_at:
                return _unknown_point()
            var width = _polynomial_jet(lanes[i].info.widths[width_at].polynomial, s)
            if lanes[i].id != lane_id:
                offset = offset + sign * width
            else:
                offset = offset + sign * width * _Jet.constant(0.5)
                done = True
    offset = offset - _polynomial_jet(road.info.lane_offsets[offset_at].polynomial, s)
    ref record = road.info.geometries[geometry_at]
    var point = _reference_jet(record.geometry, s - _Jet.constant(record.s))
    if record.geometry.kind == ARC:
        var d = _geometry_distance(record.geometry, s - _Jet.constant(record.s))
        var arc = _arc_offset_jet(record.geometry, d, offset)
        return (
            arc[0], arc[1],
            _polynomial_jet(road.info.elevations[elevation_at].polynomial, s),
        )
    var trig = _sincos_jet(point[2])
    return (
        point[0] + offset * trig[0],
        point[1] - offset * trig[1],
        _polynomial_jet(road.info.elevations[elevation_at].polynomial, s),
    )


def _distance_jet(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    location: Vector3,
) raises -> _Jet:
    var point = _lane_jet(road, section, lane, low, high)
    var x = point[0] - _Jet.constant(Float64(location.x))
    var y = -point[1] - _Jet.constant(Float64(location.y))
    var z = point[2] - _Jet.constant(Float64(location.z))
    return _square_jet(x) + _square_jet(y) + _square_jet(z)
