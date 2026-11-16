# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sample size and the power of a study, by the normal approximation.

A study plans for a two-sided test at a level `alpha`, such as 0.05, and
for a power, such as 0.8: the chance that it finds a true effect of the
size that it plans for.

- `proportions_size` and `proportions_power` compare two proportions,
  with the variance of the null under the pooled proportion and the
  variance of the alternative under the two proportions (Fleiss, without
  a continuity correction), as statsmodels does.
- `means_size` and `means_power` compare two means with a known standard
  deviation, as statsmodels' `NormalIndPower` does.
- `schoenfeld_events` gives the events that a log-rank test or a Cox model
  needs, by Schoenfeld's formula.
- `freedman_size` and `freedman_power` give the patients of a survival
  study from the chance of an event in each group, by Freedman's formula,
  as lifelines does.

A size is the exact real number of the formula. Round it up.
"""

from extensions.numerics.distributions import normal_quantile, normal_upper
from std.math import isfinite, log, sqrt


def _require_plan(alpha: Float64, power: Float64) raises:
    """Refuse a level or a power out of range."""
    if not (alpha > 0 and alpha < 1):
        raise Error("The level alpha must be between 0 and 1")
    if not (power > 0 and power < 1):
        raise Error("The power must be between 0 and 1")


def _require_ratio(ratio: Float64) raises:
    """Refuse a ratio of group sizes that is not positive and finite."""
    if not (ratio > 0) or not isfinite(ratio):
        raise Error("The ratio of the group sizes must be positive and finite")


def _require_size(n: Float64) raises:
    """Refuse a group size that is not positive and finite."""
    if not (n > 0) or not isfinite(n):
        raise Error("A group size must be positive and finite")


def _size(
    difference: Float64,
    null: Float64,
    alternative: Float64,
    alpha: Float64,
    power: Float64,
) raises -> Float64:
    """Return `((z_a null + z_b alternative) / difference)^2`."""
    var z_alpha = -normal_quantile(alpha / 2.0)
    var z_beta = -normal_quantile(1.0 - power)
    var top = max(z_alpha * null + z_beta * alternative, 0.0)
    return (top / difference) ** 2


def _power(
    difference: Float64,
    n: Float64,
    null: Float64,
    alternative: Float64,
    alpha: Float64,
) raises -> Float64:
    """Return the two-sided power, with both tails."""
    var z_alpha = -normal_quantile(alpha / 2.0)
    var shift = abs(difference) * sqrt(n) / alternative
    var scaled = z_alpha * null / alternative
    return normal_upper(scaled - shift) + normal_upper(scaled + shift)


def _proportion_spread(
    p1: Float64, p2: Float64, ratio: Float64
) raises -> Tuple[Float64, Float64]:
    """Return the null and the alternative standard deviations of the
    difference of two proportions, for one patient of the first group."""
    if not (p1 > 0 and p1 < 1 and p2 > 0 and p2 < 1) or p1 == p2:
        raise Error("Two proportions must differ, each between 0 and 1")
    _require_ratio(ratio)
    var pooled = (p1 + p2 * ratio) / (1.0 + ratio)
    return (
        sqrt(pooled * (1.0 - pooled) * (1.0 + 1.0 / ratio)),
        sqrt(p1 * (1.0 - p1) + p2 * (1.0 - p2) / ratio),
    )


def proportions_size(
    p1: Float64, p2: Float64, alpha: Float64, power: Float64, ratio: Float64
) raises -> Float64:
    """Return the first group's size to compare two proportions.

    Args:
        p1: The proportion of the first group, between 0 and 1.
        p2: The proportion of the second group, between 0 and 1.
        alpha: The two-sided level, between 0 and 1.
        power: The power, between 0 and 1.
        ratio: The size of the second group over the first.

    Returns:
        The patients of the first group. The second group has `ratio`
        times as many.

    Raises:
        Error: If a proportion, the level, the power or the ratio is out
            of range, or the proportions are equal.
    """
    _require_plan(alpha, power)
    var spread = _proportion_spread(p1, p2, ratio)
    return _size(p1 - p2, spread[0], spread[1], alpha, power)


def proportions_power(
    p1: Float64, p2: Float64, n1: Float64, alpha: Float64, ratio: Float64
) raises -> Float64:
    """Return the power to compare two proportions.

    Args:
        p1: The proportion of the first group, between 0 and 1.
        p2: The proportion of the second group, between 0 and 1.
        n1: The patients of the first group.
        alpha: The two-sided level, between 0 and 1.
        ratio: The size of the second group over the first.

    Returns:
        The chance that the test finds the difference.

    Raises:
        Error: If a proportion, the size, the level or the ratio is out of
            range, or the proportions are equal.
    """
    _require_plan(alpha, 0.5)
    _require_size(n1)
    var spread = _proportion_spread(p1, p2, ratio)
    return _power(p1 - p2, n1, spread[0], spread[1], alpha)


def _require_means(difference: Float64, deviation: Float64) raises:
    """Refuse a difference of 0 or a deviation that is not positive."""
    if not (difference != 0) or not isfinite(difference):
        raise Error("The difference of the means must be finite and not 0")
    if not (deviation > 0) or not isfinite(deviation):
        raise Error("The standard deviation must be positive and finite")


def means_size(
    difference: Float64,
    deviation: Float64,
    alpha: Float64,
    power: Float64,
    ratio: Float64,
) raises -> Float64:
    """Return the first group's size to compare two means.

    Args:
        difference: The difference of the means to find, in a unit that
            the caller chooses.
        deviation: The standard deviation in each group, in that unit.
        alpha: The two-sided level, between 0 and 1.
        power: The power, between 0 and 1.
        ratio: The size of the second group over the first.

    Returns:
        The patients of the first group.

    Raises:
        Error: If the difference, the deviation, the level, the power or
            the ratio is out of range.
    """
    _require_plan(alpha, power)
    _require_means(difference, deviation)
    _require_ratio(ratio)
    var spread = deviation * sqrt(1.0 + 1.0 / ratio)
    return _size(difference, spread, spread, alpha, power)


def means_power(
    difference: Float64,
    deviation: Float64,
    n1: Float64,
    alpha: Float64,
    ratio: Float64,
) raises -> Float64:
    """Return the power to compare two means.

    Args:
        difference: The difference of the means to find.
        deviation: The standard deviation in each group.
        n1: The patients of the first group.
        alpha: The two-sided level, between 0 and 1.
        ratio: The size of the second group over the first.

    Returns:
        The chance that the test finds the difference.

    Raises:
        Error: If the difference, the deviation, the size, the level or the
            ratio is out of range.
    """
    _require_plan(alpha, 0.5)
    _require_means(difference, deviation)
    _require_size(n1)
    _require_ratio(ratio)
    var spread = deviation * sqrt(1.0 + 1.0 / ratio)
    return _power(difference, n1, spread, spread, alpha)


def _require_hazard(hazard_ratio: Float64) raises:
    """Refuse a hazard ratio of 1, or one that is not positive."""
    if (
        not (hazard_ratio > 0)
        or not isfinite(hazard_ratio)
        or hazard_ratio == 1
    ):
        raise Error("The hazard ratio must be positive, finite and not 1")


def schoenfeld_events(
    hazard_ratio: Float64, alpha: Float64, power: Float64, allocation: Float64
) raises -> Float64:
    """Return the events that a log-rank test needs, by Schoenfeld.

    Args:
        hazard_ratio: The hazard ratio to find.
        alpha: The two-sided level, between 0 and 1.
        power: The power, between 0 and 1.
        allocation: The fraction of patients in the first group, between 0
            and 1.

    Returns:
        `(z_a + z_b)^2 / (a (1 - a) ln(HR)^2)`, the events of both groups.

    Raises:
        Error: If the hazard ratio, the level, the power or the allocation
            is out of range.
    """
    _require_plan(alpha, power)
    _require_hazard(hazard_ratio)
    if not (allocation > 0 and allocation < 1):
        raise Error("The allocation must be between 0 and 1")
    var z = -normal_quantile(alpha / 2.0) - normal_quantile(1.0 - power)
    var lhr = log(hazard_ratio)
    return z * z / (allocation * (1.0 - allocation) * lhr * lhr)


def _require_event_chances(first: Float64, second: Float64) raises:
    """Refuse a chance of an event out of (0, 1]."""
    if not (first > 0 and first <= 1 and second > 0 and second <= 1):
        raise Error("The chance of an event in each group must be in (0, 1]")


def freedman_size(
    hazard_ratio: Float64,
    alpha: Float64,
    power: Float64,
    ratio: Float64,
    first_events: Float64,
    second_events: Float64,
) raises -> Tuple[Float64, Float64]:
    """Return the patients of a survival study, by Freedman.

    The events are `(1 / r) ((r HR + 1) / (HR - 1))^2 (z_a + z_b)^2`.
    The patients divide them by the chance of an event in each group.

    Args:
        hazard_ratio: The hazard ratio to find, first group over second.
        alpha: The two-sided level, between 0 and 1.
        power: The power, between 0 and 1.
        ratio: The size of the first group over the second.
        first_events: The chance of an event in the first group, in (0, 1].
        second_events: The chance of an event in the second group.

    Returns:
        The patients of the first group and of the second group.

    Raises:
        Error: If the hazard ratio, the level, the power, the ratio or a
            chance is out of range.
    """
    _require_plan(alpha, power)
    _require_hazard(hazard_ratio)
    _require_ratio(ratio)
    _require_event_chances(first_events, second_events)
    var z = -normal_quantile(alpha / 2.0) - normal_quantile(1.0 - power)
    var lift = (ratio * hazard_ratio + 1.0) / (hazard_ratio - 1.0)
    var events = lift * lift * z * z / ratio
    var share = ratio * first_events + second_events
    return (events * ratio / share, events / share)


def freedman_power(
    hazard_ratio: Float64,
    alpha: Float64,
    first: Float64,
    second: Float64,
    first_events: Float64,
    second_events: Float64,
) raises -> Float64:
    """Return the power of a survival study, by Freedman.

    Args:
        hazard_ratio: The hazard ratio to find, first group over second.
        alpha: The two-sided level, between 0 and 1.
        first: The patients of the first group.
        second: The patients of the second group.
        first_events: The chance of an event in the first group, in (0, 1].
        second_events: The chance of an event in the second group.

    Returns:
        The chance that the test finds the hazard ratio, one-tailed as
        lifelines gives it.

    Raises:
        Error: If the hazard ratio, the level, a size or a chance is out of
            range.
    """
    _require_plan(alpha, 0.5)
    _require_hazard(hazard_ratio)
    _require_size(first)
    _require_size(second)
    _require_event_chances(first_events, second_events)
    var events = first * first_events + second * second_events
    var k = first / second
    var z = (
        sqrt(k * events) * abs(hazard_ratio - 1.0) / (k * hazard_ratio + 1.0)
    )
    # Phi(z - z_a) is the upper tail at z_a - z.
    return normal_upper(-normal_quantile(alpha / 2.0) - z)
