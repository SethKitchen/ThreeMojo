# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic case counts of an outbreak.

Run it from the repository root: `mojo run -I . tools/make_incidence.mojo`.
It writes `assets/incidence/cases.txt`: 40 daily counts, one a line,
Poisson with a mean of `8 exp(0.12 day)`. `assets/incidence/
make_incidence.py` then writes the Poisson fit of statsmodels.
"""

from extensions.numerics.elementary import precise_exp
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, write_text


def main() raises:
    """Write the counts.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for day in range(40):
        text += String(noise.poisson(8.0 * precise_exp(0.12 * Float64(day))))
        text += "\n"
    write_text("assets/incidence/cases.txt", text)
