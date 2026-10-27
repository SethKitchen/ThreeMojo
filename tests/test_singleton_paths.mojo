# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The rounded LINE singleton paths and consumer messages stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._singleton_paths import singleton_paths


def test_singleton_paths_keep_the_lane_and_the_line() raises:
    """The lane and the rounded line keep their consumer messages."""
    var doc = PyJson.parse(singleton_paths())
    assert_equal(doc.length(doc.root), 4)
    assert_equal(doc.key(doc.root, 0), "lane")
    assert_equal(doc.key(doc.root, 1), "rounded_line")
    assert_equal(doc.key(doc.root, 2), "import_scope")
    assert_equal(doc.key(doc.root, 3), "declaration")
    assert_equal(
        doc.text(doc.at(doc.root, "lane")),
        "extensions/carla/lane_refinement.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "rounded_line")),
        "extensions/carla/curve_rounded_line.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "import_scope")),
        "consumer import scope changed: ",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "declaration")),
        "consumer/reference declaration changed: ",
    )


def main() raises:
    """Run the singleton path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
