# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Independent rational Sum2 bound for materialized Float64 terms.

The formula requires nearest rounding, gradual underflow, no reassociation,
and no intermediate overflow. It is not a production interval interpreter.
"""
from fractions import Fraction as F
U = F(1, 2**53)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sum2_error(magnitude, inherited, count):
    """Exact-rational independent bound; refuse outside the reviewed range.

    M bounds sum(abs(rounded term)); E bounds sum of inherited term errors.
    Zero-start makes the first update exact. Count one therefore has no
    accumulation error, including the final addition to zero correction.
    """
    require(type(count) is int and 1 <= count <= 2**30, 'unsupported Sum2 count')
    magnitude, inherited = F(magnitude), F(inherited)
    require(0 <= magnitude <= 2**900 and inherited >= 0, 'unsupported Sum2 majorant')
    if magnitude == 0 or count == 1:
        return inherited
    nu = (count - 1) * U
    require(nu < 1, 'nonpositive Sum2 gamma denominator')
    gamma = nu / (1 - nu)
    return inherited + (U + gamma * gamma) * magnitude
