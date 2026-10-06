# ADAPTED table-lookup control. Original oracle words, fixtures,
# assertions and the five-second gate are retained. Only imports,
# coefficient access and the optional lookup-unit debit differ.
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""SOURCE ONLY. Bounded guard controls, not compiled or run by this author.

Keep the original TestSuite per-test five-second duration gate. Every ordinary
site obtains distance/counts from the unchanged helpers. Explicit malformed
payload/count tests below are adversarial API controls, never production callers.
"""

from extensions.carla.curve_bounds import _geometry_distance, _spiral_counts
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _next_down,
    _next_up,
)
from extensions.carla.geometry import RoadGeometry, SPIRAL, LINE
from extensions.carla.spiral_moment_table import (
    _SpiralMomentProof,
    _try_lookup_spiral_moments,
    _try_spiral_moment_expansion,
    _all_spiral_nodes_quadrant_zero,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true, assert_false


def _geometry() raises -> RoadGeometry:
    var result = RoadGeometry(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    result.curvature_end = 0.05
    return result^


def _proof(count: Int) raises -> _SpiralMomentProof:
    var spent = 0
    var found = _try_lookup_spiral_moments(count, spent, 22)
    if not found:
        raise Error("Expected bounded count payload")
    assert_equal(spent, 22)
    return found.value().copy()


def _assert_miss_site(geometry: RoadGeometry, distance: _Jet) raises:
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    var count = 4
    if counts[0] == counts[1] and counts[0] >= 1 and counts[0] <= 64:
        count = counts[0]
    var proof = _proof(count)
    var found = _try_spiral_moment_expansion(
        proof, geometry, d, counts, Vector3(0, 0, 0)
    )
    if found:
        raise Error("Unsupported site was accepted")


def test_build_allowance_below_at_and_above_exact_work() raises:
    var counts: List[Int] = [1, 3, 4, 6, 7, 22, 64]
    for count in counts:
        var work = 22
        var spent = 17
        var below = _try_lookup_spiral_moments(count, spent, 17 + work - 1)
        if below:
            raise Error("Underbudget proof was constructed")
        assert_equal(spent, 17)
        var exact = _try_lookup_spiral_moments(count, spent, 17 + work)
        if not exact:
            raise Error("Exact-budget proof was rejected")
        assert_equal(spent, 17 + work)
        spent = 17
        var above = _try_lookup_spiral_moments(count, spent, 18 + work)
        if not above:
            raise Error("Above-budget proof was rejected")
        assert_equal(spent, 17 + work)


def test_invalid_counts_and_invalid_budget_preserve_debit() raises:
    var counts: List[Int] = [-2, -1, 0, 65]
    for count in counts:
        var spent = 3
        var rejected = _try_lookup_spiral_moments(count, spent, 100000)
        if rejected:
            raise Error("Invalid or unsupported count was constructed")
        assert_equal(spent, 3)
    var negative = -1
    var no_negative = _try_lookup_spiral_moments(4, negative, 440)
    if no_negative:
        raise Error("Negative spent budget accepted")
    assert_equal(negative, -1)
    var overdrawn = 5
    var no_overdrawn = _try_lookup_spiral_moments(4, overdrawn, 4)
    if no_overdrawn:
        raise Error("Already-overdrawn budget accepted")
    assert_equal(overdrawn, 5)
    var zero = 0
    var no_negative_cap = _try_lookup_spiral_moments(4, zero, -1)
    if no_negative_cap:
        raise Error("Negative build allowance accepted")
    assert_equal(zero, 0)


def test_clamp_endpoints_and_clamp_joins_are_misses() raises:
    var geometry = _geometry()
    var stations: List[Float64] = [-1.0, -0.0, 0.0, 20.0, 21.0]
    for station in stations:
        _assert_miss_site(geometry, _Jet.variable(station, station))
    _assert_miss_site(geometry, _Jet.variable(-0.125, 0.125))
    _assert_miss_site(geometry, _Jet.variable(19.875, 20.125))


def test_count_join_and_neighbor_words_use_original_count_selector() raises:
    var geometry = _geometry()
    geometry.curvature_end = 0.0
    var words: List[Float64] = [_next_down(1.0), 1.0, _next_up(1.0)]
    for station in words:
        var d = _geometry_distance(geometry, _Jet.variable(station, station))
        var counts = _spiral_counts(geometry, d)
        assert_true(counts[0] >= 1)
        assert_true(counts[1] <= 4)
        var proof = _proof(counts[0])
        var found = _try_spiral_moment_expansion(
            proof, geometry, d, counts, Vector3(0, 0, 0)
        )
        if counts[0] != counts[1]:
            if found:
                raise Error("Rounded count join accepted")
        else:
            if not found:
                raise Error("Eligible neighbor of count join rejected")
    var crossing = _geometry_distance(geometry, _Jet.variable(0.99, 1.01))
    var joined = _spiral_counts(geometry, crossing)
    assert_true(joined[0] < joined[1])
    _assert_miss_site(geometry, _Jet.variable(0.99, 1.01))


def test_kind_heading_and_start_curvature_are_misses() raises:
    var geometry = _geometry()
    var distance = _Jet.variable(2.125, 2.125)
    geometry.kind = LINE
    _assert_miss_site(geometry, distance)
    geometry.kind = SPIRAL
    geometry.heading = 0.125
    _assert_miss_site(geometry, distance)
    geometry.heading = 0.0
    geometry.curvature_start = 0.001
    _assert_miss_site(geometry, distance)


def test_nonfinite_geometry_inputs_are_misses() raises:
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    var bad: List[Float64] = [inf[DType.float64](), -inf[DType.float64](), nan]
    var distance = _Jet.variable(2.125, 2.125)
    for value in bad:
        var length = _geometry()
        length.length = value
        _assert_miss_site(length, distance)
        var end = _geometry()
        end.curvature_end = value
        _assert_miss_site(end, distance)
        var start = _geometry()
        start.curvature_start = value
        _assert_miss_site(start, distance)
        var heading = _geometry()
        heading.heading = value
        _assert_miss_site(heading, distance)
    var nonpositive: List[Float64] = [0.0, -1.0]
    for value in nonpositive:
        var length = _geometry()
        length.length = value
        _assert_miss_site(length, distance)


def test_nonfinite_distance_error_and_unknown_derivatives_are_misses() raises:
    var geometry = _geometry()
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    var bad: List[Float64] = [inf[DType.float64](), -inf[DType.float64](), nan]
    for value in bad:
        _assert_miss_site(geometry, _Jet.variable(value, value))
        var error = _Jet.variable(2.125, 2.125)
        error.error = value
        _assert_miss_site(geometry, error)
    var first = _Jet.variable(2.125, 2.125)
    first.first = _Interval.whole()
    _assert_miss_site(geometry, first)
    var second = _Jet.variable(2.125, 2.125)
    second.second = _Interval.whole()
    _assert_miss_site(geometry, second)
    _assert_miss_site(
        geometry, _Jet.variable(-inf[DType.float64](), inf[DType.float64]())
    )


def test_unsupported_65_and_malformed_payload_or_counts_are_misses() raises:
    var geometry = _geometry()
    geometry.length = 128.0
    geometry.curvature_end = 0.0
    var d = _geometry_distance(geometry, _Jet.variable(63.5, 63.5))
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], 65)
    assert_equal(counts[0], counts[1])
    var proof = _proof(4)
    proof.pieces = counts[0]
    var unsupported = _try_spiral_moment_expansion(
        proof, geometry, d, counts, Vector3(0, 0, 0)
    )
    if unsupported:
        raise Error("Count 65 payload was accepted")
    var invalid: List[Int] = [-1, 0]
    for value in invalid:
        proof.pieces = value
        var malformed = _try_spiral_moment_expansion(
            proof, geometry, d, (value, value), Vector3(0, 0, 0)
        )
        if malformed:
            raise Error("Malformed count/payload was accepted")
    # Explicit API-adversarial mismatch, not a count supplied by a caller.
    proof = _proof(4)
    var mismatch = _try_spiral_moment_expansion(
        proof, geometry, d, (-1, -1), Vector3(0, 0, 0)
    )
    if mismatch:
        raise Error("Unknown/mismatching counts were accepted")


def test_quadrant_zero_guard_rejects_original_graph_miss() raises:
    var geometry = _geometry()
    geometry.curvature_end = 0.2
    var distance = _Jet.variable(19.0, 19.0)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_true(counts[0] <= 64)
    assert_false(_all_spiral_nodes_quadrant_zero(geometry, d, counts[0]))
    _assert_miss_site(geometry, distance)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
