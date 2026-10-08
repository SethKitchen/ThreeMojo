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


def _reference_minimizer_support(
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
            if _ordered_finite(radius) and radius.high >= 0.0:
                var limit = _Interval.point(best) + _Interval.point(radius.high)
                result.high = min(result.high, limit.high)
        elif derivative.high < 0.0:
            var radius = twice_error / _Interval.point(-derivative.high)
            if _ordered_finite(radius) and radius.high >= 0.0:
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
            if _ordered_finite(positive) and positive.high >= 0.0:
                var limit = _Interval.point(best) + _Interval.point(
                    positive.high
                )
                result.high = min(result.high, limit.high)
            if _ordered_finite(negative) and negative.high >= 0.0:
                var limit = _Interval.point(best) - _Interval.point(
                    negative.high
                )
                result.low = max(result.low, limit.low)
    # Defensive arithmetic refusal preserves the original conservative cover.
    if not _ordered_finite(result) or not result.contains(best):
        return _Interval(low, high)
    return result


# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.


from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.curve_bounds import _sample_index
from extensions.carla.geometry import POLY3, PARAM_POLY3
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from std.math import isfinite
from std.memory import bitcast


def _reference_sample_dispatch_predicate(
    origin: Float64, length: Float64, local: Float64, station: Float64
) -> Bool:
    return min(max(station - origin, 0.0), length) > local


def _reference_sample_dispatch_cut(
    origin: Float64, length: Float64, local: Float64
) -> Optional[Float64]:
    # The caller pre-reserves the complete three-candidate attempt.
    if not _sum2_supported_environment():
        return None
    if (
        not isfinite(origin)
        or origin < 0.0
        or not isfinite(length)
        or length <= 0.0
        or not isfinite(local)
        or local < 0.0
        or local >= length
    ):
        return None
    var start = origin + local
    if not isfinite(start) or start <= 0.0:
        return None
    var word = bitcast[DType.uint64](start)
    for i in range(3):
        var bits = word + UInt64(i)
        if bits >= UInt64(0x7FF0000000000000):
            return None
        var cut = bitcast[DType.float64](bits)
        var before = bitcast[DType.float64](bits - UInt64(1))
        if _reference_sample_dispatch_predicate(
            origin, length, local, cut
        ) and not _reference_sample_dispatch_predicate(
            origin, length, local, before
        ):
            return cut
    return None


def _reference_sample_dispatch_cuts(
    road: Road,
    low: Float64,
    high: Float64,
    mut nodes: Int,
    mut terms: Int,
    max_nodes: Int,
    max_terms: Int,
) -> Optional[Tuple[Float64, Float64, Int]]:
    if not _sum2_supported_environment():
        return None
    if not isfinite(low) or not isfinite(high) or low <= 0.0 or high < low:
        return None
    var at = info_index(road.info.geometries, low)
    if at < 0 or info_index(road.info.geometries, high) != at:
        return None
    ref record = road.info.geometries[at]
    ref geometry = record.geometry
    if geometry.kind != POLY3 and geometry.kind != PARAM_POLY3:
        return None
    if (
        len(geometry.samples) < 3
        or not isfinite(record.s)
        or record.s < 0.0
        or not isfinite(geometry.length)
        or geometry.length <= 0.0
    ):
        return None
    var dl = min(max(low - record.s, 0.0), geometry.length)
    var dh = min(max(high - record.s, 0.0), geometry.length)
    var first = _sample_index(geometry, dl)
    var last = _sample_index(geometry, dh)
    var count = last - first
    if count < 1 or count > 2:
        return None
    var extra = 8 * count
    var node_reserve = 3 * count + 2
    var term_reserve = 16 * count
    if (
        max_nodes < node_reserve
        or max_terms < 0
        or nodes < 0
        or nodes > max_nodes - node_reserve
        or terms < 0
        or terms > max_terms
        or term_reserve > max_terms - terms
    ):
        return None
    # For c cuts, retain setup + 2c visited descendants + c+1 closed-cell
    # rechecks. Each sampled descendant needs three scalar witnesses and
    # one domain reservation, in addition to the 8c optional probe units.
    # This reserves immediate followup, not completion of an arbitrary
    # remaining search. Setup follows all original node closure choices.
    # One generic node covers at most sixteen predicate/index checks and
    # constant-size packing. Eight reference-equivalent units per cut cover
    # all six possible predicate calls plus two actual sample-index checks.
    # Debit atomically before either complete optional attempt; never refund.
    nodes += 1
    terms += extra
    var one = 0.0
    var two = 0.0
    for i in range(count):
        var threshold_at = first + i + 1
        if threshold_at < 1 or threshold_at >= len(geometry.samples) - 1:
            return None
        var cut = _reference_sample_dispatch_cut(
            record.s, geometry.length, geometry.samples[threshold_at].s
        )
        if not cut:
            return None
        var station = cut.value()
        if station <= low or station > high:
            return None
        var before = bitcast[DType.float64](
            bitcast[DType.uint64](station) - UInt64(1)
        )
        var before_index = _sample_index(
            geometry, min(max(before - record.s, 0.0), geometry.length)
        )
        var after_index = _sample_index(
            geometry, min(max(station - record.s, 0.0), geometry.length)
        )
        if before_index != threshold_at - 1 or after_index != threshold_at:
            return None
        if i == 0:
            one = station
        else:
            two = station
    return (one, two, count)


from extensions.carla.curve_minimizer_support import _minimizer_support
from extensions.carla.curve_sample_dispatch import _try_sample_dispatch_cuts
from tests._sample_dispatch_controls import _dispatch_road
from std.testing import TestSuite, assert_equal, assert_true


def _compare_support(
    domain: _Jet,
    center: _Jet,
    center_s: Float64,
    best: Float64,
    low: Float64,
    high: Float64,
) raises:
    var old = _reference_minimizer_support(
        domain, center, center_s, best, low, high
    )
    var new = _minimizer_support(domain, center, center_s, best, low, high)
    assert_equal(bitcast[DType.uint64](new.low), bitcast[DType.uint64](old.low))
    assert_equal(
        bitcast[DType.uint64](new.high), bitcast[DType.uint64](old.high)
    )
    assert_true(new.contains(best))
    assert_true(new.low >= low and new.high <= high)


def test_exact_linear_and_quadratic_models_preserve_incumbent() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    for error in [Float64(0.0), -0.0, eta, 1e-300, 1e-10, 1.0, 1e100, 1e308]:
        for scale in [Float64(1e-150), 1.0, 1e150]:
            for sign in [Float64(-1.0), 1.0]:
                var slope = sign * scale
                var domain = _Jet(
                    _Interval(-scale, scale),
                    _Interval.point(slope),
                    _Interval.point(0.0),
                    error,
                )
                for station in [Float64(-1.0), -0.5, -0.0, 0.0, 0.5, 1.0]:
                    var center = _Jet(
                        _Interval.point(slope * station),
                        _Interval.point(slope),
                        _Interval.point(0.0),
                        error,
                    )
                    _compare_support(
                        domain, center, station, station, -1.0, 1.0
                    )
            var domain = _Jet(
                _Interval(0.0, scale),
                _Interval(-2.0 * scale, 2.0 * scale),
                _Interval.point(2.0 * scale),
                error,
            )
            for center_s in [Float64(-1.0), 0.0, 1.0]:
                var center = _Jet(
                    _Interval.point(scale * center_s * center_s),
                    _Interval.point(2.0 * scale * center_s),
                    _Interval.point(2.0 * scale),
                    error,
                )
                for best in [Float64(-1.0), -0.5, 0.0, 0.5, 1.0]:
                    _compare_support(domain, center, center_s, best, -1.0, 1.0)
    for sign in [Float64(-1.0), 1.0]:
        var domain = _Jet(
            _Interval(-1e308, 1e308),
            _Interval.point(sign),
            _Interval.point(0.0),
            1e308,
        )
        for best in [Float64(-1e308), 0.0, 1e308]:
            var center = _Jet(
                _Interval.point(sign * best),
                _Interval.point(sign),
                _Interval.point(0.0),
                0.0,
            )
            _compare_support(domain, center, best, best, -1e308, 1e308)


def test_real_sample_dispatch_preserves_result_and_debits() raises:
    for origin in [Float64(0.0), 0.5, 16.0, 1000000.0]:
        var road = _dispatch_road(origin)
        for low_local in [Float64(0.1), 0.9, 1.0, 1.1, 1.9, 2.1]:
            for high_local in [Float64(0.9), 1.0, 1.1, 1.9, 2.1, 2.9]:
                if high_local < low_local:
                    continue
                for budget in [0, 7, 8, 100]:
                    var old_nodes = 0
                    var new_nodes = 0
                    var old_terms = 0
                    var new_terms = 0
                    var old = _reference_sample_dispatch_cuts(
                        road,
                        origin + low_local,
                        origin + high_local,
                        old_nodes,
                        old_terms,
                        budget,
                        10000,
                    )
                    var new = _try_sample_dispatch_cuts(
                        road,
                        origin + low_local,
                        origin + high_local,
                        new_nodes,
                        new_terms,
                        budget,
                        10000,
                    )
                    assert_equal(Bool(old), Bool(new))
                    assert_equal(old_nodes, new_nodes)
                    assert_equal(old_terms, new_terms)
                    if old:
                        assert_equal(old.value()[0], new.value()[0])
                        assert_equal(old.value()[1], new.value()[1])
                        assert_equal(old.value()[2], new.value()[2])
                        assert_true(new.value()[0] > origin + low_local)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
