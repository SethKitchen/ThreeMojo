# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Uniform Catmull-Rom weights, tension one half.

The point is the weighted sum of the point before the span, the start,
the end, and the point after the span. `math.curve` keeps three.js's
Hermite form of the same spline.
"""

from math.vector3 import Vector3


def _weight_values(t: Float32) -> Tuple[Float32, Float32, Float32, Float32]:
    """Return the four weights at `t`."""
    var t2 = t * t
    var t3 = t2 * t
    return (
        Float32(0.5) * (-t3 + 2 * t2 - t),
        Float32(0.5) * (3 * t3 - 5 * t2 + 2),
        Float32(0.5) * (-3 * t3 + 4 * t2 + t),
        Float32(0.5) * (t3 - t2),
    )


def catmull_rom_weights(t: Float32) -> SIMD[DType.float32, 4]:
    """Return the four uniform Catmull-Rom weights at `t`.

    Args:
        t: How far from the second point to the third, from zero to one.

    Returns:
        The weights of the point before, the start, the end, and the
        point after.
    """
    var w = _weight_values(t)
    return SIMD[DType.float32, 4](w[0], w[1], w[2], w[3])


def catmull_rom_point(
    p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: Float32
) -> Vector3:
    """Return the uniform Catmull-Rom point at `t`.

    Args:
        p0: The point before the span.
        p1: The start of the span.
        p2: The end of the span.
        p3: The point after the span.
        t: How far from `p1` to `p2`, from zero to one.

    Returns:
        `p0 w0 + p1 w1 + p2 w2 + p3 w3`.
    """
    var w = _weight_values(t)
    return p0 * w[0] + p1 * w[1] + p2 * w[2] + p3 * w[3]
