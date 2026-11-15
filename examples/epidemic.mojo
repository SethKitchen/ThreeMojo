# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One SEIR epidemic with three levels of vaccination.

    mojo run -I . examples/epidemic.mojo [out/epidemic.png]

The page is Epidemic models. The disease has an R0 of 2.5, a latent period
of 3 days and an infectious period of 5 days. It starts from 1 in 10000 of
the population. The red curve has no one vaccinated, the orange curve 30
percent, and the blue curve 50 percent. The curves give the infectious
fraction over 300 days, up to 15 percent, with a gray line each 30 days.

The herd immunity threshold is 60 percent. The program prints the peak and
the final size of each epidemic.
"""

from extensions.clinical.epidemic import (
    EpidemicCurve,
    epidemic_image,
    final_susceptible,
    herd_immunity,
    seir,
)
from extensions.clinical.survival import DAY64
from extensions.imaging.transfer import Rgba
from render.png import encode
from std.pathlib import Path
from tools._example_output import example_destination
from units.si import Duration64

comptime DEFAULT_OUTPUT = "out/epidemic.png"
comptime R0 = 2.5
comptime START = 1e-4


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var vaccinated: List[Float64] = [0.0, 0.3, 0.5]
    var curves = List[EpidemicCurve]()
    for v in vaccinated:
        curves.append(
            seir(
                R0,
                Duration64(3, DAY64),
                Duration64(5, DAY64),
                START,
                v,
                Duration64(0.1, DAY64),
                Duration64(300, DAY64),
            )
        )
    var image = epidemic_image(
        curves,
        [
            Rgba(0.85, 0.2, 0.2, 1),
            Rgba(0.95, 0.6, 0.1, 1),
            Rgba(0.15, 0.4, 0.85, 1),
        ],
        Duration64(300, DAY64),
        Duration64(30, DAY64),
        0.15,
        720,
        360,
    )
    Path(destination).write_bytes(encode(image))
    print("Herd immunity threshold:", herd_immunity(R0))
    for c in range(3):
        var peak = curves[c].peak()
        var never = final_susceptible(R0, START, vaccinated[c])
        print(
            "Vaccinated",
            vaccinated[c],
            ": peak",
            peak[1],
            "infectious at day",
            peak[0].to(DAY64),
            "; infected in all",
            1.0 - vaccinated[c] - never,
        )
    print("Wrote", destination)
