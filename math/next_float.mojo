# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The next greater binary64.

Both signs of zero step to the smallest positive subnormal.
"""

from std.memory import bitcast


def next_binary64_up(value: Float64) -> Float64:
    """Return the adjacent greater binary64, including subnormal values.

    Args:
        value: A finite number. Zero, of either sign, steps to the
            smallest positive subnormal.

    Returns:
        The next greater value.
    """
    if value == 0:
        return bitcast[DType.float64](UInt64(1))
    var bits = bitcast[DType.uint64](value)
    return bitcast[DType.float64](bits + 1 if value > 0 else bits - 1)
