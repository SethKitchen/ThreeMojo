# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The score and station helpers stay in the Map module."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._score_caller_inventory import score_caller_inventory


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


def test_the_live_score_inventory_holds() raises:
    """The helper names keep their Map counts."""
    score_caller_inventory(".")
    score_caller_inventory("./")
    score_caller_inventory("extensions/..")


def test_a_comment_and_a_string_stay_allowed() raises:
    """A comment or a string does not add a caller."""
    var root = "/tmp/score-caller-inventory-text"
    _copy(root)
    Path(root + "/extensions/carla/note.mojo").write_text(
        "# _winner_seed_update_score\n"
        + "def note() -> String:\n"
        + '    return "_chord_station_delta"\n'
    )
    score_caller_inventory(root)


def test_an_extra_score_caller_is_refused() raises:
    """A score helper use outside Map is refused."""
    var root = "/tmp/score-caller-inventory-score"
    _copy(root)
    Path(root + "/extensions/carla/extra.mojo").write_text(
        "def extra():\n    _winner_seed_update_score()\n"
    )
    with assert_raises(
        contains="score helper production caller inventory changed"
    ):
        score_caller_inventory(root)


def test_a_changed_station_count_is_refused() raises:
    """A changed station helper count is refused."""
    var root = "/tmp/score-caller-inventory-station"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace("_chord_station_delta(", "_chord_station_delta_other(")
    )
    with assert_raises(
        contains="station helper production caller inventory changed"
    ):
        score_caller_inventory(root)


def main() raises:
    """Run the score-inventory tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
