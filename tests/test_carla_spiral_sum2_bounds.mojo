# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent stored-graph containment and frozen ideal-field controls.

Uniform cells, count joins, world origins, and full/value/envelope paths.
The separate Python Fraction oracle checks exported scalar errors against
exact stored polynomials. No tolerance or repository test gate is changed.
"""

from extensions.carla.curve_bounds import (
    _geometry_distance,
    _reference_jet,
    _spiral_counts,
    _spiral_expression,
    _expansion_distance_jet,
)
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _ValueJet,
    _without_derivatives,
    _next_up,
    _next_down,
)
from extensions.carla.curve_sum2 import _sum2_error
from extensions.carla.geometry import RoadGeometry, SPIRAL, LINE
from extensions.carla.lane_geometry import _lane_geometry_pos_at
from extensions.carla.spiral_roundoff_proof import (
    _try_spiral_roundoff_envelope,
    _sum2_envelope_error,
)
from math.vector3 import Vector3
from std.math import ceil, inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._spiral_full_jet_reference import _FullJet
from tests._spiral_half_error_reference import _half_reference_spiral
from tests._spiral_domain_controls import _road


def _bits(a: Float64, b: Float64) raises:
    assert_equal(bitcast[DType.uint64](a), bitcast[DType.uint64](b))


def _interval(a: _Interval, b: _Interval) raises:
    _bits(a.low, b.low)
    _bits(a.high, b.high)


def _geometry(
    heading: Float64,
    k0: Float64,
    k1: Float64,
    origin: Float64 = 0.0,
    length: Float64 = 100.0,
) raises -> RoadGeometry:
    var g = RoadGeometry(SPIRAL, 0.0, origin, -origin, heading, length)
    g.curvature_start = k0
    g.curvature_end = k1
    return g^


def _fields(full: _Jet, light: _ValueJet, frozen: _FullJet) raises:
    _interval(full.value, light.value)
    _bits(full.error, light.error)
    _interval(full.rounded_value(), light.rounded_value())
    assert_false(light.first.is_finite())
    assert_false(light.second.is_finite())
    _interval(full.value, frozen.value)
    _interval(full.first, frozen.first)
    _interval(full.second, frozen.second)


def _fixed_branch(g: RoadGeometry, d: _Jet, count: Int, tr: Vector3) raises:
    var full = _spiral_expression(g, d, count, tr)
    var light = _spiral_expression(g, _without_derivatives(d), count, tr)
    var frozen = _half_reference_spiral(
        g, _FullJet(d.value, d.first, d.second, d.error), count, tr
    )
    _fields(full[0], light[0], frozen[0])
    _fields(full[1], light[1], frozen[1])
    _fields(full[2], light[2], frozen[2])
    _bits(full[2].error, frozen[2].error)


def _union_fields(whole: _Jet, first: _ValueJet, last: _ValueJet) raises:
    _interval(whole.value, first.rounded_value().hull(last.rounded_value()))
    _bits(whole.error, 0.0)
    assert_false(whole.first.is_finite())
    assert_false(whole.second.is_finite())


def _cell(
    g: RoadGeometry,
    low: Float64,
    high: Float64,
    label: Int,
    envelope: Bool = False,
    export: Bool = False,
) raises:
    assert_true(low < high)
    var d = _geometry_distance(g, _Jet.variable(low, high))
    var counts = _spiral_counts(g, d)
    if counts[0] < 1 or counts[1] - counts[0] > 1:
        print("UNSUPPORTED_CELL", label, counts[0], counts[1])
    assert_true(counts[0] >= 1 and counts[1] - counts[0] <= 1)
    var zero = Vector3(0, 0, 0)
    var whole = _reference_jet(g, _Jet.variable(low, high), zero)
    for count in range(counts[0], counts[1] + 1):
        _fixed_branch(g, d, count, zero)
        var branch = _spiral_expression(g, d, count, zero)
        var errors = _try_spiral_roundoff_envelope(g, d, count)
        if envelope:
            assert_true(Bool(errors))
        for step in range(17):
            var s = low + (high - low) * Float64(step) / 16.0
            var scalar = _lane_geometry_pos_at(g, s)
            assert_true(whole[0].rounded_value().contains(scalar.x))
            assert_true(whole[1].rounded_value().contains(scalar.y))
            assert_true(whole[2].rounded_value().contains(scalar.tangent))
            var at = min(max(s, 0.0), g.length)
            var rate = (g.curvature_end - g.curvature_start) / g.length
            var reach = max(
                abs(g.curvature_start), abs(g.curvature_start + rate * at)
            )
            var actual_count = 1 + Int(ceil(at * (1.0 + reach)))
            if actual_count != count:
                continue
            assert_true(branch[0].rounded_value().contains(scalar.x))
            assert_true(branch[1].rounded_value().contains(scalar.y))
            var ex = inf[DType.float64]()
            var ey = inf[DType.float64]()
            if errors:
                ex = errors.value()[0]
                ey = errors.value()[1]
                assert_true(
                    (branch[0].value + _Interval(-ex, ex)).contains(scalar.x)
                )
                assert_true(
                    (branch[1].value + _Interval(-ey, ey)).contains(scalar.y)
                )
            if export and step % 4 == 0:
                print(
                    "EXACT",
                    label,
                    count,
                    bitcast[DType.uint64](s),
                    bitcast[DType.uint64](g.heading),
                    bitcast[DType.uint64](g.curvature_start),
                    bitcast[DType.uint64](rate),
                    bitcast[DType.uint64](g.x),
                    bitcast[DType.uint64](g.y),
                    bitcast[DType.uint64](scalar.x),
                    bitcast[DType.uint64](scalar.y),
                    bitcast[DType.uint64](branch[0].error),
                    bitcast[DType.uint64](branch[1].error),
                    bitcast[DType.uint64](ex),
                    bitcast[DType.uint64](ey),
                )
    if counts[0] != counts[1]:
        var first = _spiral_expression(
            g, _without_derivatives(d), counts[0], zero
        )
        var last = _spiral_expression(
            g, _without_derivatives(d), counts[1], zero
        )
        _union_fields(whole[0], first[0], last[0])
        _union_fields(whole[1], first[1], last[1])
        _union_fields(whole[2], first[2], last[2])


def test_uniform_full_value_and_envelope_all_admitted_counts() raises:
    for count in range(2, 65):
        var middle = Float64(count) - 1.5
        for sign in [-1.0, 1.0]:
            var g = _geometry(0.0, 0.0, sign * 0.001)
            _cell(g, middle - 0.01, middle + 0.01, count, True)


def test_exact_error_exports_positive_negative_and_large_origins() raises:
    for origin in [0.0, 1e6, -1e6, 1e20, -1e20]:
        for sign in [-1.0, 1.0]:
            var g = _geometry(0.0, 0.0, sign * 0.05, origin, 20.0)
            _cell(g, 2.125, 2.25, 100, True, True)


def test_count_join_cells_keep_both_branches() raises:
    var g = _geometry(0.0, 0.01, 0.01, 1000000.0)
    for n in [1.0, 3.0, 16.0, 30.0]:
        var cut = n / 1.01
        _cell(g, cut - 1e-7, cut + 1e-7, 200, False, True)
    g = _geometry(0.0, 0.0, 0.0)
    for n in [1.0, 3.0, 16.0, 30.0]:
        _cell(g, _next_down(n), _next_up(n), 201, True, True)


def test_mixed_sign_quadrants_and_cancellation_cells() raises:
    for heading in [-3.141592653589793, -1.57, 1.57, 3.141592653589793]:
        var g = _geometry(heading, 0.3, -0.3, 0.0, 20.0)
        _cell(g, 10.125, 10.15, 300, False, True)
    var g = _geometry(0.0, 1.0, 1.0, 0.0, 20.0)
    _cell(g, 6.28, 6.29, 301, False, True)
    _cell(g, 12.56, 12.57, 302, False, True)


def test_clamp_zero_and_small_subnormal_cells() raises:
    var g = _geometry(0.0, 0.0, 0.001, 0.0, 20.0)
    # Outward multiplication at the zero clamp may include a negative
    # underflow unit. Existing count guards must retain unknown/refusal.
    var crossing = _geometry_distance(g, _Jet.variable(-0.01, 0.01))
    assert_equal(_spiral_counts(g, crossing)[0], -1)
    var unknown = _reference_jet(
        g, _Jet.variable(-0.01, 0.01), Vector3(0, 0, 0)
    )
    assert_false(unknown[0].rounded_value().is_finite())
    _cell(g, -0.02, -0.01, 400)
    _cell(g, 19.99, 20.01, 401)
    var tiny = bitcast[DType.float64](UInt64(1))
    g = _geometry(-0.0, tiny, tiny, 0.0, 20.0)
    _cell(g, tiny, 2.0 * tiny, 402)
    _cell(g, 1e-300, 1.01e-300, 403)


def test_translated_ideal_fields_and_world_error_separation() raises:
    for origin in [1e6, -1e6, 1e20, -1e20, 1e30]:
        var g = _geometry(0.0, 0.0, 0.05, origin, 20.0)
        var d = _geometry_distance(g, _Jet.variable(2.125, 2.25))
        var counts = _spiral_counts(g, d)
        var tr = Vector3(Float32(origin), Float32(origin), 0)
        _fixed_branch(g, d, counts[0], tr)
        var road = _road(g.copy())
        var translated = _expansion_distance_jet(road, 0, 0, 2.1875, tr, 1.0)
        assert_false(isfinite(translated.error))
        _cell(g, 2.125, 2.25, 500, True)


def test_unsupported_sum2_and_envelope_inputs_refuse() raises:
    var tiny = bitcast[DType.float64](UInt64(1))
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    for count in [0, -1, 1073741825]:
        assert_false(isfinite(_sum2_error(1.0, 0.0, count)))
    for bad in [-1.0, inf[DType.float64](), nan, 1e300]:
        assert_false(isfinite(_sum2_error(bad, 0.0, 2)))
    for bad in [-1.0, inf[DType.float64](), nan]:
        assert_false(isfinite(_sum2_error(1.0, bad, 2)))
    _bits(_sum2_error(0.0, tiny, 2), tiny)
    _bits(_sum2_error(1.0, tiny, 1), tiny)
    assert_true(isfinite(_sum2_error(8.452712498170644e270, 0.0, 1073741824)))
    var term = _ValueJet(
        _Interval(-tiny, tiny), _Interval.whole(), _Interval.whole(), tiny
    )
    assert_true(_sum2_envelope_error(term, 320, 0.0) >= 320.0 * tiny)
    for count in [0, 321]:
        assert_false(isfinite(_sum2_envelope_error(term, count, 0.0)))
    assert_false(isfinite(_sum2_envelope_error(term, 5, inf[DType.float64]())))
    term.error = -1.0
    assert_false(isfinite(_sum2_envelope_error(term, 5, 0.0)))
    term = _ValueJet.constant(1e300)
    assert_false(isfinite(_sum2_envelope_error(term, 320, 0.0)))


def test_envelope_geometry_domain_refusals() raises:
    var g = _geometry(0.0, 0.0, 0.05, 0.0, 20.0)
    var d = _Jet.variable(0.1, 0.2)
    for count in [0, 65]:
        assert_false(Bool(_try_spiral_roundoff_envelope(g, d, count)))
    for heading in [-0.1, 0.1, inf[DType.float64]()]:
        g.heading = heading
        assert_false(Bool(_try_spiral_roundoff_envelope(g, d, 2)))
    g.heading = 0.0
    g.curvature_start = 0.1
    assert_false(Bool(_try_spiral_roundoff_envelope(g, d, 2)))
    g.curvature_start = 0.0
    for length in [0.0, -1.0, inf[DType.float64]()]:
        g.length = length
        assert_false(Bool(_try_spiral_roundoff_envelope(g, d, 2)))
    g.length = 20.0
    for interval in [
        _Interval(0.0, 0.2),
        _Interval(19.0, 20.0),
        _Interval.whole(),
    ]:
        assert_false(
            Bool(
                _try_spiral_roundoff_envelope(
                    g, _Jet.variable(interval.low, interval.high), 2
                )
            )
        )
    g.curvature_end = 200.0
    assert_false(Bool(_try_spiral_roundoff_envelope(g, _Jet.variable(5, 6), 7)))
    g.curvature_end = 0.05
    g.kind = LINE
    assert_false(Bool(_try_spiral_roundoff_envelope(g, d, 2)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
