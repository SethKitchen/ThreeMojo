# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic risks and outcomes of the calibration tests.

Run it from the repository root: `mojo run -I . tools/make_calibration.mojo`.
It writes `assets/calibration/patients.txt`: 300 patients, one a line, of
the risk that an overfitted model gives and the outcome, 1 or 0. With x
standard normal and z a fair flag, the true risk is the logistic of
`-1.2 + 1.1 x + 0.8 z`, and the model gives the logistic of `-0.9 + 1.5
x + 1.0 z`: too high, and too spread. `assets/calibration/
make_calibration.py` then writes the results of scikit-learn,
statsmodels and dcurves.
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
    for _ in range(300):
        var x = noise.normal()
        var z = 1.0 if noise.uniform() < 0.5 else 0.0
        var truth = logistic(-1.2 + 1.1 * x + 0.8 * z)
        var outcome = 1 if noise.uniform() < truth else 0
        var risk = logistic(-0.9 + 1.5 * x + 1.0 * z)
        text += String(risk, " ", outcome, "\n")
    write_text("assets/calibration/patients.txt", text)
