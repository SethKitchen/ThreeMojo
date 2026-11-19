# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The stable order of values, and a sorted copy."""

from extensions.numerics.order import (
    ascending_order,
    descending_order,
    order_by,
    sorted_values,
)
from std.testing import TestSuite, assert_equal


def _same(found: List[Int], wanted: List[Int]) raises:
    assert_equal(len(found), len(wanted))
    for i in range(len(wanted)):
        assert_equal(found[i], wanted[i])


def test_ascending_keeps_ties_in_order() raises:
    var keys: List[Float64] = [3.0, 1.0, 2.0, 1.0, 3.0]
    _same(ascending_order(keys), [1, 3, 2, 0, 4])
    _same(descending_order(keys), [0, 4, 2, 1, 3])


def test_sorted_values() raises:
    var values: List[Float64] = [0.5, -2.0, 0.5, 9.0]
    var out = sorted_values(values)
    var wanted: List[Float64] = [-2.0, 0.5, 0.5, 9.0]
    for i in range(4):
        assert_equal(out[i], wanted[i])
    # The input keeps its order.
    assert_equal(values[0], 0.5)


def test_order_by_a_comparison() raises:
    # Pairs sorted by the first, then the second.
    var keys: List[Tuple[Int, Int]] = [(2, 1), (1, 5), (2, 0), (1, 5)]

    def before(a: Int, b: Int) capturing -> Bool:
        if keys[a][0] != keys[b][0]:
            return keys[a][0] < keys[b][0]
        return keys[a][1] < keys[b][1]

    _same(order_by[before](len(keys)), [1, 3, 2, 0])


def test_no_values() raises:
    var none = List[Float64]()
    assert_equal(len(ascending_order(none)), 0)
    assert_equal(len(descending_order(none)), 0)
    assert_equal(len(sorted_values(none)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
