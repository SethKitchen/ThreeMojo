# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write SEIR and SIR epidemics by scipy, a Python library.

    python3 make_epidemic.py > epidemic_expected.txt

Run it with numpy and scipy 1.18.1. The epidemics are integrated by
`solve_ivp` with the method DOP853 to a relative tolerance of 1e-13. The
fractions of the population are S, E, I and R, with

    dS/dt = -b S I, dE/dt = b S I - s E, dI/dt = s E - g I, dR/dt = g I,

`b = R0 g`, `s` one over the latent period and `g` one over the infectious
period. An SIR epidemic has no E: dI/dt = b S I - g I.

The output has these lines:

- `seir` with S, E, I and R at 10, 30, 60, 90 and 150 days of an epidemic
  of R0 2.5, a latent period of 3 days and an infectious period of 5 days,
  from 1e-4 infectious and none immune.
- `sir` with S, I and R at the same days of an epidemic of R0 1.8 and an
  infectious period of 4 days, from 1e-3 infectious and 0.2 immune.
- `final` with the fraction never infected of each, from
  `ln(S0 / S) = R0 (1 - p - S)` by `brentq`, with `p` the immune
  fraction.
"""

import numpy as np
from scipy.integrate import solve_ivp
from scipy.optimize import brentq

DAYS = [10.0, 30.0, 60.0, 90.0, 150.0]


def seir(t, y, b, s, g):
    S, E, I, R = y
    return [-b * S * I, b * S * I - s * E, s * E - g * I, g * I]


def sir(t, y, b, g):
    S, I, R = y
    return [-b * S * I, b * S * I - g * I, g * I]


first = solve_ivp(
    seir, (0.0, 150.0), [1 - 1e-4, 0.0, 1e-4, 0.0], method="DOP853",
    t_eval=DAYS, rtol=1e-13, atol=1e-16, args=(2.5 / 5.0, 1 / 3.0, 1 / 5.0),
)
second = solve_ivp(
    sir, (0.0, 150.0), [1 - 1e-3 - 0.2, 1e-3, 0.2], method="DOP853",
    t_eval=DAYS, rtol=1e-13, atol=1e-16, args=(1.8 / 4.0, 1 / 4.0),
)
print("seir " + " ".join(repr(float(v)) for v in first.y.T.ravel()))
print("sir " + " ".join(repr(float(v)) for v in second.y.T.ravel()))


def never(r0, s0, immune):
    return brentq(
        lambda s: np.log(s0 / s) - r0 * (1 - immune - s), 1e-300, s0 * (1 - 1e-15),
        xtol=1e-300, rtol=8.9e-16,
    )


print("final %r %r" % (never(2.5, 1 - 1e-4, 0.0), never(1.8, 1 - 1e-3 - 0.2, 0.2)))
