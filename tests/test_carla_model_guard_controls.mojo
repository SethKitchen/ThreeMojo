# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent refusal and conservative fallback controls for proof models."""

from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_minimizer_support import _minimizer_support
from extensions.carla.curve_objective_model import (
    _restrict_objective_model,
    _try_objective_model,
)
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _linear_domain() -> _Jet:
    # F(s)=s on [0,1], with uniform stored-evaluator error 1/8.
    return _Jet(
        _Interval(0.0, 1.0),
        _Interval.point(1.0),
        _Interval.point(0.0),
        0.125,
    )


def _linear_center() -> _Jet:
    return _Jet(
        _Interval.point(0.5),
        _Interval.point(1.0),
        _Interval.point(0.0),
        inf[DType.float64](),
    )


def test_model_rejects_each_invalid_scalar_owner_input() raises:
    var domain = _linear_domain()
    var center = _linear_center()
    assert_true(Bool(_try_objective_model(0.0, 1.0, 0.5, 1.0, domain, center)))
    var infinity = inf[DType.float64]()
    for args in [
        (-infinity, Float64(1.0), Float64(0.5), Float64(1.0)),
        (Float64(0.0), infinity, Float64(0.5), Float64(1.0)),
        (Float64(0.0), Float64(1.0), infinity, Float64(1.0)),
        (Float64(1.0), Float64(1.0), Float64(1.0), Float64(1.0)),
        (Float64(0.0), Float64(1.0), Float64(-0.5), Float64(1.0)),
        (Float64(0.0), Float64(1.0), Float64(1.5), Float64(1.0)),
        (Float64(0.0), Float64(1.0), Float64(0.5), infinity),
        (Float64(0.0), Float64(1.0), Float64(0.5), Float64(0.0)),
    ]:
        assert_false(
            Bool(
                _try_objective_model(
                    args[0], args[1], args[2], args[3], domain, center
                )
            )
        )


def test_model_rejects_unknown_or_reversed_enclosures_independently() raises:
    for invalid in [_Interval.whole(), _Interval(1.0, -1.0)]:
        for field in range(5):
            var domain = _linear_domain()
            var center = _linear_center()
            if field == 0:
                domain.value = invalid
            elif field == 1:
                domain.first = invalid
            elif field == 2:
                domain.second = invalid
            elif field == 3:
                center.value = invalid
            else:
                center.first = invalid
            assert_false(
                Bool(_try_objective_model(0.0, 1.0, 0.5, 1.0, domain, center))
            )
    var domain = _linear_domain()
    domain.error = -0.125
    assert_false(
        Bool(_try_objective_model(0.0, 1.0, 0.5, 1.0, domain, _linear_center()))
    )


def test_restriction_refuses_nonfinite_bounds_and_empty_intersections() raises:
    var domain = _linear_domain()
    var center = _linear_center()
    var model = _try_objective_model(0.0, 1.0, 0.5, 1.0, domain, center).value()
    assert_false(
        Bool(_restrict_objective_model(model, -inf[DType.float64](), 1.0, 1.0))
    )
    assert_false(
        Bool(_restrict_objective_model(model, 0.0, inf[DType.float64](), 1.0))
    )
    # Directly assembled inconsistent cached records must not turn disjoint
    # value or derivative enclosures into a successful child certificate.
    model.center.value = _Interval.point(10.0)
    assert_false(Bool(_restrict_objective_model(model, 0.5, 0.5, 1.0)))
    model.center.value = center.value
    model.center.first = _Interval.point(10.0)
    assert_false(Bool(_restrict_objective_model(model, 0.5, 0.5, 1.0)))
    model.center.first = center.first
    var child = _restrict_objective_model(model, 0.5, 0.5, 1.0)
    assert_true(Bool(child))
    assert_true(child.value().value.contains(0.5))
    assert_true(child.value().first.contains(1.0))
    assert_equal(child.value().error, 0.125)


