# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The companion migration record paths stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._record_paths import record_paths


def test_companion_record_paths_stay_reviewed() raises:
    """Each companion record keeps its historical path."""
    var doc = PyJson.parse(record_paths())
    assert_equal(doc.length(doc.root), 5)
    assert_equal(doc.key(doc.root, 0), "accepted")
    assert_equal(doc.key(doc.root, 1), "lane_control")
    assert_equal(doc.key(doc.root, 2), "reviewed_cleanup")
    assert_equal(doc.key(doc.root, 3), "winner_sign")
    assert_equal(doc.key(doc.root, 4), "runtime_pins")
    assert_equal(
        doc.text(doc.at(doc.root, "accepted")),
        "tools/carla_lane_oracle/accepted-successor-migration.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "lane_control")),
        "tools/carla_lane_oracle/lane-control-migration.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "reviewed_cleanup")),
        "tools/carla_lane_oracle/reviewed-cleanup-migration.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "winner_sign")),
        "tools/carla_lane_oracle/winner-sign-query-migration.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "runtime_pins")),
        "tools/carla_lane_oracle/runtime-source-pins.json",
    )


def main() raises:
    """Run the companion record path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
