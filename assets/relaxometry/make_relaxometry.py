# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write reference fits of MRI relaxation times with numpy and scipy.

    python3 make_relaxometry.py > relaxometry_expected.txt

Run it with numpy 2.5.4 and scipy 1.18.1. The signals are synthetic, with
Rician noise of sigma 5, rounded to whole numbers as a scanner stores
them.

- `te` holds the echo times of a multi-echo spin echo, in ms. Each `t2`
  line holds the signals of one voxel, then T2 in ms and S0 from
  `numpy.polyfit` of ln S on the echo time.
- `ti` holds the inversion times, in ms. Each `t1` line holds the
  magnitude signals of one voxel of an inversion recovery, then T1 in ms,
  A, B and the number of signals whose sign the fit restores. The model is
  `S = |A - B exp(-TI / T1)|`. For each count k of the first signals taken
  as negative, scipy's `least_squares` fits A, B and T1 to 1e-15, and the
  fit of the least sum of squares wins, as Barral and others (2010) do.
"""

import numpy
from scipy.optimize import least_squares

generator = numpy.random.default_rng(20261115)


def noisy(signal):
    noise = generator.normal(0.0, 5.0, size=(2, len(signal)))
    return numpy.maximum(numpy.rint(numpy.hypot(signal + noise[0], noise[1])), 1.0)


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


te = numpy.array([10.0, 20.0, 30.0, 40.0, 60.0, 80.0, 100.0, 120.0])
line("te", te)
for index in range(8):
    s0 = 800.0 + 120.0 * index
    t2 = 30.0 + 20.0 * index
    s = noisy(s0 * numpy.exp(-te / t2))
    slope, intercept = numpy.polyfit(te, numpy.log(s), 1)
    line("t2", list(s) + [-1.0 / slope, numpy.exp(intercept)])

ti = numpy.array([50.0, 150.0, 300.0, 600.0, 1000.0, 1500.0, 2500.0, 4000.0])
line("ti", ti)
for index in range(8):
    a = 900.0 + 80.0 * index
    t1 = 300.0 + 220.0 * index
    s = noisy(numpy.abs(a - 2.0 * a * numpy.exp(-ti / t1)))
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
