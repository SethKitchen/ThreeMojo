# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Meta-analysis: the pooled effect of several studies of one question.

Each study gives an effect, such as a log risk ratio, and the variance of
that effect. `meta_analysis` pools them in two ways:

- The fixed effect model weighs each study by the inverse of its
  variance. It takes all studies to measure one true effect.
- The random effects model of DerSimonian and Laird lets the true effect
  differ from study to study, with a variance `tau^2`. It adds `tau^2` to
  the variance of each study before it weighs them.

The result also gives Cochran's Q test of heterogeneity, I^2, and the
prediction interval of Higgins and others (2009) for the effect of a new
study. `log_risk_ratio` and `log_odds_ratio` give the effect of a study
from its counts. `forest_image` draws a forest plot.

Small studies with large effects can be published more often than small
studies with none. `egger_test` tests this asymmetry: it regresses each
effect over its standard error on its precision, and tests the intercept.
`funnel_image` draws each effect against its standard error.
"""

from extensions.clinical.cox import chi_square_p_value
from extensions.clinical.distributions import student_t_quantile
from extensions.clinical.regression import linear_regression
from extensions.clinical.survival import Z95
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import erfc, floor, isfinite, log, sqrt

# The most studies of one meta-analysis.
comptime MAX_STUDIES = 160
# The height of one row of a forest plot, in pixels.
comptime FOREST_ROW = 24


struct Pooled(Copyable, Movable):
    """A pooled effect with its 95 percent interval and test."""

    var estimate: Float64
    """The pooled effect."""
    var standard_error: Float64
    """Its standard error."""
    var lower: Float64
    """The low end of the 95 percent interval."""
    var upper: Float64
    """The high end of the 95 percent interval."""
    var z: Float64
    """The estimate over its standard error."""
    var p_value: Float64
    """The two-sided chance of a z this far from 0 when the effect is 0."""

    def __init__(out self, estimate: Float64, standard_error: Float64):
        """Create a pooled effect.

        Args:
            estimate: The pooled effect.
            standard_error: Its standard error. Positive.
        """
        self.estimate = estimate
        self.standard_error = standard_error
        self.lower = estimate - Z95 * standard_error
        self.upper = estimate + Z95 * standard_error
        self.z = estimate / standard_error
        self.p_value = erfc(abs(self.z) / sqrt(2.0))


struct MetaAnalysis(Copyable, Movable):
    """The pooled effect of several studies."""

    var studies: Int
    """The studies."""
    var fixed: Pooled
    """The effect of the fixed effect model."""
    var random: Pooled
    """The effect of the random effects model."""
    var q: Float64
    """Cochran's Q: the weighted squares of the effects about the fixed
    effect."""
    var q_p_value: Float64
    """The chance of a Q this large when the studies share one effect."""
    var i_squared: Float64
    """`(Q - df) / Q`, held at 0 or more: the share of the variation of the
    effects that is between the studies."""
    var tau_squared: Float64
    """The variance of the true effects between the studies, by the method
    of moments of DerSimonian and Laird."""
    var fixed_weights: List[Float64]
    """The relative weight of each study in the fixed effect model."""
    var random_weights: List[Float64]
    """The relative weight of each study in the random effects model."""

    def __init__(
        out self,
        var fixed: Pooled,
        var random: Pooled,
        q: Float64,
        tau_squared: Float64,
        var fixed_weights: List[Float64],
        var random_weights: List[Float64],
    ) raises:
        """Create a result, with the test and the share of heterogeneity.

        Args:
            fixed: The effect of the fixed effect model.
            random: The effect of the random effects model.
            q: Cochran's Q.
            tau_squared: The variance between the studies.
            fixed_weights: The relative weights of the fixed model.
            random_weights: The relative weights of the random model.

        Raises:
            Error: If there are fewer than two studies.
        """
        var freedom = len(fixed_weights) - 1
        self.studies = len(fixed_weights)
        self.fixed = fixed^
        self.random = random^
        self.q = q
        self.q_p_value = chi_square_p_value(q, freedom)
        self.i_squared = 0.0
        if q > Float64(freedom):
            self.i_squared = (q - Float64(freedom)) / q
        self.tau_squared = tau_squared
        self.fixed_weights = fixed_weights^
        self.random_weights = random_weights^

    def prediction_interval(self) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of the effect of a new study.

        Returns:
            The random effect `-+ t sqrt(tau^2 + se^2)`, with `t` from the t
            distribution with `k - 2` degrees of freedom.

        Raises:
            Error: If there are fewer than three studies.
        """
        if self.studies < 3:
            raise Error("A prediction interval needs three studies or more")
        var t = student_t_quantile(0.975, Float64(self.studies - 2))
        var se = self.random.standard_error
        var half = t * sqrt(self.tau_squared + se * se)
        return (self.random.estimate - half, self.random.estimate + half)


