# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write reference fits of diffusion MRI signals with numpy.

    mojo run -I . tools/make_mri_signals.mojo
    cd assets/diffusion && python3 make_diffusion.py > diffusion_expected.txt

Run it with numpy 2.5.4. `tools/make_mri_signals.mojo` writes the
synthetic signals, `diffusion_signals.txt`, with Rician noise of sigma 8.
They are rounded to whole numbers, as a scanner stores them, so that a
32-bit volume holds them exactly. This script fits them.

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



def rows(name):
    with open("diffusion_signals.txt") as data:
        return [numpy.array([float(v) for v in line.split()[1:]])
                for line in data if line.split()[0] == name]


adc_b = rows("adc_b")[0]
print("adc_b", " ".join(repr(float(v)) for v in adc_b))
for s in rows("adc"):
    slope, intercept = numpy.polyfit(adc_b, numpy.log(s), 1)
    fit_s0 = numpy.exp(intercept)
    computed = fit_s0 * numpy.exp(-1500.0 * -slope)
    values = list(s) + [-slope, fit_s0, computed]
    print("adc", " ".join(repr(float(v)) for v in values))

kurtosis_b = rows("kurtosis_b")[0]
print("kurtosis_b", " ".join(repr(float(v)) for v in kurtosis_b))
for s in rows("kurtosis"):
    c2, c1, c0 = numpy.polyfit(kurtosis_b, numpy.log(s), 2)
    fit_d = -c1
    values = list(s) + [fit_d, 6.0 * c2 / (fit_d * fit_d), numpy.exp(c0)]
    print("kurtosis", " ".join(repr(float(v)) for v in values))
