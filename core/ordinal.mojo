# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether an integer names an entry in a closed range.

A named id stores an integer. Zero is the first name. `last` is the
last name. A value outside that range is not a name. Each id keeps its
own type. `index_in_count` is true from zero through one below a count.
`require_index_in_count` refuses an index outside that range.
`require_non_negative` refuses a value below zero. Callers keep their
own error text.
"""


def ordinal_valid(value: Int, last: Int) -> Bool:
    """Return True when `value` names an entry from zero through `last`.

    Args:
        value: The stored ordinal.
        last: The value of the last named entry. A count is one past this.

    Returns:
        True when `value` is from zero through `last`.
    """
    if value < 0:
        return False
    return value <= last


def index_in_count(index: Int, count: Int) -> Bool:
    """Return True when `index` is from zero through one below `count`.

    Args:
        index: The place to test.
        count: How many entries the list holds.

    Returns:
        True when `index` is at least zero and below `count`.

    Raises:
        Error: Never.
    """
    return index >= 0 and index < count


def require_index_in_count(index: Int, count: Int, message: String) raises:
    """Refuse an index that does not name an entry.

    Args:
        index: The place to test.
        count: How many entries the list holds.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `index` names an entry.

    Raises:
        Error: If `index` is negative or not less than `count`.
    """
    if not index_in_count(index, count):
        raise Error(message)


def require_non_negative(value: Int, message: String) raises:
    """Refuse a value below zero.

    Args:
        value: The stored integer.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is zero or more.

    Raises:
        Error: If `value` is below zero.
    """
    if value < 0:
        raise Error(message)
