# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Double-double arithmetic agrees with published constants to 1e-30.

The digits of e, ln 2, the root of 2, pi and ln 10 are those of OEIS
A001113, A002162, A002193, A000796 and A002392. The 97.5 percent point of
the normal distribution is `sqrt(2) erfinv(0.95)`.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._double_double import (
    DD,
    dd,
    dd_abs,
    dd_exp,
    dd_inverse,
    dd_ln2,
    dd_log,
    dd_normal_quantile,
    dd_parse,
    dd_pi,
    dd_pow,
    dd_solve,
    dd_sqrt,
)

comptime E = "2.71828182845904523536028747135266249775724709"
comptime LN2 = "0.693147180559945309417232121458176568075500134"
comptime ROOT2 = "1.41421356237309504880168872420969807856967188"
comptime PI = "3.1415926535897932384626433832795028841971694"
comptime LN10 = "2.30258509299404568401799145468436420760110149"
comptime Z975 = "1.95996398454005423552459443052055152795555008"


def _close(found: DD, text: String, tolerance: Float64 = 1e-30) raises:
    """Check a number against its decimal digits, to a relative tolerance."""
    var expected = dd_parse(text)
    var gap = dd_abs(found - expected)
    assert_true(
        gap.hi <= tolerance * abs(expected.hi),
        String(found.hi, " ", found.lo, " is not ", text),
    )


def test_the_constants() raises:
    _close(dd_ln2(), LN2)
    _close(dd_pi(), PI)
    _close(dd_sqrt(dd(2.0)), ROOT2)
    assert_equal(dd_sqrt(dd(0.0)).hi, 0.0)
    _close(dd_exp(dd(1.0)), E)
    _close(dd_log(dd(2.0)), LN2)
    _close(-dd_log(dd(1.0) / 10.0), LN10)
    _close(dd_log(dd(10.0)), LN10)
    _close(dd_normal_quantile(dd_parse("0.975")), Z975)
    _close(-dd_normal_quantile(dd_parse("0.025")), Z975)
    assert_equal(dd_normal_quantile(dd(0.5)).hi, 0.0)


def test_arithmetic() raises:
    # 1/3 times 3 is 1, and 1/3 holds digits past a double.
    var third = dd(1.0) / 3.0
    assert_true(third.lo != 0.0)
    _close(third * 3.0, "1")
    _close(3.0 * third, "1")
    _close(1.0 / dd(3.0) * dd(3.0), "1")
    _close((dd(1.0) / 7.0) * 7.0 - 1.0 + 1.0, "1")
    _close(dd(2.0) - third + third, "2")
    _close(0.5 + dd(0.25), "0.75")
    _close(1.0 - dd(0.25), "0.75")
    _close(dd(1.0) - 0.25, "0.75")
    assert_true(third < dd(0.34))
    assert_true(dd(0.34) > third)
    assert_true(not (third > third))
    assert_true(DD(1.0, 1e-20) > DD(1.0, 0.0))
    _close(dd_abs(dd(-2.5)), "2.5")
    assert_equal((-third).to_float(), -1.0 / 3.0)


def test_exp_log_and_pow() raises:
    # e^-10, e^x e^-x = 1, and 10^0.3 = e^(0.3 ln 10).
    _close(
        dd_exp(dd(-10.0)),
        "0.0000453999297624848515355915155605506102379180889",
    )
    _close(dd_exp(dd(0.0)), "1")
    _close(dd_exp(dd(25.5)) * dd_exp(dd(-25.5)), "1")
    _close(dd_log(dd_exp(dd(-3.25))), "-3.25")
    _close(
        dd_pow(dd(10.0), dd(3.0) / 10.0),
        "1.99526231496887960135245539673953555798627432",
    )
    _close(dd_pow(dd(2.0), dd(10.0)), "1024")
    with assert_raises(contains="within 700"):
        _ = dd_exp(dd(800.0))
    with assert_raises(contains="above 0"):
        _ = dd_log(dd(0.0))
    with assert_raises(contains="above 0"):
        _ = dd_log(dd(-1.0))
    with assert_raises(contains="0 or more"):
        _ = dd_sqrt(dd(-1.0))
    with assert_raises(contains="0.01 to 0.99"):
        _ = dd_normal_quantile(dd(0.999))


def test_parse() raises:
    _close(dd_parse("-12.5"), "-12.5")
    assert_equal(dd_parse("7").hi, 7.0)
    with assert_raises(contains="only digits"):
        _ = dd_parse("1e5")
    with assert_raises(contains="only digits"):
        _ = dd_parse("1-2")
    with assert_raises(contains="needs a digit"):
        _ = dd_parse("-.")


def test_solve_and_inverse() raises:
    # [[2, 1], [1, 3]] x = [3, 5] has x = (4/5, 7/5), and its inverse is
    # [[3, -1], [-1, 2]] / 5. A zero first pivot needs a swap.
    var a: List[List[DD]] = [[dd(2.0), dd(1.0)], [dd(1.0), dd(3.0)]]
    var x = dd_solve(a.copy(), [dd(3.0), dd(5.0)])
    _close(x[0], "0.8")
    _close(x[1], "1.4")
    var inverse = dd_inverse(a)
    _close(inverse[0][0], "0.6")
    _close(inverse[0][1], "-0.2")
    _close(inverse[1][0], "-0.2")
    _close(inverse[1][1], "0.4")
    var swapped = dd_solve(
        [[dd(0.0), dd(1.0)], [dd(1.0), dd(0.0)]], [dd(2.0), dd(3.0)]
    )
    _close(swapped[0], "3")
    _close(swapped[1], "2")
    with assert_raises(contains="zero pivot"):
        _ = dd_solve(
            [[dd(1.0), dd(2.0)], [dd(2.0), dd(4.0)]], [dd(1.0), dd(2.0)]
        )
    with assert_raises(contains="one row for each value"):
        _ = dd_solve([[dd(1.0)]], [dd(1.0), dd(2.0)])
    with assert_raises(contains="square matrix"):
        _ = dd_solve([[dd(1.0), dd(2.0)], [dd(1.0)]], [dd(1.0), dd(2.0)])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
