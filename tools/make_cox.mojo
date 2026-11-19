# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic cohort of the Cox model test.

Run it from the repository root: `mojo run -I . tools/make_cox.mojo`. It
writes `assets/survival/cox_cohort.txt`: 120 patients, one a line, of a
time in weeks, an event flag, an age in decades to 0.1, a treatment flag
and a lognormal marker to 0.01. The hazard is `0.002 exp(0.4 age - 0.7
treated + 0.3 marker)` a week, and the censoring time is uniform from 5
to 100 weeks, both rounded up. `assets/survival/make_cox.py` then writes
the fits of lifelines.
"""

from extensions.numerics.elementary import precise_exp
from extensions.numerics.noise import Xorshift64
from std.math import ceil
from tools._fixtures import SEED, normal, rounded, write_text


def main() raises:
    """Write the cohort.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for _ in range(120):
        var age = rounded(normal(noise, 6.0, 1.0), 1)
        var treated = 1 if noise.uniform() < 0.5 else 0
        var marker = rounded(precise_exp(normal(noise, 0.0, 0.5)), 2)
        var rate = 0.002 * precise_exp(
            0.4 * age - 0.7 * Float64(treated) + 0.3 * marker
        )
        var event_time = ceil(noise.exponential(1.0 / rate))
        var censor_time = ceil(noise.between(5.0, 100.0))
        var time = min(event_time, censor_time)
        var event = 1 if event_time <= censor_time else 0
        text += String(
            Int(time), " ", event, " ", age, " ", treated, " ", marker, "\n"
        )
    write_text("assets/survival/cox_cohort.txt", text)
