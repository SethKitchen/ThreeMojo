# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stratified two-by-two tables: Mantel-Haenszel and Breslow-Day.

`assets/strata/strata_expected.txt` holds the values of statsmodels and
scipy for a synthetic cohort in four age groups. See
`assets/strata/make_strata.py`.
"""

from extensions.clinical.strata import (
    MAX_STRATA,
    Stratum,
    breslow_day,
    mantel_haenszel,
)
from extensions.clinical.tables import chi_square_test
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _rows() raises -> Dict[String, List[List[Float64]]]:
    var out = Dict[String, List[List[Float64]]]()
    var text = open("assets/strata/strata_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        var name = String(parts[0])
        var values = List[Float64]()
        for at in range(1, len(parts)):
            values.append(atof(String(parts[at])))
        if name not in out:
            out[name] = List[List[Float64]]()
        out[name].append(values^)
    return out^


def _strata(rows: List[List[Float64]]) -> List[Stratum]:
    var out = List[Stratum]()
    for row in rows:
        out.append(Stratum(Int(row[0]), Int(row[1]), Int(row[2]), Int(row[3])))
    return out^


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def test_against_statsmodels() raises:
    var rows = _rows()
    var strata = _strata(rows["table"])
    assert_equal(len(strata), 4)
    var mh = mantel_haenszel(strata)
    ref odds = rows["odds"][0]
    _close(mh.odds_ratio.value, odds[0], 1e-14)
    _close(mh.log_odds_error, odds[1], 1e-13)
    _close(mh.odds_ratio.lower, odds[2], 1e-13)
    _close(mh.odds_ratio.upper, odds[3], 1e-13)
    ref risk = rows["risk"][0]
    _close(mh.risk_ratio.value, risk[0], 1e-14)
    _close(mh.log_risk_error, risk[1], 1e-13)
    _close(mh.risk_ratio.lower, risk[2], 1e-13)
    _close(mh.risk_ratio.upper, risk[3], 1e-13)
    ref cmh = rows["cmh"][0]
    _close(mh.test.statistic, cmh[0], 1e-13)
    _close(mh.test.p_value, cmh[1], 1e-11)
    assert_equal(mh.test.freedom, 1)
    _close(mh.corrected.statistic, cmh[2], 1e-13)
    _close(mh.corrected.p_value, cmh[3], 1e-11)
    ref crude = rows["crude"][0]
    _close(mh.crude_odds_ratio, crude[0], 1e-15)
    _close(mh.crude_risk_ratio, crude[1], 1e-15)
    var day = breslow_day(strata)
    ref expected = rows["breslow"][0]
    _close(day.test.statistic, expected[0], 1e-11)
    _close(day.test.p_value, expected[1], 1e-12)
    _close(day.tarone.statistic, expected[2], 1e-11)
    _close(day.tarone.p_value, expected[3], 1e-12)
    assert_equal(day.test.freedom, 3)
    assert_equal(day.strata, 4)


def test_other_root() raises:
    # A small pooled odds ratio and a stratum with more exposed patients and
    # cases than patients take the other form of the expected cell.
    ref odd = _rows()["odd"][0]
    var strata: List[Stratum] = [
        Stratum(Int(odd[0]), Int(odd[1]), Int(odd[2]), Int(odd[3])),
        Stratum(Int(odd[4]), Int(odd[5]), Int(odd[6]), Int(odd[7])),
    ]
    var day = breslow_day(strata)
    _close(day.test.statistic, odd[8], 1e-12)
    _close(day.tarone.statistic, odd[9], 1e-12)
    assert_equal(day.test.freedom, 1)


def test_one_stratum() raises:
    # One stratum gives the ratios of its table, with Woolf's variance and
    # the variance of the log risk ratio.
    var mh = mantel_haenszel([Stratum(10, 20, 5, 40)])
    _close(mh.odds_ratio.value, 4.0, 1e-15)
    _close(
        mh.log_odds_error,
        sqrt(1.0 / 10.0 + 1.0 / 20.0 + 1.0 / 5.0 + 1.0 / 40.0),
        1e-15,
    )
    _close(mh.risk_ratio.value, 3.0, 1e-15)
    _close(
        mh.log_risk_error,
        sqrt(1.0 / 10.0 - 1.0 / 30.0 + 1.0 / 5.0 - 1.0 / 45.0),
        1e-15,
    )
    assert_equal(mh.crude_odds_ratio, 4.0)
    _close(mh.crude_risk_ratio, 3.0, 1e-15)
    # The test is Pearson's chi-square times (n - 1) / n.
    var pearson = chi_square_test([[10, 20], [5, 40]]).statistic
    _close(mh.test.statistic, pearson * 74.0 / 75.0, 1e-14)
    # The interval is symmetric about the log of the ratio.
    _close(mh.odds_ratio.lower * mh.odds_ratio.upper, 16.0, 1e-14)


def test_continuity_correction() raises:
    # The correction subtracts a half from |O - E| only when it is a half or
    # more, as R does.
    var close = mantel_haenszel([Stratum(2, 2, 2, 3)])
    assert_true(close.test.statistic > 0)
    assert_equal(close.corrected.statistic, close.test.statistic)
    var far = mantel_haenszel([Stratum(10, 20, 5, 40)])
    # O - E is 10 - 6 = 4, so the corrected statistic is (3.5 / 4)^2 of it.
    _close(far.corrected.statistic, far.test.statistic * 0.765625, 1e-14)


def test_equal_strata() raises:
    # Two strata of one odds ratio give a Breslow-Day statistic of 0.
    var day = breslow_day([Stratum(10, 20, 5, 40), Stratum(20, 40, 10, 80)])
    assert_almost_equal(day.test.statistic, 0.0, atol=1e-24)
    assert_almost_equal(day.tarone.statistic, 0.0, atol=1e-24)
    assert_almost_equal(day.test.p_value, 1.0, atol=1e-12)


def test_zero_margins() raises:
    # A stratum with a margin of 0 says nothing of its odds ratio.
    var pair: List[Stratum] = [Stratum(10, 20, 5, 40), Stratum(12, 9, 7, 11)]
    var with_zeros = pair.copy()
    with_zeros.append(Stratum(0, 0, 4, 6))
    with_zeros.append(Stratum(0, 5, 0, 6))
    with_zeros.append(Stratum(3, 4, 0, 0))
    with_zeros.append(Stratum(3, 0, 4, 0))
    var day = breslow_day(with_zeros)
    var plain = breslow_day(pair)
    assert_equal(day.strata, 2)
    assert_equal(day.test.freedom, 1)
    _close(day.test.statistic, plain.test.statistic, 1e-14)
    _close(
        mantel_haenszel(with_zeros).odds_ratio.value,
        mantel_haenszel(pair).odds_ratio.value,
        1e-15,
    )


def test_errors() raises:
    with assert_raises(contains="1 to 1000 strata"):
        _ = mantel_haenszel(List[Stratum]())
    var many = List[Stratum]()
    for _ in range(MAX_STRATA + 1):
        many.append(Stratum(1, 1, 1, 1))
    with assert_raises(contains="1 to 1000 strata"):
        _ = mantel_haenszel(many)
    var cells: List[Stratum] = [
        Stratum(-1, 1, 1, 1),
        Stratum(1, -1, 1, 1),
        Stratum(1, 1, -1, 1),
        Stratum(1, 1, 1, -1),
    ]
    for cell in cells:
        with assert_raises(contains="0 or more"):
            _ = mantel_haenszel([cell])
    with assert_raises(contains="2 patients or more"):
        _ = breslow_day([Stratum(1, 1, 1, 1), Stratum(1, 0, 0, 0)])
    with assert_raises(contains="a and d above 0"):
        _ = mantel_haenszel([Stratum(0, 5, 5, 5)])
    with assert_raises(contains="a and d above 0"):
        _ = mantel_haenszel([Stratum(5, 0, 5, 5)])
    with assert_raises(contains="2 strata or more"):
        _ = breslow_day([Stratum(10, 20, 5, 40)])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
