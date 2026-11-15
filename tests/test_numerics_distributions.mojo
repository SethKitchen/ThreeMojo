# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Normal tails, 95 percent intervals, the gamma quantiles and the
chi-square tail, against their closed forms."""

from extensions.numerics.distributions import (
    Z95,
    chi_square_p_value,
    gamma_quantile,
    gamma_tails,
    gamma_upper_quantile,
    inverse_erfc,
    normal_quantile,
    normal_two_sided,
    normal_upper,
    ratio_interval,
    wald_interval,
)
from std.math import erfc, exp, inf, log, log1p, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def test_normal_tails() raises:
    assert_equal(normal_upper(0.0), 0.5)
    assert_almost_equal(normal_upper(Z95), 0.025, rtol=1e-15)
    assert_almost_equal(normal_upper(-Z95), 0.975, rtol=1e-15)
    assert_almost_equal(normal_two_sided(-Z95), 0.05, rtol=1e-15)
    assert_equal(normal_two_sided(Z95), normal_two_sided(-Z95))
    # The upper tail keeps its relative accuracy far out.
    assert_almost_equal(normal_upper(10.0), 7.619853024160527e-24, rtol=1e-14)
    assert_almost_equal(normal_quantile(0.975), Z95, rtol=1e-15)


def test_inverse_erfc() raises:
    var values: List[Float64] = [2e-300, 1e-10, 0.3, 1.0, 1.7, 1.999]
    for v in values:
        assert_almost_equal(erfc(inverse_erfc(v)), v, rtol=1e-13)
    assert_equal(inverse_erfc(1.0), 0.0)
    # Half of the value is the tail of a normal quantile.
    with assert_raises(contains="1e-300 or more"):
        _ = inverse_erfc(1e-300)
    var bad: List[Float64] = [0.0, 2.0, -1.0, nan[DType.float64]()]
    for v in bad:
        with assert_raises(contains="above 0 and below 2"):
            _ = inverse_erfc(v)


def test_intervals() raises:
    var w = wald_interval(10.0, 2.0)
    assert_equal(w[0], 10.0 - 2.0 * Z95)
    assert_equal(w[1], 10.0 + 2.0 * Z95)
    # A ratio of 2 with a log error of 0.5: 2 exp(-+ 0.98).
    var r = ratio_interval(2.0, 0.5)
    assert_almost_equal(r[0], 2.0 * exp(-0.5 * Z95), rtol=1e-15)
    assert_almost_equal(r[1], 2.0 * exp(0.5 * Z95), rtol=1e-15)
    var none = ratio_interval(3.0, 0.0)
    assert_equal(none[0], 3.0)
    assert_equal(none[1], 3.0)


def test_gamma_closed_forms() raises:
    # With a shape of 1, Q(1, x) = exp(-x), so the upper quantile of q is
    # -ln q and the quantile of p is -ln(1 - p).
    var tails = gamma_tails(2.5, 1.0)
    assert_almost_equal(tails[1], exp(-2.5), rtol=1e-15)
    var qs: List[Float64] = [1e-200, 0.025, 0.5, 0.9]
    for q in qs:
        assert_almost_equal(gamma_upper_quantile(q, 1.0), -log(q), rtol=1e-14)
        assert_almost_equal(gamma_quantile(q, 1.0), -log1p(-q), rtol=1e-14)
    var bad: List[Float64] = [0.0, 1.0, nan[DType.float64]()]
    for q in bad:
        with assert_raises(contains="above 0, below 1"):
            _ = gamma_upper_quantile(q, 1.0)
    with assert_raises(contains="gamma shape"):
        _ = gamma_upper_quantile(0.5, 0.0)


def test_chi_square() raises:
    # One degree: erfc(sqrt(x / 2)). Two degrees: exp(-x / 2).
    assert_almost_equal(chi_square_p_value(3.0, 1), erfc(sqrt(1.5)), rtol=1e-14)
    assert_almost_equal(chi_square_p_value(3.0, 2), exp(-1.5), rtol=1e-15)
    # Three degrees, and four: chi2.sf of scipy.
    assert_almost_equal(
        chi_square_p_value(7.0, 3), 0.07189777249646509, rtol=1e-12
    )
    assert_almost_equal(
        chi_square_p_value(7.0, 4), 0.13588822540043327, rtol=1e-12
    )
    # Many degrees, odd and even.
    assert_almost_equal(
        chi_square_p_value(250.0, 201), 0.010663859138751904, rtol=1e-10
    )
    assert_almost_equal(
        chi_square_p_value(250.0, 200), 0.009379131668826098, rtol=1e-10
    )
    assert_equal(chi_square_p_value(0.0, 5), 1.0)
    assert_equal(chi_square_p_value(inf[DType.float64](), 5), 0.0)
    var freedoms: List[Int] = [0, 1001]
    for f in freedoms:
        with assert_raises(contains="degrees of freedom"):
            _ = chi_square_p_value(1.0, f)
    var bad: List[Float64] = [-1.0, nan[DType.float64]()]
    for b in bad:
        with assert_raises(contains="0 or more"):
            _ = chi_square_p_value(b, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
