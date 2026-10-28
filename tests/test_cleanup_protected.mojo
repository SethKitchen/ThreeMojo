# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The extra reviewed-cleanup inputs stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._record_paths import record_paths
from tools.carla_cleanup_gate import (
    cleanup_composed_inputs,
    cleanup_protected_bundle,
    cleanup_protected_tail,
    cleanup_records_then_tail,
)


def test_fourteen_inputs_stay_in_order() raises:
    """The followup record stays first and the roundoff proof stays last."""
    var doc = PyJson.parse(cleanup_protected_tail())
    assert_equal(doc.length(doc.root), 14)
    assert_equal(
        doc.text(doc.item(doc.root, 0)),
        "tools/carla_lane_oracle/coverage-followup-migration.json",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 6)),
        "extensions/carla/spiral_moment_proof.mojo",
    )
    assert_equal(
        doc.text(doc.item(doc.root, 13)),
        "extensions/carla/spiral_roundoff_proof.mojo",
    )


def test_the_record_paths_are_read_before_the_tail() raises:
    """The companion records stay ahead of the protected tail."""
    var doc = PyJson.parse(cleanup_records_then_tail())
    assert_equal(doc.key(doc.root, 0), "records")
    assert_equal(doc.key(doc.root, 1), "tail")
    var records = doc.at(doc.root, "records")
    var companions = PyJson.parse(record_paths())
    assert_equal(
        doc.text(doc.at(records, "runtime_pins")),
        companions.text(companions.at(companions.root, "runtime_pins")),
    )
    var tail = doc.at(doc.root, "tail")
    assert_equal(doc.length(tail), 14)
    assert_equal(
        doc.text(doc.item(tail, 0)),
        "tools/carla_lane_oracle/coverage-followup-migration.json",
    )


def test_the_paths_and_migration_are_read_before_the_tail() raises:
    """The cleanup paths stay ahead of the migration record and the tail."""
    var doc = PyJson.parse(cleanup_protected_bundle())
    assert_equal(doc.key(doc.root, 0), "paths")
    assert_equal(doc.key(doc.root, 1), "migration")
    assert_equal(doc.key(doc.root, 2), "records")
    assert_equal(doc.key(doc.root, 3), "tail")
    var sources = doc.at(doc.at(doc.root, "paths"), "sources")
    assert_equal(doc.length(sources), 3)
    var migration = doc.at(doc.root, "migration")
    assert_equal(
        doc.text(doc.at(migration, "path")),
        "tools/carla_lane_oracle/reviewed-cleanup-migration.json",
    )
    var tail = doc.at(doc.root, "tail")
    assert_equal(doc.length(tail), 14)
    assert_equal(
        doc.text(doc.item(tail, 0)),
        "tools/carla_lane_oracle/coverage-followup-migration.json",
    )


def test_the_frozen_and_invariant_inputs_follow_the_cleanup_bundle() raises:
    """The cleanup bundle stays ahead of the frozen and invariant inputs."""
    var doc = PyJson.parse(cleanup_composed_inputs())
    assert_equal(doc.key(doc.root, 0), "cleanup")
    assert_equal(doc.key(doc.root, 1), "frozen")
    assert_equal(doc.key(doc.root, 2), "invariant")
    var cleanup = doc.at(doc.root, "cleanup")
    assert_equal(doc.length(doc.at(doc.at(cleanup, "paths"), "sources")), 3)
    assert_equal(doc.length(doc.at(cleanup, "tail")), 14)
    var frozen = doc.at(doc.root, "frozen")
    assert_equal(
        doc.text(doc.at(doc.at(frozen, "paths"), "source")),
        "extensions/carla/curve_frozen_arc.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.at(frozen, "migration"), "path")),
        "tools/carla_lane_oracle/frozen-arc-producer-migration.json",
    )
    var invariant = doc.at(doc.root, "invariant")
    assert_equal(
        doc.text(doc.at(doc.at(invariant, "invariant"), "path")),
        "tools/carla_lane_oracle/coverage-invariant-migration.json",
    )
    assert_equal(doc.length(doc.at(invariant, "tail")), 6)


def main() raises:
    """Run the cleanup protected-input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
