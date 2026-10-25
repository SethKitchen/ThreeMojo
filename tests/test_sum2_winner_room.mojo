# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live winner-seed room keeps the capped followup and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sum2_winner_room import sum2_winner_room


def _copy(root: String) raises:
    """Copy the winner-room inputs.

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
    files.append("extensions/carla/map.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_winner_seed_room_holds() raises:
    """The live room matches the pin after the three edges."""
    sum2_winner_room(".")
    sum2_winner_room("./")


def test_a_changed_winner_seed_room_body_is_refused() raises:
    """A changed room body is refused."""
    var root = "/tmp/sum2-winner-room-body"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "var seed_nodes = proof_nodes + 85",
            "var seed_nodes = proof_nodes + 86",
        )
    )
    with assert_raises(
        contains="Sum2 complete guarded caller changed: map:_winner_seed_room"
    ):
        sum2_winner_room(root)


def test_an_uncapped_winner_followup_is_refused() raises:
    """An uncapped followup is refused."""
    var root = "/tmp/sum2-winner-room-cap"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "var winner_followup = min(len(winner.cells), 16373) + 12",
            "var winner_followup = len(winner.cells) + 12",
        )
    )
    with assert_raises(
        contains="Sum2 complete guarded caller changed: map:_winner_seed_room"
    ):
        sum2_winner_room(root)


def main() raises:
    """Run the winner-seed room tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
