# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shared-helper fixtures keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.shared_helper_fixtures import shared_helper_fixtures


def _copy(root: String) raises:
    """Copy the reviewed shared-helper fixtures.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(["mkdir", "-p", root + "/tests"], 10.0)
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tests/test_carla_curve_distance.mojo")
    files.append("tests/test_carla_curve_distance_fraction.mojo")
    files.append("tests/test_xml.mojo")
    files.append("tests/test_carla_render_weathers.mojo")

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_shared_helper_fixtures_hold() raises:
    """The 4 shared-helper fixtures keep their reviewed digests."""
    shared_helper_fixtures(".")
    shared_helper_fixtures("./")
    shared_helper_fixtures("tests/..")


def test_a_changed_curve_distance_fixture_is_refused() raises:
    """A changed curve-distance fixture is refused."""
    var root = "/tmp/shared-helper-fixture-distance"
    _copy(root)
    var path = root + "/tests/test_carla_curve_distance.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "shared-helper fixture changed:"
            " tests/test_carla_curve_distance.mojo"
        )
    ):
        shared_helper_fixtures(root)


def test_a_changed_weather_fixture_is_refused() raises:
    """A changed weather fixture is refused."""
    var root = "/tmp/shared-helper-fixture-weather"
    _copy(root)
    var path = root + "/tests/test_carla_render_weathers.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "shared-helper fixture changed: "
            + "tests/test_carla_render_weathers.mojo"
        )
    ):
        shared_helper_fixtures(root)


def main() raises:
    """Run the shared-helper fixture tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
