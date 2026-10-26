# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live Map routing keeps the reviewed spans and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_map_routing import sum2_map_routing


comptime _MESSAGE = "Sum2 guard import/declaration routing changed: map"


def _copy(root: String) raises:
    """Copy the Map routing inputs.

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


def test_the_live_map_routing_holds() raises:
    """The Map module matches the pin after the reviewed spans."""
    sum2_map_routing(".")
    sum2_map_routing("./")
    sum2_map_routing("extensions/..")


def test_a_changed_map_docstring_is_refused() raises:
    """A changed Map docstring is refused."""
    var root = "/tmp/sum2-map-routing-doc"
    _copy(root)
    var source = root + "/extensions/carla/map.mojo"
    Path(source).write_text(
        Path(source)
        .read_text()
        .replace(
            "they correct one CARLA approximation",
            "they keep one CARLA approximation",
        )
    )
    with assert_raises(contains=_MESSAGE):
        sum2_map_routing(root)


def test_a_changed_map_declaration_is_refused() raises:
    """A changed Map declaration is refused."""
    var root = "/tmp/sum2-map-routing-body"
    _copy(root)
    var source = root + "/extensions/carla/map.mojo"
    Path(source).write_text(
        Path(source)
        .read_text()
        .replace("struct Map(", "var marker = 1\nstruct Map(")
    )
    with assert_raises(contains=_MESSAGE):
        sum2_map_routing(root)


def test_an_empty_map_module_is_refused() raises:
    """An empty Map module is refused."""
    var root = "/tmp/sum2-map-routing-empty"
    _copy(root)
    Path(root + "/extensions/carla/map.mojo").write_text("")
    with assert_raises(contains=_MESSAGE):
        sum2_map_routing(root)


def test_a_non_string_map_routing_pin_is_refused() raises:
    """A routing pin that is not a string is refused."""
    var root = "/tmp/sum2-map-routing-pin"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"callers":{"map":{"routing":0}}}'
    )
    with assert_raises(contains=_MESSAGE):
        sum2_map_routing(root)


def main() raises:
    """Run the Map routing tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
