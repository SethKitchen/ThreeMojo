# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The calibration and the decision curve of an overfitted risk model, and
of the same model recalibrated.

    mojo run -I . examples/risk_model.mojo [out/risk-model.png]

The page is Diagnostic tests. A synthetic cohort of 2000 patients has a
true risk of `1 / (1 + exp(-(-1.2 + 1.1 x + 0.8 z)))`, with x a normal
marker and z a coin. An overfitted model gives each patient the risk
`1 / (1 + exp(-(-0.9 + 1.5 x + 1.0 z)))`: too high, and too far from the
mean. `calibration_fit` finds its slope and intercept, and `recalibrate`
corrects the risks. The recalibration is fitted on the same patients that
it is drawn for, so it is too good: a study fits it on other patients.

The left panel is the calibration plot of ten groups of risk: the
overfitted model in orange, and the recalibrated model in blue. The gray
diagonal is right risks. The right panel is the decision curve, from a
threshold of 2 to 80 percent. The dark gray line is treating all, and the
gray line at 0 is treating none. The recalibrated model has the same AUC.
Below a threshold of about 20 percent, the two models have about the same
net benefit. Above it, the recalibrated model has more, because the
overfitted model treats too many patients.

This is a synthetic cohort, for teaching. It is not a model of a disease.
"""

from extensions.clinical.calibration import (
    DecisionCurve,
    RiskGroup,
    brier_score,
    calibration_fit,
    calibration_image,
    decision_curve,
    decision_curve_image,
    hosmer_lemeshow,
    net_benefit,
    recalibrate,
    risk_groups,
)
from extensions.clinical.roc import roc_curve
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.math import cos, expm1, log, pi, sqrt
from std.pathlib import Path
from tools._example_output import blit, example_destination

comptime DEFAULT_OUTPUT = "out/risk-model.png"
comptime PATIENTS = 2000
comptime SIDE = 480
comptime ORANGE = Rgba(0.9, 0.45, 0.1, 1)
comptime BLUE = Rgba(0.16, 0.38, 0.73, 1)


struct _Noise(Movable):
    """A seeded source of uniform and normal numbers, by xorshift."""

    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def uniform(mut self) -> Float64:
        self.state ^= self.state << 13
        self.state ^= self.state >> 7
        self.state ^= self.state << 17
        return (Float64(self.state >> 11) + 0.5) / 9007199254740992.0

    def normal(mut self) -> Float64:
        var u = self.uniform()
        var v = self.uniform()
        return sqrt(-2.0 * log(u)) * cos(2.0 * pi * v)


def _risk(eta: Float64) -> Float64:
    """Return `1 / (1 + e^-eta)`."""
    return 1.0 / (2.0 + expm1(-eta))


def _report(name: String, risks: List[Float64], outcomes: List[Bool]) raises:
    """Print the measures of one model."""
    var scores = List[Float64]()
    for p in risks:
        scores.append(p)
    var fit = calibration_fit(risks, outcomes)
    var test = hosmer_lemeshow(risks, outcomes, 10)
    print(
        name,
        ": AUC",
        roc_curve(scores, outcomes).auc,
        "Brier",
        brier_score(risks, outcomes),
        "slope",
        fit.slope,
        "in the large",
        fit.in_the_large,
        "E/O",
        fit.expected_over_observed,
    )
    print(
        "  Hosmer-Lemeshow",
        test.statistic,
        "p",
        test.p_value,
        "; net benefit at 20 percent",
        net_benefit(risks, outcomes, 0.2),
    )


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var noise = _Noise(20261115)
    var risks = List[Float64]()
    var outcomes = List[Bool]()
    for _ in range(PATIENTS):
        var x = noise.normal()
        var z = 1.0 if noise.uniform() < 0.5 else 0.0
        var truth = _risk(-1.2 + 1.1 * x + 0.8 * z)
        outcomes.append(noise.uniform() < truth)
        risks.append(_risk(-0.9 + 1.5 * x + 1.0 * z))
    var fixed = recalibrate(risks, calibration_fit(risks, outcomes))
    var thresholds = List[Float64]()
    for k in range(2, 81):
        thresholds.append(Float64(k) / 100.0)
    var groups: List[List[RiskGroup]] = [
        risk_groups(risks, outcomes, 10),
        risk_groups(fixed, outcomes, 10),
    ]
    var curves: List[DecisionCurve] = [
        decision_curve(risks, outcomes, thresholds),
        decision_curve(fixed, outcomes, thresholds),
    ]
    var sheet = Framebuffer(2 * SIDE + 16, SIDE, Color(255, 255, 255))
    blit(sheet, calibration_image(groups, [ORANGE, BLUE], SIDE), 0, 0)
    blit(
        sheet,
        decision_curve_image(curves, [ORANGE, BLUE], SIDE, SIDE),
        SIDE + 16,
        0,
    )
    Path(destination).write_bytes(encode(sheet))
    _report("Overfitted", risks, outcomes)
    _report("Recalibrated", fixed, outcomes)
    print("Wrote", destination)
