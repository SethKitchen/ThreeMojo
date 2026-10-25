# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live Sum2 alias routing keeps the road-info alias and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sum2_alias_routing import sum2_alias_routing


def _copy(root: String) raises:
    """Copy the alias-routing inputs.

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
    files.append("extensions/carla/spiral_domain_proof.mojo")
    files.append("extensions/carla/curve_sample_dispatch.mojo")
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


def test_the_live_alias_routing_holds() raises:
    """The four caller modules match the pin after the alias restore."""
    sum2_alias_routing(".")
    sum2_alias_routing("./")
    sum2_alias_routing("extensions/..")


def test_a_bare_road_info_import_is_refused() raises:
    """A bare road-info import is refused."""
    var root = "/tmp/sum2-alias-routing-bare"
    _copy(root)
    var proof = root + "/extensions/carla/spiral_domain_proof.mojo"
    Path(proof).write_text(
        Path(proof).read_text().replace("_info_index_si as ", "")
    )
    with assert_raises(
        contains=(
            "Sum2 guard import/declaration routing changed: "
            + "spiral_domain_proof"
        )
    ):
        sum2_alias_routing(root)


def test_a_changed_alias_routing_is_refused() raises:
    """A changed top-level routing statement is refused."""
    var root = "/tmp/sum2-alias-routing-body"
    _copy(root)
    var lane = root + "/extensions/carla/spiral_grouped_lane.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "from extensions.carla.geometry import SPIRAL",
            "var marker = 1\nfrom extensions.carla.geometry import SPIRAL",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 guard import/declaration routing changed: "
            + "spiral_grouped_lane"
        )
    ):
        sum2_alias_routing(root)


def test_an_empty_alias_caller_is_refused() raises:
    """An empty caller module is refused."""
    var root = "/tmp/sum2-alias-routing-empty"
    _copy(root)
    Path(root + "/extensions/carla/curve_bounds.mojo").write_text("")
    with assert_raises(
        contains="Sum2 guard import/declaration routing changed: curve_bounds"
    ):
        sum2_alias_routing(root)


def test_a_non_string_routing_pin_is_refused() raises:
    """A routing pin that is not a string is refused."""
    var root = "/tmp/sum2-alias-routing-pin"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"callers":{"curve_bounds":{"routing":0}}}'
    )
    with assert_raises(
        contains="Sum2 guard import/declaration routing changed: curve_bounds"
    ):
        sum2_alias_routing(root)


def main() raises:
    """Run the alias-routing tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
