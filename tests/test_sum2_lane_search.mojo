# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live lane search keeps the reviewed spans and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sum2_lane_search import sum2_lane_search


def _copy(root: String) raises:
    """Copy the lane-search inputs.

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


def test_the_live_lane_search_holds() raises:
    """The live search matches the pin after the reviewed spans."""
    sum2_lane_search(".")
    sum2_lane_search("./")


def test_a_changed_lane_search_body_is_refused() raises:
    """A changed search body is refused."""
    var root = "/tmp/sum2-lane-search-body"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "var sampled_checked = False",
            "var sampled_checked = True",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: "
            + "lane_refinement:_run_lane_search"
        )
    ):
        sum2_lane_search(root)


def test_a_moved_expansion_context_is_refused() raises:
    """A moved expansion context is refused."""
    var root = "/tmp/sum2-lane-search-span"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "Admit finite interpolation width before the derivative tests.",
            "Admit finite interpolation width after the derivative tests.",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: "
            + "lane_refinement:_run_lane_search"
        )
    ):
        sum2_lane_search(root)


def main() raises:
    """Run the lane-search tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
