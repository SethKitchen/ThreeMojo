# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic cohort of the logistic regression test.

Run it from the repository root: `mojo run -I . tools/make_logistic.mojo`.
It writes `assets/logistic/cohort.txt`: 200 patients, one a line, of a
disease flag, an age in decades to 0.1, a smoking flag and a marker to
0.01. The chance of the disease is the logistic of `-6 + 0.7 age + 0.9
smoker + 0.5 marker`. `assets/logistic/make_logistic.py` then writes the
fit of statsmodels.
"""

from extensions.numerics.elementary import logistic
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, normal, rounded, write_text


def main() raises:
    """Write the cohort.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for _ in range(200):
        var age = rounded(normal(noise, 6.0, 1.2), 1)
        var smoker = 1 if noise.uniform() < 0.35 else 0
        var marker = rounded(normal(noise, 2.0, 1.0), 2)
        var eta = -6.0 + 0.7 * age + 0.9 * Float64(smoker) + 0.5 * marker
        var disease = 1 if noise.uniform() < logistic(eta) else 0
        text += String(disease, " ", age, " ", smoker, " ", marker, "\n")
    write_text("assets/logistic/cohort.txt", text)
