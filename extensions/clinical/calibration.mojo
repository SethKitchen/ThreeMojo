# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The calibration and the clinical use of a risk model.

A risk model gives each patient a risk of an outcome. Its discrimination,
the AUC of `roc`, says whether the patients with the outcome get higher
risks. Its calibration says whether the risks are right: of the patients
with a risk of 20 percent, about 20 percent must have the outcome. A
decision curve says whether the model does more good than harm when a
risk above a threshold leads to a treatment.

- `brier_score` and `scaled_brier_score` measure the mean squared error of
  the risks.
- `risk_groups` sorts the patients by risk into groups of near-equal size,
  and `hosmer_lemeshow` tests the events of the groups against their
  expected events.
- `calibration_fit` gives the calibration slope and intercept, from a
  logistic model of the outcome on the logit of the risk, and the
  calibration in the large. `recalibrate` applies the slope and intercept.
- `net_benefit` and `decision_curve` give the net benefit of Vickers and
  Elkin (2006), as dcurves gives it.
- `calibration_image` and `decision_curve_image` draw them.

Each risk must be between 0 and 1, and not at either end.
"""

from extensions.clinical.logistic import logistic_regression
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import floor, isfinite, sqrt
from extensions.numerics.distributions import chi_square_p_value
from extensions.numerics.elementary import logistic, logit
from extensions.numerics.order import ascending_order
from extensions.numerics.search import bisect

# The most groups of risk, and the most thresholds of a decision curve.
comptime MAX_GROUPS = 100
comptime MAX_THRESHOLDS = 1000
# The steps of the bisection of the calibration in the large.
comptime _BISECTIONS = 200


def _require_risks(risks: List[Float64], outcomes: List[Bool]) raises -> Int:
    """Refuse risks that are not one for each outcome, or not strictly
    between 0 and 1. Return the count of events."""
    var n = len(risks)
    if n == 0 or len(outcomes) != n:
        raise Error("A risk model needs one risk for each outcome")
    var events = 0
    for i in range(n):  # pragma: no branch
        if not (risks[i] > 0 and risks[i] < 1):
            raise Error("A risk must be between 0 and 1, not at either end")
        if outcomes[i]:
            events += 1
    return events


def _require_both(events: Int, count: Int) raises:
    """Refuse outcomes that are all the same."""
    if events == 0 or events == count:
        raise Error("A risk model needs patients with and without the outcome")


def brier_score(risks: List[Float64], outcomes: List[Bool]) raises -> Float64:
    """Return the Brier score: the mean squared error of the risks.

    Args:
        risks: The risk of each patient.
        outcomes: Whether each patient has the outcome.

    Returns:
        The mean of `(risk - outcome)^2`, with an outcome of 1 or 0. 0 is
        perfect.

    Raises:
        Error: If there is not one risk for each outcome, or a risk is not
            between 0 and 1.
    """
    _ = _require_risks(risks, outcomes)
    var total = 0.0
    for i in range(len(risks)):  # pragma: no branch
        var gap = risks[i] - (1.0 if outcomes[i] else 0.0)
        total += gap * gap
    return total / Float64(len(risks))


def scaled_brier_score(
    risks: List[Float64], outcomes: List[Bool]
) raises -> Float64:
    """Return the Brier score scaled by that of a model without information.

    Args:
        risks: The risk of each patient.
        outcomes: Whether each patient has the outcome.

    Returns:
        `1 - B / (s (1 - s))`, with `s` the share of patients with the
        outcome. 1 is perfect, and 0 is no better than giving each patient
        the share.

    Raises:
        Error: If the risks are not valid, as for `brier_score`, or the
            outcomes are all the same.
    """
    var events = _require_risks(risks, outcomes)
    _require_both(events, len(risks))
    var share = Float64(events) / Float64(len(risks))
    return 1.0 - brier_score(risks, outcomes) / (share * (1.0 - share))


struct RiskGroup(Copyable, Movable):
    """The patients of one group of risk."""

    var count: Int
    """The patients of the group."""
    var expected: Float64
    """The sum of their risks: the events that the model expects."""
    var events: Int
    """The patients with the outcome."""

    def __init__(out self, count: Int, expected: Float64, events: Int):
        """Create a group.

        Args:
            count: The patients.
            expected: The sum of their risks.
            events: The patients with the outcome.
        """
        self.count = count
        self.expected = expected
        self.events = events

    def mean_risk(self) -> Float64:
        """Return the mean risk of the group.

        Returns:
            The expected events over the patients.
        """
        return self.expected / Float64(self.count)

    def observed(self) -> Float64:
        """Return the share of the group with the outcome.

        Returns:
            The events over the patients.
        """
        return Float64(self.events) / Float64(self.count)


def risk_groups(
    risks: List[Float64], outcomes: List[Bool], groups: Int
) raises -> List[RiskGroup]:
    """Sort the patients by risk into groups of near-equal size.

    The first `n mod groups` groups hold one patient more, as
    `numpy.array_split` gives them. Patients of equal risk keep their order,
    and they can fall in two groups.

    Args:
        risks: The risk of each patient.
        outcomes: Whether each patient has the outcome.
        groups: The number of groups, from 2 to 100 and no more than the
            patients.

    Returns:
        The groups, from the lowest risk to the highest.

    Raises:
        Error: If the risks are not valid, as for `brier_score`, or the
            number of groups is out of range.
    """
    _ = _require_risks(risks, outcomes)
    var n = len(risks)
    if groups < 2 or groups > MAX_GROUPS or groups > n:
        raise Error(
            "Risk groups number from 2 to 100, and no more than the patients"
        )
    var order = ascending_order(risks)
    var out = List[RiskGroup]()
    var at = 0
    for g in range(groups):  # pragma: no branch
        var count = n // groups + (1 if g < n % groups else 0)
        var expected = 0.0
        var events = 0
        for i in range(at, at + count):  # pragma: no branch
            expected += risks[order[i]]
            if outcomes[order[i]]:
                events += 1
        out.append(RiskGroup(count, expected, events))
        at += count
    return out^


struct HosmerLemeshow(Copyable, Movable):
    """The Hosmer-Lemeshow test of the calibration of a risk model."""

    var statistic: Float64
    """The chi-square statistic."""
    var freedom: Int
    """The degrees of freedom, two less than the groups."""
    var p_value: Float64
    """The chance of a statistic this large when the risks are right."""

    def __init__(out self, statistic: Float64, freedom: Int) raises:
        """Create a result, with its p value.

        Args:
            statistic: The statistic.
            freedom: The degrees of freedom.

        Raises:
            Error: If the degrees of freedom are below 1.
        """
        self.statistic = statistic
        self.freedom = freedom
        self.p_value = chi_square_p_value(statistic, freedom)


def hosmer_lemeshow(
    risks: List[Float64], outcomes: List[Bool], groups: Int
) raises -> HosmerLemeshow:
    """Test the calibration of a risk model by the groups of its risks.

    Args:
        risks: The risk of each patient.
        outcomes: Whether each patient has the outcome.
        groups: The number of groups, from 3 to 100 and no more than the
            patients. 10 is usual.

    Returns:
        The sum over the groups of `(O - E)^2 / (E (1 - E / n))`, with `g - 2`
        degrees of freedom, and its p value.

    Raises:
        Error: If the risks are not valid, as for `brier_score`, or the
            number of groups is out of range.
    """
    if groups < 3:
        raise Error("A Hosmer-Lemeshow test needs 3 groups or more")
    var statistic = 0.0
    for group in risk_groups(risks, outcomes, groups):  # pragma: no branch
        var gap = Float64(group.events) - group.expected
        statistic += (
            gap
            * gap
            / (group.expected * (1.0 - group.expected / Float64(group.count)))
        )
    return HosmerLemeshow(statistic, groups - 2)


struct CalibrationFit(Copyable, Movable):
    """The calibration slope and intercept of a risk model."""

    var intercept: Float64
    """The intercept of the logistic model of the outcome on the logit of the
    risk."""
    var slope: Float64
    """The slope of that model: 1 for right risks, below 1 for risks too far
    from the mean, as an overfitted model gives."""
    var intercept_error: Float64
    """The standard error of the intercept."""
    var slope_error: Float64
    """The standard error of the slope."""
    var in_the_large: Float64
    """The intercept with the logit of the risk as an offset: 0 for right
    risks on the whole, below 0 for risks too high."""
    var in_the_large_error: Float64
    """The standard error of the calibration in the large."""
    var expected_over_observed: Float64
    """The sum of the risks over the events."""
    var converged: Bool
    """Whether the logistic fit of the slope converged in 100 Newton
    steps."""

    def __init__(out self):
        """Create an empty fit."""
        self.intercept = 0.0
        self.slope = 0.0
        self.intercept_error = 0.0
        self.slope_error = 0.0
        self.in_the_large = 0.0
        self.in_the_large_error = 0.0
        self.expected_over_observed = 0.0
        self.converged = False


def calibration_fit(
    risks: List[Float64], outcomes: List[Bool]
) raises -> CalibrationFit:
    """Fit the calibration slope and intercept of a risk model.

    Args:
        risks: The risk of each patient.
        outcomes: Whether each patient has the outcome.

    Returns:
        The intercept and slope of the logistic model of the outcome on the
        logit of the risk, the calibration in the large, and the expected
        over the observed events.

    Raises:
        Error: If the risks are not valid, as for `brier_score`, the
            outcomes are all the same, or the logistic fit refuses the
            logits: they are all equal or they separate the outcomes.
    """
    var events = _require_risks(risks, outcomes)
    var n = len(risks)
    _require_both(events, n)
    var logits = List[Float64]()
    var rows = List[List[Float64]]()
    var expected = 0.0
    for p in risks:  # pragma: no branch
        logits.append(logit(p))
        rows.append([logit(p)])
        expected += p
    var model = logistic_regression(outcomes, rows, 1e-10, 100)
    var out = CalibrationFit()
    out.intercept = model.coefficients[0]
    out.slope = model.coefficients[1]
    out.intercept_error = model.standard_errors[0]
    out.slope_error = model.standard_errors[1]
    out.converged = model.converged
    out.expected_over_observed = expected / Float64(events)
    # The calibration in the large solves sum of risk(a + logit) = events.
    # Its left side rises with a, from 0 to n, so bisect between ends where
    # the largest and the least logit alone reach the share of events.
    var low = logits[0]
    var high = logits[0]
    for v in logits:  # pragma: no branch
        low = min(low, v)
        high = max(high, v)
    var share = logit(Float64(events) / Float64(n))

    def under(a: Float64) capturing -> Bool:
        var total = 0.0
        for v in logits:  # pragma: no branch
            total += logistic(a + v)
        return not (total > Float64(events))

    var a = bisect[under](share - high, share - low, _BISECTIONS)
    var information = 0.0
    for v in logits:  # pragma: no branch
        var r = logistic(a + v)
        information += r * (1.0 - r)
    out.in_the_large = a
    out.in_the_large_error = 1.0 / sqrt(information)
    return out^


def recalibrate(
    risks: List[Float64], fit: CalibrationFit
) raises -> List[Float64]:
    """Apply a calibration slope and intercept to risks.

    Logistic recalibration keeps the order of the risks, so it keeps the
    AUC.

    Args:
        risks: The risks of the model.
        fit: The calibration of the model, from `calibration_fit`.

    Returns:
        `1 / (1 + exp(-(a + b logit(risk))))` for each risk.

    Raises:
        Error: If a risk is not between 0 and 1, not at either end, or the
            fit is not finite.
    """
    if not isfinite(fit.intercept) or not isfinite(fit.slope):
        raise Error("A recalibration needs a finite intercept and slope")
    var out = List[Float64]()
    for p in risks:  # pragma: no branch
        if not (p > 0 and p < 1):
            raise Error("A risk must be between 0 and 1, not at either end")
        out.append(logistic(fit.intercept + fit.slope * logit(p)))
    return out^


def _require_threshold(threshold: Float64) raises:
    """Refuse a threshold that is not strictly between 0 and 1."""
    if not (threshold > 0 and threshold < 1):
        raise Error("A threshold of risk must be between 0 and 1")


def _benefit(
    risks: List[Float64], outcomes: List[Bool], threshold: Float64
) -> Float64:
    """Return the net benefit of treating each risk at the threshold or
    above."""
    var true_positive = 0
    var false_positive = 0
    for i in range(len(risks)):  # pragma: no branch
        if risks[i] >= threshold:
            if outcomes[i]:
                true_positive += 1
            else:
                false_positive += 1
    var n = Float64(len(risks))
    return Float64(true_positive) / n - Float64(
        false_positive
    ) / n * threshold / (1.0 - threshold)


def net_benefit(
    risks: List[Float64], outcomes: List[Bool], threshold: Float64
) raises -> Float64:
    """Return the net benefit of a model at a threshold of risk.

    The patients with a risk at the threshold or above are treated. The
    threshold is the risk at which a patient takes the harm of a treatment
    for the chance of its benefit. So a false positive weighs `t / (1 - t)`
    of a true positive.

    Args:
        risks: The risk of each patient.
        outcomes: Whether each patient has the outcome.
        threshold: The threshold, between 0 and 1.

    Returns:
        `TP / n - FP / n * t / (1 - t)`.

    Raises:
        Error: If the risks are not valid, as for `brier_score`, or the
            threshold is not between 0 and 1.
    """
    _ = _require_risks(risks, outcomes)
    _require_threshold(threshold)
    return _benefit(risks, outcomes, threshold)


struct DecisionCurve(Copyable, Movable):
    """The net benefit of a model and of treating all, at each threshold."""

    var thresholds: List[Float64]
    """The thresholds of risk, rising."""
    var model: List[Float64]
    """The net benefit of the model at each threshold."""
    var treat_all: List[Float64]
    """The net benefit of treating every patient at each threshold."""
    var avoided: List[Float64]
    """The net treatments avoided for each patient, against treating all."""
    var prevalence: Float64
    """The share of patients with the outcome: the most net benefit of any
    strategy."""

    def __init__(out self, var thresholds: List[Float64], prevalence: Float64):
        """Create an empty curve.

        Args:
            thresholds: The thresholds.
            prevalence: The share of patients with the outcome.
        """
        self.thresholds = thresholds^
        self.model = List[Float64]()
        self.treat_all = List[Float64]()
        self.avoided = List[Float64]()
        self.prevalence = prevalence


def decision_curve(
    risks: List[Float64], outcomes: List[Bool], thresholds: List[Float64]
) raises -> DecisionCurve:
    """Return the decision curve of a model.

    Args:
        risks: The risk of each patient.
        outcomes: Whether each patient has the outcome.
        thresholds: The thresholds of risk, from 2 to 1000, each between 0
            and 1, rising.

    Returns:
        At each threshold, the net benefit of the model and of treating all,
        and the net treatments avoided, `(NB - NB_all) / (t / (1 - t))`.
        Treating none has a net benefit of 0.

    Raises:
        Error: If the risks are not valid, as for `brier_score`, the
            outcomes have no event, or the thresholds are out of range or do
            not rise.
    """
    var events = _require_risks(risks, outcomes)
    if events == 0:
        raise Error("A decision curve needs one patient with the outcome")
    var k = len(thresholds)
    if k < 2 or k > MAX_THRESHOLDS:
        raise Error("A decision curve has from 2 to 1000 thresholds")
    for i in range(k):  # pragma: no branch
        _require_threshold(thresholds[i])
        if i > 0 and not (thresholds[i] > thresholds[i - 1]):
            raise Error("The thresholds of a decision curve must rise")
    var share = Float64(events) / Float64(len(risks))
    var out = DecisionCurve(thresholds.copy(), share)
    for t in thresholds:  # pragma: no branch
        var odds = t / (1.0 - t)
        var model = _benefit(risks, outcomes, t)
        var everyone = share - (1.0 - share) * odds
        out.model.append(model)
        out.treat_all.append(everyone)
        out.avoided.append((model - everyone) / odds)
    return out^


def _pixel(value: Float64, last: Int) -> Int:
    """Return the pixel of a fraction of the side, held near the image."""
    return Int(floor(max(-1.0, min(2.0, value)) * Float64(last) + 0.5))


def _grid(mut image: Framebuffer, columns: List[Float64]):
    """Draw light lines at each tenth of the height and at fractions of the
    width, then a dark frame."""
    var light = Rgba(0.84, 0.84, 0.86, 1)
    var right = image.width - 1
    var bottom = image.height - 1
    for n in range(1, 10):  # pragma: no branch
        var y = _pixel(Float64(n) / 10.0, bottom)
        draw_line(image, 0, y, right, y, light)
    for c in columns:  # pragma: no branch
        var x = _pixel(c, right)
        draw_line(image, x, 0, x, bottom, light)
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    draw_line(image, 0, 0, right, 0, dark)
    draw_line(image, 0, bottom, right, bottom, dark)
    draw_line(image, 0, 0, 0, bottom, dark)
    draw_line(image, right, 0, right, bottom, dark)


def calibration_image(
    models: List[List[RiskGroup]], colors: List[Rgba], size: Int
) raises -> Framebuffer:
    """Plot the observed share against the mean risk of each group.

    The mean risk runs from 0 at the left edge to 1 at the right edge, and
    the observed share from 0 at the bottom edge to 1 at the top edge. A
    gray diagonal marks right risks. Each group is a cross of 7 pixels, and
    a line joins the groups of a model.

    Args:
        models: The groups of each model, one model or more.
        colors: The color of each model.
        size: The side of the image, from 64 to 4096 pixels.

    Returns:
        A white image with light lines at each tenth and a dark frame.

    Raises:
        Error: If there is no model, a model has no group, the colors are
            not one for each model, or the size is out of range.
    """
    if len(models) == 0 or len(colors) != len(models):
        raise Error("A calibration plot needs one color for each model")
    if size < 64 or size > 4096:
        raise Error("A calibration plot is from 64 to 4096 pixels on a side")
    var image = Framebuffer(size, size, Color(255, 255, 255))
    var tenths = List[Float64]()
    for n in range(1, 10):  # pragma: no branch
        tenths.append(Float64(n) / 10.0)
    _grid(image, tenths)
    var last = size - 1
    draw_line(image, 0, last, last, 0, Rgba(0.6, 0.6, 0.63, 1))
    for m in range(len(models)):  # pragma: no branch
        ref groups = models[m]
        if len(groups) == 0:
            raise Error("A calibration plot needs groups for each model")
        var x0 = 0
        var y0 = 0
        for g in range(len(groups)):  # pragma: no branch
            var x = _pixel(groups[g].mean_risk(), last)
            var y = _pixel(1.0 - groups[g].observed(), last)
            draw_line(image, x - 3, y, x + 3, y, colors[m])
            draw_line(image, x, y - 3, x, y + 3, colors[m])
            if g > 0:
                draw_line(image, x0, y0, x, y, colors[m])
            x0 = x
            y0 = y
    return image^


def decision_curve_image(
    curves: List[DecisionCurve], colors: List[Rgba], width: Int, height: Int
) raises -> Framebuffer:
    """Plot the net benefit of models against the threshold.

    The threshold runs from the first at the left edge to the last at the
    right edge. The net benefit runs from a quarter of the prevalence below
    0 at the bottom edge to the prevalence at the top edge. A gray line at 0
    is treating none, and a dark gray line is treating all, from the first
    curve. Values below the bottom edge are left out.

    Args:
        curves: The curves of the models, on one set of patients and
            thresholds.
        colors: The color of each curve.
        width: The width, from 64 to 4096 pixels.
        height: The height, from 64 to 4096 pixels.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If there is no curve, the colors are not one for each curve,
            a side is out of range, or the curves do not share their
            thresholds and prevalence.
    """
    if len(curves) == 0 or len(colors) != len(curves):
        raise Error("A decision curve plot needs one color for each curve")
    if width < 64 or width > 4096 or height < 64 or height > 4096:
        raise Error("A decision curve plot is from 64 to 4096 pixels a side")
    ref first = curves[0]
    for curve in curves:  # pragma: no branch
        if (
            curve.thresholds != first.thresholds
            or curve.prevalence != first.prevalence
        ):
            raise Error(
                "The curves of a plot must share thresholds and patients"
            )
    var image = Framebuffer(width, height, Color(255, 255, 255))
    var right = width - 1
    var bottom = height - 1
    var start = first.thresholds[0]
    var end = first.thresholds[len(first.thresholds) - 1]
    var span = end - start
    var tenths = List[Float64]()
    for n in range(1, 10):  # pragma: no branch
        var t = Float64(n) / 10.0
        if t > start and t < end:
            tenths.append((t - start) / span)
    _grid(image, tenths)
    var top = first.prevalence
    var depth = 1.25 * top
    var zero = _pixel(top / depth, bottom)
    draw_line(image, 0, zero, right, zero, Rgba(0.6, 0.6, 0.63, 1))
    var lines = List[List[Float64]]()
    lines.append(first.treat_all.copy())
    var shades = List[Rgba]()
    shades.append(Rgba(0.35, 0.35, 0.38, 1))
    for c in range(len(curves)):  # pragma: no branch
        lines.append(curves[c].model.copy())
        shades.append(colors[c])
    for l in range(len(lines)):  # pragma: no branch
        for i in range(1, len(first.thresholds)):  # pragma: no branch
            draw_line(
                image,
                _pixel((first.thresholds[i - 1] - start) / span, right),
                _pixel((top - lines[l][i - 1]) / depth, bottom),
                _pixel((first.thresholds[i] - start) / span, right),
                _pixel((top - lines[l][i]) / depth, bottom),
                shades[l],
            )
    return image^
