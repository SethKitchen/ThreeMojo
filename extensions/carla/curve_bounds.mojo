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

from extensions.carla.curve_interval import (
    _tight_sum_bound,
    _tight_quotient_bound,
    _tight_square_bound,
    _Interval,
    _Jet,
    _JetExpression,
    _without_derivatives,
    _power_quotient_bound,
)
from extensions.carla.curve_trig import (
    _constant_sincos_jet,
    _atan2_jet,
    _atan_jet,
    _curve_cos,
    _curve_atan2,
    _curve_sin,
    _sincos_jet,
    _sincos_expression,
    _sinc_jet,
    _uncertain,
)
from extensions.carla.geometry import (
    ARC,
    LINE,
    PARAM_POLY3,
    SPIRAL,
    RoadGeometry,
    _GL_NODES,
    _GL_WEIGHTS,
)
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _SpiralDomainProof,
    _spiral_proof_matches,
    _spiral_proof_branch,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from math.vector3 import Vector3
from std.math import ceil, inf, isfinite


def _polynomial_jet(
    polynomial: CubicPolynomial, s: _Jet, shift: Float64 = 0.0
) -> _Jet:
    return (_Jet.constant(polynomial.a) - _Jet.constant(shift)) + s * (
        _Jet.constant(polynomial.b)
        + s * (_Jet.constant(polynomial.c) + s * _Jet.constant(polynomial.d))
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
        (_Jet.constant(k0) + _Jet.constant(rate) * d)
        .rounded_value()
        .absolute()
        .maximum(_Interval.point(abs(k0)))
    )
    var counts = d.rounded_value() * (_Interval.point(1.0) + reach)
    if not counts.is_finite() or counts.low < 0.0 or counts.high > 1e9:
        # No Int conversion of an unbounded value. The caller must split
        # or report exhaustion, rather than claim a missing branch is empty.
        return (-1, -1)
    return (1 + Int(ceil(counts.low)), 1 + Int(ceil(counts.high)))


def _spiral_jet(
    geometry: RoadGeometry, d: _Jet, pieces: Int, translation: Vector3
) -> Tuple[_Jet, _Jet, _Jet]:
    return _spiral_expression(geometry, d, pieces, translation)


def _spiral_expression[derivatives: Bool](
    geometry: RoadGeometry,
    d: _JetExpression[derivatives],
    pieces: Int,
    translation: Vector3,
) -> Tuple[
    _JetExpression[derivatives],
    _JetExpression[derivatives],
    _JetExpression[derivatives],
]:
    comptime Expression = _JetExpression[derivatives]
    var k0 = Expression.constant(geometry.curvature_start)
    var rate = Expression.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var step = d / Expression.constant(Float64(pieces))
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    var x = Expression.constant(0.0)
    var y = Expression.constant(0.0)
    var piece = 0
    while piece < pieces:
        var start = step * Expression.constant(Float64(piece))
        var i = 0
        while i < 5:
            var t = (
                start
                + step * Expression.constant(0.5)
                * Expression.constant(1.0 + nodes[i])
            )
            var theta = Expression.constant(geometry.heading) + t * (
                k0 + Expression.constant(0.5) * rate * t
            )
            var trig = _sincos_expression(theta)
            x = (
                x
                + step
                * Expression.constant(0.5)
                * Expression.constant(weights[i])
                * trig[1]
            )
            y = (
                y
                + step
                * Expression.constant(0.5)
                * Expression.constant(weights[i])
                * trig[0]
            )
            i += 1
        piece += 1
    var heading = Expression.constant(geometry.heading) + d * (
        k0 + Expression.constant(0.5) * rate * d
    )
    return (
        (
            Expression.constant(geometry.x)
            - Expression.constant(Float64(translation.x))
        ) + x,
        (
            Expression.constant(geometry.y)
            + Expression.constant(Float64(translation.y))
        ) + y,
        heading,
    )


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


def _intersect_ideal_bounds(one: _Interval, two: _Interval) -> _Interval:
    var low = max(one.low, two.low)
    var high = min(one.high, two.high)
    if not low <= high:
        return _Interval.whole()
    return _Interval(low, high)


