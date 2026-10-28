# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The deviation, station, and score endpoints share one frontier."""

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
from tools.score_family_predecessor import (
    score_family_check,
    score_family_predecessor_source,
)


comptime _FRONTIER_SHA = (
    "37dcfb47476001ba8633a2c9dbb78b2d5f83bc069a0c4551d32ca6fdbb4c60bf"
)
comptime _FRONTIER_TOKEN = (
    "214a759d7cb2f804b214bf7324e621d36c83be40af1ecb497550609f6b6bc063"
)


def _family() raises -> Tuple[String, String, String]:
    """Return the deviation, station, and score endpoints.

    Returns:
        The three reviewed score-family endpoints.

    Raises:
        Error: The live Map changed.
    """
    var deviation = restored_deviation_map()
    var station = station_endpoint(deviation)
    var score = score_endpoint(station)
    return (deviation, station, score)


def _copy(root: String) raises:
    """Copy the Map module into a small repository.

    Args:
        root: The temporary repository.

    Raises:
        Error: The file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(["mkdir", "-p", root + "/extensions/carla"], 10.0)
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


def test_the_live_score_family_holds() raises:
    """The three endpoints project to one frontier."""
    score_family_check(".")
    score_family_check("./")
    score_family_check("extensions/..")
    var family = _family()
    var from_deviation = score_family_predecessor_source(family[0])
    var from_station = score_family_predecessor_source(family[1])
    var from_score = score_family_predecessor_source(family[2])
    assert_true(from_deviation == from_station)
    assert_true(from_station == from_score)
    assert_equal(sha256_hex(from_score.as_bytes()), _FRONTIER_SHA)
    assert_equal(token_sha256(from_score), _FRONTIER_TOKEN)


def test_a_comment_keeps_the_token_and_is_refused() raises:
    """A comment changes the file digest and keeps the token digest."""
    var score = _family()[2]
    var changed = score + "# note\n"
    assert_equal(token_sha256(changed), token_sha256(score))
    assert_true(sha256_hex(changed.as_bytes()) != sha256_hex(score.as_bytes()))
    with assert_raises(contains="unknown score-helper successor"):
        _ = score_family_predecessor_source(changed)


def test_a_third_map_variant_is_refused() raises:
    """A deviation endpoint with extra bytes is refused."""
    var deviation = _family()[0]
    var changed = deviation + "\nvar unreviewed = 1\n"
    assert_true(token_sha256(changed) != token_sha256(deviation))
    with assert_raises(contains="unknown score-helper successor"):
        _ = score_family_predecessor_source(changed)


def test_a_changed_live_map_is_refused() raises:
    """A changed live Map is refused."""
    var root = "/tmp/score-family-map"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(Path(path).read_text() + "\n# changed\n")
    with assert_raises(contains="live map changed"):
        score_family_check(root)


def main() raises:
    """Run the score-family tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
