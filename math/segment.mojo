# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wide point-segment distances for finite Float32 coordinates.

The adaptive path uses rounded differences only when their error bounds
resolve endpoint classification and bound cancellation in the cross product.
The fallback expands the original coordinates before subtracting them.
It preserves small endpoint gaps, including an interior foot near an end.
The returned distance is a Float64 estimate, not an exact rational number.
"""

from math.matrix_determinant import _sum_products
from math.vector3 import Vector3


def _difference_dot3(
    a: Array[Float64, 3],
    b: Array[Float64, 3],
    c: Array[Float64, 3],
    d: Array[Float64, 3],
) -> Float64:
    """Estimate (a-b).(c-d) with its exact sign for widened Float32 inputs."""
    var left = Array[Float64, 12](fill=0)
    var right = Array[Float64, 12](fill=0)
    var axis = 0
    while axis < 3:
        left[4 * axis] = a[axis]
        right[4 * axis] = c[axis]
        left[4 * axis + 1] = -a[axis]
        right[4 * axis + 1] = d[axis]
        left[4 * axis + 2] = -b[axis]
        right[4 * axis + 2] = c[axis]
        left[4 * axis + 3] = b[axis]
        right[4 * axis + 3] = d[axis]
        axis += 1
    return _sum_products[12](left, right)


@no_inline
def _difference_determinant(
    a: Float64,
    b: Float64,
    c: Float64,
    d: Float64,
    e: Float64,
    f: Float64,
    g: Float64,
    h: Float64,
) -> Float64:
    """Estimate (a-b)(c-d)-(e-f)(g-h), retaining the exact sign.

    Factors are widened finite Float32 values, possibly negated. Degree-two
    products and their residuals fit normal Float64, including subnormals.
    """
    return _sum_products[8](
        [a, -a, -b, b, -e, e, f, -f],
        [c, d, c, d, g, h, g, h],
    )


def _norm2(v: Array[Float64, 3]) -> Float64:
    return v[0] * v[0] + v[1] * v[1] + v[2] * v[2]


@no_inline
def _point_segment_exact(
    a: Array[Float64, 3],
    b: Array[Float64, 3],
    p: Array[Float64, 3],
    ap: Array[Float64, 3],
    bp: Array[Float64, 3],
) -> Float64:
    """Resolve endpoint signs and interior cross products before cancellation.
    """
    if _difference_dot3(p, a, b, a) <= 0:
        return _norm2(ap)
    if _difference_dot3(p, b, a, b) <= 0:
        return _norm2(bp)
    var cross = Array[Float64, 3](fill=0)
    var axis = 0
    while axis < 3:
        var j = (axis + 1) % 3
        var k = (axis + 2) % 3
        cross[axis] = _difference_determinant(
            p[j], a[j], b[k], a[k], p[k], a[k], b[j], a[j]
        )
        axis += 1
    return _norm2(cross) / _difference_dot3(b, a, b, a)


def _point_segment_ordered(a: Vector3, b: Vector3, p: Vector3) -> Float64:
    var aa = [Float64(a.x), Float64(a.y), Float64(a.z)]
    var bb = [Float64(b.x), Float64(b.y), Float64(b.z)]
    var pp = [Float64(p.x), Float64(p.y), Float64(p.z)]
    var ab = Array[Float64, 3](fill=0)
    var ap = Array[Float64, 3](fill=0)
    var bp = Array[Float64, 3](fill=0)
    var dot_a = Float64(0)
    var dot_b = Float64(0)
    var scale_a = Float64(0)
    var scale_b = Float64(0)
    var axis = 0
    while axis < 3:
        ab[axis] = bb[axis] - aa[axis]
        ap[axis] = pp[axis] - aa[axis]
        bp[axis] = pp[axis] - bb[axis]
        var product_a = ap[axis] * ab[axis]
        var product_b = bp[axis] * ab[axis]
        dot_a += product_a
        dot_b += product_b
        scale_a += abs(product_a)
        scale_b += abs(product_b)
        axis += 1
    var len2 = _norm2(ab)
    if len2 == 0:
        return _norm2(ap)
    # u=2^-53. Each difference is rounded at most once; each product and
    # three-term sum adds at most three roundings. 16u times the computed
    # absolute-product sum bounds the dot error, with room for its rounding.
    comptime guard = 1.7763568394002505e-15
    if dot_a < -guard * scale_a:
        return _norm2(ap)
    if dot_b > guard * scale_b:
        return _norm2(bp)
    if dot_a > guard * scale_a and dot_b < -guard * scale_b:
        var cross = Array[Float64, 3](fill=0)
        var scale = Array[Float64, 3](fill=0)
        var axis = 0
        while axis < 3:
            var j = (axis + 1) % 3
            var k = (axis + 2) % 3
            var left = ap[j] * ab[k]
            var right = ap[k] * ab[j]
            cross[axis] = left - right
            scale[axis] = abs(left) + abs(right)
            axis += 1
        var numerator = _norm2(cross)
        var magnitude = _norm2(scale)
        # The cross-vector error is at most 16u*norm(scale). This guard
        # bounds it relative to norm(cross) by 1025u. Squaring, the norm
        # sums and division keep the relative distance error below 2^-40.
        # A zero scale has only zero products and needs no expansion.
        if numerator >= 0.000244140625 * magnitude:
            return numerator / len2
    return _point_segment_exact(aa, bb, pp, ap, bp)


def _point_segment_distance2(a: Vector3, b: Vector3, p: Vector3) -> Float64:
    """Return a wide squared distance invariant under endpoint reversal.

    Coordinates must be finite Float32 values. Canonical endpoint order
    makes both paths use the same operations after reversal. Neither the
    fast path nor the expansion division promises correctly rounded output.
    """
    if a.x != b.x:
        if a.x > b.x:
            return _point_segment_ordered(b, a, p)
    elif a.y != b.y:
        if a.y > b.y:
            return _point_segment_ordered(b, a, p)
    elif a.z > b.z:
        return _point_segment_ordered(b, a, p)
    return _point_segment_ordered(a, b, p)