def _sample_blend_jet(rate: _Jet, one: Float64, two: Float64) -> _Jet:
    # Scalar evaluation retains the original weighted expression. Its error
    # bounds that graph, including permitted contraction. Only the ideal real
    # value and derivatives use the algebraically identical local expression.
    var result = rate * _Jet.constant(one) + (
        _Jet.constant(1.0) - rate
    ) * _Jet.constant(two)
    var ideal = _Jet.constant(two) + rate * (
        _Jet.constant(one) - _Jet.constant(two)
    )
    # Both expressions enclose the same exact real quantity. Intersection
    # also retains the original finite enclosure if the local difference
    # overflows even though the weighted expression remains bounded.
    result.value = _intersect_ideal_bounds(result.value, ideal.value)
    result.first = _intersect_ideal_bounds(result.first, ideal.first)
    result.second = _intersect_ideal_bounds(result.second, ideal.second)
    return result


def _sample_jet(
    geometry: RoadGeometry, d: _Jet, index: Int, translation: Vector3
) -> Tuple[_Jet, _Jet, _Jet]:
    var one = geometry.samples[index]
    var two = geometry.samples[index + 1]
    # The same expression and endpoint convention as RoadGeometry._sampled.
    var rate = (_Jet.constant(two.s) - d) / _Jet.constant(two.s - one.s)
    var u = _sample_blend_jet(rate, one.u, two.u)
    var v = _sample_blend_jet(rate, one.v, two.v)
    var tu = _sample_blend_jet(rate, one.tu, two.tu)
    var tv = _sample_blend_jet(rate, one.tv, two.tv)
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
                    heading = _Jet.constant(
                        _curve_atan2(one.tv + two.tv, one.tu + two.tu)
                    )
    var c = _Jet.constant(_curve_cos(geometry.heading))
    var s = _Jet.constant(_curve_sin(geometry.heading))
    return (
        (_Jet.constant(geometry.x) - _Jet.constant(Float64(translation.x)))
        + u * c
        - v * s,
        (_Jet.constant(geometry.y) + _Jet.constant(Float64(translation.y)))
        + v * c
        + u * s,
        _Jet.constant(geometry.heading) + heading,
    )


def _union_points[derivatives: Bool](
    one: Tuple[
        _JetExpression[derivatives],
        _JetExpression[derivatives],
        _JetExpression[derivatives],
    ],
    two: Tuple[
        _JetExpression[derivatives],
        _JetExpression[derivatives],
        _JetExpression[derivatives],
    ],
) -> Tuple[_Jet, _Jet, _Jet]:
    return (
        _uncertain(one[0].rounded_value().hull(two[0].rounded_value())),
        _uncertain(one[1].rounded_value().hull(two[1].rounded_value())),
        _uncertain(one[2].rounded_value().hull(two[2].rounded_value())),
    )


def _arc_offset_jet(
    geometry: RoadGeometry, d: _Jet, offset: _Jet, translation: Vector3
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
        (_Jet.constant(geometry.x) - _Jet.constant(Float64(translation.x)))
        + offset * _Jet.constant(_curve_sin(geometry.heading))
        + chord * trig[1],
        (_Jet.constant(geometry.y) + _Jet.constant(Float64(translation.y)))
        - offset * _Jet.constant(_curve_cos(geometry.heading))
        + chord * trig[0],
        _Jet.constant(geometry.heading) + turn,
    )


def _reference_jet(
    geometry: RoadGeometry, distance: _Jet, translation: Vector3
) -> Tuple[_Jet, _Jet, _Jet]:
    var captured = _SpiralRootCapture()
    return _reference_jet_capture[False](geometry, distance, translation, captured)


