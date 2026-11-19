# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic study of the propensity score tests.

Run it from the repository root: `mojo run -I . tools/make_propensity.mojo`.
It writes `assets/propensity/patients.txt`: 500 patients, one a line, of
a treatment flag, an outcome flag, and three covariates: a standardized
age, a sex flag and a standardized severity. Older and sicker patients
are treated more often, by the logistic of `-0.4 + 0.7 age + 0.3 sex +
0.6 severity`, and have the outcome more often, by the logistic of `-1.2
+ 0.6 age + 0.2 sex + 0.8 severity - 0.5 treated`.
`assets/propensity/make_propensity.py` then writes the results of
statsmodels and numpy.
"""

from extensions.numerics.elementary import logistic
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, write_text


def main() raises:
    """Write the patients.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for _ in range(500):
        var age = noise.normal()
        var sex = 1.0 if noise.uniform() < 0.5 else 0.0
        var severity = noise.normal()
        var chance = logistic(-0.4 + 0.7 * age + 0.3 * sex + 0.6 * severity)
        var treated = 1.0 if noise.uniform() < chance else 0.0
        var risk = logistic(
            -1.2 + 0.6 * age + 0.2 * sex + 0.8 * severity - 0.5 * treated
        )
        var outcome = 1.0 if noise.uniform() < risk else 0.0
        text += String(
            treated, " ", outcome, " ", age, " ", sex, " ", severity, "\n"
        )
    write_text("assets/propensity/patients.txt", text)
