# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The count endpoint and the historical Map are the admitted sources."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._map_score_predecessor import (
    restored_deviation_map,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import token_sha256
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.count_source import count_source, count_source_check
from tools.frontier_predecessor import frontier_predecessor_source
from tools.optional_predecessor import optional_predecessor_source
from tools.score_predecessor import score_predecessor_source
from tools.support_predecessor import support_predecessor_source


comptime _HISTORICAL_SHA = (
    "52dd32213d64275be94ba714bc9b6a57c28f5ba1303525ef1a1aac20b4743c07"
)
comptime _HISTORICAL_TOKEN = (
    "0524759d2516ef9b269c2286cd0bbc01ed8b462718ac33ac276db510739de0c0"
)


def _count() raises -> String:
    """Return the reviewed count endpoint.

    Returns:
        The count endpoint of the live Map module.

    Raises:
        Error: The live Map changed.
    """
    var score = score_endpoint(station_endpoint(restored_deviation_map()))
    var frontier = score_predecessor_source(score)
    var support = frontier_predecessor_source(frontier)
    var optional = support_predecessor_source(support)
    return optional_predecessor_source(optional)


def _copy(root: String) raises:
    """Copy the Map module and the count record.

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
    var copied = run_program(
        [
            "cp",
            "extensions/carla/map.mojo",
            root + "/extensions/carla/map.mojo",
        ],
        10.0,
    )
    if copied.status != 0:
        raise Error(copied.output)
    var record = run_program(
        [
            "cp",
            "tools/carla_lane_oracle/seed-count-successor.json",
            root + "/tools/carla_lane_oracle/seed-count-successor.json",
        ],
        10.0,
    )
    if record.status != 0:
        raise Error(record.output)


def test_the_live_count_source_holds() raises:
    """The count endpoint and the historical Map are admitted."""
    count_source_check(".")
    count_source_check("./")
    count_source_check("extensions/..")
    var historical = count_source(_count())
    assert_equal(sha256_hex(historical.as_bytes()), _HISTORICAL_SHA)
    assert_equal(token_sha256(historical), _HISTORICAL_TOKEN)
    var again = count_source(historical)
    assert_equal(sha256_hex(again.as_bytes()), _HISTORICAL_SHA)


def test_a_changed_count_token_is_refused() raises:
    """A changed count token is refused."""
    var count = _count()
    var changed = count.replace(
        "_expansion_distance_jet",
        "_expansion_distance_jet_other",
    )
    assert_true(token_sha256(changed) != token_sha256(count))
    with assert_raises(contains="unknown complete Map variant"):
        _ = count_source(changed)


def test_a_comment_keeps_the_token_and_is_refused() raises:
    """A comment changes the file digest and keeps the token digest."""
    var count = _count()
    var changed = count + "# note\n"
    assert_equal(token_sha256(changed), token_sha256(count))
    assert_true(sha256_hex(changed.as_bytes()) != sha256_hex(count.as_bytes()))
    with assert_raises(contains="unknown complete Map variant"):
        _ = count_source(changed)


def test_a_changed_live_map_is_refused() raises:
    """A changed live Map is refused."""
    var root = "/tmp/count-source-map"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(Path(path).read_text() + "\n# changed\n")
    with assert_raises(contains="live map changed"):
        count_source_check(root)


def main() raises:
    """Run the count-source tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
