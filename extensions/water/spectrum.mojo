# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clearwater's ocean spectrum and the dispersion that animates it.

The spectrum is a swell, a peak and a capillary tail, spread by the wind
and scaled so the root-mean-square slope is the target. Dispersion is
gravity plus surface tension, quantized so the loop repeats every 60 s of
shader time. The stored conjugate of the opposite wave is Tessendorf's
real-valued height.
"""

from extensions.water.field import ComplexField, complex_mul
from extensions.water.random import Mulberry32
from extensions.water.resolution import SpectrumResolution
from std.math import cos, exp, floor, hypot, log, sin, sqrt
from units.si import SECOND, Duration, Length


def clearwater_patch() -> Length:
    """Return Clearwater's repeating patch size, 4.6 m.

    Returns:
        The patch length `L`.
    """
    return Length(4.6)


def clearwater_depth() -> Length:
    """Return Clearwater's mean water depth, 1.6 m.

    Returns:
        The depth used by refraction and caustics.
    """
    return Length(1.6)


def clearwater_slope() -> Float32:
    """Return the root-mean-square slope the spectrum is scaled to.

    Returns:
        `0.078`, Clearwater's `TARGET_SLOPE`.
    """
    return 0.078


def angular_frequency(wave_number: Float32) -> Float32:
    """Return the quantized angular frequency of one wave.

    Args:
        wave_number: The wave number `k`, in radians per meter. A negative
            value is treated as its magnitude.

    Returns:
        `ω` in radians per second, a multiple of `2π/60`.
    """
    var k = wave_number
    if k < 0.0:
        k = -k
    var w = sqrt(9.81 * k + 7.4e-5 * k * k * k)
    var step = Float32(6.283185307179586 / 60.0)
    return floor(w / step) * step


def _wave_numbers(
    n: Int, x: Int, y: Int, patch: Float32
) -> Tuple[Float32, Float32, Float32]:
    var nx = x
    if x >= n // 2:
        nx = x - n
    var nz = y
    if y >= n // 2:
        nz = y - n
    var kx = Float32(6.283185307179586) * Float32(nx) / patch
    var kz = Float32(6.283185307179586) * Float32(nz) / patch
    return (kx, kz, hypot(kx, kz))


def _power(kx: Float32, kz: Float32, k: Float32) -> Float32:
    if k <= 1e-6:
        return 0.0
    var kp = Float32(6.283185307179586 / 0.62)
    var kcut = Float32(6.283185307179586 / 0.045)
    var lk = log(k / kp)
    var bump = exp(-0.5 * (lk / 0.36) * (lk / 0.36))
    var tail = (
        0.035 * exp(-((kp / k) * (kp / k))) * exp(-((k / kcut) * (k / kcut)))
    )
    var swell_k = Float32(6.283185307179586 / 1.6)
    var ls = log(k / swell_k)
    var swell = 0.35 * exp(-0.5 * (ls / 0.3) * (ls / 0.3))
    var c = (kx * 0.8 + kz * 0.6) / k
    var wind = Float32(1.0)
    if c < 0.0:
        wind = 0.35
    var spread = (0.3 + 0.7 * c * c) * wind
    return (bump + tail + swell) * spread / (k * k * k * k)


def build_spectrum(
    resolution: SpectrumResolution, patch: Length, target_slope: Float32
) raises -> ComplexField:
    """Draw Clearwater's `h0` texture for one patch.

    The generator seed is 7, the same seed as the page. Each texel stores
    `H0(k)` in the first complex pair and the conjugate of `H0(-k)` in the
    second.

    Args:
        resolution: The grid side. 256 matches the page.
        patch: The patch length. It must be positive.
        target_slope: The root-mean-square slope after scaling. It must be
            positive.

    Returns:
        The spectrum grid, before time evolution.

    Raises:
        Error: If the resolution, the patch or the slope is not valid.
    """
    if patch.value <= 0.0:
        raise Error("Ocean patch length must be positive")
    if target_slope <= 0.0:
        raise Error("Ocean target slope must be positive")
    var n = resolution.value
    var re = List[Float32](length=n * n, fill=0.0)
    var im = List[Float32](length=n * n, fill=0.0)
    var rng = Mulberry32(7)
    var s2 = Float32(0.0)
    var length = patch.value
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var waves = _wave_numbers(n, x, y, length)
            var k = waves[2]
            var p = _power(waves[0], waves[1], k)
            var amp = sqrt(p * 0.5)
            var draw_re = Float32(rng.gauss()) * amp
            var draw_im = Float32(rng.gauss()) * amp
            var i = y * n + x
            re[i] = draw_re
            im[i] = draw_im
            s2 += 2.0 * k * k * (draw_re * draw_re + draw_im * draw_im)
    var scale = target_slope / sqrt(s2)
    var field = ComplexField(resolution)
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var i = y * n + x
            var jy = (n - y) % n
            var jx = (n - x) % n
            var j = jy * n + jx
            field.put(x, y, 0, re[i] * scale)
            field.put(x, y, 1, im[i] * scale)
            field.put(x, y, 2, re[j] * scale)
            field.put(x, y, 3, -im[j] * scale)
    return field^


def evolve_spectrum(
    spectrum: ComplexField, patch: Length, time: Duration
) raises -> ComplexField:
    """Advance `H0` to one time and pack height with its slopes.

    Shader time is the `uT` Clearwater passes, already scaled by 0.9 at
    the call site when the clock is the frame clock. At time zero the
    height is `H0(k) + conj(H0(-k))`.

    The first complex pair is height plus `i` times `∂h/∂x`. The second
    pair's real part is `∂h/∂z`. That is the packing in the spectrum shader.

    Args:
        spectrum: The `h0` grid from `build_spectrum`.
        patch: The patch length used to build it. It must be positive.
        time: Shader time, in seconds. A negative time plays backward.

    Returns:
        The frequency-domain grid the FFT turns into a surface.

    Raises:
        Error: If `patch` is not positive, or the grid size is not valid.
    """
    if patch.value <= 0.0:
        raise Error("Ocean patch length must be positive")
    var resolution = SpectrumResolution(spectrum.n)
    var out = ComplexField(resolution)
    var length = patch.value
    var t = time.value
    for y in range(spectrum.n):  # pragma: no branch
        for x in range(spectrum.n):  # pragma: no branch
            var waves = _wave_numbers(spectrum.n, x, y, length)
            var kx = waves[0]
            var kz = waves[1]
            var w = angular_frequency(waves[2])
            var c = cos(w * t)
            var sn = sin(w * t)
            var h_pos = complex_mul(
                spectrum.channel(x, y, 0),
                spectrum.channel(x, y, 1),
                c,
                sn,
            )
            var h_neg = complex_mul(
                spectrum.channel(x, y, 2),
                spectrum.channel(x, y, 3),
                c,
                -sn,
            )
            var hr = h_pos[0] + h_neg[0]
            var hi = h_pos[1] + h_neg[1]
            # H * (1 - kx) packs h + i * ∂h/∂x. i * kz * H is ∂h/∂z.
            out.put(x, y, 0, hr - kx * hr)
            out.put(x, y, 1, hi - kx * hi)
            out.put(x, y, 2, -kz * hi)
            out.put(x, y, 3, kz * hr)
    return out^