def _reference_jet_capture[capture: Bool](
    geometry: RoadGeometry, distance: _Jet, translation: Vector3,
    mut captured: _SpiralRootCapture,
) -> Tuple[_Jet, _Jet, _Jet]:
    var d = _geometry_distance(geometry, distance)
    if geometry.kind == LINE:
        # These coefficients are fixed across this LINE's parameter domain.
        # Enclose all allowed scalar contractions instead of treating one
        # sampled call-site result as the only possible coefficient.
        var direction = _constant_sincos_jet(geometry.heading)
        return (
            (_Jet.constant(geometry.x) - _Jet.constant(Float64(translation.x)))
            + d * direction[1],
            (_Jet.constant(geometry.y) + _Jet.constant(Float64(translation.y)))
            + d * direction[0],
            _Jet.constant(geometry.heading),
        )
    if geometry.kind == ARC:
        return _arc_offset_jet(geometry, d, _Jet.constant(0.0), translation)
    if geometry.kind == SPIRAL:
        var counts = _spiral_counts(geometry, d)
        if counts[0] < 1 or counts[1] - counts[0] > 1:
            return _unknown_point()
        if counts[0] == counts[1]:
            var point = _spiral_jet(geometry, d, counts[0], translation)
            comptime if capture:
                captured.d = d
                captured.first_count = counts[0]
                captured.last_count = counts[1]
                captured.first_x_error = point[0].error
                captured.first_y_error = point[1].error
                captured.last_x_error = point[0].error
                captured.last_y_error = point[1].error
            return point
        # A piece-count transition is an actual evaluator discontinuity.
        # Its union discards both branches' derivatives. Evaluate the same
        # value/error graphs without that derivative arithmetic. Keep the
        # clamped ideal value and its error separate at this boundary.
        var source = _without_derivatives(d)
        var first = _spiral_expression(geometry, source, counts[0], translation)
        var last = _spiral_expression(geometry, source, counts[1], translation)
        comptime if capture:
            captured.d = d
            captured.first_count = counts[0]
            captured.last_count = counts[1]
            captured.first_x_error = first[0].error
            captured.first_y_error = first[1].error
            captured.last_x_error = last[0].error
            captured.last_y_error = last[1].error
        return _union_points(first, last)
    if len(geometry.samples) < 2:
        return _unknown_point()
    var domain = d.rounded_value()
    var low = _sample_index(geometry, domain.low)
    var high = _sample_index(geometry, domain.high)
    if high - low > 1:
        return _unknown_point()
    var first = _sample_jet(geometry, d, low, translation)
    if low == high:
        return first
    return _union_points(first, _sample_jet(geometry, d, high, translation))


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


def _lane_jet_model(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    translation: Vector3,
) raises -> Tuple[_Jet, _Jet, _Jet]:
    var captured = _SpiralRootCapture()
    return _lane_jet_model_proof[False](
        road, section, lane, low, high, translation, None, low, high, captured
    )


def _lane_jet_capture(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    mut captured: _SpiralRootCapture,
) raises -> Tuple[_Jet, _Jet, _Jet]:
    captured = _SpiralRootCapture()
    return _lane_jet_model_proof[True](
        road, section, lane, low, high, Vector3(0, 0, 0), None, low, high, captured
    )


def _lane_jet_with_proof(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    root_low: Float64, root_high: Float64,
    proof: Optional[_SpiralDomainProof],
) raises -> Tuple[_Jet, _Jet, _Jet]:
    var captured = _SpiralRootCapture()
    return _lane_jet_model_proof[False](
        road, section, lane, low, high, Vector3(0, 0, 0), proof,
        root_low, root_high, captured,
    )


def _finite_spiral_moment_jet(value: _Jet) -> Bool:
    # Trusted producers retain finite nonnegative X/Y errors and reconstruct
    # fresh heading with the original graph. A finite rounded enclosure
    # therefore also establishes finite ideal value; do not check it twice.
    return (
        value.first.is_finite()
        and value.second.is_finite()
        and value.rounded_value().is_finite()
    )


def _finite_spiral_moment_branch(point: Tuple[_Jet, _Jet, _Jet]) -> Bool:
    # Inspect each smooth fixed-count branch BEFORE the intentional count
    # union discards derivatives. Reordering can overflow intermediates even
    # when the original node-scaled GL expression has finite derivatives.
    return (
        _finite_spiral_moment_jet(point[0])
        and _finite_spiral_moment_jet(point[1])
        and _finite_spiral_moment_jet(point[2])
    )


