# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live lane-refinement routing keeps the reviewed spans and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_lane_routing import sum2_lane_routing


comptime _MESSAGE = (
    "Sum2 guard import/declaration routing changed: lane_refinement"
)


def _copy(root: String) raises:
    """Copy the lane-routing inputs.

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
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_lane_routing_holds() raises:
    """The lane module matches the pin after the reviewed spans."""
    sum2_lane_routing(".")
    sum2_lane_routing("./")
    sum2_lane_routing("extensions/..")


def test_a_bare_road_info_import_is_refused() raises:
    """A bare road-info import is refused."""
    var root = "/tmp/sum2-lane-routing-bare"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane).read_text().replace("_info_index_si as ", "")
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def test_a_removed_variant_import_is_refused() raises:
    """A removed Variant import is refused."""
    var root = "/tmp/sum2-lane-routing-variant"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane).read_text().replace("from std.utils import Variant\n", "")
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def test_a_changed_expansion_block_is_refused() raises:
    """A changed expansion block is refused."""
    var root = "/tmp/sum2-lane-routing-block"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "A cached expansion is keyed",
            "A cached expansion was keyed",
        )
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def test_a_changed_lane_routing_statement_is_refused() raises:
    """A changed top-level routing statement is refused."""
    var root = "/tmp/sum2-lane-routing-body"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "def _legacy_square(",
            "var marker = 1\ndef _legacy_square(",
        )
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def test_a_renamed_cache_key_is_refused() raises:
    """A renamed cache-key marker is refused."""
    var root = "/tmp/sum2-lane-routing-start"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace("def _same_cache_key(\n", "def _same_cache_key_moved(\n")
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def test_a_renamed_lane_search_is_refused() raises:
    """A renamed lane-search marker is refused."""
    var root = "/tmp/sum2-lane-routing-end"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace("def _run_lane_search(\n", "def _run_lane_search_moved(\n")
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def test_a_search_marker_before_the_block_is_refused() raises:
    """A search marker before the expansion block is refused."""
    var root = "/tmp/sum2-lane-routing-order"
    _copy(root)
    var lane = root + "/extensions/carla/lane_refinement.mojo"
    var text = Path(lane).read_text()
    text = text.replace(
        "def _run_lane_search(\n", "def _run_lane_search_moved(\n"
    )
    text = text.replace(
        "def _same_cache_key(\n",
        "def _run_lane_search(\ndef _same_cache_key(\n",
    )
    Path(lane).write_text(text)
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def test_an_empty_lane_module_is_refused() raises:
    """An empty lane module is refused."""
    var root = "/tmp/sum2-lane-routing-empty"
    _copy(root)
    Path(root + "/extensions/carla/lane_refinement.mojo").write_text("")
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def test_a_non_string_lane_routing_pin_is_refused() raises:
    """A routing pin that is not a string is refused."""
    var root = "/tmp/sum2-lane-routing-pin"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tools/carla_lane_oracle/sum2-guard-pins.json").write_text(
        '{"callers":{"lane_refinement":{"routing":0}}}'
    )
    with assert_raises(contains=_MESSAGE):
        sum2_lane_routing(root)


def main() raises:
    """Run the lane-routing tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
