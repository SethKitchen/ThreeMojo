# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bisection and golden-section search, against closed forms."""

from extensions.numerics.search import GOLDEN, bisect, golden_minimum
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def test_bisect() raises:
    # x^2 = 2 between 0 and 2: the last place in 60 halvings.
    def below(x: Float64) capturing -> Bool:
        return x * x < 2.0

    assert_almost_equal(bisect[below](0.0, 2.0, 60), sqrt(2.0), rtol=1e-15)
    # No step gives the middle of the ends.
    assert_equal(bisect[below](0.0, 2.0, 0), 1.0)


def test_golden_minimum() raises:
    var calls = 0

    def cost(x: Float64) capturing -> Float64:
        calls += 1
        return (x - 1.25) * (x - 1.25)

    var x = golden_minimum[cost](0.0, 4.0, 80)
    assert_almost_equal(x, 1.25, atol=1e-8)
    # Two inner points, then one each step.
    assert_equal(calls, 82)
    assert_equal(golden_minimum[cost](0.0, 4.0, 0), 2.0)
    assert_almost_equal(GOLDEN * GOLDEN + GOLDEN, 1.0, rtol=1e-15)

    # The largest value of a cost, by its negation.
    def hill(x: Float64) capturing -> Float64:
        return (x - 3.0) * (x - 3.0) - 7.0

    assert_almost_equal(golden_minimum[hill](-10.0, 10.0, 100), 3.0, atol=1e-8)


def test_errors_pass_through() raises:
    def bad_test(x: Float64) raises capturing -> Bool:
        if x < 1.0:
            raise Error("A test failed")
        return True

    with assert_raises(contains="A test failed"):
        _ = bisect[bad_test](0.0, 1.0, 3)

    def bad_cost(x: Float64) raises capturing -> Float64:
        raise Error("A cost failed")

    with assert_raises(contains="A cost failed"):
        _ = golden_minimum[bad_cost](0.0, 1.0, 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
