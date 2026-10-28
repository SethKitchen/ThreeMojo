# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The coverage-invariant pin file names stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._invariant_labels import (
    invariant_labels,
    invariant_labels_with_migration,
)
from tools._migration_records import migration_records
from tools._python_json import PyJson


def test_invariant_pin_files_stay_runtime_then_guard() raises:
    """The runtime pin file stays ahead of the guard pin file."""
    var doc = PyJson.parse(invariant_labels())
    assert_equal(doc.key(doc.root, 0), "filenames")
    assert_equal(doc.key(doc.root, 1), "after")
    assert_equal(doc.key(doc.root, 2), "before")
    var names = doc.at(doc.root, "filenames")
    assert_equal(doc.length(names), 2)
    assert_equal(doc.text(doc.item(names, 0)), "runtime-source-pins.json")
    assert_equal(doc.text(doc.item(names, 1)), "sum2-guard-pins.json")
    assert_equal(doc.text(doc.at(doc.root, "after")), "after")
    assert_equal(doc.text(doc.at(doc.root, "before")), "before")
    assert_equal(
        doc.text(doc.at(doc.root, "successor")), "complete successor changed: "
    )
    assert_equal(
        doc.text(doc.at(doc.root, "prior")),
        "tools/carla_lane_oracle/frozen-arc-producer-migration.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "oracle")), "tools/carla_lane_oracle"
    )


def test_the_labels_are_read_before_the_migration_record() raises:
    """The pin file names stay ahead of the invariant migration path."""
    var text = invariant_labels_with_migration()
    var doc = PyJson.parse(text)
    var labels = doc.at(doc.root, "labels")
    var migration = doc.at(doc.root, "migration")
    var records = PyJson.parse(migration_records())
    var item = records.at(records.root, "invariant")
    assert_equal(text.find('{"labels":'), 0)
    assert_equal(doc.key(labels, 0), "filenames")
    assert_equal(
        doc.text(doc.at(labels, "prior")),
        "tools/carla_lane_oracle/frozen-arc-producer-migration.json",
    )
    assert_equal(
        doc.text(doc.at(migration, "path")),
        records.text(records.at(item, "path")),
    )
    assert_equal(
        doc.text(doc.at(migration, "sha")),
        records.text(records.at(item, "sha")),
    )


def main() raises:
    """Run the coverage-invariant label tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
