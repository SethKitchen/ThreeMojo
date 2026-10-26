# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The distance helper successor keeps its reviewed endpoint."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.distance_helper_successor import distance_helper_successor


def _copy(root: String) raises:
    """Copy the distance helper modules.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/extensions/carla", root + "/loaders"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/carla/curve_distance.mojo")
    files.append("extensions/carla/curve_interval.mojo")
    files.append("extensions/carla/render_sky.mojo")
    files.append("extensions/carla/render_weather.mojo")
    files.append("loaders/xml.mojo")
    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_distance_helper_successor_holds() raises:
    """The distance endpoint restores the interval helpers."""
    distance_helper_successor(".")
    distance_helper_successor("./")
    distance_helper_successor("extensions/..")


def test_a_changed_distance_endpoint_is_refused() raises:
    """A changed distance module is refused."""
    var root = "/tmp/distance-helper-endpoint"
    _copy(root)
    var path = root + "/extensions/carla/curve_distance.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains="unknown exact endpoint: extensions/carla/curve_distance.mojo"
    ):
        distance_helper_successor(root)


def test_a_changed_interval_helper_is_refused() raises:
    """A changed interval helper is refused."""
    var root = "/tmp/distance-helper-interval"
    _copy(root)
    var path = root + "/extensions/carla/curve_interval.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "return bitcast[DType.float64](bits + 1)",
            "return bitcast[DType.float64](bits + 2)",
        )
    )
    with assert_raises(
        contains=(
            "helper implementation differs: "
            + "extensions/carla/curve_distance.mojo:_next_up"
        )
    ):
        distance_helper_successor(root)


def main() raises:
    """Run the distance helper successor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
