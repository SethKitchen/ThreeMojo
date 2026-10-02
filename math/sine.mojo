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
nearest octant for ordinary inputs, then a polynomial. Large angles use
an integer reduction before the same polynomial. Every multiply that
feeds an add is an explicit `fma`, which rounds once on both backends. So the CPU and the GPU
give the same bits, and the noise is the same on both. The error against
libm is a few units in the last place. `noise_scale` is the multiply by
43758.5453, written so that no compiler fuses it with the subtraction that
takes the fraction.
"""

from std.math import floor, fma
from std.memory import bitcast

# Four over pi, and pi over four in three parts whose sum is exact to far
# past a float's precision: Cephes's `FOPI`, `DP1`, `DP2` and `DP3`.
comptime _FOUR_OVER_PI = Float32(1.27323954473516)
comptime _DP1 = Float32(0.78515625)
comptime _DP2 = Float32(2.4187564849853515625e-4)
comptime _DP3 = Float32(3.77489497744594108e-8)


def _reduction_word(words: Array[UInt32, 9], start: Int) -> UInt32:
    """Read 32 product bits starting at a nonnegative bit offset."""
    var index = start // 32
    var shift = start % 32
    var word = words[index] >> UInt32(shift)
    if shift != 0 and index < 8:
        word |= words[index + 1] << UInt32(32 - shift)
    return word


def _complement_fraction(upper: UInt32, lower: UInt32) -> Tuple[UInt32, UInt32]:
    """Return the two's complement of a 64-bit fraction stored in two words.

    Args:
        upper: The most significant 32 bits.
        lower: The least significant 32 bits.

    Returns:
        The high and low words of the negated unsigned value.
    """
    var complement = UInt64(0) - ((UInt64(upper) << 32) | UInt64(lower))
    return (UInt32(complement >> 32), UInt32(complement & 0xFFFFFFFF))


def _large_reduction(a: Float32) -> Tuple[Int, Float32]:
    """Reduce a finite positive angle above 8192 with integer arithmetic.

    Multiply its exact 24-bit significand by floor(2/pi * 2^256).
    At the largest Float32 exponent the discarded constant tail changes
    the product by less than 2^-128. Read the quadrant and 64 fractional
    bits around the binary point, then convert only that small remainder.
    """
    var bits = bitcast[DType.uint32](a)
    var exponent = Int((bits >> 23) & 255) - 127
    var mantissa = UInt64((bits & 0x7FFFFF) | 0x800000)
    # Little-endian 32-bit limbs of floor(2/pi * 2^256).
    var two_over_pi: Array[UInt32, 8] = [
        0xDEBBC561,
        0xFE5163AB,
        0x3C439041,
        0xDB629599,
        0xF534DDC0,
        0xFC2757D1,
        0x4E441529,
        0xA2F9836E,
    ]
    var product = Array[UInt32, 9](fill=0)
    var carry = UInt64(0)
    # The reduction constant always has eight limbs.
    for i in range(8):  # pragma: no branch
        var term = UInt64(two_over_pi[i]) * mantissa + carry
        product[i] = UInt32(term & 0xFFFFFFFF)
        carry = term >> 32
    product[8] = UInt32(carry)
    # a = mantissa * 2^(exponent - 23); the constant has 256 fractional
    # bits, so the product's binary point is at 256 + 23 - exponent.
    var point = 279 - exponent
    var quadrant = Int(_reduction_word(product, point) & 3)
    var upper = _reduction_word(product, point - 32)
    var lower = _reduction_word(product, point - 64)
    # Choose the next quadrant at a half. Exact nonzero binary angles
    # cannot be halfway between multiples of pi/2; either side at a
    # rounded midpoint also stays in the polynomial's [-pi/4, pi/4] range.
    var negative = upper >= 0x80000000
    if negative:
        # Form the distance below the next integer without subtracting
        # nearly equal floats. The two's complement keeps all 64 bits.
        var complement = _complement_fraction(upper, lower)
        upper = complement[0]
        lower = complement[1]
        quadrant = (quadrant + 1) & 3
    var fraction = fma(
        Float32(upper),
        Float32(2.3283064365386962890625e-10),
        Float32(lower) * Float32(5.4210108624275221700372640043497e-20),
    )
    if negative:
        fraction = -fraction
    var remainder = fma(
        fraction,
        Float32(1.5707962512969970703125),
        fraction * Float32(7.54978941586159635335e-8),
    )
    return (quadrant, remainder)


def sin_float32(x: Float32) -> Float32:
    """Return the sine of an angle, Cephes's `sinf`, with the same bits on
    the CPU and a GPU.

    Args:
        x: The angle, in radians. All finite Float32 angles are supported.

    Returns:
        The sine, from minus one to one. NaN for an infinite angle or NaN.
    """
    if x != x or x - x != 0:
        return x - x
    if x == 0:
        return x
    var sign = Float32(1)
    var a = x
    if a < 0:
        sign = -1
        a = -a
    var octant: Int
    var z: Float32
    if a <= 8192:
        octant = Int(a * _FOUR_OVER_PI)
        # Keep the existing Cody-Waite path for ordinary noise inputs.
        if octant % 2 == 1:
            octant += 1
        var y = Float32(octant)
        octant = octant % 8
        z = fma(y, -_DP1, a)
        z = fma(y, -_DP2, z)
        z = fma(y, -_DP3, z)
    else:
        var reduced = _large_reduction(a)
        octant = reduced[0] * 2
        z = reduced[1]
    if octant > 3:
        sign = -sign
        octant -= 4
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