def _lane_jet_model_proof[capture: Bool](
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    translation: Vector3,
    proof: Optional[_SpiralDomainProof],
    root_low: Float64,
    root_high: Float64,
    mut captured: _SpiralRootCapture,
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
            var width = _polynomial_jet(
                lanes[i].info.widths[width_at].polynomial, s
            )
            if lanes[i].id != lane_id:
                offset = offset + sign * width
            else:
                offset = offset + sign * width * _Jet.constant(0.5)
                done = True
    offset = offset - _polynomial_jet(
        road.info.lane_offsets[offset_at].polynomial, s
    )
    ref record = road.info.geometries[geometry_at]
    var reused: Optional[Tuple[_Jet, _Jet, _Jet]] = None
    comptime if not capture:
        if proof:
            # A proof is zero-translation only. Generic translated expansion
            # retains its existing operation graph and infinite final error.
            if (
                record.geometry.kind == SPIRAL
                and proof.value().record_at == geometry_at
                and translation.x == 0.0
                and translation.y == 0.0
                and translation.z == 0.0
            ):
                var d = _geometry_distance(
                    record.geometry, s - _Jet.constant(record.s)
                )
                var counts = _spiral_counts(record.geometry, d)
                if _spiral_proof_matches(
                    proof.value(), record.geometry, geometry_at, low, high,
                    root_low, root_high, d, counts,
                ):
                    var first = _spiral_proof_branch(
                        proof.value(), record.geometry, d, counts[0]
                    )
                    if _finite_spiral_moment_branch(first):
                        if counts[0] == counts[1]:
                            reused = first
                        else:
                            var last = _spiral_proof_branch(
                                proof.value(), record.geometry, d, counts[1]
                            )
                            if _finite_spiral_moment_branch(last):
                                reused = _union_points(first, last)
                    # A nonfinite reordered branch leaves reuse absent. The
                    # original reference below runs under the same already
                    # reserved/debited work; no altered error or union is used.
    var point: Tuple[_Jet, _Jet, _Jet]
    if reused:
        point = reused.value()
    else:
        point = _reference_jet_capture[capture](
            record.geometry, s - _Jet.constant(record.s), translation, captured
        )
    comptime if capture:
        captured.record_at = geometry_at
        captured.low = low
        captured.high = high
    if record.geometry.kind == ARC:
        var d = _geometry_distance(record.geometry, s - _Jet.constant(record.s))
        var arc = _arc_offset_jet(record.geometry, d, offset, translation)
        return (
            arc[0],
            arc[1],
            _polynomial_jet(
                road.info.elevations[elevation_at].polynomial,
                s,
                Float64(translation.z),
            ),
        )
    var trig: Tuple[_Jet, _Jet]
    if record.geometry.kind == LINE:
        # Structural provenance: the reference tangent is exactly the stored
        # geometry heading, regardless of changing lane widths and offsets.
        trig = _constant_sincos_jet(record.geometry.heading)
    else:
        trig = _sincos_jet(point[2])
    return (
        point[0] + offset * trig[0],
        point[1] - offset * trig[1],
        _polynomial_jet(
            road.info.elevations[elevation_at].polynomial,
            s,
            Float64(translation.z),
        ),
    )


def _lane_jet(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64
) raises -> Tuple[_Jet, _Jet, _Jet]:
    # Zero translation retains the actual scalar evaluator's operation errors.
    return _lane_jet_model(road, section, lane, low, high, Vector3(0, 0, 0))


def _distance_jet(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
) raises -> _Jet:
    var point = _lane_jet(road, section, lane, low, high)
    var x = point[0] - _Jet.constant(Float64(location.x))
    var y = -point[1] - _Jet.constant(Float64(location.y))
    var z = point[2] - _Jet.constant(Float64(location.z))
    return _square_jet(x) + _square_jet(y) + _square_jet(z)


def _scaled_coordinate_jet(point: _Jet, query: Float64, scale: Float64) -> _Jet:
    # The target is the exact real distance between stored center coordinates.
    # Query subtraction and normalization are mathematical operations here;
    # they are not additional rounded operations of the center evaluator.
    var divisor = _Interval.point(scale)
    return _Jet(
        _tight_quotient_bound(
            _tight_sum_bound(point.value, -_Interval.point(query)), divisor
        ),
        _power_quotient_bound(point.first, divisor),
        _power_quotient_bound(point.second, divisor),
        (_Interval.point(point.error) / divisor).high,
    )


def _point_square_jet(value: _Jet) -> _Jet:
    var twice = _Interval.point(2.0)
    var error = _Interval.point(value.error)
    # For the actual coordinate X+delta, |delta|<=E:
    # |(X+delta)^2-X^2| <= 2*|X|*E+E^2. Value interval arithmetic encloses
    # the ideal expression; only the actual center's scalar error is added.
    return _Jet(
        _tight_square_bound(value.value),
        twice * value.value * value.first,
        twice * (value.first.square() + value.value * value.second),
        (
            twice * _Interval.point(value.value.magnitude()) * error
            + error.square()
        ).high,
    )


def _scaled_point_distance_jet(
    point: Tuple[_Jet, _Jet, _Jet], location: Vector3, scale: Float64
) -> _Jet:
    # Derivatives describe the continuous stored-polynomial center. Its
    # separate scalar-rounding enclosure also bounds the rounded staircase.
    # No scalar rounding is invented for the exact point-distance predicate.
    var x = _point_square_jet(
        _scaled_coordinate_jet(point[0], Float64(location.x), scale)
    )
    var y = _point_square_jet(
        _scaled_coordinate_jet(-point[1], Float64(location.y), scale)
    )
    var z = _point_square_jet(
        _scaled_coordinate_jet(point[2], Float64(location.z), scale)
    )
    return _Jet(
        _tight_sum_bound(_tight_sum_bound(x.value, y.value), z.value),
        x.first + y.first + z.first,
        x.second + y.second + z.second,
        (
            _Interval.point(x.error)
            + _Interval.point(y.error)
            + _Interval.point(z.error)
        ).high,
    )


def _scaled_point_distance_box(
    point: Tuple[_Jet, _Jet, _Jet], location: Vector3, scale: Float64
) -> _Interval:
    # Direct value enclosure also works when derivative arithmetic overflows.
    # Positive infinite lower distances can still exclude a distant interval.
    var divisor = _Interval.point(scale)
    var x = (
        point[0].rounded_value() - _Interval.point(Float64(location.x))
    ) / divisor
    var y = (
        -point[1].rounded_value() - _Interval.point(Float64(location.y))
    ) / divisor
    var z = (
        point[2].rounded_value() - _Interval.point(Float64(location.z))
    ) / divisor
    var result = x.square() + y.square() + z.square()
    return _Interval(max(0.0, result.low), max(0.0, result.high))


def _expansion_distance_jet(
    road: Road,
    section: Int,
    lane: Int,
    s: Float64,
    location: Vector3,
    scale: Float64,
) raises -> _Jet:
    # Translate constant origins in the IDEAL expression before interval
    # evaluation, to avoid losing its small relative value to world-coordinate
    # cancellation. Constant translation does not change its derivatives.
    var relative = _lane_jet_model(road, section, lane, s, s, location)
    var result = _scaled_point_distance_jet(relative, Vector3(0, 0, 0), scale)
    # This translated model is only an expansion value/derivative enclosure.
    # Its hypothetical scalar error is NOT the actual world evaluator error.
    # _global_lower retains the original domain.error for that difference.
    # Infinity prevents accidental reuse as a standalone rounded-value bound.
    result.error = inf[DType.float64]()
    return result


def _lane_width_box(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64
) raises -> _Interval:
    # Bound the actual rounded width expression, not an ideal half-width.
    ref widths = road.sections[section].lanes[lane].info.widths
    var at = info_index(widths, low)
    if at < 0:
        raise Error("A lane classification needs a width record")
    if info_index(widths, high) != at:
        return _Interval.whole()
    return _polynomial_jet(
        widths[at].polynomial, _Jet.variable(low, high)
    ).rounded_value()


def _scaled_plan_width_box(
    point: Tuple[_Jet, _Jet, _Jet],
    width: _Interval,
    location: Vector3,
    scale: Float64,
) -> _Interval:
    # Sign of 4*plan_distance^2-width^2 for every stored center and width.
    # Division precedes multiplication, so tiny positive widths do not vanish.
    var divisor = _Interval.point(scale)
    var x = (
        point[0].rounded_value() - _Interval.point(Float64(location.x))
    ) / divisor
    var y = (
        -point[1].rounded_value() - _Interval.point(Float64(location.y))
    ) / divisor
    var diameter = width / divisor
    return _Interval.point(4.0) * (x.square() + y.square()) - diameter.square()
