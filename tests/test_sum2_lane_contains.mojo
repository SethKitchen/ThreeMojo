# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live lane-certificate caller keeps the SI width calls and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sum2_lane_contains import sum2_lane_contains


def _copy(root: String) raises:
    """Copy the lane-certificate inputs.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/extensions/carla",
            root + "/tools/carla_lane_oracle",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/carla/lane_refinement.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_lane_certificate_caller_holds() raises:
    """The live caller matches the pin after the SI width calls."""
    sum2_lane_contains(".")
    sum2_lane_contains("./")


def test_a_changed_lane_certificate_body_is_refused() raises:
    """A changed certificate body is refused."""
    var root = "/tmp/sum2-lane-contains-body"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "if middle <= cell.low or middle >= cell.high or cell.depth >= 96:",
            "if middle <= cell.low or middle >= cell.high or cell.depth >= 97:",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: "
            + "lane_refinement:_lane_certificate_contains"
        )
    ):
        sum2_lane_contains(root)


def test_a_dropped_width_comma_is_refused() raises:
    """A dropped trailing comma is refused."""
    var root = "/tmp/sum2-lane-contains-comma"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "road._lane_width_si(section, lane, certificate.s),\n    )",
            "road._lane_width_si(section, lane, certificate.s)\n    )",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: "
            + "lane_refinement:_lane_certificate_contains"
        )
    ):
        sum2_lane_contains(root)


def main() raises:
    """Run the lane-certificate caller tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
