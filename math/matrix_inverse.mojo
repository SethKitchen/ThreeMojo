# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared wide fallback for small column-major Float32 matrix inverses."""

from std.math import isfinite
from math.matrix_determinant import _determinant_f32


def _inverse_needs_wide[
    size: Int
](entries: Array[Float32, size * size]) -> Bool:
    """Keep degree-four products and their reciprocals in normal range.

    One conservative range serves 2x2 through 4x4 matrices. Zero entries do
    not affect the range. Cancellation in the determinant is checked later.
    """
    comptime assert 2 <= size <= 4
    # A 2x2 through 4x4 matrix always has entries.
    for index in range(size * size):  # pragma: no branch
        var magnitude = abs(entries[index])
        if magnitude != 0 and (magnitude < 1e-8 or magnitude > 1e8):
            return True
    return False


def _determinant_needs_wide(det: Float32, term_magnitude: Float32) -> Bool:
    """Select wider arithmetic without declaring small determinants singular.

    The magnitude sums every unsigned monomial, before cofactor cancellation.
    With entries in the fast-path range, those products are normal Float32.
    The 1e-5 bound exceeds the rounding bound for at most 32 operations
    (unit roundoff 2**-24), including rounding in the magnitude sum itself.
    A failed bound selects exact-sign arithmetic; it never rejects a matrix.
    """
    return (
        not isfinite(det)
        or abs(det) < Float32(1.1754943508222875e-38)
        or abs(det) <= Float32(1e-5) * term_magnitude
    )


def _inverse_nonfinite[
    size: Int
](entries: Array[Float32, size * size]) -> Tuple[
    Bool, Array[Float32, size * size]
]:
    """Preserve the original nonfinite-input propagation and pivot behavior."""
    comptime assert 2 <= size <= 4
    var matrix = Array[Float64, size * size](fill=0)
    var inverse = Array[Float64, size * size](fill=0)
    var result = Array[Float32, size * size](fill=0)
    # The static size assertion guarantees a nonempty matrix.
    for index in range(size * size):  # pragma: no branch
        matrix[index] = Float64(entries[index])
    # Every accepted size has at least two rows.
    for index in range(size):  # pragma: no branch
        inverse[index * size + index] = 1
    for column in range(size):  # pragma: no branch
        var pivot_row = column
        var pivot_magnitude = abs(matrix[column * size + column])
        for row in range(column + 1, size):
            var magnitude = abs(matrix[column * size + row])
            if magnitude > pivot_magnitude:
                pivot_row = row
                pivot_magnitude = magnitude
        if pivot_magnitude == 0:
            return False, result^
        if pivot_row != column:
            # A row always has size entries.
            for at in range(size):  # pragma: no branch
                var first = at * size + column
                var second = at * size + pivot_row
                var saved = matrix[first]
                matrix[first] = matrix[second]
                matrix[second] = saved
                saved = inverse[first]
                inverse[first] = inverse[second]
                inverse[second] = saved
        var pivot = matrix[column * size + column]
        # Eliminate before dividing the pivot row. Equal rows then cancel
        # exactly instead of leaving normalization-rounding residuals.
        for row in range(size):  # pragma: no branch
            if row == column:
                continue
            var factor = matrix[column * size + row] / pivot
            # A row always has size entries.
            for at in range(size):  # pragma: no branch
                matrix[at * size + row] -= factor * matrix[at * size + column]
                inverse[at * size + row] -= factor * inverse[at * size + column]
        # A pivot row always has size entries.
        for at in range(size):  # pragma: no branch
            matrix[at * size + column] /= pivot
            inverse[at * size + column] /= pivot
    # The static size assertion guarantees a nonempty matrix.
    for index in range(size * size):  # pragma: no branch
        result[index] = Float32(inverse[index])
    return True, result^


def _inverse_wide[
    size: Int
](entries: Array[Float32, size * size]) -> Tuple[
    Bool, Array[Float32, size * size]
]:
    """Use exact-sign cofactors for finite inputs; return zeros if singular.

    A rounded elimination pivot can be zero for an invertible matrix, or
    nonzero for a singular one. Evaluate the determinant and each cofactor
    from the original entries instead. The expansion estimates retain the
    exact signs and zeros without a determinant tolerance. All intermediates
    fit Float64; only final inverse entries are narrowed to Float32.
    """
    comptime assert 2 <= size <= 4
    for index in range(size * size):  # pragma: no branch
        if not isfinite(entries[index]):
            return _inverse_nonfinite[size](entries)
    var result = Array[Float32, size * size](fill=0)
    var determinant = _determinant_f32[size](entries)
    if determinant == 0:
        return False, result^
    for column in range(size):  # pragma: no branch
        for row in range(size):  # pragma: no branch
            var minor = Array[Float32, (size - 1) * (size - 1)](fill=0)
            for minor_column in range(size - 1):  # pragma: no branch
                var source_column = minor_column + (
                    1 if minor_column >= row else 0
                )
                for minor_row in range(size - 1):  # pragma: no branch
                    var source_row = minor_row + (
                        1 if minor_row >= column else 0
                    )
                    minor[minor_column * (size - 1) + minor_row] = entries[
                        source_column * size + source_row
                    ]
            var sign = Float64(1) if (row + column) % 2 == 0 else Float64(-1)
            result[column * size + row] = Float32(
                sign * _determinant_f32[size - 1](minor) / determinant
            )
    return True, result^
