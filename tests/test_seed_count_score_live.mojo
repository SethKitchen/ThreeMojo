# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The score-live premises keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.seed_count_score_live import seed_count_score_live


def _copy(root: String) raises:
    """Copy the score-live modules and the score fixture.

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
            root + "/tests",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/carla/curve_interval.mojo")
    files.append("extensions/carla/curve_sum2.mojo")
    files.append("extensions/carla/map.mojo")
    files.append("extensions/carla/map_search.mojo")
    files.append("tests/test_carla_winner_seed_update_score.mojo")
    # Copied in this process: one `cp` for each file took most of the
    # five seconds a test may run.
    for path in files:
        Path(root + "/" + path).write_bytes(Path(path).read_bytes())


def test_the_live_score_premises_hold() raises:
    """The score declarations, extra premises, and fixture keep their digests.
    """
    seed_count_score_live(".")
    seed_count_score_live("./")
    seed_count_score_live("extensions/..")


def test_a_changed_score_helper_is_refused() raises:
    """A changed score helper is refused."""
    var root = "/tmp/seed-count-score-live-helper"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace("return (True, score.high)", "return (True, score.low)")
    )
    with assert_raises(
        contains=(
            "live score helper/caller operation graph changed: "
            + "_winner_seed_update_score"
        )
    ):
        seed_count_score_live(root)


def test_a_changed_optional_premise_is_refused() raises:
    """A changed optional premise is refused."""
    var root = "/tmp/seed-count-score-live-optional"
    _copy(root)
    var path = root + "/extensions/carla/curve_sum2.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace("var high = total + term", "var high = total - term")
    )
    with assert_raises(
        contains=(
            "live optional-guard premise changed: "
            + "extensions/carla/curve_sum2.mojo:_sum2_update"
        )
    ):
        seed_count_score_live(root)


def test_a_changed_score_fixture_is_refused() raises:
    """A changed score fixture is refused."""
    var root = "/tmp/seed-count-score-live-fixture"
    _copy(root)
    var path = root + "/tests/test_carla_winner_seed_update_score.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "score-helper numerical fixture changed: "
            + "tests/test_carla_winner_seed_update_score.mojo"
        )
    ):
        seed_count_score_live(root)


def main() raises:
    """Run the score-live premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
