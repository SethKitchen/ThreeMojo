# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Weibull models of a classic trial, drawn over its Kaplan-Meier curves
and carried past its follow-up.

    mojo run -I . examples/parametric.mojo [out/parametric.png]

The page is Survival analysis. The data are the remission times, in
weeks, of the trial of 6-mercaptopurine (6-MP) against a placebo of
Freireich and others (1963), as in `examples/survival.mojo`.

The solid steps are the Kaplan-Meier curves: blue for 6-MP and red for
the placebo. The dashed lines are the Weibull fits of each group, from 0
to 52 weeks, with a gray line each 4 weeks. The trial follows no patient
past 35 weeks, so the dashed lines past that hold only for the model.

The program prints the scale and shape of each fit, the median remission
with its interval, the test of a constant hazard, and the remission at 52
weeks with its interval.
"""

from extensions.clinical.parametric import (
    constant_hazard_test,
    draw_fit,
    fit_weibull,
)
from extensions.clinical.survival import (
    SurvivalCurve,
    WEEK64,
    kaplan_meier,
    survival_image,
)
from extensions.imaging.transfer import Rgba
from render.png import encode
from std.pathlib import Path
from tools._example_output import example_destination
from units.si import Duration64

comptime DEFAULT_OUTPUT = "out/parametric.png"
comptime DRUG = (
    "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
)
comptime PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def _group(text: String) raises -> Tuple[List[Duration64], List[Bool]]:
    """Read times in weeks, a `+` marking a censored patient."""
    var times = List[Duration64]()
    var events = List[Bool]()
    for part in text.split(" "):
        var word = String(part)
        var censored = word.endswith("+")
        var number = String(word.removesuffix("+"))
        times.append(Duration64(atof(number), WEEK64))
        events.append(not censored)
    return (times^, events^)


def _report(name: String, times: List[Duration64], events: List[Bool]) raises:
    """Print the Weibull fit of a group."""
    var fit = fit_weibull(times, events)
    var median = fit.quantile_interval(0.5)
    var test = constant_hazard_test(times, events)
    var year = Duration64(52, WEEK64)
    var band = fit.survival_interval(year)
    print(
        name,
        ": scale",
        fit.scale.to(WEEK64),
        "weeks, shape",
        fit.shape,
        "with a standard error of",
        fit.shape_error,
    )
    print(
        "  median remission",
        fit.median().to(WEEK64),
        "weeks, 95 percent interval",
        median[0].to(WEEK64),
        "to",
        median[1].to(WEEK64),
    )
    print("  constant hazard: chi-square", test[0], "p", test[1])
    print(
        "  in remission at 52 weeks",
        fit.survival(year),
        "with an interval of",
        band[0],
        "to",
        band[1],
    )


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var drug = _group(DRUG)
    var placebo = _group(PLACEBO)
    var blue = Rgba(0.15, 0.4, 0.85, 1)
    var red = Rgba(0.85, 0.2, 0.2, 1)
    var curves = List[SurvivalCurve]()
    curves.append(kaplan_meier(drug[0], drug[1]))
    curves.append(kaplan_meier(placebo[0], placebo[1]))
    var top = Duration64(52, WEEK64)
    var image = survival_image(
        curves, [blue, red], top, Duration64(4, WEEK64), 720, 360
    )
    draw_fit(image, fit_weibull(drug[0], drug[1]), blue, top)
    draw_fit(image, fit_weibull(placebo[0], placebo[1]), red, top)
    Path(destination).write_bytes(encode(image))
    _report("6-MP", drug[0], drug[1])
    _report("Placebo", placebo[0], placebo[1])
    print("Wrote", destination)
