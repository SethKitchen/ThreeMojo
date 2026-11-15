# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""ROC curves of diagnostic tests, their AUC, and DeLong's comparison.

A diagnostic test gives each patient a score, such as the level of a
marker in the blood or the output of a model. A threshold calls a patient
diseased when the score is the threshold or more. The ROC curve gives the
sensitivity against the false positive rate at each threshold.

- `roc_curve(scores, diseased)` gives the curve, its area (AUC) and the
  standard error of the AUC by the method of DeLong and others. The AUC is
  the chance that a diseased patient has a higher score than a healthy
  one, with a tie counted as a half.
- `RocCurve.youden()` gives the threshold of the largest Youden index,
  sensitivity + specificity - 1.
- `compare_roc` compares the AUC of two tests on the same patients. It
  takes the correlation of the two tests into account.
- `roc_image` plots curves.

A higher score must mean disease. For a marker that is low in disease,
give its negative.

The DeLong components come from midranks, after Sun and Xu (2014), so a
curve takes time in proportion to `n log n`.
"""

from extensions.clinical.hypothesis import midranks
from extensions.clinical.survival import Z95
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from math.sort_utils import stable_sort
from render.framebuffer import Color, Framebuffer
from std.math import erfc, floor, inf, isfinite, sqrt


struct _Components(Movable):
    """The DeLong components of one test: for each diseased patient, the
    fraction of healthy patients below; for each healthy patient, the
    fraction of diseased patients above. A tie counts a half."""

    var auc: Float64
    var diseased: List[Float64]
    var healthy: List[Float64]

    def __init__(out self):
        self.auc = 0.0
        self.diseased = List[Float64]()
        self.healthy = List[Float64]()


def _require_scores(scores: List[Float64], diseased: List[Bool]) raises:
    """Refuse scores that are not one finite value for each patient, or
    fewer than two patients of each kind."""
    if len(scores) == 0 or len(scores) != len(diseased):
        raise Error("A ROC curve needs one score for each patient")
    var sick = 0
    for i in range(len(scores)):  # pragma: no branch
        if not isfinite(scores[i]):
            raise Error("The scores of a ROC curve must be finite")
        if diseased[i]:
            sick += 1
    if sick < 2 or len(scores) - sick < 2:
        raise Error(
            "A ROC curve needs two diseased and two healthy patients or more"
        )


def _components(scores: List[Float64], diseased: List[Bool]) -> _Components:
    """Return the AUC and the DeLong components of one test."""
    var all = midranks(scores)
    var sick = List[Float64]()
    var well = List[Float64]()
    for i in range(len(scores)):  # pragma: no branch
        if diseased[i]:
            sick.append(scores[i])
        else:
            well.append(scores[i])
    var m = Float64(len(sick))
    var n = Float64(len(well))
    var among_sick = midranks(sick)
    var among_well = midranks(well)
    var out = _Components()
    var below = 0.0
    var a = 0
    var b = 0
    for i in range(len(scores)):  # pragma: no branch
        if diseased[i]:
            # The healthy patients below, with a tie a half.
            var count = all[i] - among_sick[a]
            below += count
            out.diseased.append(count / n)
            a += 1
        else:
            out.healthy.append(1.0 - (all[i] - among_well[b]) / m)
            b += 1
    out.auc = below / (m * n)
    return out^


def _covariance(first: _Components, second: _Components) -> Float64:
    """Return the DeLong covariance of the AUC of two tests."""
    var m = len(first.diseased)
    var n = len(first.healthy)
    var s10 = 0.0
    for i in range(m):  # pragma: no branch
        s10 += (first.diseased[i] - first.auc) * (
            second.diseased[i] - second.auc
        )
    var s01 = 0.0
    for j in range(n):  # pragma: no branch
        s01 += (first.healthy[j] - first.auc) * (second.healthy[j] - second.auc)
    return s10 / Float64(m * (m - 1)) + s01 / Float64(n * (n - 1))


struct RocCurve(Copyable, Movable):
    """The ROC curve of one test."""

    var thresholds: List[Float64]
    """The thresholds, falling: infinity, then each score once."""
    var false_positive_rate: List[Float64]
    """The fraction of healthy patients called diseased at each
    threshold."""
    var sensitivity: List[Float64]
    """The fraction of diseased patients called diseased at each
    threshold."""
    var auc: Float64
    """The area under the curve."""
    var standard_error: Float64
    """The DeLong standard error of the AUC."""
    var diseased: Int
    """The diseased patients."""
    var healthy: Int
    """The healthy patients."""

    def __init__(out self):
        """Create an empty curve."""
        self.thresholds = List[Float64]()
        self.false_positive_rate = List[Float64]()
        self.sensitivity = List[Float64]()
        self.auc = 0.0
        self.standard_error = 0.0
        self.diseased = 0
        self.healthy = 0

    def interval(self) -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of the AUC.

        Returns:
            The low and the high end, `AUC -+ 1.96 se`, held between 0 and
            1.
        """
        var half = Z95 * self.standard_error
        return (max(0.0, self.auc - half), min(1.0, self.auc + half))

    def youden(self) raises -> Tuple[Float64, Float64, Float64]:
        """Return the threshold of the largest Youden index.

        Returns:
            The threshold, its sensitivity and its specificity. Of equal
            indices, the highest threshold.

        Raises:
            Error: If the curve has no point.
        """
        if len(self.thresholds) == 0:
            raise Error("A ROC curve with no point has no Youden index")
        var best = 0
        for i in range(1, len(self.thresholds)):  # pragma: no branch
            if (
                self.sensitivity[i] - self.false_positive_rate[i]
                > self.sensitivity[best] - self.false_positive_rate[best]
            ):
                best = i
        return (
            self.thresholds[best],
            self.sensitivity[best],
            1.0 - self.false_positive_rate[best],
        )


