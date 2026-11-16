# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the groups of the Weibull regression tests.

Run it from the repository root: `mojo run -I . tools/make_aft.mojo`. It
writes `assets/aft/aft_cohort.txt`. Each line holds a group, a time, 1 for
an event or 0, and the covariates. The groups are:

- `trial`: the 6-MP trial of Freireich and others (1963) in weeks, with
  1 for the placebo.
- `cohort`: 150 synthetic patients in days, with an age in decades to
  0.001, a marker to 0.0001 and a treatment flag. The scale is `exp(4.5 -
  0.25 (age - 6) - 0.3 marker + 0.4 treated)` and the shape 1.4, with
  uniform censoring from 20 to 250 days. The times are to 0.01.
- `spread` and `tiny`: two small groups of 6 and 4 patients, in days,
  that make the first Newton step too long.

`tools/reference_aft.mojo` then writes the reference fits at about 32
digits, and `assets/aft/make_aft.py` the fits of lifelines.
"""

from extensions.numerics.elementary import precise_exp, precise_power
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, normal, rounded, write_text

comptime DRUG = (
    "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
)
comptime PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def _trial() raises -> String:
    """Return the lines of the 6-MP trial."""
    var out = String()
    var texts: List[String] = [DRUG, PLACEBO]
    for arm in range(2):
        for word in texts[arm].split(" "):
            var w = String(word)
            var censored = w.endswith("+")
            out += String(
                "trial ",
                Float64(atof(String(w.removesuffix("+")))),
                " ",
                0.0 if censored else 1.0,
                " ",
                Float64(arm),
                "\n",
            )
    return out^


def main() raises:
    """Write the groups.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = _trial()
    for _ in range(150):
        var age = noise.between(4.0, 8.5)
        var marker = normal(noise, 0.0, 1.0)
        var treated = 1.0 if noise.uniform() < 0.5 else 0.0
        var scale = precise_exp(
            4.5 - 0.25 * (age - 6.0) - 0.3 * marker + 0.4 * treated
        )
        var time = scale * precise_power(noise.exponential(1.0), 1.0 / 1.4)
        var censor = noise.between(20.0, 250.0)
        var event = 1.0 if time <= censor else 0.0
        text += String(
            "cohort ",
            rounded(min(time, censor), 2),
            " ",
            event,
            " ",
            rounded(age, 3),
            " ",
            rounded(marker, 4),
            " ",
            treated,
            "\n",
        )
    var spread: List[Float64] = [0.01, 0.1, 1.0, 10.0, 100.0, 1000.0]
    for k in range(6):
        text += String("spread ", spread[k], " 1.0 ", Float64(k % 2), "\n")
    var tiny: List[Float64] = [1.0, 2.0, 3.0, 100.0]
    for k in range(4):
        text += String("tiny ", tiny[k], " 1.0 ", Float64(k % 2), "\n")
    write_text("assets/aft/aft_cohort.txt", text)
