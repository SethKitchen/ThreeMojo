# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The typed-boundary conditioned inputs keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.typed_boundary_conditioned import typed_boundary_conditioned


def _copy(root: String) raises:
    """Copy the reviewed conditioned inputs.

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
            root + "/tools/carla_lane_oracle",
            root + "/docs/validation",
            root + "/assets/carla",
            root + "/extensions/carla",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tools/carla_lane_oracle/conditioned-cubic-successor.json")
    files.append("tools/carla_lane_oracle/test_conditioned_cubic_contracts.py")
    files.append("docs/validation/conditioned-cubic-333.md")
    files.append("assets/carla/town.xodr")
    files.append("extensions/carla/curve_interval.mojo")
    files.append("tools/carla_lane_oracle/typed_boundary_contracts.py")
    files.append("tools/carla_lane_oracle/conditioned_cubic_contracts.py")

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_conditioned_inputs_hold() raises:
    """The seven conditioned inputs keep their reviewed digests."""
    typed_boundary_conditioned(".")
    typed_boundary_conditioned("./")
    typed_boundary_conditioned("docs/..")


def test_a_changed_cubic_record_is_refused() raises:
    """A changed cubic record is refused."""
    var root = "/tmp/typed-boundary-conditioned-record"
    _copy(root)
    var path = (
        root + "/tools/carla_lane_oracle/conditioned-cubic-successor.json"
    )
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "typed boundary bound input changed:"
            " tools/carla_lane_oracle/conditioned-cubic-successor.json"
        )
    ):
        typed_boundary_conditioned(root)


def test_a_changed_cubic_contract_is_refused() raises:
    """A changed cubic contract is refused."""
    var root = "/tmp/typed-boundary-conditioned-contract"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/conditioned_cubic_contracts.py"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "typed boundary bound input changed: "
            + "tools/carla_lane_oracle/conditioned_cubic_contracts.py"
        )
    ):
        typed_boundary_conditioned(root)


def main() raises:
    """Run the typed-boundary conditioned-input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
