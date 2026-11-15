# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bland-Altman agreement, intraclass correlations, and the t and F
distributions.

`assets/agreement/agreement_expected.txt` holds the results of pingouin
0.7.0 and scipy 1.18.1. See
`tools/make_agreement.mojo` and `assets/agreement/make_agreement.py`.
"""

from extensions.clinical.agreement import (
    BlandAltman,
    Icc,
    bland_altman,
    bland_altman_image,
    intraclass_correlation,
)
from extensions.numerics.distributions import (
    beta_tails,
    f_quantile,
    f_upper,
    student_t_quantile,
    student_t_upper,
)
from render.framebuffer import Framebuffer
from std.math import atan, inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime PI = 3.141592653589793


def _numbers(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    var first = True
    for part in line.split(" "):
        if first:
            first = False
            continue
        out.append(atof(String(part)))
    return out^


def _expected() raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/agreement/agreement_expected.txt", "r").read()
    for line in text.splitlines():
        out.append(_numbers(String(line)))
    return out^


def _readers() raises -> Tuple[List[Float64], List[Float64]]:
    var a = List[Float64]()
    var b = List[Float64]()
    var text = open("assets/agreement/readers.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(" ")
        a.append(atof(String(words[0])))
        b.append(atof(String(words[1])))
    return (a^, b^)


def _check(icc: Icc, row: List[Float64], at: Int) raises:
    assert_almost_equal(icc.value, row[7 * at], rtol=1e-12)
    assert_almost_equal(icc.f, row[7 * at + 1], rtol=1e-12)
    assert_equal(icc.df1, Int(row[7 * at + 2]))
    assert_equal(icc.df2, Int(row[7 * at + 3]))
    assert_almost_equal(icc.p_value, row[7 * at + 4], rtol=1e-10)
    # pingouin rounds the ends to two decimals.
    assert_almost_equal(icc.lower, row[7 * at + 5], atol=0.005 + 1e-12, rtol=0)
    assert_almost_equal(icc.upper, row[7 * at + 6], atol=0.005 + 1e-12, rtol=0)


def test_shrout_fleiss() raises:
    # Table 2 of Shrout and Fleiss (1979): six subjects, four judges.
    var ratings: List[List[Float64]] = [
        [9.0, 2.0, 5.0, 8.0],
        [6.0, 1.0, 3.0, 2.0],
        [8.0, 4.0, 6.0, 8.0],
        [7.0, 1.0, 2.0, 6.0],
        [10.0, 5.0, 6.0, 9.0],
        [6.0, 2.0, 4.0, 7.0],
    ]
    var table = intraclass_correlation(ratings)
    var row = _expected()[0].copy()
    _check(table.one, row, 0)
    _check(table.agreement, row, 1)
    _check(table.consistency, row, 2)
    _check(table.one_average, row, 3)
    _check(table.agreement_average, row, 4)
    _check(table.consistency_average, row, 5)
    # The published values, to two decimals.
    assert_almost_equal(table.one.value, 0.17, atol=0.005)
    assert_almost_equal(table.agreement.value, 0.29, atol=0.005)
    assert_almost_equal(table.consistency.value, 0.71, atol=0.006)
    assert_almost_equal(table.one_average.value, 0.44, atol=0.005)
    assert_almost_equal(table.agreement_average.value, 0.62, atol=0.005)
    assert_almost_equal(table.consistency_average.value, 0.91, atol=0.005)


def test_readers() raises:
    var data = _readers()
    var expected = _expected()
    var pair = List[List[Float64]]()
    for i in range(len(data[0])):
        var a = data[0][i]
        var b = data[1][i]
        pair.append([a, b])
    var table = intraclass_correlation(pair)
    ref row = expected[1]
    _check(table.one, row, 0)
    _check(table.agreement, row, 1)
    _check(table.consistency, row, 2)
    _check(table.one_average, row, 3)
    _check(table.agreement_average, row, 4)
    _check(table.consistency_average, row, 5)
    # The closed form of the limits: the bias -+ 1.96 sd, with the t
    # intervals of their standard errors, sd / sqrt(n) and sqrt(3 sd^2 / n).
    var first = data[0].copy()
    var second = data[1].copy()
    var result = bland_altman(data[0], data[1])
    var n = len(first)
    var bias = 0.0
    for i in range(n):
        bias += (first[i] - second[i]) / Float64(n)
    var squares = 0.0
    for i in range(n):
        var e = first[i] - second[i] - bias
        squares += e * e
    var sd = sqrt(squares / Float64(n - 1))
    var t = student_t_quantile(0.975, Float64(n - 1))
    var se_bias = sd / sqrt(Float64(n))
    var se_limit = sqrt(3.0 * sd * sd / Float64(n))
    var lower = bias - 1.96 * sd
    var upper = bias + 1.96 * sd
    assert_equal(result.count, n)
    assert_almost_equal(result.bias, bias, rtol=1e-13)
    assert_almost_equal(result.deviation, sd, rtol=1e-13)
    assert_almost_equal(result.lower, lower, rtol=1e-13)
    assert_almost_equal(result.upper, upper, rtol=1e-13)
    assert_almost_equal(result.bias_interval[0], bias - t * se_bias, rtol=1e-12)
    assert_almost_equal(result.bias_interval[1], bias + t * se_bias, rtol=1e-12)
    assert_almost_equal(
        result.lower_interval[0], lower - t * se_limit, rtol=1e-12
    )
    assert_almost_equal(
        result.lower_interval[1], lower + t * se_limit, rtol=1e-12
    )
    assert_almost_equal(
        result.upper_interval[0], upper - t * se_limit, rtol=1e-12
    )
    assert_almost_equal(
        result.upper_interval[1], upper + t * se_limit, rtol=1e-12
    )


def test_distributions() raises:
    var expected = _expected()
    ref t = expected[2]
    for c in range(5):
        var value = t[4 * c]
        var df = t[4 * c + 1]
        assert_almost_equal(
            student_t_upper(value, df), t[4 * c + 2], rtol=1e-12
        )
        assert_almost_equal(
            student_t_quantile(0.975, df), t[4 * c + 3], rtol=1e-12
        )
    ref f = expected[3]
    for c in range(6):
        var x = f[5 * c]
        var d1 = f[5 * c + 1]
        var d2 = f[5 * c + 2]
        assert_almost_equal(f_upper(x, d1, d2), f[5 * c + 3], rtol=1e-12)
        assert_almost_equal(f_quantile(0.975, d1, d2), f[5 * c + 4], rtol=1e-12)


def test_by_hand() raises:
    # Beta: I_x(1, 1) = x, I_x(3, 1) = x^3, I_x(1, 2) = 1 - (1 - x)^2.
    var uniform = beta_tails(0.3, 1.0, 1.0)
    assert_almost_equal(uniform[0], 0.3, rtol=1e-15)
    assert_almost_equal(uniform[1], 0.7, rtol=1e-15)
    assert_almost_equal(beta_tails(0.6, 3.0, 1.0)[0], 0.216, rtol=1e-14)
    assert_almost_equal(beta_tails(0.6, 1.0, 2.0)[1], 0.16, rtol=1e-14)
    assert_equal(beta_tails(0.0, 2.0, 3.0)[0], 0.0)
    assert_equal(beta_tails(1.0, 2.0, 3.0)[1], 0.0)
    # Student's t with one degree is Cauchy's: 1/2 - atan(t) / pi.
    assert_almost_equal(student_t_upper(1.0, 1.0), 0.25, rtol=1e-14)
    assert_almost_equal(
        student_t_upper(-3.0, 1.0), 0.5 + atan(3.0) / PI, rtol=1e-14
    )
    assert_almost_equal(student_t_quantile(0.75, 1.0), 1.0, rtol=1e-13)
    assert_almost_equal(student_t_quantile(0.25, 1.0), -1.0, rtol=1e-13)
    assert_equal(student_t_quantile(0.5, 4.0), 0.0)
    assert_equal(student_t_upper(0.0, 4.0), 0.5)
    # With two degrees: 1/2 - t / (2 sqrt(2 + t^2)). So the 0.6 quantile
    # is sqrt(1/12).
    assert_almost_equal(
        student_t_upper(2.0, 2.0), 0.5 - 1.0 / sqrt(6.0), rtol=1e-14
    )
    assert_almost_equal(
        student_t_quantile(0.6, 2.0), sqrt(1.0 / 12.0), rtol=1e-13
    )
    # scipy's t.ppf, far out.
    assert_almost_equal(
        student_t_quantile(0.999999, 3.0), 103.29946777942898, rtol=1e-11
    )
    # F with two and two degrees: P(F > x) = 1 / (1 + x).
    assert_almost_equal(f_upper(3.0, 2.0, 2.0), 0.25, rtol=1e-14)
    assert_almost_equal(f_quantile(0.75, 2.0, 2.0), 3.0, rtol=1e-13)
    assert_almost_equal(f_quantile(0.01, 2.0, 2.0), 1.0 / 99.0, rtol=1e-12)
    assert_equal(f_upper(0.0, 3.0, 4.0), 1.0)
    # Bland-Altman: differences 1, 0, 1, 0, so a bias of 1/2 and a
    # deviation of sqrt(1/3).
    var small = bland_altman([1.0, 2.0, 3.0, 4.0], [0.0, 2.0, 2.0, 4.0])
    assert_equal(small.bias, 0.5)
    assert_almost_equal(small.deviation, sqrt(1.0 / 3.0), rtol=1e-15)
    assert_almost_equal(small.upper, 0.5 + 1.96 * sqrt(1.0 / 3.0), rtol=1e-15)


def test_refusals() raises:
    var degrees: List[Float64] = [0.0, 2e8, nan[DType.float64]()]
    for d in degrees:
        with assert_raises(contains="degrees of freedom"):
            _ = student_t_upper(1.0, d)
        with assert_raises(contains="degrees of freedom"):
            _ = f_upper(1.0, d, 3.0)
        with assert_raises(contains="degrees of freedom"):
            _ = f_quantile(0.5, 3.0, d)
        with assert_raises(contains="degrees of freedom"):
            _ = beta_tails(0.5, 2.0 * d, 1.0)
    with assert_raises(contains="degrees of freedom"):
        _ = beta_tails(0.5, 1.0, -1.0)
    with assert_raises(contains="degrees of freedom"):
        _ = beta_tails(0.5, 1.0, 3e8)
    var points: List[Float64] = [-0.1, 1.1, nan[DType.float64]()]
    for x in points:
        with assert_raises(contains="from 0 to 1"):
            _ = beta_tails(x, 1.0, 1.0)
    var ps: List[Float64] = [0.0, 1.0, nan[DType.float64]()]
    for p in ps:
        with assert_raises(contains="between 0 and 1"):
            _ = student_t_quantile(p, 3.0)
        with assert_raises(contains="between 0 and 1"):
            _ = f_quantile(p, 3.0, 3.0)
    with assert_raises(contains="must be finite"):
        _ = student_t_upper(inf[DType.float64](), 3.0)
    var values: List[Float64] = [-1.0, inf[DType.float64]()]
    for v in values:
        with assert_raises(contains="0 or more, and finite"):
            _ = f_upper(v, 3.0, 3.0)
    with assert_raises(contains="two subjects or more"):
        _ = bland_altman([1.0], [1.0])
    with assert_raises(contains="two subjects or more"):
        _ = bland_altman([1.0, 2.0], [1.0])
    with assert_raises(contains="must be finite"):
        _ = bland_altman([1.0, 2.0], [1.0, nan[DType.float64]()])
    with assert_raises(contains="must be finite"):
        _ = bland_altman([inf[DType.float64](), 2.0], [1.0, 2.0])
    with assert_raises(contains="degrees of freedom"):
        _ = BlandAltman(1, 0.0, 1.0)
    var one_row: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises(contains="two subjects or more"):
        _ = intraclass_correlation(one_row)
    var one_rater: List[List[Float64]] = [[1.0], [2.0]]
    with assert_raises(contains="two raters or more"):
        _ = intraclass_correlation(one_rater)
    var ragged: List[List[Float64]] = [[1.0, 2.0], [2.0]]
    with assert_raises(contains="one rating by each rater"):
        _ = intraclass_correlation(ragged)
    var infinite: List[List[Float64]] = [
        [1.0, 2.0],
        [2.0, inf[DType.float64]()],
    ]
    with assert_raises(contains="must be finite"):
        _ = intraclass_correlation(infinite)
    # Raters who differ by a constant only leave no residual.
    var shifted: List[List[Float64]] = [[1.0, 2.0], [3.0, 4.0], [7.0, 8.0]]
    with assert_raises(contains="residual variation"):
        _ = intraclass_correlation(shifted)


def _rgb(image: Framebuffer, x: Int, y: Int) -> Tuple[Int, Int, Int]:
    var at = (y * image.width + x) * 4
    return (
        Int(image.pixels[at]),
        Int(image.pixels[at + 1]),
        Int(image.pixels[at + 2]),
    )


def test_bland_altman_image() raises:
    # Differences 1, 0, 1, 0 with means 0.5, 2, 2.5 and 4: a bias of 1/2.
    var first: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var second: List[Float64] = [0.0, 2.0, 2.0, 4.0]
    var result = bland_altman(first, second)
    var image = bland_altman_image(first, second, result, 101, 101)
    # r = 1.25 * (0.5 + 1.96 sqrt(1/3)): the bias row and the zero row.
    var reach = 1.25 * result.upper
    var bias_row = Int((reach - 0.5) / (2 * reach) * 100 + 0.5)
    assert_true(_rgb(image, 50, bias_row) == (38, 102, 217))
    assert_true(_rgb(image, 1, 50) == (179, 179, 184))
    # The first subject: a mean of 0.5 at x = 10, a difference of 1.
    var x = Int(Float64(0.35) / 4.2 * 100.0 + 0.5)
    var y = Int((reach - 1.0) / (2 * reach) * 100 + 0.5)
    assert_true(_rgb(image, x + 2, y) == (61, 61, 66))
    with assert_raises(contains="its own data"):
        _ = bland_altman_image(
            List[Float64](first[0:3]),
            List[Float64](second[0:3]),
            result,
            101,
            101,
        )
    var sizes: List[Int] = [63, 4097, 64, 64]
    var heights: List[Int] = [64, 64, 63, 4097]
    for n in range(4):
        with assert_raises(contains="pixels a side"):
            _ = bland_altman_image(first, second, result, sizes[n], heights[n])
    var same = bland_altman([2.0, 2.0], [1.0, 1.0])
    with assert_raises(contains="vary"):
        _ = bland_altman_image([2.0, 2.0], [1.0, 1.0], same, 64, 64)
    var level: List[Float64] = [1.0, 2.0]
    var flat = bland_altman(level, level)
    with assert_raises(contains="vary"):
        _ = bland_altman_image(level, level, flat, 64, 64)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
