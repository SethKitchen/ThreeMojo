# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write reference fits of diffusion MRI signals with numpy.

    python3 make_diffusion.py > diffusion_expected.txt

Run it with numpy 2.5.4. The signals are synthetic and have Rician noise of
sigma 8 from a seeded generator. They are rounded to whole numbers, as a
scanner stores them, so that a 32-bit volume holds them exactly.

- `adc_b` holds the b-values of the ADC voxels, in s/mm^2.
- Each `adc` line holds the signals of one voxel, then the ADC in mm^2/s,
  S0, and the computed signal at b = 1500 s/mm^2. The fit is
  `numpy.polyfit` of ln S on b, of degree 1.
- `kurtosis_b` holds the b-values of the kurtosis voxels.
- Each `kurtosis` line holds the signals, then D in mm^2/s, K and S0. The
  fit is `numpy.polyfit` of ln S on b, of degree 2:
  `ln S = ln S0 - b D + b^2 D^2 K / 6`. Each true signal falls up to
  b = 2000 s/mm^2, because `3 / (D K)` is above it.
"""

import numpy

generator = numpy.random.default_rng(20261115)


def signals(b, s0, signal):
    noise = generator.normal(0.0, 8.0, size=(2, len(b)))
    raw = numpy.hypot(signal + noise[0], noise[1])
    return numpy.maximum(numpy.rint(raw), 1.0)


adc_b = numpy.array([0.0, 50.0, 400.0, 800.0, 1000.0])
print("adc_b", " ".join(repr(float(v)) for v in adc_b))
for index in range(12):
    s0 = 600.0 + 150.0 * index
    adc = 0.5e-3 + 0.22e-3 * index
    s = signals(adc_b, s0, s0 * numpy.exp(-adc_b * adc))
    slope, intercept = numpy.polyfit(adc_b, numpy.log(s), 1)
    fit_s0 = numpy.exp(intercept)
    computed = fit_s0 * numpy.exp(-1500.0 * -slope)
    values = list(s) + [-slope, fit_s0, computed]
    print("adc", " ".join(repr(float(v)) for v in values))

kurtosis_b = numpy.array([0.0, 400.0, 800.0, 1200.0, 1600.0, 2000.0])
print("kurtosis_b", " ".join(repr(float(v)) for v in kurtosis_b))
for index in range(8):
    s0 = 1200.0 + 100.0 * index
    d = 0.6e-3 + 0.08e-3 * index
    k = 0.5 + 0.08 * index
    bd = kurtosis_b * d
    s = signals(kurtosis_b, s0, s0 * numpy.exp(-bd + bd * bd * k / 6.0))
    c2, c1, c0 = numpy.polyfit(kurtosis_b, numpy.log(s), 2)
    fit_d = -c1
    values = list(s) + [fit_d, 6.0 * c2 / (fit_d * fit_d), numpy.exp(c0)]
    print("kurtosis", " ".join(repr(float(v)) for v in values))
