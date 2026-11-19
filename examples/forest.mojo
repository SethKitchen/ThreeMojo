# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A forest plot of the trials of the BCG vaccine against tuberculosis.

    mojo run -I . examples/forest.mojo [out/forest.png]

The page is Meta-analysis. The data are the 13 trials of Colditz and others
(1994), of `assets/meta/bcg.txt`. The effect of each trial is its log risk
ratio of tuberculosis, vaccinated against not.

Each row is a trial: a line over its 95 percent interval and a square at
its effect, of an area in proportion to its weight. The gray diamond is
the fixed effect, and the blue diamond the random effect. The gray line
is no effect. Left of it, the vaccine protects. The program prints the
pooled risk ratios, the heterogeneity and the prediction interval.
"""

from extensions.clinical.meta import forest_image, log_risk_ratio, meta_analysis
from render.png import encode
from std.math import exp
from std.pathlib import Path
from tools._example_output import example_destination

comptime DEFAULT_OUTPUT = "out/forest.png"


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var effects = List[Float64]()
    var variances = List[Float64]()
    var text = open("assets/meta/bcg.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(",")
        var vaccinated = atol(String(words[1]))
        var others = atol(String(words[3]))
        var study = log_risk_ratio(
            vaccinated,
            vaccinated + atol(String(words[2])),
            others,
            others + atol(String(words[4])),
        )
        effects.append(study[0])
        variances.append(study[1])
    var result = meta_analysis(effects, variances)
    Path(destination).write_bytes(
        encode(forest_image(effects, variances, result, 640))
    )
    print(
        "Fixed effect: risk ratio",
        exp(result.fixed.estimate),
        "from",
        exp(result.fixed.lower),
        "to",
        exp(result.fixed.upper),
    )
    print(
        "Random effects: risk ratio",
        exp(result.random.estimate),
        "from",
        exp(result.random.lower),
        "to",
        exp(result.random.upper),
        "; p",
        result.random.p_value,
    )
    var band = result.prediction_interval()
    print(
        "Q",
        result.q,
        "p",
        result.q_p_value,
        "; I^2",
        result.i_squared,
        "; tau^2",
        result.tau_squared,
        "; a new trial from",
        exp(band[0]),
        "to",
        exp(band[1]),
    )
    print("Wrote", destination)
