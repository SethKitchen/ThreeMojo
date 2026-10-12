# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared wide fallback for small column-major Float32 matrix inverses."""

from std.math import isfinite
from std.memory import bitcast
from std.sys.info import is_apple_gpu
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
    """Invert a matrix whose entries are out of the fast path's range.

    The host and CUDA use exact-sign cofactors in Float64. Apple GPUs have
    no Float64, so a kernel for one uses `_inverse_scaled_float32`.
    """
    comptime chosen = _inverse_scaled_float32[
        size
    ] if is_apple_gpu() else _inverse_exact_cofactors[size]
    return chosen(entries)


def _power_of_two(exponent: Int) -> Float32:
    """Return two to a power from -126 through 127, from its bits."""
    return bitcast[DType.float32](UInt32(exponent + 127) << 23)


def _binade(value: Float32) -> Int:
    """Return floor(log2(abs(value))) for a nonzero value, or -126 for a
    subnormal one, from the exponent bits."""
    return max(-126, Int((bitcast[DType.uint32](value) >> 23) & 0xFF) - 127)


def _inverse_scaled_float32[
    size: Int
](entries: Array[Float32, size * size]) -> Tuple[
    Bool, Array[Float32, size * size]
]:
    """Invert with Float32 alone; return zeros if elimination finds the
    matrix singular.

    Each row, then each column, is divided by a power of two near its
    largest entry. Those divisions are exact, so the scaled matrix has the
    same inverse up to the same powers. Gauss-Jordan elimination with
    partial pivoting inverts it, and the powers are multiplied back. A
    nonfinite entry skips the scaling and propagates as elimination does.

    Unlike the exact cofactors, this decides singularity by a zero pivot,
    so a matrix within rounding of singular can go either way. Apple GPUs
    use it because they have no Float64.

    Parameters:
        size: The matrix's side, two through four.

    Args:
        entries: The matrix, column-major.

    Returns:
        Whether it is invertible, and its inverse or zeros.
    """
    comptime assert 2 <= size <= 4
    var matrix = entries.copy()
    var inverse = Array[Float32, size * size](fill=0)
    var result = Array[Float32, size * size](fill=0)
    var row_shift = Array[Int, size](fill=0)
    var column_shift = Array[Int, size](fill=0)
    var finite = True
    for index in range(size * size):  # pragma: no branch
        finite = finite and isfinite(entries[index])
    if finite:
        for row in range(size):  # pragma: no branch
            var largest = Float32(0)
            for column in range(size):  # pragma: no branch
                largest = max(largest, abs(matrix[column * size + row]))
            if largest == 0:
                return False, result^
            row_shift[row] = _binade(largest)
            var scale = _power_of_two(-row_shift[row])
            for column in range(size):  # pragma: no branch
                matrix[column * size + row] *= scale
        for column in range(size):  # pragma: no branch
            var largest = Float32(0)
            for row in range(size):  # pragma: no branch
                largest = max(largest, abs(matrix[column * size + row]))
            if largest == 0:
                return False, result^
            column_shift[column] = _binade(largest)
            var scale = _power_of_two(-column_shift[column])
            for row in range(size):  # pragma: no branch
                matrix[column * size + row] *= scale
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
        for row in range(size):  # pragma: no branch
            if row == column:
                continue
            var factor = matrix[column * size + row] / pivot
            for at in range(size):  # pragma: no branch
                matrix[at * size + row] -= factor * matrix[at * size + column]
                inverse[at * size + row] -= factor * inverse[at * size + column]
        for at in range(size):  # pragma: no branch
            matrix[at * size + column] /= pivot
            inverse[at * size + column] /= pivot
    # M = R M' C with R and C diagonal powers of two, so M's inverse is
    # C^-1 M'^-1 R^-1: entry (i, j) is M'^-1 (i, j) over 2 ** (c_i + r_j).
    # The shift is at most 252, so two halves keep each power in range.
    for column in range(size):  # pragma: no branch
        for row in range(size):  # pragma: no branch
            var shift = -(column_shift[row] + row_shift[column])
            var half = shift // 2
            result[column * size + row] = (
                inverse[column * size + row] * _power_of_two(half)
            ) * _power_of_two(shift - half)
    return True, result^


def _inverse_exact_cofactors[
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
