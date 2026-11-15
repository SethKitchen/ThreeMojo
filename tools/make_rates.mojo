# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic strata of the rate and negative binomial models.

Run it from the repository root: `mojo run -I . tools/make_rates.mojo`.
It writes two files into `assets/rates/`:

- `strata.txt`: 48 strata, one a line, of the events, the person-years,
  the age in decades, a smoking flag and an air pollution index. The
  events are Poisson counts of `exp(-11 + 0.9 age + 1.1 smoker + 0.15
  pollution)` per person-year.
- `negbin_strata.txt`: 120 strata of the events, the person-years, a
  smoking flag and a standardized age. The events are Poisson counts of
  a mean `years exp(-3 + 0.6 smoking + 0.4 age)` times a gamma frailty of
  shape 2 and scale 0.5, so they spread more than Poisson counts.

`assets/rates/make_rates.py` and `make_negbin.py` then write the results
of statsmodels.
"""

from extensions.numerics.elementary import precise_exp
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, normal, rounded, write_text


def main() raises:
    """Write both files.

    Raises:
        Error: If a file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for i in range(48):
        var age = rounded(noise.between(4.0, 8.0), 1)
        var smoker = i % 2
        var pollution = rounded(normal(noise, 3.0, 1.0), 2)
        var years = rounded(noise.between(200.0, 3000.0), 1)
        var rate = precise_exp(
            -11.0 + 0.9 * age + 1.1 * Float64(smoker) + 0.15 * pollution
        )
        var events = noise.poisson(rate * years)
        text += String(
            events, " ", years, " ", age, " ", smoker, " ", pollution, "\n"
        )
    write_text("assets/rates/strata.txt", text)
    text = String()
    for _ in range(120):
        var years = rounded(noise.between(50.0, 400.0), 1)
        var smoking = 1.0 if noise.uniform() < 0.4 else 0.0
        var age = rounded(noise.normal(), 2)
        var rate = precise_exp(-3.0 + 0.6 * smoking + 0.4 * age)
        var mean = years * rate * noise.gamma(2.0, 0.5)
        var events = noise.poisson(mean)
        text += String(events, " ", years, " ", smoking, " ", age, "\n")
    write_text("assets/rates/negbin_strata.txt", text)
