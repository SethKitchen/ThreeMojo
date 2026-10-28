# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live Map inventories keep the reviewed spans and the pins."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_map_inventory import sum2_map_inventory


def _copy(root: String) raises:
    """Copy the Map inventory inputs.

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


def test_the_live_map_inventories_hold() raises:
    """The restored Map modules match the pinned use digests."""
    sum2_map_inventory(".")
    sum2_map_inventory("./")
    sum2_map_inventory("extensions/..")


def test_a_moved_map_span_is_refused() raises:
    """A moved Map span is refused."""
    var root = "/tmp/sum2-map-inventory-map"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "from std.hash import Hasher", "from std.hashlib import Hasher"
        )
    )
    with assert_raises(
        contains="global protected-helper use/import inventory changed: map"
    ):
        sum2_map_inventory(root)


def test_a_moved_map_builder_span_is_refused() raises:
    """A moved map-builder span is refused."""
    var root = "/tmp/sum2-map-inventory-builder"
    _copy(root)
    var path = root + "/extensions/carla/map_builder.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace("with_arc_si as with_arc", "with_arc_si as with_arc_moved")
    )
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "map_builder"
        )
    ):
        sum2_map_inventory(root)


def test_a_changed_map_use_is_refused() raises:
    """A changed protected helper use is refused."""
    var root = "/tmp/sum2-map-inventory-use"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text("var marker = 1\n" + Path(path).read_text())
    with assert_raises(
        contains="global protected-helper use/import inventory changed: map"
    ):
        sum2_map_inventory(root)


def test_an_empty_map_module_is_refused() raises:
    """An empty Map module is refused."""
    var root = "/tmp/sum2-map-inventory-empty"
    _copy(root)
    Path(root + "/extensions/carla/map.mojo").write_text("")
    with assert_raises(
        contains="global protected-helper use/import inventory changed: map"
    ):
        sum2_map_inventory(root)


def test_a_non_string_map_inventory_pin_is_refused() raises:
    """An inventory pin that is not a string is refused."""
    var root = "/tmp/sum2-map-inventory-pin"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"protected_inventory":{"extensions/carla/map.mojo":0}}'
    )
    with assert_raises(
        contains="global protected-helper use/import inventory changed: map"
    ):
        sum2_map_inventory(root)


def main() raises:
    """Run the Map inventory tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
