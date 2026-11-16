# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic patients of the competing risks test.

Run it from the repository root: `mojo run -I . tools/make_competing.mojo`.
It writes `assets/competing/patients.txt`: 80 patients, one a line, of a
time in years to 1e-6 and its cause. The times to relapse and to death
without relapse are exponential with rates of 0.15 and 0.10 a year, and
the censoring time is uniform from 0 to 10 years. The first of the three
is the time, and its cause is 1 for relapse, 2 for death and 0 for
censoring. The longest time is censored, so the curves end there.
`assets/competing/make_competing.py` then writes the fits of lifelines.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, rounded, write_text


def main() raises:
    """Write the patients.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var n = 80
    var relapse = List[Float64]()
    var death = List[Float64]()
    var censor = List[Float64]()
    for _ in range(n):
        relapse.append(noise.exponential(1.0 / 0.15))
    for _ in range(n):
        death.append(noise.exponential(1.0 / 0.10))
    for _ in range(n):
        censor.append(noise.between(0.0, 10.0))
    var times = List[Float64]()
    var causes = List[Int]()
    var longest = 0
    for i in range(n):
        var first = min(relapse[i], min(death[i], censor[i]))
        var cause = 0
        if first == relapse[i]:
            cause = 1
        elif first == death[i]:
            cause = 2
        times.append(rounded(first, 6))
        causes.append(cause)
        if times[i] > times[longest]:
            longest = i
    causes[longest] = 0
    var text = String()
    for i in range(n):
        text += String(times[i], " ", causes[i], "\n")
    write_text("assets/competing/patients.txt", text)
