# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A funnel plot of the trials of the BCG vaccine, and Egger's test.

    mojo run -I . examples/funnel.mojo [out/funnel.png]

The page is Meta-analysis. The data are the 13 trials of Colditz and others
(1994), of `assets/meta/bcg.txt`, as log risk ratios. Each cross is a
trial: its effect across, and its standard error down, so that the larger
trials are at the top. The blue line is the fixed effect, and the gray
lines its 95 percent funnel. The program prints Egger's test of the
asymmetry of the funnel.
"""

from extensions.clinical.meta import (
    egger_test,
    funnel_image,
    log_risk_ratio,
    meta_analysis,
)
from render.png import encode
from std.pathlib import Path
from tools._example_output import example_destination

comptime DEFAULT_OUTPUT = "out/funnel.png"


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
        encode(funnel_image(effects, variances, result, 480, 400))
    )
    var test = egger_test(effects, variances)
    print(
        "Egger: intercept",
        test.intercept,
        "standard error",
        test.standard_error,
        "; t",
        test.t,
        "p",
        test.p_value,
    )
    print("Wrote", destination)
