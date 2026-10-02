# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An exact determinant sign for finite Float32 3x3 matrices."""

from std.math import fma


def _determinant3_f32(entries: Array[Float32, 9]) -> Float64:
    """Return a wide determinant estimate with the exact sign.

    The entries must be finite and column-major. Products of two widened
    Float32 values are exact in Float64. Triple products need up to 72
    bits, so FMA retains both parts. Error-free TwoSum additions keep an
    expansion whose last nonzero component has the exact determinant's
    sign. It is zero if and only if the matrix is exactly singular.
    Every degree-three Float32 product fits the normal Float64 range.
    """
    var a = Float64(entries[0])
    var d = Float64(entries[1])
    var g = Float64(entries[2])
    var b = Float64(entries[3])
    var e = Float64(entries[4])
    var h = Float64(entries[5])
    var c = Float64(entries[6])
    var f = Float64(entries[7])
    var i = Float64(entries[8])
    var left = [a * e, b * f, c * d, -a * f, -b * d, -c * e]
    var right = [i, g, h, h, i, g]
    # Six products contribute two numbers each. A grow-expansion step
    # adds at most one component. Fixed storage also permits device use.
    var expansion = Array[Float64, 12](fill=0)
    var count = 0
    for term in range(6):  # pragma: no branch
        var high = fma(left[term], right[term], Float64(0))
        var low = fma(left[term], right[term], -high)
        for value in [low, high]:  # pragma: no branch
            var parts = Array[Float64, 12](fill=0)
            var part_count = 0
            var total = value
            for index in range(count):
                var part = expansion[index]
                var next = total + part
                var virtual = next - total
                var error = (total - (next - virtual)) + (part - virtual)
                if error != 0:
                    parts[part_count] = error
                    part_count += 1
                total = next
            if total != 0:
                parts[part_count] = total
                part_count += 1
            expansion = parts^
            count = part_count
    if count == 0:
        return 0
    return expansion[count - 1]
