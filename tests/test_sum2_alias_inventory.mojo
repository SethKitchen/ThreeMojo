# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live Sum2 alias inventory keeps the road-info alias and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sum2_alias_inventory import sum2_alias_inventory


def _copy(root: String) raises:
    """Copy the alias-inventory inputs.

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
    files.append("extensions/carla/curve_sample_dispatch.mojo")
    files.append("extensions/carla/lane_box_cover.mojo")
    files.append("extensions/carla/lane_value_bounds.mojo")
    files.append("extensions/carla/spiral_domain_proof.mojo")
    files.append("extensions/carla/spiral_grouped_lane.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_alias_inventory_holds() raises:
    """The five caller modules match the pin after the alias restore."""
    sum2_alias_inventory(".")
    sum2_alias_inventory("./")
    sum2_alias_inventory("extensions/..")


def test_a_bare_road_info_import_is_refused() raises:
    """A bare road-info import is refused."""
    var root = "/tmp/sum2-alias-inventory-bare"
    _copy(root)
    var lane = root + "/extensions/carla/spiral_grouped_lane.mojo"
    Path(lane).write_text(
        Path(lane).read_text().replace("_info_index_si as ", "")
    )
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "spiral_grouped_lane"
        )
    ):
        sum2_alias_inventory(root)


def test_a_bare_lane_box_import_is_refused() raises:
    """A bare road-info import in the lane-box module is refused."""
    var root = "/tmp/sum2-alias-inventory-box"
    _copy(root)
    var box = root + "/extensions/carla/lane_box_cover.mojo"
    Path(box).write_text(
        Path(box).read_text().replace("_info_index_si as ", "")
    )
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "lane_box_cover"
        )
    ):
        sum2_alias_inventory(root)


def test_a_changed_protected_use_is_refused() raises:
    """A changed protected helper use is refused."""
    var root = "/tmp/sum2-alias-inventory-use"
    _copy(root)
    var proof = root + "/extensions/carla/spiral_domain_proof.mojo"
    Path(proof).write_text(
        Path(proof)
        .read_text()
        .replace(
            "if not _sum2_supported_environment():",
            "if not _sum2_supported_environment_moved():",
        )
    )
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "spiral_domain_proof"
        )
    ):
        sum2_alias_inventory(root)


def test_an_empty_alias_module_is_refused() raises:
    """An empty caller module is refused."""
    var root = "/tmp/sum2-alias-inventory-empty"
    _copy(root)
    Path(root + "/extensions/carla/curve_sample_dispatch.mojo").write_text("")
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "curve_sample_dispatch"
        )
    ):
        sum2_alias_inventory(root)


def test_a_non_string_inventory_pin_is_refused() raises:
    """An inventory pin that is not a string is refused."""
    var root = "/tmp/sum2-alias-inventory-pin"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"protected_inventory":{"extensions/carla/curve_sample_dispatch.mojo":0}}'
    )
    with assert_raises(
        contains=(
            "global protected-helper use/import inventory changed: "
            + "curve_sample_dispatch"
        )
    ):
        sum2_alias_inventory(root)


def main() raises:
    """Run the alias-inventory tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
