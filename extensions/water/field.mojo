# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A square grid of four floats and Clearwater's radix-2 FFT.

Each texel holds two complex numbers, the layout of one `RGBA32F` ocean
texel. The butterfly is the fragment shader `fft`: one stage reads index
`i` and `i + n/2`, and the twiddle sign selects the forward or inverse
transform. A round trip grows by `n` on each axis. Clearwater does not
divide that factor out inside the butterfly.
"""

from extensions.water.resolution import log2_resolution, SpectrumResolution
from std.math import cos, sin


def complex_mul(
    ar: Float32, ai: Float32, br: Float32, bi: Float32
) -> Tuple[Float32, Float32]:
    """Multiply two complex numbers.

    Args:
        ar: Real part of the first factor.
        ai: Imaginary part of the first factor.
        br: Real part of the second factor.
        bi: Imaginary part of the second factor.

    Returns:
        The real part, then the imaginary part.
    """
    return (ar * br - ai * bi, ar * bi + ai * br)


struct ComplexField(Copyable, Movable):
    """`n` by `n` texels, four floats each: two complex pairs."""

    var n: Int
    var samples: List[Float32]

    def __init__(out self, resolution: SpectrumResolution) raises:
        """Allocate a zero grid.

        Args:
            resolution: The side length. It must be a valid spectrum size.

        Raises:
            Error: If `resolution` is not valid.
        """
        var side = resolution.value
        # `log2_resolution` is the validity check. A bad size never allocates.
        _ = log2_resolution(resolution)
        self.n = side
        self.samples = List[Float32](length=side * side * 4, fill=0.0)

    def index(self, x: Int, y: Int) -> Int:
        """Return the first float of texel `(x, y)`.

        Args:
            x: Column, in `0 .. n`.
            y: Row, in `0 .. n`.

        Returns:
            The offset of channel 0.
        """
        return (y * self.n + x) * 4

    def channel(self, x: Int, y: Int, c: Int) -> Float32:
        """Return one channel of one texel.

        Args:
            x: Column.
            y: Row.
            c: Channel, 0 through 3.

        Returns:
            The stored float.
        """
        return self.samples[self.index(x, y) + c]

    def put(mut self, x: Int, y: Int, c: Int, value: Float32):
        """Store one channel of one texel.

        Args:
            x: Column.
            y: Row.
            c: Channel, 0 through 3.
            value: The float to store.
        """
        self.samples[self.index(x, y) + c] = value


def _fft_pass(
    source: ComplexField,
    mut dest: ComplexField,
    p: Int,
    horizontal: Bool,
    sign: Float32,
):
    var n = source.n
    var half = n // 2
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var j = x
            if not horizontal:
                j = y
            var k = j & (p - 1)
            var i = ((j - (j & (2 * p - 1))) >> 1) + k
            var upper = (j & p) != 0
            var ax = i
            var ay = y
            var bx = i + half
            var by = y
            if not horizontal:
                ax = x
                ay = i
                bx = x
                by = i + half
            var a0 = source.channel(ax, ay, 0)
            var a1 = source.channel(ax, ay, 1)
            var a2 = source.channel(ax, ay, 2)
            var a3 = source.channel(ax, ay, 3)
            var b0 = source.channel(bx, by, 0)
            var b1 = source.channel(bx, by, 1)
            var b2 = source.channel(bx, by, 2)
            var b3 = source.channel(bx, by, 3)
            var ang = (
                sign * Float32(3.141592653589793) * Float32(k) / Float32(p)
            )
            var wr = cos(ang)
            var wi = sin(ang)
            var wxy = complex_mul(wr, wi, b0, b1)
            var wzw = complex_mul(wr, wi, b2, b3)
            if upper:
                dest.put(x, y, 0, a0 - wxy[0])
                dest.put(x, y, 1, a1 - wxy[1])
                dest.put(x, y, 2, a2 - wzw[0])
                dest.put(x, y, 3, a3 - wzw[1])
            else:
                dest.put(x, y, 0, a0 + wxy[0])
                dest.put(x, y, 1, a1 + wxy[1])
                dest.put(x, y, 2, a2 + wzw[0])
                dest.put(x, y, 3, a3 + wzw[1])


def fft2(field: ComplexField, sign: Float32) raises -> ComplexField:
    """Run Clearwater's 2D butterfly on both complex pairs.

    Horizontal stages run first, then vertical stages, matching the ocean
    shader. `sign` is `+1` for the ocean and the forward glare transform,
    and `-1` for the inverse glare transform.

    Args:
        field: The source grid. It is not changed.
        sign: `+1` or `-1`. Any other value is a mistake.

    Returns:
        The transformed grid. A later inverse with the opposite sign
        scales every sample by `n * n`.

    Raises:
        Error: If `sign` is not `+1` or `-1`, or the grid is not a valid
            spectrum size.
    """
    if sign != 1.0 and sign != -1.0:
        raise Error("FFT sign must be +1 or -1")
    var resolution = SpectrumResolution(field.n)
    var stages = log2_resolution(resolution)
    var src = field.copy()
    var dst = ComplexField(resolution)
    var ping = 0
    for axis in range(2):  # pragma: no branch
        var horizontal = axis == 0
        for stage in range(stages):  # pragma: no branch
            var p = 1 << stage
            if ping == 0:
                _fft_pass(src, dst, p, horizontal, sign)
            else:
                _fft_pass(dst, src, p, horizontal, sign)
            ping = 1 - ping
    # Two axes and a power-of-two side make an even stage count, so the
    # last butterfly writes back into `src`.
    _ = ping
    return src^
