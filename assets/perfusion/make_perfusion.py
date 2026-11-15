# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the deconvolution of synthetic CT and DSC-MRI perfusion curves
by truncated singular value decomposition in numpy and scipy.

    mojo run -I . tools/make_perfusion.mojo
    cd assets/perfusion && python3 make_perfusion.py

Run it with numpy 2.5.4 and scipy 1.18.1. `tools/make_perfusion.mojo`
writes the synthetic curves, `perfusion_data.txt`: the frame step, the
arterial curve, four tissue curves from gray matter to an ischemic core,
and a DSC-MRI signal. This script writes `perfusion_expected.txt`.

The concentration of each curve is its value less the mean of its first
4 frames. The script deconvolves each tissue curve in two ways, with
numpy's pseudo-inverse `pinv`, which drops the singular values at or
below `rcond` of the largest:

- `ssvd`: the lower triangular matrix of Ostergaard and others (1996),
  `A[j, i] = step * Ca[j - i]`, from scipy's `toeplitz`, with `rcond` 0.2.
- `csvd`: the block-circulant matrix of Wu and others (2003), from
  scipy's `circulant`, with both curves padded by zeros to 80 frames and
  `rcond` 0.15.

Each line holds the residue `k = F R(t)` at each frame in 1/s, then the
flow (the largest k), the Tmax (the time of the largest k), and the
volume (the sum of the tissue concentration over that of the artery).
The script checks with numpy's singular values that none is within 1
percent of a threshold, so the choice of the kept values is stable.

A `dsc` line holds the `delta R2*` of the DSC-MRI signal, `-ln(S / S0) /
TE` with an echo time of 30 ms and S0 the mean of the first 4 frames, in
1/s.
"""

import os

import numpy
import scipy.linalg

HERE = os.path.dirname(os.path.abspath(__file__))
BASELINE = 4

rows = {}
tissues = []
with open(os.path.join(HERE, "perfusion_data.txt")) as data:
    for line in data:
        words = line.split()
        if words[0] == "tissue":
            tissues.append(numpy.array([float(v) for v in words[2:]]))
        else:
            rows[words[0]] = numpy.array([float(v) for v in words[1:]])
STEP = float(rows["step"][0])
arterial = rows["arterial"]
FRAMES = len(arterial)


def concentration(curve):
    return curve - curve[:BASELINE].mean()


def deconvolve(matrix, tissue, threshold):
    s = numpy.linalg.svd(matrix, compute_uv=False)
    near = numpy.abs(s / s.max() - threshold)
    assert near.min() > 0.01 * threshold, near.min()
    return numpy.linalg.pinv(matrix, rcond=threshold) @ tissue


ca = concentration(arterial)
lower = STEP * scipy.linalg.toeplitz(ca, numpy.zeros(FRAMES))
padded = numpy.concatenate([ca, numpy.zeros(FRAMES)])
circulant = STEP * scipy.linalg.circulant(padded)


def words(values):
    return " ".join(repr(float(v)) for v in values)


expected = []
for at, curve in enumerate(tissues):
    ct = concentration(curve)
    volume = ct.sum() / ca.sum()
    k = deconvolve(lower, ct, 0.2)
    expected.append("ssvd %d %s" % (at, words(list(k) + [k.max(), STEP * k.argmax(), volume])))
    k = deconvolve(circulant, numpy.concatenate([ct, numpy.zeros(FRAMES)]), 0.15)
    expected.append("csvd %d %s" % (at, words(list(k) + [k.max(), STEP * k.argmax(), volume])))

echo = 0.030
signal = rows["dsc"]
r2 = -numpy.log(signal / signal[:BASELINE].mean()) / echo
expected.append("dsc " + words(r2))

with open(os.path.join(HERE, "perfusion_expected.txt"), "w") as out:
    out.write("\n".join(expected) + "\n")
