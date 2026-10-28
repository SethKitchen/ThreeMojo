# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The dispatch sources and protected paths stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_dispatch_gate import (
    dispatch_paths,
    dispatch_protected_bundle,
)


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


def test_the_migration_record_is_read_before_the_paths() raises:
    """The dispatch migration record stays ahead of the protected paths."""
    var wrapped = dispatch_protected_bundle()
    var paths = dispatch_paths()
    assert_equal(wrapped.startswith('{"migration":'), True)
    var doc = PyJson.parse(wrapped)
    assert_equal(doc.key(doc.root, 0), "migration")
    assert_equal(doc.key(doc.root, 1), "paths")
    assert_equal(
        doc.text(doc.at(doc.at(doc.root, "migration"), "path")),
        "tools/carla_lane_oracle/curve-support-dispatch-migration.json",
    )
    assert_equal(doc.subtree(doc.at(doc.root, "paths")).dumps(), paths)


def main() raises:
    """Run the dispatch path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
