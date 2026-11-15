# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic MRI signals of the diffusion, IVIM and relaxometry
tests.

Run it from the repository root: `mojo run -I . tools/make_mri_signals.mojo`.
Each signal has Rician noise and is a whole number, as a scanner stores
it. It writes three files:

- `assets/diffusion/diffusion_signals.txt`: an `adc_b` line of b-values in
  s/mm^2, then 12 `adc` voxels of `S0 exp(-b ADC)` with a sigma of 8, and
  a `kurtosis_b` line, then 8 `kurtosis` voxels of `S0 exp(-b D + b^2 D^2
  K / 6)`. Each true signal falls up to b = 2000, because `3 / (D K)` is
  above it.
- `assets/diffusion/ivim_signals.txt`: a `b` line, then 8 `voxel` lines of
  `1000 (f exp(-b D*) + (1 - f) exp(-b D))` with a sigma of 4.
- `assets/relaxometry/relaxometry_signals.txt`: a `te` line of echo times
  in ms, then 8 `t2` voxels of `S0 exp(-TE / T2)`, and a `ti` line of
  inversion times, then 8 `t1` voxels of `|A - 2 A exp(-TI / T1)|`, both
  with a sigma of 5.

The scripts `make_diffusion.py`, `make_ivim.py` and `make_relaxometry.py`
beside them then write the fits of numpy and scipy.
"""

from extensions.numerics.elementary import precise_exp
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, numbers, rician, write_text


def _line(name: String, values: List[Float64]) -> String:
    """Return a named line of numbers."""
    return name + " " + numbers(values) + "\n"


def _diffusion(mut noise: Xorshift64) raises:
    """Write the ADC and kurtosis voxels."""
    var adc_b: List[Float64] = [0.0, 50.0, 400.0, 800.0, 1000.0]
    var text = _line("adc_b", adc_b)
    for index in range(12):
        var s0 = 600.0 + 150.0 * Float64(index)
        var adc = 0.5e-3 + 0.22e-3 * Float64(index)
        var s = List[Float64]()
        for b in adc_b:
            s.append(rician(noise, s0 * precise_exp(-b * adc), 8.0))
        text += _line("adc", s)
    var kurtosis_b: List[Float64] = [0.0, 400.0, 800.0, 1200.0, 1600.0, 2000.0]
    text += _line("kurtosis_b", kurtosis_b)
    for index in range(8):
        var s0 = 1200.0 + 100.0 * Float64(index)
        var d = 0.6e-3 + 0.08e-3 * Float64(index)
        var k = 0.5 + 0.08 * Float64(index)
        var s = List[Float64]()
        for b in kurtosis_b:
            var bd = b * d
            s.append(
                rician(noise, s0 * precise_exp(-bd + bd * bd * k / 6.0), 8.0)
            )
        text += _line("kurtosis", s)
    write_text("assets/diffusion/diffusion_signals.txt", text)


def _ivim(mut noise: Xorshift64) raises:
    """Write the IVIM voxels."""
    var b_values: List[Float64] = [
        0.0,
        10.0,
        20.0,
        40.0,
        60.0,
        100.0,
        150.0,
        200.0,
        400.0,
        600.0,
        800.0,
    ]
    var text = _line("b", b_values)
    for index in range(8):
        var d = 0.7e-3 + 0.12e-3 * Float64(index)
        var star = 0.012 + 0.006 * Float64(index)
        var f = 0.06 + 0.03 * Float64(index)
        var s = List[Float64]()
        for b in b_values:
            var clean = 1000.0 * (
                f * precise_exp(-b * star) + (1.0 - f) * precise_exp(-b * d)
            )
            s.append(rician(noise, clean, 4.0))
        text += _line("voxel", s)
    write_text("assets/diffusion/ivim_signals.txt", text)


def _relaxometry(mut noise: Xorshift64) raises:
    """Write the T2 and T1 voxels."""
    var te: List[Float64] = [10.0, 20.0, 30.0, 40.0, 60.0, 80.0, 100.0, 120.0]
    var text = _line("te", te)
    for index in range(8):
        var s0 = 800.0 + 120.0 * Float64(index)
        var t2 = 30.0 + 20.0 * Float64(index)
        var s = List[Float64]()
        for t in te:
            s.append(rician(noise, s0 * precise_exp(-t / t2), 5.0))
        text += _line("t2", s)
    var ti: List[Float64] = [
        50.0,
        150.0,
        300.0,
        600.0,
        1000.0,
        1500.0,
        2500.0,
        4000.0,
    ]
    text += _line("ti", ti)
    for index in range(8):
        var a = 900.0 + 80.0 * Float64(index)
        var t1 = 300.0 + 220.0 * Float64(index)
        var s = List[Float64]()
        for t in ti:
            s.append(
                rician(noise, abs(a - 2.0 * a * precise_exp(-t / t1)), 5.0)
            )
        text += _line("t1", s)
    write_text("assets/relaxometry/relaxometry_signals.txt", text)


def main() raises:
    """Write the three files.

    Raises:
        Error: If a file cannot be written.
    """
    var noise = Xorshift64(SEED)
    _diffusion(noise)
    _ivim(noise)
    _relaxometry(noise)
