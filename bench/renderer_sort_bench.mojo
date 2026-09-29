# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Compare renderer sorting with its previous insertion implementation.

Run `mojo run -I . bench/renderer_sort_bench.mojo`. Each row is the best
of three runs on sorted or reverse-depth draws with one render order. Inputs are
copied before timing. Output is checked against the previous algorithm.
This measures sorting only, not frame rendering.
"""

from renderers.renderer import _sort_by
from std.math import min
from std.testing import assert_equal
from std.time import perf_counter_ns


def _insertion(
    mut items: List[Int], mut keys: List[Float32], mut orders: List[Int]
):
    for position in range(len(items)):
        var item = items[position]
        var key = keys[position]
        var order = orders[position]
        var slot = position
        while slot > 0 and (
            orders[slot - 1] > order
            or (orders[slot - 1] == order and keys[slot - 1] > key)
        ):
            items[slot] = items[slot - 1]
            keys[slot] = keys[slot - 1]
            orders[slot] = orders[slot - 1]
            slot -= 1
        items[slot] = item
        keys[slot] = key
        orders[slot] = order


def main() raises:
    """Check matching output and print sorting times in milliseconds."""
    print("distribution,draws,insertion_ms,merge_ms,speedup")
    for count in [32, 1024, 8192]:
        _measure(count, False)
        _measure(count, True)


def _measure(count: Int, reverse: Bool) raises:
    var items = List[Int]()
    var keys = List[Float32]()
    var orders = List[Int](length=count, fill=0)
    for index in range(count):
        items.append(index)
        keys.append(Float32(count - index if reverse else index))
    var old_best = Float64(1e30)
    var new_best = Float64(1e30)
    for _ in range(3):
        var old_items = items.copy()
        var old_keys = keys.copy()
        var old_orders = orders.copy()
        var start = perf_counter_ns()
        _insertion(old_items, old_keys, old_orders)
        old_best = min(old_best, Float64(perf_counter_ns() - start))
        var new_items = items.copy()
        var new_keys = keys.copy()
        var new_orders = orders.copy()
        start = perf_counter_ns()
        _sort_by(new_items, new_keys, new_orders)
        new_best = min(new_best, Float64(perf_counter_ns() - start))
        for index in range(count):
            assert_equal(old_items[index], new_items[index])
            assert_equal(old_keys[index], new_keys[index])
            assert_equal(old_orders[index], new_orders[index])
    print(
        "reverse" if reverse else "sorted",
        count,
        old_best / 1e6,
        new_best / 1e6,
        old_best / new_best,
        sep=",",
    )
