# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Private lane-query predicates layered on the fixed-s distance kernel.

The fixed-s kernel owns exact point ordering and finite-range norm output.
This adapter adds the lane query's strict plan-width and enclosure helpers.
It preserves kernel interval endpoints when a full interval is required.
"""

from extensions.carla.curve_distance import (
    _WORDS,
    _exact_sign,
    _finite_point,
    _normalized_square as _distance_normalized_square,
    _signed_product,
)
from extensions.carla.curve_interval import _Interval
from std.math import inf, isfinite
from std.memory import bitcast


def _normalized_square[
    axes: Int
](
    point: Array[Float64, 3], query: Array[Float64, 3], scale: Float64
) -> _Interval:
    # The conversion preserves both bound endpoints exactly. It performs no
    # new arithmetic and does not tighten or widen the kernel's enclosure.
    var bound = _distance_normalized_square[axes](point, query, scale)
    return _Interval(bound.low, bound.high)


@no_inline
def _exact_plan_width(
    center: Array[Float64, 3], query: Array[Float64, 3], width: Float64
) -> Int:
    # Sign of 4*((cx-qx)^2+(cy-qy)^2)-width^2. Multiplication by four
    # avoids forming a half-width that can underflow for positive widths.
    var positive = Array[UInt64, _WORDS](fill=0)
    var negative = Array[UInt64, _WORDS](fill=0)
    var axis = 0
    while axis < 2:
        _signed_product(
            positive, negative, center[axis], center[axis], 2, False
        )
        _signed_product(positive, negative, center[axis], query[axis], 3, True)
        _signed_product(positive, negative, query[axis], query[axis], 2, False)
        axis += 1
    _signed_product(positive, negative, width, width, 0, True)
    return _exact_sign(positive, negative)


def _wide_plan_contains(
    center: Array[Float64, 3], query: Array[Float64, 3], width: Float64
) raises -> Bool:
    """Apply the strict plan half-width test without narrowing or squaring loss.
    """
    _finite_point(center)
    _finite_point(query)
    if not isfinite(width):
        raise Error("Lane distance comparison needs a finite width")
    if width <= 0.0:
        return False
    var scale = width
    var axis = 0
    while axis < 2:
        scale = max(scale, abs(center[axis] - query[axis]))
        axis += 1
    if isfinite(scale):
        var distance = _normalized_square[2](center, query, scale)
        var diameter = _Interval.point(width) / _Interval.point(scale)
        var difference = _Interval.point(4.0) * distance - diameter.square()
        if difference.high < 0.0:
            return True
        if difference.low >= 0.0:
            return False
    return _exact_plan_width(center, query, width) < 0


def _wide_distance_upper(
    point: Array[Float64, 3], query: Array[Float64, 3]
) raises -> Float64:
    """Bound a stored-point distance without an unscaled squared norm."""
    _finite_point(point)
    _finite_point(query)
    var scale = Float64(0)
    var axis = 0
    while axis < 3:
        scale = max(scale, abs(point[axis] - query[axis]))
        axis += 1
    if scale == 0.0:
        return 0.0
    if not isfinite(scale):
        return inf[DType.float64]()
    var norm = _normalized_square[3](point, query, scale).sqrt()
    return (_Interval.point(scale) * norm).high


def _point_gap_scale(
    point: Array[Float64, 3], query: Array[Float64, 3]
) raises -> Float64:
    # Zero means componentwise coincidence. No square is evaluated here.
    _finite_point(point)
    _finite_point(query)
    var gap = Float64(0)
    var magnitude = Float64(0)
    var axis = 0
    while axis < 3:
        gap = max(gap, abs(point[axis] - query[axis]))
        magnitude = max(magnitude, max(abs(point[axis]), abs(query[axis])))
        axis += 1
    if not isfinite(gap):
        gap = magnitude
    if gap == 0.0:
        return 0.0
    # A power-of-two scale preserves squared-distance ULP units wherever the
    # original square is normal. For subnormals it gives a tighter unit.
    var bits = bitcast[DType.uint64](gap)
    var exponent = bits & UInt64(0x7FF0000000000000)
    if exponent != 0:
        return bitcast[DType.float64](exponent)
    while (bits & (bits - UInt64(1))) != 0:
        bits = bits & (bits - UInt64(1))
    return bitcast[DType.float64](bits)
