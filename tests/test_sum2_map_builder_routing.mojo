# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live map-builder routing keeps the reviewed spans and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_map_builder_routing import sum2_map_builder_routing


comptime _MESSAGE = "Sum2 guard import/declaration routing changed: map_builder"


def _copy(root: String) raises:
    """Copy the map-builder routing inputs.

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
    files.append("extensions/carla/map_builder.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_map_builder_routing_holds() raises:
    """The map builder matches the pin after the reviewed spans."""
    sum2_map_builder_routing(".")
    sum2_map_builder_routing("./")
    sum2_map_builder_routing("extensions/..")


def test_a_changed_geometry_alias_is_refused() raises:
    """A changed geometry alias is refused."""
    var root = "/tmp/sum2-map-builder-routing-alias"
    _copy(root)
    var builder = root + "/extensions/carla/map_builder.mojo"
    Path(builder).write_text(
        Path(builder)
        .read_text()
        .replace("with_arc_si as with_arc", "with_arc_si as with_arc_moved")
    )
    with assert_raises(contains=_MESSAGE):
        sum2_map_builder_routing(root)


def test_a_changed_map_builder_statement_is_refused() raises:
    """A changed top-level routing statement is refused."""
    var root = "/tmp/sum2-map-builder-routing-body"
    _copy(root)
    var builder = root + "/extensions/carla/map_builder.mojo"
    Path(builder).write_text(
        Path(builder)
        .read_text()
        .replace(
            "struct MapBuilder(Movable):",
            "var marker = 1\nstruct MapBuilder(Movable):",
        )
    )
    with assert_raises(contains=_MESSAGE):
        sum2_map_builder_routing(root)


def test_an_empty_map_builder_is_refused() raises:
    """An empty map builder is refused."""
    var root = "/tmp/sum2-map-builder-routing-empty"
    _copy(root)
    Path(root + "/extensions/carla/map_builder.mojo").write_text("")
    with assert_raises(contains=_MESSAGE):
        sum2_map_builder_routing(root)


def test_a_non_string_map_builder_routing_pin_is_refused() raises:
    """A routing pin that is not a string is refused."""
    var root = "/tmp/sum2-map-builder-routing-pin"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"callers":{"map_builder":{"routing":0}}}'
    )
    with assert_raises(contains=_MESSAGE):
        sum2_map_builder_routing(root)


def main() raises:
    """Run the map-builder routing tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
