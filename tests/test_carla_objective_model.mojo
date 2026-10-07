# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent cubic Taylor restrictions retain owner, scale and error."""

from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_objective_model import (
    _try_objective_model,
    _restrict_objective_model,
)
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_uniform_taylor_children_keep_original_error_and_owner_guards() raises:
    # Independent exact polynomial F(s)=1+2*s+3*s*s+s*s*s on [0,1].
    # F'(s)=2+6*s+3*s*s, F''(s)=6+6*s. These are monotone ranges.
    var domain = _Jet(
        _Interval(1.0, 7.0), _Interval(2.0, 11.0), _Interval(6.0, 12.0), 0.0001
    )
    var center = _Jet(
        _Interval.point(2.875),
        _Interval.point(5.75),
        _Interval.point(9.0),
        inf[DType.float64](),
    )
    var packed = _try_objective_model(0.0, 1.0, 0.5, 1.0, domain, center)
    assert_true(Bool(packed))
    var model = packed.value()
    for i in range(16):
        var lo = Float64(i) / 16.0
        var hi = Float64(i + 1) / 16.0
        var child = _restrict_objective_model(model, lo, hi, 1.0)
        assert_true(Bool(child))
        var lower = 1.0 + 2.0 * lo + 3.0 * lo * lo + lo * lo * lo
        var upper = 1.0 + 2.0 * hi + 3.0 * hi * hi + hi * hi * hi
        assert_true(child.value().value.contains(lower))
        assert_true(child.value().value.contains(upper))
        assert_true(
            child.value().first.contains(2.0 + 6.0 * lo + 3.0 * lo * lo)
        )
        assert_true(
            child.value().first.contains(2.0 + 6.0 * hi + 3.0 * hi * hi)
        )
        assert_equal(child.value().error, domain.error)
        assert_true(
            child.value().rounded_value().contains(lower - domain.error)
        )
        assert_true(
            child.value().rounded_value().contains(upper + domain.error)
        )
    # The center may lie outside a child but must lie in the owning C2 cell.
    assert_true(Bool(_restrict_objective_model(model, 0.875, 1.0, 1.0)))
    assert_false(Bool(_restrict_objective_model(model, -0.125, 0.5, 1.0)))
    assert_false(Bool(_restrict_objective_model(model, 0.5, 1.125, 1.0)))
    assert_false(Bool(_restrict_objective_model(model, 0.75, 0.5, 1.0)))
    assert_false(Bool(_restrict_objective_model(model, 0.0, 1.0, 2.0)))
    assert_false(Bool(_try_objective_model(0.0, 1.0, 1.5, 1.0, domain, center)))
    var joined = domain
    joined.second = _Interval.whole()
    assert_false(Bool(_try_objective_model(0.0, 1.0, 0.5, 1.0, joined, center)))
    joined = domain
    joined.first = _Interval.whole()
    assert_false(Bool(_try_objective_model(0.0, 1.0, 0.5, 1.0, joined, center)))
    joined = domain
    joined.error = inf[DType.float64]()
    assert_false(Bool(_try_objective_model(0.0, 1.0, 0.5, 1.0, joined, center)))


def main() raises:
    var suite = TestSuite.discover_tests[__functions_in_module()]()
    suite.run()
