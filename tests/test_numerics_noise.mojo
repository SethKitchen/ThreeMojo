# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seeded uniform and normal numbers by xorshift64."""

from extensions.numerics.noise import Xorshift64
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def test_first_step() raises:
    # From 1: 1 ^ 1 << 13 = 8193, ^ >> 7 = 8257, ^ << 17 = 8257 * 131073.
    var noise = Xorshift64(1)
    var u = noise.uniform()
    assert_equal(noise.state, UInt64(1082269761))
    assert_equal(u, (528452.0 + 0.5) / 9007199254740992.0)


def test_one_seed_gives_one_sequence() raises:
    var a = Xorshift64(20261115)
    var b = Xorshift64(20261115)
    for _ in range(100):
        assert_equal(a.uniform(), b.uniform())
    assert_equal(a.normal(), b.normal())


def test_moments() raises:
    var noise = Xorshift64(7)
    var n = 20000
    var sum = 0.0
    var inside = True
    for _ in range(n):
        var u = noise.uniform()
        inside = inside and u > 0 and u < 1
        sum += u
    assert_true(inside)
    assert_almost_equal(sum / Float64(n), 0.5, atol=0.01)
    var mean = 0.0
    var square = 0.0
    for _ in range(n):
        var z = noise.normal()
        mean += z / Float64(n)
        square += z * z / Float64(n)
    assert_almost_equal(mean, 0.0, atol=0.03)
    assert_almost_equal(square, 1.0, atol=0.04)


def test_counts_and_gammas() raises:
    var noise = Xorshift64(11)
    var n = 4000
    # Poisson means of 3 and of 1200: mean = variance.
    var means: List[Float64] = [3.0, 1200.0]
    for m in means:
        var sum = 0.0
        var square = 0.0
        for _ in range(n):
            var k = Float64(noise.poisson(m))
            sum += k / Float64(n)
            square += k * k / Float64(n)
        assert_almost_equal(sum, m, rtol=0.03)
        assert_almost_equal(square - sum * sum, m, rtol=0.1)
    assert_equal(noise.poisson(0.0), 0)
    # Gamma shapes of 2 and of 0.5: mean shape scale, variance shape
    # scale^2.
    var shapes: List[Float64] = [2.0, 0.5]
    for a in shapes:
        var sum = 0.0
        var square = 0.0
        var positive = True
        for _ in range(n):
            var g = noise.gamma(a, 3.0)
            positive = positive and g > 0
            sum += g / Float64(n)
            square += g * g / Float64(n)
        assert_true(positive)
        assert_almost_equal(sum, 3.0 * a, rtol=0.06)
        assert_almost_equal(square - sum * sum, 9.0 * a, rtol=0.15)
    # An exponential of mean 4 has a variance of 16.
    var e_sum = 0.0
    var e_square = 0.0
    for _ in range(n):
        var e = noise.exponential(4.0)
        e_sum += e / Float64(n)
        e_square += e * e / Float64(n)
    assert_almost_equal(e_sum, 4.0, rtol=0.06)
    assert_almost_equal(e_square - e_sum * e_sum, 16.0, rtol=0.15)
    var x = noise.between(2.0, 5.0)
    assert_true(x > 2.0 and x < 5.0)
    var bad: List[Float64] = [-1.0, inf[DType.float64](), nan[DType.float64]()]
    for v in bad:
        with assert_raises(contains="Poisson mean"):
            _ = noise.poisson(v)
        with assert_raises(contains="gamma shape"):
            _ = noise.gamma(v, 1.0)
        with assert_raises(contains="gamma shape"):
            _ = noise.gamma(1.0, v)
    with assert_raises(contains="gamma shape"):
        _ = noise.gamma(0.0, 1.0)


def test_zero_seed() raises:
    with assert_raises(contains="must not be 0"):
        _ = Xorshift64(0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
