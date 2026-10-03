# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite global refinement and admission certificates for lane curves.

The numerical expressions live in curve_bounds. This module owns finite
local work and accuracy limits. An unresolved interval raises an Error. It
never reports an off-road result or a partially searched minimum.
"""

from extensions.carla.curve_bounds import _distance_jet, _lane_jet, _reference_work
from extensions.carla.curve_interval import _Interval, _Jet, _next_down, _next_up
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.math import inf, isfinite, sqrt


def _better(
    candidate: Float64, distance: Float64, best: Float64, best_distance: Float64
) -> Bool:
    return distance < best_distance


def _checked_distance(
    road: Road, section: Int, lane: Int, s: Float64, location: Vector3,
    mut terms: Int, max_terms: Int,
) raises -> Float64:
    var work = _reference_work(road, s, s)
    if work < 0:
        raise Error("Lane refinement cannot resolve the quadrature count")
    if terms > max_terms - work:
        raise Error("Lane refinement exhausted its quadrature work limit")
    terms += work
    var distance = road._lane_distance_squared(section, lane, s, location)
    if not isfinite(distance):
        raise Error("Lane refinement cannot bound a non-finite center distance")
    return distance


def _local_seed(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    location: Vector3, best: Float64, best_distance: Float64,
    mut terms: Int, max_terms: Int,
) raises -> Tuple[Float64, Float64]:
    comptime ratio = Float64(0.6180339887498948482)
    var lo = low
    var hi = high
    var one = hi - ratio * (hi - lo)
    var two = lo + ratio * (hi - lo)
    var d1 = _checked_distance(road, section, lane, one, location, terms, max_terms)
    var d2 = _checked_distance(road, section, lane, two, location, terms, max_terms)
    var steps = 0
    while steps < 40:
        steps += 1
        if d1 <= d2:
            hi = two
            two = one
            d2 = d1
            one = hi - ratio * (hi - lo)
            d1 = _checked_distance(road, section, lane, one, location, terms, max_terms)
        else:
            lo = one
            one = two
            d1 = d2
            two = lo + ratio * (hi - lo)
            d2 = _checked_distance(road, section, lane, two, location, terms, max_terms)
    var result = best
    var distance = best_distance
    if _better(one, d1, result, distance):
        result = one
        distance = d1
    if _better(two, d2, result, distance):
        result = two
        distance = d2
    return (result, distance)


def _global_lower(
    domain: _Jet, center: _Jet, delta: _Interval
) -> Float64:
    var natural = domain.rounded_value().low
    if not domain.second.is_finite() or not center.first.is_finite():
        return max(0.0, natural)
    # Taylor's theorem for the actual stored polynomial/rational expression.
    # The separately propagated scalar evaluation error remains in the bound.
    var taylor = center.value + center.first * delta + (
        _Interval.point(0.5) * domain.second * delta.square()
    )
    var lower = max(natural, _next_down(taylor.low - domain.error))
    if domain.second.low > 0.0:
        # Strong convexity supplies a global lower bound from any center.
        # This uses the polynomial derivative, not ideal trig identities.
        var correction = center.first.square() / (
            _Interval.point(2.0) * _Interval.point(domain.second.low)
        )
        var convex = center.value - correction
        lower = max(lower, _next_down(convex.low - domain.error))
    return max(0.0, lower)


def _accuracy(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    best: Float64, best_distance: Float64,
) raises -> Float64:
    # A distance-squared gap contract, not a new lane-width acceptance test.
    # It scales down with every positive width; there is no minimum width.
    var scale = high - low
    var width = abs(road.lane_width(section, lane, best))
    if width > 0.0:
        scale = min(scale, width)
    var spatial = _Interval.point(scale) * _Interval.point(0.00000095367431640625)
    var rounding = _Interval.point(64.0) * _Interval.point(
        _next_up(best_distance) - best_distance
    )
    return (spatial.square() + rounding).high


def _refine_lane(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    location: Vector3, seed: Float64, seed_distance: Float64,
    max_nodes: Int = 16384, max_terms: Int = 2000000, max_depth: Int = 96,
) raises -> Tuple[Float64, Float64]:
    var best = seed
    var best_distance = seed_distance
    var nodes = 0
    var terms = 0
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    while len(pending) > 0:
        if nodes >= max_nodes:
            raise Error("Lane refinement exhausted its interval work limit")
        nodes += 1
        var task = pending.pop()
        var lo = task[0]
        var hi = task[1]
        var middle = lo + (hi - lo) * 0.5
        var sample = middle
        var edge = 0
        while edge < 3:
            if edge == 1:
                sample = lo
            elif edge == 2:
                sample = hi
            var distance = _checked_distance(
                road, section, lane, sample, location, terms, max_terms
            )
            if _better(sample, distance, best, best_distance):
                best = sample
                best_distance = distance
            edge += 1
        if middle <= lo or middle >= hi:
            # The domain has no other Float64 parameter. Both actual endpoint
            # values were compared, including signed-zero/tangent branches.
            continue
        var work = _reference_work(road, lo, hi)
        if work >= 0:
            if terms > max_terms - work:
                raise Error("Lane refinement exhausted its quadrature work limit")
            terms += work
            var domain = _distance_jet(road, section, lane, lo, hi, location)
            var natural = max(0.0, domain.rounded_value().low)
            if natural > best_distance:
                continue
            if domain.second.low > 0.0:
                var local = _local_seed(
                    road, section, lane, lo, hi, location, best, best_distance,
                    terms, max_terms,
                )
                best = local[0]
                best_distance = local[1]
            var center_s = min(max(best, lo), hi)
            var center_work = _reference_work(road, center_s, center_s)
            if center_work >= 0:
                if terms > max_terms - center_work:
                    raise Error("Lane refinement exhausted its quadrature work limit")
                terms += center_work
                var center = _distance_jet(road, section, lane, center_s, center_s, location)
                var delta = _Interval(lo, hi) - _Interval.point(center_s)
                var lower = _global_lower(domain, center, delta)
                var tolerance = _accuracy(
                    road, section, lane, low, high, best, best_distance
                )
                if _next_up(best_distance - lower) <= tolerance:
                    continue
        if task[2] >= max_depth:
            raise Error("Lane refinement exhausted its numerical accuracy limit")
        # A repeated root or a branch is retained unless its full distance
        # enclosure has been resolved. A derivative sign is not enough.
        pending.append((middle, hi, task[2] + 1))
        pending.append((lo, middle, task[2] + 1))
    return (best, best_distance)


def _length_up(x: Float64, y: Float64, z: Float64) -> Float64:
    return (
        _Interval.point(x).square()
        + _Interval.point(y).square()
        + _Interval.point(z).square()
    ).sqrt().high


def _chord_error(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    start: Vector3, end: Vector3, max_terms: Int = 2000000,
) raises -> Float64:
    var work = _reference_work(road, low, high)
    if work < 0 or work > max_terms:
        return inf[DType.float64]()
    var point = _lane_jet(road, section, lane, low, high)
    # Any point in the curve box and any point of the chord give a valid,
    # possibly loose, deviation bound. This remains valid at branch jumps.
    var x = point[0].rounded_value() - _Interval(
        min(Float64(start.x), Float64(end.x)), max(Float64(start.x), Float64(end.x))
    )
    var y = -point[1].rounded_value() - _Interval(
        min(Float64(start.y), Float64(end.y)), max(Float64(start.y), Float64(end.y))
    )
    var z = point[2].rounded_value() - _Interval(
        min(Float64(start.z), Float64(end.z)), max(Float64(start.z), Float64(end.z))
    )
    var natural = _length_up(x.magnitude(), y.magnitude(), z.magnitude())
    var derivative = _length_up(
        point[0].second.magnitude(), point[1].second.magnitude(), point[2].second.magnitude()
    )
    if not isfinite(derivative):
        return natural
    var first = road._lane_point(section, lane, low)
    var last = road._lane_point(section, lane, high)
    var conversion = _length_up(
        max(abs(first.x - Float64(start.x)), abs(last.x - Float64(end.x))),
        max(abs(-first.y - Float64(start.y)), abs(-last.y - Float64(end.y))),
        max(abs(first.z - Float64(start.z)), abs(last.z - Float64(end.z))),
    )
    var evaluation = _length_up(point[0].error, point[1].error, point[2].error)
    var span = _Interval.point(high) - _Interval.point(low)
    # For each scalar twice differentiable function, the linear-interpolant
    # error is at most h^2*sup|f''|/8. Roundoff at the curve and both endpoint
    # evaluations adds at most twice the uniform evaluator error.
    var smooth = (
        span.square() * _Interval.point(0.125) * _Interval.point(derivative)
        + _Interval.point(2.0) * _Interval.point(evaluation)
        + _Interval.point(conversion)
    ).high
    return min(natural, smooth)


def _admission_roundoff(scale: Float64, deviation: Float64) -> Float64:
    # RTree uses Float64 arithmetic on finite Float32 endpoints and query.
    # A clamped scalar projection t lies in [0,1] regardless of its condition.
    # Endpoint subtraction, multiplication and residual subtraction give
    # <11u*M error per axis. Squared norm and sqrt contribute <28u*M more;
    # the Euclidean total is <48u*M. Box bounds are <16u*M. Two 64u bounds
    # cover the index distance and the best center distance. No transcendental
    # assumption or sampled chord tolerance enters this allowance.
    return (
        _Interval.point(1.4210854715202004e-14)
        * (_Interval.point(scale) + _Interval.point(deviation))
    ).high