def _require_studies(effects: List[Float64], variances: List[Float64]) raises:
    """Refuse studies that are not 2 to MAX_STUDIES finite effects, each
    with a positive finite variance."""
    var k = len(effects)
    if k < 2 or k > MAX_STUDIES or len(variances) != k:
        raise Error(
            "A meta-analysis needs 2 to 160 studies, each with a variance"
        )
    for i in range(k):  # pragma: no branch
        if not isfinite(effects[i]):
            raise Error("The effects of a meta-analysis must be finite")
        if not (variances[i] > 0) or not isfinite(variances[i]):
            raise Error("The variances of a meta-analysis must be positive")


def meta_analysis(
    effects: List[Float64], variances: List[Float64]
) raises -> MetaAnalysis:
    """Pool the effects of several studies.

    Args:
        effects: The effect of each study, such as a log risk ratio.
        variances: The variance of each effect.

    Returns:
        The fixed and random effects, the test of heterogeneity, I^2,
        tau^2 and the weights.

    Raises:
        Error: If there are not 2 to 160 studies, an effect is not finite,
            or a variance is not positive and finite.
    """
    _require_studies(effects, variances)
    var k = len(effects)
    var total = 0.0
    var squares = 0.0
    var weighted = 0.0
    for i in range(k):  # pragma: no branch
        var w = 1.0 / variances[i]
        total += w
        squares += w * w
        weighted += w * effects[i]
    var fixed = weighted / total
    var q = 0.0
    for i in range(k):  # pragma: no branch
        var gap = effects[i] - fixed
        q += gap * gap / variances[i]
    var tau2 = max(0.0, (q - Float64(k - 1)) / (total - squares / total))
    var random_total = 0.0
    var random_weighted = 0.0
    for i in range(k):  # pragma: no branch
        var w = 1.0 / (variances[i] + tau2)
        random_total += w
        random_weighted += w * effects[i]
    var fixed_weights = List[Float64]()
    var random_weights = List[Float64]()
    for i in range(k):  # pragma: no branch
        fixed_weights.append(1.0 / variances[i] / total)
        random_weights.append(1.0 / (variances[i] + tau2) / random_total)
    return MetaAnalysis(
        Pooled(fixed, 1.0 / sqrt(total)),
        Pooled(random_weighted / random_total, 1.0 / sqrt(random_total)),
        q,
        tau2,
        fixed_weights^,
        random_weights^,
    )


def _cells(
    events_a: Int, total_a: Int, events_b: Int, total_b: Int
) raises -> Tuple[Float64, Float64, Float64, Float64]:
    """Return the four cells of a two-by-two table. Add a half to each
    when one is 0."""
    if (
        total_a < 1
        or total_b < 1
        or events_a < 0
        or events_b < 0
        or events_a > total_a
        or events_b > total_b
    ):
        raise Error("A study needs events from 0 to its count of patients")
    var a = Float64(events_a)
    var b = Float64(total_a - events_a)
    var c = Float64(events_b)
    var d = Float64(total_b - events_b)
    if a == 0 or b == 0 or c == 0 or d == 0:
        return (a + 0.5, b + 0.5, c + 0.5, d + 0.5)
    return (a, b, c, d)


def log_risk_ratio(
    events_a: Int, total_a: Int, events_b: Int, total_b: Int
) raises -> Tuple[Float64, Float64]:
    """Return the log risk ratio of a study and its variance.

    Args:
        events_a: The patients with the event in the first group.
        total_a: The patients of the first group.
        events_b: The patients with the event in the second group.
        total_b: The patients of the second group.

    Returns:
        `ln((a / n1) / (c / n2))` and `1/a - 1/n1 + 1/c - 1/n2`. When a
        cell of the table is 0, each cell takes a half more.

    Raises:
        Error: If a group has no patient, or its events are out of range.
    """
    var t = _cells(events_a, total_a, events_b, total_b)
    var n1 = t[0] + t[1]
    var n2 = t[2] + t[3]
    return (
        log((t[0] / n1) / (t[2] / n2)),
        1.0 / t[0] - 1.0 / n1 + 1.0 / t[2] - 1.0 / n2,
    )


def log_odds_ratio(
    events_a: Int, total_a: Int, events_b: Int, total_b: Int
) raises -> Tuple[Float64, Float64]:
    """Return the log odds ratio of a study and its variance.

    Args:
        events_a: The patients with the event in the first group.
        total_a: The patients of the first group.
        events_b: The patients with the event in the second group.
        total_b: The patients of the second group.

    Returns:
        `ln(a d / (b c))` and Woolf's `1/a + 1/b + 1/c + 1/d`. When a cell
        of the table is 0, each cell takes a half more.

    Raises:
        Error: If a group has no patient, or its events are out of range.
    """
    var t = _cells(events_a, total_a, events_b, total_b)
    return (
        log((t[0] * t[3]) / (t[1] * t[2])),
        1.0 / t[0] + 1.0 / t[1] + 1.0 / t[2] + 1.0 / t[3],
    )


