# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic grades of the Fleiss' kappa tests.

Run it from the repository root: `mojo run -I . tools/make_fleiss.mojo`.
It writes `assets/agreement/films.txt`: 40 films, one a line, with the
count of 6 readers who give each of 4 grades. Each film has a true grade,
each as likely. A reader gives it with a share of 0.6, the grade below
with 0.16, and each other grade with 0.08, over their sum.
`assets/agreement/make_fleiss.py` then writes the kappas of statsmodels.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, integers, write_text


def main() raises:
    """Write the grades.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for _ in range(40):
        var grade = Int(noise.uniform() * 4.0)
        var shares = List[Float64](length=4, fill=0.08)
        shares[grade] = 0.6
        if grade > 0:
            shares[grade - 1] += 0.08
        var total = 0.0
        for s in shares:
            total += s
        var counts = List[Int](length=4, fill=0)
        for _ in range(6):
            var u = noise.uniform() * total
            var pick = 0
            while pick < 3 and u >= shares[pick]:
                u -= shares[pick]
                pick += 1
            counts[pick] += 1
        text += integers(counts) + "\n"
    write_text("assets/agreement/films.txt", text)
