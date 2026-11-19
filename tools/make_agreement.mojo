# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic readings of the agreement tests.

Run it from the repository root: `mojo run -I . tools/make_agreement.mojo`.
It writes `assets/agreement/readers.txt`: 40 tumors, one a line, with the
volume in mL by reader A and by reader B, to 0.1 mL. The true volume is
lognormal about 20 mL with a log deviation of 0.6. Reader A adds normal
noise of 1 mL, and reader B reads 3 percent and 0.5 mL high with noise
of 1.2 mL. `assets/agreement/make_agreement.py` then writes the results
of pingouin and scipy.
"""

from extensions.numerics.elementary import precise_exp
from extensions.numerics.noise import Xorshift64
from std.math import log
from tools._fixtures import SEED, normal, rounded, write_text


def main() raises:
    """Write the readings.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for _ in range(40):
        var truth = precise_exp(normal(noise, log(20.0), 0.6))
        var a = rounded(truth + normal(noise, 0.0, 1.0), 1)
        var b = rounded(truth * 1.03 + 0.5 + normal(noise, 0.0, 1.2), 1)
        text += String(a, " ", b, "\n")
    write_text("assets/agreement/readers.txt", text)
