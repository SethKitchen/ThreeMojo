# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write synthetic CT and DSC-MRI perfusion curves, and their deconvolution
by truncated singular value decomposition in numpy and scipy.

    python3 make_perfusion.py

Run it with numpy 2.5.4 and scipy 1.18.1. It writes `perfusion_data.txt`
and `perfusion_expected.txt` beside it.

The scan has 40 frames, 1.5 s apart. The arterial curve is a gamma
variate that peaks at 300 HU of enhancement over 100 HU. Each tissue
curve is the arterial curve convolved with `F exp(-(t - delay) / MTT)`,
on a fine grid of 1/200 of a frame, over 40 HU, with normal noise. The
tissues run from normal gray matter to an ischemic core.

The concentration of each curve is its value less the mean of its first
4 frames. The script deconvolves each tissue curve in two ways:

- `ssvd`: the lower triangular matrix of Ostergaard and others (1996),
  `A[j, i] = step * Ca[j - i]`, with the singular values below 0.2 of
  the largest dropped.
- `csvd`: the block-circulant matrix of Wu and others (2003), with both
  curves padded by zeros to 80 frames, and the singular values below 0.15
  of the largest dropped.

Each line holds the residue `k = F R(t)` at each frame in 1/s, then the
flow (the largest k), the Tmax (the time of the largest k), and the
volume (the sum of the tissue concentration over that of the artery).
The script checks that no singular value is within 1 percent of a
threshold, so the choice of the kept values is stable.

A `dsc` line holds a synthetic DSC-MRI signal with an echo time of 30
ms, and its `delta R2*` of `-ln(S / S0) / TE`, with S0 the mean of the
first 4 frames, in 1/s.
"""

import os

import numpy
import scipy.linalg

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = 40
STEP = 1.5
BASELINE = 4
FINE = 200


def gamma(t, start, alpha, beta):
    s = numpy.clip(t - start, 0, None)
    return s**alpha * numpy.exp(-s / beta)


fine = numpy.arange(FRAMES * FINE) * STEP / FINE
aif_fine = gamma(fine, 6.0, 3.0, 1.5)
aif_fine *= 300.0 / aif_fine.max()
frames = numpy.arange(FRAMES) * STEP
rng = numpy.random.default_rng(1124)
arterial = 100.0 + aif_fine[::FINE] + rng.normal(0, 2.0, FRAMES)

# Gray matter, white matter, a delayed penumbra and an ischemic core:
# CBF in 1/s, MTT and delay in s.
TISSUES = [
    (0.0128, 4.0, 0.0),
    (0.0060, 5.0, 0.5),
    (0.0070, 7.0, 4.0),
    (0.0018, 10.0, 7.5),
]
tissues = []
for flow, mtt, delay in TISSUES:
    residue = numpy.where(fine >= delay, flow * numpy.exp(-(fine - delay) / mtt), 0.0)
    conv = numpy.convolve(aif_fine, residue)[: len(fine)] * (STEP / FINE)
    tissues.append(40.0 + conv[::FINE] + rng.normal(0, 0.5, FRAMES))


def concentration(curve):
    return curve - curve[:BASELINE].mean()


def deconvolve(matrix, tissue, threshold):
    u, s, vt = numpy.linalg.svd(matrix)
    near = numpy.abs(s / s.max() - threshold)
    assert near.min() > 0.01 * threshold, near.min()
    keep = s >= threshold * s.max()
    inverse = (vt[keep].T / s[keep]) @ u[:, keep].T
    return inverse @ tissue


ca = concentration(arterial)
lower = STEP * scipy.linalg.toeplitz(ca, numpy.zeros(FRAMES))
padded = numpy.concatenate([ca, numpy.zeros(FRAMES)])
circulant = STEP * scipy.linalg.circulant(padded)


def words(values):
    return " ".join(repr(float(v)) for v in values)


data = ["step %r" % STEP, "arterial " + words(arterial)]
expected = []
for at, curve in enumerate(tissues):
    data.append("tissue %d %s" % (at, words(curve)))
    ct = concentration(curve)
    volume = ct.sum() / ca.sum()
    k = deconvolve(lower, ct, 0.2)
    expected.append("ssvd %d %s" % (at, words(list(k) + [k.max(), STEP * k.argmax(), volume])))
    k = deconvolve(circulant, numpy.concatenate([ct, numpy.zeros(FRAMES)]), 0.15)
    expected.append("csvd %d %s" % (at, words(list(k) + [k.max(), STEP * k.argmax(), volume])))

echo = 0.030
signal = 500.0 * numpy.exp(-echo * 40.0 * aif_fine[::FINE] / 300.0) + rng.normal(0, 2.0, FRAMES)
r2 = -numpy.log(signal / signal[:BASELINE].mean()) / echo
data.append("dsc " + words(signal))
expected.append("dsc " + words(r2))

with open(os.path.join(HERE, "perfusion_data.txt"), "w") as out:
    out.write("\n".join(data) + "\n")
with open(os.path.join(HERE, "perfusion_expected.txt"), "w") as out:
    out.write("\n".join(expected) + "\n")
