# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Lens-diffraction glare.

The star on a glint is the aperture's diffraction pattern, summed over
wavelengths so the spikes carry a faint spectrum. Clearwater convolves the
bright image with that pattern by FFT. The aperture here is the same round
lens, the same six flats, the same scratches and the same dust. On a grid
smaller than the page's 512, scratch widths scale with the grid so they
stay hairlines.
"""

from extensions.water.field import ComplexField, complex_mul, fft2
from extensions.water.random import Mulberry32
from extensions.water.resolution import SpectrumResolution
from std.math import cos, hypot, sin


def aperture_open(dx: Float32, dy: Float32, radius: Float32, n: Int) -> Bool:
    """Return True if one sample misses the iris, the scratches and the dust.

    Args:
        dx: Offset from the aperture center, in texels of a grid of side `n`.
        dy: Offset from the aperture center.
        radius: The round opening, in the same texels.
        n: The grid the original 512-texel scratch widths are scaled to.

    Returns:
        True when the sample is glass, false when metal or dust blocks it.
    """
    if dx * dx + dy * dy > radius * radius:
        return False
    var degrees = Float32(3.141592653589793 / 180.0)
    for k in range(6):  # pragma: no branch
        var angle = (15.0 + Float32(k) * 60.0) * degrees
        if dx * cos(angle) + dy * sin(angle) > radius * 0.955:
            return False
    var scale = Float32(n) / 512.0
    if _on_scratch(dx, dy, radius, scale):
        return False
    if _on_dust(dx, dy, radius):
        return False
    return True


def _on_scratch(
    dx: Float32, dy: Float32, radius: Float32, scale: Float32
) -> Bool:
    var degrees = Float32(3.141592653589793 / 180.0)
    var angles = List[Float32](length=5, fill=0.0)
    var offsets = List[Float32](length=5, fill=0.0)
    var widths = List[Float32](length=5, fill=0.0)
    angles[0] = 21.0 * degrees
    offsets[0] = 0.12 * radius
    widths[0] = 2.2 * scale
    angles[1] = 22.5 * degrees
    offsets[1] = -0.38 * radius
    widths[1] = 1.6 * scale
    angles[2] = 19.0 * degrees
    offsets[2] = 0.55 * radius
    widths[2] = 1.2 * scale
    angles[3] = 152.0 * degrees
    offsets[3] = 0.25 * radius
    widths[3] = 1.0 * scale
    angles[4] = 84.0 * degrees
    offsets[4] = -0.2 * radius
    widths[4] = 0.8 * scale
    for i in range(5):  # pragma: no branch
        var proj = dx * cos(angles[i]) + dy * sin(angles[i]) - offsets[i]
        if proj < 0.0:
            proj = -proj
        if proj < widths[i] * 0.5:
            return True
    return False


def _on_dust(dx: Float32, dy: Float32, radius: Float32) -> Bool:
    var rng = Mulberry32(3)
    for _i in range(7):  # pragma: no branch
        var x = (rng.next_unit() - 0.5) * 1.4 * Float64(radius)
        var y = (rng.next_unit() - 0.5) * 1.4 * Float64(radius)
        var r = (0.015 + 0.03 * rng.next_unit()) * Float64(radius)
        var ddx = Float64(dx) - x
        var ddy = Float64(dy) - y
        if ddx * ddx + ddy * ddy < r * r:
            return True
    return False


struct GlareKernels(Movable):
    """The two complex spectra that multiply the bright image."""

    var red_green: ComplexField
    var blue: ComplexField

    def __init__(out self, var red_green: ComplexField, var blue: ComplexField):
        """Store both spectra.

        Args:
            red_green: Red in the first complex pair, green in the second.
            blue: Blue in the first complex pair.
        """
        self.red_green = red_green^
        self.blue = blue^


def glare_kernels(resolution: SpectrumResolution) raises -> GlareKernels:
    """Build the wavelength-summed aperture and transform it.

    Args:
        resolution: The square grid. 512 matches the page. A frame can use
            a smaller power of two.

    Returns:
        Kernels normalized the way `allocGlare` normalizes them, then
        transformed with the forward butterfly.

    Raises:
        Error: If `resolution` is not valid.
    """
    var n = resolution.value
    var radius = Float32(n) * 0.11
    var spatial = List[Float32](length=n * n * 3, fill=0.0)
    var aperture = List[Float32](length=n * n, fill=0.0)
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var acc = Float32(0.0)
            for sy in range(3):  # pragma: no branch
                for sx in range(3):  # pragma: no branch
                    var dx = (
                        Float32(x)
                        - Float32(n) * 0.5
                        + (Float32(sx) + 0.5) / 3.0
                        - 0.5
                    )
                    var dy = (
                        Float32(y)
                        - Float32(n) * 0.5
                        + (Float32(sy) + 0.5) / 3.0
                        - 0.5
                    )
                    if aperture_open(dx, dy, radius, n):
                        acc += 1.0
            aperture[y * n + x] = acc / 9.0
    var power = _power_spectrum(aperture, resolution)
    _accumulate_wavelengths(power, spatial, n)
    _lift_field(spatial, n)
    _normalize_channels(spatial, n)
    var red_green = ComplexField(resolution)
    var blue = ComplexField(resolution)
    var norm = 1.0 / Float32(n * n)
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var i = (y * n + x) * 3
            red_green.put(x, y, 0, spatial[i] * norm)
            red_green.put(x, y, 2, spatial[i + 1] * norm)
            blue.put(x, y, 0, spatial[i + 2] * norm)
    return GlareKernels(fft2(red_green, 1.0), fft2(blue, 1.0))


def _power_spectrum(
    aperture: List[Float32], resolution: SpectrumResolution
) raises -> List[Float32]:
    var n = resolution.value
    var field = ComplexField(resolution)
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            field.put(x, y, 0, aperture[y * n + x])
    var freq = fft2(field, 1.0)
    var power = List[Float32](length=n * n, fill=0.0)
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var sx = (x + n // 2) % n
            var sy = (y + n // 2) % n
            var re = freq.channel(sx, sy, 0)
            var im = freq.channel(sx, sy, 1)
            power[y * n + x] = re * re + im * im
    return power^


def _accumulate_wavelengths(
    power: List[Float32], mut spatial: List[Float32], n: Int
):
    var bands = List[Float32](length=8 * 4, fill=0.0)
    bands[0] = 440.0
    bands[1] = 0.10
    bands[2] = 0.00
    bands[3] = 0.85
    bands[4] = 470.0
    bands[5] = 0.00
    bands[6] = 0.15
    bands[7] = 1.00
    bands[8] = 500.0
    bands[9] = 0.00
    bands[10] = 0.60
    bands[11] = 0.55
    bands[12] = 530.0
    bands[13] = 0.05
    bands[14] = 1.00
    bands[15] = 0.15
    bands[16] = 560.0
    bands[17] = 0.45
    bands[18] = 0.95
    bands[19] = 0.00
    bands[20] = 590.0
    bands[21] = 0.95
    bands[22] = 0.55
    bands[23] = 0.00
    bands[24] = 620.0
    bands[25] = 1.00
    bands[26] = 0.20
    bands[27] = 0.00
    bands[28] = 650.0
    bands[29] = 0.70
    bands[30] = 0.05
    bands[31] = 0.00
    for band in range(8):  # pragma: no branch
        var lam = bands[band * 4]
        var scale = lam / 550.0
        var wr = bands[band * 4 + 1]
        var wg = bands[band * 4 + 2]
        var wb = bands[band * 4 + 3]
        for y in range(n):  # pragma: no branch
            for x in range(n):  # pragma: no branch
                var u = (
                    Float32(n) * 0.5 + (Float32(x) - Float32(n) * 0.5) / scale
                )
                var v = (
                    Float32(n) * 0.5 + (Float32(y) - Float32(n) * 0.5) / scale
                )
                var sample = _bilinear(power, n, u, v) / (scale * scale)
                var o = (y * n + x) * 3
                spatial[o] += sample * wr
                spatial[o + 1] += sample * wg
                spatial[o + 2] += sample * wb


def _bilinear(power: List[Float32], n: Int, u: Float32, v: Float32) -> Float32:
    if u < 0.0 or v < 0.0 or u >= Float32(n - 1) or v >= Float32(n - 1):
        return 0.0
    var x0 = Int(u)
    var y0 = Int(v)
    var fx = u - Float32(x0)
    var fy = v - Float32(y0)
    var i = y0 * n + x0
    var a = power[i] * (1.0 - fx) + power[i + 1] * fx
    var b = power[i + n] * (1.0 - fx) + power[i + n + 1] * fx
    return a * (1.0 - fy) + b * fy


def _lift_field(mut spatial: List[Float32], n: Int):
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var r = hypot(
                Float32(x) - Float32(n) * 0.5, Float32(y) - Float32(n) * 0.5
            )
            var w = (r - 3.0) / 30.0
            if w < 0.0:
                w = 0.0
            if w > 1.0:
                w = 1.0
            w = 1.0 + 7.0 * w
            var o = (y * n + x) * 3
            spatial[o] *= w
            spatial[o + 1] *= w
            spatial[o + 2] *= w


def _normalize_channels(mut spatial: List[Float32], n: Int):
    var sum_r = Float32(0.0)
    var sum_g = Float32(0.0)
    var sum_b = Float32(0.0)
    for i in range(n * n):  # pragma: no branch
        sum_r += spatial[i * 3]
        sum_g += spatial[i * 3 + 1]
        sum_b += spatial[i * 3 + 2]
    # The round opening always covers the center sample, so each sum is positive.
    for i in range(n * n):  # pragma: no branch
        spatial[i * 3] /= sum_r
        spatial[i * 3 + 1] /= sum_g
        spatial[i * 3 + 2] /= sum_b


def apply_glare(
    bright: List[Float32],
    width: Int,
    height: Int,
    kernels: GlareKernels,
) raises -> List[Float32]:
    """Convolve a bright RGB image with the diffraction kernels.

    Args:
        bright: Row-major RGB, `width * height * 3` floats. Values are the
            thresholded highlights, already scaled by `1e-3` as the page does.
        width: Image width. It must be positive.
        height: Image height. It must be positive.
        kernels: The spectra from `glare_kernels`.

    Returns:
        RGB glare, the page's output before the `1e3` gain, one value per
        input pixel. The gain is applied by the grader.

    Raises:
        Error: If a dimension is not positive, or the image size does not
            match `bright`.
    """
    if width <= 0 or height <= 0:
        raise Error("Glare image dimensions must be positive")
    if len(bright) != width * height * 3:
        raise Error("Glare image length does not match its dimensions")
    var n = kernels.red_green.n
    var image = ComplexField(SpectrumResolution(n))
    var blue_image = ComplexField(SpectrumResolution(n))
    var fit = Float32(n) * 0.75
    var scale = fit / Float32(width)
    var tall = fit / Float32(height)
    if tall < scale:
        scale = tall
    var sw = Int(Float32(width) * scale + 0.5)
    var sh = Int(Float32(height) * scale + 0.5)
    if sw < 1:
        sw = 1
    if sh < 1:
        sh = 1
    for y in range(sh):  # pragma: no branch
        for x in range(sw):  # pragma: no branch
            var u = (Float32(x) + 0.5) / Float32(sw)
            var v = (Float32(y) + 0.5) / Float32(sh)
            # `u` and `v` stay below 1, so the products stay inside the image.
            var ix = Int(u * Float32(width))
            var iy = Int(v * Float32(height))
            var p = (iy * width + ix) * 3
            image.put(x, y, 0, bright[p])
            image.put(x, y, 2, bright[p + 1])
            blue_image.put(x, y, 0, bright[p + 2])
    var freq = fft2(image, -1.0)
    var freq_b = fft2(blue_image, -1.0)
    var mixed = ComplexField(SpectrumResolution(n))
    var mixed_b = ComplexField(SpectrumResolution(n))
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var rg = complex_mul(
                freq.channel(x, y, 0),
                freq.channel(x, y, 1),
                kernels.red_green.channel(x, y, 0),
                kernels.red_green.channel(x, y, 1),
            )
            var g = complex_mul(
                freq.channel(x, y, 2),
                freq.channel(x, y, 3),
                kernels.red_green.channel(x, y, 2),
                kernels.red_green.channel(x, y, 3),
            )
            var b = complex_mul(
                freq_b.channel(x, y, 0),
                freq_b.channel(x, y, 1),
                kernels.blue.channel(x, y, 0),
                kernels.blue.channel(x, y, 1),
            )
            mixed.put(x, y, 0, rg[0])
            mixed.put(x, y, 1, rg[1])
            mixed.put(x, y, 2, g[0])
            mixed.put(x, y, 3, g[1])
            mixed_b.put(x, y, 0, b[0])
            mixed_b.put(x, y, 1, b[1])
    var back = fft2(mixed, 1.0)
    var back_b = fft2(mixed_b, 1.0)
    var out = List[Float32](length=width * height * 3, fill=0.0)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            # The last pixel still maps inside the fitted rectangle.
            var gx = Int(Float32(x) / Float32(width) * Float32(sw))
            var gy = Int(Float32(y) / Float32(height) * Float32(sh))
            var r = back.channel(gx, gy, 0)
            var g = back.channel(gx, gy, 2)
            var b = back_b.channel(gx, gy, 0)
            if r < 0.0:
                r = 0.0
            if g < 0.0:
                g = 0.0
            if b < 0.0:
                b = 0.0
            var p = (y * width + x) * 3
            out[p] = r
            out[p + 1] = g
            out[p + 2] = b
    return out^
