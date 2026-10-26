# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shared-helper routing keeps its reviewed imports and call counts."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.shared_helper_routing import shared_helper_routing


def _copy(root: String) raises:
    """Copy the four shared-helper consumers.

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
    files.append("extensions/carla/render_sky.mojo")
    files.append("extensions/carla/render_weather.mojo")
    files.append("loaders/xml.mojo")
    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_shared_helper_routing_holds() raises:
    """The four consumers keep their imports and call counts."""
    shared_helper_routing(".")
    shared_helper_routing("./")
    shared_helper_routing("extensions/..")


def test_a_changed_import_is_refused() raises:
    """A changed distance import is refused."""
    var root = "/tmp/shared-helper-routing-import"
    _copy(root)
    var path = root + "/extensions/carla/curve_distance.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "from extensions.carla.curve_interval import _next_down, _next_up",
            "from extensions.carla.curve_interval import _next_up, _next_down",
        )
    )
    with assert_raises(
        contains="live import changed: extensions/carla/curve_distance.mojo"
    ):
        shared_helper_routing(root)


def test_a_changed_call_count_is_refused() raises:
    """A removed distance call is refused."""
    var root = "/tmp/shared-helper-routing-count"
    _copy(root)
    var path = root + "/extensions/carla/curve_distance.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "return Self(_next_down(low)", "return Self(_next_down_live(low)"
        )
    )
    with assert_raises(
        contains=(
            "live helper call count changed: "
            + "extensions/carla/curve_distance.mojo:_next_down"
        )
    ):
        shared_helper_routing(root)


def test_a_local_helper_is_refused() raises:
    """A local definition of an imported helper is refused."""
    var root = "/tmp/shared-helper-routing-hide"
    _copy(root)
    var path = root + "/extensions/carla/curve_distance.mojo"
    var text = (
        Path(path)
        .read_text()
        .replace(
            "return Self(_next_down(low), _next_up(high))",
            "return Self(low, _next_up(high))",
        )
    )
    Path(path).write_text(
        text
        + "\ndef _next_down(value: Float64) -> Float64:\n    return value\n"
    )
    with assert_raises(
        contains=(
            "local helper hides import:"
            " extensions/carla/curve_distance.mojo:_next_down"
        )
    ):
        shared_helper_routing(root)


def main() raises:
    """Run the shared-helper routing tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
