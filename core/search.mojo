# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Find the first or last place of a value in a list.

Loaders and exporters scan a list of names for one name. The first place
and the last place are different, and a missing name is -1.
"""


def first_match[T: Equatable](items: List[T], wanted: T) -> Int:
    """Return the first place of `wanted` in `items`, or -1.

    Args:
        items: The values, in order.
        wanted: The value to find.

    Returns:
        The first place, or -1 when `wanted` is absent.
    """
    for index in range(len(items)):
        if items[index] == wanted:
            return index
    return -1


def last_match[T: Equatable](items: List[T], wanted: T) -> Int:
    """Return the last place of `wanted` in `items`, or -1.

    Args:
        items: The values, in order.
        wanted: The value to find.

    Returns:
        The last place, or -1 when `wanted` is absent.
    """
    var found = -1
    for index in range(len(items)):
        if items[index] == wanted:
            found = index
    return found
