# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic markers of the ROC tests.

Run it from the repository root: `mojo run -I . tools/make_roc.mojo`. It
writes `assets/roc/markers.txt`: 150 patients, one a line, of a disease
flag and two markers. 60 patients, in a shuffled order, have the disease.
Marker A is normal and 1.2 higher with the disease, to 0.1, so many of
its scores tie. Marker B is `0.6 A` with more noise and 0.3 higher with
the disease, to 0.01. `assets/roc/make_roc.py` then writes the results of
scikit-learn and MLstatkit.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, normal, rounded, write_text


def main() raises:
    """Write the markers.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var n = 150
    var diseased = List[Int]()
    for i in range(n):
        diseased.append(1 if i < 60 else 0)
    # Fisher and Yates: each order is as likely.
    for i in range(n - 1, 0, -1):
        var j = Int(noise.uniform() * Float64(i + 1))
        var held = diseased[i]
        diseased[i] = diseased[j]
        diseased[j] = held
    var text = String()
    for i in range(n):
        var d = Float64(diseased[i])
        var a = rounded(normal(noise, 0.0, 1.0) + 1.2 * d, 1)
        var b = rounded(0.6 * a + normal(noise, 0.0, 0.8) + 0.3 * d, 2)
        text += String(diseased[i], " ", a, " ", b, "\n")
    write_text("assets/roc/markers.txt", text)
