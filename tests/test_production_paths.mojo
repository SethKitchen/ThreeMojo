# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Production paths skip hidden parts and non-production roots."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._production_paths import (
    keep_production,
    nonproduction_roots,
    production_paths,
    reviewed_production_paths,
)


def test_a_production_module_stays_in_the_scan() raises:
    """Only the first part is a root, and any hidden part is left out."""
    var roots = List[String]()
    roots.append("tests")
    roots.append("tools")
    assert_equal(keep_production("extensions/carla/lane.mojo", roots), True)
    assert_equal(keep_production("tools/check.mojo", roots), False)
    assert_equal(keep_production("extensions/tools/check.mojo", roots), True)
    assert_equal(keep_production(".git/lane.mojo", roots), False)
    assert_equal(keep_production("extensions/.hidden/lane.mojo", roots), False)
    assert_equal(keep_production("lane.mojo", roots), True)
    assert_equal(keep_production(".lane.mojo", roots), False)
    var empty = List[String]()
    assert_equal(keep_production("extensions/carla/lane.mojo", empty), True)


def test_a_path_list_keeps_production_order() raises:
    """Each path gets one boolean, including an empty list."""
    assert_equal(production_paths('{"roots":["tools"],"paths":[]}'), "[]")
    assert_equal(
        production_paths(
            '{"roots":["docs","tools"],"paths":["extensions/a.mojo",'
            + '"tools/a.mojo","extensions/.hidden/a.mojo"]}'
        ),
        "[true,false,false]",
    )


def test_the_reviewed_roots_are_read_before_the_paths() raises:
    """The non-production names are applied before the flag count."""
    var roots = nonproduction_roots()
    assert_equal(
        roots,
        '["tests","examples","bench","tools","docs","assets","out","coverage",'
        + '"cache","build","node_modules"]',
    )
    var paths = (
        '["extensions/carla/a.mojo","tools/a.mojo","docs/a.mojo",'
        + '"extensions/.hidden/a.mojo","lane.mojo"]'
    )
    assert_equal(
        reviewed_production_paths(paths, 5),
        production_paths('{"roots":' + roots + ',"paths":' + paths + "}"),
    )
    assert_equal(
        reviewed_production_paths(paths, 5), "[true,false,false,false,true]"
    )
    with assert_raises(
        contains="optional runtime contract: production path set changed"
    ):
        _ = reviewed_production_paths("[]", 1)


def main() raises:
    """Run the production path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
