# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Range checks that the vegetation parameters share.

Each check refuses a value outside a closed range. A NaN fails both
comparisons, so each check also refuses a NaN.
"""


def require_between(
    value: Float32, low: Float32, high: Float32, message: String
) raises:
    """Refuse a number outside `low` to `high`, or a NaN.

    Args:
        value: The number to check.
        low: The smallest number that is accepted.
        high: The largest number that is accepted.
        message: The error text for this caller.

    Raises:
        Error: If `value` is below `low`, above `high`, or NaN.
    """
    if not (value >= low and value <= high):
        raise Error(message)


def require_count_between(
    value: Int, low: Int, high: Int, message: String
) raises:
    """Refuse a count outside `low` to `high`.

    Args:
        value: The count to check.
        low: The smallest count that is accepted.
        high: The largest count that is accepted.
        message: The error text for this caller.

    Raises:
        Error: If `value` is below `low` or above `high`.
    """
    if value < low or value > high:
        raise Error(message)
