# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The frontier endpoint reverses to the support endpoint."""

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
from tools.frontier_predecessor import (
    frontier_predecessor,
    frontier_predecessor_source,
)
from tools.score_predecessor import score_predecessor_source


comptime _SUPPORT_SHA = (
    "b9acf04cb54a84b89928739ea9c4e1098843149b6e926cf043b3333a1cdff518"
)
comptime _SUPPORT_TOKEN = (
    "57b5ab51af0a83edabbfa783a9857c8f88f435244f0f171649e4290da69c58d3"
)


def _frontier() raises -> String:
    """Return the reviewed frontier endpoint.

    Returns:
        The frontier endpoint of the live Map module.

    Raises:
        Error: The live Map changed.
    """
    var score = score_endpoint(station_endpoint(restored_deviation_map()))
    return score_predecessor_source(score)


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


def test_the_live_frontier_predecessor_holds() raises:
    """The frontier endpoint restores the support file and token digests."""
    frontier_predecessor(".")
    frontier_predecessor("./")
    frontier_predecessor("extensions/..")
    var support = frontier_predecessor_source(_frontier())
    assert_equal(sha256_hex(support.as_bytes()), _SUPPORT_SHA)
    assert_equal(token_sha256(support), _SUPPORT_TOKEN)


def test_a_changed_frontier_token_is_refused() raises:
    """A changed frontier token is refused."""
    var frontier = _frontier()
    var changed = frontier.replace("16373", "16374")
    assert_true(token_sha256(changed) != token_sha256(frontier))
    with assert_raises(contains="unknown frontier-reservation successor"):
        _ = frontier_predecessor_source(changed)


def test_a_comment_keeps_the_token_and_is_refused() raises:
    """A comment changes the file digest and keeps the token digest."""
    var frontier = _frontier()
    var changed = frontier + "# note\n"
    assert_equal(token_sha256(changed), token_sha256(frontier))
    assert_true(
        sha256_hex(changed.as_bytes()) != sha256_hex(frontier.as_bytes())
    )
    with assert_raises(contains="unknown frontier-reservation successor"):
        _ = frontier_predecessor_source(changed)


def test_a_changed_live_map_is_refused() raises:
    """A changed live Map is refused."""
    var root = "/tmp/frontier-predecessor-map"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(Path(path).read_text() + "\n# changed\n")
    with assert_raises(contains="live map changed"):
        frontier_predecessor(root)


def main() raises:
    """Run the frontier-predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
