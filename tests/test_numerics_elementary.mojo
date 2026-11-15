# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Elementary functions to about one unit in the last place."""

from extensions.numerics.elementary import (
    INVERSE_LN2,
    LN10,
    LN2,
    logistic,
    logit,
    precise_exp,
    precise_log2,
    precise_power,
    precise_power10,
    softplus,
)
from std.math import exp, inf, isinf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def test_exp() raises:
    assert_equal(precise_exp(0.0), 1.0)
    assert_almost_equal(precise_exp(1.0), 2.718281828459045, rtol=2e-16)
    assert_almost_equal(precise_exp(-70.0), 3.975449735908647e-31, rtol=3e-16)
    assert_equal(precise_exp(-709.0), 0.0)
    assert_equal(precise_exp(nan[DType.float64]()), 0.0)
    assert_true(isinf(precise_exp(710.0)))


def test_powers() raises:
    # 2^10 and 10^-3 to the last place.
    assert_almost_equal(precise_power(2.0, 10.0), 1024.0, rtol=2e-16)
    assert_almost_equal(precise_power10(-3.0), 1e-3, rtol=4e-16)
    assert_almost_equal(precise_power(9.0, 0.5), 3.0, rtol=2e-16)
    assert_equal(precise_power(0.0, 2.0), 0.0)
    assert_equal(precise_power(0.0, 0.0), 1.0)
    assert_true(isinf(precise_power(0.0, -1.0)))


def test_logarithms_and_constants() raises:
    assert_equal(precise_log2(1024.0), 10.0)
    assert_almost_equal(precise_log2(10.0) * LN2 / LN10, 1.0, rtol=4e-16)
    assert_almost_equal(LN2 * INVERSE_LN2, 1.0, rtol=2e-16)
    assert_true(isinf(precise_log2(inf[DType.float64]())))


def test_logistic_link() raises:
    assert_equal(logistic(0.0), 0.5)
    assert_almost_equal(logistic(2.0), 1.0 / (1.0 + exp(-2.0)), rtol=1e-15)
    assert_almost_equal(
        logistic(-2.0), exp(-2.0) / (1.0 + exp(-2.0)), rtol=1e-15
    )
    # Far out, neither side overflows.
    assert_equal(logistic(800.0), 1.0)
    assert_equal(logistic(-800.0), 0.0)
    assert_almost_equal(logistic(-700.0), exp(-700.0), rtol=1e-12)
    assert_equal(logit(0.5), 0.0)
    assert_almost_equal(logit(logistic(3.0)), 3.0, rtol=1e-14)
    assert_almost_equal(logit(0.2), log(0.25), rtol=1e-15)
    # ln(1 + e^x): ln 2 at 0, x far up and e^x far down.
    assert_almost_equal(softplus(0.0), LN2, rtol=1e-16)
    assert_equal(softplus(800.0), 800.0)
    assert_almost_equal(softplus(-40.0), exp(-40.0), rtol=1e-15)
    assert_almost_equal(softplus(1.0), log(1.0 + exp(1.0)), rtol=1e-15)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
