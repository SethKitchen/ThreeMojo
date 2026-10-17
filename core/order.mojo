# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A stable order of a list's places.

Equal keys keep the order they had. The comparison is `>`, so a key that
is not greater stays where it is.
"""


def stable_rising_order[T: Comparable](keys: List[T]) -> List[Int]:
    """Return the places of `keys` from smallest to largest.

    Equal keys keep the order they had. This is an insertion sort, which
    is what a short list of keys uses.

    Args:
        keys: The keys, in the order they came.

    Returns:
        The places, smallest first. An empty list returns an empty order.
    """
    var order = List[Int]()
    for index in range(len(keys)):
        var at = len(order)
        while at > 0 and keys[order[at - 1]] > keys[index]:
            at -= 1
        order.insert(at, index)
    return order^
