# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.sort_utils`.

`assets/sort/three.json` holds six hundred 32-bit keys, a third of them
repeated, and the order three.js r180's `radixSort` puts their items in,
forward and reversed, run in Node by `three_sort.mjs` beside it.
"""

from loaders.json import JsonDocument, parse_json
from math.sort_utils import radix_sort, radix_sort_keys, stable_sort
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _reference() raises -> JsonDocument:
    """Return what three.js sorted."""
    return parse_json(Path("assets/sort/three.json").read_text())


def _keys(doc: JsonDocument) raises -> List[UInt32]:
    """Return the reference's keys."""
    var list = doc.get(doc.root(), "keys")
    var keys = List[UInt32]()
    for at in range(doc.length(list)):
        keys.append(UInt32(doc.integer(doc.at(list, at))))
    return keys^


def _check(reversed: Bool, name: String) raises:
    """Assert a sort puts the items in three.js's order."""
    var doc = _reference()
    var keys = _keys(doc)
    var items = List[Int]()
    for at in range(len(keys)):
        items.append(at)
    radix_sort(items, keys, reversed)
    var want = doc.get(doc.root(), name)
    assert_equal(len(items), doc.length(want))
    for at in range(len(items)):
        assert_equal(items[at], doc.integer(doc.at(want, at)))


def test_a_radix_sort_orders_as_three_js_does() raises:
    _check(False, "forward")


def test_a_reversed_radix_sort_orders_as_three_js_does() raises:
    _check(True, "reversed")


def test_the_keys_sort_themselves() raises:
    var keys: List[UInt32] = [5, 0xFFFFFFFF, 3, 5, 0, 70000]
    radix_sort_keys(keys)
    var want: List[UInt32] = [0, 3, 5, 5, 70000, 0xFFFFFFFF]
    for at in range(len(keys)):
        assert_equal(keys[at], want[at])
    radix_sort_keys(keys, reversed=True)
    assert_equal(keys[0], 0xFFFFFFFF)
    assert_equal(keys[5], 0)
    var none = List[UInt32]()
    radix_sort_keys(none)
    assert_equal(len(none), 0)


def test_a_long_sort_recurses_through_every_byte() raises:
    # Forty keys share their top three bytes, forty more only their top
    # byte, and the rest their top one too, so the sort recurses to its
    # last byte and sorts short runs at each depth.
    var keys = List[UInt32]()
    for i in range(40):
        keys.append(UInt32((i * 97) % 256))
    for i in range(40):
        keys.append(UInt32((1 << 24) + (i << 16)))
    for i in range(3000):
        keys.append(UInt32((i * 7919) % 1000003))
    for reversed in [False, True]:
        var items = List[Int]()
        for i in range(len(keys)):
            items.append(i)
        radix_sort(items, keys, reversed=reversed)
        for at in range(1, len(items)):
            if reversed:
                assert_true(keys[items[at - 1]] >= keys[items[at]])
            else:
                assert_true(keys[items[at - 1]] <= keys[items[at]])


def test_an_item_must_name_a_key() raises:
    var keys: List[UInt32] = [1, 2]
    var items: List[Int] = [0, 2]
    with assert_raises(contains="must name a key"):
        radix_sort(items, keys)
    items = [-1]
    with assert_raises(contains="must name a key"):
        radix_sort(items, keys)


def _check_stable(count: Int, reversed: Bool) raises:
    var items = List[Int]()
    var keys = List[Int]()
    for index in range(count):
        items.append(index)
        keys.append((index * 97) % 13)

    def before(a: Int, b: Int) capturing -> Bool:
        return keys[a] > keys[b] if reversed else keys[a] < keys[b]

    stable_sort[before](items)
    var seen = List[Bool](length=count, fill=False)
    for index in range(count):
        assert_true(not seen[items[index]])
        seen[items[index]] = True
        if index > 0:
            var a = items[index - 1]
            var b = items[index]
            assert_true(not before(b, a))
            if keys[a] == keys[b]:
                assert_true(a < b)


def test_stable_sort_preserves_ties_across_merge_boundaries() raises:
    for count in [0, 1, 2, 31, 32, 33, 65, 511]:
        _check_stable(count, False)
        _check_stable(count, True)


def test_a_large_reverse_sort_has_a_logarithmic_comparison_bound() raises:
    var items = List[Int]()
    for index in range(8192, 0, -1):
        items.append(index)
    var comparisons = 0

    def before(a: Int, b: Int) capturing -> Bool:
        comparisons += 1
        return a < b

    stable_sort[before](items)
    assert_true(comparisons <= 8192 * 13)
    for index in range(8192):
        assert_equal(items[index], index + 1)


def test_equal_items_and_an_already_sorted_list_keep_their_order() raises:
    for count in [2, 33, 65]:
        var items = List[Int]()
        for index in range(count):
            items.append(index)

        def tied(a: Int, b: Int) -> Bool:
            return False

        stable_sort[tied](items)
        for index in range(count):
            assert_equal(items[index], index)

        def ascending(a: Int, b: Int) -> Bool:
            return a < b

        stable_sort[ascending](items)
        for index in range(count):
            assert_equal(items[index], index)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
