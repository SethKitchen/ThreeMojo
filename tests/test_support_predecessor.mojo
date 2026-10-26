# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The support endpoint reverses to the optional endpoint."""

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
from tools.frontier_predecessor import frontier_predecessor_source
from tools.score_predecessor import score_predecessor_source
from tools.support_predecessor import (
    support_predecessor,
    support_predecessor_source,
)


comptime _OPTIONAL_SHA = (
    "e4498a5180821de4a1611cbe3c0751bda36d2e80b84c3c53caac2ca1ca0a367c"
)
comptime _OPTIONAL_TOKEN = (
    "7cd2f4af3f6ad9f12f610a5c0dfcbf9fc781c46f9bcf39c2755bf3867d251685"
)


def _support() raises -> String:
    """Return the reviewed support endpoint.

    Returns:
        The support endpoint of the live Map module.

    Raises:
        Error: The live Map changed.
    """
    var score = score_endpoint(station_endpoint(restored_deviation_map()))
    var frontier = score_predecessor_source(score)
    return frontier_predecessor_source(frontier)


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


def test_the_live_support_predecessor_holds() raises:
    """The support endpoint restores the optional file and token digests."""
    support_predecessor(".")
    support_predecessor("./")
    support_predecessor("extensions/..")
    var optional = support_predecessor_source(_support())
    assert_equal(sha256_hex(optional.as_bytes()), _OPTIONAL_SHA)
    assert_equal(token_sha256(optional), _OPTIONAL_TOKEN)


def test_a_changed_support_token_is_refused() raises:
    """A changed support token is refused."""
    var support = _support()
    var changed = support.replace("d.error < 1.0", "d.error < 2.0")
    assert_true(token_sha256(changed) != token_sha256(support))
    with assert_raises(contains="unknown support-guard successor"):
        _ = support_predecessor_source(changed)


def test_a_comment_keeps_the_token_and_is_refused() raises:
    """A comment changes the file digest and keeps the token digest."""
    var support = _support()
    var changed = support + "# note\n"
    assert_equal(token_sha256(changed), token_sha256(support))
    assert_true(
        sha256_hex(changed.as_bytes()) != sha256_hex(support.as_bytes())
    )
    with assert_raises(contains="unknown support-guard successor"):
        _ = support_predecessor_source(changed)


def test_a_changed_live_map_is_refused() raises:
    """A changed live Map is refused."""
    var root = "/tmp/support-predecessor-map"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(Path(path).read_text() + "\n# changed\n")
    with assert_raises(contains="live map changed"):
        support_predecessor(root)


def main() raises:
    """Run the support-predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
