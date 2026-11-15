# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic groups of the two-group tests.

Run it from the repository root: `mojo run -I . tools/make_hypothesis.mojo`.
It writes `assets/hypothesis/groups.txt`: falls of blood pressure in mmHg,
whole numbers so that many tie. The first line holds 25 values of a
treated group, the second 30 values of a control group, and the last two
lines 20 values of one group before and after a treatment.
`assets/hypothesis/make_hypothesis.py` then writes the results of scipy.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, integers, normal, whole, write_text


def _group(
    mut noise: Xorshift64, count: Int, mean: Float64, sd: Float64
) -> List[Int]:
    """Return whole normal numbers."""
    var out = List[Int]()
    for _ in range(count):
        out.append(whole(normal(noise, mean, sd)))
    return out^


def main() raises:
    """Write the groups.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var treated = _group(noise, 25, 12.0, 6.0)
    var control = _group(noise, 30, 7.0, 9.0)
    var before = _group(noise, 20, 150.0, 12.0)
    var fall = _group(noise, 20, 4.0, 5.0)
    var after = List[Int]()
    for i in range(20):
        after.append(before[i] - fall[i])
    write_text(
        "assets/hypothesis/groups.txt",
        integers(treated)
        + "\n"
        + integers(control)
        + "\n"
        + integers(before)
        + "\n"
        + integers(after)
        + "\n",
    )
