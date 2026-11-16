# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the groups of the exponential and Weibull fit tests.

Run it from the repository root: `mojo run -I . tools/make_parametric.mojo`.
It writes `assets/parametric/parametric_data.txt`, one group a line: a
name, a unit and the times, a `+` marking a censored time. The groups
are the 6-MP and placebo arms of the trial of Freireich and others
(1963) in weeks, and two synthetic groups in days: 60 Weibull times of
scale 10 and shape 1.6 censored uniformly up to 25 days, and 40 of scale
8 and shape 0.7 censored up to 30 days, to 0.01.
`tools/reference_parametric.mojo` then writes the reference fits at about
32 digits, and `assets/parametric/make_parametric.py` the fits of
lifelines.
"""

from extensions.numerics.elementary import precise_power
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, rounded, write_text

comptime DRUG = (
    "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
)
comptime PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def _synthetic(
    mut noise: Xorshift64,
    n: Int,
    scale: Float64,
    shape: Float64,
    follow: Float64,
) -> String:
    """Return Weibull times with uniform censoring, to 0.01."""
    var times = List[Float64]()
    for _ in range(n):
        times.append(scale * precise_power(noise.exponential(1.0), 1.0 / shape))
    var out = String()
    for i in range(n):
        var censor = noise.between(0.0, follow)
        if i > 0:
            out += " "
        if times[i] <= censor:
            out += String(rounded(times[i], 2))
        else:
            out += String(rounded(censor, 2), "+")
    return out^


def main() raises:
    """Write the groups.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String("drug wk ", DRUG, "\nplacebo wk ", PLACEBO, "\n")
    text += "rising d " + _synthetic(noise, 60, 10.0, 1.6, 25.0) + "\n"
    text += "falling d " + _synthetic(noise, 40, 8.0, 0.7, 30.0) + "\n"
    write_text("assets/parametric/parametric_data.txt", text)
