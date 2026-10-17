# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether a real number is finite and greater than zero.

Every `Float32` value converts exactly to `Float64`, so one test covers
both widths. `require_positive_finite` refuses a value that is not.
`require_finite_group` refuses a caller-tested group that is not finite.
Callers keep their own error text.
"""

from std.math import isfinite


def require_positive_tolerance(value: Float64) raises:
    """Refuse a tolerance that is not positive and finite.

    Args:
        value: The tolerance. A `Float32` converts exactly.

    Returns:
        Nothing. The call returns when the tolerance is positive and finite.

    Raises:
        Error: If the tolerance is not positive and finite.
    """
    require_positive_finite(value, "A tolerance must be positive and finite")


def positive_finite(value: Float64) -> Bool:
    """Return True when `value` is finite and greater than zero.

    Args:
        value: The number. A `Float32` converts exactly.

    Returns:
        Whether it is a positive finite number.
    """
    return isfinite(value) and value > 0


def require_positive_finite(value: Float64, message: String) raises:
    """Refuse a number that is not finite and positive.

    Args:
        value: The number. A `Float32` converts exactly.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is finite and greater than
        zero.

    Raises:
        Error: If `value` is not finite or is not greater than zero.
    """
    if not positive_finite(value):
        raise Error(message)


def require_finite_group(finite: Bool, message: String) raises:
    """Refuse a group of numbers that is not finite.

    The caller tests each number and passes the result.

    Args:
        finite: Whether every number in the group is finite.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when the group is finite.

    Raises:
        Error: If the group is not finite.
    """
    if not finite:
        raise Error(message)
