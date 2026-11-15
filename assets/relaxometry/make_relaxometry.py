# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write reference fits of MRI relaxation times with numpy and scipy.

    mojo run -I . tools/make_mri_signals.mojo
    cd assets/relaxometry && python3 make_relaxometry.py > relaxometry_expected.txt

Run it with numpy 2.5.4 and scipy 1.18.1. `tools/make_mri_signals.mojo`
writes the synthetic signals, `relaxometry_signals.txt`, with Rician
noise of sigma 5, rounded to whole numbers as a scanner stores them. This
script fits them.

- `te` holds the echo times of a multi-echo spin echo, in ms. Each `t2`
  line holds the signals of one voxel, then the slope and the intercept of
  `numpy.polyfit` of ln S on the echo time. The test finds T2 and S0 from
  them.
- `ti` holds the inversion times, in ms. Each `t1` line holds the
  magnitude signals of one voxel of an inversion recovery, then T1 in ms,
  A, B and the number of signals whose sign the fit restores. The model is
  `S = |A - B exp(-TI / T1)|`. For each count k of the first signals taken
  as negative, scipy's `least_squares` fits A, B and T1 to 1e-15, and the
  fit of the least sum of squares wins, as Barral and others (2010) do.
"""

import numpy
from scipy.optimize import least_squares


def rows(name):
    with open("relaxometry_signals.txt") as data:
        return [numpy.array([float(v) for v in line.split()[1:]])
                for line in data if line.split()[0] == name]


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


te = rows("te")[0]
line("te", te)
for s in rows("t2"):
    line("t2", list(s) + list(numpy.polyfit(te, numpy.log(s), 1)))

ti = rows("ti")[0]
line("ti", ti)
for s in rows("t1"):
    best = None
    for k in range(len(ti) + 1):
        signed = s.copy()
        signed[:k] *= -1.0

        def residual(p):
            return p[0] - p[1] * numpy.exp(-ti / p[2]) - signed

        fit = least_squares(
            residual, [s[-1], 2.0 * s[-1], 1000.0], xtol=1e-15, ftol=1e-15, gtol=1e-15,
            bounds=([-numpy.inf, -numpy.inf, 1.0], [numpy.inf, numpy.inf, 10000.0]),
        )
        cost = numpy.sum(fit.fun ** 2)
        if best is None or cost < best[0]:
            best = (cost, fit.x, k)
    line("t1", list(s) + [best[1][2], best[1][0], best[1][1], best[2]])
