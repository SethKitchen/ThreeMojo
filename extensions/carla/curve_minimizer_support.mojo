# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Outward support of rounded minima from a matching smooth ideal model.

The caller supplies one smooth ideal squared-distance branch and its uniform
error against the actual stored-center squared distance. This helper removes
only stations strictly worse than an evaluated incumbent in the same cell.
It does not prove that a smooth endpoint minimizes the rounded evaluator.
"""

from extensions.carla.curve_interval import _Interval, _Jet
from std.math import isfinite


def _ordered_finite(value: _Interval) -> Bool:
    return value.is_finite() and value.low <= value.high


def _minimizer_support(
    domain: _Jet,
    center: _Jet,
    center_s: Float64,
    best: Float64,
    low: Float64,
    high: Float64,
) -> _Interval:
    # Preconditions: the same ideal branch holds over the complete cell;
    # center encloses that branch at center_s, and best is an actual witness.
    # Only domain.error bounds the actual world-coordinate evaluator.
    var result = _Interval(low, high)
    if (
        not _ordered_finite(result)
        or not isfinite(best)
        or best < low
        or best > high
        or not isfinite(center_s)
        or center_s < low
        or center_s > high
        or not _ordered_finite(domain.value)
        or not isfinite(domain.error)
        or domain.error < 0.0
    ):
        return result
    var derivative = domain.first
    var smooth = _ordered_finite(domain.second) and _ordered_finite(
        center.first
    )
    if smooth:
        var taylor = center.first + domain.second * (
            result - _Interval.point(center_s)
        )
        if _ordered_finite(taylor):
            if _ordered_finite(derivative):
                var joined = _Interval(
                    max(derivative.low, taylor.low),
                    min(derivative.high, taylor.high),
                )
                if not _ordered_finite(joined):
                    return _Interval(low, high)
                derivative = joined
            else:
                derivative = taylor
    var twice_error = _Interval.point(2.0) * _Interval.point(domain.error)
    if _ordered_finite(derivative):
        if derivative.low > 0.0:
            var radius = twice_error / _Interval.point(derivative.low)
            if _ordered_finite(radius):
                var limit = _Interval.point(best) + _Interval.point(radius.high)
                result.high = min(result.high, limit.high)
        elif derivative.high < 0.0:
            var radius = twice_error / _Interval.point(-derivative.high)
            if _ordered_finite(radius):
                var limit = _Interval.point(best) - _Interval.point(radius.high)
                result.low = max(result.low, limit.low)
    if smooth and domain.second.low > 0.0:
        var slope = center.first + domain.second * (
            _Interval.point(best) - _Interval.point(center_s)
        )
        if _ordered_finite(slope):
            var m = _Interval.point(domain.second.low)
            var four_error = _Interval.point(4.0) * _Interval.point(
                domain.error
            )
            var a = _Interval.point(slope.low)
            var b = _Interval.point(slope.high)
            var root_a = (a.square() + four_error * m).sqrt()
            var root_b = (b.square() + four_error * m).sqrt()
            var positive = (-a + root_a) / m
            if slope.low > 0.0:
                positive = four_error / (root_a + a)
            var negative = (b + root_b) / m
            if slope.high < 0.0:
                negative = four_error / (root_b - b)
            if _ordered_finite(positive):
                var limit = _Interval.point(best) + _Interval.point(
                    positive.high
                )
                result.high = min(result.high, limit.high)
            if _ordered_finite(negative):
                var limit = _Interval.point(best) - _Interval.point(
                    negative.high
                )
                result.low = max(result.low, limit.low)
    # Each finite radius encloses a nonnegative exact radius. Outward
    # best +/- radius bounds preserve the incumbent and the original cell.
    return result
