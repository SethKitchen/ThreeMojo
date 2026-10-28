# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live lane-geometry inventory keeps the SI constructors and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_geometry_inventory import sum2_geometry_inventory


comptime _MESSAGE = (
    "global protected-helper use/import inventory changed: lane_geometry"
)


def _copy(root: String) raises:
    """Copy the lane-geometry inventory inputs.

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
    files.append("extensions/carla/lane_geometry.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_geometry_inventory_holds() raises:
    """The lane geometry matches the pin after the constructor restore."""
    sum2_geometry_inventory(".")
    sum2_geometry_inventory("./")
    sum2_geometry_inventory("extensions/..")


def test_a_bare_directed_point_is_refused() raises:
    """A bare directed-point constructor is refused."""
    var root = "/tmp/sum2-geometry-inventory-bare"
    _copy(root)
    var lane = root + "/extensions/carla/lane_geometry.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "if geometry.kind == LINE:\n        return DirectedPoint._from_si(",
            "if geometry.kind == LINE:\n        return DirectedPoint(",
        )
    )
    with assert_raises(contains=_MESSAGE):
        sum2_geometry_inventory(root)


def test_a_changed_geometry_use_is_refused() raises:
    """A changed protected helper use is refused."""
    var root = "/tmp/sum2-geometry-inventory-use"
    _copy(root)
    var lane = root + "/extensions/carla/lane_geometry.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "from extensions.carla.geometry import (",
            "var marker = 1\nfrom extensions.carla.geometry import (",
        )
    )
    with assert_raises(contains=_MESSAGE):
        sum2_geometry_inventory(root)


def test_an_empty_geometry_module_is_refused() raises:
    """An empty lane-geometry module is refused."""
    var root = "/tmp/sum2-geometry-inventory-empty"
    _copy(root)
    Path(root + "/extensions/carla/lane_geometry.mojo").write_text("")
    with assert_raises(contains=_MESSAGE):
        sum2_geometry_inventory(root)


def test_a_non_string_geometry_pin_is_refused() raises:
    """An inventory pin that is not a string is refused."""
    var root = "/tmp/sum2-geometry-inventory-pin"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"protected_inventory":{"extensions/carla/lane_geometry.mojo":0}}'
    )
    with assert_raises(contains=_MESSAGE):
        sum2_geometry_inventory(root)


def main() raises:
    """Run the lane-geometry inventory tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
