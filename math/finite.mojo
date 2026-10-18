# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether a real number is finite and greater than zero.

Every `Float32` value converts exactly to `Float64`, so one test covers
both widths.
"""

from std.math import isfinite


def positive_finite(value: Float64) -> Bool:
    """Return True when `value` is finite and greater than zero.

    Args:
        value: The number. A `Float32` converts exactly.

    Returns:
        Whether it is a positive finite number.
    """
    return isfinite(value) and value > 0
