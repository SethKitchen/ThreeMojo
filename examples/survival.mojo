# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Kaplan-Meier curves of a classic trial, and its log-rank test.

    mojo run -I . examples/survival.mojo [out/survival.png]

The page is Survival analysis. The data are the remission times, in
weeks, of 42 children with acute leukemia in the trial of
6-mercaptopurine (6-MP) against a placebo of Freireich and others (1963),
as Gehan (1965) gives them. A time with a `+` is censored.

The blue curve is the 6-MP group and the red curve the placebo group,
from 0 to 36 weeks, with a gray line each 6 weeks. A tick marks each
censored patient. The program prints the median remission of each group,
the log-rank test, the hazard ratio of the placebo by a Cox model, and the
difference of the restricted mean remission to 23 weeks.
"""

from extensions.clinical.cox import cox_regression
from extensions.clinical.rmst import compare_restricted_means
from extensions.clinical.survival import (
    SurvivalCurve,
    WEEK64,
    kaplan_meier,
    log_rank_test,
    survival_image,
)
from extensions.imaging.transfer import Rgba
from render.png import encode
from std.pathlib import Path
from tools._example_output import example_destination
from units.si import Duration64

comptime DEFAULT_OUTPUT = "out/survival.png"
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
        var number = word
        if censored:
            number = String(word[byte = 0 : word.byte_length() - 1])
        times.append(Duration64(atof(number), WEEK64))
        events.append(not censored)
    return (times^, events^)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var drug = _group(DRUG)
    var placebo = _group(PLACEBO)
    var curves = List[SurvivalCurve]()
    curves.append(kaplan_meier(drug[0], drug[1]))
    curves.append(kaplan_meier(placebo[0], placebo[1]))
    var image = survival_image(
        curves,
        [Rgba(0.15, 0.4, 0.85, 1), Rgba(0.85, 0.2, 0.2, 1)],
        Duration64(36, WEEK64),
        Duration64(6, WEEK64),
        720,
        360,
    )
    Path(destination).write_bytes(encode(image))
    var test = log_rank_test(drug[0], drug[1], placebo[0], placebo[1])
    print(
        "Median remission: 6-MP",
        curves[0].median()[1].to(WEEK64),
        "weeks; placebo",
        curves[1].median()[1].to(WEEK64),
        "weeks",
    )
    print(
        "Log-rank: chi-square",
        test.statistic,
        "p",
        test.p_value,
        "; relapses",
        test.observed[0],
        "and",
        test.observed[1],
        "where",
        test.expected[0],
        "and",
        test.expected[1],
        "were expected",
    )
    # The Cox model of one covariate: 1 for the placebo group.
    var times = drug[0].copy()
    var events = drug[1].copy()
    var rows = List[List[Float64]]()
    for _ in range(len(drug[0])):
        rows.append([0.0])
    for i in range(len(placebo[0])):
        times.append(placebo[0][i])
        events.append(placebo[1][i])
        rows.append([1.0])
    var model = cox_regression(times, events, rows, 1e-10, 50)
    var band = model.interval(0)
    print(
        "Cox: hazard ratio of the placebo",
        model.hazard_ratio(0),
        "with a 95 percent interval of",
        band[0],
        "to",
        band[1],
        "; p",
        model.p_value(0),
    )
    var rmst = compare_restricted_means(
        curves[0], curves[1], Duration64(23, WEEK64)
    )
    print(
        "Restricted mean to 23 weeks: 6-MP longer by",
        rmst.difference.to(WEEK64),
        "weeks, standard error",
        rmst.standard_error.to(WEEK64),
        "; p",
        rmst.p_value,
    )
    print("Wrote", destination)