def test_finite_model_inputs_can_overflow_taylor_value_or_derivative() raises:
    # F(s)=1e308*s has finite values on [-1,1], but a translated
    # extrapolation from -1 to +1 overflows before enclosure intersection.
    var domain = _Jet(
        _Interval(-1e308, 1e308),
        _Interval.point(1e308),
        _Interval.point(0.0),
        0.0,
    )
    var center = _Jet(
        _Interval.point(-1e308),
        _Interval.point(1e308),
        _Interval.point(0.0),
        inf[DType.float64](),
    )
    var model = _try_objective_model(-1.0, 1.0, -1.0, 1.0, domain, center)
    assert_true(Bool(model))
    assert_false(Bool(_restrict_objective_model(model.value(), 1.0, 1.0, 1.0)))
    # F(s)=0 admits a deliberately loose but valid second-derivative bound.
    # The Taylor value remains finite at 1.25 while its derivative overflows.
    domain = _Jet(
        _Interval.point(0.0), _Interval.point(0.0), _Interval(0.0, 1.6e308), 0.0
    )
    center = _Jet.constant(0.0)
    model = _try_objective_model(0.0, 1.25, 0.0, 1.0, domain, center)
    assert_true(Bool(model))
    assert_false(
        Bool(_restrict_objective_model(model.value(), 1.25, 1.25, 1.0))
    )


def test_minimizer_invalid_witnesses_preserve_original_interval() raises:
    var infinity = inf[DType.float64]()
    for args in [
        (Float64(0.5), infinity),
        (infinity, Float64(0.5)),
        (Float64(-0.5), Float64(0.5)),
        (Float64(1.5), Float64(0.5)),
        (Float64(0.5), Float64(-0.5)),
        (Float64(0.5), Float64(1.5)),
    ]:
        var result = _minimizer_support(
            _linear_domain(), _linear_center(), args[0], args[1], 0.0, 1.0
        )
        assert_equal(result.low, 0.0)
        assert_equal(result.high, 1.0)
    var reversed = _minimizer_support(
        _linear_domain(), _linear_center(), 0.5, 0.5, 1.0, 0.0
    )
    assert_equal(reversed.low, 1.0)
    assert_equal(reversed.high, 0.0)
    var unbounded = _minimizer_support(
        _linear_domain(), _linear_center(), 0.5, 0.5, -infinity, infinity
    )
    assert_equal(unbounded.low, -infinity)
    assert_equal(unbounded.high, infinity)


def test_taylor_reconstruction_can_replace_unknown_whole_cell_slope() raises:
    var domain = _linear_domain()
    domain.first = _Interval.whole()
    var result = _minimizer_support(
        domain, _linear_center(), 0.5, 0.0, 0.0, 1.0
    )
    # With G(s) in s+[-1/8,1/8], all possible rounded minima satisfy
    # s <= 1/4. The outward support must retain the worst-error tie.
    assert_equal(result.low, 0.0)
    assert_true(result.contains(0.25))
    assert_true(result.high < 0.26)


def test_overflowing_monotone_error_radius_does_not_trim() raises:
    for sign in [Float64(-1.0), Float64(1.0)]:
        var domain = _linear_domain()
        domain.first = _Interval.point(sign)
        domain.value = _Interval(-1.0, 0.0) if sign < 0.0 else _Interval(
            0.0, 1.0
        )
        domain.error = 1e308
        var center = _linear_center()
        center.value = _Interval.point(sign * 0.5)
        center.first = _Interval.point(sign)
        var result = _minimizer_support(domain, center, 0.5, 0.5, 0.0, 1.0)
        assert_equal(result.low, 0.0)
        assert_equal(result.high, 1.0)


def test_overflowing_taylor_derivatives_keep_original_conservative_cover() raises:
    var domain = _Jet(
        _Interval(0.0, 5e307),
        _Interval(-1e308, 1e308),
        _Interval.point(1e308),
        1e308,
    )
    var center = _Jet(
        _Interval.point(5e307),
        _Interval.point(-1e308),
        _Interval.point(1e308),
        inf[DType.float64](),
    )
    var result = _minimizer_support(domain, center, -1.0, 1.0, -1.0, 1.0)
    assert_equal(result.low, -1.0)
    assert_equal(result.high, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
