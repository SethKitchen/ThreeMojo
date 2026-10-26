# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Four reviewed fixtures keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.reviewed_fixture_matches import reviewed_fixture_matches


def _copy(root: String) raises:
    """Copy the four reviewed fixtures.

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
            root + "/tests",
            root + "/docs/validation",
            root + "/tools/carla_lane_oracle",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tests/test_carla_waypoint_stations.mojo")
    files.append("docs/validation/scaled-float32-746.md")
    files.append("docs/validation/carla-witness-format-successor.md")
    files.append(
        "tools/carla_lane_oracle/test_expectation_binding_successor.py"
    )

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_reviewed_fixtures_hold() raises:
    """The four reviewed fixtures keep their reviewed digests."""
    reviewed_fixture_matches(".")
    reviewed_fixture_matches("./")
    reviewed_fixture_matches("docs/..")


def test_a_changed_station_fixture_is_refused() raises:
    """A changed station fixture is refused."""
    var root = "/tmp/reviewed-fixture-station"
    _copy(root)
    var path = root + "/tests/test_carla_waypoint_stations.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "station correctness fixture changed:"
            " tests/test_carla_waypoint_stations.mojo"
        )
    ):
        reviewed_fixture_matches(root)


def test_a_changed_expectation_binding_is_refused() raises:
    """A changed expectation binding is refused."""
    var root = "/tmp/reviewed-fixture-expectation"
    _copy(root)
    var path = (
        root + "/tools/carla_lane_oracle/test_expectation_binding_successor.py"
    )
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "PR760 physical input changed: "
            + "tools/carla_lane_oracle/test_expectation_binding_successor.py"
        )
    ):
        reviewed_fixture_matches(root)


def main() raises:
    """Run the reviewed fixture tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
