# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The simplex search of Nelder and Mead on costs with known least points.
"""

from extensions.imaging.simplex import SimplexCost, minimize_simplex
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


struct _Bowl(SimplexCost):
    """`(x - 1)^2 + 10 (y + 2)^2`, least at (1, -2)."""

    var calls: Int

    def __init__(out self):
        self.calls = 0

    def cost(mut self, point: List[Float64]) -> Float64:
        self.calls += 1
        var x = point[0] - 1.0
        var y = point[1] + 2.0
        return x * x + 10.0 * y * y


struct _Rosenbrock(SimplexCost):
    """The banana valley of Rosenbrock, least at (1, 1)."""

    def __init__(out self):
        pass

    def cost(mut self, point: List[Float64]) -> Float64:
        var a = 1.0 - point[0]
        var b = point[1] - point[0] * point[0]
        return a * a + 100.0 * b * b


struct _Pit(SimplexCost):
    """0 at the origin and 1 elsewhere: no move improves, so the simplex
    shrinks onto the origin."""

    def __init__(out self):
        pass

    def cost(mut self, point: List[Float64]) -> Float64:
        for p in point:
            if p != 0:
                return 1.0
        return 0.0


def test_bowl() raises:
    var bowl = _Bowl()
    var result = minimize_simplex(bowl, [4.0, 3.0], [0.5, 0.5], 1e-9, 2000)
    assert_true(result.converged)
    assert_almost_equal(result.point[0], 1.0, atol=1e-8)
    assert_almost_equal(result.point[1], -2.0, atol=1e-8)
    assert_true(result.value < 1e-15)
    assert_equal(result.evaluations, bowl.calls)
    assert_true(result.iterations > 10)


def test_rosenbrock() raises:
    var valley = _Rosenbrock()
    var result = minimize_simplex(valley, [-1.2, 1.0], [0.1, 0.1], 1e-10, 5000)
    assert_true(result.converged)
    assert_almost_equal(result.point[0], 1.0, atol=1e-6)
    assert_almost_equal(result.point[1], 1.0, atol=1e-6)


def test_shrink_and_limits() raises:
    var pit = _Pit()
    var result = minimize_simplex(
        pit, [0.0, 0.0, 0.0], [1.0, 2.0, 3.0], 1e-3, 100
    )
    assert_true(result.converged)
    assert_equal(result.value, 0.0)
    assert_equal(result.point[2], 0.0)
    # Each iteration shrinks the simplex by half: 2^-10 is below 1e-3.
    assert_equal(result.iterations, 10)
    # One iteration does not converge.
    var bowl = _Bowl()
    var short = minimize_simplex(bowl, [4.0, 3.0], [0.5, 0.5], 1e-9, 1)
    assert_false(short.converged)
    assert_equal(short.iterations, 1)


def test_refusals() raises:
    var bowl = _Bowl()
    with assert_raises(contains="one step for each"):
        _ = minimize_simplex(bowl, List[Float64](), List[Float64](), 1e-3, 10)
    with assert_raises(contains="one step for each"):
        _ = minimize_simplex(bowl, [1.0, 2.0], [1.0], 1e-3, 10)
    var steps: List[Float64] = [0.0, inf[DType.float64](), nan[DType.float64]()]
    for s in steps:
        with assert_raises(contains="positive and finite"):
            _ = minimize_simplex(bowl, [1.0, 2.0], [1.0, s], 1e-3, 10)
    with assert_raises(contains="tolerance"):
        _ = minimize_simplex(bowl, [1.0, 2.0], [1.0, 1.0], 0.0, 10)
    with assert_raises(contains="one iteration"):
        _ = minimize_simplex(bowl, [1.0, 2.0], [1.0, 1.0], 1e-3, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
