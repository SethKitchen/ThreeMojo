# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live Map score helper and caller keep their operation graphs."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.score_operation_graphs import (
    sampled_score_graphs,
    score_operation_graphs,
)


def _copy(root: String) raises:
    """Copy the Map module.

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


def test_the_live_score_graphs_hold() raises:
    """The helper and the caller keep their reviewed token digests."""
    sampled_score_graphs(".")
    sampled_score_graphs("./")
    sampled_score_graphs("extensions/..")


def test_a_changed_helper_graph_is_refused() raises:
    """A changed score helper is refused."""
    var root = "/tmp/score-operation-graphs-helper"
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
        sampled_score_graphs(root)


def test_a_changed_caller_graph_is_refused() raises:
    """A changed winner-seed caller is refused."""
    var root = "/tmp/score-operation-graphs-caller"
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
            "live score helper/caller operation graph changed: "
            + "_try_winner_seed"
        )
    ):
        sampled_score_graphs(root)


def test_a_repeated_declaration_is_refused() raises:
    """A repeated score declaration is refused."""
    var text = (
        Path("extensions/carla/map.mojo").read_text()
        + "\ndef _winner_seed_update_score(\n    pass\n"
    )
    with assert_raises(
        contains="ambiguous score declaration: _winner_seed_update_score"
    ):
        score_operation_graphs(text)


def test_a_missing_declaration_is_refused() raises:
    """A missing score declaration is refused."""
    var text = (
        Path("extensions/carla/map.mojo")
        .read_text()
        .replace("def _try_winner_seed(", "def _try_winner_seed_other(")
    )
    with assert_raises(
        contains="ambiguous score declaration: _try_winner_seed"
    ):
        score_operation_graphs(text)


def main() raises:
    """Run the score-operation tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
