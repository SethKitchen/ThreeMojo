# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gamma tails and quantiles, exact Poisson intervals, standardized ratios
and directly standardized rates.

`assets/standardize/standardize_expected.txt` holds the values of scipy
and statsmodels. See `assets/standardize/make_standardize.py`.
"""

from extensions.clinical.standardize import (
    direct_rate,
    expected_events,
    poisson_interval,
    standardized_ratio,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import PER_YEAR64, YEAR64, Duration64, Frequency64
from extensions.numerics.distributions import gamma_quantile, gamma_tails


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _rows(kind: String) raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/standardize/standardize_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if String(parts[0]) != kind:
            continue
        var row = List[Float64]()
        for at in range(1, len(parts)):
            row.append(atof(String(parts[at])))
        out.append(row^)
    return out^


def test_gamma() raises:
    var tails = _rows("tails")
    assert_equal(len(tails), 40)
    for row in tails:
        var found = gamma_tails(row[1], row[0])
        # The cancellation in `a ln x - x - ln Gamma(a)` grows with a.
        var tolerance = 5e-14 if row[0] < 1000 else 5e-10
        _close(found[0], row[2], tolerance)
        _close(found[1], row[3], tolerance)
    var quantiles = _rows("quantile")
    assert_equal(len(quantiles), 40)
    for row in quantiles:
        var tolerance = 5e-14 if row[0] < 1000 else 2e-12
        _close(gamma_quantile(row[1], row[0]), row[2], tolerance)
    var edge = gamma_tails(0.0, 2.0)
    assert_equal(edge[0], 0.0)
    assert_equal(edge[1], 1.0)
    edge = gamma_tails(inf[DType.float64](), 2.0)
    assert_equal(edge[0], 1.0)
    assert_equal(edge[1], 0.0)


def test_poisson() raises:
    for row in _rows("poisson"):
        var band = poisson_interval(Int(row[0]))
        if row[1] == 0:
            assert_equal(band[0], 0.0)
        else:
            _close(band[0], row[1], 1e-12)
        _close(band[1], row[2], 1e-12)


def test_ratios() raises:
    var rows = _rows("ratio")
    assert_equal(len(rows), 5)
    for row in rows:
        var found = standardized_ratio(Int(row[0]), row[1])
        _close(found.ratio, row[2], 1e-15)
        if row[3] == 0:
            assert_equal(found.lower, 0.0)
        else:
            _close(found.lower, row[3], 1e-12)
        _close(found.upper, row[4], 1e-12)
        _close(found.p_value, row[5], 1e-11)
    # A ratio of exactly the expected count has a p value of 1.
    assert_equal(standardized_ratio(5, 5.0).p_value, 1.0)


def test_direct() raises:
    var events = List[Int]()
    var years = List[Duration64]()
    var shares = List[Float64]()
    for row in _rows("group"):
        events.append(Int(row[0]))
        years.append(Duration64(row[1], YEAR64))
        shares.append(row[2])
    var expected = _rows("direct")[0].copy()
    var found = direct_rate(events, years, shares)
    _close(found.rate.to(PER_YEAR64), expected[0], 1e-13)
    _close(found.lower.to(PER_YEAR64), expected[1], 1e-11)
    _close(found.upper.to(PER_YEAR64), expected[2], 1e-11)
    var empty = _rows("empty")[0].copy()
    var none = direct_rate(List[Int](length=6, fill=0), years, shares)
    assert_equal(none.rate.to(PER_YEAR64), 0.0)
    assert_equal(none.lower.to(PER_YEAR64), 0.0)
    _close(none.upper.to(PER_YEAR64), empty[2], 1e-12)
    # The expected events at the rates of a reference population.
    var rates: List[Frequency64] = [
        Frequency64(0.001, PER_YEAR64),
        Frequency64(0.004, PER_YEAR64),
    ]
    var time: List[Duration64] = [
        Duration64(1000, YEAR64),
        Duration64(500, YEAR64),
    ]
    _close(expected_events(time, rates), 3.0, 1e-14)


def test_errors() raises:
    var shapes: List[Float64] = [0.0, 2e7, nan[DType.float64]()]
    for a in shapes:
        with assert_raises(contains="gamma shape"):
            _ = gamma_tails(1.0, a)
    with assert_raises(contains="gamma point"):
        _ = gamma_tails(-1.0, 1.0)
    with assert_raises(contains="gamma point"):
        _ = gamma_tails(nan[DType.float64](), 1.0)
    var ps: List[Float64] = [0.0, 1.0, nan[DType.float64]()]
    for p in ps:
        with assert_raises(contains="above 0, below 1"):
            _ = gamma_quantile(p, 1.0)
    with assert_raises(contains="gamma shape"):
        _ = gamma_quantile(0.5, 0.0)
    var counts: List[Int] = [-1, 10000000]
    for c in counts:
        with assert_raises(contains="Poisson count"):
            _ = poisson_interval(c)
    var expected: List[Float64] = [0.0, inf[DType.float64]()]
    for e in expected:
        with assert_raises(contains="expected count"):
            _ = standardized_ratio(3, e)
    var year = Duration64(1, YEAR64)
    var rate = Frequency64(0.01, PER_YEAR64)
    with assert_raises(contains="one rate for each group"):
        _ = expected_events(List[Duration64](), List[Frequency64]())
    with assert_raises(contains="one rate for each group"):
        _ = expected_events([year], [rate, rate])
    var times: List[Float64] = [-1.0, inf[DType.float64]()]
    for t in times:
        with assert_raises(contains="0 or more, finite"):
            _ = expected_events([Duration64(t, YEAR64)], [rate])
    var bad_rates: List[Float64] = [-1.0, inf[DType.float64]()]
    for r in bad_rates:
        with assert_raises(contains="0 or more, finite"):
            _ = expected_events([year], [Frequency64(r, PER_YEAR64)])
    with assert_raises(contains="events, person-time and a share"):
        _ = direct_rate(List[Int](), List[Duration64](), List[Float64]())
    with assert_raises(contains="events, person-time and a share"):
        _ = direct_rate([1], [year, year], [1.0])
    with assert_raises(contains="events, person-time and a share"):
        _ = direct_rate([1], [year], [0.5, 0.5])
    with assert_raises(contains="0 or more"):
        _ = direct_rate([-1], [year], [1.0])
    var bad_times: List[Float64] = [0.0, inf[DType.float64]()]
    for t in bad_times:
        with assert_raises(contains="person-time must be positive"):
            _ = direct_rate([1], [Duration64(t, YEAR64)], [1.0])
    var bad_shares: List[Float64] = [-0.5, inf[DType.float64]()]
    for s in bad_shares:
        with assert_raises(contains="standard share"):
            _ = direct_rate([1], [year], [s])
    with assert_raises(contains="sum to 1"):
        _ = direct_rate([1, 2], [year, year], [0.5, 0.6])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
