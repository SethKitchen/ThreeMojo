# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The agreement of two readers who measure the same tumors.

    mojo run -I . examples/agreement.mojo [out/agreement.png]

The page is Diagnostic tests. The data are the volumes of 40 synthetic
tumors in milliliters, by reader A and by reader B, of
`assets/agreement/readers.txt`.

The picture is a Bland-Altman plot. Each cross is a tumor: its mean volume
across, and A less B up. The blue line is the bias and the red lines are
the limits of agreement. The gray line is 0. The program prints the bias,
the limits with their intervals, and the intraclass correlations of
absolute agreement and of consistency.
"""

from extensions.clinical.agreement import (
    bland_altman,
    bland_altman_image,
    intraclass_correlation,
)
from render.png import encode
from std.pathlib import Path
from tools._example_output import example_destination

comptime DEFAULT_OUTPUT = "out/agreement.png"


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var a = List[Float64]()
    var b = List[Float64]()
    var pairs = List[List[Float64]]()
    var text = open("assets/agreement/readers.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(" ")
        var first = atof(String(words[0]))
        var second = atof(String(words[1]))
        a.append(first)
        b.append(second)
        pairs.append([first, second])
    var result = bland_altman(a, b)
    Path(destination).write_bytes(
        encode(bland_altman_image(a, b, result, 720, 400))
    )
    print(
        "Bias, A less B:",
        result.bias,
        "mL, 95 percent interval",
        result.bias_interval[0],
        "to",
        result.bias_interval[1],
    )
    print(
        "Limits of agreement:",
        result.lower,
        "to",
        result.upper,
        "mL; the lower from",
        result.lower_interval[0],
        "to",
        result.lower_interval[1],
        "and the upper from",
        result.upper_interval[0],
        "to",
        result.upper_interval[1],
    )
    var table = intraclass_correlation(pairs)
    print(
        "ICC(A,1)",
        table.agreement.value,
        "from",
        table.agreement.lower,
        "to",
        table.agreement.upper,
        "; ICC(C,1)",
        table.consistency.value,
        "from",
        table.consistency.lower,
        "to",
        table.consistency.upper,
    )
    print("Wrote", destination)
