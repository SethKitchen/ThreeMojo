# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The coverage-invariant pin file names stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._invariant_labels import invariant_labels
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


def main() raises:
    """Run the coverage-invariant label tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
