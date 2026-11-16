# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic patients of the linear regression test.

Run it from the repository root: `mojo run -I . tools/make_regression.mojo`.
It writes `assets/regression/pressure.txt`: 80 patients, one a line, of
a systolic pressure in mmHg, an age in years, a BMI to 0.1 and a salt
intake in g/day to 0.1. The pressure is `90 + 0.6 age + 0.9 BMI + 1.2
salt` with normal noise of 9 mmHg, rounded. `assets/regression/
make_regression.py` then writes the fit of statsmodels.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, normal, rounded, whole, write_text


def main() raises:
    """Write the patients.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for _ in range(80):
        var age = whole(noise.between(30.0, 80.0))
        var bmi = rounded(normal(noise, 27.0, 4.0), 1)
        var salt = rounded(normal(noise, 8.0, 2.5), 1)
        var pressure = whole(
            90.0
            + 0.6 * Float64(age)
            + 0.9 * bmi
            + 1.2 * salt
            + normal(noise, 0.0, 9.0)
        )
        text += String(pressure, " ", age, " ", bmi, " ", salt, "\n")
    write_text("assets/regression/pressure.txt", text)
