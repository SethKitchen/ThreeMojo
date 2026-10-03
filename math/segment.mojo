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


@fieldwise_init
struct _SegmentMeasure(ImplicitlyCopyable):
    """An interior squared distance, or the identity of a closest endpoint.

    When endpoint is True, at_end selects the caller's end argument and
    distance2 is unused. Otherwise distance2 is the interior estimate and
    at_end is unused. This lets an index evaluate an endpoint with exactly
    the same arithmetic as its node bounds, without a second distance.
    """

    var distance2: Float64
    var endpoint: Bool
    var at_end: Bool


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
) -> _SegmentMeasure:
    """Resolve endpoint signs and interior cross products before cancellation.
    """
    if _difference_dot3(p, a, b, a) <= 0:
        return _SegmentMeasure(0, True, False)
    if _difference_dot3(p, b, a, b) <= 0:
        return _SegmentMeasure(0, True, True)
    var cross = Array[Float64, 3](fill=0)
    var axis = 0
    while axis < 3:
        var j = (axis + 1) % 3
        var k = (axis + 2) % 3
        cross[axis] = _difference_determinant(
            p[j], a[j], b[k], a[k], p[k], a[k], b[j], a[j]
        )
        axis += 1
    return _SegmentMeasure(
        _norm2(cross) / _difference_dot3(b, a, b, a), False, False
    )


def _difference_is_exact_f32(
    a: Float64, b: Float64, difference: Float64
) -> Bool:
    """Certify an exact Float32 difference of two widened Float32 values.

    The difference argument is the Float64 result of b-a. A round trip
    alone is insufficient when a wide subtraction lost a small
    endpoint. With exponent separation at most 28, both 24-bit inputs and
    a possible carry fit in 53 bits, so the wide subtraction is exact first.
    """
    if a == 0 or b == 0:
        return True
    if max(abs(a), abs(b)) > 268435456.0 * min(abs(a), abs(b)):
        return False
    return Float64(Float32(difference)) == difference


@no_inline
def _local_differences_are_exact(
    a: Array[Float64, 3],
    b: Array[Float64, 3],
    p: Array[Float64, 3],
    ab: Array[Float64, 3],
    ap: Array[Float64, 3],
) -> Bool:
    var axis = 0
    while axis < 3:
        if not _difference_is_exact_f32(a[axis], b[axis], ab[axis]):
            return False
        if not _difference_is_exact_f32(a[axis], p[axis], ap[axis]):
            return False
        axis += 1
    return True


@no_inline
def _point_segment_refined(
    a: Array[Float64, 3],
    b: Array[Float64, 3],
    p: Array[Float64, 3],
    ab: Array[Float64, 3],
    ap: Array[Float64, 3],
    len2: Float64,
    dot_a: Float64,
    scale_a: Float64,
    end_dot: Float64,
    end_guard: Float64,
) -> _SegmentMeasure:
    """Use exact local products when certified; otherwise expand coordinates."""
    if not _local_differences_are_exact(a, b, p, ab, ap):
        return _point_segment_exact(a, b, p)
    comptime guard = 1.7763568394002505e-15
    if dot_a <= guard * scale_a:
        if _sum_products[3](ap, ab) <= 0:
            return _SegmentMeasure(0, True, False)
    if end_dot >= -end_guard:
        if (
            _sum_products[6](
                [ap[0], ap[1], ap[2], -ab[0], -ab[1], -ab[2]],
                [ab[0], ab[1], ab[2], ab[0], ab[1], ab[2]],
            )
            >= 0
        ):
            return _SegmentMeasure(0, True, True)
    # Each factor is now an exact Float32 value. Products fit in 48 bits,
    # so their Float64 subtraction has relative error at most u even when
    # nearly canceled. The norm and division remain below the 2^-40 budget.
    var cross = Array[Float64, 3](fill=0)
    var axis = 0
    while axis < 3:
        var j = (axis + 1) % 3
        var k = (axis + 2) % 3
        cross[axis] = ap[j] * ab[k] - ap[k] * ab[j]
        axis += 1
    return _SegmentMeasure(_norm2(cross) / len2, False, False)


def _point_segment_ordered(
    a: Vector3, b: Vector3, p: Vector3
) -> _SegmentMeasure:
    var aa = [Float64(a.x), Float64(a.y), Float64(a.z)]
    var bb = [Float64(b.x), Float64(b.y), Float64(b.z)]
    var pp = [Float64(p.x), Float64(p.y), Float64(p.z)]
    var ab = [bb[0] - aa[0], bb[1] - aa[1], bb[2] - aa[2]]
    var ap = [pp[0] - aa[0], pp[1] - aa[1], pp[2] - aa[2]]
    var len2 = _norm2(ab)
    if len2 == 0:
        return _SegmentMeasure(0, True, False)
    var products = [ap[0] * ab[0], ap[1] * ab[1], ap[2] * ab[2]]
    var dot_a = products[0] + products[1] + products[2]
    var scale_a = abs(products[0]) + abs(products[1]) + abs(products[2])
    # The projection error is below 16u*scale_a, u=2^-53. A zero
    # absolute-product sum certifies an exact zero: no term underflows.
    comptime guard = 1.7763568394002505e-15
    if scale_a == 0 or dot_a < -guard * scale_a:
        return _SegmentMeasure(0, True, False)
    # (p-a).(b-a) - |b-a|^2 equals (p-b).(b-a) exactly. Its rounded
    # form has error below 32u*(scale_a+len2), including subtraction.
    # Ambiguous endpoint differences still use the original polynomials;
    # neither this sign nor an interior foot is inferred from rounded t.
    var end_dot = dot_a - len2
    var end_guard = 2 * guard * (scale_a + len2)
    if end_dot > end_guard:
        return _SegmentMeasure(0, True, True)
    if dot_a > guard * scale_a and end_dot < -end_guard:
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
            return _SegmentMeasure(numerator / len2, False, False)
    return _point_segment_refined(
        aa, bb, pp, ab, ap, len2, dot_a, scale_a, end_dot, end_guard
    )


def _point_segment_measure(
    a: Vector3, b: Vector3, p: Vector3
) -> _SegmentMeasure:
    """Classify the closest feature with canonical endpoint arithmetic.

    Coordinates must be finite Float32 values. Canonical endpoint order
    makes both paths use the same operations after reversal. Neither the
    fast path nor the expansion division promises correctly rounded output.
    """
    var reverse: Bool
    if a.x != b.x:
        reverse = a.x > b.x
    elif a.y != b.y:
        reverse = a.y > b.y
    else:
        reverse = a.z > b.z
    var first = a
    var last = b
    if reverse:
        first = b
        last = a
    var result = _point_segment_ordered(first, last, p)
    result.at_end = result.at_end != reverse
    return result


def _point_segment_distance2(a: Vector3, b: Vector3, p: Vector3) -> Float64:
    """Return a wide squared distance invariant under endpoint reversal.

    Finite Float32 coordinates are required. Endpoint gaps are evaluated
    directly. Interior values use the shared guarded measure.
    """
    var result = _point_segment_measure(a, b, p)
    if result.endpoint:
        var endpoint = a
        if result.at_end:
            endpoint = b
        return _norm2(
            [
                Float64(p.x) - Float64(endpoint.x),
                Float64(p.y) - Float64(endpoint.y),
                Float64(p.z) - Float64(endpoint.z),
            ]
        )
    return result.distance2
