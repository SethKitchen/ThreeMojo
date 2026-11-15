# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cumulative incidence of relapse and of death without relapse, beside
the Kaplan-Meier estimate that censors the deaths.

    mojo run -I . examples/competing.mojo [out/competing.png]

The page is Survival analysis. A synthetic cohort of 400 patients has a
relapse at a rate of 0.15 a year and a death without relapse at 0.10 a
year. Each patient is followed for a time spread evenly up to 10 years.
Each patient keeps the first of the three.

The blue steps are the cumulative incidence of relapse, and the gray steps
that of death without relapse. The red steps are `1 - S` of the
Kaplan-Meier curve of relapse with the deaths censored. They rise above
the blue steps, because they count the dead as if they could still
relapse. The true incidence of relapse at 5 years is
`0.6 (1 - exp(-1.25))`, or 0.43.

This is a synthetic cohort, for teaching. It is not a model of a disease.
"""

from extensions.clinical.competing import (
    CumulativeIncidence,
    cumulative_incidence,
    incidence_image,
)
from extensions.clinical.rates import YEAR64
from extensions.imaging.transfer import Rgba
from render.png import encode
from std.math import log
from std.pathlib import Path
from tools._example_output import example_destination
from units.si import Duration64

comptime DEFAULT_OUTPUT = "out/competing.png"
comptime PATIENTS = 400


struct _Noise(Movable):
    """A seeded source of uniform numbers, by xorshift."""

    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def uniform(mut self) -> Float64:
        self.state ^= self.state << 13
        self.state ^= self.state >> 7
        self.state ^= self.state << 17
        return (Float64(self.state >> 11) + 0.5) / 9007199254740992.0


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var noise = _Noise(20261115)
    var times = List[Duration64]()
    var relapse = List[Bool]()
    var death = List[Bool]()
    var none = List[Bool]()
    for _ in range(PATIENTS):
        var first = -log(noise.uniform()) / 0.15
        var second = -log(noise.uniform()) / 0.10
        var follow = 10.0 * noise.uniform()
        var end = min(first, second, follow)
        times.append(Duration64(end, YEAR64))
        relapse.append(end == first)
        death.append(end == second)
        none.append(False)
    var curves: List[CumulativeIncidence] = [
        cumulative_incidence(times, relapse, none),
        cumulative_incidence(times, death, relapse),
        cumulative_incidence(times, relapse, death),
    ]
    var image = incidence_image(
        curves,
        [
            Rgba(0.85, 0.2, 0.2, 1),
            Rgba(0.5, 0.5, 0.53, 1),
            Rgba(0.16, 0.38, 0.73, 1),
        ],
        Duration64(10.0, YEAR64),
        Duration64(1.0, YEAR64),
        0.8,
        640,
        400,
    )
    Path(destination).write_bytes(encode(image))
    var five = Duration64(5.0, YEAR64)
    print("At 5 years:")
    print("  relapse, Aalen-Johansen:", curves[2].at(five))
    print("  relapse, 1 - Kaplan-Meier:", curves[0].at(five))
    print("  death without relapse:", curves[1].at(five))
    print("Wrote", destination)
