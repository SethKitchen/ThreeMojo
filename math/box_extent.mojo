# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact finite extent admission for shrinking Float32 boxes."""


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
