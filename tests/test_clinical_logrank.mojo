# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The log-rank test of several groups.

`assets/survival/groups_expected.txt` holds the result of lifelines
0.30.3 on the three synthetic arms of `assets/survival/three_arms.txt`.
See `assets/survival/make_groups.py`.
"""

from extensions.clinical.logrank import GroupLogRank, log_rank_groups
from extensions.clinical.survival import WEEK64, log_rank_test
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Duration64


def _arm(text: String) raises -> Tuple[List[Duration64], List[Bool]]:
    var times = List[Duration64]()
    var events = List[Bool]()
    for part in text.split(" "):
        var word = String(part)
        var censored = word.endswith("+")
        var number = word
        if censored:
            number = String(word[byte = 0 : word.byte_length() - 1])
        times.append(Duration64(atof(number), WEEK64))
        events.append(not censored)
    return (times^, events^)


def test_three_arms() raises:
    var times = List[List[Duration64]]()
    var events = List[List[Bool]]()
    for line in open("assets/survival/three_arms.txt", "r").read().splitlines():
        var arm = _arm(String(line))
        times.append(arm[0].copy())
        events.append(arm[1].copy())
    var test = log_rank_groups(times, events)
    var words = String(
        open("assets/survival/groups_expected.txt", "r").read().splitlines()[0]
    ).split(" ")
    assert_almost_equal(test.statistic, atof(String(words[1])), rtol=1e-12)
    assert_equal(test.freedom, Int(atof(String(words[2]))))
    assert_almost_equal(test.p_value, atof(String(words[3])), rtol=1e-11)
    # The observed and expected events sum to the same total.
    var observed = 0
    var expected = 0.0
    for k in range(3):
        observed += test.observed[k]
        expected += test.expected[k]
    assert_almost_equal(expected, Float64(observed), rtol=1e-13)


def test_two_groups() raises:
    # With two groups the test is the two-group log-rank test.
    var a = _arm("6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+")
    var b = _arm("1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23")
    var times = List[List[Duration64]]()
    var events = List[List[Bool]]()
    times.append(a[0].copy())
    times.append(b[0].copy())
    events.append(a[1].copy())
    events.append(b[1].copy())
    var many = log_rank_groups(times, events)
    var two = log_rank_test(a[0], a[1], b[0], b[1])
    assert_almost_equal(many.statistic, two.statistic, rtol=1e-12)
    assert_almost_equal(many.p_value, two.p_value, rtol=1e-11)
    assert_equal(many.observed[0], two.observed[0])
    # At 5 weeks one patient alone is at risk, and adds no variance.
    var lone = List[List[Duration64]]()
    lone.append([Duration64(1, WEEK64), Duration64(5, WEEK64)])
    lone.append([Duration64(2, WEEK64)])
    var all = List[List[Bool]]()
    all.append([True, True])
    all.append([True])
    var pair = log_rank_test(lone[0], all[0], lone[1], all[1])
    assert_almost_equal(
        log_rank_groups(lone, all).statistic, pair.statistic, rtol=1e-13
    )


def test_refusals() raises:
    var one = List[List[Duration64]]()
    one.append([Duration64(1, WEEK64)])
    var flag = List[List[Bool]]()
    flag.append([True])
    with assert_raises(contains="2 to 100 groups"):
        _ = log_rank_groups(one, flag)
    var two = one.copy()
    two.append([Duration64(2, WEEK64)])
    with assert_raises(contains="2 to 100 groups"):
        _ = log_rank_groups(two, flag)
    var many = List[List[Duration64]]()
    var flags = List[List[Bool]]()
    for _ in range(101):
        many.append([Duration64(1, WEEK64)])
        flags.append([True])
    with assert_raises(contains="2 to 100 groups"):
        _ = log_rank_groups(many, flags)
    var bad = List[List[Bool]]()
    bad.append([True])
    bad.append(List[Bool]())
    with assert_raises(contains="one patient or more"):
        _ = log_rank_groups(two, bad)
    # No event: the risk never changes.
    var still = List[List[Bool]]()
    still.append([False])
    still.append([False])
    with assert_raises(contains="change the risk"):
        _ = log_rank_groups(two, still)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
