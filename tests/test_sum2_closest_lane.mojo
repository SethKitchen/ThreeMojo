# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live closest-lane certificate keeps the deviation skip and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sum2_closest_lane import sum2_closest_lane


def _copy(root: String) raises:
    """Copy the closest-lane inputs.

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
    files.append("extensions/carla/map.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_closest_lane_certificate_holds() raises:
    """The live certificate matches the pin after the deviation skip."""
    sum2_closest_lane(".")
    sum2_closest_lane("./")


def test_a_changed_closest_lane_body_is_refused() raises:
    """A changed certificate body is refused."""
    var root = "/tmp/sum2-closest-lane-body"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "improves = order < 0 or (order == 0 and index < indices[best])",
            "improves = order < 1 or (order == 0 and index < indices[best])",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: "
            + "map:_closest_lane_certificate_with_work"
        )
    ):
        sum2_closest_lane(root)


def test_a_removed_deviation_skip_is_refused() raises:
    """A removed deviation skip is refused."""
    var root = "/tmp/sum2-closest-lane-skip"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "if _indexed_curve_lower(key, segment.deviation) > best_radius:",
            (
                "if _indexed_curve_lower(key, self._curve_deviation) >"
                " best_radius:"
            ),
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: "
            + "map:_closest_lane_certificate_with_work"
        )
    ):
        sum2_closest_lane(root)


def main() raises:
    """Run the closest-lane certificate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
