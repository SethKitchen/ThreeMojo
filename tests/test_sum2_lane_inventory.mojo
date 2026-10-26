# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live lane-refinement inventory keeps the predecessor digest."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_lane_inventory import sum2_lane_inventory


comptime _MESSAGE = (
    "global protected-helper use/import inventory changed: lane_refinement"
)


def _copy(root: String) raises:
    """Copy the lane-inventory inputs.

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
    files.append("tools/carla_lane_oracle/cache-key-migration.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_lane_inventory_holds() raises:
    """The restored predecessor matches the pinned use digest."""
    sum2_lane_inventory(".")
    sum2_lane_inventory("./")
    sum2_lane_inventory("extensions/..")


def test_a_moved_lane_span_is_refused() raises:
    """A moved lane-refinement span is refused."""
    var root = "/tmp/sum2-lane-inventory-span"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            (
                "from extensions.carla.road_info import _info_index_si as"
                " info_index"
            ),
            "from extensions.carla.road_info import info_index",
        )
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_inventory(root)


def test_a_changed_lane_successor_is_refused() raises:
    """A source edit outside the spans is refused."""
    var root = "/tmp/sum2-lane-inventory-use"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text("var marker = 1\n" + Path(lane).read_text())
    with assert_raises(contains=_MESSAGE):
        sum2_lane_inventory(root)


def test_a_changed_lane_digest_is_refused() raises:
    """A changed inventory pin is refused."""
    var root = "/tmp/sum2-lane-inventory-digest"
    _copy(root)
    var pins = root + "/tools/carla_lane_oracle/sum2-guard-pins.json"
    Path(pins).write_text(
        Path(pins)
        .read_text()
        .replace(
            "14e15c91e1c3aa4b1885e74713173d3c00867510bcb8a33065bd330a62597942",
            "0000000000000000000000000000000000000000000000000000000000000000",
        )
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_inventory(root)


def test_a_changed_migration_record_is_refused() raises:
    """A changed cache-key migration record is refused."""
    var root = "/tmp/sum2-lane-inventory-migration"
    _copy(root)
    var migration = root + "/tools/carla_lane_oracle/cache-key-migration.json"
    Path(migration).write_text(Path(migration).read_text() + "\n")
    with assert_raises(contains="migration record changed"):
        sum2_lane_inventory(root)


def test_an_empty_lane_module_is_refused() raises:
    """An empty lane-refinement module is refused."""
    var root = "/tmp/sum2-lane-inventory-empty"
    _copy(root)
    Path(root + "/extensions/carla/lane_refinement.mojo").write_text("")
    with assert_raises(contains=_MESSAGE):
        sum2_lane_inventory(root)


def test_a_non_string_lane_pin_is_refused() raises:
    """An inventory pin that is not a string is refused."""
    var root = "/tmp/sum2-lane-inventory-pin"
    _copy(root)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"protected_inventory":{"extensions/carla/lane_refinement.mojo":0}}'
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_inventory(root)


def main() raises:
    """Run the lane-inventory tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
