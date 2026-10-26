# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The PR780 bound inputs keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.pr780_bound_inputs import pr780_bound_inputs


def _copy(root: String) raises:
    """Copy the four bound inputs.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tests", root + "/tools/carla_lane_oracle"],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tests/test_anatomy_muscle.mojo")
    files.append("tests/test_animation_strings.mojo")
    files.append("tests/test_loader_bounds.mojo")
    files.append("tools/carla_lane_oracle/test_pr780_source_successor.py")
    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_bound_inputs_hold() raises:
    """The four bound inputs keep their reviewed digests."""
    pr780_bound_inputs(".")
    pr780_bound_inputs("./")
    pr780_bound_inputs("tests/..")


def test_a_changed_anatomy_input_is_refused() raises:
    """A changed anatomy bound input is refused."""
    var root = "/tmp/pr780-bound-anatomy"
    _copy(root)
    var path = root + "/tests/test_anatomy_muscle.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains="PR780 bound input changed: tests/test_anatomy_muscle.mojo"
    ):
        pr780_bound_inputs(root)


def test_a_changed_successor_input_is_refused() raises:
    """A changed successor bound input is refused."""
    var root = "/tmp/pr780-bound-successor"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/test_pr780_source_successor.py"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "PR780 bound input changed: "
            + "tools/carla_lane_oracle/test_pr780_source_successor.py"
        )
    ):
        pr780_bound_inputs(root)


def main() raises:
    """Run the PR780 bound-input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
