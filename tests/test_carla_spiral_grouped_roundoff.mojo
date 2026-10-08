# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Adversarial controls for the fixed-count grouped error helper.

GROUP_EXACT rows support the independent stored-polynomial Fraction oracle.
The uniform guarantee comes from the separately reviewed interval proof.
"""

from extensions.carla.curve_bounds import _spiral_counts, _spiral_expression
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _ValueJet,
    _without_derivatives,
    _next_up,
    _next_down,
)
from extensions.carla.geometry import RoadGeometry, SPIRAL, LINE
from extensions.carla.lane_geometry import _lane_geometry_pos_at
from extensions.carla.spiral_roundoff_proof import (
    _try_spiral_roundoff_envelope,
)
from extensions.carla.spiral_grouped_roundoff_proof import (
    _spiral_grouped_roundoff_work,
    _try_spiral_grouped_roundoff_envelope,
    _try_spiral_grouped_roundoff_envelope_metered,
)
from math.vector3 import Vector3
from std.math import ceil, inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _geometry(rate: Float64 = 0.0025) raises -> RoadGeometry:
    var geometry = RoadGeometry(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    geometry.curvature_start = 0.0
    geometry.curvature_end = rate * geometry.length
    return geometry^


def _cell(g: RoadGeometry, d: _Jet, label: Int, export: Bool = False) raises:
    var counts = _spiral_counts(g, d)
    assert_true(counts[0] >= 1 and counts[1] <= 64)
    assert_true(counts[0] <= counts[1] and counts[1] - counts[0] <= 1)
    for n in range(counts[0], counts[1] + 1):
        var grouped = _try_spiral_grouped_roundoff_envelope(g, d, n)
        assert_true(Bool(grouped))
        var old = _try_spiral_roundoff_envelope(g, d, n)
        assert_true(Bool(old))
        var full = _spiral_expression(
            g, _without_derivatives(d), n, Vector3(0, 0, 0)
        )
        assert_true(isfinite(grouped.value()[0]))
        assert_true(isfinite(grouped.value()[1]))
        assert_true(grouped.value()[0] >= 0.0)
        assert_true(grouped.value()[1] >= 0.0)
        # These finite fixture inequalities are regression controls, not
        # the general inclusion proof or requirements for every geometry.
        assert_true(grouped.value()[0] >= full[0].error)
        assert_true(grouped.value()[1] >= full[1].error)
        assert_true(grouped.value()[0] <= old.value()[0])
        assert_true(grouped.value()[1] <= old.value()[1])
        print(
            "GROUP_BOUND",
            label,
            n,
            bitcast[DType.uint64](d.value.low),
            bitcast[DType.uint64](d.value.high),
            bitcast[DType.uint64](d.error),
            bitcast[DType.uint64](grouped.value()[0]),
            bitcast[DType.uint64](grouped.value()[1]),
            bitcast[DType.uint64](full[0].error),
            bitcast[DType.uint64](full[1].error),
        )
        for index in range(9):
            var s = (
                d.value.low
                + (d.value.high - d.value.low) * Float64(index) / 8.0
            )
            var rate = (g.curvature_end - g.curvature_start) / g.length
            var reach = max(
                abs(g.curvature_start), abs(g.curvature_start + rate * s)
            )
            var actual_count = 1 + Int(ceil(s * (1.0 + reach)))
            if actual_count != n:
                continue
            var point = _lane_geometry_pos_at(g, s)
            var ex = grouped.value()[0]
            var ey = grouped.value()[1]
            assert_true((full[0].value + _Interval(-ex, ex)).contains(point.x))
            assert_true((full[1].value + _Interval(-ey, ey)).contains(point.y))
            if export and d.error == 0.0:
                print(
                    "GROUP_EXACT",
                    label,
                    n,
                    bitcast[DType.uint64](s),
                    bitcast[DType.uint64](rate),
                    bitcast[DType.uint64](g.x),
                    bitcast[DType.uint64](g.y),
                    bitcast[DType.uint64](point.x),
                    bitcast[DType.uint64](point.y),
                    bitcast[DType.uint64](ex),
                    bitcast[DType.uint64](ey),
                )


def test_group_partition_and_work_inventory() raises:
    for n in range(1, 65):
        var groups = 0
        var original_terms = 0
        var grouped_terms = 0
        for group in range(4):
            var low = group * n // 4
            var high = (group + 1) * n // 4
            if low == high:
                continue
            groups += 1
            for weight in range(3):
                var multiplicity = 1 if weight == 2 else 2
                original_terms += (high - low) * multiplicity
                grouped_terms += 1
        assert_equal(original_terms, 5 * n)
        assert_equal(grouped_terms, 3 * groups)
        assert_equal(grouped_terms, _spiral_grouped_roundoff_work(n))
        assert_true(grouped_terms <= 5 * n)
    assert_equal(_spiral_grouped_roundoff_work(0), -1)
    assert_equal(_spiral_grouped_roundoff_work(65), -1)


def test_target_root_nested_and_count_union_cells() raises:
    var g = _geometry()
    _cell(g, _Jet.variable(17.999999999999986, 18.249999999999986), 2690, True)
    var at = Float64(18.09471066868641)
    _cell(g, _Jet.variable(at - 0.25 / 32.0, at + 0.25 / 32.0), 2691, True)
    _cell(g, _Jet.variable(at - 1e-6, at + 1e-6), 2692, True)
    _cell(g, _Jet.variable(19.75, 19.99999999999998), 2990, True)
    _cell(
        g,
        _Jet.variable(19.99999999999998 - 1e-6, 19.99999999999998),
        2991,
        True,
    )
    _cell(g, _Jet.variable(_next_down(20.0), _next_down(20.0)), 2992, True)


def test_negative_curvature_inherited_error_and_origins() raises:
    var at = Float64(18.09471066868641)
    for sign in [-1.0, 1.0]:
        var g = _geometry(sign * 0.0025)
        _cell(g, _Jet.variable(at - 1e-5, at + 1e-5), 3000, True)
    var g = _geometry()
    var d = _Jet.variable(at - 1e-7, at + 1e-7)
    var base = _try_spiral_grouped_roundoff_envelope(g, d, 20)
    assert_true(Bool(base))
    d.error = 4.0 * (_next_up(at) - at)
    var inherited = _try_spiral_grouped_roundoff_envelope(g, d, 20)
    assert_true(Bool(inherited))
    assert_true(inherited.value()[0] > base.value()[0])
    assert_true(inherited.value()[1] > base.value()[1])
    _cell(g, d, 3001)
    for origin in [1e12, -1e12, 1e20, -1e20]:
        g.x = origin
        g.y = -origin
        _cell(g, _Jet.variable(at - 1e-7, at + 1e-7), 3002, True)


def test_all_available_counts_and_empty_groups() raises:
    var g = _geometry(0.00001)
    g.length = 100.0
    g.curvature_end = 0.001
    for n in range(1, 65):
        var low = 0.1 if n == 1 else Float64(n) - 1.51
        var d = _Jet.variable(low, low + 0.01)
        # Count1 is an explicit fixed-branch arithmetic control. The canonical
        # positive-distance selector may never pick it; no selection is faked.
        var error = _try_spiral_grouped_roundoff_envelope(g, d, n)
        assert_true(Bool(error))
        var full = _spiral_expression(
            g, _without_derivatives(d), n, Vector3(0, 0, 0)
        )
        assert_true(error.value()[0] >= full[0].error)
        assert_true(error.value()[1] >= full[1].error)


def test_clamp_phase_and_structural_refusals() raises:
    var g = _geometry()
    for domain in [
        _Interval(0.0, 0.1),
        _Interval(19.9, 20.0),
        _Interval.whole(),
        _Interval(2.0, 1.0),
    ]:
        assert_false(
            Bool(
                _try_spiral_grouped_roundoff_envelope(
                    g, _Jet.variable(domain.low, domain.high), 20
                )
            )
        )
    var d = _Jet.variable(18.0, 18.1)
    for count in [0, -1, 65]:
        assert_false(Bool(_try_spiral_grouped_roundoff_envelope(g, d, count)))
    # Both origins are finite and the phase/count graph is unchanged.
    # Outward origin addition can nevertheless overflow its error envelope.
    assert_true(Bool(_try_spiral_grouped_roundoff_envelope(g, d, 20)))
    var original_x = g.x
    var original_y = g.y
    var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    g.x = maximum
    assert_false(Bool(_try_spiral_grouped_roundoff_envelope(g, d, 20)))
    g.x = original_x
    g.y = maximum
    assert_false(Bool(_try_spiral_grouped_roundoff_envelope(g, d, 20)))
    g.y = original_y
    assert_true(Bool(_try_spiral_grouped_roundoff_envelope(g, d, 20)))
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    for error in [-1.0, inf[DType.float64](), nan]:
        d.error = error
        assert_false(Bool(_try_spiral_grouped_roundoff_envelope(g, d, 20)))
    d.error = 0.0
    g.heading = 0.1
    assert_false(Bool(_try_spiral_grouped_roundoff_envelope(g, d, 20)))
    g.heading = 0.0
    g.curvature_start = 0.1
    assert_false(Bool(_try_spiral_grouped_roundoff_envelope(g, d, 20)))
    g.curvature_start = 0.0
    g.kind = LINE
    assert_false(Bool(_try_spiral_grouped_roundoff_envelope(g, d, 20)))
    g = _geometry(-0.005)
    assert_false(
        Bool(
            _try_spiral_grouped_roundoff_envelope(
                g, _Jet.variable(19.0, 19.1), 22
            )
        )
    )


def test_budget_skip_exact_admission_and_failed_attempt_debit() raises:
    var g = _geometry()
    var d = _Jet.variable(18.09, 18.10)
    var work = _spiral_grouped_roundoff_work(20)
    var spent = 7
    # Missing one optional unit must retain the ordinary 100-unit fallback.
    var skipped = _try_spiral_grouped_roundoff_envelope_metered(
        g, d, 20, spent, 118
    )
    assert_false(Bool(skipped))
    assert_equal(spent, 7)
    assert_true(5 * 20 <= 118 - spent)
    var admitted = _try_spiral_grouped_roundoff_envelope_metered(
        g, d, 20, spent, 119
    )
    assert_true(Bool(admitted))
    assert_equal(spent, 7 + work)
    assert_equal(119 - spent, 5 * 20)
    # A phase refusal after admission spends the attempt and retains exactly
    # one separately chargeable full traversal. No refund or double fallback.
    g = _geometry(-0.005)
    d = _Jet.variable(19.0, 19.1)
    spent = 3
    var failed = _try_spiral_grouped_roundoff_envelope_metered(
        g, d, 22, spent, 125
    )
    assert_false(Bool(failed))
    assert_equal(spent, 15)
    assert_equal(125 - spent, 110)
    spent += 5 * 22
    assert_equal(spent, 125)
    spent = -1
    assert_false(
        Bool(
            _try_spiral_grouped_roundoff_envelope_metered(g, d, 22, spent, 125)
        )
    )
    assert_equal(spent, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
