# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The frozen-arc source and dependency paths stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_frozen_arc_gate import (
    frozen_arc_paths,
    frozen_protected_bundle,
)


def test_the_source_precedes_the_two_dependencies() raises:
    """The frozen arc stays ahead of the polynomial and the road."""
    var doc = PyJson.parse(frozen_arc_paths())
    var protected = doc.at(doc.root, "protected")
    assert_equal(
        doc.text(doc.at(doc.root, "source")),
        "extensions/carla/curve_frozen_arc.mojo",
    )
    assert_equal(doc.length(protected), 2)
    assert_equal(
        doc.text(doc.item(protected, 0)), "extensions/carla/polynomial.mojo"
    )
    assert_equal(doc.text(doc.item(protected, 1)), "extensions/carla/road.mojo")


def test_the_paths_are_read_before_the_migration_record() raises:
    """The frozen-arc paths stay ahead of the migration record."""
    var paths = frozen_arc_paths()
    var wrapped = frozen_protected_bundle()
    assert_equal(
        wrapped.startswith('{"paths":' + paths + ',"migration":'), True
    )
    var doc = PyJson.parse(wrapped)
    assert_equal(doc.key(doc.root, 0), "paths")
    assert_equal(doc.key(doc.root, 1), "migration")
    assert_equal(
        doc.text(doc.at(doc.at(doc.root, "migration"), "path")),
        "tools/carla_lane_oracle/frozen-arc-producer-migration.json",
    )


def main() raises:
    """Run the frozen-arc path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
