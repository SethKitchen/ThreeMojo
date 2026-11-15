# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The early growth of an outbreak, and the reproduction number it implies.

    mojo run -I . examples/incidence.mojo [out/incidence.png]

The page is Epidemic models. The data are 40 days of synthetic case counts
of `assets/incidence/cases.txt`. Each blue bar is the cases of one day, and
the red curve is the fitted exponential growth.

The program prints the growth rate with its interval, the doubling time,
the dispersion, and the reproduction number of a disease with a latent
period of 3 days and an infectious period of 5 days.
"""

from extensions.clinical.incidence import (
    PER_DAY64,
    growth_rate,
    incidence_image,
    reproduction_number,
)
from extensions.clinical.survival import DAY64
from render.png import encode
from std.pathlib import Path
from tools._example_output import example_destination
from units.si import Duration64

comptime DEFAULT_OUTPUT = "out/incidence.png"


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var counts = List[Int]()
    var text = open("assets/incidence/cases.txt", "r").read()
    for line in text.splitlines():
        counts.append(atol(String(line)))
    var day = Duration64(1, DAY64)
    var fit = growth_rate(counts, day, 1e-12, 100)
    Path(destination).write_bytes(
        encode(incidence_image(counts, day, fit, 720, 360))
    )
    var band = fit.rate_interval()
    print(
        "Growth rate",
        fit.rate.to(PER_DAY64),
        "a day, from",
        band[0].to(PER_DAY64),
        "to",
        band[1].to(PER_DAY64),
        "; doubling time",
        fit.doubling_time().to(DAY64),
        "days; dispersion",
        fit.dispersion,
    )
    var latent = Duration64(3, DAY64)
    var infectious = Duration64(5, DAY64)
    print(
        "R",
        reproduction_number(fit.rate, latent, infectious),
        "from",
        reproduction_number(band[0], latent, infectious),
        "to",
        reproduction_number(band[1], latent, infectious),
    )
    print("Wrote", destination)
