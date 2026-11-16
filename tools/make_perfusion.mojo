# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic CT and DSC-MRI perfusion curves of the perfusion
tests.

Run it from the repository root: `mojo run -I . tools/make_perfusion.mojo`.
It writes `assets/perfusion/perfusion_data.txt`.

The scan has 40 frames, 1.5 s apart. The arterial curve is a gamma
variate that peaks at 300 HU of enhancement over 100 HU, with normal
noise of 2 HU. Each tissue curve is the arterial curve convolved with `F
exp(-(t - delay) / MTT)`, on a fine grid of 1/200 of a frame, over 40 HU,
with normal noise of 0.5 HU. The tissues run from normal gray matter to
an ischemic core. A `dsc` line holds a DSC-MRI signal with an echo time
of 30 ms: `500 exp(-TE 40 Ca / 300)` with normal noise of 2.
`assets/perfusion/make_perfusion.py` then writes the deconvolutions of
numpy.
"""

from extensions.numerics.elementary import precise_exp
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, normal, numbers, write_text

comptime FRAMES = 40
comptime STEP = 1.5
comptime FINE = 200


def _gamma(t: Float64) -> Float64:
    """Return the gamma variate `s^3 exp(-s / 1.5)` with s = t - 6, or 0."""
    var s = max(t - 6.0, 0.0)
    return s * s * s * precise_exp(-s / 1.5)


def main() raises:
    """Write the curves.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var dt = STEP / Float64(FINE)
    var count = FRAMES * FINE
    var aif = List[Float64]()
    var peak = 0.0
    for n in range(count):
        aif.append(_gamma(Float64(n) * dt))
        peak = max(peak, aif[n])
    for n in range(count):
        aif[n] *= 300.0 / peak
    var arterial = List[Float64]()
    for j in range(FRAMES):
        arterial.append(100.0 + aif[j * FINE] + normal(noise, 0.0, 2.0))
    var text = String("step ", STEP, "\narterial ", numbers(arterial), "\n")
    # Gray matter, white matter, a delayed penumbra and an ischemic core:
    # CBF in 1/s, MTT and delay in s.
    var flows: List[Float64] = [0.0128, 0.0060, 0.0070, 0.0018]
    var mtts: List[Float64] = [4.0, 5.0, 7.0, 10.0]
    var delays: List[Float64] = [0.0, 0.5, 4.0, 7.5]
    for tissue in range(4):
        var residue = List[Float64]()
        for n in range(count):
            var t = Float64(n) * dt
            residue.append(
                flows[tissue]
                * precise_exp(-(t - delays[tissue]) / mtts[tissue]) if t
                >= delays[tissue] else 0.0
            )
        var curve = List[Float64]()
        for j in range(FRAMES):
            var at = j * FINE
            var sum = 0.0
            for m in range(at + 1):
                sum += aif[m] * residue[at - m]
            curve.append(40.0 + sum * dt + normal(noise, 0.0, 0.5))
        text += String("tissue ", tissue, " ", numbers(curve), "\n")
    var signal = List[Float64]()
    for j in range(FRAMES):
        signal.append(
            500.0 * precise_exp(-0.030 * 40.0 * aif[j * FINE] / 300.0)
            + normal(noise, 0.0, 2.0)
        )
    text += "dsc " + numbers(signal) + "\n"
    write_text("assets/perfusion/perfusion_data.txt", text)
