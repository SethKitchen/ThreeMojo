# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write segmented IVIM fits of synthetic signals with numpy and scipy.

    python3 make_ivim.py > ivim_expected.txt

Run it with numpy 2.5.4 and scipy 1.18.1. The model of intravoxel
incoherent motion is

    S(b) = S0 (f exp(-b D*) + (1 - f) exp(-b D))

The signals are synthetic, with Rician noise of sigma 4, rounded to whole
numbers. The fit is segmented:

1. D and the intercept come from `numpy.polyfit` of ln S on b, over the
   b-values of 200 s/mm^2 or more.
2. f is 1 less the intercept over the signal at b = 0.
3. D* minimizes the sum of squares of the model over the b-values below
   200, with D, f and S0 held. scipy's bounded `minimize_scalar` searches
   ln D* from ln 3e-3 to ln 0.5 mm^2/s, to 1e-14.

`b` holds the b-values in s/mm^2. Each `voxel` line holds the signals,
then D and D* in mm^2/s, and f.
"""

import numpy
from scipy.optimize import minimize_scalar

generator = numpy.random.default_rng(20261115)
b = numpy.array([0.0, 10.0, 20.0, 40.0, 60.0, 100.0, 150.0, 200.0, 400.0, 600.0, 800.0])
print("b", " ".join(repr(float(v)) for v in b))
high = b >= 200.0
low = ~high
for index in range(8):
    d = 0.7e-3 + 0.12e-3 * index
    star = 0.012 + 0.006 * index
    f = 0.06 + 0.03 * index
    clean = 1000.0 * (f * numpy.exp(-b * star) + (1.0 - f) * numpy.exp(-b * d))
    noise = generator.normal(0.0, 4.0, size=(2, len(b)))
    s = numpy.maximum(numpy.rint(numpy.hypot(clean + noise[0], noise[1])), 1.0)
    slope, intercept = numpy.polyfit(b[high], numpy.log(s[high]), 1)
    fit_d = -slope
    fraction = 1.0 - numpy.exp(intercept) / s[0]

    def cost(log_star):
        model = s[0] * (fraction * numpy.exp(-b[low] * numpy.exp(log_star))
                        + (1.0 - fraction) * numpy.exp(-b[low] * fit_d))
        return numpy.sum((model - s[low]) ** 2)

    best = minimize_scalar(
        cost, bounds=(numpy.log(3e-3), numpy.log(0.5)), method="bounded",
        options={"xatol": 1e-14, "maxiter": 2000},
    )
    print("voxel", " ".join(repr(float(v)) for v in list(s) + [fit_d, numpy.exp(best.x), fraction]))
