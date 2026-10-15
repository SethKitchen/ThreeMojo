# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shard tools split suites into balanced groups and keep every suite.

`tools/shard.mojo` weighs a suite by the source it compiles.
`tools/coverage_shard.mojo` uses measured seconds and estimates a suite
that has no measurement.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._schedule import load_costs, parse_shard, schedule, split, strip_dot
from tools.coverage_shard import group as coverage_group
from tools.shard import group as shard_group


def test_parse_shard_takes_i_of_n() raises:
    var index = 0
    var count = 0
    assert_true(parse_shard("2/4", index, count))
    assert_equal(index, 2)
    assert_equal(count, 4)
    assert_true(parse_shard("01/03", index, count))
    assert_equal(index, 1)
    for text in [
        "",
        "0/3",
        "4/3",
        "a/3",
        "1/",
        "/3",
        "1/3/4",
        " 1/3",
        "+1/3",
        "1/-3",
    ]:
        assert_false(parse_shard(text, index, count), text)


def test_split_deals_the_costliest_first_to_the_lightest_group() raises:
    var groups = split(["a", "b", "c", "d", "e"], 2, [5.0, 4.0, 3.0, 3.0, 1.0])
    assert_equal(" ".join(groups[0]), "a d")
    assert_equal(" ".join(groups[1]), "b c e")
    # Equal costs order by name, and equal loads take the first group.
    groups = split(["y", "x", "z"], 3, [1.0, 1.0, 1.0])
    assert_equal(" ".join(groups[0]), "x")
    assert_equal(" ".join(groups[1]), "y")
    assert_equal(" ".join(groups[2]), "z")
    assert_equal(len(split([], 2, [])[1]), 0)


def _suites() raises -> Tree:
    """Return a tree of suites of different sizes and a cost profile."""
    var tree = Tree()
    tree.write("core/big.mojo", "# " + "x" * 400 + "\n")
    tree.write("tests/test_big.mojo", "from core.big import x\n")
    tree.write("tests/test_mid.mojo", "# " + "x" * 200 + "\n")
    tree.write("tests/test_small.mojo", "# small\n")
    tree.write(
        "tools/coverage_costs.json",
        (
            '{"seconds": {"tests/test_small.mojo": 30, "tests/test_mid.mojo":'
            " 2.5}}"
        ),
    )
    return tree^


def test_shard_keeps_the_given_order_within_a_group() raises:
    var tree = _suites()
    var arguments: List[String] = [
        "1/2",
        "./tests/test_small.mojo",
        "tests/test_mid.mojo",
        "tests/test_big.mojo",
    ]
    assert_equal(shard_group(tree.root, arguments), "tests/test_big.mojo")
    arguments[0] = "2/2"
    assert_equal(
        shard_group(tree.root, arguments),
        "tests/test_small.mojo tests/test_mid.mojo",
    )
    with assert_raises(contains="expected I/N"):
        _ = shard_group(tree.root, ["3/2", "tests/test_big.mojo"])
    with assert_raises():
        _ = shard_group(tree.root, ["1/1", "tests/test_missing.mojo"])
    tree.close()


def test_coverage_shard_uses_measured_seconds() raises:
    var tree = _suites()
    var arguments: List[String] = [
        "1/2",
        "tests/test_small.mojo",
        "tests/test_mid.mojo",
        "tests/test_big.mojo",
    ]
    # test_big has no measurement. Its 427 bytes at the median rate of the
    # other two, about 1.9 seconds a byte, make it the longest capture.
    assert_equal(coverage_group(tree.root, arguments), "tests/test_big.mojo")
    arguments[0] = "2/2"
    assert_equal(
        coverage_group(tree.root, arguments),
        "tests/test_small.mojo tests/test_mid.mojo",
    )
    with assert_raises(contains="expected I/N"):
        _ = coverage_group(tree.root, ["0/2"])
    with assert_raises(contains="unique suites"):
        _ = coverage_group(
            tree.root, ["1/1", "tests/test_mid.mojo", "tests/test_mid.mojo"]
        )
    tree.remove("tools/coverage_costs.json")
    with assert_raises():
        _ = coverage_group(tree.root, ["1/1", "tests/test_mid.mojo"])
    tree.close()


