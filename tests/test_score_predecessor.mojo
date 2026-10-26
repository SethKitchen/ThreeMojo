# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The score endpoint reverses to the frontier endpoint."""

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
from tools.score_predecessor import score_predecessor, score_predecessor_source


comptime _FRONTIER_SHA = (
    "37dcfb47476001ba8633a2c9dbb78b2d5f83bc069a0c4551d32ca6fdbb4c60bf"
)
comptime _FRONTIER_TOKEN = (
    "214a759d7cb2f804b214bf7324e621d36c83be40af1ecb497550609f6b6bc063"
)


def _score() raises -> String:
    """Return the reviewed score endpoint.

    Returns:
        The score endpoint of the live Map module.

    Raises:
        Error: The live Map changed.
    """
    return score_endpoint(station_endpoint(restored_deviation_map()))


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


def test_the_live_score_predecessor_holds() raises:
    """The score endpoint restores the frontier file and token digests."""
    score_predecessor(".")
    score_predecessor("./")
    score_predecessor("extensions/..")
    var frontier = score_predecessor_source(_score())
    assert_equal(sha256_hex(frontier.as_bytes()), _FRONTIER_SHA)
    assert_equal(token_sha256(frontier), _FRONTIER_TOKEN)


def test_a_changed_score_token_is_refused() raises:
    """A changed score token is refused."""
    var score = _score()
    var changed = score.replace(
        "return (True, score.high)",
        "return (True, score.low)",
    )
    assert_true(token_sha256(changed) != token_sha256(score))
    with assert_raises(contains="unknown score-helper successor"):
        _ = score_predecessor_source(changed)


def test_a_comment_keeps_the_token_and_is_refused() raises:
    """A comment changes the file digest and keeps the token digest."""
    var score = _score()
    var changed = score + "# note\n"
    assert_equal(token_sha256(changed), token_sha256(score))
    assert_true(sha256_hex(changed.as_bytes()) != sha256_hex(score.as_bytes()))
    with assert_raises(contains="unknown score-helper successor"):
        _ = score_predecessor_source(changed)


def test_a_changed_live_map_is_refused() raises:
    """A changed live Map is refused."""
    var root = "/tmp/score-predecessor-map"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(Path(path).read_text() + "\n# changed\n")
    with assert_raises(contains="live map changed"):
        score_predecessor(root)


def main() raises:
    """Run the score-predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
