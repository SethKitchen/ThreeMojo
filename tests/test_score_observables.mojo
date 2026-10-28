# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The score upper assignment keeps the historical guard and debits."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises, assert_true

from tools._process import run_program
from tools.score_observables import (
    require_unique_score_upper,
    score_observables,
)


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


def test_the_live_score_observables_hold() raises:
    """The fresh guard and the ordered debits match the historical caller."""
    score_observables(".")
    score_observables("./")
    score_observables("extensions/..")


def test_a_missing_upper_assignment_is_refused() raises:
    """Zero or two upper assignments are refused."""
    with assert_raises(contains="missing unique score upper correspondence"):
        _ = require_unique_score_upper("certificate.upper = score.high\n")
    var twice = "certificate.upper = update[1]\ncertificate.upper = update[1]\n"
    with assert_raises(contains="missing unique score upper correspondence"):
        _ = require_unique_score_upper(twice)


def test_one_upper_assignment_is_read_as_the_score_high() raises:
    """The one upper assignment becomes the score high."""
    var rewritten = require_unique_score_upper(
        "certificate.upper = update[1]\n"
    )
    assert_true(rewritten == "certificate.upper = score.high\n")


def test_a_changed_caller_is_refused() raises:
    """A changed winner-seed caller is refused."""
    var root = "/tmp/score-observables-caller"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "certificate.upper = update[1]",
            "certificate.upper = update[0]",
        )
    )
    with assert_raises(
        contains=(
            "live score helper/caller operation graph changed: _try_winner_seed"
        )
    ):
        score_observables(root)


def main() raises:
    """Run the score-observable tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
