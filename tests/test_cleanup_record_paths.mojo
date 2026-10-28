# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The cleanup record check returns the companion paths."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._record_paths import record_paths
from tools.carla_cleanup_gate import cleanup_record_paths


def test_the_companion_paths_follow_the_cleanup_record() raises:
    """A changed record fails before the companion paths are returned."""
    with assert_raises(
        contains="reviewed cleanup source contract: unreviewed migration record"
    ):
        _ = cleanup_record_paths(String("").as_bytes())
    var raw = Path(
        "tools/carla_lane_oracle/reviewed-cleanup-migration.json"
    ).read_bytes()
    assert_equal(cleanup_record_paths(raw), record_paths())


def main() raises:
    """Run the cleanup record path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
