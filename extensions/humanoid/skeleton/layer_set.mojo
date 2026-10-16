# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bit-set checks shared by the regional tissue-layer types.

Each region keeps its own contents type, so a hand set cannot be passed
where a torso set is required. The bit tests are the same.
"""


def layer_set_valid(value: Int, limit: Int) -> Bool:
    """Return True when `value` is a non-empty subset of the named bits.

    Args:
        value: The stored bit set.
        limit: The value of `ALL` for that region.

    Returns:
        True when `value` is from 1 through `limit`.
    """
    if value <= 0:
        return False
    return value <= limit


def require_layer_set(value: Int, limit: Int, message: String) raises:
    """Raise `message` when `value` is not a named layer set.

    Args:
        value: The stored bit set.
        limit: The value of `ALL` for that region.
        message: The error text for this region.

    Raises:
        Error: If `value` is not a named layer set.
    """
    if not layer_set_valid(value, limit):
        raise Error(message)


def layer_includes(
    value: Int, bit: Int, limit: Int, message: String
) raises -> Bool:
    """Return True when `bit` is set on a valid layer set.

    Args:
        value: The stored bit set.
        bit: The layer bit to test.
        limit: The value of `ALL` for that region.
        message: The error text for this region.

    Returns:
        True when `bit` is set.

    Raises:
        Error: If `value` is not a named layer set.
    """
    require_layer_set(value, limit, message)
    return (value & bit) != 0


def layer_union(
    value: Int, other: Int, limit: Int, message: String
) raises -> Int:
    """Return the bitwise union of two named layer sets.

    Args:
        value: The first stored bit set.
        other: The second stored bit set.
        limit: The value of `ALL` for that region.
        message: The error text for this region.

    Returns:
        Every bit from either set.

    Raises:
        Error: If `value` or `other` is not a named layer set.
    """
    require_layer_set(value, limit, message)
    if not layer_set_valid(other, limit):
        raise Error(message)
    return value | other
