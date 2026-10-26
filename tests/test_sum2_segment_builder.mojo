# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live segment builder stays a Map method and matches the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_segment_builder import sum2_segment_builder


def _copy(root: String) raises:
    """Copy the segment-builder inputs.

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


def test_the_live_segment_builder_holds() raises:
    """The live builder matches the pin after the SI helpers."""
    sum2_segment_builder(".")
    sum2_segment_builder("./")


def test_a_changed_segment_builder_body_is_refused() raises:
    """A changed builder body is refused."""
    var root = "/tmp/sum2-segment-builder-body"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "comptime angle_threshold = 3.14159265358979323846 / 100.0",
            "comptime angle_threshold = 3.14159265358979323846 / 101.0",
        )
    )
    with assert_raises(
        contains="Sum2 complete guarded caller changed: map:_create_segments"
    ):
        sum2_segment_builder(root)


def test_a_bare_section_length_is_refused() raises:
    """A bare section-length call is refused."""
    var root = "/tmp/sum2-segment-builder-length"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "self.roads[at[0]]._section_length_si(",
            "self.roads[at[0]].section_length(",
        )
    )
    with assert_raises(
        contains="Sum2 complete guarded caller changed: map:_create_segments"
    ):
        sum2_segment_builder(root)


def main() raises:
    """Run the segment builder tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
