# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether a real number is finite, and whether it is greater than zero.

Every `Float32` value converts exactly to `Float64`, so one test covers
both widths. `require_finite` refuses a value that is not finite.
`finite_float32` narrows a `Float64` and refuses a result that is not
finite. `require_positive_finite` refuses a value that is not positive
and finite. `require_non_negative_finite` refuses a value that is not
finite or is negative. `require_unit_finite` refuses a value outside
zero through one, or one that is not finite. `require_finite_group`
refuses a caller-tested group that is not finite. Callers keep their
own error text.
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


def non_negative_finite(value: Float64) -> Bool:
    """Return True when `value` is finite and zero or more.

    Args:
        value: The number. A `Float32` converts exactly.

    Returns:
        Whether it is a finite number, zero or more.

    Raises:
        Error: Never.
    """
    return isfinite(value) and value >= 0


def require_non_negative_finite(value: Float64, message: String) raises:
    """Refuse a number that is not finite or is negative.

    Args:
        value: The number. A `Float32` converts exactly.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is finite and zero or more.

    Raises:
        Error: If `value` is not finite or is negative.
    """
    if not non_negative_finite(value):
        raise Error(message)


def unit_finite(value: Float64) -> Bool:
    """Return True when `value` is finite and from zero through one.

    Args:
        value: The number. A `Float32` converts exactly.

    Returns:
        Whether it is finite and from zero through one.

    Raises:
        Error: Never.
    """
    return isfinite(value) and value >= 0 and value <= 1


def require_unit_finite(value: Float64, message: String) raises:
    """Refuse a number outside zero through one, or one that is not finite.

    Args:
        value: The number. A `Float32` converts exactly.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is finite and from zero
        through one.

    Raises:
        Error: If `value` is not finite or is outside zero through one.
    """
    if not unit_finite(value):
        raise Error(message)


def require_finite(value: Float64, message: String) raises:
    """Refuse a number that is not finite.

    Args:
        value: The number. A `Float32` converts exactly.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is finite.

    Raises:
        Error: If `value` is not finite.
    """
    if not isfinite(value):
        raise Error(message)


def finite_float32(value: Float64, message: String) raises -> Float32:
    """Return `value` as a `Float32`, refusing a result that is not finite.

    Args:
        value: The wide number.
        message: The error text when the `Float32` is not finite.

    Returns:
        The `Float32`.

    Raises:
        Error: If the `Float32` is not finite.
    """
    var narrow = Float32(value)
    require_finite(Float64(narrow), message)
    return narrow


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
