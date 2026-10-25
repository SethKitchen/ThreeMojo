# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Sum2 guard pin and the live helper graph stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sum2_guard_pins import sum2_guard_pins


def _copy(root: String) raises:
    """Copy the pin, the helper, and the winner record.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/tools/carla_lane_oracle",
            root + "/extensions/carla",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var pins = run_program(
        [
            "cp",
            "tools/carla_lane_oracle/sum2-guard-pins.json",
            root + "/tools/carla_lane_oracle/sum2-guard-pins.json",
        ],
        10.0,
    )
    if pins.status != 0:
        raise Error(pins.output)
    var winner = run_program(
        [
            "cp",
            "tools/carla_lane_oracle/winner-sign-query-migration.json",
            root + "/tools/carla_lane_oracle/winner-sign-query-migration.json",
        ],
        10.0,
    )
    if winner.status != 0:
        raise Error(winner.output)
    var helper = run_program(
        [
            "cp",
            "extensions/carla/curve_sum2.mojo",
            root + "/extensions/carla/curve_sum2.mojo",
        ],
        10.0,
    )
    if helper.status != 0:
        raise Error(helper.output)


def test_the_sum2_guard_pin_holds() raises:
    """The pin keys, lineage hashes, and live helper tokens stay fixed."""
    sum2_guard_pins(".")


def test_a_changed_sum2_guard_pin_is_refused() raises:
    """A changed schema, helper, or winner record is refused."""
    var schema_root = "/tmp/sum2-guard-pins-schema"
    _copy(schema_root)
    var pins = schema_root + "/tools/carla_lane_oracle/sum2-guard-pins.json"
    var pin_text = Path(pins).read_text()
    Path(pins).write_text(pin_text.replace('"schema": 2', '"schema": 3'))
    with assert_raises(contains="unsupported Sum2 guard pin schema"):
        sum2_guard_pins(schema_root)
    var helper_root = "/tmp/sum2-guard-pins-helper"
    _copy(helper_root)
    var helper = helper_root + "/extensions/carla/curve_sum2.mojo"
    Path(helper).write_text(Path(helper).read_text() + "\nvar extra = 1\n")
    with assert_raises(
        contains="Sum2 complete guard/helper token graph changed"
    ):
        sum2_guard_pins(helper_root)
    var winner_root = "/tmp/sum2-guard-pins-winner"
    _copy(winner_root)
    var winner = (
        winner_root
        + "/tools/carla_lane_oracle/winner-sign-query-migration.json"
    )
    Path(winner).write_text(Path(winner).read_text() + "\n")
    with assert_raises(
        contains="unreviewed winner/sign-query source migration"
    ):
        sum2_guard_pins(winner_root)


def main() raises:
    """Run the Sum2 guard pin tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
