# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The dispatch sources and protected paths stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_dispatch_gate import dispatch_paths


def test_sources_precede_the_protected_paths() raises:
    """Two sources stay in order, then five protected dependencies."""
    var doc = PyJson.parse(dispatch_paths())
    var sources = doc.at(doc.root, "sources")
    var protected = doc.at(doc.root, "protected")
    assert_equal(doc.length(sources), 2)
    assert_equal(doc.length(protected), 5)
    assert_equal(
        doc.text(doc.item(sources, 0)),
        "extensions/carla/curve_minimizer_support.mojo",
    )
    assert_equal(
        doc.text(doc.item(sources, 1)),
        "extensions/carla/curve_sample_dispatch.mojo",
    )
    assert_equal(
        doc.text(doc.item(protected, 0)), "extensions/carla/curve_interval.mojo"
    )
    assert_equal(
        doc.text(doc.item(protected, 1)), "extensions/carla/curve_sum2.mojo"
    )
    assert_equal(
        doc.text(doc.item(protected, 2)), "extensions/carla/curve_bounds.mojo"
    )
    assert_equal(doc.text(doc.item(protected, 3)), "extensions/carla/map.mojo")
    assert_equal(
        doc.text(doc.item(protected, 4)),
        "extensions/carla/lane_refinement.mojo",
    )


def main() raises:
    """Run the dispatch path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
