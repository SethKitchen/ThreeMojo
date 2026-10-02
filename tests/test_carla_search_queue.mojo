# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The navigation heap agrees with a simple linear selection oracle."""

from extensions.carla.search_queue import _MinCostQueue
from std.testing import TestSuite, assert_equal, assert_raises


def _linear_pop(mut entries: List[Tuple[Float64, Int]]) -> Tuple[Float64, Int]:
    var best = 0
    for i in range(1, len(entries)):
        if entries[i][0] < entries[best][0] or (
            entries[i][0] == entries[best][0]
            and entries[i][1] < entries[best][1]
        ):
            best = i
    return entries.pop(best)


def test_queue_matches_linear_selection_with_ties_and_duplicates() raises:
    var queue = _MinCostQueue()
    var oracle = List[Tuple[Float64, Int]]()
    assert_equal(len(queue), 0)
    # Permuted scores, equal scores, repeated keys, and negative keys used
    # by loose-end route nodes. Interleave pushes and pops too.
    for i in range(1024):
        var score = Float64((i * 37) % 97)
        var key = (i * 19) % 41 - 20
        queue.push(score, key)
        oracle.append((score, key))
        if i % 7 == 0:
            var got = queue.pop()
            var want = _linear_pop(oracle)
            assert_equal(got[0], want[0])
            assert_equal(got[1], want[1])
    while len(oracle) > 0:
        var got = queue.pop()
        var want = _linear_pop(oracle)
        assert_equal(got[0], want[0])
        assert_equal(got[1], want[1])
        assert_equal(len(queue), len(oracle))


def test_queue_handles_single_entry_and_equal_scores() raises:
    var queue = _MinCostQueue()
    queue.push(3, -7)
    var single = queue.pop()
    assert_equal(single[0], 3)
    assert_equal(single[1], -7)
    assert_equal(len(queue), 0)
    for i in range(127, -1, -1):
        queue.push(1, i)
    for i in range(128):
        assert_equal(queue.pop()[1], i)
    assert_equal(len(queue), 0)


def test_queue_orders_large_and_infinite_scores() raises:
    var queue = _MinCostQueue()
    var infinity = Float64("inf")
    queue.push(infinity, 3)
    queue.push(Float64(1e300), 1)
    queue.push(0, 9)
    queue.push(infinity, -2)
    assert_equal(queue.pop()[1], 9)
    assert_equal(queue.pop()[1], 1)
    assert_equal(queue.pop()[1], -2)
    assert_equal(queue.pop()[1], 3)


def test_queue_rejects_nan_without_changing_pending_entries() raises:
    var queue = _MinCostQueue()
    queue.push(1, 7)
    with assert_raises(contains="must not be NaN"):
        queue.push(Float64("nan"), 3)
    assert_equal(len(queue), 1)
    assert_equal(queue.pop()[1], 7)


def test_queue_preserves_integer_scores_above_float64_precision() raises:
    var queue = _MinCostQueue[DType.uint64]()
    queue.push(9007199254740993, -1)
    queue.push(9007199254740992, 7)
    queue.push(9223372036854775807, 0)
    queue.push(9223372036854775808, 0)
    queue.push(9007199254740992, -2)
    assert_equal(queue.pop()[1], -2)
    assert_equal(queue.pop()[1], 7)
    var next = queue.pop()
    assert_equal(next[0], 9007199254740993)
    assert_equal(next[1], -1)
    assert_equal(queue.pop()[0], 9223372036854775807)
    assert_equal(queue.pop()[0], 9223372036854775808)
    assert_equal(len(queue), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
