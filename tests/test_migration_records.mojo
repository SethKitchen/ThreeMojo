# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The reviewed migration records keep their digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.migration_records import migration_records


def _copy(root: String) raises:
    """Copy the seventeen migration records.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tools/carla_lane_oracle/accepted-successor-migration.json")
    files.append("tools/carla_lane_oracle/border-parser-successor.json")
    files.append("tools/carla_lane_oracle/cache-key-migration.json")
    files.append("tools/carla_lane_oracle/conditioned-cubic-successor.json")
    files.append("tools/carla_lane_oracle/coverage-followup-migration.json")
    files.append("tools/carla_lane_oracle/coverage-invariant-migration.json")
    files.append(
        "tools/carla_lane_oracle/curve-support-dispatch-migration.json"
    )
    files.append("tools/carla_lane_oracle/frozen-arc-producer-migration.json")
    files.append("tools/carla_lane_oracle/grouped-y-successor-record.json")
    files.append("tools/carla_lane_oracle/raw-cut-inverse-migration.json")
    files.append("tools/carla_lane_oracle/render-actor-reuse-successor.json")
    files.append("tools/carla_lane_oracle/reviewed-cleanup-migration.json")
    files.append("tools/carla_lane_oracle/rounded-line-selector-migration.json")
    files.append(
        "tools/carla_lane_oracle/rounded-line-singleton-migration.json"
    )
    files.append("tools/carla_lane_oracle/runtime-boundary-successor.json")
    files.append("tools/carla_lane_oracle/runtime-view-successor.json")
    files.append("tools/carla_lane_oracle/speed-parser-successor.json")
    # Copied in this process: one `cp` for each file took most of the
    # five seconds a test may run.
    for path in files:
        Path(root + "/" + path).write_bytes(Path(path).read_bytes())


def test_the_live_migration_records_hold() raises:
    """The seventeen records keep their reviewed digests."""
    migration_records(".")
    migration_records("./")
    migration_records("tools/..")


def test_a_changed_accepted_record_is_refused() raises:
    """A changed accepted-successor record is refused."""
    var root = "/tmp/migration-records-accepted"
    _copy(root)
    var path = (
        root + "/tools/carla_lane_oracle/accepted-successor-migration.json"
    )
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(contains="unreviewed migration record"):
        migration_records(root)


def test_a_changed_speed_record_is_refused() raises:
    """A changed speed-parser record is refused."""
    var root = "/tmp/migration-records-speed"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/speed-parser-successor.json"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains="reviewed speed parser successor: unreviewed exact edge"
    ):
        migration_records(root)


def main() raises:
    """Run the migration-record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
