# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two-by-two tables in strata, pooled by the method of Mantel and
Haenszel.

A confounder, such as age, can make an exposure look more or less harmful
than it is. Split the patients into strata of the confounder, with one
two-by-two table each, and pool the tables:

- `mantel_haenszel(strata)` gives the pooled odds ratio, with the variance
  of Robins, Breslow and Greenland (1986), and the pooled risk ratio, with
  the variance of Greenland and Robins (1985). It gives the
  Cochran-Mantel-Haenszel test that the common odds ratio is 1, with and
  without the continuity correction, and the crude ratios of the summed
  table. A crude ratio far from the pooled one shows confounding.
- `breslow_day(strata)` tests that the odds ratios of the strata are equal,
  with and without Tarone's adjustment. Pool only strata that share one
  ratio.

Each stratum holds `a` and `b`, the exposed patients with and without the
outcome, and `c` and `d`, the unexposed patients with and without it.
"""

from extensions.numerics.elementary import precise_exp
from extensions.clinical.proportions import Estimate
from extensions.clinical.survival import Z95
from extensions.clinical.tables import TableTest
from std.math import sqrt

# The most strata of one analysis.
comptime MAX_STRATA = 1000


struct Stratum(Copyable, ImplicitlyCopyable, Movable):
    """The two-by-two table of one stratum."""

    var a: Int
    """The exposed patients with the outcome."""
    var b: Int
    """The exposed patients without the outcome."""
    var c: Int
    """The unexposed patients with the outcome."""
    var d: Int
    """The unexposed patients without the outcome."""

    def __init__(out self, a: Int, b: Int, c: Int, d: Int):
        """Create a stratum.

        Args:
            a: The exposed patients with the outcome.
            b: The exposed patients without the outcome.
            c: The unexposed patients with the outcome.
            d: The unexposed patients without the outcome.
        """
        self.a = a
        self.b = b
        self.c = c
        self.d = d

    def total(self) -> Float64:
        """Return the patients of the stratum.

        Returns:
            `a + b + c + d`.
        """
        return Float64(self.a + self.b + self.c + self.d)


def _require_strata(strata: List[Stratum]) raises:
    """Refuse strata out of range, a cell below 0, or a stratum of fewer
    than two patients."""
    if len(strata) == 0 or len(strata) > MAX_STRATA:
        raise Error("A stratified analysis has from 1 to 1000 strata")
    for s in strata:  # pragma: no branch
        if s.a < 0 or s.b < 0 or s.c < 0 or s.d < 0:
            raise Error("The cells of a stratum must be 0 or more")
        if s.total() < 2:
            raise Error("A stratum needs 2 patients or more")


def _pooled_odds(strata: List[Stratum]) raises -> Float64:
    """Return the Mantel-Haenszel odds ratio, refusing one that is 0 or
    infinite."""
    var r = 0.0
    var s = 0.0
    for t in strata:  # pragma: no branch
        r += Float64(t.a * t.d) / t.total()
        s += Float64(t.b * t.c) / t.total()
    if not (r > 0 and s > 0):
        raise Error(
            "A pooled ratio needs a stratum with a and d above 0, and one"
            " with b and c above 0"
        )
    return r / s


struct MantelHaenszel(Copyable, Movable):
    """The pooled measures and the test of stratified tables."""

    var odds_ratio: Estimate
    """The pooled odds ratio, with its 95 percent interval."""
    var log_odds_error: Float64
    """The standard error of the log of the pooled odds ratio."""
    var risk_ratio: Estimate
    """The pooled risk ratio, with its 95 percent interval."""
    var log_risk_error: Float64
    """The standard error of the log of the pooled risk ratio."""
    var test: TableTest
    """The Cochran-Mantel-Haenszel test that the odds ratio is 1."""
    var corrected: TableTest
    """The same test with the continuity correction, as R gives it."""
    var crude_odds_ratio: Float64
    """The odds ratio of the summed table."""
    var crude_risk_ratio: Float64
    """The risk ratio of the summed table."""

    def __init__(
        out self,
        odds_ratio: Estimate,
        log_odds_error: Float64,
        risk_ratio: Estimate,
        log_risk_error: Float64,
        test: TableTest,
        corrected: TableTest,
    ):
        """Create a result.

        Args:
            odds_ratio: The pooled odds ratio.
            log_odds_error: The standard error of its log.
            risk_ratio: The pooled risk ratio.
            log_risk_error: The standard error of its log.
            test: The test without the correction.
            corrected: The test with the correction.
        """
        self.odds_ratio = odds_ratio.copy()
        self.log_odds_error = log_odds_error
        self.risk_ratio = risk_ratio.copy()
        self.log_risk_error = log_risk_error
        self.test = test.copy()
        self.corrected = corrected.copy()
        self.crude_odds_ratio = 0.0
        self.crude_risk_ratio = 0.0


def _estimate(ratio: Float64, error: Float64) -> Estimate:
    """Return a ratio with the interval `ratio exp(-+ 1.96 se)`."""
    var half = Z95 * error
    return Estimate(
        ratio, ratio * precise_exp(-half), ratio * precise_exp(half)
    )


def mantel_haenszel(strata: List[Stratum]) raises -> MantelHaenszel:
    """Pool the odds ratio and the risk ratio of stratified tables.

    Args:
        strata: The tables, from 1 to 1000.

    Returns:
        The pooled odds and risk ratios with their errors and intervals,
        the Cochran-Mantel-Haenszel test, and the crude ratios.

    Raises:
        Error: If there are not 1 to 1000 strata, a cell is below 0, a
            stratum has fewer than two patients, or no stratum has `a` and
            `d` above 0 or none has `b` and `c` above 0.
    """
    _require_strata(strata)
    var ratio = _pooled_odds(strata)
    # The sums of Robins, Breslow and Greenland.
    var r = 0.0
    var s = 0.0
    var pr = 0.0
    var cross = 0.0
    var qs = 0.0
    # The sums of Greenland and Robins.
    var risk_top = 0.0
    var risk_bottom = 0.0
    var spread = 0.0
    # The Cochran-Mantel-Haenszel sums.
    var gap = 0.0
    var variance = 0.0
    var totals = Stratum(0, 0, 0, 0)
    for t in strata:  # pragma: no branch
        var n = t.total()
        var a = Float64(t.a)
        var b = Float64(t.b)
        var c = Float64(t.c)
        var d = Float64(t.d)
        var p = (a + d) / n
        var q = (b + c) / n
        var ri = a * d / n
        var si = b * c / n
        r += ri
        s += si
        pr += p * ri
        cross += p * si + q * ri
        qs += q * si
        var exposed = a + b
        var unexposed = c + d
        var cases = a + c
        risk_top += a * unexposed / n
        risk_bottom += c * exposed / n
        spread += (exposed * unexposed * cases - a * c * n) / (n * n)
        gap += a - exposed * cases / n
        variance += exposed * unexposed * cases * (b + d) / (n * n * (n - 1.0))
        totals.a += t.a
        totals.b += t.b
        totals.c += t.c
        totals.d += t.d
    var odds_error = sqrt(
        pr / (2.0 * r * r) + cross / (2.0 * r * s) + qs / (2.0 * s * s)
    )
    var risk_error = sqrt(spread / (risk_top * risk_bottom))
    var size = abs(gap)
    if size >= 0.5:
        size -= 0.5
    var out = MantelHaenszel(
        _estimate(ratio, odds_error),
        odds_error,
        _estimate(risk_top / risk_bottom, risk_error),
        risk_error,
        TableTest(gap * gap / variance, 1),
        TableTest(size * size / variance, 1),
    )
    out.crude_odds_ratio = Float64(totals.a * totals.d) / Float64(
        totals.b * totals.c
    )
    out.crude_risk_ratio = (
        Float64(totals.a)
        / Float64(totals.a + totals.b)
        / (Float64(totals.c) / Float64(totals.c + totals.d))
    )
    return out^


struct BreslowDay(Copyable, Movable):
    """The Breslow-Day test that the strata share one odds ratio."""

    var test: TableTest
    """The Breslow-Day test."""
    var tarone: TableTest
    """The test with Tarone's adjustment, which has the chi-square
    distribution when the pooled odds ratio is that of Mantel and
    Haenszel."""
    var strata: Int
    """The strata of the test: those with no margin of 0."""

    def __init__(out self, test: TableTest, tarone: TableTest, strata: Int):
        """Create a result.

        Args:
            test: The test.
            tarone: The adjusted test.
            strata: The strata of the test.
        """
        self.test = test.copy()
        self.tarone = tarone.copy()
        self.strata = strata


def breslow_day(strata: List[Stratum]) raises -> BreslowDay:
    """Test that the odds ratios of the strata are equal.

    For each stratum, the expected `a` is the one that gives the stratum
    the pooled odds ratio with its margins. The statistic sums
    `(a - E)^2 / V` over the strata, with `V` the variance of `a` from the
    four expected cells. A stratum with a margin of 0 says nothing of its
    odds ratio, so the test leaves it out.

    Args:
        strata: The tables, from 1 to 1000.

    Returns:
        The test and Tarone's adjusted test, each with one degree of
        freedom less than the strata that it uses.

    Raises:
        Error: If the strata are not valid, as for `mantel_haenszel`, or
            fewer than two strata have no margin of 0.
    """
    _require_strata(strata)
    var ratio = _pooled_odds(strata)
    var statistic = 0.0
    var observed = 0.0
    var expected = 0.0
    var variance = 0.0
    var used = 0
    for t in strata:  # pragma: no branch
        var n = t.total()
        var exposed = Float64(t.a + t.b)
        var cases = Float64(t.a + t.c)
        if exposed == 0 or cases == 0 or exposed == n or cases == n:
            continue
        # The root in range of (1 - r) e^2 + qb e - r n1 m1 = 0, in the
        # form that does not cancel.
        var qa = 1.0 - ratio
        var qb = ratio * (exposed + cases) + (n - exposed - cases)
        var qc = -ratio * exposed * cases
        var root = sqrt(max(qb * qb - 4.0 * qa * qc, 0.0))
        var e: Float64
        if qb >= 0:
            e = -2.0 * qc / (qb + root)
        else:
            e = (root - qb) / (2.0 * qa)
        var v = 1.0 / (
            1.0 / e
            + 1.0 / (exposed - e)
            + 1.0 / (cases - e)
            + 1.0 / (n - exposed - cases + e)
        )
        var a = Float64(t.a)
        statistic += (a - e) * (a - e) / v
        observed += a
        expected += e
        variance += v
        used += 1
    if used < 2:
        raise Error(
            "A Breslow-Day test needs 2 strata or more with no margin of 0"
        )
    var shift = observed - expected
    return BreslowDay(
        TableTest(statistic, used - 1),
        TableTest(max(statistic - shift * shift / variance, 0.0), used - 1),
        used,
    )
