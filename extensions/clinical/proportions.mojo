# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Proportions and the measures of two-by-two tables, with 95 percent
intervals.

- `wilson_interval` and `exact_interval` give the interval of a
  proportion: Wilson's score interval, and the exact interval of Clopper
  and Pearson from the beta distribution.
- `diagnostic_accuracy` gives the sensitivity, specificity, predictive
  values, accuracy and prevalence of a test with their exact intervals,
  and its likelihood ratios with log intervals.
- `compare_risks` gives the risk difference, the risk ratio, the odds
  ratio and the number needed to treat of two groups.

All intervals are 95 percent.
"""

from extensions.numerics.distributions import (
    Z95,
    beta_quantile,
    ratio_interval,
    wald_interval,
)
from extensions.numerics.elementary import precise_exp
from extensions.clinical.meta import log_odds_ratio, log_risk_ratio
from std.math import inf, sqrt


struct Estimate(Copyable, Movable):
    """A value with its 95 percent interval."""

    var value: Float64
    """The value."""
    var lower: Float64
    """The low end of the interval."""
    var upper: Float64
    """The high end of the interval."""

    def __init__(out self, value: Float64, lower: Float64, upper: Float64):
        """Create an estimate.

        Args:
            value: The value.
            lower: The low end of the interval.
            upper: The high end of the interval.
        """
        self.value = value
        self.lower = lower
        self.upper = upper


def _require_count(successes: Int, trials: Int) raises:
    """Refuse a proportion with no trial, or successes out of range."""
    if trials < 1 or successes < 0 or successes > trials:
        raise Error("A proportion needs successes from 0 to its trials")


def wilson_interval(
    successes: Int, trials: Int
) raises -> Tuple[Float64, Float64]:
    """Return Wilson's score interval of a proportion.

    Args:
        successes: The successes, from 0 to the trials.
        trials: The trials, 1 or more.

    Returns:
        The low and the high end. The interval stays in [0, 1], and it is
        not empty at 0 or all successes.

    Raises:
        Error: If the counts are out of range.
    """
    _require_count(successes, trials)
    var x = Float64(successes)
    var n = Float64(trials)
    var z2 = Z95 * Z95
    var center = (x + z2 / 2.0) / (n + z2)
    var half = Z95 / (n + z2) * sqrt(x * (n - x) / n + z2 / 4.0)
    return (center - half, center + half)


def exact_interval(
    successes: Int, trials: Int
) raises -> Tuple[Float64, Float64]:
    """Return the exact interval of Clopper and Pearson of a proportion.

    Args:
        successes: The successes, from 0 to the trials.
        trials: The trials, 1 or more.

    Returns:
        The low end, the 0.025 quantile of Beta(x, n - x + 1), and the high
        end, the 0.975 quantile of Beta(x + 1, n - x). The low end is 0 at
        0 successes, and the high end is 1 at all successes.

    Raises:
        Error: If the counts are out of range.
    """
    _require_count(successes, trials)
    var x = Float64(successes)
    var n = Float64(trials)
    var low = 0.0
    var high = 1.0
    if successes > 0:
        low = beta_quantile(0.025, x, n - x + 1.0)
    if successes < trials:
        high = beta_quantile(0.975, x + 1.0, n - x)
    return (low, high)


def _exact(successes: Int, trials: Int) raises -> Estimate:
    """Return a proportion with its exact interval."""
    var band = exact_interval(successes, trials)
    return Estimate(Float64(successes) / Float64(trials), band[0], band[1])


def _ratio(effect: Tuple[Float64, Float64]) -> Estimate:
    """Return a ratio and its interval from its log and the variance."""
    var ratio = precise_exp(effect[0])
    var band = ratio_interval(ratio, sqrt(effect[1]))
    return Estimate(ratio, band[0], band[1])


struct DiagnosticAccuracy(Copyable, Movable):
    """The accuracy of a diagnostic test against a reference standard."""

    var sensitivity: Estimate
    """The fraction of diseased patients that the test finds."""
    var specificity: Estimate
    """The fraction of healthy patients that the test clears."""
    var positive_predictive: Estimate
    """The fraction of positive tests that are right."""
    var negative_predictive: Estimate
    """The fraction of negative tests that are right."""
    var accuracy: Estimate
    """The fraction of all tests that are right."""
    var prevalence: Estimate
    """The fraction of patients that are diseased."""
    var positive_likelihood: Estimate
    """`sensitivity / (1 - specificity)`: how much a positive test raises
    the odds of disease."""
    var negative_likelihood: Estimate
    """`(1 - sensitivity) / specificity`: how much a negative test lowers
    the odds of disease."""

    def __init__(
        out self,
        true_positive: Int,
        false_positive: Int,
        false_negative: Int,
        true_negative: Int,
    ) raises:
        """Measure a test from the four cells of its table.

        Args:
            true_positive: Diseased patients with a positive test.
            false_positive: Healthy patients with a positive test.
            false_negative: Diseased patients with a negative test.
            true_negative: Healthy patients with a negative test.

        Raises:
            Error: If a cell is negative, or a margin has no patient.
        """
        var diseased = true_positive + false_negative
        var healthy = false_positive + true_negative
        var positive = true_positive + false_positive
        var negative = false_negative + true_negative
        if (
            true_positive < 0
            or false_positive < 0
            or false_negative < 0
            or true_negative < 0
        ):
            raise Error("The cells of a diagnostic table must be 0 or more")
        if diseased == 0 or healthy == 0 or positive == 0 or negative == 0:
            raise Error(
                "A diagnostic table needs diseased, healthy, positive and"
                " negative patients"
            )
        var total = diseased + healthy
        self.sensitivity = _exact(true_positive, diseased)
        self.specificity = _exact(true_negative, healthy)
        self.positive_predictive = _exact(true_positive, positive)
        self.negative_predictive = _exact(true_negative, negative)
        self.accuracy = _exact(true_positive + true_negative, total)
        self.prevalence = _exact(diseased, total)
        # A likelihood ratio is a risk ratio of a test result, diseased
        # against healthy.
        self.positive_likelihood = _ratio(
            log_risk_ratio(true_positive, diseased, false_positive, healthy)
        )
        self.negative_likelihood = _ratio(
            log_risk_ratio(false_negative, diseased, true_negative, healthy)
        )


def diagnostic_accuracy(
    true_positive: Int,
    false_positive: Int,
    false_negative: Int,
    true_negative: Int,
) raises -> DiagnosticAccuracy:
    """Return the accuracy of a diagnostic test.

    The proportions have exact intervals. The likelihood ratios have log
    intervals, with a half added to each cell when one is 0.

    Args:
        true_positive: Diseased patients with a positive test.
        false_positive: Healthy patients with a positive test.
        false_negative: Diseased patients with a negative test.
        true_negative: Healthy patients with a negative test.

    Returns:
        The measures of the test.

    Raises:
        Error: If a cell is negative, or a margin has no patient.
    """
    return DiagnosticAccuracy(
        true_positive, false_positive, false_negative, true_negative
    )


struct RiskComparison(Copyable, Movable):
    """The risks of an event in two groups, such as treated and control."""

    var first: Estimate
    """The risk of the first group, with its exact interval."""
    var second: Estimate
    """The risk of the second group, with its exact interval."""
    var difference: Estimate
    """The first risk less the second, with the Wald interval."""
    var ratio: Estimate
    """The first risk over the second, with the log interval."""
    var odds_ratio: Estimate
    """The odds ratio, with Woolf's log interval."""
    var number_needed: Float64
    """`1 / |difference|`: the patients to treat for one event more or
    less. Infinite when the risks are equal."""

    def __init__(
        out self, events_a: Int, total_a: Int, events_b: Int, total_b: Int
    ) raises:
        """Compare the risks of two groups.

        Args:
            events_a: The patients with the event in the first group.
            total_a: The patients of the first group.
            events_b: The patients with the event in the second group.
            total_b: The patients of the second group.

        Raises:
            Error: If a group has no patient, or its events are out of
                range.
        """
        self.first = _exact(events_a, total_a)
        self.second = _exact(events_b, total_b)
        var p1 = self.first.value
        var p2 = self.second.value
        var gap = p1 - p2
        var band = wald_interval(
            gap,
            sqrt(
                p1 * (1.0 - p1) / Float64(total_a)
                + p2 * (1.0 - p2) / Float64(total_b)
            ),
        )
        self.difference = Estimate(gap, band[0], band[1])
        self.ratio = _ratio(
            log_risk_ratio(events_a, total_a, events_b, total_b)
        )
        self.odds_ratio = _ratio(
            log_odds_ratio(events_a, total_a, events_b, total_b)
        )
        if gap == 0:
            self.number_needed = inf[DType.float64]()
        else:
            self.number_needed = 1.0 / abs(gap)


def compare_risks(
    events_a: Int, total_a: Int, events_b: Int, total_b: Int
) raises -> RiskComparison:
    """Compare the risks of an event in two groups.

    The risk and odds ratios add a half to each cell when one is 0.

    Args:
        events_a: The patients with the event in the first group.
        total_a: The patients of the first group.
        events_b: The patients with the event in the second group.
        total_b: The patients of the second group.

    Returns:
        The two risks, their difference, ratio and odds ratio with their
        intervals, and the number needed to treat.

    Raises:
        Error: If a group has no patient, or its events are out of range.
    """
    return RiskComparison(events_a, total_a, events_b, total_b)
