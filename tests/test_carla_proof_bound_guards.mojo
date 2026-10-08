# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent rejection controls for private numerical proof boundaries.

Each malformed input changes one guard operand from an accepted baseline.
Rejected preconditions preserve the accumulators. Arithmetic overflow must
return an unknown bound rather than a finite proof.
"""

from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _ValueJet,
    _stored_half,
    _stored_difference,
    _stored_blend_error,
)
from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.geometry import LINE
from extensions.carla.spiral_grouped_roundoff_proof import (
    _grouped_term,
    _grouped_origin_error,
    _spiral_grouped_domain_rate,
    _try_spiral_grouped_roundoff_envelope_metered,
)
from extensions.carla.spiral_roundoff_proof import (
    _sum2_envelope_error,
    _try_spiral_roundoff_envelope,
)
from extensions.carla.spiral_moment_proof import _all_spiral_nodes_quadrant_zero
from std.math import inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._spiral_domain_controls import _geometry


def test_grouped_term_rejects_each_invalid_input_before_mutation() raises:
    for kind in range(7):
        var term = _ValueJet.constant(2.0)
        var count = 3
        if kind == 1:
            count = 0
        elif kind == 2:
            count = 321
        elif kind == 3:
            term.value = _Interval.whole()
        elif kind == 4:
            term.value = _Interval(3.0, 2.0)
        elif kind == 5:
            term.error = inf[DType.float64]()
        elif kind == 6:
            term.error = -1.0
        var ideal = _Interval.point(0.0)
        var magnitude = _Interval.point(0.0)
        var inherited = _Interval.point(0.0)
        var accepted = _grouped_term(term, count, ideal, magnitude, inherited)
        assert_equal(accepted, kind == 0)
        if accepted:
            assert_true(ideal.contains(6.0))
            assert_true(magnitude.contains(6.0))
            assert_true(inherited.is_point(0.0))
        else:
            assert_true(ideal.is_point(0.0))
            assert_true(magnitude.is_point(0.0))
            assert_true(inherited.is_point(0.0))


def test_grouped_term_rounded_and_accumulator_overflow_are_unknown() raises:
    var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var term = _ValueJet.constant(maximum)
    term.error = maximum
    var ideal = _Interval.point(0.0)
    var magnitude = _Interval.point(0.0)
    var inherited = _Interval.point(0.0)
    assert_false(_grouped_term(term, 1, ideal, magnitude, inherited))
    assert_true(ideal.is_point(0.0))
    assert_true(magnitude.is_point(0.0))
    assert_true(inherited.is_point(0.0))
    for kind in range(3):
        term = _ValueJet.constant(1.0)
        term.error = 0.25
        ideal = _Interval.whole() if kind == 0 else _Interval.point(0.0)
        magnitude = _Interval.whole() if kind == 1 else _Interval.point(0.0)
        inherited = _Interval.whole() if kind == 2 else _Interval.point(0.0)
        assert_false(_grouped_term(term, 1, ideal, magnitude, inherited))


def test_sum2_error_envelopes_reject_invalid_and_overflowing_bounds() raises:
    assert_true(_sum2_supported_environment())
    var zero = _Interval.point(0.0)
    assert_true(isfinite(_grouped_origin_error(zero, zero, zero, 1, 0.0)))
    assert_false(
        isfinite(_grouped_origin_error(zero, _Interval.whole(), zero, 1, 0.0))
    )
    assert_false(
        isfinite(_grouped_origin_error(_Interval.whole(), zero, zero, 1, 0.0))
    )
    var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    assert_false(
        isfinite(
            _grouped_origin_error(
                _Interval.point(2.0), _Interval.point(2.0), zero, 1, maximum
            )
        )
    )
    for kind in range(7):
        var term = _ValueJet.constant(1.0)
        var count = 1
        var origin = 0.0
        if kind == 1:
            term.value = _Interval.whole()
        elif kind == 2:
            term.error = inf[DType.float64]()
        elif kind == 3:
            term.error = -1.0
        elif kind == 4:
            count = 0
        elif kind == 5:
            count = 321
        elif kind == 6:
            origin = maximum
        assert_equal(
            isfinite(_sum2_envelope_error(term, count, origin)), kind == 0
        )


def test_grouped_domain_structure_and_roundoff_origins_are_checked() raises:
    for kind in range(13):
        var geometry = _geometry()
        var d = _Jet.variable(2.125, 2.25)
        if kind == 1:
            geometry.kind = LINE
        elif kind == 2:
            geometry.heading = 0.1
        elif kind == 3:
            geometry.curvature_start = 0.01
        elif kind == 4:
            geometry.length = inf[DType.float64]()
        elif kind == 5:
            geometry.length = 0.0
        elif kind == 6:
            geometry.x = inf[DType.float64]()
        elif kind == 7:
            geometry.y = inf[DType.float64]()
        elif kind == 8:
            geometry.curvature_end = inf[DType.float64]()
        elif kind == 9:
            d.value = _Interval.whole()
        elif kind == 10:
            d.value = _Interval(3.0, 2.0)
        elif kind == 11:
            d.error = inf[DType.float64]()
        elif kind == 12:
            d.error = -1.0
        assert_equal(
            Bool(_spiral_grouped_domain_rate(geometry, d, 4)), kind == 0
        )
        if kind < 9:
            assert_equal(
                Bool(_try_spiral_roundoff_envelope(geometry, d, 4)), kind == 0
            )
    var geometry = _geometry()
    geometry.length = 1e-300
    geometry.curvature_end = 1e300
    var d = _Jet.variable(2e-301, 3e-301)
    assert_false(Bool(_spiral_grouped_domain_rate(geometry, d, 4)))
    assert_false(Bool(_try_spiral_roundoff_envelope(geometry, d, 4)))
    geometry = _geometry()
    d = _Jet.variable(2.125, 2.25)
    d.error = 1e308
    assert_false(Bool(_spiral_grouped_domain_rate(geometry, d, 4)))
    d.error = -0.01
    assert_false(Bool(_try_spiral_roundoff_envelope(geometry, d, 4)))


def test_grouped_metering_declines_without_debit_before_attempt() raises:
    var geometry = _geometry()
    var d = _Jet.variable(2.125, 2.25)
    for kind in range(3):
        var terms = 17
        var count = 4
        if kind == 0:
            count = 0
        elif kind == 1:
            terms = 101
        else:
            geometry.heading = 0.1
        var before = terms
        assert_false(
            Bool(
                _try_spiral_grouped_roundoff_envelope_metered(
                    geometry, d, count, terms, 100
                )
            )
        )
        assert_equal(terms, before)


def test_original_node_phase_guard_rejects_nonfinite_and_large_phase() raises:
    var geometry = _geometry()
    assert_true(
        _all_spiral_nodes_quadrant_zero(geometry, _Jet.variable(2.125, 2.25), 4)
    )
    assert_false(
        _all_spiral_nodes_quadrant_zero(
            geometry, _Jet.variable(1e200, 1e200), 4
        )
    )
    assert_false(
        _all_spiral_nodes_quadrant_zero(geometry, _Jet.variable(1e9, 1e9), 4)
    )


def test_stored_primitive_invalid_inputs_and_right_operand_controls() raises:
    for kind in range(4):
        var value = _Jet.constant(2.0)
        if kind == 1:
            value.value = _Interval(3.0, 2.0)
        elif kind == 2:
            value.error = inf[DType.float64]()
        elif kind == 3:
            value.error = -1.0
        var result = _stored_half(value)
        var ordinary = value * _Jet.constant(0.5)
        if kind == 0:
            assert_equal(result.error, 0.0)
        else:
            assert_equal(result.error, ordinary.error)
    assert_false(
        isfinite(
            _stored_blend_error(
                _Jet.variable(-inf[DType.float64](), inf[DType.float64]()),
                1.0,
                2.0,
            )
        )
    )
    assert_false(
        isfinite(
            _stored_blend_error(_Jet.constant(0.5), 1.0, inf[DType.float64]())
        )
    )
    var one = _Jet.constant(2.0)
    var two = _Jet.constant(2.0)
    two.error = 0.125
    assert_true(_stored_difference(one, two).error >= 0.125)
    var maximum = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    var left = _Jet.constant(maximum)
    var right = _Jet.variable(maximum, maximum * 1.5)
    var ordinary = left - right
    assert_equal(_stored_difference(left, right).error, ordinary.error)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
