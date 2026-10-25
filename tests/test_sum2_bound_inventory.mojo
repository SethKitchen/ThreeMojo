# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live bound inventories keep the reviewed spans and the pins."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sum2_bound_inventory import sum2_bound_inventory


def _copy(root: String) raises:
    """Copy the bound-inventory inputs.

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
    files.append("extensions/carla/curve_bounds.mojo")
    files.append("extensions/carla/junction_bounds.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_bound_inventories_hold() raises:
    """The restored bound modules match the pinned use digests."""
    sum2_bound_inventory(".")
    sum2_bound_inventory("./")
    sum2_bound_inventory("extensions/..")


def test_a_moved_curve_bounds_span_is_refused() raises:
    """A moved curve-bounds span is refused."""
    var root = "/tmp/sum2-bound-inventory-curve"
    _copy(root)
    var path = root + "/extensions/carla/curve_bounds.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            (
                "from extensions.carla.road_info import _info_index_si as"
                " info_index"
            ),
            "from extensions.carla.road_info import info_index",
        )
    )
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "curve_bounds"
        )
    ):
        sum2_bound_inventory(root)


def test_a_moved_junction_span_is_refused() raises:
    """A moved junction-bounds span is refused."""
    var root = "/tmp/sum2-bound-inventory-junction"
    _copy(root)
    var path = root + "/extensions/carla/junction_bounds.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace("record._distance_si()", "record.distance()")
    )
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "junction_bounds"
        )
    ):
        sum2_bound_inventory(root)


def test_a_changed_bound_use_is_refused() raises:
    """A changed protected helper use is refused."""
    var root = "/tmp/sum2-bound-inventory-use"
    _copy(root)
    var path = root + "/extensions/carla/curve_bounds.mojo"
    Path(path).write_text("var marker = 1\n" + Path(path).read_text())
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "curve_bounds"
        )
    ):
        sum2_bound_inventory(root)


def test_an_empty_curve_bounds_module_is_refused() raises:
    """An empty curve-bounds module is refused."""
    var root = "/tmp/sum2-bound-inventory-empty"
    _copy(root)
    Path(root + "/extensions/carla/curve_bounds.mojo").write_text("")
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "curve_bounds"
        )
    ):
        sum2_bound_inventory(root)


def test_a_non_string_bound_pin_is_refused() raises:
    """An inventory pin that is not a string is refused."""
    var root = "/tmp/sum2-bound-inventory-pin"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"protected_inventory":{"extensions/carla/curve_bounds.mojo":0}}'
    )
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "curve_bounds"
        )
    ):
        sum2_bound_inventory(root)


def main() raises:
    """Run the bound-inventory tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
