# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The pose report matches the reviewed Python lane-center derivatives."""

from std.os.path import realpath
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._sha256 import sha256_hex
from tools._lane_reports import output_directory, repository_root
from tools.carla_pose_report import publish


comptime _REPORT = (
    "619f64d539d0edf4a152e00e255188125223445445f84a3e65657e586eb29c08"
)
"""SHA-256 of `pose-results.json` from `poses.py`."""


def test_report_matches_the_python_bytes() raises:
    var root = repository_root(realpath("."))
    var text = publish(root, "/tmp/pose-report-test")
    assert_equal(sha256_hex(text.as_bytes()), _REPORT)
    var written = Path("/tmp/pose-report-test/pose-results.json").read_text()
    assert_equal(written, text)
    assert_equal(output_directory(root, ""), root + "/out/carla-lane-oracle")
    assert_equal(output_directory(root, "/tmp/out"), "/tmp/out")
    assert_true(
        Path(root + "/tools/fixtures/carla_lane_constants.json").exists()
    )
    with assert_raises(contains="cannot find"):
        _ = repository_root("/tmp")
    with assert_raises(contains="cannot find"):
        _ = repository_root("missing")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
