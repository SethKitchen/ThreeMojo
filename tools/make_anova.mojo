# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic groups of the tests of several groups.

Run it from the repository root: `mojo run -I . tools/make_anova.mojo`.
It writes `assets/hypothesis/three_groups.txt`: three lines of falls of
LDL cholesterol in mg/dL, whole numbers so that some tie, of 18, 22 and
20 patients on three doses. `assets/hypothesis/make_anova.py` then
writes the results of scipy for them.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, integers, normal, whole, write_text


def main() raises:
    """Write the groups.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var sizes: List[Int] = [18, 22, 20]
    var means: List[Float64] = [20.0, 26.0, 31.0]
    var sds: List[Float64] = [8.0, 8.0, 9.0]
    var text = String()
    for g in range(3):
        var group = List[Int]()
        for _ in range(sizes[g]):
            group.append(whole(normal(noise, means[g], sds[g])))
        text += integers(group) + "\n"
    write_text("assets/hypothesis/three_groups.txt", text)