def test_an_unmeasured_suite_gets_the_median_rate_and_at_least_a_second() raises:
    var costs = Dict[String, Float64]()
    costs["tests/test_a.mojo"] = 10
    costs["tests/test_b.mojo"] = 40
    # Rates 0.1 and 0.2 per byte: the median is 0.15, so test_c costs 45
    # seconds and test_d the one-second floor.
    var groups = schedule(
        [
            "tests/test_a.mojo",
            "tests/test_b.mojo",
            "tests/test_c.mojo",
            "tests/test_d.mojo",
        ],
        2,
        costs,
        [100, 200, 300, 2],
    )
    assert_equal(" ".join(groups[0]), "tests/test_c.mojo tests/test_d.mojo")
    assert_equal(" ".join(groups[1]), "tests/test_b.mojo tests/test_a.mojo")
    # With no measurement, a byte costs 1/10000 of a second.
    groups = schedule(
        ["tests/test_x.mojo", "tests/test_y.mojo"],
        2,
        Dict[String, Float64](),
        [50000, 0],
    )
    assert_equal(" ".join(groups[0]), "tests/test_x.mojo")
    with assert_raises(contains="positive shard count"):
        _ = schedule(["tests/test_x.mojo"], 0, costs, [1])


def test_the_cost_profile_is_checked() raises:
    var tree = Tree()
    var bad = [
        ('{"seconds": {}}', "nonempty object"),
        ('{"seconds": []}', "nonempty object"),
        ('{"seconds": {"tests/test_a.mojo": 0}}', "invalid coverage cost"),
        ('{"seconds": {"tests/test_a.mojo": -1}}', "invalid coverage cost"),
        ('{"seconds": {"tests/test_a.mojo": null}}', "invalid coverage cost"),
        ('{"seconds": {"../test_a.mojo": 1}}', "invalid coverage cost"),
        ('{"seconds": {"tests/test_a/../b.mojo": 1}}', "invalid coverage cost"),
        ('{"seconds": {"tests/a.mojo": 1}}', "invalid coverage cost"),
        ('{"seconds": {"tests/test_a.mojo": true}}', "invalid coverage cost"),
        ('{"seconds": {"tests/test_a.mojo": "1"}}', "invalid coverage cost"),
        ('{"seconds": {"tests/a/test_a.mojo": 1}}', "invalid coverage cost"),
        ('{"seconds": {"tests/test_a.py": 1}}', "invalid coverage cost"),
        ('{"seconds": {"src/test_a.mojo": 1}}', "invalid coverage cost"),
        (
            '{"seconds": {"tests/test_a.mojo": 1, "tests/test_a.mojo": 2}}',
            "duplicate",
        ),
        (
            '{"seconds": {"tests/test_a.mojo": 1}, "x": [{"k": 1, "k": 2}]}',
            "duplicate",
        ),
    ]
    for entry in bad:
        tree.write("costs.json", entry[0])
        with assert_raises(contains=entry[1]):
            _ = load_costs(tree.root + "/costs.json")
    tree.write("costs.json", '{"seconds": {"tests/test_a.mojo": 1.5}}')
    assert_equal(
        load_costs(tree.root + "/costs.json")["tests/test_a.mojo"], 1.5
    )
    tree.close()


def test_unknown_suites_and_empty_groups_are_kept() raises:
    var costs = Dict[String, Float64]()
    costs["known"] = 20
    var groups = schedule(["known", "new", "tiny"], 5, costs, [200, 400, 1])
    var expected = ["new", "known", "tiny", "", ""]
    for index in range(5):
        assert_equal(" ".join(groups[index]), expected[index])
    assert_equal(len(schedule([], 2, costs, [])), 2)
    assert_equal(
        " ".join(schedule(["new"], 1, Dict[String, Float64](), [400])[0]), "new"
    )


def test_the_repository_profile_starts_the_known_expensive_suites_first() raises:
    var costs = load_costs("tools/coverage_costs.json")
    var suites = List[String]()
    for entry in costs.items():
        suites.append(entry.key)
    var reversed = List[String]()
    for index in range(len(suites) - 1, -1, -1):
        reversed.append(suites[index])
    var ones = List[Int](length=len(suites), fill=1)
    var groups = schedule(suites, 8, costs, ones)
    var again = schedule(reversed, 8, costs, ones)
    var dealt = 0
    for index in range(8):
        dealt += len(groups[index])
        assert_equal(" ".join(groups[index]), " ".join(again[index]))
        # Each group starts its longest captures first.
        for position in range(1, len(groups[index])):
            assert_true(
                costs[groups[index][position - 1]]
                >= costs[groups[index][position]]
            )
    assert_equal(dealt, len(suites))
    assert_equal(groups[0][0], "tests/test_carla_recorder_world.mojo")
    assert_equal(groups[1][0], "tests/test_carla_map.mojo")
    assert_equal(groups[2][0], "tests/test_carla_world.mojo")
    assert_equal(strip_dot("./a"), "a")
    assert_equal(strip_dot("a/./b"), "a/./b")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
