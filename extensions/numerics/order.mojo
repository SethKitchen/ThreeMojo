# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The order of values: the indexes that sort them, and a sorted copy.

- `ascending_order(keys)` gives the indexes of the keys from the least.
- `descending_order(keys)` gives them from the largest.
- `sorted_values(values)` gives a copy from the least.
- `order_by[before](count)` gives the indexes from 0 to `count - 1` in
  the order of a comparison of indexes, for keys that are not numbers.

Each sort is stable: equal keys keep their order. It is the merge sort of
`math.sort_utils.stable_sort`. A key that is not a number compares as
neither less nor more than another.
"""

from math.sort_utils import stable_sort


def order_by[
    before: def(Int, Int) capturing[_] -> Bool
](count: Int) -> List[Int]:
    """Return the indexes from 0 to `count - 1`, sorted stably.

    Parameters:
        before: True when the first index must precede the second.

    Args:
        count: The number of indexes.

    Returns:
        The indexes in the order of `before`. Indexes that neither
        precedes keep their order.
    """
    var out = List[Int](capacity=max(count, 0))
    for i in range(count):
        out.append(i)
    stable_sort[before](out)
    return out^


def ascending_order(keys: List[Float64]) -> List[Int]:
    """Return the indexes of the keys, from the least key.

    Args:
        keys: The keys.

    Returns:
        The index of each key, from the least to the largest key. Equal
        keys keep their order.
    """

    def before(a: Int, b: Int) capturing -> Bool:
        return keys[a] < keys[b]

    return order_by[before](len(keys))


def descending_order(keys: List[Float64]) -> List[Int]:
    """Return the indexes of the keys, from the largest key.

    Args:
        keys: The keys.

    Returns:
        The index of each key, from the largest to the least key. Equal
        keys keep their order.
    """

    def before(a: Int, b: Int) capturing -> Bool:
        return keys[a] > keys[b]

    return order_by[before](len(keys))


def sorted_values(values: List[Float64]) -> List[Float64]:
    """Return a copy of the values, from the least.

    Args:
        values: The values.

    Returns:
        The values from the least to the largest.
    """
    var out = values.copy()

    def before(a: Float64, b: Float64) capturing -> Bool:
        return a < b

    stable_sort[before](out)
    return out^
