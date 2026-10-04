# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Source-only controls for the proposed strict Y-dominance guard cleanup.

No native pass is claimed. Keep original suites and five-second gate intact.
"""

from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_trig import _atan2_jet, _curve_atan2
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_zero_containment_precludes_strict_absolute_dominance() raises:
    for dy in [
        _Interval(-2.0, 3.0),
        _Interval(-2.0, 0.0),
        _Interval(-0.0, 3.0),
        _Interval(-0.0, 0.0),
    ]:
        assert_true(dy.contains(0.0))
        assert_equal(dy.absolute().low, 0.0)
        for dx in [
            _Interval(-3.0, 2.0),
            _Interval(1.0, 2.0),
            _Interval(-2.0, -1.0),
            _Interval(-0.0, 0.0),
        ]:
            assert_true(dx.absolute().high >= 0.0)
            assert_false(dy.absolute().low > dx.absolute().high)
    var origin = _atan2_jet(_Jet.constant(0.0), _Jet.constant(0.0))
    assert_true(origin.value.contains(-3.141592653589793))
    assert_true(origin.value.contains(3.141592653589793))
    assert_false(origin.first.is_finite())
    var crossing = _atan2_jet(
        _Jet.variable(-2.0, 3.0), _Jet.variable(-1.0, 1.0)
    )
    assert_true(crossing.value.contains(-3.141592653589793))
    assert_true(crossing.value.contains(3.141592653589793))
    assert_false(crossing.first.is_finite())


def test_positive_and_negative_y_dominance_keep_scalar_enclosures() raises:
    for dy in [_Interval(3.0, 4.0), _Interval(-4.0, -3.0)]:
        var dx = _Interval(-1.0, 1.0)
        assert_true(dy.absolute().low > dx.absolute().high)
        assert_false(dy.contains(0.0))
        var result = _atan2_jet(
            _Jet.variable(dy.low, dy.high), _Jet.variable(dx.low, dx.high)
        ).rounded_value()
        for y in [dy.low, dy.high]:
            for x in [dx.low, 0.0, dx.high]:
                assert_true(result.contains(_curve_atan2(y, x)))


def test_equal_absolute_magnitudes_keep_the_join_and_x_zero_guard() raises:
    var dy = _Interval(1.0, 2.0)
    var dx = _Interval(1.0, 2.0)
    assert_false(dy.absolute().low > dx.absolute().high)
    var join = _atan2_jet(_Jet.variable(1.0, 2.0), _Jet.variable(1.0, 2.0))
    for y in [1.0, 2.0]:
        for x in [1.0, 2.0]:
            assert_true(join.rounded_value().contains(_curve_atan2(y, x)))
    assert_false(join.first.is_finite())
    # >= does NOT establish noncontainment at zero. Keep the X guard intact.
    var zero = _Interval(-0.0, 0.0)
    assert_true(zero.absolute().low >= zero.absolute().high)
    assert_true(zero.contains(0.0))
    var origin = _atan2_jet(_Jet.variable(-0.0, 0.0), _Jet.variable(-0.0, 0.0))
    assert_false(origin.first.is_finite())
    assert_true(origin.value.contains(-3.141592653589793))
    assert_true(origin.value.contains(3.141592653589793))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
