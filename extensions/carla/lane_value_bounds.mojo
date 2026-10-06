# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Private derivative-elided value/error bounds for sampled lane covers.

This follows the full sampled Jet's value, scalar-error and branch graph.
Unused derivative fields remain whole and must never be used as a proof.
No scalar evaluator, stored literal, domain selection or work cap changes.
"""

from extensions.carla.curve_interval import _Interval, _ValueJet
from extensions.carla.curve_bounds import _sample_index, _intersect_ideal_bounds
from extensions.carla.curve_trig import (
    _expression_polynomial,
    _uncertain_expression,
    _sincos_expression,
    _PI,
    _HALF_PI,
    _QUARTER_PI,
    _ATAN_REDUCE,
    _ATAN_COEFFICIENTS,
    _sign_bit,
    _curve_cos,
    _curve_sin,
    _curve_atan2,
)
from extensions.carla.geometry import RoadGeometry, PARAM_POLY3, POLY3
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from math.vector3 import Vector3


def _uncertain_value(value: _Interval) -> _ValueJet:
    return _uncertain_expression[False](value)


def _atan_value_branch(
    value: _ValueJet, inverse: Bool, shifted: Bool
) -> _ValueJet:
    var magnitude = value
    if inverse:
        magnitude = _ValueJet.constant(1.0) / magnitude
    if shifted:
        magnitude = (magnitude - _ValueJet.constant(1.0)) / (
            magnitude + _ValueJet.constant(1.0)
        )
    var result = magnitude * _expression_polynomial(
        materialize[_ATAN_COEFFICIENTS](), magnitude * magnitude
    )
    if shifted:
        result = _ValueJet.constant(_QUARTER_PI) + result
    if inverse:
        result = _ValueJet.constant(_HALF_PI) - result
    return result


def _atan_value(value: _ValueJet) -> _ValueJet:
    var domain = value.rounded_value()
    if not domain.is_finite():
        return _uncertain_value(_Interval(-_HALF_PI, _HALF_PI))
    if domain.low < 0.0 and domain.high > 0.0:
        # The sign join is continuous but rounded scalar evaluations are
        # bounded separately. Its derivative is not used to prune.
        var left = _atan_value(_ValueJet.variable(0.0, -domain.low))
        var right = _atan_value(_ValueJet.variable(0.0, domain.high))
        return _uncertain_value(
            (-left.rounded_value()).hull(right.rounded_value())
        )
    var negative = domain.high <= 0.0
    var source = -value if negative else value
    var positive = source.rounded_value()
    var inverse = positive.low >= 1.0 and positive.high > 1.0
    if positive.low < 1.0 and positive.high > 1.0:
        var before = _atan_value(_ValueJet.variable(positive.low, 1.0))
        var after = _atan_value(_ValueJet.variable(1.0, positive.high))
        var bound = before.rounded_value().hull(after.rounded_value())
        return _uncertain_value(-bound if negative else bound)
    var reduced = _ValueJet.constant(1.0) / source if inverse else source
    var reduction = reduced.rounded_value()
    if reduction.low <= _ATAN_REDUCE and reduction.high > _ATAN_REDUCE:
        # Both recipes cover this fixed source interval. This is finite
        # work, including when the endpoint equals the branch threshold.
        var one = _atan_value_branch(source, inverse, False).rounded_value()
        var two = _atan_value_branch(source, inverse, True).rounded_value()
        var bound = one.hull(two)
        return _uncertain_value(-bound if negative else bound)
    var result = _atan_value_branch(
        source, inverse, reduction.low > _ATAN_REDUCE
    )
    return -result if negative else result


def _atan2_value(y: _ValueJet, x: _ValueJet) -> _ValueJet:
    var dx = x.rounded_value()
    var dy = y.rounded_value()
    if not dx.is_finite() or not dy.is_finite():
        return _uncertain_value(_Interval(-_PI, _PI))
    if dy.is_point(0.0) and not dx.contains(0.0):
        if dx.low > 0.0:
            return y
        if _sign_bit(dy.low) != _sign_bit(dy.high):
            return _uncertain_value(_Interval(-_PI, _PI))
        var angle = -_PI if _sign_bit(dy.low) else _PI
        return _ValueJet.constant(angle)
    if dx.is_point(0.0) and not dy.contains(0.0):
        return _ValueJet.constant(-_HALF_PI if dy.high < 0.0 else _HALF_PI)
    var bx = dx.absolute()
    var by = dy.absolute()
    if bx.low >= by.high and not dx.contains(0.0):
        var result = _atan_value(y / x)
        if dx.low > 0.0:
            return result
        if dy.low > 0.0:
            return _ValueJet.constant(_PI) + result
        if dy.high < 0.0:
            return _ValueJet.constant(-_PI) + result
        # The negative-axis winding cut contains both one-sided headings.
        return _uncertain_value(_Interval(-_PI, _PI))
    if by.low > bx.high:
        var result = _atan_value(x / y)
        if dy.low > 0.0:
            return _ValueJet.constant(_HALF_PI) - result
        return _ValueJet.constant(-_HALF_PI) - result
    if dx.contains(0.0) or dy.contains(0.0):
        # An internal stationary tangent has no single continuous heading.
        return _uncertain_value(_Interval(-_PI, _PI))
    var one = _atan_value(y / x)
    if dx.high < 0.0:
        one = _ValueJet.constant(_PI if dy.low > 0.0 else -_PI) + one
    var two = _ValueJet.constant(
        _HALF_PI if dy.low > 0.0 else -_HALF_PI
    ) - _atan_value(x / y)
    # Include both scalar recipes where the magnitude comparison changes.
    return _uncertain_value(one.rounded_value().hull(two.rounded_value()))


def _polynomial_value(
    polynomial: CubicPolynomial, s: _ValueJet, shift: Float64 = 0.0
) -> _ValueJet:
    return (
        _ValueJet.constant(polynomial.a) - _ValueJet.constant(shift)
    ) + s * (
        _ValueJet.constant(polynomial.b)
        + s
        * (
            _ValueJet.constant(polynomial.c)
            + s * _ValueJet.constant(polynomial.d)
        )
    )


def _unknown_value_point() -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
    var unknown = _uncertain_value(_Interval.whole())
    return (unknown, unknown, unknown)


def _value_geometry_distance(
    geometry: RoadGeometry, distance: _ValueJet
) -> _ValueJet:
    var domain = distance.rounded_value()
    if domain.high <= 0.0:
        return _ValueJet.constant(0.0)
    if domain.low >= geometry.length:
        return _ValueJet.constant(geometry.length)
    if domain.low >= 0.0 and domain.high <= geometry.length:
        return distance
    return _uncertain_value(
        _Interval(max(domain.low, 0.0), min(domain.high, geometry.length))
    )


def _sample_blend_value(
    rate: _ValueJet, one: Float64, two: Float64
) -> _ValueJet:
    # Scalar evaluation retains the original weighted expression. Its error
    # bounds that graph, including permitted contraction. Only the ideal real
    # value and derivatives use the algebraically identical local expression.
    var result = rate * _ValueJet.constant(one) + (
        _ValueJet.constant(1.0) - rate
    ) * _ValueJet.constant(two)
    var ideal = _ValueJet.constant(two) + rate * (
        _ValueJet.constant(one) - _ValueJet.constant(two)
    )
    # Both expressions enclose the same exact real quantity. Intersection
    # also retains the original finite enclosure if the local difference
    # overflows even though the weighted expression remains bounded.
    result.value = _intersect_ideal_bounds(result.value, ideal.value)
    return result


def _sample_value(
    geometry: RoadGeometry, d: _ValueJet, index: Int, translation: Vector3
) -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
    var one = geometry.samples[index]
    var two = geometry.samples[index + 1]
    # The same expression and endpoint convention as RoadGeometry._sampled.
    var rate = (_ValueJet.constant(two.s) - d) / _ValueJet.constant(
        two.s - one.s
    )
    var u = _sample_blend_value(rate, one.u, two.u)
    var v = _sample_blend_value(rate, one.v, two.v)
    var tu = _sample_blend_value(rate, one.tu, two.tu)
    var tv = _sample_blend_value(rate, one.tv, two.tv)
    var heading = _atan_value(tv)
    if geometry.kind == PARAM_POLY3:
        heading = _atan2_value(tv, tu)
        var domain = d.rounded_value()
        if domain.low >= one.s and domain.high <= two.s:
            # Convex nonnegative weights preserve positive-zero vertical
            # samples. A strict rounded horizontal sign therefore fixes
            # atan2 even when the stored horizontal endpoints disagree.
            var horizontal = tu.rounded_value()
            if (
                one.tv == 0.0
                and two.tv == 0.0
                and not _sign_bit(one.tv)
                and not _sign_bit(two.tv)
            ):
                if horizontal.low > 0.0:
                    heading = _ValueJet.constant(0.0)
                elif horizontal.high < 0.0:
                    heading = _ValueJet.constant(_curve_atan2(0.0, -1.0))
            if one.tv == 0.0 and two.tv == 0.0:
                if one.tu > 0.0 and two.tu > 0.0:
                    heading = _ValueJet.constant(
                        _curve_atan2(one.tv + two.tv, 1.0)
                    )
                elif one.tu < 0.0 and two.tu < 0.0:
                    heading = _ValueJet.constant(
                        _curve_atan2(one.tv + two.tv, -1.0)
                    )
                elif one.tu == 0.0 and two.tu == 0.0:
                    heading = _ValueJet.constant(
                        _curve_atan2(one.tv + two.tv, one.tu + two.tu)
                    )
    var c = _ValueJet.constant(_curve_cos(geometry.heading))
    var s = _ValueJet.constant(_curve_sin(geometry.heading))
    return (
        (
            _ValueJet.constant(geometry.x)
            - _ValueJet.constant(Float64(translation.x))
        )
        + u * c
        - v * s,
        (
            _ValueJet.constant(geometry.y)
            + _ValueJet.constant(Float64(translation.y))
        )
        + v * c
        + u * s,
        _ValueJet.constant(geometry.heading) + heading,
    )


def _reference_sampled_value(
    geometry: RoadGeometry, distance: _ValueJet, translation: Vector3
) -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
    if geometry.kind != POLY3 and geometry.kind != PARAM_POLY3:
        return _unknown_value_point()
    var d = _value_geometry_distance(geometry, distance)
    if len(geometry.samples) < 2:
        return _unknown_value_point()
    var domain = d.rounded_value()
    var low = _sample_index(geometry, domain.low)
    var high = _sample_index(geometry, domain.high)
    if high - low > 1:
        return _unknown_value_point()
    var first = _sample_value(geometry, d, low, translation)
    if low == high:
        return first
    return _union_value_points(
        first, _sample_value(geometry, d, high, translation)
    )


def _union_value_points(
    one: Tuple[_ValueJet, _ValueJet, _ValueJet],
    two: Tuple[_ValueJet, _ValueJet, _ValueJet],
) -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
    return (
        _uncertain_value(one[0].rounded_value().hull(two[0].rounded_value())),
        _uncertain_value(one[1].rounded_value().hull(two[1].rounded_value())),
        _uncertain_value(one[2].rounded_value().hull(two[2].rounded_value())),
    )


def _sampled_lane_value_bound(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
) raises -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
    var translation = Vector3(0, 0, 0)
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
        return _unknown_value_point()
    var s = _ValueJet.variable(low, high)
    var offset = _ValueJet.constant(0.0)
    ref lanes = road.sections[section].lanes
    var lane_id = lanes[lane].id
    var negative = lane_id.value < 0
    var sign = _ValueJet.constant(1.0 if negative else -1.0)
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
                return _unknown_value_point()
            var width = _polynomial_value(
                lanes[i].info.widths[width_at].polynomial, s
            )
            if lanes[i].id != lane_id:
                offset = offset + sign * width
            else:
                offset = offset + sign * width * _ValueJet.constant(0.5)
                done = True
    offset = offset - _polynomial_value(
        road.info.lane_offsets[offset_at].polynomial, s
    )
    ref record = road.info.geometries[geometry_at]
    var point = _reference_sampled_value(
        record.geometry, s - _ValueJet.constant(record.s), translation
    )
    var trig = _sincos_expression(point[2])
    return (
        point[0] + offset * trig[0],
        point[1] - offset * trig[1],
        _polynomial_value(
            road.info.elevations[elevation_at].polynomial,
            s,
            Float64(translation.z),
        ),
    )
