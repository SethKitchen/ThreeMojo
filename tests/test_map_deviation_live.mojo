# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Map deviation declarations keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tests._small_loop_proofs import NEAREST_BEGIN
from tools._process import run_program
from tools.map_deviation_live import map_deviation_live


def _copy(root: String) raises:
    """Copy the live Map module.

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


def test_the_live_deviation_declarations_hold() raises:
    """The query and the builder keep their reviewed digests."""
    map_deviation_live(".")
    map_deviation_live("./")
    map_deviation_live("extensions/..")


def test_a_changed_query_is_refused() raises:
    """A changed query certificate is refused."""
    var root = "/tmp/map-deviation-live-query"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "var frontier = self._tree." + NEAREST_BEGIN + "(location, work)",
            "var frontier = self._tree."
            + NEAREST_BEGIN
            + "(location, work, work)",
        )
    )
    with assert_raises(
        contains=(
            "live query/builder changed: _closest_lane_certificate_with_work"
        )
    ):
        map_deviation_live(root)


def main() raises:
    """Run the Map deviation declaration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
