# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The reviewed cleanup paths stay in order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_cleanup_gate import cleanup_paths


def test_successors_precede_the_premise_paths() raises:
    """Three successors stay in order, then the two premise paths."""
    var doc = PyJson.parse(cleanup_paths())
    var sources = doc.at(doc.root, "sources")
    var premises = doc.at(doc.root, "premises")
    assert_equal(doc.length(sources), 3)
    assert_equal(doc.length(premises), 2)
    assert_equal(
        doc.text(doc.item(sources, 0)),
        "extensions/carla/curve_rounded_line.mojo",
    )
    assert_equal(
        doc.text(doc.item(sources, 1)),
        "extensions/carla/curve_rounded_arc.mojo",
    )
    assert_equal(
        doc.text(doc.item(sources, 2)), "extensions/carla/junction_bounds.mojo"
    )
    assert_equal(
        doc.text(doc.item(premises, 0)), "extensions/carla/road_info.mojo"
    )
    assert_equal(
        doc.text(doc.item(premises, 1)), "extensions/carla/curve_trig.mojo"
    )


def main() raises:
    """Run the cleanup path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
