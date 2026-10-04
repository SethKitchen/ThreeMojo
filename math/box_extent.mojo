# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite Float32 box extents, midpoints and conservative radii."""

from math.matrix_determinant import _sum_products
from std.math import sqrt
from std.memory import bitcast


def _midpoint(low: Float32, high: Float32) -> Float32:
    """Round a midpoint after a sum that cannot overflow for finite inputs."""
    return Float32((Float64(low) + Float64(high)) * 0.5)


def _extent_about_center(
    low: Float32, high: Float32, center: Float32
) -> Float64:
    """Round the maximum endpoint distance from the actual stored center."""
    return max(
        Float64(center) - Float64(low),
        Float64(high) - Float64(center),
    )


def _radius_up(x: Float64, y: Float64, z: Float64) -> Float32:
    """Enclose corners using a proved bound on Float64 rounding.

    Each endpoint subtraction has relative error at most u=2**-53. Three
    squares and two additions therefore give a squared sum no smaller than
    (1-u)**5 times the exact squared corner distance. A correctly rounded
    square root and a final multiplication give a lower bound of
    (1-u)**4.5 times the exact radius. Multiplying by 1+8*u is sufficient:
    (1-u)**4.5*(1+8*u) >= (1-4.5*u)*(1+8*u) > 1.

    All nonzero intermediates are normal finite Float64 values: distances
    between finite Float32 values range from 2**-149 through below 2**129.
    Zero stays exact. The final Float32 conversion rounds outward, and the
    caller handles the finite type limit with an exact corner predicate.
    """
    var squared = x * x + y * y + z * z
    # This is exactly 1+8*u in Float64, not an empirical padding constant.
    var radius = sqrt(squared) * Float64(1.0000000000000009)
    var stored = Float32(radius)
    if Float64(stored) < radius:
        stored = bitcast[DType.float32](bitcast[DType.uint32](stored) + 1)
    return stored


def _max_radius_encloses_box(
    low: Array[Float32, 3],
    high: Array[Float32, 3],
    center: Array[Float32, 3],
) -> Bool:
    """Check the finite Float32 radius limit with exact corner predicates.

    Directed arithmetic can cross the type limit even when the true radius
    fits. For that rare case, expand each squared distance minus the squared
    limit into exact products of stored Float32 values. The shared expansion
    retains their exact sign. No intermediate endpoint difference is rounded.
    This does not clamp an unrepresentable radius: every corner must fit.
    """
    var radius = Float64(bitcast[DType.float32](UInt32(0x7F7FFFFF)))
    var cx = Float64(center[0])
    var cy = Float64(center[1])
    var cz = Float64(center[2])
    # A finite nonempty box has all eight corners; this loop cannot be empty.
    for corner in range(8):  # pragma: no branch
        var x = Float64(low[0] if corner & 1 == 0 else high[0])
        var y = Float64(low[1] if corner & 2 == 0 else high[1])
        var z = Float64(low[2] if corner & 4 == 0 else high[2])
        var left: Array[Float64, 10] = [
            x,
            cx,
            -2 * x,
            y,
            cy,
            -2 * y,
            z,
            cz,
            -2 * z,
            -radius,
        ]
        var right: Array[Float64, 10] = [
            x,
            cx,
            cx,
            y,
            cy,
            cy,
            z,
            cz,
            cz,
            radius,
        ]
        if _sum_products[10](left, right) > 0:
            return False
    return True


def _shrink_exceeds_extent(
    low: Float32, high: Float32, amount: Float32
) -> Bool:
    """Return whether a negative per-face expansion exceeds a finite span.

    Widen before subtracting. TwoSum retains the low part of the span, so
    a tiny endpoint beside a large one cannot disappear at an exact tie.
    Twice a finite Float32 contraction is exact and finite in Float64.
    This predicate does not change nonnegative expansion arithmetic.
    """
    if amount >= 0:
        return False
    var first = Float64(high)
    var second = -Float64(low)
    var width = first + second
    var virtual = width - first
    var low_part = (first - (width - virtual)) + (second - virtual)
    var contraction = -2 * Float64(amount)
    return contraction > width or (contraction == width and low_part < 0)