def _column(value: Float64, low: Float64, high: Float64, right: Float64) -> Int:
    """Return the image column of an effect."""
    return Int(floor((value - low) / (high - low) * right + 0.5))


def _diamond(
    mut image: Framebuffer,
    pooled: Pooled,
    center: Int,
    low: Float64,
    high: Float64,
    right: Float64,
    color: Rgba,
):
    """Draw a pooled effect as a diamond over its interval."""
    var left = _column(pooled.lower, low, high, right)
    var middle = _column(pooled.estimate, low, high, right)
    var end = _column(pooled.upper, low, high, right)
    for dy in range(-6, 7):  # pragma: no branch
        var share = 1.0 - Float64(abs(dy)) / 7.0
        draw_line(
            image,
            middle - Int(Float64(middle - left) * share),
            center + dy,
            middle + Int(Float64(end - middle) * share),
            center + dy,
            color,
        )


def forest_image(
    effects: List[Float64],
    variances: List[Float64],
    result: MetaAnalysis,
    width: Int,
) raises -> Framebuffer:
    """Draw a forest plot.

    Each study has a row, from the top: a line over its 95 percent interval
    and a square at its effect, with an area in proportion to its random
    effects weight. Below them, a gray diamond spans the fixed effect's
    interval, and a blue diamond the random effect's. A gray line marks an
    effect of 0. The effect runs from the least end of an interval to the
    most, with a margin of a twentieth of the range, from left to right.

    Args:
        effects: The effect of each study.
        variances: The variance of each effect.
        result: Their meta-analysis, from `meta_analysis`.
        width: The width of the image, from 128 to 4096 pixels. The height
            is 24 pixels for each study, and three rows more.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If the studies are not valid, the result is not theirs, or
            the width is out of range.
    """
    _require_studies(effects, variances)
    var k = len(effects)
    if result.studies != k:
        raise Error("A forest plot needs the meta-analysis of its own studies")
    if width < 128 or width > 4096:
        raise Error("A forest plot is from 128 to 4096 pixels wide")
    var low = min(0.0, min(result.fixed.lower, result.random.lower))
    var high = max(0.0, max(result.fixed.upper, result.random.upper))
    var heaviest = 0.0
    for i in range(k):  # pragma: no branch
        var half = Z95 * sqrt(variances[i])
        low = min(low, effects[i] - half)
        high = max(high, effects[i] + half)
        heaviest = max(heaviest, result.random_weights[i])
    var margin = 0.05 * (high - low)
    low -= margin
    high += margin
    var height = FOREST_ROW * (k + 3)
    var image = Framebuffer(width, height, Color(255, 255, 255))
    var right = Float64(width - 1)
    var gray = Rgba(0.6, 0.6, 0.63, 1)
    var zero = _column(0.0, low, high, right)
    draw_line(image, zero, 0, zero, height - 1, gray)
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    for i in range(k):  # pragma: no branch
        var y = FOREST_ROW * (i + 1)
        var half = Z95 * sqrt(variances[i])
        draw_line(
            image,
            _column(effects[i] - half, low, high, right),
            y,
            _column(effects[i] + half, low, high, right),
            y,
            dark,
        )
        var x = _column(effects[i], low, high, right)
        var side = 1 + Int(7.0 * sqrt(result.random_weights[i] / heaviest))
        for dy in range(-side, side + 1):  # pragma: no branch
            draw_line(image, x - side, y + dy, x + side, y + dy, dark)
    _diamond(image, result.fixed, FOREST_ROW * (k + 1), low, high, right, gray)
    _diamond(
        image,
        result.random,
        FOREST_ROW * (k + 2),
        low,
        high,
        right,
        Rgba(0.15, 0.4, 0.85, 1),
    )
    draw_line(image, 0, 0, width - 1, 0, dark)
    draw_line(image, 0, height - 1, width - 1, height - 1, dark)
    draw_line(image, 0, 0, 0, height - 1, dark)
    draw_line(image, width - 1, 0, width - 1, height - 1, dark)
    return image^


