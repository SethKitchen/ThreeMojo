# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The arc tangent, written out so that a GPU kernel can call it.

`std.math.atan` and `std.math.atan2` call libm, and a GPU target has no
libm. On an NVIDIA card before sm_80, `atan2` compiles to a call that
ptxas cannot resolve, and `atan` does not compile for a GPU at all. So a
function a kernel calls must use these: the node library, a panorama's
`equirect_uv`, the kaleidoscope and the square halftone. They are
Cephes's `atanf` and the quadrant rule of `atan2`, in plain arithmetic.
The CPU and the GPU both call them, so they agree by construction, as
with `math.smoothstep`.
"""


def atan_float32(x: Float32) -> Float32:
    """Return the arc tangent of one number, Cephes's `atanf`.

    The argument is folded to below tan(pi / 8), and a polynomial is used
    there. The error is a few units in the last place.

    Args:
        x: Any number.

    Returns:
        The angle, in radians, from minus a half pi to a half pi.
    """
    var sign = Float32(1)
    var a = x
    if a < 0:
        sign = -1
        a = -a
    var offset = Float32(0)
    if a > 2.414213562373095:
        offset = Float32(1.5707963267948966)
        a = -1 / a
    elif a > 0.41421356237309503:
        offset = Float32(0.7853981633974483)
        a = (a - 1) / (a + 1)
    var z = a * a
    var y = (
        (
            (Float32(8.05374449538e-2) * z - Float32(1.38776856032e-1)) * z
            + Float32(1.99777106478e-1)
        )
        * z
        - Float32(3.33329491539e-1)
    ) * z * a + a
    return sign * (offset + y)


def atan2_float32(y: Float32, x: Float32) -> Float32:
    """Return the angle of the point `(x, y)`, as `atan2` gives it.

    Args:
        y: The point's second coordinate.
        x: The point's first coordinate.

    Returns:
        The angle from the positive x axis, in radians, from minus pi to
        pi. Zero for the origin, and NaN when either coordinate is NaN.
    """
    if x != x or y != y:
        return x + y
    if x > 0:
        return atan_float32(y / x)
    if x < 0:
        return atan_float32(y / x) + Float32(
            3.141592653589793 if y >= 0 else -3.141592653589793
        )
    if y > 0:
        return Float32(1.5707963267948966)
    if y < 0:
        return Float32(-1.5707963267948966)
    return 0