def roc_curve(scores: List[Float64], diseased: List[Bool]) raises -> RocCurve:
    """Return the ROC curve of a test.

    Args:
        scores: The score of each patient. A higher score means disease.
        diseased: Whether each patient is diseased.

    Returns:
        The curve, its AUC and the DeLong standard error of the AUC.

    Raises:
        Error: If the scores are not one finite value for each patient, or
            there are fewer than two diseased or two healthy patients.
    """
    _require_scores(scores, diseased)
    var parts = _components(scores, diseased)
    var out = RocCurve()
    out.diseased = len(parts.diseased)
    out.healthy = len(parts.healthy)
    out.auc = parts.auc
    out.standard_error = sqrt(_covariance(parts, parts))
    var order = List[Int]()
    for i in range(len(scores)):  # pragma: no branch
        order.append(i)

    def higher(a: Int, b: Int) capturing -> Bool:
        return scores[a] > scores[b]

    stable_sort[higher](order)
    out.thresholds.append(inf[DType.float64]())
    out.false_positive_rate.append(0.0)
    out.sensitivity.append(0.0)
    var true_positive = 0
    var false_positive = 0
    var at = 0
    while at < len(order):
        var t = scores[order[at]]
        while at < len(order) and scores[order[at]] == t:
            if diseased[order[at]]:
                true_positive += 1
            else:
                false_positive += 1
            at += 1
        out.thresholds.append(t)
        out.false_positive_rate.append(
            Float64(false_positive) / Float64(out.healthy)
        )
        out.sensitivity.append(Float64(true_positive) / Float64(out.diseased))
    return out^


struct RocComparison(Copyable, Movable):
    """DeLong's test of the AUC of two tests on the same patients."""

    var difference: Float64
    """The AUC of the second test less the AUC of the first."""
    var standard_error: Float64
    """The standard error of the difference."""
    var z: Float64
    """The difference over its standard error."""
    var p_value: Float64
    """The two-sided chance of a z this far from 0 when the two tests
    have one AUC."""

    def __init__(out self, difference: Float64, variance: Float64):
        """Create a result.

        Args:
            difference: The difference of the AUC.
            variance: Its variance. Positive, or 0 with a difference of 0.
        """
        self.difference = difference
        self.standard_error = sqrt(variance)
        if variance > 0:
            self.z = difference / self.standard_error
        else:
            self.z = 0.0
        self.p_value = erfc(abs(self.z) / sqrt(2.0))


def compare_roc(
    first: List[Float64], second: List[Float64], diseased: List[Bool]
) raises -> RocComparison:
    """Compare the AUC of two tests on the same patients by DeLong's test.

    Args:
        first: The score of each patient by the first test.
        second: The score of each patient by the second test.
        diseased: Whether each patient is diseased.

    Returns:
        The difference of the AUC, second less first, and its test.

    Raises:
        Error: If either test is not valid, or the difference is not 0 and
            has no variance.
    """
    _require_scores(first, diseased)
    _require_scores(second, diseased)
    var a = _components(first, diseased)
    var b = _components(second, diseased)
    var variance = (
        _covariance(a, a) + _covariance(b, b) - 2.0 * _covariance(a, b)
    )
    var difference = b.auc - a.auc
    if not (variance > 0) and difference != 0:
        raise Error("The difference of the two AUCs has no variance")
    return RocComparison(difference, max(variance, 0.0))


def roc_image(
    curves: List[RocCurve], colors: List[Rgba], size: Int
) raises -> Framebuffer:
    """Plot ROC curves on a square.

    The false positive rate runs from 0 at the left edge to 1 at the right
    edge. The sensitivity runs from 0 at the bottom edge to 1 at the top
    edge. Light gray lines mark each tenth, and a darker gray diagonal
    marks a test no better than chance.

    Args:
        curves: The curves, one or more.
        colors: The color of each curve.
        size: The side of the image, from 64 to 4096 pixels.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If there is no curve, the colors are not one for each
            curve, or the size is out of range.
    """
    if len(curves) == 0 or len(colors) != len(curves):
        raise Error("A ROC plot needs one color for each of its curves")
    if size < 64 or size > 4096:
        raise Error("A ROC plot is from 64 to 4096 pixels on a side")
    var image = Framebuffer(size, size, Color(255, 255, 255))
    var light = Rgba(0.84, 0.84, 0.86, 1)
    var last = Float64(size - 1)
    for n in range(1, 10):  # pragma: no branch
        var p = Int(floor(Float64(n) / 10.0 * last + 0.5))
        draw_line(image, p, 0, p, size - 1, light)
        draw_line(image, 0, p, size - 1, p, light)
    draw_line(image, 0, size - 1, size - 1, 0, Rgba(0.6, 0.6, 0.63, 1))
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    draw_line(image, 0, 0, size - 1, 0, dark)
    draw_line(image, 0, size - 1, size - 1, size - 1, dark)
    draw_line(image, 0, 0, 0, size - 1, dark)
    draw_line(image, size - 1, 0, size - 1, size - 1, dark)
    for c in range(len(curves)):  # pragma: no branch
        ref curve = curves[c]
        for i in range(1, len(curve.thresholds)):  # pragma: no branch
            draw_line(
                image,
                Int(floor(curve.false_positive_rate[i - 1] * last + 0.5)),
                Int(floor((1.0 - curve.sensitivity[i - 1]) * last + 0.5)),
                Int(floor(curve.false_positive_rate[i] * last + 0.5)),
                Int(floor((1.0 - curve.sensitivity[i]) * last + 0.5)),
                colors[c],
            )
    return image^
