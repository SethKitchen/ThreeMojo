# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact determinant signs for finite small Float32 matrices."""

from std.math import fma


def _sum_products[
    terms: Int
](left: Array[Float64, terms], right: Array[Float64, terms]) -> Float64:
    """Sum exact products as an expansion, then estimate their full magnitude.

    Each input factor is an exact product of one or two finite Float32
    entries. Each product needs at most 96 bits and lies in normal Float64
    range. FMA retains both parts. Error-free TwoSum additions keep their
    exact sum. At most two components per term need fixed storage.
    The last nonzero component determines sign, but division also needs the
    lower components. Sum all of them before returning a wide estimate.
    """
    comptime assert terms > 0
    var expansion = Array[Float64, 2 * terms](fill=0)
    var count = 0
    for term in range(terms):  # pragma: no branch
        var high = fma(left[term], right[term], Float64(0))
        var low = fma(left[term], right[term], -high)
        for value in [low, high]:  # pragma: no branch
            var parts = Array[Float64, 2 * terms](fill=0)
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
    # The most significant component has the exact sign, but cancellation
    # can leave several significant components. Sum them for division.
    var estimate = Float64(0)
    for index in range(count):  # pragma: no branch
        estimate += expansion[index]
    return estimate


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
    return _sum_products[6](left, right)


def _determinant4_f32(entries: Array[Float32, 16]) -> Float64:
    """Return a determinant estimate with exact sign and zero for finite inputs.

    Each term is the product of two exact Float64 products of Float32
    entries. FMA splits that 96-bit product into two exact components.
    All degree-four Float32 products fit the normal Float64 range, from
    2**-596 to below 2**512. TwoSum preserves the exact sum of 24 terms.
    The column-major input must be finite. Fixed storage permits device use.
    """
    var left = Array[Float64, 24](fill=0)
    var right = Array[Float64, 24](fill=0)
    var rows = [
        [0, 1, 2, 3],
        [0, 1, 3, 2],
        [0, 2, 1, 3],
        [0, 2, 3, 1],
        [0, 3, 1, 2],
        [0, 3, 2, 1],
        [1, 0, 2, 3],
        [1, 0, 3, 2],
        [1, 2, 0, 3],
        [1, 2, 3, 0],
        [1, 3, 0, 2],
        [1, 3, 2, 0],
        [2, 0, 1, 3],
        [2, 0, 3, 1],
        [2, 1, 0, 3],
        [2, 1, 3, 0],
        [2, 3, 0, 1],
        [2, 3, 1, 0],
        [3, 0, 1, 2],
        [3, 0, 2, 1],
        [3, 1, 0, 2],
        [3, 1, 2, 0],
        [3, 2, 0, 1],
        [3, 2, 1, 0],
    ]
    var signs = [
        1,
        -1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
    ]
    for term in range(24):  # pragma: no branch
        left[term] = (
            Float64(signs[term])
            * Float64(entries[rows[term][0]])
            * Float64(entries[4 + rows[term][1]])
        )
        right[term] = Float64(entries[8 + rows[term][2]]) * Float64(
            entries[12 + rows[term][3]]
        )
    return _sum_products[24](left, right)


def _determinant_f32[
    size: Int
](entries: Array[Float32, size * size]) -> Float64:
    """Return an exact-sign determinant estimate for finite orders one to four.

    No tolerance classifies a small nonzero determinant as singular.
    Two widened Float32 factors are exact; higher orders use expansions.
    """
    comptime assert 1 <= size <= 4
    # Nested rather than `elif`: the coverage tool reads an `elif` as a run
    # time decision, and in a compile-time chain it is not one.
    comptime if size == 1:
        return Float64(entries[0])
    else:
        comptime if size == 2:
            return Float64(entries[0]) * Float64(entries[3]) - Float64(
                entries[1]
            ) * Float64(entries[2])
        else:
            comptime if size == 3:
                return _determinant3_f32(rebind[Array[Float32, 9]](entries))
            else:
                return _determinant4_f32(rebind[Array[Float32, 16]](entries))
