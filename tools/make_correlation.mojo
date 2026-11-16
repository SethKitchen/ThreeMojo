# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic pairs of the correlation tests.

Run it from the repository root: `mojo run -I . tools/make_correlation.mojo`.
It writes `assets/hypothesis/pairs.txt`: two lines of 30 values, a fasting
glucose in mmol/L to 0.1, and an HbA1c in percent to 0.1, so that some
tie. `assets/hypothesis/make_correlation.py` then writes the results of
scipy for them.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, normal, numbers, whole, write_text


def _tenth(x: Float64) -> Float64:
    """Return a number rounded to 0.1."""
    return Float64(whole(10.0 * x)) / 10.0


def main() raises:
    """Write the pairs.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var glucose = List[Float64]()
    var hba1c = List[Float64]()
    for _ in range(30):
        glucose.append(_tenth(normal(noise, 6.5, 1.2)))
    for i in range(30):
        hba1c.append(_tenth(4.0 + 0.4 * glucose[i] + normal(noise, 0.0, 0.35)))
    write_text(
        "assets/hypothesis/pairs.txt",
        numbers(glucose) + "\n" + numbers(hba1c) + "\n",
    )
