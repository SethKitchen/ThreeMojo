# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live winner-seed guard and debit statements stay reviewed."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_winner_seed import sum2_winner_seed


def _copy(root: String) raises:
    """Copy the winner-seed inputs.

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


def test_the_live_winner_seed_guard_holds() raises:
    """The live guard and debit statements match the pin."""
    sum2_winner_seed(".")
    sum2_winner_seed("./")


def test_a_changed_winner_seed_debit_is_refused() raises:
    """A changed debit statement is refused."""
    var root = "/tmp/sum2-winner-seed-debit"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path).read_text().replace("work._step(60)", "work._step(61)")
    )
    with assert_raises(
        contains="Sum2 live winner-seed fresh guard or debit statements changed"
    ):
        sum2_winner_seed(root)


def test_a_missing_score_upper_assignment_is_refused() raises:
    """A missing upper assignment is refused."""
    var root = "/tmp/sum2-winner-seed-upper"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "certificate.upper = update[1]",
            "certificate.upper = score.high",
        )
    )
    with assert_raises(contains="missing unique score upper correspondence"):
        sum2_winner_seed(root)


def main() raises:
    """Run the winner-seed tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
