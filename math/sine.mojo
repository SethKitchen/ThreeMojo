# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sine that the CPU and a GPU kernel compute to the same bits.

three.js's noise is `fract(sin(x) * 43758.5453)`. The multiplier turns a
difference in the last place of the sine into a different noise value. The
host's `sin` is libm, and a kernel's is the device's, and the two differ in
the last place for most arguments. A compiler can also fuse a multiply and
an add into one rounding on one backend and not on the other.

`sin_float32` is Cephes's `sinf`: a three-part Cody-Waite reduction to the
nearest octant, then a polynomial. Every multiply that feeds an add is an
explicit `fma`, which rounds once on both backends. So the CPU and the GPU
give the same bits, and the noise is the same on both. The error against
libm is a few units in the last place. `noise_scale` is the multiply by
43758.5453, written so that no compiler fuses it with the subtraction that
takes the fraction.
"""

from std.math import floor, fma

# Four over pi, and pi over four in three parts whose sum is exact to far
# past a float's precision: Cephes's `FOPI`, `DP1`, `DP2` and `DP3`.
comptime _FOUR_OVER_PI = Float32(1.27323954473516)
comptime _DP1 = Float32(0.78515625)
comptime _DP2 = Float32(2.4187564849853515625e-4)
comptime _DP3 = Float32(3.77489497744594108e-8)


def sin_float32(x: Float32) -> Float32:
    """Return the sine of an angle, Cephes's `sinf`, with the same bits on
    the CPU and a GPU.

    Args:
        x: The angle, in radians. The reduction is exact to a few units in
            the last place below about 8192.

    Returns:
        The sine, from minus one to one. NaN for an infinite angle or NaN.
    """
    if x != x or x - x != 0:
        return x - x
    var sign = Float32(1)
    var a = x
    if a < 0:
        sign = -1
        a = -a
    var octant = Int(a * _FOUR_OVER_PI)
    # An odd octant rounds up to the next even one: the reduction is to
    # the nearest multiple of a quarter turn's half.
    if octant % 2 == 1:
        octant += 1
    var y = Float32(octant)
    octant = octant % 8
    if octant > 3:
        sign = -sign
        octant -= 4
    var z = fma(y, -_DP1, a)
    z = fma(y, -_DP2, z)
    z = fma(y, -_DP3, z)
    var zz = z * z
    var result: Float32
    # The octant is even, so after the fold it is 0 or 2: a quarter turn
    # off, where the cosine's polynomial is the sine.
    if octant == 2:
        var p = fma(
            Float32(2.443315711809948e-5), zz, Float32(-1.388731625493765e-3)
        )
        p = fma(p, zz, Float32(4.166664568298827e-2))
        result = fma(p, zz * zz, fma(Float32(-0.5), zz, Float32(1)))
    else:
        var p = fma(Float32(-1.9515295891e-4), zz, Float32(8.3321608736e-3))
        p = fma(p, zz, Float32(-1.6666654611e-1))
        result = fma(p, zz * z, z)
    return sign * result


def noise_scale(s: Float32) -> Float32:
    """Return `s` times 43758.5453 as one rounded product, so the fraction
    taken of it next is the same on every backend.

    Args:
        s: A sine.

    Returns:
        The product, rounded once.
    """
    return fma(s, Float32(43758.5453), Float32(0))


def fraction(s: Float32) -> Float32:
    """Return GLSL's `fract`: `s` minus its floor.

    Args:
        s: Any finite number.

    Returns:
        A number from zero up to one.
    """
    return s - floor(s)
