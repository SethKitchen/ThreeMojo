# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""3 by 3 matrices of Float64 in SIMD lanes, and their inverse by
cofactors.

A `Matrix3x3` holds a matrix in row-major order in the first 9 of 16
lanes. `determinant3(a)` gives its determinant and `adjugate3(a)` its
adjugate, the transpose of its cofactors. The inverse is the adjugate
over the determinant, so a caller tests the determinant first and keeps
its own message for a singular matrix.
"""

comptime Matrix3x3 = SIMD[DType.float64, 16]
"""A 3 by 3 matrix in row-major order, in the first 9 lanes."""


def determinant3(a: Matrix3x3) -> Float64:
    """Return the determinant of a 3 by 3 matrix, along its first row.

    Args:
        a: The matrix, in the first 9 lanes, row-major.

    Returns:
        `a0 (a4 a8 - a5 a7) - a1 (a3 a8 - a5 a6) + a2 (a3 a7 - a4 a6)`.
    """
    return (
        a[0] * (a[4] * a[8] - a[5] * a[7])
        - a[1] * (a[3] * a[8] - a[5] * a[6])
        + a[2] * (a[3] * a[7] - a[4] * a[6])
    )


def adjugate3(a: Matrix3x3) -> Matrix3x3:
    """Return the adjugate of a 3 by 3 matrix.

    Args:
        a: The matrix, in the first 9 lanes, row-major.

    Returns:
        The transpose of the cofactors, in the same layout. Over the
        determinant, it is the inverse. The other lanes are 0.
    """
    var out = Matrix3x3(0)
    out[0] = a[4] * a[8] - a[5] * a[7]
    out[1] = a[2] * a[7] - a[1] * a[8]
    out[2] = a[1] * a[5] - a[2] * a[4]
    out[3] = a[5] * a[6] - a[3] * a[8]
    out[4] = a[0] * a[8] - a[2] * a[6]
    out[5] = a[2] * a[3] - a[0] * a[5]
    out[6] = a[3] * a[7] - a[4] * a[6]
    out[7] = a[1] * a[6] - a[0] * a[7]
    out[8] = a[0] * a[4] - a[1] * a[3]
    return out
