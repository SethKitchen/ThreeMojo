# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The full-audit authority files keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.full_audit_authority import full_audit_authority


def _copy(root: String) raises:
    """Copy the four authority files.

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
    files.append("tools/carla_lane_oracle/full-audit-cleanup-successor.json")
    files.append("tools/carla_lane_oracle/pr760-source-image.json")
    files.append("tools/carla_lane_oracle/pr760-owner-predecessor.txt")
    files.append("tools/carla_lane_oracle/consumer-successor-ledger.json")
    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_authority_files_hold() raises:
    """The four authority files keep their reviewed digests."""
    full_audit_authority(".")
    full_audit_authority("./")
    full_audit_authority("tools/..")


def test_a_changed_cleanup_record_is_refused() raises:
    """A changed cleanup record is refused."""
    var root = "/tmp/full-audit-authority-record"
    _copy(root)
    var path = (
        root + "/tools/carla_lane_oracle/full-audit-cleanup-successor.json"
    )
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(contains="immutable successor record changed"):
        full_audit_authority(root)


def test_a_changed_consumer_ledger_is_refused() raises:
    """A changed consumer ledger is refused."""
    var root = "/tmp/full-audit-authority-ledger"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/consumer-successor-ledger.json"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(contains="unreviewed consumer ledger"):
        full_audit_authority(root)


def main() raises:
    """Run the full-audit authority tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
