# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The reviewed migration paths and digests stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._migration_records import migration_records
from tools._python_json import PyJson


def test_reviewed_migration_records_stay_reviewed() raises:
    """Each checker keeps its migration path and digest."""
    var doc = PyJson.parse(migration_records())
    var cleanup = doc.at(doc.root, "cleanup")
    assert_equal(
        doc.text(doc.at(cleanup, "path")),
        "tools/carla_lane_oracle/reviewed-cleanup-migration.json",
    )
    assert_equal(
        doc.text(doc.at(cleanup, "sha")),
        "01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9",
    )
    var render = doc.at(doc.root, "render")
    assert_equal(
        doc.text(doc.at(render, "path")),
        "tools/carla_lane_oracle/render-actor-reuse-successor.json",
    )
    assert_equal(
        doc.text(doc.at(render, "sha")),
        "c4d146fe145289a1ad443956d2941d1e90186d448b8056f8be97d72f4f672771",
    )
    var singleton = doc.at(doc.root, "singleton")
    assert_equal(
        doc.text(doc.at(singleton, "path")),
        "tools/carla_lane_oracle/rounded-line-singleton-migration.json",
    )
    assert_equal(
        doc.text(doc.at(singleton, "sha")),
        "e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506",
    )
    var speed = doc.at(doc.root, "speed")
    assert_equal(
        doc.text(doc.at(speed, "path")),
        "tools/carla_lane_oracle/speed-parser-successor.json",
    )
    assert_equal(
        doc.text(doc.at(speed, "sha")),
        "47e949673fb8740816c06d455654c7e7ae43f65ce7d7568a201e83ae16c49364",
    )
    var runtime = doc.at(doc.root, "runtime")
    assert_equal(
        doc.text(doc.at(runtime, "path")),
        "tools/carla_lane_oracle/runtime-boundary-successor.json",
    )
    assert_equal(
        doc.text(doc.at(runtime, "sha")),
        "992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00",
    )
    var dispatch = doc.at(doc.root, "dispatch")
    assert_equal(
        doc.text(doc.at(dispatch, "path")),
        "tools/carla_lane_oracle/curve-support-dispatch-migration.json",
    )
    assert_equal(
        doc.text(doc.at(dispatch, "sha")),
        "1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f",
    )
    var invariant = doc.at(doc.root, "invariant")
    assert_equal(
        doc.text(doc.at(invariant, "path")),
        "tools/carla_lane_oracle/coverage-invariant-migration.json",
    )
    assert_equal(
        doc.text(doc.at(invariant, "sha")),
        "56a72d9bccbf9e7b8a6b51db2b9944ef4bbf55d9bcc7311f7f9615be3b3b36ac",
    )
    var frozen = doc.at(doc.root, "frozen")
    assert_equal(
        doc.text(doc.at(frozen, "path")),
        "tools/carla_lane_oracle/frozen-arc-producer-migration.json",
    )
    assert_equal(
        doc.text(doc.at(frozen, "sha")),
        "70091e23400193257514363570187b47890e3c08c352fe79eb08bf291737cc9f",
    )


def main() raises:
    """Run the migration record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
