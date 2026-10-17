# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numbers read from a Collada text.

The geometry reader and the animation reader both read a white-space
separated list, and refuse a value that is not finite as a `Float32`.
Both also refuse a source stride below one.
"""

from loaders.js_text import split_fields
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


def collada_number(field: String) raises -> Float64:
    """Return one Collada number.

    Args:
        field: The text of the number.

    Returns:
        The number.

    Raises:
        Error: If `field` is not a number.
    """
    try:
        return Float64(field)
    except:
        raise Error("Collada: not a number: " + field)


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
    for field in split_fields(text):
        var value = collada_number(field)
        if not isfinite(Float32(value)):
            raise Error("Collada: a number must be finite: " + field)
        out.append(value)
    return out^
