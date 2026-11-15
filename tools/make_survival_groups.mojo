# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic arms of the log-rank test of several groups.

Run it from the repository root:
`mojo run -I . tools/make_survival_groups.mojo`. It writes
`assets/survival/three_arms.txt`: three lines of 25 times in weeks, one
line an arm. The event times are exponential with means of 20, 28 and 40
weeks, and the censoring times uniform from 10 to 60 weeks, both rounded
up. A censored time ends in `+`. `assets/survival/make_groups.py` then
writes the test of lifelines.
"""

from extensions.numerics.noise import Xorshift64
from std.math import ceil
from tools._fixtures import SEED, write_text


def main() raises:
    """Write the arms.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var scales: List[Float64] = [20.0, 28.0, 40.0]
    var text = String()
    for arm in range(3):
        var events = List[Float64]()
        for _ in range(25):
            events.append(ceil(noise.exponential(scales[arm])))
        for i in range(25):
            var censor = ceil(noise.between(10.0, 60.0))
            if i > 0:
                text += " "
            if events[i] <= censor:
                text += String(Int(events[i]))
            else:
                text += String(Int(censor), "+")
        text += "\n"
    write_text("assets/survival/three_arms.txt", text)
