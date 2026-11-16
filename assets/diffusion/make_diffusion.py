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
- Each `adc` line holds the signals of one voxel, then the slope and the
  intercept of `numpy.polyfit` of ln S on b, of degree 1.
- `kurtosis_b` holds the b-values of the kurtosis voxels.
- Each `kurtosis` line holds the signals, then the coefficients of b^2, b
  and 1 of `numpy.polyfit` of ln S on b, of degree 2. Each true signal
  falls up to b = 2000 s/mm^2, because `3 / (D K)` is above it.

The test finds the ADC, D, K and S0 from the coefficients, by
`ln S = ln S0 - b D + b^2 D^2 K / 6`.
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
    print("adc", " ".join(repr(float(v)) for v in list(s) + [slope, intercept]))

kurtosis_b = rows("kurtosis_b")[0]
print("kurtosis_b", " ".join(repr(float(v)) for v in kurtosis_b))
for s in rows("kurtosis"):
    values = list(s) + list(numpy.polyfit(kurtosis_b, numpy.log(s), 2))
    print("kurtosis", " ".join(repr(float(v)) for v in values))
