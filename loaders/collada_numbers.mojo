# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numbers read from a Collada text.

The geometry reader and the animation reader both read a white-space
separated list, and refuse a value that is not finite as a `Float32`.
Both also refuse a source stride below one.
"""

from std.math import isfinite


def require_positive_stride(stride: Int) raises:
    """Refuse a Collada source stride that is not positive.

    Args:
        stride: How many values one element holds.

    Returns:
        Nothing. The call returns when the stride is at least one.

    Raises:
        Error: If the stride is below one.
    """
    if stride < 1:
        raise Error("Collada: a source's stride must be positive")


def collada_floats(text: String) raises -> List[Float64]:
    """Return the numbers a white-space separated list holds.

    Args:
        text: The list.

    Returns:
        The numbers, in order.

    Raises:
        Error: If one is not a number, or is not finite once it is a
            `Float32`.
    """
    var out = List[Float64]()
    for piece in text.split():
        var field = String(piece)
        var value: Float64
        try:
            value = Float64(field)
        except:
            raise Error("Collada: not a number: " + field)
        if not isfinite(Float32(value)):
            raise Error("Collada: a number must be finite: " + field)
        out.append(value)
    return out^
