# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Production paths skip hidden parts and non-production roots."""

from std.testing import TestSuite, assert_equal

from tools._production_paths import keep_production, production_paths


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


def main() raises:
    """Run the production path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