struct EggerTest(Copyable, Movable):
    """Egger's regression test of the asymmetry of a funnel plot."""

    var intercept: Float64
    """The intercept of the regression of `y / se` on `1 / se`. 0 for a
    symmetric funnel."""
    var standard_error: Float64
    """The standard error of the intercept."""
    var t: Float64
    """The intercept over its standard error."""
    var p_value: Float64
    """The two-sided p value, on `k - 2` degrees of freedom."""
    var slope: Float64
    """The slope: an estimate of the effect that is free of the
    asymmetry."""

    def __init__(
        out self,
        intercept: Float64,
        standard_error: Float64,
        t: Float64,
        p_value: Float64,
        slope: Float64,
    ):
        """Create a result.

        Args:
            intercept: The intercept.
            standard_error: Its standard error.
            t: Its t value.
            p_value: Its two-sided p value.
            slope: The slope.
        """
        self.intercept = intercept
        self.standard_error = standard_error
        self.t = t
        self.p_value = p_value
        self.slope = slope


def egger_test(
    effects: List[Float64], variances: List[Float64]
) raises -> EggerTest:
    """Test the asymmetry of the studies by Egger's regression.

    Args:
        effects: The effect of each study.
        variances: The variance of each effect. Three studies or more.

    Returns:
        The intercept of the least squares line of `y / se` on `1 / se`,
        with its test.

    Raises:
        Error: If the studies are not valid, there are fewer than three, or
            their precisions do not vary.
    """
    _require_studies(effects, variances)
    if len(effects) < 3:
        raise Error("Egger's test needs three studies or more")
    var standardized = List[Float64]()
    var precision = List[List[Float64]]()
    for i in range(len(effects)):  # pragma: no branch
        var se = sqrt(variances[i])
        standardized.append(effects[i] / se)
        precision.append([1.0 / se])
    var fit = linear_regression(standardized, precision)
    return EggerTest(
        fit.coefficients[0],
        fit.standard_errors[0],
        fit.t(0),
        fit.p_value(0),
        fit.coefficients[1],
    )


def funnel_image(
    effects: List[Float64],
    variances: List[Float64],
    result: MetaAnalysis,
    width: Int,
    height: Int,
) raises -> Framebuffer:
    """Draw a funnel plot: each effect against its standard error.

    The effect runs across, from the least to the most of the funnel's
    edges and the effects, with a margin of a twentieth of the range. The
    standard error runs from 0 at the top edge to 1.05 times the largest
    standard error at the bottom edge. A blue line marks the fixed effect, and gray
    lines its 95 percent funnel, `estimate -+ 1.96 se`. A cross marks each
    study. Without bias, the crosses fall evenly about the blue line.

    Args:
        effects: The effect of each study.
        variances: The variance of each effect.
        result: Their meta-analysis, from `meta_analysis`.
        width: The width of the image, from 64 to 4096 pixels.
        height: The height of the image, from 64 to 4096 pixels.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If the studies are not valid, the result is not theirs, or a
            size is out of range.
    """
    _require_studies(effects, variances)
    var k = len(effects)
    if result.studies != k:
        raise Error("A funnel plot needs the meta-analysis of its own studies")
    if width < 64 or width > 4096 or height < 64 or height > 4096:
        raise Error("A funnel plot is from 64 to 4096 pixels a side")
    var center = result.fixed.estimate
    var deepest = 0.0
    for v in variances:  # pragma: no branch
        deepest = max(deepest, sqrt(v))
    deepest *= 1.05
    var low = center - Z95 * deepest
    var high = center + Z95 * deepest
    for e in effects:  # pragma: no branch
        low = min(low, e)
        high = max(high, e)
    var margin = 0.05 * (high - low)
    low -= margin
    high += margin
    var image = Framebuffer(width, height, Color(255, 255, 255))
    var right = Float64(width - 1)
    var bottom = Float64(height - 1)
    var gray = Rgba(0.6, 0.6, 0.63, 1)
    var apex = _column(center, low, high, right)
    draw_line(
        image,
        apex,
        0,
        _column(center - Z95 * deepest, low, high, right),
        height - 1,
        gray,
    )
    draw_line(
        image,
        apex,
        0,
        _column(center + Z95 * deepest, low, high, right),
        height - 1,
        gray,
    )
    draw_line(image, apex, 0, apex, height - 1, Rgba(0.15, 0.4, 0.85, 1))
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    for i in range(k):  # pragma: no branch
        var x = _column(effects[i], low, high, right)
        var y = Int(floor(sqrt(variances[i]) / deepest * bottom + 0.5))
        draw_line(image, x - 3, y, x + 3, y, dark)
        draw_line(image, x, y - 3, x, y + 3, dark)
    draw_line(image, 0, 0, width - 1, 0, dark)
    draw_line(image, 0, height - 1, width - 1, height - 1, dark)
    draw_line(image, 0, 0, 0, height - 1, dark)
    draw_line(image, width - 1, 0, width - 1, height - 1, dark)
    return image^
