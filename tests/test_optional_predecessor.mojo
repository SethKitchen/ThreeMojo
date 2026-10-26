# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The optional endpoint reverses to the count endpoint."""

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
from tools.optional_predecessor import (
    optional_predecessor,
    optional_predecessor_source,
)
from tools.score_predecessor import score_predecessor_source
from tools.support_predecessor import support_predecessor_source


comptime _COUNT_SHA = (
    "9e29cdd57fc37ffa9dc9c09ed9b263ddb7ced5781f938ff13d7fd9b2c6c997a5"
)
comptime _COUNT_TOKEN = (
    "ef1e317a812dec93adc1e47857825cfc747eae7117dd3f9664b7e4dda646b938"
)


def _optional() raises -> String:
    """Return the reviewed optional endpoint.

    Returns:
        The optional endpoint of the live Map module.

    Raises:
        Error: The live Map changed.
    """
    var score = score_endpoint(station_endpoint(restored_deviation_map()))
    var frontier = score_predecessor_source(score)
    var support = frontier_predecessor_source(frontier)
    return support_predecessor_source(support)


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


def test_the_live_optional_predecessor_holds() raises:
    """The optional endpoint restores the count file and token digests."""
    optional_predecessor(".")
    optional_predecessor("./")
    optional_predecessor("extensions/..")
    var count = optional_predecessor_source(_optional())
    assert_equal(sha256_hex(count.as_bytes()), _COUNT_SHA)
    assert_equal(token_sha256(count), _COUNT_TOKEN)


def test_a_changed_optional_token_is_refused() raises:
    """A changed optional token is refused."""
    var optional = _optional()
    var changed = optional.replace(
        "winner_units * winner_reference",
        "winner_units * winner_followup",
    )
    assert_true(token_sha256(changed) != token_sha256(optional))
    with assert_raises(contains="unknown optional-guard successor"):
        _ = optional_predecessor_source(changed)


def test_a_comment_keeps_the_token_and_is_refused() raises:
    """A comment changes the file digest and keeps the token digest."""
    var optional = _optional()
    var changed = optional + "# note\n"
    assert_equal(token_sha256(changed), token_sha256(optional))
    assert_true(
        sha256_hex(changed.as_bytes()) != sha256_hex(optional.as_bytes())
    )
    with assert_raises(contains="unknown optional-guard successor"):
        _ = optional_predecessor_source(changed)


def test_a_changed_live_map_is_refused() raises:
    """A changed live Map is refused."""
    var root = "/tmp/optional-predecessor-map"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(Path(path).read_text() + "\n# changed\n")
    with assert_raises(contains="live map changed"):
        optional_predecessor(root)


def main() raises:
    """Run the optional-predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
