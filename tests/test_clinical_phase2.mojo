# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Simon's two-stage designs and the posterior of a response rate.

`assets/phase2/phase2_expected.txt` holds the designs of Simon's table of
1989, scipy's binomial probabilities for them, and scipy's beta tails. See
`assets/phase2/make_phase2.py`. The test builds the errors of each design
from the binomial probabilities.
"""

from extensions.clinical.phase2 import (
    SimonDesign,
    posterior_above,
    simon_errors,
    simon_minimax,
    simon_optimal,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def _rows(kind: String) raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/phase2/phase2_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if String(parts[0]) != kind:
            continue
        var row = List[Float64]()
        for at in range(1, len(parts)):
            row.append(atof(String(parts[at])))
        out.append(row^)
    return out^


def _binomial(m: Int, p: Float64) raises -> List[Float64]:
    """Return scipy's pmf and then its sf of k from 0 to m."""
    for row in _rows("binomial"):
        if Int(row[0]) == m and row[1] == p:
            return List[Float64](row[2:])
    raise Error("The fixture has no binomial table of that size and chance")


def _simon(
    r1: Int, n1: Int, r: Int, n: Int, p: Float64
) raises -> Tuple[Float64, Float64]:
    """Return the chance of rejecting the null at p, and of an early stop.

    A design rejects when x1 > r1 and x1 + x2 > r, so the chance is the sum
    over x1 from r1 + 1 to n1 of P(x1) P(x2 > r - x1). It stops early with
    P(x1 <= r1) = 1 - P(x1 > r1).
    """
    var first = _binomial(n1, p)
    var m = n - n1
    var second = _binomial(m, p)
    var reject = 0.0
    for x1 in range(r1 + 1, n1 + 1):
        var k = r - x1
        var above = 1.0 if k < 0 else second[m + 1 + k]
        reject += first[x1] * above
    return (reject, 1.0 - first[n1 + 1 + r1])


def _check(design: SimonDesign, row: List[Float64], at: Int) raises:
    """Check a design against Simon's table and the errors of scipy."""
    var r1 = Int(row[at])
    var n1 = Int(row[at + 1])
    var r = Int(row[at + 2])
    var n = Int(row[at + 3])
    assert_equal(design.r1, r1)
    assert_equal(design.n1, n1)
    assert_equal(design.r, r)
    assert_equal(design.n, n)
    var null = _simon(r1, n1, r, n, row[0])
    var alternative = _simon(r1, n1, r, n, row[1])
    assert_almost_equal(design.early_stop, null[1], rtol=1e-12)
    assert_almost_equal(
        design.expected,
        Float64(n1) + (1.0 - null[1]) * Float64(n - n1),
        rtol=1e-13,
    )
    assert_almost_equal(design.alpha, null[0], rtol=1e-11)
    assert_almost_equal(design.power, alternative[0], rtol=1e-12)


def test_optimal() raises:
    var rows = _rows("design")
    assert_equal(len(rows), 3)
    for row in rows:
        _check(simon_optimal(row[0], row[1], row[2], row[3], 60), row, 4)


def test_minimax() raises:
    for row in _rows("design"):
        _check(simon_minimax(row[0], row[1], row[2], row[3], 60), row, 8)


def test_errors_of_a_design() raises:
    # The optimal design of 0.1 against 0.3: 1/10, then 5/29.
    var design = simon_optimal(0.1, 0.3, 0.05, 0.2, 40)
    var null = simon_errors(design, 0.1)
    assert_almost_equal(null[0], design.alpha, rtol=1e-15)
    assert_almost_equal(null[1], design.early_stop, rtol=1e-15)
    var alternative = simon_errors(design, 0.3)
    assert_almost_equal(alternative[0], design.power, rtol=1e-15)
    # A high p0 of 0.3 needs more than two patients before any design.
    var high = simon_minimax(0.3, 0.6, 0.05, 0.2, 40)
    assert_equal(high.n > 2, True)


def test_posterior() raises:
    var rows = _rows("posterior")
    assert_equal(len(rows), 4)
    for row in rows:
        assert_almost_equal(
            posterior_above(row[0], row[1], Int(row[2]), Int(row[3]), row[4]),
            row[5],
            rtol=1e-12,
        )


def test_errors() raises:
    var pairs: List[Tuple[Float64, Float64]] = [
        (0.0, 0.3),
        (0.3, 0.3),
        (0.3, 1.0),
        (nan[DType.float64](), 0.3),
    ]
    for p in pairs:
        with assert_raises(contains="0 < p0 < p1 < 1"):
            _ = simon_optimal(p[0], p[1], 0.05, 0.2, 40)
    var errors: List[Tuple[Float64, Float64]] = [
        (0.0, 0.2),
        (0.5, 0.2),
        (0.05, 0.0),
        (0.05, 0.5),
    ]
    for e in errors:
        with assert_raises(contains="alpha and beta"):
            _ = simon_minimax(0.1, 0.3, e[0], e[1], 40)
    var sizes: List[Int] = [1, 101]
    for most in sizes:
        with assert_raises(contains="from 2 to 100"):
            _ = simon_optimal(0.1, 0.3, 0.05, 0.2, most)
    with assert_raises(contains="No Simon design"):
        _ = simon_optimal(0.1, 0.3, 0.05, 0.2, 10)
    var design = simon_optimal(0.1, 0.3, 0.05, 0.2, 40)
    var rates: List[Float64] = [0.0, 1.0]
    for p in rates:
        with assert_raises(contains="response rate"):
            _ = simon_errors(design, p)
    var bad: List[Tuple[Int, Int, Int, Int]] = [
        (-1, 10, 5, 29),
        (10, 10, 12, 29),
        (1, 29, 5, 29),
        (6, 10, 5, 29),
        (1, 10, 29, 29),
        (1, 10, 5, 101),
    ]
    for d in bad:
        with assert_raises(contains="0 <= r1 < n1 < n"):
            _ = simon_errors(
                SimonDesign(d[0], d[1], d[2], d[3], 0.5, 0.05, 0.8), 0.2
            )
    var shapes: List[Tuple[Float64, Float64]] = [
        (0.0, 1.0),
        (1.0, 0.0),
        (inf[DType.float64](), 1.0),
        (1.0, inf[DType.float64]()),
    ]
    for s in shapes:
        with assert_raises(contains="beta prior"):
            _ = posterior_above(s[0], s[1], 3, 10, 0.2)
    var counts: List[Tuple[Int, Int]] = [(3, 0), (-1, 10), (11, 10)]
    for c in counts:
        with assert_raises(contains="from 0 to the patients"):
            _ = posterior_above(1.0, 1.0, c[0], c[1], 0.2)
    for p in rates:
        with assert_raises(contains="response rate"):
            _ = posterior_above(1.0, 1.0, 3, 10, p)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
